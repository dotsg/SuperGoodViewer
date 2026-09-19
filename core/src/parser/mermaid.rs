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
    // Length 5
    ("Delta", "Δ", true),
    ("Gamma", "Γ", true),
    ("Theta", "Θ", true),
    ("Sigma", "Σ", true),
    ("Omega", "Ω", true),
    ("alpha", "α", true),
    ("gamma", "γ", true),
    ("delta", "δ", true),
    ("theta", "θ", true),
    ("kappa", "κ", true),
    ("sigma", "σ", true),
    ("omega", "ω", true),
    ("notin", "∉", false),
    ("subset", "⊂", false),
    ("equiv", "≡", false),
    ("infty", "∞", false),
    ("partial", "∂", false),
    ("nabla", "∇", false),
    ("qquad", " ", false),
    // Length 4
    ("beta", "β", true),
    ("zeta", "ζ", true),
    ("iota", "ι", true),
    ("times", "×", false),
    ("cdot", "·", false),
    ("neq", "≠", false),
    ("hbar", "ℏ", false),
    ("prod", "∏", false),
    ("quad", " ", false),
    ("vert", "|", false),
    // Length 3
    ("Phi", "Φ", true),
    ("Psi", "Ψ", true),
    ("eta", "η", true),
    ("rho", "ρ", true),
    ("tau", "τ", true),
    ("phi", "ϕ", true),
    ("chi", "χ", true),
    ("psi", "ψ", true),
    ("pm", "±", false),
    ("mp", "∓", false),
    ("div", "÷", false),
    ("leq", "≤", false),
    ("geq", "≥", false),
    ("sim", "∼", false),
    ("sum", "∑", false),
    ("int", "∫", false),
    // Length 2
    ("Xi", "Ξ", true),
    ("Pi", "Π", true),
    ("mu", "μ", true),
    ("nu", "ν", true),
    ("xi", "ξ", true),
    ("pi", "π", true),
    ("in", "∈", false),
    ("le", "≤", false),
    ("ge", "≥", false),
    ("ne", "≠", false),
    ("to", "→", false),
];

fn match_macro_prefix(chars: &[char]) -> Option<(&'static str, usize, bool)> {
    for &(name, rep, eat_space) in MACROS {
        let name_chars = name.chars().count();
        if chars.len() >= name_chars {
            let matches = chars.iter().take(name_chars).zip(name.chars()).all(|(&c1, c2)| c1 == c2);
            if matches {
                return Some((rep, name_chars, eat_space));
            }
        }
    }
    None
}

fn to_superscript(c: char) -> Option<char> {
    match c {
        '0' => Some('⁰'),
        '1' => Some('¹'),
        '2' => Some('²'),
        '3' => Some('³'),
        '4' => Some('⁴'),
        '5' => Some('⁵'),
        '6' => Some('⁶'),
        '7' => Some('⁷'),
        '8' => Some('⁸'),
        '9' => Some('⁹'),
        '+' => Some('⁺'),
        '-' => Some('⁻'),
        _ => None,
    }
}

fn to_subscript(c: char) -> Option<char> {
    match c {
        '0' => Some('₀'),
        '1' => Some('₁'),
        '2' => Some('₂'),
        '3' => Some('₃'),
        '4' => Some('₄'),
        '5' => Some('₅'),
        '6' => Some('₆'),
        '7' => Some('₇'),
        '8' => Some('₈'),
        '9' => Some('₉'),
        '+' => Some('₊'),
        '-' => Some('₋'),
        _ => None,
    }
}

