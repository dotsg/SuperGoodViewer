import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'pdf_page_analysis_service.dart';

/// Semantic element type classified by the client-side PDF reflow engine.
enum ReflowElementType {
  title,
  h1,
  h2,
  h3,
  bullet,
  paragraph,
}

/// A structured semantic block extracted from a PDF document.
class ReflowElement {
  final ReflowElementType type;
  String text;
  final int pageNumber;

  ReflowElement({
    required this.type,
    required this.text,
    required this.pageNumber,
  });
}

/// Result of client-side PDF reflow analysis and Markdown generation.
class PdfReflowResult {
  final String markdown;
  final List<ReflowElement> elements;
  final bool isCjk;
  final double bodyFontSize;
  final int pageCount;

  const PdfReflowResult({
    required this.markdown,
    required this.elements,
    required this.isCjk,
    required this.bodyFontSize,
    required this.pageCount,
  });

  bool get hasContent => elements.isNotEmpty && markdown.trim().isNotEmpty;
}

class _VisualFragment {
  final Rect rect;
  final String text;

  const _VisualFragment({required this.rect, required this.text});
}

class _VisualLine {
  final Rect bounds;
  final String text;
  final double maxHeight;

  const _VisualLine({
    required this.bounds,
    required this.text,
    required this.maxHeight,
  });
}

/// Client-side PDF Reflow Service for SuperGoodViewer.
///
/// Converts standard A4 / Letter / multi-column PDFs into clean, mobile-friendly
/// structured Markdown on-device using PDFium (`pdfrx`) text geometry and
/// [PdfPageAnalysisService] column detection, which is then compiled by the
/// native Rust Typst engine into a responsive Fluid or Paged document.
class PdfReflowService {
  static final Map<int, PdfReflowResult> _cache = {};
  static const int _maxCacheEntries = 6;

  /// Clears the in-memory reflow cache.
  static void clearCache() => _cache.clear();

