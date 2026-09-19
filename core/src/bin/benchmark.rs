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
//! * Document labels carry the measured byte size of the actual input, never a
//!   hand-written estimate.
//!
//! Run with `make bench`. Pass `--json <path>` to also emit machine-readable
//! results.

use std::env;
use std::fs;
use std::path::Path;
use std::time::Instant;

use sogood_core::compile_markdown_to_pdf;
use sogood_core::compiler::engine::{compile_typst_to_pdf_with_options, RenderOptions};
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

    let mut docs: Vec<(String, String)> = Vec::new();

    docs.push((
        "Quick note".to_string(),
        "# Quick Meeting Note\n\n- Discuss project timeline\n- Action items assigned to team\n- Follow up next Monday\n\nFormula: $f(x) = x^2 + 2x + 1$\n".to_string(),
    ));

    if let Some(readme) = read_first(&["../README.md", "README.md"]) {
        docs.push(("Project README".to_string(), readme));
    }

    docs.push(("Technical PRD".to_string(), build_prd()));
    docs.push(("Book chapter".to_string(), build_book()));

    if let Some(test_md) = read_first(&["../test.md", "test.md"]) {
        docs.push(("Real-world test.md".to_string(), test_md));
    }

    let mut results: Vec<DocResult> = Vec::new();
    for (label, md) in &docs {
        results.push(benchmark_document(label, md));
    }

    println!(
        "  {:<20} {:>7} {:>8} | {:>20} | {:>12} | {:>20} | {:>17} | {:>8}",
        "document", "input", "PDF", "cold (min/p50/p95)", "edit p50/p95", "warm (min/p50/p95)", "cold stages p50", "paged p50"
    );
    for r in &results {
        println!(
            "  {:<20} {:>6.1}K {:>7.1}K | {:>5.2} {:>5.2} {:>5.2} ms | {:>4.2} {:>4.2} ms | {:>5.2} {:>5.2} {:>5.2} ms | md {:>5.2} + ts {:>5.2} | {:>5.2} ms",
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

const COLD_SAMPLES: usize = 20;
const WARM_SAMPLES: usize = 30;

fn read_first(paths: &[&str]) -> Option<String> {
    paths
        .iter()
        .find_map(|p| fs::read_to_string(Path::new(p)).ok())
}

fn benchmark_document(label: &str, markdown: &str) -> DocResult {
    let fluid = fluid_options();
    let paged = paged_options();

    drop_all_caches();
    let pdf_bytes = compile_markdown_to_pdf(markdown, "BenchDoc", ".", &fluid)
        .expect("fluid compile failed")
        .len();

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

    DocResult {
        label: label.to_string(),
        input_bytes: markdown.len(),
        pdf_bytes,
        parse,
        typst,
        e2e_cold,
        e2e_edit,
        e2e_warm,
        paged_cold,
    }
}

/// A technical specification with Mermaid, math, tables and code, repeated until
/// it reaches roughly 20 KB of real Markdown.
fn build_prd() -> String {
    let section = r#"
## Section {N}: System Topology

```mermaid
graph LR
    User{N}[Desktop User] --> Shell{N}[Flutter Native UI]
    Shell{N} --> Bridge{N}[C-ABI FFI Bridge]
    Bridge{N} --> Core{N}[Rust Native Core]
    Core{N} --> Typst{N}[Typst Compiler]
    Typst{N} --> PDF{N}[Vector PDF Stream]
```

> [!NOTE]
> All measurements in section {N} were taken on Apple Silicon with Metal acceleration.

### Mathematical Foundations

The thermodynamic entropy is given by:

$ S = -k_B sum_i p_i ln p_i $

The electromagnetic field tensor satisfies:

$ F^(mu nu) = partial^mu A^nu - partial^nu A^mu $

### Benchmark Matrix

| Component | Implementation | Target Latency | Status |
| :--- | :--- | :--- | :--- |
| Markdown Parser | pulldown-cmark | < 1 ms | Exceeded |
| Math Transpiler | mitex | < 50 us | Exceeded |
| Mermaid Vector | mermaid-rs-renderer | < 5 ms | Exceeded |
| Memory World | Typst In-Memory | < 15 ms | Exceeded |
| Vector PDFium | pdfrx + Metal | < 16 ms | Exceeded |

### Implementation Sample

```rust
pub fn compile_document_{N}(md: &str) -> Vec<u8> {
    compile_markdown_to_pdf(md, "Arch", ".", &RenderOptions::default()).unwrap()
}
```

This section specifies the end-to-end architecture, the failure modes we tolerate,
and the latency budget each stage of the pipeline is allowed to consume.
"#;
    let mut out = String::from("# System Technical Architecture Document\n");
    let mut n = 1;
    while out.len() < 20_000 {
        out.push_str(&section.replace("{N}", &n.to_string()));
        n += 1;
    }
    out
}

/// A 20-chapter book-length document of roughly 100 KB.
fn build_book() -> String {
    let mut out = String::with_capacity(120_000);
    out.push_str("# High-Performance Distributed Systems Handbook\n\n");
    let mut i = 1;
    while out.len() < 100_000 {
        out.push_str(&format!(
            "\n## Chapter {}: Architectural Patterns and Scalability\n\n",
            i
        ));
        out.push_str("In this chapter we analyze consensus protocols and latency mitigation strategies.\n\n");
        out.push_str("> [!TIP]\n> Always profile under maximum sustained throughput before tuning concurrency limits.\n\n");
        out.push_str("Consider the equation:\n\n$ E = m c^2 $\n\n");
        out.push_str("| Metric | Node A | Node B | Node C | P99 Latency |\n| :--- | :--- | :--- | :--- | :--- |\n| Throughput | 12,000 rps | 14,500 rps | 13,200 rps | 1.8 ms |\n| P50 | 0.4 ms | 0.35 ms | 0.42 ms | 0.9 ms |\n| Error Rate | 0.001% | 0.000% | 0.002% | 0.005% |\n\n");
        out.push_str("```rust\nfn calculate_quorum(nodes: usize) -> usize {\n    (nodes / 2) + 1\n}\n```\n\n");
        out.push_str("Replication lag is bounded by the slowest follower in the quorum, so the tail of the\nlatency distribution -- not its mean -- determines the user-visible behaviour of the system.\n");
        i += 1;
    }
    out
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
            "    {{\"label\":\"{}\",\"input_bytes\":{},\"pdf_bytes\":{},\"parse\":{},\"typst\":{},\"e2e_cold\":{},\"e2e_edit\":{},\"e2e_warm\":{},\"paged_cold\":{}}}{}\n",
            d.label,
            d.input_bytes,
            d.pdf_bytes,
            d.parse.json(),
            d.typst.json(),
            d.e2e_cold.json(),
            d.e2e_edit.json(),
            d.e2e_warm.json(),
            d.paged_cold.json(),
            if i + 1 == docs.len() { "" } else { "," }
        ));
    }
    s.push_str("  ]\n}\n");
    s
}
