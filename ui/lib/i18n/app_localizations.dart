import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'app_strings.dart';
import 'locales.dart';
import 'strings_en.dart';
import 'strings_zh_hans.dart';
import 'strings_zh_hant.dart';

/// Flutter [LocalizationsDelegate] for [AppStrings].
class AppLocalizationsDelegate extends LocalizationsDelegate<AppStrings> {
  final String? forcedLanguage;

  const AppLocalizationsDelegate([this.forcedLanguage]);

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(AppI18n.resolve(forcedLanguage ?? 'system', locale));
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => old.forcedLanguage != forcedLanguage;
}

/// Entry point and helpers for application internationalization.
class AppI18n {
  static const AppStrings _defaultHans = ZhHansStrings();
  static const AppStrings _defaultHant = ZhHantStrings();
  static const AppStrings _defaultEn = EnStrings();

  /// Resolves the concrete [AppStrings] implementation for the given language code and locale.
  static AppStrings resolve(String languageCode, [Locale? systemLocale]) {
    final active = AppLocales.resolveActiveLanguage(languageCode, systemLocale);
    switch (active) {
      case AppLanguage.zhHans:
        return _defaultHans;
      case AppLanguage.zhHant:
        return _defaultHant;
      case AppLanguage.en:
        return _defaultEn;
      case AppLanguage.system:
        return _defaultHans;
    }
  }

  /// Convenience accessor from [BuildContext].
  /// Falls back to system resolution if not found in widget tree.
  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        resolve('system', Localizations.maybeLocaleOf(context));
  }
}

/// Extension on [BuildContext] for ergonomic string access.
extension AppLocalizationsX on BuildContext {
  AppStrings get l10n => AppI18n.of(this);
  AppStrings get strings => AppI18n.of(this);
}
