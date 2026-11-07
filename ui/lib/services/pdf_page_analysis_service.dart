import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../controllers/reader_controller.dart';

/// Represents a detected vertical column within a PDF page.
class PdfColumnInfo {
  final Rect bounds;
  final int index;
  const PdfColumnInfo({required this.bounds, required this.index});

  @override
  String toString() => 'PdfColumnInfo(#$index, bounds: $bounds)';
}

/// Analysis result for a single PDF page: content bounds and column layout.
class PdfPageAnalysis {
  final int pageNumber;
  final Size pageSize;
  final Rect contentBounds;
  final List<PdfColumnInfo> columns;
  final bool isMultiColumn;

  const PdfPageAnalysis({
    required this.pageNumber,
    required this.pageSize,
    required this.contentBounds,
    required this.columns,
    required this.isMultiColumn,
  });

  /// Finds the column containing [offset], or the horizontally closest column.
  PdfColumnInfo findBestColumn(Offset offset) {
    if (columns.isEmpty) {
      return PdfColumnInfo(bounds: contentBounds, index: 0);
    }
    if (columns.length == 1) {
      return columns.first;
    }
    for (final col in columns) {
      if (offset.dx >= col.bounds.left - 8.0 && offset.dx <= col.bounds.right + 8.0) {
        return col;
      }
    }
    PdfColumnInfo closest = columns.first;
    double minDistance = double.infinity;
    for (final col in columns) {
      final dist = (offset.dx - col.bounds.center.dx).abs();
      if (dist < minDistance) {
        minDistance = dist;
        closest = col;
      }
    }
    return closest;
  }
}

/// Service that analyzes and caches page layout geometries (content boundaries,
/// multi-column gutters, and column widths) for smart double-tap zooming and margin cropping.
class PdfPageAnalysisService {
  static final Map<String, Map<int, PdfPageAnalysis>> _cache = {};
  static const int _maxCachedDocs = 10;

  /// Returns a cache key uniquely identifying the document content currently being displayed.
  /// Uses identityHashCode of currentPdfBytes so that any new compilation or cached session swap
  /// automatically invalidates previous analysis without relying on generation numbers.
  static String keyFor(ReaderController controller) {
    final path = controller.currentFilePath ?? 'untitled';
    final bytes = controller.currentPdfBytes;
    final bytesId = bytes != null ? identityHashCode(bytes) : 0;
    return '$path#$bytesId';
  }

  /// Clears analysis cache for a specific document or globally.
  static void clearCache([String? docKey]) {
    if (docKey != null) {
      _cache.remove(docKey);
    } else {
      _cache.clear();
    }
  }

  /// Gets cached analysis if available without triggering asynchronous extraction.
  /// Promotes the document to most-recently-used in the LRU cache.
  static PdfPageAnalysis? getCachedAnalysis(String docKey, int pageNumber) {
    final docPages = _cache.remove(docKey);
    if (docPages != null) {
      _cache[docKey] = docPages;
      return docPages[pageNumber];
    }
    return null;
  }

  /// Analyzes a [PdfPage] on demand, caching the result in memory.
  static Future<PdfPageAnalysis> analyzePage(PdfPage page, {String? docKey}) async {
    final key = docKey ?? 'doc_${page.document.hashCode}';
    final pageNum = page.pageNumber;
    final cached = getCachedAnalysis(key, pageNum);
    if (cached != null) return cached;

    final pageText = await page.loadStructuredText();
    final analysis = computePageAnalysis(page, pageText);

    final docPages = _cache.remove(key) ?? <int, PdfPageAnalysis>{};
    docPages[pageNum] = analysis;
    _cache[key] = docPages;

    if (_cache.length > _maxCachedDocs) {
      _cache.remove(_cache.keys.first);
    }
    return analysis;
  }

  static final RegExp _uprightNarrowGlyphRegex =
      RegExp(r'^["“‘\x27\(\[]?[I1l!|][\.,;:]?$');

