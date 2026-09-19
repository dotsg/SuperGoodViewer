use super::markdown::escape_typst_string;

/// LaTeX math to Typst math transpiler using `mitex`.

/// Converts a LaTeX math string to Typst math syntax.
/// If transpilation succeeds, returns the Typst math code.
/// If it fails, falls back gracefully to the original input (or raw text) to prevent compilation breakage.
/// Helper to preprocess \mathllap and \mathrlap using MiTeX's native `\iftypst ... \fi` pass-through,
/// avoiding any pollution of TeX commands like \mathinner or \mathpunct.
fn preprocess_laps(input: &str) -> String {
    if !input.contains(r"\mathllap") && !input.contains(r"\mathrlap") && !input.contains(r"\smash") {
        return input.to_string();
    }

    let mut result = String::with_capacity(input.len());
    let mut i = 0;
    let bytes = input.as_bytes();
    let len = bytes.len();

    while i < len {
        let is_llap = input[i..].starts_with(r"\mathllap");
        let is_rlap = input[i..].starts_with(r"\mathrlap");
        let is_smash = input[i..].starts_with(r"\smash");

        if is_llap || is_rlap || is_smash {
            let cmd_name = if is_llap {
                "mathllap"
            } else if is_rlap {
                "mathrlap"
            } else {
                "smash"
            };
            let cmd_len = cmd_name.len() + 1; // +1 for leading '\'
            let after_cmd = i + cmd_len;

            // Preceded by an odd number of backslashes means it is truly escaped (e.g. \\mathllap)
            let num_backslashes = input[..i].chars().rev().take_while(|&c| c == '\\').count();
            let is_escaped = num_backslashes % 2 == 1;
            let is_boundary = after_cmd >= len || !bytes[after_cmd].is_ascii_alphabetic();

            if !is_escaped && is_boundary {
                let mut brace_start = after_cmd;
                while brace_start < len && bytes[brace_start].is_ascii_whitespace() {
                    brace_start += 1;
                }

                if brace_start < len && bytes[brace_start] == b'{' {
                    let mut depth = 1;
                    let mut j = brace_start + 1;
                    while j < len && depth > 0 {
                        match bytes[j] {
                            b'\\' => {
                                j += 1; // Skip escaped character like \{ or \}
                            }
                            b'{' => depth += 1,
                            b'}' => depth -= 1,
                            _ => {}
                        }
                        j += 1;
                    }

                    if depth == 0 {
                        let inner = &input[brace_start + 1..j - 1];
                        let processed_inner = preprocess_laps(inner);
                        if let Ok(inner_typst) = mitex::convert_math(&processed_inner, None) {
                            let trimmed_typst = inner_typst.trim();
                            result.push_str(&format!(r"\iftypst {}({}) \fi", cmd_name, trimmed_typst));
                            i = j;
                            continue;
                        } else {
                            // If inner conversion failed, do NOT rewrite to \iftypst!
                            // Leave \mathllap{...} / \mathrlap{...} as raw input so outer mitex fails
                            // and triggers transpile_latex_math's graceful fallback.
                            result.push_str(&input[i..j]);
                            i = j;
                            continue;
                        }
                    }
                }
            }
        }

        let ch = input[i..].chars().next().unwrap();
        result.push(ch);
        i += ch.len_utf8();
    }

    result
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        use std::fmt::Write;
        let _ = write!(&mut s, "{:02x}", b);
    }
    s
}

pub(crate) fn hex_decode(s: &str) -> Option<String> {
    if s.len() % 2 != 0 {
        return None;
    }
    let mut bytes = Vec::with_capacity(s.len() / 2);
    for i in (0..s.len()).step_by(2) {
        let byte = u8::from_str_radix(&s[i..i + 2], 16).ok()?;
        bytes.push(byte);
    }
    String::from_utf8(bytes).ok()
}

pub fn transpile_latex_math(latex: &str, is_block: bool) -> String {
    transpile_latex_math_with_index(latex, is_block, None)
}

