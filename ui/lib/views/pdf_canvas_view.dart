import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' as vec;
import '../controllers/reader_controller.dart';
import '../services/startup_metrics.dart';

const List<double> kZoomLadder = [
  0.25, 0.33, 0.50, 0.67, 0.75, 0.80, 0.90, 1.00,
  1.10, 1.25, 1.50, 1.75, 2.00, 2.50, 3.00, 4.00, 5.00
];

/// Seamless vertical layout for fluid documents:
/// Stacks continuous slices with 0 margin, forming an uninterrupted flow.
PdfPageLayout _layoutFluidPages(List<PdfPage> pages, PdfViewerParams params) {
  final width = pages.fold(0.0, (w, p) => math.max(w, p.width));
  final pageLayout = <Rect>[];
  var y = 0.0;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    final rect = Rect.fromLTWH(0, y, width, page.height + 0.5);
    pageLayout.add(rect);
    y += page.height;
  }
  return PdfPageLayout(pageLayouts: pageLayout, documentSize: Size(width, y));
}

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
    const pageGap = 12.0;
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

/// Sizing strategy tailor-made for SuperGoodViewer.
///
/// 1. In Fluid Mode: The document is a single continuous tall page.
///    It strictly anchors to horizontal fit and maintains a safe floor scale (0.35).
/// 2. In A4 Two-Page Mode: Computes spread width and height across paired facing pages
///    to cleanly fill both pages on screen in full-page / full-window mode.
/// 3. In Reload / Edit / Theme Toggle: Intelligently restores saved reading position.
class SuperGoodSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  final ReaderController readerController;
  final bool isFluid;
  final bool isTwoPage;
  final double minScale;
  final double maxScale;

  const SuperGoodSizeDelegateProvider({
    required this.readerController,
    required this.isFluid,
    required this.isTwoPage,
    this.minScale = 0.35,
    this.maxScale = 5.0,
  });

  @override
  PdfViewerSizeDelegate create() => SuperGoodSizeDelegate(
        readerController: readerController,
        isFluid: isFluid,
        isTwoPage: isTwoPage,
        minScale: minScale,
        maxScale: maxScale,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperGoodSizeDelegateProvider &&
          other.readerController == readerController &&
          other.isFluid == isFluid &&
          other.isTwoPage == isTwoPage &&
          other.minScale == minScale &&
          other.maxScale == maxScale;

  @override
  int get hashCode => Object.hash(readerController, isFluid, isTwoPage, minScale, maxScale);
}

typedef SoGoodSizeDelegateProvider = SuperGoodSizeDelegateProvider;
typedef SoGoodSizeDelegate = SuperGoodSizeDelegate;

class SuperGoodSizeDelegate implements PdfViewerSizeDelegate {
  final ReaderController readerController;
  final bool isFluid;
  final bool isTwoPage;
  final double minScale;
  final double maxScale;

  PdfViewerController? _controller;

  SuperGoodSizeDelegate({
    required this.readerController,
    required this.isFluid,
    required this.isTwoPage,
    required this.minScale,
    required this.maxScale,
  });

  @override
  double get onePassRenderingScaleThreshold => isFluid ? 1.2 : 200 / 72;

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
      final docWidth = layout.documentSize.width;
      final fitWidth = (viewSize.width - bmh - pageMargin * 2) / (docWidth > 0 ? docWidth : 800.0);
      final clampedFitWidth = fitWidth.clamp(minScale, maxScale);
      final comfortableFit = (clampedFitWidth < 1.15 ? clampedFitWidth : 1.15).clamp(minScale, maxScale);