  /// Returns true if a fragment represents 90°-rotated vertical side-margin or interior credit text
  /// (such as vertical photo credits along the outer edge of magazine pages or beside illustrations).
  static bool isVerticalMarginFragment(
    PdfPage page,
    PdfPageTextFragment fragment,
    Rect rect, {
    String? rawText,
  }) {
    final inOuterMargin =
        rect.right < page.width * 0.046 || rect.left > page.width * 0.954;
    if (fragment.direction == PdfTextDirection.vrtl) {
      if (inOuterMargin) return true;
      final isUprightNarrowI = rect.height >= 6.8 &&
          (rawText == null
              ? (fragment.length <= 2 && rect.height >= rect.width * 0.85)
              : _uprightNarrowGlyphRegex.hasMatch(rawText.trim()));
      return !isUprightNarrowI;
    }
    if (!inOuterMargin) return false;
    if (rect.width < 12.5 && rect.height > math.max(14.0, rect.width * 1.65)) {
      return true;
    }
    return false;
  }

  /// Pure geometric layout analyzer: Computes content bounding box and multi-column gutters (2, 3, or 4 columns).
  static PdfPageAnalysis computePageAnalysis(PdfPage page, PdfPageText pageText) {
    if (pageText.fragments.isEmpty) {
      final full = Rect.fromLTWH(0, 0, page.width, page.height);
      return PdfPageAnalysis(
        pageNumber: page.pageNumber,
        pageSize: Size(page.width, page.height),
        contentBounds: full,
        columns: [PdfColumnInfo(bounds: full, index: 0)],
        isMultiColumn: false,
      );
    }

    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    final validFragments = <({PdfPageTextFragment frag, Rect rect})>[];
    for (final f in pageText.fragments) {
      final r = f.bounds.toRect(page: page);
      if (!r.left.isFinite || !r.top.isFinite || r.width <= 0 || r.height <= 0) {
        continue;
      }
      final start = f.index.clamp(0, pageText.fullText.length);
      final end = f.end.clamp(start, pageText.fullText.length);
      final rawSub = pageText.fullText.substring(start, end);
      if (isVerticalMarginFragment(page, f, r, rawText: rawSub)) continue;
      validFragments.add((frag: f, rect: r));
      if (r.left < minX) minX = r.left;
      if (r.right > maxX) maxX = r.right;
      if (r.top < minY) minY = r.top;
      if (r.bottom > maxY) maxY = r.bottom;
    }

    if (validFragments.isEmpty) {
      final full = Rect.fromLTWH(0, 0, page.width, page.height);
      return PdfPageAnalysis(
        pageNumber: page.pageNumber,
        pageSize: Size(page.width, page.height),
        contentBounds: full,
        columns: [PdfColumnInfo(bounds: full, index: 0)],
        isMultiColumn: false,
      );
    }

    final contentWidth = maxX - minX;
    final contentBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    if (contentWidth <= 50) {
      return PdfPageAnalysis(
        pageNumber: page.pageNumber,
        pageSize: Size(page.width, page.height),
        contentBounds: contentBounds,
        columns: [PdfColumnInfo(bounds: contentBounds, index: 0)],
        isMultiColumn: false,
      );
    }

    // Group word fragments on the same baseline with normal inter-word spacing (<= 5.5pt)
    // so that multi-column spanning titles/subtitles/captions can be identified by their combined width.
    final headerCutoff = page.height * 0.042;
    final footerCutoff = page.height * 0.948;
    final bodyRects = <Rect>[];
    for (final item in validFragments) {
      final r = item.rect;
      if ((page.pageNumber > 1 && r.bottom < headerCutoff) || r.top > footerCutoff) {
        continue;
      }
      // Exclude decorative full-column single-char ornaments (e.g. 40pt rule glyphs)
      if (r.height > 28.0 && item.frag.length <= 2 && r.width > 80.0) {
        continue;
      }
      bodyRects.add(r);
    }

    bodyRects.sort((a, b) {
      final dy = (a.center.dy - b.center.dy).abs();
      final tol = math.max(2.5, math.min(a.height, b.height) * 0.45);
      if (dy <= tol) return a.left.compareTo(b.left);
      return a.center.dy.compareTo(b.center.dy);
    });

    final mergedRuns = <Rect>[];
    for (final r in bodyRects) {
      if (mergedRuns.isEmpty) {
        mergedRuns.add(r);
        continue;
      }
      final prev = mergedRuns.last;
      final dy = (r.center.dy - prev.center.dy).abs();
      final tol = math.max(2.5, math.min(r.height, prev.height) * 0.5);
      final gap = r.left - prev.right;
      if (dy <= tol && gap >= -2.0 && gap <= math.max(5.5, math.min(r.height, prev.height) * 0.52)) {
        mergedRuns[mergedRuns.length - 1] = prev.expandToInclude(r);
      } else {
        mergedRuns.add(r);
      }
    }

    // 2pt buckets for high-resolution horizontal projection histogram (detects narrow ~9pt magazine gutters)
    const bucketSize = 2.0;
    final bucketCount = (page.width / bucketSize).ceil();
    final buckets = List<int>.filled(bucketCount, 0);

    for (final r in mergedRuns) {
      // Exclude wide cross-column elements (2-of-3 or full-width spanning titles, banners, captions)
      if (r.width > contentWidth * 0.54) continue;
      final start = (r.left / bucketSize).floor().clamp(0, bucketCount - 1);
      final end = (r.right / bucketSize).floor().clamp(0, bucketCount - 1);
      for (var b = start; b <= end; b++) {
        buckets[b]++;
      }
    }

    final minBucket = (minX / bucketSize).floor().clamp(0, bucketCount - 1);
    final maxBucket = (maxX / bucketSize).ceil().clamp(0, bucketCount);
    final rangeBuckets = buckets.sublist(minBucket, maxBucket);
    final totalDensity = rangeBuckets.isEmpty ? 0 : rangeBuckets.reduce((a, b) => a + b);
    final avgDensity = totalDensity / math.max(1.0, contentWidth / bucketSize);
    final threshold = (avgDensity * 0.14).ceil().clamp(1, 8);

    // Search for column gutters (valleys) in the middle 18% to 82% of content width
    final searchStart = ((minX + contentWidth * 0.18) / bucketSize).floor().clamp(0, bucketCount - 1);
    final searchEnd = ((minX + contentWidth * 0.82) / bucketSize).floor().clamp(0, bucketCount - 1);

    final candidateGutters = <({double left, double right})>[];
    int currentGapLen = 0;
    int currentGapStart = 0;

    for (var i = searchStart; i <= searchEnd; i++) {
      if (buckets[i] <= threshold) {
        if (currentGapLen == 0) currentGapStart = i;
        currentGapLen++;
      } else {
        if (currentGapLen * bucketSize >= 6.0) {
          candidateGutters.add((
            left: currentGapStart * bucketSize,
            right: i * bucketSize,
          ));
        }
        currentGapLen = 0;
      }
    }
    if (currentGapLen * bucketSize >= 6.0) {
      candidateGutters.add((
        left: currentGapStart * bucketSize,
        right: (searchEnd + 1) * bucketSize,
      ));
    }

    double columnAverageDensity(double leftX, double rightX) {
      final s = (leftX / bucketSize).floor().clamp(0, bucketCount - 1);
      final e = (rightX / bucketSize).ceil().clamp(s, bucketCount);
      if (e <= s) return 0.0;
      var sum = 0;
      for (var i = s; i < e; i++) {
        sum += buckets[i];
      }
      return sum / (e - s);
    }

    int effectiveLineCount(Rect r) => (r.height / 11.0).round().clamp(1, 45);

    List<Rect> mergeRunsRespectingGutters(List<({double left, double right})> gutters) {
      final result = <Rect>[];
      for (final r in mergedRuns) {
        if (result.isEmpty) {
          result.add(r);
          continue;
        }
        final prev = result.last;
        final dy = (r.center.dy - prev.center.dy).abs();
        final tol = math.max(3.0, math.min(r.height, prev.height) * 0.45);
        final gap = r.left - prev.right;
        final crossesGutterGap = gutters.any(
          (g) =>
              prev.right <= g.right + 3.0 &&
              r.left >= g.left - 3.0 &&
              gap >= math.max(6.0, (g.right - g.left) * 0.65),
        );
        if (dy <= tol &&
            r.height <= 18.0 &&
            prev.height <= 18.0 &&
            gap >= -2.0 &&
            gap <= 14.0 &&
            !crossesGutterGap) {
          result[result.length - 1] = prev.expandToInclude(r);
        } else {
          result.add(r);
        }
      }
      return result;
    }

    // Computes the line-count-weighted median width within a candidate column.
    double columnMedianLineWidth(List<Rect> colRects) {
      if (colRects.isEmpty) return 0.0;
      final items = <({double width, int weight})>[
        for (final r in colRects) (width: r.width, weight: effectiveLineCount(r)),
      ]..sort((a, b) => a.width.compareTo(b.width));
      final totalWeight = items.fold<int>(0, (sum, item) => sum + item.weight);
      int acc = 0;
      for (final item in items) {
        acc += item.weight;
        if (acc * 2 >= totalWeight) {
          return item.width;
        }
      }
      return items.last.width;
    }

    // 1. Try 3-column (or 4-column) layout if 2+ valid gutters partition the page into balanced columns
    if (candidateGutters.length >= 2) {
      final minColW = math.max(90.0, contentWidth * 0.18);
      final filtered = <({double left, double right})>[];
      double prevRight = minX;
      for (final g in candidateGutters) {
        if (g.left - prevRight >= minColW &&
            columnAverageDensity(prevRight, g.left) >= avgDensity * 0.22) {
          filtered.add(g);
          prevRight = g.right;
        }
      }
      while (filtered.isNotEmpty &&
          (maxX - filtered.last.right < minColW ||
              columnAverageDensity(filtered.last.right, maxX) < avgDensity * 0.22)) {
        filtered.removeLast();
      }

      if (filtered.length >= 2 && filtered.length <= 3) {
        final colBounds = <Rect>[];
        double curLeft = minX;
        for (final g in filtered) {
          colBounds.add(Rect.fromLTRB(curLeft, minY, g.left, maxY));
          curLeft = g.right;
        }
        colBounds.add(Rect.fromLTRB(curLeft, minY, maxX, maxY));

        final widths = colBounds.map((c) => c.width).toList();
        final minW = widths.reduce(math.min);
        final maxW = widths.reduce(math.max);
        final colOnlyCounts = List<int>.filled(colBounds.length, 0);
        int crossAnyGutterRuns = 0;
        for (final r in mergedRuns) {
          final crosses = filtered.any((g) => r.left < g.left - 18.0 && r.right > g.right + 18.0);
          if (crosses) {
            crossAnyGutterRuns++;
          } else {
            for (var c = 0; c < colBounds.length; c++) {
              if (r.left >= colBounds[c].left - 6.0 && r.right <= colBounds[c].right + 6.0) {
                colOnlyCounts[c]++;
                break;
              }
            }
          }
        }
        final minColRuns = colOnlyCounts.reduce(math.min);
        bool isValidThreeCol = minColRuns >= 4 && crossAnyGutterRuns <= minColRuns * 0.65;
        if (!isValidThreeCol && minColRuns >= 4) {
          final combinedRuns = mergeRunsRespectingGutters(filtered);
          final colRuns = List<List<Rect>>.generate(colBounds.length, (_) => <Rect>[]);
          final crossRects = <Rect>[];
          for (final r in combinedRuns) {
            final crosses = filtered.any((g) => r.left < g.left - 18.0 && r.right > g.right + 18.0);
            if (crosses) {
              crossRects.add(r);
            } else {
              for (var c = 0; c < colBounds.length; c++) {
                if (r.left >= colBounds[c].left - 6.0 && r.right <= colBounds[c].right + 6.0) {
                  colRuns[c].add(r);
                  break;
                }
              }
            }
          }
          if (colRuns.every((runs) => runs.isNotEmpty)) {
            final minThreeColLines = colRuns
                .map((runs) => runs.fold<int>(0, (s, r) => s + effectiveLineCount(r)))
                .reduce(math.min);
            final overlapTop = colRuns
                .map((runs) => runs.map((r) => r.top).reduce(math.min))
                .reduce(math.max);
            final overlapBottom = colRuns
                .map((runs) => runs.map((r) => r.bottom).reduce(math.max))
                .reduce(math.min);
            final overlapHeight = math.max(0.0, overlapBottom - overlapTop);
            final inBandCrossLines = crossRects
                .where((r) => r.center.dy >= overlapTop && r.center.dy <= overlapBottom)
                .fold<int>(0, (s, r) => s + effectiveLineCount(r));
            final allColsProse = List.generate(
              colBounds.length,
              (c) => columnMedianLineWidth(colRuns[c]) >= colBounds[c].width * 0.55,
            ).every((v) => v);
            isValidThreeCol = minThreeColLines >= 4 &&
                inBandCrossLines <= minThreeColLines * 0.45 &&
                overlapHeight >= (maxY - minY) * 0.22 &&
                allColsProse;
          }
        }
        if (minW >= minColW &&
            maxW <= contentWidth * 0.45 &&
            (maxW / minW) <= 1.85 &&
            isValidThreeCol) {
          return PdfPageAnalysis(
            pageNumber: page.pageNumber,
            pageSize: Size(page.width, page.height),
            contentBounds: contentBounds,
            columns: [
              for (var i = 0; i < colBounds.length; i++)
                PdfColumnInfo(bounds: colBounds[i], index: i),
            ],
            isMultiColumn: true,
          );
        }
      }
    }

    // 2. Try 2-column layout in the central 28%..72% region
    final fullWidthRunCount = mergedRuns.where((r) => r.width > contentWidth * 0.65).length;
    final centralMinX = minX + contentWidth * 0.28;
    final centralMaxX = minX + contentWidth * 0.72;
    ({double left, double right})? bestTwoColGutter;
    for (final g in candidateGutters) {
      final mid = (g.left + g.right) / 2.0;
      if (mid < centralMinX || mid > centralMaxX) continue;
      final isCenteredLowFullWidth = mergedRuns.isNotEmpty &&
          fullWidthRunCount <= mergedRuns.length * 0.12 &&
          (mid - (minX + contentWidth * 0.5)).abs() <= contentWidth * 0.08;
      final minTwoColGutterWidth = isCenteredLowFullWidth ? 6.0 : 6.5;
      if (g.right - g.left < minTwoColGutterWidth) continue;
      final leftW = g.left - minX;
      final rightW = maxX - g.right;
      final minTwoColW = math.max(90.0, contentWidth * 0.26);
      if (leftW < minTwoColW || rightW < minTwoColW) continue;
      if (columnAverageDensity(minX, g.left) < avgDensity * 0.22 ||
          columnAverageDensity(g.right, maxX) < avgDensity * 0.22) {
        continue;
      }
      // Reject false 2-column splits on single-column pages where a table creates a central gap,
      // while allowing genuine 2-column pages that have a long full-width abstract/header above
      // the 2-column vertical overlap region.
      int col1OnlyRuns = 0;
      int col2OnlyRuns = 0;
      int crossGutterRuns = 0;
      for (final r in mergedRuns) {
        if (r.right <= g.right + 6.0) {
          col1OnlyRuns++;
        } else if (r.left >= g.left - 6.0) {
          col2OnlyRuns++;
        } else if (r.left < g.left - 18.0 && r.right > g.right + 18.0) {
          crossGutterRuns++;
        }
      }
      final minRawColRuns = math.min(col1OnlyRuns, col2OnlyRuns);
      bool isValidTwoCol = minRawColRuns >= 4 && crossGutterRuns <= minRawColRuns * 0.45;
      if (!isValidTwoCol) {
        final combinedRuns = mergeRunsRespectingGutters([g]);
        final col1Rects = <Rect>[];
        final col2Rects = <Rect>[];
        final crossGutterRects = <Rect>[];
        for (final r in combinedRuns) {
          if (r.right <= g.right + 6.0) {
            col1Rects.add(r);
          } else if (r.left >= g.left - 6.0) {
            col2Rects.add(r);
          } else if (r.left < g.left - 18.0 && r.right > g.right + 18.0) {
            crossGutterRects.add(r);
          }
        }
        if (col1Rects.isNotEmpty && col2Rects.isNotEmpty) {
          final col1Lines = col1Rects.fold<int>(0, (s, r) => s + effectiveLineCount(r));
          final col2Lines = col2Rects.fold<int>(0, (s, r) => s + effectiveLineCount(r));
          final minTwoColLines = math.min(col1Lines, col2Lines);
          final col1Top = col1Rects.map((r) => r.top).reduce(math.min);
          final col1Bottom = col1Rects.map((r) => r.bottom).reduce(math.max);
          final col2Top = col2Rects.map((r) => r.top).reduce(math.min);
          final col2Bottom = col2Rects.map((r) => r.bottom).reduce(math.max);
          final overlapTop = math.max(col1Top, col2Top);
          final overlapBottom = math.min(col1Bottom, col2Bottom);
          final overlapHeight = math.max(0.0, overlapBottom - overlapTop);
          final maxColSpanHeight = math.max(col1Bottom - col1Top, col2Bottom - col2Top);
          final inBandCrossLines = crossGutterRects
              .where((r) => r.center.dy >= overlapTop && r.center.dy <= overlapBottom)
              .fold<int>(0, (s, r) => s + effectiveLineCount(r));
          final col1MedianW = columnMedianLineWidth(col1Rects);
          final col2MedianW = columnMedianLineWidth(col2Rects);
          isValidTwoCol = minTwoColLines >= 4 &&
              inBandCrossLines <= minTwoColLines * 0.45 &&
              overlapHeight >= 36.0 &&
              maxColSpanHeight >= (maxY - minY) * 0.22 &&
              col1MedianW >= leftW * 0.55 &&
              col2MedianW >= rightW * 0.55;
        }
      }
      if (!isValidTwoCol) {
        continue;
      }
      if (bestTwoColGutter == null ||
          (g.right - g.left) > (bestTwoColGutter.right - bestTwoColGutter.left)) {
        bestTwoColGutter = g;
      }
    }

    if (bestTwoColGutter != null) {
      final col1 = Rect.fromLTRB(minX, minY, bestTwoColGutter.left, maxY);
      final col2 = Rect.fromLTRB(bestTwoColGutter.right, minY, maxX, maxY);

      // If one side is ~2x wider than the other (1/3 + 2/3 split on a 3-column page where
      // an inset poem/sidebar box spans two columns in the upper or lower half), check the
      // un-spanned vertical half of the wider side for the third column gutter.
      final narrowRect = col1.width < col2.width ? col1 : col2;
      final wideRect = col2.width > col1.width ? col2 : col1;
      if (wideRect.width >= narrowRect.width * 1.72 &&
          wideRect.width <= narrowRect.width * 2.45) {
        final wMidMin = wideRect.left + wideRect.width * 0.34;
        final wMidMax = wideRect.left + wideRect.width * 0.66;
        final wSearchStart = (wMidMin / bucketSize).floor().clamp(0, bucketCount - 1);
        final wSearchEnd = (wMidMax / bucketSize).ceil().clamp(0, bucketCount - 1);

        for (final band in [
          (top: minY + contentBounds.height * 0.48, bottom: maxY),
          (top: minY, bottom: minY + contentBounds.height * 0.52),
          (top: minY + contentBounds.height * 0.70, bottom: maxY),
          (top: minY, bottom: minY + contentBounds.height * 0.34),
        ]) {
          final bandBuckets = List<int>.filled(bucketCount, 0);
          int bandRuns = 0;
          for (final r in mergedRuns) {
            if (r.top < band.top || r.bottom > band.bottom) continue;
            if (r.left < wideRect.left - 8.0 || r.right > wideRect.right + 8.0) continue;
            if (r.width > wideRect.width * 0.62) continue;
            bandRuns++;
            final s = (r.left / bucketSize).floor().clamp(0, bucketCount - 1);
            final e = (r.right / bucketSize).floor().clamp(0, bucketCount - 1);
            for (var b = s; b <= e; b++) {
              bandBuckets[b]++;
            }
          }
          if (bandRuns < 6) continue;
          double subBandDensity(double leftX, double rightX) {
            final s = (leftX / bucketSize).floor().clamp(0, bucketCount - 1);
            final e = (rightX / bucketSize).ceil().clamp(s, bucketCount);
            if (e <= s) return 0.0;
            var sum = 0;
            for (var i = s; i < e; i++) {
              sum += bandBuckets[i];
            }
            return sum / (e - s);
          }

          int gLen = 0;
          int gStart = 0;
          ({double left, double right})? subGutter;
          for (var i = wSearchStart; i <= wSearchEnd; i++) {
            if (bandBuckets[i] == 0) {
              if (gLen == 0) gStart = i;
              gLen++;
            } else {
              if (gLen * bucketSize >= 6.0) {
                subGutter = (left: gStart * bucketSize, right: i * bucketSize);
                break;
              }
              gLen = 0;
            }
          }
          if (subGutter == null && gLen * bucketSize >= 6.0) {
            subGutter = (left: gStart * bucketSize, right: (wSearchEnd + 1) * bucketSize);
          }
          if (subGutter != null &&
              subBandDensity(wideRect.left, subGutter.left) >= 2.0 &&
              subBandDensity(subGutter.right, wideRect.right) >= 2.0) {
            final subA = Rect.fromLTRB(wideRect.left, minY, subGutter.left, maxY);
            final subB = Rect.fromLTRB(subGutter.right, minY, wideRect.right, maxY);
            if ((subA.width - narrowRect.width).abs() <= narrowRect.width * 0.22 &&
                (subB.width - narrowRect.width).abs() <= narrowRect.width * 0.22) {
              final threeCols = col2.width > col1.width ? [col1, subA, subB] : [subA, subB, col2];
              return PdfPageAnalysis(
                pageNumber: page.pageNumber,
                pageSize: Size(page.width, page.height),
                contentBounds: contentBounds,
                columns: [
                  for (var i = 0; i < threeCols.length; i++)
                    PdfColumnInfo(bounds: threeCols[i], index: i),
                ],
                isMultiColumn: true,
              );
            }
          }
        }
      }

      return PdfPageAnalysis(
        pageNumber: page.pageNumber,
        pageSize: Size(page.width, page.height),
        contentBounds: contentBounds,
        columns: [
          PdfColumnInfo(bounds: col1, index: 0),
          PdfColumnInfo(bounds: col2, index: 1),
        ],
        isMultiColumn: true,
      );
    }

    return PdfPageAnalysis(
      pageNumber: page.pageNumber,
      pageSize: Size(page.width, page.height),
      contentBounds: contentBounds,
      columns: [PdfColumnInfo(bounds: contentBounds, index: 0)],
      isMultiColumn: false,
    );
  }

