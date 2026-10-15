#!/usr/bin/env python3
"""
General-Purpose PDF Reflow Engine for SuperGoodViewer
=====================================================
A unified, adaptive reflow engine that converts ANY standard A4/Letter PDF
(Academic papers, financial reports, manuals, books) into an elegant,
mobile-optimized vector PDF (108mm x 195mm).

Pipeline:
1. Document Profiler: Statistical clustering of font sizes, weights, and CJK/Latin detection.
2. Layout & Column Detector: Automatic multi-column uncurling and reading order resolution.
3. Asset & Fidelity Island Extractor: High-DPI figure extraction with alpha preservation.
4. Semantic Block Assembler: Hyphen unwrapping, cross-page stitching, bullet & heading classification.
5. Typst Generator & Vector Compiler: Generates Typst AST with native bookmarks, compiles to PDF.
"""

import os
import sys
import re
import argparse
import subprocess
from collections import Counter
import pymupdf

def is_cjk_char(ch):
    cp = ord(ch)
    return (0x4E00 <= cp <= 0x9FFF) or (0x3400 <= cp <= 0x4DBF) or (0xF900 <= cp <= 0xFAFF) or (0x3000 <= cp <= 0x303F) or (0xFF00 <= cp <= 0xFFEF)

def detect_language(doc, sample_pages=5):
    """Detects whether document is primarily CJK or Latin."""
    cjk_count = 0
    total_count = 0
    pages_to_check = min(len(doc), sample_pages)
    for i in range(pages_to_check):
        text = doc[i].get_text()
        for ch in text:
            if not ch.isspace():
                total_count += 1
                if is_cjk_char(ch):
                    cjk_count += 1
    if total_count == 0:
        return 'latin'
    ratio = cjk_count / total_count
    return 'cjk' if ratio > 0.15 else 'latin'

def profile_document_fonts(doc):
    """
    Scans the document to discover the typographical hierarchy:
    Body font size (statistical mode), H1, H2, H3, and Title sizes.
    """
    size_counter = Counter()
    for page in doc:
        blocks = page.get_text('dict')['blocks']
        for b in blocks:
            if 'lines' in b:
                for l in b['lines']:
                    for s in l['spans']:
                        text = s['text'].strip()
                        if len(text) > 1:
                            size_counter[round(s['size'], 1)] += len(text)
                            
    if not size_counter:
        return {'body': 10.0, 'h1': 14.0, 'h2': 12.0, 'h3': 11.0, 'title': 16.0}
        
    body_size = size_counter.most_common(1)[0][0]
    larger_sizes = sorted([s for s in size_counter.keys() if s > body_size * 1.05])
    
    # Classify sizes
    h3_size = body_size * 1.08
    h2_size = body_size * 1.18
    h1_size = body_size * 1.35
    title_size = body_size * 1.55
    
    if larger_sizes:
        if len(larger_sizes) == 1:
            h1_size = larger_sizes[0]
            h2_size = larger_sizes[0]
        elif len(larger_sizes) == 2:
            h2_size = larger_sizes[0]
            h1_size = larger_sizes[1]
            title_size = larger_sizes[1]
        elif len(larger_sizes) >= 3:
            h3_size = larger_sizes[0]
            h2_size = larger_sizes[1]
            h1_size = larger_sizes[2]
            title_size = larger_sizes[-1]
            
    return {
        'body': body_size,
        'h3': h3_size,
        'h2': h2_size,
        'h1': h1_size,
        'title': title_size
    }

def detect_column_layout(page):
    """
    Determines if a page is 2-column or 1-column layout based on horizontal clustering.
    Returns list of blocks in proper reading order.
    """
    rect = page.rect
    mid_x = rect.width / 2.0
    blocks = page.get_text('dict')['blocks']
    
    # Filter valid text blocks
    text_blocks = []
    for b in blocks:
        if 'lines' in b and b['lines']:
            # Ignore running headers (top 4%) and footers (bottom 4%)
            y0 = b['bbox'][1]
            y1 = b['bbox'][3]
            if y0 < rect.height * 0.04 or y1 > rect.height * 0.96:
                continue
            text_blocks.append(b)
            
    if not text_blocks:
        return text_blocks
        
    # Check if blocks span across both left and right columns
    left_blocks = [b for b in text_blocks if b['bbox'][2] < mid_x + 20 and b['bbox'][0] < mid_x - 30]
    right_blocks = [b for b in text_blocks if b['bbox'][0] > mid_x - 20 and b['bbox'][2] > mid_x + 30]
    spanning_blocks = [b for b in text_blocks if b['bbox'][0] < mid_x - 30 and b['bbox'][2] > mid_x + 30]
    
    # If substantial blocks exist in both columns, it's a 2-column layout
    is_two_column = (len(left_blocks) >= 2 and len(right_blocks) >= 2)
    
    if is_two_column:
        # Reading order: Spanning blocks at top -> Left column -> Right column -> Spanning blocks at bottom
        top_spanning = [b for b in spanning_blocks if b['bbox'][1] < rect.height * 0.4]
        bottom_spanning = [b for b in spanning_blocks if b['bbox'][1] >= rect.height * 0.4]
        
        top_spanning.sort(key=lambda b: b['bbox'][1])
        left_blocks.sort(key=lambda b: b['bbox'][1])
        right_blocks.sort(key=lambda b: b['bbox'][1])
        bottom_spanning.sort(key=lambda b: b['bbox'][1])
        
        return top_spanning + left_blocks + right_blocks + bottom_spanning
    else:
        # Single column layout: simple top-to-bottom sorting
        text_blocks.sort(key=lambda b: (b['bbox'][1], b['bbox'][0]))
        return text_blocks

