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

pub fn compile_typst_to_pdf(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
) -> Result<Vec<u8>, CompileError> {
    let world = MemoryWorld::new(typst_source, doc_dir, virtual_files);

    let warned = typst::compile(&world);
    let document = warned.output.map_err(|errs| {
        let msgs: Vec<String> = errs.iter().map(|e| e.message.to_string()).collect();
        CompileError::Typst(msgs.join("\n"))
    })?;

    let pdf_bytes = typst_pdf::pdf(&document, &PdfOptions::default())
        .map_err(|e| CompileError::Pdf(format!("{:?}", e)))?;

    let sliced_pdf = crate::compiler::slicer::slice_continuous_pdf(
        &pdf_bytes,
        crate::compiler::slicer::DEFAULT_SLICE_HEIGHT,
    )?;

    Ok(sliced_pdf)
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
