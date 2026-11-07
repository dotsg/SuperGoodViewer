use std::path::{Path, PathBuf};
use std::sync::{Arc, OnceLock};
use std::time::UNIX_EPOCH;

use parking_lot::Mutex;

use crate::{CompileError, RenderOptions};

const OLE2_MAGIC: &[u8; 8] = b"\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1";
#[cfg(any(target_os = "android", target_os = "ios"))]
const PARSED_PRES_CACHE_CAPACITY: usize = 2;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const PARSED_PRES_CACHE_CAPACITY: usize = 4;
const MAX_CACHED_PPT_FILE_BYTES: u64 = 16 * 1024 * 1024;
#[cfg(any(target_os = "android", target_os = "ios"))]
const DEFAULT_PPT_RENDER_DPI: f64 = 120.0;
#[cfg(not(any(target_os = "android", target_os = "ios")))]
const DEFAULT_PPT_RENDER_DPI: f64 = 144.0;
const EXPORT_PPT_RENDER_DPI: f64 = 240.0;

type ParsedPresKey = (PathBuf, u64, u32, u64);
type LoadedFontKey = (PathBuf, u64, u64);

static PARSED_PRES_CACHE: OnceLock<Mutex<Vec<(ParsedPresKey, Arc<deckcraft_model::Presentation>)>>> =
    OnceLock::new();
static LOADED_CUSTOM_FONTS: OnceLock<Mutex<std::collections::HashSet<LoadedFontKey>>> =
    OnceLock::new();

/// Rendering backend for parsed [`deckcraft_model::Presentation`] models.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PptRenderBackend {
    /// DeckCraft native renderer (`vello_cpu` + Krilla hybrid PDF with selectable text layer).
    #[default]
    Native,
}

/// Returns true if `path_or_ext` has a supported PowerPoint file extension
/// (`.pptx`, `.pptm`, `.potx`, `.potm`, `.ppsx`, `.ppsm`).
pub fn is_ppt_extension(path_or_ext: &str) -> bool {
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
        "pptx" | "pptm" | "potx" | "potm" | "ppsx" | "ppsm"
    )
}

/// Ensures any custom user fonts downloaded into `<cache_dir>/fonts` are loaded into
/// [`deckcraft_fonts::FontDb::global`] in memory, automatically picking up fonts
/// downloaded during the current session.
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
            let _ = deckcraft_fonts::FontDb::global().add_font(bytes);
            loaded.insert(key);
        }
    }
}

/// Loads any TrueType/OpenType fonts embedded inside the presentation into
/// [`deckcraft_fonts::FontDb::global`].
fn install_embedded_fonts(pres: &deckcraft_model::Presentation) {
    let db = deckcraft_fonts::FontDb::global();
    for font in &pres.embedded_fonts {
        for id in font.faces().into_iter().flatten() {
            let Some(item) = pres.media(id) else {
                continue;
            };
            let Some(sfnt) = deckcraft_fonts::embedded_sfnt(&item.data) else {
                continue;
            };
            let _ = db.add_font(sfnt.to_vec());
        }
    }
}

/// Parses raw PowerPoint presentation bytes (`.pptx`, `.pptm`, `.potx`, `.potm`, `.ppsx`, `.ppsm`)
/// into a [`deckcraft_model::Presentation`] IR.
pub fn parse_ppt_bytes(bytes: &[u8]) -> Result<deckcraft_model::Presentation, CompileError> {
    if bytes.is_empty() {
        return Err(CompileError::Ppt(
            "PowerPoint presentation file is empty (0 bytes)".to_string(),
        ));
    }

    if bytes.starts_with(OLE2_MAGIC) {
        if deckcraft_pptx::is_encrypted(bytes) {
            return Err(CompileError::Ppt(
                "PowerPoint presentation is password-protected (encrypted)".to_string(),
            ));
        }
        return Err(CompileError::Ppt(
            "Legacy binary PowerPoint (.ppt) format is not supported; please save as .pptx"
                .to_string(),
        ));
    }

    let mut pres = deckcraft_pptx::import(bytes).map_err(|e| {
        CompileError::Ppt(format!(
            "Not a valid PowerPoint (.pptx) presentation: {e}"
        ))
    })?;

    install_embedded_fonts(&pres);

    if pres.slides.is_empty() {
        pres.slides.push(Arc::new(deckcraft_model::Slide::default()));
    }

    Ok(pres)
}

