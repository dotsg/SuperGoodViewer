pub mod c_api;
pub mod compiler;
pub mod parser;

use std::path::{Path, PathBuf};
use compiler::engine::{
    compile_typst_to_document_with_raw_equations, evict_memo_cache, export_document_to_pdf, CompileError,
    RenderOptions, FLUID_CAPPED_PAGE_HEIGHT_PT,
};
use parser::markdown::convert_markdown_to_typst;
use typst::layout::{Frame, FrameItem, Point};

/// Recursively checks if any content in a Frame extends beyond the page height
/// or was clipped by a container group that was forced to shrink by pagination.
fn frame_has_overflow(frame: &Frame, origin: Point, page_height: f64) -> bool {
    for (pos, item) in frame.items() {
        let abs_pos = origin + *pos;
        match item {
            FrameItem::Group(group) => {
                // Check if the group itself extends beyond the page height
                if abs_pos.y.to_pt() + group.frame.size().y.to_pt() > page_height + 1.0 {
                    return true;
                }

                if group.clip.is_some() {
                    let group_h = group.frame.size().y.to_pt();
                    // Check direct children of the clipped container (e.g. image container block).
                    // If a direct child group or direct image's layout height exceeds the container,
                    // the container was forced to shrink by pagination, clipping the element.
                    // Deliberate aspect-ratio crops (e.g. width=100, height=10) place an inner
                    // group whose layout size matches the container (10pt), so they are not flagged.
                    for (inner_pos, inner_item) in group.frame.items() {
                        let inner_bottom = inner_pos.y.to_pt() + match inner_item {
                            FrameItem::Group(inner_group) => inner_group.frame.size().y.to_pt(),
                            FrameItem::Image(_, size, _) => size.y.to_pt(),
                            _ => 0.0,
                        };
                        if inner_bottom > group_h + 1.0 {
                            return true;
                        }
                    }
                    // Since group.clip is true and no direct child exceeds group_h, everything inside
                    // is safely bounded by group.size (which fits within page_height).
                } else {
                    // Group does not clip its children, so recurse to check if unclipped children overflow.
                    if frame_has_overflow(&group.frame, abs_pos, page_height) {
                        return true;
                    }
                }
            }
            FrameItem::Image(_, size, _) => {
                if abs_pos.y.to_pt() + size.y.to_pt() > page_height + 1.0 {
                    return true;
                }
            }
            FrameItem::Shape(_, _) | FrameItem::Text(_) => {
                if abs_pos.y.to_pt() > page_height + 1.0 {
                    return true;
                }
            }
            _ => {}
        }
    }
    false
}

/// Checks whether any page in the document suffered content clipping or overflow,
/// or contains empty pages caused by oversized blocks forcing premature page breaks.
fn document_has_overflow(doc: &typst_layout::PagedDocument) -> bool {
    for page in doc.pages() {
        if page.frame.items().len() == 0 {
            return true;
        }
        let page_height = page.frame.size().y.to_pt();
        if frame_has_overflow(&page.frame, Point::zero(), page_height) {
            return true;
        }
    }
    false
}

/// High-level function: Compiles Markdown directly into a PDF byte stream.
///
/// 1. Transpiles Markdown + LaTeX Math + Mermaid into Typst code and virtual assets.
/// 2. Compiles Typst into an in-memory PDF stream using the embedded Typst engine.
#[derive(Debug)]
pub struct MarkdownCompilationResult {
    pub pdf_bytes: Vec<u8>,
    pub degraded_equation_count: usize,
    pub degraded_equations: Vec<String>,
}

/// High-level function: Compiles Markdown directly into a PDF byte stream with compilation metadata.
///
/// Every exit path releases stale Typst memo entries through [`evict_memo_cache`],
/// so a long-running process (hot reload, many documents) does not accumulate
/// layout caches for content it will never compile again.
pub fn compile_markdown_to_pdf_result(
    markdown: &str,
    title: &str,
    doc_dir: impl AsRef<Path>,
    options: &RenderOptions,
) -> Result<MarkdownCompilationResult, CompileError> {
    let result = compile_markdown_to_pdf_result_uncached(markdown, title, doc_dir, options);
    evict_memo_cache();
    result
}

