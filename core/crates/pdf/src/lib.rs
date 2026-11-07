//! WordCraft PDF export through the shared `craft-pdf` writer and Krilla drawing primitives.
//!
//! [`export`] lays the document out and draws each page's display list
//! ([`wordcraft_layout::display::page_display`]) into a PDF page:
//!
//! - **Text as real text:** glyph runs are written with embedded, subsetted fonts and a Unicode
//!   mapping taken from the paragraph text, so text is selectable, searchable and extractable.
//!   Synthetic bold (fill + stroke) and italic (skew) follow the renderer.
//! - **Graphics:** fills (highlight, shading, cell fills), rules and underlines (solid, dotted,
//!   dashed, double, wave), shapes, pictures (decoded with `image`; JPEG passed through, the rest
//!   embedded losslessly; WMF and EMF drawn as vector paths and embedded bitmaps) with cropping and
//!   opacity, the page colour and the watermark.
//! - **Interactive:** link annotations for hyperlinked runs (URLs and internal `#bookmark`
//!   links) and a document outline built from the headings (outline levels).
//! - **Metadata:** title, author, subject, keywords, language, creation date.
//! - **Tagged PDF (best effort):** one structure element per paragraph (`H1`–`H6` for headings,
//!   `P` otherwise), `Figure` for pictures with their alt text; headers, footers, decorations and
//!   the watermark are artifacts.
//!
//! Nothing here panics on hostile documents: sizes are clamped, unknown fonts or undecodable
//! pictures are skipped (a grey box stands in for a picture).
#![deny(clippy::unwrap_used, clippy::expect_used, clippy::panic, clippy::unimplemented, clippy::todo, clippy::unreachable)]
#![forbid(unsafe_code)]

pub mod imposition;

use std::collections::{HashMap, HashSet};
use std::num::NonZeroU16;
use std::sync::Arc;

pub(crate) mod write {
    #[derive(Default)]
    pub struct Metadata {
        pub creator: String,
        pub producer: String,
        pub title: Option<String>,
        pub authors: Vec<String>,
        pub description: Option<String>,
        pub keywords: Vec<String>,
        pub created: Option<krilla::metadata::DateTime>,
    }

    #[derive(Debug, thiserror::Error)]
    pub enum WriteError {
        #[error("invalid font")]
        InvalidFont,
        #[error("{0:?}")]
        Serialization(Box<krilla::error::KrillaError>),
    }

    pub struct Writer {
        doc: krilla::Document,
    }

    impl Writer {
        pub fn new_with_language(
            settings: krilla::SerializeSettings,
            meta: Metadata,
            language: Option<String>,
        ) -> Self {
            let mut doc = krilla::Document::new_with(settings);
            let mut m = krilla::metadata::Metadata::new()
                .creator(meta.creator)
                .producer(meta.producer);
            if let Some(t) = meta.title {
                m = m.title(t);
            }
            if !meta.authors.is_empty() {
                m = m.authors(meta.authors);
            }
            if let Some(d) = meta.description {
                m = m.description(d);
            }
            if !meta.keywords.is_empty() {
                m = m.keywords(meta.keywords);
            }
            if let Some(lang) = language {
                m = m.language(lang);
            }
            if let Some(c) = meta.created {
                m = m.creation_date(c);
            }
            doc.set_metadata(m);
            Self { doc }
        }

        pub fn document_mut(&mut self) -> &mut krilla::Document {
            &mut self.doc
        }

        pub fn finish(self) -> Result<Vec<u8>, WriteError> {
            self.doc
                .finish()
                .map_err(|e| WriteError::Serialization(Box::new(e)))
        }
    }

    pub fn guard<T>(f: impl FnOnce() -> Result<T, super::PdfError>) -> Result<T, super::PdfError> {
        std::panic::catch_unwind(std::panic::AssertUnwindSafe(f))
            .unwrap_or_else(|_| Err(super::PdfError::Write("internal PDF writer panic".into())))
    }

    pub fn font(
        data: &[u8],
        index: u32,
        variations: Option<&[([u8; 4], f32)]>,
    ) -> Result<krilla::text::Font, WriteError> {
        let data: krilla::Data = data.to_vec().into();
        let font = match variations {
            Some(coords) => {
                let coords: Vec<(krilla::text::Tag, f32)> = coords
                    .iter()
                    .map(|(t, v)| (krilla::text::Tag::new(t), *v))
                    .collect();
                krilla::text::Font::new_variable(data, index, &coords)
            }
            None => krilla::text::Font::new(data, index),
        };
        font.ok_or(WriteError::InvalidFont)
    }

    pub fn uri_target(target: &str) -> Option<krilla::annotation::Target> {
        let lower = target.trim().to_ascii_lowercase();
        if lower.starts_with("http://")
            || lower.starts_with("https://")
            || lower.starts_with("mailto:")
        {
            Some(krilla::annotation::Target::Action(
                krilla::action::Action::Link(krilla::action::LinkAction::new(target.to_string())),
            ))
        } else {
            None
        }
    }
}

pub(crate) use krilla;
use write::{Metadata, WriteError, Writer};
use krilla::annotation::{Annotation, LinkAnnotation, Target};
use krilla::color::rgb;
use krilla::destination::XyzDestination;
use krilla::error::KrillaError;
use krilla::geom::{Path, PathBuilder, Point, Size, Transform};
use krilla::image::Image;
use krilla::metadata::DateTime;
use krilla::num::NormalizedF32;
use krilla::outline::{Outline, OutlineNode};
use krilla::page::PageSettings;
use krilla::paint::{Fill, FillRule, LineCap, LineJoin, Stroke, StrokeDash};
use krilla::surface::Surface;
use krilla::tagging::{Artifact, ArtifactType, ContentTag, Identifier, Node, SpanTag, Tag, TagGroup, TagKind, TagTree};
use krilla::text::{Font, GlyphId, KrillaGlyph};
use wordcraft_doc::graphic::GraphicKind;
use wordcraft_doc::para::{InlineObject, ShapeKind};
use wordcraft_doc::{Document, Path as DocPath, Rgb, StoryRef};
use wordcraft_fonts::FaceRef;
use wordcraft_geom::Rect;
use wordcraft_layout::display::Paint;
use wordcraft_layout::display::{DisplayOptions, Draw, ItemDisplay, Stroke as LineStyle};
use wordcraft_layout::para::{ClKind, LineEnd};
use wordcraft_layout::{DocLayout, LayoutCache, LayoutOptions, NumeralMode, Page, Placed, layout};
use wordcraft_metafile::{Picture, PlacedItem};

mod export;
mod exporter;
mod glyphs;
mod metadata;
mod options;
mod paint;
mod picture;
mod tags;

#[cfg(test)]
use export::Fit;
pub use export::{export, export_layout};
#[cfg(test)]
use exporter::Exporter;
#[cfg(test)]
use glyphs::{baseline, cluster_ends, left_to_right, split_clusters, visual_order};
#[cfg(test)]
use metadata::{civil, parse_iso};
pub use options::{PdfError, PdfOptions};
#[cfg(test)]
use paint::shape_path;
#[cfg(test)]
use picture::{load_image, load_image_within};

#[cfg(test)]
mod tests;

#[cfg(test)]
mod fill_alpha_tests;
