# 我为什么放弃 Electron，用 Rust 写了一款“只读”的 Markdown 桌面阅读器？

今天，市面上的笔记软件都在卷双链图谱、AI 对话、多维表格、插件市场。但唯独没有人认真对待过一件最基础的事：「排版与阅读」。

于是，在无数次被卡顿和糟糕排版劝退后，我决定自己动手，做一款纯粹为“排版强迫症”与“极致阅读体验”而生的桌面应用：超好读 SuperGoodViewer：

![Image](https://mmbiz.qpic.cn/sz_mmbiz_png/yVwYcibHCQbUhbtEib78gzlSRsHicerMcIao6Kvxeib6EtnWkS8KypicuPrSdJteTt5VxQgpPs7k9Bhgr6GdymmPvrxVnD3Q7Jdp98nhnvNmDfHY/640?wx_fmt=png&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1#imgIndex=0)

# 🚀 什么是「超好读 SuperGoodViewer」？

一句话概括：它是一款专为电脑桌面打造的纯原生、只读 Markdown 矢量排版阅读器。

它的核心理念极其克制：

- 彻底剥离富文本编辑器的一切冗余复杂度，专注“只读”。
- 出版级排版（Publication-Grade Typography）
- 像素级一致（Pixel-Perfect Consistency）
- 零 WebView（Zero-WebView）

为了达成这个目标，超好读在底层彻底舍弃了传统 Electron / Chromium 内核的方案，采用了一套极其硬核的原生全闭环流水线：

```
Markdown 源文档 (.md)
        │
        ▼ 纯内存零拷贝管道
[Rust 嵌入式排版内核] (sogood_core)
  ├── 1. GFM 高速语法解析
  ├── 2. LaTeX 公式微秒级转译 (mitex)
  ├── 3. 离线纯矢量 Mermaid 渲染与 SHA-256 缓存
  └── 4. 纯内存 Typst 出版编译器 (typst + typst-pdf)
        │
        ▼ Uint8List 零拷贝二进制直通
[Flutter Desktop 原生视窗]
  └── Google PDFium 硬件加速矢量渲染视窗 (Metal / DirectX)
```

# 💡 为什么它能快到像“呼吸一样自然”？

我对超好读的要求就是：快、极致的快，然后尽可能的好用。

1. 重新渲染流水线：0.5ms ~ 20ms

得益于纯 Rust 实现的嵌入式内存编译器，一篇上万字的综合技术文档（含大量代码块、公式和图表）首次打开约 94 毫秒，此后改主题、改字号等重新渲染只要 9 毫秒左右；100KB、30 页以上的整本小书首次打开约 0.3 秒，重新渲染约 20 毫秒。也就是说，只有第一次打开需要等一下，之后的每一次调整都在视觉暂留门槛附近完成。（实测数据与方法见仓库 docs/BENCHMARKS.md）

2. 双排版视窗模型 (Dual-Layout)

市面上绝大多数 Markdown 工具的排版是屏幕流动的。超好读创新性地设计了双排版视窗：

自适应流式视窗 (Fluid Screen)：锁定 720pt 出版黄金阅读行宽，居中呈现，无缝连续卷轴。不论你的显示器是 13 寸笔记本还是 34 寸带鱼屏，窗口拉伸时完全0 次触发编译器，依靠 Metal / GPU 变换完成缩放；

A4 出版打印视图 (Paged)：精确的标准 A4 页面排版、动态页眉页脚、防孤行孤字控制，100% 真正做到“屏幕即纸面，打印即所见”。

3. 出版级数学公式与纯矢量 Mermaid

公式吞吐 30 万式/秒：内置 mitex LaTeX to Typst 原生转译引擎，微积分、高阶矩阵与多行对齐方程瞬间呈现，不再依赖庞大的 JS 库；

离线 Mermaid 图表：采用纯 Rust 实现的 mermaid-rs-renderer，毫秒级直接计算矢量路径，告别无头 Chromium。自带 SHA-256 增量图表缓存，再次查看二次复用仅需830 纳秒。

4. 导出无损 PDF：无需重新排版，只写一次文件

在超好读中，文档在内存中的编译结果本质上就已经是符合 PDF/X 规范的高精度矢量 PDF！因此，按下 Cmd + E（或 Ctrl + E），导出无损矢量 PDF 仅仅是一次磁盘 I/O 写入，不需要重新排版，彻底告别传统浏览器的转圈等待。

# 📊 数据说话：与传统工具的基准对比

我们用真实的综合技术文档（包含代码、数学公式、Mermaid 时序图与复杂表格），在同等硬件环境（就我的M4 Mac Studio）下进行了严谨的性能基准对比：

| 测试维度            | 超好读（实测中位数）           | Obsidian              | Typora           | VS Code          |
| ------------------- | ------------------------------ | --------------------- | ---------------- | ---------------- |
| 底层架构            | Rust + Metal/GPU 纯原生        | Electron              | Cocoa + WebKit   | Electron         |
| 操作系统进程        | 1 个原生进程                   | 4 个独立进程          | 2 个独立进程     | 8+ 个独立进程    |
| 温启动 UI 首帧      | 98 ms（文档上屏 141 ms）       | 1,500 ~ 2,500 ms      | 450 ~ 600 ms     | 1,800 ~ 3,500 ms |
| 20KB PRD 首次排版   | 179 ms（重新渲染 4.4 ms）      | 350 ~ 450 ms          | 300 ~ 400 ms     | 500 ~ 700 ms     |
| 100KB 书籍首次排版  | 299 ms（重新渲染 20 ms）       | 750 ~ 1,000 ms        | 600 ~ 800 ms     | 1,200 ~ 2,000 ms |
| 窗口拉伸流畅度      | 拉伸 0 次触发编译（GPU 变换）  | 35 ~ 55 FPS (DOM重排) | 45 ~ 60 FPS      | 40 ~ 60 FPS      |
| 无损 PDF 导出       | 一次文件写入，无需重新排版     | 2,000 ~ 5,000 ms      | 1,500 ~ 3,500 ms | 3,000 ~ 8,000 ms |

> 超好读一列为 2026-09-20 在 Apple M4 Max / macOS 27 上的实测数据（方法与分位数见仓库
> `docs/BENCHMARKS.md`）；其余三款为旧版文档沿用的估计值，未在本轮复测，仅供量级参考。

更重要的是：全自包含，零外部依赖。在任何设备上都能呈现 100% 一致的字体与版面。

# 📦 如何获取与体验？

「超好读 SuperGoodViewer」现已正式发布1.0.1 版本，并在 GitHub 全开源：

开源协议：MIT License（完全免费、开源）

项目仓库：https://github.com/dotsg/supergoodviewer

💻 客户端直接下载：

前往 GitHub Releases 页面，即可直接下载预编译安装包：👉下载地址：

🍏 macOS 用户：下载 `SuperGoodViewer-v1.0.1-macos.dmg` (Universal 通用安装包，原生支持 M 系列与 Intel 芯片 Mac)

🪟 Windows 用户：下载 SuperGoodViewer-v1.0.1-windows-x64.zip

# 写在最后

开发这个软件我其实主要只是治疗处女座我自己的强迫症。

在我试过的所有md软件中，就没有一个考虑中英文全角、半角字符混合严格对齐的问题，这是超好读的显示：

![Image](https://mmbiz.qpic.cn/mmbiz_png/yVwYcibHCQbXibZ5yiblkFRUiaZRflZonYIRoicH6gYpLKRqUzk3uXicoEeLX5eoAniccwSlGgOdSwyE73714HULDaHZBgwvTNQvo5NuOhxKvKwtNQ/640?wx_fmt=png&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1#imgIndex=1)

但市面没有一款软件可以默认把类似上面的表格显示完美，看到的，往往是：

![Image](https://mmbiz.qpic.cn/mmbiz_png/yVwYcibHCQbVibQfZBJFj8sEQB5wIVQ1KHsgATPs2rv2la5FiaGnFVvTqGybzwsDia5ibZ5Kic8BasXlq5x0GWuGcQssIlkdSXUtXrzNZc8ia73a5w/640?wx_fmt=png&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1#imgIndex=2)

就很难忍。

而且，更为关键的是，即便我通过各种设置，使得我本地显示完美了，当我把md文件发给别人的时候，排版也是会乱掉；而几乎所有的markdown格式软件，导出的pdf跟预览模式完全可以是两个排版！

因为市面上所有同类软件使用的几乎都是web引擎去做渲染，web天生无法对排版做像素级别的精准控制，web与pdf也是两套独立的引擎，自然会有差异。

所以，超好读完全不用任何web技术，我直接用rust，站在typst（typst值得单独写文章来介绍）这个巨人的肩膀上重新做一个md阅读器！

超好读显示的就是pdf光栅化后的图形，所以导出与预览，会严格一致，所见即所得！

我也完全不做编辑功能，超好读的实时渲染速度极快，并且默认监控当前文件的修改，会自动刷新预览；可以使用任意现有编辑器去做编辑；屏幕一边编辑，一边显示超好读就是：

![Image](https://mmbiz.qpic.cn/sz_mmbiz_png/yVwYcibHCQbUTZdeI7mibiaibIv9l2NacJ6OgKeQdjBGc8GGdniaWNHhVVNN2KE2XMJx8Nu92vvFJ6NLEUicOH9jbPaHY07UMSPYKbv9KEYD9LeuU/640?wx_fmt=png&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1#imgIndex=3)

我自己日常使用的是Sublime Text：并且也为md各种表格、图表的严格对齐搞了个插件：github.com/Wuvist/md\_table\_format

祝大家阅读愉快！

我是玩家翁伟，谢谢～
