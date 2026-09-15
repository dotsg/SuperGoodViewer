import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/shortcut_service.dart';
import 'package:sogoodviewer/views/keyboard_shortcuts_dialog.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_shortcut_test_');
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
      expect(service.getKey('toggleTheme'), LogicalKeyboardKey.keyT);
      expect(service.getKey('toggleTwoPage'), LogicalKeyboardKey.keyD);
      expect(service.getKey('keyboardShortcuts'), LogicalKeyboardKey.comma);
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

  group('KeyboardShortcutsDialog Widget Tests', () {
    testWidgets('renders all action categories and allows key rebinding', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showKeyboardShortcutsDialog(ctx, controller),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Dialog title & top categories visible
      expect(find.text('快捷键自定义设置'), findsOneWidget);
      expect(find.text('视图模式'), findsOneWidget);
      expect(find.text('文档文件'), findsOneWidget);

      // Primary actions are present
      expect(find.text('切换版式 / 视图模式'), findsOneWidget);
      expect(find.text('全屏单页演示 (PPT)'), findsOneWidget);
      expect(find.text('查找文档内容'), findsOneWidget);
      expect(find.text('导出为出版级 PDF'), findsOneWidget);

      // Initial keys: toggleMode is M, exportPdf is P
      final modeShortcutLabel = controller.shortcutService.getShortcutLabel('toggleMode');
      expect(modeShortcutLabel, contains('M'));
      expect(find.text(modeShortcutLabel), findsWidgets);

      // Close dialog
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('快捷键自定义设置'), findsNothing);
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
          home: KeyboardShortcutsDialog(controller: controller),
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
