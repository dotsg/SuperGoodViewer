import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Representation of a configurable shortcut action.
class AppShortcutAction {
  final String id;
  final String name;
  final String category;
  final String description;
  final LogicalKeyboardKey defaultKey;
  final bool hasShift;
  final bool hasMetaOrControl;

  const AppShortcutAction({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.defaultKey,
    this.hasShift = false,
    this.hasMetaOrControl = true,
  });
}

/// Service managing customizable application keyboard shortcuts.
class ShortcutService extends ChangeNotifier {
  static const List<AppShortcutAction> allActions = [
    // 视图模式与显示
    AppShortcutAction(
      id: 'toggleMode',
      name: '切换 A4 / 流式视图',
      category: '视图模式',
      description: '在自适应屏幕长卷轴与标准 A4 出版预览之间切换',
      defaultKey: LogicalKeyboardKey.keyF, // 主键默认为 F (Cmd+F / Ctrl+F)
    ),
    AppShortcutAction(
      id: 'toggleTheme',
      name: '切换明亮 / 暗黑模式',
      category: '视图模式',
      description: '在日间明亮和夜间暗黑阅读主题之间无缝切换',
      defaultKey: LogicalKeyboardKey.keyT,
    ),
    AppShortcutAction(
      id: 'toggleTwoPage',
      name: '切换单页 / 双页对开',
      category: '视图模式',
      description: '在 A4 出版模式下切换单页纵向与双页对开书籍排版',
      defaultKey: LogicalKeyboardKey.keyD,
    ),
    AppShortcutAction(
      id: 'toggleToolbar',
      name: '显示 / 隐藏底部浮动栏',
      category: '视图模式',
      description: '切换底部浮动工具栏显示状态，进入极致沉浸 Zen 模式',
      defaultKey: LogicalKeyboardKey.backslash,
    ),

    // 文档与文件操作
    AppShortcutAction(
      id: 'exportPdf',
      name: '导出为出版级 PDF',
      category: '文档文件',
      description: '导出当前文档为出版级无损明亮模式矢量 PDF',
      defaultKey: LogicalKeyboardKey.keyP, // 主键默认为 P (Cmd+P / Ctrl+P)
    ),
    AppShortcutAction(
      id: 'openFile',
      name: '打开本地文档',
      category: '文档文件',
      description: '通过系统文件选择器打开并阅读本地 Markdown 或 PDF 文件',
      defaultKey: LogicalKeyboardKey.keyO,
    ),
    AppShortcutAction(
      id: 'toggleSidebar',
      name: '展开 / 收起侧边栏',
      category: '文档文件',
      description: '显示或收起文档多级大纲目录及最近打开历史',
      defaultKey: LogicalKeyboardKey.keyB,
    ),
    AppShortcutAction(
      id: 'compileDocument',
      name: '刷新 / 重新编译',
      category: '文档文件',
      description: '立即重新编译并热刷新当前文档排版视图',
      defaultKey: LogicalKeyboardKey.keyR,
    ),

    // 缩放与自适应
    AppShortcutAction(
      id: 'zoomIn',
      name: '放大页面视口',
      category: '缩放自适应',
      description: '递增页面渲染视口缩放比例',
      defaultKey: LogicalKeyboardKey.equal,
    ),
    AppShortcutAction(
      id: 'zoomOut',
      name: '缩小页面视口',
      category: '缩放自适应',
      description: '递减页面渲染视口缩放比例',
      defaultKey: LogicalKeyboardKey.minus,
    ),
    AppShortcutAction(
      id: 'resetZoom',
      name: '重置缩放到 100%',
      category: '缩放自适应',
      description: '将页面缩放快速恢复为 100% 原始比例',
      defaultKey: LogicalKeyboardKey.digit0,
    ),
    AppShortcutAction(
      id: 'fitWidth',
      name: '自适应窗口宽度',
      category: '缩放自适应',
      description: '根据当前窗口自适应页面宽度',
      defaultKey: LogicalKeyboardKey.digit9,
    ),
    AppShortcutAction(
      id: 'fitPage',
      name: '自适应整页全貌',
      category: '缩放自适应',
      description: '自适应整页视口使页面完整呈现',
      defaultKey: LogicalKeyboardKey.digit1,
    ),

    // 排版与设置
    AppShortcutAction(
      id: 'preferences',
      name: '偏好设置',
      category: '排版与设置',
      description: '打开全局统一偏好设置面板（常规、字体、快捷键、CLI）',
      defaultKey: LogicalKeyboardKey.comma,
    ),
    AppShortcutAction(
      id: 'fontSettings',
      name: '排版与字体设置',
      category: '排版与设置',
      description: '打开 CJK 字体排版与 1:2 等宽对齐设置面板',
      defaultKey: LogicalKeyboardKey.keyF,
      hasShift: true,
    ),
    AppShortcutAction(
      id: 'keyboardShortcuts',
      name: '自定义快捷键面板',
      category: '排版与设置',
      description: '打开快捷键设置面板，可随心修改按键',
      defaultKey: LogicalKeyboardKey.comma,
    ),
  ];

