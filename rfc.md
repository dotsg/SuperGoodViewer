# 技术架构与本地开发规范：只读 Markdown 矢量排版桌面浏览器

本文档指导开发一套具备出版级排版精度、导出与预览零差异（WYSIWYG）的跨平台 Markdown 只读桌面阅读器。系统通过“解析转换 $\to$ Rust 嵌入式 Typst 编译器输出内存 PDF 流 $\to$ 本地 PDFium 矢量渲染”的纯本地原生架构，彻底规避 Webview 屏幕流布局在排版漂移、分页打印截断、高内存占用及跨平台字体渲染不一致的顽疾。

---

## 1. 核心设计原则与架构边界

### 1.1 核心原则
1. **只读专注，放弃编辑**：不提供富文本/源码编辑功能，所有算力与交互完全聚焦于“极速打开、丝滑翻阅、排版美感、零等待导出”。
2. **纯原生、零 WebView、零外部运行时依赖**：坚决不内嵌 Chromium/WebKit，不要求用户安装 Node.js、Typst CLI、Python 等外部环境。客户端作为独立二进制/App Bundle 发布，开箱即用。
3. **桌面专注**：仅面向 macOS、Windows、Linux 桌面端，不向移动端妥协排版复杂度与交互逻辑。
4. **像素级跨平台确定性**：依赖 Typst 出版级排版规则与 Google PDFium 矢量光栅化，保证在不同操作系统下展现完全一致的字偶距、数学公式与分页效果。

### 1.2 系统分层架构

系统分为 **Flutter Desktop UI 外壳** 与 **Rust Native 核心引擎** 两大边界，通过 `flutter_rust_bridge` (FRB) 进行毫秒级进程内 FFI 交互与内存零拷贝数据传递，彻底告别多进程 IPC 开销。

```
+──────────────────────────────────────────────────────────────────────────+
| UI 宿主层 (Flutter Desktop: macOS / Windows / Linux)                     |
|                                                                          |
| [侧边栏目录树 / TOC 大纲]      [顶部工具栏: 视图切换 / 导出]  [快捷搜索 Cmd+F] |
|                                                                          |
|                  [PDF 交互核心视窗: pdfrx (基于 Google PDFium)]           |
|                  - 纯内存 Uint8List 即时重绘                             |
|                  - 视口位置平滑记忆 (Scroll Retention)                    |
|                  - 原生划词选择 / 超链接拦截分流                           |
+────────────────────────────────────┬─────────────────────────────────────+
                                     │ FFI 通信 (flutter_rust_bridge)
                                     │ 请求: (文档源码, 工作目录, 排版配置)
                                     │ 返回: Vec<u8> (PDF 内存字节流)
                                     ▼
+──────────────────────────────────────────────────────────────────────────+
| 核心排版引擎 (Rust Native Core - 静态嵌入 / 动态库)                       |
|                                                                          |
| 1. Markdown 解析与语法转译 (pulldown-cmark)                              |
|    ├── LaTeX 公式转译 (texmath / mitex 映射为 Typst 原生公式)             |
|    ├── 相对资源定位 (挂载文档父目录，自动解析 ./images/xxx)               |
|    └── Mermaid 提取与矢量化 (mermaid-rs-renderer / Typst WASM 插件)      |
|                                                                          |
| 2. 增量渲染缓存层 (In-Memory SHA-256 Cache)                               |
|    └── 对已渲染 Mermaid 矢量图进行哈希缓存，避免重复计算                |
|                                                                          |
| 3. Typst 编译器内核 (typst + typst-pdf Crates)                            |
|    ├── 实现内存 Typst World (跨平台系统字体回退链 + 虚拟文件系统)         |
|    ├── 动态注入母版 (支持暗黑/浅色模式、连续流式 / A4 打印分页双模)       |
|    └── 纯内存编译生成 PDF 二进制流 (编译耗时 10ms ~ 50ms)                 |
+──────────────────────────────────────────────────────────────────────────+
```

---

## 2. 技术选型清单与考量