/// Reads and parses a PowerPoint file from disk with a bounded in-memory LRU cache keyed by
/// `(canonical_path, mtime_secs, mtime_nanos, size)`, so toggling between Slides and Notes views
/// does not re-parse the archive.
pub fn parse_ppt_file_cached(
    path: &Path,
) -> Result<Arc<deckcraft_model::Presentation>, CompileError> {
    let meta = std::fs::metadata(path).map_err(|e| {
        CompileError::Ppt(format!(
            "Failed to stat PowerPoint file '{}': {}",
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
    let key: ParsedPresKey = (
        canonical_path,
        mtime.as_secs(),
        mtime.subsec_nanos(),
        file_size,
    );

    let cache_lock = PARSED_PRES_CACHE.get_or_init(|| Mutex::new(Vec::new()));
    if file_size <= MAX_CACHED_PPT_FILE_BYTES {
        let mut cache = cache_lock.lock();
        if let Some(pos) = cache.iter().position(|(k, _)| *k == key) {
            let entry = cache.remove(pos);
            let pres = entry.1.clone();
            cache.push(entry);
            return Ok(pres);
        }
    }

    let bytes = std::fs::read(path).map_err(|e| {
        CompileError::Ppt(format!(
            "Failed to read PowerPoint file '{}': {}",
            path.display(),
            e
        ))
    })?;
    let pres = Arc::new(parse_ppt_bytes(&bytes)?);

    if file_size <= MAX_CACHED_PPT_FILE_BYTES {
        let mut cache = cache_lock.lock();
        if cache.len() >= PARSED_PRES_CACHE_CAPACITY {
            cache.remove(0);
        }
        cache.push((key, pres.clone()));
    }

    Ok(pres)
}

/// Renders a parsed [`deckcraft_model::Presentation`] to PDF bytes using the selected backend.
pub fn render_ppt_document_to_pdf(
    pres: &deckcraft_model::Presentation,
    title: &str,
    options: &RenderOptions,
    backend: PptRenderBackend,
) -> Result<Vec<u8>, CompileError> {
    match backend {
        PptRenderBackend::Native => render_ppt_native_pdf(pres, title, options),
    }
}

pub(crate) fn ppt_render_dpi(options: &RenderOptions) -> f64 {
    let is_export = options.export_quality == Some(true)
        || options.mode.eq_ignore_ascii_case("export")
        || matches!(
            options.page_format.as_deref(),
            Some("pptSlidesExport" | "pptNotesExport")
        );
    if is_export {
        EXPORT_PPT_RENDER_DPI
    } else {
        DEFAULT_PPT_RENDER_DPI
    }
}

fn render_ppt_native_pdf(
    pres: &deckcraft_model::Presentation,
    title: &str,
    options: &RenderOptions,
) -> Result<Vec<u8>, CompileError> {
    sync_custom_user_fonts();

    let is_notes_layout = matches!(
        options.page_format.as_deref(),
        Some("pptNotes" | "pptNotesExport" | "notes")
    ) || options.mode.eq_ignore_ascii_case("notes");

    let layout = if is_notes_layout {
        deckcraft_pdf::PageLayout::Notes
    } else {
        deckcraft_pdf::PageLayout::Slides
    };

    let all_hidden = pres.slides.iter().all(|s| s.hidden);
    let has_pres_title = !pres.props.title.trim().is_empty();

    let pdf_opts = deckcraft_pdf::PdfOptions {
        layout,
        dpi: ppt_render_dpi(options),
        slides: None,
        include_hidden: all_hidden,
        text_layer: true,
        frame_slides: true,
        title: (!has_pres_title && !title.trim().is_empty()).then(|| title.to_string()),
        paper: (595.28, 841.89),
    };

    deckcraft_pdf::export(pres, &pdf_opts)
        .map_err(|e| CompileError::Ppt(format!("PowerPoint PDF export failed: {e}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_ppt_render_dpi_preview_vs_export() {
        let preview_opts = RenderOptions::default();
        assert_eq!(ppt_render_dpi(&preview_opts), DEFAULT_PPT_RENDER_DPI);

        let export_opts = RenderOptions {
            export_quality: Some(true),
            ..Default::default()
        };
        assert_eq!(ppt_render_dpi(&export_opts), EXPORT_PPT_RENDER_DPI);
        assert!(ppt_render_dpi(&export_opts) > ppt_render_dpi(&preview_opts));
    }
}
