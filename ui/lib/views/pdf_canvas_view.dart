import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';

class PdfCanvasView extends StatefulWidget {
  final Uint8List? pdfBytes;
  final String documentTitle;
  final ReaderController controller;

  const PdfCanvasView({
    super.key,
    required this.pdfBytes,
    required this.documentTitle,
    required this.controller,
  });

  @override
  State<PdfCanvasView> createState() => _PdfCanvasViewState();
}

class _PdfCanvasViewState extends State<PdfCanvasView> {
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
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(
              '正在排版文档...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 14,
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
      body: PdfViewer.data(
        widget.pdfBytes!,
        key: ValueKey('${widget.documentTitle}_${widget.pdfBytes!.length}'),
        sourceName: widget.documentTitle,
        controller: _pdfController,
        params: PdfViewerParams(
          backgroundColor: canvasBg,
          pageAnchor: PdfPageAnchor.top,
          underflowAnchor: PdfPageAnchor.top,
          onViewerReady: (document, controller) {
            _restoreScroll();
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
    );
  }

}