| 层次 | 技术选型 | 选用考量 |
| :--- | :--- | :--- |
| **UI 宿主外壳** | **Flutter Desktop (macOS / Windows / Linux)** | 自绘引擎保障侧边栏、大纲树与动画丝滑；成熟的桌面窗口与键盘快捷键生态；无 Electron/WebView 内存暴涨包袱。 |
| **PDF 预览引擎** | **`pdfrx` (基于 Google PDFium)** | 工业级 C++ 底层光栅化，亚像素抗锯齿；原生支持内存字节流即时加载、缩放重绘、文本选区、PDF 内部大纲目录。 |
| **排版内核** | **Typst (纯 Rust Crate: `typst`, `typst-pdf`)** | 原生 Rust 库直接静态链接，单进程内存编译，支持现代排版微观调整（Kerning, Justification）与公式渲染，免安装 CLI。 |
| **通信通道** | **`flutter_rust_bridge` (FRB)** | 高性能 Rust-Dart 代码生成与 FFI 绑定，支持大块二进制（PDF 字节流）零拷贝传输。 |
| **Markdown 转译** | **`pulldown-cmark` + `texmath`** | Rust 生态高性能流式 CommonMark/GFM 解析器；将标准 LaTeX 公式转译为 Typst 原生公式 AST。 |
| **Mermaid 渲染** | **`mermaid-rs-renderer` / Typst WASM 插件** | 纯 Rust/WASM 无头渲染，比 Node+Puppeteer 快 500 倍；免去 Chromium 依赖；语法异常时优雅降级为高亮代码块。 |

---

## 3. 排版引擎与母版设计规范

### 3.1 多元版式与母版系统（Multi-Layout Architecture）
阅读器不拘泥于固定的 A4 纸张，提供五大多元版式与全屏单页演示模式，支持通过快捷键 `Cmd/Ctrl + M` 顺畅轮换或通过下拉菜单直选：
1. **自适应流式长卷轴（Fluid Screen Mode - 默认）**：
   页面宽度自适应窗口逻辑宽度，高度 `auto`，消除分页缝隙，呈现原生应用般的无缝长卷轴滚动体验。
2. **A4 纵向出版（A4 Portrait）**：
   标准 210mm × 297mm (595.28pt × 841.89pt) 页面排版，支持三槽位页眉页脚、动态页码与防孤行分页控制，支持单页与双页对开。
3. **A4 横向出版（A4 Landscape）**：
   标准 297mm × 210mm (841.89pt × 595.28pt) 横向排版，适合宽表格、数据报表与宽屏阅读。
4. **16:9 幻灯片（Slide 16:9 - 960pt × 540pt）**：
   专为现代宽屏演示设计的 PPT 页面规格，正文字号基准缩放至 16pt，幻灯片内容垂直居中且紧凑呈现。
5. **4:3 幻灯片（Slide 4:3 - 960pt × 720pt）**：
   专为传统投影机与大屏汇报设计的页面规格。

### 3.2 Marp 演示语法兼容机制
当文档顶部包含 YAML Frontmatter 并声明 `marp: true` 时：
- 自动解析 `size`（`16:9` 或 `4:3`）并作为幻灯片尺寸的最高优先级基准；
- 自动提取 `header` 与 `footer` 指令注入母版网格；
- 将 Markdown 中的水平分割线 `---` 直接转译为 Typst `#pagebreak()` 换页符；
- 语法解析时自动剔除 Frontmatter 文本块，防止元数据泄露入正文流。

### 3.3 全屏单页演示模式 (Presentation Mode / PPT)
针对 Markdown 演讲汇报与原生 PDF 投影需求，架构提供全屏单页演示流水线：
- **入口快捷键**：`F5`、`Cmd + Enter` 或 `Cmd + Shift + P` 即时进入，`Esc` / `F5` 退出；
- **纯净单页投影**：使用 `PdfPageView` 绑定 `BoxFit.contain` 渲染当前页，消除多页溢出与纵向滚动缝隙；
- **智能 HUD 与激光笔光标**：在无鼠标操作 2.5 秒后平滑隐退底部控制条与鼠标指针；
- **主题自适应背景**：全屏演示画布底色与 Presenter HUD 随明亮/暗黑模式自适应切换（暗黑模式 `#141414`，亮色模式 `#EBEBEB`）。

