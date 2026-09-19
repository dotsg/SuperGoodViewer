use std::env;
use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};
use std::process::exit;

use sogood_core::compile_markdown_to_pdf_result;
use sogood_core::compiler::engine::RenderOptions;

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn print_help() {
    println!(
        r#"sgv-cli {VERSION} - SuperGoodViewer Headless Markdown Exporter & CLI

Usage:
  sgv export <path>... [options]
  sgv-cli export <path>... [options]
  sgv <input.md> -o <output.pdf> [options]

Arguments:
  <path>...                       One or more Markdown files or directories,
                                  or '-' to read from stdin

Options:
  -o, --output <path>             Output PDF path (for single file) or
                                  destination directory (for directory/multi-file)
  -f, --format <format>           Page layout format: a4, a4-landscape, fluid, slide, slide-4-3
                                  (default: a4)
      --fluid                     Shorthand for --format fluid
  -t, --theme <theme>             Theme: light, dark (default: light)
      --dark                      Shorthand for --theme dark
  -s, --font-size <pt>            Font size in points (default: 10.5)
      --title <title>             Document title override (single-document only)
      --image-cache-dir <dir>     Directory for caching remote images
  -r, --recursive                 Recursively scan subdirectories (default: enabled)
      --no-recursive              Do not scan subdirectories
  -h, --help                      Show this help message
  -v, --version                   Show version information

Examples:
  sgv export README.md                             # Single file -> README.pdf
  sgv export ./docs                                # All markdown in ./docs (in-place)
  sgv export ./docs -o ./dist                      # All markdown in ./docs -> ./dist/*.pdf
  sgv export doc1.md doc2.md -o ./dist             # Multiple files into ./dist
  cat draft.md | sgv export - -o draft.pdf         # Stdin pipe
"#
    );
}

#[derive(Debug, Clone)]
struct CliConfig {
    inputs: Vec<String>,
    output: Option<String>,
    format: Option<String>,
    theme: Option<String>,
    font_size: Option<f32>,
    title: Option<String>,
    image_cache_dir: Option<String>,
    recursive: bool,
}

impl Default for CliConfig {
    fn default() -> Self {
        Self {
            inputs: Vec::new(),
            output: None,
            format: None,
            theme: None,
            font_size: None,
            title: None,
            image_cache_dir: None,
            recursive: true,
        }
    }
}

fn normalize_format(fmt: &str) -> String {
    let lower = fmt.trim().to_ascii_lowercase();
    match lower.as_str() {
        "a4" | "a4_portrait" | "a4portrait" | "portrait" => "a4".to_string(),
        "a4_landscape" | "a4landscape" | "landscape" | "a4-landscape" => "a4_landscape".to_string(),
        "fluid" => "fluid".to_string(),
        "slide" | "slide_16_9" | "slide16x9" | "slide-16-9" | "16:9" | "16x9" => "slide_16_9".to_string(),
        "slide_4_3" | "slide4x3" | "slide-4-3" | "4:3" | "4x3" => "slide_4_3".to_string(),
        other => other.to_string(),
    }
}

fn extract_title_from_markdown(markdown: &str, fallback: &str) -> String {
    let mut in_frontmatter = false;
    let mut in_fence = false;
    let mut line_index = 0;

    for line in markdown.lines() {
        let trimmed = line.trim();
        if line_index == 0 && trimmed == "---" {
            in_frontmatter = true;
            line_index += 1;
            continue;
        }
        if in_frontmatter {
            if trimmed == "---" {
                in_frontmatter = false;
            }
            line_index += 1;
            continue;
        }

        if trimmed.starts_with("```") || trimmed.starts_with("~~~") {
            in_fence = !in_fence;
            line_index += 1;
            continue;
        }
        if in_fence {
            line_index += 1;
            continue;
        }

        if trimmed.starts_with("# ") {
            let candidate = trimmed.trim_start_matches("# ").trim();
            if !candidate.is_empty() {
                return candidate.to_string();
            }
        }
        line_index += 1;
    }

    fallback.to_string()
}