/// The compilation itself. Runs one or more internal Typst compilations (fluid
/// slice candidates share memo entries), so eviction belongs to the caller above
/// rather than anywhere in here.
fn compile_markdown_to_pdf_result_uncached(
    markdown: &str,
    title: &str,
    doc_dir: impl AsRef<Path>,
    options: &RenderOptions,
) -> Result<MarkdownCompilationResult, CompileError> {
    let cache_dir = options.image_cache_dir.as_ref().map(PathBuf::from);

    // Pass 1: Parse and compile the document (defaults to natural height for fluid mode).
    // Moving parsed.virtual_files avoids cloning large image or diagram buffers in memory.
    let parsed = convert_markdown_to_typst(markdown, title, options);
    let document = compile_typst_to_document_with_raw_equations(
        &parsed.typst_source,
        doc_dir.as_ref(),
        parsed.virtual_files,
        cache_dir.clone(),
        &parsed.raw_equations,
    )?;

    let valid_fluid_page_height = options.valid_fluid_page_height();

    // Check if rendered layout height exceeds the PDF 1.7 default user space limit (14,400pt).
    // We check against FLUID_CAPPED_PAGE_HEIGHT_PT (14,000pt), which provides a 400pt safety margin.
    // If parsed.is_fluid is true and slicing is not explicitly disabled or specified,
    // we inspect actual layout height across all pages.
    if parsed.is_fluid && options.disable_fluid_slice != Some(true) && valid_fluid_page_height.is_none() {
        let max_height = document
            .pages()
            .iter()
            .map(|p| p.frame.size().y.to_pt())
            .fold(0.0f64, f64::max);

        if max_height > FLUID_CAPPED_PAGE_HEIGHT_PT as f64 {
            let expected_slices = (max_height / FLUID_CAPPED_PAGE_HEIGHT_PT as f64).ceil() as usize;
            let dynamic_slice_height = (max_height / expected_slices as f64) as f32;

            // Candidate B: Dynamic slice height (H / ceil(H / 14000)), substantially reducing blank tail
            let mut opts_b = options.clone();
            opts_b.fluid_page_height = Some(dynamic_slice_height);
            let parsed_b = convert_markdown_to_typst(markdown, title, &opts_b);
            let doc_b = compile_typst_to_document_with_raw_equations(
                &parsed_b.typst_source,
                doc_dir.as_ref(),
                parsed_b.virtual_files,
                cache_dir.clone(),
                &parsed_b.raw_equations,
            )?;

            let overflow_b = document_has_overflow(&doc_b);
            let pages_b = doc_b.pages().len();
            let canvas_b = pages_b as f64 * dynamic_slice_height as f64;
            // Candidate A's page count must be >= expected_slices, so expected_slices * 14000
            // represents the theoretical minimum canvas of Candidate A (a lower bound).
            let min_canvas_a = expected_slices as f64 * FLUID_CAPPED_PAGE_HEIGHT_PT as f64;

            // Content integrity takes precedence over canvas area:
            // 1. If Candidate B suffered content clipping/overflow (e.g. a tall unbreakable block
            //    exceeded dynamic_slice_height), we must compile Candidate A to preserve content.
            // 2. If Candidate B has no overflow, but severe page spillover caused its canvas to exceed
            //    Candidate A's theoretical minimum (canvas_b > min_canvas_a), we compile Candidate A.
            // Otherwise (no overflow and canvas_b <= min_canvas_a), Candidate B is provably optimal.
            if overflow_b || canvas_b > min_canvas_a {
                let mut opts_a = options.clone();
                opts_a.fluid_page_height = Some(FLUID_CAPPED_PAGE_HEIGHT_PT);
                let parsed_a = convert_markdown_to_typst(markdown, title, &opts_a);
                let doc_a = compile_typst_to_document_with_raw_equations(
                    &parsed_a.typst_source,
                    doc_dir.as_ref(),
                    parsed_a.virtual_files,
                    cache_dir,
                    &parsed_a.raw_equations,
                )?;

                let overflow_a = document_has_overflow(&doc_a);
                if overflow_b && !overflow_a {
                    // Candidate A preserves content integrity while Candidate B clipped content.
                    let count = doc_a.degraded_equation_count;
                    let equations = doc_a.degraded_equations.clone();
                    let pdf_bytes = export_document_to_pdf(&doc_a)?;
                    return Ok(MarkdownCompilationResult {
                        pdf_bytes,
                        degraded_equation_count: count,
                        degraded_equations: equations,
                    });
                }
                if !overflow_b && overflow_a {
                    // Candidate B preserves content integrity while Candidate A clipped content.
                    let count = doc_b.degraded_equation_count;
                    let equations = doc_b.degraded_equations.clone();
                    let pdf_bytes = export_document_to_pdf(&doc_b)?;
                    return Ok(MarkdownCompilationResult {
                        pdf_bytes,
                        degraded_equation_count: count,
                        degraded_equations: equations,
                    });
                }

                let pages_a = doc_a.pages().len();
                let canvas_a = pages_a as f64 * FLUID_CAPPED_PAGE_HEIGHT_PT as f64;

                // When content integrity is equivalent (neither overflows, or both overflow),
                // choose whichever produces the smaller total canvas.
                if canvas_a < canvas_b {
                    let count = doc_a.degraded_equation_count;
                    let equations = doc_a.degraded_equations.clone();
                    let pdf_bytes = export_document_to_pdf(&doc_a)?;
                    return Ok(MarkdownCompilationResult {
                        pdf_bytes,
                        degraded_equation_count: count,
                        degraded_equations: equations,
                    });
                }
            }

            let count = doc_b.degraded_equation_count;
            let equations = doc_b.degraded_equations.clone();
            let pdf_bytes = export_document_to_pdf(&doc_b)?;
            return Ok(MarkdownCompilationResult {
                pdf_bytes,
                degraded_equation_count: count,
                degraded_equations: equations,
            });
        }
    }

    let count = document.degraded_equation_count;
    let equations = document.degraded_equations.clone();
    let pdf_bytes = export_document_to_pdf(&document)?;
    Ok(MarkdownCompilationResult {
        pdf_bytes,
        degraded_equation_count: count,
        degraded_equations: equations,
    })
}

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
    compile_markdown_to_pdf_result(markdown, title, doc_dir, options).map(|r| r.pdf_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_e2e_markdown_to_pdf_fluid_mode() {
        let md = r#"
# SuperGoodViewer: Modern Desktop Markdown Reader

Welcome to **SuperGoodViewer**! This is a test document.

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
| Feature | SuperGoodViewer | Electron Viewer |
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
            ..Default::default()
        };

        let result = compile_markdown_to_pdf(md, "E2E Test", ".", &options);

        assert!(result.is_ok(), "End-to-end compilation failed: {:?}", result.err());


        let pdf = result.unwrap();
        assert!(pdf.starts_with(b"%PDF-"), "Invalid PDF header");
        assert!(pdf.len() > 1000, "PDF size is unexpectedly small: {} bytes", pdf.len());
        println!("Successfully generated E2E Fluid PDF ({} bytes)", pdf.len());
    }

    #[test]
    fn test_emoji_compilation() {
        let md = "🚀 ✨ 🎯 📐 📊 🖥 🪟 ⚙️ ⌨️ ⚡ 💾 🎨 📦 👉";
        let options = RenderOptions::default();
        let result = compile_markdown_to_pdf(md, "Emoji Test", ".", &options);
        assert!(result.is_ok());
        let pdf = result.unwrap();
        println!("Emoji PDF bytes: {}", pdf.len());
        assert!(pdf.len() > 50_000, "Emoji PDF should contain embedded font glyph data");
    }

    #[test]
    fn test_e2e_markdown_to_pdf_dark_paged_mode() {
        let md = r#"
# Dark Mode Paper

This is an A4 paginated paper in dark mode.

$ \nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} $

