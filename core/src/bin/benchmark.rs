//! SuperGoodViewer Rust core benchmark suite.
//!
//! Methodology (see docs/BENCHMARKS.md):
//!
//! * Every measurement is a distribution, not a single shot. We report
//!   min / p50 / p95 / mean over N samples after a warm-up.
//! * Typst memoizes layout through `comemo`. Re-compiling the *same* source in a
//!   loop therefore measures the memo cache, not the compiler. Cold runs call
//!   `typst::comemo::evict(0)` and clear the Mermaid SVG cache before every
//!   sample, so they represent "user opens this document for the first time".
//! * Warm runs keep both caches, representing "same document re-rendered"
//!   (theme switch, window resize, hot reload with unchanged content).
//! * Inputs come from the frozen corpus in `docs/samples/bench/`, and every label
//!   carries the measured byte size of the file, never a hand-written estimate.
//!   Nothing in the repo that people edit (the README, `test.md`) feeds the
//!   benchmark, so numbers stay comparable across runs.
//!
//! Run with `make bench`. Pass `--json <path>` to also emit machine-readable
//! results.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::Instant;

use sogood_core::compile_markdown_to_pdf;
use sogood_core::compiler::engine::{
    compile_typst_to_pdf_with_options, layout_passes, reset_layout_passes, RenderOptions,
};
use sogood_core::parser::markdown::convert_markdown_to_typst;
use sogood_core::parser::math::transpile_latex_math;
use sogood_core::parser::mermaid::{clear_cache as clear_mermaid_cache, render_mermaid};

/// Summary statistics over a set of samples, in milliseconds.
#[derive(Clone, Copy)]
struct Stats {
    min: f64,
    p50: f64,
    p95: f64,
    mean: f64,
    n: usize,
}

impl Stats {
    fn from(mut samples: Vec<f64>) -> Self {
        assert!(!samples.is_empty());
        samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let n = samples.len();
        let pick = |q: f64| {
            let idx = ((n as f64 - 1.0) * q).round() as usize;
            samples[idx]
        };
        Stats {
            min: samples[0],
            p50: pick(0.50),
            p95: pick(0.95),
            mean: samples.iter().sum::<f64>() / n as f64,
            n,
        }
    }

    fn json(&self) -> String {
        format!(
            "{{\"min\":{:.4},\"p50\":{:.4},\"p95\":{:.4},\"mean\":{:.4},\"n\":{}}}",
            self.min, self.p50, self.p95, self.mean, self.n
        )
    }
}

/// Runs `reset` (untimed) then `body` (timed) `samples` times, after `warmup` unmeasured rounds.
fn measure<R: FnMut(), B: FnMut()>(warmup: usize, samples: usize, mut reset: R, mut body: B) -> Stats {
    for _ in 0..warmup {
        reset();
        body();
    }
    let mut out = Vec::with_capacity(samples);
    for _ in 0..samples {
        reset();
        let start = Instant::now();
        body();
        out.push(start.elapsed().as_secs_f64() * 1000.0);
    }
    Stats::from(out)
}

/// Drops every global cache that would otherwise hide real compilation work.
fn drop_all_caches() {
    typst::comemo::evict(0);
    clear_mermaid_cache();
}

fn fluid_options() -> RenderOptions {
    RenderOptions::default()
}

fn paged_options() -> RenderOptions {
    RenderOptions {
        mode: "paged".to_string(),
        theme: "light".to_string(),
        viewport_width: 720.0,
        font_size: 10.5,
        ..Default::default()
    }
}

struct DocResult {
    label: String,
    input_bytes: usize,
    pdf_bytes: usize,
    /// Full Typst layout passes one cold compilation costs. Fluid documents taller
    /// than the PDF page limit pay one pass per slice candidate on top of the
    /// natural-height pass, which is the single largest avoidable-looking cost in
    /// the pipeline -- tracked here so it cannot grow unnoticed.
    layout_passes: usize,
    /// Cold p50 with slicing switched off, for documents that slice. The gap
    /// against `e2e_cold` is what the extra candidate pass actually costs.
    no_slice_cold: Option<Stats>,
    parse: Stats,
    typst: Stats,
    e2e_cold: Stats,
    e2e_edit: Stats,
    e2e_warm: Stats,
    paged_cold: Stats,
}

