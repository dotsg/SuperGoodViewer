<div align="center">
  <img src="docs/images/app_logo.png" width="128" height="128" alt="超好读 Logo" />
  <h1>超好读 (SuperGoodViewer) 🚀</h1>
  <p><strong>只读 Markdown 矢量排版桌面阅读器</strong></p>
  <p><em>Publication-Grade Typography, Pixel-Perfect Consistency, Zero-WebView Desktop Reader.</em></p>
</div>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release: v1.0.2](https://img.shields.io/badge/Release-v1.0.2-blue.svg)](https://github.com/dotsg/sogoodviewer/releases/latest)
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
  - **A4 出版打印视图 (Paged)**：标准 A4 页面排版、动态页眉页脚与防孤行分页控制，实现 100% “打印即所见”，支持单页纵向与双页对开。
- 🪟 **沉浸式 macOS 统一标题栏**：深度融合原生 32pt 交通灯按钮；阅读向下滚动时标题栏自动平滑隐退，向上轻滑或回顶即时唤出，最大化阅读可视高度。
- ⚙️ **macOS 风格排版与偏好设置 (`Cmd + ,`)**：
  - 左右分屏排版配置界面，配备**实时排版渲染预览卡片**，调整正文字号、行间距、对齐方式即时可见；
  - 自动检测并枚举系统可用字体（Monaco、霞鹜文楷、思源黑体/宋体、Maple Mono 等）；
  - 采用显式“保存并应用”机制，避免参数调节过程中的频繁重排抖动。
- ⌨️ **自定义键盘快捷键 (`Cmd + K`)**：支持随心定制所有阅读与视图快捷键，并提供一键恢复官方默认设置。
- ⚡ **命令行极速启动 (`sgv` CLI)**：支持终端通过 `sgv <file.md>` 打开文档或向已运行实例热发送文件（零终端配置，可在菜单栏或设置中一键安装）。
- 💾 **无感会话与窗口几何持久化**：原生持久化窗口尺寸与屏幕坐标；自动恢复上次打开文档；多文档独立记忆阅读滚动进度与缩放比例。
- 🚀 **编译磁盘高速缓存与垂直局部预渲染**：已编译文档磁盘快照秒级比对，二次打开 **0ms** 瞬间排版就绪；垂直预渲染缓冲区消除大文件高速滑动白屏。
- 🎨 **编译期原生主题与一致性导出**：原生支持亮色 (Light) 与暗黑 (Dark) 主题，排版编译期注入色彩基准；导出 PDF 时智能统一为出版级高对比明亮矢量格式。
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

## 💻 命令行启动器 (`sgv` CLI)

SuperGoodViewer 提供专用的快速启动工具 `sgv`，方便开发者在终端即开即读：

### 安装与卸载方式（免终端指令）
- **方式一**：在 macOS 顶部应用菜单点击 **「SuperGoodViewer」 $\to$ 「安装命令行工具 sgv...」**；
- **方式二**：在应用内快捷键 `Cmd + ,` 打开 **偏好设置** $\to$ 选择 **「命令行工具」** 选项卡点击安装。
*(安装程序会自动在 `/usr/local/bin/sgv` 建立符号链接)*

### 终端使用示例
```bash
# 打开指定 Markdown 文档
sgv README.md

# 打开绝对路径文档
sgv /Users/username/Documents/research.md

# 查看版本与使用帮助
sgv --help
```
*如果应用已处于运行状态，`sgv` 会通过本地 IPC 瞬时唤起主窗口并将阅读文档切换到目标文件。*

---

## ⌨️ 快捷键指南

| 快捷键 | 功能 | 说明 |
| :--------------------------- | :--------------------------- | :--------------------------------- |
| `Cmd + O` / `Ctrl + O`       | 打开本地 Markdown 文件       | 调用系统原生文件拾取器             |
| `Cmd + R` / `Ctrl + R`       | 立即重新编译排版             | 热刷新并重排当前文件               |
| `Cmd + F` / `Cmd + M`        | 切换自适应流式 / A4 出版视图 | 720pt 黄金宽度卷轴 $\leftrightarrow$ A4 标准页 |
| `Cmd + T` / `Ctrl + T`       | 切换明亮 / 暗黑阅读主题      | 纯编译期注入高品质配色基准         |
| `Cmd + D` / `Ctrl + D`       | 切换单页纵向 / 双页对开      | A4 出版视图下生效                  |
| `Cmd + P` / `Cmd + E`        | 导出为出版级矢量 PDF         | 0 毫秒即时保存无损 PDF (明亮版面)  |
| `Cmd + B` / `Ctrl + B`       | 展开 / 收起侧边栏            | 快速查看大纲目录与历史文档         |
| `Cmd + ,` / `Ctrl + ,`       | 打开偏好设置                 | 分屏字体排版、CLI工具与全局选项    |
| `Cmd + K` / `Ctrl + K`       | 打开快捷键自定义面板         | 自定义按键映射，支持一键复位       |
| `Cmd + +` / `Cmd + =`        | 放大页面视口比例             | 逐级放大渲染视口                   |
| `Cmd + -`                    | 缩小页面视口比例             | 逐级缩小渲染视口                   |
| `Cmd + 0`                    | 重置页面缩放为 100%          | 快速复位原始比例                   |
| `Cmd + 9`                    | 自适应当前窗口宽度           | 铺满当前可视宽度                   |
| `Cmd + 1`                    | 自适应整页全貌               | 完整呈现整页版面                   |
| `Cmd + \`                    | 显示 / 隐藏底部浮动栏        | 极简 Zen 专注阅读模式              |

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

### 4. 编译发布打包 (macOS Release Bundle & DMG)
```bash
# 编译 Release Bundle
make build

# 一键制作 macOS DMG 安装镜像 (带 /Applications 快捷拖拽)
make dmg
```
编译生成的独立应用与安装镜像位于：
- `ui/build/macos/Build/Products/Release/SuperGoodViewer.app`
- `SuperGoodViewer-macos.dmg`

---

## 📝 更新日志 (Changelog)

### v1.0.2 (2026-09)
- **全新沉浸体验**：
  - macOS 统一标题栏深度融合原生交通灯按钮，向下滚动时自动平滑隐藏，最大化阅读有效空间；
  - 精炼纯粹的底部阅读浮动栏 (HUD) 与紧凑目录侧边栏，减少视觉遮挡。
- **全新排版与偏好设置 (`Cmd + ,`)**：
  - 左右分屏设置弹窗，搭载实时排版渲染预览卡片，字体字号行距调节立竿见影；
  - 动态探测系统已安装中英文字体（Monaco、霞鹜文楷、Maple Mono、思源黑体等）；
  - 显式“保存并应用”排版流程，避免调节过程重复排版抖动。
- **命令行工具 (`sgv` CLI)**：
  - 零终端操作，macOS 菜单栏与设置面板一键安全安装/卸载；
  - 终端 `sgv document.md` 极速调用，支持多开 IPC 瞬时热唤起已运行窗口。
- **自定义快捷键 (`Cmd + K`)**：
  - 集中管理并修改全部快捷键映射，随时一键恢复出厂默认。
- **会话与阅读记忆恢复**：
  - 窗口几何尺寸与屏幕位置原生记忆恢复 (`setFrameAutosaveName`)；
  - 自动记住上次打开文件；独立记忆每份文档的历史滚动比例与视口缩放，并与自动隐藏标题栏协同对齐。
- **极致性能与缓存优化**：
  - 编译 PDF 本地磁盘高速缓存与哈希对比，再次打开 **0ms** 瞬间就绪；
  - 垂直方向局部预渲染缓冲区 (Vertical Pre-rendering Buffer) 与迟滞缓存策略，消除极速滚动白屏；
  - 优化构建系统，彻底隔离基准测试目标与核心动态库。

### v1.0.1
- 正式发布官方视觉 Logo 与应用图标，全平台 macOS、Windows 高清图标与 DMG 拖拽安装适配。

### v1.0.0
- 首次发布：纯 Rust 内存编译 Typst、出版级 LaTeX 数学公式、离线矢量 Mermaid、双排版视窗及 0ms 无损 PDF 导出。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。

