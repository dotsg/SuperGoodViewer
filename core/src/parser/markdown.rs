use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use pulldown_cmark::{Alignment, Event, HeadingLevel, Options, Parser, Tag, TagEnd};
use typst::foundations::Bytes;

use crate::compiler::engine::RenderOptions;
use super::math::transpile_latex_math;
use super::mermaid::render_mermaid;

pub struct ParsedDocument {
    pub typst_source: String,
    pub virtual_files: HashMap<PathBuf, Bytes>,
}

/// Escapes characters that have special syntactic meaning in Typst markup
fn escape_typst_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for c in text.chars() {
        match c {
            '#' => out.push_str("\\#"),
            '@' => out.push_str("\\@"),
            '$' => out.push_str("\\$"),
            _ => out.push(c),
        }
    }
    out
}

/// Escapes characters for embedding inside a Typst string literal ("...")
pub(crate) fn escape_typst_string(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out
}

fn decode_percent(s: &str) -> String {
    let mut bytes = Vec::new();
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '%' {
            if let (Some(h1), Some(h2)) = (chars.next(), chars.next()) {
                if let Ok(b) = u8::from_str_radix(&format!("{}{}", h1, h2), 16) {
                    bytes.push(b);
                    continue;
                }
            }
        }
        let mut buf = [0; 4];
        bytes.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
    }
    String::from_utf8(bytes).unwrap_or_else(|_| s.to_string())
}

fn slugify_heading(text: &str) -> (String, Vec<String>) {
    // 1. Primary GFM slug: lowercase ASCII, dots/punctuation stripped, spaces/underscores to dashes
    let mut gfm = String::new();
    let mut prev_is_dash = false;
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            gfm.extend(ch.to_lowercase());
            prev_is_dash = false;
        } else if ch == '-' {
            if !prev_is_dash && !gfm.is_empty() {
                gfm.push('-');
                prev_is_dash = true;
            }
        } else if ch.is_whitespace() || ch == '_' {
            if !prev_is_dash && !gfm.is_empty() {
                gfm.push('-');
                prev_is_dash = true;
            }
        }
    }
    if gfm.ends_with('-') {
        gfm.pop();
    }

    // 2. Alternative slugs: replacing dots with dashes
    let mut alt_dot_dash = String::new();
    let mut prev_dash = false;
    for ch in text.chars() {
        if ch.is_alphanumeric() {
            alt_dot_dash.extend(ch.to_lowercase());
            prev_dash = false;
        } else if ch.is_whitespace() || ch == '.' || ch == '-' || ch == '_' {
            if !prev_dash && !alt_dot_dash.is_empty() {
                alt_dot_dash.push('-');
                prev_dash = true;
            }
        }
    }
    if alt_dot_dash.ends_with('-') {
        alt_dot_dash.pop();
    }

    let literal = text.trim().to_string();

    let mut secondary = Vec::new();
    if !alt_dot_dash.is_empty() && alt_dot_dash != gfm {
        secondary.push(alt_dot_dash);
    }
    if !literal.is_empty() && literal != gfm && !secondary.contains(&literal) {
        secondary.push(literal);
    }

    (gfm, secondary)
}

fn decode_html_entities(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&nbsp;", " ")
}

fn extract_html_attr(tag: &str, attr: &str) -> Option<String> {
    let lower_tag = tag.to_lowercase();
    let needle_double = format!("{}=\"", attr);
    let needle_single = format!("{}='", attr);
    let (start_idx, quote_char) = if let Some(pos) = lower_tag.find(&needle_double) {
        (pos + needle_double.len(), '"')
    } else if let Some(pos) = lower_tag.find(&needle_single) {
        (pos + needle_single.len(), '\'')
    } else {
        return None;
    };
    let rest = &tag[start_idx..];
    if let Some(end_idx) = rest.find(quote_char) {
        Some(rest[..end_idx].to_string())
    } else {
        None
    }
}

fn parse_dimension(val: &str) -> Option<String> {
    let s = val.trim();
    if let Some(num) = s.strip_suffix('%') {
        let n: f64 = num.trim().parse().ok()?;
        if n.is_finite() && n > 0.0 {
            return Some(format!("{}%", n));
        }
    } else if let Some(num) = s.strip_suffix("px") {
        let n: f64 = num.trim().parse().ok()?;
        if n.is_finite() && n > 0.0 {
            return Some(format!("{}pt", n));
        }
    } else if let Some(num) = s.strip_suffix("pt") {
        let n: f64 = num.trim().parse().ok()?;
        if n.is_finite() && n > 0.0 {
            return Some(format!("{}pt", n));
        }
    } else if let Ok(n) = s.parse::<f64>() {
        if n.is_finite() && n > 0.0 {
            return Some(format!("{}pt", n));
        }
    }
    None
}

pub fn sanitize_image_url(url: &str) -> &str {
    if let Some(pos) = url.find('#') {
        &url[..pos]
    } else {
        url
    }
}

pub fn extract_url_extension(clean_url: &str) -> &'static str {
    let (url_path, query) = match clean_url.find('?') {
        Some(idx) => (&clean_url[..idx], Some(&clean_url[idx + 1..])),
        None => (clean_url, None),
    };

    if let Some(last_segment) = url_path.split('/').last() {
        if let Some(dot_idx) = last_segment.rfind('.') {
            let ext = &last_segment[dot_idx + 1..];
            let ext_lower = ext.to_ascii_lowercase();
            match ext_lower.as_str() {
                "png" => return "png",
                "jpg" | "jpeg" => return "jpg",
                "webp" => return "webp",
                "gif" => return "gif",
                "svg" => return "svg",
                _ => {}
            }
        }
    }

    if let Some(q) = query {
        let q_lower = q.to_ascii_lowercase();
        for param in q_lower.split('&') {
            if let Some((k, v)) = param.split_once('=') {
                if k == "wx_fmt" || k == "format" {
                    match v {
                        "png" => return "png",
                        "jpg" | "jpeg" => return "jpg",
                        "webp" => return "webp",
                        "gif" => return "gif",
                        "svg" => return "svg",
                        _ => {}
                    }
                }
            }
        }
    }

    "png"
}

pub fn url_to_cache_filename(url: &str) -> String {
    let clean_url = sanitize_image_url(url);
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(clean_url.as_bytes());
    let hash = format!("{:x}", hasher.finalize());
    let ext = extract_url_extension(clean_url);
    format!("{}.{}", &hash[..32], ext)
}

pub fn find_cached_image_file(custom_cache: Option<&Path>, url: &str) -> Option<String> {
    let clean_url = sanitize_image_url(url);
    let predicted = url_to_cache_filename(clean_url);

    // 1. Check custom cache dir first if provided (O(1) stat call)
    if let Some(dir) = custom_cache {
        if dir.join(&predicted).is_file() {
            return Some(predicted);
        }
    }

    // 2. Fall back to default system cache dir (O(1) stat call)
    let default_cache = crate::compiler::world::get_default_image_cache_dir();
    if default_cache.join(&predicted).is_file() {
        return Some(predicted);
    }

    None
}

