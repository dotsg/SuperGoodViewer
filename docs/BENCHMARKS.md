# SuperGoodViewer 性能基准报告 (Performance Benchmarks)

本轮数据由 2026-09-20 的一次完整复测产生，全部可复现（复现命令见文末第 8 节）。
除第 7 节明确标注为"引用/未复测"的第三方软件数据外，本文所有数字均为本机实测。

## 0. 测试环境

| 项目     | 规格                                                            |
| -------- | --------------------------------------------------------------- |
| 硬件     | Apple M4 Max，14 核，36 GB 统一内存，APFS SSD                   |
| 操作系统 | macOS 27.0 (Build 26A428)                                       |
| Rust     | rustc 1.98.1，release profile（`opt-level = 3`, `lto = "thin"`) |
| Flutter  | 3.47.3 stable / Dart 3.13.3，Impeller (Metal)                   |
| 被测版本 | SuperGoodViewer v1.0.8 (arm64 本机构建)                         |

> 测量期间机器有其他常规进程在跑（未做单用户模式隔离），因此尾部分位数
> (p95) 会比理想环境略高。每项指标都给出 min / p50 / p95 而不是单一数字。

---

## 1. 本轮修正了什么（旧数据为何不可信）

上一版文档把"端到端排版"写成 **0.28 ms ~ 4.54 ms**。该数字是**基准方法错误**造成的，
不是真实排版耗时：

1. **Typst 通过 `comemo` 做全局记忆化。** 旧基准在循环里反复编译**同一份**源文件，
   第 2 次起 Typst 的布局结果直接从 memo 缓存返回。测到的是哈希查表，不是排版。
   本轮基准在每个冷样本前调用 `typst::comemo::evict(0)`。
2. **Mermaid 有 SHA-256 内容缓存。** 旧基准循环内的图表全部命中缓存，
   于是"含 6 张 Mermaid 图的 PRD"反而比纯文本 README 还快。本轮冷样本前清空该缓存。
