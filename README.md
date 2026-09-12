# 超好读 (SuperGoodViewer) 🚀

> **只读 Markdown 矢量排版桌面阅读器**  
> *Publication-Grade Typography, Pixel-Perfect Consistency, Zero-WebView Desktop Reader.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI Status](https://img.shields.io/badge/CI-Passing-brightgreen.svg)]()
[![Platform: macOS | Windows | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

**超好读 (SuperGoodViewer)** 是一款专为排版强迫症与极致阅读体验打造的跨平台桌面 Markdown 阅读器。系统彻底舍弃传统 WebView 屏幕流动排版方案，采用 **“Markdown $\to$ 嵌入式 Rust Typst 内存编译 $\to$ 本地 Google PDFium 矢量渲染”** 的全原生架构，带来真正的跨平台像素级一致性与 0 毫秒即时导出无损 PDF 体验。

---

## ✨ 核心特性

- 🎯 **专注只读，极致性能**：剥离富文本编辑器的一切冗余复杂度，纯 Rust 内存流水线，文档排版仅需 **0.5ms ~ 5ms**（100KB 书籍仅 2.8ms），冷启动仅 **~200ms**。
- 📐 **出版级数学公式**：集成 `mitex` LaTeX $\to$ Typst 原生公式转换引擎，公式解析吞吐量高达 **150,000 ~ 320,000 式/秒**，全面支持复杂微积分、矩阵与多行对齐方程。
- 📊 **离线纯矢量 Mermaid 渲染**：基于纯 Rust 实现的 `mermaid-rs-renderer`，毫秒级直接生成矢量路径，无 Chromium / Node.js 外部开销，带 SHA-256 增量图表缓存（复用仅 830ns）。
- 🖥 **双排版视窗模型 (Dual-Layout)**：
  - **自适应流式视窗 (Fluid Screen)**：锁定 720pt 黄金阅读行宽，无缝连续长卷轴阅读，窗口拉伸 **120 FPS 锁定满帧**（0次触发编译器）；
  - **A4 出版打印视图 (Paged)**：标准 A4 页面排版、动态页眉页脚与防孤行分页控制，实现 100% “打印即所见”。
- 🎨 **编译期原生主题**：原生支持亮色 (Light) 与暗黑 (Dark) 主题，排版编译期直接注入色彩基准，**2 ~ 4ms** 即时切换，告别粗暴的像素反色。
- 🔄 **视口记忆与平滑重载**：外部编辑器修改保存文档时，系统自动保持当前滚动位置（Scroll Ratio Retention），杜绝跳回第一页。
- 📦 **零外部依赖开箱即用**：自带 17 款开源出版级字体与全套渲染引擎，无需安装 Node.js、Typst CLI、Python 等环境，单文件独立应用双击即用。

---

## ⚡ 性能基准对比 (Benchmarks)

SuperGoodViewer 在体积、启动耗时、排版速度与内存管理上对传统 Electron / WebView 类笔记软件实现了**数量级超越**：

| 测试维度                        |                     SuperGoodViewer (本品)                     |       Obsidian        |         Typora         |      MarkText       |       VS Code       |
| ------------------------------- | :------------------------------------------------------------: | :-------------------: | :--------------------: | :-----------------: | :-----------------: |
| **底层引擎**                    |                   **Rust + Metal Impeller**                    |  Electron (Chromium)  |   Cocoa + WKWebView    | Electron (Chromium) | Electron (Chromium) |
| **应用体积**                    |                    **94 MB** (自带17款字体)                    |        482 MB         | 46 MB (依附系统WebKit) |       367 MB        |       932 MB        |
| **操作系统进程**                |                        **1 个原生进程**                        |     4 个独立进程      |      2 个独立进程      |    5 个独立进程     |    8+ 个独立进程    |
| **启动与首帧**                  | **~80 ms (UI首帧) / ~210 ms (文档就绪)** · 冷启动 417 / 487 ms |   1,500 ~ 2,500 ms    |      450 ~ 600 ms      |  1,800 ~ 3,000 ms   |  1,800 ~ 3,500 ms   |
| **真实综合文档 (test.md 22KB)** |               **8.77 ~ 10.67 ms** (单核~13-23ms)               |     350 ~ 450 ms      |      300 ~ 400 ms      |    450 ~ 600 ms     |    500 ~ 700 ms     |
| **100KB 书籍排版**              |                **2.55 ~ 4.54 ms** (30+页纯矢量)                |    750 ~ 1,000 ms     |      600 ~ 800 ms      |  1,000 ~ 1,500 ms   |  1,200 ~ 2,000 ms   |
| **20KB PRD 排版**               |                       **0.62 ~ 0.89 ms**                       |     350 ~ 450 ms      |      300 ~ 400 ms      |    450 ~ 600 ms     |    500 ~ 700 ms     |
| **窗口拉伸帧率**                |                   **120 FPS 满帧 (GPU变换)**                   | 35 ~ 55 FPS (DOM重排) |      45 ~ 60 FPS       |     30 ~ 45 FPS     |     40 ~ 60 FPS     |
| **无损 PDF 导出**               |                  **0 ms 即时保存** (已为PDF)                   |   2,000 ~ 5,000 ms    |    1,500 ~ 3,500 ms    |  3,000 ~ 6,000 ms   |  3,000 ~ 8,000 ms   |

👉 **完整真实基准评测、测试方法论与内存优化分解详见：[docs/BENCHMARKS.md](docs/BENCHMARKS.md)**。

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

| 快捷键                 | 功能                         |
| ---------------------- | ---------------------------- |
| `Cmd + O` / `Ctrl + O` | 打开本地 Markdown 文件       |
| `Cmd + R` / `Ctrl + R` | 立即重新编译排版             |
| `Cmd + M` / `Ctrl + M` | 切换自适应流式 / A4 出版视图 |
| `Cmd + T` / `Ctrl + T` | 切换浅色 / 暗黑模式          |
| `Cmd + E` / `Ctrl + E` | 0 毫秒即时导出无损 PDF       |

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。