fn main() {
    let args: Vec<String> = env::args().collect();
    let json_path = args
        .iter()
        .position(|a| a == "--json")
        .and_then(|i| args.get(i + 1))
        .cloned();

    println!("============================================================");
    println!("   SuperGoodViewer Core Benchmark Suite (Rust, release)     ");
    println!("============================================================");
    println!(
        "  cold = comemo memo cache evicted + Mermaid cache cleared before every sample"
    );
    println!("  warm = all caches retained (same document re-rendered)");
    println!();

    // ---------------------------------------------------------------- 1. math
    println!("--- 1. LaTeX -> Typst transpilation (mitex) ---");
    println!(
        "  {:<22} {:>9} {:>9} {:>9} {:>9}   {:>12}",
        "sample", "min us", "p50 us", "p95 us", "mean us", "p50 ops/s"
    );
    let math_samples: [(&str, &str); 4] = [
        ("Simple inline", "E = m c^2"),
        (
            "Fraction & Integral",
            r"\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}",
        ),
        (
            "Maxwell Equation",
            r"\nabla \times \mathbf{B} - \frac{1}{c} \frac{\partial \mathbf{E}}{\partial t} = \frac{4\pi}{c}\mathbf{J}",
        ),
        (
            "Matrix 3x3",
            r"\begin{pmatrix} a & b & c \\ d & e & f \\ g & h & i \end{pmatrix}",
        ),
    ];
    let mut math_results: Vec<(String, Stats)> = Vec::new();
    for (name, latex) in math_samples {
        // Each sample is timed individually so we get a real distribution rather
        // than a loop average that hides outliers.
        let stats = measure(200, 5000, || {}, || {
            std::hint::black_box(transpile_latex_math(std::hint::black_box(latex), false));
        });
        println!(
            "  {:<22} {:>9.2} {:>9.2} {:>9.2} {:>9.2}   {:>12.0}",
            name,
            stats.min * 1000.0,
            stats.p50 * 1000.0,
            stats.p95 * 1000.0,
            stats.mean * 1000.0,
            1000.0 / stats.p50
        );
        math_results.push((name.to_string(), stats));
    }
    println!();

    // ------------------------------------------------------------- 2. mermaid
    println!("--- 2. Mermaid offline vector rendering (mermaid-rs-renderer) ---");
    let mermaid_template = r#"graph TD
    A[Markdown Source {ID}] --> B(AST Parser)
    B --> C{Formula / Chart?}
    C -->|Math| D[MiTeX Engine]
    C -->|Mermaid| E[Rust Vector Renderer]
    D --> F[Typst Compiler]
    E --> F
    F --> G[Google PDFium]
    G --> H[Native Canvas]
"#;
    // Cold: a unique diagram every sample, so the SHA-256 cache can never hit.
    let counter = std::cell::Cell::new(0usize);
    let svg_len_cell = std::cell::Cell::new(0usize);
    let mermaid_cold = measure(
        5,
        200,
        || {
            counter.set(counter.get() + 1);
            clear_mermaid_cache();
        },
        || {
            let code = mermaid_template.replace("{ID}", &counter.get().to_string());
            let res = render_mermaid(&code, false);
            svg_len_cell.set(res.svg_bytes.len());
        },
    );
    let svg_len = svg_len_cell.get();
    // Warm: identical diagram, so every call is a hash + cache lookup.
    let warm_code = mermaid_template.replace("{ID}", "warm");
    let _ = render_mermaid(&warm_code, false);
    let mermaid_warm = measure(1000, 20000, || {}, || {
        std::hint::black_box(render_mermaid(std::hint::black_box(&warm_code), false));
    });
    println!(
        "  {:<22} {:>9} {:>9} {:>9} {:>9}",
        "sample", "min", "p50", "p95", "mean"
    );
    println!(
        "  {:<22} {:>8.2}ms {:>8.2}ms {:>8.2}ms {:>8.2}ms   (SVG {} bytes; unique diagram each sample)",
        "Cold render", mermaid_cold.min, mermaid_cold.p50, mermaid_cold.p95, mermaid_cold.mean, svg_len
    );
    println!(
        "  {:<22} {:>8.0}ns {:>8.0}ns {:>8.0}ns {:>8.0}ns   (SHA-256 hash + cache lookup only)",
        "Warm cache hit",
        mermaid_warm.min * 1e6,
        mermaid_warm.p50 * 1e6,
        mermaid_warm.p95 * 1e6,
        mermaid_warm.mean * 1e6
    );
    println!();

    // ------------------------------------------------- 3. end-to-end pipeline
    println!("--- 3. End-to-end compilation (Markdown -> Typst -> PDF bytes) ---");
    println!(
        "  Fluid mode, {} cold/edit samples and {} warm samples per document.",
        COLD_SAMPLES, WARM_SAMPLES
    );
    println!();

    let corpus_dir = corpus_dir();
    println!("  Corpus: {}", corpus_dir.display());
    println!();
    let docs: Vec<(String, String)> = CORPUS
        .iter()
        .map(|(file, label)| {
            let path = corpus_dir.join(file);
            let text = fs::read_to_string(&path)
                .unwrap_or_else(|e| panic!("cannot read corpus file {}: {e}", path.display()));
            (label.to_string(), text)
        })
        .collect();

    let mut results: Vec<DocResult> = Vec::new();
    for (label, md) in &docs {
        results.push(benchmark_document(label, md));
    }

    println!(
        "  {:<20} {:>7} {:>8} | {:>20} | {:>12} | {:>20} | {:>17} | {:>8} | {:>6} {:>12}",
        "document", "input", "PDF", "cold (min/p50/p95)", "edit p50/p95", "warm (min/p50/p95)", "cold stages p50", "paged p50", "passes", "slice cost"
    );
    for r in &results {
        println!(
            "  {:<20} {:>6.1}K {:>7.1}K | {:>5.2} {:>5.2} {:>5.2} ms | {:>4.2} {:>4.2} ms | {:>5.2} {:>5.2} {:>5.2} ms | md {:>5.2} + ts {:>5.2} | {:>5.2} ms | {:>6} {:>12}",
            r.label,
            r.input_bytes as f64 / 1024.0,
            r.pdf_bytes as f64 / 1024.0,
            r.e2e_cold.min,
            r.e2e_cold.p50,
            r.e2e_cold.p95,
            r.e2e_edit.p50,
            r.e2e_edit.p95,
            r.e2e_warm.min,
            r.e2e_warm.p50,
            r.e2e_warm.p95,
            r.parse.p50,
            r.typst.p50,
            r.paged_cold.p50,
            r.layout_passes,
            match &r.no_slice_cold {
                Some(no_slice) => format!("+{:.0} ms", r.e2e_cold.p50 - no_slice.p50),
                None => "-".to_string(),
            },
        );
    }
    println!();

    if let Some(path) = json_path {
        let json = build_json(&math_results, mermaid_cold, mermaid_warm, svg_len, &results);
        fs::write(&path, json).expect("failed to write JSON results");
        println!("  JSON results written to {}", path);
        println!();
    }

    println!("============================================================");
    println!("                 Benchmark Complete                         ");
    println!("============================================================");
}

