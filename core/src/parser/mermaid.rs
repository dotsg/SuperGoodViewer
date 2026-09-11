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

    fn get(&self, key: &str) -> Option<Bytes> {
        self.map.get(key).cloned()
    }

    fn insert(&mut self, key: String, val: Bytes) {
        if self.map.contains_key(&key) {
            self.map.insert(key, val);
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

fn macro_replacement(name: &str) -> Option<(&'static str, bool)> {
    match name {
        // Greek Upper (eats trailing space as LaTeX command delimiter)
        "Delta" => Some(("Δ", true)),
        "Gamma" => Some(("Γ", true)),
        "Theta" => Some(("Θ", true)),
        "Lambda" => Some(("Λ", true)),
        "Xi" => Some(("Ξ", true)),
        "Pi" => Some(("Π", true)),
        "Sigma" => Some(("Σ", true)),
        "Phi" => Some(("Φ", true)),
        "Psi" => Some(("Ψ", true)),
        "Omega" => Some(("Ω", true)),
        // Greek Lower
        "alpha" => Some(("α", true)),
        "beta" => Some(("β", true)),
        "gamma" => Some(("γ", true)),
        "delta" => Some(("δ", true)),
        "epsilon" => Some(("ε", true)),
        "varepsilon" => Some(("ε", true)),
        "zeta" => Some(("ζ", true)),
        "eta" => Some(("η", true)),
        "theta" => Some(("θ", true)),
        "vartheta" => Some(("θ", true)),
        "iota" => Some(("ι", true)),
        "kappa" => Some(("κ", true)),
        "lambda" => Some(("λ", true)),
        "mu" => Some(("μ", true)),
        "nu" => Some(("ν", true)),
        "xi" => Some(("ξ", true)),
        "pi" => Some(("π", true)),
        "rho" => Some(("ρ", true)),
        "sigma" => Some(("σ", true)),
        "tau" => Some(("τ", true)),
        "upsilon" => Some(("υ", true)),
        "phi" => Some(("ϕ", true)),
        "varphi" => Some(("φ", true)),
        "chi" => Some(("χ", true)),
        "psi" => Some(("ψ", true)),
        "omega" => Some(("ω", true)),
        // Quantum & Brackets
        "rangle" => Some(("⟩", false)),
        "langle" => Some(("⟨", false)),
        "vert" => Some(("|", false)),
        // Operators & Relations
        "in" => Some(("∈", false)),
        "notin" => Some(("∉", false)),
        "subset" => Some(("⊂", false)),
        "subseteq" => Some(("⊆", false)),
        "times" => Some(("×", false)),
        "cdot" => Some(("·", false)),
        "pm" => Some(("±", false)),
        "mp" => Some(("∓", false)),
        "div" => Some(("÷", false)),
        "le" => Some(("≤", false)),
        "leq" => Some(("≤", false)),
        "ge" => Some(("≥", false)),
        "geq" => Some(("≥", false)),
        "ne" => Some(("≠", false)),
        "neq" => Some(("≠", false)),
        "approx" => Some(("≈", false)),
        "equiv" => Some(("≡", false)),
        "sim" => Some(("∼", false)),
        "to" => Some(("→", false)),
        "rightarrow" => Some(("→", false)),
        "leftarrow" => Some(("←", false)),
        "Rightarrow" => Some(("⇒", false)),
        "Leftarrow" => Some(("⇐", false)),
        "infty" => Some(("∞", false)),
        "hbar" => Some(("ℏ", false)),
        "partial" => Some(("∂", false)),
        "nabla" => Some(("∇", false)),
        "sum" => Some(("∑", false)),
        "prod" => Some(("∏", false)),
        "int" => Some(("∫", false)),
        "quad" => Some((" ", false)),
        "qquad" => Some(("  ", false)),
        _ => None,
    }
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

/// Translates common LaTeX math expressions inside Mermaid diagrams into clean Unicode symbols
/// in a high-efficiency single pass without intermediate string allocations.
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
                _ if next_c.is_alphabetic() => {
                    let start = i;
                    while i < len && chars[i].is_alphabetic() {
                        i += 1;
                    }
                    let name: String = chars[start..i].iter().collect();
                    if let Some((rep, eat_space)) = macro_replacement(&name) {
                        out.push_str(rep);
                        if eat_space && i < len && chars[i] == ' ' {
                            i += 1;
                        }
                    } else {
                        out.push('\\');
                        out.push_str(&name);
                    }
                }
                _ => {
                    out.push('\\');
                    out.push(next_c);
                    i += 1;
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
        } else if c == ' ' {
            if !out.ends_with(' ') && !out.is_empty() {
                out.push(' ');
            }
            i += 1;
        } else {
            out.push(c);
            i += 1;
        }
    }

    out.trim().to_string()
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

/// Renders Mermaid diagram code into an SVG byte stream with SHA-256 caching.
/// If rendering fails, returns a fallback rendered block.
pub fn render_mermaid(code: &str) -> RenderedMermaid {
    let processed_code = preprocess_mermaid_code(code);

    let mut hasher = Sha256::new();
    hasher.update(processed_code.trim().as_bytes());
    let hash = format!("{:x}", hasher.finalize());
    let virtual_filename = format!("mermaid_{}.svg", &hash[..16]);

    // Check cache
    {
        let cache = get_cache().read();
        if let Some(bytes) = cache.get(&hash) {
            return RenderedMermaid {
                virtual_filename,
                svg_bytes: bytes,
                is_fallback: false,
            };
        }
    }

    // Render using mermaid-rs-renderer
    match mermaid_rs_renderer::render(&processed_code) {
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
            let fallback_svg = format!(
                r##"<svg xmlns="http://www.w3.org/2000/svg" width="600" height="100" viewBox="0 0 600 100">
                    <rect width="600" height="100" rx="8" fill="#f8d7da" stroke="#f5c2c7" stroke-width="1.5"/>
                    <text x="20" y="38" font-family="sans-serif" font-size="14" font-weight="bold" fill="#842029">
                        [Mermaid Render Error]
                    </text>
                    <text x="20" y="65" font-family="monospace" font-size="11" fill="#842029">
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
        let res = render_mermaid(code);
        assert!(!res.is_fallback);
        assert!(res.virtual_filename.starts_with("mermaid_"));
        assert!(res.svg_bytes.starts_with(b"<svg"));
    }

    #[test]
    fn test_render_cache_hit() {
        let code = "graph LR;\n  X --> Y;";
        let res1 = render_mermaid(code);
        let res2 = render_mermaid(code);
        assert_eq!(res1.virtual_filename, res2.virtual_filename);
        assert_eq!(res1.svg_bytes, res2.svg_bytes);
    }

    #[test]
    fn test_render_invalid_mermaid_fallback() {
        let code = "not a valid mermaid diagram at all %%%!!!";
        let res = render_mermaid(code);
        assert!(res.is_fallback);
        assert!(res.svg_bytes.starts_with(b"<svg"));
    }

    #[test]
    fn test_latex_to_unicode_conversion() {
        assert_eq!(latex_to_unicode(r"\Delta \tau"), "Δτ");
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
        let res = render_mermaid(code);
        assert!(!res.is_fallback);
        let svg_str = String::from_utf8_lossy(&res.svg_bytes);
        assert!(svg_str.contains("Δτ"));
        assert!(!svg_str.contains(r"\Delta"));
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
        let res = render_mermaid(code);
        assert!(!res.is_fallback, "Should render without fallback");
        let svg_str = String::from_utf8_lossy(&res.svg_bytes);
        assert!(svg_str.contains("Δτ"));
        assert!(svg_str.contains("|Ψ⁺⟩_BC"));
        assert!(svg_str.contains("|Φ⁺⟩_AB"));
        assert!(svg_str.contains("∈"));
        assert!(!svg_str.contains(r"\Delta"));
        assert!(!svg_str.contains(r"\Psi"));
        assert!(!svg_str.contains(r"\Phi"));
    }

    #[test]
    fn test_bounded_cache_capacity() {
        let mut cache = BoundedCache::new(3);
        cache.insert("k1".to_string(), Bytes::new(b"v1"));
        cache.insert("k2".to_string(), Bytes::new(b"v2"));
        cache.insert("k3".to_string(), Bytes::new(b"v3"));
        assert_eq!(cache.get("k1"), Some(Bytes::new(b"v1")));

        cache.insert("k4".to_string(), Bytes::new(b"v4"));
        // k1 should be evicted since capacity is 3
        assert_eq!(cache.get("k1"), None);
        assert_eq!(cache.get("k2"), Some(Bytes::new(b"v2")));
        assert_eq!(cache.get("k3"), Some(Bytes::new(b"v3")));
        assert_eq!(cache.get("k4"), Some(Bytes::new(b"v4")));
    }
}
