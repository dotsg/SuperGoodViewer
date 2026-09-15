import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import '../controllers/reader_controller.dart';

/// Full-screen, single-page presentation mode designed for projecting Markdown/Marp slides and PDFs.
class PresentationView extends StatefulWidget {
  final ReaderController controller;
  final VoidCallback onExit;

  const PresentationView({
    super.key,
    required this.controller,
    required this.onExit,
  });

  @override
  State<PresentationView> createState() => PresentationViewState();
}

class PresentationViewState extends State<PresentationView> {
  PdfDocument? _document;
  int _currentPage = 1;
  int _pageCount = 1;
  bool _isLoading = true;
  String? _loadError;

  // Cursor & HUD auto-hide
  bool _isHudVisible = true;
  bool _isCursorVisible = true;
  Timer? _idleTimer;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentPage = widget.controller.lastPageNumber.clamp(1, 999999);
    _loadDocument();
    _resetIdleTimer();
  }

  @override
  void didUpdateWidget(covariant PresentationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.currentPdfBytes != oldWidget.controller.currentPdfBytes ||
        widget.controller.isCompiling != oldWidget.controller.isCompiling) {
      _loadDocument();
    }
  }

  Future<void> _loadDocument() async {
    final bytes = widget.controller.currentPdfBytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _isLoading = false;
        _loadError = '未找到可供放映的文档内容';
      });
      return;
    }

    try {
      await pdfrxFlutterInitialize();
      final source = widget.controller.currentFilePath ?? 'presentation_${bytes.length}';
      final doc = await PdfDocument.openData(bytes, sourceName: source);
      if (mounted) {
        setState(() {
          _document = doc;
          _pageCount = doc.pages.length;
          _currentPage = _currentPage.clamp(1, _pageCount);
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = '加载放映文档失败: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _focusNode.dispose();
    _document?.dispose();
    super.dispose();
  }

  void nextPage() => _nextPage();
  void prevPage() => _prevPage();
  void goToPage(int p) => _goToPage(p);
  void goToLastPage() => _goToPage(_pageCount);

  void _resetIdleTimer() {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    if (!_isHudVisible || !_isCursorVisible) {
      setState(() {
        _isHudVisible = true;
        _isCursorVisible = true;
      });
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        setState(() {
          _isHudVisible = false;
          _isCursorVisible = false;
        });
      }
    });
  }

  void _nextPage() {
    _resetIdleTimer();
    if (_currentPage < _pageCount) {
      setState(() => _currentPage++);
      _notifyControllerPage();
    }
  }

  void _prevPage() {
    _resetIdleTimer();
    if (_currentPage > 1) {
      setState(() => _currentPage--);
      _notifyControllerPage();
    }
  }

  void _goToPage(int page) {
    _resetIdleTimer();
    final clamped = page.clamp(1, _pageCount);
    if (clamped != _currentPage) {
      setState(() => _currentPage = clamped);
      _notifyControllerPage();
    }
  }

  void _notifyControllerPage() {
    widget.controller.updatePageNumber(_currentPage);
    widget.controller.updateScrollRatio(
      (_currentPage - 1) / (_pageCount > 1 ? _pageCount - 1 : 1),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    // Esc or F5 to exit
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.f5) {
      widget.onExit();
      return KeyEventResult.handled;
    }

    // Next page keys
    if (key == LogicalKeyboardKey.space && !HardwareKeyboard.instance.isShiftPressed ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.keyN) {
      _nextPage();
      return KeyEventResult.handled;
    }

    // Prev page keys
    if ((key == LogicalKeyboardKey.space && HardwareKeyboard.instance.isShiftPressed) ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.keyP) {
      _prevPage();
      return KeyEventResult.handled;
    }

    // Home / End
    if (key == LogicalKeyboardKey.home) {
      _goToPage(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _goToPage(_pageCount);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _handleScreenTap(TapUpDetails details, Size size) {
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    // Clicking on left 20% advances backwards; right 80% advances forwards
    if (details.localPosition.dx < size.width * 0.20) {
      _prevPage();
    } else {
      _nextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.controller.renderOptions.isDark;
    final backgroundColor = isDark ? const Color(0xFF141414) : const Color(0xFFEBEBEB);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: _isCursorVisible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onHover: (_) => _resetIdleTimer(),
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest;
              return Stack(
                children: [
                  // 1. Interactive Single Slide Canvas
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => _handleScreenTap(details, size),
                      child: _buildSlideContent(isDark),
                    ),
                  ),

                  // 2. Presenter Floating Mini-HUD (Bottom Center)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _isHudVisible ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_isHudVisible,
                          child: _buildPresenterHud(isDark),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSlideContent(bool isDark) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final indicatorColor = isDark ? Colors.white70 : Colors.black54;

    if (_isLoading || widget.controller.isCompiling) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: indicatorColor),
            const SizedBox(height: 16),
            Text(widget.controller.strings.compiling, style: TextStyle(color: textColor, fontSize: 14)),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Text(
          _loadError!,
          style: TextStyle(color: textColor, fontSize: 16),
        ),
      );
    }
    if (_document == null || _pageCount == 0) {
      return Center(
        child: Text(
          widget.controller.strings.noMatches,
          style: TextStyle(color: textColor, fontSize: 16),
        ),
      );
    }

    return Center(
      child: PdfPageView(
        key: ValueKey('slide_page_$_currentPage'),
        document: _document,
        pageNumber: _currentPage,
        alignment: Alignment.center,
        maximumDpi: 300,
        decoration: const BoxDecoration(color: Colors.transparent),
      ),
    );
  }

  Widget _buildPresenterHud(bool isDark) {
    final hudBg = isDark ? const Color(0xCC1E1E1E) : const Color(0xE8FFFFFF);
    final hudBorder = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.12);
    final iconColor = isDark ? Colors.white70 : Colors.black54;
    final textColor = isDark ? Colors.white : Colors.black87;
    final dividerColor = isDark ? Colors.white24 : Colors.black12;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: hudBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: hudBorder),
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
              // Prev
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new, size: 15, color: iconColor),
                tooltip: widget.controller.strings.presentationPrev,
                splashRadius: 18,
                onPressed: _currentPage > 1 ? _prevPage : null,
              ),

              // Page counter
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$_currentPage / $_pageCount',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Next
              IconButton(
                icon: Icon(Icons.arrow_forward_ios, size: 15, color: iconColor),
                tooltip: widget.controller.strings.presentationNext,
                splashRadius: 18,
                onPressed: _currentPage < _pageCount ? _nextPage : null,
              ),

              const SizedBox(width: 8),
              Container(width: 1, height: 16, color: dividerColor),
              const SizedBox(width: 4),

              // Exit presentation
              IconButton(
                icon: Icon(Icons.close, size: 17, color: iconColor),
                tooltip: widget.controller.strings.exitPresentation,
                splashRadius: 18,
                onPressed: widget.onExit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
