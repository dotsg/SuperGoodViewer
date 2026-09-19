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

fn degrade_failing_equations(
    typst_source: &str,
    world: &MemoryWorld,
    errs: &[typst::diag::SourceDiagnostic],
) -> Option<String> {
    use typst::syntax::{LinkedNode, Side, SyntaxKind};
    use typst::{World, WorldExt};

    let main_id = world.main();
    let main_src = world.source(main_id).ok()?;
    let root = LinkedNode::new(main_src.root());

    let mut equation_ranges = std::collections::BTreeSet::new();

    for err in errs {
        if let Some(range) = world.range(err.span) {
            if let Some(leaf) = root.leaf_at(range.start, Side::After).or_else(|| root.leaf_at(range.start, Side::Before)) {
                let mut cur = Some(leaf);
                let mut outermost_equation = None;
                while let Some(node) = cur {
                    if node.kind() == SyntaxKind::Equation {
                        outermost_equation = Some(node.range());
                    }
                    cur = node.parent().cloned();
                }
                if let Some(r) = outermost_equation {
                    equation_ranges.insert((r.start, r.end));
                }
            }
        }
    }

    if equation_ranges.is_empty() {
        return None;
    }

    // Keep only outermost ranges: if range A contains range B, discard range B
    let mut outermost_ranges: Vec<(usize, usize)> = Vec::new();
    for &(s, e) in &equation_ranges {
        let is_nested = equation_ranges.iter().any(|&(os, oe)| {
            (os < s && oe >= e) || (os <= s && oe > e)
        });
        if !is_nested {
            outermost_ranges.push((s, e));
        }
    }

    // Sort ranges in descending order so earlier replacements don't invalidate later byte offsets
    outermost_ranges.sort_by_key(|r| std::cmp::Reverse(r.0));

    let had_mitexdegraded = typst_source.contains("#let mitexdegraded");
    let mut new_source = typst_source.to_string();
    for (start, end) in outermost_ranges {
        let range = start..end;
        if range.end <= new_source.len() && new_source.is_char_boundary(range.start) && new_source.is_char_boundary(range.end) {
            let eq_str = &new_source[range.clone()];
            // Try to recover original raw LaTeX from /*sgv-raw:<hex>*/ if embedded by transpile_latex_math
            let recovered_raw = if let Some(raw_start) = eq_str.find("/*sgv-raw:") {
                let after_prefix = &eq_str[raw_start + 10..];
                if let Some(raw_end) = after_prefix.find("*/") {
                    let hex_str = &after_prefix[..raw_end];
                    crate::parser::math::hex_decode(hex_str)
                } else {
                    None
                }
            } else {
                None
            };

            let fallback_content = match recovered_raw {
                Some(raw) => raw,
                None => {
                    let trimmed = eq_str.trim();
                    trimmed
                        .strip_prefix('$')
                        .unwrap_or(trimmed)
                        .strip_suffix('$')
                        .unwrap_or(trimmed)
                        .trim()
                        .to_string()
                }
            };

            let safe_inner = crate::parser::markdown::escape_typst_string(&fallback_content);
            let replacement = format!("$ mitexdegraded(\"{}\") $", safe_inner);
            new_source.replace_range(range, &replacement);
        }
    }

    // Prepend default mitexdegraded definition if not already in source
    if !had_mitexdegraded {
        let default_prelude = "#let mitexdegraded(raw) = box(stroke: (dash: \"densely-dashed\", paint: rgb(\"#cf222e\"), thickness: 0.65pt), fill: rgb(\"#fff5f5\"), inset: (x: 4pt, y: 2.5pt), radius: 3pt, baseline: 0%, text(fill: rgb(\"#cf222e\"), font: (\"Menlo\", \"Consolas\", \"monospace\"), size: 0.82em, raw))\n";
        new_source.insert_str(0, default_prelude);
    }

    Some(new_source)
}

pub(crate) fn compile_typst_to_document(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
) -> Result<typst_layout::PagedDocument, CompileError> {
    let mut current_source = typst_source.to_string();
    let max_degrade_passes = 3;
    let virtual_files_arc = std::sync::Arc::new(virtual_files);

    for _ in 0..=max_degrade_passes {
        let world = MemoryWorld::new_with_cache_dir(&current_source, doc_dir.as_ref(), virtual_files_arc.clone(), image_cache_dir.clone());
        let warned = typst::compile::<typst_layout::PagedDocument>(&world);
        match warned.output {
            Ok(doc) => return Ok(doc),
            Err(errs) => {
                if let Some(degraded_source) = degrade_failing_equations(&current_source, &world, &errs) {
                    if degraded_source != current_source {
                        current_source = degraded_source;
                        continue;
                    }
                }
                let msgs: Vec<String> = errs.iter().map(|e| e.message.to_string()).collect();
                return Err(CompileError::Typst(msgs.join("\n")));
            }
        }
    }

    let world = MemoryWorld::new_with_cache_dir(&current_source, doc_dir.as_ref(), virtual_files_arc, image_cache_dir);
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
    }

    #[test]
    fn test_formula_level_degradation() {
        let raw_latex = r"\brokencommand{xyz}";
        let mut hex = String::new();
        for &b in raw_latex.as_bytes() {
            use std::fmt::Write;
            let _ = write!(&mut hex, "{:02x}", b);
        }

        let source_with_bad_math = format!(r#"
        #set page(width: 400pt, height: auto, margin: 20pt)
        = Document With Broken Math

        This heading and text should render fine.

        Here is a valid equation: $ E = m c^2 $

        Here is a broken equation with raw LaTeX comment: $ /*sgv-raw:{}*/ brokencommand(x y z) $

        And another broken equation without raw comment: $ unknownsyntax $

        And a valid equation: $ 1 + 1 = 2 $
        "#, hex);
        let res = compile_typst_to_pdf(&source_with_bad_math, ".", HashMap::new());
        assert!(res.is_ok(), "Document should compile with degraded math formula instead of failing completely: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }
}
