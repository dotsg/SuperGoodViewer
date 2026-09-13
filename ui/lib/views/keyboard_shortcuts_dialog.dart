import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../controllers/reader_controller.dart';
import '../services/shortcut_service.dart';

/// Opens the customizable keyboard shortcuts configuration dialog.
void showKeyboardShortcutsDialog(BuildContext context, ReaderController controller) {
  showDialog(
    context: context,
    builder: (ctx) => KeyboardShortcutsDialog(controller: controller),
  );
}

class KeyboardShortcutsDialog extends StatefulWidget {
  final ReaderController controller;

  const KeyboardShortcutsDialog({super.key, required this.controller});

  @override
  State<KeyboardShortcutsDialog> createState() => _KeyboardShortcutsDialogState();
}

class _KeyboardShortcutsDialogState extends State<KeyboardShortcutsDialog> {
  String? _listeningActionId;
  String? _conflictMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shortcutService = widget.controller.shortcutService;

    // Group actions by category
    final categories = <String, List<AppShortcutAction>>{};
    for (final action in ShortcutService.allActions) {
      categories.putIfAbsent(action.category, () => []).add(action);
    }

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 680),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.keyboard_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '快捷键自定义设置',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击按键标签后直接按下键盘按键即可完成重置绑定，修改即刻生效',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF999999) : const Color(0xFF666666),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5)),

            // Conflict banner if any
            if (_conflictMessage != null)
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _conflictMessage!,
                        style: const TextStyle(fontSize: 12, color: Colors.amber),
                      ),
                    ),
                  ],
                ),
              ),

            // Scrollable Action List
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final category in categories.keys) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 6),
                      child: Text(
                        category,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    for (final action in categories[category]!)
                      _buildActionRow(action, shortcutService, isDark, theme),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 12),
            Divider(color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5)),
            const SizedBox(height: 8),

            // Bottom Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      shortcutService.resetAll();
                      _listeningActionId = null;
                      _conflictMessage = null;
                    });
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 16),
                  label: const Text('恢复全部默认', style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: const Text('完成', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(
    AppShortcutAction action,
    ShortcutService shortcutService,
    bool isDark,
    ThemeData theme,
  ) {
    final isListening = _listeningActionId == action.id;
    final isCustomized = shortcutService.isCustomized(action.id);
    final shortcutLabel = shortcutService.getShortcutLabel(action.id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isListening
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isListening
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF333333) : const Color(0xFFECECEC)),
          width: isListening ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      action.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCustomized) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '已修改',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  action.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF888888) : const Color(0xFF777777),
                  ),
                ),
              ],
            ),
          ),

          // Shortcut Key Badge / Key Listener
          Focus(
            autofocus: isListening,
            onKeyEvent: (node, event) {
              if (!isListening) return KeyEventResult.ignored;
              if (event is KeyDownEvent) {
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.escape) {
                  setState(() => _listeningActionId = null);
                  return KeyEventResult.handled;
                }
                if (ShortcutService.isModifierKey(key)) {
                  return KeyEventResult.handled;
                }
                if (ShortcutService.isSupportedKey(key)) {
                  final conflict = shortcutService.findConflict(action.id, key);
                  shortcutService.setKey(action.id, key);
                  setState(() {
                    _listeningActionId = null;
                    if (conflict != null) {
                      _conflictMessage = '快捷键已绑定为 $key，与「$conflict」存在相同主键，请留意避免冲突';
                    } else {
                      _conflictMessage = null;
                    }
                  });
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _listeningActionId = isListening ? null : action.id;
                  _conflictMessage = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isListening
                      ? theme.colorScheme.primary
                      : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isListening
                        ? theme.colorScheme.primary
                        : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isListening ? Icons.hearing_rounded : Icons.keyboard_outlined,
                      size: 13,
                      color: isListening
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isListening ? '请直接按下新按键...' : shortcutLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: isListening
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Reset button if customized
          if (isCustomized) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.undo_rounded, size: 16),
              tooltip: '恢复此项默认',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                setState(() {
                  shortcutService.resetKey(action.id);
                  if (_listeningActionId == action.id) {
                    _listeningActionId = null;
                  }
                  _conflictMessage = null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }
}