fn render_html_image(
    tag: &str,
    in_center: bool,
    is_dark: bool,
    badge_bg: &str,
    badge_stroke: &str,
    badge_fg: &str,
    custom_cache: Option<&Path>,
) -> String {
    let src = extract_html_attr(tag, "src").unwrap_or_default();
    if src.is_empty() {
        return String::new();
    }
    let alt = extract_html_attr(tag, "alt").unwrap_or_else(|| "图片".to_string());
    let width = extract_html_attr(tag, "width");
    let height = extract_html_attr(tag, "height");

    let is_url = src.starts_with("http://") || src.starts_with("https://");
    let resolved_src = if is_url {
        if let Some(cached_filename) = find_cached_image_file(custom_cache, &src) {
            cached_filename
        } else {
            let escaped_alt = escape_typst_text(&alt);
            let escaped_src = escape_typst_string(&src);
            return format!(
                "#link(\"{escaped_src}\")[#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 5pt, y: 2.5pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[🖼️ {escaped_alt}]]]"
            );
        }
    } else {
        src
    };

    let mut args = Vec::new();
    if let Some(w) = width {
        if let Some(dim) = parse_dimension(&w) {
            args.push(format!("width: {}", dim));
        }
    }
    if let Some(h) = height {
        if let Some(dim) = parse_dimension(&h) {
            args.push(format!("height: {}", dim));
        }
    }
    let args_str = if args.is_empty() {
        String::new()
    } else {
        format!(", {}", args.join(", "))
    };

    let (img_stroke, img_radius) = if is_dark {
        ("0.5pt + rgb(\"#383e4a\")", "4pt")
    } else {
        ("none", "4pt")
    };

    let escaped_resolved_src = escape_typst_string(&resolved_src);
    let block_str = format!("#block(radius: {img_radius}, stroke: {img_stroke}, clip: true)[#image(\"{escaped_resolved_src}\"{args_str})]");
    if in_center {
        format!("\n{}\n", block_str)
    } else {
        format!("\n#align(center)[{}]\n\n", block_str)
    }
}

struct HtmlTranspiler<'a> {
    center_depth: usize,
    is_dark: bool,
    badge_bg: &'a str,
    badge_stroke: &'a str,
    badge_fg: &'a str,
    custom_cache: Option<&'a Path>,
}

impl<'a> HtmlTranspiler<'a> {
    fn new(
        is_dark: bool,
        badge_bg: &'a str,
        badge_stroke: &'a str,
        badge_fg: &'a str,
        custom_cache: Option<&'a Path>,
    ) -> Self {
        Self {
            center_depth: 0,
            is_dark,
            badge_bg,
            badge_stroke,
            badge_fg,
            custom_cache,
        }
    }

    fn transpile_chunk(&mut self, chunk: &str, out: &mut String) {
        let mut rest = chunk;
        while !rest.is_empty() {
            if let Some(start) = rest.find('<') {
                let (before, tag_start) = rest.split_at(start);
                if !before.is_empty() {
                    out.push_str(&escape_typst_text(&decode_html_entities(before)));
                }
                if let Some(end) = tag_start.find('>') {
                    let tag = &tag_start[..=end];
                    rest = &tag_start[end + 1..];
                    self.handle_tag(tag, out);
                } else {
                    out.push_str(&escape_typst_text(&decode_html_entities(tag_start)));
                    break;
                }
            } else {
                out.push_str(&escape_typst_text(&decode_html_entities(rest)));
                break;
            }
        }
    }

    fn handle_tag(&mut self, tag: &str, out: &mut String) {
        let lower = tag.to_lowercase();
        let trimmed_lower = lower.trim();
        if trimmed_lower.starts_with("<!--") {
            return;
        }
        if trimmed_lower.starts_with("<img") {
            let rendered = render_html_image(
                tag,
                self.center_depth > 0,
                self.is_dark,
                self.badge_bg,
                self.badge_stroke,
                self.badge_fg,
                self.custom_cache,
            );
            out.push_str(&rendered);
        } else if (trimmed_lower.starts_with("<div")
            && (lower.contains("center") || lower.contains("align=\"center\"") || lower.contains("align='center'")))
            || trimmed_lower == "<center>"
        {
            self.center_depth += 1;
            out.push_str("\n#align(center)[\n");
        } else if trimmed_lower == "</div>" || trimmed_lower == "</center>" {
            if self.center_depth > 0 {
                self.center_depth -= 1;
                out.push_str("]\n\n");
            }
        } else if trimmed_lower.starts_with("<h1") {
            out.push_str("\n= ");
        } else if trimmed_lower == "</h1>" {
            out.push_str("\n\n");
        } else if trimmed_lower.starts_with("<h2") {
            out.push_str("\n== ");
        } else if trimmed_lower == "</h2>" {
            out.push_str("\n\n");
        } else if trimmed_lower.starts_with("<h3") {
            out.push_str("\n=== ");
        } else if trimmed_lower == "</h3>" {
            out.push_str("\n\n");
        } else if trimmed_lower.starts_with("<h4") {
            out.push_str("\n==== ");
        } else if trimmed_lower == "</h4>" {
            out.push_str("\n\n");
        } else if trimmed_lower.starts_with("<p") {
            out.push('\n');
        } else if trimmed_lower == "</p>" {
            out.push_str("\n\n");
        } else if trimmed_lower == "<strong>" || trimmed_lower == "<b>" {
            out.push('*');
        } else if trimmed_lower == "</strong>" || trimmed_lower == "</b>" {
            out.push('*');
        } else if trimmed_lower == "<em>" || trimmed_lower == "<i>" {
            out.push('_');
        } else if trimmed_lower == "</em>" || trimmed_lower == "</i>" {
            out.push('_');
        } else if trimmed_lower == "<br>" || trimmed_lower == "<br/>" || trimmed_lower == "<br />" {
            out.push_str("\\ \n");
        } else if trimmed_lower.starts_with("<a ") {
            if let Some(href) = extract_html_attr(tag, "href") {
                let escaped_href = escape_typst_string(&href);
                out.push_str(&format!("#link(\"{escaped_href}\")["));
            } else {
                out.push('[');
            }
        } else if trimmed_lower == "</a>" {
            out.push(']');
        }
    }

    fn finish(&mut self, out: &mut String) {
        while self.center_depth > 0 {
            self.center_depth -= 1;
            out.push_str("]\n\n");
        }
    }
}

#[derive(Debug, Default, Clone)]
pub struct DocumentFrontmatter {
    pub marp: bool,
    pub size: Option<String>,
    pub theme: Option<String>,
    pub paginate: Option<bool>,
    pub header: Option<String>,
    pub footer: Option<String>,
    pub page_format: Option<String>,
}

pub fn extract_frontmatter(content: &str) -> (DocumentFrontmatter, &str) {
    let trimmed = content.trim_start();
    if !trimmed.starts_with("---") {
        return (DocumentFrontmatter::default(), content);
    }

    let rest = &trimmed[3..];
    let first_nl = match rest.find('\n') {
        Some(idx) => idx,
        None => return (DocumentFrontmatter::default(), content),
    };
    if !rest[..first_nl].trim().is_empty() {
        return (DocumentFrontmatter::default(), content);
    }

    let after_first_line = &rest[first_nl + 1..];
    let mut closing_idx = None;
    let mut byte_pos = 0;
    for line in after_first_line.split_inclusive('\n') {
        let line_trimmed = line.trim();
        if line_trimmed == "---" {
            closing_idx = Some(byte_pos);
            break;
        }
        byte_pos += line.len();
    }

    let closing_pos = match closing_idx {
        Some(pos) => pos,
        None => return (DocumentFrontmatter::default(), content),
    };

    let yaml_block = &after_first_line[..closing_pos];
    let after_closing = &after_first_line[closing_pos..];
    let body_start = match after_closing.find('\n') {
        Some(nl) => &after_closing[nl + 1..],
        None => "",
    };

    let mut fm = DocumentFrontmatter::default();
    for line in yaml_block.lines() {
        let trimmed_line = line.trim();
        if trimmed_line.is_empty() || trimmed_line.starts_with('#') {
            continue;
        }
        if let Some((k, v)) = trimmed_line.split_once(':') {
            let key = k.trim().to_lowercase();
            let val = v.trim().trim_matches('"').trim_matches('\'').trim();
            match key.as_str() {
                "marp" => {
                    fm.marp = val.eq_ignore_ascii_case("true") || val.eq_ignore_ascii_case("yes");
                }
                "size" => {
                    fm.size = Some(val.to_string());
                }
                "theme" => {
                    fm.theme = Some(val.to_string());
                }
                "paginate" => {
                    fm.paginate = Some(val.eq_ignore_ascii_case("true") || val.eq_ignore_ascii_case("yes"));
                }
                "header" => {
                    fm.header = Some(val.to_string());
                }
                "footer" => {
                    fm.footer = Some(val.to_string());
                }
                "page_format" | "page-format" => {
                    fm.page_format = Some(val.to_string());
                }
                _ => {}
            }
        }
    }

    (fm, body_start)
}

