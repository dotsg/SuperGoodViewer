# SuperGoodViewer Architecture & Technical Design

SuperGoodViewer is a high-performance, read-only Markdown desktop viewer designed for users who demand publication-grade typography, zero-drift cross-platform consistency, and instant PDF export.

---

## 1. High-Level Design Architecture

```
+──────────────────────────────────────────────────────────────────────────+
|                    UI Shell (Flutter Desktop - macOS/Win/Linux)          |
|                                                                          |
|  - Modern Cupertino/Metal Desktop UI (Impeller Rendering Engine)         |
|  - Collapsible Sidebar: TOC, File Management, Reading Preferences        |
|  - Top Bar: Fluid / Paged Toggle, Light / Dark Toggle, 0ms PDF Export    |
|  - PDF Viewport: pdfrx (Google PDFium C++ Subpixel Antialiased Engine)   |
|  - Scroll Position Memory (Scroll Ratio Retention across reloads)        |
+────────────────────────────────────┬─────────────────────────────────────+
                                     │ C-ABI FFI (dart:ffi / Zero IPC)
                                     │ (markdown_cstr, title, dir, options)
                                     │ ◄── returns *mut SogoodBuffer (PDF)
                                     ▼
+──────────────────────────────────────────────────────────────────────────+
|                    Core Engine (Rust Embedded `sogood_core`)             |
|                                                                          |
|  1. Markdown & AST Transpiler (pulldown-cmark)                           |
|     ├── LaTeX Math Conversion (mitex TeX-to-Typst AST mapper)            |
|     ├── Mermaid Vector Engine (mermaid-rs-renderer + SHA-256 Cache)      |
|     └── VFS Asset Resolver (resolves ./images/ against doc directory)    |
|                                                                          |
|  2. Typst In-Memory Compiler (`typst` & `typst-pdf` crates)              |
|     ├── MemoryWorld Implementation (implements `typst::World` trait)     |
|     ├── GlobalFontStore (OnceLock singleton caching embedded+system)     |
|     └── In-memory compilation: Document -> Vec<u8> PDF binary stream     |
+──────────────────────────────────────────────────────────────────────────+
```

---

## 2. Memory Management & FFI Contract

### 2.1 C-ABI Buffer Protocol
Data is transferred between Dart and Rust without TCP sockets or child process pipes.
The buffer is defined as:
```rust
#[repr(C)]
pub struct SogoodBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}
```

1. **Allocation**: When Markdown is compiled, Rust creates a `Vec<u8>` containing the PDF binary stream, boxes it, and transfers ownership to a raw `*mut SogoodBuffer` pointer.
2. **Transfer to Dart**: Dart reads the byte stream directly into a managed `Uint8List` via `buffer.data.asTypedList(buffer.len)`.
3. **Deallocation**: Dart calls `sogood_free_buffer(bufferPtr)`, ensuring memory is reclaimed by Rust using `Vec::from_raw_parts` without leaks.

### 2.2 Global Font Store & Memory Optimization
Scanning and parsing system fonts on every keypress or reload can take 300ms–800ms. SuperGoodViewer uses a thread-safe `OnceLock<GlobalFontStore>`:
- Embedded Typst fonts (New Computer Modern, DejaVu, Latin Modern Math, etc.) and primary system fonts (PingFang SC, Microsoft YaHei, Inter, Segoe UI) are indexed **once** at initial launch.
- **TTC (TrueType Collection) In-Memory Deduplication**: TTC font files containing multiple faces (such as macOS `PingFang.ttc` 74.6MB with 6 faces) are read only once and deduplicated via an in-memory `PathBuf -> Arc<Bytes>` cache, so 141 matched faces read only 48 distinct files instead of re-allocating per face.
- **Memory-mapped font files**: those 48 files are mapped with `memmap2` rather than read onto the heap, so font bytes are clean file-backed pages — only pages actually touched during shaping become resident, and the kernel can evict them under pressure. Measured in isolation, loading 158 fonts costs **11 MB** of `phys_footprint` versus **548 MB** with `fs::read`. Whole-app resident footprint dropped from ~695 MB to **~200 MB** (measured 2026-09-20 with `test.md` loaded). See [BENCHMARKS.md](BENCHMARKS.md) for the measured attribution.
- Subsequent compilations reference the cached `LazyHash<FontBook>`. Re-rendering an already-compiled document (theme switch, font-size change) costs **0.5 ms ~ 20 ms** depending on document size; a document opened for the first time in a fresh process costs **~1 ms (short note) to ~292 ms (100 KB book)**. See [BENCHMARKS.md](BENCHMARKS.md) for the cold/warm split.

See [BENCHMARKS.md](BENCHMARKS.md) for detailed performance metrics and comparison with Obsidian, Typora, MarkText, and VS Code.

---

## 3. Mermaid & Asset Resolution

