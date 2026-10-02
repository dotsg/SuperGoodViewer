import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/shortcut_service.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('supergoodviewer_shortcut_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );
  });

  setUp(() {
    final testFile = File(p.join(tempTestDir.path, 'preferences.json'));
    if (testFile.existsSync()) {
      testFile.deleteSync();
    }
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('ShortcutService Unit Tests', () {
    test('default keys conform to user specifications', () {
      final service = ShortcutService();

      // Primary user requests:
      // 1. toggleMode primary key is M (Cmd+M / Ctrl+M)
      expect(service.getKey('toggleMode'), LogicalKeyboardKey.keyM);
      expect(service.getShortcutLabel('toggleMode'), contains('M'));

      // 2. togglePresentation is Shift+P (Cmd+Shift+P / Ctrl+Shift+P)
      expect(service.getKey('togglePresentation'), LogicalKeyboardKey.keyP);
      expect(service.getShortcutLabel('togglePresentation'), contains('P'));

      // 3. findInDocument is F (Cmd+F / Ctrl+F)
      expect(service.getKey('findInDocument'), LogicalKeyboardKey.keyF);
      expect(service.getShortcutLabel('findInDocument'), contains('F'));

      // 4. exportPdf primary key MUST be P (Cmd+P / Ctrl+P)
      expect(service.getKey('exportPdf'), LogicalKeyboardKey.keyP);
      expect(service.getShortcutLabel('exportPdf'), contains('P'));

      // 5. other standard keys
      expect(service.getKey('openFile'), LogicalKeyboardKey.keyO);
      expect(service.getKey('toggleSidebar'), LogicalKeyboardKey.keyB);
      expect(service.getKey('compileDocument'), LogicalKeyboardKey.keyR);
      expect(service.getKey('toggleTheme'), LogicalKeyboardKey.keyL);
      expect(service.getShortcutLabel('toggleTheme'), endsWith('Shift+L'));
      expect(service.getKey('toggleTwoPage'), LogicalKeyboardKey.keyD);
      expect(service.getKey('keyboardShortcuts'), LogicalKeyboardKey.comma);
    });

    group('zoom defaults follow each platform', () {
      tearDown(() => ShortcutService.debugIsMacLayout = null);

      test('macOS follows Preview', () {
        ShortcutService.debugIsMacLayout = true;
        final service = ShortcutService();
        expect(service.getShortcutLabel('resetZoom'), 'Cmd+0');
        expect(service.getShortcutLabel('fitPage'), 'Cmd+9');
        expect(service.getShortcutLabel('fitWidth'), 'Cmd+8');
        expect(service.getShortcutLabel('toggleTheme'), 'Cmd+Shift+L');
      });

      test('Windows and Linux follow SumatraPDF and Acrobat', () {
        ShortcutService.debugIsMacLayout = false;
        final service = ShortcutService();
        expect(service.getShortcutLabel('fitPage'), 'Ctrl+0');
        expect(service.getShortcutLabel('resetZoom'), 'Ctrl+1');
        expect(service.getShortcutLabel('fitWidth'), 'Ctrl+2');
        expect(service.getShortcutLabel('toggleTheme'), 'Ctrl+Shift+L');
      });

      test('a persisted platform default is not stored as a customization', () {
        ShortcutService.debugIsMacLayout = false;
        final service = ShortcutService()..loadFromMap({'fitWidth': '2'}, notify: false);
        expect(service.isCustomized('fitWidth'), isFalse);
      });
    });

    test('a user binding wins over a default that moved onto the same key', () {
      ShortcutService.debugIsMacLayout = false;
      addTearDown(() => ShortcutService.debugIsMacLayout = null);
      // Saved before Ctrl+2 became the fit-width default.
      final service = ShortcutService()..loadFromMap({'compileDocument': '2'}, notify: false);

      expect(service.isShadowed('fitWidth'), isTrue);
      expect(service.getShortcutLabel('fitWidth'), isEmpty);
      expect(service.findConflict('openFile', LogicalKeyboardKey.digit2), '刷新 / 重新编译');

      var compiled = 0;
      var fitted = 0;
      void noop() {}
      final bindings = service.buildBindings(
        onToggleMode: noop, onExportPdf: noop, onOpenFile: noop, onToggleSidebar: noop,
        onCompileDocument: () => compiled++, onToggleTheme: noop, onToggleTwoPage: noop,
        onZoomIn: noop, onZoomOut: noop, onResetZoom: noop, onFitWidth: () => fitted++,
        onFitPage: noop, onToggleToolbar: noop, onFontSettings: noop,
      );
      final ctrl2 = bindings.entries.where((e) {
        final activator = e.key;
        return activator is SingleActivator &&
            activator.trigger == LogicalKeyboardKey.digit2 &&
            activator.control &&
            !activator.shift;
      }).toList();
      expect(ctrl2, hasLength(1));
      ctrl2.single.value();
      expect(compiled, 1);
      expect(fitted, 0);

      // Moving the custom binding away frees the default again.
      service.resetKey('compileDocument');
      expect(service.isShadowed('fitWidth'), isFalse);
      expect(service.getShortcutLabel('fitWidth'), 'Ctrl+2');
    });

    test('rebinding, customization detection and reset work properly', () {
      final service = ShortcutService();

      expect(service.isCustomized('toggleMode'), isFalse);

      // Rebind toggleMode to Key J
      service.setKey('toggleMode', LogicalKeyboardKey.keyJ);
      expect(service.isCustomized('toggleMode'), isTrue);
      expect(service.getKey('toggleMode'), LogicalKeyboardKey.keyJ);
      expect(service.getShortcutLabel('toggleMode'), contains('J'));

      // Single action reset
      service.resetKey('toggleMode');
      expect(service.isCustomized('toggleMode'), isFalse);
      expect(service.getKey('toggleMode'), LogicalKeyboardKey.keyM);

      // Multiple customizations and resetAll
      service.setKey('toggleMode', LogicalKeyboardKey.keyJ);
      service.setKey('exportPdf', LogicalKeyboardKey.keyK);
      expect(service.isCustomized('toggleMode'), isTrue);
      expect(service.isCustomized('exportPdf'), isTrue);

      service.resetAll();
      expect(service.isCustomized('toggleMode'), isFalse);
      expect(service.isCustomized('exportPdf'), isFalse);
      expect(service.getKey('toggleMode'), LogicalKeyboardKey.keyM);
      expect(service.getKey('exportPdf'), LogicalKeyboardKey.keyP);
    });

    test('conflict detection catches duplicates among same modifier profiles', () {
      final service = ShortcutService();

      // Default toggleMode uses M. If user tries to set openFile to M:
      final conflictWithM = service.findConflict('openFile', LogicalKeyboardKey.keyM);
      expect(conflictWithM, isNotNull);
      expect(conflictWithM, '切换版式 / 视图模式');

      // findInDocument uses F. If user tries to set openFile to F:
      final conflictWithF = service.findConflict('openFile', LogicalKeyboardKey.keyF);
      expect(conflictWithF, isNotNull);
      expect(conflictWithF, '查找文档内容');

      // fontSettings uses Shift+F, so binding a non-shift key should not conflict with fontSettings
      final conflictWithSelf = service.findConflict('toggleMode', LogicalKeyboardKey.keyM);
      expect(conflictWithSelf, isNull); // Setting to its own current key is allowed
    });

    test('toMap and loadFromMap serialize correctly', () {
      final service = ShortcutService();
      service.setKey('toggleMode', LogicalKeyboardKey.keyK);
      service.setKey('exportPdf', LogicalKeyboardKey.keyE);

      final map = service.toMap();
      expect(map['toggleMode'], 'K');
      expect(map['exportPdf'], 'E');

      final newService = ShortcutService();
      newService.loadFromMap(map);
      expect(newService.getKey('toggleMode'), LogicalKeyboardKey.keyK);
      expect(newService.getKey('exportPdf'), LogicalKeyboardKey.keyE);
      expect(newService.isCustomized('toggleMode'), isTrue);
      expect(newService.isCustomized('exportPdf'), isTrue);
    });

    test('buildBindings maps shortcuts to callbacks', () {
      final service = ShortcutService();
      bool toggledMode = false;
      bool toggledPresentation = false;
      bool exported = false;

      final bindings = service.buildBindings(
        onToggleMode: () => toggledMode = true,
        onTogglePresentation: () => toggledPresentation = true,
        onExportPdf: () => exported = true,
        onOpenFile: () {},
        onToggleSidebar: () {},
        onCompileDocument: () {},
        onToggleTheme: () {},
        onToggleTwoPage: () {},
        onZoomIn: () {},
        onZoomOut: () {},
        onResetZoom: () {},
        onFitWidth: () {},
        onFitPage: () {},
        onToggleToolbar: () {},
        onFontSettings: () {},
      );

      // Find activator for keyM
      final toggleActivators = bindings.keys.where((a) {
        if (a is SingleActivator) {
          return a.trigger == LogicalKeyboardKey.keyM && !a.shift;
        }
        return false;
      });
      expect(toggleActivators, isNotEmpty);

      // Invoke callback
      bindings[toggleActivators.first]!();
      expect(toggledMode, isTrue);

      // Find activator for togglePresentation (keyP with shift)
      final presActivators = bindings.keys.where((a) {
        if (a is SingleActivator) {
          return a.trigger == LogicalKeyboardKey.keyP && a.shift;
        }
        return false;
      });
      expect(presActivators, isNotEmpty);
      bindings[presActivators.first]!();
      expect(toggledPresentation, isTrue);

      // Find activator for keyP without shift (exportPdf)
      final exportActivators = bindings.keys.where((a) {
        if (a is SingleActivator) {
          return a.trigger == LogicalKeyboardKey.keyP && !a.shift;
        }
        return false;
      });
      expect(exportActivators, isNotEmpty);

      bindings[exportActivators.first]!();
      expect(exported, isTrue);
    });
  });

  group('Settings shortcuts tab Widget Tests', () {
    testWidgets('renders all action categories and current key labels', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsDialog(controller: controller, initialTab: SettingsTab.shortcuts),
        ),
      );

      // Top categories visible
      expect(find.text('视图模式'), findsOneWidget);
      expect(find.text('文档文件'), findsOneWidget);

      // Primary actions are present
      expect(find.text('切换版式 / 视图模式'), findsOneWidget);
      expect(find.text('全屏单页演示'), findsOneWidget);
      expect(find.text('查找文档内容'), findsOneWidget);
      expect(find.text('导出为出版级 PDF'), findsOneWidget);

      // Initial keys: toggleMode is M
      final modeShortcutLabel = controller.shortcutService.getShortcutLabel('toggleMode');
      expect(modeShortcutLabel, contains('M'));
      expect(find.text(modeShortcutLabel), findsWidgets);
    });

    testWidgets('customizing a key displays modification chip and resets on button click', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      // Customize toggleMode to key G
      controller.shortcutService.setKey('toggleMode', LogicalKeyboardKey.keyG);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsDialog(controller: controller, initialTab: SettingsTab.shortcuts),
        ),
      );

      // Shows '已修改' badge for the customized item
      expect(find.text('已修改'), findsOneWidget);

      // The label reflects G
      final newLabel = controller.shortcutService.getShortcutLabel('toggleMode');
      expect(newLabel, contains('G'));
      expect(find.text(newLabel), findsOneWidget);

      // Tap single action reset button
      final resetBtn = find.byTooltip('恢复此项默认');
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Reverts back to default M
      expect(controller.shortcutService.isCustomized('toggleMode'), isFalse);
      expect(find.text('已修改'), findsNothing);
      expect(controller.shortcutService.getKey('toggleMode'), LogicalKeyboardKey.keyM);

      // Drain debounced persist timer
      await tester.pump(const Duration(milliseconds: 700));
    });
  });
}
