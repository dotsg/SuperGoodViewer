use std::collections::{HashMap, VecDeque};
use std::sync::OnceLock;
use parking_lot::RwLock;
use sha2::{Digest, Sha256};
use typst::foundations::Bytes;

struct BoundedCache {
    map: HashMap<String, Bytes>,
    order: VecDeque<String>,
    capacity: usize,
}

impl BoundedCache {
    fn new(capacity: usize) -> Self {
        Self {
            map: HashMap::with_capacity(capacity),
            order: VecDeque::with_capacity(capacity),
            capacity,
        }
    }

    fn get(&mut self, key: &str) -> Option<Bytes> {
        if let Some(val) = self.map.get(key) {
            let val = val.clone();
            if let Some(pos) = self.order.iter().position(|k| k == key) {
                let k = self.order.remove(pos).unwrap();
                self.order.push_back(k);
            }
            Some(val)
        } else {
            None
        }
    }

    fn clear(&mut self) {
        self.map.clear();
        self.order.clear();
    }

    fn insert(&mut self, key: String, val: Bytes) {
        if self.map.contains_key(&key) {
            self.map.insert(key.clone(), val);
            if let Some(pos) = self.order.iter().position(|k| k == &key) {
                let k = self.order.remove(pos).unwrap();
                self.order.push_back(k);
            }
            return;
        }
        if self.map.len() >= self.capacity {
            if let Some(oldest) = self.order.pop_front() {
                self.map.remove(&oldest);
            }
        }
        self.order.push_back(key.clone());
        self.map.insert(key, val);
    }
}

static MERMAID_CACHE: OnceLock<RwLock<BoundedCache>> = OnceLock::new();

fn get_cache() -> &'static RwLock<BoundedCache> {
    MERMAID_CACHE.get_or_init(|| RwLock::new(BoundedCache::new(128)))
}

/// Clears the global Mermaid SVG cache.
/// Used by the benchmark suite to measure true cold-render latency, and by tests
/// that need a deterministic starting state.
pub fn clear_cache() {
    get_cache().write().clear();
}

pub struct RenderedMermaid {
    pub virtual_filename: String,
    pub svg_bytes: Bytes,
    pub is_fallback: bool,
}

fn unwrap_sub_sup_braces(s: &str) -> String {
    let mut res = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();

    while let Some(c) = chars.next() {
        if (c == '_' || c == '^') && chars.peek() == Some(&'{') {
            chars.next(); // consume '{'
            res.push(c);
            for inner in chars.by_ref() {
                if inner == '}' {
                    break;
                }
                res.push(inner);
            }
        } else {
            res.push(c);
        }
    }

    res
}