```rust
fn main() {
    println!("Hello from SuperGoodViewer!");
}
```
"#;

        let options = RenderOptions {
            mode: "paged".to_string(),
            theme: "dark".to_string(),
            viewport_width: 800.0,
            font_size: 11.0,
            ..Default::default()
        };

        let result = compile_markdown_to_pdf(md, "Dark Paper", ".", &options);
        assert!(result.is_ok(), "Dark paged compilation failed: {:?}", result.err());
        let pdf = result.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_long_document_fluid_auto() {
        let mut long_md = String::new();
        for i in 0..300 {
            long_md.push_str(&format!(
                "## Section {}\n\nParagraph 1 for section {}. This contains detailed engineering explanations.\n\nParagraph 2 for section {}. Testing long document continuous rendering in fluid mode.\n\n",
                i, i, i
            ));
        }

        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            viewport_width: 850.0,
            font_size: 10.5,
            ..Default::default()
        };

        let start = std::time::Instant::now();
        let result = compile_markdown_to_pdf(&long_md, "Long Fluid Doc", ".", &options);
        let elapsed = start.elapsed();
        assert!(result.is_ok(), "Long fluid compilation failed: {:?}", result.err());
        let pdf = result.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
        println!("Compiled 300 sections ({} chars) in {:?}, generated PDF bytes: {}", long_md.len(), elapsed, pdf.len());
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
                ..Default::default()
            };
            let start = std::time::Instant::now();
            let parsed = convert_markdown_to_typst(&content, "IQRP Quantum Spec", &options);
            let res = compile_markdown_to_pdf(&content, "IQRP Quantum Spec", "..", &options);
            let elapsed = start.elapsed();
            if let Err(ref e) = res {
                eprintln!("Failed typst error: {:?}", e);
                eprintln!("Generated typst source:\n{}", parsed.typst_source);
            }
            assert!(res.is_ok(), "Failed to compile test.md: {:?}", res.err());
            let pdf = res.unwrap();
            assert!(pdf.starts_with(b"%PDF-"));
            assert!(
                parsed.typst_source.contains("]/**/"),
                "test.md parsed typst source should use ]/**/ delimiter"
            );
            println!("Compiled rich test.md spec in {:?}, generated PDF bytes: {}", elapsed, pdf.len());
        }
    }

    fn extract_all_mediabox_heights(pdf_bytes: &[u8]) -> Vec<f64> {
        let s = String::from_utf8_lossy(pdf_bytes);
        let mut heights = Vec::new();
        let marker = "/MediaBox";
        let mut search_from = 0;
        while let Some(pos) = s[search_from..].find(marker) {
            let abs_pos = search_from + pos;
            let rest = &s[abs_pos + marker.len()..];
            if let (Some(start), Some(end)) = (rest.find('['), rest.find(']')) {
                let inner = &rest[start + 1..end];
                let numbers: Vec<&str> = inner.split_whitespace().collect();
                if numbers.len() == 4 {
                    if let Ok(h) = numbers[3].parse::<f64>() {
                        heights.push(h);
                    }
                }
                search_from = abs_pos + marker.len() + end + 1;
            } else {
                break;
            }
        }
        heights
    }

    #[test]
    fn test_fluid_two_pass_auto_height_and_capped_fallback() {
        // Construct a document with 1480 lines / ~19k chars whose rendered height
        // exceeds 14,400pt (PDF 1.7 limit). The two-pass strategy must detect the
        // actual height and automatically re-compile with dynamic slices <= 14,000pt
        // so that the canvas fits the content without a large blank tail.
        let mut tall_md = String::new();
        for i in 0..740 {
            tall_md.push_str(&format!("Line {i}\n\n"));
        }

        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            viewport_width: 850.0,
            font_size: 10.5,
            ..Default::default()
        };

        let res = compile_markdown_to_pdf(&tall_md, "Tall Document", ".", &options);
        assert!(res.is_ok(), "Tall document failed two-pass compile: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));

        // Verify that two-pass dynamically sliced the document into multiple pages
        let heights = extract_all_mediabox_heights(&pdf);
        assert!(heights.len() > 1, "Tall document must be sliced into multiple pages, got {}", heights.len());
        for (i, h) in heights.iter().enumerate() {
            assert!(*h <= 14000.5, "Page {i} height {h}pt exceeds 14,000pt limit");
            // Dynamic slicing should produce ~7837pt per page rather than a fixed 14,000pt
            assert!(*h < 10000.0, "Page {i} height {h}pt should be dynamically sliced (~7837pt), not fixed 14000pt");
        }
        // Verify blank tail elimination: total canvas must closely match natural height (~15674pt)
        let total_canvas: f64 = heights.iter().sum();
        assert!(total_canvas < 16500.0, "Total canvas {total_canvas}pt must not leave large blank tail (was 28,000pt)");
    }

    #[test]
    fn test_fluid_frontmatter_two_pass_tall_document() {
        // Reproduce P1: Frontmatter page_format: fluid with default RenderOptions
        // (options.page_format is None, options.mode is default).
        // A tall document with 480 table rows with <br> exceeds 14,000pt.
        // Must correctly trigger two-pass capping instead of outputting a 35,000pt+ single page.
        let mut md = String::from("---\npage_format: fluid\n---\n\n| Col A | Col B |\n| --- | --- |\n");
        for i in 0..480 {
            md.push_str(&format!("| Cell {i} A<br>extra line 1<br>extra line 2 | Cell {i} B |\n"));
        }

        let options = RenderOptions {
            viewport_width: 850.0,
            ..Default::default()
        };

        let res = compile_markdown_to_pdf(&md, "Tall Frontmatter Doc", ".", &options);
        assert!(res.is_ok(), "Tall frontmatter compile failed: {:?}", res.err());
        let pdf = res.unwrap();
        let heights = extract_all_mediabox_heights(&pdf);
        assert!(heights.len() > 1, "Frontmatter fluid document must be sliced into multiple pages");
        for (i, h) in heights.iter().enumerate() {
            assert!(*h <= 14000.5, "Page {i} height {h}pt exceeds 14,000pt limit");
        }
    }

    #[test]
    fn test_fluid_escape_hatch_disables_capping() {
        let mut tall_md = String::new();
        for i in 0..740 {
            tall_md.push_str(&format!("Line {i}\n\n"));
        }

        let disabled_opts = RenderOptions {
            mode: "fluid".to_string(),
            viewport_width: 850.0,
            disable_fluid_slice: Some(true),
            ..Default::default()
        };
        let res = compile_markdown_to_pdf(&tall_md, "Tall Disabled", ".", &disabled_opts);
        assert!(res.is_ok(), "Tall disabled failed compile: {:?}", res.err());
        let heights = extract_all_mediabox_heights(&res.unwrap());
        assert_eq!(heights.len(), 1, "disable_fluid_slice must keep a single page");
        assert!(heights[0] > 14000.0, "disable_fluid_slice must keep natural height, got {}pt", heights[0]);
    }

    #[test]
    fn test_fluid_tall_blocks_candidate_comparison() {
        // Construct a document with 25 tall blocks (1300pt each).
        // Self-contained: does not depend on external assets; unresolvable images safely
        // fall back to a transparent placeholder while preserving the 1300pt layout box.
        //
        // Measured metrics:
        // - Natural height ~33,756pt -> expected_slices = 3, min_canvas_a = 42,000pt.
        // - Candidate B (dynamic slice ~11,252pt): each page fits at most 8 blocks (10,400pt),
        //   causing 25 blocks to spill across 4 pages -> canvas_B = 4 * 11,252pt ≈ 45,008pt > 42,000pt.
        // - Candidate A (slice 14,000pt): each page fits 10 blocks -> fits in 3 pages = 42,000pt.
        // Candidate A wins because canvas_A (42,000pt) < canvas_B (45,008pt).
        let mut md = String::new();
        for i in 0..25 {
            md.push_str(&format!("### Section {i}\n\nParagraph text {i}.\n\n<img src=\"dummy.png\" height=\"1300pt\" />\n\n"));
        }

        let options = RenderOptions {
            mode: "fluid".to_string(),
            viewport_width: 850.0,
            ..Default::default()
        };

        let res = compile_markdown_to_pdf(&md, "Tall Blocks Doc", ".", &options);
        assert!(res.is_ok(), "Tall blocks compile failed: {:?}", res.err());
        let pdf = res.unwrap();
        let heights = extract_all_mediabox_heights(&pdf);
        assert_eq!(heights.len(), 3, "Candidate A should win with exactly 3 pages (Candidate B would spill to 4)");
        for (i, h) in heights.iter().enumerate() {
            assert_eq!(*h, 14000.0, "Page {i} height {h}pt should be Candidate A (14,000pt)");
        }
    }

    #[test]
    fn test_fluid_content_integrity_tall_block_prefers_candidate_a() {
        let temp_dir = std::env::temp_dir().join(format!("sgv_test_svg_{}", std::process::id()));
        std::fs::create_dir_all(&temp_dir).unwrap();
        let tall_svg = r#"<svg xmlns="http://www.w3.org/2000/svg" width="800" height="10000"><rect width="800" height="10000" fill="red"/></svg>"#;
        let crop_svg = r#"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100"><rect width="100" height="100" fill="blue"/></svg>"#;
        std::fs::write(temp_dir.join("tall.svg"), tall_svg).unwrap();
        std::fs::write(temp_dir.join("crop.svg"), crop_svg).unwrap();

        let mut md = String::new();
        md.push_str("<img src=\"tall.svg\" height=\"10000pt\" />\n\n");
        md.push_str("<img src=\"crop.svg\" width=\"100pt\" height=\"10pt\" />\n\n");
        for i in 0..400 {
            md.push_str(&format!("Paragraph {i} with some content to fill up the page.\n\n"));
        }

        let options = RenderOptions {
            mode: "fluid".to_string(),
            viewport_width: 850.0,
            ..Default::default()
        };

        let res = compile_markdown_to_pdf(&md, "Integrity Test", &temp_dir, &options);
        assert!(res.is_ok(), "Compile failed: {:?}", res.err());
        let pdf = res.unwrap();
        let heights = extract_all_mediabox_heights(&pdf);
        assert_eq!(heights.len(), 2, "Candidate A should be selected with 2 pages of 14,000pt");
        for (i, h) in heights.iter().enumerate() {
            assert_eq!(*h, 14000.0, "Page {i} height {h}pt should be 14,000pt (Candidate A)");
        }

        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_compile_sample_document_full_modes() {
        let sample_md = r#"
# SuperGoodViewer 🚀
### 出版级排版 Markdown 桌面阅读器

欢迎体验 **SuperGoodViewer**！本应用通过 **Typst 嵌入式编译 + PDFium 矢量渲染**，为您提供极致的阅读美感与跨平台 100% 像素级一致性。

---

## 📐 高精度数学排版 (LaTeX 支持)

麦克斯韦方程组微分形式：

$$
\begin{cases}
\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} = 0 \\
\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} \\
\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{cases}
$$