### 3.4 三槽位自定义页眉与页脚系统 (Header & Footer Grid)
支持在偏好设置中自定义顶底页眉页脚：
- 采用 Typst 三列网格 `#grid(columns: (1fr, auto, 1fr))` 布局，分别实现左对齐、居中、右对齐；
- 支持宏变量动态置换：
  - `{title}`：文档标题或文件名；
  - `{page}`：当前物理页码；
  - `{total}`：文档总页数；
  - `{date}`：当前系统编译日期；
- 支持独立的顶底横向细分割线开闭控制与首页面（封面）页眉页脚抑制。

### 3.2 现代 Typst 模板骨架 (`template.typ`)
使用现代 Typst（v0.11+ / v0.12+ 的 `context` 表达式机制，彻底废弃过时的 `locate` API），并支持主题变量注入：

```typst
// template.typ - 现代动态排版骨架
#let setup-doc(
  title: "Document",
  mode: "fluid",           // "fluid" (自适应屏幕流) 或 "paged" (A4打印)
  theme: "light",          // "light" 或 "dark"
  viewport-width: 800pt,
  body
) = {
  // 配色定义
  let bg-color = if theme == "dark" { rgb("#1e1e1e") } else { rgb("#ffffff") }
  let text-color = if theme == "dark" { rgb("#d4d4d4") } else { rgb("#1a1a1a") }
  let header-color = if theme == "dark" { rgb("#808080") } else { rgb("#666666") }

  // 页面尺寸自适应
  let page-width = if mode == "fluid" { viewport-width } else { 595.28pt } // A4 宽
  let page-height = if mode == "fluid" { auto } else { 841.89pt }          // A4 高
  let page-margin = if mode == "fluid" { (x: 24pt, y: 24pt) } else { (x: 2cm, top: 2.5cm, bottom: 2.5cm) }

  set page(
    width: page-width,
    height: page-height,
    margin: page-margin,
    fill: bg-color,
    header: if mode == "paged" {
      context {
        let page-num = counter(page).get().first()
        if page-num > 1 {
          align(right, text(fill: header-color, size: 9pt)[#title])
        }
      }
    } else { none },
    footer: if mode == "paged" {
      context {
        let page-num = counter(page).get().first()
        align(center, text(fill: header-color, size: 9pt)[#page-num])
      }
    } else { none }
  )

  // 跨平台字体回退链
  set text(
    font: (
      "Inter",
      "PingFang SC",       // macOS 首选
      "Microsoft YaHei",   // Windows 首选
      "Noto Sans CJK SC",  // Linux 首选
      "STIX Two Text"
    ),
    size: 10.5pt,
    fill: text-color,
    spacing: 120%,
    lang: "zh"
  )

  // 标题与断行防孤行优化
  show heading: it => {
    set text(weight: "bold", fill: if theme == "dark" { rgb("#ffffff") } else { rgb("#000000") })
    block(below: 1em, above: 1.5em, it.body)
  }

  body
}
```

---

## 4. Markdown 语法转换与降级规范

### 4.1 节点映射与转译处理