/// The frozen corpus under `docs/samples/bench/`, in report order.
///
/// These files are inputs, not documentation: they are deliberately never edited,
/// so numbers stay comparable across runs and across machines. Editing the repo's
/// own README or `test.md` must not move the benchmark.
const CORPUS: [(&str, &str); 5] = [
    ("01-note.md", "Quick note"),
    ("02-readme.md", "Project README"),
    ("03-prd.md", "Technical PRD"),
    ("04-book.md", "Book chapter"),
    ("05-real-world.md", "Real-world doc"),
];

/// Resolves `docs/samples/bench/` whether the binary is run from `core/` (as
/// `make bench` does) or from the repository root.
fn corpus_dir() -> PathBuf {
    for candidate in ["../docs/samples/bench", "docs/samples/bench"] {
        let path = PathBuf::from(candidate);
        if path.is_dir() {
            return path;
        }
    }
    panic!("benchmark corpus not found: expected docs/samples/bench/ relative to the repo root or core/");
}

const COLD_SAMPLES: usize = 20;
const WARM_SAMPLES: usize = 30;

fn benchmark_document(label: &str, markdown: &str) -> DocResult {
    let fluid = fluid_options();
    let paged = paged_options();

    drop_all_caches();
    reset_layout_passes();
    let pdf_bytes = compile_markdown_to_pdf(markdown, "BenchDoc", ".", &fluid)
        .expect("fluid compile failed")
        .len();
    let passes = layout_passes();

    // Stage A: Markdown -> Typst source (includes Mermaid rendering and LaTeX transpilation).
    let parse = measure(3, COLD_SAMPLES, drop_all_caches, || {
        std::hint::black_box(convert_markdown_to_typst(markdown, "BenchDoc", &fluid));
    });

    // Stage B: Typst source -> PDF bytes (layout + PDF export), same cold conditions.
    let parsed = convert_markdown_to_typst(markdown, "BenchDoc", &fluid);
    let typst = measure(3, COLD_SAMPLES, drop_all_caches, || {
        std::hint::black_box(
            compile_typst_to_pdf_with_options(
                &parsed.typst_source,
                ".",
                parsed.virtual_files.clone(),
                None,
            )
            .expect("typst compile failed"),
        );
    });

    let e2e_cold = measure(3, COLD_SAMPLES, drop_all_caches, || {
        std::hint::black_box(
            compile_markdown_to_pdf(markdown, "BenchDoc", ".", &fluid).expect("fluid compile failed"),
        );
    });

    // Warm process, changed content: the caches hold shared library/font/diagram
    // entries from earlier documents, but this document's text is new every
    // sample. This is what a live edit (hot reload) or opening a second document
    // in an already-running app actually costs.
    let rev = std::cell::Cell::new(0usize);
    let e2e_edit = measure(3, COLD_SAMPLES, || rev.set(rev.get() + 1), || {
        let edited = format!("{}\n\nRevision {}.\n", markdown, rev.get());
        std::hint::black_box(
            compile_markdown_to_pdf(&edited, "BenchDoc", ".", &fluid).expect("fluid compile failed"),
        );
    });

    let e2e_warm = measure(3, WARM_SAMPLES, || {}, || {
        std::hint::black_box(
            compile_markdown_to_pdf(markdown, "BenchDoc", ".", &fluid).expect("fluid compile failed"),
        );
    });

    let paged_cold = measure(3, COLD_SAMPLES, drop_all_caches, || {
        std::hint::black_box(
            compile_markdown_to_pdf(markdown, "BenchDoc", ".", &paged).expect("paged compile failed"),
        );
    });

    // Only meaningful where slicing actually runs; a single-pass document would
    // just measure the same work twice.
    let no_slice_cold = (passes > 1).then(|| {
        let no_slice = RenderOptions { disable_fluid_slice: Some(true), ..fluid_options() };
        measure(3, COLD_SAMPLES, drop_all_caches, || {
            std::hint::black_box(
                compile_markdown_to_pdf(markdown, "BenchDoc", ".", &no_slice)
                    .expect("no-slice compile failed"),
            );
        })
    });

    DocResult {
        label: label.to_string(),
        input_bytes: markdown.len(),
        pdf_bytes,
        layout_passes: passes,
        no_slice_cold,
        parse,
        typst,
        e2e_cold,
        e2e_edit,
        e2e_warm,
        paged_cold,
    }
}