fn parse_cli_args(args: &[String]) -> Result<CliConfig, String> {
    let mut config = CliConfig::default();
    let mut i = 0;

    while i < args.len() {
        let arg = &args[i];
        match arg.as_str() {
            "export" if i == 0 => {
                // subcommand marker
                i += 1;
            }
            "--export" => {
                // alias flag for export mode
                i += 1;
            }
            "-h" | "--help" => {
                print_help();
                exit(0);
            }
            "-v" | "--version" => {
                println!("sgv-cli {}", VERSION);
                exit(0);
            }
            "-o" | "--output" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for output path".to_string());
                }
                config.output = Some(args[i].clone());
                i += 1;
            }
            "-f" | "--format" | "--page-format" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for page format".to_string());
                }
                config.format = Some(normalize_format(&args[i]));
                i += 1;
            }
            "--fluid" => {
                config.format = Some("fluid".to_string());
                i += 1;
            }
            "-t" | "--theme" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for theme".to_string());
                }
                config.theme = Some(args[i].to_ascii_lowercase());
                i += 1;
            }
            "--dark" => {
                config.theme = Some("dark".to_string());
                i += 1;
            }
            "-s" | "--font-size" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for font size".to_string());
                }
                let pt = args[i]
                    .parse::<f32>()
                    .map_err(|_| format!("Invalid font size: {}", args[i]))?;
                config.font_size = Some(pt);
                i += 1;
            }
            "--title" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for document title".to_string());
                }
                config.title = Some(args[i].clone());
                i += 1;
            }
            "--image-cache-dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("Missing argument for image cache dir".to_string());
                }
                config.image_cache_dir = Some(args[i].clone());
                i += 1;
            }
            "-r" | "--recursive" => {
                config.recursive = true;
                i += 1;
            }
            "--no-recursive" => {
                config.recursive = false;
                i += 1;
            }
            flag if flag.starts_with('-') && flag != "-" => {
                return Err(format!("Unknown option: {}", flag));
            }
            positional => {
                config.inputs.push(positional.to_string());
                i += 1;
            }
        }
    }

    Ok(config)
}

fn collect_markdown_files(dir: &Path, recursive: bool) -> io::Result<Vec<PathBuf>> {
    let mut files = Vec::new();
    collect_markdown_files_internal(dir, recursive, &mut files)?;
    files.sort();
    Ok(files)
}

fn collect_markdown_files_internal(
    dir: &Path,
    recursive: bool,
    files: &mut Vec<PathBuf>,
) -> io::Result<()> {
    if !dir.is_dir() {
        return Ok(());
    }

    let entries = fs::read_dir(dir)?;
    for entry in entries {
        let entry = entry?;
        let path = entry.path();
        let file_name = entry.file_name();
        let name_str = file_name.to_string_lossy();

        // Skip hidden files/directories and common build/ignore directories
        if name_str.starts_with('.')
            || name_str == "node_modules"
            || name_str == "target"
            || name_str == "build"
            || name_str == ".dart_tool"
        {
            continue;
        }

        if path.is_dir() {
            if recursive {
                collect_markdown_files_internal(&path, recursive, files)?;
            }
        } else if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                let ext_lower = ext.to_ascii_lowercase();
                if ext_lower == "md" || ext_lower == "markdown" {
                    files.push(path);
                }
            }
        }
    }

    Ok(())
}

#[derive(Debug)]
struct ExportTask {
    source: SourceInput,
    output_path: PathBuf,
    doc_dir: PathBuf,
    fallback_title: String,
}

#[derive(Debug)]
enum SourceInput {
    Stdin,
    File(PathBuf),
}

