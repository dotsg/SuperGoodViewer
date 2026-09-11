# SoGoodViewer Architecture & Technical Design

SoGoodViewer is a high-performance, read-only Markdown desktop viewer designed for users who demand publication-grade typography, zero-drift cross-platform consistency, and instant PDF export.

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
Scanning and parsing system fonts on every keypress or reload can take 300ms–800ms. SoGoodViewer uses a thread-safe `OnceLock<GlobalFontStore>`:
- Embedded Typst fonts (New Computer Modern, DejaVu, Latin Modern Math, etc.) and primary system fonts (PingFang SC, Microsoft YaHei, Inter, Segoe UI) are indexed **once** at initial launch.
- **TTC (TrueType Collection) In-Memory Deduplication**: TTC font files containing multiple faces (such as macOS `PingFang.ttc` 74.6MB with 6 faces) are read only once and deduplicated via an in-memory `PathBuf -> Arc<Bytes>` cache, so 141 matched faces read only 48 distinct files instead of re-allocating per face.
- **Memory-mapped font files**: those 48 files are mapped with `memmap2` rather than read onto the heap, so font bytes are clean file-backed pages — only pages actually touched during shaping become resident, and the kernel can evict them under pressure. Measured in isolation, loading 158 fonts costs **11 MB** of `phys_footprint` versus **548 MB** with `fs::read`. Whole-app resident footprint dropped from ~695 MB to **~158 MB**. See [BENCHMARKS.md](BENCHMARKS.md) for the measured attribution.
- Subsequent compilations reference the cached `LazyHash<FontBook>`, bringing re-compilation latency down to **0.5ms ~ 5ms**.

See [BENCHMARKS.md](BENCHMARKS.md) for detailed performance metrics and comparison with Obsidian, Typora, MarkText, and VS Code.

---

## 3. Mermaid & Asset Resolution

### 3.1 Headless Vector Mermaid Rendering
Official Mermaid CLI spawns Puppeteer/Chromium, consuming hundreds of megabytes. SoGoodViewer integrates `mermaid-rs-renderer`:
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