  static final Map<String, AppShortcutAction> actionMap = {
    for (final a in allActions) a.id: a,
  };

  static final Map<String, LogicalKeyboardKey> _nameToKey = {
    'A': LogicalKeyboardKey.keyA,
    'B': LogicalKeyboardKey.keyB,
    'C': LogicalKeyboardKey.keyC,
    'D': LogicalKeyboardKey.keyD,
    'E': LogicalKeyboardKey.keyE,
    'F': LogicalKeyboardKey.keyF,
    'G': LogicalKeyboardKey.keyG,
    'H': LogicalKeyboardKey.keyH,
    'I': LogicalKeyboardKey.keyI,
    'J': LogicalKeyboardKey.keyJ,
    'K': LogicalKeyboardKey.keyK,
    'L': LogicalKeyboardKey.keyL,
    'M': LogicalKeyboardKey.keyM,
    'N': LogicalKeyboardKey.keyN,
    'O': LogicalKeyboardKey.keyO,
    'P': LogicalKeyboardKey.keyP,
    'Q': LogicalKeyboardKey.keyQ,
    'R': LogicalKeyboardKey.keyR,
    'S': LogicalKeyboardKey.keyS,
    'T': LogicalKeyboardKey.keyT,
    'U': LogicalKeyboardKey.keyU,
    'V': LogicalKeyboardKey.keyV,
    'W': LogicalKeyboardKey.keyW,
    'X': LogicalKeyboardKey.keyX,
    'Y': LogicalKeyboardKey.keyY,
    'Z': LogicalKeyboardKey.keyZ,
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
    '=': LogicalKeyboardKey.equal,
    '-': LogicalKeyboardKey.minus,
    '\\': LogicalKeyboardKey.backslash,
    ',': LogicalKeyboardKey.comma,
    '.': LogicalKeyboardKey.period,
    '/': LogicalKeyboardKey.slash,
    ';': LogicalKeyboardKey.semicolon,
    '[': LogicalKeyboardKey.bracketLeft,
    ']': LogicalKeyboardKey.bracketRight,
  };

  static final Map<LogicalKeyboardKey, String> _keyToName = {
    for (final entry in _nameToKey.entries) entry.value: entry.key,
  };

  final Map<String, LogicalKeyboardKey> _customKeys = {};

  ShortcutService();

  /// Retrieve the active primary key for a given action.
  LogicalKeyboardKey getKey(String actionId) {
    if (_customKeys.containsKey(actionId)) {
      return _customKeys[actionId]!;
    }
    final action = actionMap[actionId];
    return action?.defaultKey ?? LogicalKeyboardKey.keyF;
  }

  /// Whether the action currently uses a customized key.
  bool isCustomized(String actionId) {
    return _customKeys.containsKey(actionId);
  }

  /// Update the primary key for an action.
  void setKey(String actionId, LogicalKeyboardKey key) {
    final action = actionMap[actionId];
    if (action == null) return;

    if (action.defaultKey == key) {
      _customKeys.remove(actionId);
    } else {
      _customKeys[actionId] = key;
    }
    notifyListeners();
  }

  /// Reset an action to its default shortcut key.
  void resetKey(String actionId) {
    if (_customKeys.remove(actionId) != null) {
      notifyListeners();
    }
  }

  /// Reset all shortcuts to system defaults.
  void resetAll() {
    if (_customKeys.isNotEmpty) {
      _customKeys.clear();
      notifyListeners();
    }
  }

  /// Check if the key conflicts with another action with matching modifier signatures.
  String? findConflict(String actionId, LogicalKeyboardKey candidateKey) {
    final targetAction = actionMap[actionId];
    if (targetAction == null) return null;

    for (final action in allActions) {
      if (action.id == actionId) continue;
      if (action.hasShift == targetAction.hasShift &&
          action.hasMetaOrControl == targetAction.hasMetaOrControl) {
        final currentKeyForOther = getKey(action.id);
        if (currentKeyForOther == candidateKey) {
          return action.name;
        }
      }
    }
    return null;
  }