      return PdfViewerLayoutMetrics(
        minScale: minScale,
        maxScale: maxScale,
        coverScale: clampedFitWidth,
        alternativeFitScale: comfortableFit,
      );
    } else {
      // Paged A4 mode
      if (isTwoPage && layout.pageLayouts.length > 1) {
        // Two-page spread
        final p1 = layout.pageLayouts[0];
        final p2 = layout.pageLayouts[1];
        const pageGap = 12.0;
        final spreadWidth = p1.width + p2.width + pageGap;
        final spreadHeight = math.max(p1.height, p2.height);

        final sX = (viewSize.width - bmh - pageMargin * 2) / spreadWidth;
        final sY = (viewSize.height - bmv - pageMargin * 2) / spreadHeight;
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
        final sY = (viewSize.height - bmv - pageMargin * 2) / page.height;
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

    final fitMode = readerController.autoFitMode;
    final double initialZoom;
    if (fitMode == AutoFitMode.fitWidth) {
      initialZoom = coverScale.clamp(minScale, maxScale);
    } else if (fitMode == AutoFitMode.fitPage) {
      initialZoom = (alternativeFitScale ?? coverScale).clamp(minScale, maxScale);
    } else if (readerController.lastZoom > 0.1) {
      initialZoom = readerController.lastZoom.clamp(minScale, maxScale);
    } else if (isFluid) {
      final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
      final rawFitWidth = state.viewSize.width / docWidth;
      initialZoom = (rawFitWidth > 1.35 ? 1.25 : rawFitWidth).clamp(minScale, maxScale);
    } else {
      initialZoom = (alternativeFitScale ?? 1.0).clamp(0.2, maxScale);
    }

    if (readerController.isReloading) {
      // Restoring reading position after reload/theme/edit/session restore
      if (isFluid) {
        final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
        final targetY = readerController.lastScrollRatio * layout.documentSize.height;
        controller.setZoom(Offset(docWidth / 2, targetY), initialZoom, duration: Duration.zero);
        controller.goToPosition(documentOffset: Offset(0, targetY));
      } else {
        final targetPage = readerController.lastPageNumber.clamp(1, layout.pageLayouts.length);
        final page = layout.pageLayouts[targetPage - 1];
        controller.setZoom(page.center, initialZoom, duration: Duration.zero);
        controller.goToPage(pageNumber: targetPage, duration: Duration.zero);
      }
    } else {
      // Fresh document load
      if (isFluid) {
        final docWidth = layout.documentSize.width > 0 ? layout.documentSize.width : 800.0;
        final center = Offset(docWidth / 2, 0);
        controller.setZoom(center, initialZoom, duration: Duration.zero);
      } else {
        if (isTwoPage && layout.pageLayouts.length > 1) {
          final spreadCenter = Offset(layout.documentSize.width / 2, layout.pageLayouts.first.center.dy);
          controller.setZoom(spreadCenter, initialZoom, duration: Duration.zero);
        } else {
          final page = layout.pageLayouts.first;
          controller.setZoom(page.center, initialZoom, duration: Duration.zero);
        }
      }
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
        final fitMode = readerController.autoFitMode;
        final double targetZoom;
        if (fitMode == AutoFitMode.fitWidth) {
          targetZoom = newState.coverScale;
        } else if (fitMode == AutoFitMode.fitPage) {
          targetZoom = newState.alternativeFitScale ?? newState.coverScale;
        } else {
          targetZoom = currentZoom;
        }
        controller.goToPosition(documentOffset: newRect.topLeft, zoom: targetZoom);
      }
      return;
    }

    if (isViewSizeChanged) {
      final oldSize = oldState.viewSize;
      final newSize = newState.viewSize;
      if (oldSize.width <= 0 || newSize.width <= 0) return;

      final fitMode = readerController.autoFitMode;
      final double targetZoom;
      if (fitMode == AutoFitMode.fitWidth) {
        targetZoom = newState.coverScale;
      } else if (fitMode == AutoFitMode.fitPage) {
        targetZoom = (newState.alternativeFitScale ?? newState.coverScale);
      } else {
        targetZoom = currentZoom.clamp(minScale, maxScale);
      }

      if (isFluid) {
        final oldCenterInDoc = controller.value.calcPosition(oldSize);
        final docWidth = newState.layout?.documentSize.width ?? 800.0;
        final newMatrix = controller.calcMatrixFor(
          Offset(docWidth / 2, oldCenterInDoc.dy),
          zoom: targetZoom.clamp(minScale, maxScale),
          viewSize: newSize,
        );
        final clampedMatrix = controller.calcMatrixForClampedToNearestBoundary(
          newMatrix,
          viewSize: newSize,
        );
        controller.stopInteractiveViewerAnimation();
        controller.value = clampedMatrix;
      } else {
        Offset targetCenter;
        final layout = newState.layout;
        final currentPage = controller.pageNumber ?? 1;
        final oldCenterInDoc = controller.value.calcPosition(oldSize);
        if (layout != null && layout.pageLayouts.isNotEmpty) {
          double targetCenterX;
          if (isTwoPage && layout.pageLayouts.length > 1) {
            final spreadIndex = (currentPage - 1) ~/ 2;
            final leftIdx = (spreadIndex * 2).clamp(0, layout.pageLayouts.length - 1);
            final leftRect = layout.pageLayouts[leftIdx];
            final rightRect = (leftIdx + 1 < layout.pageLayouts.length)
                ? layout.pageLayouts[leftIdx + 1]
                : leftRect;
            targetCenterX = (leftRect.left + rightRect.right) / 2;
          } else {
            final pageIdx = (currentPage - 1).clamp(0, layout.pageLayouts.length - 1);
            targetCenterX = layout.pageLayouts[pageIdx].center.dx;
          }
          targetCenter = Offset(targetCenterX, oldCenterInDoc.dy);
        } else {
          targetCenter = oldCenterInDoc;
        }

        final newMatrix = controller.calcMatrixFor(
          targetCenter,
          zoom: targetZoom.clamp(0.2, maxScale),
          viewSize: newSize,
        );
        final clampedMatrix = controller.calcMatrixForClampedToNearestBoundary(
          newMatrix,
          viewSize: newSize,
        );
        controller.stopInteractiveViewerAnimation();
        controller.value = clampedMatrix;
      }
    }
  }
}

class SuperGoodZoomStepsDelegateProvider extends PdfViewerZoomStepsDelegateProvider {
  final bool isFluid;

  const SuperGoodZoomStepsDelegateProvider({required this.isFluid});

  @override
  PdfViewerZoomStepsDelegate create() => SuperGoodZoomStepsDelegate(isFluid: isFluid);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperGoodZoomStepsDelegateProvider && other.isFluid == isFluid;

  @override
  int get hashCode => isFluid.hashCode;
}

typedef SoGoodZoomStepsDelegateProvider = SuperGoodZoomStepsDelegateProvider;
typedef SoGoodZoomStepsDelegate = SuperGoodZoomStepsDelegate;

class SuperGoodZoomStepsDelegate implements PdfViewerZoomStepsDelegate {
  final bool isFluid;
  SuperGoodZoomStepsDelegate({required this.isFluid});

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

/// Physics-based desktop scroll delegate with velocity acceleration tailor-made for SuperGoodViewer.
///
/// Provides:
/// 1. Dynamic Mouse Wheel Acceleration:
///    - For slow scrolls (reading): 1:1 precision without jumping.
///    - For rapid scrolls (e.g. Logitech MX Master 3 free-spin or quick flicking):
///      Dynamically accelerates up to 4.5x based on wheel event frequency and velocity.
/// 2. Buttery Smooth Exponential Decay:
///    - Runs at display refresh rate (60/120Hz ProMotion on macOS).
///    - Accumulates incoming wheel deltas into a smooth physics target.
/// 3. Zero-overshoot Boundary Clamping:
///    - Prevents bouncing or getting stuck at document edges.
class SuperGoodScrollInteractionDelegateProvider extends PdfViewerScrollInteractionDelegateProvider {
  final double panFriction;
  final double zoomFriction;
  final void Function(SuperGoodScrollInteractionDelegate delegate)? onDelegateCreated;

  const SuperGoodScrollInteractionDelegateProvider({
    this.panFriction = 13.5,
    this.zoomFriction = 12.0,
    this.onDelegateCreated,
  });

