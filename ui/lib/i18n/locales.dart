import 'package:flutter/material.dart';

/// Supported application languages.
/// Note: To avoid political controversies, country/national flags are strictly NOT used.
/// Clean neutral typography and system icons are used across all UI menus.
enum AppLanguage {
  system,
  zhHans,
  zhHant,
  en;

  String get code {
    switch (this) {
      case AppLanguage.system:
        return 'system';
      case AppLanguage.zhHans:
        return 'zhHans';
      case AppLanguage.zhHant:
        return 'zhHant';
      case AppLanguage.en:
        return 'en';
    }
  }

  /// Neutral display name in native script.
  String get nativeLabel {
    switch (this) {
      case AppLanguage.system:
        return '跟随系统 / System Default';
      case AppLanguage.zhHans:
        return '简体中文';
      case AppLanguage.zhHant:
        return '繁體中文';
      case AppLanguage.en:
        return 'English';
    }
  }

  /// Neutral Material icon (no national flags).
  IconData get icon {
    switch (this) {
      case AppLanguage.system:
        return Icons.settings_suggest_rounded;
      case AppLanguage.zhHans:
      case AppLanguage.zhHant:
      case AppLanguage.en:
        return Icons.translate_rounded;
    }
  }

  /// Flutter [Locale] mapping. Returns null for [system] so Flutter follows the OS locale.
  Locale? get locale {
    switch (this) {
      case AppLanguage.system:
        return null;
      case AppLanguage.zhHans:
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');
      case AppLanguage.zhHant:
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      case AppLanguage.en:
        return const Locale('en');
    }
  }

  static AppLanguage fromCode(String? code) {
    if (code == null) return AppLanguage.system;
    for (final lang in AppLanguage.values) {
      if (lang.code == code) return lang;
    }
    // Backward-compatible fallback
    if (code == 'zh' || code == 'zh-CN' || code == 'zh_CN') return AppLanguage.zhHans;
    if (code == 'zh-TW' || code == 'zh_TW' || code == 'zh-HK' || code == 'zh_HK') return AppLanguage.zhHant;
    if (code.startsWith('en')) return AppLanguage.en;
    return AppLanguage.system;
  }
}

/// Metadata and helper utilities for locales.
class AppLocales {
  static const List<Locale> supportedLocales = [
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('zh', 'HK'),
    Locale('en'),
    Locale('en', 'US'),
    Locale('en', 'GB'),
  ];

  /// Resolves the concrete [AppLanguage] based on user setting or OS locale.
  static AppLanguage resolveActiveLanguage(String code, [Locale? systemLocale]) {
    final lang = AppLanguage.fromCode(code);
    if (lang != AppLanguage.system) return lang;

    // Resolve system locale
    final sys = systemLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
    if (sys.languageCode == 'zh') {
      if (sys.scriptCode == 'Hant' ||
          sys.countryCode == 'TW' ||
          sys.countryCode == 'HK' ||
          sys.countryCode == 'MO') {
        return AppLanguage.zhHant;
      }
      return AppLanguage.zhHans;
    }
    if (sys.languageCode == 'en') {
      return AppLanguage.en;
    }
    // Default fallback
    return AppLanguage.zhHans;
  }
}
