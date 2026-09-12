import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import '../bridge/native_engine.dart';
import '../models/render_options.dart';
import '../services/preferences_service.dart';

class OutlineItem {
  final String title;
  final int level;
  final String anchor;
  final int lineNumber;

  const OutlineItem({
    required this.title,
    required this.level,
    required this.anchor,
    required this.lineNumber,
  });

  @override
  String toString() => 'OutlineItem(H$level: $title, line: $lineNumber)';
}

enum AutoFitMode {
  none,
  fitWidth,
  fitPage,
}

class ReaderController extends ChangeNotifier {
  String? _currentFilePath;
  String _currentMarkdown = '';
  String _documentTitle = 'Welcome';
  Uint8List? _currentPdfBytes;
  RenderOptions _renderOptions = const RenderOptions(
    mode: 'fluid',
    theme: 'light',
    viewportWidth: 720.0,
    fontSize: 10.5,
  );
  bool _isCompiling = false;
  int _compileGeneration = 0;
  bool _hasPendingCompile = false;
  String? _errorMessage;
  double _lastScrollRatio = 0.0;
  int _lastPageNumber = 1;
  double _lastZoom = 1.0;
  AutoFitMode _autoFitMode = AutoFitMode.none;
  bool _isReloading = false;
  bool _autoReload = true;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  Timer? _persistDebounceTimer;

  final List<String> _recentFiles = [];
  Map<String, dynamic> _fontReport = {};

  bool _isTwoPage = false;
  List<OutlineItem> _outlineItems = [];
  OutlineItem? _requestedJumpItem;

  // Getters
  String? get currentFilePath => _currentFilePath;
  String get currentMarkdown => _currentMarkdown;
  String get documentTitle => _documentTitle;
  Uint8List? get currentPdfBytes => _currentPdfBytes;
  RenderOptions get renderOptions => _renderOptions;
  bool get isCompiling => _isCompiling;
  String? get errorMessage => _errorMessage;
  double get lastScrollRatio => _lastScrollRatio;
  int get lastPageNumber => _lastPageNumber;
  double get lastZoom => _lastZoom;
  AutoFitMode get autoFitMode => _autoFitMode;
  bool get isReloading => _isReloading;
  bool get autoReload => _autoReload;
  List<String> get recentFiles => List.unmodifiable(_recentFiles);
  Map<String, dynamic> get fontReport => _fontReport;
  bool get isTwoPage => _isTwoPage;
  List<OutlineItem> get outlineItems => _outlineItems;
  OutlineItem? get requestedJumpItem => _requestedJumpItem;

  void jumpToOutline(OutlineItem item) {
    _requestedJumpItem = item;
    notifyListeners();
  }

  void clearJumpRequest() {
    _requestedJumpItem = null;
  }

  void toggleTwoPage() {
    _isTwoPage = !_isTwoPage;
    _persistPreferences();
    notifyListeners();
  }

  void setTwoPage(bool value) {
    if (_isTwoPage != value) {
      _isTwoPage = value;
      _persistPreferences();
      notifyListeners();
    }
  }

  void setAutoFitMode(AutoFitMode mode) {
    if (_autoFitMode != mode) {
      _autoFitMode = mode;
      _persistDebounced();
      notifyListeners();
    }
  }

  ReaderController({String? initialFilePath, bool autoRestorePreferences = true}) {
    unawaited(refreshFontReport());
    _setSampleDocumentContent();
    if (initialFilePath != null && initialFilePath.isNotEmpty) {
      openFile(initialFilePath);
    } else if (autoRestorePreferences) {
      _initSession();
    } else {
      compileDocument();
    }
  }