  /// Resolves the effective page width when `pdfCropMargins` is enabled.
  static double resolveEffectivePageWidth(
    ReaderController readerController,
    PdfPageLayout layout,
    int? pageNumber, {
    required bool pdfCropMargins,
  }) {
    final targetPageNum =
        (pageNumber != null && pageNumber >= 1 && pageNumber <= layout.pageLayouts.length)
            ? pageNumber
            : 1;
    final page = layout.pageLayouts[targetPageNum - 1];
    if (!pdfCropMargins) return page.width;

    final docKey = keyFor(readerController);
    final analysis = getCachedAnalysis(docKey, targetPageNum);
    if (analysis != null && analysis.contentBounds.width > 50.0) {
      return math.min(analysis.contentBounds.width + 32.0, page.width);
    }
    return page.width;
  }

  /// Pre-analyzes the first page on viewer ready when on mobile or margin crop is active.
  static void warmupFirstPage(
    PdfDocument document,
    ReaderController readerController, {
    required bool isMobile,
    required VoidCallback onCroppedReady,
  }) {
    if (document.pages.isEmpty) return;
    if (!isMobile && !readerController.effectivePdfCropMargins) return;
    analyzePage(
      document.pages.first,
      docKey: keyFor(readerController),
    ).then((_) {
      if (readerController.effectivePdfCropMargins) {
        onCroppedReady();
      }
    });
  }

