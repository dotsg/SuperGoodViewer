import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' show Locale;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'package:path/path.dart' as p;
import '../bridge/native_engine.dart';
import '../i18n/app_localizations.dart';
import '../i18n/app_strings.dart';
import '../i18n/locales.dart';
import '../models/render_options.dart';
import '../services/document_cache_service.dart';
import '../services/preferences_service.dart';
import '../services/remote_image_service.dart';
import '../services/shortcut_service.dart';

class OutlineItem {
  final String title;
  final int level;
  final String anchor;
  final int lineNumber;
  final int? pageNumber;
  final double? docY;

  const OutlineItem({
    required this.title,
    required this.level,
    required this.anchor,
    required this.lineNumber,
    this.pageNumber,
    this.docY,
  });

  OutlineItem copyWith({
    String? title,
    int? level,
    String? anchor,
    int? lineNumber,
    int? pageNumber,
    double? docY,
  }) {
    return OutlineItem(
      title: title ?? this.title,
      level: level ?? this.level,
      anchor: anchor ?? this.anchor,
      lineNumber: lineNumber ?? this.lineNumber,
      pageNumber: pageNumber ?? this.pageNumber,
      docY: docY ?? this.docY,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutlineItem &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          level == other.level &&
          anchor == other.anchor &&
          lineNumber == other.lineNumber &&
          pageNumber == other.pageNumber &&
          docY == other.docY;

  @override
  int get hashCode => Object.hash(title, level, anchor, lineNumber, pageNumber, docY);

  @override
  String toString() => 'OutlineItem(H$level: $title, line: $lineNumber, page: $pageNumber, docY: $docY)';
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
  bool _isRawPdf = false;
  RenderOptions _renderOptions = RenderOptions(
    mode: 'fluid',
    theme: 'light',
    viewportWidth: 720.0,
    fontSize: 10.5,
    imageCacheDir: RemoteImageService.instance.getCacheDirectory().path,
  );
  bool _isCompiling = false;
  int _compileGeneration = 0;
  bool _hasPendingCompile = false;
  String? _errorMessage;
  int _degradedEquationCount = 0;
  List<String> _degradedEquations = const [];
  double _lastScrollRatio = 0.0;
  double _lastScrollOffset = 0.0;
  int _lastPageNumber = 1;
  double _lastZoom = 1.0;
  AutoFitMode _autoFitMode = AutoFitMode.none;
  bool _isReloading = false;
  Timer? _reloadingSafetyTimer;
  bool _autoReload = true;
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  Timer? _persistDebounceTimer;
  bool _isDisposed = false;

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  final List<String> _recentFiles = [];
  final Map<String, Map<String, dynamic>> _fileHistory = {};
  Map<String, dynamic> _fontReport = {};

  final ShortcutService shortcutService = ShortcutService();

  bool _isTwoPage = false;
  bool _isSidebarOpen = false;
  String _sidebarPosition = 'left'; // 'left' or 'right'
  static const double defaultSidebarWidth = 270.0;
  static const double minSidebarWidth = 180.0;
  static const double maxSidebarWidth = 600.0;
  double _sidebarWidth = defaultSidebarWidth;
  bool _isPresentationMode = false;
  List<OutlineItem> _outlineItems = [];
  int _activeOutlineIndex = -1;
  final ValueNotifier<int> activeOutlineNotifier = ValueNotifier<int>(-1);
  Timer? _activeOutlineLockTimer;
  bool _isActiveOutlineLocked = false;
  OutlineItem? _requestedJumpItem;
  bool renderOptionsChanged = false;

  String _language = 'zhHans';

  // Getters
  String get language => _language;
  Locale? get currentLocale => AppLanguage.fromCode(_language).locale;
  AppStrings get strings => AppI18n.resolve(_language);

  void setLanguage(String lang) {
    if (_language != lang) {
      _language = lang;
      _persistPreferences();
      notifyListeners();
    }
  }
  String? get currentFilePath => _currentFilePath;
  String get currentMarkdown => _currentMarkdown;
  String get documentTitle => _documentTitle;
  Uint8List? get currentPdfBytes => _currentPdfBytes;
  RenderOptions get renderOptions => _renderOptions;
  bool get isCompiling => _isCompiling;
  int get compileGeneration => _compileGeneration;
  String? get errorMessage => _errorMessage;
  int get degradedEquationCount => _degradedEquationCount;
  List<String> get degradedEquations => List.unmodifiable(_degradedEquations);
  bool get hasDegradedEquations => _degradedEquationCount > 0;
  double get lastScrollRatio => _lastScrollRatio;
  double get lastScrollOffset => _lastScrollOffset;
  int get lastPageNumber => _lastPageNumber;
  double get lastZoom => _lastZoom;
  AutoFitMode get autoFitMode => _autoFitMode;
  bool get isReloading => _isReloading;
  bool get autoReload => _autoReload;
  List<String> get recentFiles => List.unmodifiable(_recentFiles);
  Map<String, dynamic> get fontReport => _fontReport;
  bool get isTwoPage => _isTwoPage;
  bool get isSidebarOpen => _isSidebarOpen;
  String get sidebarPosition => _sidebarPosition;
  bool get isSidebarOnRight => _sidebarPosition == 'right';
  double get sidebarWidth => _sidebarWidth;
  bool get isPresentationMode => _isPresentationMode;
  List<OutlineItem> get outlineItems => _outlineItems;
  int get activeOutlineIndex => _activeOutlineIndex;
  OutlineItem? get requestedJumpItem => _requestedJumpItem;
  bool get isPdfDocument =>
      _isRawPdf || (_currentFilePath?.toLowerCase().endsWith('.pdf') ?? false);

  /// Native PDFs always use paged navigation, regardless of the saved Markdown layout preference.
  bool get isFluidLayout => _renderOptions.isFluid && !isPdfDocument;

  /// Top scroll deadband threshold (in points). Offsets <= this value are treated as top of document.
  static const double topScrollThreshold = 20.0;

  /// Calculates the effective target scroll offset Y in fluid mode based on document height.
  /// When [useOffset] is true, uses absolute [_lastScrollOffset] (e.g. streaming append / live edit).
  /// When [useOffset] is false, scales [_lastScrollRatio] with [docHeight] (e.g. option/theme/mode/zoom change).
  /// If [maxScroll] is provided, clamps the result to [0.0, maxScroll].
  double calculateFluidTargetScrollY(
    double docHeight, {
    required bool useOffset,
    double? maxScroll,
  }) {
    if (docHeight <= 0) return 0.0;
    final raw = (useOffset && _lastScrollOffset > 0.0)
        ? _lastScrollOffset
        : (_lastScrollRatio > 0.0 ? _lastScrollRatio * docHeight : 0.0);
    return maxScroll != null ? raw.clamp(0.0, maxScroll) : raw;
  }

  void setActiveOutlineIndex(int index) {
    if (_activeOutlineIndex != index) {
      _activeOutlineIndex = index;
      activeOutlineNotifier.value = index;
    }
  }

  void _lockActiveOutline() {
    _isActiveOutlineLocked = true;
    _activeOutlineLockTimer?.cancel();
    _activeOutlineLockTimer = Timer(const Duration(milliseconds: 350), () {
      _isActiveOutlineLocked = false;
    });
  }

  void updateActiveOutline({int? pageNumber, double? scrollRatio, double? scrollOffset}) {
    if (_isActiveOutlineLocked) return;
    if (_outlineItems.isEmpty) {
      setActiveOutlineIndex(-1);
      return;
    }

    final effectiveOffset = scrollOffset ?? _lastScrollOffset;
    final effectivePage = pageNumber ?? _lastPageNumber;
    final effectiveRatio = scrollRatio ?? _lastScrollRatio;

    final hasDocY = _outlineItems.any((item) => item.docY != null);
    int targetIndex = 0;

    if (hasDocY) {
      // Anchored strictly to the TOP of the reading viewport:
      // A chapter is active when its heading coordinate has reached or passed the top of the reading view.
      // Small buffer (12.0) ensures that when jumping to a chapter (with 8px top breathing room),
      // the chapter heading is immediately active without flickering.
      const double topBuffer = 12.0;
      final thresholdY = effectiveOffset + topBuffer;

      for (int i = 0; i < _outlineItems.length; i++) {
        final y = _outlineItems[i].docY;
        if (y != null && y <= thresholdY) {
          targetIndex = i;
        } else if (y != null && y > thresholdY) {
          break;
        }
      }

      // If user has scrolled all the way to the very bottom of the document, activate the last chapter
      if (effectiveRatio >= 0.98) {
        targetIndex = _outlineItems.length - 1;
      }
    } else if (_outlineItems.any((item) => item.pageNumber != null) && !isFluidLayout) {
      // Fallback for paged documents without docY: anchor strictly to the page at the TOP of the viewport
      for (int i = 0; i < _outlineItems.length; i++) {
        final p = _outlineItems[i].pageNumber;
        if (p != null && p <= effectivePage) {
          targetIndex = i;
        }
      }
    } else {
      // Fallback for documents without PDF outline positions
      if (effectiveRatio <= 0.005) {
        targetIndex = 0;
      } else if (effectiveRatio >= 0.98) {
        targetIndex = _outlineItems.length - 1;
      } else {
        final totalLines = math.max(1, _currentMarkdown.split('\n').length);
        for (int i = 0; i < _outlineItems.length; i++) {
          final item = _outlineItems[i];
          if (item.lineNumber > 0) {
            final itemRatio = (item.lineNumber - 1) / totalLines;
            if (itemRatio <= effectiveRatio + 0.015) {
              targetIndex = i;
            } else {
              break;
            }
          }
        }
      }
    }

    setActiveOutlineIndex(targetIndex);
  }

  void syncOutlinesDestinations(Map<String, ({int? pageNumber, double? docY})> destMap, {List<double>? orderedDocYs}) {
    if (_outlineItems.isEmpty || (destMap.isEmpty && (orderedDocYs == null || orderedDocYs.isEmpty))) return;
    bool changed = false;
    final updated = <OutlineItem>[];
    for (int i = 0; i < _outlineItems.length; i++) {
      final item = _outlineItems[i];
      final meta = destMap[item.title.trim()];
      final listY = (orderedDocYs != null && i < orderedDocYs.length) ? orderedDocYs[i] : null;
      final p = meta?.pageNumber;
      final y = meta?.docY ?? listY;
      if ((p != null && item.pageNumber != p) || (y != null && item.docY != y)) {
        changed = true;
        updated.add(item.copyWith(pageNumber: p, docY: y));
      } else {
        updated.add(item);
      }
    }

    if (changed) {
      _outlineItems = List.unmodifiable(updated);
      updateActiveOutline();
      notifyListeners();
    }
  }

  void syncOutlinesPageNumbers(Map<String, int> pageMap) {
    syncOutlinesDestinations(
      pageMap.map((key, val) => MapEntry(key, (pageNumber: val, docY: null))),
    );
  }

  void jumpToOutline(OutlineItem item) {
    final idx = _outlineItems.indexOf(item);
    if (idx >= 0) {
      setActiveOutlineIndex(idx);
      _lockActiveOutline();
    }
    _requestedJumpItem = item;
    notifyListeners();
  }

  /// Strictly checks whether [bytes] begins with '%PDF' at offset 0 (or immediately after UTF-8 BOM).
  /// Used for format detection when the file does not have a .pdf extension.
  static bool startsWithPdfHeader(Uint8List bytes) {
    if (bytes.length < 4) return false;
    int offset = 0;
    // Skip UTF-8 BOM [0xEF, 0xBB, 0xBF] if present
    if (bytes.length >= 7 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      offset = 3;
    }
    return bytes.length >= offset + 4 &&
        bytes[offset] == 0x25 && // '%'
        bytes[offset + 1] == 0x50 && // 'P'
        bytes[offset + 2] == 0x44 && // 'D'
        bytes[offset + 3] == 0x46; // 'F'
  }

  /// Searches for the '%PDF' magic header within the first 1024 bytes of [bytes],
  /// conforming to ISO 32000-1 §7.5.2 tolerance for leading bytes.
  static bool hasPdfHeader(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final searchLimit = math.min(1024, bytes.length - 4);
    for (int i = 0; i <= searchLimit; i++) {
      if (bytes[i] == 0x25 && // '%'
          bytes[i + 1] == 0x50 && // 'P'
          bytes[i + 2] == 0x44 && // 'D'
          bytes[i + 3] == 0x46) { // 'F'
        return true;
      }
    }
    return false;
  }

  /// Validates whether [bytes] is structurally a completed PDF document (used for hot reload safety).
  /// Checks that '%PDF' appears within the first 1024 bytes, and '%%EOF' is present
  /// when scanning backwards from the end (up to 64KB to tolerate appended metadata/padding).
  static bool isValidPdfBytes(Uint8List bytes) {
    if (bytes.length < 16) return false;
    if (!hasPdfHeader(bytes)) return false;

    // Search backwards for '%%EOF' across up to 64KB of trailing data
    final searchLimit = math.max(0, bytes.length - 65536);
    for (int i = bytes.length - 5; i >= searchLimit; i--) {
      if (bytes[i] == 0x25 &&
          bytes[i + 1] == 0x25 &&
          bytes[i + 2] == 0x45 &&
          bytes[i + 3] == 0x4F &&
          bytes[i + 4] == 0x46) {
        return true;
      }
    }
    return false;
  }

  void setErrorMessage(String? message) {
    if (_errorMessage == message) return;
    _errorMessage = message;
    try {
      final binding = SchedulerBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        binding.addPostFrameCallback((_) {
          if (!_isDisposed) {
            notifyListeners();
          }
        });
      } else {
        notifyListeners();
      }
    } catch (_) {
      notifyListeners();
    }
  }

  void setPdfOutlines(List<OutlineItem> items, {String? targetFilePath}) {
    if (!isPdfDocument) return;
    if (targetFilePath != null && _currentFilePath != targetFilePath) return;
    _outlineItems = List.unmodifiable(items);
    updateActiveOutline();
    notifyListeners();
  }

  @visibleForTesting
  void setOutlinesForTesting(List<OutlineItem> items) {
    _outlineItems = List.unmodifiable(items);
    updateActiveOutline();
    notifyListeners();
  }

  void clearJumpRequest() {
    _requestedJumpItem = null;
  }

  void toggleTwoPage() {
    renderOptionsChanged = true;
    _isTwoPage = !_isTwoPage;
    _persistPreferences();
    notifyListeners();
  }

  void setTwoPage(bool value) {
    if (_isTwoPage != value) {
      renderOptionsChanged = true;
      _isTwoPage = value;
      _persistPreferences();
      notifyListeners();
    }
  }

  void toggleSidebar() {
    setSidebarOpen(!_isSidebarOpen);
  }

  void setSidebarOpen(bool value) {
    if (_isSidebarOpen != value) {
      _isSidebarOpen = value;
      _persistPreferences();
      notifyListeners();
    }
  }

  void setSidebarPosition(String position) {
    if (position != 'left' && position != 'right') return;
    if (_sidebarPosition != position) {
      _sidebarPosition = position;
      _persistPreferences();
      notifyListeners();
    }
  }

  void toggleSidebarPosition() {
    setSidebarPosition(isSidebarOnRight ? 'left' : 'right');
  }

  void setSidebarWidth(double width) {
    final clamped = width.clamp(minSidebarWidth, maxSidebarWidth);
    if ((_sidebarWidth - clamped).abs() > 0.5) {
      _sidebarWidth = clamped;
      _persistDebounced();
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

  final bool autoRestorePreferences;

  ReaderController({
    String? initialFilePath,
    this.autoRestorePreferences = true,
    String? defaultLanguage,
  }) {
    if (defaultLanguage != null) {
      _language = defaultLanguage;
    }
    unawaited(refreshFontReport());
    _setSampleDocumentContent();
    if (initialFilePath != null && initialFilePath.isNotEmpty && File(initialFilePath).existsSync()) {
      _initPreferencesOnly();
      _openFileInternal(initialFilePath, preservePosition: false);
    } else if (autoRestorePreferences) {
      _initSession();
    } else {
      compileDocument();
    }
    shortcutService.addListener(_persistDebounced);
    shortcutService.addListener(notifyListeners);
  }

  void _initPreferencesOnly() {
    try {
      final prefs = PreferencesService.loadSync();
      final savedLanguage = prefs['language'] as String?;
      final savedTheme = prefs['theme'] as String?;
      final savedMode = prefs['mode'] as String?;
      final savedTwoPage = prefs['isTwoPage'] as bool?;
      final savedSidebarOpen = prefs['isSidebarOpen'] as bool?;
      final savedAutoFit = prefs['autoFitMode'] as String?;
      final recent = (prefs['recentFiles'] as List<dynamic>?)?.cast<String>();
      final savedFontSize = (prefs['fontSize'] as num?)?.toDouble();
      final savedBodyFont = prefs['bodyFont'] as String?;
      final savedCodeFont = prefs['codeFont'] as String?;
      final savedZoom = (prefs['lastZoom'] as num?)?.toDouble();
      final savedHistory = prefs['fileHistory'] as Map<String, dynamic>?;
      final rawPageFormat = prefs['pageFormat'] as String?;
      final savedPageFormat = (rawPageFormat != null && PageFormat.all.contains(rawPageFormat))
          ? rawPageFormat
          : null;
      final rawLastPagedFormat = prefs['lastPagedFormat'] as String?;
      final savedLastPagedFormat = (rawLastPagedFormat != null &&
              rawLastPagedFormat != PageFormat.fluid &&
              PageFormat.all.contains(rawLastPagedFormat))
          ? rawLastPagedFormat
          : null;
      final savedHeaderLeft = prefs['headerLeft'] as String?;
      final savedHeaderCenter = prefs['headerCenter'] as String?;
      final savedHeaderRight = prefs['headerRight'] as String?;
      final savedFooterLeft = prefs['footerLeft'] as String?;
      final savedFooterCenter = prefs['footerCenter'] as String?;
      final savedFooterRight = prefs['footerRight'] as String?;
      final savedShowHeaderRule = prefs['showHeaderRule'] as bool?;
      final savedShowFooterRule = prefs['showFooterRule'] as bool?;
      final savedSkipFirstPage = prefs['skipFirstPageHeaderFooter'] as bool?;
      final savedMarpEnabled = prefs['marpEnabled'] as bool?;

      if (recent != null && recent.isNotEmpty) {
        _recentFiles.clear();
        _recentFiles.addAll(recent);
      }

      if (savedTheme != null ||
          savedMode != null ||
          savedFontSize != null ||
          savedBodyFont != null ||
          savedCodeFont != null ||
          savedPageFormat != null ||
          savedLastPagedFormat != null ||
          savedHeaderLeft != null ||
          savedHeaderCenter != null ||
          savedHeaderRight != null ||
          savedFooterLeft != null ||
          savedFooterCenter != null ||
          savedFooterRight != null ||
          savedShowHeaderRule != null ||
          savedShowFooterRule != null ||
          savedSkipFirstPage != null ||
          savedMarpEnabled != null) {
        _renderOptions = _renderOptions.copyWith(
          theme: savedTheme ?? _renderOptions.theme,
          mode: savedMode ?? _renderOptions.mode,
          pageFormat: savedPageFormat ?? _renderOptions.pageFormat,
          fontSize: savedFontSize ?? _renderOptions.fontSize,
          bodyFont: savedBodyFont ?? _renderOptions.bodyFont,
          codeFont: savedCodeFont ?? _renderOptions.codeFont,
          headerLeft: savedHeaderLeft ?? _renderOptions.headerLeft,
          headerCenter: savedHeaderCenter ?? _renderOptions.headerCenter,
          headerRight: savedHeaderRight ?? _renderOptions.headerRight,
          footerLeft: savedFooterLeft ?? _renderOptions.footerLeft,
          footerCenter: savedFooterCenter ?? _renderOptions.footerCenter,
          footerRight: savedFooterRight ?? _renderOptions.footerRight,
          showHeaderRule: savedShowHeaderRule ?? _renderOptions.showHeaderRule,
          showFooterRule: savedShowFooterRule ?? _renderOptions.showFooterRule,
          skipFirstPageHeaderFooter: savedSkipFirstPage ?? _renderOptions.skipFirstPageHeaderFooter,
          marpEnabled: savedMarpEnabled ?? _renderOptions.marpEnabled,
          imageCacheDir: RemoteImageService.instance.getCacheDirectory().path,
        );
        if (savedLastPagedFormat != null) {
          _lastPagedFormat = savedLastPagedFormat;
        } else if (savedPageFormat != null && savedPageFormat != PageFormat.fluid) {
          _lastPagedFormat = savedPageFormat;
        }
      }
      if (savedLanguage != null) {
        _language = savedLanguage;
      }
      if (savedTwoPage != null) {
        _isTwoPage = savedTwoPage;
      }
      final savedSidebarPosition = prefs['sidebarPosition'] as String?;
      if (savedSidebarPosition == 'left' || savedSidebarPosition == 'right') {
        _sidebarPosition = savedSidebarPosition!;
      }
      final savedSidebarWidth = (prefs['sidebarWidth'] as num?)?.toDouble();
      if (savedSidebarWidth != null && savedSidebarWidth >= minSidebarWidth && savedSidebarWidth <= maxSidebarWidth) {
        _sidebarWidth = savedSidebarWidth;
      }
      if (savedSidebarOpen != null) {
        _isSidebarOpen = savedSidebarOpen;
      }
      if (savedAutoFit != null) {
        _autoFitMode = AutoFitMode.values.firstWhere(
          (m) => m.name == savedAutoFit,
          orElse: () => AutoFitMode.none,
        );
      }
      if (savedZoom != null && savedZoom > 0.1) {
        _lastZoom = savedZoom;
      }
      if (savedHistory != null) {
        _fileHistory.clear();
        for (final entry in savedHistory.entries) {
          if (entry.value is Map) {
            _fileHistory[entry.key] = Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }
      final savedShortcuts = prefs['shortcuts'] as Map<String, dynamic>?;
      if (savedShortcuts != null) {
        shortcutService.loadFromMap(savedShortcuts, notify: false);
      }
    } catch (e) {
      debugPrint('Error loading preferences: $e');
    }
  }

  void _initSession() {
    try {
      _initPreferencesOnly();
      final prefs = PreferencesService.loadSync();
      final lastFile = prefs['lastOpenedFile'] as String?;

      if (lastFile != null && lastFile.isNotEmpty) {
        final file = File(lastFile);
        if (file.existsSync()) {
          final history = _fileHistory[lastFile];
          final savedScroll = (history?['scrollRatio'] as num?)?.toDouble() ??
              (prefs['lastScrollRatio'] as num?)?.toDouble() ??
              0.0;
          final savedOffset = (history?['scrollOffset'] as num?)?.toDouble() ??
              (prefs['lastScrollOffset'] as num?)?.toDouble() ??
              0.0;
          final savedPage = (history?['pageNumber'] as num?)?.toInt() ??
              (prefs['lastPageNumber'] as num?)?.toInt() ??
              1;
          final savedZoom = (history?['zoom'] as num?)?.toDouble() ??
              (prefs['lastZoom'] as num?)?.toDouble() ??
              _lastZoom;

          _lastScrollRatio = savedScroll;
          _lastScrollOffset = savedOffset;
          _lastPageNumber = savedPage;
          _lastZoom = savedZoom;
          _openFileInternal(lastFile, preservePosition: true);
          return;
        }
      }
    } catch (e) {
      debugPrint('Error restoring last session: $e');
    }
    // Only compile sample document if no valid previous file exists
    compileDocument();
  }

  void _persistPreferences() {
    _updateCurrentFileHistory();
    PreferencesService.save({
      'language': _language,
      'lastOpenedFile': _currentFilePath,
      'recentFiles': List<String>.from(_recentFiles),
      'theme': _renderOptions.theme,
      'mode': _renderOptions.mode,
      'pageFormat': _renderOptions.effectivePageFormat,
      'lastPagedFormat': _lastPagedFormat,
      'isTwoPage': _isTwoPage,
      'isSidebarOpen': _isSidebarOpen,
      'sidebarPosition': _sidebarPosition,
      'sidebarWidth': _sidebarWidth,
      'autoFitMode': _autoFitMode.name,
      'fontSize': _renderOptions.fontSize,
      'bodyFont': _renderOptions.bodyFont,
      'codeFont': _renderOptions.codeFont,
      'headerLeft': _renderOptions.headerLeft,
      'headerCenter': _renderOptions.headerCenter,
      'headerRight': _renderOptions.headerRight,
      'footerLeft': _renderOptions.footerLeft,
      'footerCenter': _renderOptions.footerCenter,
      'footerRight': _renderOptions.footerRight,
      'showHeaderRule': _renderOptions.showHeaderRule,
      'showFooterRule': _renderOptions.showFooterRule,
      'skipFirstPageHeaderFooter': _renderOptions.skipFirstPageHeaderFooter,
      'marpEnabled': _renderOptions.marpEnabled,
      'lastScrollRatio': _lastScrollRatio,
      'lastScrollOffset': _lastScrollOffset,
      'lastPageNumber': _lastPageNumber,
      'lastZoom': _lastZoom,
      'fileHistory': _fileHistory,
      'shortcuts': shortcutService.toMap(),
    });
  }

  final Stopwatch _persistThrottleClock = Stopwatch();

  void _persistDebounced() {
    if (_persistDebounceTimer?.isActive == true &&
        _persistThrottleClock.isRunning &&
        _persistThrottleClock.elapsedMilliseconds < 120) {
      return;
    }
    _persistThrottleClock
      ..reset()
      ..start();
    _persistDebounceTimer?.cancel();
    _persistDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _persistThrottleClock.stop();
      _persistPreferences();
    });
  }

  void startReloading() {
    _isReloading = true;
    _reloadingSafetyTimer?.cancel();
    _reloadingSafetyTimer = Timer(const Duration(milliseconds: 800), () {
      _isReloading = false;
    });
  }

  void finishReloading() {
    _reloadingSafetyTimer?.cancel();
    _reloadingSafetyTimer = null;
    _isReloading = false;
  }

  void _updateCurrentFileHistory() {
    if (_currentFilePath != null) {
      _fileHistory[_currentFilePath!] = {
        'scrollRatio': _lastScrollRatio,
        'scrollOffset': _lastScrollOffset,
        'pageNumber': _lastPageNumber,
        'zoom': _lastZoom,
      };
    }
  }

  void updateScrollRatio(double ratio, {double? offset}) {
    if (ratio >= 0.0 && ratio <= 1.0) {
      _lastScrollRatio = ratio;
      if (offset != null && offset >= 0.0) {
        _lastScrollOffset = offset;
      }
      _updateCurrentFileHistory();
      _persistDebounced();
      updateActiveOutline(scrollRatio: ratio, scrollOffset: offset ?? _lastScrollOffset);
    }
  }

  void updatePageNumber(int pageNumber) {
    // While reloading, ignore transient reset to page 1 before page is restored
    if (_isReloading && pageNumber == 1 && _lastPageNumber > 1) return;
    if (pageNumber >= 1) {
      _lastPageNumber = pageNumber;
      _updateCurrentFileHistory();
      _persistDebounced();
      updateActiveOutline(pageNumber: pageNumber);
    }
  }

  void updateZoom(double zoom) {
    if (zoom > 0.1) {
      _lastZoom = zoom;
      _updateCurrentFileHistory();
      _persistDebounced();
    }
  }

  void _openFileInternal(String filePath, {bool preservePosition = false}) {
    final file = File(filePath);
    if (!file.existsSync()) {
      _watcherSubscription?.cancel();
      _currentFilePath = filePath;
      _documentTitle = p.basenameWithoutExtension(filePath);
      _currentPdfBytes = null;
      _outlineItems = [];
      _currentMarkdown = '';
      _isRawPdf = false;
      _errorMessage = 'File not found: $filePath';
      _degradedEquationCount = 0;
      _degradedEquations = const [];
      finishReloading();
      notifyListeners();
      return;
    }

    try {
      final bytes = file.readAsBytesSync();
      final isPdf = filePath.toLowerCase().endsWith('.pdf') || startsWithPdfHeader(bytes);

      _currentFilePath = filePath;
      _documentTitle = p.basenameWithoutExtension(filePath);

      if (isPdf) {
        _compileGeneration++;
        _hasPendingCompile = false;
        _isRawPdf = true;
        _currentMarkdown = '';
        _outlineItems = [];
        _currentPdfBytes = bytes;
        _errorMessage = null;
        _degradedEquationCount = 0;
        _degradedEquations = const [];

        if (!preservePosition) {
          final history = _fileHistory[filePath];
          if (history != null) {
            _lastScrollRatio = (history['scrollRatio'] as num?)?.toDouble() ?? 0.0;
            _lastScrollOffset = (history['scrollOffset'] as num?)?.toDouble() ?? 0.0;
            _lastPageNumber = (history['pageNumber'] as num?)?.toInt() ?? 1;
            _lastZoom = (history['zoom'] as num?)?.toDouble() ?? _lastZoom;
            startReloading();
          } else {
            _lastScrollRatio = 0.0;
            _lastScrollOffset = 0.0;
            _lastPageNumber = 1;
            finishReloading();
          }
        } else {
          startReloading();
        }

        // Add to recent files
        _recentFiles.remove(filePath);
        _recentFiles.insert(0, filePath);
        if (_recentFiles.length > 10) {
          _recentFiles.removeLast();
        }

        RemoteImageService.instance.clearNegativeCache();
        _persistDebounced();
        _setupFileWatcher(filePath);
        notifyListeners();
        return;
      }

      _isRawPdf = false;
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = utf8.decode(bytes, allowMalformed: true);
      }
      _currentMarkdown = content;
      _extractOutline(_currentMarkdown);

      final frontmatterFormat = _detectFrontmatterPageFormat(content);
      if (frontmatterFormat != null) {
        _renderOptions = _renderOptions.copyWith(
          pageFormat: frontmatterFormat,
          mode: frontmatterFormat == PageFormat.fluid ? 'fluid' : 'paged',
        );
        if (frontmatterFormat != PageFormat.fluid) {
          _lastPagedFormat = frontmatterFormat;
        }
      }

      if (!preservePosition) {
        final history = _fileHistory[filePath];
        if (history != null) {
          _lastScrollRatio = (history['scrollRatio'] as num?)?.toDouble() ?? 0.0;
          _lastScrollOffset = (history['scrollOffset'] as num?)?.toDouble() ?? 0.0;
          _lastPageNumber = (history['pageNumber'] as num?)?.toInt() ?? 1;
          _lastZoom = (history['zoom'] as num?)?.toDouble() ?? _lastZoom;
          startReloading();
        } else {
          _lastScrollRatio = 0.0;
          _lastScrollOffset = 0.0;
          _lastPageNumber = 1;
          finishReloading();
        }
      } else {
        startReloading();
      }

      // Add to recent files
      _recentFiles.remove(filePath);
      _recentFiles.insert(0, filePath);
      if (_recentFiles.length > 10) {
        _recentFiles.removeLast();
      }

      RemoteImageService.instance.clearNegativeCache();
      _persistDebounced();
      _setupFileWatcher(filePath);
      _triggerRemoteImageDownloads();

      // Check fast disk cache for pre-compiled PDF!
      final cachedPdf = DocumentCacheService.getCachedPdf(filePath, _renderOptions);
      if (cachedPdf != null && cachedPdf.isNotEmpty) {
        _currentPdfBytes = cachedPdf;
        _errorMessage = null;
        _degradedEquationCount = 0;
        _degradedEquations = const [];
        debugPrint('[ReaderController] Fast cache hit: instant PDF loaded (${cachedPdf.length} bytes) for $filePath');
        notifyListeners();
        return;
      }

      compileDocument();
    } catch (e) {
      final msg = 'Failed to read file: $e';
      _currentPdfBytes = null;
      _outlineItems = [];
      _errorMessage = msg;
      _degradedEquationCount = 0;
      _degradedEquations = const [];
      finishReloading();
      notifyListeners();
    }
  }

  Future<void> openFile(String filePath, {bool preservePosition = false}) async {
    _openFileInternal(filePath, preservePosition: preservePosition);
  }

  void clearRecentFiles() {
    _recentFiles.clear();
    _persistPreferences();
    notifyListeners();
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
  DateTime? _firstStreamEventTime;
  static const _debounceDelay = Duration(milliseconds: 150);
  static const _maxWaitDelay = Duration(milliseconds: 500);

  /// Debounced file reloader with max-wait throttle:
  /// - Waits 150ms after the latest write event to avoid reading partially flushed files.
  /// - Flushes at least every 500ms during continuous streaming writes.
  void _onExternalFileModified() {
    final now = DateTime.now();
    _firstStreamEventTime ??= now;

    final elapsed = now.difference(_firstStreamEventTime!);
    if (elapsed >= _maxWaitDelay) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _firstStreamEventTime = null;
      _triggerExternalFileReload();
    } else {
      _debounceTimer?.cancel();
      final remaining = _maxWaitDelay - elapsed;
      final delay = remaining < _debounceDelay ? remaining : _debounceDelay;
      _debounceTimer = Timer(delay, () {
        _debounceTimer = null;
        _firstStreamEventTime = null;
        _triggerExternalFileReload();
      });
    }
  }

  Future<void> _triggerExternalFileReload() async {
    if (_currentFilePath != null) {
      final file = File(_currentFilePath!);
      if (await file.exists()) {
        try {
          if (isPdfDocument) {
            final bytes = await file.readAsBytes();
            if (!isValidPdfBytes(bytes)) {
              debugPrint('[ReaderController] PDF reload skipped: incomplete file (in-flight write)');
              return;
            }
            if (_currentPdfBytes != null && listEquals(bytes, _currentPdfBytes)) {
              return;
            }
            _currentPdfBytes = bytes;
            _errorMessage = null;
            startReloading();
            notifyListeners();
            return;
          }
          final bytes = await file.readAsBytes();
          final text = utf8.decode(bytes, allowMalformed: true);
          if (text == _currentMarkdown) {
            return; // Content unchanged, skip redundant compilation & remount
          }
          _currentMarkdown = text;
          _extractOutline(_currentMarkdown);
          _triggerRemoteImageDownloads();
          startReloading();
          await compileDocument();
        } catch (e) {
          debugPrint('Failed to reload modified file: $e');
        }
      }
    }
  }

  /// Manually refreshes the current document, clearing negative image cache and re-triggering downloads.
  Future<void> refreshDocument() async {
    if (isPdfDocument) {
      if (_currentFilePath != null) {
        final file = File(_currentFilePath!);
        try {
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            _currentPdfBytes = bytes;
            _errorMessage = null;
            startReloading();
            notifyListeners();
          }
        } catch (e) {
          _errorMessage = 'Failed to refresh PDF: $e';
          finishReloading();
          notifyListeners();
        }
      }
      return;
    }
    RemoteImageService.instance.clearNegativeCache();
    _triggerRemoteImageDownloads();
    await compileDocument();
  }

  void _triggerRemoteImageDownloads() {
    final markdownToScan = _currentMarkdown;
    if (markdownToScan.isEmpty) return;

    RemoteImageService.instance.fetchImagesInMarkdown(
      markdownToScan,
      onBatchReady: () {
        if (_isDisposed) return;
        if (_currentMarkdown != markdownToScan) return;
        debugPrint('[ReaderController] Remote images batch downloaded, triggering progressive re-render');
        startReloading();
        compileDocument();
      },
    );
  }

  Future<void> compileDocument() async {
    if (isPdfDocument) return;
    if (_currentMarkdown.isEmpty) return;

    final int generation = ++_compileGeneration;
    if (_isCompiling) {
      _hasPendingCompile = true;
      return;
    }

    _isCompiling = true;
    _hasPendingCompile = false;
    _errorMessage = null;
    _degradedEquationCount = 0;
    _degradedEquations = const [];
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

      final result = await NativeEngine.instance.compileMarkdownResultAsync(
        _currentMarkdown,
        title: _documentTitle,
        docDir: docDir,
        options: _renderOptions,
      );

      if (generation == _compileGeneration && !isPdfDocument) {
        if (result.isSuccess) {
          final pdfBytes = result.pdfBytes!;
          _currentPdfBytes = pdfBytes;
          _errorMessage = null;
          _degradedEquationCount = result.degradedEquationCount;
          _degradedEquations = result.degradedEquations;
          if (_degradedEquationCount > 0) {
            debugPrint(
              '[ReaderController] compileDocument: WARNING gen $generation: '
              '$_degradedEquationCount degraded equation(s) detected: $_degradedEquations',
            );
          }
          debugPrint('[ReaderController] compileDocument: SUCCESS gen $generation (${pdfBytes.length} bytes)');
          if (_currentFilePath != null) {
            unawaited(DocumentCacheService.saveCachedPdf(_currentFilePath!, _renderOptions, pdfBytes));
          }
        } else {
          _degradedEquationCount = 0;
          _degradedEquations = const [];
          _errorMessage = result.errorMessage ?? NativeEngine.instance.getLastError() ?? 'Compilation failed';
          debugPrint('[ReaderController] compileDocument: FAILED gen $generation ($_errorMessage)');
        }
      }
    } catch (e, st) {
      if (generation == _compileGeneration && !isPdfDocument) {
        _errorMessage = 'Compilation error: $e';
        debugPrint('[ReaderController] compileDocument: EXCEPTION gen $generation ($e)\n$st');
      }
    } finally {
      _isCompiling = false;
      if (_hasPendingCompile && !isPdfDocument) {
        _hasPendingCompile = false;
        compileDocument();
      } else {
        notifyListeners();
      }
    }
  }

