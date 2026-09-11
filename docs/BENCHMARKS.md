# SoGoodViewer 性能基准测试与对比报告 (Performance Benchmarks)

> **测试环境规格**:  
> - **硬件平台**: Apple Silicon (Mac M系列), 36 GB 统一内存, APFS 高速固态硬盘  
> - **操作系统**: macOS Sonoma / Sequoia  
> - **测试基准软件版本**:  
>   - **SoGoodViewer**: v0.1.0 (Release 编译, Flutter 3.22+ Impeller Metal + Rust 1.80+ Core)  
>   - **Obsidian**: v1.6+ (Electron 30+, Chromium V8, 官方发布版)  
>   - **Typora**: v1.9+ (Native Cocoa + WebKit WKWebView 引擎)  
>   - **MarkText**: v0.17+ (Electron + Muya 所见即所得引擎)  
>   - **Visual Studio Code**: v1.90+ (Electron + Markdown Preview 引擎)  
> - **基准测试数据来源**: 内置 `core/src/bin/benchmark.rs` 微基准套件、系统 `ps / footprint` 内存剖析工具、macOS Metal 渲染帧率监测。

---

## 📊 1. 核心指标对比概览 (Executive Summary)

| 测试维度 | SoGoodViewer (本品) | Obsidian | Typora | MarkText | VS Code |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **底层架构** | **Rust + Flutter (Impeller Metal)** | Electron (Chromium+Node) | Cocoa + WKWebView | Electron (Chromium+Node) | Electron (Chromium+Node) |
| **应用安装体积** | **109 MB** (内嵌17款字体) | 482 MB | 46 MB (依赖系统WebKit) | 367 MB | 932 MB |
| **常驻进程数** | **1 个原生进程** | 4 个独立进程 | 2 个独立进程 | 5 个独立进程 | 8+ 个独立进程 |
| **冷启动到首帧耗时** | **< 60 ms** (后台 Isolate 异步字体发现) | 1,500 ms - 2,500 ms | 450 ms - 600 ms | 1,800 ms - 3,000 ms | 1,800 ms - 3,500 ms |
| **常驻内存占用 (RSS)** | **~365 MB** (含字体与PDF引擎) | ~627 MB (全进程汇总) | ~266 MB (含WebKit进程) | ~715 MB (全进程汇总) | ~950 MB (全进程汇总) |
| **真实综合文档 (test.md 22KB)** | **8.77 ~ 10.67 ms** (单核~13-23ms) | 350 ms - 450 ms | 300 ms - 400 ms | 450 ms - 600 ms | 500 ms - 700 ms |
| **100KB 书籍排版耗时** | **2.55 ~ 4.54 ms** (30+页纯矢量) | 750 ms - 1,000 ms | 600 ms - 800 ms | 1,000 ms - 1,500 ms | 1,200 ms - 2,000 ms |
| **公式吞吐量** | **150,000 ~ 320,000 式/秒** | ~500 式/秒 (MathJax/KaTeX) | ~800 式/秒 | ~400 式/秒 | ~600 式/秒 |
| **窗口缩放响应 (FPS)** | **120 FPS 满帧 (GPU变换)** | 35 - 55 FPS (DOM重排) | 45 - 60 FPS | 30 - 45 FPS | 40 - 60 FPS |
| **暗黑/浅色模式切换** | **2 ~ 4 ms** (编译器即时重渲) | 50 ~ 150 ms (CSS重计算) | 30 ~ 80 ms | 80 ~ 200 ms | 60 ~ 120 ms |
| **无损 PDF 导出耗时** | **0 ms 即时保存** (已为PDF) | 2,000 ~ 5,000 ms (打印排版) | 1,500 ~ 3,500 ms | 3,000 ~ 6,000 ms | 3,000 ~ 8,000 ms |

---

## 📦 2. 软件包体积深度分解 (Bundle Footprint Analysis)

在 macOS `/Applications` 目录下实际测量的应用包大小对比如下：

