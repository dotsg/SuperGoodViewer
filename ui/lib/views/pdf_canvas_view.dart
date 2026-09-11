import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';

class PdfCanvasView extends StatefulWidget {
  final Uint8List? pdfBytes;
  final String documentTitle;
  final ReaderController controller;
  final VoidCallback? onUserScrolled;
  final VoidCallback? onCanvasTapped;
  final VoidCallback? onOpenFile;
  final VoidCallback? onToggleSidebar;
  final VoidCallback? onExportPdf;

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
  });

  @override
  State<PdfCanvasView> createState() => PdfCanvasViewState();
}

class PdfCanvasViewState extends State<PdfCanvasView> {
  late final PdfViewerController _pdfController;
  bool _isRestoringScroll = false;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _pdfController.addListener(_onPdfViewerChanged);
  }

  void _onPdfViewerChanged() {
    if (_isRestoringScroll) return;
    if (_pdfController.isReady) {
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
