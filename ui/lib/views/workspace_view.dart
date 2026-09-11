import 'dart:async';
import 'dart:ui';
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
  // Zen Mode: clean reading canvas by default, toolbar visible until scroll
  bool _isSidebarOpen = false;
  bool _isToolbarVisible = true;
  bool _isHoveringToolbar = false;
  Timer? _toolbarTimer;
  final GlobalKey<PdfCanvasViewState> _pdfCanvasKey = GlobalKey<PdfCanvasViewState>();

  @override
  void initState() {
    super.initState();
    // Briefly display the toolbar on launch so the user discovers the controls
    _showToolbarTemporarily();
  }

  @override
  void dispose() {
    _toolbarTimer?.cancel();
    super.dispose();
  }

  void _showToolbarTemporarily() {
    _toolbarTimer?.cancel();
    if (!_isToolbarVisible) {
      setState(() {
        _isToolbarVisible = true;
      });
    }
    _startToolbarTimer();
  }

  void _startToolbarTimer() {
    _toolbarTimer?.cancel();
    _toolbarTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_isHoveringToolbar) {
        setState(() {
          _isToolbarVisible = false;
        });
      }
    });
  }

  void _hideToolbar() {
    if (_isHoveringToolbar) return;
    _toolbarTimer?.cancel();
    if (_isToolbarVisible) {
      setState(() {
        _isToolbarVisible = false;
      });
    }
  }

  void _toggleToolbar() {
    _toolbarTimer?.cancel();
    setState(() {
      _isToolbarVisible = !_isToolbarVisible;
    });
    if (_isToolbarVisible) {
      _startToolbarTimer();
    }
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt'],
        dialogTitle: '选择要阅读的 Markdown 文件',
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          await widget.controller.openFile(path);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开文件失败: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

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
              success ? '已成功导出出版级 PDF 至 $savePath' : '导出失败，请重试',
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _handleCopySelection() async {
    final copied = await _pdfCanvasKey.currentState?.copyTextSelection() ?? false;
    if (!mounted) return;
    if (copied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制所选文本'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, meta: true): _pickAndOpenFile,
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
          setState(() => _isSidebarOpen = !_isSidebarOpen);
        },
        const SingleActivator(LogicalKeyboardKey.keyE, meta: true): _handleExportPdf,
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            controller.compileDocument,
        const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
            controller.toggleTheme,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            controller.toggleMode,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () {
          controller.setFontSize(controller.renderOptions.fontSize + 0.5);
        },
        const SingleActivator(LogicalKeyboardKey.add, meta: true): () {
          controller.setFontSize(controller.renderOptions.fontSize + 0.5);
        },
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () {
          controller.setFontSize(controller.renderOptions.fontSize - 0.5);
        },
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
          controller.setFontSize(10.5);
        },
        const SingleActivator(LogicalKeyboardKey.backslash, meta: true): _toggleToolbar,
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_isToolbarVisible) {
            setState(() => _isToolbarVisible = false);
          } else if (_isSidebarOpen) {
            setState(() => _isSidebarOpen = false);
          }
        },
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _handleCopySelection,
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () async {
          await _pdfCanvasKey.currentState?.selectAllText();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              // Collapsible Left Sidebar (Outline & Recents)
              if (_isSidebarOpen)
                SidebarView(
                  controller: controller,
                  onClose: () => setState(() => _isSidebarOpen = false),
                ),

              // Main Canvas + Zen Floating Toolbar Stack
              Expanded(
                child: Stack(
                  children: [
                    // Pure Edge-to-Edge PDF Canvas
                    PdfCanvasView(
                      key: _pdfCanvasKey,
                      pdfBytes: controller.currentPdfBytes,
                      documentTitle: controller.documentTitle,
                      controller: controller,
                      onUserScrolled: _hideToolbar,
                      onCanvasTapped: _toggleToolbar,
                      onOpenFile: _pickAndOpenFile,
                      onToggleSidebar: () =>
                          setState(() => _isSidebarOpen = !_isSidebarOpen),
                      onExportPdf: _handleExportPdf,
                    ),

                    // Top Hover Zone: moving mouse to the top edge gracefully brings up the floating controls
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 72,
                      child: MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        onEnter: (_) => _showToolbarTemporarily(),
                        onHover: (event) {
                          if (event.position.dy <= 72) {
                            _showToolbarTemporarily();
                          }
                        },
                      ),
                    ),

                    // Zen Floating Frosted Glass Pill Toolbar
                    Positioned(
                      top: 32,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: IgnorePointer(
                          ignoring: !_isToolbarVisible,
                          child: MouseRegion(
                            onEnter: (_) {
                              _isHoveringToolbar = true;
                              _toolbarTimer?.cancel();
                            },
                            onExit: (_) {
                              _isHoveringToolbar = false;
                              _startToolbarTimer();
                            },
                            child: AnimatedSlide(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              offset: _isToolbarVisible
                                  ? Offset.zero
                                  : const Offset(0, -1.2),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _isToolbarVisible ? 1.0 : 0.0,
                                child: _buildFloatingPill(context, isDark, controller),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Floating Error Toast / Banner (if any error occurs)
                    if (controller.errorMessage != null)
                      Positioned(
                        bottom: 20,
                        left: 24,
                        right: 24,
                        child: Center(
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 600),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xE6B91C1C),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 12,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    controller.errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: controller.compileDocument,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: const Text('重试', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
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
    },
  );
}

  Widget _buildFloatingPill(
    BuildContext context,
    bool isDark,
    ReaderController controller,
  ) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xD8202020) : const Color(0xF2FFFFFF),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0x30FFFFFF) : const Color(0x18000000),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Open Local File
              _PillIconButton(
                icon: Icons.folder_open_rounded,
                tooltip: '打开本地 Markdown (Cmd+O)',
                onPressed: _pickAndOpenFile,
              ),
              _PillDivider(isDark: isDark),

              // Sidebar Outline Toggle
              _PillIconButton(
                icon: _isSidebarOpen
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
                tooltip: _isSidebarOpen ? '收起侧边栏 (Cmd+B)' : '展开侧边栏 (Cmd+B)',
                isSelected: _isSidebarOpen,
                onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
              ),
              _PillDivider(isDark: isDark),

              // Document Title & Compiling indicator
              Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        controller.documentTitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (controller.isCompiling) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                  ],
                ),
              ),
              _PillDivider(isDark: isDark),

              // Mode switcher (Fluid vs A4 Paged)
              _ModePill(
                mode: controller.renderOptions.mode,
                onToggle: controller.toggleMode,
                isDark: isDark,
              ),
              _PillDivider(isDark: isDark),

              // Font Size Adjustment (- / +)
              _PillIconButton(
                icon: Icons.remove_rounded,
                tooltip: '缩小排版字号 (Cmd+-)',
                iconSize: 15,
                onPressed: () => controller.setFontSize(
                  controller.renderOptions.fontSize - 0.5,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  controller.renderOptions.fontSize.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _PillIconButton(
                icon: Icons.add_rounded,
                tooltip: '放大排版字号 (Cmd+=)',
                iconSize: 15,
                onPressed: () => controller.setFontSize(
                  controller.renderOptions.fontSize + 0.5,
                ),
              ),
              _PillDivider(isDark: isDark),

              // Theme Toggle (Light / Dark)
              _PillIconButton(
                icon: controller.renderOptions.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                tooltip: controller.renderOptions.isDark
                    ? '切换为亮色模式 (Cmd+T)'
                    : '切换为暗黑模式 (Cmd+T)',
                onPressed: controller.toggleTheme,
              ),
              _PillDivider(isDark: isDark),

              // Export PDF
              _PillIconButton(
                icon: Icons.download_rounded,
                tooltip: '导出出版级 PDF (Cmd+E)',
                onPressed: _handleExportPdf,
              ),
              _PillDivider(isDark: isDark),

              // Zen Mode Button (Hide Floating Toolbar)
              _PillIconButton(
                icon: Icons.close_rounded,
                tooltip: '隐藏工具栏 (Esc 或 Cmd+\\)',
                onPressed: () => setState(() => _isToolbarVisible = false),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}

class _PillIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isSelected;
  final double iconSize;

  const _PillIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isSelected = false,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface.withValues(alpha: 0.75);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String mode;
  final VoidCallback onToggle;
  final bool isDark;

  const _ModePill({
    required this.mode,
    required this.onToggle,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final isFluid = mode == 'fluid';
    final theme = Theme.of(context);

    return Tooltip(
      message: isFluid ? '当前：自适应流式 (点击切换 A4 出版 Cmd+P)' : '当前：A4 出版 (点击切换流式 Cmd+P)',
      waitDuration: const Duration(milliseconds: 500),
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFluid ? Icons.view_stream_rounded : Icons.auto_stories_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                isFluid ? '流式' : 'A4',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillDivider extends StatelessWidget {
  final bool isDark;

  const _PillDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
    );
  }
}

