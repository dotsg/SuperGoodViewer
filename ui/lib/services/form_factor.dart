import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../bridge/native_engine.dart';
import 'document_cache_service.dart';
import 'preferences_service.dart';
import 'remote_image_service.dart';

/// FormFactor helper separating platform interaction paradigm (Mobile vs Desktop)
/// from viewport geometry (Compact vs Wide).
class FormFactor {
  /// Test-only override for mobile platform simulation.
  @visibleForTesting
  static bool? debugOverrideIsMobile;

  /// Initializes sandboxed mobile application directories on Android / iOS.
  static Future<void> initMobileDirectoriesIfNeeded() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      PreferencesService.setAppSupportDir(appSupportDir);
      final cacheDir = await getTemporaryDirectory();
      DocumentCacheService.setAppCacheDir(cacheDir);
      RemoteImageService.setAppRemoteImageCacheDir(cacheDir);
      NativeEngine.instance.setCacheDir(appSupportDir.path);
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
