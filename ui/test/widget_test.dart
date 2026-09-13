import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';
import 'package:sogoodviewer/views/sidebar_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_test_');
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
    if (tempTestDir.existsSync()) {
      tempTestDir.deleteSync(recursive: true);
    }
  });

  group('RenderOptions Tests', () {
    test('default options are fluid and light', () {
      const options = RenderOptions();
      expect(options.mode, 'fluid');
      expect(options.theme, 'light');
      expect(options.isFluid, true);
      expect(options.isDark, false);
      expect(options.viewportWidth, 850.0);
      expect(options.fontSize, 10.5);
    });

    test('copyWith works correctly', () {
      const options = RenderOptions();
      final updated = options.copyWith(
        mode: 'paged',
        theme: 'dark',
        fontSize: 12.0,
      );
      expect(updated.mode, 'paged');
      expect(updated.theme, 'dark');
      expect(updated.isFluid, false);
      expect(updated.isDark, true);
      expect(updated.fontSize, 12.0);
      expect(updated.viewportWidth, 850.0);
    });

    test('toJsonString produces valid JSON', () {
      const options = RenderOptions(
        mode: 'paged',
        theme: 'dark',
        viewportWidth: 700.0,
        fontSize: 11.5,
      );
      final json = options.toJsonString();
      expect(json, contains('"mode":"paged"'));
      expect(json, contains('"theme":"dark"'));
      expect(json, contains('"viewport_width":700.0'));
      expect(json, contains('"font_size":11.5'));
    });

    test('toJsonString includes bodyFont and codeFont when specified', () {
      const options = RenderOptions(
        bodyFont: 'PingFang SC',
        codeFont: 'Maple Mono CN',
      );
      final json = options.toJsonString();
      expect(json, contains('"body_font":"PingFang SC"'));
      expect(json, contains('"code_font":"Maple Mono CN"'));
    });
  });

  group('ReaderController State Tests', () {
    test('initializes with demo document', () {
      final controller = ReaderController();
      expect(controller.documentTitle, 'SuperGoodViewer Demo');
      expect(controller.currentMarkdown, isNotEmpty);
      expect(controller.renderOptions.isFluid, true);
      expect(controller.renderOptions.isDark, false);
    });

    test('toggles mode and theme', () {
      final controller = ReaderController();
      controller.toggleMode();
      expect(controller.renderOptions.mode, 'paged');
      controller.toggleMode();
      expect(controller.renderOptions.mode, 'fluid');

      controller.toggleTheme();
      expect(controller.renderOptions.theme, 'dark');
      controller.toggleTheme();
      expect(controller.renderOptions.theme, 'light');
    });

    test('updates scroll ratio correctly within [0.0, 1.0]', () {
      final controller = ReaderController();
      controller.updateScrollRatio(0.45);
      expect(controller.lastScrollRatio, 0.45);

      // Out of bounds values should be ignored
      controller.updateScrollRatio(1.5);
      expect(controller.lastScrollRatio, 0.45);
    });

    test('font size adjustment clamped between 8.0 and 24.0', () {
      final controller = ReaderController();
      controller.setFontSize(14.0);
      expect(controller.renderOptions.fontSize, 14.0);

      // Clamping low
      controller.setFontSize(4.0);
      expect(controller.renderOptions.fontSize, 8.0);

      // Clamping high
      controller.setFontSize(30.0);
      expect(controller.renderOptions.fontSize, 24.0);
    });

    test('auto-reload toggle updates state', () {
      final controller = ReaderController();
      expect(controller.autoReload, true);
      controller.setAutoReload(false);
      expect(controller.autoReload, false);
      controller.setAutoReload(true);
      expect(controller.autoReload, true);
    });

    test('openFile with non-existent path records error message', () async {
      final controller = ReaderController();
      await controller.openFile('/non/existent/file.md');
      expect(controller.errorMessage, contains('File not found'));
    });

    test('openFile with valid file updates markdown, title, and recent files', () async {
      final controller = ReaderController();
      await controller.openFile('../README.md');
      expect(controller.errorMessage, isNull);
      expect(controller.documentTitle, 'README');
      expect(controller.currentFilePath, contains('README.md'));
      expect(controller.recentFiles, contains(contains('README.md')));
      expect(controller.currentMarkdown.isNotEmpty, true);
    });

    test('initialFilePath in constructor loads file immediately', () async {
      final controller = ReaderController(initialFilePath: '../README.md');
      // Wait for openFile to complete
      await Future.delayed(const Duration(milliseconds: 100));
      expect(controller.documentTitle, 'README');
      expect(controller.currentMarkdown.isNotEmpty, true);
    });

    test('exportPdf fails gracefully when currentPdfBytes is null', () async {
      final controller = ReaderController();
      // Before compilation completes or if bytes null
      final success = await controller.exportPdf('/tmp/test.pdf');
      // If null, should return false without crashing
      if (controller.currentPdfBytes == null) {
        expect(success, false);
      }
    });

    test('two-page mode toggle updates state', () {
      final controller = ReaderController();
      expect(controller.isTwoPage, false);
      controller.toggleTwoPage();
      expect(controller.isTwoPage, true);
      controller.toggleTwoPage();
      expect(controller.isTwoPage, false);
      controller.setTwoPage(true);
      expect(controller.isTwoPage, true);
      controller.setTwoPage(false);
      expect(controller.isTwoPage, false);
    });

    test('outline items are extracted correctly from markdown', () {
      final controller = ReaderController(autoRestorePreferences: false);
      expect(controller.outlineItems.isNotEmpty, true);
      // Demo document headings
      expect(controller.outlineItems.any((item) => item.title.contains('高精度数学排版')), true);
      expect(controller.outlineItems.any((item) => item.title.contains('Mermaid')), true);
      final first = controller.outlineItems.first;
      controller.jumpToOutline(first);
      expect(controller.requestedJumpItem, first);
      controller.clearJumpRequest();
      expect(controller.requestedJumpItem, null);
    });

    test('reloading flag and scroll position are preserved on theme and mode toggle', () {
      final controller = ReaderController(autoRestorePreferences: false);
      controller.updateScrollRatio(0.68);
      controller.updatePageNumber(4);
      expect(controller.lastScrollRatio, 0.68);
      expect(controller.lastPageNumber, 4);

      // Toggle theme
      controller.toggleTheme();
      expect(controller.isReloading, true);
      // While reloading, transient 0.0 updates are ignored
      controller.updateScrollRatio(0.0);
      controller.updatePageNumber(1);
      expect(controller.lastScrollRatio, 0.68);
      expect(controller.lastPageNumber, 4);

      // Finish reloading
      controller.finishReloading();
      expect(controller.isReloading, false);
    });

    test('PreferencesService saves and loads key-values', () async {
      await PreferencesService.saveKey('test_key', 'test_value');
      final prefs = await PreferencesService.load();
      expect(prefs['test_key'], 'test_value');
    });
  });

  group('WorkspaceView Widget Tests', () {
    testWidgets('renders in Zen mode with sidebar closed by default', (tester) async {
      final controller = ReaderController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Sidebar should NOT be rendered by default (pure Zen reading mode)
      expect(find.byType(SidebarView), findsNothing);

      // Document title should be displayed in the floating pill
      expect(find.text('SuperGoodViewer Demo'), findsOneWidget);

      // Check floating pill action buttons
      final exportShortcut = controller.shortcutService.getShortcutLabel('exportPdf');
      expect(exportShortcut, 'Cmd+P');
      expect(find.byTooltip('打开本地 Markdown (Cmd+O)'), findsOneWidget);
      expect(find.byTooltip('展开侧边栏 (Cmd+B)'), findsOneWidget);
      expect(find.byTooltip('导出出版级 PDF ($exportShortcut)'), findsOneWidget);
      expect(find.byTooltip('隐藏工具栏 (Esc 或 Cmd+\\)'), findsOneWidget);
    });

    testWidgets('sidebar can be opened and closed interactively', (tester) async {
      final controller = ReaderController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      expect(find.byType(SidebarView), findsNothing);

      // Tap sidebar button in the floating pill toolbar
      final sidebarBtn = find.byTooltip('展开侧边栏 (Cmd+B)');
      expect(sidebarBtn, findsOneWidget);
      await tester.tap(sidebarBtn);
      await tester.pump();

      // Sidebar is now mounted and visible
      expect(find.byType(SidebarView), findsOneWidget);
      expect(find.text('大纲目录'), findsOneWidget);

      // Verify compact macOS-style footer bar items
      expect(find.text('偏好设置'), findsOneWidget);

      // Switch to Recents tab
      await tester.tap(find.text('最近文件'));
      await tester.pump();
      expect(find.text('暂无历史文件'), findsOneWidget);

      // Close sidebar via header close button
      final closeBtn = find.byTooltip('收起侧边栏 (Cmd+B 或 Esc)');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      // Sidebar is hidden again
      expect(find.byType(SidebarView), findsNothing);
    });

    testWidgets('mode and page zoom controls render and trigger actions', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      expect(controller.renderOptions.isFluid, true);

      // Tap mode toggle pill
      final modePill = find.text('流式');
      expect(modePill, findsOneWidget);
      await tester.tap(modePill);
      await tester.pump();

      expect(controller.renderOptions.isFluid, false);
      expect(find.text('A4'), findsOneWidget);

      // Page zoom buttons & badge exist
      final zoomOutBtn = find.byTooltip('缩小页面 (Cmd+-)');
      final zoomInBtn = find.byTooltip('放大页面 (Cmd+=)');
      final zoomBadge = find.byTooltip('页面缩放比例与预设');

      expect(zoomOutBtn, findsOneWidget);
      expect(zoomInBtn, findsOneWidget);
      expect(zoomBadge, findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      // Tap zoom in button
      await tester.tap(zoomInBtn);
      await tester.pump(const Duration(milliseconds: 300));

      // Open zoom preset dropdown
      await tester.tap(zoomBadge);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('满窗口 (适应宽度)'), findsOneWidget);
      expect(find.text('满屏 (适应整页)'), findsOneWidget);
      expect(find.text('全屏沉浸浏览'), findsOneWidget);
      expect(find.text('100% (原始大小)'), findsOneWidget);
      expect(find.text('150%'), findsOneWidget);

      // Tap '满窗口 (适应宽度)' preset from popup menu
      await tester.tap(find.text('满窗口 (适应宽度)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.autoFitMode, equals(AutoFitMode.fitWidth));

      await tester.pump(const Duration(seconds: 1));
      controller.dispose();
    });

    testWidgets('font settings button opens font dialog with CJK status and font size adjustments', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Open unified settings dialog via "偏好设置" button in bottom floating pill
      final prefShortcut = controller.shortcutService.getShortcutLabel('preferences');
      final settingsBtn = find.byTooltip('偏好设置 ($prefShortcut)');
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Switch to typography tab
      final typoTab = find.text('排版与字体');
      expect(typoTab, findsOneWidget);
      await tester.tap(typoTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('字体排版与中英文等宽对齐'), findsOneWidget);
      expect(find.text('正文排版字体 (Body Typography)'), findsOneWidget);
      expect(find.text('排版基础字号 (Base Typesetting Font Size)'), findsOneWidget);
      expect(find.text('恢复默认 (10.5 pt)'), findsOneWidget);
      expect(find.text('恢复默认字体'), findsOneWidget);

      // Adjust font size in dialog
      final initialFontSize = controller.renderOptions.fontSize;
      final addFontSizeBtn = find.byTooltip('放大字号');
      expect(addFontSizeBtn, findsOneWidget);
      await tester.tap(addFontSizeBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(controller.renderOptions.fontSize, initialFontSize + 0.5);

      // Close dialog via top close button
      final closeBtn = find.byTooltip('关闭');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('字体排版与中英文等宽对齐'), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      controller.dispose();
    });

    testWidgets('A4 mode displays two-page spread toggle and page navigation controls', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // In fluid mode by default: two-page toggle and page nav pill should NOT be shown
      expect(find.byTooltip('当前为单页纵向，点击切换双页对开 (Cmd+D)'), findsNothing);
      expect(find.byTooltip('点击跳转页面'), findsNothing);

      // Switch to A4 mode
      final modePill = find.text('流式');
      expect(modePill, findsOneWidget);
      await tester.tap(modePill);
      await tester.pump();

      expect(controller.renderOptions.isFluid, false);

      // Now two-page toggle and page navigation are visible
      final twoPageBtn = find.byTooltip('当前为单页纵向，点击切换双页对开 (Cmd+D)');
      expect(twoPageBtn, findsOneWidget);
      expect(find.byTooltip('上一页 (← 或 [)'), findsOneWidget);
      expect(find.byTooltip('下一页 (→ 或 ])'), findsOneWidget);
      expect(find.byTooltip('点击跳转页面'), findsOneWidget);

      // Tap two-page toggle button
      await tester.tap(twoPageBtn);
      await tester.pump();

      expect(controller.isTwoPage, true);
      expect(find.byTooltip('当前为双页对开，点击切换单页 (Cmd+D)'), findsOneWidget);

      // Tap jump page badge to open jump dialog
      final jumpBadge = find.byTooltip('点击跳转页面');
      await tester.tap(jumpBadge);
      await tester.pump();

      expect(find.text('跳转到页面'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.text('跳转'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text('取消'));
      await tester.pump();

      expect(find.text('跳转到页面'), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      controller.dispose();
    });

    testWidgets('titlebar auto-hides on scroll down and shows at page top', (tester) async {
      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Initially at top of page, sidebar closed: titlebar is visible
      expect(find.byTooltip('切换侧边栏 (Cmd+B)'), findsOneWidget);

      final pdfCanvasFinder = find.byType(PdfCanvasView);
      expect(pdfCanvasFinder, findsOneWidget);
      final pdfCanvas = tester.widget<PdfCanvasView>(pdfCanvasFinder);

      // Simulate scrolling down
      pdfCanvas.onScrollChanged?.call(deltaY: 50.0, isAtTop: false);
      await tester.pump(const Duration(milliseconds: 250));

      // Titlebar has animated to height 0 (hidden)
      final titleBarContainer = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer && widget.constraints?.maxHeight == 0.0,
      );
      expect(titleBarContainer, findsOneWidget);

      // Simulate scrolling back to top
      pdfCanvas.onScrollChanged?.call(deltaY: -20.0, isAtTop: true);
      await tester.pump(const Duration(milliseconds: 250));

      // Titlebar has animated back to height 32 (shown)
      final titleBarVisible = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer && widget.constraints?.maxHeight == 32.0,
      );
      expect(titleBarVisible, findsOneWidget);

      // Now open sidebar: titlebar should remain visible even when scrolling down
      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(SidebarView), findsOneWidget);

      // Scroll down while sidebar is open
      pdfCanvas.onScrollChanged?.call(deltaY: 100.0, isAtTop: false);
      await tester.pump(const Duration(milliseconds: 250));

      // Titlebar is STILL visible (height 32)
      final titleBarStillVisible = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer && widget.constraints?.maxHeight == 32.0,
      );
      expect(titleBarStillVisible, findsOneWidget);

      controller.dispose();
    });
  });
}

