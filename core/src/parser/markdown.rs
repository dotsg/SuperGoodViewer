use std::collections::HashMap;
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

pub fn convert_markdown_to_typst(
    markdown: &str,
    title: &str,
    options: &RenderOptions,
) -> ParsedDocument {
    let mut virtual_files = HashMap::new();
    let mut out = String::with_capacity(markdown.len() * 2);

    // 1. Inject Modern Typst Preamble Template
    let bg_color = if options.theme == "dark" { "rgb(\"#1e1e1e\")" } else { "rgb(\"#ffffff\")" };
    let text_color = if options.theme == "dark" { "rgb(\"#d4d4d4\")" } else { "rgb(\"#1a1a1a\")" };
    let header_color = if options.theme == "dark" { "rgb(\"#808080\")" } else { "rgb(\"#666666\")" };
    let heading_color = if options.theme == "dark" { "rgb(\"#ffffff\")" } else { "rgb(\"#000000\")" };
    let code_bg = if options.theme == "dark" { "rgb(\"#2d2d2d\")" } else { "rgb(\"#f5f5f5\")" };
    let table_stroke = if options.theme == "dark" { "rgb(\"#404040\")" } else { "rgb(\"#e0e0e0\")" };

    let is_fluid = options.mode == "fluid";
    let page_width = if is_fluid {
        format!("{}pt", options.viewport_width)
    } else {
        "595.28pt".to_string()
    };
    let page_height = if is_fluid { "auto".to_string() } else { "841.89pt".to_string() };
    let page_margin = if is_fluid {
        "(x: 24pt, top: 24pt, bottom: 24pt)"
    } else {
        "(x: 2cm, top: 2.5cm, bottom: 2.5cm)"
    };

    out.push_str(&format!(
        r##"// Auto-generated Typst markup by SoGoodViewer
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

    out.push_str(&format!(
        r##")

#set text(
  font: ("Inter", "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "STIX Two Text"),
  size: {font_size}pt,
  fill: {text_color},
  spacing: 120%,
  lang: "zh"
)

#show raw.where(block: false): it => box(
  fill: {code_bg},
  inset: (x: 3pt, y: 0pt),
  outset: (y: 3pt),
  radius: 3pt,
  text(size: 0.9em, it)
)

#show raw.where(block: true): it => block(
  fill: {code_bg},
  inset: 10pt,
  radius: 6pt,
  width: 100%,
  text(size: 0.9em, it)
)

#show heading: it => block(
  below: 0.8em,
  above: 1.4em,
  text(fill: {heading_color}, weight: "bold", it.body)
)

// Math helper definitions for LaTeX compatibility
#let textmath(body) = text(body)
#let mitexsqrt(body) = math.sqrt(body)
#let mitexdisplay(body) = math.display(body)
#let mitextag(body) = none
#let zws = []


#set table(

  stroke: (x, y) => if y == 0 {{ (bottom: 1.5pt + {heading_color}) }} else {{ (bottom: 0.5pt + {table_stroke}) }},
  fill: (x, y) => if y == 0 {{ none }} else {{ none }},
)

"##,
        font_size = options.font_size,
        text_color = text_color,
        code_bg = code_bg,
        heading_color = heading_color,
        table_stroke = table_stroke
    ));

    // 2. Parse Markdown AST with pulldown-cmark
    let mut parser_opts = Options::empty();
    parser_opts.insert(Options::ENABLE_TABLES);
    parser_opts.insert(Options::ENABLE_FOOTNOTES);
    parser_opts.insert(Options::ENABLE_STRIKETHROUGH);
    parser_opts.insert(Options::ENABLE_TASKLISTS);
    parser_opts.insert(Options::ENABLE_MATH);
    parser_opts.insert(Options::ENABLE_HEADING_ATTRIBUTES);

    let parser = Parser::new_ext(markdown, parser_opts);

    let mut in_code_block = false;
    let mut code_block_lang = String::new();
    let mut code_block_content = String::new();
    let mut in_table_head = false;
    let mut list_depth: usize = 0;




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
                }
                Tag::BlockQuote(kind) => {
                    let callout_info = match kind {
                        Some(pulldown_cmark::BlockQuoteKind::Note) => Some(("Note", "blue")),
                        Some(pulldown_cmark::BlockQuoteKind::Tip) => Some(("Tip", "green")),
                        Some(pulldown_cmark::BlockQuoteKind::Important) => Some(("Important", "purple")),
                        Some(pulldown_cmark::BlockQuoteKind::Warning) => Some(("Warning", "orange")),
                        Some(pulldown_cmark::BlockQuoteKind::Caution) => Some(("Caution", "red")),
                        _ => None,
                    };

                    if let Some((label, color)) = callout_info {
                        out.push_str(&format!(
                            "\n#block(width: 100%, stroke: (left: 3pt + {color}), inset: (left: 10pt, y: 6pt), fill: {color}.lighten(90%))[\n*{}*\n\n",
                            label
                        ));
                    } else {
                        out.push_str("\n#block(width: 100%, stroke: (left: 2.5pt + gray), inset: (left: 10pt, y: 4pt))[\n");
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
                    out.push_str(&format!("#link(\"{}\")[", dest_url));
                }
                Tag::Image { dest_url, .. } => {
                    out.push_str(&format!("#image(\"{}\")", dest_url));
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
                    out.push_str("\n\n");
                }
                TagEnd::BlockQuote(_) => {
                    out.push_str("]\n\n");
                }
                TagEnd::CodeBlock => {
                    in_code_block = false;
                    let lang = code_block_lang.trim().to_lowercase();
                    if lang == "mermaid" {
                        // Render Mermaid diagram to SVG
                        let rendered = render_mermaid(&code_block_content);
                        let file_path = PathBuf::from(&rendered.virtual_filename);
                        virtual_files.insert(file_path, Bytes::new(rendered.svg_bytes));
                        out.push_str(&format!(
                            "\n#align(center)[#image(\"{}\", width: 90%)]\n\n",
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
                TagEnd::Link => out.push(']'),
                TagEnd::Image => {}
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
                if in_code_block {
                    code_block_content.push_str(&text);
                } else {
                    out.push_str(&escape_typst_text(&text));
                }
            }
            Event::Code(code) => {
                out.push('`');
                out.push_str(&code);
                out.push('`');
            }
            Event::InlineMath(latex) => {
                out.push_str(&transpile_latex_math(&latex, false));
            }
            Event::DisplayMath(latex) => {
                out.push_str(&transpile_latex_math(&latex, true));
            }
            Event::Rule => {
                out.push_str("\n#line(length: 100%, stroke: 0.5pt + gray.lighten(50%))\n\n");
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
            _ => {}
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
}
