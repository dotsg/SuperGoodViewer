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
    tempTestDir = Directory.systemTemp.createTempSync('supergoodviewer_test_');
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

    test('demo document contains font alignment tip', () {
      final controller = ReaderController();
      expect(controller.currentMarkdown, contains('Maple Mono'));
      expect(controller.currentMarkdown, contains('关于排版对齐'));
      expect(controller.currentMarkdown, contains('https://github.com/subframe7536/maple-font'));
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

    test('sidebar position toggle updates state and clamps values', () {
      final controller = ReaderController();
      expect(controller.sidebarPosition, 'left');
      expect(controller.isSidebarOnRight, false);

      controller.setSidebarPosition('right');
      expect(controller.sidebarPosition, 'right');
      expect(controller.isSidebarOnRight, true);

      // Invalid value should be ignored
      controller.setSidebarPosition('top');
      expect(controller.sidebarPosition, 'right');

      controller.setSidebarPosition('left');
      expect(controller.sidebarPosition, 'left');
      expect(controller.isSidebarOnRight, false);

      controller.toggleSidebarPosition();
      expect(controller.sidebarPosition, 'right');
      expect(controller.isSidebarOnRight, true);

      controller.toggleSidebarPosition();
      expect(controller.sidebarPosition, 'left');
      expect(controller.isSidebarOnRight, false);
    });

    test('sidebar width controls clamp and persist properly', () {
      final controller = ReaderController();
      expect(controller.sidebarWidth, ReaderController.defaultSidebarWidth);

      controller.setSidebarWidth(350.0);
      expect(controller.sidebarWidth, 350.0);

      // Clamping minimum
      controller.setSidebarWidth(100.0);
      expect(controller.sidebarWidth, ReaderController.minSidebarWidth);

      // Clamping maximum
      controller.setSidebarWidth(900.0);
      expect(controller.sidebarWidth, ReaderController.maxSidebarWidth);
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

      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      final exportShortcut = controller.shortcutService.getShortcutLabel('exportPdf');
      expect(exportShortcut, '$mod+P');
      expect(find.byTooltip('打开本地文档 ($mod+O)'), findsOneWidget);
      expect(find.byTooltip('展开侧边栏 ($mod+B)'), findsOneWidget);
      expect(find.byTooltip('导出出版级 PDF ($exportShortcut)'), findsOneWidget);
      expect(find.byTooltip('隐藏工具栏 (Esc 或 $mod+\\)'), findsOneWidget);
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

      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      // Tap sidebar button in the floating pill toolbar
      final sidebarBtn = find.byTooltip('展开侧边栏 ($mod+B)');
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
      final closeBtn = find.byTooltip('收起侧边栏 ($mod+B 或 Esc)');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      // Sidebar is hidden again
      expect(find.byType(SidebarView), findsNothing);
      expect(controller.isSidebarOpen, isFalse);
    });

    testWidgets('renders with sidebar open initially if controller.isSidebarOpen is true', (tester) async {
      final controller = ReaderController();
      controller.setSidebarOpen(true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Sidebar should be rendered initially because preference restored it as open
      expect(find.byType(SidebarView), findsOneWidget);
      expect(find.text('大纲目录'), findsOneWidget);
    });

    testWidgets('renders with sidebar open on the right when sidebarPosition is right', (tester) async {
      final controller = ReaderController();
      controller.setSidebarPosition('right');
      controller.setSidebarOpen(true);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      expect(find.byType(SidebarView), findsOneWidget);
      expect(find.text('大纲目录'), findsOneWidget);
    });

    testWidgets('sidebar quick swap button toggles sidebar position', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      controller.setSidebarOpen(true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      expect(controller.sidebarPosition, 'left');

      // Click swap button in sidebar header
      final swapButton = find.byIcon(Icons.swap_horiz_rounded);
      expect(swapButton, findsOneWidget);
      await tester.tap(swapButton);
      await tester.pump();

      expect(controller.sidebarPosition, 'right');
      expect(controller.isSidebarOnRight, true);

      // Tap again to return to left
      await tester.tap(swapButton);
      await tester.pump();

      expect(controller.sidebarPosition, 'left');
      expect(controller.isSidebarOnRight, false);
    });

    testWidgets('sidebar resize handle resizes on drag and resets on double-tap', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      controller.setSidebarOpen(true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      expect(controller.sidebarWidth, ReaderController.defaultSidebarWidth);

      // Find the resize handle tooltip
      final handle = find.byTooltip('双击恢复默认宽度');
      expect(handle, findsOneWidget);

      // Drag right by 50px
      await tester.drag(handle, const Offset(50, 0));
      await tester.pump();

      expect(controller.sidebarWidth > ReaderController.defaultSidebarWidth, isTrue);

      // Double tap handle to reset
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handle);
      await tester.pump(const Duration(milliseconds: 700));

      expect(controller.sidebarWidth, ReaderController.defaultSidebarWidth);
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
      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      final zoomOutBtn = find.byTooltip('缩小页面 ($mod+-)');
      final zoomInBtn = find.byTooltip('放大页面 ($mod+=)');
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

      // Tap save button to apply changes to controller
      final saveBtn = find.text('保存并刷新文档');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
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

      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      // In fluid mode by default: two-page toggle and page nav pill should NOT be shown
      expect(find.byTooltip('当前为单页纵向，点击切换双页对开 ($mod+D)'), findsNothing);
      expect(find.byTooltip('点击跳转页面'), findsNothing);

      // Switch to A4 mode
      final modePill = find.text('流式');
      expect(modePill, findsOneWidget);
      await tester.tap(modePill);
      await tester.pump();

      expect(controller.renderOptions.isFluid, false);

      // Now two-page toggle and page navigation are visible
      final twoPageBtn = find.byTooltip('当前为单页纵向，点击切换双页对开 ($mod+D)');
      expect(twoPageBtn, findsOneWidget);
      expect(find.byTooltip('上一页 (← 或 [)'), findsOneWidget);
      expect(find.byTooltip('下一页 (→ 或 ])'), findsOneWidget);
      expect(find.byTooltip('点击跳转页面'), findsOneWidget);

      // Tap two-page toggle button
      await tester.tap(twoPageBtn);
      await tester.pump();

      expect(controller.isTwoPage, true);
      expect(find.byTooltip('当前为双页对开，点击切换单页 ($mod+D)'), findsOneWidget);

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
      final controller = ReaderController(autoRestorePreferences: false);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Initially at top of page, sidebar closed: titlebar is visible
      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      expect(find.byTooltip('切换侧边栏 ($mod+B)'), findsOneWidget);

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

    testWidgets('PdfCanvasView captures option changes across multi-frame async compile and distinguishes streaming updates', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final key = GlobalKey<PdfCanvasViewState>();
      final bytesA = Uint8List.fromList([1, 2, 3, 4]);
      final bytesB = Uint8List.fromList([5, 6, 7, 8]);
      final bytesC = Uint8List.fromList([9, 10, 11, 12]);

      const optInitial = RenderOptions(fontSize: 12.0);
      const optModified = RenderOptions(fontSize: 14.0);

      // Frame 0: Initial mount
      await tester.pumpWidget(
        MaterialApp(
          home: PdfCanvasView(
            key: key,
            pdfBytes: bytesA,
            documentTitle: 'Doc',
            renderOptions: optInitial,
            isTwoPage: false,
            controller: controller,
          ),
        ),
      );
      expect(key.currentState?.renderOptionsChanged, false);

      // Frame A: User changes font size -> rebuilds with new options, but bytes are still bytesA (compiling in background)
      await tester.pumpWidget(
        MaterialApp(
          home: PdfCanvasView(
            key: key,
            pdfBytes: bytesA,
            documentTitle: 'Doc',
            renderOptions: optModified,
            isTwoPage: false,
            controller: controller,
          ),
        ),
      );
      // optionsChanged must be true even though bytes did not change in this frame!
      expect(key.currentState?.renderOptionsChanged, true);

      // Frame B: Background compile completes -> new bytes arrive with optModified
      await tester.pumpWidget(
        MaterialApp(
          home: PdfCanvasView(
            key: key,
            pdfBytes: bytesB,
            documentTitle: 'Doc',
            renderOptions: optModified,
            isTwoPage: false,
            controller: controller,
          ),
        ),
      );
      // _renderOptionsChanged must remain sticky so restoration uses ratio!
      expect(key.currentState?.renderOptionsChanged, true);

      // Simulate scroll restore having run on ready controller (clearing sticky flag)
      key.currentState?.restoreScrollForTesting();

      // Frame C: Streaming append -> new bytesC arrive with UNCHANGED options
      await tester.pumpWidget(
        MaterialApp(
          home: PdfCanvasView(
            key: key,
            pdfBytes: bytesC,
            documentTitle: 'Doc',
            renderOptions: optModified,
            isTwoPage: false,
            controller: controller,
          ),
        ),
      );
      // Pure streaming append must NOT trigger renderOptionsChanged (uses absolute offset)!
      expect(key.currentState?.renderOptionsChanged, false);
    });

    test('ReaderController flags renderOptionsChanged across options including twoPage and preserves top scroll', () {
      final controller = ReaderController(autoRestorePreferences: false);
      expect(controller.renderOptionsChanged, false);

      // 1. Changing options sets renderOptionsChanged flag
      controller.setFontSize(16.0);
      expect(controller.renderOptionsChanged, true);
      controller.renderOptionsChanged = false;

      controller.toggleTheme();
      expect(controller.renderOptionsChanged, true);
      controller.renderOptionsChanged = false;

      controller.toggleMode();
      expect(controller.renderOptionsChanged, true);
      controller.renderOptionsChanged = false;

      controller.toggleTwoPage();
      expect(controller.renderOptionsChanged, true);
      controller.renderOptionsChanged = false;

      controller.setTwoPage(false);
      expect(controller.renderOptionsChanged, true);
      controller.renderOptionsChanged = false;

      // 2. User scroll to top during streaming (when reloading) is faithfully preserved
      controller.updateScrollRatio(0.45, offset: 500.0);
      expect(controller.lastScrollRatio, 0.45);
      expect(controller.lastScrollOffset, 500.0);

      controller.startReloading();
      expect(controller.isReloading, true);

      // User scrolls back to top during streaming: must NOT be discarded
      controller.updateScrollRatio(0.0, offset: 0.0);
      expect(controller.lastScrollRatio, 0.0);
      expect(controller.lastScrollOffset, 0.0);

      controller.finishReloading();
      controller.dispose();
    });

    test('calculateFluidTargetScrollY honors useOffset and clamps properly', () {
      final controller = ReaderController(autoRestorePreferences: false);
      controller.updateScrollRatio(0.5, offset: 400.0);

      // docHeight <= 0 returns 0.0
      expect(controller.calculateFluidTargetScrollY(0.0, useOffset: true), 0.0);
      expect(controller.calculateFluidTargetScrollY(-10.0, useOffset: false), 0.0);

      // useOffset: true -> returns _lastScrollOffset (400.0)
      expect(controller.calculateFluidTargetScrollY(2000.0, useOffset: true), 400.0);
      // with maxScroll clamping
      expect(controller.calculateFluidTargetScrollY(2000.0, useOffset: true, maxScroll: 300.0), 300.0);

      // useOffset: false -> calculates ratio * docHeight (0.5 * 2000.0 = 1000.0)
      expect(controller.calculateFluidTargetScrollY(2000.0, useOffset: false), 1000.0);
      expect(controller.calculateFluidTargetScrollY(2000.0, useOffset: false, maxScroll: 800.0), 800.0);

      controller.dispose();
    });

    testWidgets('PdfCanvasView _isRestoringScroll is governed by generation gating', (tester) async {
      final key = GlobalKey<PdfCanvasViewState>();
      final controller = ReaderController(autoRestorePreferences: false);
      final bytesA = Uint8List.fromList([1, 2, 3, 4]);

      await tester.pumpWidget(
        MaterialApp(
          home: PdfCanvasView(
            key: key,
            pdfBytes: bytesA,
            documentTitle: 'Doc',
            renderOptions: const RenderOptions(),
            isTwoPage: false,
            controller: controller,
          ),
        ),
      );

      final state = key.currentState;
      expect(state, isNotNull);

      // On initial mount before restore completes, isRestoringScroll is true
      expect(state!.isRestoringScroll, true);

      // Restore scroll completes
      state.restoreScrollForTesting();
      expect(state.isRestoringScroll, false);

      // Trigger a new mount generation
      state.setRestoringScrollForTesting(true);
      expect(state.isRestoringScroll, true);

      state.restoreScrollForTesting();
      expect(state.isRestoringScroll, false);

      controller.dispose();
    });

    testWidgets('WorkspaceView initializes titlebar as visible when at top in fluid mode and hidden when scrolled past top', (tester) async {
      // 1. Controller at top (offset: 0.0) -> titlebar visible
      final controllerTop = ReaderController(autoRestorePreferences: false);
      controllerTop.updateScrollRatio(0.0, offset: 0.0);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(key: const ValueKey('top'), controller: controllerTop),
        ),
      );

      final titleBarVisible = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer && widget.constraints?.maxHeight == 32.0,
      );
      expect(titleBarVisible, findsOneWidget);
      controllerTop.dispose();

      // 2. Controller scrolled down in fluid mode (offset: 150.0) -> titlebar initialized hidden
      final controllerScrolled = ReaderController(autoRestorePreferences: false);
      controllerScrolled.updateScrollRatio(0.1, offset: 150.0);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(key: const ValueKey('scrolled'), controller: controllerScrolled),
        ),
      );

      final titleBarHidden = find.byWidgetPredicate(
        (widget) => widget is AnimatedContainer && widget.constraints?.maxHeight == 0.0,
      );
      expect(titleBarHidden, findsOneWidget);
      controllerScrolled.dispose();
    });
  });
}

