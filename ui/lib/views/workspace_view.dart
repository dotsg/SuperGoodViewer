import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../controllers/reader_controller.dart';
import '../i18n/app_strings.dart';
import '../models/render_options.dart';
import '../services/cli_ipc_service.dart';
import '../services/native_cli_service.dart';
import 'pdf_canvas_view.dart';
import 'presentation_view.dart';
import 'settings_dialog.dart';
import 'sidebar_view.dart';
import 'update_dialog.dart';
import '../services/update_service.dart';

class WorkspaceView extends StatefulWidget {
  final ReaderController controller;

  const WorkspaceView({super.key, required this.controller});

  @override
  State<WorkspaceView> createState() => _WorkspaceViewState();
}

class _WorkspaceViewState extends State<WorkspaceView> {
  // Zen Mode: clean reading canvas by default, toolbar visible until scroll
  bool get _isSidebarOpen => widget.controller.isSidebarOpen;
  bool _isToolbarVisible = true;
  bool _isHoveringToolbar = false;
  Timer? _toolbarTimer;
  final GlobalKey<PdfCanvasViewState> _pdfCanvasKey = GlobalKey<PdfCanvasViewState>();
  final GlobalKey<PresentationViewState> _presentationKey = GlobalKey<PresentationViewState>();

  // Titlebar auto-hide on scroll
  bool _isTitleBarVisible = true;
  bool _isAtTop = true;
  bool _isHoveringTitleBar = false;
  Timer? _titleBarHoverTimer;
  bool _isDraggingFileOver = false;

  bool get _shouldShowTitleBar {
    if (_isFullScreen) return false;
    if (_isSidebarOpen) return true;
    if (_isHoveringTitleBar) return true;
    return _isAtTop && _isTitleBarVisible;
  }

  void _updateTrafficLights() {
    // In full screen, macOS handles traffic lights automatically on top hover.
    // Never hide standard window buttons in full screen mode.
    final show = _isFullScreen ? true : _shouldShowTitleBar;
    try {
      _windowChannel.invokeMethod('setTrafficLightsVisible', show);
    } catch (_) {}
  }

  int _currentPage = 1;
  int _pageCount = 1;

  double _currentZoom = 1.0;
  bool _isZoomHudVisible = false;
  String _zoomHudText = '100%';
  Timer? _zoomHudTimer;
  Timer? _updateCheckTimer;

  bool _isFullScreen = false;
  static const _windowChannel = MethodChannel('com.sogoodviewer.window');