def clean_typst_text(text):
    """Escapes special Typst markup characters and cleans invalid control characters."""
    text = text.replace('\x00', '')
    text = text.replace('\\', '\\\\')
    text = text.replace('#', '\\#')
    text = text.replace('$', '\\$')
    text = text.replace('@', '\\@')
    text = text.replace('*', '\\*')
    text = text.replace('_', '\\_')
    text = text.replace('<', '\\<')
    text = text.replace('>', '\\>')
    text = text.replace('`', '\\`')
    return text

def join_text_flow(t1, t2, is_cjk):
    """Language-aware text joining with hyphenation and CJK unwrapping."""
    if not t1: return t2
    if not t2: return t1
    
    # Handle English hyphenation: e.g. "multi-" + "head" -> "multi-head" or "dimen-" + "sion" -> "dimension"
    if t1.endswith('-'):
        # Check if it was a line-break hyphenation of a single word
        word_before = t1[:-1].split()[-1] if t1[:-1].split() else ""
        word_after = t2.split()[0] if t2.split() else ""
        if word_before.isalpha() and word_after.isalpha():
            return t1[:-1] + t2
        return t1 + t2
        
    c1 = t1[-1]
    c2 = t2[0]
    
    if is_cjk:
        if is_cjk_char(c1) or is_cjk_char(c2):
            return t1 + t2
        return t1 + ' ' + t2
    else:
        return t1 + ' ' + t2

