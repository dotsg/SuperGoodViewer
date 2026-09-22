//! Loads the `sogood_core` shared engine at runtime and exposes the one call
//! this CLI needs.
//!
//! The engine is the same shared library the desktop app loads, so it is not
//! linked into this binary: shipping it statically would duplicate Typst and the
//! embedded fonts (~46 MB) inside every bundle. The search order below mirrors
//! `ui/lib/bridge/native_engine.dart` — paths next to the executable first, so a
//! packaged build always runs the engine it shipped with, never a stale copy that
//! happens to sit in the current working directory.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::{Path, PathBuf};

use libloading::{Library, Symbol};

#[repr(C)]
struct SogoodBuffer {
    data: *mut u8,
    len: usize,
    capacity: usize,
}

type CompileMarkdownFn = unsafe extern "C" fn(
    *const c_char,
    *const c_char,
    *const c_char,
    *const c_char,
) -> *mut SogoodBuffer;
type FreeBufferFn = unsafe extern "C" fn(*mut SogoodBuffer);
type GetLastErrorFn = unsafe extern "C" fn() -> *mut c_char;
type FreeStringFn = unsafe extern "C" fn(*mut c_char);
type GetVersionFn = unsafe extern "C" fn() -> *const c_char;
type GetDegradedCountFn = unsafe extern "C" fn() -> usize;

/// The platform's file name for the engine.
const fn library_file_name() -> &'static str {
    if cfg!(target_os = "windows") {
        "sogood_core.dll"
    } else if cfg!(target_os = "macos") {
        "libsogood_core.dylib"
    } else {
        "libsogood_core.so"
    }
}

/// A successful compilation: the PDF bytes plus how many equations had to fall
/// back to degraded styling.
pub struct Compilation {
    pub pdf_bytes: Vec<u8>,
    pub degraded_equation_count: usize,
}

pub struct CoreEngine {
    library: Library,
    path: PathBuf,
}

impl CoreEngine {
    /// Opens the engine, reporting every path that was tried when it is missing.
    ///
    /// `SGV_CORE_LIB` is authoritative: if it is set, no other path is tried, so
    /// an override can never silently fall back to a different engine.
    pub fn load() -> Result<Self, String> {
        if let Some(explicit) = std::env::var_os("SGV_CORE_LIB") {
            let path = PathBuf::from(explicit);
            return match unsafe { Library::new(&path) } {
                Ok(library) => Ok(Self { library, path }),
                Err(e) => Err(format!(
                    "SGV_CORE_LIB points at '{}', which could not be loaded: {e}",
                    path.display()
                )),
            };
        }

        let candidates = candidate_paths();
        for path in &candidates {
            // SAFETY: loading a shared library runs its initializers; this is the
            // same engine the app itself loads.
            if let Ok(library) = unsafe { Library::new(path) } {
                return Ok(Self { library, path: path.clone() });
            }
        }

        // Last resort: let the platform loader search its own paths.
        let bare = library_file_name();
        if let Ok(library) = unsafe { Library::new(bare) } {
            return Ok(Self { library, path: PathBuf::from(bare) });
        }

        let tried: Vec<String> = candidates.iter().map(|p| format!("  {}", p.display())).collect();
        Err(format!(
            "cannot find the SuperGoodViewer engine ({bare}).\nLooked in:\n{}\n\
             Set SGV_CORE_LIB to the library path if it lives somewhere else.",
            tried.join("\n")
        ))
    }

    /// Path the engine was actually loaded from; shown by `--version`.
    pub fn path(&self) -> &Path {
        &self.path
    }

    pub fn version(&self) -> Option<String> {
        let symbol: Symbol<GetVersionFn> = unsafe { self.library.get(b"sogood_get_version").ok()? };
        let ptr = unsafe { symbol() };
        if ptr.is_null() {
            return None;
        }
        Some(unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned())
    }

