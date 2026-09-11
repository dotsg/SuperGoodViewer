import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/reader_controller.dart';
import 'pdf_canvas_view.dart';
import 'sidebar_view.dart';

class WorkspaceView extends StatefulWidget {
  final ReaderController controller;

  const WorkspaceView({super.key, required this.controller});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  bool _isSidebarOpen = true;

  Future<void> _handleExportPdf() async {
    final title = widget.controller.documentTitle.replaceAll(' ', '_');
    final defaultFileName = '$title.pdf';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出为出版级 PDF',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (savePath != null) {
      final success = await widget.controller.exportPdf(savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? '已成功导出 PDF 至 $savePath' : '导出失败，请重试',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = widget.controller;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
          // Cmd+O open file
        },
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _handleExportPdf,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            controller.compileDocument,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            controller.toggleTheme,
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true):
            controller.toggleMode,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              // Modern Desktop Top Navigation Bar
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF222222) : Colors.white,
                  border: Border(
                    bottom: BorderSide(
                      color: isDark
                          ? const Color(0xFF333333)
                          : const Color(0xFFE5E5E5),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Sidebar toggle
                    IconButton(
                      tooltip: _isSidebarOpen ? '收起侧边栏' : '展开侧边栏',
                      icon: Icon(
                        _isSidebarOpen
                            ? Icons.menu_open_rounded
                            : Icons.menu_rounded,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isSidebarOpen = !_isSidebarOpen;
                        });
                      },
                    ),
                    const SizedBox(width: 8),

                    // Document Title & Mode Tag
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              controller.documentTitle,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (controller.isCompiling)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                    ),

                    // View Mode Toggle (Fluid vs Paged)
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'fluid',
                          icon: Icon(Icons.view_stream_rounded, size: 16),
                          label: Text('自适应流式', style: TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: 'paged',
                          icon: Icon(Icons.auto_stories_rounded, size: 16),
                          label: Text('A4 出版', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {controller.renderOptions.mode},
                      onSelectionChanged: (val) {
                        if (val.first != controller.renderOptions.mode) {
                          controller.toggleMode();
                        }
                      },
                      style: ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Theme Toggle
                    IconButton(
                      tooltip: controller.renderOptions.isDark ? '切换浅色模式' : '切换暗黑模式',
                      icon: Icon(
                        controller.renderOptions.isDark
                            ? Icons.light_mode_rounded
                            : Icons.dark_mode_rounded,
                        size: 19,
                      ),
                      onPressed: controller.toggleTheme,
                    ),

                    // Refresh Button
                    IconButton(
                      tooltip: '重新编译排版 (Cmd+R)',
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      onPressed: controller.compileDocument,
                    ),

                    const SizedBox(width: 4),

                    // Export PDF Button
                    FilledButton.icon(
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text('导出 PDF', style: TextStyle(fontSize: 12.5)),
                      onPressed: _handleExportPdf,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Error Banner (if any)
              if (controller.errorMessage != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Colors.red.shade900,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          controller.errorMessage!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 16,
                        ),
                        onPressed: () {
                          // Clear error
                        },
                      ),
                    ],
                  ),
                ),

              // Workspace Body: Sidebar + PDF Viewport
              Expanded(
                child: Row(
                  children: [
                    if (_isSidebarOpen) SidebarView(controller: controller),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // Dynamically adapt fluid viewport width to window size
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final targetWidth = (constraints.maxWidth - 64)
                                .clamp(600.0, 1400.0);
                            controller.setViewportWidth(targetWidth);
                          });

                          return PdfCanvasView(
                            pdfBytes: controller.currentPdfBytes,
                            documentTitle: controller.documentTitle,
                            controller: controller,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