fn format_slot_to_typst(template: &str, safe_title: &str, text_color: &str) -> String {
    if template.trim().is_empty() {
        return "[]".to_string();
    }
    let safe_template = escape_typst_text(template);
    let with_title = safe_template.replace("{title}", safe_title);
    let with_page = with_title.replace("{page}", "#page-num");
    let with_total = with_page.replace("{total}", "#total-pages");
    format!("[#text(fill: {}, size: 9pt)[{}]]", text_color, with_total)
}

pub fn convert_markdown_to_typst(
    markdown: &str,
    title: &str,
    options: &RenderOptions,
) -> ParsedDocument {
    let (frontmatter, markdown_body) = extract_frontmatter(markdown);

    let is_marp = frontmatter.marp || options.marp_enabled.unwrap_or(false);
    let raw_format = if let Some(ref pf) = frontmatter.page_format {
        pf.as_str()
    } else if is_marp {
        if let Some(ref s) = frontmatter.size {
            if s == "4:3" || s == "4_3" {
                "slide_4_3"
            } else {
                "slide_16_9"
            }
        } else {
            "slide_16_9"
        }
    } else if let Some(ref pf) = options.page_format {
        pf.as_str()
    } else if options.mode == "fluid" {
        "fluid"
    } else {
        "a4"
    };

    let normalized_format = match raw_format {
        "fluid" => "fluid",
        "a4" | "a4_portrait" | "a4Portrait" | "portrait" => "a4",
        "a4_landscape" | "a4Landscape" | "landscape" => "a4_landscape",
        "slide_16_9" | "slide16x9" | "16:9" | "16_9" => "slide_16_9",
        "slide_4_3" | "slide4x3" | "4:3" | "4_3" => "slide_4_3",
        _ => if options.mode == "fluid" { "fluid" } else { "a4" },
    };

    let is_fluid = normalized_format == "fluid";
    let is_slide = normalized_format == "slide_16_9" || normalized_format == "slide_4_3";
    let is_slide_mode = is_slide || is_marp;

    let mut virtual_files = HashMap::new();
    let mut out = String::with_capacity(markdown.len() * 2);

    // 1. Inject Modern Typst Preamble Template
    let is_dark = options.theme == "dark";
    let bg_color = if is_dark { "rgb(\"#1e1e1e\")" } else { "rgb(\"#ffffff\")" };
    let text_color = if is_dark { "rgb(\"#d4d4d4\")" } else { "rgb(\"#1a1a1a\")" };
    let header_color = if is_dark { "rgb(\"#808080\")" } else { "rgb(\"#666666\")" };
    let heading_color = if is_dark { "rgb(\"#ffffff\")" } else { "rgb(\"#111111\")" };
    let code_bg = if is_dark { "rgb(\"#252830\")" } else { "rgb(\"#f6f8fa\")" };
    let code_border = if is_dark { "rgb(\"#383e4a\")" } else { "rgb(\"#e1e4e8\")" };
    let table_stroke = if is_dark { "rgb(\"#333842\")" } else { "rgb(\"#d0d7de\")" };
    let table_header_bg = if is_dark { "rgb(\"#252830\")" } else { "rgb(\"#f6f8fa\")" };
    let link_color = if is_dark { "rgb(\"#58a6ff\")" } else { "rgb(\"#0969da\")" };
    let link_underline = if is_dark { "rgb(\"#58a6ff\").transparentize(60%)" } else { "rgb(\"#0969da\").transparentize(65%)" };
    let quote_bg = if is_dark { "rgb(\"#22252b\")" } else { "rgb(\"#f6f8fa\")" };
    let quote_border = if is_dark { "rgb(\"#484f58\")" } else { "rgb(\"#d0d7de\")" };
    let rule_color = if is_dark { "rgb(\"#333842\")" } else { "rgb(\"#d0d7de\")" };

    let (badge_bg, badge_stroke, badge_fg) = if is_dark {
        ("rgb(\"#262930\")", "rgb(\"#475569\")", "rgb(\"#e2e8f0\")")
    } else {
        ("rgb(\"#f1f5f9\")", "rgb(\"#cbd5e1\")", "rgb(\"#334155\")")
    };

    let (page_width, page_height, page_margin) = match normalized_format {
        "fluid" => (
            format!("{}pt", options.viewport_width),
            "auto".to_string(),
            "(x: 24pt, top: 0pt, bottom: 56pt)".to_string(),
        ),
        "a4" => (
            "595.28pt".to_string(),
            "841.89pt".to_string(),
            "(x: 2cm, top: 2.5cm, bottom: 2.5cm)".to_string(),
        ),
        "a4_landscape" => (
            "841.89pt".to_string(),
            "595.28pt".to_string(),
            "(x: 2.5cm, top: 2cm, bottom: 2cm)".to_string(),
        ),
        "slide_16_9" => (
            "960pt".to_string(),
            "540pt".to_string(),
            "(x: 48pt, top: 36pt, bottom: 36pt)".to_string(),
        ),
        "slide_4_3" => (
            "960pt".to_string(),
            "720pt".to_string(),
            "(x: 48pt, top: 40pt, bottom: 40pt)".to_string(),
        ),
        _ => (
            "595.28pt".to_string(),
            "841.89pt".to_string(),
            "(x: 2cm, top: 2.5cm, bottom: 2.5cm)".to_string(),
        ),
    };

    out.push_str(&format!(
        r##"// Auto-generated Typst markup by SuperGoodViewer
#set page(
  width: {page_width},
  height: {page_height},
  margin: {page_margin},
  fill: {bg_color},
"##
    ));

    let safe_title = escape_typst_text(title);

    if !is_fluid {
        let skip_first = options.skip_first_page_header_footer.unwrap_or(true);
        let show_header_rule = options.show_header_rule.unwrap_or(false);
        let show_footer_rule = options.show_footer_rule.unwrap_or(false);

        // Header slots
        let default_header_right = if is_slide {
            frontmatter.header.as_deref().unwrap_or("")
        } else {
            frontmatter.header.as_deref().unwrap_or("{title}")
        };
        let h_left = options.header_left.as_deref().unwrap_or("");
        let h_center = options.header_center.as_deref().unwrap_or("");
        let h_right = options.header_right.as_deref().unwrap_or(default_header_right);

        let has_header = !h_left.is_empty() || !h_center.is_empty() || !h_right.is_empty() || show_header_rule;

        if has_header {
            let slot_left = format_slot_to_typst(h_left, &safe_title, header_color);
            let slot_center = format_slot_to_typst(h_center, &safe_title, header_color);
            let slot_right = format_slot_to_typst(h_right, &safe_title, header_color);
            let rule = if show_header_rule {
                format!("\n      v(-4pt)\n      line(length: 100%, stroke: 0.3pt + {header_color})")
            } else {
                "".to_string()
            };
            let cond = if skip_first { "if page-num > 1" } else { "if true" };
            out.push_str(&format!(
                r##"  header: context {{
    let page-num = counter(page).get().first()
    let total-pages = counter(page).final().first()
    {cond} {{
      grid(
        columns: (1fr, 1fr, 1fr),
        align: (left + horizon, center + horizon, right + horizon),
        {slot_left},
        {slot_center},
        {slot_right},
      ){rule}
    }}
  }},
"##
            ));
        }

        // Footer slots
        let default_footer_center = if is_slide {
            ""
        } else {
            frontmatter.footer.as_deref().unwrap_or("{page}")
        };
        let default_footer_right = if is_slide {
            if frontmatter.paginate.unwrap_or(true) {
                "{page}"
            } else {
                ""
            }
        } else {
            ""
        };
        let default_footer_left = if is_slide {
            frontmatter.footer.as_deref().unwrap_or("")
        } else {
            ""
        };

        let f_left = options.footer_left.as_deref().unwrap_or(default_footer_left);
        let f_center = options.footer_center.as_deref().unwrap_or(default_footer_center);
        let f_right = options.footer_right.as_deref().unwrap_or(default_footer_right);

        let has_footer = !f_left.is_empty() || !f_center.is_empty() || !f_right.is_empty() || show_footer_rule;

        if has_footer {
            let slot_left = format_slot_to_typst(f_left, &safe_title, header_color);
            let slot_center = format_slot_to_typst(f_center, &safe_title, header_color);
            let slot_right = format_slot_to_typst(f_right, &safe_title, header_color);
            let rule = if show_footer_rule {
                format!("line(length: 100%, stroke: 0.3pt + {header_color})\n      v(4pt)\n      ")
            } else {
                "".to_string()
            };
            let cond = if skip_first { "if page-num > 1" } else { "if true" };
            out.push_str(&format!(
                r##"  footer: context {{
    let page-num = counter(page).get().first()
    let total-pages = counter(page).final().first()
    {cond} {{
      {rule}grid(
        columns: (1fr, 1fr, 1fr),
        align: (left + horizon, center + horizon, right + horizon),
        {slot_left},
        {slot_center},
        {slot_right},
      )
    }}
  }},
"##
            ));
        }
    }
    let body_fonts_default = [
        "Inter",
        "SF Pro Text",
        "PingFang SC",
        "Microsoft YaHei",
        "Noto Sans CJK SC",
        "STIX Two Text",
        "Apple Color Emoji",
        "Segoe UI Emoji",
        "Noto Color Emoji",
        "Twemoji Mozilla",
    ];
    let custom_body = options.body_font.as_deref().unwrap_or("").trim();
    let body_font_str = if !custom_body.is_empty() {
        let escaped_custom = escape_typst_string(custom_body);
        format!("(\"{}\", {})", escaped_custom, body_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
    } else {
        format!("({})", body_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
    };

    let code_fonts_default = [
        "Maple Mono NF CN",
        "Maple Mono CN",
        "Maple Mono SC NF",
        "Maple Mono NF",
        "Maple Mono",
        "Sarasa Mono SC",
        "Sarasa Gothic SC",
        "Cascadia Mono",
        "JetBrains Mono",
        "Fira Code",
        "Menlo",
        "Consolas",
        "PingFang SC",
        "DejaVu Sans Mono",
        "Apple Color Emoji",
        "Segoe UI Emoji",
        "Noto Color Emoji",
        "Twemoji Mozilla",
    ];
    let custom_code = options.code_font.as_deref().unwrap_or("").trim();
    let code_font_str = if !custom_code.is_empty() {
        let escaped_custom = escape_typst_string(custom_code);
        format!("(\"{}\", {})", escaped_custom, code_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
    } else {
        format!("({})", code_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
    };

    out.push_str(&format!(
        r##")

#set text(
  font: {body_font_str},
  size: {font_size}pt,
  fill: {text_color},
  lang: "zh"
)

#set par(
  justify: false,
  leading: 0.78em,
  spacing: 1.15em
)

#show raw: set text(font: {code_font_str}, size: 0.9em)

#show raw.where(block: false): it => box(
  fill: {code_bg},
  stroke: 0.5pt + {code_border},
  inset: (x: 4pt, y: 0pt),
  outset: (y: 3pt),
  radius: 3pt,
  it
)

#show raw.where(block: true): it => block(
  fill: {code_bg},
  stroke: 0.5pt + {code_border},
  inset: (x: 12pt, y: 10pt),
  radius: 6pt,
  width: 100%,
  it
)

#show heading: set text(fill: {heading_color}, weight: "bold")
#show heading.where(level: 1): set block(above: 1.6em, below: 0.9em)
#show heading.where(level: 2): set block(above: 1.3em, below: 0.7em)
#show heading.where(level: 3): set block(above: 1.1em, below: 0.6em)
#show heading.where(level: 4): set block(above: 1.0em, below: 0.5em)

#show link: it => text(fill: {link_color}, weight: "medium", underline(stroke: 0.5pt + {link_underline}, offset: 2.2pt, it))

// Math helper definitions for LaTeX / MiTeX compatibility
#let textmath(it) = text(it)
#let textmd(it) = text(weight: "regular", it)
#let textnormal(it) = text(style: "normal", weight: "regular", it)
#let textbf(it) = text(weight: "bold", it)
#let textit(it) = text(style: "italic", it)
#let textrm(it) = text(it)
#let textup(it) = text(style: "normal", it)
#let textsf(it) = text(it)
#let texttt(it) = text(it)
#let diff = math.partial
#let pmod(n) = $(mod #n)$
#let odot = sym.dot.o

#let mitexsqrt(..args) = {{
  if args.pos().len() == 1 {{
    math.sqrt(args.pos().at(0))
  }} else if args.pos().len() == 2 {{
    math.root(args.pos().at(0), args.pos().at(1))
  }} else {{
    math.sqrt(..args)
  }}
}}
#let mitexdisplay(it) = math.display(it)
#let mitexinline(it) = math.inline(it)
#let mitexmathbf(it) = math.bold(math.upright(it))
#let mitexmathit(it) = math.italic(it)
#let mitexmathrm(it) = math.upright(it)
#let mitexbold(it) = math.bold(math.upright(it))
#let mitexupright(it) = math.upright(it)
#let mitexitalic(it) = math.italic(it)
#let mitexsans(it) = math.sans(it)
#let mitexfrak(it) = math.frak(it)
#let mitexmono(it) = math.mono(it)
#let mitexcal(it) = math.cal(it)
#let mitexbb(it) = math.bb(it)
#let mitexnot(it) = math.cancel(angle: 20deg, it)
#let mitexset(it) = ${{it}}$
#let mitexlabel(..args) = none
#let mitextag(..args) = none
#let mitexcite(..args) = none
#let mitexref(..args) = none
#let mitexcaption(..args) = none
#let mitexcomment(..args) = none
#let mitexbibliography(..args) = none
#let operatornamewithlimits(it) = math.op(limits: true, math.upright(it))
#let zws = math.zws
#let mitexarray(arg0: ("l",), ..args) = {{
  let matrix = args.pos().map(row => if type(row) == array {{ row }} else {{ (row,) }} )
  let m = calc.max(..matrix.map(row => row.len()), 1)
  matrix = matrix.map(row => row + (m - row.len()) * (none,))
  pad(y: 0.2em, grid(
    columns: m,
    column-gutter: 0.5em,
    row-gutter: 0.5em,
    ..matrix.flatten().map(it => $it$)
  ))
}}


