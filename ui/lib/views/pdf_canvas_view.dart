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
  });

  @override
  State<PdfCanvasView> createState() => PdfCanvasViewState();
}

class PdfCanvasViewState extends State<PdfCanvasView> {
  late final PdfViewerController _pdfController;
  bool _isRestoringScroll = false;
  double _currentZoom = 1.0;

  double get currentZoom => _pdfController.isReady ? _pdfController.currentZoom : _currentZoom;
  bool get isReady => _pdfController.isReady;

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
    target = target.clamp(0.2, 5.0);
    final center = focalPoint ?? _pdfController.centerPosition;
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
    target = target.clamp(0.2, 5.0);
    final center = focalPoint ?? _pdfController.centerPosition;
    await _pdfController.setZoom(
      center,
      target,
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> resetZoom() async {
    if (!_pdfController.isReady) return;
    final center = _pdfController.centerPosition;
    await _pdfController.setZoom(
      center,
      1.0,
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> zoomTo(double targetZoom, {Offset? focalPoint}) async {
    if (!_pdfController.isReady) return;
    final center = focalPoint ?? _pdfController.centerPosition;
    await _pdfController.setZoom(
      center,
      targetZoom.clamp(0.2, 5.0),
      duration: const Duration(milliseconds: 180),
    );
  }

  Future<void> fitWidth() async {
    if (!_pdfController.isReady) return;
    final pageLayouts = _pdfController.layout.pageLayouts;
    if (pageLayouts.isEmpty) return;
    final pageIndex = ((_pdfController.pageNumber ?? 1) - 1).clamp(0, pageLayouts.length - 1);
    final page = pageLayouts[pageIndex];
    final viewWidth = _pdfController.viewSize.width;
    final margin = _pdfController.params.margin;

    final targetZoom = ((viewWidth - margin * 2) / page.width).clamp(0.2, 5.0);
    final targetCenter = Offset(page.center.dx, _pdfController.centerPosition.dy);
    await _pdfController.setZoom(
      targetCenter,
      targetZoom,
      duration: const Duration(milliseconds: 220),
    );
  }

  Future<void> fitPage() async {
    if (!_pdfController.isReady) return;
    final pageLayouts = _pdfController.layout.pageLayouts;
    if (pageLayouts.isEmpty) return;
    final pageIndex = ((_pdfController.pageNumber ?? 1) - 1).clamp(0, pageLayouts.length - 1);
    final page = pageLayouts[pageIndex];
    final viewSize = _pdfController.viewSize;
    final margin = _pdfController.params.margin;

    if (widget.controller.renderOptions.isFluid) {
      final fitWidthZoom = (viewSize.width - margin * 2) / page.width;
      final targetZoom = (fitWidthZoom < 1.0 ? fitWidthZoom : 1.0).clamp(0.2, 5.0);
      final targetCenter = Offset(page.center.dx, _pdfController.centerPosition.dy);
      await _pdfController.setZoom(
        targetCenter,
        targetZoom,
        duration: const Duration(milliseconds: 220),
      );
    } else {
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
          key: ValueKey('${widget.documentTitle}_${widget.pdfBytes!.hashCode}'),
          sourceName: '${widget.documentTitle}_${widget.pdfBytes!.hashCode}',
          controller: _pdfController,
          params: PdfViewerParams(
            backgroundColor: canvasBg,
            margin: 16.0,
            boundaryMargin: const EdgeInsets.only(
              top: 48,
              bottom: 48,
              left: 20,
              right: 20,
            ),
            pageAnchor: PdfPageAnchor.top,
            underflowAnchor: PdfPageAnchor.top,
            sizeDelegateProvider: const PdfViewerSizeDelegateProviderSmart(
              smartMaxScale: 5.0,
              maxScale: 5.0,
              minScale: 0.2,
            ),
            textSelectionParams: const PdfTextSelectionParams(
              enabled: true,
              showContextMenuAutomatically: true,
            ),
            onViewerReady: (document, controller) {
              _restoreScroll();
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