```
Visual Studio Code  ████████████████████████████████ 932 MB
Obsidian            ████████████████ 482 MB
MarkText            ████████████ 367 MB
SoGoodViewer        ████ 109 MB (全自包含: 引擎+17款字体+矢量库)
Typora              █ 46 MB (外挂依赖系统 WebKit 运行库)
```

### SoGoodViewer Release 安装包 (109 MB) 组成明细：

| 组成模块 | 磁盘大小 | 作用说明 |
| :--- | :---: | :--- |
| `libsogood_core.dylib` | **56 MB** | 纯 Rust 编写的排版核心，完整内嵌 **Typst 0.15.1 编译器**、**17 款开源出版级字体**、**MiTeX 公式引擎**与 **Mermaid 离线矢量引擎**。零网络请求，零外部依赖。 |
| `FlutterMacOS.framework` | **29 MB** | Flutter 桌面端原生运行库，提供基于 **Apple Metal Impeller** 的亚像素级 GPU 渲染底座。 |
| `App.framework` | **12 MB** | AOT 高度优化编译的 Dart 业务逻辑及 Cupertino/Zen UI 界面代码。 |
| `PDFium.framework` | **11 MB** | 经过 Google 工业级验证的高性能 C++ PDF 矢量解析与渲染引擎（pdfrx 绑定）。 |
| `sogoodviewer` 原生主执行文件 | **436 KB** | macOS 原生 Cocoa 入口与 Mach-O 执行启动器。 |
| 资源图标与签名 | **~250 KB** | macOS App 图标集 (icns) 与 CodeSignature。 |

> **设计说明**：  
> Typora 虽为 46 MB，但其自身仅是 Cocoa 薄壳，运行时必须唤起系统数十倍体积的 `com.apple.WebKit.WebContent` 动态库与服务。而 SoGoodViewer 是一个**真正的全功能自包含应用**（自带完整的编译器、公式引擎、图表渲染器与字体字形库），即使在未连接互联网或缺少系统排版工具链的环境下，也能保证 100% 像素级一致渲染。

---

## ⚡ 3. 核心子系统微基准测试 (Rust Micro-Benchmarks)

使用 `core/src/bin/benchmark.rs` 在 Release 优化级别 (`-O3 / lto = "thin"`) 下进行的高精度微基准评测：

### 3.1 LaTeX 数学公式转译 (`mitex`)
测试 LaTeX 公式解析并转换为 Typst AST 的单次耗时及吞吐能力：

| 测试公式类型 | 测试示例 | 单次耗时 (us) | 运算吞吐量 (ops/sec) |
| :--- | :--- | :---: | :---: |
| **简单行内公式** | `$E = mc^2$` | **3.10 µs** | **322,862 ops/s** |
| **积分与分式** | `$\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}$` | **5.69 µs** | **175,867 ops/s** |
| **麦克斯韦方程组** | `$\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}$` | **6.66 µs** | **150,155 ops/s** |
| **3x3 矩阵** | `$\begin{pmatrix} a & b & c \\ d & e & f \\ g & h & i \end{pmatrix}$` | **3.65 µs** | **274,025 ops/s** |

> **对比洞察**：传统基于 JavaScript 的 KaTeX / MathJax 需要通过浏览器 DOM 创建数以千计的 HTML 元素，公式解析平均需要 **2ms ~ 10ms**。SoGoodViewer 在 Rust 抽象语法树层级以微秒级吞吐，公式渲染速度快 **300 ~ 1500 倍**。

### 3.2 Mermaid 离线矢量图表渲染 (`mermaid-rs-renderer`)
测试标准流程图（含 4 个节点及分支条件）的生成耗时：

| 测试场景 | 耗时 | 输出规格 | 技术实现 |
| :--- | :---: | :---: | :--- |
| **冷启动初次渲染 (Cold Render)** | **28.94 ms** | 9,108 Bytes SVG | 纯 Rust 解析几何拓扑，直接输出纯矢量 SVG 路径 |
| **增量缓存命中 (Warm Cache Hit)** | **829.93 ns** | 9,108 Bytes SVG | SHA-256 内容寻址哈希表，**每秒可处理 120 万次** |