// Ordered by descending length so longer prefixes match first (e.g. infty before in, leq before le)
const MACROS: &[(&str, &str, bool)] = &[
    // Length 10
    ("varepsilon", "ε", true),
    ("rightarrow", "→", false),
    ("Rightarrow", "⇒", false),
    ("leftarrow", "←", false),
    ("Leftarrow", "⇐", false),
    // Length 8
    ("vartheta", "θ", true),
    ("subseteq", "⊆", false),
    ("setminus", "∖", false),
    // Length 7
    ("epsilon", "ε", true),
    ("upsilon", "υ", true),
    // Length 6
    ("lambda", "λ", true),
    ("Lambda", "Λ", true),
    ("varphi", "φ", true),
    ("rangle", "⟩", false),
    ("langle", "⟨", false),
    ("approx", "≈", false),
    ("propto", "∝", false),
    ("otimes", "⊗", false),
    ("forall", "∀", false),
    ("exists", "∃", false),
    ("subset", "⊂", false),
    ("models", "⊨", false),
    ("succeq", "⪰", false),
    ("preceq", "⪯", false),
    ("mapsto", "↦", false),
    // Length 5
    ("alpha", "α", true),
    ("gamma", "γ", true),
    ("Gamma", "Γ", true),
    ("delta", "δ", true),
    ("Delta", "Δ", true),
    ("theta", "θ", true),
    ("Theta", "Θ", true),
    ("kappa", "κ", true),
    ("sigma", "σ", true),
    ("Sigma", "Σ", true),
    ("omega", "ω", true),
    ("Omega", "Ω", true),
    ("equiv", "≡", false),
    ("times", "×", false),
    ("oplus", "⊕", false),
    ("infty", "∞", false),
    ("nabla", "∇", false),
    ("notin", "∉", false),
    ("empty", "∅", false),
    ("vdash", "⊢", false),
    ("aleph", "ℵ", false),
    ("cdots", "⋯", false),
    ("ldots", "…", false),
    // Length 4
    ("beta", "β", true),
    ("zeta", "ζ", true),
    ("iota", "ι", true),
    ("prod", "∏", false),
    ("oint", "∮", false),
    ("sqrt", "√", false),
    ("perp", "⊥", false),
    ("cong", "≅", false),
    ("odot", "⊙", false),
    ("succ", "≻", false),
    ("prec", "≺", false),
    ("hbar", "ℏ", false),
    ("dots", "…", false),
    // Length 3
    ("eta", "η", true),
    ("rho", "ρ", true),
    ("tau", "τ", true),
    ("phi", "φ", true),
    ("Phi", "Φ", true),
    ("chi", "χ", true),
    ("psi", "ψ", true),
    ("Psi", "Ψ", true),
    ("leq", "≤", false),
    ("geq", "≥", false),
    ("neq", "≠", false),
    ("sim", "∼", false),
    ("div", "÷", false),
    ("cup", "∪", false),
    ("cap", "∩", false),
    ("sum", "∑", false),
    ("int", "∫", false),
    ("neg", "¬", false),
    ("lnot", "¬", false),
    ("ell", "ℓ", false),
    ("mid", "|", false),
    ("iff", "⇔", false),
    ("top", "⊤", false),
    ("bot", "⊥", false),
    // Length 2
    ("mu", "μ", true),
    ("nu", "ν", true),
    ("xi", "ξ", true),
    ("Xi", "Ξ", true),
    ("pi", "π", true),
    ("Pi", "Π", true),
    ("le", "≤", false),
    ("ge", "≥", false),
    ("ne", "≠", false),
    ("pm", "±", false),
    ("mp", "∓", false),
    ("in", "∈", false),
    ("ni", "∋", false),
    ("to", "→", false),
    ("Re", "ℜ", false),
    ("Im", "ℑ", false),
    ("wp", "℘", false),
];

const SUBSCRIPTS: &[(&str, &str)] = &[
    ("_0", "₀"),
    ("_1", "₁"),
    ("_2", "₂"),
    ("_3", "₃"),
    ("_4", "₄"),
    ("_5", "₅"),
    ("_6", "₆"),
    ("_7", "₇"),
    ("_8", "₈"),
    ("_9", "₉"),
    ("_a", "ₐ"),
    ("_e", "ₑ"),
    ("_h", "ₕ"),
    ("_i", "ᵢ"),
    ("_j", "ⱼ"),
    ("_k", "ₖ"),
    ("_l", "ₗ"),
    ("_m", "ₘ"),
    ("_n", "ₙ"),
    ("_o", "ₒ"),
    ("_p", "ₚ"),
    ("_r", "ᵣ"),
    ("_s", "ₛ"),
    ("_t", "ₜ"),
    ("_u", "ᵤ"),
    ("_v", "ᵥ"),
    ("_x", "ₓ"),
    ("_+", "₊"),
    ("_-", "₋"),
    ("_=", "₌"),
];

const SUPERSCRIPTS: &[(&str, &str)] = &[
    ("^0", "⁰"),
    ("^1", "¹"),
    ("^2", "²"),
    ("^3", "³"),
    ("^4", "⁴"),
    ("^5", "⁵"),
    ("^6", "⁶"),
    ("^7", "⁷"),
    ("^8", "⁸"),
    ("^9", "⁹"),
    ("^+", "⁺"),
    ("^-", "⁻"),
    ("^=", "⁼"),
    ("^n", "ⁿ"),
    ("^i", "ⁱ"),
    ("^*", "*"),
];