  @override
  PdfViewerScrollInteractionDelegate create() {
    final delegate = SuperGoodScrollInteractionDelegate(
      panFriction: panFriction,
      zoomFriction: zoomFriction,
    );
    onDelegateCreated?.call(delegate);
    return delegate;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperGoodScrollInteractionDelegateProvider &&
          other.panFriction == panFriction &&
          other.zoomFriction == zoomFriction;

  @override
  int get hashCode => Object.hash(panFriction, zoomFriction);
}

class SuperGoodScrollInteractionDelegate implements PdfViewerScrollInteractionDelegate {
  SuperGoodScrollInteractionDelegate({
    required this.panFriction,
    required this.zoomFriction,
  });

  final double panFriction;
  final double zoomFriction;

  PdfViewerController? _controller;
  TickerProvider? _vsync;

  // --- Pan Physics State ---
  Ticker? _panTicker;
  Offset? _panTarget;
  Duration? _lastPanFrameTime;

  // Acceleration tracking
  DateTime? _lastPanEventTime;
  double _currentMultiplier = 1.0;

  // --- Zoom Physics State ---
  Ticker? _zoomTicker;
  double? _zoomTarget;
  Duration? _lastZoomFrameTime;
  Offset? _lastFocalPoint;

  static const double _kEpsilon = 0.5;
  static const double _kScaleEpsilon = 0.0001;

  @override
  void init(PdfViewerController controller, TickerProvider vsync) {
    _controller = controller;
    _vsync = vsync;
  }

  @override
  void dispose() {
    stop();
    _controller = null;
    _vsync = null;
  }

  @override
  void stop() {
    _panTicker?.dispose();
    _panTicker = null;
    _panTarget = null;
    _lastPanFrameTime = null;
    _lastPanEventTime = null;
    _currentMultiplier = 1.0;

    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;
    _lastZoomFrameTime = null;
    _lastFocalPoint = null;
  }

  @override
  void pan(Offset delta, PdfViewerLayoutMetrics layoutMetrics) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) {
      return;
    }

    // Stop zoom if panning starts
    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;

    if (_panTarget == null) {
      final currentTrans = controller.value.getTranslation();
      _panTarget = Offset(currentTrans.x, currentTrans.y);
    }

    // Mouse wheel velocity acceleration curve:
    // When wheel events arrive in rapid succession (< 110ms), scale the delta smoothly
    final now = DateTime.now();
    double multiplier = 1.0;
    if (_lastPanEventTime != null) {
      final intervalMs = now.difference(_lastPanEventTime!).inMicroseconds / 1000.0;
      if (intervalMs < 110.0) {
        final freqFactor = (110.0 - intervalMs) / 110.0;
        final speed = delta.distance / math.max(1.0, intervalMs);
        final boost = math.pow(freqFactor, 1.25) * math.min(3.5, speed * 1.5);
        multiplier = (1.0 + boost).clamp(1.0, 4.5);
        _currentMultiplier = math.max(_currentMultiplier * 0.75, multiplier);
      } else {
        _currentMultiplier = 1.0;
      }
    } else {
      _currentMultiplier = 1.0;
    }
    _lastPanEventTime = now;

    final effectiveDelta = delta * _currentMultiplier;
    _panTarget = _panTarget! + effectiveDelta;

    if (_panTicker == null) {
      _lastPanFrameTime = null;
      _panTicker = vsync.createTicker(_onPanTick)..start();
    }
  }