### 3.1 Headless Vector Mermaid Rendering
Official Mermaid CLI spawns Puppeteer/Chromium, consuming hundreds of megabytes. SuperGoodViewer integrates `mermaid-rs-renderer`:
- Parses diagram AST directly in Rust.
- Calculates node geometry and edge paths.
- Emits clean SVG vector strings without browser dependencies.
- **SHA-256 Cache**: Before rendering, the diagram's content is hashed. If the diagram has already been rendered in the current session, the cached SVG bytes are reused instantly.
- **Graceful Fallback**: If invalid Mermaid syntax is provided, the engine generates an informative warning block instead of breaking the entire document compilation.

### 3.2 Relative Asset Resolution
When a document references `./images/chart.png`:
- The Rust engine mounts the source file's directory as the virtual file root.
- The `MemoryWorld` trait interceptor resolves file lookups against the local file system or in-memory virtual files (for dynamic Mermaid SVGs).

---

## 4. Dual-Mode Layout Engine

1. **Fluid Screen Mode (`fluid`)**:
   - `page(width: viewport_width, height: auto, margin: 24pt)`
   - Eliminates page break gaps and headers/footers.
   - Creates a seamless, responsive reading scroll experience tailored to the user's window size.
2. **Print / Paged Mode (`paged`)**:
   - `page(width: 595.28pt, height: 841.89pt, margin: ...)`
   - Full A4 paginated layout with dynamic headers, footers (`counter(page)`), and orphan/widow line control.
   - Provides 100% WYSIWYG match between screen and physical paper export.

---

## 5. Desktop Runner & Platform Integration

### 5.1 Native Window Management (`com.sogoodviewer.window`)
Desktop platforms require distinct native window management strategies to maintain fluid desktop integration:
- **macOS**: AppKit native toolbar styling, seamless full-screen zoom, and a 78px traffic-light button safe zone.
- **Windows**: Win32 native methods implemented in C++:
  - `startDragging`: Intercepts custom title bar drag events using `ReleaseCapture()` and `SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0)`.
  - `toggleFullScreen`: Toggles borderless immersion fullscreen mode (with F11 shortcut support) by saving and restoring `WINDOWPLACEMENT` and window styles.
  - `zoom`: Toggles between `SW_MAXIMIZE` and `SW_RESTORE`.

### 5.2 Single-Instance Enforcement & IPC Document Forwarding
To avoid opening multiple instances when clicking markdown files or executing CLI commands:
- **Windows**:
  - `CreateMutex(nullptr, TRUE, L"SuperGoodViewer_SingleInstance_Mutex")` guards against multiple process spawns.
  - When a secondary process is invoked with target files, it locates the running window via `FindWindow` and forwards the target path using Win32 `WM_COPYDATA` (magic identifier `0x53475631`).
  - The primary instance brings its window to the foreground (`SetForegroundWindow`, `SW_RESTORE`) and triggers `onOpenFile` inside Flutter via method channels.
  - Initial startup arguments are resolved via `getInitialFile`.

### 5.3 Command Line Integration (`sgv` CLI)
SuperGoodViewer ships with unified `sgv` CLI tooling across platforms:
- **macOS**: Generates a launcher shell script and establishes a symlink in `/usr/local/bin/sgv` via AppleScript privilege escalation if required.
- **Windows**: Deploys lightweight wrappers `sgv.cmd` and `sgv.ps1` to `%LOCALAPPDATA%\Microsoft\WindowsApps`. Because this directory is part of the default user `PATH` in modern Windows, installation requires zero UAC elevation and is immediately active in CMD, PowerShell, and Windows Terminal.

The headless exporter behind those wrappers, `sgv-cli` (crate `core/cli`), does argument
parsing, export planning and file I/O only — it loads the very `libsogood_core` the app
loads, through the same C ABI and the same executable-relative search order, rather than
linking the engine statically. Static linking put a second copy of Typst and the 17 embedded
fonts into every bundle: **46 MB of duplication, now 0.5 MB** (see
[BENCHMARKS.md](BENCHMARKS.md) §4). `SGV_CORE_LIB` overrides the engine path and is
authoritative — if it is set and cannot be loaded, the CLI fails instead of silently falling
back to a different engine.

### 5.4 Dual-Architecture Support (x64 & ARM64)
SuperGoodViewer targets both primary architectures on Windows:
- **x64**: Optimized for standard Intel and AMD 64-bit systems.
- **ARM64**: Cross-compiled natively using `aarch64-pc-windows-msvc` (Rust Core) and `windows-arm64` (Flutter Engine & Google PDFium), providing 100% native execution on Qualcomm Snapdragon X Elite/Plus and Microsoft Surface Pro devices with zero emulation overhead.


## 6. Scrolling and raster readiness

The application vendors pdfrx 2.6.1 with stable high-resolution tile caching, directional
prefetch and a visible-raster completion callback. See [SCROLL_RENDERING.md](SCROLL_RENDERING.md)
for cache budgets, invalidation, double buffering and validation, and
[the dependency patch log](../ui/packages/pdfrx/PATCHES.md) for upstream maintenance.