  String _lastPagedFormat = PageFormat.a4Portrait;

  void setPageFormat(String format) {
    if (isPdfDocument) return;
    if (format != PageFormat.fluid) {
      _lastPagedFormat = format;
    }
    if (_renderOptions.effectivePageFormat == format) return;
    renderOptionsChanged = true;
    startReloading();
    final nextMode = format == PageFormat.fluid ? 'fluid' : 'paged';
    _renderOptions = _renderOptions.copyWith(
      mode: nextMode,
      pageFormat: format,
    );
    _persistDebounced();
    notifyListeners();
    if (_currentFilePath != null) {
      final cached = DocumentCacheService.getCachedPdf(_currentFilePath!, _renderOptions);
      if (cached != null && cached.isNotEmpty) {
        _currentPdfBytes = cached;
        _errorMessage = null;
        debugPrint('[ReaderController] PageFormat change cache hit: instant PDF loaded');
        notifyListeners();
        return;
      }
    }
    compileDocument();
  }

  void cyclePageFormat() {
    if (isPdfDocument) return;
    final current = _renderOptions.effectivePageFormat;
    final formats = PageFormat.all;
    final idx = formats.indexOf(current);
    final nextIdx = (idx == -1 || idx == formats.length - 1) ? 0 : idx + 1;
    setPageFormat(formats[nextIdx]);
  }

