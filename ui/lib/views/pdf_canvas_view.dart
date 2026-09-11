import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';

const List<double> kZoomLadder = [
  0.25, 0.33, 0.50, 0.67, 0.75, 0.80, 0.90, 1.00,
  1.10, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00, 4.00, 5.00
];

/// Publication-grade layout for A4 documents:
/// - In Single-page mode: Centers pages vertically stacked.
/// - In Two-page spread mode: Pairs pages side-by-side (Row 0: Page 1 & 2, Row 1: Page 3 & 4)
///   with a subtle book gutter gap, giving a true book/magazine spread experience.
PdfPageLayout _layoutA4Pages(List<PdfPage> pages, PdfViewerParams params, {required bool isTwoPage}) {
  if (!isTwoPage || pages.length <= 1) {
    final width = pages.fold(0.0, (w, p) => math.max(w, p.width)) + params.margin * 2;
    final pageLayout = <Rect>[];
    var y = params.margin;
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final rect = Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height);
      pageLayout.add(rect);
      y += page.height + params.margin;
    }
    return PdfPageLayout(pageLayouts: pageLayout, documentSize: Size(width, y));
  } else {
    const pageGap = 16.0;
    double maxSpreadWidth = 0.0;
    for (var i = 0; i < pages.length; i += 2) {
      final p1 = pages[i];
      final p2 = (i + 1 < pages.length) ? pages[i + 1] : null;
      final rowWidth = p1.width + (p2 != null ? (p2.width + pageGap) : 0);
      maxSpreadWidth = math.max(maxSpreadWidth, rowWidth);
    }
    final totalDocWidth = maxSpreadWidth + params.margin * 2;
    final pageLayout = <Rect>[];
    var y = params.margin;

    for (var i = 0; i < pages.length; i += 2) {
      final p1 = pages[i];
      final p2 = (i + 1 < pages.length) ? pages[i + 1] : null;
      final rowHeight = p2 != null ? math.max(p1.height, p2.height) : p1.height;
      final rowWidth = p1.width + (p2 != null ? (p2.width + pageGap) : 0);
      final rowStartX = (totalDocWidth - rowWidth) / 2;

      // Left page
      final rect1 = Rect.fromLTWH(
        rowStartX,
        y + (rowHeight - p1.height) / 2,
        p1.width,
        p1.height,
      );
      pageLayout.add(rect1);

      // Right page
      if (p2 != null) {
        final rect2 = Rect.fromLTWH(
          rowStartX + p1.width + pageGap,
          y + (rowHeight - p2.height) / 2,
          p2.width,
          p2.height,
        );
        pageLayout.add(rect2);
      }

      y += rowHeight + params.margin;
    }

    return PdfPageLayout(pageLayouts: pageLayout, documentSize: Size(totalDocWidth, y));
  }
}

/// Sizing strategy tailor-made for SoGoodViewer.
///
/// 1. In Fluid Mode: The document is a single continuous tall page.
///    It NEVER computes vertical shrink `viewHeight / docHeight` (which would shrink
///    a 12000pt document into a tiny 50px sliver). It strictly anchors to horizontal
///    fit and maintains a safe floor scale (0.35).
/// 2. In A4 Two-Page Mode: Computes spread width and height across paired facing pages
///    to cleanly fit both pages on screen in full-page mode.
/// 3. Prevents jitter and reading position jumps during window resizing or zoom transitions.
class SoGoodSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  final bool isFluid;
  final bool isTwoPage;
  final double minScale;
  final double maxScale;

  const SoGoodSizeDelegateProvider({
    required this.isFluid,
    required this.isTwoPage,
    this.minScale = 0.35,
    this.maxScale = 5.0,
  });

  @override
  PdfViewerSizeDelegate create() => SoGoodSizeDelegate(
        isFluid: isFluid,
        isTwoPage: isTwoPage,
        minScale: minScale,
        maxScale: maxScale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoGoodSizeDelegateProvider &&
          other.isFluid == isFluid &&
          other.isTwoPage == isTwoPage &&
          other.minScale == minScale &&
          other.maxScale == maxScale;

  @override
  int get hashCode => Object.hash(isFluid, isTwoPage, minScale, maxScale);
}

