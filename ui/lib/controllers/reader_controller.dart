import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:path/path.dart' as p;
import '../bridge/native_engine.dart';
import '../models/render_options.dart';

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
  String? _errorMessage;
  double _lastScrollRatio = 0.0;
  bool _autoReload = true;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;

  final List<String> _recentFiles = [];
  Map<String, dynamic> _fontReport = {};

  // Getters
  String? get currentFilePath => _currentFilePath;
  String get currentMarkdown => _currentMarkdown;
  String get documentTitle => _documentTitle;
  Uint8List? get currentPdfBytes => _currentPdfBytes;
  RenderOptions get renderOptions => _renderOptions;
  bool get isCompiling => _isCompiling;
  String? get errorMessage => _errorMessage;
  double get lastScrollRatio => _lastScrollRatio;
  bool get autoReload => _autoReload;
  List<String> get recentFiles => List.unmodifiable(_recentFiles);
  Map<String, dynamic> get fontReport => _fontReport;

  ReaderController({String? initialFilePath}) {
    refreshFontReport();
    if (initialFilePath != null && initialFilePath.isNotEmpty) {
      openFile(initialFilePath);
    } else {
      loadSampleDocument();
    }
  }

  void updateScrollRatio(double ratio) {
    if (ratio >= 0.0 && ratio <= 1.0) {
      _lastScrollRatio = ratio;
    }
  }

  Future<void> openFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      _errorMessage = 'File not found: $filePath';
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
      _documentTitle = p.basenameWithoutExtension(filePath);

      // Add to recent files
      _recentFiles.remove(filePath);
      _recentFiles.insert(0, filePath);
      if (_recentFiles.length > 10) {
        _recentFiles.removeLast();
      }

      _setupFileWatcher(filePath);
      await compileDocument();
    } catch (e) {
      _errorMessage = 'Failed to read file: $e';
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

    _isCompiling = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final docDir = _currentFilePath != null
          ? p.dirname(_currentFilePath!)
          : Directory.current.path;

      final pdfBytes = await NativeEngine.instance.compileMarkdownAsync(
        _currentMarkdown,
        title: _documentTitle,
        docDir: docDir,
        options: _renderOptions,
      );

      if (pdfBytes != null && pdfBytes.isNotEmpty) {
        _currentPdfBytes = pdfBytes;
        _errorMessage = null;
      } else {
        _errorMessage = NativeEngine.instance.getLastError() ?? 'Compilation failed';
      }
    } catch (e) {
      _errorMessage = 'Compilation error: $e';
    } finally {
      _isCompiling = false;
      notifyListeners();
    }
  }

  void toggleMode() {
    final nextMode = _renderOptions.mode == 'fluid' ? 'paged' : 'fluid';
    _renderOptions = _renderOptions.copyWith(mode: nextMode);
    compileDocument();
  }

  void toggleTheme() {
    final nextTheme = _renderOptions.theme == 'light' ? 'dark' : 'light';
    _renderOptions = _renderOptions.copyWith(theme: nextTheme);
    compileDocument();
  }

  Timer? _viewportDebounceTimer;
  void setViewportWidth(double width) {
    if ((width - _renderOptions.viewportWidth).abs() > 40) {
      _viewportDebounceTimer?.cancel();
      _viewportDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        _renderOptions = _renderOptions.copyWith(viewportWidth: width);
        if (_renderOptions.isFluid) {
          compileDocument();
        }
      });
    }
  }

  void setFontSize(double size) {
    _renderOptions = _renderOptions.copyWith(fontSize: size.clamp(8.0, 24.0));
    compileDocument();
  }

  void refreshFontReport() {
    try {
      _fontReport = NativeEngine.instance.detectFonts();
      notifyListeners();
    } catch (_) {}
  }

  void setBodyFont(String? font) {
    _renderOptions = _renderOptions.copyWith(bodyFont: font);
    compileDocument();
  }

  void setCodeFont(String? font) {
    _renderOptions = _renderOptions.copyWith(codeFont: font);
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

  void loadSampleDocument() {
    _currentFilePath = null;
    _documentTitle = 'SoGoodViewer Demo';
    _currentMarkdown = r'''
# SoGoodViewer 🚀
### 出版级排版 Markdown 桌面阅读器

欢迎体验 **SoGoodViewer**！本应用通过 **Typst 嵌入式编译 + PDFium 矢量渲染**，为您提供极致的阅读美感与跨平台 100% 像素级一致性。

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

| 衡量维度 | SoGoodViewer (纯原生) | 传统 Electron / WebView 阅读器 |
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

    compileDocument();
  }

  @override
  void dispose() {
    _viewportDebounceTimer?.cancel();
    _debounceTimer?.cancel();
    _watcherSubscription?.cancel();
    super.dispose();
  }
}