  /// Returns true if [codeUnit] is a CJK unified ideograph or punctuation character.
  static bool isCjkCodeUnit(int cp) {
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0x3000 && cp <= 0x303F) ||
        (cp >= 0xFF00 && cp <= 0xFFEF);
  }

  /// Detects whether a collection of text samples is primarily CJK (>15% CJK chars).
  static bool detectIsCjk(Iterable<String> samples) {
    int cjkCount = 0;
    int totalCount = 0;
    for (final sample in samples) {
      for (final rune in sample.runes) {
        if (rune <= 0x20 || rune == 0xA0) continue;
        totalCount++;
        if (isCjkCodeUnit(rune)) {
          cjkCount++;
        }
      }
    }
    if (totalCount == 0) return false;
    return (cjkCount / totalCount) > 0.15;
  }

  /// Language-aware line joining with English hyphenation unwrapping and CJK stitching.
  static String joinTextFlow(String t1, String t2, {required bool isCjk}) {
    final a = t1.trimRight();
    final b = t2.trimLeft();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;

    // Unwrap English line-break hyphenation (e.g. "dimen-" + "sion" -> "dimension")
    if (a.endsWith('-') || a.endsWith('\u00AD')) {
      final prefix = a.substring(0, a.length - 1);
      final lastSpace = prefix.lastIndexOf(' ');
      final wordBefore = lastSpace == -1 ? prefix : prefix.substring(lastSpace + 1);
      final firstSpace = b.indexOf(' ');
      final wordAfter = firstSpace == -1 ? b : b.substring(0, firstSpace);
      final alphaRegex = RegExp(r'^[a-zA-Z]+$');
      if (alphaRegex.hasMatch(wordBefore) && alphaRegex.hasMatch(wordAfter)) {
        // Keep hyphen for compound modifiers like "multi-head" or capitalized second part
        final lowerBefore = wordBefore.toLowerCase();
        const compoundPrefixes = {
          'multi',
          'self',
          'cross',
          'non',
          'pre',
          'post',
          'sub',
          'co',
          'inter',
          'intra',
          'semi',
          'high',
          'low',
          'real',
          'end',
          'state',
          'fine',
          'zero',
          'one',
          'two',
          'three',
        };
        if (compoundPrefixes.contains(lowerBefore) ||
            (wordAfter.isNotEmpty &&
                wordAfter[0] == wordAfter[0].toUpperCase() &&
                wordAfter[0] != wordAfter[0].toLowerCase())) {
          return '$prefix-$b';
        }
        return '$prefix$b';
      }
      return '$a$b';
    }

    final lastRune = a.runes.last;
    final firstRune = b.runes.first;
    if (isCjk && (isCjkCodeUnit(lastRune) || isCjkCodeUnit(firstRune))) {
      return '$a$b';
    }
    return '$a $b';
  }

  /// Escapes characters in raw PDF text that could be misinterpreted as broken
  /// Markdown or LaTeX math syntax while preserving readable prose.
  static String escapeMarkdownSpan(String input) {
    final cleaned = input
        .replaceAll('\x00', '')
        .replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F]'), '')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';

    final sb = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      final ch = cleaned[i];
      switch (ch) {
        case r'\':
          sb.write(r'\\');
        case r'$':
          sb.write(r'\$');
        case '*':
          sb.write(r'\*');
        case '_':
          sb.write(r'\_');
        case '`':
          sb.write(r'\`');
        case '<':
          sb.write('&lt;');
        case '>':
          sb.write('&gt;');
        case '[':
          sb.write(r'\[');
        case ']':
          sb.write(r'\]');
        case '~':
          sb.write(r'\~');
        default:
          sb.write(ch);
      }
    }
    var result = sb.toString();
    if (result.startsWith('#')) {
      result = '\\$result';
    }
    return result;
  }

  /// Extracts and reflows a PDF byte buffer into structured Markdown.
  static Future<PdfReflowResult> reflowPdfBytes(
    Uint8List pdfBytes, {
    String? documentTitle,
  }) async {
    final cacheKey = Object.hash(pdfBytes.length, identityHashCode(pdfBytes), documentTitle);
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final doc = await PdfDocument.openData(pdfBytes);
    try {
      final result = await reflowDocument(doc, documentTitle: documentTitle);
      if (result.hasContent) {
        _cache[cacheKey] = result;
        if (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return result;
    } finally {
      await doc.dispose();
    }
  }

  /// Extracts and reflows an already opened [PdfDocument] into structured Markdown.
  static Future<PdfReflowResult> reflowDocument(
    PdfDocument doc, {
    String? documentTitle,
  }) async {
    if (doc.pages.isEmpty) {
      return const PdfReflowResult(
        markdown: '',
        elements: [],
        isCjk: false,
        bodyFontSize: 10.0,
        pageCount: 0,
      );
    }

    final unloaded = <int>[
      for (final p in doc.pages)
        if (!p.isLoaded) p.pageNumber,
    ];
    if (unloaded.isNotEmpty) {
      await doc.reloadPages(pageNumbersToReload: unloaded);
    }

    final pageTexts = <PdfPageText>[];
    final pageAnalyses = <PdfPageAnalysis>[];
    final sampleStrings = <String>[];

    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final pageText = await page.loadStructuredText();
      pageTexts.add(pageText);
      pageAnalyses.add(PdfPageAnalysisService.computePageAnalysis(page, pageText));
      if (i < 5 && pageText.fullText.isNotEmpty) {
        sampleStrings.add(pageText.fullText);
      }
    }

    final isCjk = detectIsCjk(sampleStrings);

    // Collect ordered visual lines per page and profile line heights
    final heightHistogram = <double, int>{};
    final pageLinesList = <List<({List<_VisualLine> lines, Rect regionBounds})>>[];

    for (var pno = 0; pno < doc.pages.length; pno++) {
      final page = doc.pages[pno];
      final pageText = pageTexts[pno];
      final analysis = pageAnalyses[pno];
      final regions = _extractOrderedRegionLines(page, pageText, analysis);
      pageLinesList.add(regions);

      for (final region in regions) {
        for (final line in region.lines) {
          final textLen = line.text.trim().length;
          if (textLen > 1 && line.maxHeight > 4.0 && line.maxHeight < 72.0) {
            final bucket = (line.maxHeight * 2).round() / 2.0;
            heightHistogram[bucket] = (heightHistogram[bucket] ?? 0) + textLen;
          }
        }
      }
    }

    double bodyHeight = 10.0;
    if (heightHistogram.isNotEmpty) {
      var bestBucket = 10.0;
      var bestWeight = -1;
      heightHistogram.forEach((bucket, weight) {
        if (weight > bestWeight) {
          bestWeight = weight;
          bestBucket = bucket;
        }
      });
      bodyHeight = bestBucket;
    }

    final largerSizes = heightHistogram.keys
        .where((s) => s > bodyHeight * 1.08 && (heightHistogram[s] ?? 0) >= 4)
        .toList()
      ..sort();

    double h3Size = bodyHeight * 1.10;
    double h2Size = bodyHeight * 1.18;
    double h1Size = bodyHeight * 1.32;
    double titleSize = bodyHeight * 1.50;

    if (largerSizes.length == 1) {
      h1Size = largerSizes[0];
      h2Size = largerSizes[0];
    } else if (largerSizes.length == 2) {
      h2Size = largerSizes[0];
      h1Size = largerSizes[1];
      titleSize = largerSizes[1];
    } else if (largerSizes.length >= 3) {
      h3Size = largerSizes[0];
      h2Size = largerSizes[1];
      h1Size = largerSizes[2];
      titleSize = largerSizes.last;
    }

    final elements = <ReflowElement>[];
    ReflowElement? curBullet;
    ReflowElement? curParagraph;

    void flushBlock() {
      if (curBullet != null) {
        elements.add(curBullet!);
        curBullet = null;
      }
      if (curParagraph != null) {
        elements.add(curParagraph!);
        curParagraph = null;
      }
    }

    final bulletRegex = RegExp(r'^(?:[•●○▪◆Ø\-\*]|(?:\(\d+\))|(?:\d+\)))\s+(.*)$');
    final h1SectionRegex = RegExp(
      r'^(?:(?:Abstract|Introduction|Conclusion|Conclusions|References|Acknowledgments|Acknowledgements|Appendix|摘要|引言|结论|参考文献|致谢)|(?:[IVX]+\.\s+[A-Z].*)|(?:\d+\.?\s+[A-Z\u4e00-\u9fa5].*)|(?:第[一二三四五六七八九十百千万0-9]+[章节篇部]\s*.*))$',
    );
    final h2SectionRegex = RegExp(
      r'^(?:(?:\d+\.\d+(?:\.\d+)?\.?\s+\S+.*)|(?:[一二三四五六七八九十]+、\s*\S+.*)|(?:\([一二三四五六七八九十]+\)\s*\S+.*))$',
    );

    for (var pno = 0; pno < doc.pages.length; pno++) {
      final regions = pageLinesList[pno];
      for (final region in regions) {
        final lines = region.lines;
        final regionRight = region.regionBounds.right;
        double? prevLineBottom;
        double? prevLineRight;

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;

          // Skip isolated page numbers
          if (RegExp(r'^\d{1,4}$').hasMatch(lineText) && lines.length > 2) {
            continue;
          }

          final maxSize = line.maxHeight;
          final verticalGap = prevLineBottom != null ? (line.bounds.top - prevLineBottom) : 0.0;
          final isLargeVerticalGap = prevLineBottom != null && verticalGap > bodyHeight * 0.85;
          final prevWasShortLine = prevLineRight != null &&
              region.regionBounds.width > 100 &&
              (regionRight - prevLineRight) > region.regionBounds.width * 0.22;

          prevLineBottom = line.bounds.bottom;
          prevLineRight = line.bounds.right;

          // 1. Document Title detection on page 1
          if (pno == 0 &&
              maxSize >= math.min(titleSize * 0.94, bodyHeight * 1.42) &&
              lineText.length < 140) {
            flushBlock();
            if (elements.isNotEmpty &&
                elements.last.type == ReflowElementType.title &&
                elements.last.pageNumber == 1) {
              elements.last.text = joinTextFlow(elements.last.text, lineText, isCjk: isCjk);
            } else {
              elements.add(ReflowElement(
                type: ReflowElementType.title,
                text: lineText,
                pageNumber: pno + 1,
              ));
            }
            continue;
          }

          final endsWithSentencePunct = lineText.endsWith('.') ||
              lineText.endsWith('。') ||
              lineText.endsWith(',') ||
              lineText.endsWith('，') ||
              lineText.endsWith(';') ||
              lineText.endsWith('；');

          // 2. Heading 1 detection
          if (!endsWithSentencePunct &&
              lineText.length < 90 &&
              (maxSize >= math.min(h1Size * 0.94, bodyHeight * 1.26) ||
                  (maxSize >= bodyHeight * 1.05 && h1SectionRegex.hasMatch(lineText)))) {
            flushBlock();
            elements.add(ReflowElement(
              type: ReflowElementType.h1,
              text: lineText,
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 3. Heading 2 detection
          if (!endsWithSentencePunct &&
              lineText.length < 80 &&
              ((maxSize >= math.min(h2Size * 0.95, bodyHeight * 1.14) && maxSize >= bodyHeight * 1.08) ||
                  (maxSize >= bodyHeight * 0.96 && h2SectionRegex.hasMatch(lineText)))) {
            flushBlock();
            elements.add(ReflowElement(
              type: ReflowElementType.h2,
              text: lineText,
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 4. Heading 3 detection
          if (!endsWithSentencePunct &&
              lineText.length < 65 &&
              maxSize >= math.min(h3Size * 0.96, bodyHeight * 1.09) &&
              isLargeVerticalGap) {
            flushBlock();
            elements.add(ReflowElement(
              type: ReflowElementType.h3,
              text: lineText,
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 5. Bullet list item detection
          final bulletMatch = bulletRegex.firstMatch(lineText);
          if (bulletMatch != null) {
            flushBlock();
            curBullet = ReflowElement(
              type: ReflowElementType.bullet,
              text: bulletMatch.group(1)!.trim(),
              pageNumber: pno + 1,
            );
            continue;
          }

          // 6. Paragraph boundary check on vertical gap or short preceding line ending in punctuation
          if (isLargeVerticalGap) {
            flushBlock();
          } else if (curParagraph != null &&
              prevWasShortLine &&
              (curParagraph!.text.endsWith('.') ||
                  curParagraph!.text.endsWith('。') ||
                  curParagraph!.text.endsWith('!') ||
                  curParagraph!.text.endsWith('！') ||
                  curParagraph!.text.endsWith('?') ||
                  curParagraph!.text.endsWith('？') ||
                  curParagraph!.text.endsWith(':') ||
                  curParagraph!.text.endsWith('：'))) {
            flushBlock();
          }

          if (curBullet != null) {
            curBullet!.text = joinTextFlow(curBullet!.text, lineText, isCjk: isCjk);
          } else if (curParagraph != null) {
            curParagraph!.text = joinTextFlow(curParagraph!.text, lineText, isCjk: isCjk);
          } else {
            curParagraph = ReflowElement(
              type: ReflowElementType.paragraph,
              text: lineText,
              pageNumber: pno + 1,
            );
          }
        }
        // Flush at the end of a region (e.g., before switching from top spanning to left column)
        if (curParagraph != null &&
            (curParagraph!.text.endsWith('.') ||
                curParagraph!.text.endsWith('。') ||
                curParagraph!.text.endsWith('!') ||
                curParagraph!.text.endsWith('?'))) {
          flushBlock();
        }
      }
    }
    flushBlock();

    final markdown = buildMarkdownFromElements(
      elements,
      documentTitle: documentTitle,
    );

    return PdfReflowResult(
      markdown: markdown,
      elements: elements,
      isCjk: isCjk,
      bodyFontSize: bodyHeight,
      pageCount: doc.pages.length,
    );
  }

  /// Generates clean Markdown from classified [ReflowElement] blocks.
  static String buildMarkdownFromElements(
    List<ReflowElement> elements, {
    String? documentTitle,
  }) {
    if (elements.isEmpty) return '';

    final lines = <String>[];
    bool titleRendered = false;

    for (final el in elements) {
      final escaped = escapeMarkdownSpan(el.text);
      if (escaped.isEmpty) continue;

      switch (el.type) {
        case ReflowElementType.title:
          if (!titleRendered) {
            lines.add('# $escaped\n');
            titleRendered = true;
          } else {
            lines.add('## $escaped\n');
          }
        case ReflowElementType.h1:
          lines.add('## $escaped\n');
        case ReflowElementType.h2:
          lines.add('### $escaped\n');
        case ReflowElementType.h3:
          lines.add('#### $escaped\n');
        case ReflowElementType.bullet:
          lines.add('- $escaped');
        case ReflowElementType.paragraph:
          lines.add('$escaped\n');
      }
    }

    if (!titleRendered && documentTitle != null && documentTitle.trim().isNotEmpty) {
      final cleanTitle = escapeMarkdownSpan(documentTitle.replaceAll('_', ' ').trim());
      if (cleanTitle.isNotEmpty) {
        lines.insert(0, '# $cleanTitle\n');
      }
    }

    return lines.join('\n').trim();
  }

  /// Partitions page fragments into reading-order regions (1-column or uncurled 2-column)
  /// and merges horizontally adjacent fragments into visual lines.
  static List<({List<_VisualLine> lines, Rect regionBounds})> _extractOrderedRegionLines(
    PdfPage page,
    PdfPageText pageText,
    PdfPageAnalysis analysis,
  ) {
    if (pageText.fragments.isEmpty) return const [];

    final pageHeight = page.height;
    final headerCutoff = pageHeight * 0.042;
    final footerCutoff = pageHeight * 0.958;

    final rawFragments = <_VisualFragment>[];
    for (final f in pageText.fragments) {
      final rect = f.bounds.toRect(page: page);
      if (!rect.left.isFinite || !rect.top.isFinite || rect.width <= 0 || rect.height <= 0) {
        continue;
      }
      // Strip running headers & footers (except on page 1 top where title may sit near top)
      if ((page.pageNumber > 1 && rect.bottom < headerCutoff) || rect.top > footerCutoff) {
        continue;
      }
      final start = f.index.clamp(0, pageText.fullText.length);
      final end = f.end.clamp(start, pageText.fullText.length);
      final text = pageText.fullText.substring(start, end).trim();
      if (text.isEmpty) continue;
      rawFragments.add(_VisualFragment(rect: rect, text: text));
    }

    if (rawFragments.isEmpty) return const [];

    if (!analysis.isMultiColumn || analysis.columns.length < 2) {
      final lines = _groupFragmentsIntoLines(rawFragments);
      return [(lines: lines, regionBounds: analysis.contentBounds)];
    }

    // 2-Column layout: separate wide spanning fragments (title/abstract/wide banners)
    // from left-column and right-column fragments.
    final col0 = analysis.columns[0].bounds;
    final col1 = analysis.columns[1].bounds;
    final gutterMidX = (col0.right + col1.left) / 2.0;
    final contentWidth = analysis.contentBounds.width;

    final topSpanning = <_VisualFragment>[];
    final leftCol = <_VisualFragment>[];
    final rightCol = <_VisualFragment>[];
    final bottomSpanning = <_VisualFragment>[];

    for (final frag in rawFragments) {
      final r = frag.rect;
      final spansGutter = r.left < gutterMidX - 25.0 && r.right > gutterMidX + 25.0;
      final isWide = r.width > contentWidth * 0.58;
      if (spansGutter || isWide) {
        if (r.top < pageHeight * 0.42) {
          topSpanning.add(frag);
        } else {
          bottomSpanning.add(frag);
        }
      } else if (r.center.dx < gutterMidX) {
        leftCol.add(frag);
      } else {
        rightCol.add(frag);
      }
    }

    final result = <({List<_VisualLine> lines, Rect regionBounds})>[];
    if (topSpanning.isNotEmpty) {
      result.add((
        lines: _groupFragmentsIntoLines(topSpanning),
        regionBounds: analysis.contentBounds,
      ));
    }
    if (leftCol.isNotEmpty) {
      result.add((
        lines: _groupFragmentsIntoLines(leftCol),
        regionBounds: col0,
      ));
    }
    if (rightCol.isNotEmpty) {
      result.add((
        lines: _groupFragmentsIntoLines(rightCol),
        regionBounds: col1,
      ));
    }
    if (bottomSpanning.isNotEmpty) {
      result.add((
        lines: _groupFragmentsIntoLines(bottomSpanning),
        regionBounds: analysis.contentBounds,
      ));
    }
    return result;
  }

  static List<_VisualLine> _groupFragmentsIntoLines(List<_VisualFragment> fragments) {
    if (fragments.isEmpty) return const [];

    final sorted = List<_VisualFragment>.from(fragments)
      ..sort((a, b) {
        final dy = (a.rect.center.dy - b.rect.center.dy).abs();
        final tol = math.max(2.5, math.min(a.rect.height, b.rect.height) * 0.45);
        if (dy <= tol) {
          return a.rect.left.compareTo(b.rect.left);
        }
        return a.rect.center.dy.compareTo(b.rect.center.dy);
      });

    final lineClusters = <List<_VisualFragment>>[];
    for (final frag in sorted) {
      if (lineClusters.isEmpty) {
        lineClusters.add([frag]);
        continue;
      }
      final currentCluster = lineClusters.last;
      final clusterCenterY = currentCluster.fold<double>(
            0.0,
            (sum, item) => sum + item.rect.center.dy,
          ) /
          currentCluster.length;
      final clusterHeight = currentCluster.fold<double>(
        0.0,
        (maxH, item) => math.max(maxH, item.rect.height),
      );
      final tol = math.max(3.0, math.min(clusterHeight, frag.rect.height) * 0.5);
      if ((frag.rect.center.dy - clusterCenterY).abs() <= tol) {
        currentCluster.add(frag);
      } else {
        lineClusters.add([frag]);
      }
    }

    final lines = <_VisualLine>[];
    for (final cluster in lineClusters) {
      cluster.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      Rect? bounds;
      double maxH = 0.0;
      final sb = StringBuffer();
      double? prevRight;

      for (final item in cluster) {
        bounds = bounds == null ? item.rect : bounds.expandToInclude(item.rect);
        if (item.rect.height > maxH) maxH = item.rect.height;
        if (prevRight != null) {
          final gap = item.rect.left - prevRight;
          if (gap > 1.5 && !sb.toString().endsWith(' ')) {
            sb.write(' ');
          }
        }
        sb.write(item.text);
        prevRight = item.rect.right;
      }

      final text = sb.toString().trim();
      if (text.isNotEmpty && bounds != null) {
        lines.add(_VisualLine(bounds: bounds, text: text, maxHeight: maxH));
      }
    }
    return lines;
  }
}