  void toggleMode() {
    if (isPdfDocument) return;
    if (_renderOptions.isFluid) {
      setPageFormat(_lastPagedFormat);
    } else {
      setPageFormat(PageFormat.fluid);
    }
  }

  String? _formatBeforePresentation;

  void setPresentationMode(bool value) {
    if (_isPresentationMode != value) {
      _isPresentationMode = value;
      if (value) {
        if (!isPdfDocument && _renderOptions.isFluid) {
          _formatBeforePresentation = _renderOptions.effectivePageFormat;
          final savedLastPaged = _lastPagedFormat;
          setPageFormat(PageFormat.slide16x9);
          _lastPagedFormat = savedLastPaged;
        }
      } else {
        if (_formatBeforePresentation != null) {
          final restore = _formatBeforePresentation!;
          _formatBeforePresentation = null;
          setPageFormat(restore);
        }
      }
      notifyListeners();
    }
  }

  void togglePresentationMode() {
    setPresentationMode(!_isPresentationMode);
  }

  static const Object _undefined = Object();

  void setHeaderFooterOptions({
    Object? headerLeft = _undefined,
    Object? headerCenter = _undefined,
    Object? headerRight = _undefined,
    Object? footerLeft = _undefined,
    Object? footerCenter = _undefined,
    Object? footerRight = _undefined,
    bool? showHeaderRule,
    bool? showFooterRule,
    bool? skipFirstPageHeaderFooter,
    bool? marpEnabled,
  }) {
    if (isPdfDocument) return;
    renderOptionsChanged = true;
    startReloading();
    _renderOptions = _renderOptions.copyWith(
      headerLeft: headerLeft,
      headerCenter: headerCenter,
      headerRight: headerRight,
      footerLeft: footerLeft,
      footerCenter: footerCenter,
      footerRight: footerRight,
      showHeaderRule: showHeaderRule,
      showFooterRule: showFooterRule,
      skipFirstPageHeaderFooter: skipFirstPageHeaderFooter,
      marpEnabled: marpEnabled,
    );
    _persistDebounced();
    notifyListeners();
    compileDocument();
  }