pub fn transpile_latex_math_with_index(latex: &str, is_block: bool, eq_idx: Option<usize>) -> String {
    let trimmed = latex.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let preprocessed = preprocess_laps(trimmed);

    match mitex::convert_math(&preprocessed, None) {
        Ok(typst_math) => {
            let clean = typst_math
                .trim()
                .replace("mitexsqrt", "sqrt")
                .replace("mitexdisplay", "display")
                .replace("mitextag", "tag")
                .replace("planck.reduce", "planck")
                .replace("angle.l", "chevron.l")
                .replace("angle.r", "chevron.r")
                .replace("dot.circle", "dot.o")
                .replace("times.circle", "times.o");
            let marker = match eq_idx {
                Some(idx) => idx.to_string(),
                None => hex_encode(trimmed.as_bytes()),
            };
            if is_block {
                format!("$ /*sgv-raw:{}*/ {} $\n", marker, clean)
            } else {
                format!("$/*sgv-raw:{}*/ {}$", marker, clean)
            }
        }

        Err(_err) => {
            // Graceful fallback: escape special Typst string symbols (quotes and backslashes)
            // and wrap in mitexdegraded for visible styling and error recovery
            let safe_fallback = escape_typst_string(trimmed);
            if is_block {
                format!("$ mitexdegraded(\"{}\") $\n", safe_fallback)
            } else {
                format!("$ mitexdegraded(\"{}\") $", safe_fallback)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use typst::layout::{Frame, FrameItem, Point};

    #[derive(Debug)]
    struct TextRun {
        text: String,
        pos: Point,
    }

    fn find_text_runs(frame: &Frame, origin: Point, out: &mut Vec<TextRun>) {
        for (pos, item) in frame.items() {
            let p = origin + *pos;
            match item {
                FrameItem::Group(g) => find_text_runs(&g.frame, p, out),
                FrameItem::Text(t) => out.push(TextRun {
                    text: t.text.clone().into(),
                    pos: p,
                }),
                _ => {}
            }
        }
    }

    #[test]
    fn test_transpile_simple_math() {
        let res = transpile_latex_math("E = mc^2", false);
        assert!(res.starts_with('$') && res.ends_with('$'));
        assert!(res.contains("/*sgv-raw:"));
        let hex_start = res.find("/*sgv-raw:").unwrap() + 10;
        let hex_end = res.find("*/").unwrap();
        let decoded = hex_decode(&res[hex_start..hex_end]).unwrap();
        assert_eq!(decoded, "E = mc^2");

        let res_idx = transpile_latex_math_with_index("E = mc^2", false, Some(42));
        assert!(res_idx.contains("/*sgv-raw:42*/"));
    }

    #[test]
    fn test_latex_spacing_no_code_execution() {

        // Malicious Typst code injection attempts inside LaTeX length expressions
        // Must NOT be executed by eval(), but safely rejected by pure numeric parser.
        // Also verifies multibyte CJK characters do NOT cause slice boundary panics,
        // and dimension identifiers like \textwidth are supported.
        let md = r#"
$$ A \hspace{3pt} B $$
$$ A \hspace{\text{calc.abs(-3pt)+0pt}} B $$
$$ A \hspace{\text{calc.max(30pt,1pt)+0pt}} B $$
$$ A \hspace{\text{中}} B $$
$$ A \hspace{\text{1米m}} B $$
$$ A \hspace{0.5\textwidth} B $$
"#;
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs = Vec::new();
        find_text_runs(&compiled.pages()[0].frame, Point::zero(), &mut runs);

        let a_runs: Vec<&TextRun> = runs.iter().filter(|r| r.text == "𝐴").collect();
        let b_runs: Vec<&TextRun> = runs.iter().filter(|r| r.text == "𝐵").collect();
        assert_eq!(a_runs.len(), 6);
        assert_eq!(b_runs.len(), 6);

        let gap_3pt = (b_runs[0].pos.x - a_runs[0].pos.x).to_pt();
        let gap_exploit1 = (b_runs[1].pos.x - a_runs[1].pos.x).to_pt();
        let gap_exploit2 = (b_runs[2].pos.x - a_runs[2].pos.x).to_pt();

        // gap_exploit1 must NOT match gap_3pt (calc.abs(-3pt) must NOT be executed)
        assert!((gap_exploit1 - gap_3pt).abs() > 5.0, "calc.abs code injection must NOT be executed: exploit={:.2}pt, 3pt={:.2}pt", gap_exploit1, gap_3pt);
        // gap_exploit2 must NOT evaluate to 30pt (which would be ~37.88pt)
        assert!((gap_exploit2 - gap_exploit1).abs() < 0.01, "Both unparsed expressions must fall back to safe default length");

        // CJK multibyte inputs must safely fall back without panic
        let gap_cjk1 = (b_runs[3].pos.x - a_runs[3].pos.x).to_pt();
        let gap_cjk2 = (b_runs[4].pos.x - a_runs[4].pos.x).to_pt();
        assert!((gap_cjk1 - gap_exploit1).abs() < 0.01, "CJK '中' must safely fall back to default length");
        assert!((gap_cjk2 - gap_exploit1).abs() < 0.01, "CJK '1米m' must safely fall back to default length");

        // textwidth formula compiles successfully and produces positive gap matching half body width (~376pt)
        let gap_textwidth = (b_runs[5].pos.x - a_runs[5].pos.x).to_pt();
        assert!(gap_textwidth > 200.0, "textwidth formula must produce gap > 200pt, got {:.2}pt", gap_textwidth);
    }

    #[test]
    fn test_transpile_maxwell() {
        let latex = r"\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t}";
        let res = transpile_latex_math(latex, true);
        println!("Maxwell full equation output:\n{}", res);
    }

    #[test]
    fn test_transpile_fraction_and_integral() {
        let res = transpile_latex_math(r"\int_0^1 x dx + \frac{a}{b}", true);
        assert!(res.contains('$'));
        assert!(res.contains("integral") || res.contains("int"));
    }

    #[test]
    fn test_transpile_matrix() {
        let latex = r"\begin{matrix} 1 & 2 \\ 3 & 4 \end{matrix}";
        let md = format!("# Matrix\n\n$$\n{}\n$$\n", latex);
        let doc = crate::parser::markdown::convert_markdown_to_typst(&md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None);
        assert!(compiled.is_ok(), "Matrix compilation failed: {:?}", compiled.err());
    }

    #[test]
    fn test_transpile_invalid_latex_graceful_fallback() {
        let invalid = r#"\invalidcommand{{{broken "quoted""#;
        let res = transpile_latex_math(invalid, false);
        // Should not panic, returns a safe string with quotes and backslashes escaped
        assert!(res.starts_with('$') && res.ends_with('$'));
        assert!(res.contains(r#"\"quoted\""#));

        // Verify compilation with Typst engine succeeds without syntax error
        let source = format!("#set page(width: 400pt, height: auto)\n{}", res);
        let compiled = crate::compiler::engine::compile_typst_to_pdf(&source, ".", std::collections::HashMap::new());
        assert!(compiled.is_ok(), "Typst compilation failed: {:?}", compiled.err());
    }

    #[test]
    fn test_transpile_latex_macro_compatibility() {
        let test_cases = [
            r"\boxed{R_{target}=M+C-2}",
            r"\fbox{E=mc^2}",
            r"\hbox{test abc}",
            r"\hbox{\text{test}}",
            r"\textsf{abc}",
            r"\texttt{abc}",
            r"\textup{abc}",
            r"\cfrac{1}{\sqrt{2}}",
            r"\dfrac{a}{b}",
            r"\tfrac{1}{2}",
            r"\dbinom{n}{k}",
            r"\tbinom{n}{k}",
            r"\substack{0 < i < m \\ 0 < j < n}",
            r"\bra{\psi}",
            r"\ket{\phi}",
            r"\braket{\psi|\phi}",
            r"\Bra{\psi}",
            r"\Ket{\phi}",
            r"\Braket{\psi|\phi}",
            r"\pod{n}",
            r"\pmod{n}",
            r"\xcancel{x}",
            r"\bcancel{x}",
            r"\sout{x}",
            r"\mathclap{x}",
            r"\mathllap{x}",
            r"\mathrlap{x}",
            r"\mathring{A}",
            r"\underbar{x}",
            r"\overgroup{AB}",
            r"\undergroup{AB}",
            r"\phantom{x}",
            r"\hphantom{x}",
            r"\vphantom{x}",
            r"\middle|",
            r"\Set{x \mid x > 0}",
        ];

        for latex in test_cases {
            let md = format!("# Test\n\n$$\n{}\n$$\n", latex);
            let doc = crate::parser::markdown::convert_markdown_to_typst(&md, "Test", &crate::compiler::engine::RenderOptions::default());
            let compiled = crate::compiler::engine::compile_typst_to_pdf(&doc.typst_source, ".", std::collections::HashMap::new());
            assert!(compiled.is_ok(), "Failed for {}: {:?}", latex, compiled.err());
        }
    }

    #[test]
    fn test_typst_macro_fidelity() {
        use typst::layout::{Frame, FrameItem, Point};

        #[derive(Debug)]
        struct TextRun {
            text: String,
            pos: Point,
            font_size: typst::layout::Abs,
        }

        fn find_text_runs(frame: &Frame, origin: Point, out: &mut Vec<TextRun>) {
            for (pos, item) in frame.items() {
                let p = origin + *pos;
                match item {
                    FrameItem::Group(g) => find_text_runs(&g.frame, p, out),
                    FrameItem::Text(t) => out.push(TextRun {
                        text: t.text.clone().into(),
                        pos: p,
                        font_size: t.size,
                    }),
                    _ => {}
                }
            }
        }

        // 1. substack: verify vertical stacking, script font size, and baseline isolation
        let md_sub = "# Substack\n\n$$\nX + \\substack{A \\\\ B} + Y\n$$\n";
        let doc_sub = crate::parser::markdown::convert_markdown_to_typst(md_sub, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_sub = crate::compiler::engine::compile_typst_to_document(&doc_sub.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_sub = Vec::new();
        find_text_runs(&compiled_sub.pages()[0].frame, Point::zero(), &mut runs_sub);
        let x_run = runs_sub.iter().find(|r| r.text == "𝑋").expect("Outer X not found");
        let y_run = runs_sub.iter().find(|r| r.text == "𝑌").expect("Outer Y not found");
        let a_run = runs_sub.iter().find(|r| r.text == "𝐴").expect("Substack row 1 A not found");
        let b_run = runs_sub.iter().find(|r| r.text == "𝐵").expect("Substack row 2 B not found");

        // Row 2 below Row 1
        assert!(b_run.pos.y > a_run.pos.y, "Substack row B must be vertically below row A");
        // Script font size assertion (discriminates against unreduced #let substack(it) = it)
        assert!(a_run.font_size < x_run.font_size, "Substack must reduce font size with script(): a_size={:?} vs x_size={:?}", a_run.font_size, x_run.font_size);
        // Outer equation baseline isolation assertion (discriminates against unboxed line breaks)
        assert!((x_run.pos.y - y_run.pos.y).abs().to_pt() < 0.01, "Outer elements X and Y must remain on the exact same baseline");

        // 2. sout: verify horizontal strikethrough using native Typst strike
        let md_sout = "# Sout\n\n$$\n\\sout{x + y}\n$$\n";
        let doc_sout = crate::parser::markdown::convert_markdown_to_typst(md_sout, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_sout = crate::compiler::engine::compile_typst_to_document(&doc_sout.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut has_strike = false;
        fn check_strike(frame: &Frame, found: &mut bool) {
            for (_, item) in frame.items() {
                match item {
                    FrameItem::Tag(tag) if format!("{:?}", tag).contains("strike") => *found = true,
                    FrameItem::Group(g) => check_strike(&g.frame, found),
                    _ => {}
                }
            }
        }
        check_strike(&compiled_sout.pages()[0].frame, &mut has_strike);
        assert!(has_strike, "sout must generate a native strike element");

        // 3. hbox: verify upright Latin text
        let md_hbox = "# Hbox\n\n$$\n\\hbox{test}\n$$\n";
        let doc_hbox = crate::parser::markdown::convert_markdown_to_typst(md_hbox, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_hbox = crate::compiler::engine::compile_typst_to_document(&doc_hbox.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_hbox = Vec::new();
        find_text_runs(&compiled_hbox.pages()[0].frame, Point::zero(), &mut runs_hbox);
        let combined: String = runs_hbox.into_iter().map(|r| r.text).collect();
        assert!(combined.contains("t e s t") || combined.contains("test"), "hbox must contain upright text: got {}", combined);

        // 4. textsf and texttt: verify upright font mode
        let md_txt = "# Text Mode\n\n$$\n\\textsf{a} + \\texttt{b}\n$$\n";
        let doc_txt = crate::parser::markdown::convert_markdown_to_typst(md_txt, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_txt = crate::compiler::engine::compile_typst_to_document(&doc_txt.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_txt = Vec::new();
        find_text_runs(&compiled_txt.pages()[0].frame, Point::zero(), &mut runs_txt);
        // textsf must be upright sans '𝖺' (U+1D5BA), NOT italic sans '𝘢' (U+1D622) or default math italic '𝑎' (U+1D44E)
        let a_txt = runs_txt.iter().find(|r| r.text == "\u{1d5ba}").expect("textsf 'a' must be upright sans-serif '𝖺'");
        assert_ne!(a_txt.text, "\u{1d622}", "textsf must NOT be italic sans '𝘢'");
        assert_ne!(a_txt.text, "\u{1d44e}", "textsf must NOT be default math italic '𝑎'");

        // texttt must be upright mono '𝚋' (U+1D68B), NOT italic '𝑏' (U+1D44F)
        let b_txt = runs_txt.iter().find(|r| r.text == "\u{1d68b}").expect("texttt 'b' must be upright monospace '𝚋'");
        assert_ne!(b_txt.text, "\u{1d44f}", "texttt must NOT be default math italic '𝑏'");

        // 5. mathclap, mathllap, mathrlap: verify true displacement and baseline preservation
        let md_clap = "# Mathclap\n\n$$\nA \\mathclap{X Y Z} B\n$$\n";
        let doc_clap = crate::parser::markdown::convert_markdown_to_typst(md_clap, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_clap = crate::compiler::engine::compile_typst_to_document(&doc_clap.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_clap = Vec::new();
        find_text_runs(&compiled_clap.pages()[0].frame, Point::zero(), &mut runs_clap);
        let x_clap = runs_clap.iter().find(|r| r.text == "𝑋").expect("X clap not found");
        let b_clap = runs_clap.iter().find(|r| r.text == "𝐵").expect("B clap not found");

        let md_llap = "# Mathllap\n\n$$\nA \\mathllap{X Y Z} B\n$$\n";
        let doc_llap = crate::parser::markdown::convert_markdown_to_typst(md_llap, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_llap = crate::compiler::engine::compile_typst_to_document(&doc_llap.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_llap = Vec::new();
        find_text_runs(&compiled_llap.pages()[0].frame, Point::zero(), &mut runs_llap);
        let x_llap = runs_llap.iter().find(|r| r.text == "𝑋").expect("X llap not found");
        let b_llap = runs_llap.iter().find(|r| r.text == "𝐵").expect("B llap not found");

        let md_rlap = "# Mathrlap\n\n$$\nA \\mathrlap{X Y Z} B\n$$\n";
        let doc_rlap = crate::parser::markdown::convert_markdown_to_typst(md_rlap, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_rlap = crate::compiler::engine::compile_typst_to_document(&doc_rlap.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_rlap = Vec::new();
        find_text_runs(&compiled_rlap.pages()[0].frame, Point::zero(), &mut runs_rlap);
        let x_rlap = runs_rlap.iter().find(|r| r.text == "𝑋").expect("X rlap not found");
        let b_rlap = runs_rlap.iter().find(|r| r.text == "𝐵").expect("B rlap not found");

        // Zero-width invariant: B must be at identical position across all three laps (< 0.01pt tolerance)
        assert!((b_clap.pos.x - b_llap.pos.x).abs().to_pt() < 0.01, "Zero-width box: B position must be identical");
        assert!((b_clap.pos.x - b_rlap.pos.x).abs().to_pt() < 0.01, "Zero-width box: B position must be identical");

        // Baseline preservation: X must stay on the exact same baseline as A and B (< 0.01pt tolerance)
        assert!((x_clap.pos.y - b_clap.pos.y).abs().to_pt() < 0.01, "mathclap must preserve baseline");
        assert!((x_llap.pos.y - b_llap.pos.y).abs().to_pt() < 0.01, "mathllap must preserve baseline");
        assert!((x_rlap.pos.y - b_rlap.pos.y).abs().to_pt() < 0.01, "mathrlap must preserve baseline");

        // Precise discriminating displacement assertions:
        // mathrlap is at offset 0; mathclap is shifted by -w/2; mathllap is shifted by -w
        let clap_shift = (x_rlap.pos.x - x_clap.pos.x).to_pt();
        let llap_shift = (x_rlap.pos.x - x_llap.pos.x).to_pt();
        assert!(clap_shift > 10.0, "mathclap MUST produce an actual negative displacement: got {:.2}pt (would be 0 with no-op)", clap_shift);
        assert!(llap_shift > 20.0, "mathllap MUST produce full negative displacement: got {:.2}pt (would be 0 with no-op)", llap_shift);
        // clap_shift must be exactly half of llap_shift (within 0.5pt tolerance)
        assert!((llap_shift - 2.0 * clap_shift).abs() < 0.5, "llap shift must be double clap shift: llap={:.2}, clap={:.2}", llap_shift, clap_shift);

        // 6. xcancel: verify cross of 2 lines
        let md_xcancel = "# XCancel\n\n$$\n\\xcancel{x}\n$$\n";
        let doc_xcancel = crate::parser::markdown::convert_markdown_to_typst(md_xcancel, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_xcancel = crate::compiler::engine::compile_typst_to_document(&doc_xcancel.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut line_count = 0;
        fn count_lines(frame: &Frame, count: &mut usize) {
            for (_, item) in frame.items() {
                match item {
                    FrameItem::Group(g) => count_lines(&g.frame, count),
                    FrameItem::Shape(..) => *count += 1,
                    _ => {}
                }
            }
        }
        count_lines(&compiled_xcancel.pages()[0].frame, &mut line_count);
        assert_eq!(line_count, 2, "xcancel must generate an X cross (2 lines)");

        // 7. hphantom and vphantom dimensions
        let md_phan = "# Phantom\n\n$$\n\\hphantom{X}\n$$\n$$\n\\vphantom{X}\n$$\n";
        let doc_phan = crate::parser::markdown::convert_markdown_to_typst(md_phan, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_phan = crate::compiler::engine::compile_typst_to_pdf(&doc_phan.typst_source, ".", std::collections::HashMap::new());
        assert!(compiled_phan.is_ok(), "Phantom compilation failed: {:?}", compiled_phan.err());

        // 8. atop, brace, brack: verify vertical stacking
        let md_atop = "# Atop\n\n$$\nX + {A \\atop B} + Y\n$$\n$$\n{N \\brace K}\n$$\n$$\n{M \\brack L}\n$$\n";
        let doc_atop = crate::parser::markdown::convert_markdown_to_typst(md_atop, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_atop = crate::compiler::engine::compile_typst_to_document(&doc_atop.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_atop = Vec::new();
        find_text_runs(&compiled_atop.pages()[0].frame, Point::zero(), &mut runs_atop);

        let a_run = runs_atop.iter().find(|r| r.text == "𝐴").expect("atop row 1 A not found");
        let b_run = runs_atop.iter().find(|r| r.text == "𝐵").expect("atop row 2 B not found");
        assert!(b_run.pos.y > a_run.pos.y, "atop row B must be vertically below row A (found y_B={:?}, y_A={:?})", b_run.pos.y, a_run.pos.y);

        let n_run = runs_atop.iter().find(|r| r.text == "𝑁").expect("brace row 1 N not found");
        let k_run = runs_atop.iter().find(|r| r.text == "𝐾").expect("brace row 2 K not found");
        assert!(k_run.pos.y > n_run.pos.y, "brace row K must be vertically below row N (found y_K={:?}, y_N={:?})", k_run.pos.y, n_run.pos.y);

        let m_run = runs_atop.iter().find(|r| r.text == "𝑀").expect("brack row 1 M not found");
        let l_run = runs_atop.iter().find(|r| r.text == "𝐿").expect("brack row 2 L not found");
        assert!(l_run.pos.y > m_run.pos.y, "brack row L must be vertically below row M (found y_L={:?}, y_M={:?})", l_run.pos.y, m_run.pos.y);

        // 9. hspace: verify proportional horizontal spacing
        let md_hsp1 = "$$\nA \\hspace{1em} B\n$$\n";
        let doc_hsp1 = crate::parser::markdown::convert_markdown_to_typst(md_hsp1, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_hsp1 = crate::compiler::engine::compile_typst_to_document(&doc_hsp1.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_hsp1 = Vec::new();
        find_text_runs(&compiled_hsp1.pages()[0].frame, Point::zero(), &mut runs_hsp1);
        let a1 = runs_hsp1.iter().find(|r| r.text == "𝐴").expect("A1 not found");
        let b1 = runs_hsp1.iter().find(|r| r.text == "𝐵").expect("B1 not found");
        let gap_1em = (b1.pos.x - a1.pos.x).to_pt();

        let md_hsp5 = "$$\nA \\hspace{5em} B\n$$\n";
        let doc_hsp5 = crate::parser::markdown::convert_markdown_to_typst(md_hsp5, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_hsp5 = crate::compiler::engine::compile_typst_to_document(&doc_hsp5.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_hsp5 = Vec::new();
        find_text_runs(&compiled_hsp5.pages()[0].frame, Point::zero(), &mut runs_hsp5);
        let a5 = runs_hsp5.iter().find(|r| r.text == "𝐴").expect("A5 not found");
        let b5 = runs_hsp5.iter().find(|r| r.text == "𝐵").expect("B5 not found");
        let gap_5em = (b5.pos.x - a5.pos.x).to_pt();

        assert!(gap_5em > 2.5 * gap_1em, "hspace{{5em}} ({:.2}pt) must produce a much wider gap than hspace{{1em}} ({:.2}pt)", gap_5em, gap_1em);

        // 10. raisebox: verify vertical displacement and baseline preservation
        let md_raise = "# Raisebox\n\n$$\nA \\raisebox{10pt}{B} C\n$$\n";
        let doc_raise = crate::parser::markdown::convert_markdown_to_typst(md_raise, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_raise = crate::compiler::engine::compile_typst_to_document(&doc_raise.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_raise = Vec::new();
        find_text_runs(&compiled_raise.pages()[0].frame, Point::zero(), &mut runs_raise);
        let a_raise = runs_raise.iter().find(|r| r.text == "𝐴").expect("A not found");
        let b_raise = runs_raise.iter().find(|r| r.text == "𝐵" || r.text == "B").expect("B not found");
        let c_raise = runs_raise.iter().find(|r| r.text == "𝐶").expect("C not found");
        let raise_amount = (a_raise.pos.y - b_raise.pos.y).to_pt();
        assert!(raise_amount > 8.0, "raisebox{{10pt}} must displace B upwards by ~10pt: got {:.2}pt", raise_amount);
        assert!((a_raise.pos.y - c_raise.pos.y).abs().to_pt() < 0.01, "A and C must remain on identical baseline");

        // 11. smallmatrix: verify inline multi-row multi-column layout
        let md_smat = "# Smallmatrix\n\n$$\n\\begin{smallmatrix} 1 & 2 \\\\ 3 & 4 \\end{smallmatrix}\n$$\n";
        let doc_smat = crate::parser::markdown::convert_markdown_to_typst(md_smat, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_smat = crate::compiler::engine::compile_typst_to_document(&doc_smat.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut runs_smat = Vec::new();
        find_text_runs(&compiled_smat.pages()[0].frame, Point::zero(), &mut runs_smat);
        let r1 = runs_smat.iter().find(|r| r.text == "1").expect("1 not found");
        let r2 = runs_smat.iter().find(|r| r.text == "2").expect("2 not found");
        let r3 = runs_smat.iter().find(|r| r.text == "3").expect("3 not found");
        let _r4 = runs_smat.iter().find(|r| r.text == "4").expect("4 not found");
        assert!(r3.pos.y > r1.pos.y, "Row 2 must be below row 1: y3={:?} vs y1={:?}", r3.pos.y, r1.pos.y);
        assert!(r2.pos.x > r1.pos.x, "Column 2 must be to the right of col 1: x2={:?} vs x1={:?}", r2.pos.x, r1.pos.x);
    }

    #[test]
    fn test_math_laps_non_pollution() {
        // 1. \mathrlap{a} + \mathinner{b}: \mathinner must NOT be rewritten to \mathllap
        let raw1 = r"\mathrlap{a} + \mathinner{b}";
        let trans1 = transpile_latex_math(raw1, false);
        assert!(trans1.contains("mathrlap"), "Must contain mathrlap: got {}", trans1);
        assert!(trans1.contains("mathinner"), "Must preserve mathinner: got {}", trans1);
        assert!(!trans1.contains("mathllap"), "Must NOT pollute into mathllap: got {}", trans1);

        // 2. \mathllap{a} + \mathpunct{b}: \mathpunct must NOT be rewritten to \mathrlap
        let raw2 = r"\mathllap{a} + \mathpunct{b}";
        let trans2 = transpile_latex_math(raw2, false);
        assert!(trans2.contains("mathllap"), "Must contain mathllap: got {}", trans2);
        assert!(trans2.contains("mathpunct"), "Must preserve mathpunct: got {}", trans2);
        assert!(!trans2.contains("mathrlap"), "Must NOT pollute into mathrlap: got {}", trans2);

        // 3. \text{use \mathrlap here}: Must not mangle into mathpunct
        let raw3 = r"\text{use \mathrlap here}";
        let trans3 = transpile_latex_math(raw3, false);
        assert!(!trans3.contains("mathpunct"), "Text with mathrlap must not be mangled to mathpunct: got {}", trans3);

        // 4. Verify full document compilation of coexistence
        let md = "# Coexistence\n\n$$\n\\mathrlap{a} + \\mathinner{b}\n$$\n\n$$\n\\mathllap{c} + \\mathpunct{d}\n$$\n";
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None);
        assert!(compiled.is_ok(), "Coexistence compilation failed: {:?}", compiled.err());
    }

    #[test]
    fn test_tex_atom_classes_compilation() {
        let md = "# Atoms\n\n$$\n\\mathord{a} + \\mathop{b} + \\mathbin{c} + \\mathrel{d} + \\mathopen{e} + \\mathclose{f} + \\mathpunct{g} + \\mathinner{h}\n$$\n";
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None);
        assert!(compiled.is_ok(), "TeX atom classes compilation failed: {:?}", compiled.err());
    }

    #[test]
    fn test_common_latex_structures_compilation() {
        // Smoke test all common environments and commands reported:
        // matrix, pmatrix, bmatrix, Bmatrix, vmatrix, Vmatrix, smallmatrix, aligned, alignedat, rcases,
        // operatorname, overset, underset, stackrel, xrightarrow, xleftarrow, hspace, vspace, raisebox, smash,
        // overleftrightarrow, overleftharpoon, overrightharpoon, overlinesegment, atop, choose, brace, brack,
        // and big delimiters (big, Big, bigg, Bigg, bigl, Bigl, biggl, Biggl, bigm, Bigm, biggm, Biggm, bigr, Bigr, biggr, Biggr)
        let md = r#"# Common LaTeX Constructs

$$\begin{matrix} 1 & 2 \\ 3 & 4 \end{matrix}$$
$$\begin{pmatrix} a & b \\ c & d \end{pmatrix}$$
$$\begin{bmatrix} x & y \\ z & w \end{bmatrix}$$
$$\begin{Bmatrix} 1 & 0 \\ 0 & 1 \end{Bmatrix}$$
$$\begin{vmatrix} a & b \\ c & d \end{vmatrix}$$
$$\begin{Vmatrix} a & b \\ c & d \end{Vmatrix}$$
$$\begin{smallmatrix} 1 & 2 \\ 3 & 4 \end{smallmatrix}$$
$$\begin{aligned} a &= b \\ c &= d \end{aligned}$$
$$\begin{alignedat}{2} a &= b & c &= d \\ e &= f & g &= h \end{alignedat}$$
$$\begin{rcases} a & \text{if } b \\ c & \text{if } d \end{rcases}$$
$$\operatorname{sgn}(x) + \operatorname*{max}_{i} x_i$$
$$\overset{a}{b} + \underset{a}{b} + \stackrel{a}{=}$$
$$\xrightarrow{f} + \xleftarrow{g}$$
$$A \hspace{1em} B \vspace{1em} C$$
$$\raisebox{5pt}{B} + \smash{x}$$
$$\overleftrightarrow{AB} + \overleftharpoon{CD} + \overrightharpoon{EF} + \overlinesegment{GH}$$
$$a \atop b$$
$$n \choose k$$
$${n \brace k} + {n \brack k}$$
$$\big( \Big( \bigg( \Bigg( \bigl( \Bigl( \biggl( \Biggl( \bigm| \Bigm| \biggm| \Biggm| \bigr) \Bigr) \biggr) \Biggr)$$
"#;
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None);
        assert!(compiled.is_ok(), "Common LaTeX structures compilation failed: {:?}", compiled.err());
    }

    #[test]
    fn test_invalid_lap_graceful_fallback() {
        // An invalid command inside \mathrlap must NOT inject uncompilable raw LaTeX into Typst.
        // It must trigger graceful fallback for that equation without crashing document compilation.
        let raw = r"\mathrlap{\invalidcommandhere}";
        let trans = transpile_latex_math(raw, false);
        assert!(trans.contains("mitexdegraded"), "Invalid lap must fall back to degraded math: got {}", trans);
        assert!(trans.contains(r#"\\mathrlap{\\invalidcommandhere}"#), "Must retain original LaTeX: got {}", trans);

        let md = format!("# Test\n\n$$\n{}\n$$\n", raw);
        let doc = crate::parser::markdown::convert_markdown_to_typst(&md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document(&doc.typst_source, ".", std::collections::HashMap::new(), None);
        assert!(compiled.is_ok(), "Document compilation must not fail on invalid lap: {:?}", compiled.err());
    }

    #[test]
    fn test_extended_latex_structures_authentic_rendering() {
        let md = r#"
# Extended LaTeX Macros Authentic Rendering

$$\overbrace{x+y}^{top}$$
$$\underbrace{x+y}_{bottom}$$
$$\overbracket{x}$$
$$\underbracket{x}$$
$$\xleftrightarrow{f}$$
$$\textcolor{red}{x}$$
$$\color{blue}{y}$$
"#;
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        // Must compile cleanly
        let compiled = crate::compiler::engine::compile_typst_to_document_with_raw_equations(
            &doc.typst_source,
            ".",
            std::collections::HashMap::new(),
            None,
            &doc.raw_equations,
        ).expect("Extended LaTeX macros must compile cleanly");

        // Must NOT have degraded into mitexdegraded in any equation
        assert_eq!(
            compiled.degraded_equation_count, 0,
            "Extended LaTeX structures must render authentically without degradation, but found degraded equations: {:?}",
            compiled.degraded_equations
        );
        assert!(
            !compiled.final_typst_source.contains("mitexdegraded(\""),
            "Final Typst source must not contain mitexdegraded calls: {}",
            compiled.final_typst_source
        );

        // Verify that math runs were actually rendered authentically into layout frames
        let mut runs = Vec::new();
        for page in compiled.pages() {
            find_text_runs(&page.frame, typst::layout::Point::zero(), &mut runs);
        }
        let texts: Vec<&str> = runs.iter().map(|r| r.text.as_str()).collect();
        // Mathematical overbrace and underbrace glyphs
        assert!(texts.contains(&"⏞"), "Rendered frames must contain top curly bracket overbrace glyph: {:?}", texts);
        assert!(texts.contains(&"⏟"), "Rendered frames must contain bottom curly bracket underbrace glyph: {:?}", texts);
        // Extensible square brackets
        assert!(texts.contains(&"⎴"), "Rendered frames must contain top square bracket overbracket glyph: {:?}", texts);
        assert!(texts.contains(&"⎵"), "Rendered frames must contain bottom square bracket underbracket glyph: {:?}", texts);
        // Extensible arrow annotation
        assert!(texts.contains(&"𝑓"), "Rendered frames must contain mathematical italic f annotation: {:?}", texts);
        // Ensure no internal macro names or degraded boxes leaked into text
        assert!(
            !texts.iter().any(|t| t.contains("mitex") || t.contains("degraded") || t.contains("overbrace")),
            "No raw macro names or degraded text should leak into frames: {:?}",
            texts
        );
    }

    #[test]
    fn test_extended_latex_macros_degradation_detected_if_missing_from_prelude() {
        let md = r#"
# Test Missing Prelude Degradation Detection

$$\overbrace{x+y}^{top}$$
"#;
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        // Deliberately remove #let mitexoverbrace to verify that missing macros are caught by degradation detection
        let modified_source = doc.typst_source.replace("#let mitexoverbrace = math.overbrace", "// removed mitexoverbrace");
        assert_ne!(modified_source, doc.typst_source, "Source must have contained #let mitexoverbrace");

        let compiled = crate::compiler::engine::compile_typst_to_document_with_raw_equations(
            &modified_source,
            ".",
            std::collections::HashMap::new(),
            None,
            &doc.raw_equations,
        ).expect("Compilation must succeed via graceful degradation");

        assert_eq!(
            compiled.degraded_equation_count, 1,
            "Missing #let mitexoverbrace MUST be detected as a degraded equation"
        );
        assert_eq!(compiled.degraded_equations[0], r"\overbrace{x+y}^{top}");
    }

    #[test]
    fn test_formula_level_visible_degradation_with_raw_latex() {
        let md = r#"
# Document with Unhandled LaTeX Commands

$$\genfrac{(}{)}{0pt}{}{n}{k}$$
$$\sideset{_a^b}{_c^d}\sum$$
$$\unknownlatexcommand{42}$$
"#;
        let doc = crate::parser::markdown::convert_markdown_to_typst(md, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled = crate::compiler::engine::compile_typst_to_document_with_raw_equations(
            &doc.typst_source,
            ".",
            std::collections::HashMap::new(),
            None,
            &doc.raw_equations,
        ).expect("Document compilation must succeed with degraded formulas");

        // Check that degraded formulas display the original raw LaTeX (escaped for string literal)
        assert!(doc.typst_source.contains("mitexdegraded"), "Must use mitexdegraded for unhandled formulas");
        assert_eq!(compiled.degraded_equation_count, 3);
        assert!(compiled.degraded_equations.iter().any(|e| e.contains(r"\genfrac{(}{)}{0pt}{}{n}{k}")));
        assert!(compiled.degraded_equations.iter().any(|e| e.contains(r"\sideset{_a^b}{_c^d}\sum")));
        assert!(compiled.degraded_equations.iter().any(|e| e.contains(r"\unknownlatexcommand{42}")));
    }
}