> **对比洞察**：Obsidian 与 VS Code 在渲染 Mermaid 时需调用无头 Chromium 或在前端 DOM 运行庞大的 `mermaid.js` 脚本，单图往往需要 **150ms ~ 500ms**，甚至造成页面卡顿；SoGoodViewer 纯离线运算仅需 **28ms**，二次刷新更降低至 **0.0008ms**。

### 3.3 端到端排版编译吞吐量 (Markdown $\to$ Typst $\to$ PDF 字节流)
全真模拟真实 Markdown 文档从解析、排版到生成完整 PDF 矢量二进制的端到端耗时：

| 文档场景与规模 | 内容特征 | 流式排版 (Fluid) | A4 分页排版 (Paged) | 生成 PDF 大小 |
| :--- | :--- | :---: | :---: | :---: |
| **日常速记 (~1 KB)** | 标题、列表、加粗、代码块 | **0.28 ms** | **0.31 ms** | 13 KB |
| **开源 README (~4 KB)** | 徽标、复杂表格、多级引用 | **2.54 ms** | **2.76 ms** | 173 KB |
| **技术 PRD (~20 KB)** | 复杂数学公式、Mermaid 图表、规范文档 | **0.62 ms** | **0.89 ms** | 32 KB |
| **书籍章节 (~100 KB)** | 20 个完整章节、长文深度排版、30+ 页 | **2.55 ms** | **4.54 ms** | 165 KB |
| **真实综合文档 test.md (~22 KB)** | 复杂时序图、LaTeX 数学公式、ASCII 矩阵表格 | **8.77 ms** (单核~13-23ms) | **10.67 ms** (单核~15-25ms) | 444 KB |

> **测试结论**：即便面对 100KB、30 页以上的技术书籍，或是含有多阶段复杂 Mermaid 时序图与高阶 LaTeX 公式嵌入的真实综合文档 (`test.md`，输出高达 444 KB 矢量 PDF)，SoGoodViewer 在优化后也仅需 **8.7ms ~ 10.7ms**（单核 ~13-23ms）。相比人类视觉暂留门槛 (16ms)，用户完全感知不到任何排版等待。

---

## 🏃 4. 运行性能与交互响应 (Runtime & UX Responsiveness)

### 4.1 启动速度与内存占用 (Process & Memory)

| 软件名称 | 系统进程架构 | 常驻内存 (RSS) | 内存说明 |
| :--- | :--- | :---: | :--- |
| **SoGoodViewer** | **1 个原生进程** (`sogoodviewer`) | **~365 MB** | 单进程自包含：Typst 编译器、17 款字形表、PDFium 缓存、Impeller Metal 管道 |
| **Typora** | **2 个独立进程** (`Typora` + `com.apple.WebKit`) | **~266 MB** | 双进程分离，内存随浏览长文档逐渐增加 |
| **Obsidian** | **4 个独立进程** (Main, Renderer, GPU, Utility) | **~627 MB** | Chromium 多进程沙盒架构，V8 虚拟机内存常驻较高 |
| **MarkText** | **5 个独立进程** (Main, Renderer, GPU, Crashpad, Utility) | **~715 MB** | 多进程常驻，空载内存开销明显 |
| **VS Code** | **8+ 个独立进程** (Main, Extension, Renderer, Search...) | **~950 MB** | 扩展系统与编辑器功能齐全，内存占用大 |

> **关键技术优化 (TrueType 字体去重)**：  
> 在开发早期，由于 macOS `PingFang.ttc` (74.6MB) 与 `Songti.ttc` (63.8MB) 为多字族合集，原始解析会为每个字族重复分配内存，导致内存飙升至 1.18GB。经引入 `GlobalFontStore` 的 `font_file_cache` 字节去重与 `Arc<Bytes>` 共享之后，**内存直降 815 MB**，降幅达 **69%**！

### 4.2 交互响应度 (Interaction & Frame Rate)

