use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use typst::diag::{FileError, FileResult};
use typst::foundations::{Bytes, Datetime, Duration};
use typst::syntax::{FileId, RootedPath, Source, VirtualPath, VirtualRoot};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};


/// Global font store to avoid re-scanning and re-loading fonts on every compile.
pub struct GlobalFontStore {
    pub book: LazyHash<FontBook>,
    pub fonts: Vec<Font>,
    pub monospace_families: Vec<String>,
    pub body_families: Vec<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FontCapabilityReport {
    pub has_cjk_monospace: bool,
    pub maple_mono_installed: bool,
    pub detected_monospace_fonts: Vec<String>,
    pub detected_body_fonts: Vec<String>,
    pub recommended_font_name: String,
    pub recommended_font_url: String,
    pub download_guide: String,
}

pub fn detect_font_capabilities() -> FontCapabilityReport {
    let store = GlobalFontStore::get();
    let has_cjk_mono = store.monospace_families.iter().any(|f| {
        let l = f.to_lowercase();
        l.contains("maple") || l.contains("sarasa")
    });
    let maple_installed = store.monospace_families.iter().any(|f| {
        f.to_lowercase().contains("maple")
    });

    FontCapabilityReport {
        has_cjk_monospace: has_cjk_mono,
        maple_mono_installed: maple_installed,
        detected_monospace_fonts: store.monospace_families.clone(),
        detected_body_fonts: store.body_families.clone(),
        recommended_font_name: "Maple Mono (NF / SC)".to_string(),
        recommended_font_url: "https://github.com/subframe7536/maple-font".to_string(),
        download_guide: if maple_installed {
            "当前系统已就绪 Maple Mono 字体，支持代码与 ASCII 表格中英文严格 1:2 等宽对齐。".to_string()
        } else {
            "未检测到 Maple Mono 字体。若文档中含有 ASCII 字符画或中英文混合表格，推荐前往 GitHub 下载并安装 Maple Mono 以获得完美对齐效果。".to_string()
        },
    }
}

static FONT_STORE: OnceLock<GlobalFontStore> = OnceLock::new();

impl GlobalFontStore {
    pub fn get() -> &'static GlobalFontStore {
        FONT_STORE.get_or_init(|| {
            let mut fonts = Vec::new();

            let mut asset_count = 0;
            for font_bytes in typst_assets::fonts() {
                let bytes = Bytes::new(font_bytes);
                for font in Font::iter(bytes) {
                    fonts.push(font);
                    asset_count += 1;
                }
            }
            eprintln!("Loaded {} fonts from typst_assets", asset_count);

            // 2. Discover system fonts via fontdb
            let mut db = fontdb::Database::new();
            db.load_system_fonts();

            // Load user font directories across platforms
            if let Ok(home) = std::env::var("HOME") {
                let home = PathBuf::from(home);
                let mac_user_fonts = home.join("Library/Fonts");
                if mac_user_fonts.exists() {
                    db.load_fonts_dir(&mac_user_fonts);
                }
                let linux_user_fonts = home.join(".local/share/fonts");
                if linux_user_fonts.exists() {
                    db.load_fonts_dir(&linux_user_fonts);
                }
                let linux_fonts = home.join(".fonts");
                if linux_fonts.exists() {
                    db.load_fonts_dir(&linux_fonts);
                }
            }
            if let Ok(local_appdata) = std::env::var("LOCALAPPDATA") {
                let win_user_fonts = PathBuf::from(local_appdata).join("Microsoft\\Windows\\Fonts");
                if win_user_fonts.exists() {
                    db.load_fonts_dir(&win_user_fonts);
                }
            }

            // Target key Chinese / Japanese / Korean & clean UI fonts
            let target_prefixes = [
                // CJK Proportional UI Fonts
                "pingfang",
                "songti",
                "kaiti",
                "hiragino",
                "microsoft yahei",
                "simsun",
                "simhei",
                "noto sans cjk",
                "noto serif cjk",
                "source han sans",
                "source han serif",
                // Western Clean Proportional Fonts
                "inter",
                "sf pro",
                "segoe ui",
                "helvetica neue",
                "arial",
                // CJK Strict Monospace / Alignment Fonts
                "maple mono",
                "sarasa mono",
                "sarasa gothic",
                "sarasa term",
                // Western Monospace Fonts
                "jetbrains mono",
                "fira code",
                "cascadia code",
                "cascadia mono",
                "source code pro",
                "hack",
                "iosevka",
                "inconsolata",
                "consolas",
                "menlo",
                "monaco",
                "courier new",
                // Math Fonts
                "stix two",
            ];

            let mut font_file_cache: HashMap<PathBuf, Bytes> = HashMap::new();
            let mut detected_mono = std::collections::BTreeSet::new();
            let mut detected_body = std::collections::BTreeSet::new();

            for face in db.faces() {
                let is_target = face.families.iter().any(|(f_name, _)| {
                    let l = f_name.to_lowercase();
                    target_prefixes.iter().any(|p| l.contains(p))
                });
                if !is_target {
                    continue;
                }

                // For multi-weight CJK / Monospace families (like Maple Mono with 32 TTFs),
                // only keep standard Regular (380-450) and Bold (650-750) to optimize memory.
                let is_cjk_multi_weight = face.families.iter().any(|(f_name, _)| {
                    let l = f_name.to_lowercase();
                    l.contains("maple") || l.contains("sarasa") || l.contains("noto")
                });
                if is_cjk_multi_weight {
                    let w = face.weight.0;
                    if (w < 380 || w > 450) && (w < 650 || w > 750) {
                        continue;
                    }
                }

                // Track detected font families
                for (f, _) in &face.families {
                    let l = f.to_lowercase();
                    if l.contains("mono") || l.contains("code") || l.contains("menlo") || l.contains("consolas") || l.contains("courier") || face.monospaced {
                        detected_mono.insert(f.clone());
                    } else {
                        detected_body.insert(f.clone());
                    }
                }

                match &face.source {
                    fontdb::Source::File(path) => {
                        let bytes = if let Some(b) = font_file_cache.get(path) {
                            b.clone()
                        } else {
                            match fs::read(path) {
                                Ok(data) => {
                                    let b = Bytes::new(data);
                                    font_file_cache.insert(path.clone(), b.clone());
                                    b
                                }
                                Err(_) => continue,
                            }
                        };
                        if let Some(font) = Font::new(bytes, face.index) {
                            fonts.push(font);
                        }
                    }
                    _ => {
                        db.with_face_data(face.id, |data, index| {
                            let bytes = Bytes::new(data.to_vec());
                            if let Some(font) = Font::new(bytes, index) {
                                fonts.push(font);
                            }
                        });
                    }
                }
            }

            let monospace_families: Vec<String> = detected_mono.into_iter().collect();
            let body_families: Vec<String> = detected_body.into_iter().collect();

            let book = LazyHash::new(FontBook::from_fonts(&fonts));
            GlobalFontStore {
                book,
                fonts,
                monospace_families,
                body_families,
            }
        })
    }
}

