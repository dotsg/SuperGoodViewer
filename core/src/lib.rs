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
            ..Default::default()
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
                ..Default::default()
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

    #[test]
    fn test_compile_sample_document_full_modes() {
        let sample_md = r#"
# SoGoodViewer 🚀
### 出版级排版 Markdown 桌面阅读器

欢迎体验 **SoGoodViewer**！本应用通过 **Typst 嵌入式编译 + PDFium 矢量渲染**，为您提供极致的阅读美感与跨平台 100% 像素级一致性。

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

## 🎯 核心工程特性对比

| 衡量维度 | SoGoodViewer (纯原生) | 传统 Electron / WebView 阅读器 |
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
│ 1. Token 資產治理與商業分銷         │ 2. 可插拔合規安全護欄               │
│  · 基於 Envoy AI Gateway 雲原生底座 │  · 基於 Go ext_proc 高性能自研中間件│
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
}