高斯积分：

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

---

## 📊 Mermaid 离线纯矢量渲染

```mermaid
graph LR
  MD[Markdown Source] --> P[Rust Pulldown-Cmark]
  P --> M[TeX & Mermaid Transpiler]
  M --> T[Typst Memory Engine]
  T --> PDF[Vector PDF Stream]
  PDF --> V[Google PDFium Viewport]
```

---

## 🔤 CJK 1:2 等宽代码与 ASCII 字符表

搭配 **Maple Mono** 字体，实现中英文全角半角严格 1:2 绝对对齐：

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│ 1. 量子纠缠分发与纯化引擎 (QED)     │ 2. 相对论时空测地线同步网关 (STG)   │
├─────────────────────────────────────┼─────────────────────────────────────┤
│ · 贝尔态多粒子纯化与量子中继存储    │ · 史瓦西引力场时间膨胀动态频率修正  │
│ · 纠缠交换路由与拓扑自动愈合        │ · 纳秒级深空原子钟激光同步信标      │
│ · 拓扑容错量子表面码校验 (Surface)  │ · 任意子非阿贝尔统计相位标定        │
│ · 兆赫兹纠缠对生成与自旋偏振锁定    │ · 零知识量子密钥分发与抗监听验证    │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

---

## 🎯 核心工程特性对比

