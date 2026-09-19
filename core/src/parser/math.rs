use super::markdown::escape_typst_string;

/// LaTeX math to Typst math transpiler using `mitex`.

/// Converts a LaTeX math string to Typst math syntax.
/// If transpilation succeeds, returns the Typst math code.
/// If it fails, falls back gracefully to the original input (or raw text) to prevent compilation breakage.
pub fn transpile_latex_math(latex: &str, is_block: bool) -> String {
    let trimmed = latex.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    match mitex::convert_math(trimmed, None) {
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
        println!("text: {:?}", mitex::convert_math(r"\text{Cost}", None));
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

        fn find_texts(frame: &Frame, origin: Point, out: &mut Vec<(String, Point)>) {
            for (pos, item) in frame.items() {
                let p = origin + *pos;
                match item {
                    FrameItem::Group(g) => find_texts(&g.frame, p, out),
                    FrameItem::Text(t) => out.push((t.text.clone().into(), p)),
                    _ => {}
                }
            }
        }

        // 1. substack: verify vertical stacking and proper row separation
        let md_sub = "# Substack\n\n$$\n\\sum_{\\substack{0 < i < m \\\\ 0 < j < n}} a_{i j}\n$$\n";
        let doc_sub = crate::parser::markdown::convert_markdown_to_typst(md_sub, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_sub = crate::compiler::engine::compile_typst_to_document(&doc_sub.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut texts_sub = Vec::new();
        find_texts(&compiled_sub.pages()[0].frame, Point::zero(), &mut texts_sub);
        let i_row = texts_sub.iter().find(|(t, _)| t.contains('i') || t.contains('\u{1d456}')).expect("Row 1 'i' not found");
        let j_row = texts_sub.iter().find(|(t, _)| t.contains('j') || t.contains('\u{1d457}')).expect("Row 2 'j' not found");
        assert!(j_row.1.y > i_row.1.y, "Row 2 (j) must be positioned below row 1 (i) vertically");

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
        let mut texts_hbox = Vec::new();
        find_texts(&compiled_hbox.pages()[0].frame, Point::zero(), &mut texts_hbox);
        let combined: String = texts_hbox.into_iter().map(|(t, _)| t).collect();
        assert!(combined.contains("t e s t") || combined.contains("test"), "hbox must contain upright text 't e s t' or 'test': got {}", combined);

        // 4. mathclap: verify centered zero-width overflow
        let md_clap = "# Mathclap\n\n$$\nA \\mathclap{X Y Z} B\n$$\n";
        let doc_clap = crate::parser::markdown::convert_markdown_to_typst(md_clap, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_clap = crate::compiler::engine::compile_typst_to_document(&doc_clap.typst_source, ".", std::collections::HashMap::new(), None).unwrap();
        let mut texts_clap = Vec::new();
        find_texts(&compiled_clap.pages()[0].frame, Point::zero(), &mut texts_clap);
        let a_pos = texts_clap.iter().find(|(t, _)| t == "𝐴").expect("A not found").1;
        let b_pos = texts_clap.iter().find(|(t, _)| t == "𝐵").expect("B not found").1;
        let y_pos = texts_clap.iter().find(|(t, _)| t == "𝑌").expect("Y not found").1;
        let midpoint = (a_pos.x + b_pos.x) / 2.0;
        // Y (center of XYZ) should be near the midpoint between A and B
        assert!((y_pos.x - midpoint).abs().to_pt() < 5.0, "mathclap must center content between delimiters");

        // 5. xcancel: verify cross of 2 lines
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

        // 6. hphantom and vphantom dimensions
        let md_phan = "# Phantom\n\n$$\n\\hphantom{X}\n$$\n$$\n\\vphantom{X}\n$$\n";
        let doc_phan = crate::parser::markdown::convert_markdown_to_typst(md_phan, "Test", &crate::compiler::engine::RenderOptions::default());
        let compiled_phan = crate::compiler::engine::compile_typst_to_pdf(&doc_phan.typst_source, ".", std::collections::HashMap::new());
        assert!(compiled_phan.is_ok(), "Phantom compilation failed: {:?}", compiled_phan.err());
    }
}
