use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::UNIX_EPOCH;

use parking_lot::Mutex;

use crate::{CompileError, RenderOptions};

const OLE2_MAGIC: &[u8; 8] = b"\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1";
const UTF8_BOM: &[u8; 3] = b"\xEF\xBB\xBF";
const UTF16_LE_BOM: &[u8; 2] = b"\xFF\xFE";
const UTF16_BE_BOM: &[u8; 2] = b"\xFE\xFF";
const FLUID_PDF_MAX_PAGE_HEIGHT_PT: f32 = 14_000.0;
const PARSED_DOC_CACHE_CAPACITY: usize = 4;
const MAX_CACHED_WORD_FILE_BYTES: u64 = 16 * 1024 * 1024;

type ParsedDocKey = (PathBuf, u64, u32, u64);
type LoadedFontKey = (PathBuf, u64, u64);

static PARSED_DOC_CACHE: OnceLock<Mutex<Vec<(ParsedDocKey, Arc<wordcraft_doc::Document>)>>> =
    OnceLock::new();
static LOADED_CUSTOM_FONTS: OnceLock<Mutex< std::collections::HashSet<LoadedFontKey>>> =
    OnceLock::new();

/// Rendering backend for parsed [`wordcraft_doc::Document`] models.
///
/// Keeping parsing (`bytes -> wordcraft_doc::Document`) decoupled from rendering
/// allows switching between WordCraft's native 1:1 layout engine (`Native`) and
/// a future Typst-based reflow pipeline without changing FFI or UI callers.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum WordRenderBackend {
    /// Route A: WordCraft native layout (`Print` / `Web` / `Read`) + Krilla PDF export.
    #[default]
    Native,
}

/// Returns true if `path_or_ext` has a supported Microsoft Word file extension
/// (`.docx`, `.doc`, `.docm`, `.dotx`, `.dotm`).
pub fn is_word_extension(path_or_ext: &str) -> bool {
    let trimmed = path_or_ext.trim();
    if trimmed.is_empty() {
        return false;
    }
    let ext = Path::new(trimmed)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or_else(|| trimmed.trim_start_matches('.'));
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "docx" | "doc" | "docm" | "dotx" | "dotm"
    )
}

/// Ensures any custom user fonts downloaded into `<cache_dir>/fonts` are loaded into
/// [`wordcraft_fonts::FontDb::global`] in memory (without setting `user.dir` on disk),
/// automatically picking up fonts downloaded during the current session.
fn sync_custom_user_fonts() {
    let Some(cdir) = crate::compiler::world::custom_fonts_dir() else {
        return;
    };
    let Ok(rd) = std::fs::read_dir(&cdir) else {
        return;
    };
    let lock = LOADED_CUSTOM_FONTS.get_or_init(|| Mutex::new(std::collections::HashSet::new()));
    let mut loaded = lock.lock();
    for entry in rd.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        if !wordcraft_fonts::is_font_file_name(name) {
            continue;
        }
        let Ok(meta) = entry.metadata() else {
            continue;
        };
        let mtime_secs = meta
            .modified()
            .ok()
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_secs());
        let key = (path.clone(), meta.len(), mtime_secs);
        if loaded.contains(&key) {
            continue;
        }
        if let Ok(bytes) = std::fs::read(&path) {
            let _ = wordcraft_fonts::FontDb::global().install_font(name, &bytes);
            loaded.insert(key);
        }
    }
}

fn decode_utf16_xml(bytes: &[u8]) -> Option<Vec<u8>> {
    if bytes.len() < 4 {
        return None;
    }
    if bytes.starts_with(UTF16_LE_BOM) {
        let units: Vec<u16> = bytes[2..]
            .chunks_exact(2)
            .map(|c| u16::from_le_bytes([c[0], c[1]]))
            .collect();
        let text = String::from_utf16(&units).ok()?;
        if text.trim_start().starts_with('<') {
            return Some(text.into_bytes());
        }
    } else if bytes.starts_with(UTF16_BE_BOM) {
        let units: Vec<u16> = bytes[2..]
            .chunks_exact(2)
            .map(|c| u16::from_be_bytes([c[0], c[1]]))
            .collect();
        let text = String::from_utf16(&units).ok()?;
        if text.trim_start().starts_with('<') {
            return Some(text.into_bytes());
        }
    }
    None
}

/// Parses raw Word document bytes (`.docx`, `.docm`, `.dotx`, `.dotm`, `.doc`, or Word XML)
/// into a unified [`wordcraft_doc::Document`] IR.
pub fn parse_word_bytes(bytes: &[u8]) -> Result<wordcraft_doc::Document, CompileError> {
    if bytes.is_empty() {
        return Err(CompileError::Word(
            "Word document file is empty (0 bytes)".to_string(),
        ));
    }

    if bytes.starts_with(OLE2_MAGIC) {
        if wordcraft_docx::is_encrypted(bytes) {
            return wordcraft_docx::read(bytes).map_err(|e| {
                CompileError::Word(format!("Failed to read encrypted DOCX document: {e}"))
            });
        }
        match wordcraft_docbin::read(bytes) {
            Ok(doc) => return Ok(doc),
            Err(docbin_err) => match wordcraft_docx::read(bytes) {
                Ok(doc) => return Ok(doc),
                Err(docx_err) => {
                    return Err(CompileError::Word(format!(
                        "Not a valid Word binary (.doc) document: {docbin_err} (docx fallback: {docx_err})"
                    )));
                }
            },
        }
    }

    if let Some(utf8_xml) = decode_utf16_xml(bytes)
        && let Ok(doc) = wordcraft_docx::read_xml(&utf8_xml)
    {
        return Ok(doc);
    }

    let without_bom = bytes.strip_prefix(UTF8_BOM).unwrap_or(bytes);
    let trimmed_ascii = without_bom
        .iter()
        .position(|b| !b.is_ascii_whitespace())
        .map_or(&[][..], |idx| &without_bom[idx..]);

    if trimmed_ascii.starts_with(b"{\\rtf") {
        return Err(CompileError::Word(
            "RTF (.rtf) document saved with a Word extension is not supported".to_string(),
        ));
    }

    if trimmed_ascii.starts_with(b"<")
        && let Ok(doc) = wordcraft_docx::read_xml(without_bom)
    {
        return Ok(doc);
    }

    wordcraft_docx::read(bytes).map_err(|e| {
        CompileError::Word(format!(
            "Not a valid Word (.docx) document: {e}"
        ))
    })
}

