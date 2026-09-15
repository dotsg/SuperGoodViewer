import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/i18n/app_localizations.dart';
import 'package:sogoodviewer/i18n/locales.dart';
import 'package:sogoodviewer/i18n/strings_en.dart';
import 'package:sogoodviewer/i18n/strings_zh_hans.dart';
import 'package:sogoodviewer/i18n/strings_zh_hant.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLanguage and Locales Tests', () {
    test('AppLanguage codes and fromCode parsing', () {
      expect(AppLanguage.system.code, 'system');
      expect(AppLanguage.zhHans.code, 'zhHans');
      expect(AppLanguage.zhHant.code, 'zhHant');
      expect(AppLanguage.en.code, 'en');

      expect(AppLanguage.fromCode('system'), AppLanguage.system);
      expect(AppLanguage.fromCode('zhHans'), AppLanguage.zhHans);
      expect(AppLanguage.fromCode('zhHant'), AppLanguage.zhHant);
      expect(AppLanguage.fromCode('en'), AppLanguage.en);

      // Backward compatible / fuzzy codes
      expect(AppLanguage.fromCode('zh'), AppLanguage.zhHans);
      expect(AppLanguage.fromCode('zh-CN'), AppLanguage.zhHans);
      expect(AppLanguage.fromCode('zh_CN'), AppLanguage.zhHans);
      expect(AppLanguage.fromCode('zh-TW'), AppLanguage.zhHant);
      expect(AppLanguage.fromCode('zh_HK'), AppLanguage.zhHant);
      expect(AppLanguage.fromCode('en-US'), AppLanguage.en);
      expect(AppLanguage.fromCode(null), AppLanguage.system);
      expect(AppLanguage.fromCode('unknown'), AppLanguage.system);
    });

    test('Strict neutrality: No country/national flags in language definitions', () {
      final flagRegex = RegExp(r'[\uD83C][\uDDE6-\uDDFF]{2}');
      for (final lang in AppLanguage.values) {
        // Assert no country flag emoji exists in nativeLabel
        expect(
          flagRegex.hasMatch(lang.nativeLabel),
          isFalse,
          reason: '${lang.name} must NOT use any national flag emoji to maintain political neutrality',
        );

        // Assert strictly neutral material icons are used
        expect(
          lang.icon == Icons.settings_suggest_rounded || lang.icon == Icons.translate_rounded,
          isTrue,
          reason: '${lang.name} icon must be neutral (translate or settings_suggest)',
        );
      }
    });

    test('AppLocales.resolveActiveLanguage resolves correctly for explicit and system locales', () {
      // Explicit language selection
      expect(AppLocales.resolveActiveLanguage('zhHans'), AppLanguage.zhHans);
      expect(AppLocales.resolveActiveLanguage('zhHant'), AppLanguage.zhHant);
      expect(AppLocales.resolveActiveLanguage('en'), AppLanguage.en);

      // System resolution
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('zh', 'CN')),
        AppLanguage.zhHans,
      );
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('zh', 'TW')),
        AppLanguage.zhHant,
      );
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('zh', 'HK')),
        AppLanguage.zhHant,
      );
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
        AppLanguage.zhHant,
      );
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('en', 'US')),
        AppLanguage.en,
      );
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('en', 'GB')),
        AppLanguage.en,
      );
      // Fallback for unlisted locale
      expect(
        AppLocales.resolveActiveLanguage('system', const Locale('de', 'DE')),
        AppLanguage.zhHans,
      );
    });
  });

  group('String Bundles Content and Parity Tests', () {
    test('AppI18n.resolve returns correct string bundle', () {
      final hans = AppI18n.resolve('zhHans');
      final hant = AppI18n.resolve('zhHant');
      final en = AppI18n.resolve('en');

      expect(hans, isA<ZhHansStrings>());
      expect(hant, isA<ZhHantStrings>());
      expect(en, isA<EnStrings>());

      // Verify Chinese Simplified vs Traditional vs English terms
      expect(hans.appTitle, '超好读');
      expect(hant.appTitle, '超好讀');
      expect(en.appTitle, 'SuperGoodViewer');

      expect(hans.openDocument, '打开本地文档');
      expect(hant.openDocument, '開啟本機檔案');
      expect(en.openDocument, 'Open Document');

      expect(hans.settingsTitle, '偏好设置');
      expect(hant.settingsTitle, '偏好設定');
      expect(en.settingsTitle, 'Preferences');

      expect(hans.sidebarTabOutline, '大纲目录');
      expect(hant.sidebarTabOutline, '大綱目錄');
      expect(en.sidebarTabOutline, 'Outline');

      expect(hans.sidebarTabRecent, '最近文件');
      expect(hant.sidebarTabRecent, '最近檔案');
      expect(en.sidebarTabRecent, 'Recent');
    });

    test('Parameterized strings work properly across languages', () {
      final hans = AppI18n.resolve('zhHans');
      final hant = AppI18n.resolve('zhHant');
      final en = AppI18n.resolve('en');

      expect(hans.matchCount(3, 10), '3 / 10');
      expect(hant.matchCount(3, 10), '3 / 10');
      expect(en.matchCount(3, 10), '3 / 10');

      expect(hans.pageNumberBadge(5), 'P5');
      expect(hant.pageNumberBadge(5), 'P5');
      expect(en.pageNumberBadge(5), 'P5');

      expect(hans.cacheCleared('1.2 MB'), '成功清理缓存，释放了 1.2 MB 磁盘空间');
      expect(hant.cacheCleared('1.2 MB'), '成功清理快取，釋放了 1.2 MB 磁碟空間');
      expect(en.cacheCleared('1.2 MB'), 'Cache cleared successfully, freed 1.2 MB disk space.');
    });
  });

  group('ReaderController I18n Integration Tests', () {
    test('setLanguage switches language and notifies listeners', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      int notifyCount = 0;
      controller.addListener(() => notifyCount++);

      expect(controller.language, 'zhHans');
      expect(controller.strings, isA<ZhHansStrings>());
      expect(controller.currentLocale, const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'));

      // Switch to English
      controller.setLanguage('en');
      expect(controller.language, 'en');
      expect(controller.strings, isA<EnStrings>());
      expect(controller.currentLocale, const Locale('en'));
      expect(notifyCount, 1);

      // Switch to Traditional Chinese
      controller.setLanguage('zhHant');
      expect(controller.language, 'zhHant');
      expect(controller.strings, isA<ZhHantStrings>());
      expect(controller.currentLocale, const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
      expect(notifyCount, 2);

      // Switch to System
      controller.setLanguage('system');
      expect(controller.language, 'system');
      expect(controller.currentLocale, isNull);
      expect(notifyCount, 3);
    });
  });

  group('SettingsDialog Language Switching Widget Tests', () {
    testWidgets('Displays neutral language selector and switches UI language interactively', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              controller: controller,
              initialTab: SettingsTab.general,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial state is Simplified Chinese
      expect(find.text('常规阅读'), findsWidgets);
      expect(find.text('偏好设置'), findsOneWidget);
      expect(find.text('界面语言'), findsWidgets);

      // Verify no country flag emojis are rendered anywhere in the dialog
      final allTextWidgets = tester.widgetList<Text>(find.byType(Text));
      final flagRegex = RegExp(r'[\uD83C][\uDDE6-\uDDFF]{2}');
      for (final text in allTextWidgets) {
        final content = text.data ?? text.textSpan?.toPlainText() ?? '';
        expect(
          flagRegex.hasMatch(content),
          isFalse,
          reason: 'UI text "$content" contains a country flag, violating neutrality constraint',
        );
      }

      // Open the language dropdown
      final dropdown = find.byType(DropdownButton<String>);
      expect(dropdown, findsOneWidget);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Tap "English" option
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      // Verify controller updated to English
      expect(controller.language, 'en');

      // Verify dialog labels immediately switched to English
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('General'), findsWidgets);
      expect(find.text('Display Language'), findsWidgets);
    });
  });
}
