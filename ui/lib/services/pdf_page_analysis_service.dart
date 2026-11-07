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

  /// Pure geometric layout analyzer: Computes content bounding box and multi-column gutters.
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

    for (final f in pageText.fragments) {
      final r = f.bounds.toRect(page: page);
      if (r.left < minX) minX = r.left;
      if (r.right > maxX) maxX = r.right;
      if (r.top < minY) minY = r.top;
      if (r.bottom > maxY) maxY = r.bottom;
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

    // 5pt buckets for horizontal projection histogram
    const bucketSize = 5.0;
    final bucketCount = (page.width / bucketSize).ceil();
    final buckets = List<int>.filled(bucketCount, 0);

    for (final f in pageText.fragments) {
      final r = f.bounds.toRect(page: page);
      // Exclude wide cross-column elements (titles, wide figures, table banners)
      if (r.width > contentWidth * 0.65) continue;
      final start = (r.left / bucketSize).floor().clamp(0, bucketCount - 1);
      final end = (r.right / bucketSize).floor().clamp(0, bucketCount - 1);
      for (var b = start; b <= end; b++) {
        buckets[b]++;
      }
    }

    // Search for a column gutter (valley) in the middle 30% to 70% of content width
    final searchStart = ((minX + contentWidth * 0.3) / bucketSize).floor();
    final searchEnd = ((minX + contentWidth * 0.7) / bucketSize).floor();
    final rangeBuckets = buckets.sublist(
      (minX / bucketSize).floor(),
      (maxX / bucketSize).ceil().clamp(0, bucketCount),
    );
    final totalDensity = rangeBuckets.isEmpty ? 0 : rangeBuckets.reduce((a, b) => a + b);
    final avgDensity = totalDensity / math.max(1, contentWidth / bucketSize);

    int? bestGutterStart;
    int? bestGutterEnd;
    int currentGapLen = 0;
    int currentGapStart = 0;
    final threshold = (avgDensity * 0.15).ceil().clamp(1, 10);

    for (var i = searchStart; i <= searchEnd; i++) {
      if (buckets[i] <= threshold) {
        if (currentGapLen == 0) currentGapStart = i;
        currentGapLen++;
      } else {
        if (currentGapLen * bucketSize >= 8.0) {
          if (bestGutterStart == null || currentGapLen > (bestGutterEnd! - bestGutterStart)) {
            bestGutterStart = currentGapStart;
            bestGutterEnd = i;
          }
        }
        currentGapLen = 0;
      }
    }
    if (currentGapLen * bucketSize >= 8.0) {
      if (bestGutterStart == null || currentGapLen > (bestGutterEnd! - bestGutterStart)) {
        bestGutterStart = currentGapStart;
        bestGutterEnd = searchEnd;
      }
    }

    if (bestGutterStart != null && bestGutterEnd != null) {
      final gutterLeft = bestGutterStart * bucketSize;
      final gutterRight = bestGutterEnd * bucketSize;
      final col1 = Rect.fromLTRB(minX, minY, gutterLeft, maxY);
      final col2 = Rect.fromLTRB(gutterRight, minY, maxX, maxY);
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
