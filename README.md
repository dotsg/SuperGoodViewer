<div align="center">
  <img src="docs/images/app_logo.png" width="128" height="128" alt="超好读 Logo" />
  <h1>超好读 (SuperGoodViewer) 🚀</h1>
  <p><strong>只读 Markdown 矢量排版桌面阅读器</strong></p>
  <p><em>Publication-Grade Typography, Pixel-Perfect Consistency, Zero-WebView Desktop Reader.</em></p>
</div>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release: v1.0.9](https://img.shields.io/badge/Release-v1.0.9-blue.svg)](https://github.com/dotsg/supergoodviewer/releases/latest)
[![CI Status](https://img.shields.io/badge/CI-Passing-brightgreen.svg)]()
[![Platform: macOS | Windows | Linux](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)]()

**超好读 (SuperGoodViewer)** 是一款专为排版强迫症与极致阅读体验打造的跨平台桌面 Markdown 阅读器。系统彻底舍弃传统 WebView 屏幕流动排版方案，采用 **“Markdown $\to$ 嵌入式 Rust Typst 内存编译 $\to$ 本地 Google PDFium 矢量渲染”** 的全原生架构，带来真正的跨平台像素级一致性；由于渲染结果本身就是矢量 PDF，导出无损 PDF 只是一次文件写入，无需重新排版。

---

## ✨ 核心特性

- 🎯 **专注只读，极致性能**：剥离富文本编辑器的一切冗余复杂度，纯 Rust 内存流水线。22KB 综合文档首次打开 **94ms**、100KB 书籍 **292ms**；切主题、改字号等重新渲染仅 **0.5 ~ 20ms**；温启动 **~98ms** 出 UI 首帧、**~141ms** 文档上屏。
- 📐 **出版级数学公式**：集成 `mitex` LaTeX $\to$ Typst 原生公式转换引擎，公式转译吞吐量 **135,000 ~ 270,000 式/秒**，全面支持复杂微积分、矩阵与多行对齐方程。
- 📊 **离线纯矢量 Mermaid 渲染**：基于纯 Rust 实现的 `mermaid-rs-renderer`，直接生成矢量路径，无 Chromium / Node.js 外部开销；单张流程图冷渲染约 **23ms**，并带 SHA-256 内容缓存，同一张图重复出现时不再渲染（查表约 0.8µs）。
- 🖥 **多元版式与母版系统 (Multi-Layout System)**：
  - **自适应流式 (Fluid Screen)**：锁定 720pt 黄金阅读行宽，无缝连续长卷轴阅读，窗口拉伸**不触发任何重新编译**，只做 GPU 画布缩放与视口裁剪；
  - **A4 纵向出版 (A4 Portrait)**：标准 A4 页面排版、动态页眉页脚与防孤行分页控制，实现 100% “打印即所见”，支持单页纵向与双页对开；
  - **A4 横向出版 (A4 Landscape)**：横向表格、宽屏报告排版；
  - **16:9 与 4:3 幻灯片 (Slides)**：专为演讲汇报优化的幻灯片版式，正文字号自动缩放，投影大屏纤毫毕现。
- 📽 **全屏单页演示模式 (Presentation Mode / PPT)**：
  - 支持快捷键 `F5` / `Cmd + Enter` / `Cmd + Shift + P` 一键进入无边框纯净放映；
  - **Marp 语法兼容**：支持 YAML Frontmatter (`marp: true`, `size: 16:9`, `paginate`, `header`, `footer`) 与 `---` 水平线幻灯片分页符；
  - **双向兼容原生 PDF**：既可放映 Markdown 编译的幻灯片，也可直接全屏演示外部打开的原生 PDF 文档；
  - **演讲者利器**：激光笔视角的自动隐藏 Presenter HUD 与鼠标光标（2.5秒闲置淡出）；背景底色与 HUD 自适应随明亮/暗黑模式无缝契合。
- 🔍 **原生全文查找与高亮导航 (`Cmd + F`)**：
  - 悬浮胶囊搜索栏，支持实时键入防抖搜索与匹配命中计数（如 `3 / 14`）；
  - 支持 `Enter` / `Cmd + G` 跳转下一个匹配项、`Shift + Enter` / `Cmd + Shift + G` 跳转上一个匹配项，支持循环回绕；
  - 硬件加速 Canvas 矢量高亮渲染（当前高亮橙色、其余高亮黄色），按 `Esc` 一键关闭并清除高亮。
- 📑 **可定制三槽位页眉与页脚 (Header & Footer System)**：
  - 支持左、中、右独立槽位内容配置；
  - 支持动态宏替换：`{title}`（文档标题）、`{page}`（当前页码）、`{total}`（总页数）、`{date}`（当前日期）；
  - 支持顶底分割线开关与首页（封面）页眉页脚智能隐藏。
- 🪟 **沉浸式 macOS 统一标题栏**：深度融合原生 32pt 交通灯按钮；阅读向下滚动时标题栏自动平滑隐退，向上轻滑或回顶即时唤出，最大化阅读可视高度。
- ⚙️ **macOS 风格排版与偏好设置 (`Cmd + ,`)**：
  - 左右分屏排版配置界面，配备**实时排版渲染预览卡片**，调整正文字号、行间距、对齐方式即时可见；
  - 自动检测并枚举系统可用字体（Monaco、霞鹜文楷、思源黑体/宋体、Maple Mono 等）；
  - 采用显式“保存并应用”机制，避免参数调节过程中的频繁重排抖动。
- ⌨️ **自定义键盘快捷键 (`Cmd + K`)**：支持随心定制所有阅读与视图快捷键，并提供一键恢复官方默认设置。
- ⚡ **命令行极速启动 (`sgv` CLI)**：支持终端通过 `sgv <file.md>` 打开文档或向已运行实例热发送文件（零终端配置，可在菜单栏或设置中一键安装）。
- 💾 **无感会话与窗口几何持久化**：原生持久化窗口尺寸与屏幕坐标；自动恢复上次打开文档；多文档独立记忆阅读滚动进度与缩放比例。
- 🚀 **编译磁盘高速缓存与垂直局部预渲染**：已编译文档磁盘快照秒级比对，二次打开直接复用快照、跳过整轮编译；垂直预渲染缓冲区消除大文件高速滑动白屏。
- 🎨 **编译期原生主题与一致性导出**：原生支持亮色 (Light) 与暗黑 (Dark) 主题，排版编译期注入色彩基准；导出 PDF 时智能统一为出版级高对比明亮矢量格式。
- 📦 **零外部依赖开箱即用**：自带 17 款开源出版级字体与全套渲染引擎，无需安装 Node.js、Typst CLI、Python 等环境，单文件独立应用双击即用。

---

## ⚡ 性能基准对比 (Benchmarks)

下表 SuperGoodViewer 一列为 2026-09-20 在 Apple M4 Max / macOS 27 上的实测中位数；
其他软件仅"应用体积"为同机实测，启动、排版、内存为沿用旧版文档的估计值（**本轮未复测**，仅供量级参考）。
完整方法论与分位数见 [docs/BENCHMARKS.md](docs/BENCHMARKS.md)。

| 测试维度 | SuperGoodViewer (本品) | Obsidian | Typora | MarkText | VS Code |
| --- | :---: | :---: | :---: | :---: | :---: |
| **底层引擎** | **Rust + Metal Impeller** | Electron (Chromium) | Cocoa + WKWebView | Electron (Chromium) | Electron (Chromium) |
| **应用体积** | **107 MB** (arm64) / **154 MB** (通用版) | 482 MB | 46 MB (依附系统WebKit) | 368 MB | 933 MB |
| **操作系统进程** | **1 个原生进程** | 4 个独立进程 | 2 个独立进程 | 5 个独立进程 | 8+ 个独立进程 |
| **常驻内存** | **200 MB** (峰值约 630 MB) | ~627 MB | ~266 MB | ~715 MB | ~950 MB |
| **温启动 UI 首帧 / 文档上屏** | **98 ms / 141 ms** | 1,500 ~ 2,500 ms | 450 ~ 600 ms | 1,800 ~ 3,000 ms | 1,800 ~ 3,500 ms |
| **22KB 综合文档首次排版** | **93.7 ms**（重渲染 9.0 ms） | 350 ~ 450 ms | 300 ~ 400 ms | 450 ~ 600 ms | 500 ~ 700 ms |
| **100KB 书籍首次排版** | **291.9 ms**（重渲染 19.6 ms） | 750 ~ 1,000 ms | 600 ~ 800 ms | 1,000 ~ 1,500 ms | 1,200 ~ 2,000 ms |
| **20KB PRD（6 张 Mermaid）首次排版** | **182 ms**（重渲染 4.4 ms） | 350 ~ 450 ms | 300 ~ 400 ms | 450 ~ 600 ms | 500 ~ 700 ms |
| **无损 PDF 导出** | **单次文件写入**（渲染结果本身即 PDF） | 2,000 ~ 5,000 ms | 1,500 ~ 3,500 ms | 3,000 ~ 6,000 ms | 3,000 ~ 8,000 ms |

👉 **完整基准数据、测试方法论、冷/热口径区分与内存归因详见：[docs/BENCHMARKS.md](docs/BENCHMARKS.md)**；原始数据见 [docs/benchmark-results.json](docs/benchmark-results.json)。

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
- **Flutter SDK**: 3.22+ (支持 Desktop 平台)
- **C++ 编译器**:
  - macOS: Xcode Command Line Tools
  - Windows: Visual Studio 2022 C++ 生成工具（若需编译原生 ARM64，需额外勾选 *MSVC v143 ARM64/ARM64EC* 工具集与 `rustup target add aarch64-pc-windows-msvc`）

### 2. 运行自动化测试套件
```bash
make test
```
将自动执行 Rust 核心单元与集成测试 (`cargo test`)、Flutter 静态分析 (`flutter analyze`) 及 Flutter 单元测试 (`flutter test`)。

### 3. 本地调试运行
- **macOS**:
  ```bash
  make run-macos
  ```
- **Windows**:
  ```bash
  make run-windows
  ```

### 4. 编译发布与打包
- **macOS (App Bundle & DMG)**:
  ```bash
  make build          # 生成 ui/build/macos/Build/Products/Release/SuperGoodViewer.app
  make dmg            # 生成独立架构安装镜像 dist/SuperGoodViewer-macos-arm64.dmg 与 dist/SuperGoodViewer-macos-x64.dmg
  # 亦可单独构建指定架构镜像：
  make dmg-arm64      # 生成 dist/SuperGoodViewer-macos-arm64.dmg (Apple Silicon M 系列)
  make dmg-x64        # 生成 dist/SuperGoodViewer-macos-x64.dmg (Intel 处理器)
  make dmg-universal  # 生成 Universal 通用安装镜像 dist/SuperGoodViewer-macos.dmg
  ```
- **Windows x64 便携包 (Intel / AMD 架构及通用)**:
  ```bash
  make package-windows       # 生成 dist/SuperGoodViewer-windows-x64.zip
  ```
- **Windows ARM64 原生便携包 (高通骁龙 X Elite / Surface 等 WoA 设备)**:
  ```bash
  make package-windows-arm64 # 生成 dist/SuperGoodViewer-windows-arm64.zip
  ```

---

## 🛠 命令行集成工具 (`sgv` CLI)

SuperGoodViewer 提供跨平台的终端命令行启动工具 `sgv`，支持直接在终端中毫秒级预览 Markdown 文档。

### 1. 一键安装
- **图形化安装**：打开应用 $\to$ 偏好设置 (`Cmd/Ctrl + ,`) $\to$ **命令行工具** $\to$ 点击 **「一键安装 sgv 工具」**。
  - macOS：自动创建符号链接至 `/usr/local/bin/sgv`（免手动终端配置，支持授权弹窗）。
  - Windows：自动安装至用户环境变量目录 `%LOCALAPPDATA%\Microsoft\WindowsApps\sgv.cmd` 与 `sgv.ps1`（免管理员 UAC 提权，CMD / PowerShell / Windows Terminal 即装即用）。

### 2. 常用终端用法
```bash
# 打开单个文档（支持绝对路径与相对路径）
sgv README.md

# 一次性打开多个 Markdown 文档
sgv chapter1.md chapter2.md

# 唤醒或置顶当前已在运行的 SuperGoodViewer 窗口
sgv

# 查看帮助信息
sgv -h
```

### 3. 无头静默导出 PDF (`sgv export`)
支持 AI 编码工具（如 Claude Code, Cursor, 脚本）或终端用户直接将 Markdown 批量导出为出版级 PDF，完全后台静默执行、不弹出任何窗口、支持 stdin 管道：

```bash
# 导出单个文档为 PDF（默认输出 README.pdf）
sgv export README.md

# 指定输出文件路径与页面版式（支持 a4, a4-landscape, fluid, slide）
sgv export report.md -o output.pdf --format a4

# 导出为 16:9 演示幻灯片 PDF
sgv export deck.md -o slides.pdf --format slide

# 批量导出整个目录（保留子目录层级）
sgv export ./docs -o ./dist

# 从标准输入 (stdin) 管道读取并导出
cat draft.md | sgv export - -o draft.pdf
```

---

## ⌨️ 常用快捷键指南

| macOS 快捷键 | Windows / Linux 快捷键 | 功能描述 |
| :--- | :--- | :--- |
| `Cmd + O` | `Ctrl + O` | 打开本地 Markdown 或 PDF 文件 |
| `Cmd + R` | `Ctrl + R` | 立即重新编译与排版当前文档 |
| `Cmd + M` | `Ctrl + M` | **切换版式**（流式 / A4纵向 / A4横向 / 16:9 / 4:3） |
| **`F5`** / `Cmd + Shift + P` / `Cmd + Enter` | **`F5`** / `Ctrl + Shift + P` / `Ctrl + Enter` | **全屏单页演示模式 (PPT)** 进入与退出 |
| `Cmd + F` | `Ctrl + F` | **查找文档内容**（唤起悬浮搜索栏） |
| `Cmd + G` / `Enter` | `F3` / `Enter` | 跳转到下一个搜索匹配项 |
| `Cmd + Shift + G` / `Shift + Enter` | `Shift + F3` / `Shift + Enter` | 跳转到上一个搜索匹配项 |
| `Cmd + P` | `Ctrl + P` | **导出出版级无损明亮 PDF（无需重新排版，仅一次文件写入）** |
| `Cmd + D` | `Ctrl + D` | 切换单页纵向 / 双页对开书籍阅读 |
| `Cmd + T` | `Ctrl + T` | 切换浅色 (Light) / 暗黑 (Dark) 主题 |
| `Cmd + B` | `Ctrl + B` | 展开 / 折叠左侧目录与管理侧边栏 |
| `Cmd + \` | `Ctrl + \` | 显示 / 隐藏底部浮动工具栏 (Zen 模式) |
| `Cmd + ,` | `Ctrl + ,` | 打开偏好设置面板（版式/页眉页脚/字体/CLI） |
| `Cmd + Ctrl + F` | `F11` | 进入 / 退出操作系统全屏模式 |
| `Cmd + +` / `-` | `Ctrl + +` / `-` | 放大 / 缩小阅读视口渲染比例 (100% ~ 300%) |
| `Cmd + 0` | `Ctrl + 0` | 恢复 100% 原始视口缩放比例 |

### 📽 全屏演示模式专有控制键 (Presentation HUD)

| 控制键 | 动作效果 | 说明 |
| :--- | :--- | :--- |
| **`Space`** / **`→`** / **`PageDown`** / **`↓`** | 下一张幻灯片 | 顺畅演讲前进 |
| **`←`** / **`PageUp`** / **`↑`** | 上一张幻灯片 | 回顾前页内容 |
| **`Home`** / **`End`** | 首页 / 末页 | 快速直达开头与结尾 |
| **`Esc`** / **`F5`** | 退出演示模式 | 返回普通阅读排版视窗 |

---

## 📝 更新日志 (Changelog)

### v1.0.9 (2026-09)
- **macOS Apple Silicon 与 Intel 独立安装包切分与安全更新 (#11)**：
  - 将 macOS DMG 安装包切分为 `arm64`（Apple Silicon M 系列）与 `x64`（Intel 芯片）双独立发行版本，安装包体积由 76MB 大幅缩减至 38~42MB（缩减约 45%~50%）；
  - `UpdateService` 增加宿主真实硬件架构与 Rosetta 2 运行态探测（通过 `sysctl hw.optional.arm64`），原地自动更新提供架构精准匹配与替换前二进制架构安全校验，防止误装不兼容架构；
  - 增强 `scripts/package-macos-dmg.sh` 脚本，引入必需组件表驱动架构验证与临时目录清理保障；
  - `Makefile` 支持按宿主架构智能分流 `make dmg-arm64` / `make dmg-x64` / `make dmg` 构建依赖，加速本地开发打包体验。
- **长文档平滑滚动与极速渲染性能 (Viewer Smooth Scrolling & High Performance)**：
  - 超长页面结构化文本提取移至后台 Isolate（阈值 >= 8192 字符），主线程事件循环耗时由 39ms 降至 12ms，消除大文档滚动卡顿；
  - 引入 `TextFragmentIndex` 基于二分查找区间扫描，消除鼠标悬停与命中测试时的 $O(N)$ 冗余遍历；
  - 重构 `PageTextCache`，统一阅读态与全文检索的文本缓存，支持优先级调度队列、并发合并与 LRU 容量上限；
  - 纯平移滚动帧复用已有页面布局（`_pageLayoutDirty`），消除每帧重复的重排耗时；平移期间绕过 `InteractiveViewer` 矩阵规格化；
  - `RasterTileCache` 增加二级页面索引，每帧瓦片检索耗时由 $O(N)$ 降至 $O(K)$；
  - 使用单调时钟节流阅读器控制器状态持久化，避免 120Hz 高刷滚动频繁重置定时器。
- **Linux 跨桌面环境文件定位与异常加固 (#15)**：
  - 加固 Linux 环境下“在文件管理器中显示”链路，全面适配 XDG Desktop Portal (`org.freedesktop.portal.OpenURI.OpenDirectory`) 与 D-Bus `FileManager1.ShowItems`；
  - 优先使用 `gdbus` 携带超时与可靠退出码，回退至 `dbus-send`（添加 `--print-reply`、超时控制与 URI 逗号转义），最后兜底至 `xdg-open` 目录，解决沙盒与各类桌面文件定位难题；
  - 导出 PDF 增加平台层异常捕获与友好 SnackBar / 错误提示，防止平台通道偶发异常导致界面静默无响应。
- **Markdown 解析鲁棒性与排版保真度**：
  - **表格分页跨页表头重复**：Markdown 表格表头采用 Typst 原生 `table.header(...)` 包装，跨页长表格自动在每页顶部重复表头与底部分割线；
  - **图片路径 URL 编码与格式对齐**：支持本地图片路径字节级百分号编码（如 `%20` 空格、`%E4%B8%89` 中文路径）自动解码；严格对齐 Typst 0.15 图像格式规范（扩展支持 Windows JPEG `.jfif`、`.jpe` 与 `.apng`），非图片或不支持格式（.bmp, .tiff, .avif, .ico 等）优雅降级为占位徽标，杜绝引擎 panic 崩溃；缺失本地图片提供格式感知占位图；
  - **嵌套列表与大纲目录修复**：修复紧凑嵌套列表首项粘连与有序/无序列表标记嵌套换行；大纲目录自动清洗 Markdown 格式与转义反斜杠。
- **核心引擎内存治理与 CLI 极致轻量化**：
  - 引入 `evict_memo_cache()` 策略（保留 5 代），顶层编译完成后自动回收 Typst Comemo 缓存，杜绝长时间多文档阅读会话中的内存线性增长（15 次连续编译内存增长由 +40.5MB 压至 +0.2MB）；
  - `sgv-cli` 独立二进制改为动态链接 `sogood_core`，独立体积从 47MB 骤降至 481KB，消除通用分发包中 46MB 的重复 Typst 引擎与内嵌字体；
  - 引入 Fluid 切片布局 passes 计数探针与基准测试断言。

### v1.0.8 (2026-09)
- **无头命令行导出出版级 PDF (Headless CLI PDF Export)**：
  - 新增独立 `sgv-cli` 二进制与 `sgv export` 命令，支持无 GUI 快速导出 Markdown 为高品质无损 PDF；
  - 支持单文件转换、标准输入管道 (`cat doc.md | sgv export - -o out.pdf`) 与整目录批量导出（递归保持原目录层级与资产路径）；
  - 支持通过命令行参数指定主题（浅色/暗黑）、正文字号、纸张格式与输出路径；
  - 加固跨平台快捷启动脚本（macOS / Linux / Windows），提供一键安装、PATH 环境变量检测与卸载安全确认。
- **LaTeX 数学公式保真度与可视化降级 (LaTeX Math Fidelity & Visible Degradation)**：
  - 全面增强 MiTeX 与 Typst 兼容宏前言，新增支持 `\overbrace`、`\underbrace`、`\overbracket`、`\underbracket`、`\xleftrightarrow`、`\textcolor`、`\color`、`\colortext`、`\substack`、`\sout`、`\smallmatrix` 等大量常用 LaTeX 命令；
  - 移除 `mitex-len` 的动态 `eval()`，替换为严格数值解析器，支持按页面实际版心宽度计算 `\textwidth` 与 `\linewidth`；
  - **公式级可见降级**：编译或转译失败的公式不再静默丢弃，而是以醒目的红色虚线框与原始 LaTeX 源码清晰渲染；
  - 界面底部动态显示降级公式警告横幅，可直观查看受影响公式总数与具体源码清单；
  - C-API 降级统计指标支持线程局部存储（thread-local），确保多线程并发编译场景下指标统计互不串扰。
- **可拖拽侧边栏与布局自定义**：
  - 侧边栏支持鼠标边缘拖拽自由调整宽度，双击把手一键恢复默认 270px 宽度；
  - 支持侧边栏左侧/右侧一键快捷对调，状态与宽度跨会话自动记忆恢复。
- **macOS 架构感知更新与构建优化**：
  - 自动更新器支持 Apple Silicon (ARM64) 与 Intel (x64) 架构精准匹配，防止 Intel 机器误下 ARM64 更新包；
  - 新增独立 `scripts/package-macos-dmg.sh` 脚本并支持 `make dmg` / `dmg-arm64` / `dmg-x64` 打包；
  - 切换至多线程 ThinLTO 编译优化，大幅降低构建耗时。
- **长文档流式排版动态截断**：
  - 引入双 pass 动态页高计算与截断保护，替换 ZWSP 内联分隔符，保障极端超大文档排版稳定性。

### v1.0.7 (2026-09)
- **内置自动更新器与就地重启 (In-App Auto Updater)**：
  - 自动检查 GitHub Releases 最新版本，支持后台流式下载更新包与一键原地重启；
  - 完善的跨平台原子替换与回滚保护：macOS 备份失败时安全终止并不删除原应用，移动失败时自动回滚；跨版本更新保持用户偏好设置，Linux 重启二进制检测与并发防重入等。
- **A4 与分页模式排版增强 (Manual Page Breaks & CSS Directives)**：
  - 支持 HTML 分页标记（`<div style="page-break-after: always; break-after: page;"></div>`、`<pagebreak />`、`<!-- pagebreak -->` 与 `\newpage`）；
  - 流式排版智能忽略手动分页以保持连续平滑滚动体验；
  - 修复 Marp 幻灯片布局误判问题，确保普通文档不会被强制套用 16:9 比例，优先尊重用户选择的页面规格。
- **侧边栏与目录大纲定位优化 (Sidebar & Outline Navigation)**：
  - 修复 32px 顶部沉浸式标题栏偏移补偿，大纲章节跳转及初始载入精准对齐阅读区顶部；
  - 大纲高亮检测严格锚定阅读视区顶部，匹配跳转目标；
  - 流式视图下自动隐藏大纲页码（因流式文档连续无固定分页）；
  - 跨会话持久化记录侧边栏展开/折叠状态。
- **排版转译与空链接括号修复**：
  - 修复 Markdown 中空链接（如 `[text]()` 或无目标徽标）在 Typst Markup 模式下泄漏外层方括号的问题；
  - 引入渲染缓存版本机制（v1），自动失效并重新渲染旧版含括号的 PDF 缓存。
- **键盘导航优化**：
  - 修复双页铺展模式下特定情况键盘翻页事件拦截问题。

### v1.0.6 (2026-09)
- **Linux 平台原生桌面与 CLI 支持**：
  - 全面支持主流 Linux 64 位桌面环境（GTK 3），原生嵌入 Flutter 渲染引擎与 Rust 核心动态库；
  - 单实例控制与 Unix Domain Socket / IPC 通信：避免多开，支持命令行打开文件时将路径安全转发至已运行实例；
  - Linux 原生 CLI 启动脚本（`bin/sgv`），偏好设置中支持免提权一键安装与符号链接维护；
  - GitHub Actions 自动化构建与打包 Linux 便携归档包（`.tar.gz`）。
- **多语言国际化支持 (i18n)**：
  - 完整支持简体中文 (zh-CN)、繁体中文 (zh-TW) 与英文 (en) 三种语言，提供中立语言选择器并支持实时动态无缝切换；
  - 动态同步窗口标题与语言感知启动，偏好设置与系统交互全面国际化。
- **拖拽文件与目录交互 (Drag & Drop)**：
  - 支持直接拖拽 Markdown / PDF 文件或整个目录至窗口快速打开，异步安全 I/O 与热重载监控。
- **演播模式与多母版版式系统 (Presentation & Layouts)**：
  - 支持多版式演示模式（Marp 幻灯片语法解析、自定义页眉与页脚插槽，支持转义与清空保存）；
  - 全屏演示模式与视口状态双向同步，独立隔离演播排版状态与日常阅读排版设置。
- **高清分块切片渲染与导航优化**：
  - 引入高清分块切片渲染 (Tiled High-Resolution Rendering) 与狭长自适应栅格条带化，消除长文档内存尖峰与模糊；
  - 翻页与长文档导航优化：翻页时精准保留页内相对偏移与缩放比例，区分屏幕卷动与整页翻转，防空格加速与边界状态保护。
- **macOS Universal 双架构动态库**：
  - 自动化构建包含 Apple Silicon (arm64) 与 Intel (x86_64) 的通用架构动态库，消除混合架构兼容问题。

### v1.0.5 (2026-09)
- **原生 PDF 阅读器与大纲目录导航**：
  - 核心架构全面支持直接打开本地 `.pdf` 文件进行独立矢量渲染，无需经过 Markdown 编译包装；
  - 自动从 PDF 解析提取多级大纲目录（TOC / Outline），无缝展示在侧边栏并带有页码徽标（`P{n}`），支持点击平滑滚动跳转；
  - 智能切换工作模式：精准区分 Markdown 排版与 PDF 独立阅读，在 PDF 模式下自动隐藏无意义的排版参数（分页/流式、双页折叠、字体大小等）；
  - 支持 PDF 文件变动热重载监控（外部编辑即时刷新）与文件缺失统一占位展示；
  - 完善格式探测（严格基于 Magic Bytes 偏移识别，避免开头含 `%PDF` 字面量的 Markdown 文件被误判）与异常容错；
  - 修复双缓冲 slot 复用下大纲异步回调覆写下一文档、slot 脏状态竞态等系列稳定性问题。
- **CI/CD 流水线与发布自动化增强**：
  - 支持在 `main` 分支通过 GitHub Actions `workflow_dispatch` 手动输入版本号触发发版，由 Action 自动打 Tag 并发布 Release；
  - 建立 Rust / Flutter 编译依赖缓存全生命周期闭环（直接读写 `main` 分支全局缓存池），大幅缩减 Release 构建耗时；
  - 在 Windows Runner 上排除 Rust 编译输出目录的 Windows Defender 杀毒扫描，提升 30%~50% 编译效率；
  - 在构建任务起始阶段增加严格的版本格式校验，并与 `Cargo.toml` 和 `pubspec.yaml` 源码版本强绑定，0.1 秒内快速失败防错；
  - 解决 Windows ARM64 交叉编译中 JNI 插件与 x64 JVM 的链接冲突。

### v1.0.4 (2026-09)
- **Windows 全平台特性对齐与原生 ARM64 支持**：
  - 实现 Win32 平台原生交互：原生无边框全屏切换 (`F11`)、窗口标题栏拖拽、滚轮缩放与快捷键控制；
  - Win32 互斥锁 (Mutex) 单实例控制与 IPC 消息机制：通过 `WM_COPYDATA` 实现终端或外部热唤醒已运行窗口并即时打开新文档；
  - Windows 命令行工具 (`sgv` CLI)：新增 `sgv.cmd` 与 `sgv.ps1` 启动脚本，偏好设置中支持免提权一键安装/卸载，智能写入 `%LOCALAPPDATA%` 并动态安全维护用户注册表 PATH，控制台自动适配 UTF-8 (65001 代码页) 防乱码；
  - Windows ARM64 (WoA) 原生交叉编译支持：核心库与 UI 支持 `aarch64-pc-windows-msvc` 原生构建，新增打包命令与 CI 自动化发布便携包；
  - Windows 字体与界面适配：适配 Segoe UI 与微软雅黑回退链，去除 macOS 专属交通灯安全留白，修复 MSVC 编译编码避免窗口标题乱码。
- **远程/网络图片异步下载与渐进式渲染**：
  - 自动识别 Markdown 文档中的远程 HTTP/HTTPS 图片，后台非阻塞异步并发下载与工作池并发调度；
  - 本地磁盘 SHA-256 URL 散列缓存，引入支持 TTL 与容量上限的负缓存 (Negative Cache) 机制，区分瞬时网络异常与 404 等永久失败；
  - 严格的安全与格式校验：校验 Magic Bytes 真实文件类型、Content-Length、Content-Encoding (gzip) 解压，严格验证 SVG 结构，防范畸形文件与注入；
  - 渐进式排版渲染 (Progressive Re-render)：文档首开秒级即时呈现，远程图片下载就绪后防抖自动触发局部无感知平滑重排。
- **彩色 Emoji 表情与字体回退系统**：
  - 编译器内核集成各平台原生彩色表情字体扫描与回退（macOS Apple Color Emoji、Windows Segoe UI Emoji、Linux Noto Color Emoji），彻底消除表情符号在 Typst 编译时的缺失与方块乱码。
- **Markdown 本地文档相对路径跳转与超链接导航**：
  - 原生 PDF 画布视图全面拦截并解析相对路径 Markdown 超链接（如 `[Doc](docs/ARCHITECTURE.md)`），点击即在阅读器中无缝切换并打开目标文档；
  - 结合文档内锚点跳转，打通跨文档知识跳转网络；外部 HTTP/HTTPS 链接继续唤起系统默认浏览器。
- **HTML 标签转译与内联/块级排版增强**：
  - 支持解析常用 HTML 结构标签（如 `<div align="center">` 居中容器）并转换为 Typst 原生对齐容器；
  - 加固 `<img width="...">` / `<img height="...">` 尺寸解析，严格校验合法数值并规范化格式输出（支持 `5.px`、`.5`、科学计数法与正负号），自动拦截无效参数与潜在代码注入风险；
  - 修复标题元数据锚点周围出现的意外括号字符。
- **Typst 编译转义与稳定性加固 (#1)**：
  - 修复标题含 ASCII 双引号导致 Typst 报错 `expected comma` 的问题，完善 Typst 代码模式字符串字面量转义；
  - Markdown 标题备用 slug、跳转锚点、外部链接及兜底锚点标签全面增加转义保护；
  - 解决 LaTeX Math 在公式解析失败触发 fallback 时若包含引号引发 Typst `unknown variable` 的隐患；
  - 优化锚点去重逻辑，消除未命中备用锚点产生的冗余兜底元数据标签。

### v1.0.3 (2026-09)
- **流式阅读体验与排版升级**：
  - 全面消除中短文档与长文档流式模式底部的空白断层，统一采用 Typst `auto` 高度连续排版并结合双缓冲平滑过渡；
  - 底部增加 56pt 呼吸留白边距，杜绝最后一页文字贴合底边的局促感；
  - 优化自适应流式缩放策略，保持长文档排版高清晰度渲染。
- **预编译 PDF 缓存管理 (`Cmd + ,`)**：
  - 常规偏好设置面板新增磁盘缓存容量统计与一键清理功能，支持直达 Finder / Explorer 目录；
  - 缓存 I/O 全面非阻塞异步化，设置面板秒开无卡顿；
  - 缓存签名引入 20pt 视口量化栅格，避免窗口微小缩放产生缓存碎片，大幅提升冷热命中率。
- **窗口与会话恢复机制加固**：
  - 修复 macOS 启动时每次关闭重开窗口位置向下漂移一个标题栏的顽疾；
  - 完善 Direct Reload 超时守卫 (Watchdog) 与 Generation Gating，杜绝并发加载导致的滚动与缩放锁死；
  - 解耦排版选项变更标志与精确滚动偏移恢复，提升流式续读定位准确率。
- **跨平台与稳定性优化**：
  - 修复 Windows 上 `explorer.exe` 打开缓存目录返回状态码 1 被误判为失败的问题；
  - 全量自动化单元测试与 Widget 异步测试加固，消除竞态与 Flaky 测试。

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

### v1.0.1 (2026-09)
- **品牌视觉与全平台图标整合**：正式发布官方视觉 Logo 与应用图标，完成 macOS、Windows 原生高清图标与 DMG 拖拽安装适配。
- **发布自动化工作流优化**：精简 GitHub Actions Release 工作流，严格仅在推送新 Tag 时触发构建与多平台制品打包。

### v1.0.0 (2026-09)
- **首次正式发布**：
  - **Rust + Typst + PDFium 全原生架构**：彻底舍弃传统 WebView，纯 Rust 内存流水线，实现毫秒级极速排版与 0ms 即时导出出版级无损 PDF；
  - **出版级 LaTeX 数学公式与离线矢量 Mermaid**：集成 mitex 原生转译复杂微积分、矩阵与多行对齐方程；基于 `mermaid-rs-renderer` 纯 Rust 离线秒级生成矢量图表，内置 SHA-256 增量图表缓存；
  - **双排版视窗模型 (Dual-Layout)**：自适应流式视窗 (Fluid Screen, 720pt 黄金阅读行宽, 120 FPS 满帧 GPU 变换) 与 A4 出版打印视图 (Paged, 标准 A4 页面排版, 支持单页与双页对开)；
  - **出版级中西文字体库与等宽对齐**：内置 17 款开源出版级字体，搭载 Maple Mono 实现 CJK 1:2 中西文完美等宽对齐；
  - **阅读交互与基础功能**：目录大纲树侧边栏导航、文档内标题锚点跳转、缩放自适应、浅色/暗黑主题原生切换与零闪烁双缓冲实时热重载。

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 开源。