class SoGoodSizeDelegate implements PdfViewerSizeDelegate {
  final bool isFluid;
  final bool isTwoPage;
  final double minScale;
  final double maxScale;

  PdfViewerController? _controller;

  SoGoodSizeDelegate({
    required this.isFluid,
    required this.isTwoPage,
    required this.minScale,
    required this.maxScale,
  });

  @override
  double get onePassRenderingScaleThreshold => 200 / 72;

  @override
  void init(PdfViewerController controller) {
    _controller = controller;
  }

  @override
  void dispose() {
    _controller = null;
  }

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) {
    if (layout == null || layout.documentSize.width <= 0) {
      return PdfViewerLayoutMetrics(
        minScale: minScale,
        maxScale: maxScale,
        coverScale: 1.0,
        alternativeFitScale: 1.0,
      );
    }

    final bmh = boundaryMargin?.horizontal == double.infinity ? 0.0 : boundaryMargin?.horizontal ?? 0.0;
    final bmv = boundaryMargin?.vertical == double.infinity ? 0.0 : boundaryMargin?.vertical ?? 0.0;

    if (isFluid) {
      // Fluid mode: continuous long page.
      // ALWAYS fit width, NEVER fit full 10,000pt height into viewport!
      final docWidth = layout.documentSize.width;
      final fitWidth = (viewSize.width - bmh - pageMargin * 2) / (docWidth > 0 ? docWidth : 800.0);
      final clampedFitWidth = fitWidth.clamp(minScale, maxScale);

      return PdfViewerLayoutMetrics(
        minScale: minScale,
        maxScale: maxScale,
        coverScale: clampedFitWidth,
        alternativeFitScale: clampedFitWidth,
      );
    } else {
      // Paged A4 mode
      if (isTwoPage && layout.pageLayouts.length > 1) {
        // Two-page spread
        final spreadWidth = layout.documentSize.width;
        final spreadHeight = layout.pageLayouts.first.height;
        final sX = (viewSize.width - bmh - pageMargin * 2) / spreadWidth;
        final sY = (viewSize.height - bmv - pageMargin * 2 - 32.0) / spreadHeight;
        final fitSpread = math.min(sX, sY).clamp(0.2, maxScale);
        final fitWidth = sX.clamp(0.2, maxScale);

        return PdfViewerLayoutMetrics(
          minScale: 0.2,
          maxScale: maxScale,
          coverScale: fitWidth,
          alternativeFitScale: fitSpread,
        );
      } else {
        // Single A4 page
        final page = (pageNumber != null && pageNumber >= 1 && pageNumber <= layout.pageLayouts.length)
            ? layout.pageLayouts[pageNumber - 1]
            : layout.pageLayouts.first;
        final sX = (viewSize.width - bmh - pageMargin * 2) / page.width;
        final sY = (viewSize.height - bmv - pageMargin * 2 - 32.0) / page.height;
        final fitPage = math.min(sX, sY).clamp(0.2, maxScale);
        final fitWidth = sX.clamp(0.2, maxScale);

        return PdfViewerLayoutMetrics(
          minScale: 0.2,
          maxScale: maxScale,
          coverScale: fitWidth,
          alternativeFitScale: fitPage,
        );
      }
    }
  }

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) {
    final controller = _controller;
    if (controller == null) return;

    if (isFluid) {
      final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
      final rawFitWidth = state.viewSize.width / docWidth;
      final initialZoom = (rawFitWidth > 1.35 ? 1.25 : rawFitWidth).clamp(minScale, maxScale);
      final center = Offset(docWidth / 2, 0);
      controller.setZoom(center, initialZoom, duration: Duration.zero);
    } else {
      final zoom = (alternativeFitScale ?? 1.0).clamp(0.2, maxScale);
      final page = layout.pageLayouts.first;
      controller.setZoom(page.center, zoom, duration: Duration.zero);
    }
  }

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    final controller = _controller;
    if (controller == null) return;

    if (isLayoutChanged) {
      final oldLayout = oldState.layout;
      final newLayout = newState.layout;
      if (oldLayout != null && newLayout != null && anchorPageNumber != null) {
        final hit = controller.getClosestPageHit(anchorPageNumber, oldLayout, oldVisibleRect);
        final pageNum = hit?.page.pageNumber ?? anchorPageNumber;
        final clampedPage = pageNum.clamp(1, newLayout.pageLayouts.length);
        final newRect = newLayout.pageLayouts[clampedPage - 1];
        controller.goToPosition(documentOffset: newRect.topLeft, zoom: currentZoom);
      }
      return;
    }

    if (isViewSizeChanged) {
      final oldSize = oldState.viewSize;
      final newSize = newState.viewSize;
      if (oldSize.width <= 0 || newSize.width <= 0) return;

      if (isFluid) {
        final oldCenterInDoc = controller.value.calcPosition(oldSize);
        final docWidth = newState.layout?.documentSize.width ?? 800.0;
        final clampedZoom = currentZoom.clamp(minScale, maxScale);
        final newMatrix = controller.calcMatrixFor(
          Offset(docWidth / 2, oldCenterInDoc.dy),
          zoom: clampedZoom,
          viewSize: newSize,
        );
        controller.stopInteractiveViewerAnimation();
        controller.value = newMatrix;
      } else {
        final oldCenterInDoc = controller.value.calcPosition(oldSize);
        final newMatrix = controller.calcMatrixFor(
          oldCenterInDoc,
          zoom: currentZoom.clamp(0.2, maxScale),
          viewSize: newSize,
        );
        controller.stopInteractiveViewerAnimation();
        controller.value = newMatrix;
      }
    }
  }
}