| 衡量维度 | SuperGoodViewer (纯原生) | 传统 Electron / WebView 阅读器 |
| :--- | :--- | :--- |
| **排版引擎** | **Typst 出版级矢量排版** | 浏览器 DOM / Webview 屏幕流动 |
| **内存占用** | **~ 45 MB** | **~ 350 MB - 1 GB** |
| **冷启动耗时** | **< 100 ms** | **~ 1.5 s - 3 s** |
| **跨平台一致性** | **100% 像素级吻合** | 字体、行高、渲染随系统漂移 |
| **打印/导出** | **0 毫秒即时导出无损 PDF** | 分页被截断、需二次排版转换 |

---

## 🛠 功能体验清单

- [x] 纯 Rust 进程内嵌入式编译，零外部 CLI 依赖
- [x] 连续流式长卷轴 (Fluid) 与 A4 出版打印 (Paged) 一键切换
- [x] 原生亮色 (Light) / 暗黑 (Dark) 主题支持
- [x] 外部修改秒级自动热重载，并智能保持阅读视口位置
- [x] 0 毫秒即时导出 PDF

> [!TIP]
> 点击顶部工具栏的 **视图切换** 按钮，可在自适应屏幕长卷轴与标准 A4 打印预览间丝滑切换。
"#;

        for mode in &["fluid", "paged"] {
            for theme in &["light", "dark"] {
                let options = RenderOptions {
                    mode: mode.to_string(),
                    theme: theme.to_string(),
                    viewport_width: 800.0,
                    font_size: 10.5,
                    ..Default::default()
                };
                let parsed = convert_markdown_to_typst(sample_md, "Sample Document", &options);
                if mode == &"fluid" && theme == &"light" {
                    println!("--- GENERATED TYPST SOURCE ---\n{}\n--- END SOURCE ---", parsed.typst_source);
                }
                let res = compile_markdown_to_pdf(sample_md, "Sample Document", ".", &options);
                assert!(res.is_ok(), "Failed for mode={}, theme={}: {:?}", mode, theme, res.err());
                let pdf = res.unwrap();
                assert!(pdf.starts_with(b"%PDF-"));
                println!("Sample doc mode={}, theme={} compiled: {} bytes", mode, theme, pdf.len());
            }
        }
    }

    #[test]
    fn test_compile_ascii_table_with_maple_mono() {
        let md = r#"
# ASCII Table Test

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│ 1. 量子纠缠分发与纯化引擎 (QED)     │ 2. 相对论时空测地线同步网关 (STG)   │
├─────────────────────────────────────┼─────────────────────────────────────┤
│ · 贝尔态多粒子纯化与量子中继存储    │ · 史瓦西引力场时间膨胀动态频率修正  │
│ · 纠缠交换路由与拓扑自动愈合        │ · 纳秒级深空原子钟激光同步信标      │
│ · 拓扑容错量子表面码校验 (Surface)  │ · 任意子非阿贝尔统计相位标定        │
│ · 兆赫兹纠缠对生成与自旋偏振锁定    │ · 零知识量子密钥分发与抗监听验证    │
└─────────────────────────────────────┴─────────────────────────────────────┘
```
"#;
        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            ..Default::default()
        };
        let res = compile_markdown_to_pdf(md, "ASCII Align", ".", &options);
        assert!(res.is_ok(), "ASCII table failed to compile: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_all_equations() {
        let equations = [
            r"ds^2 = -\left(1 - \frac{2GM}{r c^2}\right) c^2 dt^2 + \left(1 - \frac{2GM}{r c^2}\right)^{-1} dr^2 + r^2 (d\theta^2 + \sin^2\theta \, d\phi^2)",
            r"\frac{d\tau}{dt} = \sqrt{1 - \frac{2GM}{r c^2} - \frac{v^2}{c^2}} \approx 1 - \frac{GM}{r c^2} - \frac{v^2}{2c^2} + \mathcal{O}(c^{-4})",
            r"G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}",
            r"\Delta t_{\text{Shapiro}} = \frac{2GM_\odot}{c^3} \ln \left( \frac{4 r_1 r_2}{d^2} \right)",
            r"\mathrm{Var}(\hat{\theta}) \ge \frac{1}{\mathcal{F}_Q[\rho(\theta)]}, \quad \mathcal{F}_Q = 4 \sum_{k} \frac{(\partial_\theta \lambda_k)^2}{\lambda_k} + 2 \sum_{k \neq m} \frac{(\lambda_k - \lambda_m)^2}{\lambda_k + \lambda_m} |\langle \psi_k | \partial_\theta \psi_m \rangle|^2",
            r"|\Phi^\pm\rangle = \frac{1}{\sqrt{2}} (|00\rangle \pm |11\rangle), \quad |\Psi^\pm\rangle = \frac{1}{\sqrt{2}} (|01\rangle \pm |10\rangle)",
            r"|\Phi^+_{12}\rangle \otimes |\Phi^+_{34}\rangle = \frac{1}{2} \left[ |\Phi^+_{23}\rangle |\Phi^+_{14}\rangle + |\Phi^-_{23}\rangle |\Phi^-_{14}\rangle + |\Psi^+_{23}\rangle |\Psi^+_{14}\rangle + |\Psi^-_{23}\rangle |\Psi^-_{14}\rangle \right]",
            r"\frac{d\rho(t)}{dt} = -\frac{i}{\hbar} [H_{\text{eff}}, \rho(t)] + \sum_{k=1}^M \left( L_k \rho(t) L_k^\dagger - \frac{1}{2} \{L_k^\dagger L_k, \rho(t)\} \right)",
            r"[\bar{X}, \bar{Z}] = 0 \pmod 2, \quad \mathcal{S} = \langle A_s, B_p \rangle",
            r"A_s = \prod_{j \in \text{star}(s)} X_j",
            r"B_p = \prod_{j \in \partial p} Z_j",
            r"b_1 b_2 \in \{00,01,10,11\}",
            r"\sigma_x^{b_2} \sigma_z^{b_1}",
            r"F = 99.42\%",
            r"[\hat{q}, \hat{p}] = i \hbar, \quad \Delta \hat{q} \cdot \Delta \hat{p} \ge \frac{\hbar}{2}",
            r"V_A = V_A^{\text{mod}} + 1, \quad T_{\text{channel}} = 10^{-\alpha L / 10}",
        ];
        let options = RenderOptions::default();
        for (i, eq) in equations.iter().enumerate() {
            let md = format!("$$\n{}\n$$", eq);
            let res = compile_markdown_to_pdf(&md, "Math Test", ".", &options);
            assert!(res.is_ok(), "Equation {} failed: {:?}\nLaTeX: {}", i + 1, res.err(), eq);
        }
    }

    #[test]
    fn test_heading_with_quotes_compilation() {
        let md = r#"
# heading with "quotes" inside

## "Quote at start" and "Quote at end"

Paragraph mentioning "quotes" in body.
"#;
        let options = RenderOptions::default();
        let res = compile_markdown_to_pdf(md, "Doc with \"quotes\"", ".", &options);
        assert!(res.is_ok(), "Markdown with quotes failed to compile: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_compile_datasheet_register_tables() {
        // Representative excerpt from hardware datasheets: underscores in
        // identifiers, @ in headings, HTML <br> inside table cells, and
        // quoted pin names with a trailing *Note marker.
        let md = r#"
## 6.1.4.8 eSPI PC Control 0 (ESPCTRL0)

Supports AW\_FCS hardwired mechanism

## BFNAME@REGNAME

Endless loop to wait for FCEAF@ESGCTRL0 = 1 and Write 1b Clear.

It's allowed to let {VSTBY,VFSPI}={on,off}.

n = 1 ~ 8

//Register Write

| Bit | R/W | Description |
|-----|-----|-------------|
| 7 | R/WC | PUT_PC Status<br>3h: Message<br>4h: Message with Data |
| 5-0 | R | Target RPMC Supported.<br>0h: The slave does not support RPMC. |

| Pin | Signal |
|-----|--------|
| 3 | "SSCE1#/CEC1/GPH7' or 'VCORE2" *Note |

## Index: 30h

First index.

## Index: 30h

Second index.
"#;
        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            viewport_width: 850.0,
            font_size: 10.5,
            ..Default::default()
        };
        let parsed = convert_markdown_to_typst(md, "IT51378 Excerpt", &options);
        let res = compile_markdown_to_pdf(md, "IT51378 Excerpt", ".", &options);
        if let Err(ref e) = res {
            eprintln!("Datasheet excerpt failed: {e:?}");
            eprintln!("Generated typst source:\n{}", parsed.typst_source);
        }
        assert!(res.is_ok(), "Datasheet excerpt failed to compile: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    #[ignore = "set SGV_LARGE_MD to a large Markdown path and run with --ignored"]
    fn test_compile_large_external_markdown_if_present() {
        let path = match std::env::var_os("SGV_LARGE_MD") {
            Some(p) => PathBuf::from(p),
            None => {
                eprintln!("Skipping: set SGV_LARGE_MD to a Markdown file path");
                return;
            }
        };
        if !path.exists() {
            panic!("SGV_LARGE_MD path does not exist: {}", path.display());
        }
        let content = std::fs::read_to_string(&path).expect("Read large markdown");
        let doc_dir = path.parent().unwrap_or(Path::new("."));
        let options = RenderOptions {
            mode: "fluid".to_string(),
            theme: "light".to_string(),
            viewport_width: 850.0,
            font_size: 10.5,
            ..Default::default()
        };
        let start = std::time::Instant::now();
        let pdf = compile_markdown_to_pdf(&content, "Large Markdown", doc_dir, &options)
            .unwrap_or_else(|err| panic!("Large markdown compile failed in {:?}: {:?}", start.elapsed(), err));
        let heights = extract_all_mediabox_heights(&pdf);
        println!(
            "Laid out {} page(s) in {:?}",
            heights.len(),
            start.elapsed()
        );
        for (i, h) in heights.iter().enumerate() {
            if i < 3 {
                println!(
                    "page {} size: {:.1}pt",
                    i + 1,
                    h
                );
            }
            assert!(
                *h <= 14000.5,
                "fluid page {} is too tall for PDF: {:.1}pt",
                i + 1,
                h
            );
        }
        assert!(
            heights.len() > 1,
            "large markdown should paginate in fluid mode"
        );
        assert!(pdf.starts_with(b"%PDF-"));
    }

    /// Guards the memo-cache eviction in [`compile_markdown_to_pdf_result`].
    ///
    /// Typst's `comemo` cache is process-global and never shrinks by itself, so
    /// compiling a stream of *different* documents used to grow resident memory
    /// by roughly 2.4 MB per compilation and never give it back. With eviction in
    /// place the curve plateaus instead. Measured on an M4 Max: the second batch
    /// below adds 0.2 MB with eviction and 40.5 MB without, so the 20 MB limit has
    /// room for allocator noise while still catching a regression.
    #[cfg(unix)]
    #[test]
    fn test_memo_cache_does_not_grow_across_distinct_documents() {
        fn rss_mb() -> f64 {
            let pid = std::process::id().to_string();
            let out = std::process::Command::new("ps")
                .args(["-o", "rss=", "-p", &pid])
                .output()
                .expect("ps failed");
            String::from_utf8_lossy(&out.stdout).trim().parse::<f64>().unwrap_or(0.0) / 1024.0
        }

        // Compile two equal batches of distinct documents and compare how much
        // resident memory each batch adds. The steady-state working set (the
        // generations eviction deliberately retains) is already paid for by the
        // first batch, so a healthy build adds almost nothing in the second one,
        // while an unevicted cache keeps climbing at the same rate.
        const BATCH: usize = 15;
        const MAX_SECOND_BATCH_GROWTH_MB: f64 = 20.0;

        let section = concat!(
            "## Memo cache growth probe\n\n",
            "Consider the equation $E = m c^2$ and the table below.\n\n",
            "| Metric | Node A | Node B |\n",
            "| :--- | :--- | :--- |\n",
            "| Throughput | 12,000 rps | 14,500 rps |\n\n",
            "```rust\n",
            "fn quorum(n: usize) -> usize { n / 2 + 1 }\n",
            "```\n\n",
        );
        // The entries that accumulate are layout results, so document size matters:
        // a 200-byte note barely moves resident memory, while a ~20 KB document
        // (a realistic chapter or spec) makes the growth unmistakable.
        let base: String = section.repeat(60);
        let options = RenderOptions::default();

        let compile_batch = |batch: usize, offset: usize| {
            for i in 0..batch {
                let doc = format!(
                    "{base}\n\nRevision {}: unique content forces a real compilation.\n",
                    offset + i
                );
                compile_markdown_to_pdf(&doc, "probe", ".", &options).expect("compile failed");
            }
        };

        // Warm-up: fonts and the shared library are one-off costs, not what this
        // test is about.
        compile_batch(3, 0);

        compile_batch(BATCH, 100);
        let after_first_batch = rss_mb();
        compile_batch(BATCH, 200);
        let growth = rss_mb() - after_first_batch;

        assert!(
            growth < MAX_SECOND_BATCH_GROWTH_MB,
            "resident memory grew another {growth:.1} MB over {BATCH} further distinct \
             compilations (limit {MAX_SECOND_BATCH_GROWTH_MB} MB), so the cache is still \
             growing - is the Typst memo cache still being evicted?"
        );
    }

    /// Pins how many full layout passes each shape of fluid document costs today.
    ///
    /// A layout pass is the expensive unit of work in the pipeline (~143 ms for a
    /// 100 KB book on an M4 Max; the natural-height, 14,000pt and dynamic-height
    /// passes all cost the same). Slicing a document taller than the PDF page limit
    /// inherently needs a second pass — the slice height cannot be known without
    /// laying the document out once — and a third when the dynamic-height candidate
    /// has to be compared against the capped one.
    ///
    /// This test does not claim the current counts are optimal. It exists so that
    /// any change to the slicing strategy has to state, in this file, what it did to
    /// the number of passes.
    #[test]
    fn test_fluid_slicing_layout_pass_counts() {
        use crate::compiler::engine::{layout_passes, reset_layout_passes};

        let options = RenderOptions {
            mode: "fluid".to_string(),
            viewport_width: 850.0,
            ..Default::default()
        };

        // A short document fits one page: one pass, no slicing machinery at all.
        reset_layout_passes();
        compile_markdown_to_pdf("# Short\n\nOne paragraph.\n", "Short", ".", &options)
            .expect("short compile failed");
        assert_eq!(
            layout_passes(),
            1,
            "a document that fits one page must cost exactly one layout pass"
        );

        // Taller than 14,000pt, content flows evenly: natural pass + candidate B.
        let mut tall = String::new();
        for i in 0..740 {
            tall.push_str(&format!("Line {i}\n\n"));
        }
        reset_layout_passes();
        compile_markdown_to_pdf(&tall, "Tall", ".", &options).expect("tall compile failed");
        assert_eq!(
            layout_passes(),
            2,
            "a sliced document costs the natural-height pass plus one candidate"
        );

        // Tall unbreakable blocks make the dynamic candidate spill, so the capped
        // candidate has to be laid out as well and wins (see
        // test_fluid_tall_blocks_candidate_comparison for the selection itself).
        let mut blocks = String::new();
        for i in 0..25 {
            blocks.push_str(&format!(
                "### Section {i}\n\nParagraph text {i}.\n\n<img src=\"dummy.png\" height=\"1300pt\" />\n\n"
            ));
        }
        reset_layout_passes();
        compile_markdown_to_pdf(&blocks, "Tall Blocks", ".", &options)
            .expect("tall blocks compile failed");
        assert_eq!(
            layout_passes(),
            3,
            "when both slice candidates must be compared, the cost is three passes"
        );

        // The escape hatch must never pay for a candidate.
        let disabled = RenderOptions {
            disable_fluid_slice: Some(true),
            ..options.clone()
        };
        reset_layout_passes();
        compile_markdown_to_pdf(&tall, "Tall Disabled", ".", &disabled)
            .expect("disabled compile failed");
        assert_eq!(
            layout_passes(),
            1,
            "disable_fluid_slice must skip the candidate passes entirely"
        );
    }

    struct TempDirGuard(std::path::PathBuf);
    impl Drop for TempDirGuard {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn test_percent_encoded_local_images_compilation() {
        let temp_dir = std::env::temp_dir().join(format!("sgv_img_test_{}", std::process::id()));
        let _guard = TempDirGuard(temp_dir.clone());
        let img_dir = temp_dir.join("Images attachments");
        std::fs::create_dir_all(&img_dir).unwrap();

        // 2x2 test red PNG (73 bytes) with dimensions (2, 2)
        const TEST_2X2_PNG: &[u8] = &[
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
            0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x02,
            0x08, 0x02, 0x00, 0x00, 0x00, 0xfd, 0xd4, 0x9a, 0x73, 0x00, 0x00, 0x00,
            0x10, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00,
            0x44, 0x0c, 0x10, 0x0a, 0x00, 0x1f, 0xee, 0x03, 0xfd, 0x8b, 0x5f, 0x14,
            0xd4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60,
            0x82,
        ];
        std::fs::write(img_dir.join("image 2.png"), TEST_2X2_PNG).unwrap();

        let md = "![image](Images%20attachments/image%202.png)";
        let opts = RenderOptions {
            mode: "fluid".to_string(),
            ..Default::default()
        };

        // 1. Verify via Typst document frame inspection that the image dimensions are (2, 2)
        // (rather than the 1x1 fallback for unresolvable images).
        let parsed = crate::parser::markdown::convert_markdown_to_typst(md, "Image Test", &opts);
        let world = crate::compiler::world::MemoryWorld::new(&parsed.typst_source, &temp_dir, parsed.virtual_files);
        let doc = typst::compile::<typst_layout::PagedDocument>(&world).output.expect("Typst compile must succeed");

        fn find_image_sizes(frame: &typst::layout::Frame, sizes: &mut Vec<(u32, u32)>) {
            for (_, item) in frame.items() {
                match item {
                    typst::layout::FrameItem::Group(group) => find_image_sizes(&group.frame, sizes),
                    typst::layout::FrameItem::Image(img, _, _) => {
                        sizes.push((img.width() as u32, img.height() as u32));
                    }
                    _ => {}
                }
            }
        }
        let mut image_sizes = Vec::new();
        find_image_sizes(&doc.pages()[0].frame, &mut image_sizes);
        assert_eq!(
            image_sizes,
            vec![(2, 2)],
            "The image must be resolved with its actual 2x2 dimensions, not broken image placeholder!"
        );

        // 2. Also contrast against an unresolvable image to prove fallback produces (64, 48)
        let parsed_missing = crate::parser::markdown::convert_markdown_to_typst("![image](Images%20attachments/nonexistent.png)", "Missing", &opts);
        let world_missing = crate::compiler::world::MemoryWorld::new(&parsed_missing.typst_source, &temp_dir, parsed_missing.virtual_files);
        let doc_missing = typst::compile::<typst_layout::PagedDocument>(&world_missing).output.expect("Typst compile missing");
        let mut missing_sizes = Vec::new();
        find_image_sizes(&doc_missing.pages()[0].frame, &mut missing_sizes);
        assert_eq!(
            missing_sizes,
            vec![(64, 48)],
            "Unresolvable PNG image must fall back to 64x48 broken image placeholder"
        );

        // 3. Verify end-to-end PDF compilation produces valid PDF for normal image
        let pdf = compile_markdown_to_pdf(md, "Image Test", &temp_dir, &opts)
            .expect("Compilation should succeed");
        assert!(pdf.starts_with(b"%PDF-"));

        // 4. Verify escaping paths (../secret.png, ..%2Fsecret.png) never cause fatal compilation failure
        let md_escape_dot = "![secret](../secret.png)";
        let pdf_escape_dot = compile_markdown_to_pdf(md_escape_dot, "Escape Dot Test", &temp_dir, &opts)
            .expect("Escaping path '../' must gracefully fall back to badge and compile to PDF");
        assert!(pdf_escape_dot.starts_with(b"%PDF-"));

        let md_escape_percent = "![secret](..%2Fsecret.png)";
        let pdf_escape_percent = compile_markdown_to_pdf(md_escape_percent, "Escape Percent Test", &temp_dir, &opts)
            .expect("Encoded escaping path '..%2F' must gracefully fall back to badge and compile to PDF");
        assert!(pdf_escape_percent.starts_with(b"%PDF-"));

        let md_nope = "![nope](nope.png)";
        let pdf_nope = compile_markdown_to_pdf(md_nope, "Nope Test", &temp_dir, &opts)
            .expect("Nonexistent path within doc_dir must fall back to broken image placeholder");
        assert!(pdf_nope.starts_with(b"%PDF-"));

        // 5. Verify format-aware fallback for missing .jpg, .svg, .webp, .gif, .jfif, .jpe, and .apng files
        for ext in &["jpg", "svg", "webp", "gif", "jfif", "jpe", "apng"] {
            let md = format!("![missing {ext}](missing.{ext})");
            let pdf = compile_markdown_to_pdf(&md, &format!("Missing {ext}"), &temp_dir, &opts)
                .unwrap_or_else(|e| panic!("Missing .{ext} must fall back without crashing: {e:?}"));
            assert!(pdf.starts_with(b"%PDF-"));
        }

        // 6. Verify unsupported image formats (bmp, tiff, avif, ico, heic) degrade to placeholder
        // badges at parse time rather than emitting #image(...) and fatally crashing Typst, even
        // when such files exist on disk.
        std::fs::write(temp_dir.join("real.bmp"), b"BM dummy bmp bytes").unwrap();
        std::fs::write(temp_dir.join("real.tiff"), b"II*\0 dummy tiff bytes").unwrap();

        for ext in &["bmp", "tiff", "avif", "ico", "heic", "unknown"] {
            let md = format!("![test {ext}](real.{ext})");
            let pdf = compile_markdown_to_pdf(&md, &format!("Test {ext}"), &temp_dir, &opts)
                .unwrap_or_else(|e| panic!("Unsupported .{ext} must degrade to placeholder badge without crashing: {e:?}"));
            assert!(pdf.starts_with(b"%PDF-"));
        }

        // 7. Verify absolute path and non-image paths fall back to placeholder badges without crashing
        let md_abs = "![abs](/Users/x/pic.png)";
        let pdf_abs = compile_markdown_to_pdf(md_abs, "Absolute Path", &temp_dir, &opts)
            .expect("Absolute path must fall back to placeholder badge and compile successfully");
        assert!(pdf_abs.starts_with(b"%PDF-"));

        let md_non_image = "![data](report.csv)\n\n![notes](notes.txt)";
        let pdf_non_image = compile_markdown_to_pdf(md_non_image, "Non-image Files", &temp_dir, &opts)
            .expect("Non-image files must fall back to placeholder badges and compile successfully");
        assert!(pdf_non_image.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_table_header_repeats_on_page_break() {
        let mut md = String::from("# Multi-page Table\n\n| Col A | Col B | Col C |\n|---|---|---|\n");
        for i in 1..=80 {
            md.push_str(&format!("| Val A{} | Val B{} | Val C{} |\n", i, i, i));
        }
        let temp_dir = std::env::temp_dir().join(format!("sgv_table_test_{}", std::process::id()));
        let _guard = TempDirGuard(temp_dir.clone());
        std::fs::create_dir_all(&temp_dir).unwrap();
        let opts = RenderOptions::default();
        let res = compile_markdown_to_pdf_result(&md, "Table Test", &temp_dir, &opts)
            .expect("Multi-page table should compile successfully");
        assert!(res.pdf_bytes.starts_with(b"%PDF-"));

        // Verify that Typst source contains table.header
        let parsed = crate::parser::markdown::convert_markdown_to_typst(&md, "Table Test", &opts);
        assert!(parsed.typst_source.contains("table.header("));
    }
}
