# 与 markview 的性能对比

[markview](https://github.com/szdytom/markview) 的 README 用一组表说明它“大幅领先”
SuperGoodViewer：打开文档 0.10 s 对 0.63～0.77 s，常驻内存 51 MiB 对 300 MiB，
导出 PDF 0.04 / 0.07 s 对 0.10 / 0.16 s。那组数据测于 Linux（Intel 核显、X11），
被测的是 SuperGoodViewer 1.0.8 发布包。

本文在本机重做了这组对比，核实差距在哪里、原因是什么，并记录据此做的两处修复。
除第 5 节标明的历史数据外，所有数字都来自本文第 8 节的脚本。

## 0. 测试环境

| 项目 | 规格 |
| --- | --- |
| 硬件 | Apple M4 Max，14 核，36 GB |
| 系统 | macOS 27.0 (26A428) |
| 工具链 | rustc 1.98.1，Flutter 3.47.3 / Dart 3.13.3 |
| markview | `911921a`（0.1.7），`cargo build --release` |
| SuperGoodViewer | `597d726`（含第 6 节两处修复）；“修复前”为 `f92af37` 的界面，配 2026-09-20 构建的引擎（此后 core 只改了 Markdown 表格表头，测试文件不含表格） |

测量日期 2026-09-23，机器上有常规后台进程。

## 1. 结论

- **命令行导出 PDF（A4）不比 markview 慢。** 10 KiB 两者持平；内容不重复时，
  100 KiB 快 1.6 倍，1 MiB 快 2.4 倍。
- **markview 表里的大文档差距来自测试文件本身。** 它的测试文件把 6 段文字循环拼接
  到目标大小，而 markview 按段落内容缓存排版：1 MiB 的 2842 段里 2834 段直接复用
  （见第 3 节）。换成每段都不同的内容，markview 的耗时增长约 2～4 倍，SGV 不变。
- **SGV 做的排版更简单。** 模板是 `justify: false`，Typst 用贪心断行；markview 默认
  两端对齐，并做整段最优断行和英文断字。SGV 打开同样的功能后排版慢约 90%，但端到端
  仍快约 1.3～1.5 倍（第 4 节）。
- **桌面端打开文档确实更慢**：本机 10～100 KiB 约为 markview 的 1.3～2 倍，1 MiB
  约 5 倍（默认流式版式）。主要是 Flutter 引擎在进入 Dart `main()` 前的约 150 ms，
  以及“排完全文、生成 PDF、PDFium 解析”这条串行链路；markview 边排边显示，首帧
  不随文档变大（第 5 节）。markview 文档里 10～100 KiB 的 6 倍测于 Linux，本机无法复现。
- **两处真实问题已修复**：系统字体初始化 43 → 17 ms，macOS 上同一文件被打开两次
  （第 6 节）。

## 2. 测试文件

`scripts/markview-compare/fixtures.py` 生成两组文件，均为确定性输出：

| 文件 | 内容 |
| --- | --- |
| `prose-10k/100k/1m`、`math-10k/100k` | markview 自己的对比测试文件（调用其 `scripts/comparison_fixtures.py`）：6 段固定文字循环拼接，`math-*` 每段后附同一组 7 个公式 |
| `uprose-100k`、`uprose-1m` | 相同词汇，每段随机抽词重排，任意两段都不相同 |
| `umath-100k` | 同 `uprose`，公式结构不变但每处数字都不同 |

`umath` 只替换数字，不改字母：改字母会破坏 `\xi` 这类命令，导致 SGV 触发公式降级和
一轮额外的重试排版，测到的就不是正常路径了。导出脚本会拒绝出现降级的样本。

## 3. 命令行导出 PDF（A4）

每个样本是一个冷启动进程，从启动到退出的墙钟时间，输出写入磁盘；两个程序在每轮内
交替运行，取 5 轮中位数。只比 A4，这是 PDF 导出的默认格式。

| 文件 | markview (ms) | sgv-cli (ms) |
| --- | ---: | ---: |
| prose-10k | 43 | 47 |
| prose-100k | 57 | 71 |
| **uprose-100k** | **118** | **72** |
| math-100k | 59 | 110 |
| **umath-100k** | **111** | **117** |
| prose-1m | 222 | 336 |
| **uprose-1m** | **832** | **345** |

markview 导出时会在日志里报告复用的段落数，差异一目了然：

| 文件 | 段落数 | 复用 | markview 自报耗时 |
| --- | ---: | ---: | ---: |
| prose-100k | 279 | 271 | 61 ms |
| uprose-100k | 291 | 0 | 109 ms |
| math-100k | 730 | 715 | 48 ms |
| umath-100k | 730 | 98 | 104 ms |
| prose-1m | 2842 | 2834 | 213 ms |
| uprose-1m | 2970 | 0 | 810 ms |

原因在 markview 的 `LayoutEngine`（`crates/markview-core/src/layout.rs`）：它按
`CacheKey` 缓存每个段落的排版结果，键是段落内容的哈希加排版参数，**不含段落位置**，
同一次排版里第二次遇到相同内容就直接复用。markview 自己的
`docs/development.md` 也写明其测试文件 “flatters any content-keyed cache”。

Typst 也缓存段落排版（`layout_par_impl` 带 `#[comemo::memoize]`），但参数里有
`locator`（元素在文档中的位置标识），实测重复内容不带来任何收益：prose-1m 与
uprose-1m 的 SGV 耗时相差不到 3%。

## 4. SGV 导出分段

`core/examples/stage_probe.rs`，A4。“清缓存后重排”是同一源码在清空 Typst 缓存后
再排一次，与首次排版之差就是进程内的一次性初始化。

| 文件 | 字体初始化 | Markdown→Typst | 首次排版 | 清缓存后重排 | 写 PDF | 写 PDF（不带标签） |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| prose-10k | 16.2 | 0.2 | 21.4 | 2.9 | 1.9 | 0.6 |
| uprose-100k | 16.5 | 0.3 | 40.7 | 22.5 | 5.5 | 4.6 |
| umath-100k | 16.6 | 4.3 | 69.9 | 52.5 | 15.4 | 9.6 |
| uprose-1m | 17.6 | 2.7 | 249.5 | 233.0 | 50.2 | 45.3 |

一次性初始化的构成（`stage_probe first-use`，单位 ms）：

| 触发项 | 耗时 |
| --- | ---: |
| 字体初始化（fontdb 扫描约 11 ms + 读取 FontInfo 缓存） | 18.2 |
| 首次用到 PingFang | 16.5 |
| 首次出现代码块（加载 syntect 语法集） | 9.9 |
| Typst 标准库 + 首次排版 | 1.2 |
| 中日文断行器（`lang: "zh"`） | 0.1 |
| 公式 | 0.5 |

首次用到 PingFang 的 16 ms 来自 Typst 内部：`impl Hash for Font` 会哈希字体的整个
数据，而 `Font::instantiate` 是带缓存的函数，于是整个 74 MB 的 `PingFang.ttc` 会被
读一遍算哈希。英文正文也会落到 PingFang，因为字体列表里排在前面的 Inter、
SF Pro Text 在 macOS 上通常没有安装。每个进程每个字体文件只付一次。

对 1 MiB 排版采样，时间几乎都在 rustybuzz 的字形查找、shaping、断行和双向文本分析，
即正常的排版工作，没有发现额外浪费。两者都基本单线程：uprose-1m 上 markview
用户态 CPU 0.19 s、墙钟 0.21 s；sgv-cli 分别为 0.35 s 和 0.33 s。

### 两端对齐与断字

`stage_probe variants`，排版和写 PDF 耗时（ms）：

| 文件 | 现状 `justify: false` | `justify: true` | 再加 `lang: "en"`（英文断字） | 去掉页眉页脚 |
| --- | ---: | ---: | ---: | ---: |
| uprose-100k | 22.4 + 5.2 | 31.0 + 5.6 | 41.0 + 5.6 | 18.6 + 5.0 |
| uprose-1m | 229.9 + 49.3 | 317.1 + 51.0 | 425.6 + 52.6 | 189.0 + 47.4 |
| prose-1m | 214.1 + 47.8 | 305.3 + 51.6 | 406.0 + 50.6 | 185.1 + 45.1 |

- 两端对齐切换到 Knuth–Plass 整段最优断行，排版约贵 40%；再加英文断字约贵 90%。
- 换算成 CLI 端到端（实测总时间减去排版和写 PDF，再加上变体的时间）：uprose-100k
  约 94 ms（markview 118），uprose-1m 约 550 ms（markview 832）。
- 这不是严格的同工对比：markview 的断行模型还限制词距、微调字距，页面设置排出的
  行更多（100 KiB 它排 40 页，SGV 排 28～32 页）。
- 页眉页脚里的 `counter(page)` 让 Typst 多排一轮，约占排版时间的 15%；只去掉未使用的
  `counter(page).final()` 仅省 1%。默认配置需要页码，因此保留。

## 5. 桌面端打开文档

`scripts/markview-compare/gui_open_bench.py`，Profile 构建。从启动进程计时到应用
打印 `time to first document displayed`。每次打开的都是一份新的文件副本，避开已编译
PDF 的磁盘缓存；使用临时 HOME，不读写用户偏好，因此两个版本用的都是默认参数，即流式
版式。5 轮中位数，两个版本交替运行。

| 文件 | 修复前 | 修复后 | 编译次数 | markview `smoke` |
| --- | ---: | ---: | --- | ---: |
| prose-10k | 261 ms | 236 ms | 2 → 1 | 181 ms |
| prose-100k | 311 ms | 286 ms | 2 → 1 | 183 ms |
| math-100k | 395 ms | 353 ms | 2 → 1 | 181 ms |
| prose-1m | 1013 ms | 930 ms | 2 → 1 | 179 ms |

- SGV 的探针在 PDF 查看器就绪后的下一帧打点，页面瓦片可能仍在光栅化，所以它是
  “上屏”的下限。markview 的 `smoke` 从进程入口计时到首个可读的 GPU 帧完成，
  不含合成器呈现，两者口径接近但不完全相同。
- markview 的首帧不随文档变大，因为它边排版边发布已排好的开头部分。SGV 必须排完
  全文、生成整个 PDF 才能显示。

修复前 math-100k 一次打开的时间线（日志时间戳，从启动进程起算）：

| 时间 | 阶段 |
| --- | --- |
| 0 → 150 ms | 加载动态库、初始化 Flutter 引擎、Impeller (Metal)、Dart VM，注册插件，进入 `main()` |
| 150 → 172 ms | `runApp`，读文件，开始编译 |
| 172 → 306 ms | 字体初始化约 45 ms，Typst 排版与写 PDF 约 125 ms |
| 306 → 325 ms | 同一文件第二次编译（第 6 节修复的问题） |
| 325 → 343 ms | PDFium 解析 PDF 与首帧 |

**内存**（历史数据，1.0.9 发布版与 markview，math-100k 打开后静置 3 s，`vmmap`）：
物理内存占用 294 MiB 对 73 MiB。SGV 中 GPU 纹理约 105 MiB（markview 7.5 MiB），
malloc 约 105 MiB（markview 19 MiB），窗口表面 44 MiB。PDF 光栅缓存在流式模式下
上限为 256 MiB（`pdf_canvas_view.dart` 的 `maxImageBytesCachedOnMemory`）；1 MiB
文档的常驻内存达到 546 MiB，未逐项归因。

## 6. 据此修复的问题

| 提交 | 问题 | 效果 |
| --- | --- | --- |
| `75d93e6` | 首次编译时对约 190 个匹配的系统字体逐个计算 `FontInfo`（遍历 cmap 算覆盖表），约 40 ms | 字体元数据缓存到 `font_index.json`，字体在 Typst 首次用到时才解析；字体初始化 43 → 17 ms。72 个 PDF 与修复前逐字节一致 |
| `597d726` | macOS 启动时文件从 argv 和 `openFiles` 事件各送来一次（路径写法分别是 `/private/tmp` 与 `/tmp`），第一次编译的结果被丢弃后重编 | 同一文件且内容未变时跳过；每次打开只编译一次 |

两处合计：命令行导出 10 KiB 从 70 ms（1.0.9 发布版）降到 44～47 ms；桌面端打开快
25～85 ms。

## 7. 未处理的项

- **首次用到 PingFang 的 16 ms**：Typst 内部对字体整体数据求哈希。绕开它需要把单个字体
  从 `.ttc` 中拆出来，改动较大，收益仅此一项。
- **每次启动的 fontdb 扫描约 11 ms**：省掉它需要自行维护各平台的字体目录，Linux 上还
  涉及 fontconfig 配置。
- **Flutter 启动约 150 ms**：框架层面的固定开销。
- **无障碍标签（tagged PDF）**：关闭只省约 5 ms，但文件会显著变小（uprose-1m
  1486 → 956 KiB）。属于功能取舍。
- **`lang: "zh"` 全局生效**：英文单词永远不会断字。目前 `justify: false` 时影响不大；
  若以后启用两端对齐，需要按段落设置语言，开销见第 4 节“再加 `lang: "en"`”一列。

## 8. 复现方法

```sh
# 1. markview（与本仓库并列检出）
git clone https://github.com/szdytom/markview ../markview
(cd ../markview && cargo build --release)

# 2. 测试文件
python3 scripts/markview-compare/fixtures.py --markview ../markview --out /tmp/fx

# 3. 命令行导出（A4）
make build-core
python3 scripts/markview-compare/export_bench.py --fixtures /tmp/fx \
  --markview ../markview/target/release/markview --sgv core/target/release/sgv-cli
# markview 自报的复用段落数
../markview/target/release/markview pdf /tmp/fx/uprose-1m.md -o /tmp/mv.pdf --offline

# 4. SGV 分段、一次性初始化、两端对齐变体
cd core
cargo run --release --example stage_probe -- first-use
cargo run --release --example stage_probe -- stages /tmp/fx/uprose-1m.md   # 每个文件单独一个进程
cargo run --release --example stage_probe -- variants /tmp/fx/uprose-100k.md /tmp/fx/uprose-1m.md
cd ..

# 5. 桌面端打开（Profile 构建；从 core/ 启动，使其加载 core/target/release 下的引擎）
(cd ui && flutter build macos --profile)
python3 scripts/markview-compare/gui_open_bench.py --fixtures /tmp/fx \
  --app "after=ui/build/macos/Build/Products/Profile/SuperGoodViewer.app/Contents/MacOS/SuperGoodViewer@core"
for f in prose-10k prose-1m; do
  RUST_LOG=info ../markview/target/release/markview smoke /tmp/fx/$f.md \
    --width 1200 --height 800 --offline 2>&1 | grep 'process entry'
done
```

在非 release 构建中，应用会先在工作目录下的 `test/`、`ui/test/` 等位置查找
`libsogood_core.dylib`；从仓库根目录启动会加载 `ui/test/` 里可能已过期的副本。
`gui_open_bench.py` 的 `@CWD` 就是用来指定加载哪一份引擎的。要对比修复前后，
可把旧版 Profile 应用和旧版引擎放在
`<dir>/core/target/release/libsogood_core.dylib`，再以 `before=<旧应用>@<dir>/cwd`
的形式传入（`<dir>/cwd` 需存在）。