pub struct MemoryWorld {
    library: LazyHash<Library>,
    main_id: FileId,
    main_source: Source,
    doc_dir: PathBuf,
    virtual_files: HashMap<PathBuf, Bytes>,
    now: Datetime,
}

impl MemoryWorld {
    pub fn new(
        source_text: &str,
        doc_dir: impl AsRef<Path>,
        virtual_files: HashMap<PathBuf, Bytes>,
    ) -> Self {
        let vpath = VirtualPath::new("main.typ").unwrap();
        let rooted = RootedPath::new(VirtualRoot::Project, vpath);
        let main_id = FileId::new(rooted);
        let main_source = Source::new(main_id, source_text.to_string());

        let library = LazyHash::new(Library::default());
        let doc_dir = doc_dir.as_ref().to_path_buf();

        Self {
            library,
            main_id,
            main_source,
            doc_dir,
            virtual_files,
            now: Datetime::from_ymd(2026, 9, 11).unwrap_or_else(|| Datetime::from_ymd(2026, 1, 1).unwrap()),
        }
    }
}

impl World for MemoryWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &GlobalFontStore::get().book
    }

    fn main(&self) -> FileId {
        self.main_id
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == self.main_id {
            Ok(self.main_source.clone())
        } else {
            let rel_str = id.vpath().get_without_slash();
            let rel_path = Path::new(rel_str);
            if let Some(bytes) = self.virtual_files.get(rel_path) {
                let text = std::str::from_utf8(bytes.as_slice())
                    .map_err(|_| FileError::InvalidUtf8)?;
                Ok(Source::new(id, text.to_string()))
            } else {
                let full_path = self.doc_dir.join(rel_path);
                let text = fs::read_to_string(&full_path)
                    .map_err(|e| match e.kind() {
                        std::io::ErrorKind::NotFound => FileError::NotFound(rel_path.to_path_buf()),
                        std::io::ErrorKind::PermissionDenied => FileError::AccessDenied,
                        _ => FileError::Other(Some(e.to_string().into())),
                    })?;
                Ok(Source::new(id, text))
            }
        }
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        let rel_str = id.vpath().get_without_slash();
        let rel_path = Path::new(rel_str);

        // 1. Check virtual memory files (e.g. generated Mermaid SVG)
        if let Some(bytes) = self.virtual_files.get(rel_path) {
            return Ok(bytes.clone());
        }

        // Also check with simple filename
        if let Some(filename) = rel_path.file_name() {
            let file_path = PathBuf::from(filename);
            if let Some(bytes) = self.virtual_files.get(&file_path) {
                return Ok(bytes.clone());
            }
        }

        // 2. Fall back to local file system in doc_dir
        let full_path = self.doc_dir.join(rel_path);
        match fs::read(&full_path) {
            Ok(data) => Ok(Bytes::new(data)),
            Err(_) => {
                // Graceful fallback for missing or remote assets:
                // Provide a 1x1 transparent PNG so compilation never aborts with a fatal crash.
                const TRANSPARENT_PNG: &[u8] = &[
                    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
                    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
                    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
                    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
                    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
                    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
                ];
                Ok(Bytes::new(TRANSPARENT_PNG))
            }
        }
    }


    fn font(&self, index: usize) -> Option<Font> {
        GlobalFontStore::get().fonts.get(index).cloned()
    }

    fn today(&self, _offset: Option<Duration>) -> Option<Datetime> {
        Some(self.now)
    }
}
