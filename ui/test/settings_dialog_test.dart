import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.sogoodviewer.app');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'checkCliStatus') {
        return {
          'isInstalled': false,
          'path': '/usr/local/bin/sgv',
          'target': '',
          'isCurrentApp': false,
        };
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SettingsDialog Widget Tests', () {
    testWidgets('renders general tab by default and switches between tabs', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showSettingsDialog(ctx, controller),
                child: const Text('Open Settings'),
              ),
            ),
          ),
        ),
      );

      // Open Settings dialog
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();

      // Verify header and navigation sidebar items
      expect(find.text('偏好设置'), findsWidgets);
      expect(find.text('常规阅读'), findsOneWidget);
      expect(find.text('排版与字体'), findsOneWidget);
      expect(find.text('快捷键'), findsOneWidget);
      expect(find.text('命令行 (sgv)'), findsOneWidget);
      expect(find.text('关于软件'), findsOneWidget);

      // Verify General tab content
      expect(find.text('常规与阅读偏好'), findsOneWidget);
      expect(find.text('默认排版模式 (Default View Mode)'), findsOneWidget);
      expect(find.text('自适应流式 (Fluid)'), findsOneWidget);
      expect(find.text('A4 出版模式 (Paged)'), findsOneWidget);
      expect(find.text('文件修改自动热重载 (Auto Reload)'), findsOneWidget);

      // Switch to Typography tab
      await tester.tap(find.text('排版与字体'));
      await tester.pumpAndSettle();

      expect(find.text('字体排版与中英文等宽对齐'), findsOneWidget);
      expect(find.text('正文排版字体 (Body Typography)'), findsOneWidget);
      expect(find.text('排版基础字号 (Base Typesetting Font Size)'), findsOneWidget);
      expect(find.text('恢复默认字体'), findsOneWidget);

      // Switch to Shortcuts tab
      await tester.tap(find.text('快捷键'));
      await tester.pumpAndSettle();

      expect(find.text('快捷键自定义设置'), findsOneWidget);
      expect(find.text('视图模式'), findsOneWidget);
      expect(find.text('恢复全部默认快捷键'), findsOneWidget);

      // Switch to CLI tab
      await tester.tap(find.text('命令行 (sgv)'));
      await tester.pumpAndSettle();

      expect(find.text('命令行工具 (sgv) 集成'), findsOneWidget);

      // Switch to About tab
      await tester.tap(find.text('关于软件'));
      await tester.pumpAndSettle();

      expect(find.text('关于 SuperGoodViewer'), findsOneWidget);
      expect(find.text('载入精选排版样例 (Sample Document)'), findsOneWidget);
      expect(find.text('载入体验'), findsOneWidget);

      // Close dialog
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      expect(find.text('关于 SuperGoodViewer'), findsNothing);
    });

    testWidgets('opens directly with initialTab set to typography or cli', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showSettingsDialog(
                  ctx,
                  controller,
                  initialTab: SettingsTab.typography,
                ),
                child: const Text('Open Typography'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Typography'));
      await tester.pumpAndSettle();

      expect(find.text('字体排版与中英文等宽对齐'), findsOneWidget);
      expect(find.text('正文排版字体 (Body Typography)'), findsOneWidget);
    });

    testWidgets('toggling auto reload and font size in SettingsDialog updates controller', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsDialog(
            controller: controller,
            initialTab: SettingsTab.general,
          ),
        ),
      );

      // Toggle auto reload switch
      final initialReload = controller.autoReload;
      final reloadSwitch = find.byType(Switch);
      expect(reloadSwitch, findsOneWidget);
      await tester.tap(reloadSwitch);
      await tester.pumpAndSettle();

      expect(controller.autoReload, !initialReload);

      // Switch to typography tab and increase font size
      await tester.tap(find.text('排版与字体'));
      await tester.pumpAndSettle();

      final initialSize = controller.renderOptions.fontSize;
      final addBtn = find.byTooltip('放大字号');
      expect(addBtn, findsOneWidget);
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(controller.renderOptions.fontSize, initialSize + 0.5);

      // Tap reset font size
      await tester.tap(find.text('恢复默认 (10.5 pt)'));
      await tester.pumpAndSettle();
      expect(controller.renderOptions.fontSize, 10.5);
    });
  });
}