fn build_json(
    math: &[(String, Stats)],
    mermaid_cold: Stats,
    mermaid_warm: Stats,
    svg_len: usize,
    docs: &[DocResult],
) -> String {
    let mut s = String::from("{\n  \"unit\": \"milliseconds\",\n  \"math\": {\n");
    for (i, (name, st)) in math.iter().enumerate() {
        s.push_str(&format!(
            "    \"{}\": {}{}\n",
            name,
            st.json(),
            if i + 1 == math.len() { "" } else { "," }
        ));
    }
    s.push_str("  },\n  \"mermaid\": {\n");
    s.push_str(&format!("    \"svg_bytes\": {},\n", svg_len));
    s.push_str(&format!("    \"cold\": {},\n", mermaid_cold.json()));
    s.push_str(&format!("    \"warm\": {}\n", mermaid_warm.json()));
    s.push_str("  },\n  \"documents\": [\n");
    for (i, d) in docs.iter().enumerate() {
        s.push_str(&format!(
            "    {{\"label\":\"{}\",\"input_bytes\":{},\"pdf_bytes\":{},\"parse\":{},\"typst\":{},\"e2e_cold\":{},\"e2e_edit\":{},\"e2e_warm\":{},\"paged_cold\":{},\"layout_passes\":{},\"no_slice_cold\":{}}}{}\n",
            d.label,
            d.input_bytes,
            d.pdf_bytes,
            d.parse.json(),
            d.typst.json(),
            d.e2e_cold.json(),
            d.e2e_edit.json(),
            d.e2e_warm.json(),
            d.paged_cold.json(),
            d.layout_passes,
            match &d.no_slice_cold {
                Some(stats) => stats.json(),
                None => "null".to_string(),
            },
            if i + 1 == docs.len() { "" } else { "," }
        ));
    }
    s.push_str("  ]\n}\n");
    s
}
