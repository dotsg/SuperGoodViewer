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
}
