import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vector_math/vector_math_64.dart' as vec;
import '../controllers/reader_controller.dart';
import '../models/render_options.dart';

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
    final isLast = i == pages.length - 1;
    final rect = Rect.fromLTWH(0, y, width, page.height + (isLast ? 0.0 : 0.5));
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
  final double topInset;

  const SuperGoodSizeDelegateProvider({
    required this.readerController,
    required this.isFluid,
    required this.isTwoPage,
    this.minScale = 0.35,
    this.maxScale = 5.0,
    this.topInset = 0.0,
  });

  @override
  PdfViewerSizeDelegate create() => SuperGoodSizeDelegate(
        readerController: readerController,
        isFluid: isFluid,
        isTwoPage: isTwoPage,
        minScale: minScale,
        maxScale: maxScale,
        topInset: topInset,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SuperGoodSizeDelegateProvider &&
          other.readerController == readerController &&
          other.isFluid == isFluid &&
          other.isTwoPage == isTwoPage &&
          other.minScale == minScale &&
          other.maxScale == maxScale &&
          other.topInset == topInset;

  @override
  int get hashCode => Object.hash(readerController, isFluid, isTwoPage, minScale, maxScale, topInset);
}

typedef SoGoodSizeDelegateProvider = SuperGoodSizeDelegateProvider;
typedef SoGoodSizeDelegate = SuperGoodSizeDelegate;

class SuperGoodSizeDelegate implements PdfViewerSizeDelegate {
  final ReaderController readerController;
  final bool isFluid;
  final bool isTwoPage;
  final double minScale;
  final double maxScale;
  final double topInset;

  PdfViewerController? _controller;

  SuperGoodSizeDelegate({
    required this.readerController,
    required this.isFluid,
    required this.isTwoPage,
    required this.minScale,
    required this.maxScale,
    this.topInset = 0.0,
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
        final maxScroll = math.max(0.0, layout.documentSize.height - state.viewSize.height);
        final targetY = readerController.calculateFluidTargetScrollY(
          layout.documentSize.height,
          useOffset: !readerController.renderOptionsChanged,
          maxScroll: maxScroll,
        );
        if (targetY > ReaderController.topScrollThreshold) {
          controller.setZoom(Offset(docWidth / 2, targetY), initialZoom, duration: Duration.zero);
          controller.goToPosition(documentOffset: Offset(0, targetY));
        } else {
          final center = Offset(docWidth / 2, 0);
          controller.setZoom(center, initialZoom, duration: Duration.zero);
          final topDocOffset = initialZoom > 0 ? topInset / initialZoom : 0.0;
          if (topDocOffset > 0) {
            controller.goToPosition(documentOffset: Offset(0, -topDocOffset), duration: Duration.zero);
          }
        }
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
        final topDocOffset = initialZoom > 0 ? topInset / initialZoom : 0.0;
        if (topDocOffset > 0) {
          controller.goToPosition(documentOffset: Offset(0, -topDocOffset), duration: Duration.zero);
        }
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
  ///
  /// [accelerate] drives the key-repeat acceleration below, which is tuned for the
  /// small line-scroll delta of the arrow keys. Deltas that are already a full
  /// screen high must pass `false`: multiplying one by up to 3.5x would skip
  /// several screens of unread content per keypress.
  void scrollByScreenDelta(Offset delta, {bool accelerate = true}) {
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
    if (!accelerate) {
      // Neither consume nor leave behind an acceleration streak, so an
      // unaccelerated scroll cannot boost a following arrow key either.
      _currentMultiplier = 1.0;
      _lastPanEventTime = null;
    } else if (_lastPanEventTime != null) {
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
    if (accelerate) _lastPanEventTime = now;

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
  final RenderOptions renderOptions;
  final bool isTwoPage;
  final ReaderController controller;
  final VoidCallback? onUserScrolled;
  final VoidCallback? onCanvasTapped;
  final VoidCallback? onOpenFile;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onExportPdf;
  final ValueChanged<double>? onZoomChanged;
  final void Function(int pageNumber, int pageCount)? onPageChanged;
  final double topInset;
  final VoidCallback? onTextCopied;
  final void Function({required double deltaY, required bool isAtTop})? onScrollChanged;

  const PdfCanvasView({
    super.key,
    this.topInset = 0.0,
    required this.pdfBytes,
    required this.documentTitle,
    required this.renderOptions,
    required this.isTwoPage,
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
  Uint8List? _queuedBytes;
  Timer? _cleanupTimer;
  final List<PdfViewerController> _controllers = [
    PdfViewerController(),
    PdfViewerController(),
  ];
  final List<Uint8List?> _slotBytes = [null, null];
  final List<int> _slotDocHash = [0, 0];
  final List<SuperGoodScrollInteractionDelegate?> _scrollDelegates = [null, null];
  int _mountGeneration = 0;
  int _restoredGeneration = 0;
  bool _isProgrammaticZooming = false;
  double _currentZoom = 1.0;
  int _lastReportedPage = 1;
  int _lastReportedCount = 1;
  double _lastVisibleTop = 0.0;
  bool _lastReportedAtTop = true;
  bool _modeOrDocChanged = false;
  Timer? _pendingWatchdogTimer;
  Timer? _directReloadWatchdogTimer;
  bool _pendingViewerReady = false;
  bool _pendingImageLoaded = false;

  bool get _isRestoringScroll => _restoredGeneration < _mountGeneration;

  @visibleForTesting
  bool get renderOptionsChanged => widget.controller.renderOptionsChanged;

  @visibleForTesting
  bool get isRestoringScroll => _isRestoringScroll;

  @visibleForTesting
  void setRestoringScrollForTesting(bool value) {
    if (value) {
      _mountGeneration++;
    } else {
      _restoredGeneration = _mountGeneration;
    }
  }

  @visibleForTesting
  void restoreScrollForTesting() {
    widget.controller.renderOptionsChanged = false;
    _restoredGeneration = _mountGeneration;
  }

  PdfViewerController get _pdfController => _controllers[_activeSlot];
  @visibleForTesting
  PdfViewerController get pdfController => _pdfController;
  double get currentZoom => _pdfController.isReady ? _pdfController.currentZoom : _currentZoom;
  bool get isReady => _pdfController.isReady;
  int get pageNumber => _pdfController.isReady ? (_pdfController.pageNumber ?? 1) : 1;
  int get pageCount => _pdfController.isReady ? _pdfController.pageCount : 1;

  final List<PdfTextSearcher?> _textSearchers = [null, null];
  bool _isSearchOpen = false;
  late final TextEditingController _searchFieldController;
  late final FocusNode _searchFocusNode;
  int _searchMatchIndex = 0;
  int _searchTotalMatches = 0;
  bool _isSearchingText = false;

  PdfTextSearcher? get _activeSearcher => _textSearchers[_activeSlot];
  bool get isSearchOpen => _isSearchOpen;
  bool get isSearchFocused => _isSearchOpen && _searchFocusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _searchFieldController = TextEditingController();
    _searchFocusNode = FocusNode(onKeyEvent: _handleSearchKeyEvent);

    _slotBytes[0] = widget.pdfBytes;
    _slotDocHash[0] = widget.pdfBytes?.hashCode ?? 0;
    _activeSlot = 0;
    _pendingSlot = null;
    _mountGeneration = 1;
    _restoredGeneration = 0;
    _controllers[0].addListener(_onViewerChanged0);
    _controllers[1].addListener(_onViewerChanged1);
    if (widget.pdfBytes != null && widget.pdfBytes!.isNotEmpty) {
      _startDirectReloadWatchdog();
    }
  }

  void _onViewerChanged0() => _onPdfViewerChanged(0);
  void _onViewerChanged1() => _onPdfViewerChanged(1);

  void _onSearchUpdated() {
    if (!mounted) return;
    final searcher = _activeSearcher;
    setState(() {
      _isSearchingText = searcher?.isSearching ?? false;
      _searchTotalMatches = searcher?.matches.length ?? 0;
      _searchMatchIndex = (searcher?.currentIndex != null) ? searcher!.currentIndex! + 1 : 0;
    });
  }

  @override
  void dispose() {
    _cleanupTimer?.cancel();
    _pendingWatchdogTimer?.cancel();
    _directReloadWatchdogTimer?.cancel();
    _controllers[0].removeListener(_onViewerChanged0);
    _controllers[1].removeListener(_onViewerChanged1);
    for (final s in _textSearchers) {
      s?.removeListener(_onSearchUpdated);
      s?.dispose();
    }
    _searchFieldController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _startDirectReloadWatchdog() {
    _directReloadWatchdogTimer?.cancel();
    final targetGen = _mountGeneration;
    // 1500ms watchdog: If active slot direct reload (or initial load) fails to fire onViewerReady,
    // ensure _isRestoringScroll and readerController are safely unlocked.
    _directReloadWatchdogTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted && _restoredGeneration < targetGen) {
        debugPrint('[PdfCanvasView] Direct reload watchdog: onViewerReady timed out for gen $targetGen, unlocking scroll');
        _restoredGeneration = targetGen;
        widget.controller.renderOptionsChanged = false;
        widget.controller.finishReloading();
        setState(() {});
      }
    });
  }

  void _startPendingWatchdog() {
    _pendingWatchdogTimer?.cancel();
    // 5s watchdog: If pending rendering fails to complete,
    // recover by directly replacing active slot with latest bytes.
    _pendingWatchdogTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _pendingSlot != null) {
        debugPrint('[PdfCanvasView] Watchdog: pending slot $_pendingSlot timed out, recovering');
        final fallbackBytes = _queuedBytes ?? _slotBytes[_pendingSlot!];
        _pendingSlot = null;
        _queuedBytes = null;
        _pendingViewerReady = false;
        _pendingImageLoaded = false;
        if (fallbackBytes != null && fallbackBytes.isNotEmpty) {
          _mountGeneration++;
          _activeSlot = 0;
          _slotBytes[0] = fallbackBytes;
          _slotDocHash[0] = fallbackBytes.hashCode;
          _slotBytes[1] = null;
          _slotDocHash[1] = 0;
          _startDirectReloadWatchdog();
          setState(() {});
        } else {
          _restoredGeneration = _mountGeneration;
          widget.controller.renderOptionsChanged = false;
          widget.controller.finishReloading();
        }
      }
    });
  }

