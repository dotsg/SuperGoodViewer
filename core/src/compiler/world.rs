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

            // Target key Chinese / Japanese / Korean & clean UI fonts
            let target_families = [
                "PingFang SC",
                "Songti SC",
                "Hiragino Sans GB",
                "Microsoft YaHei",
                "SimSun",
                "SimHei",
                "Noto Sans CJK SC",
                "Noto Serif CJK SC",
                "Noto Sans",
                "Inter",
                "SF Pro",
                "SF Pro Text",
                "SF Pro Display",
                "Segoe UI",
                "San Francisco",
                "Helvetica Neue",
                "Arial",
                "JetBrains Mono",
                "Fira Code",
                "Cascadia Code",
                "Consolas",
                "Menlo",
                "Courier New",
                "STIX Two Text",
                "STIX Two Math",
                "Source Han Sans SC",
                "Source Han Serif SC",
            ];

            for face in db.faces() {
                let is_target = face.families.iter().any(|(f_name, _)| {
                    target_families.iter().any(|tf| tf.eq_ignore_ascii_case(f_name))
                });
                if is_target {
                    db.with_face_data(face.id, |data, index| {
                        let bytes = Bytes::new(data.to_vec());
                        if let Some(font) = Font::new(bytes, index) {
                            fonts.push(font);
                        }
                    });
                }
            }

            let book = LazyHash::new(FontBook::from_fonts(&fonts));
            GlobalFontStore { book, fonts }
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