3. **文档规模标注与实际输入不符**（由 [issue #14](https://github.com/dotsg/SuperGoodViewer/issues/14)
   指出，感谢 @szdytom）。旧基准里："书籍章节 (~100 KB, 20 Chapters)" 实际只有约 11.8 KB
   （每章约 600 B）；"技术 PRD (~20 KB)" 实际约 1.3 KB；"开源 README (~4 KB)" 实际读的是
   仓库 README（约 29 KB）。也就是说"100KB 书籍排版 2.55 ms"这一行，既用了 11.8 KB 的文档，
   又命中了 memo 缓存，错了两次。
   本轮的做法是两头都堵上：样本按标签补足到真实规模（PRD 20.1 KB、书籍 97.8 KB），
   并全部冻结进 [`docs/samples/bench/`](samples/bench/)；规模一律由程序打印
   `markdown.len()`，标签就是文件名，不再手写。此前基准直接读仓库根目录的
   `README.md` 与 `test.md`，这两个文件一改，基准输入就跟着变（本轮复测过程中
   README 的大小就变过三次）。
4. **单点采样。** 旧数据是 N 次循环的平均值，没有分位数，异常值被平均掉。
   本轮每项单独计时，报告 min / p50 / p95。

同时修正的还有：包体积（94 MB → 实测 153 MB）、常驻内存（158 MB → 实测约 207 MB）、
以及"文档就绪耗时"——旧文档把 Flutter trace 里的 `timeToFirstFrameRasterized`
当作"文档渲染上屏"，实际上那时文档尚未加载。本轮为此在 `onViewerReady`
后补了真实探针 `StartupMetrics.markFirstDocument()`。

---

## 2. 端到端排版编译 (Markdown → Typst → PDF 字节流)

`core/src/bin/benchmark.rs`，release 构建，Fluid（流式）模式，每档 20 个冷样本、
20 个编辑样本、30 个热样本。输入取自冻结语料 [`docs/samples/bench/`](samples/bench/)——
这些文件只增不改，改仓库 README 或 `test.md` 不会再影响基准数字。
三种口径对应三种真实场景：

| 口径     | 缓存状态                                      | 对应真实场景                                     |
| -------- | --------------------------------------------- | ------------------------------------------------ |
| **冷**   | 每个样本前清空 comemo + Mermaid 缓存          | 进程刚启动，打开本次会话的第一篇文档             |
| **编辑** | 保留缓存，但每个样本的正文都不同              | 编辑保存触发热重载；在已运行的实例里打开下一篇   |
| **热**   | 保留全部缓存，重复编译完全相同的内容          | 切换主题、改排版参数、窗口重排后的重新渲染       |

### 2.1 总表（单位 ms）

| 文档                        | 输入    | 输出 PDF |   冷 min |   冷 p50 |   冷 p95 | 编辑 p50 | 热 p50 | A4 分页 冷 p50 |
| --------------------------- | ------: | -------: | -------: | -------: | -------: | -------: | -----: | -------------: |
| `01-note.md` 速记短文       |   137 B |  13.7 KB |     0.98 | **1.03** |     1.45 |     0.89 |   0.50 |           1.18 |
| `02-readme.md` 项目 README  | 28.2 KB |  1042 KB |    40.84 | **42.50**|    44.46 |    12.33 |  10.80 |          43.87 |
| `03-prd.md`（含 6 张 Mermaid）| 20.1 KB |   211 KB |   181.09 |**182.28**|   191.32 |     8.45 |   4.43 |         186.23 |
| `04-book.md`（20 章）       | 97.8 KB |   923 KB |   293.19 |**296.00**|   299.55 |    51.52 |  19.99 |         175.93 |
| `05-real-world.md`          | 21.7 KB |   449 KB |    93.80 | **94.98**|    96.09 |    11.31 |   8.69 |          99.32 |

### 2.2 阶段拆解（冷口径 p50，单位 ms）

| 文档               | Markdown → Typst 源码 | Typst 布局 + PDF 导出 | 端到端 | 端到端 − 两阶段之和 |
| ------------------ | --------------------: | --------------------: | -----: | ------------------: |
| `01-note.md`       |                  0.01 |                  1.10 |   1.03 |                ~0   |
| `02-readme.md`     |                  0.13 |                 41.34 |  42.50 |                +1.0 |
| `03-prd.md`        |                140.10 |                 40.87 | 182.28 |                +1.3 |
| `04-book.md`       |                  0.52 |                155.06 | 296.00 |              +140.4 |
| `05-real-world.md` |                 41.79 |                 53.00 |  94.98 |                ~0   |

两处值得解释的地方：

- **PRD 的 140 ms 全在 Markdown 阶段**，因为该文档有 6 张各不相同的 Mermaid 图，
  冷渲染每张约 23 ms（见 3.2）。Mermaid 冷渲染是首次打开图表类文档的主要成本；
  同一张图第二次出现即命中缓存（约 0.8 µs），所以"编辑"口径骤降到 8.5 ms。
- **书籍章节端到端比两阶段之和多出约 140 ms**，这不是测量误差：Fluid 模式下
  单页画布超过 PDF 1.7 的 14,400 pt 上限时，`compile_markdown_to_pdf` 会再编译
  1～2 个切分候选方案并择优（见 `core/src/lib.rs` 的 candidate A / B 逻辑）。
  同一文档在 A4 分页模式只需 176 ms，正好印证多出来的是额外那轮编译。

### 2.3 结论

- 短文档（几 KB 以内）冷编译 **约 1 ms**，任何口径下都远低于一帧。
- 20 KB 级真实文档首次打开 **约 95～182 ms**（取决于 Mermaid 图数量），
  再次渲染 **约 4～12 ms**。
- 100 KB 书籍首次打开 **约 0.3 s**，其中近一半是 Fluid 切分的重复编译开销。
- 交互式使用（改主题、改字号、热重载）的实际感知延迟在 **0.5～20 ms**，
  这才是"毫秒级"说法成立的范围；**首次打开不是毫秒级**。

---

## 3. 子系统微基准

### 3.1 LaTeX → Typst 转译 (`mitex`)

每条公式单独计时 5,000 次（预热 200 次）：

| 公式                                                                  | min (µs) | p50 (µs) | p95 (µs) | p50 吞吐 (式/秒) |
| --------------------------------------------------------------------- | -------: | -------: | -------: | ---------------: |
| `E = mc^2`                                                            |     2.40 | **3.60** |     4.20 |          278,000 |
| `\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}`                    |     5.70 | **7.40** |    11.20 |          135,000 |
| `\nabla \times \mathbf{B} - \frac{1}{c}\frac{\partial \mathbf{E}}{\partial t} = \frac{4\pi}{c}\mathbf{J}` | 6.10 | **7.30** | 9.20 |  137,000 |
| 3×3 `pmatrix`                                                         |     3.40 | **3.70** |     5.00 |          270,000 |

即 **13.5 万 ~ 27.8 万 式/秒**（旧文档写 15 万 ~ 32 万，取的是均值/最优值）。
注意这是 LaTeX → Typst AST 的转译耗时，不含后续排版与字形绘制。

### 3.2 Mermaid 离线矢量渲染 (`mermaid-rs-renderer`)

9 节点流程图，输出 8,685 字节纯矢量 SVG：

| 口径                     |      min |      p50 |      p95 | 说明                                     |
| ------------------------ | -------: | -------: | -------: | ---------------------------------------- |
| 冷渲染（每次图内容不同） | 22.56 ms | **23.27 ms** | 24.74 ms | 真正的解析 + 布局 + SVG 生成         |
| 缓存命中（同一张图）     |   708 ns | **792 ns**   |  959 ns | SHA-256 求哈希 + 哈希表查表          |

旧文档把 829 ns 写成"增量渲染"，容易被读成"再渲染一次只要 0.8 µs"。
准确表述是：**命中缓存时不再渲染**，0.8 µs 是查表成本。冷渲染 23.3 ms
是图表类文档首屏耗时的主要来源。

---

## 4. 安装包体积

本机 `make build`（arm64）产物，`du -sm` 实测：

| 组成                          |  体积 | 说明                                                       |
| ----------------------------- | ----: | ---------------------------------------------------------- |
| `Resources/bin/sgv-cli`       | 47 MB | 命令行工具，静态包含同一套 Typst 引擎与字体（与 dylib 重复） |
| `Frameworks/libsogood_core.dylib` | 45 MB | Rust 排版核心：Typst 0.15.1 + 17 款字体 + MiTeX + Mermaid |
| `Frameworks/FlutterMacOS.framework` | 30 MB | Flutter 桌面运行库（x86_64 + arm64 胖二进制）        |
| `Frameworks/App.framework`    | 18 MB | Dart AOT 业务代码                                          |
| `Frameworks/PDFium.framework` | 12 MB | Google PDFium 矢量渲染引擎                                 |
| 图标、签名、其他资源          |  ~2 MB | Assets.car、icns、_CodeSignature                          |
| **合计**                      | **153 MB** | arm64 本机构建                                        |

其他口径：

- **通用（arm64 + x86_64）发行版**，即 `/Applications/SuperGoodViewer.app`：**248 MB**
- **DMG 下载体积（压缩后）**：**50 MB**

> 旧文档的 94 MB 已不成立。主要增量来自：随包附带的 `sgv-cli`（47 MB，
> 与动态库重复打包了一整套引擎和字体）、Flutter framework 的胖二进制，
> 以及核心库自身的增长。**体积优化空间明确在 `sgv-cli` 的重复打包上。**

同目录下第三方软件实测（`du -sm /Applications/*.app`，同一台机器）：

| 软件               | 体积   |
| ------------------ | -----: |
| Visual Studio Code | 933 MB |
| Obsidian           | 482 MB |
| MarkText           | 368 MB |
| SuperGoodViewer    | 248 MB（通用版）/ 153 MB（arm64）|
| Typora             |  46 MB（外挂系统 WebKit）|

---

## 5. 启动耗时

Profile 构建，`flutter run -d macos --profile --trace-startup`，命令行传入 `test.md`，
连续 5 次启动（每次重开进程，二进制已在 page cache 中，属**温启动**）。
trace 口径来自 Flutter engine 自带的 `build/start_up_info.json`，
应用内探针 `StartupMetrics` 从 `main()` 起算，两者互相校验：

| 阶段                                                | min | 中位数  | max | 口径                                   |
| --------------------------------------------------- | --: | ------: | --: | -------------------------------------- |
| engine 启动 → Flutter framework 就绪 (`timeToFrameworkInit`) |  49 |  **54** |  64 | trace                                  |
| `main()` → UI 首帧（外壳绘制）                      |  32 |  **45** |  53 | 应用内探针（≈ trace `timeAfterFrameworkInit`）|
| **engine 启动 → UI 首帧** (`timeToFirstFrame`)      |  86 |  **98** | 115 | trace                                  |
| engine 启动 → 首帧完成光栅化                        | 114 | **124** | 142 | trace                                  |
| `main()` → **文档真正显示**                         |  78 |  **85** |  92 | 应用内探针 `markFirstDocument()`       |
| **engine 启动 → 文档显示**（第 1 行 + 第 5 行，逐次相加）| 132 | **141** | 154 | 合成                                   |

单位 ms，n = 5。

> **口径提醒（旧文档在这里出过错）**：
> - `timeToFrameworkInit`（约 54 ms）时应用尚未绘制任何像素，不能当"首帧"。
> - `timeToFirstFrameRasterized`（约 124 ms）是**外壳**首帧光栅化完成，文档此时还没加载完；
>   旧文档把它当成"文档渲染上屏"。本轮为此补上了真实探针：`PdfCanvasView.onViewerReady`
>   之后的第一帧才算文档上屏，实测中位数为 engine 启动后 **141 ms**。
> - **冷启动（page cache 为空、刚开机或刚构建完）本轮没有复测**，需要 `sudo purge`
>   或重启才能构造，旧文档的 417 / 487 ms 未经本轮验证。仅有的一个参考点：
>   构建完成后的首次启动，engine → UI 首帧 141 ms、首帧光栅化 221 ms。

---

## 6. 内存与进程

Release 构建，命令行传入 `test.md` 启动，静置 40 秒后采样（`ps` / `footprint`）：

| 指标                       |        实测 |
| -------------------------- | ----------: |
| `phys_footprint` 常驻      | **207 ~ 209 MB** |
| `phys_footprint_peak` 峰值 | **638 ~ 676 MB** |
| `ps` RSS                   | **227 MB**（含字体 mmap 的常驻文件页）|
| 进程数                     | **1 个**    |

说明：

- 字体经 `memmap2` 内存映射，属干净的文件背景页，内存压力下可回收；
  这部分会计入 RSS 但可被内核换出，因此 RSS 高于 `phys_footprint` 属正常。
- **峰值 638 MB 远高于常驻。** 峰值出现在首次编译期间。Typst 的 `comemo`
  记忆化缓存目前没有调用 `evict`（Typst CLI 每次编译后会 `evict(5)`），
  长时间反复编译会让这部分内存只增不减——这是当前已知的可优化点。
- 旧文档的 158 MB / 597 MB 峰值是更早一个构建、且加载的是内置示例文档时的读数，
  与当前版本不可比。

历史优化（`fs::read` → `mmap`）的隔离测量仍然有效，保留备查：

|                       | `fs::read` |  `mmap`   |
| --------------------- | :--------: | :-------: |
| 加载 158 个字体后     |   548 MB   | **11 MB** |
| 再编译一份 CJK 文档后 |   552 MB   | **15 MB** |

---

## 7. 与其他 Markdown 软件的对比

**本机实测的只有体积一项（见第 4 节）。** 下表中 Obsidian / Typora / MarkText /
VS Code 的启动、排版、内存数据来自上一版文档，属于**估计值，本轮未复测**，
仅供量级参考，不应作为精确结论引用。

| 维度            | SuperGoodViewer（本轮实测）                   | Obsidian（未复测） | Typora（未复测） | MarkText（未复测） | VS Code（未复测） |
| --------------- | --------------------------------------------- | ------------------ | ---------------- | ------------------ | ----------------- |
| 底层架构        | Rust + Flutter (Impeller Metal)               | Electron           | Cocoa + WKWebView| Electron           | Electron          |
| 进程数          | **1**                                         | 4                  | 2                | 5                  | 8+                |
| 安装体积        | **153 MB (arm64) / 248 MB (通用)**            | 482 MB             | 46 MB            | 368 MB             | 933 MB            |
| 常驻内存        | **207 MB**（峰值 638 MB）                     | ~627 MB            | ~266 MB          | ~715 MB            | ~950 MB           |
| 22 KB 文档首次排版 | **95.0 ms**（含 Mermaid 冷渲染）           | 350 ~ 450 ms       | 300 ~ 400 ms     | 450 ~ 600 ms       | 500 ~ 700 ms      |
| 同文档重新渲染  | **8.7 ms**                                    | —                  | —                | —                  | —                 |
| 100 KB 书籍首次排版 | **296 ms**                                | 750 ~ 1,000 ms     | 600 ~ 800 ms     | 1,000 ~ 1,500 ms   | 1,200 ~ 2,000 ms  |
| 无损 PDF 导出   | **单次文件写入**（渲染结果本身即 PDF）        | 2 ~ 5 s            | 1.5 ~ 3.5 s      | 3 ~ 6 s            | 3 ~ 8 s           |

---

## 8. 复现方法

输入语料固定在 [`docs/samples/bench/`](samples/bench/)，五个文件只增不改；
新增场景请加新文件并在 `benchmark.rs` 的 `CORPUS` 表登记。

```sh
# Rust 核心基准（约 50 秒）
make bench
# 同一套基准，并刷新 docs/benchmark-results.json
make bench-json

# 包体积
make build
du -sm ui/build/macos/Build/Products/Release/SuperGoodViewer.app

# 内存（启动后静置 40 秒）
open -n ui/build/macos/Build/Products/Release/SuperGoodViewer.app --args "$PWD/test.md"
footprint -p $(pgrep -f Release/SuperGoodViewer.app | head -1)

# 启动耗时（Profile 构建，读取 Flutter 自带 trace）
cd ui && flutter run -d macos --profile --trace-startup \
  --dart-entrypoint-args "$PWD/../test.md"
cat build/start_up_info.json
```

原始逐项数据：[benchmark-results.json](benchmark-results.json)。
渲染层图块/条带策略的独立基准见 [RASTER_GRID_BENCHMARK.md](RASTER_GRID_BENCHMARK.md)。