| 源语法 (Markdown) | 转换机制 | 目标语法 (Typst) | 异常兜底策略 |
| :--- | :--- | :--- | :--- |
| **行内/块级 LaTeX 公式**<br>`$E=mc^2$`<br>`$$\int_0^1 x dx$$` | 通过 `texmath` crate 解析 TeX AST，转译为 Typst 数学标记。 | `$E = m c^2$`<br>`$ integral_0^1 x dif x $` | 若 TeX 语法不支持，降级包裹为代码块或原始文本输出，杜绝整篇编译中断。 |
| **Mermaid 图表**<br>```` ```mermaid ```` | 1. 优先调用 Rust 原生/WASM `mermaid-rs-renderer`<br>2. 结果生成 SVG 并以 SHA-256 存入内存缓存 | `#image.decode(svg_data, format: "svg")` | **优雅降级**：若语法解析失败，输出带高亮与 Mermaid 标识的代码框，保证排版不崩溃。 |
| **本地相对图片**<br>`![alt](./assets/demo.png)` | 挂载 Markdown 文件的 Parent 目录至 Typst 虚拟文件系统 (VFS)。 | `#image("assets/demo.png")` | 图片不存在时渲染灰色占位块 `[Image missing: assets/demo.png]`。 |
| **GFM 任务列表**<br>`- [x] 完成任务` | 转换为自定义符号块。 | `[- #sym.checkmark 完成任务]` | 映射为原生 Unicode 符号。 |
| **GFM 提示框 (Callouts)**<br>`> [!NOTE]` | 映射为带圆角与左侧装饰条的彩色容器块。 | `#block(stroke: (left: 3pt + blue), ...)` | 普通引用块回退。 |

---

## 5. 阅读器交互体验规范 (Reader UX)

作为面向日常高频阅读的工具，客户端必须具备以下桌面交互特质：

1. **视口无缝保持 (Scroll Retention)**：
   * 当文件监听器（Watcher）捕获到本地文档被外部编辑保存时，UI 必须记录当前 `pageNumber` 与页面滚动比率（`scrollOffset / maxScrollExtent`）；
   * 新 PDF 流生成载入后，无感知平滑跳转回对应位置，杜绝每次修改强制跳回第 1 页的灾难体验。
2. **链接分流与拦截**：
   * **外部链接 (`http://`, `https://`)**：点击后拦截，调用操作系统默认浏览器在外部打开；
   * **本地链接 (`./chapter2.md`)**：点击后直接让阅读器打开并渲染对应本地 Markdown 文件；
   * **内部锚点 (`#section-3`)**：通过 PDFium 内部命名目的地（Named Destination）即时跳转。
3. **原生大纲树 (TOC / Outlines)**：
   * Typst 编译时自动生成 Document Bookmarks，`pdfrx` 读取 PDF 内部大纲结构，直接在侧边栏渲染多级可折叠的目录树，点击直达章节。
4. **即时无损导出**：
   * 由于内存中始终常驻最新一版的完整 PDF 二进制数据，用户点击“导出 PDF”时仅需弹出系统文件保存弹窗，写入本地耗时 **0 毫秒**，且保证输出文件与当前屏幕所见 **100% 像素级吻合**。

---

## 6. 工程结构与核心代码骨架

### 6.1 工程目录结构

```text
sogoodviewer/
├── core/                         # Rust 核心引擎 (Cargo Workspace)
│   ├── Cargo.toml
│   ├── src/
│   │   ├── lib.rs                # FFI 暴露接口 (FRB 绑定)
│   │   ├── api.rs                # 面向 Flutter 的数据结构与 API
│   │   ├── compiler/
│   │   │   ├── world.rs          # 内存 Typst World 实现 (字体与VFS)
│   │   │   └── engine.rs         # Typst 编译驱动
│   │   ├── parser/
│   │   │   ├── markdown.rs       # pulldown-cmark 事件流处理
│   │   │   └── math.rs           # LaTeX -> Typst 公式转译 (texmath)
│   │   ├── mermaid/
│   │   │   └── renderer.rs       # 纯 Rust Mermaid 渲染与缓存
│   │   └── assets/
│   │       ├── fonts/            # 内嵌基础西文与符号字体
│   │       └── templates/        # default.typ 母版
│   └── Makefile
│
└── ui/                           # 前端交互 (Flutter Desktop)
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── bridge/               # 由 flutter_rust_bridge 自动生成的绑定代码
    │   ├── controllers/
    │   │   └── document_controller.dart # 文档状态、暗黑模式与热重载
    │   └── views/
    │       ├── workspace_view.dart      # 桌面主视窗 (侧边栏 + 阅读区)
    │       ├── sidebar_toc.dart         # 大纲树视图
    │       └── pdf_canvas.dart          # 基于 pdfrx 的视口与位置恢复组件
    └── assets/
```