  /// Human-friendly display string for key name (e.g. 'F', '=', 'P').
  static String getKeyDisplayName(LogicalKeyboardKey key) {
    return _keyToName[key] ?? key.keyLabel;
  }

  /// Formatted shortcut label for tooltips and menus, e.g. 'Cmd+F' or 'Ctrl+F'.
  String getShortcutLabel(String actionId) {
    final action = actionMap[actionId];
    if (action == null) return '';

    final key = getKey(actionId);
    final keyName = getKeyDisplayName(key);
    final isMac = !kIsWeb && Platform.isMacOS;

    final buffer = StringBuffer();
    if (action.hasMetaOrControl) {
      buffer.write(isMac ? 'Cmd+' : 'Ctrl+');
    }
    if (action.hasShift) {
      buffer.write('Shift+');
    }
    buffer.write(keyName);
    return buffer.toString();
  }

  /// Check if key is a modifier key (Shift, Ctrl, Alt, Meta).
  static bool isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  /// Check if a key is supported for shortcut binding.
  static bool isSupportedKey(LogicalKeyboardKey key) {
    return _keyToName.containsKey(key);
  }

  /// Export configured shortcuts to Map for persistence.
  Map<String, String> toMap() {
    final map = <String, String>{};
    for (final entry in _customKeys.entries) {
      final name = _keyToName[entry.value];
      if (name != null) {
        map[entry.key] = name;
      }
    }
    return map;
  }

  /// Load customized shortcuts from persisted Map.
  void loadFromMap(Map<String, dynamic> map, {bool notify = true}) {
    _customKeys.clear();
    for (final entry in map.entries) {
      final keyStr = entry.value?.toString().toUpperCase();
      if (keyStr != null && _nameToKey.containsKey(keyStr)) {
        final action = actionMap[entry.key];
        if (action != null) {
          final key = _nameToKey[keyStr]!;
          if (key != action.defaultKey) {
            _customKeys[entry.key] = key;
          }
        }
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  /// Build CallbackShortcuts bindings map based on active configuration.
  Map<ShortcutActivator, VoidCallback> buildBindings({
    required VoidCallback onToggleMode,
    required VoidCallback onExportPdf,
    required VoidCallback onOpenFile,
    required VoidCallback onToggleSidebar,
    required VoidCallback onCompileDocument,
    required VoidCallback onToggleTheme,
    required VoidCallback onToggleTwoPage,
    required VoidCallback onZoomIn,
    required VoidCallback onZoomOut,
    required VoidCallback onResetZoom,
    required VoidCallback onFitWidth,
    required VoidCallback onFitPage,
    required VoidCallback onToggleToolbar,
    required VoidCallback onFontSettings,
    VoidCallback? onPreferences,
    VoidCallback? onKeyboardShortcuts,
  }) {
    final Map<ShortcutActivator, VoidCallback> map = {};

    void addAction(String actionId, VoidCallback? callback) {
      if (callback == null) return;
      final action = actionMap[actionId];
      if (action == null) return;
      final key = getKey(actionId);

      if (action.hasMetaOrControl) {
        // Register Cmd (macOS)
        map[SingleActivator(key, meta: true, shift: action.hasShift)] = callback;
        // Register Ctrl (Windows / Linux)
        map[SingleActivator(key, control: true, shift: action.hasShift)] = callback;
      }
    }

    addAction('toggleMode', onToggleMode);
    addAction('exportPdf', onExportPdf);
    addAction('openFile', onOpenFile);
    addAction('toggleSidebar', onToggleSidebar);
    addAction('compileDocument', onCompileDocument);
    addAction('toggleTheme', onToggleTheme);
    addAction('toggleTwoPage', onToggleTwoPage);
    addAction('zoomIn', onZoomIn);
    addAction('zoomOut', onZoomOut);
    addAction('resetZoom', onResetZoom);
    addAction('fitWidth', onFitWidth);
    addAction('fitPage', onFitPage);
    addAction('toggleToolbar', onToggleToolbar);
    addAction('fontSettings', onFontSettings);
    addAction('preferences', onPreferences ?? onKeyboardShortcuts);
    addAction('keyboardShortcuts', onKeyboardShortcuts ?? onPreferences);

    return map;
  }
}