/// Converts common LaTeX math expressions inside Mermaid labels to clean Unicode text.
/// Used as a graceful fallback when a diagram type does not enable RaTeX math or when
/// an expression contains macros unsupported by RaTeX.
fn latex_to_unicode(latex: &str) -> String {
    let mut s = latex.to_string();

    // 1. Escaped characters
    s = s
        .replace(r"\{", "{")
        .replace(r"\}", "}")
        .replace(r"\%", "%")
        .replace(r"\_", "_")
        .replace(r"\&", "&")
        .replace(r"\#", "#");

    // 2. Spacing commands
    for cmd in &[r"\qquad", r"\quad", r"\;", r"\:", r"\,", r"\!"] {
        s = s.replace(cmd, " ");
    }
    s = s.replace(r"\ ", " ");

    // 3. Structural wrappers
    for wrapper in &[
        r"\text{",
        r"\mathrm{",
        r"\mathbf{",
        r"\mathit{",
        r"\mathcal{",
        r"\mathbb{",
    ] {
        while let Some(idx) = s.find(wrapper) {
            let after_wrapper = idx + wrapper.len();
            if let Some(close_offset) = s[after_wrapper..].find('}') {
                let inner = s[after_wrapper..after_wrapper + close_offset].to_string();
                s.replace_range(idx..after_wrapper + close_offset + 1, &inner);
            } else {
                break;
            }
        }
    }
    s = s.replace(r"\left", "").replace(r"\right", "");

    // 4. Replace macros in a single left-to-right scan so longer names match first
    for &(cmd, unicode, strip_trailing_space) in MACROS {
        let pattern = format!(r"\{}", cmd);
        let mut out = String::with_capacity(s.len());
        let mut rest = s.as_str();

        while let Some(pos) = rest.find(&pattern) {
            out.push_str(&rest[..pos]);
            let after = &rest[pos + pattern.len()..];
            let next_char = after.chars().next();
            let is_boundary = match next_char {
                None => true,
                Some(ch) => !ch.is_ascii_alphabetic(),
            };

            if is_boundary {
                out.push_str(unicode);
                if strip_trailing_space && after.starts_with(' ') {
                    rest = &after[1..];
                } else {
                    rest = after;
                }
            } else {
                out.push_str(unicode);
                rest = after;
            }
        }
        out.push_str(rest);
        s = out;
    }

    // 5. Unwrap simple _{...} and ^{...} braces before applying sub/superscript tables
    s = unwrap_sub_sup_braces(&s);

    // 6. Subscripts & Superscripts
    for &(pat, rep) in SUBSCRIPTS {
        s = s.replace(pat, rep);
    }
    for &(pat, rep) in SUPERSCRIPTS {
        s = s.replace(pat, rep);
    }

    // 7. Collapse multiple spaces
    let mut collapsed = String::with_capacity(s.len());
    let mut prev_space = false;
    for c in s.chars() {
        if c == ' ' {
            if !prev_space {
                collapsed.push(c);
            }
            prev_space = true;
        } else {
            collapsed.push(c);
            prev_space = false;
        }
    }

    collapsed.trim().to_string()
}

/// Promotes single-dollar `$math$` spans in Mermaid source to `$$math$$` so `zebra-mermaid`'s
/// built-in RaTeX engine renders them as authentic vector math outlines.
/// Operates line-by-line so an unclosed `$` (e.g. currency) never consumes across lines.
fn promote_single_dollar_math(code: &str) -> String {
    if !code.contains('$') {
        return code.to_string();
    }

    let mut out = String::with_capacity(code.len() + 32);
    for (line_idx, line) in code.split('\n').enumerate() {
        if line_idx > 0 {
            out.push('\n');
        }
        if !line.contains('$') {
            out.push_str(line);
            continue;
        }

        let mut chars = line.chars().peekable();
        while let Some(c) = chars.next() {
            if c == '\\' {
                out.push(c);
                if let Some(next_c) = chars.next() {
                    out.push(next_c);
                }
                continue;
            }
            if c == '$' {
                if chars.peek() == Some(&'$') {
                    // Existing $$...$$ block: copy through until closing $$
                    chars.next();
                    out.push_str("$$");
                    while let Some(mc) = chars.next() {
                        if mc == '\\' {
                            out.push(mc);
                            if let Some(esc_c) = chars.next() {
                                out.push(esc_c);
                            }
                        } else if mc == '$' && chars.peek() == Some(&'$') {
                            chars.next();
                            out.push_str("$$");
                            break;
                        } else {
                            out.push(mc);
                        }
                    }
                } else {
                    // Single $...$: collect on the same line
                    let mut math_content = String::new();
                    let mut closed = false;
                    while let Some(mc) = chars.next() {
                        if mc == '\\' {
                            math_content.push(mc);
                            if let Some(esc_c) = chars.next() {
                                math_content.push(esc_c);
                            }
                        } else if mc == '$' {
                            closed = true;
                            break;
                        } else {
                            math_content.push(mc);
                        }
                    }
                    let trimmed = math_content.trim();
                    let trailing_digit = chars.peek().is_some_and(|ch| ch.is_ascii_digit());
                    if closed && !trimmed.is_empty() && !trailing_digit {
                        out.push_str("$$");
                        out.push_str(&math_content);
                        out.push_str("$$");
                    } else {
                        out.push('$');
                        out.push_str(&math_content);
                        if closed {
                            out.push('$');
                        }
                    }
                }
            } else {
                out.push(c);
            }
        }
    }

    out
}

