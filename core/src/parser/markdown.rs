use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
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

fn parse_dimension(val: &str) -> String {
    let s = val.trim();
    if s.ends_with('%') {
        s.to_string()
    } else if let Some(num) = s.strip_suffix("px") {
        format!("{}pt", num.trim())
    } else if let Some(num) = s.strip_suffix("pt") {
        format!("{}pt", num.trim())
    } else if s.chars().all(|c| c.is_ascii_digit() || c == '.') {
        format!("{}pt", s)
    } else {
        format!("{}pt", s)
    }
}

fn render_html_image(
    tag: &str,
    in_center: bool,
    is_dark: bool,
    badge_bg: &str,
    badge_stroke: &str,
    badge_fg: &str,
) -> String {
    let src = extract_html_attr(tag, "src").unwrap_or_default();
    if src.is_empty() {
        return String::new();
    }
    let alt = extract_html_attr(tag, "alt").unwrap_or_else(|| "图片".to_string());
    let width = extract_html_attr(tag, "width");
    let height = extract_html_attr(tag, "height");

    let is_url = src.starts_with("http://") || src.starts_with("https://");
    if is_url {
        let escaped_alt = escape_typst_text(&alt);
        return format!(
            "#link(\"{src}\")[#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 4pt, y: 2pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[🔗 {escaped_alt}]]]"
        );
    }

    let mut args = Vec::new();
    if let Some(w) = width {
        args.push(format!("width: {}", parse_dimension(&w)));
    }
    if let Some(h) = height {
        args.push(format!("height: {}", parse_dimension(&h)));
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

    let block_str = format!("#block(radius: {img_radius}, stroke: {img_stroke}, clip: true)[#image(\"{src}\"{args_str})]");
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
}

impl<'a> HtmlTranspiler<'a> {
    fn new(is_dark: bool, badge_bg: &'a str, badge_stroke: &'a str, badge_fg: &'a str) -> Self {
        Self {
            center_depth: 0,
            is_dark,
            badge_bg,
            badge_stroke,
            badge_fg,
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
                out.push_str(&format!("#link(\"{}\")[", href));
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

pub fn convert_markdown_to_typst(
    markdown: &str,
    title: &str,
    options: &RenderOptions,
) -> ParsedDocument {
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

    let is_fluid = options.mode == "fluid";
    let page_width = if is_fluid {
        format!("{}pt", options.viewport_width)
    } else {
        "595.28pt".to_string()
    };
    let page_height = if is_fluid { "auto".to_string() } else { "841.89pt".to_string() };
    let page_margin = if is_fluid {
        "(x: 24pt, top: 0pt, bottom: 56pt)"
    } else {
        "(x: 2cm, top: 2.5cm, bottom: 2.5cm)"
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

    if !is_fluid {
        out.push_str(&format!(
            r##"  header: context {{
    let page-num = counter(page).get().first()
    if page-num > 1 {{
      align(right, text(fill: {header_color}, size: 9pt)[{safe_title}])
    }}
  }},
  footer: context {{
    let page-num = counter(page).get().first()
    align(center, text(fill: {header_color}, size: 9pt)[#page-num])
  }},
"##,
            header_color = header_color,
            safe_title = escape_typst_text(title)
        ));
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
        format!("(\"{}\", {})", custom_body, body_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
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
        format!("(\"{}\", {})", custom_code, code_fonts_default.iter().map(|f| format!("\"{}\"", f)).collect::<Vec<_>>().join(", "))
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
        font_size = options.font_size,
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

    let parser = Parser::new_ext(markdown, parser_opts);

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
    let mut html_transpiler = HtmlTranspiler::new(is_dark, badge_bg, badge_stroke, badge_fg);

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
                        referenced_anchors.insert(anchor.to_string());
                        if decoded != anchor {
                            referenced_anchors.insert(decoded);
                        }
                        out.push_str(&format!("#link(label(\"{anchor}\"))["));
                    } else {
                        link_stack.push(true);
                        out.push_str(&format!("#link(\"{dest}\")["));
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
                            out.push_str(&format!(" #label(\"{primary}\")"));
                            registered_slugs.insert(primary);
                            for sec in secondary {
                                out.push_str(&format!(" [#metadata(none) #label(\"{sec}\")]"));
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
                        if is_url {
                            if in_link {
                                // Inside an outer #link(...)[...], render clean inline badge without nesting #link
                                out.push_str(&format!(
                                    "#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 4pt, y: 2pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[{}]]",
                                    escaped_alt
                                ));
                            } else {
                                out.push_str(&format!(
                                    "#link(\"{url}\")[#box(fill: {badge_bg}, stroke: 0.5pt + {badge_stroke}, radius: 3pt, inset: (x: 4pt, y: 2pt), baseline: 10%)[#text(size: 8pt, weight: \"medium\", fill: {badge_fg})[🔗 {}]]]",
                                    escaped_alt
                                ));
                            }
                        } else {
                            // Local file path (resolved by MemoryWorld against doc_dir)
                            let (img_stroke, img_radius) = if is_dark {
                                ("0.5pt + rgb(\"#383e4a\")", "4pt")
                            } else {
                                ("none", "4pt")
                            };
                            out.push_str(&format!("\n#align(center)[#block(radius: {img_radius}, stroke: {img_stroke}, clip: true)[#image(\"{url}\")]]\n\n"));
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
                out.push_str(&format!("\n#line(length: 100%, stroke: 0.5pt + {rule_color})\n\n"));
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
            out.push_str(&format!("\n[#metadata(none) #label(\"{anchor}\")]\n"));
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
}
