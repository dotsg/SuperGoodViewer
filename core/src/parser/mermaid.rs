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
    ("lminus", "−", true),
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
    ("lnot", "¬", true),
    ("land", "∧", false),
    // Length 3
    ("Phi", "Φ", true),
    ("Psi", "Ψ", true),
    ("eta", "η", true),
    ("rho", "ρ", true),
    ("tau", "τ", true),
    ("phi", "ϕ", true),
    ("chi", "χ", true),
    ("psi", "ψ", true),
    ("cap", "∩", false),
    ("cup", "∪", false),
    ("lor", "∨", false),
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

#[derive(Debug, Clone, Copy)]
struct FlowchartRefineConfig {
    header_unwrap_padding: f32,
    header_min_box_extra_h: f32,
    min_cross_gap: f32,
    min_main_gap: f32,
    main_gap_tolerance: f32,
    canvas_start_offset: f32,
    port_corner_pad: f32,
    detour_base_offset: f32,
    detour_lane_step: f32,
    obstructed_approach_gap: f32,
    parallel_edge_spacing: f32,
    canvas_margin: f32,
}

impl Default for FlowchartRefineConfig {
    fn default() -> Self {
        Self {
            header_unwrap_padding: 40.0,
            header_min_box_extra_h: 24.0,
            min_cross_gap: 36.0,
            min_main_gap: 52.0,
            main_gap_tolerance: 28.0,
            canvas_start_offset: 40.0,
            port_corner_pad: 18.0,
            detour_base_offset: 28.0,
            detour_lane_step: 22.0,
            obstructed_approach_gap: 24.0,
            parallel_edge_spacing: 18.0,
            canvas_margin: 16.0,
        }
    }
}

fn estimate_single_line_width(text: &str, font_size: f32) -> f32 {
    let mut width = 0.0f32;
    for ch in text.chars() {
        let code = ch as u32;
        if code > 0xFFFF || (0x2000..=0x2BFF).contains(&code) {
            // Emoji and wide mathematical/dingbat symbols
            width += font_size * 1.25;
        } else if code > 0x7F {
            // CJK ideographs and full-width punctuation
            width += font_size * 1.05;
        } else if ch.is_ascii_uppercase() || matches!(ch, 'w' | 'm' | '@' | '%') {
            width += font_size * 0.72;
        } else {
            width += font_size * 0.58;
        }
    }
    width + font_size * 1.2
}

fn shift_subgraph_contents(
    sub_idx: usize,
    dx: f32,
    dy: f32,
    layout: &mut mermaid_rs_renderer::Layout,
    sub_member_sets: &[std::collections::HashSet<String>],
    nested_children: &[Vec<usize>],
    sub_to_anchor_ids: &[Vec<String>],
) {
    if dx.abs() < 1e-3 && dy.abs() < 1e-3 {
        return;
    }
    let mut affected_subs = vec![sub_idx];
    affected_subs.extend_from_slice(&nested_children[sub_idx]);

    let mut moved_nodes = std::collections::HashSet::new();
    for &s_idx in &affected_subs {
        if let Some(sub) = layout.subgraphs.get_mut(s_idx) {
            sub.x += dx;
            sub.y += dy;
            for n_id in &sub.nodes {
                moved_nodes.insert(n_id.clone());
            }
        }
        for anchor_id in &sub_to_anchor_ids[s_idx] {
            moved_nodes.insert(anchor_id.clone());
        }
    }

    for node_id in &moved_nodes {
        if let Some(node) = layout.nodes.get_mut(node_id) {
            node.x += dx;
            node.y += dy;
        }
    }

    let member_set = &sub_member_sets[sub_idx];
    for edge in &mut layout.edges {
        if member_set.contains(&edge.from) && member_set.contains(&edge.to) {
            for pt in &mut edge.points {
                pt.0 += dx;
                pt.1 += dy;
            }
            if let Some(ref mut anchor) = edge.label_anchor {
                anchor.0 += dx;
                anchor.1 += dy;
            }
            if let Some(ref mut anchor) = edge.start_label_anchor {
                anchor.0 += dx;
                anchor.1 += dy;
            }
            if let Some(ref mut anchor) = edge.end_label_anchor {
                anchor.0 += dx;
                anchor.1 += dy;
            }
        }
    }
}

fn compute_edge_label_anchor(
    points: &[(f32, f32)],
    label_size: (f32, f32),
    pair_ord: usize,
    pair_total: usize,
    parallel_offset: f32,
    detour_dir: Option<f32>,
) -> (f32, f32) {
    if points.is_empty() {
        return (0.0, 0.0);
    }
    if points.len() == 1 {
        return points[0];
    }
    let mut best_len_sq = -1.0f32;
    let mut best_seg = (points[0], points[1]);
    for pair in points.windows(2) {
        let dx = pair[1].0 - pair[0].0;
        let dy = pair[1].1 - pair[0].1;
        let len_sq = dx * dx + dy * dy;
        if len_sq > best_len_sq {
            best_len_sq = len_sq;
            best_seg = (pair[0], pair[1]);
        }
    }
    let (p0, p1) = best_seg;
    let mut ax = (p0.0 + p1.0) * 0.5;
    let mut ay = (p0.1 + p1.1) * 0.5;
    let (lw, lh) = label_size;
    let dx = (p1.0 - p0.0).abs();
    let dy = (p1.1 - p0.1).abs();

    if let Some(dir) = detour_dir {
        if dy >= dx {
            ax += dir * (lw * 0.5 + 4.0);
        } else {
            ay += dir * (lh * 0.5 + 4.0);
        }
    } else if pair_total > 1 {
        let rank_centered = pair_ord as f32 - (pair_total as f32 - 1.0) * 0.5;
        if dy >= dx {
            // Vertical segment: shift label outward away from sibling parallel edges
            if parallel_offset.abs() > 0.5 {
                ax += parallel_offset.signum() * (lw * 0.5 + 4.0);
            }
            if pair_total >= 3 {
                let half_usable = (dy * 0.5 - lh * 0.5 - 6.0).max(0.0);
                ay += (rank_centered * (lh + 8.0)).clamp(-half_usable, half_usable);
            }
        } else {
            // Horizontal segment: shift label outward vertically away from sibling parallel edges
            if parallel_offset.abs() > 0.5 {
                ay += parallel_offset.signum() * (lh * 0.5 + 4.0);
            }
            if pair_total >= 3 {
                let half_usable = (dx * 0.5 - lw * 0.5 - 6.0).max(0.0);
                ax += (rank_centered * (lw + 12.0)).clamp(-half_usable, half_usable);
            }
        }
    }

    (ax, ay)
}

/// Normalizes flowchart subgraphs before `compute_layout`.
///
/// Note on intentional behavior difference from upstream `mermaid-rs-renderer`:
/// In `mermaid-rs-renderer`, a subgraph with zero internal edges places all its
/// member nodes in a single rank (`rank 0`), which `assign_positions` lays out
/// along the cross-axis of `sub.direction`. Consequently, when a user writes
/// `direction LR` / `direction RL` inside an edgeless layer subgraph of a
/// `flowchart TB` / `BT` diagram (intending the sibling cards to be arranged
/// horizontally), `mermaid-rs-renderer` would otherwise lay out `rank 0` along
/// the vertical cross-axis. Likewise, `direction TB` / `BT` inside an edgeless
/// subgraph of a `flowchart LR` / `RL` diagram would be laid out horizontally.
/// Clearing `sub.direction` for edgeless subgraphs whose explicit direction is
/// orthogonal to `graph.direction` aligns `rank 0`'s cross-axis with the user's
/// requested direction.
fn normalize_flowchart_subgraph_directions(graph: &mut mermaid_rs_renderer::Graph) {
    if graph.kind != mermaid_rs_renderer::DiagramKind::Flowchart {
        return;
    }
    let is_vertical_main = matches!(
        graph.direction,
        mermaid_rs_renderer::Direction::TopDown | mermaid_rs_renderer::Direction::BottomTop
    );
    for sub in &mut graph.subgraphs {
        if sub.nodes.len() <= 1 {
            continue;
        }
        let is_orthogonal_override = if is_vertical_main {
            matches!(
                sub.direction,
                Some(
                    mermaid_rs_renderer::Direction::LeftRight
                        | mermaid_rs_renderer::Direction::RightLeft
                )
            )
        } else {
            matches!(
                sub.direction,
                Some(
                    mermaid_rs_renderer::Direction::TopDown
                        | mermaid_rs_renderer::Direction::BottomTop
                )
            )
        };
        if is_orthogonal_override {
            let member_set: std::collections::HashSet<&str> =
                sub.nodes.iter().map(String::as_str).collect();
            let has_internal_edge = graph
                .edges
                .iter()
                .any(|e| member_set.contains(e.from.as_str()) && member_set.contains(e.to.as_str()));
            if !has_internal_edge {
                sub.direction = None;
            }
        }
    }
}