  void _checkAndTriggerPendingSwap(int slotIndex) {
    if (!mounted || _pendingSlot != slotIndex) return;
    if (!_pendingViewerReady || !_pendingImageLoaded) return;
    final expectedBytes = _slotBytes[slotIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingSlot == slotIndex &&
          identical(_slotBytes[slotIndex], expectedBytes) &&
          _pendingViewerReady && _pendingImageLoaded) {
        _triggerSlotSwap(slotIndex);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _triggerSlotSwap(int slotIndex) {
    if (!mounted || _pendingSlot != slotIndex) return;
    _pendingWatchdogTimer?.cancel();
    _pendingViewerReady = false;
    _pendingImageLoaded = false;
    _restoredGeneration = _mountGeneration;
    setState(() {
      _activeSlot = slotIndex;
      _pendingSlot = null;
    });
    if (_isSearchOpen && _searchFieldController.text.trim().isNotEmpty) {
      _activeSearcher?.startTextSearch(
        _searchFieldController.text.trim(),
        caseInsensitive: true,
        goToFirstMatch: false,
        searchImmediately: true,
      );
    }
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _pendingSlot == null) {
        setState(() {
          _slotBytes[1 - _activeSlot] = null;
          _slotDocHash[1 - _activeSlot] = 0;
        });
      }
    });

