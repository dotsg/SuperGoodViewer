use std::collections::HashMap;
use std::path::{Path, PathBuf};
use typst::foundations::Bytes;
use typst_pdf::PdfOptions;

use super::world::MemoryWorld;

fn default_mode() -> String {
    "fluid".to_string()
}

fn default_theme() -> String {
    "light".to_string()
}

fn default_viewport_width() -> f32 {
    800.0
}

fn default_font_size() -> f32 {
    10.5
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RenderOptions {
    #[serde(default = "default_mode")]
    pub mode: String,
    #[serde(default = "default_theme")]
    pub theme: String,
    #[serde(default = "default_viewport_width")]
    pub viewport_width: f32,
    #[serde(default = "default_font_size")]
    pub font_size: f32,
    #[serde(default)]
    pub body_font: Option<String>,
    #[serde(default)]
    pub code_font: Option<String>,
    #[serde(default)]
    pub image_cache_dir: Option<String>,
    #[serde(default)]
    pub page_format: Option<String>,
    #[serde(default)]
    pub header_left: Option<String>,
    #[serde(default)]
    pub header_center: Option<String>,
    #[serde(default)]
    pub header_right: Option<String>,
    #[serde(default)]
    pub footer_left: Option<String>,
    #[serde(default)]
    pub footer_center: Option<String>,
    #[serde(default)]
    pub footer_right: Option<String>,
    #[serde(default)]
    pub show_header_rule: Option<bool>,
    #[serde(default)]
    pub show_footer_rule: Option<bool>,
    #[serde(default)]
    pub skip_first_page_header_footer: Option<bool>,
    #[serde(default)]
    pub marp_enabled: Option<bool>,
    /// Explicit fluid page slice height in points. Must be finite and positive.
    /// Values above 14,000pt are clamped to 14,000pt to prevent exceeding PDF 1.7 limits.
    /// - None: automatic two-pass detection (natural height if <= 14000pt; dynamic slices if > 14000pt).
    /// - Some(h) if h.is_finite() && h > 0.0: explicitly set slice height (clamped to <= 14000pt).
    #[serde(default)]
    pub fluid_page_height: Option<f32>,
    /// Explicit escape hatch to disable fluid page height slicing.
    /// When true, fluid documents will always render at their full natural height on a single page,
    /// even if exceeding the 14,400pt PDF 1.7 limit.
    #[serde(default)]
    pub disable_fluid_slice: Option<bool>,
}

/// PDF 默认用户单位（1/72 英寸）下页面尺寸上限为 14,400pt，PDFium 超限会裁切或拒绝渲染。
/// 此处使用 14,000.0pt（预留 400pt 安全边际）作为 fluid 模式切片的最大单页高度。
pub const FLUID_CAPPED_PAGE_HEIGHT_PT: f32 = 14000.0;

impl RenderOptions {
    /// Returns validated and clamped fluid slice height in points.
    /// Filters out non-finite (NaN, Inf) and non-positive (<= 0.0) values,
    /// and clamps to FLUID_CAPPED_PAGE_HEIGHT_PT to prevent exceeding PDF limits.
    pub fn valid_fluid_page_height(&self) -> Option<f32> {
        self.fluid_page_height
            .filter(|h| h.is_finite() && *h > 0.0)
            .map(|h| h.min(FLUID_CAPPED_PAGE_HEIGHT_PT))
    }

    pub fn resolved_page_format(&self) -> &str {
        if let Some(ref pf) = self.page_format {
            pf.as_str()
        } else if self.mode == "fluid" {
            "fluid"
        } else {
            "a4"
        }
    }

    pub fn is_fluid(&self) -> bool {
        self.resolved_page_format() == "fluid"
    }

    pub fn is_slide(&self) -> bool {
        let fmt = self.resolved_page_format();
        fmt == "slide_16_9"
            || fmt == "slide_4_3"
            || fmt == "slide16x9"
            || fmt == "slide4x3"
            || fmt == "16:9"
            || fmt == "4:3"
    }
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            mode: default_mode(),
            theme: default_theme(),
            viewport_width: default_viewport_width(),
            font_size: default_font_size(),
            body_font: None,
            code_font: None,
            image_cache_dir: None,
            page_format: None,
            header_left: None,
            header_center: None,
            header_right: None,
            footer_left: None,
            footer_center: None,
            footer_right: None,
            show_header_rule: None,
            show_footer_rule: None,
            skip_first_page_header_footer: None,
            marp_enabled: None,
            fluid_page_height: None,
            disable_fluid_slice: None,
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum CompileError {
    #[error("Typst compile errors:\n{0}")]
    Typst(String),
    #[error("PDF export error: {0}")]
    Pdf(String),
}

pub(crate) fn compile_typst_to_document(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
) -> Result<typst_layout::PagedDocument, CompileError> {
    let world = MemoryWorld::new_with_cache_dir(typst_source, doc_dir, virtual_files, image_cache_dir);

    let warned = typst::compile::<typst_layout::PagedDocument>(&world);
    warned.output.map_err(|errs| {
        let msgs: Vec<String> = errs.iter().map(|e| e.message.to_string()).collect();
        CompileError::Typst(msgs.join("\n"))
    })
}

pub(crate) fn export_document_to_pdf(document: &typst_layout::PagedDocument) -> Result<Vec<u8>, CompileError> {
    typst_pdf::pdf(document, &PdfOptions::default())
        .map_err(|e| CompileError::Pdf(format!("{:?}", e)))
}

pub fn compile_typst_to_pdf_with_options(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
) -> Result<Vec<u8>, CompileError> {
    let document = compile_typst_to_document(typst_source, doc_dir, virtual_files, image_cache_dir)?;
    export_document_to_pdf(&document)
}

pub fn compile_typst_to_pdf(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
) -> Result<Vec<u8>, CompileError> {
    compile_typst_to_pdf_with_options(typst_source, doc_dir, virtual_files, None)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compile_simple_typst() {
        let source = r#"
        #set page(width: 400pt, height: auto, margin: 20pt)
        = Hello World
        This is a test from SuperGoodViewer!
        $ E = m c^2 $
        $ partial $
        "#;
        let res = compile_typst_to_pdf(source, ".", HashMap::new());
        assert!(res.is_ok(), "Typst compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"), "Output is not a valid PDF header");
        assert!(pdf.len() > 100);
        println!("Generated PDF bytes: {}", pdf.len());
    }
}
