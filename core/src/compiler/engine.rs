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

#[derive(Debug)]
pub struct CompilationResult {
    pub document: typst_layout::PagedDocument,
    pub degraded_equation_count: usize,
    pub degraded_equations: Vec<String>,
    pub final_typst_source: String,
}

impl std::ops::Deref for CompilationResult {
    type Target = typst_layout::PagedDocument;

    fn deref(&self) -> &Self::Target {
        &self.document
    }
}

impl CompilationResult {
    pub fn into_document(self) -> typst_layout::PagedDocument {
        self.document
    }
}

pub(crate) fn default_degraded_math_macro(is_dark: bool, code_font_str: Option<&str>) -> String {
    let (degraded_math_bg, degraded_math_stroke, degraded_math_fg) = if is_dark {
        ("rgb(\"#3c1e22\")", "rgb(\"#f85149\")", "rgb(\"#ff7b72\")")
    } else {
        ("rgb(\"#fff5f5\")", "rgb(\"#cf222e\")", "rgb(\"#cf222e\")")
    };
    let font = code_font_str.unwrap_or("(\"Menlo\", \"Consolas\", \"monospace\")");
    format!(
        "#let mitexdegraded(raw-latex) = box(\n  stroke: (dash: \"densely-dashed\", paint: {degraded_math_stroke}, thickness: 0.65pt),\n  fill: {degraded_math_bg},\n  inset: (x: 4pt, y: 2.5pt),\n  radius: 3pt,\n  baseline: 0%,\n  text(fill: {degraded_math_fg}, font: {font}, size: 0.82em, raw-latex)\n)\n#let mitex-degraded-math = mitexdegraded\n"
    )
}

pub(crate) fn extract_degraded_equations_from_source(source: &str) -> Vec<String> {
    let mut results = Vec::new();
    let pattern = "mitexdegraded";
    let bytes = source.as_bytes();
    let mut cursor = 0;

    while let Some(pos) = source[cursor..].find(pattern) {
        let mut idx = cursor + pos + pattern.len();
        // Skip whitespace
        while idx < bytes.len() && (bytes[idx] == b' ' || bytes[idx] == b'\t' || bytes[idx] == b'\n' || bytes[idx] == b'\r') {
            idx += 1;
        }
        // Expect '('
        if idx < bytes.len() && bytes[idx] == b'(' {
            idx += 1;
            // Skip whitespace
            while idx < bytes.len() && (bytes[idx] == b' ' || bytes[idx] == b'\t' || bytes[idx] == b'\n' || bytes[idx] == b'\r') {
                idx += 1;
            }
            // Expect '"'
            if idx < bytes.len() && bytes[idx] == b'"' {
                idx += 1;
                let mut escaped = false;
                let mut str_bytes = Vec::new();
                while idx < bytes.len() {
                    let b = bytes[idx];
                    if escaped {
                        match b {
                            b'\\' => str_bytes.push(b'\\'),
                            b'"' => str_bytes.push(b'"'),
                            b'n' => str_bytes.push(b'\n'),
                            b'r' => str_bytes.push(b'\r'),
                            b't' => str_bytes.push(b'\t'),
                            _ => {
                                str_bytes.push(b'\\');
                                str_bytes.push(b);
                            }
                        }
                        escaped = false;
                    } else if b == b'\\' {
                        escaped = true;
                    } else if b == b'"' {
                        idx += 1;
                        break;
                    } else {
                        str_bytes.push(b);
                    }
                    idx += 1;
                }
                results.push(String::from_utf8_lossy(&str_bytes).into_owned());
                cursor = idx;
                continue;
            }
        }
        cursor = idx.max(cursor + pos + 1);
    }
    results
}

