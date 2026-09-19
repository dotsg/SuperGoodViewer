use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use parking_lot::RwLock;

use std::sync::atomic::{AtomicUsize, Ordering};
use crate::compiler::engine::RenderOptions;
use crate::compile_markdown_to_pdf_result;

#[repr(C)]
pub struct SogoodBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

static LAST_ERROR: RwLock<Option<String>> = RwLock::new(None);
static LAST_DEGRADED_COUNT: AtomicUsize = AtomicUsize::new(0);
static LAST_DEGRADED_EQUATIONS: RwLock<Vec<String>> = RwLock::new(Vec::new());

fn set_last_error(err: String) {
    let mut guard = LAST_ERROR.write();
    *guard = Some(err);
}

fn clear_last_error() {
    let mut guard = LAST_ERROR.write();
    *guard = None;
}

fn set_last_degraded(count: usize, equations: Vec<String>) {
    LAST_DEGRADED_COUNT.store(count, Ordering::SeqCst);
    let mut guard = LAST_DEGRADED_EQUATIONS.write();
    *guard = equations;
}

fn clear_last_degraded() {
    LAST_DEGRADED_COUNT.store(0, Ordering::SeqCst);
    let mut guard = LAST_DEGRADED_EQUATIONS.write();
    guard.clear();
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_get_version() -> *const c_char {
    static VERSION: &str = concat!(env!("CARGO_PKG_VERSION"), "\0");
    VERSION.as_ptr() as *const c_char
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_get_last_error() -> *mut c_char {
    let guard = LAST_ERROR.read();
    match &*guard {
        Some(msg) => match CString::new(msg.as_str()) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_get_last_degraded_count() -> usize {
    LAST_DEGRADED_COUNT.load(Ordering::SeqCst)
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_get_last_degraded_equations_json() -> *mut c_char {
    let guard = LAST_DEGRADED_EQUATIONS.read();
    if guard.is_empty() {
        return std::ptr::null_mut();
    }
    match serde_json::to_string(&*guard) {
        Ok(json) => match CString::new(json) {
            Ok(c_str) => c_str.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_free_buffer(buf: *mut SogoodBuffer) {
    if !buf.is_null() {
        unsafe {
            let boxed = Box::from_raw(buf);
            if !boxed.data.is_null() && boxed.capacity > 0 {
                let _ = Vec::from_raw_parts(boxed.data, boxed.len, boxed.capacity);
            }
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_compile_markdown(
    markdown_ptr: *const c_char,
    title_ptr: *const c_char,
    doc_dir_ptr: *const c_char,
    options_json_ptr: *const c_char,
) -> *mut SogoodBuffer {
    std::panic::catch_unwind(|| {
        clear_last_error();
        clear_last_degraded();

        if markdown_ptr.is_null() {
            set_last_error("Markdown pointer is null".to_string());
            return std::ptr::null_mut();
        }

        let markdown = match unsafe { CStr::from_ptr(markdown_ptr) }.to_str() {
            Ok(s) => s,
            Err(e) => {
                set_last_error(format!("Invalid UTF-8 in markdown string: {}", e));
                return std::ptr::null_mut();
            }
        };

        let title = if title_ptr.is_null() {
            "Document"
        } else {
            unsafe { CStr::from_ptr(title_ptr) }.to_str().unwrap_or("Document")
        };

        let doc_dir = if doc_dir_ptr.is_null() {
            "."
        } else {
            unsafe { CStr::from_ptr(doc_dir_ptr) }.to_str().unwrap_or(".")
        };

        let options: RenderOptions = if !options_json_ptr.is_null() {
            if let Ok(json_str) = unsafe { CStr::from_ptr(options_json_ptr) }.to_str() {
                serde_json::from_str(json_str).unwrap_or_default()
            } else {
                RenderOptions::default()
            }
        } else {
            RenderOptions::default()
        };

        match compile_markdown_to_pdf_result(markdown, title, Path::new(doc_dir), &options) {
            Ok(result) => {
                if result.degraded_equation_count > 0 {
                    set_last_degraded(result.degraded_equation_count, result.degraded_equations);
                }
                let mut buf = result.pdf_bytes.into_boxed_slice();
                let data = buf.as_mut_ptr();
                let len = buf.len();
                let capacity = len;
                std::mem::forget(buf);

                Box::into_raw(Box::new(SogoodBuffer { data, len, capacity }))
            }
            Err(e) => {
                set_last_error(e.to_string());
                std::ptr::null_mut()
            }
        }
    })
    .unwrap_or_else(|_| {
        set_last_error("Internal panic caught in sogood_compile_markdown".to_string());
        std::ptr::null_mut()
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_detect_fonts() -> *mut SogoodBuffer {
    std::panic::catch_unwind(|| {
        let report = crate::compiler::world::detect_font_capabilities();
        let json_bytes = serde_json::to_vec(&report).unwrap_or_else(|_| b"{}".to_vec());
        let mut boxed_slice = json_bytes.into_boxed_slice();
        let data = boxed_slice.as_mut_ptr();
        let len = boxed_slice.len();
        let capacity = len;
        std::mem::forget(boxed_slice);

        Box::into_raw(Box::new(SogoodBuffer { data, len, capacity }))
    })
    .unwrap_or_else(|_| std::ptr::null_mut())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_c_api_version() {
        let version_ptr = sogood_get_version();
        let version_cstr = unsafe { CStr::from_ptr(version_ptr) };
        assert_eq!(version_cstr.to_str().unwrap(), env!("CARGO_PKG_VERSION"));
    }

    #[test]
    fn test_c_api_compile() {
        let md = CString::new("# C-API Test\n\nHello from C ABI!").unwrap();
        let title = CString::new("Title").unwrap();
        let dir = CString::new(".").unwrap();
        let opts = CString::new(r#"{"mode":"fluid","theme":"light","viewport_width":800.0}"#).unwrap();

        let buffer_ptr = sogood_compile_markdown(
            md.as_ptr(),
            title.as_ptr(),
            dir.as_ptr(),
            opts.as_ptr(),
        );

        assert!(!buffer_ptr.is_null());
        unsafe {
            let buf = &*buffer_ptr;
            assert!(buf.len > 100);
            let slice = std::slice::from_raw_parts(buf.data, buf.len);
            assert!(slice.starts_with(b"%PDF-"));
            sogood_free_buffer(buffer_ptr);
        }
    }

    #[test]
    fn test_c_api_detect_fonts() {
        let buffer_ptr = sogood_detect_fonts();
        assert!(!buffer_ptr.is_null());
        unsafe {
            let buf = &*buffer_ptr;
            assert!(buf.len > 10);
            let slice = std::slice::from_raw_parts(buf.data, buf.len);
            let json_str = std::str::from_utf8(slice).unwrap();
            assert!(json_str.contains("recommended_font_name"));
            assert!(json_str.contains("maple_mono_installed"));
            sogood_free_buffer(buffer_ptr);
        }
    }

    #[test]
    fn test_c_api_degraded_equations_reporting() {
        let md = CString::new("# C-API Degraded Test\n\n$$\\brokencommand{xyz}$$\n$$\\alsobroken{123}$$\n").unwrap();
        let title = CString::new("Degradation").unwrap();
        let dir = CString::new(".").unwrap();
        let opts = CString::new(r#"{"mode":"fluid"}"#).unwrap();

        let buffer_ptr = sogood_compile_markdown(
            md.as_ptr(),
            title.as_ptr(),
            dir.as_ptr(),
            opts.as_ptr(),
        );

        assert!(!buffer_ptr.is_null());
        sogood_free_buffer(buffer_ptr);

        let degraded_count = sogood_get_last_degraded_count();
        assert_eq!(degraded_count, 2);

        let json_ptr = sogood_get_last_degraded_equations_json();
        assert!(!json_ptr.is_null());
        unsafe {
            let json_cstr = CStr::from_ptr(json_ptr);
            let json_str = json_cstr.to_str().unwrap();
            assert!(json_str.contains(r"\brokencommand{xyz}"));
            assert!(json_str.contains(r"\alsobroken{123}"));
            sogood_free_string(json_ptr);
        }
    }
}

