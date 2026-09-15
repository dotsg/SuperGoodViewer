---
marp: true
size: 16:9
paginate: true
header: "SuperGoodViewer · Slide Presentation Mode"
footer: "Page {page} of {total} · 极致性能与排版体验"
---

# 🚀 SuperGoodViewer
## 极速、出版级排版的现代 Markdown & PDF 演示与阅读器

- **纯原生内核**：Rust + Typst + PDFium
- **0ms WebView 延迟**：告别 Electron / Webkit 内存吞噬
- **多版式支持**：自适应长卷轴、A4 纵向/横向、16:9 与 4:3 幻灯片
- **Marp 语法兼容**：以写 Markdown 的方式轻松做演示

---

# 📐 核心特性与设计理念

> “写作时专注内容，展示时震撼全场。”

- **全屏单页演示 (Presentation Mode)**：
  - 快捷键 `F5` / `Cmd+Enter` / `Cmd+Shift+P` 一键进入全屏放映
  - 激光笔视角的自动隐藏 Presenter HUD 与鼠标光标（背景随明暗主题自适应）
- **统一矢量渲染**：
  - 无论是 Markdown 幻灯片还是外部导入的 `.pdf`，均享受极致清晰的矢量渲染
  - 零边缘锯齿，投影大屏上纤毫毕现

---

# 🧮 科学公式与排版排版

原生数学公式渲染，支持行内公式如 $E = m c^2$ 与复杂块级公式：

$$
\mathcal{L} = -\frac{1}{4} F_{\mu\nu} F^{\mu\nu} + i \bar{\psi} \gamma^\mu D_\mu \psi + \text{h.c.} + \psi_i y_{ij} \psi_j \phi + \text{h.c.} + |D_\mu \phi|^2 - V(\phi)
$$

麦克斯韦电磁场方程组：

$$
\begin{cases}
\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} = 0 \\
\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} \\
\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{cases}
$$

---

# 💻 优雅的代码块展示

内置现代语法高亮，搭配等宽字体：

```rust
// 核心编译器调度逻辑
pub fn compile_markdown(source: &str, opts: &RenderOptions) -> Result<Vec<u8>, CompileError> {
    let frontmatter = extract_frontmatter(source);
    let typst_markup = transpile_to_typst(source, &frontmatter, opts)?;
    
    // 瞬时编译为出版级矢量 PDF
    let pdf_bytes = typst_compiler::compile_to_pdf(&typst_markup)?;
    Ok(pdf_bytes)
}
```

---

# 📊 灵活版式对比

| 版式名称 | 推荐场景 | 典型尺寸 / 比例 | 切换快捷键 |
| :--- | :--- | :--- | :--- |
| **自适应长卷轴** | 沉浸阅读、宽屏排版、网页风格 | 自适应视口宽，高度自延展 | `Cmd+M` |
| **A4 纵向出版** | 打印成册、书籍阅读、两页对开 | 210mm × 297mm (1:1.414) | `Cmd+M` / 下拉 |
| **A4 横向出版** | 横向表格、宽屏报告排版 | 297mm × 210mm (1.414:1) | `Cmd+M` / 下拉 |
| **16:9 幻灯片** | 现代宽屏投影、Marp PPT 演示 | 960pt × 540pt (16:9) | `Cmd+M` / 下拉 |
| **4:3 幻灯片** | 传统投影机、报告大屏展示 | 960pt × 720pt (4:3) | `Cmd+M` / 下拉 |

---

# 🎯 总结

- **Markdown 即 PPT**：用熟悉的标记语言完成高质感演讲
- **快捷键完全重构**：`Cmd+M` 切换版式，`Cmd+F` 预留全局检索，`F5` / `Cmd+Shift+P` 演示放映
- **可配置页眉页脚**：三槽位定制，宏变量动态替换
- **开箱即用**：零额外环境配置，全平台高效运行