fn degrade_failing_equations(
    typst_source: &str,
    world: &MemoryWorld,
    errs: &[typst::diag::SourceDiagnostic],
    raw_equations: &[String],
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
            // Try to recover original raw LaTeX from /*sgv-raw:<index or hex>*/ if embedded by transpile_latex_math
            let recovered_raw = if let Some(raw_start) = eq_str.find("/*sgv-raw:") {
                let after_prefix = &eq_str[raw_start + 10..];
                if let Some(raw_end) = after_prefix.find("*/") {
                    let marker = &after_prefix[..raw_end];
                    if let Ok(idx) = marker.parse::<usize>() {
                        raw_equations.get(idx).cloned()
                    } else {
                        crate::parser::math::hex_decode(marker)
                    }
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

    // Prepend default mitexdegraded definition if not already in source (fallback for raw Typst)
    if !had_mitexdegraded {
        let default_prelude = default_degraded_math_macro(false, None);
        new_source.insert_str(0, &default_prelude);
    }

    Some(new_source)
}

pub(crate) fn compile_typst_to_document(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
) -> Result<CompilationResult, CompileError> {
    compile_typst_to_document_with_raw_equations(
        typst_source,
        doc_dir,
        virtual_files,
        image_cache_dir,
        &[],
    )
}

pub(crate) fn compile_typst_to_document_with_raw_equations(
    typst_source: &str,
    doc_dir: impl AsRef<Path>,
    virtual_files: HashMap<PathBuf, Bytes>,
    image_cache_dir: Option<PathBuf>,
    raw_equations: &[String],
) -> Result<CompilationResult, CompileError> {
    let mut current_source = typst_source.to_string();
    let max_degrade_passes = 3;
    let virtual_files_arc = std::sync::Arc::new(virtual_files);

    for _ in 0..=max_degrade_passes {
        let world = MemoryWorld::new_with_cache_dir(&current_source, doc_dir.as_ref(), virtual_files_arc.clone(), image_cache_dir.clone());
        let warned = typst::compile::<typst_layout::PagedDocument>(&world);
        match warned.output {
            Ok(doc) => {
                let degraded_equations = extract_degraded_equations_from_source(&current_source);
                let degraded_equation_count = degraded_equations.len();
                return Ok(CompilationResult {
                    document: doc,
                    degraded_equation_count,
                    degraded_equations,
                    final_typst_source: current_source,
                });
            }
            Err(errs) => {
                if let Some(degraded_source) = degrade_failing_equations(&current_source, &world, &errs, raw_equations) {
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
    match warned.output {
        Ok(doc) => {
            let degraded_equations = extract_degraded_equations_from_source(&current_source);
            let degraded_equation_count = degraded_equations.len();
            Ok(CompilationResult {
                document: doc,
                degraded_equation_count,
                degraded_equations,
                final_typst_source: current_source,
            })
        }
        Err(errs) => {
            let msgs: Vec<String> = errs.iter().map(|e| e.message.to_string()).collect();
            Err(CompileError::Typst(msgs.join("\n")))
        }
    }
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

    #[test]
    fn test_degraded_equations_side_table_and_hex_fallback() {
        let raw_table = vec![r"\indexedcommand{abc}".to_string()];
        let raw_latex = r"\hexcommand{xyz}";
        let mut hex = String::new();
        for &b in raw_latex.as_bytes() {
            use std::fmt::Write;
            let _ = write!(&mut hex, "{:02x}", b);
        }

        let source = format!(r#"
        #set page(width: 400pt, height: auto, margin: 20pt)
        $ /*sgv-raw:0*/ indexedcommand(a b c) $
        $ /*sgv-raw:{}*/ hexcommand(x y z) $
        $ unknownbare $
        "#, hex);

        let res = compile_typst_to_document_with_raw_equations(&source, ".", HashMap::new(), None, &raw_table).unwrap();
        assert_eq!(res.degraded_equation_count, 3);
        assert_eq!(res.degraded_equations[0], r"\indexedcommand{abc}");
        assert_eq!(res.degraded_equations[1], r"\hexcommand{xyz}");
        assert_eq!(res.degraded_equations[2], "unknownbare");
    }

    #[test]
    fn test_extract_degraded_equations_preserves_utf8_multibyte() {
        let source = r#"
        $ mitexdegraded("\\unknowncmd{中文公式}") $
        $ mitexdegraded("\\alsobad{\\text{αβγ}}") $
        "#;
        let extracted = extract_degraded_equations_from_source(source);
        assert_eq!(extracted.len(), 2);
        assert_eq!(extracted[0], r"\unknowncmd{中文公式}");
        assert_eq!(extracted[1], r"\alsobad{\text{αβγ}}");
    }
}