/// Preprocesses Mermaid source code to convert inline `$...$` and `$$...$$` LaTeX math
/// into readable Unicode symbols.
pub fn preprocess_mermaid_code(code: &str) -> String {
    if !code.contains('$') {
        return code.to_string();
    }

    let mut result = String::with_capacity(code.len());
    let mut chars = code.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '$' {
            let is_double = chars.peek() == Some(&'$');
            if is_double {
                chars.next(); // consume second '$'
            }

            let mut math_content = String::new();
            let mut closed = false;

            while let Some(mc) = chars.next() {
                if mc == '\\' {
                    // Preserve escape sequences like \$ or \{ inside math
                    if let Some(&next_c) = chars.peek() {
                        if next_c == '$' {
                            chars.next();
                            math_content.push('$');
                            continue;
                        }
                    }
                    math_content.push(mc);
                } else if mc == '$' {
                    if is_double {
                        if chars.peek() == Some(&'$') {
                            chars.next();
                            closed = true;
                            break;
                        } else {
                            math_content.push(mc);
                        }
                    } else {
                        closed = true;
                        break;
                    }
                } else if mc == '\n' && !is_double {
                    math_content.push(mc);
                    break;
                } else {
                    math_content.push(mc);
                }
            }

            if closed {
                let converted = latex_to_unicode(&math_content);
                result.push_str(&converted);
            } else {
                result.push('$');
                if is_double {
                    result.push('$');
                }
                result.push_str(&math_content);
            }
        } else {
            result.push(c);
        }
    }

    result
}

const DEFAULT_MERMAID_FONT_FAMILY: &str = "Inter, ui-sans-serif, system-ui, -apple-system, \"PingFang SC\", \"Microsoft YaHei\", \"Noto Sans CJK SC\", sans-serif";
const DEFAULT_MERMAID_MONO_FAMILY: &str = "\"Maple Mono NF\", \"Maple Mono SC NF\", \"Maple Mono\", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace";

fn build_light_palette() -> zebra_mermaid::MermaidPalette {
    let mut p = zebra_mermaid::MermaidPalette::light();
    p.group_background = Some("#F3F4F6".to_string());
    p.group_border = Some("#D4D4D8".to_string());
    p.edge = Some("#52525B".to_string());
    p
}

fn build_dark_palette() -> zebra_mermaid::MermaidPalette {
    let mut p = zebra_mermaid::MermaidPalette::dark();
    p.background = "#1E1E1E".to_string();
    p.surface = "#252830".to_string();
    p.surface_secondary = "#1E293B".to_string();
    p.text = "#E2E8F0".to_string();
    p.secondary_text = "#94A3B8".to_string();
    p.accent = "#60A5FA".to_string();
    p.border = "#475569".to_string();
    p.group_background = Some("#16181D".to_string());
    p.group_border = Some("#374151".to_string());
    p.edge = Some("#94A3B8".to_string());
    p
}

fn build_render_options(is_dark: bool) -> zebra_mermaid::RenderOptions {
    zebra_mermaid::RenderOptions {
        color_mode: zebra_mermaid::ColorMode::Resolved,
        theme: if is_dark {
            zebra_mermaid::MermaidThemeMode::Dark
        } else {
            zebra_mermaid::MermaidThemeMode::Light
        },
        palette: Some(if is_dark {
            build_dark_palette()
        } else {
            build_light_palette()
        }),
        canvas_background: Some(zebra_mermaid::CanvasBackground::Opaque),
        font_family: Some(DEFAULT_MERMAID_FONT_FAMILY.to_string()),
        font_family_mono: Some(DEFAULT_MERMAID_MONO_FAMILY.to_string()),
        font_size: Some(14.0),
        ..Default::default()
    }
}

