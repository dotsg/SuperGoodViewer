# Benchmark corpus (frozen)

These five files are the **inputs** to `core/src/bin/benchmark.rs` (`make bench`).
They are data, not documentation — **do not edit, reformat or "improve" them.**
Changing a byte here changes every number in [../../BENCHMARKS.md](../../BENCHMARKS.md)
and makes runs incomparable.

| 文件               |    大小 | 内容                                                                   |
| ------------------ | ------: | ---------------------------------------------------------------------- |
| `01-note.md`       |   137 B | 最小样本：标题、列表、一个行内公式                                     |
| `02-readme.md`     | 28.2 KB | 项目 README 在 2026-09-20 的快照：徽标、多级表格、引用、emoji          |
| `03-prd.md`        | 20.1 KB | 合成技术规范：6 张各不相同的 Mermaid 图、公式、表格、代码块            |
| `04-book.md`       | 97.8 KB | 合成书稿：20 章，每章含公式、5 列表格、代码块                          |
| `05-real-world.md` | 21.7 KB | 仓库演示文档 `test.md` 在 2026-09-20 的快照：复杂时序图、LaTeX、ASCII 表 |

前身是直接读仓库根目录的 `README.md` 与 `test.md`——这两个文件随时会变，
基准输入也就跟着变（同一轮复测里 README 就变过三次大小）。冻结成快照后，
改仓库文档不再影响基准数字。

需要新增场景时，**加一个新文件**并在 `benchmark.rs` 的 `CORPUS` 表里登记，
不要改动已有文件；同时在 BENCHMARKS.md 里说明新样本是何时、为何加入的。
