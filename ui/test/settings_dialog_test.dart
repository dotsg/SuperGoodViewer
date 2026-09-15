import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/document_cache_service.dart';
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

      final controller = ReaderController(autoRestorePreferences: false);
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

      // Verify General tab content (toolbar duplicate options removed)
      expect(find.text('常规与阅读偏好'), findsOneWidget);
      expect(find.text('文件修改自动热重载 (Auto Reload)'), findsOneWidget);
      expect(find.text('会话与历史记录 (Session & History)'), findsOneWidget);
      expect(find.text('最近打开文档记录'), findsOneWidget);
      expect(find.text('启动恢复上次会话'), findsOneWidget);
      expect(find.text('默认排版模式 (Default View Mode)'), findsNothing);
      expect(find.text('阅读外观主题 (Appearance Theme)'), findsNothing);
      expect(find.text('A4 页面展示偏好 (Spread Layout)'), findsNothing);

      // Switch to Typography tab
      await tester.tap(find.text('排版与字体'));
      await tester.pumpAndSettle();

      expect(find.text('字体排版与中英文等宽对齐'), findsOneWidget);
      expect(find.text('正文排版字体 (Body Typography)'), findsOneWidget);
      expect(find.text('排版基础字号 (Base Typesetting Font Size)'), findsOneWidget);
      expect(find.text('恢复默认字体'), findsOneWidget);

      // Verify Live Typography Preview card is visible
      expect(find.text('排版实时渲染预览 (Live Typography Preview)'), findsOneWidget);
      expect(find.text('实时排版预览 (Live Preview)'), findsOneWidget);
      expect(find.text('现代出版级技术文档排版 (Publisher-Grade Typography)'), findsOneWidget);
      expect(find.text('ASCII 表格全角/半角严格 1:2 等宽对齐校验'), findsOneWidget);

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

      final controller = ReaderController(autoRestorePreferences: false);
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

      final controller = ReaderController(autoRestorePreferences: false);
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

      // Controller should NOT update until Save is clicked
      expect(controller.renderOptions.fontSize, initialSize);
      expect(find.textContaining('${(initialSize + 0.5).toStringAsFixed(1)} pt'), findsWidgets);

      // Save button should apply changes to controller
      final saveBtn = find.text('保存并刷新文档');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(controller.renderOptions.fontSize, initialSize + 0.5);

      // Tap reset font size and save
      await tester.tap(find.text('恢复默认 (10.5 pt)'));
      await tester.pumpAndSettle();
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(controller.renderOptions.fontSize, 10.5);
      expect(find.textContaining('10.5 pt'), findsWidgets);
    });

    testWidgets('General tab displays compiled cache info and clears cache on button press', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('sgv_settings_cache_test_');
      DocumentCacheService.setCacheDirForTesting(tempDir);
      final dummyFile = File(p.join(tempDir.path, 'test_123.pdf'));
      dummyFile.writeAsStringSync('%PDF-1.7\n12345');

      final controller = ReaderController(autoRestorePreferences: false);
      await tester.runAsync(() async {
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
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Verify cache section elements
      expect(find.text('预编译 PDF 缓存 (Compiled Cache)'), findsOneWidget);
      expect(find.text('本地磁盘缓存'), findsOneWidget);
      expect(find.textContaining('已缓存 1 个文档'), findsOneWidget);
      expect(find.text('打开目录'), findsOneWidget);
      expect(find.text('清理缓存'), findsOneWidget);

      // Click clear cache inside runAsync so stream I/O completes
      await tester.runAsync(() async {
        await tester.tap(find.text('清理缓存'));
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Verify cache cleared
      expect(find.text('暂无缓存文件 (0 B)'), findsOneWidget);
      expect(dummyFile.existsSync(), isFalse);

      DocumentCacheService.setCacheDirForTesting(null);
      tempDir.deleteSync(recursive: true);
      controller.dispose();
    });

    testWidgets('Layout tab allows setting header slots and then clearing and saving them', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(
              controller: controller,
              initialTab: SettingsTab.layout,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially status says consistent
      expect(find.text('版式与页眉页脚与当前文档一致'), findsOneWidget);

      // Find the Header Center slot by looking for the TextField with label '中插槽' in header slots
      final centerFields = find.widgetWithText(TextField, '中插槽');
      expect(centerFields, findsNWidgets(2)); // header and footer

      // Enter header text
      await tester.enterText(centerFields.first, '{title}');
      await tester.pumpAndSettle();

      // Status changes to modified and '放弃修改' is visible
      expect(find.text('版式与页眉页脚有变动 (未保存)'), findsOneWidget);
      expect(find.text('放弃修改'), findsOneWidget);

      // Tap '保存并应用版式'
      final saveBtn = find.text('保存并应用版式');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      expect(controller.renderOptions.headerCenter, '{title}');
      expect(find.text('版式与页眉页脚与当前文档一致'), findsOneWidget);
      expect(find.text('放弃修改'), findsNothing);

      // Now test '放弃修改'
      await tester.enterText(centerFields.first, 'Temporary changed text');
      await tester.pumpAndSettle();
      expect(find.text('版式与页眉页脚有变动 (未保存)'), findsOneWidget);
      final revertBtn = find.text('放弃修改');
      expect(revertBtn, findsOneWidget);
      await tester.tap(revertBtn);
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(centerFields.first).controller?.text, '{title}');
      expect(find.text('版式与页眉页脚与当前文档一致'), findsOneWidget);

      // Tap '清空页眉' button
      final clearHeaderBtn = find.text('清空页眉');
      expect(clearHeaderBtn, findsOneWidget);
      await tester.tap(clearHeaderBtn);
      await tester.pumpAndSettle();

      expect(find.text('版式与页眉页脚有变动 (未保存)'), findsOneWidget);

      // Save again
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Header center should now be null!
      expect(controller.renderOptions.headerCenter, isNull);
      expect(find.text('版式与页眉页脚与当前文档一致'), findsOneWidget);
    });
  });
}