### 6.2 核心代码骨架：Rust 内存级 Typst 编译 (`engine.rs`)

直接在内存中链接 Typst，摆脱外部 CLI 进程：

```rust
use std::path::Path;
use typst::diag::SourceResult;
use typst_pdf::PdfOptions;
use crate::compiler::world::MemoryTypstWorld;

pub struct RenderOptions {
    pub mode: String,          // "fluid" | "paged"
    pub theme: String,         // "light" | "dark"
    pub viewport_width: f32,   // 屏幕流宽度
}

/// 将已转译好的 Typst 源码编译为 PDF 内存流
pub fn compile_typst_to_pdf(
    typst_source: &str,
    doc_dir: &Path,
    options: &RenderOptions,
) -> Result<Vec<u8>, String> {
    // 1. 初始化实现 World Trait 的内存环境，挂载 doc_dir 作为相对资源根目录
    let mut world = MemoryTypstWorld::new(typst_source, doc_dir, options)?;

    // 2. 内存增量编译为 Document 结构
    let document = typst::compile(&world)
        .map_err(|errs| {
            errs.iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n")
        })?;

    // 3. 输出 PDF 二进制字节流
    let pdf_bytes = typst_pdf::pdf(&document, &PdfOptions::default())
        .map_err(|e| format!("PDF 导出失败: {:?}", e))?;

    Ok(pdf_bytes)
}
```

### 6.3 核心代码骨架：Flutter 视口与滚动记忆 (`pdf_canvas.dart`)

```dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfCanvasView extends StatefulWidget {
  final Uint8List? pdfBytes;
  final String documentTitle;

  const PdfCanvasView({
    super.key,
    required this.pdfBytes,
    required this.documentTitle,
  });

  @override
  State<PdfCanvasView> createState() => _PdfCanvasViewState();
}

class _PdfCanvasViewState extends State<PdfCanvasView> {
  late final PdfViewerController _controller;
  double _savedScrollRatio = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
  }

  void _recordScrollPosition() {
    if (_controller.isReady && _controller.pageCount > 0) {
      // 记录当前相对滚动位置比例
      _savedScrollRatio = _controller.pageNumber / _controller.pageCount;
    }
  }

  void _restoreScrollPosition() {
    if (_savedScrollRatio > 0 && _controller.isReady) {
      final targetPage = (_savedScrollRatio * _controller.pageCount).round().clamp(1, _controller.pageCount);
      _controller.goToPage(pageNumber: targetPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pdfBytes == null || widget.pdfBytes!.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PdfViewer.data(
      widget.pdfBytes!,
      sourceName: widget.documentTitle,
      controller: _controller,
      params: PdfViewerParams(
        enableTextSelection: true,
        maxScale: 5.0,
        minScale: 0.5,
        onViewerReady: (document, controller) {
          // 文档重载后恢复视口，杜绝跳回第一页
          _restoreScrollPosition();
        },
        linkHandlerParams: PdfLinkHandlerParams(
          onLinkTap: (link) {
            if (link.url != null) {
              // 拦截外部链接，交给系统默认浏览器
              // launchUrl(Uri.parse(link.url!));
            }
          },
        ),
      ),
    );
  }
}
```

---

## 7. 开发者准备与开箱即用构建

### 7.1 开发环境依赖要求
开发者无需安装任何全局 CLI，仅需原生开发工具链：
* **Rust**：`rustup` (版本 $\ge$ 1.80)
* **Flutter SDK**：3.22+，开启 Desktop 支持 (`flutter config --enable-macos-desktop` / windows / linux)
* **代码生成工具**：`cargo install flutter_rust_bridge_codegen`

### 7.2 打包与分发规格
* **终端无依赖**：编译输出的应用（`SuperGoodViewer.app` / `.exe` / `AppImage`）内嵌了所有必要的排版内核、数学转译器与图表渲染器，**无需用户主机安装任何第三方工具包**。
* **冷启动性能目标**：文档冷启动解析并渲染首屏耗时控制在 **100ms** 以内；本地文件变更热重载控制在 **30ms** 以内。