class SoGoodZoomStepsDelegateProvider extends PdfViewerZoomStepsDelegateProvider {
  final bool isFluid;

  const SoGoodZoomStepsDelegateProvider({required this.isFluid});

  @override
  PdfViewerZoomStepsDelegate create() => SoGoodZoomStepsDelegate(isFluid: isFluid);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SoGoodZoomStepsDelegateProvider && other.isFluid == isFluid;

  @override
  int get hashCode => isFluid.hashCode;
}

class SoGoodZoomStepsDelegate implements PdfViewerZoomStepsDelegate {
  final bool isFluid;
  SoGoodZoomStepsDelegate({required this.isFluid});

  @override
  void dispose() {}

  @override
  List<double> generateZoomStops(PdfViewerLayoutMetrics metrics) {
    final stops = <double>[];
    for (final step in kZoomLadder) {
      if (step >= metrics.minScale - 0.01 && step <= metrics.maxScale + 0.01) {
        stops.add(step);
      }
    }
    if (metrics.alternativeFitScale != null) {
      final fit = metrics.alternativeFitScale!;
      if (fit >= metrics.minScale && fit <= metrics.maxScale) {
        if (!stops.any((s) => (s - fit).abs() < 0.03)) {
          stops.add(fit);
        }
      }
    }
    stops.sort();
    return stops;
  }
}

class PdfCanvasView extends StatefulWidget {
  final Uint8List? pdfBytes;
  final String documentTitle;
  final ReaderController controller;
  final VoidCallback? onUserScrolled;
  final VoidCallback? onCanvasTapped;
  final VoidCallback? onOpenFile;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onExportPdf;
  final ValueChanged<double>? onZoomChanged;
  final void Function(int pageNumber, int pageCount)? onPageChanged;

  const PdfCanvasView({
    super.key,
    required this.pdfBytes,
    required this.documentTitle,
    required this.controller,
    this.onUserScrolled,
    this.onCanvasTapped,
    this.onOpenFile,
    this.onToggleSidebar,
    this.onExportPdf,
    this.onZoomChanged,
    this.onPageChanged,
  });