  void toggleTheme() {
    if (isPdfDocument) {
      final nextTheme = _renderOptions.theme == 'light' ? 'dark' : 'light';
      _renderOptions = _renderOptions.copyWith(theme: nextTheme);
      _persistDebounced();
      notifyListeners();
      return;
    }
    renderOptionsChanged = true;
    startReloading();
    final nextTheme = _renderOptions.theme == 'light' ? 'dark' : 'light';
    _renderOptions = _renderOptions.copyWith(theme: nextTheme);
    _persistDebounced();
    notifyListeners();
    if (_currentFilePath != null) {
      final cached = DocumentCacheService.getCachedPdf(_currentFilePath!, _renderOptions);
      if (cached != null && cached.isNotEmpty) {
        _currentPdfBytes = cached;
        _errorMessage = null;
        debugPrint('[ReaderController] Theme toggle cache hit: instant PDF loaded');
        notifyListeners();
        return;
      }
    }
    compileDocument();
  }

  Timer? _viewportDebounceTimer;
  void setViewportWidth(double width) {
    if (isPdfDocument) return;
    if ((width - _renderOptions.viewportWidth).abs() > 40) {
      _viewportDebounceTimer?.cancel();
      _viewportDebounceTimer = Timer(const Duration(milliseconds: 300), () {
        renderOptionsChanged = true;
        _renderOptions = _renderOptions.copyWith(viewportWidth: width);
        if (_renderOptions.isFluid) {
          startReloading();
          compileDocument();
        }
      });
    }
  }