    // Unconditionally drain queue to prevent stale updates from lingering
    final queued = _queuedBytes;
    _queuedBytes = null;
    if (queued != null && queued.isNotEmpty && queued.hashCode != _slotDocHash[_activeSlot]) {
      _loadQueuedBytes(queued);
    } else {
      widget.controller.renderOptionsChanged = false;
      widget.controller.finishReloading();
    }
  }

  void _loadQueuedBytes(Uint8List queued) {
    final nextSlot = 1 - _activeSlot;
    _mountGeneration++;
    _pendingSlot = nextSlot;
    _pendingViewerReady = false;
    _pendingImageLoaded = false;
    _slotBytes[nextSlot] = queued;
    _slotDocHash[nextSlot] = queued.hashCode;
    _startPendingWatchdog();
    setState(() {});
  }

  @override
  void didUpdateWidget(PdfCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Options and bytes arrive across distinct frames:
    // Frame A: User changes font/size/theme/mode -> notifyListeners() rebuilds with new options but old bytes.
    // Frame B: Async compilation finishes -> notifyListeners() rebuilds with new bytes.
    // Therefore, option/mode change detection MUST run unconditionally outside the byte hash guard.
    final pageFormatChanged = widget.renderOptions.effectivePageFormat != oldWidget.renderOptions.effectivePageFormat;
    final optionsChanged = widget.renderOptions != oldWidget.renderOptions ||
        pageFormatChanged ||
        widget.isTwoPage != oldWidget.isTwoPage ||
        widget.documentTitle != oldWidget.documentTitle;
    if (optionsChanged) {
      widget.controller.renderOptionsChanged = true;
    }

    if (widget.renderOptions.mode != oldWidget.renderOptions.mode ||
        pageFormatChanged ||
        widget.isTwoPage != oldWidget.isTwoPage ||
        widget.documentTitle != oldWidget.documentTitle) {
      _modeOrDocChanged = true;
    }

    if (oldWidget.topInset != widget.topInset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onPdfViewerChanged(_activeSlot);
      });
    }

    final newBytes = widget.pdfBytes;
    if (newBytes == null || newBytes.isEmpty) {
      if (_slotBytes[0] != null || _slotBytes[1] != null) {
        _slotBytes[0] = null;
        _slotBytes[1] = null;
        _slotDocHash[0] = 0;
        _slotDocHash[1] = 0;
        _pendingSlot = null;
        _pendingViewerReady = false;
        _pendingImageLoaded = false;
        _pendingWatchdogTimer?.cancel();
        setState(() {});
      }
      return;
    }

    if (_slotBytes[_activeSlot] == null) {
      _slotBytes[_activeSlot] = newBytes;
      _slotDocHash[_activeSlot] = newBytes.hashCode;
      _modeOrDocChanged = false;
      _mountGeneration++;
      _pendingViewerReady = false;
      _pendingImageLoaded = false;
      _startDirectReloadWatchdog();
      setState(() {});
      return;
    }

    if (newBytes.hashCode != _slotDocHash[_activeSlot]) {
      final isDirectReload = _modeOrDocChanged;
      _modeOrDocChanged = false;

      if (isDirectReload) {
        // Mode change or different document opened: direct reload
        _mountGeneration++;
        _cleanupTimer?.cancel();
        _pendingWatchdogTimer?.cancel();
        _activeSlot = 0;
        _pendingSlot = null;
        _queuedBytes = null;
        _slotBytes[0] = newBytes;
        _slotDocHash[0] = newBytes.hashCode;
        _slotBytes[1] = null;
        _slotDocHash[1] = 0;
        _pendingViewerReady = false;
        _pendingImageLoaded = false;
        _startDirectReloadWatchdog();
        setState(() {});
      } else {
        // Same document updated (hot reload / edit / theme / stream):
        if (_pendingSlot != null) {
          // A background slot is already mounting. Queue newest bytes
          // instead of destroying in-flight viewer, avoiding frozen updates.
          _queuedBytes = newBytes;
        } else {
          // Mount into background slot for seamless double buffering
          _cleanupTimer?.cancel();
          final nextSlot = 1 - _activeSlot;
          _mountGeneration++;
          _pendingSlot = nextSlot;
          _slotBytes[nextSlot] = newBytes;
          _slotDocHash[nextSlot] = newBytes.hashCode;
          _pendingViewerReady = false;
          _pendingImageLoaded = false;
          _startPendingWatchdog();
          setState(() {});
        }
      }
    }
  }

  void _onPdfViewerChanged(int slot) {
    if (slot != _activeSlot) return;
    if (_isRestoringScroll) return;
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
      final isFluid = widget.controller.isFluidLayout;
      final isTwoPage = widget.isTwoPage && !isFluid;
      final topDocOffset = zoom > 0 ? widget.topInset / zoom : 0.0;
      final visibleDocTop = currentTop + topDocOffset;

      final isAtTop = isFluid
          ? (visibleDocTop <= 20.0 || currentTop <= 0.0)
          : (pageNum <= (isTwoPage ? 2 : 1) && (visibleDocTop <= 20.0 || currentTop <= 0.0));
      final deltaY = currentTop - _lastVisibleTop;
      final effectiveAtTop = isAtTop && deltaY <= 0.5;

      if (docSize.height > 0) {
        if (isAtTop && visibleDocTop <= 20.0) {
          widget.controller.updateScrollRatio(0.0, offset: 0.0);
        } else {
          final ratio = (visibleDocTop / docSize.height).clamp(0.0, 1.0);
          widget.controller.updateScrollRatio(ratio, offset: visibleDocTop);
        }
      }

      if (deltaY.abs() > 0.5 || effectiveAtTop != _lastReportedAtTop) {
        _lastVisibleTop = currentTop;
        _lastReportedAtTop = effectiveAtTop;
        widget.onScrollChanged?.call(deltaY: deltaY, isAtTop: effectiveAtTop);
      }
    }
  }

  void _restoreScrollFor(PdfViewerController ctrl) {
    _directReloadWatchdogTimer?.cancel();
    final restoreGen = _mountGeneration;

    // Capture whether options changed before resetting the flag at the top.
    // This guarantees the flag is never leaked across reloads, early exits, or zero-height fallthroughs.
    final optionsChanged = widget.controller.renderOptionsChanged;
    widget.controller.renderOptionsChanged = false;

    if (!ctrl.isReady) {
      _restoredGeneration = restoreGen;
      widget.controller.finishReloading();
      return;
    }
    final docSize = ctrl.documentSize;
    final isFluid = widget.controller.isFluidLayout;

    if (isFluid) {
      if (docSize.height > 0) {
        final visibleHeight = ctrl.visibleRect.height > 0 ? ctrl.visibleRect.height : 600.0;
        final maxScroll = math.max(0.0, docSize.height - visibleHeight);
        final targetY = widget.controller.calculateFluidTargetScrollY(
          docSize.height,
          useOffset: !optionsChanged,
          maxScroll: maxScroll,
        );

        if (targetY > ReaderController.topScrollThreshold) {
          ctrl.goToPosition(documentOffset: Offset(0, targetY));

          Future.delayed(const Duration(milliseconds: 250), () {
            if (mounted && _mountGeneration == restoreGen) {
              _restoredGeneration = restoreGen;
              _lastVisibleTop = targetY;
              _lastReportedAtTop = false;
              widget.onScrollChanged?.call(deltaY: 0, isAtTop: false);
            }
            widget.controller.finishReloading();
          });
          return;
        } else {
          final zoom = ctrl.currentZoom;
          final topDocOffset = zoom > 0 ? widget.topInset / zoom : 0.0;
          if (topDocOffset > 0) {
            ctrl.goToPosition(documentOffset: Offset(0, -topDocOffset), duration: Duration.zero);
          } else {
            ctrl.goToPage(pageNumber: 1, duration: Duration.zero);
          }
        }
      }
    } else {
      widget.controller.renderOptionsChanged = false;
      final targetPage = widget.controller.lastPageNumber;
      if (targetPage > 1 && targetPage <= ctrl.pageCount) {
        ctrl.goToPage(pageNumber: targetPage, duration: Duration.zero);

        Future.delayed(const Duration(milliseconds: 250), () {
          if (mounted && _mountGeneration == restoreGen) {
            _restoredGeneration = restoreGen;
            _lastReportedAtTop = false;
            widget.onScrollChanged?.call(deltaY: 0, isAtTop: false);
          }
          widget.controller.finishReloading();
        });
        return;
      }
    }
    _restoredGeneration = restoreGen;
    _lastReportedAtTop = true;
    widget.onScrollChanged?.call(deltaY: 0, isAtTop: true);
    widget.controller.finishReloading();
  }

  void _restoreScroll() => _restoreScrollFor(_pdfController);

  Offset? _calcDestDocumentOffsetFor(PdfViewerController ctrl, PdfDest? dest) {
    if (dest == null || !ctrl.isReady) return null;
    final layout = ctrl.layoutOrNull;
    if (layout == null || layout.pageLayouts.isEmpty) return null;
    final pageIndex = dest.pageNumber - 1;
    if (pageIndex < 0 || pageIndex >= layout.pageLayouts.length) return null;

    final pageRect = layout.pageLayouts[pageIndex];
    final pages = ctrl.document.pages;
    if (pageIndex >= pages.length) return null;
    final page = pages[pageIndex];

    double calcX(double? x) => page.width > 0 ? ((x ?? 0) / page.width * pageRect.width) : 0.0;
    double calcY(double? y) => page.height > 0 ? ((page.height - (y ?? 0)) / page.height * pageRect.height) : 0.0;

    final params = dest.params;
    switch (dest.command) {
      case PdfDestCommand.xyz:
        final relY = (params != null && params.length >= 2 && params[1] != null) ? calcY(params[1]) : 0.0;
        return Offset(pageRect.left, pageRect.top + relY);
      case PdfDestCommand.fitH:
      case PdfDestCommand.fitBH:
        final relY = (params != null && params.isNotEmpty && params[0] != null) ? calcY(params[0]) : 0.0;
        return Offset(pageRect.left, pageRect.top + relY);
      case PdfDestCommand.fitV:
      case PdfDestCommand.fitBV:
        final relX = (params != null && params.isNotEmpty && params[0] != null) ? calcX(params[0]) : 0.0;
        return Offset(pageRect.left + relX, pageRect.top);
      case PdfDestCommand.fitR:
        if (params != null && params.length >= 4 && params[3] != null) {
          return Offset(pageRect.left, pageRect.top + calcY(params[3]));
        }
        return pageRect.topLeft;
      case PdfDestCommand.fit:
      case PdfDestCommand.fitB:
      default:
        return pageRect.topLeft;
    }
  }

  Future<bool> _goToDestWithTopInset(PdfViewerController ctrl, PdfDest dest) async {
    if (!ctrl.isReady) return false;
    final destOffset = _calcDestDocumentOffsetFor(ctrl, dest);
    if (destOffset != null) {
      final zoom = ctrl.currentZoom;
      const breathingPadding = 8.0;
      final effectiveTopInset = widget.topInset > 0 ? (widget.topInset + breathingPadding) : 0.0;
      final topDocOffset = zoom > 0 ? effectiveTopInset / zoom : 0.0;
      final targetY = destOffset.dy - topDocOffset;
      await ctrl.goToPosition(
        documentOffset: Offset(destOffset.dx, targetY),
        duration: const Duration(milliseconds: 200),
        targetPageNumber: dest.pageNumber,
      );
      return true;
    }
    return await ctrl.goToDest(dest);
  }

  Future<void> jumpToOutline(OutlineItem item) async {
    if (!_pdfController.isReady) return;
    final zoom = _pdfController.currentZoom;
    const breathingPadding = 8.0;
    final effectiveTopInset = widget.topInset > 0 ? (widget.topInset + breathingPadding) : 0.0;
    final topDocOffset = zoom > 0 ? effectiveTopInset / zoom : 0.0;

    // 1. Try resolving exact destination from PDF outline tree (both fluid & paged layouts)
    try {
      final outlines = await _pdfController.document.loadOutline();
      final targetNode = _findOutlineNode(outlines, item);
      if (targetNode?.dest != null) {
        final success = await _goToDestWithTopInset(_pdfController, targetNode!.dest!);
        if (success) return;
      }
    } catch (e) {
      debugPrint('[PdfCanvasView] Failed to jump via outline dest: $e');
    }

    // 2. Fallback: If item has an explicit page number (e.g. in paged mode or pure PDF outline)
    if (item.pageNumber != null) {
      final pageCount = _pdfController.pageCount;
      final targetPage = item.pageNumber!.clamp(1, pageCount);
      final layout = _pdfController.layoutOrNull;
      if (layout != null && targetPage <= layout.pageLayouts.length && topDocOffset > 0) {
        final pageRect = layout.pageLayouts[targetPage - 1];
        final targetY = pageRect.top - topDocOffset;
        await _pdfController.goToPosition(
          documentOffset: Offset(pageRect.left, targetY),
          duration: const Duration(milliseconds: 200),
          targetPageNumber: targetPage,
        );
        return;
      }
      await _pdfController.goToPage(
        pageNumber: targetPage,
        anchor: PdfPageAnchor.top,
        duration: const Duration(milliseconds: 200),
      );
      return;
    }

    // 3. Fallback: Approximate position based on markdown line number ratio
    final totalLines = math.max(1, widget.controller.currentMarkdown.split('\n').length);
    final ratio = ((item.lineNumber - 1) / totalLines).clamp(0.0, 1.0);

    if (widget.controller.isFluidLayout) {
      final docHeight = _pdfController.documentSize.height;
      if (docHeight > 0) {
        final targetY = (docHeight * ratio) - topDocOffset;
        await _pdfController.goToPosition(
          documentOffset: Offset(0, targetY),
          duration: const Duration(milliseconds: 200),
        );
      }
    } else {
      final pageCount = _pdfController.pageCount;
      final targetPage = (1 + (ratio * (pageCount - 1)).round()).clamp(1, pageCount);
      final layout = _pdfController.layoutOrNull;
      if (layout != null && targetPage <= layout.pageLayouts.length && topDocOffset > 0) {
        final pageRect = layout.pageLayouts[targetPage - 1];
        final targetY = pageRect.top - topDocOffset;
        await _pdfController.goToPosition(
          documentOffset: Offset(pageRect.left, targetY),
          duration: const Duration(milliseconds: 200),
          targetPageNumber: targetPage,
        );
        return;
      }
      await _pdfController.goToPage(
        pageNumber: targetPage,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  PdfOutlineNode? _findOutlineNode(List<PdfOutlineNode> nodes, OutlineItem item) {
    // Collect all nodes in pre-order traversal
    final flatNodes = <PdfOutlineNode>[];
    void collect(List<PdfOutlineNode> list) {
      for (final n in list) {
        flatNodes.add(n);
        if (n.children.isNotEmpty) collect(n.children);
      }
    }
    collect(nodes);

    // 1. If outline list lengths match, check corresponding index first
    final itemIndex = widget.controller.outlineItems.indexOf(item);
    if (itemIndex >= 0 && itemIndex < flatNodes.length) {
      final candidate = flatNodes[itemIndex];
      if (candidate.title.trim().toLowerCase() == item.title.trim().toLowerCase()) {
        return candidate;
      }
    }

    // 2. Exact title match
    final q = item.title.trim().toLowerCase();
    for (final node in flatNodes) {
      if (node.title.trim().toLowerCase() == q) {
        return node;
      }
    }

    // 3. Substring match
    for (final node in flatNodes) {
      final t = node.title.trim().toLowerCase();
      if (t.contains(q) || q.contains(t)) {
        return node;
      }
    }

    return null;
  }

  Offset _calcStableZoomCenter(Offset? focalPoint) {
    if (focalPoint != null) return focalPoint;
    if (!_pdfController.isReady) return Offset.zero;
    final layout = _pdfController.layoutOrNull;
    if (layout == null || layout.pageLayouts.isEmpty) return _pdfController.centerPosition;

    if (widget.controller.isFluidLayout) {
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
    final minS = widget.controller.isFluidLayout ? 0.35 : 0.2;
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
    final minS = widget.controller.isFluidLayout ? 0.35 : 0.2;
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
    final minS = widget.controller.isFluidLayout ? 0.35 : 0.2;
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

  /// Bounding box of the page at [index], or of the whole spread it starts in
  /// when [isTwoPage] is set.
  Rect _spreadRectAt(PdfPageLayout layout, int index, bool isTwoPage) {
    final rect = layout.pageLayouts[index];
    if (isTwoPage && index + 1 < layout.pageLayouts.length) {
      return rect.expandToInclude(layout.pageLayouts[index + 1]);
    }
    return rect;
  }

  /// Maps the viewport's offset from the edge of the page it currently sits on
  /// onto a page of [targetExtent], along one axis.
  double _mapAxis({
    required double relStart,
    required double currentExtent,
    required double targetExtent,
    required double viewportExtent,
  }) {
    // How far past the end of its own page the viewport already sits. Document
    // margins legitimately put it slightly outside, and that is worth keeping:
    // clamping it away would nudge the view sideways on every single flip.
    final currentMax = math.max(0.0, currentExtent - viewportExtent);
    final overhang = math.max(0.0, relStart - currentMax);
    // Refuse to scroll further past the target's far edge than that. Without
    // this, flipping onto a shorter page (a document mixing page sizes) lands
    // the viewport over the *following* page while the indicator names this one.
    final targetMax = math.max(0.0, targetExtent - viewportExtent);
    return math.min(relStart, targetMax + overhang);
  }

  /// Document offset that lands [visibleRect] on [targetRect] the way it
  /// currently sits on [currentRect], so a page flip keeps the reader where they
  /// were within the page instead of jumping to its top-left corner.
  ///
  /// Both rects are the page's -- or, in two-page mode, the whole spread's --
  /// own bounds rather than absolute document coordinates, because
  /// `_layoutA4Pages` centres each row on its own width: an absolute left edge
  /// drifts whenever the row width changes, such as the trailing single-page
  /// spread of an odd-page document.
  Offset _preservedOffset(Rect currentRect, Rect targetRect, Rect visibleRect) {
    final relX = _mapAxis(
      relStart: visibleRect.left - currentRect.left,
      currentExtent: currentRect.width,
      targetExtent: targetRect.width,
      viewportExtent: visibleRect.width,
    );
    final relY = _mapAxis(
      relStart: visibleRect.top - currentRect.top,
      currentExtent: currentRect.height,
      targetExtent: targetRect.height,
      viewportExtent: visibleRect.height,
    );
    return Offset(targetRect.left + relX, targetRect.top + relY);
  }

  Future<void> nextPage({bool preserveOffset = true}) async {
    if (!_pdfController.isReady) return;
    final pCount = _pdfController.pageCount;
    final currentPage = _pdfController.pageNumber ?? 1;
    final isTwoPage = widget.controller.isTwoPage && !widget.controller.isFluidLayout;

    int targetPage;
    if (isTwoPage) {
      final currentSpreadIndex = (currentPage - 1) ~/ 2;
      final maxSpreadIndex = (pCount - 1) ~/ 2;
      if (currentSpreadIndex >= maxSpreadIndex) return;
      targetPage = (currentSpreadIndex + 1) * 2 + 1;
    } else {
      if (currentPage >= pCount) return;
      targetPage = currentPage + 1;
    }

    if (preserveOffset) {
      final layout = _pdfController.layoutOrNull;
      if (layout != null) {
        final currentIdx = isTwoPage ? ((currentPage - 1) ~/ 2) * 2 : currentPage - 1;
        final targetIdx = isTwoPage ? ((targetPage - 1) ~/ 2) * 2 : targetPage - 1;
        if (currentIdx < layout.pageLayouts.length && targetIdx < layout.pageLayouts.length) {
          final currentRect = _spreadRectAt(layout, currentIdx, isTwoPage);
          final targetRect = _spreadRectAt(layout, targetIdx, isTwoPage);

          final visibleRect = _pdfController.visibleRect;
          final targetOffset = _preservedOffset(currentRect, targetRect, visibleRect);
          await _pdfController.goToPosition(
            documentOffset: targetOffset,
            zoom: currentZoom,
            duration: const Duration(milliseconds: 220),
            targetPageNumber: targetPage,
          );
          return;
        }
      }
    }

    await _pdfController.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> prevPage({bool preserveOffset = true}) async {
    if (!_pdfController.isReady) return;
    final currentPage = _pdfController.pageNumber ?? 1;
    final isTwoPage = widget.controller.isTwoPage && !widget.controller.isFluidLayout;

    int targetPage;
    if (isTwoPage) {
      final currentSpreadIndex = (currentPage - 1) ~/ 2;
      if (currentSpreadIndex <= 0) return;
      targetPage = (currentSpreadIndex - 1) * 2 + 1;
    } else {
      if (currentPage <= 1) return;
      targetPage = currentPage - 1;
    }

    if (preserveOffset) {
      final layout = _pdfController.layoutOrNull;
      if (layout != null) {
        final currentIdx = isTwoPage ? ((currentPage - 1) ~/ 2) * 2 : currentPage - 1;
        final targetIdx = isTwoPage ? ((targetPage - 1) ~/ 2) * 2 : targetPage - 1;
        if (currentIdx < layout.pageLayouts.length && targetIdx < layout.pageLayouts.length) {
          final currentRect = _spreadRectAt(layout, currentIdx, isTwoPage);
          final targetRect = _spreadRectAt(layout, targetIdx, isTwoPage);

          final visibleRect = _pdfController.visibleRect;
          final targetOffset = _preservedOffset(currentRect, targetRect, visibleRect);
          await _pdfController.goToPosition(
            documentOffset: targetOffset,
            zoom: currentZoom,
            duration: const Duration(milliseconds: 220),
            targetPageNumber: targetPage,
          );
          return;
        }
      }
    }

    await _pdfController.goToPage(
      pageNumber: targetPage,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  bool get isCurrentPageFittingViewport {
    if (!_pdfController.isReady) return false;
    final layout = _pdfController.layoutOrNull;
    if (layout == null) return false;
    final currentPage = _pdfController.pageNumber ?? 1;
    final isTwoPage = widget.controller.isTwoPage && !widget.controller.isFluidLayout;
    final currentIdx = isTwoPage ? ((currentPage - 1) ~/ 2) * 2 : currentPage - 1;
    if (currentIdx < 0 || currentIdx >= layout.pageLayouts.length) return false;
    final currentRect = _spreadRectAt(layout, currentIdx, isTwoPage);
    final visibleRect = _pdfController.visibleRect;
    // Tolerance is in document units, so scale it to stay ~4 screen pixels
    // regardless of zoom.
    final zoom = currentZoom;
    final topDocOffset = zoom > 0 ? widget.topInset / zoom : 0.0;
    final tolerance = zoom > 0 ? 4.0 / zoom : 4.0;
    final effectiveVisibleTop = visibleRect.top + topDocOffset;
    // Fitting is not enough: the layout is a continuous stack, so after free
    // panning the viewport can straddle two pages while the page still fits.
    // Flipping from there would skip the part the reader has not seen yet.
    return currentRect.top >= effectiveVisibleTop - tolerance && currentRect.bottom <= visibleRect.bottom + tolerance;
  }

  Future<void> scrollScreenDown() async {
    if (!_pdfController.isReady) return;
    final h = _pdfController.visibleRect.height;
    final zoom = currentZoom;
    final screenH = h * zoom;
    final screenStep = (screenH > 0 ? screenH * 0.85 : 420.0).clamp(40.0, 4000.0);
    final step = zoom > 0 ? screenStep / zoom : screenStep;
    await scrollByDelta(step, accelerate: false);
  }

  Future<void> scrollScreenUp() async {
    if (!_pdfController.isReady) return;
    final h = _pdfController.visibleRect.height;
    final zoom = currentZoom;
    final screenH = h * zoom;
    final screenStep = (screenH > 0 ? screenH * 0.85 : 420.0).clamp(40.0, 4000.0);
    final step = zoom > 0 ? screenStep / zoom : screenStep;
    await scrollByDelta(-step, accelerate: false);
  }

  Future<void> goToPageNumber(int pageNumber) async {
    if (!_pdfController.isReady) return;
    final pCount = _pdfController.pageCount;
    final target = pageNumber.clamp(1, pCount);
    final layout = _pdfController.layoutOrNull;
    final zoom = _pdfController.currentZoom;
    final topDocOffset = zoom > 0 ? widget.topInset / zoom : 0.0;
    if (layout != null && target <= layout.pageLayouts.length && topDocOffset > 0) {
      final pageRect = layout.pageLayouts[target - 1];
      final targetY = pageRect.top - topDocOffset;
      await _pdfController.goToPosition(
        documentOffset: Offset(pageRect.left, targetY),
        duration: const Duration(milliseconds: 220),
        targetPageNumber: target,
      );
      return;
    }
    await _pdfController.goToPage(
      pageNumber: target,
      anchor: PdfPageAnchor.top,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> scrollByDelta(double deltaY, {bool accelerate = true}) async {
    final delegate = _scrollDelegates[_activeSlot];
    if (delegate != null && _pdfController.isReady) {
      final zoom = currentZoom;
      // In screen coordinates, scrolling DOWN (deltaY > 0) translates the viewport UP (negative Y)
      final screenDeltaY = -deltaY * zoom;
      delegate.scrollByScreenDelta(Offset(0, screenDeltaY), accelerate: accelerate);
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

    final s = widget.controller.strings;
    if (isText) {
      // 1. Text Selection Context Menu: strictly text actions
      if (params.isTextSelectionEnabled && params.textSelectionDelegate.isCopyAllowed) {
        items.add(
          ContextMenuButtonItem(
            label: '${s.copy} (${Platform.isMacOS ? 'Cmd+C' : 'Ctrl+C'})',
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
            label: '${s.selectAll} (${Platform.isMacOS ? 'Cmd+A' : 'Ctrl+A'})',
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
            label: '${s.selectAll} (${Platform.isMacOS ? 'Cmd+A' : 'Ctrl+A'})',
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
          label: '${s.fitWindowWidth} (${widget.controller.shortcutService.getShortcutLabel('fitWidth')})',
          onPressed: () {
            params.dismissContextMenu();
            fitWidth();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: '${s.fitPageWhole} (${widget.controller.shortcutService.getShortcutLabel('fitPage')})',
          onPressed: () {
            params.dismissContextMenu();
            fitPage();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: s.resetZoomTooltip(widget.controller.shortcutService.getShortcutLabel('resetZoom')),
          onPressed: () {
            params.dismissContextMenu();
            resetZoom();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: s.zoomInTooltip(widget.controller.shortcutService.getShortcutLabel('zoomIn')),
          onPressed: () {
            params.dismissContextMenu();
            zoomIn();
          },
        ),
      );
      items.add(
        ContextMenuButtonItem(
          label: s.zoomOutTooltip(widget.controller.shortcutService.getShortcutLabel('zoomOut')),
          onPressed: () {
            params.dismissContextMenu();
            zoomOut();
          },
        ),
      );
      if (widget.controller.isPdfDocument || !widget.controller.isFluidLayout) {
        items.add(
          ContextMenuButtonItem(
            label: s.toggleTwoPageTooltip(widget.controller.isTwoPage, widget.controller.shortcutService.getShortcutLabel('toggleTwoPage')),
            onPressed: () {
              params.dismissContextMenu();
              widget.controller.toggleTwoPage();
            },
          ),
        );
      }
      if (!widget.controller.isPdfDocument) {
        items.add(
          ContextMenuButtonItem(
            label: s.toggleModeTooltip(widget.controller.shortcutService.getShortcutLabel('toggleMode')),
            onPressed: () {
              params.dismissContextMenu();
              widget.controller.toggleMode();
            },
          ),
        );
      }
      items.add(
        ContextMenuButtonItem(
          label: s.toggleThemeTooltip(widget.controller.renderOptions.isDark, widget.controller.shortcutService.getShortcutLabel('toggleTheme')),
          onPressed: () {
            params.dismissContextMenu();
            widget.controller.toggleTheme();
          },
        ),
      );
      if (widget.onToggleSidebar != null) {
        items.add(
          ContextMenuButtonItem(
            label: s.toggleSidebarTooltip(widget.controller.shortcutService.getShortcutLabel('toggleSidebar')),
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
            label: '${s.exportPdf} (${widget.controller.shortcutService.getShortcutLabel('exportPdf')})',
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
    final isPdfDoc = widget.controller.isPdfDocument;
    final builtForPath = widget.controller.currentFilePath;
    bool isCurrentSlot() => mounted && identical(_slotBytes[slotIndex], bytes) &&
        widget.controller.currentFilePath == builtForPath;
    final effectiveFluid = isFluid && !isPdfDoc;
    return PdfViewer.data(
      bytes,
      initialPageNumber: effectiveFluid ? 1 : widget.controller.lastPageNumber.clamp(1, 999999),
      key: ValueKey(
        'slot_${slotIndex}_${_slotDocHash[slotIndex]}_${widget.renderOptions.mode}_${widget.renderOptions.effectivePageFormat}_${widget.isTwoPage}_$isPdfDoc',
      ),
      sourceName: '${widget.documentTitle}_slot_${slotIndex}_${_slotDocHash[slotIndex]}',
      controller: ctrl,
      params: PdfViewerParams(
        backgroundColor: canvasBg,
        enableTiledRendering: true,
        onKey: (params, key, isRealKeyPress) {
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.pageUp ||
              key == LogicalKeyboardKey.pageDown ||
              key == LogicalKeyboardKey.space ||
              key == LogicalKeyboardKey.home ||
              key == LogicalKeyboardKey.end ||
              key == LogicalKeyboardKey.bracketLeft ||
              key == LogicalKeyboardKey.bracketRight ||
              key == LogicalKeyboardKey.equal ||
              key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.add) {
            return false;
          }
          return null;
        },
        calculateCurrentPageNumber: (visibleRect, pageLayouts, controller) {
          if (pageLayouts.isEmpty) return 1;
          final zoom = controller.isReady ? controller.currentZoom : 1.0;
          final topDocOffset = zoom > 0 ? widget.topInset / zoom : 0.0;
          if (effectiveFluid) {
            final targetY = visibleRect.top + topDocOffset;
            for (var i = 0; i < pageLayouts.length; i++) {
              final rect = pageLayouts[i];
              if (targetY >= rect.top && targetY <= rect.bottom) {
                return i + 1;
              }
            }
            if (targetY >= (pageLayouts.lastOrNull?.bottom ?? 0)) {
              return pageLayouts.length;
            }
            return 1;
          }

          final isTwoPage = widget.isTwoPage && !effectiveFluid;
          final adjustedVisibleRect = Rect.fromLTRB(
            visibleRect.left,
            visibleRect.top + topDocOffset,
            visibleRect.right,
            visibleRect.bottom,
          );
          final viewCenter = adjustedVisibleRect.center;

          double maxVisibleArea = -1;
          int bestPage = 1;
          double minCenterDistanceSq = double.infinity;
          int closestPage = 1;

          for (int i = 0; i < pageLayouts.length; i++) {
            final rect = pageLayouts[i];
            final dx = rect.center.dx - viewCenter.dx;
            final dy = rect.center.dy - viewCenter.dy;
            final distSq = dx * dx + dy * dy;
            if (distSq < minCenterDistanceSq) {
              minCenterDistanceSq = distSq;
              closestPage = i + 1;
            }

            final intersect = adjustedVisibleRect.intersect(rect);
            if (!intersect.isEmpty && intersect.width > 0 && intersect.height > 0) {
              final area = intersect.width * intersect.height;
              if (area > maxVisibleArea) {
                maxVisibleArea = area;
                bestPage = i + 1;
              }
            }
          }

          final selectedPage = maxVisibleArea > 0 ? bestPage : closestPage;
          if (isTwoPage) {
            final spreadIndex = (selectedPage - 1) ~/ 2;
            return (spreadIndex * 2 + 1).clamp(1, pageLayouts.length);
          }
          return selectedPage;
        },
        pagePaintCallbacks: [
          (canvas, pageRect, page) {
            _textSearchers[slotIndex]?.pageTextMatchPaintCallback(canvas, pageRect, page);
          },
        ],
        matchTextColor: isDark ? const Color(0x77FBC02D) : const Color(0x66FFEB3B),
        activeMatchTextColor: isDark ? const Color(0xBBFF9800) : const Color(0x99FF9800),
        onVisiblePagesRendered: (ready) {
          if (!isCurrentSlot()) return;
          if (slotIndex == _pendingSlot) {
            _pendingImageLoaded = ready;
            if (ready) _checkAndTriggerPendingSwap(slotIndex);
          }
        },
        scrollByMouseWheel: 1.0,
        calculateInitialPageNumber: (document, controller) {
          if (effectiveFluid) {
            final layouts = controller.layout.pageLayouts;
            if (layouts.isEmpty) return 1;
            final docHeight = controller.layout.documentSize.height;
            final targetY = widget.controller.calculateFluidTargetScrollY(
              docHeight,
              useOffset: !widget.controller.renderOptionsChanged,
            );

            if (targetY <= ReaderController.topScrollThreshold) return 1;

            for (var i = 0; i < layouts.length; i++) {
              final rect = layouts[i];
              if (targetY >= rect.top && targetY <= rect.bottom) {
                return i + 1;
              }
            }
            if (targetY >= (layouts.lastOrNull?.bottom ?? 0)) {
              return layouts.length;
            }
            return 1;
          } else {
            return widget.controller.lastPageNumber.clamp(1, document.pages.length);
          }
        },
        interactionDelegateProvider: SuperGoodScrollInteractionDelegateProvider(
          onDelegateCreated: (delegate) => _scrollDelegates[slotIndex] = delegate,
        ),
        margin: effectiveFluid ? 0.0 : 10.0,
        boundaryMargin: effectiveFluid
            ? EdgeInsets.only(
                top: widget.topInset > 0 ? math.max(72.0, widget.topInset + 40.0) : 48.0,
                bottom: 24,
                left: 0,
                right: 0,
              )
            : EdgeInsets.only(
                top: widget.topInset > 0 ? math.max(72.0, widget.topInset + 40.0) : 48.0,
                bottom: 16,
                left: 8,
                right: 8,
              ),
        maxImageBytesCachedOnMemory: effectiveFluid ? 256 * 1024 * 1024 : 64 * 1024 * 1024,
        onePassRenderingSizeThreshold: effectiveFluid ? 4000.0 : 2000.0,
        getPageRenderingScale: (context, page, controller, estimatedScale) {
          if (effectiveFluid && (page.width > 4000 || page.height > 4000)) {
            return math.min(4000 / page.width, 4000 / page.height);
          }
          final physicalScale = controller.currentZoom * MediaQuery.devicePixelRatioOf(context);
          final screenScale = (physicalScale * 2).ceil() / 2;
          final memoryScale = math.sqrt((16 * 1024 * 1024) / (4 * page.width * page.height));
          final dimensionScale = 4096 / math.max(page.width, page.height);
          return math.min(screenScale, math.min(memoryScale, dimensionScale));
        },
        verticalCacheExtent: 1.5,
        pageAnchor: PdfPageAnchor.top,
        underflowAnchor: PdfPageAnchor.top,
        pageDropShadow: effectiveFluid
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
        layoutPages: effectiveFluid
            ? _layoutFluidPages
            : (pages, params) => _layoutA4Pages(
                  pages,
                  params,
                  isTwoPage: widget.isTwoPage,
                ),
        sizeDelegateProvider: SuperGoodSizeDelegateProvider(
          readerController: widget.controller,
          isFluid: effectiveFluid,
          isTwoPage: widget.isTwoPage,
          minScale: effectiveFluid ? 0.35 : 0.2,
          maxScale: 5.0,
          topInset: widget.topInset,
        ),
        zoomStepsDelegateProvider: SuperGoodZoomStepsDelegateProvider(
          isFluid: effectiveFluid,
        ),
        textSelectionParams: const PdfTextSelectionParams(
          enabled: true,
          showContextMenuAutomatically: false,
        ),
        onDocumentLoadFinished: (documentRef, succeeded) {
          if (!isCurrentSlot()) return;
          if (mounted &&
              widget.controller.isPdfDocument &&
              widget.controller.currentFilePath == builtForPath) {
            if (succeeded) {
              if (widget.controller.errorMessage == 'Failed to load PDF document') {
                widget.controller.setErrorMessage(null);
              }
            } else {
              widget.controller.setErrorMessage('Failed to load PDF document');
            }
          }
        },
        onViewerReady: (document, controller) {
          if (!isCurrentSlot()) return;
          _textSearchers[slotIndex]?.removeListener(_onSearchUpdated);
          _textSearchers[slotIndex]?.dispose();
          _textSearchers[slotIndex] = PdfTextSearcher(controller)..addListener(_onSearchUpdated);
          if (_isSearchOpen && _searchFieldController.text.trim().isNotEmpty) {
            _textSearchers[slotIndex]?.startTextSearch(
              _searchFieldController.text.trim(),
              caseInsensitive: true,
              goToFirstMatch: false,
              searchImmediately: true,
            );
          }
          final srcPath = widget.controller.currentFilePath;
          document.loadOutline().then((outlines) {
            if (!mounted) {
              return;
            }
            if (widget.controller.currentFilePath != srcPath) {
              return;
            }
            final destMap = <String, ({int? pageNumber, double? docY})>{};
            final orderedDocYs = <double>[];
            void extractNodes(List<PdfOutlineNode> list) {
              for (final n in list) {
                final dest = n.dest;
                final offset = dest != null ? _calcDestDocumentOffsetFor(controller, dest) : null;
                final pageNum = dest?.pageNumber;
                final docY = offset?.dy;
                if (docY != null) orderedDocYs.add(docY);
                if (pageNum != null || docY != null) {
                  destMap[n.title.trim()] = (pageNumber: pageNum, docY: docY);
                }
                if (n.children.isNotEmpty) extractNodes(n.children);
              }
            }
            extractNodes(outlines);

            if (widget.controller.isPdfDocument) {
              final items = <OutlineItem>[];
              void traverse(List<PdfOutlineNode> nodes, int level) {
                for (final node in nodes) {
                  final dest = node.dest;
                  final offset = dest != null ? _calcDestDocumentOffsetFor(controller, dest) : null;
                  items.add(OutlineItem(
                    title: node.title,
                    level: level,
                    anchor: node.title,
                    lineNumber: 0,
                    pageNumber: dest?.pageNumber,
                    docY: offset?.dy,
                  ));
                  if (node.children.isNotEmpty) {
                    traverse(node.children, level + 1);
                  }
                }
              }
              traverse(outlines, 1);
              widget.controller.setPdfOutlines(items, targetFilePath: srcPath);
            } else if (outlines.isNotEmpty) {
              widget.controller.syncOutlinesDestinations(destMap, orderedDocYs: orderedDocYs);
            }
          }).catchError((e) {
            debugPrint('[PdfCanvasView] Failed to load PDF outline: $e');
          });
          if (slotIndex == _pendingSlot) {
            _pendingViewerReady = true;
            _restoreScrollFor(controller);
            _checkAndTriggerPendingSwap(slotIndex);
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
              await _goToDestWithTopInset(ctrl, link.dest!);
            } else if (link.url != null) {
              final uri = link.url!;

              // 1. 外部网络协议：浏览器或外部客户端打开
              final scheme = uri.scheme.toLowerCase();
              if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
                return;
              }

              // 2. 本地相对路径或文件链接 (scheme 为 file，或无 scheme)
              String rawPath = uri.path;
              if (Platform.isWindows && rawPath.startsWith('/') && rawPath.length > 2 && rawPath[2] == ':') {
                rawPath = rawPath.substring(1);
              }
              rawPath = Uri.decodeFull(rawPath);

              final currentDoc = widget.controller.currentFilePath;
              String resolvedPath = rawPath;
              if (!p.isAbsolute(resolvedPath) && currentDoc != null) {
                resolvedPath = p.normalize(p.join(p.dirname(currentDoc), rawPath));
              }

              final file = File(resolvedPath);
              if (await file.exists()) {
                final ext = p.extension(resolvedPath).toLowerCase();
                const supportedExtensions = {'.md', '.markdown', '.mdown', '.mkd', '.mkdn', '.pdf'};
                if (supportedExtensions.contains(ext) || ext.isEmpty) {
                  // Markdown 与 PDF 文档：直接在当前视窗中平滑切换打开
                  await widget.controller.openFile(resolvedPath);
                } else {
                  // 其他本地文件（如图片、Office 文档等）：唤起系统关联程序打开
                  await launchUrl(Uri.file(resolvedPath));
                }
              } else {
                // 若直接路径不存在，尝试去掉或补齐 .md 扩展名匹配
                final altMdPath = resolvedPath.endsWith('.md') ? resolvedPath : '$resolvedPath.md';
                if (await File(altMdPath).exists()) {
                  await widget.controller.openFile(altMdPath);
                  return;
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(widget.controller.strings.targetDocNotExist(p.basename(resolvedPath))),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
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
              widget.controller.strings.compiling,
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

    final isDark = widget.renderOptions.isDark;
    final isFluid = widget.controller.isFluidLayout;
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
          if (_isRestoringScroll) return;
          if (event is PointerScrollEvent) {
            if (event.scrollDelta.dy > 1.0) {
              widget.onScrollChanged?.call(deltaY: event.scrollDelta.dy, isAtTop: false);
            }
          }
          widget.onUserScrolled?.call();
        },
        onPointerPanZoomUpdate: (event) {
          if (_isRestoringScroll) return;
          if (event.panDelta.dy < -1.0) {
            widget.onScrollChanged?.call(deltaY: -event.panDelta.dy, isAtTop: false);
          }
          widget.onUserScrolled?.call();
        },
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ...children,
              if (_isSearchOpen)
                Positioned(
                  top: 52,
                  right: 24,
                  child: _buildSearchBar(context, isDark),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void openSearch() {
    _isSearchOpen = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
        _searchFieldController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _searchFieldController.text.length,
        );
      }
    });
  }

  void closeSearch() {
    if (!_isSearchOpen) return;
    _isSearchOpen = false;
    _searchFieldController.clear();
    for (final s in _textSearchers) {
      s?.resetTextSearch();
    }
    setState(() {
      _searchMatchIndex = 0;
      _searchTotalMatches = 0;
      _isSearchingText = false;
    });
  }

  void searchNext() async {
    final searcher = _activeSearcher;
    if (searcher == null) return;
    if (searcher.matches.isEmpty) {
      if (_searchFieldController.text.trim().isNotEmpty) {
        searcher.startTextSearch(
          _searchFieldController.text.trim(),
          caseInsensitive: true,
          goToFirstMatch: true,
          searchImmediately: true,
        );
      }
      return;
    }
    final curr = searcher.currentIndex ?? -1;
    if (curr + 1 >= searcher.matches.length) {
      await searcher.goToMatchOfIndex(0);
    } else {
      await searcher.goToNextMatch();
    }
  }

  void searchPrev() async {
    final searcher = _activeSearcher;
    if (searcher == null || searcher.matches.isEmpty) return;
    final curr = searcher.currentIndex ?? 0;
    if (curr <= 0) {
      await searcher.goToMatchOfIndex(searcher.matches.length - 1);
    } else {
      await searcher.goToPrevMatch();
    }
  }

  void _onSearchQueryChanged(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      for (final s in _textSearchers) {
        s?.resetTextSearch();
      }
      setState(() {
        _searchTotalMatches = 0;
        _searchMatchIndex = 0;
        _isSearchingText = false;
      });
    } else {
      _activeSearcher?.startTextSearch(
        trimmed,
        caseInsensitive: true,
        goToFirstMatch: true,
        searchImmediately: false,
      );
    }
  }

  KeyEventResult _handleSearchKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        closeSearch();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          searchPrev();
        } else {
          searchNext();
        }
        return KeyEventResult.handled;
      }
    }
    // Return skipRemainingHandlers so ancestor shortcuts (such as Space for next page,
    // Arrow keys, Home/End) do not intercept keystrokes while the search box is active,
    // while still allowing the TextField and IME to receive keystrokes and candidate selection.
    return KeyEventResult.skipRemainingHandlers;
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    final bgColor = isDark ? const Color(0xEE242424) : const Color(0xEEF6F6F6);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1);
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    final s = widget.controller.strings;
    String matchInfo;
    if (_searchFieldController.text.isEmpty) {
      matchInfo = '';
    } else if (_isSearchingText) {
      matchInfo = '...';
    } else if (_searchTotalMatches == 0) {
      matchInfo = s.noMatches;
    } else {
      matchInfo = s.matchCount(_searchMatchIndex, _searchTotalMatches);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 16, color: hintColor),
              const SizedBox(width: 6),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _searchFieldController,
                  focusNode: _searchFocusNode,
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: s.searchPlaceholder,
                    hintStyle: TextStyle(fontSize: 12.5, color: hintColor),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                  onChanged: _onSearchQueryChanged,
                  onSubmitted: (_) => searchNext(),
                ),
              ),
              if (matchInfo.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    matchInfo,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: _searchTotalMatches == 0 && _searchFieldController.text.isNotEmpty
                          ? Colors.redAccent
                          : hintColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 2),
              IconButton(
                icon: Icon(Icons.keyboard_arrow_up, size: 17, color: iconColor),
                tooltip: s.searchPrevious,
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _searchTotalMatches > 0 ? searchPrev : null,
              ),
              IconButton(
                icon: Icon(Icons.keyboard_arrow_down, size: 17, color: iconColor),
                tooltip: s.searchNext,
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: _searchTotalMatches > 0 ? searchNext : null,
              ),
              const SizedBox(width: 4),
              Container(width: 1, height: 14, color: borderColor),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.close, size: 15, color: iconColor),
                tooltip: s.closeSearch,
                splashRadius: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: closeSearch,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