  /// Pre-analyzes the active page on page change when on mobile or margin crop is active.
  static void preloadPageIfNeeded(
    PdfViewerController pdfController,
    ReaderController readerController,
    int pageNum, {
    required bool isMobile,
  }) {
    if (!isMobile && !readerController.effectivePdfCropMargins) return;
    if (pdfController.pages.isNotEmpty && pageNum >= 1 && pageNum <= pdfController.pages.length) {
      analyzePage(
        pdfController.pages[pageNum - 1],
        docKey: keyFor(readerController),
      );
    }
  }

  /// Smart double-tap: Zooms to fit tapped column or toggles back to fit page.
  static Future<bool> handleSmartDoubleTap(
    PdfViewerController controller,
    PdfViewerGeneralTapHandlerDetails details,
    ReaderController readerController, {
    required double topInset,
    required bool Function() isMounted,
  }) async {
    final layout = controller.layoutOrNull;
    if (layout == null || controller.pages.isEmpty) return false;

    final docPos = details.documentPosition;
    int? tappedPageIndex;
    for (int i = 0; i < layout.pageLayouts.length; i++) {
      final rect = layout.pageLayouts[i];
      if (rect.contains(docPos)) {
        tappedPageIndex = i;
        break;
      }
    }

    if (tappedPageIndex == null) {
      double minVerticalDist = double.infinity;
      for (int i = 0; i < layout.pageLayouts.length; i++) {
        final rect = layout.pageLayouts[i];
        final dist = (docPos.dy - rect.center.dy).abs();
        if (dist < minVerticalDist) {
          minVerticalDist = dist;
          tappedPageIndex = i;
        }
      }
    }

    if (tappedPageIndex == null || tappedPageIndex >= controller.pages.length) {
      return false;
    }

    final page = controller.pages[tappedPageIndex];
    final pageRect = layout.pageLayouts[tappedPageIndex];
    final localOffset = Offset(
      (docPos.dx - pageRect.left).clamp(0.0, page.width),
      (docPos.dy - pageRect.top).clamp(0.0, page.height),
    );

    final analysis = await analyzePage(
      page,
      docKey: keyFor(readerController),
    );
    if (!isMounted()) return true;

    final col = analysis.findBestColumn(localOffset);
    final colWidth = math.max(col.bounds.width, 80.0);
    final viewWidth = controller.viewSize.width;
    final viewHeight = controller.viewSize.height;

    const horizontalPadding = 16.0;
    final availableWidth = math.max(viewWidth - horizontalPadding * 2, 80.0);
    final targetZoom = (availableWidth / colWidth).clamp(0.4, 5.0);

    final currentZoom = controller.currentZoom;
    final normalScale = controller.coverScale;

    if (currentZoom >= targetZoom * 0.88) {
      final topDocOffset = normalScale > 0 ? topInset / normalScale : 0.0;
      await controller.goToPosition(
        documentOffset: Offset(
          pageRect.left,
          (pageRect.top - topDocOffset).clamp(0.0, double.infinity),
        ),
        zoom: normalScale,
        duration: const Duration(milliseconds: 250),
      );
      return true;
    }

    final colDocLeft = pageRect.left + col.bounds.left;
    final targetDocX = colDocLeft - (horizontalPadding / targetZoom);
    final targetDocY = docPos.dy - (viewHeight * 0.25 / targetZoom);

    await controller.goToPosition(
      documentOffset: Offset(
        targetDocX.clamp(0.0, double.infinity),
        targetDocY.clamp(0.0, double.infinity),
      ),
      zoom: targetZoom,
      duration: const Duration(milliseconds: 250),
    );
    return true;
  }