  @override
  State<PdfCanvasView> createState() => PdfCanvasViewState();
}

class PdfCanvasViewState extends State<PdfCanvasView> {
  late final PdfViewerController _pdfController;
  bool _isRestoringScroll = false;
  double _currentZoom = 1.0;
  int _lastReportedPage = 1;
  int _lastReportedCount = 1;

  double get currentZoom => _pdfController.isReady ? _pdfController.currentZoom : _currentZoom;
  bool get isReady => _pdfController.isReady;
  int get pageNumber => _pdfController.isReady ? (_pdfController.pageNumber ?? 1) : 1;
  int get pageCount => _pdfController.isReady ? _pdfController.pageCount : 1;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onPdfViewerChanged);
  }

  void _onPdfViewerChanged() {
    if (_isRestoringScroll) return;
    if (_pdfController.isReady) {
      final zoom = _pdfController.currentZoom;
      if ((zoom - _currentZoom).abs() > 0.005) {
        _currentZoom = zoom;
        widget.onZoomChanged?.call(_currentZoom);
      }

      final pageNum = _pdfController.pageNumber ?? 1;
      final pCount = _pdfController.pageCount;
      if (pageNum != _lastReportedPage || pCount != _lastReportedCount) {
        _lastReportedPage = pageNum;
        _lastReportedCount = pCount;
        widget.onPageChanged?.call(pageNum, pCount);
      }

      final docSize = _pdfController.documentSize;
      if (docSize.height > 0) {
        final ratio = (_pdfController.visibleRect.top / docSize.height).clamp(0.0, 1.0);
        widget.controller.updateScrollRatio(ratio);
      }
    }
  }

  void _restoreScroll() {
    final targetRatio = widget.controller.lastScrollRatio;
    if (_pdfController.isReady) {
      final docSize = _pdfController.documentSize;
      if (targetRatio > 0.0 && docSize.height > 0) {
        _isRestoringScroll = true;
        final targetY = targetRatio * docSize.height;
        _pdfController.goToPosition(documentOffset: Offset(0, targetY));

        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _isRestoringScroll = false;
          }
        });
      }
    }
  }

  Offset _calcStableZoomCenter(Offset? focalPoint) {
    if (focalPoint != null) return focalPoint;
    if (!_pdfController.isReady) return Offset.zero;
    final layout = _pdfController.layout;
    if (layout.pageLayouts.isEmpty) return _pdfController.centerPosition;

    if (widget.controller.renderOptions.isFluid) {
      final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
      return Offset(docWidth / 2, _pdfController.centerPosition.dy);
    } else {
      if (widget.controller.isTwoPage && layout.pageLayouts.length > 1) {
        final currentPage = _pdfController.pageNumber ?? 1;
        final spreadIndex = (currentPage - 1) ~/ 2;
        final leftIdx = spreadIndex * 2;
        final leftRect = layout.pageLayouts[leftIdx];
        final rightRect = (leftIdx + 1 < layout.pageLayouts.length)
            ? layout.pageLayouts[leftIdx + 1]
            : leftRect;
        return Offset(
          (leftRect.left + rightRect.right) / 2,
          (leftRect.top + leftRect.bottom) / 2,
        );
      } else {
        final pageIndex = ((_pdfController.pageNumber ?? 1) - 1).clamp(0, layout.pageLayouts.length - 1);
        return layout.pageLayouts[pageIndex].center;
      }
    }
  }

  Future<void> zoomIn({Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    final current = _pdfController.currentZoom;
    double target = current * 1.2;
    for (final step in kZoomLadder) {
      if (step > current + 0.02) {
        target = step;
        break;
      }
    }
    final minS = widget.controller.renderOptions.isFluid ? 0.35 : 0.2;
    target = target.clamp(minS, 5.0);
    final center = _calcStableZoomCenter(focalPoint);
    await _pdfController.setZoom(
      center,
      target,
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> zoomOut({Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    final current = _pdfController.currentZoom;
    double target = current / 1.2;
    for (var i = kZoomLadder.length - 1; i >= 0; i--) {
      final step = kZoomLadder[i];
      if (step < current - 0.02) {
        target = step;
        break;
      }
    }
    final minS = widget.controller.renderOptions.isFluid ? 0.35 : 0.2;
    target = target.clamp(minS, 5.0);
    final center = _calcStableZoomCenter(focalPoint);
    await _pdfController.setZoom(
      center,
      target,
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> resetZoom() async {
    if (!_pdfController.isReady) return;
    final center = _calcStableZoomCenter(null);
    await _pdfController.setZoom(
      center,
      1.0,
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> zoomTo(double targetZoom, {Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    final minS = widget.controller.renderOptions.isFluid ? 0.35 : 0.2;
    final center = _calcStableZoomCenter(focalPoint);
    await _pdfController.setZoom(
      center,
      targetZoom.clamp(minS, 5.0),
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> fitWidth() async {
    if (!_pdfController.isReady) return;
    final layout = _pdfController.layout;
    final viewWidth = _pdfController.viewSize.width;
    final margin = _pdfController.params.margin;

    final docWidth = layout.documentSize.width;
    if (docWidth <= 0) return;

    final targetZoom = ((viewWidth - margin * 2) / docWidth).clamp(0.2, 5.0);
    final center = _calcStableZoomCenter(null);
    await _pdfController.setZoom(
      center,
      targetZoom,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> fitPage() async {
    if (!_pdfController.isReady) return;
    final layout = _pdfController.layout;
    final pageLayouts = layout.pageLayouts;
    if (pageLayouts.isEmpty) return;

    final viewSize = _pdfController.viewSize;
    final margin = _pdfController.params.margin;

    if (widget.controller.renderOptions.isFluid) {
      final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
      final fitWidthZoom = (viewSize.width - margin * 2) / docWidth;
      final targetZoom = (fitWidthZoom < 1.15 ? fitWidthZoom : 1.15).clamp(0.35, 5.0);
      final center = _calcStableZoomCenter(null);
      await _pdfController.setZoom(
        center,
        targetZoom,
        duration: const Duration(milliseconds: 220),
      );
    } else {
      final isTwoPage = widget.controller.isTwoPage;
      if (isTwoPage && pageLayouts.length > 1) {
        final spreadWidth = layout.documentSize.width;
        final spreadHeight = pageLayouts.first.height;
        final zoomX = (viewSize.width - margin * 2) / spreadWidth;
        final zoomY = (viewSize.height - margin * 2 - 32.0) / spreadHeight;
        final targetZoom = math.min(zoomX, zoomY).clamp(0.2, 5.0);
        final center = _calcStableZoomCenter(null);
        await _pdfController.setZoom(
          center,
          targetZoom,
          duration: const Duration(milliseconds: 220),
        );
      } else {
        final pageIndex = ((_pdfController.pageNumber ?? 1) - 1).clamp(0, pageLayouts.length - 1);
        final page = pageLayouts[pageIndex];
        final zoomX = (viewSize.width - margin * 2) / page.width;
        final zoomY = (viewSize.height - margin * 2 - 32.0) / page.height;
        final targetZoom = math.min(zoomX, zoomY).clamp(0.2, 5.0);
        await _pdfController.setZoom(
          page.center,
          targetZoom,
          duration: const Duration(milliseconds: 220),
        );
      }
    }
  }

  Future<void> nextPage() async {
    if (!_pdfController.isReady) return;
    final pCount = _pdfController.pageCount;
    final currentPage = _pdfController.pageNumber ?? 1;
    final isTwoPage = widget.controller.isTwoPage && !widget.controller.renderOptions.isFluid;

    int targetPage;
    if (isTwoPage) {
      final spreadIndex = (currentPage - 1) ~/ 2;
      targetPage = (spreadIndex + 1) * 2 + 1;
    } else {
      targetPage = currentPage + 1;
    }

    if (targetPage > pCount) {
      targetPage = pCount;
      if (currentPage == pCount) return;
    }

    await _pdfController.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> prevPage() async {
    if (!_pdfController.isReady) return;
    final currentPage = _pdfController.pageNumber ?? 1;
    final isTwoPage = widget.controller.isTwoPage && !widget.controller.renderOptions.isFluid;

    int targetPage;
    if (isTwoPage) {
      final spreadIndex = (currentPage - 1) ~/ 2;
      targetPage = (spreadIndex - 1) * 2 + 1;
    } else {
      targetPage = currentPage - 1;
    }

    if (targetPage < 1) {
      targetPage = 1;
      if (currentPage == 1) return;
    }

    await _pdfController.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> goToPageNumber(int pageNumber) async {
    if (!_pdfController.isReady) return;
    final pCount = _pdfController.pageCount;
    final target = pageNumber.clamp(1, pCount);
    await _pdfController.goToPage(
      pageNumber: target,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> scrollByDelta(double deltaY) async {
    if (!_pdfController.isReady) return;
    final currentPos = _pdfController.visibleRect.topLeft;
    final targetY = (currentPos.dy + deltaY).clamp(0.0, _pdfController.documentSize.height);
    await _pdfController.goToPosition(
      documentOffset: Offset(currentPos.dx, targetY),
      duration: const Duration(milliseconds: 160),
    );
  }

  Future<bool> copyTextSelection() async {
    if (_pdfController.isReady) {
      return await _pdfController.textSelectionDelegate.copyTextSelection();
    }
    return false;
  }

  Future<void> selectAllText() async {
    if (_pdfController.isReady) {
      await _pdfController.textSelectionDelegate.selectAllText();
    }
  }

  void _enrichContextMenu(
    PdfViewerContextMenuBuilderParams params,
    List<ContextMenuButtonItem> items,
  ) {
    if (widget.onOpenFile != null) {
      items.add(
        ContextMenuButtonItem(
          label: '打开文件... (Cmd+O)',
          onPressed: () {
            params.dismissContextMenu();
            widget.onOpenFile!();
          },
        ),
      );
    }
    items.add(
      ContextMenuButtonItem(
        label: '放大页面 (Cmd+=)',
        onPressed: () {
          params.dismissContextMenu();
          zoomIn();
        },
      ),
    );
    items.add(
      ContextMenuButtonItem(
        label: '缩小页面 (Cmd+-)',
        onPressed: () {
          params.dismissContextMenu();
          zoomOut();
        },
      ),
    );
    items.add(
      ContextMenuButtonItem(
        label: '实际大小 100% (Cmd+0)',
        onPressed: () {
          params.dismissContextMenu();
          resetZoom();
        },
      ),
    );
    items.add(
      ContextMenuButtonItem(
        label: '满窗口 (适应宽度) (Cmd+9)',
        onPressed: () {
          params.dismissContextMenu();
          fitWidth();
        },
      ),
    );
    items.add(
      ContextMenuButtonItem(
        label: '满屏 (适应整页) (Cmd+1)',
        onPressed: () {
          params.dismissContextMenu();
          fitPage();
        },
      ),
    );
    if (!widget.controller.renderOptions.isFluid) {
      items.add(
        ContextMenuButtonItem(
          label: widget.controller.isTwoPage
              ? '切换为单页纵向浏览 (Cmd+D)'
              : '切换为双页对开浏览 (Cmd+D)',
          onPressed: () {
            params.dismissContextMenu();
            widget.controller.toggleTwoPage();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '上一页 (←)',
          onPressed: () {
            params.dismissContextMenu();
            prevPage();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '下一页 (→)',
          onPressed: () {
            params.dismissContextMenu();
            nextPage();
          },
        ),
      );
    }
    items.add(
      ContextMenuButtonItem(
        label: widget.controller.renderOptions.isFluid
            ? '切换为 A4 出版模式 (Cmd+P)'
            : '切换为自适应流式 (Cmd+P)',
        onPressed: () {
          params.dismissContextMenu();
          widget.controller.toggleMode();
        },
      ),
    );
    items.add(
      ContextMenuButtonItem(
        label: widget.controller.renderOptions.isDark
            ? '切换为明亮主题 (Cmd+T)'
            : '切换为暗黑主题 (Cmd+T)',
        onPressed: () {
          params.dismissContextMenu();
          widget.controller.toggleTheme();
        },
      ),
    );
    if (widget.onToggleSidebar != null) {
      items.add(
        ContextMenuButtonItem(
          label: '展开/收起侧边栏 (Cmd+B)',
          onPressed: () {
            params.dismissContextMenu();
            widget.onToggleSidebar!();
          },
        ),
      );
    }
    if (widget.onExportPdf != null) {
      items.add(
        ContextMenuButtonItem(
          label: '导出出版级 PDF... (Cmd+E)',
          onPressed: () {
            params.dismissContextMenu();
            widget.onExportPdf!();
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    _pdfController.removeListener(_onPdfViewerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pdfBytes == null || widget.pdfBytes!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            const SizedBox(height: 16),
            Text(
              '正在排版文档...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 13.5,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      );
    }

    final isDark = widget.controller.renderOptions.isDark;
    final canvasBg = isDark ? const Color(0xFF141414) : const Color(0xFFEBEBEB);

    return Scaffold(
      backgroundColor: canvasBg,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          widget.onUserScrolled?.call();
        },
        onPointerPanZoomUpdate: (_) {
          widget.onUserScrolled?.call();
        },
        child: PdfViewer.data(
          widget.pdfBytes!,
          key: ValueKey(
            '${widget.documentTitle}_${widget.pdfBytes!.hashCode}_${widget.controller.renderOptions.mode}_${widget.controller.isTwoPage}',
          ),
          sourceName: '${widget.documentTitle}_${widget.pdfBytes!.hashCode}',
          controller: _pdfController,
          params: PdfViewerParams(
            backgroundColor: canvasBg,
            margin: 16.0,
            boundaryMargin: const EdgeInsets.only(
              top: 48,
              bottom: 48,
              left: 24,
              right: 24,
            ),
            pageAnchor: PdfPageAnchor.top,
            underflowAnchor: PdfPageAnchor.top,
            pageDropShadow: BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 14,
              spreadRadius: 1,
              offset: const Offset(0, 4),
            ),
            layoutPages: widget.controller.renderOptions.isFluid
                ? null
                : (pages, params) => _layoutA4Pages(
                      pages,
                      params,
                      isTwoPage: widget.controller.isTwoPage,
                    ),
            sizeDelegateProvider: SoGoodSizeDelegateProvider(
              isFluid: widget.controller.renderOptions.isFluid,
              isTwoPage: widget.controller.isTwoPage,
              minScale: widget.controller.renderOptions.isFluid ? 0.35 : 0.2,
              maxScale: 5.0,
            ),
            zoomStepsDelegateProvider: SoGoodZoomStepsDelegateProvider(
              isFluid: widget.controller.renderOptions.isFluid,
            ),
            textSelectionParams: const PdfTextSelectionParams(
              enabled: true,
              showContextMenuAutomatically: true,
            ),
            onViewerReady: (document, controller) {
              _restoreScroll();
              final pNum = _pdfController.pageNumber ?? 1;
              final pCnt = _pdfController.pageCount;
              widget.onPageChanged?.call(pNum, pCnt);
            },
            onGeneralTap: (context, controller, details) {
              if (details.type == PdfViewerGeneralTapType.tap) {
                widget.onCanvasTapped?.call();
              }
              return false;
            },
            customizeContextMenuItems: (params, items) {
              _enrichContextMenu(params, items);
            },
            linkHandlerParams: PdfLinkHandlerParams(
              onLinkTap: (link) async {
                if (link.url != null && await canLaunchUrl(link.url!)) {
                  await launchUrl(link.url!);
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
