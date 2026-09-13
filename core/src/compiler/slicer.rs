use lopdf::{Document, Object, ObjectId};
use crate::compiler::engine::CompileError;

pub const DEFAULT_SLICE_HEIGHT: f64 = 1200.0;

/// Slices oversized continuous pages in a PDF document into vertically adjacent page slices.
///
/// For fluid layout documents (which Typst compiles as a single continuous page of height `auto`),
/// this slices the document into pages of `max_slice_height` (e.g. 1200pt).
/// All slices share the identical underlying content stream, fonts, and resources with zero re-encoding,
/// while setting their respective `MediaBox` and `CropBox` viewports.
pub fn slice_continuous_pdf(pdf_bytes: &[u8], max_slice_height: f64) -> Result<Vec<u8>, CompileError> {
    let mut doc = Document::load_mem(pdf_bytes)
        .map_err(|e| CompileError::Pdf(format!("Failed to parse PDF for slicing: {:?}", e)))?;

    let pages = doc.get_pages();
    let mut needs_slicing = false;

    for &page_id in pages.values() {
        if let Ok(page_dict) = doc.get_dictionary(page_id) {
            if let Ok(media_box) = page_dict.get(b"MediaBox") {
                if let Ok(arr) = media_box.as_array() {
                    if arr.len() == 4 {
                        let y1 = arr[1].as_float().unwrap_or(0.0) as f64;
                        let y2 = arr[3].as_float().unwrap_or(0.0) as f64;
                        let height = (y2 - y1).abs();
                        if height > max_slice_height + 50.0 {
                            needs_slicing = true;
                            break;
                        }
                    }
                }
            }
        }
    }

    if !needs_slicing {
        return Ok(pdf_bytes.to_vec());
    }

    // Perform slicing
    let mut new_page_objects: Vec<(ObjectId, Vec<ObjectId>)> = Vec::new();

    for (_page_num, &page_id) in pages.iter() {
        let page_dict = doc.get_dictionary(page_id)
            .map_err(|e| CompileError::Pdf(format!("Invalid page dict: {:?}", e)))?
            .clone();

        let media_box = page_dict.get(b"MediaBox")
            .map_err(|e| CompileError::Pdf(format!("Missing MediaBox: {:?}", e)))?;
        let arr = media_box.as_array()
            .map_err(|e| CompileError::Pdf(format!("MediaBox not array: {:?}", e)))?;

        let x1 = arr[0].as_float().unwrap_or(0.0) as f64;
        let y1 = arr[1].as_float().unwrap_or(0.0) as f64;
        let x2 = arr[2].as_float().unwrap_or(0.0) as f64;
        let y2 = arr[3].as_float().unwrap_or(0.0) as f64;

        let _width = (x2 - x1).abs();
        let total_height = (y2 - y1).abs();
        let min_y = y1.min(y2);
        let max_y = y1.max(y2);

        if total_height <= max_slice_height + 50.0 {
            new_page_objects.push((page_id, vec![page_id]));
            continue;
        }

        let num_slices = ((total_height / max_slice_height).ceil() as usize).max(1);
        let mut slice_ids = Vec::new();

        // Original annotations if present
        let original_annots = page_dict.get(b"Annots").ok().and_then(|a| {
            if let Ok(arr) = a.as_array() {
                Some(arr.clone())
            } else if let Ok(annot_id) = a.as_reference() {
                doc.get_object(annot_id).and_then(|obj| obj.as_array()).ok().cloned()
            } else {
                None
            }
        });

        for i in 0..num_slices {
            let slice_top = max_y - (i as f64) * max_slice_height;
            let slice_bottom = (max_y - ((i + 1) as f64) * max_slice_height).max(min_y);

            let mut slice_dict = page_dict.clone();
            let new_box = Object::Array(vec![
                Object::Real(x1 as f32),
                Object::Real(slice_bottom as f32),
                Object::Real(x2 as f32),
                Object::Real(slice_top as f32),
            ]);

            slice_dict.set("MediaBox", new_box.clone());
            slice_dict.set("CropBox", new_box);

            // Filter annotations that intersect this slice
            if let Some(ref annots) = original_annots {
                let mut slice_annots = Vec::new();
                for annot_ref in annots {
                    let annot_obj = match annot_ref {
                        Object::Reference(id) => doc.get_object(*id).ok(),
                        _ => Some(annot_ref),
                    };

                    if let Some(annot_obj) = annot_obj {
                        if let Ok(annot_dict) = annot_obj.as_dict() {
                            if let Ok(rect_arr) = annot_dict.get(b"Rect").and_then(|r| r.as_array()) {
                                if rect_arr.len() == 4 {
                                    let ay1 = rect_arr[1].as_float().unwrap_or(0.0) as f64;
                                    let ay2 = rect_arr[3].as_float().unwrap_or(0.0) as f64;
                                    let a_bottom = ay1.min(ay2);
                                    let a_top = ay1.max(ay2);
                                    if a_top >= slice_bottom && a_bottom <= slice_top {
                                        slice_annots.push(annot_ref.clone());
                                    }
                                }
                            }
                        }
                    }
                }
                slice_dict.set("Annots", Object::Array(slice_annots));
            }

            let new_id = doc.add_object(Object::Dictionary(slice_dict));
            slice_ids.push(new_id);
        }

        new_page_objects.push((page_id, slice_ids));
    }

    // Now update the Pages tree in the PDF
    // Find all Pages parent nodes and replace old page references with new slice references
    for (old_page_id, new_slice_ids) in new_page_objects {
        if new_slice_ids.len() == 1 && new_slice_ids[0] == old_page_id {
            continue;
        }

        // Find parent of old_page_id
        if let Ok(page_dict) = doc.get_dictionary(old_page_id) {
            if let Some(parent_ref) = page_dict.get(b"Parent").ok().and_then(|p| match p {
                Object::Reference(id) => Some(*id),
                _ => None,
            }) {
                if let Ok(parent_dict) = doc.get_dictionary_mut(parent_ref) {
                    if let Ok(kids) = parent_dict.get_mut(b"Kids").and_then(|k| k.as_array_mut()) {
                        if let Some(pos) = kids.iter().position(|k| match k {
                            Object::Reference(id) => *id == old_page_id,
                            _ => false,
                        }) {
                            kids.remove(pos);
                            for (insert_idx, slice_id) in new_slice_ids.into_iter().enumerate() {
                                kids.insert(pos + insert_idx, Object::Reference(slice_id));
                            }
                        }
                    }
                    // Update /Count in parent
                    let mut total_count = 0;
                    if let Ok(kids) = parent_dict.get(b"Kids").and_then(|k| k.as_array()) {
                        total_count = kids.len() as i64;
                    }
                    parent_dict.set("Count", Object::Integer(total_count));
                }
            }
        }
        // Remove old page object
        doc.objects.remove(&old_page_id);
    }

    // Also verify root Pages count in catalog
    if let Ok(catalog) = doc.catalog() {
        if let Ok(pages_ref) = catalog.get(b"Pages").and_then(|p| p.as_reference()) {
            let page_count = doc.get_pages().len() as i64;
            if let Ok(pages_dict) = doc.get_dictionary_mut(pages_ref) {
                pages_dict.set("Count", Object::Integer(page_count));
            }
        }
    }

    let mut output = Vec::new();
    doc.save_to(&mut output)
        .map_err(|e| CompileError::Pdf(format!("Failed to serialize sliced PDF: {:?}", e)))?;

    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_slice_pdf_roundtrip() {
        let pdf_path = std::path::Path::new("../test_prd.pdf");
        if pdf_path.exists() {
            let bytes = std::fs::read(pdf_path).expect("Read test_prd.pdf");
            let sliced = slice_continuous_pdf(&bytes, 1200.0).expect("Slice PDF");
            assert!(sliced.starts_with(b"%PDF-"));

            let _ = std::fs::write("/tmp/rust_sliced.pdf", &sliced);
            let doc = Document::load_mem(&sliced).expect("Load sliced PDF");
            let pages = doc.get_pages();
            assert!(pages.len() > 1, "Should have sliced into multiple pages, got {}", pages.len());
            println!("Successfully sliced test_prd.pdf into {} pages!", pages.len());
        }
    }
}
