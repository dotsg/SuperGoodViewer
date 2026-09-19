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
    #[serde(default)]
    pub cap_fluid_height: Option<bool>,
}

impl RenderOptions {
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
            cap_fluid_height: None,
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

pub fn compile_typst_to_pdf_with_options(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
) -> Result<Vec<u8>, CompileError> {
    let world = MemoryWorld::new_with_cache_dir(typst_source, doc_dir, virtual_files, image_cache_dir);

    let warned = typst::compile(&world);
    let document = warned.output.map_err(|errs| {
        let msgs: Vec<String> = errs.iter().map(|e| e.message.to_string()).collect();
        CompileError::Typst(msgs.join("\n"))
    })?;

    let pdf_bytes = typst_pdf::pdf(&document, &PdfOptions::default())
        .map_err(|e| CompileError::Pdf(format!("{:?}", e)))?;

    Ok(pdf_bytes)
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
