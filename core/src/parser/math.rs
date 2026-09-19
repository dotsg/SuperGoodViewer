use super::markdown::escape_typst_string;

/// LaTeX math to Typst math transpiler using `mitex`.

/// Converts a LaTeX math string to Typst math syntax.
/// If transpilation succeeds, returns the Typst math code.
/// If it fails, falls back gracefully to the original input (or raw text) to prevent compilation breakage.
/// Helper to preprocess \mathllap and \mathrlap using MiTeX's native `\iftypst ... \fi` pass-through,
/// avoiding any pollution of TeX commands like \mathinner or \mathpunct.
fn preprocess_laps(input: &str) -> String {
    if !input.contains(r"\mathllap") && !input.contains(r"\mathrlap") {
        return input.to_string();
    }

    let mut result = String::with_capacity(input.len());
    let mut i = 0;
    let bytes = input.as_bytes();
    let len = bytes.len();

    while i < len {
        let is_llap = input[i..].starts_with(r"\mathllap");
        let is_rlap = input[i..].starts_with(r"\mathrlap");

        if is_llap || is_rlap {
            let cmd_name = if is_llap { "mathllap" } else { "mathrlap" };
            let cmd_len = 9; // r"\mathllap".len() == 9
            let after_cmd = i + cmd_len;

            let is_escaped = i > 0 && bytes[i - 1] == b'\\';
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
                        let inner_typst = match mitex::convert_math(&processed_inner, None) {
                            Ok(t) => t.trim().to_string(),
                            Err(_) => processed_inner,
                        };
                        result.push_str(&format!(r"\iftypst {}({}) \fi", cmd_name, inner_typst));
                        i = j;
                        continue;
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

pub fn transpile_latex_math(latex: &str, is_block: bool) -> String {
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
            if is_block {
                format!("$ {} $\n", clean)
            } else {
                format!("${}$", clean)
            }
        }

        Err(_err) => {
            // Graceful fallback: escape special Typst string symbols (quotes and backslashes)
            // so it doesn't crash the document with unexpected tokens or unknown variable errors
            let safe_fallback = escape_typst_string(trimmed);
            if is_block {
                format!("$ \"{}\" $\n", safe_fallback)
            } else {
                format!("$ \"{}\" $", safe_fallback)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_transpile_simple_math() {
        let res = transpile_latex_math("E = mc^2", false);
        assert!(res.starts_with('$') && res.ends_with('$'));
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
        let res = transpile_latex_math(latex, true);
        assert!(res.contains('$'));
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
}