  /// Smoothly scrolls the canvas by a logical screen delta (e.g. from keyboard arrow keys or page navigation).
  /// Unlike goToPosition, modifying the matrix directly preserves existing rendered bitmap tiles and
  /// prevents white blank flashing or flickering.
  void scrollByScreenDelta(Offset delta) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) {
      return;
    }

    // Stop zoom if panning starts
    _zoomTicker?.dispose();
    _zoomTicker = null;
    _zoomTarget = null;

    if (_panTarget == null) {
      final currentTrans = controller.value.getTranslation();
      _panTarget = Offset(currentTrans.x, currentTrans.y);
    }

    // Key repeat acceleration:
    // When arrow keys are held down or pressed in quick succession (< 140ms),
    // scale delta with smooth physics acceleration
    final now = DateTime.now();
    double multiplier = 1.0;
    if (_lastPanEventTime != null) {
      final intervalMs = now.difference(_lastPanEventTime!).inMicroseconds / 1000.0;
      if (intervalMs < 140.0) {
        final freqFactor = (140.0 - intervalMs) / 140.0;
        final boost = math.pow(freqFactor, 1.2) * 1.5;
        multiplier = (1.0 + boost).clamp(1.0, 3.5);
        _currentMultiplier = math.max(_currentMultiplier * 0.8, multiplier);
      } else {
        _currentMultiplier = 1.0;
      }
    } else {
      _currentMultiplier = 1.0;
    }
    _lastPanEventTime = now;

    final effectiveDelta = delta * _currentMultiplier;
    _panTarget = _panTarget! + effectiveDelta;

    if (_panTicker == null) {
      _lastPanFrameTime = null;
      _panTicker = vsync.createTicker(_onPanTick)..start();
    }
  }

  void _onPanTick(Duration elapsed) {
    final controller = _controller;
    if (controller == null || _panTarget == null) {
      _panTicker?.dispose();
      _panTicker = null;
      return;
    }

    final dt = _lastPanFrameTime == null
        ? (1.0 / 60.0)
        : (elapsed - _lastPanFrameTime!).inMicroseconds / 1000000.0;
    _lastPanFrameTime = elapsed;

    final currentTransVec = controller.value.getTranslation();
    final currentTrans = Offset(currentTransVec.x, currentTransVec.y);
    final diff = _panTarget! - currentTrans;

    if (diff.distance < _kEpsilon) {
      _applyTranslation(_panTarget!);
      _panTicker?.dispose();
      _panTicker = null;
      _panTarget = null;
      _lastPanFrameTime = null;
      return;
    }

    final alpha = 1.0 - math.exp(-panFriction * dt);
    final newTrans = currentTrans + diff * alpha;
    _applyTranslation(newTrans);
  }

  void _applyTranslation(Offset translation) {
    final controller = _controller;
    if (controller == null) return;

    final currentMatrix = controller.value;
    final newMatrix = currentMatrix.clone();
    newMatrix.setTranslation(vec.Vector3(translation.dx, translation.dy, 0.0));

    controller.value = controller.makeMatrixInSafeRange(newMatrix, forceClamp: true);

    final actualTransVec = controller.value.getTranslation();
    final actualTrans = Offset(actualTransVec.x, actualTransVec.y);

    if (_panTarget != null) {
      if ((actualTrans.dx - translation.dx).abs() > 1.0) {
        _panTarget = Offset(actualTrans.dx, _panTarget!.dy);
      }
      if ((actualTrans.dy - translation.dy).abs() > 1.0) {
        _panTarget = Offset(_panTarget!.dx, actualTrans.dy);
      }
    }
  }

  @override
  void zoom(double scaleFactor, Offset focalPoint, PdfViewerLayoutMetrics layoutMetrics) {
    final controller = _controller;
    final vsync = _vsync;
    if (controller == null || !controller.isReady || vsync == null) return;

    _panTicker?.dispose();
    _panTicker = null;
    _panTarget = null;

    final currentZoom = controller.currentZoom;
    _zoomTarget ??= currentZoom;
    _zoomTarget = (_zoomTarget! * scaleFactor).clamp(layoutMetrics.minScale, layoutMetrics.maxScale);
    _lastFocalPoint = focalPoint;

    if (_zoomTicker == null) {
      _lastZoomFrameTime = null;
      _zoomTicker = vsync.createTicker(_onZoomTick)..start();
    }
  }

  void _onZoomTick(Duration elapsed) {
    final controller = _controller;
    if (controller == null || _zoomTarget == null || _lastFocalPoint == null) {
      _zoomTicker?.dispose();
      _zoomTicker = null;
      return;
    }

    final dt = _lastZoomFrameTime == null ? 1.0 / 60.0 : (elapsed - _lastZoomFrameTime!).inMicroseconds / 1000000.0;
    _lastZoomFrameTime = elapsed;

    final currentZoom = controller.currentZoom;
    final diff = _zoomTarget! - currentZoom;

    if (diff.abs() < _kScaleEpsilon) {
      controller.zoomOnLocalPosition(localPosition: _lastFocalPoint!, newZoom: _zoomTarget!, duration: Duration.zero);
      _zoomTicker?.dispose();
      _zoomTicker = null;
      _zoomTarget = null;
      _lastZoomFrameTime = null;
      return;
    }

    final alpha = 1.0 - math.exp(-zoomFriction * dt);
    final newZoom = currentZoom + diff * alpha;
    controller.zoomOnLocalPosition(localPosition: _lastFocalPoint!, newZoom: newZoom, duration: Duration.zero);
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
  final VoidCallback? onTextCopied;
  final void Function({required double deltaY, required bool isAtTop})? onScrollChanged;

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
    this.onTextCopied,
    this.onScrollChanged,
  });

  @override
  State<PdfCanvasView> createState() => PdfCanvasViewState();
}

class PdfCanvasViewState extends State<PdfCanvasView> {
  int _activeSlot = 0;
  int? _pendingSlot;
  Timer? _cleanupTimer;
  final List<PdfViewerController> _controllers = [
    PdfViewerController(),
    PdfViewerController(),
  ];
  final List<Uint8List?> _slotBytes = [null, null];
  final List<int> _slotDocHash = [0, 0];
  final List<SuperGoodScrollInteractionDelegate?> _scrollDelegates = [null, null];
  bool _isRestoringScroll = false;
  bool _isProgrammaticZooming = false;
  double _currentZoom = 1.0;
  int _lastReportedPage = 1;
  int _lastReportedCount = 1;
  double _lastVisibleTop = 0.0;
  bool _lastReportedAtTop = true;
  bool _renderOptionsChanged = false;

  PdfViewerController get _pdfController => _controllers[_activeSlot];
  double get currentZoom => _pdfController.isReady ? _pdfController.currentZoom : _currentZoom;
  bool get isReady => _pdfController.isReady;
  int get pageNumber => _pdfController.isReady ? (_pdfController.pageNumber ?? 1) : 1;
  int get pageCount => _pdfController.isReady ? _pdfController.pageCount : 1;

  @override
  void initState() {
    super.initState();
    _slotBytes[0] = widget.pdfBytes;
    _slotDocHash[0] = widget.pdfBytes?.hashCode ?? 0;
    _activeSlot = 0;
    _pendingSlot = null;
    _controllers[0].addListener(_onViewerChanged0);
    _controllers[1].addListener(_onViewerChanged1);
  }