fn plan_export_tasks(config: &CliConfig) -> Result<Vec<ExportTask>, String> {
    if config.inputs.is_empty() {
        return Err("No input files or directories specified.\nUsage: sgv export <path>... [-o <output>]".to_string());
    }

    let is_stdin = config.inputs.len() == 1 && config.inputs[0] == "-";
    if is_stdin {
        let out = match &config.output {
            Some(o) => {
                let p = Path::new(o);
                if p.is_dir() || o.ends_with('/') || o.ends_with('\\') {
                    p.join("output.pdf")
                } else {
                    PathBuf::from(o)
                }
            }
            None => PathBuf::from("output.pdf"),
        };
        return Ok(vec![ExportTask {
            source: SourceInput::Stdin,
            output_path: out,
            doc_dir: PathBuf::from("."),
            fallback_title: "Document".to_string(),
        }]);
    }

    // Expand inputs into file paths
    struct Item {
        file_path: PathBuf,
        base_dir: Option<PathBuf>,
    }

    let mut collected_items: Vec<Item> = Vec::new();

    for input_str in &config.inputs {
        if input_str == "-" {
            return Err("Cannot combine stdin '-' with other input files or directories.".to_string());
        }

        let path = Path::new(input_str);
        if !path.exists() {
            return Err(format!("Input path not found: {}", input_str));
        }

        if path.is_dir() {
            let files = collect_markdown_files(path, config.recursive)
                .map_err(|e| format!("Failed to scan directory '{}': {}", input_str, e))?;
            for f in files {
                collected_items.push(Item {
                    file_path: f,
                    base_dir: Some(path.to_path_buf()),
                });
            }
        } else if path.is_file() {
            collected_items.push(Item {
                file_path: path.to_path_buf(),
                base_dir: None,
            });
        }
    }

    if collected_items.is_empty() {
        return Err("No Markdown files (.md or .markdown) found to export.".to_string());
    }

    let is_single = collected_items.len() == 1;
    let mut tasks = Vec::with_capacity(collected_items.len());

    for item in collected_items {
        let f_path = item.file_path;
        let stem = f_path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("document")
            .to_string();
        let parent = f_path.parent().unwrap_or(Path::new(".")).to_path_buf();

        let out_path = if let Some(ref dest) = config.output {
            let dest_p = Path::new(dest);
            if is_single && item.base_dir.is_none() && !dest_p.is_dir() && !dest.ends_with('/') && !dest.ends_with('\\') {
                // User passed single file and specific output file name (e.g. -o out.pdf)
                dest_p.to_path_buf()
            } else {
                // Destination is a directory
                if let Some(ref base) = item.base_dir {
                    // Preserve subpath relative to base directory
                    let rel = f_path
                        .strip_prefix(base)
                        .unwrap_or(&f_path);
                    let mut rel_out = rel.to_path_buf();
                    rel_out.set_extension("pdf");
                    dest_p.join(rel_out)
                } else {
                    dest_p.join(format!("{}.pdf", stem))
                }
            }
        } else {
            // No -o given: export in place next to markdown file
            parent.join(format!("{}.pdf", stem))
        };

        tasks.push(ExportTask {
            source: SourceInput::File(f_path),
            output_path: out_path,
            doc_dir: parent,
            fallback_title: stem,
        });
    }

    Ok(tasks)
}