  Future<void> _initSession() async {
    try {
      final prefs = await PreferencesService.load();
      final lastFile = prefs['lastOpenedFile'] as String?;
      final savedTheme = prefs['theme'] as String?;
      final savedMode = prefs['mode'] as String?;
      final savedTwoPage = prefs['isTwoPage'] as bool?;
      final savedAutoFit = prefs['autoFitMode'] as String?;
      final recent = (prefs['recentFiles'] as List<dynamic>?)?.cast<String>();

      if (recent != null && recent.isNotEmpty) {
        _recentFiles.clear();
        _recentFiles.addAll(recent);
      }

      if (savedTheme != null || savedMode != null) {
        _renderOptions = _renderOptions.copyWith(
          theme: savedTheme ?? _renderOptions.theme,
          mode: savedMode ?? _renderOptions.mode,
        );
      }
      if (savedTwoPage != null) {
        _isTwoPage = savedTwoPage;
      }
      if (savedAutoFit != null) {
        _autoFitMode = AutoFitMode.values.firstWhere(
          (m) => m.name == savedAutoFit,
          orElse: () => AutoFitMode.none,
        );
      }

      if (lastFile != null && lastFile.isNotEmpty) {
        final file = File(lastFile);
        if (await file.exists()) {
          final savedScroll = (prefs['lastScrollRatio'] as num?)?.toDouble() ?? 0.0;
          final savedPage = (prefs['lastPageNumber'] as num?)?.toInt() ?? 1;
          _lastScrollRatio = savedScroll;
          _lastPageNumber = savedPage;
          await openFile(lastFile, preservePosition: true);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error restoring last session: $e');
    }
    // Only compile sample document if no valid previous file exists
    await compileDocument();
  }

  void _persistPreferences() {
    PreferencesService.save({
      'lastOpenedFile': _currentFilePath,
      'recentFiles': List<String>.from(_recentFiles),
      'theme': _renderOptions.theme,
      'mode': _renderOptions.mode,
      'isTwoPage': _isTwoPage,
      'autoFitMode': _autoFitMode.name,
      'fontSize': _renderOptions.fontSize,
      'bodyFont': _renderOptions.bodyFont,
      'codeFont': _renderOptions.codeFont,
      'lastScrollRatio': _lastScrollRatio,
      'lastPageNumber': _lastPageNumber,
    });
  }

  void _persistDebounced() {
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _persistPreferences();
    });
  }

  void finishReloading() {
    _isReloading = false;
  }

  void updateScrollRatio(double ratio) {
    if (_isReloading) return;
    if (ratio >= 0.0 && ratio <= 1.0) {
      _lastScrollRatio = ratio;
      _persistDebounced();
    }
  }

  void updatePageNumber(int pageNumber) {
    if (_isReloading) return;
    if (pageNumber >= 1) {
      _lastPageNumber = pageNumber;
      _persistDebounced();
    }
  }

  void updateZoom(double zoom) {
    if (_isReloading) return;
    if (zoom > 0.1) {
      _lastZoom = zoom;
    }
  }