/// Renders Mermaid diagram code into an SVG byte stream with SHA-256 caching.
/// If rendering fails, returns a fallback rendered block.
pub fn render_mermaid(code: &str, is_dark: bool) -> RenderedMermaid {
    let theme_tag = if is_dark { "dark" } else { "light" };

    let mut hasher = Sha256::new();
    hasher.update(theme_tag.as_bytes());
    hasher.update(b":");
    hasher.update(code.trim().as_bytes());
    let hash = format!("{:x}", hasher.finalize());
    let virtual_filename = format!("mermaid_{}_{}.svg", theme_tag, &hash[..16]);

    // Check cache
    {
        let mut cache = get_cache().write();
        if let Some(bytes) = cache.get(&hash) {
            return RenderedMermaid {
                virtual_filename,
                svg_bytes: bytes,
                is_fallback: false,
            };
        }
    }

    let options = build_render_options(is_dark);
    let math_promoted = promote_single_dollar_math(code);

    let rendered = zebra_mermaid::render(&math_promoted, &options).and_then(|res| {
        // If the input had math delimiters and the rendered SVG still contains literal `$$`
        // (e.g. in a diagram type or title slot where RaTeX is inactive, or for an unsupported
        // LaTeX macro), fall back to Unicode math conversion so raw `$$...$$` is never shown.
        if code.contains('$') && res.svg.contains("$$") {
            let unicode_fallback = preprocess_mermaid_code(code);
            zebra_mermaid::render(&unicode_fallback, &options)
        } else {
            Ok(res)
        }
    });

    match rendered {
        Ok(res) => {
            let bytes = Bytes::new(res.svg.into_bytes());
            {
                let mut cache = get_cache().write();
                cache.insert(hash, bytes.clone());
            }
            RenderedMermaid {
                virtual_filename,
                svg_bytes: bytes,
                is_fallback: false,
            }
        }
        Err(err) => {
            // Generate a clean fallback SVG indicating the error
            let err_msg = err.to_string().replace('<', "&lt;").replace('>', "&gt;");
            let (bg, stroke, text_color) = if is_dark {
                ("#2d1517", "#5c2227", "#f87171")
            } else {
                ("#f8d7da", "#f5c2c7", "#842029")
            };
            let fallback_svg = format!(
                r##"<svg xmlns="http://www.w3.org/2000/svg" width="600" height="100" viewBox="0 0 600 100">
                    <rect width="600" height="100" rx="8" fill="{bg}" stroke="{stroke}" stroke-width="1.5"/>
                    <text x="20" y="38" font-family="sans-serif" font-size="14" font-weight="bold" fill="{text_color}">
                        [Mermaid Render Error]
                    </text>
                    <text x="20" y="65" font-family="monospace" font-size="11" fill="{text_color}">
                        {}
                    </text>
                </svg>"##,
                err_msg
            );

            RenderedMermaid {
                virtual_filename,
                svg_bytes: Bytes::new(fallback_svg.into_bytes()),
                is_fallback: true,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_render_flowchart() {
        let code = "graph TD;\n  A[Start] --> B[Finish];";
        let res_light = render_mermaid(code, false);
        assert!(!res_light.is_fallback);
        assert!(res_light.virtual_filename.starts_with("mermaid_light_"));
        assert!(res_light.svg_bytes.starts_with(b"<svg"));

        let res_dark = render_mermaid(code, true);
        assert!(!res_dark.is_fallback);
        assert!(res_dark.virtual_filename.starts_with("mermaid_dark_"));
        assert!(res_dark.svg_bytes.starts_with(b"<svg"));
        assert_ne!(res_light.virtual_filename, res_dark.virtual_filename);

        // Verify dark theme resolved colors are applied in SVG
        let dark_svg = String::from_utf8_lossy(&res_dark.svg_bytes).to_ascii_lowercase();
        assert!(dark_svg.contains("#1e1e1e") || dark_svg.contains("#252830"));
    }

    #[test]
    fn test_render_cache_hit() {
        let code = "graph LR;\n  X --> Y;";
        let res1 = render_mermaid(code, false);
        let res2 = render_mermaid(code, false);
        assert_eq!(res1.virtual_filename, res2.virtual_filename);
        assert_eq!(res1.svg_bytes, res2.svg_bytes);

        let res_dark1 = render_mermaid(code, true);
        let res_dark2 = render_mermaid(code, true);
        assert_eq!(res_dark1.virtual_filename, res_dark2.virtual_filename);
        assert_eq!(res_dark1.svg_bytes, res_dark2.svg_bytes);
    }

    #[test]
    fn test_render_invalid_mermaid_fallback() {
        let code = "not a valid mermaid diagram at all %%%!!!";
        let res_light = render_mermaid(code, false);
        assert!(res_light.is_fallback);
        assert!(res_light.svg_bytes.starts_with(b"<svg"));

        let res_dark = render_mermaid(code, true);
        assert!(res_dark.is_fallback);
        assert!(res_dark.svg_bytes.starts_with(b"<svg"));
        let dark_svg = String::from_utf8_lossy(&res_dark.svg_bytes);
        assert!(dark_svg.contains("#2d1517"));
    }

    #[test]
    fn test_latex_to_unicode_conversion() {
        assert_eq!(latex_to_unicode(r"\Delta \tau"), "Δτ");
        assert_eq!(latex_to_unicode(r"\DeltaE"), "ΔE");
        assert_eq!(latex_to_unicode(r"x \quad y"), "x y");
        assert_eq!(latex_to_unicode(r"a \qquad b"), "a b");
        assert_eq!(latex_to_unicode(r"p \ q"), "p q");
        assert_eq!(latex_to_unicode(r"\leq \infty"), "≤ ∞");
        assert_eq!(latex_to_unicode(r"|\Psi^+\rangle_{BC}"), "|Ψ⁺⟩_BC");
        assert_eq!(latex_to_unicode(r"|\Phi^+\rangle_{AB}"), "|Φ⁺⟩_AB");
        assert_eq!(latex_to_unicode(r"b_1 b_2 \in \{00,01,10,11\}"), "b₁ b₂ ∈ {00,01,10,11}");
        assert_eq!(latex_to_unicode(r"\sigma_x^{b_2} \sigma_z^{b_1}"), "σₓ^b₂ σ_z^b₁");
        assert_eq!(latex_to_unicode(r"F = 99.42\%"), "F = 99.42%");
    }

    #[test]
    fn test_preprocess_mermaid_math() {
        let input = "sequenceDiagram\n    Moon-->>Earth: 返回时钟差 $\\Delta \\tau$ 与夏皮罗时延遥测\n    Moon->>Mars: 分发超高频纠缠光子流 $|\\Psi^+\\rangle_{BC}$";
        let output = preprocess_mermaid_code(input);
        assert!(output.contains("返回时钟差 Δτ 与夏皮罗时延遥测"));
        assert!(output.contains("分发超高频纠缠光子流 |Ψ⁺⟩_BC"));

        let promoted = promote_single_dollar_math(input);
        assert!(promoted.contains(r"$$\Delta \tau$$"));
        assert!(promoted.contains(r"$$|\Psi^+\rangle_{BC}$$"));
    }

    #[test]
    fn test_render_sequence_with_latex() {
        let code = r#"sequenceDiagram
    autonumber
    participant Earth as 地球主站
    participant Moon as 月球中继
    Earth->>Moon: 连续激光探测
    Moon-->>Earth: 返回时钟差 $\Delta \tau$ 信号
"#;
        let res = render_mermaid(code, false);
        assert!(!res.is_fallback);
        let svg_str = String::from_utf8_lossy(&res.svg_bytes);
        assert!(svg_str.contains("pele-math") || svg_str.contains("Δτ"));
        assert!(!svg_str.contains(r"\Delta"));

        let res_dark = render_mermaid(code, true);
        assert!(!res_dark.is_fallback);
        let svg_dark = String::from_utf8_lossy(&res_dark.svg_bytes);
        assert!(svg_dark.contains("pele-math") || svg_dark.contains("Δτ"));
        assert!(!svg_dark.contains(r"\Delta"));
    }

    #[test]
    fn test_render_test_md_sequence_diagram() {
        let code = r#"sequenceDiagram
    autonumber
    participant Earth as 地球主站 (Earth-GEO)
    participant Moon as 月球中继 (Lunar-L2)
    participant Mars as 火星前哨 (Mars-Ares)

    Note over Earth,Moon: 阶段一：深空引力频移信标自适应对齐
    Earth->>Moon: 连续激光相对论频偏探测信标
    Moon-->>Earth: 返回时钟差 $\Delta \tau$ 与夏皮罗时延遥测
    
    Note over Moon,Mars: 阶段二：星际纠缠对源分发
    Moon->>Mars: 分发超高频纠缠光子流 $|\Psi^+\rangle_{BC}$
    Moon->>Earth: 分发共轭纠缠光子流 $|\Phi^+\rangle_{AB}$
    
    Note over Moon: 阶段三：中继纠缠交换 (Entanglement Swapping)
    Moon->>Moon: 执行联合贝尔基测量 (BSM on 2,3)
    Moon-->>Earth: 经典前馈信令：BSM 结果 $b_1 b_2 \in \{00,01,10,11\}$
    Moon-->>Mars: 经典前馈广播：对齐时间戳与泡利旋转指令

    Note over Earth,Mars: 阶段四：端到端量子态隐形传输与保真度校核
    Earth->>Earth: 态映射：根据测量结果施加 $\sigma_x^{b_2} \sigma_z^{b_1}$
    Mars->>Mars: 拓扑量子存储单元锁定并执行态层析验证
    Mars-->>Earth: 量子层析保真度收敛确认 ($F = 99.42\%$)
"#;
        let res = render_mermaid(code, false);
        assert!(!res.is_fallback, "Should render without fallback in light mode");
        let svg_str = String::from_utf8_lossy(&res.svg_bytes);
        assert!(svg_str.contains("pele-math"), "Should render inline LaTeX via RaTeX vector math");
        assert!(!svg_str.contains(r"\Delta"));
        assert!(!svg_str.contains(r"\Psi"));
        assert!(!svg_str.contains(r"\Phi"));
        assert!(!svg_str.contains("$$"));

        let res_dark = render_mermaid(code, true);
        assert!(!res_dark.is_fallback, "Should render without fallback in dark mode");
        let svg_dark = String::from_utf8_lossy(&res_dark.svg_bytes).to_ascii_lowercase();
        assert!(svg_dark.contains("pele-math"));
        assert!(svg_dark.contains("#1e1e1e") || svg_dark.contains("#252830"));
    }

    #[test]
    fn test_bounded_cache_capacity() {
        let mut cache = BoundedCache::new(3);
        cache.insert("k1".to_string(), Bytes::new(b"v1"));
        cache.insert("k2".to_string(), Bytes::new(b"v2"));
        cache.insert("k3".to_string(), Bytes::new(b"v3"));
        // Access k1 so it becomes most recently used
        assert_eq!(cache.get("k1"), Some(Bytes::new(b"v1")));

        cache.insert("k4".to_string(), Bytes::new(b"v4"));
        // k2 should be evicted (LRU) because k1 was promoted by get()
        assert_eq!(cache.get("k2"), None);
        assert_eq!(cache.get("k1"), Some(Bytes::new(b"v1")));
        assert_eq!(cache.get("k3"), Some(Bytes::new(b"v3")));
        assert_eq!(cache.get("k4"), Some(Bytes::new(b"v4")));
    }

    #[test]
    fn test_issue_28_flowchart_subgraph_alignment_and_routing() {
        let code = r#"flowchart TB
    subgraph Channels["1. 渠道与入口层 (Channels & Entry)"]
        direction LR
        C1["个人桌面 / 移动端 / 浏览器插件"]
        C2["企业 IM 集成（飞书 / 钉钉 / 企微）"]
        C3["业务系统内嵌 Copilot / OpenAPI"]
    end

    subgraph Application["2. 核心应用层：对话与工作台 (Application Layer)"]
        direction LR
        A1["对话交互中心 (Chat & Thread)"]
        A2["智能体与技能市场 (Agent & Skill Hub)"]
        A3["互动工件画布 (Artifacts / Canvas)"]
        A4["自动化与任务中心 (Automation & Cron)"]
    end

    subgraph Intelligence["3. 智能引擎与编排层 (AI & Orchestration)"]
        direction LR
        I1["意图路由与模型网关 (Model Router)"]
        I2["自主规划与反思引擎 (ReAct / Plan)"]
        I3["多智能体协同框架 (Multi-Agent)"]
        I4["长期记忆与上下文管理 (Memory & Context)"]
    end

    subgraph Data["4. 数据与知识资产层 (Data & Knowledge)"]
        direction LR
        D1["多模态知识库 (RAG / Vector + Graph)"]
        D2["结构化数据引擎 (Text-to-SQL / BI)"]
    end

    subgraph Integration["5. 外部生态与基础底座 (Integration & Infra)"]
        direction LR
        E1["工具与协议连接器 (MCP / API / RPA)"]
        E2["安全沙箱执行环境 (Code / Browser Sandbox)"]
        E3["企业级安全治理 (RBAC / DLP / 审计 / 观测)"]
    end

    Channels --> Application
    Application --> Intelligence
    Intelligence --> Data
    Intelligence --> Integration
    Application --> Data
    Application --> Integration
"#;
        let rendered = render_mermaid(code, false);
        assert!(!rendered.is_fallback, "Issue #28 flowchart must render without fallback");
        let svg = String::from_utf8_lossy(&rendered.svg_bytes);
        assert!(svg.contains("1. 渠道与入口层 (Channels &amp; Entry)"));
        assert!(svg.contains("2. 核心应用层：对话与工作台 (Application Layer)"));
        assert!(svg.contains("3. 智能引擎与编排层 (AI &amp; Orchestration)"));
        assert!(svg.contains("4. 数据与知识资产层 (Data &amp; Knowledge)"));
        assert!(svg.contains("5. 外部生态与基础底座 (Integration &amp; Infra)"));
        assert!(svg.contains("data-id=\"Channels\""));
        assert!(svg.contains("data-id=\"Application\""));
        assert!(svg.contains("data-id=\"Intelligence\""));
        assert!(svg.contains("data-id=\"Data\""));
        assert!(svg.contains("data-id=\"Integration\""));
        assert!(svg.contains("data-id=\"L_Application_Data_0\""));
        assert!(svg.contains("data-id=\"L_Application_Integration_0\""));
        assert!(!svg.contains("var(--"), "Resolved mode must not emit unresolved CSS variables");
    }

    #[test]
    fn test_flowchart_lr_subgraphs_and_strict_unclosed_subgraph_fallback() {
        let code = r#"flowchart LR
    subgraph S1["Stage 1"]
        direction TB
        a1[Step A1]
        a2[Step A2]
    end
    subgraph S2["Stage 2"]
        direction TB
        b1[Step B1]
        b2[Step B2]
    end
    subgraph S3["Stage 3"]
        direction TB
        c1[Step C1]
    end
    S1 --> S2
    S2 --> S3
    S1 --> S3
"#;
        let res = render_mermaid(code, false);
        assert!(!res.is_fallback, "Valid flowchart LR with subgraphs should render");

        // Unclosed subgraph must fail strict parsing and return fallback SVG
        let unclosed = "flowchart TB\n    subgraph S1[\"Unclosed\"]\n        A --> B\n";
        let fallback_res = render_mermaid(unclosed, false);
        assert!(
            fallback_res.is_fallback,
            "Unclosed subgraph without `end` must return fallback SVG"
        );
    }

    #[test]
    fn test_all_major_mermaid_diagram_types() {
        let samples = [
            "classDiagram\n  Animal <|-- Duck\n  Animal : +int age\n  Animal : +isMammal()",
            "stateDiagram-v2\n  [*] --> Still\n  Still --> Moving\n  Moving --> [*]",
            "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER ||--|{ LINE-ITEM : contains",
            "gantt\n  title A Gantt Diagram\n  dateFormat YYYY-MM-DD\n  section Section\n  A task :a1, 2024-01-01, 30d",
            "pie title Pets\n  \"Dogs\" : 386\n  \"Cats\" : 85",
            "mindmap\n  root((mindmap))\n    Origins\n      Long history",
            "gitGraph\n  commit\n  branch develop\n  checkout develop\n  commit\n  checkout main\n  merge develop",
            "timeline\n  title History\n  2023 : Alpha\n  2024 : Beta",
        ];
        for sample in samples {
            let res = render_mermaid(sample, false);
            assert!(
                !res.is_fallback,
                "Diagram should render cleanly with zebra-mermaid: {sample}"
            );
            let svg = String::from_utf8_lossy(&res.svg_bytes);
            assert!(svg.starts_with("<svg"));
            assert!(!svg.contains("var(--"), "Resolved SVG must not contain CSS variables");
        }
    }

    #[test]
    fn test_e2e_zebra_mermaid_diagrams_and_math_compile_to_pdf() {
        let md = r#"# Mermaid E2E Test

```mermaid
flowchart LR
    A["Energy $E = mc^2$"] --> B["Fraction $$\frac{\alpha + \beta}{\sqrt{\gamma}}$$"]
```

```mermaid
classDiagram
    Animal <|-- Duck
    Animal : +int age
    Animal : +isMammal()
```

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing
    Processing --> [*]
```

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE-ITEM : contains
```
"#;
        let opts = crate::RenderOptions::default();
        let pdf = crate::compile_markdown_to_pdf(md, "Mermaid E2E", ".", &opts)
            .expect("Markdown with zebra-mermaid diagrams and RaTeX math must compile to PDF");
        assert!(pdf.starts_with(b"%PDF-"));
        assert!(pdf.len() > 1000);
    }
}
