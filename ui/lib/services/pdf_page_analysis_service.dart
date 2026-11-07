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

  /// Returns true if a fragment represents 90°-rotated vertical side-margin text
  /// (such as vertical photo credits along the outer edge of magazine pages).
  static bool isVerticalMarginFragment(
    PdfPage page,
    PdfPageTextFragment fragment,
    Rect rect,
  ) {
    if (fragment.direction == PdfTextDirection.vrtl) return true;
    final inOuterMargin =
        rect.right < page.width * 0.058 || rect.left > page.width * 0.942;
    if (inOuterMargin && rect.width < 12.5 && rect.height > rect.width * 1.35) {
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
      if (isVerticalMarginFragment(page, f, r)) continue;
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
        right: searchEnd * bucketSize,
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
        if (minW >= minColW && maxW <= contentWidth * 0.45 && (maxW / minW) <= 1.85) {
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
    final centralMinX = minX + contentWidth * 0.28;
    final centralMaxX = minX + contentWidth * 0.72;
    ({double left, double right})? bestTwoColGutter;
    for (final g in candidateGutters) {
      final mid = (g.left + g.right) / 2.0;
      if (mid < centralMinX || mid > centralMaxX) continue;
      if (g.right - g.left < 6.5) continue;
      final leftW = g.left - minX;
      final rightW = maxX - g.right;
      final minTwoColW = math.max(90.0, contentWidth * 0.26);
      if (leftW < minTwoColW || rightW < minTwoColW) continue;
      if (columnAverageDensity(minX, g.left) < avgDensity * 0.22 ||
          columnAverageDensity(g.right, maxX) < avgDensity * 0.22) {
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
