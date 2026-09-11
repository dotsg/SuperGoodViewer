use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use parking_lot::RwLock;

use crate::compiler::engine::RenderOptions;
use crate::compile_markdown_to_pdf;

#[repr(C)]
pub struct SogoodBuffer {
    pub data: *mut u8,
    pub len: usize,
    pub capacity: usize,
}

static LAST_ERROR: RwLock<Option<String>> = RwLock::new(None);

fn set_last_error(err: String) {
    let mut guard = LAST_ERROR.write();
    *guard = Some(err);
}

fn clear_last_error() {
    let mut guard = LAST_ERROR.write();
    *guard = None;
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_get_version() -> *const c_char {
    static VERSION: &[u8] = b"0.1.0\0";
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
    clear_last_error();

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

    match compile_markdown_to_pdf(markdown, title, Path::new(doc_dir), &options) {
        Ok(pdf_bytes) => {
            let mut buf = pdf_bytes.into_boxed_slice();
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
}

#[unsafe(no_mangle)]
pub extern "C" fn sogood_detect_fonts() -> *mut SogoodBuffer {
    let report = crate::compiler::world::detect_font_capabilities();
    let json_bytes = serde_json::to_vec(&report).unwrap_or_else(|_| b"{}".to_vec());
    let mut boxed_slice = json_bytes.into_boxed_slice();
    let data = boxed_slice.as_mut_ptr();
    let len = boxed_slice.len();
    let capacity = len;
    std::mem::forget(boxed_slice);

    Box::into_raw(Box::new(SogoodBuffer { data, len, capacity }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_c_api_version() {
        let version_ptr = sogood_get_version();
        let version_cstr = unsafe { CStr::from_ptr(version_ptr) };
        assert_eq!(version_cstr.to_str().unwrap(), "0.1.0");
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
}