#set table(
  stroke: (x, y) => if y == 0 {{ (bottom: 1.5pt + {heading_color}) }} else {{ (bottom: 0.5pt + {table_stroke}) }},
  fill: (x, y) => if y == 0 {{ {table_header_bg} }} else {{ none }},
  inset: (x: 9pt, y: 7pt),
)

"##,
        font_size = if is_slide_mode && options.font_size <= 12.0 {
            16.0
        } else {
            options.font_size
        },
        text_color = text_color,
        code_bg = code_bg,
        code_border = code_border,
        heading_color = heading_color,
        table_stroke = table_stroke,
        table_header_bg = table_header_bg,
        body_font_str = body_font_str,
        code_font_str = code_font_str
    ));

    if is_fluid {
        out.push_str("#v(12pt)\n");
    }

    // 2. Parse Markdown AST with pulldown-cmark
    let mut parser_opts = Options::empty();
    parser_opts.insert(Options::ENABLE_TABLES);
    parser_opts.insert(Options::ENABLE_FOOTNOTES);
    parser_opts.insert(Options::ENABLE_STRIKETHROUGH);
    parser_opts.insert(Options::ENABLE_TASKLISTS);
    parser_opts.insert(Options::ENABLE_MATH);
    parser_opts.insert(Options::ENABLE_HEADING_ATTRIBUTES);
    parser_opts.insert(Options::ENABLE_GFM);

    let parser = Parser::new_ext(markdown_body, parser_opts);

    let mut in_code_block = false;
    let mut code_block_lang = String::new();
    let mut code_block_content = String::new();
    let mut in_table_head = false;
    let mut list_depth: usize = 0;
    let mut link_stack: Vec<bool> = Vec::new();
    let mut current_image: Option<(String, String)> = None;
    let mut current_heading: Option<(HeadingLevel, String)> = None;
    let mut registered_slugs: HashSet<String> = HashSet::new();
    let mut referenced_anchors: HashSet<String> = HashSet::new();
    let custom_cache = options.image_cache_dir.as_deref().map(Path::new);
    let mut html_transpiler = HtmlTranspiler::new(is_dark, badge_bg, badge_stroke, badge_fg, custom_cache);

    for event in parser {
        match event {
            Event::Start(tag) => match tag {
                Tag::Paragraph => {}
                Tag::Heading { level, .. } => {
                    let prefix = match level {
                        HeadingLevel::H1 => "= ",
                        HeadingLevel::H2 => "== ",
                        HeadingLevel::H3 => "=== ",
                        HeadingLevel::H4 => "==== ",
                        HeadingLevel::H5 => "===== ",
                        HeadingLevel::H6 => "====== ",
                    };
                    out.push_str(prefix);
                    current_heading = Some((level, String::new()));
                }
                Tag::BlockQuote(kind) => {
                    let callout_info = match kind {
                        Some(pulldown_cmark::BlockQuoteKind::Note) => {
                            if is_dark {
                                Some(("Note", "rgb(\"#58a6ff\")", "rgb(\"#13233a\")", "rgb(\"#58a6ff\")"))
                            } else {
                                Some(("Note", "rgb(\"#0969da\")", "rgb(\"#f0f7ff\")", "rgb(\"#0969da\")"))
                            }
                        }
                        Some(pulldown_cmark::BlockQuoteKind::Tip) => {
                            if is_dark {
                                Some(("Tip", "rgb(\"#3fb950\")", "rgb(\"#132d1e\")", "rgb(\"#3fb950\")"))
                            } else {
                                Some(("Tip", "rgb(\"#1a7f37\")", "rgb(\"#f0fdf4\")", "rgb(\"#1a7f37\")"))
                            }
                        }
                        Some(pulldown_cmark::BlockQuoteKind::Important) => {
                            if is_dark {
                                Some(("Important", "rgb(\"#a371f7\")", "rgb(\"#251938\")", "rgb(\"#bc8cff\")"))
                            } else {
                                Some(("Important", "rgb(\"#8250df\")", "rgb(\"#fbf5ff\")", "rgb(\"#8250df\")"))
                            }
                        }
                        Some(pulldown_cmark::BlockQuoteKind::Warning) => {
                            if is_dark {
                                Some(("Warning", "rgb(\"#d29922\")", "rgb(\"#342813\")", "rgb(\"#d29922\")"))
                            } else {
                                Some(("Warning", "rgb(\"#9a6700\")", "rgb(\"#fffbeb\")", "rgb(\"#9a6700\")"))
                            }
                        }
                        Some(pulldown_cmark::BlockQuoteKind::Caution) => {
                            if is_dark {
                                Some(("Caution", "rgb(\"#f85149\")", "rgb(\"#38171c\")", "rgb(\"#ff7b72\")"))
                            } else {
                                Some(("Caution", "rgb(\"#cf222e\")", "rgb(\"#fff1f0\")", "rgb(\"#cf222e\")"))
                            }
                        }
                        _ => None,
                    };

                    if let Some((label, border_c, bg_c, title_c)) = callout_info {
                        out.push_str(&format!(
                            "\n#block(width: 100%, stroke: (left: 3.5pt + {border_c}), inset: (x: 12pt, y: 8pt), radius: (right: 4pt), fill: {bg_c})[\n#text(fill: {title_c}, weight: \"bold\")[{label}]\n\n"
                        ));
                    } else {
                        out.push_str(&format!(
                            "\n#block(width: 100%, stroke: (left: 3.5pt + {quote_border}), inset: (x: 12pt, y: 8pt), radius: (right: 4pt), fill: {quote_bg})[\n"
                        ));
                    }
                }
                Tag::CodeBlock(kind) => {
                    in_code_block = true;
                    code_block_content.clear();
                    code_block_lang = match kind {
                        pulldown_cmark::CodeBlockKind::Fenced(lang) => lang.to_string(),
                        pulldown_cmark::CodeBlockKind::Indented => String::new(),
                    };
                }
                Tag::List(first_number) => {
                    list_depth += 1;
                    if let Some(start) = first_number {
                        if start > 1 {
                            out.push_str(&format!("#set enum(start: {})\n", start));
                        }
                    }
                }
                Tag::Item => {
                    let indent = "  ".repeat(list_depth.saturating_sub(1));
                    out.push_str(&format!("{}- ", indent));
                }
                Tag::Emphasis => out.push('_'),
                Tag::Strong => out.push('*'),
                Tag::Strikethrough => out.push_str("#strike["),
                Tag::Link { dest_url, .. } => {
                    let dest = dest_url.trim();
                    if dest.is_empty() {
                        link_stack.push(false);
                        out.push('[');
                    } else if dest.starts_with('#') {
                        link_stack.push(true);
                        let anchor = dest[1..].trim();
                        let decoded = decode_percent(anchor);
                        let target = if decoded != anchor { decoded } else { anchor.to_string() };
                        referenced_anchors.insert(target.clone());
                        let escaped_target = escape_typst_string(&target);
                        out.push_str(&format!("#link(label(\"{escaped_target}\"))["));
                    } else {
                        link_stack.push(true);
                        let escaped_dest = escape_typst_string(dest);
                        out.push_str(&format!("#link(\"{escaped_dest}\")["));
                    }
                }
                Tag::Image { dest_url, .. } => {
                    current_image = Some((dest_url.to_string(), String::new()));
                }
                Tag::Table(aligns) => {
                    let cols_count = aligns.len();
                    let align_str: Vec<&str> = aligns
                        .iter()
                        .map(|a| match a {
                            Alignment::Left => "left",
                            Alignment::Center => "center",
                            Alignment::Right => "right",
                            Alignment::None => "auto",
                        })
                        .collect();
                    out.push_str(&format!(
                        "\n#align(center)[#table(\n  columns: {},\n  align: ({}),\n",
                        cols_count,
                        align_str.join(", ")
                    ));
                }

                Tag::TableHead => {
                    in_table_head = true;
                }
                Tag::TableRow => {}
                Tag::TableCell => {
                    out.push_str("  [");
                    if in_table_head {
                        out.push('*');
                    }
                }
                Tag::FootnoteDefinition(label) => {
                    out.push_str(&format!("#footnote[{}: ", label));
                }
                _ => {}
            },
            Event::End(tag_end) => match tag_end {
                TagEnd::Paragraph => {
                    out.push_str("\n\n");
                }
                TagEnd::Heading(_) => {
                    if let Some((_, h_text)) = current_heading.take() {
                        let (primary, secondary) = slugify_heading(&h_text);
                        if !primary.is_empty() {
                            let escaped_primary = escape_typst_string(&primary);
                            out.push_str(&format!(" #label(\"{escaped_primary}\")"));
                            registered_slugs.insert(primary);
                            for sec in secondary {
                                let escaped_sec = escape_typst_string(&sec);
                                out.push_str(&format!(" #metadata(none) #label(\"{escaped_sec}\")"));
                                registered_slugs.insert(sec);
                            }
                        }
                    }
                    out.push_str("\n\n");
                }
                TagEnd::BlockQuote(_) => {
                    out.push_str("]\n\n");
                }
                TagEnd::CodeBlock => {
                    in_code_block = false;
                    let lang = code_block_lang.trim().to_lowercase();
                    if lang == "mermaid" {
                        // Render Mermaid diagram to SVG with theme awareness
                        let rendered = render_mermaid(&code_block_content, is_dark);
                        let file_path = PathBuf::from(&rendered.virtual_filename);
                        virtual_files.insert(file_path, rendered.svg_bytes);
                        let (diagram_fill, diagram_stroke) = if is_dark {
                            ("rgb(\"#1e1e1e\")", "rgb(\"#333842\")")
                        } else {
                            ("rgb(\"#ffffff\")", "rgb(\"#e1e4e8\")")
                        };
                        out.push_str(&format!(
                            "\n#align(center)[#block(fill: {diagram_fill}, stroke: 0.5pt + {diagram_stroke}, radius: 6pt, inset: (x: 8pt, y: 6pt))[#image(\"{}\", width: 92%)]]\n\n",
                            rendered.virtual_filename
                        ));
                    } else {
                        out.push_str(&format!("```{}\n{}```\n\n", code_block_lang, code_block_content));
                    }
                }
                TagEnd::List(_) => {
                    list_depth = list_depth.saturating_sub(1);
                    out.push('\n');
                }
                TagEnd::Item => {
                    out.push('\n');
                }
                TagEnd::Emphasis => out.push('_'),
                TagEnd::Strong => out.push('*'),
                TagEnd::Strikethrough => out.push(']'),
                TagEnd::Link => {
                    link_stack.pop();
                    out.push(']');
                }
                TagEnd::Image => {
                    if let Some((url, alt_raw)) = current_image.take() {
                        let alt = if alt_raw.trim().is_empty() {
                            "图片".to_string()
                        } else {
                            alt_raw.trim().to_string()
                        };
                        let escaped_alt = escape_typst_text(&alt);
                        let in_link = link_stack.iter().any(|&active| active);

                        let is_url = url.starts_with("http://") || url.starts_with("https://");
                        let resolved_image = if is_url {
                            find_cached_image_file(custom_cache, &url)
                        } else {
                            Some(url.clone())
                        };

                        if let Some(target_path) = resolved_image {
                            let (img_stroke, img_radius) = if is_dark {
                                ("0.5pt + rgb(\"#383e4a\")", "4pt")
                            } else {
                                ("none", "4pt")
                            };
                            let escaped_target_path = escape_typst_string(&target_path);
                            out.push_str(&format!("\n#align(center)[#block(radius: {img_radius}, stroke: {img_stroke}, clip: true)[#image(\"{escaped_target_path}\")]]\n\n"));
                        } else {
                            // Remote image not yet cached: render elegant clickable placeholder badge
                            if in_link {
                                out.push_str(&format!(
                                    "#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 5pt, y: 2.5pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[🖼️ {}]]",
                                    escaped_alt
                                ));
                            } else {
                                let escaped_url = escape_typst_string(&url);
                                out.push_str(&format!(
                                    "#link(\"{escaped_url}\")[#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 5pt, y: 2.5pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[🖼️ {}]]]",
                                    escaped_alt
                                ));
                            }
                        }
                    }
                }
                TagEnd::Table => {
                    out.push_str(")]\n\n");
                }
                TagEnd::TableHead => {
                    in_table_head = false;
                }
                TagEnd::TableRow => {}
                TagEnd::TableCell => {
                    if in_table_head {
                        out.push('*');
                    }
                    out.push_str("],\n");
                }
                TagEnd::FootnoteDefinition => {
                    out.push_str("]\n");
                }
                _ => {}
            },
            Event::Text(text) => {
                if let Some((_, ref mut h_text)) = current_heading {
                    h_text.push_str(&text);
                }
                if let Some((_, ref mut alt_text)) = current_image {
                    alt_text.push_str(&text);
                } else if in_code_block {
                    code_block_content.push_str(&text);
                } else {
                    out.push_str(&escape_typst_text(&text));
                }
            }
            Event::Code(code) => {
                if let Some((_, ref mut h_text)) = current_heading {
                    h_text.push_str(&code);
                }
                if let Some((_, ref mut alt_text)) = current_image {
                    alt_text.push('`');
                    alt_text.push_str(&code);
                    alt_text.push('`');
                } else {
                    out.push('`');
                    out.push_str(&code);
                    out.push('`');
                }
            }
            Event::InlineMath(latex) => {
                out.push_str(&transpile_latex_math(&latex, false));
            }
            Event::DisplayMath(latex) => {
                out.push_str(&transpile_latex_math(&latex, true));
            }
            Event::Rule => {
                if is_slide_mode {
                    out.push_str("\n#pagebreak()\n\n");
                } else {
                    out.push_str(&format!("\n#line(length: 100%, stroke: 0.5pt + {rule_color})\n\n"));
                }
            }
            Event::TaskListMarker(checked) => {
                if checked {
                    out.push_str("☑ ");
                } else {
                    out.push_str("☐ ");
                }
            }

            Event::SoftBreak => out.push('\n'),
            Event::HardBreak => out.push_str("\\ \n"),
            Event::Html(raw) | Event::InlineHtml(raw) => {
                html_transpiler.transpile_chunk(&raw, &mut out);
            }
            _ => {}
        }
    }

    html_transpiler.finish(&mut out);

    // Safely emit metadata anchors for any referenced links that don't match a defined heading
    // This prevents Typst compilation errors if an external markdown contains broken or missing local anchors
    for anchor in &referenced_anchors {
        if !registered_slugs.contains(anchor) {
            let escaped_anchor = escape_typst_string(anchor);
            out.push_str(&format!("\n#metadata(none) #label(\"{escaped_anchor}\")\n"));
        }
    }

    ParsedDocument {
        typst_source: out,
        virtual_files,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_markdown_full_suite() {
        let md = r#"
# Heading 1

This is a paragraph with **bold**, *italic*, and `code`.

Here is an inline formula: $E = mc^2$ and a block formula:

$$
\int_0^1 x^2 dx = \frac{1}{3}
$$

> [!NOTE]
> This is a callout note.

- [x] Finished task
- [ ] Todo task

```mermaid
graph TD;
  A[Start] --> B[Finish];
```

| Syntax | Description |
| :--- | :--- |
| Header | Title |
| Paragraph | Text |

---
"#;
        let options = RenderOptions::default();
        let parsed = convert_markdown_to_typst(md, "Test Doc", &options);

        assert!(parsed.typst_source.contains("Heading 1"));
        assert!(parsed.typst_source.contains("$"));
        assert!(parsed.virtual_files.len() == 1, "Mermaid diagram should generate 1 virtual file");
        for (name, bytes) in &parsed.virtual_files {
            println!("Virtual file: {:?}, bytes: {}", name, bytes.len());
            assert!(bytes.len() > 100);
        }
    }

    #[test]
    fn test_heading_with_quotes() {
        let md = r#"
# heading with "quotes" inside

## "Fully Quoted Heading"

### Heading with mixed 'single' and "double" quotes and \ backslash

- [Link 1](#heading-with-quotes-inside)
- [Link 2](#fully-quoted-heading)
- [Link 3](#heading with "quotes" inside)
- [Broken Link](#missing "quotes" here)

Some body text with "quotes" inside.
"#;
        let options = RenderOptions::default();
        let parsed = convert_markdown_to_typst(md, "Test Doc", &options);
        println!("Generated Typst:\n{}", parsed.typst_source);

        // Verify that quotes inside label(...) strings are properly escaped as \"
        assert!(parsed.typst_source.contains(r#"#label("heading with \"quotes\" inside")"#));
        assert!(parsed.typst_source.contains(r#"#label("\"Fully Quoted Heading\"")"#));
        // Verify that backslashes and mixed quotes inside label(...) strings are properly escaped
        assert!(parsed.typst_source.contains(r#"#label("Heading with mixed 'single' and \"double\" quotes and \\ backslash")"#));

        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, ".", parsed.virtual_files);
        assert!(res.is_ok(), "Typst compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }

    #[test]
    fn test_parse_dimension() {
        assert_eq!(parse_dimension("128"), Some("128pt".to_string()));
        assert_eq!(parse_dimension("128px"), Some("128pt".to_string()));
        assert_eq!(parse_dimension("128pt"), Some("128pt".to_string()));
        assert_eq!(parse_dimension("50%"), Some("50%".to_string()));
        assert_eq!(parse_dimension("12.5px"), Some("12.5pt".to_string()));

        // Edge cases where Rust's f64 parsing accepts trailing dot / scientific notation / signs
        assert_eq!(parse_dimension("5."), Some("5pt".to_string()));
        assert_eq!(parse_dimension("5.px"), Some("5pt".to_string()));
        assert_eq!(parse_dimension(".5"), Some("0.5pt".to_string()));
        assert_eq!(parse_dimension(".5px"), Some("0.5pt".to_string()));
        assert_eq!(parse_dimension("1e5"), Some("100000pt".to_string()));
        assert_eq!(parse_dimension("1e5px"), Some("100000pt".to_string()));
        assert_eq!(parse_dimension("+5"), Some("5pt".to_string()));
        assert_eq!(parse_dimension("+5px"), Some("5pt".to_string()));
        assert_eq!(parse_dimension("50.%"), Some("50%".to_string()));
        assert_eq!(parse_dimension(".5%"), Some("0.5%".to_string()));

        // Invalid / malicious inputs should be discarded (None)
        assert_eq!(parse_dimension("auto"), None);
        assert_eq!(parse_dimension("1) ; #import ..."), None);
        assert_eq!(parse_dimension("-10px"), None);
        assert_eq!(parse_dimension("0"), None);
        assert_eq!(parse_dimension("0px"), None);
        assert_eq!(parse_dimension(""), None);
        assert_eq!(parse_dimension("   "), None);

        // Verify HTML img with trailing dot dimension compiles through Typst without error
        let html_img_md = r#"<img src="docs/images/app_logo.png" width="5.px" height="5." />"#;
        let parsed = convert_markdown_to_typst(html_img_md, "Trailing Dot", &RenderOptions::default());
        assert!(parsed.typst_source.contains("width: 5pt"));
        assert!(parsed.typst_source.contains("height: 5pt"));
        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, "..", parsed.virtual_files);
        assert!(res.is_ok(), "Trailing dot dimension failed to compile: {:?}", res.err());
    }

    #[test]
    fn test_heading_slugs_and_anchor_links() {
        let md = r#"
## 目录
- [1. 协议概述与物理层体系架构](#1-协议概述与物理层体系架构)
- [1.1 物理背景与星际中继需求](#11-物理背景与星际中继需求)
- [未定义链接](#nonexistent-anchor)

## 1. 协议概述与物理层体系架构

### 1.1 物理背景与星际中继需求
"#;
        let options = RenderOptions::default();
        let parsed = convert_markdown_to_typst(md, "Test Doc", &options);

        // Verify label attachment
        assert!(parsed.typst_source.contains("#label(\"1-协议概述与物理层体系架构\")"));
        assert!(parsed.typst_source.contains("#label(\"11-物理背景与星际中继需求\")"));

        // Verify link generation to label
        assert!(parsed.typst_source.contains("#link(label(\"1-协议概述与物理层体系架构\"))"));
        assert!(parsed.typst_source.contains("#link(label(\"11-物理背景与星际中继需求\"))"));

        // Verify nonexistent anchor is safely defined as metadata
        assert!(parsed.typst_source.contains("#label(\"nonexistent-anchor\")"));

        // Verify beautiful link styling is present in preamble
        assert!(parsed.typst_source.contains("#show link: it => text"));

        // Verify full compilation to PDF succeeds
        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, ".", parsed.virtual_files);
        assert!(res.is_ok(), "Typst compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));

        // Verify that headings with dots or emojis (like v1.0.0 or 📄 开源许可证) never emit stray brackets
        let heading_md = "### v1.0.0\n\n## 📄 开源许可证\n";
        let heading_parsed = convert_markdown_to_typst(heading_md, "Heading Test", &options);
        assert!(!heading_parsed.typst_source.contains("[#metadata"), "Heading must not contain bracketed metadata");
        assert!(!heading_parsed.typst_source.contains("[ ]"), "Heading must not contain stray brackets");

        let heading_res = crate::compiler::engine::compile_typst_to_pdf(&heading_parsed.typst_source, ".", heading_parsed.virtual_files);
        assert!(heading_res.is_ok());
    }

    #[test]
    fn test_convert_markdown_dark_mode() {
        let md = r#"
# Dark Mode Test Document

> [!TIP]
> This tip should be rendered with refined dark palette.

> [!WARNING]
> Warning callout in dark mode.

```mermaid
graph TD
  A[Client] --> B[Server]
```

---

Local image with dark border:
![Test Image](docs/images/app_logo.png)
"#;
        let options = RenderOptions {
            theme: "dark".to_string(),
            ..Default::default()
        };
        let parsed = convert_markdown_to_typst(md, "Dark Doc", &options);

        // Check dark mode colors in preamble
        assert!(parsed.typst_source.contains("fill: rgb(\"#1e1e1e\")"));
        assert!(parsed.typst_source.contains("stroke: 0.5pt + rgb(\"#383e4a\")"));

        // Check dark callout styling
        assert!(parsed.typst_source.contains("rgb(\"#3fb950\")")); // Tip border
        assert!(parsed.typst_source.contains("rgb(\"#132d1e\")")); // Tip bg
        assert!(parsed.typst_source.contains("rgb(\"#d29922\")")); // Warning border

        // Check dark mermaid diagram
        assert!(parsed.virtual_files.len() == 1);
        for (name, _) in &parsed.virtual_files {
            assert!(name.to_string_lossy().contains("mermaid_dark_"));
        }
    }

    #[test]
    fn test_fluid_mode_uses_auto_height_for_zero_blank_space() {
        let fluid_opts = RenderOptions {
            mode: "fluid".to_string(),
            ..Default::default()
        };

        // 1. Short document uses auto height and bottom padding
        let short_md = "# Quick Note\n\nShort content.";
        let short_parsed = convert_markdown_to_typst(short_md, "Short", &fluid_opts);
        assert!(short_parsed.typst_source.contains("height: auto"));
        assert!(short_parsed.typst_source.contains("bottom: 56pt"));

        // 2. Medium/Long document also uses auto height so that the final page never has blank void
        let mut long_md = String::new();
        for i in 0..100 {
            long_md.push_str(&format!("## Section {}\n\nThis is paragraph content for section {}.\n\n", i, i));
        }
        let long_parsed = convert_markdown_to_typst(&long_md, "Long", &fluid_opts);
        assert!(long_parsed.typst_source.contains("height: auto"));
        assert!(long_parsed.typst_source.contains("bottom: 56pt"));
    }

    #[test]
    fn test_html_readme_header() {
        let md = r#"<div align="center">
  <img src="docs/images/app_logo.png" width="128" height="128" alt="超好读 Logo" />
  <h1>超好读 (SuperGoodViewer) 🚀</h1>
  <p><strong>只读 Markdown 矢量排版桌面阅读器</strong></p>
  <p><em>Publication-Grade Typography, Pixel-Perfect Consistency, Zero-WebView Desktop Reader.</em></p>
</div>"#;
        let options = RenderOptions::default();
        let parsed = convert_markdown_to_typst(md, "README", &options);
        println!("Generated Typst:\n{}", parsed.typst_source);

        assert!(parsed.typst_source.contains("#align(center)"));
        assert!(parsed.typst_source.contains("#image(\"docs/images/app_logo.png\""));
        assert!(parsed.typst_source.contains("width: 128pt"));
        assert!(parsed.typst_source.contains("height: 128pt"));
        assert!(parsed.typst_source.contains("超好读 (SuperGoodViewer) 🚀"));

        // Test actual compilation with the real docs/images/app_logo.png from repo root
        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, "..", parsed.virtual_files);
        assert!(res.is_ok(), "Typst compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
        println!("README header compiled PDF size: {} bytes", pdf.len());
        assert!(pdf.len() > 10_000);
    }

    #[test]
    fn test_extract_url_extension() {
        assert_eq!(extract_url_extension("https://cdn.x/.png-assets/a.jpg"), "jpg");
        assert_eq!(extract_url_extension("https://cdn.x/.png-assets/a.jpeg?token=123"), "jpg");
        assert_eq!(extract_url_extension("https://cdn.x/vector.svg"), "svg");
        assert_eq!(extract_url_extension("https://cdn.x/animation.gif"), "gif");
        assert_eq!(extract_url_extension("https://cdn.x/photo.webp"), "webp");
        assert_eq!(extract_url_extension("https://mmbiz.qpic.cn/sz_mmbiz_png/test/640?wx_fmt=png"), "png");
        assert_eq!(extract_url_extension("https://mmbiz.qpic.cn/sz_mmbiz_jpeg/test/640?wx_fmt=jpeg"), "jpg");
        assert_eq!(extract_url_extension("https://example.com/asset"), "png"); // default fallback
    }

    #[test]
    fn test_remote_image_caching_and_rendering() {
        let temp_dir = std::env::temp_dir().join(format!("sgv_test_cache_{}", std::process::id()));
        let _ = std::fs::create_dir_all(&temp_dir);

        let wechat_url = "https://mmbiz.qpic.cn/sz_mmbiz_png/isolated_test_uuid/640?wx_fmt=png";
        let md = format!("![Architecture Diagram]({wechat_url})");
        let mut options = RenderOptions::default();
        options.image_cache_dir = Some(temp_dir.to_string_lossy().to_string());

        // 1. When not cached in temp_dir, it renders an elegant placeholder badge
        let parsed_uncached = convert_markdown_to_typst(&md, "Blog", &options);
        assert!(parsed_uncached.typst_source.contains("🖼️ Architecture Diagram"));

        // 2. Mock a cached file strictly inside temp_dir
        let cache_filename = url_to_cache_filename(wechat_url);
        let cache_file_path = temp_dir.join(&cache_filename);
        let _ = std::fs::write(&cache_file_path, b"mock_cached_image_bytes");

        let parsed_cached = convert_markdown_to_typst(&md, "Blog", &options);
        assert!(parsed_cached.typst_source.contains(&format!("#image(\"{cache_filename}\")")));

        // Clean up temp_dir
        let _ = std::fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_frontmatter_extraction() {
        let md = r#"---
marp: true
theme: gaia
size: 16:9
paginate: true
header: "Company Confidential"
footer: "All Rights Reserved"
page_format: slide_16_9
---

# Hello Marp

This is slide content.
"#;
        let (fm, body) = extract_frontmatter(md);
        assert!(fm.marp);
        assert_eq!(fm.theme.as_deref(), Some("gaia"));
        assert_eq!(fm.size.as_deref(), Some("16:9"));
        assert_eq!(fm.paginate, Some(true));
        assert_eq!(fm.header.as_deref(), Some("Company Confidential"));
        assert_eq!(fm.footer.as_deref(), Some("All Rights Reserved"));
        assert_eq!(fm.page_format.as_deref(), Some("slide_16_9"));
        assert!(body.trim_start().starts_with("# Hello Marp"));
    }

    #[test]
    fn test_marp_presentation_compiles_to_pdf() {
        let md = r#"---
marp: true
size: 16:9
paginate: true
header: "SuperGoodViewer Tech Talk"
footer: "Slide"
---

# Title Slide: Architecture Overview
Speaker: SuperGoodViewer Team

---

# Second Slide: High Performance
- Pure Rust Typst Core
- Google PDFium Hardware Rasterization
- 0ms PDF Export

---

# Third Slide: Mathematical Rigor
$ E = m c^2 $
$ integral_0^1 x^2 dif x = 1/3 $
"#;
        let options = RenderOptions::default();
        let parsed = convert_markdown_to_typst(md, "Tech Talk", &options);

        // Check Typst dimensions
        assert!(parsed.typst_source.contains("width: 960pt"));
        assert!(parsed.typst_source.contains("height: 540pt"));
        // Check rule turns into pagebreak in slide mode
        assert!(parsed.typst_source.contains("#pagebreak()"));

        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, ".", parsed.virtual_files);
        assert!(res.is_ok(), "Slide compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
        assert!(pdf.len() > 1000);
    }

    #[test]
    fn test_a4_landscape_and_custom_header_footer() {
        let md = r#"# Data Report
A table with wide metrics.
"#;
        let mut options = RenderOptions::default();
        options.page_format = Some("a4_landscape".to_string());
        options.header_left = Some("Confidential Report".to_string());
        options.header_right = Some("{title}".to_string());
        options.footer_center = Some("Page {page} of {total}".to_string());
        options.show_header_rule = Some(true);
        options.show_footer_rule = Some(true);

        let parsed = convert_markdown_to_typst(md, "Q3 Metrics", &options);
        assert!(parsed.typst_source.contains("width: 841.89pt"));
        assert!(parsed.typst_source.contains("height: 595.28pt"));
        assert!(parsed.typst_source.contains("Confidential Report"));
        assert!(parsed.typst_source.contains("Q3 Metrics"));
        assert!(parsed.typst_source.contains("#page-num"));
        assert!(parsed.typst_source.contains("#total-pages"));

        let res = crate::compiler::engine::compile_typst_to_pdf(&parsed.typst_source, ".", parsed.virtual_files);
        assert!(res.is_ok(), "A4 Landscape compilation failed: {:?}", res.err());
        let pdf = res.unwrap();
        assert!(pdf.starts_with(b"%PDF-"));
    }
}