  /// Smoothly animates zoom to crop white margins, or restores fit-width.
  static Future<void> applyMarginCrop(
    PdfViewerController pdfController,
    ReaderController readerController,
    bool crop, {
    required bool Function() isMounted,
  }) async {
    if (!pdfController.isReady || pdfController.pages.isEmpty) return;
    final pageNum = pdfController.pageNumber ?? 1;
    final clampedNum = pageNum.clamp(1, pdfController.pages.length);
    final page = pdfController.pages[clampedNum - 1];
    final layout = pdfController.layoutOrNull;
    final pageRect = (layout != null && clampedNum <= layout.pageLayouts.length)
        ? layout.pageLayouts[clampedNum - 1]
        : null;

    final currentPos = pdfController.visibleRect.topLeft;

    if (crop) {
      final analysis = await analyzePage(
        page,
        docKey: keyFor(readerController),
      );
      if (!isMounted()) return;
      final content = analysis.contentBounds;
      if (content.width > 50.0) {
        final viewWidth = pdfController.viewSize.width;
        const horizontalPadding = 16.0;
        final cropZoom = ((viewWidth - horizontalPadding * 2) / content.width).clamp(0.4, 5.0);
        final targetDocX = (pageRect?.left ?? 0.0) + content.left - (horizontalPadding / cropZoom);
        await pdfController.goToPosition(
          documentOffset: Offset(targetDocX.clamp(0.0, double.infinity), currentPos.dy),
          zoom: cropZoom,
          duration: const Duration(milliseconds: 250),
        );
        return;
      }
    }

    final targetDocX = pageRect?.left ?? 0.0;
    await pdfController.goToPosition(
      documentOffset: Offset(targetDocX, currentPos.dy),
      zoom: pdfController.coverScale,
      duration: const Duration(milliseconds: 250),
    );
  }
}
