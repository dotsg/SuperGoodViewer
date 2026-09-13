# SuperGoodViewer (UI Frontend)

This directory contains the desktop Flutter application for **SuperGoodViewer (超好读)**.

## Overview

The Flutter frontend acts as a high-performance shell over the embedded Rust core (`sogood_core`):
- **Document Viewport**: Uses `pdfrx` and Google's C++ PDFium library to render vector-sharp PDF page buffers in real-time.
- **Native Method Channels**:
  - `com.sogoodviewer.window`: Controls borderless fullscreen, custom titlebar window dragging, and zoom.
  - `com.sogoodviewer.app`: Manages single-instance IPC (`WM_COPYDATA` / `onOpenFile`) and CLI script installation (`sgv.cmd` / `sgv.ps1` / macOS symlinks).
- **Embedded Engine FFI**: Connects to `sogood_core.dll` (Windows) / `libsogood_core.dylib` (macOS) via `dart:ffi`.

## Build & Test Commands

From repo root:
```bash
# Run unit tests and static analysis
make test-app

# Run desktop app in debug mode
make run-macos     # macOS
make run-windows   # Windows

# Build release desktop app
make build-windows       # Windows x64
make build-windows-arm64 # Windows ARM64
```
