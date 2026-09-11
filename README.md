# SoGoodViewer 🚀

> **只读 Markdown 矢量排版桌面阅读器**  
> *Publication-Grade Typography, Pixel-Perfect Consistency, Zero-WebView Desktop Reader.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI Status](https://img.shields.io/badge/CI-Passing-brightgreen.svg)]()
[![Platform: macOS | Windows | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

SoGoodViewer 是一款专为排版强迫症与极致阅读体验打造的跨平台桌面 Markdown 阅读器。系统彻底舍弃传统 WebView 屏幕流动排版方案，采用 **“Markdown $\to$ 嵌入式 Rust Typst 内存编译 $\to$ 本地 Google PDFium 矢量渲染”** 的全原生架构，带来真正的跨平台像素级一致性与 0 毫秒即时导出无损 PDF 体验。

---

## ✨ 核心特性

- 🎯 **专注只读，极致性能**：剥离富文本编辑器的一切冗余复杂度，纯内存增量编译，文档热刷新仅需 **10ms ~ 30ms**，内存常驻仅约 **45MB**。
- 📐 **出版级数学公式**：集成 `mitex` LaTeX $\to$ Typst 原生公式转换引擎，全面支持复杂微积分、矩阵与多行对齐方程。
- 📊 **离线纯矢量 Mermaid 渲染**：基于纯 Rust 实现的 `mermaid-rs-renderer`，毫秒级直接生成矢量路径，无 Chromium / Node.js 外部开销，带 SHA-256 增量图表缓存。
- 🖥 **双排版视窗模型 (Dual-Layout)**：
  - **自适应流式视窗 (Fluid Screen)**：宽度绑定窗口逻辑宽度，高度 `auto`，无缝连续长卷轴阅读；
  - **A4 出版打印视图 (Paged)**：标准 A4 页面排版、动态页眉页脚与防孤行分页控制，实现 100% “打印即所见”。
- 🎨 **编译期原生主题**：原生支持亮色 (Light) 与暗黑 (Dark) 主题，排版编译期直接注入色彩基准，告别粗暴的像素反色。
- 🔄 **视口记忆与平滑重载**：外部编辑器修改保存文档时，系统自动保持当前滚动位置（Scroll Ratio Retention），杜绝跳回第一页。
- 📦 **零外部依赖开箱即用**：无需安装 Node.js、Typst CLI、Python 等环境，独立应用双击即用。

---

## 🏗 系统架构

```
Markdown Document (.md)
        │
        ▼
[Rust Native Core] (sogood_core)
  ├── 1. pulldown-cmark + GFM 语法解析
  ├── 2. LaTeX 公式转译 (mitex)
  ├── 3. Mermaid 矢量化与 SHA-256 缓存 (mermaid-rs-renderer)
  ├── 4. 虚拟文件系统 (VFS) 本地图片相对路径挂载
  └── 5. Typst 纯内存编译器 (typst + typst-pdf)
        │
        ▼ 纯内存零拷贝传输 (Uint8List via C-ABI FFI)
[Flutter Desktop UI]
  └── Google PDFium (pdfrx) 硬件加速矢量渲染视窗
```

详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

---

## 🚀 快速上手与本地开发

### 1. 开发前置准备
- **Rust Toolchain**: `rustup` (1.80+)
- **Flutter SDK**: 3.22+ (支持 Desktop)

### 2. 运行自动化测试套件
```bash
make test
```
将自动执行 Rust 核心单元与集成测试 (`cargo test`)、Flutter 静态分析 (`flutter analyze`) 及 Flutter 单元测试 (`flutter test`)。

### 3. 本地调试运行 (macOS)
```bash
make run-macos
```

### 4. 编译发布打包 (macOS Release Bundle)
```bash
make build
```
编译生成的独立应用位于：
`ui/build/macos/Build/Products/Release/sogoodviewer.app`

---

## ⌨️ 快捷键指南

| 快捷键 | 功能 |
| :--- | :--- |
| `Cmd + O` / `Ctrl + O` | 打开本地 Markdown 文件 |
| `Cmd + R` / `Ctrl + R` | 立即重新编译排版 |
| `Cmd + M` / `Ctrl + M` | 切换自适应流式 / A4 出版视图 |
| `Cmd + T` / `Ctrl + T` | 切换浅色 / 暗黑模式 |
| `Cmd + E` / `Ctrl + E` | 0 毫秒即时导出无损 PDF |

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