/// Translates common LaTeX math expressions inside Mermaid diagrams into clean Unicode symbols.
pub fn latex_to_unicode(math: &str) -> String {
    let unwrapped = unwrap_sub_sup_braces(math.trim());
    let chars: Vec<char> = unwrapped.chars().collect();
    let len = chars.len();
    let mut out = String::with_capacity(len);
    let mut i = 0;

    while i < len {
        let c = chars[i];
        if c == '\\' {
            i += 1;
            if i >= len {
                out.push('\\');
                break;
            }
            let next_c = chars[i];
            match next_c {
                '{' => { out.push('{'); i += 1; }
                '}' => { out.push('}'); i += 1; }
                '%' => { out.push('%'); i += 1; }
                ' ' => { out.push(' '); i += 1; }
                _ => {
                    if let Some((rep, match_len, eat_space)) = match_macro_prefix(&chars[i..]) {
                        out.push_str(rep);
                        i += match_len;
                        if eat_space && i < len && chars[i] == ' ' {
                            i += 1;
                        }
                    } else {
                        out.push('\\');
                        out.push(next_c);
                        i += 1;
                    }
                }
            }
        } else if c == '^' {
            i += 1;
            if i < len {
                if let Some(sup) = to_superscript(chars[i]) {
                    out.push(sup);
                    i += 1;
                } else {
                    out.push('^');
                }
            } else {
                out.push('^');
            }
        } else if c == '_' {
            i += 1;
            if i < len {
                if let Some(sub) = to_subscript(chars[i]) {
                    out.push(sub);
                    i += 1;
                } else {
                    out.push('_');
                }
            } else {
                out.push('_');
            }
        } else {
            out.push(c);
            i += 1;
        }
    }

    // Collapse multiple spaces and trim
    let mut cleaned = String::with_capacity(out.len());
    let mut prev_space = false;
    for c in out.chars() {
        if c == ' ' {
            if !prev_space {
                cleaned.push(' ');
                prev_space = true;
            }
        } else {
            cleaned.push(c);
            prev_space = false;
        }
    }

    cleaned.trim().to_string()
}

