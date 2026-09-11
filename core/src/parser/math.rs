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
                .replace("mitextag", "tag");
            if is_block {
                format!("$ {} $\n", clean)
            } else {
                format!("${}$", clean)
            }
        }

        Err(_err) => {
            // Graceful fallback: escape special Typst symbols so it doesn't crash the document
            let safe_fallback = trimmed.replace('$', "\\$");
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
        let invalid = r"\invalidcommand{{{broken";
        let res = transpile_latex_math(invalid, false);
        // Should not panic, returns a safe string
        assert!(res.starts_with('$') && res.ends_with('$'));
    }
}