def extract_document_elements(pdf_path, assets_dir):
    doc = pymupdf.open(pdf_path)
    lang = detect_language(doc)
    is_cjk = (lang == 'cjk')
    font_hierarchy = profile_document_fonts(doc)
    
    os.makedirs(assets_dir, exist_ok=True)
    elements = []
    
    # Step 1: Extract Images with Alpha Mask Compositing
    image_count = 0
    page_images = {}
    for pno in range(len(doc)):
        page = doc[pno]
        imgs = page.get_images(full=True)
        img_list = []
        for img_idx, img_info in enumerate(imgs):
            xref = img_info[0]
            smask = img_info[1]
            try:
                pix = pymupdf.Pixmap(doc, xref)
                # Convert CMYK / other color spaces to RGB
                if pix.n >= 5:
                    pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
                if smask > 0:
                    mask = pymupdf.Pixmap(doc, smask)
                    pix = pymupdf.Pixmap(pix, mask)
                w, h = pix.width, pix.height
                if w > 80 and h > 80:
                    img_filename = f"fig_p{pno+1}_{img_idx}_{w}x{h}.png"
                    img_path = os.path.join(assets_dir, img_filename)
                    if not os.path.exists(img_path):
                        pix.save(img_path)
                    img_list.append(img_filename)
                    image_count += 1
            except Exception:
                pass
        page_images[pno] = img_list
        
    # Clean up asset dir if no images found
    if image_count == 0 and os.path.exists(assets_dir) and not os.listdir(assets_dir):
        try:
            os.rmdir(assets_dir)
        except OSError:
            pass
        
    # Step 2: Extract Text and Semantic Elements
    cur_bullet = None
    cur_paragraph = None
    
    def flush_block():
        nonlocal cur_bullet, cur_paragraph
        if cur_bullet:
            elements.append(cur_bullet)
            cur_bullet = None
        if cur_paragraph:
            elements.append(cur_paragraph)
            cur_paragraph = None
            
    for pno in range(len(doc)):
        page = doc[pno]
        ordered_blocks = detect_column_layout(page)
        
        # Check if page has images to insert at the top/appropriate place
        if pno in page_images and page_images[pno]:
            flush_block()
            for img_file in page_images[pno]:
                elements.append({'type': 'image', 'path': img_file, 'page': pno + 1})
                
        for b in ordered_blocks:
            # Group lines inside block
            for l in b['lines']:
                line_spans = l['spans']
                if not line_spans:
                    continue
                    
                line_text = ''.join([s['text'] for s in line_spans]).strip()
                if not line_text:
                    continue
                    
                # Inspect font size and weight
                max_size = max([s['size'] for s in line_spans])
                is_bold = any(['Bold' in s['font'] or 'bold' in s['font'].lower() or s['flags'] & 2 != 0 for s in line_spans])
                
                # Title detection (on page 1)
                if pno == 0 and max_size >= font_hierarchy['title'] * 0.95 and len(line_text) < 120:
                    flush_block()
                    elements.append({'type': 'title', 'text': line_text, 'page': pno + 1})
                    continue
                    
                # Heading 1 detection
                if (max_size >= font_hierarchy['h1'] * 0.95 or (is_bold and max_size >= font_hierarchy['h2'] * 1.05)) and len(line_text) < 100:
                    flush_block()
                    elements.append({'type': 'h1', 'text': line_text, 'page': pno + 1})
                    continue
                    
                # Heading 2 detection
                if ((max_size >= font_hierarchy['h2'] * 0.95 and is_bold) or (is_bold and len(line_text) < 50 and not line_text.endswith('.'))):
                    # Check if it looks like a heading
                    if not line_text.endswith(('。', '，', ',', '.')) and len(line_text) < 60:
                        flush_block()
                        elements.append({'type': 'h2', 'text': line_text, 'page': pno + 1})
                        continue
                        
                # Heading 3 / Topic badge detection (e.g. starts with Ø, 1.1, etc.)
                if (line_text.startswith('Ø') or re.match(r'^\d+\.\d+\s+', line_text)) and len(line_text) < 50:
                    flush_block()
                    topic = re.sub(r'^[Ø\s]+', '', line_text).strip()
                    elements.append({'type': 'h3', 'text': topic, 'page': pno + 1})
                    continue
                    
                # Bullet list item detection
                m_bullet = re.match(r'^(?:[•●○on\-\*]|(?:\d+[\.\)]))\s+(.*)', line_text)
                if m_bullet:
                    flush_block()
                    cur_bullet = {'type': 'bullet', 'text': m_bullet.group(1).strip(), 'page': pno + 1}
                    continue
                    
                # Continuation or regular paragraph
                if cur_bullet:
                    cur_bullet['text'] = join_text_flow(cur_bullet['text'], line_text, is_cjk)
                elif cur_paragraph:
                    cur_paragraph['text'] = join_text_flow(cur_paragraph['text'], line_text, is_cjk)
                else:
                    cur_paragraph = {'type': 'paragraph', 'text': line_text, 'page': pno + 1}
                    
            # End of block: soft paragraph break if it ends with punctuation
            if cur_paragraph and cur_paragraph['text'].endswith(('.', '。', '!', '！', '?', '？', ':')):
                flush_block()
                
        flush_block()
        
    return {
        'lang': lang,
        'is_cjk': is_cjk,
        'fonts': font_hierarchy,
        'elements': elements,
        'image_count': image_count
    }