  void setFontSize(double size) {
    _renderOptions = _renderOptions.copyWith(fontSize: size.clamp(8.0, 24.0));
    _persistPreferences();
    if (isPdfDocument) {
      notifyListeners();
      return;
    }
    renderOptionsChanged = true;
    startReloading();
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
    _renderOptions = _renderOptions.copyWith(bodyFont: font);
    _persistPreferences();
    if (isPdfDocument) {
      notifyListeners();
      return;
    }
    renderOptionsChanged = true;
    startReloading();
    compileDocument();
  }

  void setCodeFont(String? font) {
    _renderOptions = _renderOptions.copyWith(codeFont: font);
    _persistPreferences();
    if (isPdfDocument) {
      notifyListeners();
      return;
    }
    renderOptionsChanged = true;
    startReloading();
    compileDocument();
  }

  void setTypography({String? bodyFont, String? codeFont, double? fontSize}) {
    _renderOptions = _renderOptions.copyWith(
      bodyFont: bodyFont,
      codeFont: codeFont,
      fontSize: fontSize?.clamp(8.0, 24.0),
    );
    _persistPreferences();
    if (isPdfDocument) {
      notifyListeners();
      return;
    }
    renderOptionsChanged = true;
    startReloading();
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

  /// Prepares and returns the PDF bytes for export (e.g. publication-grade light mode PDF).
  Future<Uint8List?> getPdfBytesForExport() async {
    if (_currentPdfBytes == null) return null;
    try {
      if (isPdfDocument || _renderOptions.theme == 'light') {
        // Direct PDF or light mode: use current in-memory PDF immediately (0ms fast path)
        return _currentPdfBytes;
      }

      // When viewing in dark mode, strictly export publication-grade light mode document
      final exportOptions = _renderOptions.copyWith(theme: 'light');

      if (_currentFilePath != null) {
        final cached = DocumentCacheService.getCachedPdf(_currentFilePath!, exportOptions);
        if (cached != null && cached.isNotEmpty) {
          return cached;
        }
      }

      if (!NativeEngine.instance.isAvailable) {
        _errorMessage = NativeEngine.instance.initError ?? 'Native library not loaded';
        notifyListeners();
        return null;
      }

      final docDir = _currentFilePath != null
          ? p.dirname(_currentFilePath!)
          : Directory.current.path;

      final exportResult = await NativeEngine.instance.compileMarkdownResultAsync(
        _currentMarkdown,
        title: _documentTitle,
        docDir: docDir,
        options: exportOptions,
      );
      final bytes = exportResult.pdfBytes;

      if (exportResult.degradedEquationCount > 0) {
        debugPrint(
          '[ReaderController] exportPdf: WARNING: ${exportResult.degradedEquationCount} degraded equation(s) in export',
        );
      }

      if (bytes != null && bytes.isNotEmpty && _currentFilePath != null) {
        unawaited(DocumentCacheService.saveCachedPdf(_currentFilePath!, exportOptions, bytes));
      }

      if (bytes == null || bytes.isEmpty) {
        _errorMessage = 'Export failed: Unable to generate light-mode PDF';
        notifyListeners();
        return null;
      }

      return bytes;
    } catch (e) {
      _errorMessage = 'Export failed: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> exportPdf(String destinationPath) async {
    final bytesToExport = await getPdfBytesForExport();
    if (bytesToExport == null || bytesToExport.isEmpty) return false;
    try {
      final file = File(destinationPath);
      await file.writeAsBytes(bytesToExport);
      return true;
    } catch (e) {
      _errorMessage = 'Export failed: $e';
      notifyListeners();
      return false;
    }
  }

  static const String _sampleMarkdown = r'''# SuperGoodViewer 🚀
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

搭配 **Maple Mono** 或中英文严格 1:2 等宽字体，实现全角半角绝对对齐：

> [!TIP]
> **关于排版对齐**：若下方字符画表格右侧边框存在轻微错位，是因为当前环境所用等宽字体的全角汉字与半角英文未达到严格 1:2 宽度比例（常见于英文等宽字体回退至系统通用黑体）。推荐下载安装开源 [Maple Mono](https://github.com/subframe7536/maple-font) 或更纱黑体（Sarasa Gothic）。若您已配置魔改 Consolas 等 1:2 等宽字体，可按快捷键 **Cmd/Ctrl + ,** 进入 **「字体与排版」** 设置中指定代码字体。

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

  void _setSampleDocumentContent() {
    _currentFilePath = null;
    _documentTitle = 'SuperGoodViewer Demo';
    _currentMarkdown = _sampleMarkdown;
    _extractOutline(_currentMarkdown);
  }

  void loadSampleDocument() {
    _setSampleDocumentContent();
    compileDocument();
  }

  static String cleanHeadingTitle(String raw) {
    var title = raw.trim();
    // 1. Strip leading and trailing ATX heading markers: e.g. "### Heading ##" -> "Heading"
    title = title.replaceFirst(RegExp(r'^#+\s*'), '');
    title = title.replaceAll(RegExp(r'\s+#+\s*$'), '');

    // 2. Resolve markdown links: e.g. "[Link text](url)" or "[Link text][ref]" -> "Link text"
    title = title.replaceAllMapped(
      RegExp(r'\[([^\]]+)\](?:\([^)]*\)|\[[^\]]*\])'),
      (m) => m[1] ?? '',
    );

    // 3. Resolve inline code: e.g. "`code`" -> "code"
    title = title.replaceAllMapped(
      RegExp(r'`([^`]+)`'),
      (m) => m[1] ?? '',
    );

    // 4. Resolve bold, italic, strikethrough markers
    title = title.replaceAllMapped(
      RegExp(r'(\*\*|__)(.*?)\1'),
      (m) => m[2] ?? '',
    );
    title = title.replaceAllMapped(
      RegExp(r'~~(.*?)~~'),
      (m) => m[1] ?? '',
    );
    title = title.replaceAllMapped(
      RegExp(r'(?<!\w)([*_])([^*_]+)\1(?!\w)'),
      (m) => m[2] ?? '',
    );

    // 5. Unescape markdown backslash escapes (CommonMark §2.4):
    // e.g. "\." -> ".", "\-" -> "-", "\*" -> "*", etc.
    title = title.replaceAllMapped(
      RegExp(r"""\\([!"#$%&'()*+,-./:;<=>?@[\\\]^_`{|}~])"""),
      (m) => m[1] ?? '',
    );

    return title.trim();
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
          final rawTitle = match.group(2)!.trim();
          final title = cleanHeadingTitle(rawTitle);
          if (title.isEmpty || title == '目录' || title.toLowerCase() == 'table of contents') {
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
    updateActiveOutline();
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

  String? _detectFrontmatterPageFormat(String markdown) {
    if (!(_renderOptions.marpEnabled ?? true)) return null;
    final trimmed = markdown.trimLeft();
    if (!trimmed.startsWith('---')) return null;
    final rest = trimmed.substring(3);
    final firstNl = rest.indexOf('\n');
    if (firstNl == -1 || rest.substring(0, firstNl).trim().isNotEmpty) return null;
    final afterFirstLine = rest.substring(firstNl + 1);
    final endIdx = afterFirstLine.indexOf('\n---');
    if (endIdx == -1) return null;
    final yaml = afterFirstLine.substring(0, endIdx);

    bool isMarp = false;
    String? size;
    String? pageFormat;

    for (final line in yaml.split('\n')) {
      final lineTrimmed = line.trim();
      if (lineTrimmed.isEmpty || lineTrimmed.startsWith('#')) continue;
      final colonIdx = lineTrimmed.indexOf(':');
      if (colonIdx == -1) continue;
      final key = lineTrimmed.substring(0, colonIdx).trim().toLowerCase();
      final val = lineTrimmed.substring(colonIdx + 1).replaceAll(RegExp(r'''^['"]|['"]$'''), '').trim();

      if (key == 'marp') {
        isMarp = val.toLowerCase() == 'true' || val.toLowerCase() == 'yes';
      } else if (key == 'size') {
        size = val;
      } else if (key == 'page_format' || key == 'page-format') {
        pageFormat = val;
      }
    }

    if (pageFormat != null) {
      switch (pageFormat.toLowerCase()) {
        case 'fluid':
          return PageFormat.fluid;
        case 'a4':
        case 'a4_portrait':
        case 'a4portrait':
        case 'portrait':
          return PageFormat.a4Portrait;
        case 'a4_landscape':
        case 'a4landscape':
        case 'landscape':
          return PageFormat.a4Landscape;
        case 'slide_16_9':
        case 'slide16x9':
        case '16:9':
        case '16_9':
          return PageFormat.slide16x9;
        case 'slide_4_3':
        case 'slide4x3':
        case '4:3':
        case '4_3':
          return PageFormat.slide4x3;
      }
    }

    if (isMarp) {
      if (size == '4:3' || size == '4_3') {
        return PageFormat.slide4x3;
      }
      return PageFormat.slide16x9;
    }

    return null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _activeOutlineLockTimer?.cancel();
    activeOutlineNotifier.dispose();
    shortcutService.removeListener(_persistDebounced);
    shortcutService.removeListener(notifyListeners);
    _reloadingSafetyTimer?.cancel();
    _persistDebounceTimer?.cancel();
    _persistThrottleClock.stop();
    _persistPreferences();
    _viewportDebounceTimer?.cancel();
    _debounceTimer?.cancel();
    _watcherSubscription?.cancel();
    super.dispose();
  }
}