/// Preprocesses Mermaid diagram source code, converting embedded LaTeX math `$ ... $` or `$$ ... $$`
/// into clean, rendered Unicode symbols suitable for Mermaid SVG text generation.
pub fn preprocess_mermaid_code(code: &str) -> String {
    let mut result = String::with_capacity(code.len());
    let mut chars = code.chars().peekable();

    while let Some(c) = chars.next() {
        if c == '$' {
            let is_double = chars.peek() == Some(&'$');
            if is_double {
                chars.next();
            }

            let mut math_content = String::new();
            let mut closed = false;

            while let Some(mc) = chars.next() {
                if mc == '$' {
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

fn build_light_theme() -> mermaid_rs_renderer::Theme {
    let mut theme = mermaid_rs_renderer::Theme::modern();
    theme.font_family = "Inter, ui-sans-serif, system-ui, -apple-system, \"PingFang SC\", \"Microsoft YaHei\", \"Noto Sans CJK SC\", sans-serif".to_string();
    theme.background = "#FFFFFF".to_string();
    theme
}

fn build_dark_theme() -> mermaid_rs_renderer::Theme {
    let primary_color = "#252830".to_string();
    let secondary_color = "#1e293b".to_string();
    let tertiary_color = "#0f172a".to_string();
    mermaid_rs_renderer::Theme {
        font_family: "Inter, ui-sans-serif, system-ui, -apple-system, \"PingFang SC\", \"Microsoft YaHei\", \"Noto Sans CJK SC\", sans-serif".to_string(),
        font_size: 14.0,
        primary_color: primary_color.clone(),
        primary_text_color: "#e2e8f0".to_string(),
        primary_border_color: "#475569".to_string(),
        line_color: "#94a3b8".to_string(),
        secondary_color: secondary_color.clone(),
        tertiary_color,
        edge_label_background: "#1e1e1e".to_string(),
        cluster_background: "#16181d".to_string(),
        cluster_border: "#374151".to_string(),
        background: "#1e1e1e".to_string(),
        sequence_actor_fill: primary_color.clone(),
        sequence_actor_border: "#475569".to_string(),
        sequence_actor_line: "#64748b".to_string(),
        sequence_note_fill: "#2a2718".to_string(),
        sequence_note_border: "#786221".to_string(),
        sequence_activation_fill: secondary_color,
        sequence_activation_border: "#60a5fa".to_string(),
        text_color: "#e2e8f0".to_string(),
        git_colors: [
            "#60a5fa", "#34d399", "#f472b6", "#fbbf24", "#a78bfa", "#38bdf8", "#fb923c",
            "#4ade80",
        ]
        .map(|s| s.to_string()),
        git_inv_colors: [
            "#93c5fd", "#6ee7b7", "#f9a8d4", "#fde68a", "#c4b5fd", "#7dd3fc", "#fdba74",
            "#86efac",
        ]
        .map(|s| s.to_string()),
        git_branch_label_colors: [
            "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#ffffff",
            "#ffffff",
        ]
        .map(|s| s.to_string()),
        git_commit_label_color: "#e2e8f0".to_string(),
        git_commit_label_background: primary_color,
        git_tag_label_color: "#e2e8f0".to_string(),
        git_tag_label_background: "#1e293b".to_string(),
        git_tag_label_border: "#475569".to_string(),
        pie_colors: [
            "#38bdf8", "#818cf8", "#c084fc", "#f472b6", "#fb7185", "#fb923c", "#facc15",
            "#4ade80", "#2dd4bf", "#22d3ee", "#a78bfa", "#e879f9",
        ]
        .map(|s| s.to_string()),
        pie_title_text_size: 25.0,
        pie_title_text_color: "#f1f5f9".to_string(),
        pie_section_text_size: 17.0,
        pie_section_text_color: "#ffffff".to_string(),
        pie_legend_text_size: 17.0,
        pie_legend_text_color: "#cbd5e1".to_string(),
        pie_stroke_color: "#1e1e1e".to_string(),
        pie_stroke_width: 1.6,
        pie_outer_stroke_width: 1.6,
        pie_outer_stroke_color: "#374151".to_string(),
        pie_opacity: 0.9,
    }
}

/// Renders Mermaid diagram code into an SVG byte stream with SHA-256 caching.
/// If rendering fails, returns a fallback rendered block.
pub fn render_mermaid(code: &str, is_dark: bool) -> RenderedMermaid {
    let processed_code = preprocess_mermaid_code(code);
    let theme_tag = if is_dark { "dark" } else { "light" };

    let mut hasher = Sha256::new();
    hasher.update(theme_tag.as_bytes());
    hasher.update(b":");
    hasher.update(processed_code.trim().as_bytes());
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

    let theme = if is_dark {
        build_dark_theme()
    } else {
        build_light_theme()
    };
    let render_opts = mermaid_rs_renderer::RenderOptions {
        theme,
        layout: mermaid_rs_renderer::LayoutConfig::default(),
    };

    // Render using mermaid-rs-renderer
    match mermaid_rs_renderer::render_with_options(&processed_code, render_opts) {
        Ok(svg_string) => {
            let bytes = Bytes::new(svg_string.into_bytes());
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

        // Verify dark theme colors are applied in SVG
        let dark_svg = String::from_utf8_lossy(&res_dark.svg_bytes);
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
        assert_eq!(latex_to_unicode(r"\sigma_x^{b_2} \sigma_z^{b_1}"), "σ_x^b₂ σ_z^b₁");
        assert_eq!(latex_to_unicode(r"F = 99.42\%"), "F = 99.42%");
    }

    #[test]
    fn test_preprocess_mermaid_math() {
        let input = "sequenceDiagram\n    Moon-->>Earth: 返回时钟差 $\\Delta \\tau$ 与夏皮罗时延遥测\n    Moon->>Mars: 分发超高频纠缠光子流 $|\\Psi^+\\rangle_{BC}$";
        let output = preprocess_mermaid_code(input);
        assert!(output.contains("返回时钟差 Δτ 与夏皮罗时延遥测"));
        assert!(output.contains("分发超高频纠缠光子流 |Ψ⁺⟩_BC"));
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
        assert!(svg_str.contains("Δτ"));
        assert!(!svg_str.contains(r"\Delta"));

        let res_dark = render_mermaid(code, true);
        assert!(!res_dark.is_fallback);
        let svg_dark = String::from_utf8_lossy(&res_dark.svg_bytes);
        assert!(svg_dark.contains("Δτ"));
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
        assert!(svg_str.contains("Δτ"));
        assert!(svg_str.contains("|Ψ⁺⟩_BC"));
        assert!(svg_str.contains("|Φ⁺⟩_AB"));
        assert!(svg_str.contains("∈"));
        assert!(!svg_str.contains(r"\Delta"));
        assert!(!svg_str.contains(r"\Psi"));
        assert!(!svg_str.contains(r"\Phi"));

        let res_dark = render_mermaid(code, true);
        assert!(!res_dark.is_fallback, "Should render without fallback in dark mode");
        let svg_dark = String::from_utf8_lossy(&res_dark.svg_bytes);
        assert!(svg_dark.contains("Δτ"));
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
}