def generate_typst_document(doc_data, assets_dir_rel, output_typ_path, doc_title="Mobile Document"):
    is_cjk = doc_data['is_cjk']
    elements = doc_data['elements']
    
    font_family = '("PingFang SC", "Heiti SC", "Microsoft YaHei", "Noto Sans CJK SC", "Arial")' if is_cjk else '("Linux Libertine", "Times New Roman", "DejaVu Serif")'
    body_size = "9.6pt" if is_cjk else "9.8pt"
    leading = "0.72em" if is_cjk else "0.62em"
    spacing = "0.85em" if is_cjk else "0.75em"
    bullet_marker = 'text(size: 7.2pt, fill: rgb("#3b82f6"))[●]' if is_cjk else 'text(size: 7.5pt, fill: rgb("#475569"))[•]'
    
    lines = []
    lines.append(f"""// ========================================================
// Auto-generated by SuperGoodViewer General Reflow Engine
// ========================================================

#set document(title: "{clean_typst_text(doc_title)}", author: "SuperGoodViewer")

// 手机视口规范：108mm x 195mm (标准 9:16.25 移动阅读比例)
#set page(
  width: 108mm,
  height: 195mm,
  margin: (top: 12mm, bottom: 10mm, x: 8.5mm),
  header: context {{
    let p = counter(page).get().first()
    if p > 1 [
      #grid(
        columns: (1fr, 1fr),
        align: (left, right),
        text(size: 6.8pt, fill: rgb("#94a3b8"))[{clean_typst_text(doc_title)[:30]}],
        text(size: 6.8pt, fill: rgb("#94a3b8"))[#p]
      )
      #v(-2mm)
      #line(length: 100%, stroke: 0.3pt + rgb("#e2e8f0"))
    ]
  }},
  footer: none
)

#set text(
  font: {font_family},
  size: {body_size},
  fill: rgb("#1e293b"),
  lang: "{"zh" if is_cjk else "en"}"
)

#set par(
  leading: {leading},
  spacing: {spacing},
  justify: true
)

// ---------- STICKY HEADINGS & PDF BOOKMARKS ----------
#show heading.where(level: 1): it => block(
  width: 100%,
  fill: rgb("#1e3a8a"),
  inset: (x: 3.5mm, y: 2.2mm),
  radius: 3pt,
)[#text(size: 11pt, weight: "bold", fill: white)[#it.body]]

#show heading.where(level: 2): it => block(
  inset: (top: 2.5mm, bottom: 1mm),
)[
  #rect(
    fill: rgb("#eff6ff"),
    radius: 2pt,
    inset: (x: 2mm, y: 1.2mm),
    stroke: (left: 2.5pt + rgb("#2563eb"))
  )[
    #text(size: 10pt, weight: "bold", fill: rgb("#1d4ed8"))[#it.body]
  ]
]

#show heading.where(level: 3): it => block(
  inset: (top: 1.8mm, bottom: 0.8mm),
)[
  #text(size: 8.8pt, weight: "bold", fill: rgb("#475569"))[◆ #it.body]
]

#set list(
  marker: {bullet_marker},
  body-indent: 1.8mm,
  spacing: 0.8em
)
""")

    title_rendered = False
    for el in elements:
        el_type = el['type']
        
        if el_type == 'image':
            img_rel_path = os.path.join(assets_dir_rel, el['path'])
            lines.append(f"""
#align(center)[
  #figure(
    image("{img_rel_path}", width: 95%),
    caption: none
  )
]
""")
            continue
            
        t = clean_typst_text(el['text'])
        if not t:
            continue
            
        if el_type == 'title':
            if not title_rendered:
                lines.append(f"""
#align(center)[
  #v(2mm)
  #text(size: 14pt, weight: "bold", fill: rgb("#0f172a"))[{t}]
  #v(2mm)
]
""")
                title_rendered = True
            else:
                lines.append(f"""#heading(level: 1)[{t}]""")
        elif el_type == 'h1':
            lines.append(f"""#heading(level: 1)[{t}]""")
        elif el_type == 'h2':
            lines.append(f"""#heading(level: 2)[{t}]""")
        elif el_type == 'h3':
            lines.append(f"""#heading(level: 3)[{t}]""")
        elif el_type == 'bullet':
            lines.append(f"""#list.item[{t}]""")
        elif el_type == 'paragraph':
            lines.append(f"""{t}\n""")
            
    with open(output_typ_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Generated Typst code at: {output_typ_path}")

def reflow_pdf(input_pdf, output_pdf=None):
    if not os.path.exists(input_pdf):
        print(f"Error: File not found: {input_pdf}")
        sys.exit(1)
        
    input_abs = os.path.abspath(input_pdf)
    base_name = os.path.splitext(os.path.basename(input_abs))[0]
    
    if not output_pdf:
        output_dir = os.path.dirname(input_abs)
        output_pdf = os.path.join(output_dir, f"{base_name}_mobile.pdf")
    else:
        output_pdf = os.path.abspath(output_pdf)
        output_dir = os.path.dirname(output_pdf)
        
    os.makedirs(output_dir, exist_ok=True)
    
    stem = os.path.splitext(output_pdf)[0]
    typ_path = f"{stem}.typ"
    assets_dir = f"{stem}_assets"
    assets_rel = os.path.relpath(assets_dir, output_dir)
    
    print(f"[1/4] Analyzing layout & extracting content from: {input_abs}")
    doc_data = extract_document_elements(input_abs, assets_dir)
    print(f"      Language: {doc_data['lang'].upper()} | Body Size: {doc_data['fonts']['body']}pt | Images: {doc_data['image_count']} | Elements: {len(doc_data['elements'])}")
    
    print(f"[2/4] Generating Typst mobile AST...")
    generate_typst_document(doc_data, assets_rel, typ_path, doc_title=base_name.replace('_', ' ').title())
    
    print(f"[3/4] Compiling vector mobile PDF via Typst...")
    cmd = ["typst", "compile", typ_path, output_pdf]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print("Typst compile error:")
        print(res.stderr)
        sys.exit(1)
        
    file_size_kb = os.path.getsize(output_pdf) / 1024.0
    print(f"[4/4] Success! Output mobile PDF: {output_pdf} ({file_size_kb:.1f} KB)")
    return output_pdf

def main():
    parser = argparse.ArgumentParser(description="General-purpose PDF Mobile Reflow Engine")
    parser.add_argument("input_pdf", help="Path to input PDF file (A4, Letter, etc.)")
    parser.add_argument("-o", "--output", help="Path to output mobile reflow PDF", default=None)
    args = parser.parse_args()
    
    reflow_pdf(args.input_pdf, args.output)

if __name__ == "__main__":
    main()