/// Post-processes Flowchart layouts containing subgraphs to fix three upstream
/// `mermaid-rs-renderer` issues:
/// 1. Unwraps subgraph header titles that wrapped prematurely even though the
///    subgraph box is wide enough for a single-line header.
/// 2. Centers and normalizes rank spacing for top-level subgraphs when all visible
///    nodes belong to subgraphs and cross-subgraph edges are subgraph-anchored.
/// 3. Reroutes subgraph-to-subgraph edges with clean orthogonal paths so edges never
///    detour through their own subgraph header/corners or cut through intermediate
///    subgraphs or free nodes.
fn refine_flowchart_subgraph_layout(
    graph: &mermaid_rs_renderer::Graph,
    layout: &mut mermaid_rs_renderer::Layout,
    theme: &mermaid_rs_renderer::Theme,
    config: &mermaid_rs_renderer::LayoutConfig,
) {
    if graph.kind != mermaid_rs_renderer::DiagramKind::Flowchart || layout.subgraphs.is_empty() {
        return;
    }
    let rcfg = FlowchartRefineConfig::default();

    // 1. Unwrap prematurely wrapped subgraph header labels when single-line fits inside the box.
    for sub_idx in 0..layout.subgraphs.len() {
        let (old_y, sub_x, sub_w, dh) = {
            let sub = &mut layout.subgraphs[sub_idx];
            let trimmed = sub.label.trim();
            if sub.label_block.lines.len() > 1
                && !trimmed.is_empty()
                && !trimmed.contains('\n')
                && !trimmed.to_ascii_lowercase().contains("<br")
            {
                let single_w = estimate_single_line_width(trimmed, theme.font_size);
                if single_w <= sub.width - rcfg.header_unwrap_padding {
                    let new_h = theme.font_size * config.label_line_height;
                    let dh = (sub.label_block.height - new_h).max(0.0);
                    let old_y = sub.y;
                    sub.label_block.lines = vec![trimmed.to_string()];
                    sub.label_block.width = single_w;
                    sub.label_block.height = new_h;
                    if dh > 0.0 {
                        sub.y += dh;
                        sub.height = (sub.height - dh).max(new_h + rcfg.header_min_box_extra_h);
                    }
                    (old_y, sub.x, sub.width, dh)
                } else {
                    (0.0, 0.0, 0.0, 0.0)
                }
            } else {
                (0.0, 0.0, 0.0, 0.0)
            }
        };
        if dh > 0.0 {
            let new_y = old_y + dh;
            for edge in &mut layout.edges {
                if let Some(first) = edge.points.first_mut() {
                    if (first.1 - old_y).abs() <= 2.5
                        && first.0 >= sub_x - 2.0
                        && first.0 <= sub_x + sub_w + 2.0
                    {
                        first.1 = new_y;
                    }
                }
                if let Some(last) = edge.points.last_mut() {
                    if (last.1 - old_y).abs() <= 2.5
                        && last.0 >= sub_x - 2.0
                        && last.0 <= sub_x + sub_w + 2.0
                    {
                        last.1 = new_y;
                    }
                }
            }
        }
    }

    // 2. Map anchor nodes to layout.subgraphs indices using upstream `node.anchor_subgraph`.
    let sub_count = layout.subgraphs.len();
    let mut node_id_to_subgraph: HashMap<String, usize> = HashMap::new();
    let mut sub_to_anchor_ids: Vec<Vec<String>> = vec![Vec::new(); sub_count];

    for (node_id, node) in &layout.nodes {
        if let Some(l_idx) = node.anchor_subgraph {
            if l_idx < sub_count {
                node_id_to_subgraph.insert(node_id.clone(), l_idx);
                if !sub_to_anchor_ids[l_idx].contains(node_id) {
                    sub_to_anchor_ids[l_idx].push(node_id.clone());
                }
            }
        }
    }

    let has_subgraph_to_subgraph_edges = layout.edges.iter().any(|e| {
        match (
            node_id_to_subgraph.get(&e.from),
            node_id_to_subgraph.get(&e.to),
        ) {
            (Some(a), Some(b)) => a != b,
            _ => false,
        }
    });

    if !has_subgraph_to_subgraph_edges {
        return;
    }

    // 3. Identify top-level subgraphs, nested subgraphs, and ancestor relationships.
    let sub_member_sets: Vec<std::collections::HashSet<String>> = layout
        .subgraphs
        .iter()
        .map(|s| s.nodes.iter().cloned().collect())
        .collect();

    let mut parent_sub: Vec<Option<usize>> = vec![None; sub_count];
    let mut nested_children: Vec<Vec<usize>> = vec![Vec::new(); sub_count];
    let mut ancestors: Vec<std::collections::HashSet<usize>> =
        vec![std::collections::HashSet::new(); sub_count];

    for i in 0..sub_count {
        if sub_member_sets[i].is_empty() {
            continue;
        }
        // layout.subgraphs is ordered from largest area to smallest area;
        // find the smallest ancestor j that strictly contains all nodes of i.
        let mut best_parent: Option<usize> = None;
        for j in 0..sub_count {
            if i == j || sub_member_sets[j].len() < sub_member_sets[i].len() {
                continue;
            }
            if sub_member_sets[i].is_subset(&sub_member_sets[j]) {
                if sub_member_sets[j].len() > sub_member_sets[i].len() || j < i {
                    match best_parent {
                        None => best_parent = Some(j),
                        Some(prev) => {
                            if sub_member_sets[j].len() < sub_member_sets[prev].len() {
                                best_parent = Some(j);
                            }
                        }
                    }
                }
            }
        }
        parent_sub[i] = best_parent;
    }
    for i in 0..sub_count {
        let mut curr = parent_sub[i];
        while let Some(p) = curr {
            nested_children[p].push(i);
            ancestors[i].insert(p);
            curr = parent_sub[p];
        }
    }

    let top_level_subs: Vec<usize> = (0..sub_count).filter(|&i| parent_sub[i].is_none()).collect();
    let mut node_to_top_sub: HashMap<String, usize> = HashMap::new();
    for &top_idx in &top_level_subs {
        for member_id in &layout.subgraphs[top_idx].nodes {
            node_to_top_sub.insert(member_id.clone(), top_idx);
        }
    }

    // Safety guard for Step 4 (top-level subgraph rank re-centering & gap normalization):
    // Only move top-level subgraphs when:
    // (a) Every visible non-anchor node belongs to a top-level subgraph (no free nodes that
    //     could be overlapped by shifted subgraphs), AND
    // (b) Every cross-subgraph edge is a subgraph-to-subgraph edge (no node-to-node or
    //     node-to-subgraph cross-subgraph edges whose endpoints would detach when subgraphs move).
    let has_free_visible_nodes = layout.nodes.iter().any(|(id, node)| {
        !node.hidden && node.anchor_subgraph.is_none() && !node_to_top_sub.contains_key(id)
    });
    let has_unanchored_cross_subgraph_edges = layout.edges.iter().any(|e| {
        let from_sub_anchor = node_id_to_subgraph.get(&e.from).copied();
        let to_sub_anchor = node_id_to_subgraph.get(&e.to).copied();
        if from_sub_anchor.is_some() && to_sub_anchor.is_some() {
            return false;
        }
        let from_top = from_sub_anchor
            .map(|mut s| {
                while let Some(p) = parent_sub[s] {
                    s = p;
                }
                s
            })
            .or_else(|| node_to_top_sub.get(&e.from).copied());
        let to_top = to_sub_anchor
            .map(|mut s| {
                while let Some(p) = parent_sub[s] {
                    s = p;
                }
                s
            })
            .or_else(|| node_to_top_sub.get(&e.to).copied());
        from_top != to_top
    });

    let has_nested_subgraphs = parent_sub.iter().any(|p| p.is_some());
    let can_recenter_top_level_subgraphs =
        !has_free_visible_nodes && !has_unanchored_cross_subgraph_edges && !has_nested_subgraphs;

    let is_vertical = matches!(
        graph.direction,
        mermaid_rs_renderer::Direction::TopDown | mermaid_rs_renderer::Direction::BottomTop
    );

    // Helper: compute minimum main-axis gap between two adjacent ranks so edge labels
    // between those ranks fit comfortably without overlapping subgraph borders or each other.
    let compute_required_rank_gap =
        |prev_rank: &[usize], curr_rank: &[usize], edges: &[mermaid_rs_renderer::EdgeLayout]| -> f32 {
            let mut gap = rcfg.min_main_gap;
            let mut pair_label_spans: HashMap<(usize, usize), Vec<f32>> = HashMap::new();
            let mut pair_edge_counts: HashMap<(usize, usize), usize> = HashMap::new();
            for e in edges {
                let (Some(&fs), Some(&ts)) = (
                    node_id_to_subgraph.get(&e.from),
                    node_id_to_subgraph.get(&e.to),
                ) else {
                    continue;
                };
                let connects = (prev_rank.contains(&fs) && curr_rank.contains(&ts))
                    || (prev_rank.contains(&ts) && curr_rank.contains(&fs));
                if !connects {
                    continue;
                }
                let key = (fs.min(ts), fs.max(ts));
                *pair_edge_counts.entry(key).or_insert(0) += 1;
                if let Some(ref lbl) = e.label {
                    let main_span = if is_vertical { lbl.height } else { lbl.width };
                    pair_label_spans.entry(key).or_default().push(main_span);
                }
            }
            for (key, spans) in pair_label_spans {
                let total_edges = pair_edge_counts.get(&key).copied().unwrap_or(spans.len());
                let max_span = spans.iter().copied().fold(0.0f32, f32::max);
                let needed = if total_edges >= 3 {
                    let step = if is_vertical {
                        max_span + 8.0
                    } else {
                        max_span + 12.0
                    };
                    step * (total_edges as f32 - 1.0) + max_span + 24.0
                } else {
                    max_span + 28.0
                };
                gap = gap.max(needed);
            }
            gap
        };

    let compute_required_cross_gap =
        |sub_a: usize, sub_b: usize, edges: &[mermaid_rs_renderer::EdgeLayout]| -> f32 {
            let mut gap = rcfg.min_cross_gap;
            for e in edges {
                let (Some(&fs), Some(&ts)) = (
                    node_id_to_subgraph.get(&e.from),
                    node_id_to_subgraph.get(&e.to),
                ) else {
                    continue;
                };
                if (fs == sub_a && ts == sub_b) || (fs == sub_b && ts == sub_a) {
                    if let Some(ref lbl) = e.label {
                        let cross_span = if is_vertical { lbl.width } else { lbl.height };
                        gap = gap.max(cross_span + 28.0);
                    }
                }
            }
            gap
        };

    // 4. Group top-level subgraphs into ranks and center-align them along the main axis.
    if can_recenter_top_level_subgraphs && is_vertical && !top_level_subs.is_empty() {
        let mut sorted_top = top_level_subs.clone();
        sorted_top.sort_by(|&a, &b| {
            layout.subgraphs[a]
                .y
                .partial_cmp(&layout.subgraphs[b].y)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        let mut rows: Vec<Vec<usize>> = Vec::new();
        for sub_idx in sorted_top {
            let sub = &layout.subgraphs[sub_idx];
            let placed = if let Some(last_row) = rows.last_mut() {
                let ref_sub = &layout.subgraphs[last_row[0]];
                let overlap_top = sub.y.max(ref_sub.y);
                let overlap_bottom = (sub.y + sub.height).min(ref_sub.y + ref_sub.height);
                let min_h = sub.height.min(ref_sub.height).max(1.0);
                if overlap_bottom - overlap_top > min_h * 0.25 {
                    last_row.push(sub_idx);
                    true
                } else {
                    false
                }
            } else {
                false
            };
            if !placed {
                rows.push(vec![sub_idx]);
            }
        }

        let mut max_row_width = 0.0f32;
        for row in &mut rows {
            row.sort_by(|&a, &b| {
                layout.subgraphs[a]
                    .x
                    .partial_cmp(&layout.subgraphs[b].x)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            for idx in 1..row.len() {
                let req_col_gap =
                    compute_required_cross_gap(row[idx - 1], row[idx], &layout.edges);
                let prev = &layout.subgraphs[row[idx - 1]];
                let prev_right = prev.x + prev.width;
                let curr_x = layout.subgraphs[row[idx]].x;
                if curr_x - prev_right < req_col_gap {
                    let dx = (prev_right + req_col_gap) - curr_x;
                    shift_subgraph_contents(
                        row[idx],
                        dx,
                        0.0,
                        layout,
                        &sub_member_sets,
                        &nested_children,
                        &sub_to_anchor_ids,
                    );
                }
            }
            let row_left = row
                .iter()
                .map(|&i| layout.subgraphs[i].x)
                .fold(f32::INFINITY, f32::min);
            let row_right = row
                .iter()
                .map(|&i| layout.subgraphs[i].x + layout.subgraphs[i].width)
                .fold(f32::NEG_INFINITY, f32::max);
            max_row_width = max_row_width.max(row_right - row_left);
        }

        let target_center_x = rcfg.canvas_start_offset + max_row_width * 0.5;
        let mut prev_row_bottom: Option<f32> = None;

        for (row_idx, row) in rows.iter().enumerate() {
            let row_left = row
                .iter()
                .map(|&i| layout.subgraphs[i].x)
                .fold(f32::INFINITY, f32::min);
            let row_right = row
                .iter()
                .map(|&i| layout.subgraphs[i].x + layout.subgraphs[i].width)
                .fold(f32::NEG_INFINITY, f32::max);
            let row_center_x = (row_left + row_right) * 0.5;
            let dx = target_center_x - row_center_x;

            let row_top = row
                .iter()
                .map(|&i| layout.subgraphs[i].y)
                .fold(f32::INFINITY, f32::min);
            let dy = if let Some(prev_bottom) = prev_row_bottom {
                let req_row_gap =
                    compute_required_rank_gap(&rows[row_idx - 1], row, &layout.edges);
                let current_gap = row_top - prev_bottom;
                if !(req_row_gap..=req_row_gap + rcfg.main_gap_tolerance).contains(&current_gap) {
                    (prev_bottom + req_row_gap) - row_top
                } else {
                    0.0
                }
            } else {
                0.0
            };

            let target_row_top = row_top + dy;
            for &sub_idx in row {
                let sub_dy = target_row_top - layout.subgraphs[sub_idx].y;
                shift_subgraph_contents(
                    sub_idx,
                    dx,
                    sub_dy,
                    layout,
                    &sub_member_sets,
                    &nested_children,
                    &sub_to_anchor_ids,
                );
            }

            let new_row_bottom = row
                .iter()
                .map(|&i| layout.subgraphs[i].y + layout.subgraphs[i].height)
                .fold(f32::NEG_INFINITY, f32::max);
            prev_row_bottom = Some(new_row_bottom);
        }
    } else if can_recenter_top_level_subgraphs && !is_vertical && !top_level_subs.is_empty() {
        let mut sorted_top = top_level_subs.clone();
        sorted_top.sort_by(|&a, &b| {
            layout.subgraphs[a]
                .x
                .partial_cmp(&layout.subgraphs[b].x)
                .unwrap_or(std::cmp::Ordering::Equal)
        });

        let mut cols: Vec<Vec<usize>> = Vec::new();
        for sub_idx in sorted_top {
            let sub = &layout.subgraphs[sub_idx];
            let placed = if let Some(last_col) = cols.last_mut() {
                let ref_sub = &layout.subgraphs[last_col[0]];
                let overlap_left = sub.x.max(ref_sub.x);
                let overlap_right = (sub.x + sub.width).min(ref_sub.x + ref_sub.width);
                let min_w = sub.width.min(ref_sub.width).max(1.0);
                if overlap_right - overlap_left > min_w * 0.25 {
                    last_col.push(sub_idx);
                    true
                } else {
                    false
                }
            } else {
                false
            };
            if !placed {
                cols.push(vec![sub_idx]);
            }
        }

        let mut max_col_height = 0.0f32;
        for col in &mut cols {
            col.sort_by(|&a, &b| {
                layout.subgraphs[a]
                    .y
                    .partial_cmp(&layout.subgraphs[b].y)
                    .unwrap_or(std::cmp::Ordering::Equal)
            });
            for idx in 1..col.len() {
                let req_row_gap =
                    compute_required_cross_gap(col[idx - 1], col[idx], &layout.edges);
                let prev = &layout.subgraphs[col[idx - 1]];
                let prev_bottom = prev.y + prev.height;
                let curr_y = layout.subgraphs[col[idx]].y;
                if curr_y - prev_bottom < req_row_gap {
                    let dy = (prev_bottom + req_row_gap) - curr_y;
                    shift_subgraph_contents(
                        col[idx],
                        0.0,
                        dy,
                        layout,
                        &sub_member_sets,
                        &nested_children,
                        &sub_to_anchor_ids,
                    );
                }
            }
            let col_top = col
                .iter()
                .map(|&i| layout.subgraphs[i].y)
                .fold(f32::INFINITY, f32::min);
            let col_bottom = col
                .iter()
                .map(|&i| layout.subgraphs[i].y + layout.subgraphs[i].height)
                .fold(f32::NEG_INFINITY, f32::max);
            max_col_height = max_col_height.max(col_bottom - col_top);
        }

        let target_center_y = rcfg.canvas_start_offset + max_col_height * 0.5;
        let mut prev_col_right: Option<f32> = None;

        for (col_idx, col) in cols.iter().enumerate() {
            let col_top = col
                .iter()
                .map(|&i| layout.subgraphs[i].y)
                .fold(f32::INFINITY, f32::min);
            let col_bottom = col
                .iter()
                .map(|&i| layout.subgraphs[i].y + layout.subgraphs[i].height)
                .fold(f32::NEG_INFINITY, f32::max);
            let col_center_y = (col_top + col_bottom) * 0.5;
            let dy = target_center_y - col_center_y;

            let col_left = col
                .iter()
                .map(|&i| layout.subgraphs[i].x)
                .fold(f32::INFINITY, f32::min);
            let dx = if let Some(prev_right) = prev_col_right {
                let req_col_gap =
                    compute_required_rank_gap(&cols[col_idx - 1], col, &layout.edges);
                let current_gap = col_left - prev_right;
                if !(req_col_gap..=req_col_gap + rcfg.main_gap_tolerance).contains(&current_gap) {
                    (prev_right + req_col_gap) - col_left
                } else {
                    0.0
                }
            } else {
                0.0
            };

            let target_col_left = col_left + dx;
            for &sub_idx in col {
                let sub_dx = target_col_left - layout.subgraphs[sub_idx].x;
                shift_subgraph_contents(
                    sub_idx,
                    sub_dx,
                    dy,
                    layout,
                    &sub_member_sets,
                    &nested_children,
                    &sub_to_anchor_ids,
                );
            }

            let new_col_right = col
                .iter()
                .map(|&i| layout.subgraphs[i].x + layout.subgraphs[i].width)
                .fold(f32::NEG_INFINITY, f32::max);
            prev_col_right = Some(new_col_right);
        }
    }

    // Keep hidden subgraph anchor nodes centered on their subgraph so bounds remain accurate.
    for (sub_idx, anchor_ids) in sub_to_anchor_ids.iter().enumerate() {
        let sub = &layout.subgraphs[sub_idx];
        let cx = sub.x + sub.width * 0.5;
        let cy = sub.y + sub.height * 0.5;
        for anchor_id in anchor_ids {
            if let Some(node) = layout.nodes.get_mut(anchor_id) {
                if node.anchor_subgraph.is_some() || node.hidden {
                    node.x = cx - node.width * 0.5;
                    node.y = cy - node.height * 0.5;
                }
            }
        }
    }

    // 5. Reroute subgraph-to-subgraph edges with clean orthogonal paths.
    // Count parallel subgraph-to-subgraph edges per unordered pair so straight segments can be offset.
    let mut pair_counts: HashMap<(usize, usize), usize> = HashMap::new();
    for edge in &layout.edges {
        if let (Some(&fs), Some(&ts)) = (
            node_id_to_subgraph.get(&edge.from),
            node_id_to_subgraph.get(&edge.to),
        ) {
            if fs != ts && !ancestors[fs].contains(&ts) && !ancestors[ts].contains(&fs) {
                let key = (fs.min(ts), fs.max(ts));
                *pair_counts.entry(key).or_insert(0) += 1;
            }
        }
    }
    let mut pair_seen: HashMap<(usize, usize), usize> = HashMap::new();

    // Track per-scope detour lane counts (keyed by common parent subgraph `Option<usize>`).
    let mut left_detours: HashMap<Option<usize>, usize> = HashMap::new();
    let mut right_detours: HashMap<Option<usize>, usize> = HashMap::new();
    let mut top_detours: HashMap<Option<usize>, usize> = HashMap::new();
    let mut bottom_detours: HashMap<Option<usize>, usize> = HashMap::new();

    let is_related_subgraph = |idx: usize, from_sub: usize, to_sub: usize| -> bool {
        idx == from_sub
            || idx == to_sub
            || ancestors[from_sub].contains(&idx)
            || ancestors[to_sub].contains(&idx)
            || ancestors[idx].contains(&from_sub)
            || ancestors[idx].contains(&to_sub)
    };

    let is_node_in_sub_or_descendants = |node_id: &str, sub_idx: usize| -> bool {
        if sub_member_sets[sub_idx].contains(node_id) {
            return true;
        }
        nested_children[sub_idx]
            .iter()
            .any(|&child_idx| sub_member_sets[child_idx].contains(node_id))
    };

    // Route deeper nested subgraph-to-subgraph edges before outer/top-level edges so any
    // ancestor box expansion happens before edges attached to that ancestor are routed.
    let mut edge_order: Vec<usize> = (0..layout.edges.len()).collect();
    edge_order.sort_by(|&a, &b| {
        let depth_of = |e_idx: usize| -> usize {
            let e = &layout.edges[e_idx];
            match (
                node_id_to_subgraph.get(&e.from),
                node_id_to_subgraph.get(&e.to),
            ) {
                (Some(&fs), Some(&ts)) => ancestors[fs].len() + ancestors[ts].len(),
                _ => 0,
            }
        };
        depth_of(b).cmp(&depth_of(a)).then_with(|| a.cmp(&b))
    });

    for edge_idx in edge_order {
        let from_id = layout.edges[edge_idx].from.clone();
        let to_id = layout.edges[edge_idx].to.clone();
        let (Some(&from_sub), Some(&to_sub)) = (
            node_id_to_subgraph.get(&from_id),
            node_id_to_subgraph.get(&to_id),
        ) else {
            continue;
        };
        if from_sub == to_sub
            || ancestors[from_sub].contains(&to_sub)
            || ancestors[to_sub].contains(&from_sub)
        {
            continue;
        }

        let pair_key = (from_sub.min(to_sub), from_sub.max(to_sub));
        let pair_total = pair_counts.get(&pair_key).copied().unwrap_or(1);
        let pair_ord = {
            let entry = pair_seen.entry(pair_key).or_insert(0);
            let ord = *entry;
            *entry += 1;
            ord
        };
        let parallel_offset =
            (pair_ord as f32 - (pair_total as f32 - 1.0) * 0.5) * rcfg.parallel_edge_spacing;

        // Determine common scope (siblings sharing the same parent subgraph, or top-level).
        let common_parent = if parent_sub[from_sub] == parent_sub[to_sub] {
            parent_sub[from_sub]
        } else {
            None
        };
        let mut scope_min_x = f32::INFINITY;
        let mut scope_max_x = f32::NEG_INFINITY;
        let mut scope_min_y = f32::INFINITY;
        let mut scope_max_y = f32::NEG_INFINITY;
        for (idx, s) in layout.subgraphs.iter().enumerate() {
            if parent_sub[idx] == common_parent
                || idx == from_sub
                || idx == to_sub
            {
                scope_min_x = scope_min_x.min(s.x);
                scope_max_x = scope_max_x.max(s.x + s.width);
                scope_min_y = scope_min_y.min(s.y);
                scope_max_y = scope_max_y.max(s.y + s.height);
            }
        }
        for (id, node) in &layout.nodes {
            if node.hidden || node.anchor_subgraph.is_some() {
                continue;
            }
            let in_scope = match common_parent {
                Some(p_idx) => is_node_in_sub_or_descendants(id, p_idx),
                None => !node_to_top_sub.contains_key(id),
            };
            if in_scope {
                scope_min_x = scope_min_x.min(node.x);
                scope_max_x = scope_max_x.max(node.x + node.width);
                scope_min_y = scope_min_y.min(node.y);
                scope_max_y = scope_max_y.max(node.y + node.height);
            }
        }
        let scope_center_x = (scope_min_x + scope_max_x) * 0.5;
        let scope_center_y = (scope_min_y + scope_max_y) * 0.5;

        let is_unrelated_visible_node = |id: &str, n: &mermaid_rs_renderer::NodeLayout| -> bool {
            !n.hidden
                && n.anchor_subgraph.is_none()
                && !is_node_in_sub_or_descendants(id, from_sub)
                && !is_node_in_sub_or_descendants(id, to_sub)
        };

        let (fx, fy, fw, fh) = {
            let s = &layout.subgraphs[from_sub];
            (s.x, s.y, s.width, s.height)
        };
        let (tx, ty, tw, th) = {
            let s = &layout.subgraphs[to_sub];
            (s.x, s.y, s.width, s.height)
        };

        let f_right = fx + fw;
        let f_bottom = fy + fh;
        let f_cx = fx + fw * 0.5;
        let f_cy = fy + fh * 0.5;

        let t_right = tx + tw;
        let t_bottom = ty + th;
        let t_cx = tx + tw * 0.5;
        let t_cy = ty + th * 0.5;

        let mut detour_dir: Option<f32> = None;
        let new_points = if is_vertical {
            let downward = f_bottom <= ty + 2.0;
            let upward = fy >= t_bottom - 2.0;

            if downward || upward {
                let (span_top, span_bottom) = if downward {
                    (f_bottom, ty)
                } else {
                    (t_bottom, fy)
                };
                let horiz_min = fx.min(tx);
                let horiz_max = f_right.max(t_right);

                // Check if any unrelated subgraph or unrelated visible node lies vertically between from and to
                let has_blocking_subgraph = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                    if is_related_subgraph(idx, from_sub, to_sub) {
                        return false;
                    }
                    let s_bottom = s.y + s.height;
                    let vert_between = s.y < span_bottom - 4.0 && s_bottom > span_top + 4.0;
                    vert_between && s.x < horiz_max && (s.x + s.width) > horiz_min
                });
                let has_blocking_free_node = layout.nodes.iter().any(|(id, n)| {
                    if !is_unrelated_visible_node(id, n) {
                        return false;
                    }
                    let n_bottom = n.y + n.height;
                    let vert_between = n.y < span_bottom - 2.0 && n_bottom > span_top + 2.0;
                    vert_between && n.x < horiz_max && (n.x + n.width) > horiz_min
                });

                if !has_blocking_subgraph && !has_blocking_free_node {
                    let pad = rcfg.port_corner_pad;
                    let overlap_left = (fx + pad).max(tx + pad);
                    let overlap_right = (f_right - pad).min(t_right - pad);
                    let start_y = if downward { f_bottom } else { fy };
                    let end_y = if downward { ty } else { t_bottom };

                    if overlap_left <= overlap_right {
                        let x = ((overlap_left + overlap_right) * 0.5 + parallel_offset)
                            .clamp(overlap_left, overlap_right);
                        vec![(x, start_y), (x, end_y)]
                    } else {
                        let mid_y = (start_y + end_y) * 0.5;
                        vec![(f_cx, start_y), (f_cx, mid_y), (t_cx, mid_y), (t_cx, end_y)]
                    }
                } else {
                    // Long-span edge skipping one or more intermediate ranks:
                    // Route cleanly around the left or right channel of the current scope.
                    let go_left = if (t_cx - scope_center_x).abs() > 10.0 {
                        t_cx < scope_center_x
                    } else {
                        f_cx <= scope_center_x
                    };
                    detour_dir = Some(if go_left { -1.0 } else { 1.0 });

                    let lane_idx = if go_left {
                        let entry = left_detours.entry(common_parent).or_insert(0);
                        let i = *entry;
                        *entry += 1;
                        i
                    } else {
                        let entry = right_detours.entry(common_parent).or_insert(0);
                        let i = *entry;
                        *entry += 1;
                        i
                    };
                    let lane_offset =
                        rcfg.detour_base_offset + (lane_idx as f32) * rcfg.detour_lane_step;
                    let lane_x = if go_left {
                        scope_min_x - lane_offset
                    } else {
                        scope_max_x + lane_offset
                    };

                    // Check if source or target side is obstructed by another subgraph or node in the same rank
                    let from_side_obstructed = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                        if is_related_subgraph(idx, from_sub, to_sub) {
                            return false;
                        }
                        let vert_overlap = s.y < f_bottom && (s.y + s.height) > fy;
                        if !vert_overlap {
                            return false;
                        }
                        if go_left {
                            s.x < fx
                        } else {
                            (s.x + s.width) > f_right
                        }
                    }) || layout.nodes.iter().any(|(id, n)| {
                        if !is_unrelated_visible_node(id, n) {
                            return false;
                        }
                        let vert_overlap = n.y < f_bottom && (n.y + n.height) > fy;
                        if !vert_overlap {
                            return false;
                        }
                        if go_left {
                            n.x < fx
                        } else {
                            (n.x + n.width) > f_right
                        }
                    });
                    let to_side_obstructed = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                        if is_related_subgraph(idx, from_sub, to_sub) {
                            return false;
                        }
                        let vert_overlap = s.y < t_bottom && (s.y + s.height) > ty;
                        if !vert_overlap {
                            return false;
                        }
                        if go_left {
                            s.x < tx
                        } else {
                            (s.x + s.width) > t_right
                        }
                    }) || layout.nodes.iter().any(|(id, n)| {
                        if !is_unrelated_visible_node(id, n) {
                            return false;
                        }
                        let vert_overlap = n.y < t_bottom && (n.y + n.height) > ty;
                        if !vert_overlap {
                            return false;
                        }
                        if go_left {
                            n.x < tx
                        } else {
                            (n.x + n.width) > t_right
                        }
                    });

                    let mut pts = Vec::with_capacity(6);
                    if !from_side_obstructed {
                        let start_x = if go_left { fx } else { f_right };
                        pts.push((start_x, f_cy));
                        pts.push((lane_x, f_cy));
                    } else {
                        let start_y = if downward { f_bottom } else { fy };
                        let depart_y = if downward {
                            f_bottom + rcfg.obstructed_approach_gap
                        } else {
                            fy - rcfg.obstructed_approach_gap
                        };
                        pts.push((f_cx, start_y));
                        pts.push((f_cx, depart_y));
                        pts.push((lane_x, depart_y));
                    }

                    if !to_side_obstructed {
                        let end_x = if go_left { tx } else { t_right };
                        pts.push((lane_x, t_cy));
                        pts.push((end_x, t_cy));
                    } else {
                        let approach_y = if downward {
                            ty - rcfg.obstructed_approach_gap
                        } else {
                            t_bottom + rcfg.obstructed_approach_gap
                        };
                        let end_y = if downward { ty } else { t_bottom };
                        pts.push((lane_x, approach_y));
                        pts.push((t_cx, approach_y));
                        pts.push((t_cx, end_y));
                    }
                    pts
                }
            } else {
                // Same rank (side-by-side) subgraphs
                let overlap_top = (fy + 16.0).max(ty + 16.0);
                let overlap_bottom = (f_bottom - 16.0).min(t_bottom - 16.0);
                let y = if overlap_top <= overlap_bottom {
                    ((overlap_top + overlap_bottom) * 0.5 + parallel_offset)
                        .clamp(overlap_top, overlap_bottom)
                } else {
                    (f_cy + t_cy) * 0.5
                };
                if f_right <= tx + 2.0 {
                    vec![(f_right, y), (tx, y)]
                } else if t_right <= fx + 2.0 {
                    vec![(fx, y), (t_right, y)]
                } else {
                    vec![(f_cx, f_bottom), (t_cx, ty)]
                }
            }
        } else {
            // Horizontal flow (LR / RL)
            let rightward = f_right <= tx + 2.0;
            let leftward = fx >= t_right - 2.0;

            if rightward || leftward {
                let (span_left, span_right) = if rightward {
                    (f_right, tx)
                } else {
                    (t_right, fx)
                };
                let vert_min = fy.min(ty);
                let vert_max = f_bottom.max(t_bottom);

                let has_blocking_subgraph = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                    if is_related_subgraph(idx, from_sub, to_sub) {
                        return false;
                    }
                    let s_right = s.x + s.width;
                    let horiz_between = s.x < span_right - 4.0 && s_right > span_left + 4.0;
                    horiz_between && s.y < vert_max && (s.y + s.height) > vert_min
                });
                let has_blocking_free_node = layout.nodes.iter().any(|(id, n)| {
                    if !is_unrelated_visible_node(id, n) {
                        return false;
                    }
                    let n_right = n.x + n.width;
                    let horiz_between = n.x < span_right - 2.0 && n_right > span_left + 2.0;
                    horiz_between && n.y < vert_max && (n.y + n.height) > vert_min
                });

                if !has_blocking_subgraph && !has_blocking_free_node {
                    let pad = rcfg.port_corner_pad;
                    let overlap_top = (fy + pad).max(ty + pad);
                    let overlap_bottom = (f_bottom - pad).min(t_bottom - pad);
                    let start_x = if rightward { f_right } else { fx };
                    let end_x = if rightward { tx } else { t_right };

                    if overlap_top <= overlap_bottom {
                        let y = ((overlap_top + overlap_bottom) * 0.5 + parallel_offset)
                            .clamp(overlap_top, overlap_bottom);
                        vec![(start_x, y), (end_x, y)]
                    } else {
                        let mid_x = (start_x + end_x) * 0.5;
                        vec![(start_x, f_cy), (mid_x, f_cy), (mid_x, t_cy), (end_x, t_cy)]
                    }
                } else {
                    let go_top = if (t_cy - scope_center_y).abs() > 10.0 {
                        t_cy < scope_center_y
                    } else {
                        f_cy <= scope_center_y
                    };
                    detour_dir = Some(if go_top { -1.0 } else { 1.0 });
                    let lane_idx = if go_top {
                        let entry = top_detours.entry(common_parent).or_insert(0);
                        let i = *entry;
                        *entry += 1;
                        i
                    } else {
                        let entry = bottom_detours.entry(common_parent).or_insert(0);
                        let i = *entry;
                        *entry += 1;
                        i
                    };
                    let lane_offset =
                        rcfg.detour_base_offset + (lane_idx as f32) * rcfg.detour_lane_step;
                    let lane_y = if go_top {
                        scope_min_y - lane_offset
                    } else {
                        scope_max_y + lane_offset
                    };

                    let from_side_obstructed = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                        if is_related_subgraph(idx, from_sub, to_sub) {
                            return false;
                        }
                        let horiz_overlap = s.x < f_right && (s.x + s.width) > fx;
                        if !horiz_overlap {
                            return false;
                        }
                        if go_top {
                            s.y < fy
                        } else {
                            (s.y + s.height) > f_bottom
                        }
                    }) || layout.nodes.iter().any(|(id, n)| {
                        if !is_unrelated_visible_node(id, n) {
                            return false;
                        }
                        let horiz_overlap = n.x < f_right && (n.x + n.width) > fx;
                        if !horiz_overlap {
                            return false;
                        }
                        if go_top {
                            n.y < fy
                        } else {
                            (n.y + n.height) > f_bottom
                        }
                    });
                    let to_side_obstructed = layout.subgraphs.iter().enumerate().any(|(idx, s)| {
                        if is_related_subgraph(idx, from_sub, to_sub) {
                            return false;
                        }
                        let horiz_overlap = s.x < t_right && (s.x + s.width) > tx;
                        if !horiz_overlap {
                            return false;
                        }
                        if go_top {
                            s.y < ty
                        } else {
                            (s.y + s.height) > t_bottom
                        }
                    }) || layout.nodes.iter().any(|(id, n)| {
                        if !is_unrelated_visible_node(id, n) {
                            return false;
                        }
                        let horiz_overlap = n.x < t_right && (n.x + n.width) > tx;
                        if !horiz_overlap {
                            return false;
                        }
                        if go_top {
                            n.y < ty
                        } else {
                            (n.y + n.height) > t_bottom
                        }
                    });

                    let mut pts = Vec::with_capacity(6);
                    if !from_side_obstructed {
                        let start_y = if go_top { fy } else { f_bottom };
                        pts.push((f_cx, start_y));
                        pts.push((f_cx, lane_y));
                    } else {
                        let start_x = if rightward { f_right } else { fx };
                        let depart_x = if rightward {
                            f_right + rcfg.obstructed_approach_gap
                        } else {
                            fx - rcfg.obstructed_approach_gap
                        };
                        pts.push((start_x, f_cy));
                        pts.push((depart_x, f_cy));
                        pts.push((depart_x, lane_y));
                    }

                    if !to_side_obstructed {
                        let end_y = if go_top { ty } else { t_bottom };
                        pts.push((t_cx, lane_y));
                        pts.push((t_cx, end_y));
                    } else {
                        let approach_x = if rightward {
                            tx - rcfg.obstructed_approach_gap
                        } else {
                            t_right + rcfg.obstructed_approach_gap
                        };
                        let end_x = if rightward { tx } else { t_right };
                        pts.push((approach_x, lane_y));
                        pts.push((approach_x, t_cy));
                        pts.push((end_x, t_cy));
                    }
                    pts
                }
            } else {
                let overlap_left = (fx + 16.0).max(tx + 16.0);
                let overlap_right = (f_right - 16.0).min(t_right - 16.0);
                let x = if overlap_left <= overlap_right {
                    ((overlap_left + overlap_right) * 0.5 + parallel_offset)
                        .clamp(overlap_left, overlap_right)
                } else {
                    (f_cx + t_cx) * 0.5
                };
                if f_bottom <= ty + 2.0 {
                    vec![(x, f_bottom), (x, ty)]
                } else {
                    vec![(x, fy), (x, t_bottom)]
                }
            }
        };

        let new_label_anchor = layout.edges[edge_idx].label.as_ref().map(|lbl| {
            compute_edge_label_anchor(
                &new_points,
                (lbl.width, lbl.height),
                pair_ord,
                pair_total,
                parallel_offset,
                detour_dir,
            )
        });
        let label_size_opt = layout.edges[edge_idx]
            .label
            .as_ref()
            .map(|lbl| (lbl.width, lbl.height));

        // If this edge is inside a parent subgraph and detours beyond the parent's current box,
        // expand the ancestor subgraph boxes so nested detours and their labels remain inside.
        let mut anc_opt = common_parent;
        while let Some(anc_idx) = anc_opt {
            let anc = &mut layout.subgraphs[anc_idx];
            let pad = 14.0f32;
            let mut include_pt = |px: f32, py: f32| {
                if px - pad < anc.x {
                    let right = anc.x + anc.width;
                    anc.x = px - pad;
                    anc.width = right - anc.x;
                }
                if px + pad > anc.x + anc.width {
                    anc.width = (px + pad) - anc.x;
                }
                if py - pad < anc.y {
                    let bottom = anc.y + anc.height;
                    anc.y = py - pad;
                    anc.height = bottom - anc.y;
                }
                if py + pad > anc.y + anc.height {
                    anc.height = (py + pad) - anc.y;
                }
            };
            for &(px, py) in &new_points {
                include_pt(px, py);
            }
            if let (Some((ax, ay)), Some((lw, lh))) = (new_label_anchor, label_size_opt) {
                include_pt(ax - lw * 0.5, ay - lh * 0.5);
                include_pt(ax + lw * 0.5, ay + lh * 0.5);
            }
            anc_opt = parent_sub[anc_idx];
        }

        let edge = &mut layout.edges[edge_idx];
        edge.points = new_points;
        if edge.label.is_some() {
            edge.label_anchor = new_label_anchor;
        }
        if edge.start_label.is_some() {
            edge.start_label_anchor = edge.points.first().copied();
        }
        if edge.end_label.is_some() {
            edge.end_label_anchor = edge.points.last().copied();
        }
    }

    // Separate any remaining colliding edge labels (e.g. edges from different source subgraphs
    // converging on the same target subgraph within the same rank gap).
    let edge_count = layout.edges.len();
    for _ in 0..8 {
        let mut moved = false;
        for i in 0..edge_count {
            for j in (i + 1)..edge_count {
                let (Some((ax_i, ay_i)), Some(lbl_i), Some((ax_j, ay_j)), Some(lbl_j)) = (
                    layout.edges[i].label_anchor,
                    layout.edges[i].label.as_ref(),
                    layout.edges[j].label_anchor,
                    layout.edges[j].label.as_ref(),
                ) else {
                    continue;
                };
                let req_w = (lbl_i.width + lbl_j.width) * 0.5 + 6.0;
                let req_h = (lbl_i.height + lbl_j.height) * 0.5 + 6.0;
                let dx = (ax_j - ax_i).abs();
                let dy = (ay_j - ay_i).abs();
                if dx < req_w && dy < req_h {
                    moved = true;
                    if is_vertical {
                        let push = (req_w - dx) * 0.5;
                        if ax_i <= ax_j {
                            layout.edges[i].label_anchor = Some((ax_i - push, ay_i));
                            layout.edges[j].label_anchor = Some((ax_j + push, ay_j));
                        } else {
                            layout.edges[i].label_anchor = Some((ax_i + push, ay_i));
                            layout.edges[j].label_anchor = Some((ax_j - push, ay_j));
                        }
                    } else {
                        let push = (req_h - dy) * 0.5;
                        if ay_i <= ay_j {
                            layout.edges[i].label_anchor = Some((ax_i, ay_i - push));
                            layout.edges[j].label_anchor = Some((ax_j, ay_j + push));
                        } else {
                            layout.edges[i].label_anchor = Some((ax_i, ay_i + push));
                            layout.edges[j].label_anchor = Some((ax_j, ay_j - push));
                        }
                    }
                }
            }
        }
        if !moved {
            break;
        }
    }

    // 6. Recompute overall viewBox / canvas bounds so exterior detours and edge labels are never clipped.
    let mut min_x = f32::INFINITY;
    let mut min_y = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut max_y = f32::NEG_INFINITY;

    for sub in &layout.subgraphs {
        min_x = min_x.min(sub.x);
        min_y = min_y.min(sub.y);
        max_x = max_x.max(sub.x + sub.width);
        max_y = max_y.max(sub.y + sub.height);
    }
    for node in layout.nodes.values() {
        if node.hidden || node.anchor_subgraph.is_some() {
            continue;
        }
        min_x = min_x.min(node.x);
        min_y = min_y.min(node.y);
        max_x = max_x.max(node.x + node.width);
        max_y = max_y.max(node.y + node.height);
    }
    for edge in &layout.edges {
        for &(px, py) in &edge.points {
            min_x = min_x.min(px);
            min_y = min_y.min(py);
            max_x = max_x.max(px);
            max_y = max_y.max(py);
        }
        let mut include_label_box = |anchor: Option<(f32, f32)>, size: Option<(f32, f32)>| {
            if let (Some((ax, ay)), Some((w, h))) = (anchor, size) {
                let half_w = w * 0.5 + 8.0;
                let half_h = h * 0.5 + 6.0;
                min_x = min_x.min(ax - half_w);
                max_x = max_x.max(ax + half_w);
                min_y = min_y.min(ay - half_h);
                max_y = max_y.max(ay + half_h);
            }
        };
        include_label_box(
            edge.label_anchor,
            edge.label.as_ref().map(|b| (b.width, b.height)),
        );
        include_label_box(
            edge.start_label_anchor,
            edge.start_label.as_ref().map(|b| (b.width, b.height)),
        );
        include_label_box(
            edge.end_label_anchor,
            edge.end_label.as_ref().map(|b| (b.width, b.height)),
        );
    }

    if min_x.is_finite() && min_y.is_finite() && max_x.is_finite() && max_y.is_finite() {
        let margin = rcfg.canvas_margin;
        let shift_x = if min_x < margin { margin - min_x } else { 0.0 };
        let shift_y = if min_y < margin { margin - min_y } else { 0.0 };

        if shift_x > 0.0 || shift_y > 0.0 {
            for sub in &mut layout.subgraphs {
                sub.x += shift_x;
                sub.y += shift_y;
            }
            for node in layout.nodes.values_mut() {
                node.x += shift_x;
                node.y += shift_y;
            }
            for edge in &mut layout.edges {
                for pt in &mut edge.points {
                    pt.0 += shift_x;
                    pt.1 += shift_y;
                }
                if let Some(ref mut a) = edge.label_anchor {
                    a.0 += shift_x;
                    a.1 += shift_y;
                }
                if let Some(ref mut a) = edge.start_label_anchor {
                    a.0 += shift_x;
                    a.1 += shift_y;
                }
                if let Some(ref mut a) = edge.end_label_anchor {
                    a.0 += shift_x;
                    a.1 += shift_y;
                }
            }
            max_x += shift_x;
            max_y += shift_y;
        }

        layout.width = (max_x + margin).max(1.0);
        layout.height = (max_y + margin).max(1.0);
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
    let layout_cfg = mermaid_rs_renderer::LayoutConfig::default();

    // Parse (strict) -> compute layout -> refine flowchart subgraphs -> render SVG
    let rendered = mermaid_rs_renderer::parse_mermaid_strict(&processed_code).map(|mut parsed| {
        normalize_flowchart_subgraph_directions(&mut parsed.graph);
        let mut layout = mermaid_rs_renderer::compute_layout(&parsed.graph, &theme, &layout_cfg);
        refine_flowchart_subgraph_layout(&parsed.graph, &mut layout, &theme, &layout_cfg);
        mermaid_rs_renderer::render_svg(&layout, &theme, &layout_cfg)
    });

    match rendered {
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
        let processed = preprocess_mermaid_code(code);
        let mut parsed =
            mermaid_rs_renderer::parse_mermaid_strict(&processed).expect("Should parse flowchart");
        normalize_flowchart_subgraph_directions(&mut parsed.graph);
        let theme = build_light_theme();
        let cfg = mermaid_rs_renderer::LayoutConfig::default();
        let mut layout = mermaid_rs_renderer::compute_layout(&parsed.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed.graph, &mut layout, &theme, &cfg);

        // 1. All 5 subgraph headers must be single-line (no forced multi-line wrapping)
        assert_eq!(layout.subgraphs.len(), 5);
        for sub in &layout.subgraphs {
            assert_eq!(
                sub.label_block.lines.len(),
                1,
                "Subgraph '{}' header should not wrap into multiple lines",
                sub.label
            );
        }

        // 2. Top 3 single-subgraph rows (Channels, Application, Intelligence) must have aligned horizontal centers
        let find_sub = |prefix: &str| {
            layout
                .subgraphs
                .iter()
                .find(|s| s.label.starts_with(prefix))
                .expect("Subgraph should exist")
        };
        let s1 = find_sub("1.");
        let s2 = find_sub("2.");
        let s3 = find_sub("3.");
        let s4 = find_sub("4.");
        let s5 = find_sub("5.");

        let c1_x = s1.x + s1.width * 0.5;
        let c2_x = s2.x + s2.width * 0.5;
        let c3_x = s3.x + s3.width * 0.5;
        assert!((c1_x - c2_x).abs() < 1.0, "Row 1 and Row 2 centers must align");
        assert!((c2_x - c3_x).abs() < 1.0, "Row 2 and Row 3 centers must align");

        // Row 4 (Data + Integration) combined center must also align with Row 2 center
        let row4_left = s4.x.min(s5.x);
        let row4_right = (s4.x + s4.width).max(s5.x + s5.width);
        let row4_center = (row4_left + row4_right) * 0.5;
        assert!(
            (row4_center - c2_x).abs() < 1.0,
            "Row 4 combined center ({row4_center}) must align with Row 2 center ({c2_x})"
        );
        assert!(
            (s4.y - s5.y).abs() < 1.0,
            "Side-by-side subgraphs in Row 4 must have aligned top edges"
        );

        // 3. Every edge must attach to its source and target subgraph borders, and
        // long-span skip-rank edges must not pass through Intelligence (s3)'s interior.
        assert_eq!(layout.edges.len(), 6);
        let point_on_sub_border = |pt: (f32, f32), s: &mermaid_rs_renderer::SubgraphLayout| -> bool {
            let on_x = (pt.0 - s.x).abs() <= 1.5 || (pt.0 - (s.x + s.width)).abs() <= 1.5;
            let in_y = pt.1 >= s.y - 1.5 && pt.1 <= s.y + s.height + 1.5;
            let on_y = (pt.1 - s.y).abs() <= 1.5 || (pt.1 - (s.y + s.height)).abs() <= 1.5;
            let in_x = pt.0 >= s.x - 1.5 && pt.0 <= s.x + s.width + 1.5;
            (on_x && in_y) || (on_y && in_x)
        };
        let mut detour_count = 0;
        for edge in &layout.edges {
            let first = *edge.points.first().expect("edge has start");
            let last = *edge.points.last().expect("edge has end");
            assert!(
                layout.subgraphs.iter().any(|s| point_on_sub_border(first, s)),
                "Edge start {:?} must lie on a subgraph border",
                first
            );
            assert!(
                layout.subgraphs.iter().any(|s| point_on_sub_border(last, s)),
                "Edge end {:?} must lie on a subgraph border",
                last
            );
            if edge.points.len() >= 4 {
                detour_count += 1;
                let detour_x = edge.points[1].0;
                assert!(
                    detour_x < s3.x || detour_x > s3.x + s3.width,
                    "Long-span edge detour x={detour_x} must not pass through Intelligence [{}, {}]",
                    s3.x,
                    s3.x + s3.width
                );
            }
        }
        assert_eq!(detour_count, 2, "Both Application->Data and Application->Integration must detour");

        // 4. Full SVG render succeeds and includes all subgraph titles
        let rendered = render_mermaid(code, false);
        assert!(!rendered.is_fallback);
        let svg = String::from_utf8_lossy(&rendered.svg_bytes);
        assert!(svg.contains("1. 渠道与入口层 (Channels &amp; Entry)"));
        assert!(svg.contains("5. 外部生态与基础底座 (Integration &amp; Infra)"));
    }

    #[test]
    fn test_flowchart_mixed_free_nodes_and_cross_subgraph_node_edges() {
        let code = r#"flowchart TB
    Start[Start Node] --> A
    subgraph A["Subgraph A"]
        a1[Node A1] --> a2[Node A2]
    end
    A --> Mid[Free Middle Node]
    Mid --> B
    subgraph B["Subgraph B"]
        b1[Node B1] --> b2[Node B2]
    end
    a2 --> b1
"#;
        let processed = preprocess_mermaid_code(code);
        let mut parsed =
            mermaid_rs_renderer::parse_mermaid_strict(&processed).expect("Should parse");
        normalize_flowchart_subgraph_directions(&mut parsed.graph);
        let theme = build_light_theme();
        let cfg = mermaid_rs_renderer::LayoutConfig::default();
        let mut layout = mermaid_rs_renderer::compute_layout(&parsed.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed.graph, &mut layout, &theme, &cfg);

        // Free node `Mid` must not overlap with Subgraph A or Subgraph B
        let mid = layout.nodes.get("Mid").expect("Mid node exists");
        for sub in &layout.subgraphs {
            let overlap_x = mid.x < sub.x + sub.width && mid.x + mid.width > sub.x;
            let overlap_y = mid.y < sub.y + sub.height && mid.y + mid.height > sub.y;
            assert!(
                !(overlap_x && overlap_y),
                "Free node Mid {:?} must not overlap subgraph '{}' {:?}",
                (mid.x, mid.y, mid.width, mid.height),
                sub.label,
                (sub.x, sub.y, sub.width, sub.height)
            );
        }

        // Cross-subgraph node edge `a2 --> b1` must remain attached to `a2` and `b1`
        let a2 = layout.nodes.get("a2").expect("a2 exists");
        let b1 = layout.nodes.get("b1").expect("b1 exists");
        let edge_a2_b1 = layout
            .edges
            .iter()
            .find(|e| e.from == "a2" && e.to == "b1")
            .expect("a2 -> b1 edge exists");
        let start = *edge_a2_b1.points.first().unwrap();
        let end = *edge_a2_b1.points.last().unwrap();
        assert!(
            start.0 >= a2.x - 2.0
                && start.0 <= a2.x + a2.width + 2.0
                && start.1 >= a2.y - 2.0
                && start.1 <= a2.y + a2.height + 2.0,
            "Edge a2->b1 start {:?} must stay attached to a2 {:?}",
            start,
            (a2.x, a2.y, a2.width, a2.height)
        );
        assert!(
            end.0 >= b1.x - 2.0
                && end.0 <= b1.x + b1.width + 2.0
                && end.1 >= b1.y - 2.0
                && end.1 <= b1.y + b1.height + 2.0,
            "Edge a2->b1 end {:?} must stay attached to b1 {:?}",
            end,
            (b1.x, b1.y, b1.width, b1.height)
        );
    }

    #[test]
    fn test_flowchart_nested_subgraphs_routing_stays_inside_outer() {
        let code = r#"flowchart TB
    subgraph Outer["Outer Container"]
        subgraph I1["Inner 1"]
            n1[Node 1]
        end
        subgraph I2["Inner 2"]
            n2[Node 2]
        end
        subgraph I3["Inner 3"]
            n3[Node 3]
        end
        I1 --> I2
        I2 --> I3
        I1 --> I3
    end
"#;
        let processed = preprocess_mermaid_code(code);
        let mut parsed =
            mermaid_rs_renderer::parse_mermaid_strict(&processed).expect("Should parse");
        normalize_flowchart_subgraph_directions(&mut parsed.graph);
        let theme = build_light_theme();
        let cfg = mermaid_rs_renderer::LayoutConfig::default();
        let mut layout = mermaid_rs_renderer::compute_layout(&parsed.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed.graph, &mut layout, &theme, &cfg);

        let outer = layout
            .subgraphs
            .iter()
            .find(|s| s.label == "Outer Container")
            .expect("Outer exists");
        let i2 = layout
            .subgraphs
            .iter()
            .find(|s| s.label == "Inner 2")
            .expect("Inner 2 exists");

        // All nested edges must stay strictly inside Outer's bounding box
        for edge in &layout.edges {
            for &(px, py) in &edge.points {
                assert!(
                    px >= outer.x && px <= outer.x + outer.width && py >= outer.y && py <= outer.y + outer.height,
                    "Nested edge point ({px}, {py}) must stay inside Outer {:?}",
                    (outer.x, outer.y, outer.width, outer.height)
                );
            }
        }

        // Adjacent nested subgraphs (I1 -> I2 and I2 -> I3) must use direct 2-point segments,
        // while skip-rank I1 -> I3 must detour around I2 without cutting through I2.
        let direct_count = layout.edges.iter().filter(|e| e.points.len() == 2).count();
        assert_eq!(direct_count, 2, "I1->I2 and I2->I3 must be direct 2-point vertical edges");

        let skip_edge = layout
            .edges
            .iter()
            .find(|e| e.points.len() >= 4)
            .expect("I1->I3 should detour");
        let detour_x = skip_edge.points[1].0;
        assert!(
            detour_x < i2.x || detour_x > i2.x + i2.width,
            "Nested skip-rank detour x={detour_x} must not pass through Inner 2 [{}, {}]",
            i2.x,
            i2.x + i2.width
        );
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
    fn test_flowchart_nested_plain_node_obstacle_and_parallel_edge_labels() {
        // 1. Plain node `p` inside `Outer` between `I1` and `I3` must be treated as an obstacle
        // so `I1 --> I3` detours around `p` while remaining inside `Outer`.
        let nested_plain = r#"flowchart TB
    subgraph Outer["Outer Container"]
        subgraph I1["Inner 1"]
            n1[Node 1]
        end
        p[Plain inside]
        subgraph I3["Inner 3"]
            n3[Node 3]
        end
        I1 --> p
        p --> I3
        I1 --> I3
    end
"#;
        let processed = preprocess_mermaid_code(nested_plain);
        let mut parsed =
            mermaid_rs_renderer::parse_mermaid_strict(&processed).expect("Should parse");
        normalize_flowchart_subgraph_directions(&mut parsed.graph);
        let theme = build_light_theme();
        let cfg = mermaid_rs_renderer::LayoutConfig::default();
        let mut layout = mermaid_rs_renderer::compute_layout(&parsed.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed.graph, &mut layout, &theme, &cfg);

        let outer = layout
            .subgraphs
            .iter()
            .find(|s| s.label == "Outer Container")
            .expect("Outer exists");
        let p_node = layout.nodes.get("p").expect("p exists");
        let skip_edge = layout
            .edges
            .iter()
            .find(|e| e.from != "p" && e.to != "p")
            .expect("I1->I3 edge exists");
        assert!(
            skip_edge.points.len() >= 4,
            "I1->I3 must detour around plain node p, got {:?}",
            skip_edge.points
        );
        let detour_x = skip_edge.points[1].0;
        assert!(
            detour_x < p_node.x || detour_x > p_node.x + p_node.width,
            "I1->I3 detour x={detour_x} must not pass through plain node p [{}, {}]",
            p_node.x,
            p_node.x + p_node.width
        );
        for &(px, py) in &skip_edge.points {
            assert!(
                px >= outer.x && px <= outer.x + outer.width && py >= outer.y && py <= outer.y + outer.height,
                "Detour point ({px}, {py}) must remain inside Outer {:?}",
                (outer.x, outer.y, outer.width, outer.height)
            );
        }

        // 2. Parallel subgraph edges with labels (`A -->|first label| B` and `B -->|back| A`)
        // must have non-overlapping label bounding boxes.
        let parallel_code = r#"flowchart TB
    subgraph A["Subgraph A"]
        a1[Node A]
    end
    subgraph B["Subgraph B"]
        b1[Node B]
    end
    A -->|first label| B
    B -->|back| A
"#;
        let processed_par = preprocess_mermaid_code(parallel_code);
        let mut parsed_par =
            mermaid_rs_renderer::parse_mermaid_strict(&processed_par).expect("Should parse");
        normalize_flowchart_subgraph_directions(&mut parsed_par.graph);
        let mut layout_par =
            mermaid_rs_renderer::compute_layout(&parsed_par.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed_par.graph, &mut layout_par, &theme, &cfg);

        assert_eq!(layout_par.edges.len(), 2);
        let e0 = &layout_par.edges[0];
        let e1 = &layout_par.edges[1];
        let (ax0, ay0) = e0.label_anchor.expect("e0 label anchor");
        let (ax1, ay1) = e1.label_anchor.expect("e1 label anchor");
        let w0 = e0.label.as_ref().unwrap().width;
        let h0 = e0.label.as_ref().unwrap().height;
        let w1 = e1.label.as_ref().unwrap().width;
        let h1 = e1.label.as_ref().unwrap().height;

        let horiz_overlap = (ax0 - ax1).abs() < (w0 + w1) * 0.5;
        let vert_overlap = (ay0 - ay1).abs() < (h0 + h1) * 0.5;
        assert!(
            !(horiz_overlap && vert_overlap),
            "Parallel edge labels must not overlap: e0=({ax0},{ay0},{w0}x{h0}), e1=({ax1},{ay1},{w1}x{h1})"
        );
    }

    #[test]
    fn test_flowchart_rank_gap_expands_for_edge_labels() {
        let theme = build_light_theme();
        let cfg = mermaid_rs_renderer::LayoutConfig::default();

        // 1. LR flowchart with a wide edge label (`sends request payload`)
        let lr_code = r#"flowchart LR
    subgraph A["Service A"]
        a1[Handler]
    end
    subgraph B["Service B"]
        b1[Worker]
    end
    A -->|sends request payload| B
"#;
        let processed_lr = preprocess_mermaid_code(lr_code);
        let mut parsed_lr =
            mermaid_rs_renderer::parse_mermaid_strict(&processed_lr).expect("Should parse LR");
        normalize_flowchart_subgraph_directions(&mut parsed_lr.graph);
        let mut layout_lr = mermaid_rs_renderer::compute_layout(&parsed_lr.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed_lr.graph, &mut layout_lr, &theme, &cfg);

        let edge_lr = &layout_lr.edges[0];
        let (ax, ay) = edge_lr.label_anchor.expect("LR label anchor");
        let lbl_lr = edge_lr.label.as_ref().expect("LR label");
        let l_left = ax - lbl_lr.width * 0.5;
        let l_right = ax + lbl_lr.width * 0.5;
        let l_top = ay - lbl_lr.height * 0.5;
        let l_bottom = ay + lbl_lr.height * 0.5;
        for sub in &layout_lr.subgraphs {
            let overlap_x = l_left < sub.x + sub.width && l_right > sub.x;
            let overlap_y = l_top < sub.y + sub.height && l_bottom > sub.y;
            assert!(
                !(overlap_x && overlap_y),
                "LR label box [{l_left}, {l_top}, {l_right}, {l_bottom}] must not overlap subgraph '{}' {:?}",
                sub.label,
                (sub.x, sub.y, sub.width, sub.height)
            );
        }

        // 2. TB flowchart with a 3-line edge label
        let tb_code = "flowchart TB\n    subgraph Alpha[\"Alpha Layer\"]\n        a1[Node 1]\n    end\n    subgraph Beta[\"Beta Layer\"]\n        b1[Node 2]\n    end\n    Alpha -->|\"line one<br/>line two<br/>line three\"| Beta\n";
        let processed_tb = preprocess_mermaid_code(tb_code);
        let mut parsed_tb =
            mermaid_rs_renderer::parse_mermaid_strict(&processed_tb).expect("Should parse TB");
        normalize_flowchart_subgraph_directions(&mut parsed_tb.graph);
        let mut layout_tb = mermaid_rs_renderer::compute_layout(&parsed_tb.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed_tb.graph, &mut layout_tb, &theme, &cfg);

        let edge_tb = &layout_tb.edges[0];
        let (tx, ty) = edge_tb.label_anchor.expect("TB label anchor");
        let lbl_tb = edge_tb.label.as_ref().expect("TB label");
        let t_left = tx - lbl_tb.width * 0.5;
        let t_right = tx + lbl_tb.width * 0.5;
        let t_top = ty - lbl_tb.height * 0.5;
        let t_bottom = ty + lbl_tb.height * 0.5;
        for sub in &layout_tb.subgraphs {
            let overlap_x = t_left < sub.x + sub.width && t_right > sub.x;
            let overlap_y = t_top < sub.y + sub.height && t_bottom > sub.y;
            assert!(
                !(overlap_x && overlap_y),
                "TB multi-line label box [{t_left}, {t_top}, {t_right}, {t_bottom}] must not overlap subgraph '{}' {:?}",
                sub.label,
                (sub.x, sub.y, sub.width, sub.height)
            );
        }

        // 3. TB detour edge with a wide label (`T -->|to right side| R` skipping over `L`)
        // and converging labelled edges (`L -->|left to bottom| Bt`, `R -->|right to bottom label| Bt`):
        // no label box may overlap any subgraph box or any other label box.
        let detour_code = r#"flowchart TB
    subgraph T["Top"]
        t1[Top Node]
    end
    subgraph L["Left"]
        l1[Left Node]
    end
    subgraph R["Right"]
        r1[Right Node]
    end
    subgraph Bt["Bottom"]
        b1[Bottom Node]
    end
    T --> L
    L --> R
    T -->|to right side| R
    L -->|left to bottom| Bt
    R -->|right to bottom label| Bt
"#;
        let processed_det = preprocess_mermaid_code(detour_code);
        let mut parsed_det =
            mermaid_rs_renderer::parse_mermaid_strict(&processed_det).expect("Should parse detour");
        normalize_flowchart_subgraph_directions(&mut parsed_det.graph);
        let mut layout_det = mermaid_rs_renderer::compute_layout(&parsed_det.graph, &theme, &cfg);
        refine_flowchart_subgraph_layout(&parsed_det.graph, &mut layout_det, &theme, &cfg);

        let labelled_edges: Vec<_> = layout_det
            .edges
            .iter()
            .filter_map(|e| {
                let (ax, ay) = e.label_anchor?;
                let lbl = e.label.as_ref()?;
                Some((ax, ay, lbl.width, lbl.height))
            })
            .collect();
        assert_eq!(labelled_edges.len(), 3);
        for &(ax, ay, lw, lh) in &labelled_edges {
            let left = ax - lw * 0.5;
            let right = ax + lw * 0.5;
            let top = ay - lh * 0.5;
            let bottom = ay + lh * 0.5;
            for sub in &layout_det.subgraphs {
                let overlap_x = left < sub.x + sub.width && right > sub.x;
                let overlap_y = top < sub.y + sub.height && bottom > sub.y;
                assert!(
                    !(overlap_x && overlap_y),
                    "Detour/converging label box [{left}, {top}, {right}, {bottom}] must not overlap subgraph '{}' {:?}",
                    sub.label,
                    (sub.x, sub.y, sub.width, sub.height)
                );
            }
        }
        for i in 0..labelled_edges.len() {
            for j in (i + 1)..labelled_edges.len() {
                let (ax0, ay0, w0, h0) = labelled_edges[i];
                let (ax1, ay1, w1, h1) = labelled_edges[j];
                let overlap_x = (ax0 - ax1).abs() < (w0 + w1) * 0.5;
                let overlap_y = (ay0 - ay1).abs() < (h0 + h1) * 0.5;
                assert!(
                    !(overlap_x && overlap_y),
                    "Converging edge labels must not overlap: {i}={:?}, {j}={:?}",
                    labelled_edges[i],
                    labelled_edges[j]
                );
            }
        }
    }
}
