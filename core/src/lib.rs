pub mod c_api;
pub mod compiler;
pub mod parser;

use std::path::Path;
use compiler::engine::{compile_typst_to_pdf, CompileError, RenderOptions};
use parser::markdown::convert_markdown_to_typst;

/// High-level function: Compiles Markdown directly into a PDF byte stream.
///
/// 1. Transpiles Markdown + LaTeX Math + Mermaid into Typst code and virtual assets.
/// 2. Compiles Typst into an in-memory PDF stream using the embedded Typst engine.
pub fn compile_markdown_to_pdf(
    markdown: &str,
    title: &str,
    doc_dir: impl AsRef<Path>,
    options: &RenderOptions,
) -> Result<Vec<u8>, CompileError> {
    let parsed = convert_markdown_to_typst(markdown, title, options);
    compile_typst_to_pdf(&parsed.typst_source, doc_dir, parsed.virtual_files)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_e2e_markdown_to_pdf_fluid_mode() {
        let md = r#"
# SoGoodViewer: Modern Desktop Markdown Reader

Welcome to **SoGoodViewer**! This is a test document.

## Mathematical Equations
Inline formula: $e^{i \pi} + 1 = 0$

Block equation:
$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

## Architecture Diagram
```mermaid
graph LR
  Markdown --> Typst
  Typst --> PDFium
  PDFium --> Screen
```

## Features & Comparison
| Feature | SoGoodViewer | Electron Viewer |
| :--- | :--- | :--- |
| Engine | Typst + PDFium | Chromium WebView |
| Memory | < 60 MB | > 300 MB |
| Pixel Perfect | Yes (Vector) | Varies by OS |

## Action Items
- [x] Pure Rust backend
- [x] In-memory Typst compiler
- [x] Mermaid vector support
- [ ] Mobile version (Not planned)

> [!TIP]
> This reader is designed for the most discerning users who demand pixel-perfect typography.
"#;

        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            viewport_width: 800.0,
            font_size: 10.5,
        };

        let result = compile_markdown_to_pdf(md, "E2E Test", ".", &options);

        assert!(result.is_ok(), "End-to-end compilation failed: {:?}", result.err());


        let pdf = result.unwrap();
        assert!(pdf.starts_with(b"%PDF-"), "Invalid PDF header");
        assert!(pdf.len() > 1000, "PDF size is unexpectedly small: {} bytes", pdf.len());
        println!("Successfully generated E2E Fluid PDF ({} bytes)", pdf.len());
    }

    #[test]
    fn test_e2e_markdown_to_pdf_dark_paged_mode() {
        let md = r#"
# Dark Mode Paper

This is an A4 paginated paper in dark mode.

$ \nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} $

```rust
fn main() {
    println!("Hello from SoGoodViewer!");
}
```
"#;

        let options = RenderOptions {
            mode: "paged".to_string(),
            theme: "dark".to_string(),
            viewport_width: 800.0,
            font_size: 11.0,
        };

        let result = compile_markdown_to_pdf(md, "Dark Paper", ".", &options);
        assert!(result.is_ok(), "Dark paged compilation failed: {:?}", result.err());
        let pdf = result.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_compile_real_world_prd_document() {

        let test_md_path = std::path::Path::new("../test.md");
        if test_md_path.exists() {
            let content = std::fs::read_to_string(test_md_path).expect("Read test.md");
            let options = RenderOptions {
                mode: "fluid".to_string(),
                theme: "light".to_string(),
                viewport_width: 850.0,
                font_size: 10.5,
            };
            let start = std::time::Instant::now();
            let res = compile_markdown_to_pdf(&content, "AI Relay PRD", "..", &options);
            let elapsed = start.elapsed();
            assert!(res.is_ok(), "Failed to compile real-world test.md: {:?}", res.err());
            let pdf = res.unwrap();
            assert!(pdf.starts_with(b"%PDF-"));
            println!("Compiled 683-line real-world PRD in {:?}, generated PDF bytes: {}", elapsed, pdf.len());
        }
    }
}