fn main() {
    let raw_args: Vec<String> = env::args().skip(1).collect();

    if raw_args.is_empty() {
        print_help();
        exit(0);
    }

    let config = match parse_cli_args(&raw_args) {
        Ok(cfg) => cfg,
        Err(e) => {
            eprintln!("sgv-cli: error: {}", e);
            eprintln!("Run 'sgv --help' for usage information.");
            exit(1);
        }
    };

    let tasks = match plan_export_tasks(&config) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("sgv-cli: error: {}", e);
            exit(1);
        }
    };

    let chosen_format = config.format.unwrap_or_else(|| "a4".to_string());
    let is_fluid = chosen_format == "fluid";

    let options = RenderOptions {
        mode: if is_fluid {
            "fluid".to_string()
        } else {
            "paged".to_string()
        },
        theme: config.theme.unwrap_or_else(|| "light".to_string()),
        font_size: config.font_size.unwrap_or(10.5),
        page_format: Some(chosen_format),
        image_cache_dir: config.image_cache_dir.clone(),
        ..Default::default()
    };

    let total = tasks.len();
    let is_multi = total > 1;
    let mut success_count = 0;
    let mut fail_count = 0;

    for (index, task) in tasks.iter().enumerate() {
        let (content, display_src) = match &task.source {
            SourceInput::Stdin => {
                let mut buffer = String::new();
                if let Err(e) = io::stdin().read_to_string(&mut buffer) {
                    eprintln!("sgv-cli: error: failed to read from stdin: {}", e);
                    fail_count += 1;
                    continue;
                }
                (buffer, "<stdin>".to_string())
            }
            SourceInput::File(p) => match fs::read_to_string(p) {
                Ok(c) => (c, p.display().to_string()),
                Err(e) => {
                    eprintln!("sgv-cli: error: failed to read file '{}': {}", p.display(), e);
                    fail_count += 1;
                    continue;
                }
            },
        };

        let title = if total == 1 && config.title.is_some() {
            config.title.clone().unwrap()
        } else {
            extract_title_from_markdown(&content, &task.fallback_title)
        };

        if is_multi {
            println!(
                "[{}/{}] Exporting: {} -> {}",
                index + 1,
                total,
                display_src,
                task.output_path.display()
            );
        }

        match compile_markdown_to_pdf_result(&content, &title, &task.doc_dir, &options) {
            Ok(result) => {
                if result.degraded_equation_count > 0 {
                    eprintln!(
                        "sgv-cli: warning: in '{}': {} LaTeX equation(s) could not be rendered and were degraded with fallback styling",
                        display_src,
                        result.degraded_equation_count
                    );
                }
                let pdf_bytes = result.pdf_bytes;
                if let Some(parent) = task.output_path.parent() {
                    if !parent.as_os_str().is_empty() && !parent.exists() {
                        let _ = fs::create_dir_all(parent);
                    }
                }

                if let Err(e) = fs::write(&task.output_path, &pdf_bytes) {
                    eprintln!(
                        "sgv-cli: error: failed to write output PDF to '{}': {}",
                        task.output_path.display(),
                        e
                    );
                    fail_count += 1;
                    continue;
                }

                let size_kb = pdf_bytes.len() as f64 / 1024.0;
                if is_multi {
                    println!("       ✓ Success ({:.1} KB)", size_kb);
                } else {
                    println!("Exported: {} ({:.1} KB)", task.output_path.display(), size_kb);
                }
                success_count += 1;
            }
            Err(e) => {
                eprintln!(
                    "sgv-cli: error: failed to compile '{}': {}",
                    display_src, e
                );
                fail_count += 1;
            }
        }
    }

    if is_multi {
        println!(
            "\nFinished: {} exported successfully, {} failed.",
            success_count, fail_count
        );
    }

    if fail_count > 0 {
        exit(1);
    } else {
        exit(0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_normalize_format() {
        assert_eq!(normalize_format("a4"), "a4");
        assert_eq!(normalize_format("a4_portrait"), "a4");
        assert_eq!(normalize_format("A4"), "a4");
        assert_eq!(normalize_format("a4-landscape"), "a4_landscape");
        assert_eq!(normalize_format("fluid"), "fluid");
        assert_eq!(normalize_format("slide"), "slide_16_9");
        assert_eq!(normalize_format("16:9"), "slide_16_9");
        assert_eq!(normalize_format("4:3"), "slide_4_3");
    }

    #[test]
    fn test_extract_title_from_markdown() {
        let md1 = "# My Great Document\n\nSome body text.";
        assert_eq!(extract_title_from_markdown(md1, "Fallback"), "My Great Document");

        let md_frontmatter = "---\ntitle: Frontmatter\n---\n\n# Real Header\n\nBody";
        assert_eq!(extract_title_from_markdown(md_frontmatter, "Fallback"), "Real Header");

        let md_no_h1 = "## Level 2\n\nNo h1 here";
        assert_eq!(extract_title_from_markdown(md_no_h1, "Fallback"), "Fallback");

        let md_fence = "```bash\n# install deps\nnpm install\n```\n# Real Document Title\n";
        assert_eq!(extract_title_from_markdown(md_fence, "Fallback"), "Real Document Title");
    }

    #[test]
    fn test_parse_cli_args_positional_export_and_flag() {
        // "export" at index 0 is subcommand, "export" at index 1 is positional argument
        let args = vec!["export".to_string(), "export".to_string()];
        let cfg = parse_cli_args(&args).expect("parse failed");
        assert_eq!(cfg.inputs, vec!["export"]);

        // --export anywhere should be accepted
        let args2 = vec!["doc.md".to_string(), "--export".to_string(), "-o".to_string(), "out.pdf".to_string()];
        let cfg2 = parse_cli_args(&args2).expect("parse failed");
        assert_eq!(cfg2.inputs, vec!["doc.md"]);
        assert_eq!(cfg2.output.as_deref(), Some("out.pdf"));
    }

    #[test]
    fn test_parse_cli_args_export_subcommand() {
        let args = vec![
            "export".to_string(),
            "doc.md".to_string(),
            "-o".to_string(),
            "out.pdf".to_string(),
            "-f".to_string(),
            "a4".to_string(),
            "-t".to_string(),
            "dark".to_string(),
            "-s".to_string(),
            "12.0".to_string(),
            "--title".to_string(),
            "Custom Title".to_string(),
        ];
        let cfg = parse_cli_args(&args).expect("parse failed");
        assert_eq!(cfg.inputs, vec!["doc.md"]);
        assert_eq!(cfg.output.as_deref(), Some("out.pdf"));
        assert_eq!(cfg.format.as_deref(), Some("a4"));
        assert_eq!(cfg.theme.as_deref(), Some("dark"));
        assert_eq!(cfg.font_size, Some(12.0));
        assert_eq!(cfg.title.as_deref(), Some("Custom Title"));
        assert!(cfg.recursive);
    }

    #[test]
    fn test_parse_cli_args_stdin_dash() {
        let args = vec![
            "export".to_string(),
            "-".to_string(),
            "-o".to_string(),
            "stdin.pdf".to_string(),
        ];
        let cfg = parse_cli_args(&args).expect("parse failed");
        assert_eq!(cfg.inputs, vec!["-"]);
        assert_eq!(cfg.output.as_deref(), Some("stdin.pdf"));
    }

    #[test]
    fn test_parse_cli_args_shorthand_flags() {
        let args = vec![
            "input.md".to_string(),
            "--fluid".to_string(),
            "--dark".to_string(),
            "-o".to_string(),
            "fluid_dark.pdf".to_string(),
            "--no-recursive".to_string(),
        ];
        let cfg = parse_cli_args(&args).expect("parse failed");
        assert_eq!(cfg.inputs, vec!["input.md"]);
        assert_eq!(cfg.output.as_deref(), Some("fluid_dark.pdf"));
        assert_eq!(cfg.format.as_deref(), Some("fluid"));
        assert_eq!(cfg.theme.as_deref(), Some("dark"));
        assert!(!cfg.recursive);
    }

    #[test]
    fn test_plan_export_directory_structure() {
        let temp_dir = std::env::temp_dir().join(format!("sgv_test_dir_{}", std::process::id()));
        let sub_dir = temp_dir.join("sub");
        let _ = fs::create_dir_all(&sub_dir);

        let file1 = temp_dir.join("doc1.md");
        let file2 = sub_dir.join("doc2.markdown");
        let ignored_file = temp_dir.join("ignore.txt");

        fs::write(&file1, "# Doc 1\n").unwrap();
        fs::write(&file2, "# Doc 2\n").unwrap();
        fs::write(&ignored_file, "text\n").unwrap();

        let cfg = CliConfig {
            inputs: vec![temp_dir.to_string_lossy().to_string()],
            output: Some(temp_dir.join("dist").to_string_lossy().to_string()),
            recursive: true,
            ..Default::default()
        };

        let tasks = plan_export_tasks(&cfg).expect("plan failed");
        assert_eq!(tasks.len(), 2);

        let out1 = &tasks[0].output_path;
        let out2 = &tasks[1].output_path;

        assert!(out1.ends_with("doc1.pdf"));
        assert!(out2.ends_with(Path::new("sub").join("doc2.pdf")));

        let _ = fs::remove_dir_all(&temp_dir);
    }

    #[test]
    fn test_plan_export_single_file_directory_preserves_extension() {
        let temp_dir = std::env::temp_dir().join(format!("sgv_test_single_in_dir_{}", std::process::id()));
        let _ = fs::create_dir_all(&temp_dir);
        let file1 = temp_dir.join("single.md");
        fs::write(&file1, "# Single\n").unwrap();

        let dist = temp_dir.join("dist"); // directory does not exist yet!
        let cfg = CliConfig {
            inputs: vec![temp_dir.to_string_lossy().to_string()],
            output: Some(dist.to_string_lossy().to_string()),
            recursive: true,
            ..Default::default()
        };

        let tasks = plan_export_tasks(&cfg).expect("plan failed");
        assert_eq!(tasks.len(), 1);
        assert_eq!(tasks[0].output_path, dist.join("single.pdf"));

        let _ = fs::remove_dir_all(&temp_dir);
    }
}
