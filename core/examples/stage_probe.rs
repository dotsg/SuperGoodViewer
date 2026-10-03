//! Per-stage timing for the Markdown → PDF pipeline, used by
//! `docs/MARKVIEW_COMPARISON.md`.
//!
//! ```sh
//! cargo run --release --example stage_probe -- stages   <file.md>...
//! cargo run --release --example stage_probe -- variants <file.md>...
//! cargo run --release --example stage_probe -- first-use
//! ```
//!
//! * `stages`: font store, Markdown → Typst, cold layout, layout again with the
//!   memo cache evicted (no one-time init), PDF export tagged and untagged.
//!   Run each file in its own process: the first file also pays one-time costs.
//! * `variants`: layout + PDF time of the generated source as-is, with
//!   `justify: true`, with `justify: true` plus `lang: "en"` (English
//!   hyphenation), and without the header/footer (no page-counter
//!   introspection). Best of three, memo cache evicted before each run.
//! * `first-use`: what the first compile of a process pays once, split by the
//!   feature that triggers it.
//!
//! Every mode lays out A4 (`paged`), the format PDF export uses by default.

use std::collections::HashMap;
use std::time::Instant;

use sogood_core::compiler::engine::RenderOptions;
use sogood_core::compiler::world::{GlobalFontStore, MemoryWorld};
use sogood_core::parser::markdown::convert_markdown_to_typst;
use typst_layout::PagedDocument;
use typst_pdf::PdfOptions;

fn ms(start: Instant) -> f64 {
    start.elapsed().as_secs_f64() * 1000.0
}

fn a4_options() -> RenderOptions {
    RenderOptions {
        mode: "paged".into(),
        page_format: Some("a4Portrait".into()),
        ..RenderOptions::default()
    }
}

fn typst_source(path: &str) -> String {
    let markdown = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    convert_markdown_to_typst(&markdown, "doc", &a4_options()).typst_source
}

fn compile(source: &str) -> PagedDocument {
    let world = MemoryWorld::new(source, ".", HashMap::new());
    typst::compile::<PagedDocument>(&world)
        .output
        .unwrap_or_else(|errs| panic!("compile failed: {errs:?}"))
}

fn name(path: &str) -> String {
    std::path::Path::new(path)
        .file_stem()
        .map(|s| s.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string())
}

fn stages(paths: &[String]) {
    let start = Instant::now();
    GlobalFontStore::get();
    let font = ms(start);

    for path in paths {
        let markdown = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
        let start = Instant::now();
        let parsed = convert_markdown_to_typst(&markdown, "doc", &a4_options());
        let convert = ms(start);

        let world = MemoryWorld::new(&parsed.typst_source, ".", parsed.virtual_files);
        let start = Instant::now();
        let document = typst::compile::<PagedDocument>(&world)
            .output
            .unwrap_or_else(|errs| panic!("compile failed: {errs:?}"));
        let layout = ms(start);

        typst::comemo::evict(0);
        let start = Instant::now();
        compile(&parsed.typst_source);
        let relayout = ms(start);

        let start = Instant::now();
        let pdf = typst_pdf::pdf(&document, &PdfOptions::default()).expect("pdf export");
        let export = ms(start);
        let start = Instant::now();
        let untagged = typst_pdf::pdf(&document, &PdfOptions { tagged: false, ..PdfOptions::default() })
            .expect("pdf export");
        let export_untagged = ms(start);

        println!(
            "{:<14} font store {font:5.1} | md→typst {convert:5.1} | layout {layout:6.1} (memo evicted {relayout:6.1}) \
             | pdf {export:5.1} ({} KiB), untagged {export_untagged:5.1} ({} KiB) | {} pages",
            name(path),
            pdf.len() / 1024,
            untagged.len() / 1024,
            document.pages().len(),
        );
    }
}

fn variants(paths: &[String]) {
    GlobalFontStore::get();
    // Pay the one-time costs up front so every variant is timed alike.
    compile("#set text(font: (\"Inter\", \"SF Pro Text\", \"PingFang SC\"), lang: \"zh\")\nwarm *bold* $x$");

    for path in paths {
        let base = typst_source(path);
        assert!(base.contains("justify: false") && base.contains("lang: \"zh\""), "template changed");
        let justify = base.replace("justify: false", "justify: true");
        let justify_en = justify.replace("lang: \"zh\"", "lang: \"en\"");
        let header_start = base.find("  header: context {").expect("header");
        let footer_end = base[header_start..].find("\n  },\n)").expect("footer") + header_start + "\n  },\n".len();
        let no_header_footer = format!("{}{}", &base[..header_start], &base[footer_end..]);

        for (label, source) in [
            ("as generated", &base),
            ("justify: true", &justify),
            ("justify + lang en", &justify_en),
            ("no header/footer", &no_header_footer),
        ] {
            let mut best = (f64::MAX, 0.0, 0);
            for _ in 0..3 {
                typst::comemo::evict(0);
                let start = Instant::now();
                let document = compile(source);
                let layout = ms(start);
                let start = Instant::now();
                typst_pdf::pdf(&document, &PdfOptions::default()).expect("pdf export");
                let export = ms(start);
                if layout < best.0 {
                    best = (layout, export, document.pages().len());
                }
            }
            println!(
                "{:<14} {label:<18} layout {:6.1} ms  pdf {:5.1} ms  {} pages",
                name(path),
                best.0,
                best.1,
                best.2
            );
        }
    }
}

fn first_use() {
    let start = Instant::now();
    GlobalFontStore::get();
    println!("{:<44} {:6.1} ms", "font store", ms(start));
    for (label, source) in [
        ("first compile (library, first layout)", "hello"),
        ("same again", "hello world"),
        ("lang: \"zh\" (CJ line segmenter)", "#set text(lang: \"zh\")\nhello again"),
        ("first use of PingFang (hashes the .ttc)", "#set text(font: (\"Inter\", \"SF Pro Text\", \"PingFang SC\"))\nhello 你好"),
        ("inline + display math", "$x^2$ and $ integral_0^1 x dif x $"),
        ("raw block (syntect syntax set)", "```rust\nfn main() {}\n```"),
    ] {
        let start = Instant::now();
        compile(source);
        println!("{label:<44} {:6.1} ms", ms(start));
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("stages") if args.len() > 1 => stages(&args[1..]),
        Some("variants") if args.len() > 1 => variants(&args[1..]),
        Some("first-use") => first_use(),
        _ => {
            eprintln!("usage: stage_probe stages|variants <file.md>... | stage_probe first-use");
            std::process::exit(2);
        }
    }
}