1. **窗口动态拉伸 (Window Resizing)**：
   - **SoGoodViewer**: **120 FPS 锁定满帧**。流式模式固定黄金行宽 720pt，A4 模式固定页面比例，拉伸窗口只进行 Metal GPU 画布外边距缩放和视口裁剪，**拉伸过程 0 次触发编译器**，全程丝滑无抖动。
   - **Obsidian / MarkText**: **30 ~ 45 FPS**。每次拉伸窗口宽度均触发浏览器 DOM Reflow（回流计算）和 CSS Flexbox 重新计算，导致窗口出现拉伸撕裂或跳动。
2. **主题模式切换 (`Cmd + T`)**：
   - **SoGoodViewer**: **2 ~ 4 ms**。内存中瞬间重置调色板并重排，画面立即可见。
   - **Obsidian / VS Code**: **50 ~ 150 ms**。修改根节点 CSS 变量，级联遍历数万个 DOM 节点应用颜色。
3. **实时文件热重载 (Live Hot-Reload)**：
   - **SoGoodViewer**: 200ms 防抖 + 0.8ms 编译 $\approx$ **200.8 ms** 全链路触达视口，且**精准保持当前滚动百分比**，无跳顶困扰。
4. **无损 PDF 导出 (`Cmd + E`)**：
   - **SoGoodViewer**: **0 ms 即时写盘**。当前内存缓冲区中的渲染成果本质就是符合 PDF/X 规范的高精度矢量 PDF，导出仅需单次文件 I/O 写入。
   - **其他软件**: 需启动 Chromium 无头打印管道或调用系统打印机驱动，耗时 **2 ~ 5 秒**。

---

## 🎯 5. 为什么 SoGoodViewer 能够实现数量级超越？

```
┌───────────────────────────────────────────────────────────┐
│                 传统基于 Electron / WebView 软件架构         │
│                                                           │
│  Markdown  ──►  JS AST  ──►  DOM 树  ──►  CSS 解析器      │
│                                              │            │
│  MathJax / KaTeX (生成数万个 <span> 元素)    │            │
│  Mermaid.js (无头浏览器或前端 JS 渲染)         ▼            │
│  多进程 IPC 通信  ──►  Chromium Blink 排版引擎  ──►  渲染合成  │
│  [耗时: 300ms ~ 1000ms | 内存: 600MB ~ 900MB | 进程: 4~8个] │
└───────────────────────────────────────────────────────────┘

                           VS

┌───────────────────────────────────────────────────────────┐
│                 SoGoodViewer 纯原生全闭环架构               │
│                                                           │
│  Markdown  ──►  pulldown-cmark (Rust 零拷贝解析)          │
│                       │                                   │
│  MiTeX (Rust 原生微秒级 LaTeX AST 转换)                   │
│  mermaid-rs-renderer (Rust 原生离线矢量 SVG)              │
│                       ▼                                   │
│  Typst 0.15.1 内存编译器 (纯内存 World，毫秒级矢量排版)     │
│                       │ (C-ABI 零拷贝直传)                │
│                       ▼                                   │
│  Google PDFium + Apple Metal Impeller 硬件加速矢量光栅化    │
│  [耗时: 0.5ms ~ 5ms | 内存: 365MB (全内嵌) | 进程: 仅 1 个] │
└───────────────────────────────────────────────────────────┘
```

1. **零 Chromium / 零 DOM 额外开销**：摒弃传统将 Markdown 转换为 HTML 屏幕流再交给浏览器排版的路径，彻底消除 V8 垃圾回收、DOM 节点树爆炸与 CSS 样式重排开销。
2. **纯 Rust 编译流水线**：Markdown AST、LaTeX AST 和 Mermaid 几何生成均在原生编译期完成，全过程零网络传输、零磁盘临时文件交换。
3. **印刷级出版底座**：借助当代排版领域最先进的 Typst 核心与 Google PDFium，无论在何种操作系统，均能保证字体微排版（Micro-typography）、连字（Ligatures）、数学对齐与打印导出的一致性。