  Future<void> openFile(String filePath, {bool preservePosition = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      final msg = 'File not found: $filePath';
      if (_currentPdfBytes == null) {
        await compileDocument();
      }
      _errorMessage = msg;
      notifyListeners();
      return;
    }

    try {
      final bytes = await file.readAsBytes();
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = utf8.decode(bytes, allowMalformed: true);
      }
      _currentFilePath = filePath;
      _currentMarkdown = content;
      _extractOutline(_currentMarkdown);
      _documentTitle = p.basenameWithoutExtension(filePath);

      if (!preservePosition) {
        _lastScrollRatio = 0.0;
        _lastPageNumber = 1;
        _isReloading = false;
      } else {
        _isReloading = true;
      }

      // Add to recent files
      _recentFiles.remove(filePath);
      _recentFiles.insert(0, filePath);
      if (_recentFiles.length > 10) {
        _recentFiles.removeLast();
      }

      _persistPreferences();
      _setupFileWatcher(filePath);
      await compileDocument();
    } catch (e) {
      final msg = 'Failed to read file: $e';
      if (_currentPdfBytes == null) {
        await compileDocument();
      }
      _errorMessage = msg;
      notifyListeners();
    }
  }

  void _setupFileWatcher(String filePath) {
    _watcherSubscription?.cancel();
    if (!_autoReload) return;

    final file = File(filePath);
    final dir = file.parent;

    try {
      _watcherSubscription = dir.watch().listen((event) {
        if (p.normalize(event.path) == p.normalize(filePath)) {
          if (event.type == FileSystemEvent.modify ||
              event.type == FileSystemEvent.create) {
            // Debounced reload
            _onExternalFileModified();
          }
        }
      });
    } catch (e) {
      debugPrint('Watcher setup failed: $e');
    }
  }

  Timer? _debounceTimer;
  void _onExternalFileModified() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () async {
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        if (await file.exists()) {
          try {
            final bytes = await file.readAsBytes();
            _currentMarkdown = utf8.decode(bytes, allowMalformed: true);
            _extractOutline(_currentMarkdown);
            _isReloading = true;
            await compileDocument();
          } catch (e) {
            debugPrint('Failed to reload modified file: $e');
          }
        }
      }
    });
  }

  Future<void> compileDocument() async {
    if (_currentMarkdown.isEmpty) return;

    final int generation = ++_compileGeneration;
    if (_isCompiling) {
      _hasPendingCompile = true;
      return;
    }

    _isCompiling = true;
    _hasPendingCompile = false;
    _errorMessage = null;
    debugPrint('[ReaderController] compileDocument: starting gen $generation for "$_documentTitle" (${_currentMarkdown.length} chars)');
    notifyListeners();

    try {
      if (!NativeEngine.instance.isAvailable) {
        _errorMessage = NativeEngine.instance.initError ?? 'Native library not loaded';
        debugPrint('[ReaderController] compileDocument: $_errorMessage');
        return;
      }

      final docDir = _currentFilePath != null
          ? p.dirname(_currentFilePath!)
          : Directory.current.path;

      final pdfBytes = await NativeEngine.instance.compileMarkdownAsync(
        _currentMarkdown,
        title: _documentTitle,
        docDir: docDir,
        options: _renderOptions,
      );

      if (generation == _compileGeneration) {
        if (pdfBytes != null && pdfBytes.isNotEmpty) {
          _currentPdfBytes = pdfBytes;
          _errorMessage = null;
          debugPrint('[ReaderController] compileDocument: SUCCESS gen $generation (${pdfBytes.length} bytes)');
        } else {
          _errorMessage = NativeEngine.instance.getLastError() ?? 'Compilation failed';
          debugPrint('[ReaderController] compileDocument: FAILED gen $generation ($_errorMessage)');
        }
      }
    } catch (e, st) {
      if (generation == _compileGeneration) {
        _errorMessage = 'Compilation error: $e';
        debugPrint('[ReaderController] compileDocument: EXCEPTION gen $generation ($e)\n$st');
      }
    } finally {
      _isCompiling = false;
      if (_hasPendingCompile) {
        _hasPendingCompile = false;
        compileDocument();
      } else {
        notifyListeners();
      }
    }
  }

  void toggleMode() {
    _isReloading = true;
    final nextMode = _renderOptions.mode == 'fluid' ? 'paged' : 'fluid';
    _renderOptions = _renderOptions.copyWith(mode: nextMode);
    _persistPreferences();
    compileDocument();
  }

  void toggleTheme() {
    _isReloading = true;
    final nextTheme = _renderOptions.theme == 'light' ? 'dark' : 'light';
    _renderOptions = _renderOptions.copyWith(theme: nextTheme);
    _persistPreferences();
    compileDocument();
  }

  Timer? _viewportDebounceTimer;
  void setViewportWidth(double width) {
    if ((width - _renderOptions.viewportWidth).abs() > 40) {
      _viewportDebounceTimer?.cancel();
      _viewportDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        _renderOptions = _renderOptions.copyWith(viewportWidth: width);
        if (_renderOptions.isFluid) {
          _isReloading = true;
          compileDocument();
        }
      });
    }
  }

  void setFontSize(double size) {
    _isReloading = true;
    _renderOptions = _renderOptions.copyWith(fontSize: size.clamp(8.0, 24.0));
    _persistPreferences();
    compileDocument();
  }

  Future<void> refreshFontReport() async {
    try {
      final report = await Isolate.run(() => NativeEngine.instance.detectFonts());
      if (report.isNotEmpty) {
        _fontReport = report;
        notifyListeners();
      }
    } catch (_) {}
  }

  void setBodyFont(String? font) {
    _isReloading = true;
    _renderOptions = _renderOptions.copyWith(bodyFont: font);
    _persistPreferences();
    compileDocument();
  }

  void setCodeFont(String? font) {
    _isReloading = true;
    _renderOptions = _renderOptions.copyWith(codeFont: font);
    _persistPreferences();
    compileDocument();
  }

  void setAutoReload(bool enabled) {
    _autoReload = enabled;
    if (enabled && _currentFilePath != null) {
      _setupFileWatcher(_currentFilePath!);
    } else {
      _watcherSubscription?.cancel();
    }
    notifyListeners();
  }

  Future<bool> exportPdf(String destinationPath) async {
    if (_currentPdfBytes == null) return false;
    try {
      final file = File(destinationPath);
      await file.writeAsBytes(_currentPdfBytes!);
      return true;
    } catch (e) {
      _errorMessage = 'Export failed: $e';
      notifyListeners();
      return false;
    }
  }

  void _setSampleDocumentContent() {
    _currentFilePath = null;
    _documentTitle = 'SuperGoodViewer Demo';
    _currentMarkdown = r'''
# SuperGoodViewer 🚀
### 出版级排版 Markdown 桌面阅读器

欢迎体验 **SuperGoodViewer**！本应用通过 **Typst 嵌入式编译 + PDFium 矢量渲染**，为您提供极致的阅读美感与跨平台 100% 像素级一致性。

---

## 📐 高精度数学排版 (LaTeX 支持)

麦克斯韦方程组微分形式：

$$
\begin{cases}
\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0} \\
\nabla \cdot \mathbf{B} = 0 \\
\nabla \times \mathbf{E} = -\frac{\partial \mathbf{B}}{\partial t} \\
\nabla \times \mathbf{B} = \mu_0 \mathbf{J} + \mu_0 \varepsilon_0 \frac{\partial \mathbf{E}}{\partial t}
\end{cases}
$$

高斯积分：

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

---

## 📊 Mermaid 离线纯矢量渲染

```mermaid
graph LR
  MD[Markdown Source] --> P[Rust Pulldown-Cmark]
  P --> M[TeX & Mermaid Transpiler]
  M --> T[Typst Memory Engine]
  T --> PDF[Vector PDF Stream]
  PDF --> V[Google PDFium Viewport]
```

---

## 🔤 CJK 1:2 等宽代码与 ASCII 字符表

搭配 **Maple Mono** 字体，实现中英文全角半角严格 1:2 绝对对齐：

```
┌─────────────────────────────────────┬─────────────────────────────────────┐
│ 1. 量子纠缠分发与纯化引擎 (QED)     │ 2. 相对论时空测地线同步网关 (STG)   │
├─────────────────────────────────────┼─────────────────────────────────────┤
│ · 贝尔态多粒子纯化与量子中继存储    │ · 史瓦西引力场时间膨胀动态频率修正  │
│ · 纠缠交换路由与拓扑自动愈合        │ · 纳秒级深空原子钟激光同步信标      │
│ · 拓扑容错量子表面码校验 (Surface)  │ · 任意子非阿贝尔统计相位标定        │
│ · 兆赫兹纠缠对生成与自旋偏振锁定    │ · 零知识量子密钥分发与抗监听验证    │
└─────────────────────────────────────┴─────────────────────────────────────┘
```

---

## 🎯 核心工程特性对比

| 衡量维度 | SuperGoodViewer (纯原生) | 传统 Electron / WebView 阅读器 |
| :--- | :--- | :--- |
| **排版引擎** | **Typst 出版级矢量排版** | 浏览器 DOM / Webview 屏幕流动 |
| **内存占用** | **~ 45 MB** | **~ 350 MB - 1 GB** |
| **冷启动耗时** | **< 100 ms** | **~ 1.5 s - 3 s** |
| **跨平台一致性** | **100% 像素级吻合** | 字体、行高、渲染随系统漂移 |
| **打印/导出** | **0 毫秒即时导出无损 PDF** | 分页被截断、需二次排版转换 |

---

## 🛠 功能体验清单

- [x] 纯 Rust 进程内嵌入式编译，零外部 CLI 依赖
- [x] 连续流式长卷轴 (Fluid) 与 A4 出版打印 (Paged) 一键切换
- [x] 原生亮色 (Light) / 暗黑 (Dark) 主题支持
- [x] 外部修改秒级自动热重载，并智能保持阅读视口位置
- [x] 0 毫秒即时导出 PDF

    > [!TIP]
    > 点击顶部工具栏的 **视图切换** 按钮，可在自适应屏幕长卷轴与标准 A4 打印预览间丝滑切换。
''';

    _extractOutline(_currentMarkdown);
  }

  void loadSampleDocument() {
    _setSampleDocumentContent();
    compileDocument();
  }

  void _extractOutline(String markdown) {
    final items = <OutlineItem>[];
    final lines = markdown.split('\n');
    bool inCodeBlock = false;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        inCodeBlock = !inCodeBlock;
        continue;
      }
      if (inCodeBlock) continue;

      if (trimmed.startsWith('#')) {
        final match = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
        if (match != null) {
          final level = match.group(1)!.length;
          final title = match.group(2)!.trim();
          if (title == '目录' || title.toLowerCase() == 'table of contents') {
            continue;
          }
          final slug = _slugify(title);
          items.add(OutlineItem(
            title: title,
            level: level,
            anchor: slug,
            lineNumber: i + 1,
          ));
        }
      }
    }
    _outlineItems = List.unmodifiable(items);
  }

  static final _unicodeAlphaNumRegex = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _isAlphaNum(int rune, String ch) {
    if ((rune >= 0x30 && rune <= 0x39) ||
        (rune >= 0x41 && rune <= 0x5A) ||
        (rune >= 0x61 && rune <= 0x7A) ||
        (rune >= 0x4E00 && rune <= 0x9FFF)) {
      return true;
    }
    return _unicodeAlphaNumRegex.hasMatch(ch);
  }

  static String _slugify(String text) {
    final buffer = StringBuffer();
    bool prevIsDash = false;
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (_isAlphaNum(rune, ch)) {
        buffer.write(ch.toLowerCase());
        prevIsDash = false;
      } else if (ch == '-') {
        if (!prevIsDash && buffer.isNotEmpty) {
          buffer.write('-');
          prevIsDash = true;
        }
      } else if (ch.trim().isEmpty || ch == '_') {
        if (!prevIsDash && buffer.isNotEmpty) {
          buffer.write('-');
          prevIsDash = true;
        }
      }
    }
    var slug = buffer.toString();
    if (slug.endsWith('-')) {
      slug = slug.substring(0, slug.length - 1);
    }
    return slug;
  }

  @override
  void dispose() {
    _persistDebounceTimer?.cancel();
    _persistPreferences();
    _viewportDebounceTimer?.cancel();
    _debounceTimer?.cancel();
    _watcherSubscription?.cancel();
    super.dispose();
  }
}