  @override
  void initState() {
    super.initState();
    final isFluid = widget.controller.isFluidLayout;
    final atTop = isFluid
        ? (widget.controller.lastScrollOffset <= ReaderController.topScrollThreshold && widget.controller.lastScrollRatio <= 0.005)
        : (widget.controller.lastScrollRatio <= 0.005 && widget.controller.lastPageNumber <= 1);
    _isAtTop = atTop;
    _isTitleBarVisible = atTop;
    _initWindowChannel();
    // Briefly display the toolbar on launch so the user discovers the controls
    _showToolbarTemporarily();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateTrafficLights();
      _syncWindowTitle();
    });
    widget.controller.addListener(_onControllerChanged);
    NativeCliService.channel.setMethodCallHandler(_handleNativeMethodCall);
    _checkInitialFileFromSystem();
    CliIpcService.start((filePath) {
      if (mounted) {
        widget.controller.openFile(filePath);
      }
    });
    _scheduleStartupUpdateCheck();
  }

  void _scheduleStartupUpdateCheck() {
    if (!widget.controller.autoRestorePreferences) return;

    _updateCheckTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      try {
        final info = await UpdateService.instance.checkUpdate(
          currentVersion: SettingsDialog.appVersion,
          isManual: false,
        );
        if (info.hasUpdate && mounted) {
          UpdateDialog.show(context, widget.controller, info);
        }
      } catch (e) {
        debugPrint('[UpdateService] Startup check skipped or failed: $e');
      }
    });
  }

  String? _lastSyncedTitle;

  void _syncWindowTitle() {
    final appTitle = widget.controller.strings.appTitle;
    final docTitle = widget.controller.documentTitle;
    final fullTitle = (docTitle.isNotEmpty && docTitle != 'Welcome' && docTitle != 'SuperGoodViewer Demo')
        ? '$docTitle - $appTitle'
        : appTitle;

    if (_lastSyncedTitle != fullTitle) {
      _lastSyncedTitle = fullTitle;
      try {
        _windowChannel.invokeMethod('setWindowTitle', fullTitle);
      } catch (_) {}
    }
  }

  void _initWindowChannel() {
    _windowChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFullScreenChanged') {
        final isFs = call.arguments as bool? ?? false;
        if (mounted && _isFullScreen != isFs) {
          setState(() => _isFullScreen = isFs);
          _updateTrafficLights();
        }
      }
    });
    _windowChannel.invokeMethod<bool>('isFullScreen').then((isFs) {
      if (isFs != null && mounted && _isFullScreen != isFs) {
        setState(() => _isFullScreen = isFs);
        _updateTrafficLights();
      }
    }).catchError((_) {});
  }

  Future<void> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onOpenFile') {
      final path = call.arguments as String?;
      if (path != null && path.isNotEmpty) {
        await widget.controller.openFile(path);
      }
    } else if (call.method == 'showCliDialog') {
      if (mounted) {
        showSettingsDialog(context, widget.controller, initialTab: SettingsTab.cli);
      }
    }
  }

  Future<void> _checkInitialFileFromSystem() async {
    final file = await NativeCliService.getInitialFile();
    if (file != null && file.isNotEmpty) {
      await widget.controller.openFile(file);
    }
  }

  void _onControllerChanged() {
    if (widget.controller.requestedJumpItem != null) {
      final req = widget.controller.requestedJumpItem!;
      widget.controller.clearJumpRequest();
      _pdfCanvasKey.currentState?.jumpToOutline(req);
    }
    if (!widget.controller.isPresentationMode && _enteredFullScreenForPresentation) {
      _enteredFullScreenForPresentation = false;
      if (_isFullScreen) {
        _toggleFullScreen();
      }
    }
    _syncWindowTitle();
    _updateTrafficLights();
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    CliIpcService.stop();
    NativeCliService.channel.setMethodCallHandler(null);
    widget.controller.removeListener(_onControllerChanged);
    _toolbarTimer?.cancel();
    _zoomHudTimer?.cancel();
    _titleBarHoverTimer?.cancel();
    _updateCheckTimer?.cancel();
    super.dispose();
  }

  void _handleScrollChanged({required double deltaY, required bool isAtTop}) {
    if (isAtTop) {
      _titleBarHoverTimer?.cancel();
      if (!_isAtTop || !_isTitleBarVisible) {
        setState(() {
          _isAtTop = true;
          _isTitleBarVisible = true;
        });
        _updateTrafficLights();
      }
      return;
    }

    // When scrolling down, cancel hover so titlebar reliably hides
    if (deltaY > 1.0) {
      _isHoveringTitleBar = false;
      _titleBarHoverTimer?.cancel();
    }

    if (_isAtTop || _isTitleBarVisible) {
      setState(() {
        _isAtTop = false;
        if (!_isSidebarOpen && !_isHoveringTitleBar) {
          _isTitleBarVisible = false;
        }
      });
      _updateTrafficLights();
    }
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

  void _setSidebarOpen(bool open) {
    if (_isSidebarOpen != open) {
      if (!open && !_isAtTop && !_isHoveringTitleBar) {
        setState(() {
          _isTitleBarVisible = false;
        });
      }
      widget.controller.setSidebarOpen(open);
      _updateTrafficLights();
    }
  }

  void _toggleSidebar() {
    _setSidebarOpen(!_isSidebarOpen);
  }

  Future<void> _pickAndOpenFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['md', 'markdown', 'txt', 'pdf'],
        dialogTitle: widget.controller.strings.openDocument,
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
            content: Text(widget.controller.strings.openFileFailed('$e')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  static const Set<String> _supportedExtensions = {
    '.md',
    '.markdown',
    '.mdown',
    '.mkd',
    '.mdx',
    '.pdf',
    '.typ',
    '.txt',
  };

  static const Set<String> _knownBinaryExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico', '.tiff', '.heic',
    '.zip', '.tar', '.gz', '.7z', '.rar', '.bz2', '.xz',
    '.dmg', '.iso', '.pkg', '.app', '.exe', '.dll', '.so', '.dylib', '.bin',
    '.mp4', '.mov', '.avi', '.mkv', '.webm', '.mp3', '.wav', '.flac', '.aac',
    '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
  };

  static Future<bool> _isFileSupported(File file) async {
    final ext = p.extension(file.path).toLowerCase();
    if (_supportedExtensions.contains(ext)) return true;
    if (_knownBinaryExtensions.contains(ext)) return false;

    // For files with unknown or missing extension, inspect sample bytes
    try {
      RandomAccessFile? raf;
      Uint8List sample;
      try {
        raf = await file.open(mode: FileMode.read);
        sample = await raf.read(1024);
      } finally {
        await raf?.close();
      }

      if (sample.isEmpty) return true; // Empty file is safe to open as empty markdown
      if (ReaderController.startsWithPdfHeader(sample)) return true;

      // If sample contains null bytes, it's very likely a binary format
      if (sample.contains(0)) return false;

      // Otherwise, attempt UTF-8 decode
      utf8.decode(sample, allowMalformed: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _handleDroppedFiles(List<DropItem> files) async {
    if (files.isEmpty) return;

    String? targetFilePath;
    String? unsupportedReason;

    for (final file in files) {
      final path = file.path;
      if (path.isEmpty) continue;

      try {
        final type = await FileSystemEntity.type(path);
        if (type == FileSystemEntityType.file) {
          final f = File(path);
          if (await _isFileSupported(f)) {
            targetFilePath = path;
            break;
          } else {
            final ext = p.extension(path);
            unsupportedReason = ext.isNotEmpty
                ? widget.controller.strings.unsupportedFileFormat(ext)
                : widget.controller.strings.unsupportedBinaryFile;
          }
        } else if (type == FileSystemEntityType.directory) {
          // If a directory was dropped, check for common entry files
          const candidates = [
            'README.md',
            'readme.md',
            'index.md',
            'main.md',
            'README.markdown',
            'readme.markdown',
          ];
          for (final c in candidates) {
            final candidateFile = File(p.join(path, c));
            if (await candidateFile.exists()) {
              targetFilePath = candidateFile.path;
              break;
            }
          }
          if (targetFilePath != null) break;

          // Try to find the first supported file in the directory (sorted deterministically)
          final dir = Directory(path);
          final entries = await dir.list(followLinks: false).toList();
          entries.sort((a, b) {
            final cmp = a.path.toLowerCase().compareTo(b.path.toLowerCase());
            return cmp != 0 ? cmp : a.path.compareTo(b.path);
          });
          for (final entry in entries) {
            if (entry is File && await _isFileSupported(entry)) {
              targetFilePath = entry.path;
              break;
            }
          }
          if (targetFilePath != null) break;

          unsupportedReason = widget.controller.strings.unsupportedDirectory;
        }
      } catch (e) {
        debugPrint('Error inspecting dropped file: $e');
      }
    }

    if (targetFilePath != null) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
      }
      await widget.controller.openFile(targetFilePath);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(unsupportedReason ?? widget.controller.strings.unsupportedDropGeneral),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleExportPdf() async {
    final title = widget.controller.documentTitle.replaceAll(' ', '_');
    final defaultFileName = '$title.pdf';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: widget.controller.strings.exportPdfDialogTitle,
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
              success ? widget.controller.strings.exportPdfSuccess(savePath) : widget.controller.strings.exportPdfFailed,
            ),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showCopiedFeedback() {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.controller.strings.copiedSelectedText),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleCopySelection() async {
    final copied = await _pdfCanvasKey.currentState?.copyTextSelection() ?? false;
    if (!mounted) return;
    if (copied) {
      _showCopiedFeedback();
    }
  }

  void _handleNextPage() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.nextPage();
      return;
    }
    if (!_isSidebarOpen && !_isHoveringTitleBar && (_isTitleBarVisible || _isAtTop)) {
      setState(() {
        _isAtTop = false;
        _isTitleBarVisible = false;
      });
      _updateTrafficLights();
    }
    if (widget.controller.isFluidLayout) {
      _pdfCanvasKey.currentState?.scrollScreenDown();
    } else {
      _pdfCanvasKey.currentState?.nextPage();
    }
  }

  void _handlePrevPage() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.prevPage();
      return;
    }
    if (widget.controller.isFluidLayout) {
      _pdfCanvasKey.currentState?.scrollScreenUp();
    } else {
      if (_currentPage <= 2) {
        setState(() {
          _isAtTop = true;
          _isTitleBarVisible = true;
        });
        _updateTrafficLights();
      }
      _pdfCanvasKey.currentState?.prevPage();
    }
  }

  void _handleScrollScreenDown() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.nextPage();
      return;
    }
    if (!_isSidebarOpen && !_isHoveringTitleBar && (_isTitleBarVisible || _isAtTop)) {
      setState(() {
        _isAtTop = false;
        _isTitleBarVisible = false;
      });
      _updateTrafficLights();
    }
    if (!widget.controller.isFluidLayout) {
      final canvas = _pdfCanvasKey.currentState;
      if (canvas != null && canvas.isCurrentPageFittingViewport) {
        _handleNextPage();
        return;
      }
    }
    _pdfCanvasKey.currentState?.scrollScreenDown();
  }

  void _handleScrollScreenUp() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.prevPage();
      return;
    }
    if (!widget.controller.isFluidLayout) {
      final canvas = _pdfCanvasKey.currentState;
      if (canvas != null && canvas.isCurrentPageFittingViewport) {
        _handlePrevPage();
        return;
      }
    }
    _pdfCanvasKey.currentState?.scrollScreenUp();
  }

  void _handleFirstPage() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.goToPage(1);
      return;
    }
    setState(() {
      _isAtTop = true;
      _isTitleBarVisible = true;
    });
    _updateTrafficLights();
    _pdfCanvasKey.currentState?.goToPageNumber(1);
  }

  void _handleLastPage() {
    if (_pdfCanvasKey.currentState?.isSearchFocused == true) return;
    if (widget.controller.isPresentationMode) {
      _presentationKey.currentState?.goToLastPage();
      return;
    }
    if (!_isSidebarOpen && !_isHoveringTitleBar) {
      setState(() {
        _isAtTop = false;
        _isTitleBarVisible = false;
      });
      _updateTrafficLights();
    }
    _pdfCanvasKey.currentState?.goToPageNumber(_pageCount);
  }

  void _handleToggleTwoPage() {
    if (widget.controller.isFluidLayout) {
      widget.controller.toggleMode();
      if (!widget.controller.isTwoPage) {
        widget.controller.toggleTwoPage();
      }
      _showZoomHud(widget.controller.strings.hudTwoPageA4);
    } else {
      widget.controller.toggleTwoPage();
      _showZoomHud(widget.controller.isTwoPage ? widget.controller.strings.hudTwoPage : widget.controller.strings.hudSinglePage);
    }
  }

  Future<void> _toggleFullScreen() async {
    try {
      final res = await _windowChannel.invokeMethod('toggleFullScreen');
      if (res is bool && mounted) {
        setState(() => _isFullScreen = res);
      }
    } catch (_) {}
  }

  bool _enteredFullScreenForPresentation = false;

  Future<void> _handleTogglePresentation() async {
    final willEnter = !widget.controller.isPresentationMode;
    if (willEnter) {
      if (!_isFullScreen) {
        _enteredFullScreenForPresentation = true;
        await _toggleFullScreen();
      } else {
        _enteredFullScreenForPresentation = false;
      }
      widget.controller.setPresentationMode(true);
    } else {
      await _exitPresentationMode();
    }
  }

  Future<void> _exitPresentationMode() async {
    widget.controller.setPresentationMode(false);
    if (_enteredFullScreenForPresentation) {
      _enteredFullScreenForPresentation = false;
      if (_isFullScreen) {
        await _toggleFullScreen();
      }
    }
  }

  void _showZoomHud(String text) {
    _zoomHudTimer?.cancel();
    setState(() {
      _zoomHudText = text;
      _isZoomHudVisible = true;
    });
    _zoomHudTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) {
        setState(() {
          _isZoomHudVisible = false;
        });
      }
    });
  }

  void _handleZoomIn() async {
    widget.controller.setAutoFitMode(AutoFitMode.none);
    await _pdfCanvasKey.currentState?.zoomIn();
    final zoom = _pdfCanvasKey.currentState?.currentZoom ?? _currentZoom;
    setState(() => _currentZoom = zoom);
    _showZoomHud('${(zoom * 100).round()}%');
  }

  void _handleZoomOut() async {
    widget.controller.setAutoFitMode(AutoFitMode.none);
    await _pdfCanvasKey.currentState?.zoomOut();
    final zoom = _pdfCanvasKey.currentState?.currentZoom ?? _currentZoom;
    setState(() => _currentZoom = zoom);
    _showZoomHud('${(zoom * 100).round()}%');
  }

  void _handleResetZoom() async {
    widget.controller.setAutoFitMode(AutoFitMode.none);
    await _pdfCanvasKey.currentState?.resetZoom();
    setState(() => _currentZoom = 1.0);
    _showZoomHud(widget.controller.strings.hudActualSize);
  }

  void _handleFitWidth() async {
    widget.controller.setAutoFitMode(AutoFitMode.fitWidth);
    await _pdfCanvasKey.currentState?.fitWidth();
    final zoom = _pdfCanvasKey.currentState?.currentZoom ?? _currentZoom;
    setState(() => _currentZoom = zoom);
    _showZoomHud(widget.controller.strings.hudFitWidth((zoom * 100).round()));
  }

  void _handleFitPage() async {
    widget.controller.setAutoFitMode(AutoFitMode.fitPage);
    await _pdfCanvasKey.currentState?.fitPage();
    final zoom = _pdfCanvasKey.currentState?.currentZoom ?? _currentZoom;
    setState(() => _currentZoom = zoom);
    _showZoomHud(widget.controller.strings.hudFitPage((zoom * 100).round()));
  }

  void _handleZoomTo(double targetZoom) async {
    widget.controller.setAutoFitMode(AutoFitMode.none);
    await _pdfCanvasKey.currentState?.zoomTo(targetZoom);
    setState(() => _currentZoom = targetZoom);
    _showZoomHud('${(targetZoom * 100).round()}%');
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
            ...controller.shortcutService.buildBindings(
              onToggleMode: controller.toggleMode,
              onExportPdf: _handleExportPdf,
              onOpenFile: _pickAndOpenFile,
              onToggleSidebar: _toggleSidebar,
              onCompileDocument: controller.refreshDocument,
              onToggleTheme: controller.toggleTheme,
              onToggleTwoPage: _handleToggleTwoPage,
              onZoomIn: _handleZoomIn,
              onZoomOut: _handleZoomOut,
              onResetZoom: _handleResetZoom,
              onFitWidth: _handleFitWidth,
              onFitPage: _handleFitPage,
              onToggleToolbar: _toggleToolbar,
              onFontSettings: () => showSettingsDialog(context, controller, initialTab: SettingsTab.typography),
              onTogglePresentation: _handleTogglePresentation,
              onFindInDocument: () => _pdfCanvasKey.currentState?.openSearch(),
              onPreferences: () => showSettingsDialog(context, controller, initialTab: SettingsTab.general),
              onKeyboardShortcuts: () => showSettingsDialog(context, controller, initialTab: SettingsTab.shortcuts),
            ),

            // In-Document Search Shortcuts (Cmd+F / Ctrl+F, Cmd+G / Ctrl+G)
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
                _pdfCanvasKey.currentState?.openSearch(),
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
                _pdfCanvasKey.currentState?.openSearch(),
            const SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
                _pdfCanvasKey.currentState?.searchNext(),
            const SingleActivator(LogicalKeyboardKey.keyG, meta: true, shift: true): () =>
                _pdfCanvasKey.currentState?.searchPrev(),
            const SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
                _pdfCanvasKey.currentState?.searchNext(),
            const SingleActivator(LogicalKeyboardKey.keyG, control: true, shift: true): () =>
                _pdfCanvasKey.currentState?.searchPrev(),

            // Presentation Mode Direct Activators (F5, Cmd+Enter, Ctrl+Enter)
            const SingleActivator(LogicalKeyboardKey.f5): _handleTogglePresentation,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _handleTogglePresentation,
            const SingleActivator(LogicalKeyboardKey.enter, control: true): _handleTogglePresentation,

            // Zoom Keypad Aliases (Numpad +)
            const SingleActivator(LogicalKeyboardKey.add, meta: true): _handleZoomIn,
            const SingleActivator(LogicalKeyboardKey.add, control: true): _handleZoomIn,

            // Page Navigation & Book Mode (Arrow keys, Bracket keys, PageUp/PageDown)
            const SingleActivator(LogicalKeyboardKey.arrowLeft): _handlePrevPage,
            const SingleActivator(LogicalKeyboardKey.arrowRight): _handleNextPage,
            const SingleActivator(LogicalKeyboardKey.bracketLeft): _handlePrevPage,
            const SingleActivator(LogicalKeyboardKey.bracketRight): _handleNextPage,
            const SingleActivator(LogicalKeyboardKey.pageUp): _handlePrevPage,
            const SingleActivator(LogicalKeyboardKey.pageDown): _handleNextPage,

            // Scrolling (Arrow keys = line scroll, Space = screen scroll)
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _pdfCanvasKey.currentState?.scrollByDelta(-120),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _pdfCanvasKey.currentState?.scrollByDelta(120),
            const SingleActivator(LogicalKeyboardKey.space): _handleScrollScreenDown,
            const SingleActivator(LogicalKeyboardKey.space, shift: true): _handleScrollScreenUp,
            const SingleActivator(LogicalKeyboardKey.home): _handleFirstPage,
            const SingleActivator(LogicalKeyboardKey.end): _handleLastPage,
            const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): _handleFirstPage,
            const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): _handleLastPage,

            // Full Screen Toggle
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true, control: true):
                _toggleFullScreen,
            const SingleActivator(LogicalKeyboardKey.f11): _toggleFullScreen,

            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_pdfCanvasKey.currentState?.isSearchOpen == true) {
                _pdfCanvasKey.currentState?.closeSearch();
              } else if (controller.isPresentationMode) {
                _exitPresentationMode();
              } else if (_isFullScreen) {
                _toggleFullScreen();
              } else if (_isToolbarVisible) {
                setState(() => _isToolbarVisible = false);
              } else if (_isSidebarOpen) {
                _setSidebarOpen(false);
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                _handleCopySelection,
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _handleCopySelection,
            const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () async {
              await _pdfCanvasKey.currentState?.selectAllText();
            },
            const SingleActivator(LogicalKeyboardKey.keyA, control: true): () async {
              await _pdfCanvasKey.currentState?.selectAllText();
            },
          },
      child: DropTarget(
        onDragEntered: (_) => setState(() => _isDraggingFileOver = true),
        onDragExited: (_) => setState(() => _isDraggingFileOver = false),
        onDragDone: (detail) {
          setState(() => _isDraggingFileOver = false);
          _handleDroppedFiles(detail.files);
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              children: [
                Row(
            children: [
              // Collapsible Left Sidebar (Outline & Recents)
              if (_isSidebarOpen)
                SidebarView(
                  controller: controller,
                  onClose: () => _setSidebarOpen(false),
                  onJumpToOutline: (item) => _pdfCanvasKey.currentState?.jumpToOutline(item),
                ),

              // Main Canvas + Zen Floating Toolbar Stack
              Expanded(
                child: Stack(
                  children: [
                    // Pure Edge-to-Edge PDF Canvas (always fills 100% of workspace, zero layout shifting)
                    PdfCanvasView(
                      key: _pdfCanvasKey,
                      topInset: _shouldShowTitleBar ? 32.0 : 0.0,
                      pdfBytes: controller.currentPdfBytes,
                      documentTitle: controller.documentTitle,
                      renderOptions: controller.renderOptions,
                      isTwoPage: controller.isTwoPage,
                      controller: controller,
                      onUserScrolled: _hideToolbar,
                      onScrollChanged: _handleScrollChanged,
                      onCanvasTapped: _toggleToolbar,
                      onOpenFile: _pickAndOpenFile,
                      onToggleSidebar: _toggleSidebar,
                      onExportPdf: _handleExportPdf,
                      onZoomChanged: (zoom) {
                        if (mounted && (zoom - _currentZoom).abs() > 0.005) {
                          setState(() => _currentZoom = zoom);
                        }
                      },
                      onPageChanged: (pageNumber, pageCount) {
                        if (mounted && (_currentPage != pageNumber || _pageCount != pageCount)) {
                          setState(() {
                            _currentPage = pageNumber;
                            _pageCount = pageCount;
                          });
                        }
                      },
                      onTextCopied: _showCopiedFeedback,
                    ),

                    // Top Floating Unified Titlebar / Traffic Light Safe Strip
                    if (!_isFullScreen)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _buildTopTitleBar(context, isDark, controller),
                      ),

                    // Top Hover Zone: moving mouse to the very top edge gracefully brings up titlebar and floating controls
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        onEnter: (_) {
                          _titleBarHoverTimer?.cancel();
                          if (!_isHoveringTitleBar) {
                            setState(() => _isHoveringTitleBar = true);
                            _updateTrafficLights();
                          }
                          _showToolbarTemporarily();
                        },
                        onExit: (_) {
                          _titleBarHoverTimer?.cancel();
                          _titleBarHoverTimer = Timer(const Duration(milliseconds: 800), () {
                            if (mounted) {
                              setState(() => _isHoveringTitleBar = false);
                              _updateTrafficLights();
                            }
                          });
                        },
                      ),
                    ),

                    // Bottom Hover Zone: moving mouse to the bottom edge brings up the floating reading toolbar
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: MouseRegion(
                        hitTestBehavior: HitTestBehavior.translucent,
                        onEnter: (_) {
                          _showToolbarTemporarily();
                        },
                      ),
                    ),

                    // Zen Floating Frosted Glass Pill Toolbar (Bottom Reading HUD)
                    Positioned(
                      bottom: 24,
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
                                  : const Offset(0, 1.4),
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

                    // Transient Zoom HUD Capsule (Floats above the bottom pill toolbar)
                    if (_isZoomHudVisible)
                      Positioned(
                        bottom: 84,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _isZoomHudVisible ? 1.0 : 0.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xE6242424) : const Color(0xF2FFFFFF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isDark ? const Color(0x38FFFFFF) : const Color(0x1C000000),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.zoom_in_rounded,
                                      size: 16,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _zoomHudText,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black87,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ],
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
                                  onPressed: controller.refreshDocument,
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

                    // Full-screen Presentation View (PPT Mode)
                    if (controller.isPresentationMode && controller.currentPdfBytes != null)
                      Positioned.fill(
                        child: PresentationView(
                          key: _presentationKey,
                          controller: controller,
                          onExit: _exitPresentationMode,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_isDraggingFileOver)
            _buildDragDropOverlay(theme, isDark),
        ],
      ),
    ),
  ),
),
);
},
);
}

  Widget _buildDragDropOverlay(ThemeData theme, bool isDark) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: (isDark ? const Color(0xFF141414) : Colors.white).withValues(alpha: 0.88),
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0x1F0284C7) : const Color(0x0F0284C7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF0284C7),
                width: 2.5,
              ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0x330284C7) : const Color(0x240284C7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.file_download_outlined,
                      size: 40,
                      color: Color(0xFF0284C7),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.controller.strings.dragDropTitle,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.controller.strings.dragDropSubtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopTitleBar(
    BuildContext context,
    bool isDark,
    ReaderController controller,
  ) {
    final show = _shouldShowTitleBar;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      height: show ? 32.0 : 0.0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7)).withValues(alpha: 0.90),
        border: show
            ? Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5),
                  width: 1,
                ),
              )
            : null,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: OverflowBox(
            minHeight: 32.0,
            maxHeight: 32.0,
            alignment: Alignment.topCenter,
            child: MouseRegion(
              onEnter: (_) {
                _titleBarHoverTimer?.cancel();
                if (!_isHoveringTitleBar) {
                  setState(() => _isHoveringTitleBar = true);
                  _updateTrafficLights();
                }
              },
              onExit: (_) {
                _titleBarHoverTimer?.cancel();
                _titleBarHoverTimer = Timer(const Duration(milliseconds: 800), () {
                  if (mounted) {
                    setState(() => _isHoveringTitleBar = false);
                    _updateTrafficLights();
                  }
                });
              },
              child: Material(
                type: MaterialType.transparency,
                child: Row(
                  children: [
                    // When sidebar is closed, provide safe space for macOS traffic lights & sidebar button
                    if (!_isSidebarOpen) ...[
                      if (Platform.isMacOS) const SizedBox(width: 78),
                      Tooltip(
                        message: controller.strings.toggleSidebarTooltip(controller.shortcutService.getShortcutLabel('toggleSidebar')),
                        child: InkWell(
                          onTap: () => _setSidebarOpen(true),
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: Center(
                              child: Icon(
                                Icons.view_sidebar_outlined,
                                size: 16,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],

                    // Native window drag / caption area
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (_) {
                          try {
                            _windowChannel.invokeMethod('startDragging');
                          } catch (_) {}
                        },
                        onDoubleTap: () {
                          try {
                            _windowChannel.invokeMethod('zoom');
                          } catch (_) {}
                        },
                        child: Container(
                          height: 32,
                          alignment: Alignment.center,
                          child: controller.documentTitle.isNotEmpty
                              ? Text(
                                  controller.documentTitle,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ),

                    if (!_isSidebarOpen) SizedBox(width: (Platform.isMacOS ? 78.0 : 0.0) + 32.0),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingPill(
    BuildContext context,
    bool isDark,
    ReaderController controller,
  ) {
    const double pillHeight = 44.0;
    const double pillRadius = pillHeight / 2; // 22.0: Exact symmetrical semicircle pill ends

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(pillRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(pillRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xD0202020) : const Color(0xE8FFFFFF),
              borderRadius: BorderRadius.circular(pillRadius),
              border: Border.all(
                color: isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
                width: 1,
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
              // Open Local File
              _PillIconButton(
                icon: Icons.folder_open_rounded,
                tooltip: '${controller.strings.openDocument} (${controller.shortcutService.getShortcutLabel('openFile')})',
                onPressed: _pickAndOpenFile,
              ),
              _PillDivider(isDark: isDark),

              // Sidebar Outline Toggle
              _PillIconButton(
                icon: _isSidebarOpen
                    ? Icons.view_sidebar_rounded
                    : Icons.view_sidebar_outlined,
                tooltip: _isSidebarOpen
                    ? controller.strings.toggleSidebarCollapse(controller.shortcutService.getShortcutLabel('toggleSidebar'))
                    : controller.strings.toggleSidebarExpand(controller.shortcutService.getShortcutLabel('toggleSidebar')),
                isSelected: _isSidebarOpen,
                onPressed: _toggleSidebar,
              ),
              _PillDivider(isDark: isDark),

              // Mode & Layout switcher (Fluid, A4, 16:9, etc.) - Markdown only
              if (!controller.isPdfDocument) ...[
                _FormatSelectorPill(
                  format: controller.renderOptions.effectivePageFormat,
                  shortcutLabel: controller.shortcutService.getShortcutLabel('toggleMode'),
                  onSelectFormat: controller.setPageFormat,
                  onToggle: controller.toggleMode,
                  isDark: isDark,
                  strings: controller.strings,
                ),
                _PillDivider(isDark: isDark),
              ],

              // Full-screen Presentation Mode (PPT) - works for both Markdown and PDF
              _PillIconButton(
                icon: Icons.slideshow_rounded,
                tooltip: controller.strings.togglePresentationTooltip(controller.shortcutService.getShortcutLabel('togglePresentation')),
                isSelected: controller.isPresentationMode,
                iconSize: 18,
                onPressed: _handleTogglePresentation,
              ),
              _PillDivider(isDark: isDark),

              // When in A4 Paged mode or reading a PDF, show Two-Page Spread toggle and Page Navigation
              if (controller.isPdfDocument || !controller.renderOptions.isFluid) ...[
                _PillIconButton(
                  icon: controller.isTwoPage
                      ? Icons.auto_stories_rounded
                      : Icons.menu_book_outlined,
                  tooltip: controller.strings.toggleTwoPageTooltip(controller.isTwoPage, controller.shortcutService.getShortcutLabel('toggleTwoPage')),
                  isSelected: controller.isTwoPage,
                  iconSize: 17,
                  onPressed: _handleToggleTwoPage,
                ),
                _PillDivider(isDark: isDark),
                _PageNavPill(
                  currentPage: _currentPage,
                  pageCount: _pageCount,
                  isTwoPage: controller.isTwoPage,
                  isDark: isDark,
                  strings: controller.strings,
                  onPrev: _handlePrevPage,
                  onNext: _handleNextPage,
                  onJumpToPage: (p) => _pdfCanvasKey.currentState?.goToPageNumber(p),
                ),
                _PillDivider(isDark: isDark),
              ],

              // Page Zoom Stepper & Preset Dropdown (- / % / +)
              _PillIconButton(
                icon: Icons.remove_rounded,
                tooltip: controller.strings.zoomOutTooltip(controller.shortcutService.getShortcutLabel('zoomOut')),
                iconSize: 15,
                onPressed: _handleZoomOut,
              ),
              _ZoomDropdownBadge(
                currentZoom: _currentZoom,
                autoFitMode: controller.autoFitMode,
                isDark: isDark,
                strings: controller.strings,
                onZoomSelected: (zoom) {
                  if (zoom == -1.0) {
                    _handleFitWidth();
                  } else if (zoom == -2.0) {
                    _handleFitPage();
                  } else if (zoom == -3.0) {
                    _toggleFullScreen();
                  } else {
                    _handleZoomTo(zoom);
                  }
                },
              ),
              _PillIconButton(
                icon: Icons.add_rounded,
                tooltip: controller.strings.zoomInTooltip(controller.shortcutService.getShortcutLabel('zoomIn')),
                iconSize: 15,
                onPressed: _handleZoomIn,
              ),
              _PillDivider(isDark: isDark),

              // Theme Toggle (Light / Dark)
              _PillIconButton(
                icon: controller.renderOptions.isDark
                    ? Icons.light_mode_rounded
                    : Icons.dark_mode_rounded,
                tooltip: controller.strings.toggleThemeTooltip(controller.renderOptions.isDark, controller.shortcutService.getShortcutLabel('toggleTheme')),
                onPressed: controller.toggleTheme,
              ),
              _PillDivider(isDark: isDark),

              // Export PDF
              _PillIconButton(
                icon: Icons.download_rounded,
                tooltip: '${controller.strings.exportPdf} (${controller.shortcutService.getShortcutLabel('exportPdf')})',
                onPressed: _handleExportPdf,
              ),
              _PillDivider(isDark: isDark),

              // Settings (Preferences)
              _PillIconButton(
                icon: Icons.settings_outlined,
                tooltip: controller.strings.settingsTooltip(controller.shortcutService.getShortcutLabel('preferences')),
                onPressed: () => showSettingsDialog(context, controller),
              ),
              _PillDivider(isDark: isDark),

              // Zen Mode Button (Hide Floating Toolbar)
              _PillIconButton(
                icon: Icons.close_rounded,
                tooltip: controller.strings.hideToolbarTooltip(controller.shortcutService.getShortcutLabel('toggleToolbar')),
                onPressed: () => setState(() => _isToolbarVisible = false),
              ),
            ],
          ),
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
        child: Container(
          decoration: isSelected
              ? BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: iconSize, color: color),
        ),
      ),
    );
  }
}

class _FormatSelectorPill extends StatelessWidget {
  final String format;
  final ValueChanged<String> onSelectFormat;
  final VoidCallback onToggle;
  final bool isDark;
  final String? shortcutLabel;
  final AppStrings strings;

  const _FormatSelectorPill({
    required this.format,
    required this.onSelectFormat,
    required this.onToggle,
    required this.isDark,
    required this.strings,
    this.shortcutLabel,
  });

  IconData _getFormatIcon(String fmt) {
    switch (fmt) {
      case PageFormat.fluid:
        return Icons.view_stream_rounded;
      case PageFormat.a4Portrait:
        return Icons.description_outlined;
      case PageFormat.a4Landscape:
        return Icons.landscape_outlined;
      case PageFormat.slide16x9:
        return Icons.slideshow_rounded;
      case PageFormat.slide4x3:
        return Icons.tv_rounded;
      default:
        return Icons.auto_stories_rounded;
    }
  }

  String _getFormatShortLabel(String fmt) {
    return strings.layoutModeShortName(fmt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shortcut = shortcutLabel ?? 'Cmd+M';

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: '${PageFormat.getDisplayName(format, strings)} ($shortcut)',
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getFormatIcon(format),
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getFormatShortLabel(format),
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
          ),
          PopupMenuButton<String>(
            tooltip: strings.layoutSelectTooltip,
            initialValue: format,
            offset: const Offset(0, -230),
            onSelected: onSelectFormat,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              Icons.arrow_drop_up_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: PageFormat.fluid,
                child: Row(
                  children: [
                    const Icon(Icons.view_stream_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(strings.layoutModeFluid),
                  ],
                ),
              ),
              PopupMenuItem(
                value: PageFormat.a4Portrait,
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(strings.layoutModeA4Portrait),
                  ],
                ),
              ),
              PopupMenuItem(
                value: PageFormat.a4Landscape,
                child: Row(
                  children: [
                    const Icon(Icons.landscape_outlined, size: 16),
                    const SizedBox(width: 8),
                    Text(strings.layoutModeA4Landscape),
                  ],
                ),
              ),
              PopupMenuItem(
                value: PageFormat.slide16x9,
                child: Row(
                  children: [
                    const Icon(Icons.slideshow_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(strings.layoutModeSlide169),
                  ],
                ),
              ),
              PopupMenuItem(
                value: PageFormat.slide4x3,
                child: Row(
                  children: [
                    const Icon(Icons.tv_rounded, size: 16),
                    const SizedBox(width: 8),
                    Text(strings.layoutModeSlide43),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 2),
        ],
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

class _ZoomDropdownBadge extends StatelessWidget {
  final double currentZoom;
  final AutoFitMode autoFitMode;
  final bool isDark;
  final ValueChanged<double> onZoomSelected;
  final AppStrings strings;

  const _ZoomDropdownBadge({
    required this.currentZoom,
    required this.autoFitMode,
    required this.isDark,
    required this.strings,
    required this.onZoomSelected,
  });

  @override
  Widget build(BuildContext context) {
    final percentText = '${(currentZoom * 100).round()}%';
    final textColor = isDark ? Colors.white : Colors.black87;
    final theme = Theme.of(context);

    return PopupMenuButton<double>(
      tooltip: strings.zoomPresetsTooltip,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: isDark ? const Color(0xFF262626) : Colors.white,
      onSelected: onZoomSelected,
      itemBuilder: (context) => [
        PopupMenuItem<double>(
          value: -1.0,
          child: Row(
            children: [
              Icon(
                Icons.fit_screen_outlined,
                size: 16,
                color: autoFitMode == AutoFitMode.fitWidth ? theme.colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Text(
                strings.fitWindowWidth,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: autoFitMode == AutoFitMode.fitWidth ? FontWeight.w600 : FontWeight.normal,
                  color: autoFitMode == AutoFitMode.fitWidth ? theme.colorScheme.primary : null,
                ),
              ),
              const Spacer(),
              if (autoFitMode == AutoFitMode.fitWidth)
                Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.primary)
              else
                const Text('Cmd+9', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        PopupMenuItem<double>(
          value: -2.0,
          child: Row(
            children: [
              Icon(
                Icons.crop_free_rounded,
                size: 16,
                color: autoFitMode == AutoFitMode.fitPage ? theme.colorScheme.primary : null,
              ),
              const SizedBox(width: 8),
              Text(
                strings.fitPageWhole,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: autoFitMode == AutoFitMode.fitPage ? FontWeight.w600 : FontWeight.normal,
                  color: autoFitMode == AutoFitMode.fitPage ? theme.colorScheme.primary : null,
                ),
              ),
              const Spacer(),
              if (autoFitMode == AutoFitMode.fitPage)
                Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.primary)
              else
                const Text('Cmd+1', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        PopupMenuItem<double>(
          value: -3.0,
          child: Row(
            children: [
              const Icon(Icons.fullscreen_rounded, size: 16),
              const SizedBox(width: 8),
              Text(strings.fullScreenImmersive, style: const TextStyle(fontSize: 12.5)),
              const Spacer(),
              const Text('Cmd+Ctrl+F', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        _buildZoomItem(0.50, '50%'),
        _buildZoomItem(0.75, '75%'),
        _buildZoomItem(1.00, strings.originalSize, shortcut: 'Cmd+0'),
        _buildZoomItem(1.25, '125%'),
        _buildZoomItem(1.50, '150%'),
        _buildZoomItem(2.00, '200%'),
        _buildZoomItem(3.00, '300%'),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? const Color(0x28FFFFFF) : const Color(0x14000000),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              percentText,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 1),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 14,
              color: textColor.withValues(alpha: 0.6),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<double> _buildZoomItem(double val, String label, {String? shortcut}) {
    final isCurrent = (currentZoom - val).abs() < 0.02;
    return PopupMenuItem<double>(
      value: val,
      child: Row(
        children: [
          Icon(
            isCurrent ? Icons.check_rounded : Icons.radio_button_unchecked,
            size: 14,
            color: isCurrent ? const Color(0xFF22C55E) : Colors.transparent,
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12.5)),
          if (shortcut != null) ...[
            const Spacer(),
            Text(shortcut, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ],
      ),
    );
  }
}



class _PageNavPill extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final bool isTwoPage;
  final bool isDark;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int> onJumpToPage;
  final AppStrings strings;

  const _PageNavPill({
    required this.currentPage,
    required this.pageCount,
    required this.isTwoPage,
    required this.isDark,
    required this.strings,
    required this.onPrev,
    required this.onNext,
    required this.onJumpToPage,
  });

  String _formatPageLabel() {
    if (isTwoPage && pageCount > 1) {
      final spreadStart = ((currentPage - 1) ~/ 2) * 2 + 1;
      final spreadEnd = math.min(spreadStart + 1, pageCount);
      if (spreadStart == spreadEnd) {
        return '$spreadStart / $pageCount';
      }
      return '$spreadStart-$spreadEnd / $pageCount';
    }
    return '$currentPage / $pageCount';
  }

  void _showJumpDialog(BuildContext context) {
    final textController = TextEditingController(text: '$currentPage');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.jumpToPageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.jumpToPageHint(1, pageCount), style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: '1 - $pageCount',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onSubmitted: (value) {
                final page = int.tryParse(value);
                if (page != null && page >= 1 && page <= pageCount) {
                  Navigator.of(ctx).pop();
                  onJumpToPage(page);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              final page = int.tryParse(textController.text);
              if (page != null && page >= 1 && page <= pageCount) {
                Navigator.of(ctx).pop();
                onJumpToPage(page);
              }
            },
            child: Text(strings.jumpButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPrev = currentPage > 1;
    final canNext = isTwoPage
        ? (((currentPage - 1) ~/ 2 + 1) * 2 + 1 <= pageCount)
        : currentPage < pageCount;

    final navColor = isDark ? Colors.white : Colors.black;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: strings.pageNavPrev,
          waitDuration: const Duration(milliseconds: 500),
          child: InkWell(
            onTap: canPrev ? onPrev : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: canPrev
                    ? navColor.withValues(alpha: 0.85)
                    : navColor.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
        Tooltip(
          message: strings.pageNavTooltip,
          waitDuration: const Duration(milliseconds: 500),
          child: InkWell(
            onTap: () => _showJumpDialog(context),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0x20FFFFFF) : const Color(0x10000000),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatPageLabel(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                ),
              ),
            ),
          ),
        ),
        Tooltip(
          message: strings.pageNavNext,
          waitDuration: const Duration(milliseconds: 500),
          child: InkWell(
            onTap: canNext ? onNext : null,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: canNext
                    ? navColor.withValues(alpha: 0.85)
                    : navColor.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

