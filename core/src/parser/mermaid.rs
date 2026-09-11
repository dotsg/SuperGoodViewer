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

/// Renders Mermaid diagram code into an SVG byte stream with SHA-256 caching.
/// If rendering fails, returns a fallback rendered block.
pub fn render_mermaid(code: &str) -> RenderedMermaid {
    let mut hasher = Sha256::new();
    hasher.update(code.trim().as_bytes());
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
    match mermaid_rs_renderer::render(code) {
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
}