  void _onViewerChanged0() => _onPdfViewerChanged(0);
  void _onViewerChanged1() => _onPdfViewerChanged(1);

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _controllers[0].removeListener(_onViewerChanged0);
    _controllers[1].removeListener(_onViewerChanged1);
    super.dispose();
  }

  @override
  void didUpdateWidget(PdfCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newBytes = widget.pdfBytes;
    if (newBytes == null || newBytes.isEmpty) return;

    if (_slotBytes[_activeSlot] == null) {
      _slotBytes[_activeSlot] = newBytes;
      _slotDocHash[_activeSlot] = newBytes.hashCode;
      setState(() {});
      return;
    }

    if (newBytes.hashCode != _slotDocHash[_activeSlot]) {
      final optionsChanged = widget.controller.renderOptions != oldWidget.controller.renderOptions ||
          widget.controller.isTwoPage != oldWidget.controller.isTwoPage ||
          widget.documentTitle != oldWidget.documentTitle;
      if (optionsChanged) {
        _renderOptionsChanged = true;
      }

      if (widget.controller.renderOptions.mode != oldWidget.controller.renderOptions.mode ||
          widget.controller.isTwoPage != oldWidget.controller.isTwoPage ||
          widget.documentTitle != oldWidget.documentTitle) {
        // Mode change or different document opened: direct reload
        _cleanupTimer?.cancel();
        _activeSlot = 0;
        _pendingSlot = null;
        _slotBytes[0] = newBytes;
        _slotDocHash[0] = newBytes.hashCode;
        _slotBytes[1] = null;
        _slotDocHash[1] = 0;
        setState(() {});
      } else {
        // Same document updated (hot reload / edit / theme / mode):
        // Mount into background slot for seamless double buffering
        _cleanupTimer?.cancel();
        final nextSlot = 1 - _activeSlot;
        _pendingSlot = nextSlot;
        _slotBytes[nextSlot] = newBytes;
        _slotDocHash[nextSlot] = newBytes.hashCode;
        setState(() {});
      }
    }
  }

  void _onPdfViewerChanged(int slot) {
    if (slot != _activeSlot) return;
    if (_isRestoringScroll || widget.controller.isReloading) return;
    final ctrl = _controllers[slot];
    if (ctrl.isReady) {
      final zoom = ctrl.currentZoom;
      if ((zoom - _currentZoom).abs() > 0.005) {
        _currentZoom = zoom;
        widget.controller.updateZoom(zoom);
        widget.onZoomChanged?.call(_currentZoom);

        if (!_isProgrammaticZooming) {
          final mode = widget.controller.autoFitMode;
          if (mode == AutoFitMode.fitWidth) {
            final expected = ctrl.coverScale;
            if ((zoom - expected).abs() > 0.06) {
              widget.controller.setAutoFitMode(AutoFitMode.none);
            }
          } else if (mode == AutoFitMode.fitPage) {
            final expected = ctrl.alternativeFitScale ?? ctrl.coverScale;
            if ((zoom - expected).abs() > 0.06) {
              widget.controller.setAutoFitMode(AutoFitMode.none);
            }
          }
        }
      }

      final pageNum = ctrl.pageNumber ?? 1;
      final pCount = ctrl.pageCount;
      if (pageNum != _lastReportedPage || pCount != _lastReportedCount) {
        _lastReportedPage = pageNum;
        _lastReportedCount = pCount;
        widget.controller.updatePageNumber(pageNum);
        widget.onPageChanged?.call(pageNum, pCount);
      }

      final docSize = ctrl.documentSize;
      final currentTop = ctrl.visibleRect.top;
      if (docSize.height > 0) {
        final ratio = (currentTop / docSize.height).clamp(0.0, 1.0);
        widget.controller.updateScrollRatio(ratio, offset: currentTop);
      }
      final deltaY = currentTop - _lastVisibleTop;
      final isFluid = widget.controller.renderOptions.isFluid;
      final isTwoPage = widget.controller.isTwoPage && !isFluid;
      final isAtTop = isFluid
          ? (currentTop <= 20.0)
          : (pageNum <= (isTwoPage ? 2 : 1) && currentTop <= 20.0);
      final effectiveAtTop = isAtTop && deltaY <= 0.5;

      if (deltaY.abs() > 0.5 || effectiveAtTop != _lastReportedAtTop) {
        _lastVisibleTop = currentTop;
        _lastReportedAtTop = effectiveAtTop;
        widget.onScrollChanged?.call(deltaY: deltaY, isAtTop: effectiveAtTop);
      }
    }
  }

  void _restoreScrollFor(PdfViewerController ctrl) {
    if (!ctrl.isReady) {
      widget.controller.finishReloading();
      return;
    }
    final docSize = ctrl.documentSize;
    final isFluid = widget.controller.renderOptions.isFluid;

    if (isFluid) {
      final targetOffset = widget.controller.lastScrollOffset;
      final targetRatio = widget.controller.lastScrollRatio;
      if (docSize.height > 0) {
        final visibleHeight = ctrl.visibleRect.height > 0 ? ctrl.visibleRect.height : 600.0;
        final maxScroll = math.max(0.0, docSize.height - visibleHeight);

        // When render options changed (font size, font family, theme, window width),
        // total document height changed, so ratio is the accurate anchor.
        // When options are identical (streaming content append / external edit),
        // use absolute offset to prevent reading position from jumping.
        final useOffset = !_renderOptionsChanged && targetOffset > 0.0;
        final targetY = useOffset
            ? targetOffset.clamp(0.0, maxScroll)
            : (targetRatio > 0.0 ? (targetRatio * docSize.height).clamp(0.0, maxScroll) : 0.0);

        _renderOptionsChanged = false;

        if (targetY > 0.0) {
          _isRestoringScroll = true;
          ctrl.goToPosition(documentOffset: Offset(0, targetY));

          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted) {
              _isRestoringScroll = false;
              _lastVisibleTop = targetY;
              final isAtTop = targetY <= 20.0;
              _lastReportedAtTop = isAtTop;
              widget.onScrollChanged?.call(deltaY: 0, isAtTop: isAtTop);
            }
            widget.controller.finishReloading();
          });
          return;
        }
      }
    } else {
      _renderOptionsChanged = false;
      final targetPage = widget.controller.lastPageNumber;
      if (targetPage > 1 && targetPage <= ctrl.pageCount) {
        _isRestoringScroll = true;
        ctrl.goToPage(pageNumber: targetPage, duration: Duration.zero);

        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted) {
            _isRestoringScroll = false;
            _lastReportedAtTop = false;
            widget.onScrollChanged?.call(deltaY: 0, isAtTop: false);
          }
          widget.controller.finishReloading();
        });
        return;
      }
    }
    _lastReportedAtTop = true;
    widget.onScrollChanged?.call(deltaY: 0, isAtTop: true);
    widget.controller.finishReloading();
  }

  void _restoreScroll() => _restoreScrollFor(_pdfController);

  Future<void> jumpToOutline(OutlineItem item) async {
    if (!_pdfController.isReady) return;
    try {
      final outlines = await _pdfController.document.loadOutline();
      final targetNode = _findOutlineNode(outlines, item.title);
      if (targetNode?.dest != null) {
        await _pdfController.goToDest(targetNode!.dest);
        return;
      }
    } catch (_) {}

    final totalLines = math.max(1, widget.controller.currentMarkdown.split('\n').length);
    final ratio = ((item.lineNumber - 1) / totalLines).clamp(0.0, 1.0);

    if (widget.controller.renderOptions.isFluid) {
      final docHeight = _pdfController.documentSize.height;
      if (docHeight > 0) {
        await _pdfController.goToPosition(
          documentOffset: Offset(0, docHeight * ratio),
          duration: const Duration(milliseconds: 200),
        );
      }
    } else {
      final pageCount = _pdfController.pageCount;
      final targetPage = (1 + (ratio * (pageCount - 1)).round()).clamp(1, pageCount);
      await _pdfController.goToPage(
        pageNumber: targetPage,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  PdfOutlineNode? _findOutlineNode(List<PdfOutlineNode> nodes, String title) {
    for (final node in nodes) {
      final t = node.title.trim();
      final q = title.trim();
      if (t == q || t.contains(q) || q.contains(t)) {
        return node;
      }
      final child = _findOutlineNode(node.children, title);
      if (child != null) return child;
    }
    return null;
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
    widget.controller.setAutoFitMode(AutoFitMode.none);
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
    _isProgrammaticZooming = true;
    try {
      await _pdfController.setZoom(
        center,
        target,
        duration: const Duration(milliseconds: 180),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 200), () {
        _isProgrammaticZooming = false;
      });
    }
  }

  Future<void> zoomOut({Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    widget.controller.setAutoFitMode(AutoFitMode.none);
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
    _isProgrammaticZooming = true;
    try {
      await _pdfController.setZoom(
        center,
        target,
        duration: const Duration(milliseconds: 180),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 200), () {
        _isProgrammaticZooming = false;
      });
    }
  }

  Future<void> resetZoom() async {
    if (!_pdfController.isReady) return;
    widget.controller.setAutoFitMode(AutoFitMode.none);
    final center = _calcStableZoomCenter(null);
    _isProgrammaticZooming = true;
    try {
      await _pdfController.setZoom(
        center,
        1.0,
        duration: const Duration(milliseconds: 180),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 200), () {
        _isProgrammaticZooming = false;
      });
    }
  }

  Future<void> zoomTo(double targetZoom, {Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    widget.controller.setAutoFitMode(AutoFitMode.none);
    final minS = widget.controller.renderOptions.isFluid ? 0.35 : 0.2;
    final center = _calcStableZoomCenter(focalPoint);
    _isProgrammaticZooming = true;
    try {
      await _pdfController.setZoom(
        center,
        targetZoom.clamp(minS, 5.0),
        duration: const Duration(milliseconds: 180),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 200), () {
        _isProgrammaticZooming = false;
      });
    }
  }

  Future<void> fitWidth() async {
    if (!_pdfController.isReady) return;
    widget.controller.setAutoFitMode(AutoFitMode.fitWidth);
    _isProgrammaticZooming = true;
    try {
      final targetZoom = _pdfController.coverScale;
      final center = _calcStableZoomCenter(null);
      await _pdfController.setZoom(
        center,
        targetZoom,
        duration: const Duration(milliseconds: 200),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 220), () {
        _isProgrammaticZooming = false;
      });
    }
  }

  Future<void> fitPage() async {
    if (!_pdfController.isReady) return;
    widget.controller.setAutoFitMode(AutoFitMode.fitPage);
    _isProgrammaticZooming = true;
    try {
      final targetZoom = _pdfController.alternativeFitScale ?? _pdfController.coverScale;
      final center = _calcStableZoomCenter(null);
      await _pdfController.setZoom(
        center,
        targetZoom,
        duration: const Duration(milliseconds: 200),
      );
    } finally {
      Future.delayed(const Duration(milliseconds: 220), () {
        _isProgrammaticZooming = false;
      });
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
    final delegate = _scrollDelegates[_activeSlot];
    if (delegate != null && _pdfController.isReady) {
      final zoom = currentZoom;
      // In screen coordinates, scrolling DOWN (deltaY > 0) translates the viewport UP (negative Y)
      final screenDeltaY = -deltaY * zoom;
      delegate.scrollByScreenDelta(Offset(0, screenDeltaY));
      return;
    }

    if (!_pdfController.isReady) return;
    final currentPos = _pdfController.visibleRect.topLeft;
    final targetY = (currentPos.dy + deltaY).clamp(0.0, _pdfController.documentSize.height);
    await _pdfController.goToPosition(
      documentOffset: Offset(currentPos.dx, targetY),
      duration: const Duration(milliseconds: 160),
    );
  }

  /// Sanitizes text before passing to system clipboard.
  /// Fixes broken surrogate pairs, unmapped font codes, and null bytes that cause
  /// macOS NSJSONSerialization / FlutterJSONMessageCodec to abort/crash.
  static String sanitizeForClipboard(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    final len = text.length;
    for (var i = 0; i < len; i++) {
      final code = text.codeUnitAt(i);
      // Strip null characters from embedded font padding
      if (code == 0) continue;

      // Check for high surrogate (0xD800..0xDBFF)
      if (code >= 0xD800 && code <= 0xDBFF) {
        if (i + 1 < len) {
          final next = text.codeUnitAt(i + 1);
          if (next >= 0xDC00 && next <= 0xDFFF) {
            buffer.writeCharCode(code);
            buffer.writeCharCode(next);
            i++;
            continue;
          }
        }
        buffer.writeCharCode(0xFFFD);
        continue;
      }

      // Check for unpaired low surrogate (0xDC00..0xDFFF)
      if (code >= 0xDC00 && code <= 0xDFFF) {
        buffer.writeCharCode(0xFFFD);
        continue;
      }

      buffer.writeCharCode(code);
    }
    return buffer.toString();
  }

  Future<bool> _safeCopySelectedText(PdfTextSelectionDelegate delegate) async {
    if (!delegate.hasSelectedText || !delegate.isCopyAllowed) return false;
    try {
      final rawText = await delegate.getSelectedText();
      if (rawText.isEmpty) return false;
      final cleanText = sanitizeForClipboard(rawText);
      if (cleanText.isEmpty) return false;
      await Clipboard.setData(ClipboardData(text: cleanText));
      return true;
    } catch (e) {
      debugPrint('[Clipboard] Failed to copy text: $e');
      return false;
    }
  }

  Future<bool> copyTextSelection() async {
    if (_pdfController.isReady) {
      return await _safeCopySelectedText(_pdfController.textSelectionDelegate);
    }
    return false;
  }

  Future<void> selectAllText() async {
    if (_pdfController.isReady) {
      await _pdfController.textSelectionDelegate.selectAllText();
    }
  }

  Widget? _buildCustomContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final isText = params.contextMenuFor == PdfViewerPart.selectedText ||
        (params.isTextSelectionEnabled && params.textSelectionDelegate.hasSelectedText);

    final items = <ContextMenuButtonItem>[];

    if (isText) {
      // 1. Text Selection Context Menu: strictly text actions
      if (params.isTextSelectionEnabled && params.textSelectionDelegate.isCopyAllowed) {
        items.add(
          ContextMenuButtonItem(
            label: '复制 (Cmd+C)',
            type: ContextMenuButtonType.copy,
            onPressed: () async {
              params.dismissContextMenu();
              final copied = await _safeCopySelectedText(params.textSelectionDelegate);
              if (copied && mounted) {
                widget.onTextCopied?.call();
              }
            },
          ),
        );
      }
      if (params.isTextSelectionEnabled && !params.textSelectionDelegate.isSelectingAllText) {
        items.add(
          ContextMenuButtonItem(
            label: '全选 (Cmd+A)',
            type: ContextMenuButtonType.selectAll,
            onPressed: () {
              params.dismissContextMenu();
              params.textSelectionDelegate.selectAllText();
            },
          ),
        );
      }
    } else {
      // 2. Canvas / Background Context Menu: document & view actions
      if (params.isTextSelectionEnabled) {
        items.add(
          ContextMenuButtonItem(
            label: '全选文本 (Cmd+A)',
            type: ContextMenuButtonType.selectAll,
            onPressed: () {
              params.dismissContextMenu();
              params.textSelectionDelegate.selectAllText();
            },
          ),
        );
      }
      items.add(
        ContextMenuButtonItem(
          label: '满窗口 (适应宽度) (${widget.controller.shortcutService.getShortcutLabel('fitWidth')})',
          onPressed: () {
            params.dismissContextMenu();
            fitWidth();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '满屏 (适应整页) (${widget.controller.shortcutService.getShortcutLabel('fitPage')})',
          onPressed: () {
            params.dismissContextMenu();
            fitPage();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '实际大小 100% (${widget.controller.shortcutService.getShortcutLabel('resetZoom')})',
          onPressed: () {
            params.dismissContextMenu();
            resetZoom();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '放大 (${widget.controller.shortcutService.getShortcutLabel('zoomIn')})',
          onPressed: () {
            params.dismissContextMenu();
            zoomIn();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '缩小 (${widget.controller.shortcutService.getShortcutLabel('zoomOut')})',
          onPressed: () {
            params.dismissContextMenu();
            zoomOut();
          },
        ),
      );
      if (!widget.controller.renderOptions.isFluid) {
        items.add(
          ContextMenuButtonItem(
            label: widget.controller.isTwoPage
                ? '切换为单页纵向浏览 (${widget.controller.shortcutService.getShortcutLabel('toggleTwoPage')})'
                : '切换为双页对开浏览 (${widget.controller.shortcutService.getShortcutLabel('toggleTwoPage')})',
            onPressed: () {
              params.dismissContextMenu();
              widget.controller.toggleTwoPage();
            },
          ),
        );
      }
      items.add(
        ContextMenuButtonItem(
          label: widget.controller.renderOptions.isFluid
              ? '切换为 A4 出版模式 (${widget.controller.shortcutService.getShortcutLabel('toggleMode')})'
              : '切换为自适应流式 (${widget.controller.shortcutService.getShortcutLabel('toggleMode')})',
          onPressed: () {
            params.dismissContextMenu();
            widget.controller.toggleMode();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: widget.controller.renderOptions.isDark
              ? '切换为明亮主题 (${widget.controller.shortcutService.getShortcutLabel('toggleTheme')})'
              : '切换为暗黑主题 (${widget.controller.shortcutService.getShortcutLabel('toggleTheme')})',
          onPressed: () {
            params.dismissContextMenu();
            widget.controller.toggleTheme();
          },
        ),
      );
      if (widget.onToggleSidebar != null) {
        items.add(
          ContextMenuButtonItem(
            label: '展开/收起侧边栏 (${widget.controller.shortcutService.getShortcutLabel('toggleSidebar')})',
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
            label: '导出出版级 PDF... (${widget.controller.shortcutService.getShortcutLabel('exportPdf')})',
            onPressed: () {
              params.dismissContextMenu();
              widget.onExportPdf!();
            },
          ),
        );
      }
    }

    if (items.isEmpty) return null;

    return Align(
      alignment: Alignment.topLeft,
      child: AdaptiveTextSelectionToolbar.buttonItems(
        anchors: TextSelectionToolbarAnchors(
          primaryAnchor: params.anchorA,
          secondaryAnchor: params.anchorB,
        ),
        buttonItems: items,
      ),
    );
  }

  Widget _buildPdfViewer(
    int slotIndex,
    Uint8List bytes,
    bool isDark,
    bool isFluid,
    Color canvasBg,
  ) {
    final ctrl = _controllers[slotIndex];
    return PdfViewer.data(
      bytes,
      initialPageNumber: isFluid ? 1 : widget.controller.lastPageNumber.clamp(1, 999999),
      key: ValueKey(
        'slot_${slotIndex}_${_slotDocHash[slotIndex]}_${widget.controller.renderOptions.mode}_${widget.controller.isTwoPage}',
      ),
      sourceName: '${widget.documentTitle}_slot_${slotIndex}_${_slotDocHash[slotIndex]}',
      controller: ctrl,
      params: PdfViewerParams(
        backgroundColor: canvasBg,
        scrollByMouseWheel: 1.0,
        interactionDelegateProvider: SuperGoodScrollInteractionDelegateProvider(
          onDelegateCreated: (delegate) => _scrollDelegates[slotIndex] = delegate,
        ),
        margin: isFluid ? 0.0 : 10.0,
        boundaryMargin: isFluid
            ? const EdgeInsets.only(top: 36, bottom: 24, left: 0, right: 0)
            : const EdgeInsets.only(top: 36, bottom: 16, left: 8, right: 8),
        maxImageBytesCachedOnMemory: 256 * 1024 * 1024,
        verticalCacheExtent: 1.5,
        pageBackgroundPaintCallbacks: [
          (canvas, rect, page) {
            canvas.drawRect(
              rect,
              Paint()..color = canvasBg,
            );
          },
        ],
        pageAnchor: PdfPageAnchor.top,
        underflowAnchor: PdfPageAnchor.top,
        pageDropShadow: isFluid
            ? null
            : BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 10,
                spreadRadius: 1,
                offset: const Offset(0, 3),
              ),
        behaviorControlParams: const PdfViewerBehaviorControlParams(
          enableLowResolutionPagePreview: true,
          trailingPageLoadingDelay: Duration.zero,
          pageImageCachingDelay: Duration.zero,
          partialImageLoadingDelay: Duration.zero,
        ),
        layoutPages: isFluid
            ? _layoutFluidPages
            : (pages, params) => _layoutA4Pages(
                  pages,
                  params,
                  isTwoPage: widget.controller.isTwoPage,
                ),
        sizeDelegateProvider: SuperGoodSizeDelegateProvider(
          readerController: widget.controller,
          isFluid: isFluid,
          isTwoPage: widget.controller.isTwoPage,
          minScale: isFluid ? 0.35 : 0.2,
          maxScale: 5.0,
        ),
        zoomStepsDelegateProvider: SuperGoodZoomStepsDelegateProvider(
          isFluid: widget.controller.renderOptions.isFluid,
        ),
        textSelectionParams: const PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: false,
        ),
        onViewerReady: (document, controller) {
          StartupMetrics.markFirstDocument();
          if (slotIndex == _pendingSlot) {
            _restoreScrollFor(controller);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _pendingSlot == slotIndex) {
                setState(() {
                  _activeSlot = slotIndex;
                  _pendingSlot = null;
                });
                _cleanupTimer?.cancel();
                _cleanupTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted && _pendingSlot == null) {
                    setState(() {
                      _slotBytes[1 - _activeSlot] = null;
                      _slotDocHash[1 - _activeSlot] = 0;
                    });
                  }
                });
              }
            });
          } else if (slotIndex == _activeSlot) {
            _restoreScroll();
          }
          final pNum = _pdfController.pageNumber ?? 1;
          final pCnt = _pdfController.pageCount;
          widget.onPageChanged?.call(pNum, pCnt);
        },
        onGeneralTap: (context, controller, details) {
          if (details.type == PdfViewerGeneralTapType.doubleTap) {
            controller.textSelectionDelegate.selectWord(details.documentPosition);
            return true;
          }
          if (details.type == PdfViewerGeneralTapType.secondaryTap) {
            if (details.tapOn == PdfViewerPart.nonSelectedText) {
              controller.textSelectionDelegate.selectWord(details.documentPosition);
            }
          }
          if (details.type == PdfViewerGeneralTapType.tap) {
            if (details.tapOn == PdfViewerPart.background) {
              widget.onCanvasTapped?.call();
            }
          }
          return false;
        },
        buildContextMenu: (context, params) => _buildCustomContextMenu(context, params),
        linkHandlerParams: PdfLinkHandlerParams(
          linkColor: Colors.transparent,
          onLinkTap: (link) async {
            if (link.dest != null) {
              await ctrl.goToDest(link.dest);
            } else if (link.url != null) {
              final uri = link.url!;
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveBytes = _slotBytes[_activeSlot] != null && _slotBytes[_activeSlot]!.isNotEmpty;
    final hasPendingBytes = _pendingSlot != null &&
        _slotBytes[_pendingSlot!] != null &&
        _slotBytes[_pendingSlot!]!.isNotEmpty;

    if (!hasActiveBytes && !hasPendingBytes) {
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
    final isFluid = widget.controller.renderOptions.isFluid;
    final canvasBg = isDark ? const Color(0xFF141414) : const Color(0xFFEBEBEB);

    final children = <Widget>[];
    final inactiveSlot = 1 - _activeSlot;

    // Inactive slot is mounted underneath in background
    if (_slotBytes[inactiveSlot] != null && _slotBytes[inactiveSlot]!.isNotEmpty) {
      children.add(
        Positioned.fill(
          key: ValueKey('slot_container_$inactiveSlot'),
          child: IgnorePointer(
            ignoring: true,
            child: _buildPdfViewer(
              inactiveSlot,
              _slotBytes[inactiveSlot]!,
              isDark,
              isFluid,
              canvasBg,
            ),
          ),
        ),
      );
    }

    // Active slot is mounted on top
    if (_slotBytes[_activeSlot] != null && _slotBytes[_activeSlot]!.isNotEmpty) {
      children.add(
        Positioned.fill(
          key: ValueKey('slot_container_$_activeSlot'),
          child: IgnorePointer(
            ignoring: false,
            child: _buildPdfViewer(
              _activeSlot,
              _slotBytes[_activeSlot]!,
              isDark,
              isFluid,
              canvasBg,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: canvasBg,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: (event) {
          if (_isRestoringScroll || widget.controller.isReloading) return;
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 1.0) {
              widget.onScrollChanged?.call(deltaY: event.scrollDelta.dy, isAtTop: false);
            }
          }
          widget.onUserScrolled?.call();
        },
        onPointerPanZoomUpdate: (event) {
          if (_isRestoringScroll || widget.controller.isReloading) return;
          if (event.panDelta.dy < -1.0) {
            widget.onScrollChanged?.call(deltaY: -event.panDelta.dy, isAtTop: false);
          }
          widget.onUserScrolled?.call();
        },
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: children,
          ),
        ),
      ),
    );
  }
}
