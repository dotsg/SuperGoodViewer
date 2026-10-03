import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../controllers/reader_controller.dart';

/// Browser-style tabs for the open documents, shown in the title bar once
/// more than one document is open.
class DocumentTabStrip extends StatelessWidget {
  final ReaderController controller;
  final bool isDark;

  /// Width available to the tabs; they shrink towards [minTabWidth] and
  /// scroll horizontally beyond that.
  final double maxWidth;

  static const double maxTabWidth = 200;
  static const double minTabWidth = 96;

  const DocumentTabStrip({
    super.key,
    required this.controller,
    required this.isDark,
    required this.maxWidth,
  });

  /// Tab labels: the document title, plus as many parent folder names as it
  /// takes to tell apart documents that share a title (two README.md files
  /// show as "README · project-one" and "README · project-two").
  static List<String> labelsFor(List<DocumentSession> sessions) {
    final labels = [for (final s in sessions) s.title];
    for (var depth = 1; depth <= 3; depth++) {
      final counts = <String, int>{};
      for (final label in labels) {
        counts[label] = (counts[label] ?? 0) + 1;
      }
      if (counts.values.every((c) => c == 1)) break;
      for (var i = 0; i < sessions.length; i++) {
        final path = sessions[i].filePath;
        if (path == null || counts[labels[i]] == 1) continue;
        final folders = p.split(p.dirname(path));
        final suffix = folders.sublist((folders.length - depth).clamp(0, folders.length)).join('/');
        labels[i] = '${sessions[i].title} · $suffix';
      }
    }
    return labels;
  }

  static double widthFor(int tabCount, double available) {
    if (tabCount == 0) return 0;
    return (available / tabCount).clamp(minTabWidth, maxTabWidth);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = controller.sessions;
    final active = controller.activeSessionIndex;
    final tabWidth = widthFor(sessions.length, maxWidth);
    final labels = labelsFor(sessions);
    final closeLabel = controller.shortcutService.getShortcutLabel('closeTab');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < sessions.length; i++)
            _DocumentTab(
              key: ValueKey(sessions[i].id),
              session: sessions[i],
              label: labels[i],
              width: tabWidth,
              isActive: i == active,
              isDark: isDark,
              closeTooltip: controller.strings.closeTabTooltip(closeLabel),
              onSelect: () => controller.activateSession(i),
              onClose: () => controller.closeSession(i),
            ),
        ],
      ),
    );
  }
}

class _DocumentTab extends StatefulWidget {
  final DocumentSession session;
  final String label;
  final double width;
  final bool isActive;
  final bool isDark;
  final String closeTooltip;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  const _DocumentTab({
    super.key,
    required this.session,
    required this.label,
    required this.width,
    required this.isActive,
    required this.isDark,
    required this.closeTooltip,
    required this.onSelect,
    required this.onClose,
  });

  @override
  State<_DocumentTab> createState() => _DocumentTabState();
}

class _DocumentTabState extends State<_DocumentTab> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = widget.isDark;
    final session = widget.session;
    final isActive = widget.isActive;
    final textColor = isActive
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? const Color(0xFF9A9A9A) : const Color(0xFF666666));
    final isPdf = session.isRawPdf || (session.filePath?.toLowerCase().endsWith('.pdf') ?? false);

    final Widget leading;
    if (session.isCompiling) {
      leading = const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5));
    } else {
      leading = Icon(
        session.errorMessage != null
            ? Icons.error_outline_rounded
            : (isPdf ? Icons.picture_as_pdf_outlined : Icons.description_outlined),
        size: 13,
        color: session.errorMessage != null ? theme.colorScheme.error : textColor,
      );
    }

    return Listener(
      // Middle click closes, as in browsers.
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse && event.buttons == kMiddleMouseButton) {
          widget.onClose();
        }
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: Tooltip(
          message: session.filePath ?? session.title,
          waitDuration: const Duration(milliseconds: 700),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
            child: Material(
              color: isActive
                  ? (isDark ? const Color(0xFF2C2C2C) : Colors.white)
                  : (_isHovering
                      ? (isDark ? const Color(0x14FFFFFF) : const Color(0x0F000000))
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.onSelect,
                child: SizedBox(
                  width: widget.width - 4,
                  height: 26,
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      leading,
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                            color: textColor,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      // Hidden on inactive tabs unless hovered; ignore clicks
                      // while invisible so a stray click cannot close the tab.
                      IgnorePointer(
                        ignoring: !(isActive || _isHovering),
                        child: Opacity(
                          opacity: isActive || _isHovering ? 1 : 0,
                          child: Tooltip(
                            message: widget.closeTooltip,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: widget.onClose,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(Icons.close_rounded, size: 13, color: textColor),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
