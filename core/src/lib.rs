pub mod c_api;
pub mod compiler;
pub mod parser;

use std::path::{Path, PathBuf};
use compiler::engine::{compile_typst_to_pdf_with_options, CompileError, RenderOptions};
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
    let cache_dir = options.image_cache_dir.as_ref().map(PathBuf::from);
    compile_typst_to_pdf_with_options(&parsed.typst_source, doc_dir, parsed.virtual_files, cache_dir)
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
            println!("Compiled rich test.md spec in {:?}, generated PDF bytes: {}", elapsed, pdf.len());
        }
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
}

