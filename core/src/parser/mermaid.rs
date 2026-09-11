use std::collections::HashMap;
use std::sync::OnceLock;
use parking_lot::RwLock;
use sha2::{Digest, Sha256};

static MERMAID_CACHE: OnceLock<RwLock<HashMap<String, Vec<u8>>>> = OnceLock::new();

fn get_cache() -> &'static RwLock<HashMap<String, Vec<u8>>> {
    MERMAID_CACHE.get_or_init(|| RwLock::new(HashMap::new()))
}

pub struct RenderedMermaid {
    pub virtual_filename: String,
    pub svg_bytes: Vec<u8>,
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

/// Translates common LaTeX math expressions inside Mermaid diagrams into clean Unicode symbols.
pub fn latex_to_unicode(math: &str) -> String {
    let unwrapped = unwrap_sub_sup_braces(math.trim());
    let mut s = unwrapped;

    // Specific replacements for LaTeX macros
    let macros = [
        // Greek upper (with and without space)
        (r"\Delta ", "Δ"),
        (r"\Delta", "Δ"),
        (r"\Gamma ", "Γ"),
        (r"\Gamma", "Γ"),
        (r"\Theta ", "Θ"),
        (r"\Theta", "Θ"),
        (r"\Lambda ", "Λ"),
        (r"\Lambda", "Λ"),
        (r"\Xi ", "Ξ"),
        (r"\Xi", "Ξ"),
        (r"\Pi ", "Π"),
        (r"\Pi", "Π"),
        (r"\Sigma ", "Σ"),
        (r"\Sigma", "Σ"),
        (r"\Phi ", "Φ"),
        (r"\Phi", "Φ"),
        (r"\Psi ", "Ψ"),
        (r"\Psi", "Ψ"),
        (r"\Omega ", "Ω"),
        (r"\Omega", "Ω"),
        // Greek lower (with and without space)
        (r"\alpha ", "α"),
        (r"\alpha", "α"),
        (r"\beta ", "β"),
        (r"\beta", "β"),
        (r"\gamma ", "γ"),
        (r"\gamma", "γ"),
        (r"\delta ", "δ"),
        (r"\delta", "δ"),
        (r"\epsilon ", "ε"),
        (r"\epsilon", "ε"),
        (r"\varepsilon ", "ε"),
        (r"\varepsilon", "ε"),
        (r"\zeta ", "ζ"),
        (r"\zeta", "ζ"),
        (r"\eta ", "η"),
        (r"\eta", "η"),
        (r"\theta ", "θ"),
        (r"\theta", "θ"),
        (r"\vartheta ", "θ"),
        (r"\vartheta", "θ"),
        (r"\iota ", "ι"),
        (r"\iota", "ι"),
        (r"\kappa ", "κ"),
        (r"\kappa", "κ"),
        (r"\lambda ", "λ"),
        (r"\lambda", "λ"),
        (r"\mu ", "μ"),
        (r"\mu", "μ"),
        (r"\nu ", "ν"),
        (r"\nu", "ν"),
        (r"\xi ", "ξ"),
        (r"\xi", "ξ"),
        (r"\pi ", "π"),
        (r"\pi", "π"),
        (r"\rho ", "ρ"),
        (r"\rho", "ρ"),
        (r"\sigma ", "σ"),
        (r"\sigma", "σ"),
        (r"\tau ", "τ"),
        (r"\tau", "τ"),
        (r"\upsilon ", "υ"),
        (r"\upsilon", "υ"),
        (r"\phi ", "ϕ"),
        (r"\phi", "ϕ"),
        (r"\varphi ", "φ"),
        (r"\varphi", "φ"),
        (r"\chi ", "χ"),
        (r"\chi", "χ"),
        (r"\psi ", "ψ"),
        (r"\psi", "ψ"),
        (r"\omega ", "ω"),
        (r"\omega", "ω"),
        // Quantum & Brackets
        (r"\rangle", "⟩"),
        (r"\langle", "⟨"),
        (r"\vert", "|"),
        (r"\{", "{"),
        (r"\}", "}"),
        // Operators & Relations
        (r"\in", "∈"),
        (r"\notin", "∉"),
        (r"\subset", "⊂"),
        (r"\subseteq", "⊆"),
        (r"\times", "×"),
        (r"\cdot", "·"),
        (r"\pm", "±"),
        (r"\mp", "∓"),
        (r"\div", "÷"),
        (r"\le", "≤"),
        (r"\leq", "≤"),
        (r"\ge", "≥"),
        (r"\geq", "≥"),
        (r"\ne", "≠"),
        (r"\neq", "≠"),
        (r"\approx", "≈"),
        (r"\equiv", "≡"),
        (r"\sim", "∼"),
        (r"\to", "→"),
        (r"\rightarrow", "→"),
        (r"\leftarrow", "←"),
        (r"\Rightarrow", "⇒"),
        (r"\Leftarrow", "⇐"),
        (r"\infty", "∞"),
        (r"\hbar", "ℏ"),
        (r"\partial", "∂"),
        (r"\nabla", "∇"),
        (r"\sum", "∑"),
        (r"\prod", "∏"),
        (r"\int", "∫"),
        (r"\%", "%"),
        (r"\ ", " "),
        (r"\quad", " "),
        (r"\qquad", "  "),
    ];

    for (pattern, replacement) in macros {
        s = s.replace(pattern, replacement);
    }

    // Common superscripts
    s = s.replace("^+", "⁺")
        .replace("^-", "⁻")
        .replace("^{0}", "⁰").replace("^0", "⁰")
        .replace("^{1}", "¹").replace("^1", "¹")
        .replace("^{2}", "²").replace("^2", "²")
        .replace("^{3}", "³").replace("^3", "³")
        .replace("^{4}", "⁴").replace("^4", "⁴")
        .replace("^{5}", "⁵").replace("^5", "⁵")
        .replace("^{6}", "⁶").replace("^6", "⁶")
        .replace("^{7}", "⁷").replace("^7", "⁷")
        .replace("^{8}", "⁸").replace("^8", "⁸")
        .replace("^{9}", "⁹").replace("^9", "⁹");

    // Common subscripts
    s = s.replace("_{0}", "₀").replace("_0", "₀")
        .replace("_{1}", "₁").replace("_1", "₁")
        .replace("_{2}", "₂").replace("_2", "₂")
        .replace("_{3}", "₃").replace("_3", "₃")
        .replace("_{4}", "₄").replace("_4", "₄")
        .replace("_{5}", "₅").replace("_5", "₅")
        .replace("_{6}", "₆").replace("_6", "₆")
        .replace("_{7}", "₇").replace("_7", "₇")
        .replace("_{8}", "₈").replace("_8", "₈")
        .replace("_{9}", "₉").replace("_9", "₉")
        .replace("_{+}", "₊").replace("_+", "₊")
        .replace("_{-}", "₋").replace("_-", "₋");

    // Clean up multiple spaces
    let mut cleaned = String::with_capacity(s.len());
    let mut prev_space = false;
    for c in s.chars() {
        if c == ' ' {
            if !prev_space {
                cleaned.push(c);
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
                svg_bytes: bytes.clone(),
                is_fallback: false,
            };
        }
    }

    // Render using mermaid-rs-renderer
    match mermaid_rs_renderer::render(&processed_code) {
        Ok(svg_string) => {
            let bytes = svg_string.into_bytes();
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
                svg_bytes: fallback_svg.into_bytes(),
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
}