/// Reads and parses a Word file from disk with a bounded in-memory LRU cache keyed by
/// `(canonical_path, mtime_secs, mtime_nanos, size)`, so toggling between Paged and Fluid modes
/// or resizing the Fluid viewport does not re-parse the file.
pub fn parse_word_file_cached(path: &Path) -> Result<Arc<wordcraft_doc::Document>, CompileError> {
    let meta = std::fs::metadata(path).map_err(|e| {
        CompileError::Word(format!(
            "Failed to stat Word file '{}': {}",
            path.display(),
            e
        ))
    })?;
    let mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .unwrap_or_default();
    let canonical_path = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    let file_size = meta.len();
    let key: ParsedDocKey = (
        canonical_path,
        mtime.as_secs(),
        mtime.subsec_nanos(),
        file_size,
    );

    let cache_lock = PARSED_DOC_CACHE.get_or_init(|| Mutex::new(Vec::new()));
    if file_size <= MAX_CACHED_WORD_FILE_BYTES {
        let mut cache = cache_lock.lock();
        if let Some(pos) = cache.iter().position(|(k, _)| *k == key) {
            let entry = cache.remove(pos);
            let doc = entry.1.clone();
            cache.push(entry);
            return Ok(doc);
        }
    }

    let bytes = std::fs::read(path).map_err(|e| {
        CompileError::Word(format!(
            "Failed to read Word file '{}': {}",
            path.display(),
            e
        ))
    })?;
    let doc = Arc::new(parse_word_bytes(&bytes)?);

    if file_size <= MAX_CACHED_WORD_FILE_BYTES {
        let mut cache = cache_lock.lock();
        if cache.len() >= PARSED_DOC_CACHE_CAPACITY {
            cache.remove(0);
        }
        cache.push((key, doc.clone()));
    }

    Ok(doc)
}

/// Renders a parsed [`wordcraft_doc::Document`] to PDF bytes using the selected backend.
pub fn render_word_document_to_pdf(
    doc: &wordcraft_doc::Document,
    title: &str,
    file_path: Option<&Path>,
    options: &RenderOptions,
    backend: WordRenderBackend,
) -> Result<Vec<u8>, CompileError> {
    match backend {
        WordRenderBackend::Native => render_word_native_pdf(doc, title, file_path, options),
    }
}

fn render_word_native_pdf(
    doc: &wordcraft_doc::Document,
    title: &str,
    file_path: Option<&Path>,
    options: &RenderOptions,
) -> Result<Vec<u8>, CompileError> {
    sync_custom_user_fonts();

    let filename: Option<Arc<str>> = file_path
        .and_then(|p| p.file_name())
        .and_then(|n| n.to_str())
        .map(Arc::from);
    let filepath: Option<Arc<str>> = file_path.and_then(|p| p.to_str()).map(Arc::from);

    let mut cache = wordcraft_layout::LayoutCache::new();
    let lay = if options.mode == "fluid" {
        let web_width = if options.viewport_width > 0.0 {
            options.viewport_width.clamp(240.0, 2400.0)
        } else {
            595.28
        };
        let mut lo = wordcraft_layout::LayoutOptions {
            view: wordcraft_layout::ViewMode::Web,
            web_width,
            hide_deleted: true,
            filename,
            filepath,
            ..Default::default()
        };
        let web_layout = wordcraft_layout::layout(doc, &mut cache, &lo);
        if web_layout
            .pages
            .iter()
            .any(|p| p.h > FLUID_PDF_MAX_PAGE_HEIGHT_PT)
        {
            lo.view = wordcraft_layout::ViewMode::Read;
            lo.read_height = FLUID_PDF_MAX_PAGE_HEIGHT_PT;
            wordcraft_layout::layout(doc, &mut cache, &lo)
        } else {
            web_layout
        }
    } else {
        let lo = wordcraft_layout::LayoutOptions {
            view: wordcraft_layout::ViewMode::Print,
            hide_deleted: true,
            filename,
            filepath,
            ..Default::default()
        };
        wordcraft_layout::layout(doc, &mut cache, &lo)
    };

    let has_doc_title = !doc.core.title.trim().is_empty();
    let pdf_opts = wordcraft_pdf::PdfOptions {
        title: (!has_doc_title && !title.trim().is_empty()).then(|| title.to_string()),
        ..Default::default()
    };

    wordcraft_pdf::export_layout(doc, &lay, &pdf_opts)
        .map_err(|e| CompileError::Word(format!("Word PDF export failed: {e}")))
}
