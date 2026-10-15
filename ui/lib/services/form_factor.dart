import 'dart:async' show unawaited;
import 'dart:io' show Directory, File, Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../bridge/native_engine.dart';
import '../controllers/reader_controller.dart';
import 'document_cache_service.dart';
import 'font_download_service.dart';
import 'preferences_service.dart';
import 'remote_image_service.dart';

/// FormFactor helper separating platform interaction paradigm (Mobile vs Desktop)
/// from viewport geometry (Compact vs Wide).
class FormFactor {
  /// Test-only override for mobile platform simulation.
  @visibleForTesting
  static bool? debugOverrideIsMobile;

  /// Default logical viewport width for mobile phone Fluid Markdown layout.
  static const double defaultMobileViewportWidth = 390.0;

  /// Default font size (pt) on mobile when user has not saved a custom size.
  static const double defaultMobileFontSize = 11.5;

  /// Initializes sandboxed mobile application directories on Android / iOS.
  static Future<void> initMobileDirectoriesIfNeeded() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      unawaited(FontDownloadService.instance.loadInstalledCustomFontsIntoFlutter());
      return;
    }
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      PreferencesService.setAppSupportDir(appSupportDir);
      final cacheDir = await getTemporaryDirectory();
      DocumentCacheService.setAppCacheDir(cacheDir);
      RemoteImageService.setAppRemoteImageCacheDir(cacheDir);
      NativeEngine.instance.setCacheDir(appSupportDir.path);
      MobileReadingPrefs.instance.loadFromDisk();
      unawaited(FontDownloadService.instance.loadInstalledCustomFontsIntoFlutter());
    } catch (e) {
      debugPrint('[Init] Failed to initialize mobile app directories: $e');
    }
  }

  /// Whether the current execution platform is a mobile touch operating system (Android or iOS).
  ///
  /// This determines interaction paradigms:
  /// - Touch drawer vs permanent sidebar
  /// - Fullscreen modal vs desktop dialog
  /// - Bottom reading HUD vs floating toolbar
  /// - Touch double-tap zoom vs mouse double-click word selection
  static bool isMobilePlatform([BuildContext? context]) {
    if (debugOverrideIsMobile != null) {
      return debugOverrideIsMobile!;
    }
    if (!kIsWeb) {
      return Platform.isAndroid || Platform.isIOS;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  /// Whether the current platform is desktop (macOS, Windows, Linux).
  static bool isDesktopPlatform([BuildContext? context]) {
    return !isMobilePlatform(context);
  }

  /// Whether the viewport width is compact (less than [breakpoint], default 600).
  ///
  /// Note: A desktop window can be compact if resized by the user, but it
  /// remains a desktop platform and should retain desktop window mechanics.
  static bool isCompact(BuildContext context, {double breakpoint = 600}) {
    return MediaQuery.sizeOf(context).width < breakpoint;
  }
}

/// Mobile-specific reading preferences and commercial value-add features:
/// - Warm Sepia Eye-Care theme (`isSepia`)
/// - Smart PDF Dark Mode page inversion (`pdfDarkInvert`)
/// - One-handed left/right edge tap page turning (`edgeTapPageTurn`)
/// - Keep screen awake while reading (`keepScreenOn`)
/// - Native Android system share / PDF export sheet
class MobileReadingPrefs extends ChangeNotifier {
  MobileReadingPrefs._() {
    loadFromDisk();
  }

  static final MobileReadingPrefs instance = MobileReadingPrefs._();
  static const MethodChannel _appChannel = MethodChannel('com.sogoodviewer.app');

  bool _isSepia = false;
  bool _pdfDarkInvert = true;
  bool _edgeTapPageTurn = true;
  bool _keepScreenOn = false;

  bool get isSepia => _isSepia;
  bool get pdfDarkInvert => _pdfDarkInvert;
  bool get edgeTapPageTurn => _edgeTapPageTurn;
  bool get keepScreenOn => _keepScreenOn;

  /// Warm paper Sepia filter: maps pure white (#FFFFFF) to warm paper (#F6EEDD)
  /// and softens harsh black (#000000) to espresso ink (#241E16).
  static const ColorFilter sepiaColorFilter = ColorFilter.matrix(<double>[
    0.824, 0.0,   0.0,   0.0, 36.0,
    0.0,   0.816, 0.0,   0.0, 30.0,
    0.0,   0.0,   0.780, 0.0, 22.0,
    0.0,   0.0,   0.0,   1.0,  0.0,
  ]);

  /// Smart PDF Dark Mode filter: maps blinding white (#FFFFFF) PDF pages to
  /// comfortable dark slate (#1C1C1E) and black text (#000000) to crisp silver (#E2E2E8).
  static const ColorFilter pdfDarkColorFilter = ColorFilter.matrix(<double>[
    -0.776,  0.0,    0.0,   0.0, 226.0,
     0.0,   -0.776,  0.0,   0.0, 226.0,
     0.0,    0.0,   -0.792, 0.0, 232.0,
     0.0,    0.0,    0.0,   1.0,   0.0,
  ]);

  void loadFromDisk() {
    try {
      final prefs = PreferencesService.loadSync();
      _isSepia = (prefs['mobileSepia'] as bool?) ?? false;
      _pdfDarkInvert = (prefs['mobilePdfDarkInvert'] as bool?) ?? true;
      _edgeTapPageTurn = (prefs['mobileEdgeTapPageTurn'] as bool?) ?? true;
      _keepScreenOn = (prefs['mobileKeepScreenOn'] as bool?) ?? false;
      if (_keepScreenOn) {
        _syncKeepScreenOn(true);
      }
    } catch (_) {}
  }

  @visibleForTesting
  void resetForTesting() {
    _isSepia = false;
    _pdfDarkInvert = true;
    _edgeTapPageTurn = true;
    _keepScreenOn = false;
    notifyListeners();
  }

  void setSepia(bool value) {
    if (_isSepia == value) return;
    _isSepia = value;
    PreferencesService.saveKey('mobileSepia', value);
    notifyListeners();
  }

  void setPdfDarkInvert(bool value) {
    if (_pdfDarkInvert == value) return;
    _pdfDarkInvert = value;
    PreferencesService.saveKey('mobilePdfDarkInvert', value);
    notifyListeners();
  }

  void setEdgeTapPageTurn(bool value) {
    if (_edgeTapPageTurn == value) return;
    _edgeTapPageTurn = value;
    PreferencesService.saveKey('mobileEdgeTapPageTurn', value);
    notifyListeners();
  }

  void setKeepScreenOn(bool value) {
    if (_keepScreenOn == value) return;
    _keepScreenOn = value;
    PreferencesService.saveKey('mobileKeepScreenOn', value);
    _syncKeepScreenOn(value);
    notifyListeners();
  }

  Future<void> _syncKeepScreenOn(bool enable) async {
    try {
      await _appChannel.invokeMethod('setKeepScreenOn', enable);
    } catch (_) {}
  }

  /// Resolves the active [ColorFilter] for the PDF/Markdown canvas on mobile.
  ColorFilter? resolveCanvasColorFilter({
    required bool isMobile,
    required bool isPdfDocument,
    required bool isDark,
  }) {
    if (!isMobile) return null;
    if (isDark) {
      if (isPdfDocument && _pdfDarkInvert) {
        return pdfDarkColorFilter;
      }
      return null;
    }
    if (_isSepia) {
      return sepiaColorFilter;
    }
    return null;
  }

  /// Shares the current document as a PDF using the native mobile share sheet.
  static Future<bool> shareDocumentAsPdf(ReaderController controller) async {
    final bytes = await controller.getPdfBytesForExport();
    if (bytes == null || bytes.isEmpty) return false;
    try {
      Directory tempDir;
      try {
        tempDir = await getTemporaryDirectory();
      } catch (_) {
        tempDir = Directory.systemTemp;
      }
      final shareDir = Directory(p.join(tempDir.path, 'share'))..createSync(recursive: true);
      final safeTitle = controller.documentTitle
          .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
          .replaceAll(RegExp(r'^_+|_+$'), '');
      final fileName = '${safeTitle.isEmpty ? 'document' : safeTitle}.pdf';
      final file = File(p.join(shareDir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);

      final shared = await _appChannel.invokeMethod<bool>('shareFile', {
        'path': file.path,
        'title': fileName,
        'mimeType': 'application/pdf',
      });
      return shared ?? false;
    } catch (e) {
      debugPrint('[MobileReadingPrefs] shareDocumentAsPdf failed: $e');
      return false;
    }
  }
}