    /// Compiles Markdown to PDF bytes through the engine's C ABI.
    ///
    /// `options_json` is a `RenderOptions` object; every field is optional on the
    /// engine side, so the CLI only sends what it was asked for.
    pub fn compile_markdown(
        &self,
        markdown: &str,
        title: &str,
        doc_dir: &Path,
        options_json: &str,
    ) -> Result<Compilation, String> {
        let markdown_c = to_c_string(markdown, "markdown")?;
        let title_c = to_c_string(title, "title")?;
        let doc_dir_c = to_c_string(&doc_dir.to_string_lossy(), "document directory")?;
        let options_c = to_c_string(options_json, "render options")?;

        let compile: Symbol<CompileMarkdownFn> = unsafe {
            self.library
                .get(b"sogood_compile_markdown")
                .map_err(|e| format!("engine is missing sogood_compile_markdown: {e}"))?
        };
        let free_buffer: Symbol<FreeBufferFn> = unsafe {
            self.library
                .get(b"sogood_free_buffer")
                .map_err(|e| format!("engine is missing sogood_free_buffer: {e}"))?
        };

        let buffer = unsafe {
            compile(
                markdown_c.as_ptr(),
                title_c.as_ptr(),
                doc_dir_c.as_ptr(),
                options_c.as_ptr(),
            )
        };

        if buffer.is_null() {
            return Err(self.last_error().unwrap_or_else(|| "unknown engine error".to_string()));
        }

        // Copy out before handing the buffer back: the bytes belong to the engine's
        // allocator, so they must be freed through the engine, not by Rust here.
        let pdf_bytes = unsafe {
            let buf = &*buffer;
            std::slice::from_raw_parts(buf.data, buf.len).to_vec()
        };
        unsafe { free_buffer(buffer) };

        let degraded_equation_count = self.degraded_equation_count();

        Ok(Compilation { pdf_bytes, degraded_equation_count })
    }

    fn degraded_equation_count(&self) -> usize {
        let Ok(symbol) = (unsafe {
            self.library.get::<GetDegradedCountFn>(b"sogood_get_last_degraded_count")
        }) else {
            return 0;
        };
        unsafe { symbol() }
    }

    fn last_error(&self) -> Option<String> {
        let get_last_error: Symbol<GetLastErrorFn> =
            unsafe { self.library.get(b"sogood_get_last_error").ok()? };
        let free_string: Symbol<FreeStringFn> =
            unsafe { self.library.get(b"sogood_free_string").ok()? };

        let ptr = unsafe { get_last_error() };
        if ptr.is_null() {
            return None;
        }
        let message = unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned();
        unsafe { free_string(ptr) };
        Some(message)
    }
}

fn to_c_string(value: &str, what: &str) -> Result<CString, String> {
    CString::new(value).map_err(|_| format!("{what} contains an interior NUL byte"))
}

/// Where to look for the engine, most specific first.
fn candidate_paths() -> Vec<PathBuf> {
    let name = library_file_name();
    let mut candidates = Vec::new();

    if let Ok(exe) = std::env::current_exe()
        && let Some(dir) = exe.parent()
    {
        // Windows bundle: engine sits beside the executable.
        candidates.push(dir.join(name));
        // Linux bundle: bin/sgv-cli -> lib/libsogood_core.so
        candidates.push(dir.join("..").join("lib").join(name));
        // macOS bundle: Contents/Resources/bin/sgv-cli -> Contents/Frameworks/
        candidates.push(dir.join("..").join("..").join("Frameworks").join(name));
        candidates.push(dir.join("..").join("Frameworks").join(name));
    }

    // Development: running straight out of the cargo target directory.
    for prefix in ["target/release", "target/debug", "core/target/release", "core/target/debug"] {
        candidates.push(PathBuf::from(prefix).join(name));
        candidates.push(PathBuf::from("..").join(prefix).join(name));
    }

    candidates
}
