# Vendored Office Crates (`word-*` & `deck-*`)

This directory contains read-only parsing, layout, font, rendering, and PDF export crates vendored from the sister projects **WordCraft** and **DeckCraft** so that `sogood_core` builds as a self-contained workspace across macOS, Windows, Linux, iOS, and Android.

## 1. WordCraft Crates (`word-*`) — Upstream commit: `14ca2031`

- `word-doc` (`wordcraft-doc`): Document IR (`Document`, `Section`, `Paragraph`, `Run`, `Table`, `Drawing`).
- `word-fonts` (`wordcraft-fonts`): Bundled OFL font set (Liberation Sans/Serif/Mono, Carlito, Caladea, Noto Sans/Serif/Mono, DejaVu Math TeX Gyre, Symbols) + system font scanner + CJK fallback cascade.
- `word-docx` (`wordcraft-docx`): `.docx` / `.docm` / `.dotx` / `.dotm` OOXML and Word 2003 XML reader.
- `word-doc97` (`wordcraft-doc97`): Legacy OLE2 Word 97–2003 `.doc` binary FIB/piece-table reader.
- `word-layout` (`wordcraft-layout`): Paged (`ViewMode::Print`) and fluid/mobile (`ViewMode::Web` / `ViewMode::Read`) layout engine.
- `word-pdf` (`wordcraft-pdf`): Vector PDF exporter built on `krilla`.

### Local Adaptations in `word-*`
- **`word-fonts`**: Added iOS (`/System/Library/Fonts/...`) and Android (`/system/fonts`, `/product/fonts`) font directory discovery, expanded `CJK_FALLBACK_ORDER`, and exposed `bundled()` and `is_font_file_name()` so `deck-fonts` and `sogood_core` share the compiled-in font bytes without duplicating ~9 MB of font data in the binary.

## 2. DeckCraft Crates (`deck-*`) — Upstream commit: `159ed07e`

- `deck-geom` (`deckcraft-geom`): 2D geometry primitives (`Point`, `Size`, `Rect`, `Transform`, `Path`) and preset OOXML shapes.
- `deck-color` (`deckcraft-color`): sRGB / HSL color types, stops, and gradients.
- `deck-metafile` (`deckcraft-metafile`): WMF / EMF / PICT vector metafile decoder for legacy embedded clipart.
- `deck-model` (`deckcraft-model`): Presentation IR (`Presentation`, `Slide`, `SlideLayout`, `SlideMaster`, `Shape`, `Table`, `Chart`, `SmartArt`, `TextBody`, speaker `notes`).
- `deck-anim` (`deckcraft-anim`): Slide transition and animation timing metadata.
- `deck-fonts` (`deckcraft-fonts`): Font database, metric-compatible Office substitutes, embedded `.odttf` / `.fntdata` deobfuscation, and HarfRust shaping.
- `deck-text` (`deckcraft-text`): Rich text paragraph layout, auto-fit, bullets, and glyph run positioning.
- `deck-pptx` (`deckcraft-pptx`): `.pptx` / `.pptm` / `.potx` / `.potm` / `.ppsx` / `.ppsm` OOXML importer and OLE2 encryption detector (`cfb`).
- `deck-render` (`deckcraft-render`): `vello_cpu` slide compositor (backgrounds, shapes, tables, charts, images, text).
- `deck-pdf` (`deckcraft-pdf`): Hybrid vector + raster PDF exporter (`PageLayout::Slides` and `PageLayout::Notes`) built on `krilla`.

### Local Adaptations in `deck-*`
- **`deck-fonts`**: Linked against `wordcraft-fonts` via `wordcraft_fonts::bundled()` instead of embedding duplicate static font blobs; added iOS/Android system font directories and expanded `SYSTEM_FALLBACKS` for CJK/mobile coverage; upgraded `FontDb::add_fonts` so fuller font files replace smaller subset-embedded faces of the same `(family, style, coords)`.
- **`deck-pdf`**: Upgraded `Exporter::paragraphs` (`PageLayout::Notes` speaker notes renderer) to perform per-character `FontDb::global().cascade` font fallback and character-level line wrapping for CJK/no-space scripts so Chinese/Japanese/Korean speaker notes wrap and render without `.notdef` tofu boxes.
- **`deck-pptx`**: Removed external `deckcraft_engine` dev-dependency reference in `cfb::tests::a_password_protected_presentation_is_named_as_such` so `cargo test --workspace` compiles standalone.

### Known Limitations
- **Disjoint Embedded Font Subsets Across Presentations**: `deckcraft_fonts::FontDb::global()` is process-wide. When a newly loaded presentation embeds a larger font file for the same `(family, style, coords)` as an earlier embedded subset, `FontDb::add_fonts` upgrades the face in place. However, if two presentations opened in the same session embed *disjoint* glyph subsets of a font family that is not installed on the system, the larger subset replaces the smaller one rather than merging glyph tables. Installing the full font on the system (or via SuperGoodViewer's custom font directory) resolves this completely; per-document font overlay isolation can be explored in a future iteration.

