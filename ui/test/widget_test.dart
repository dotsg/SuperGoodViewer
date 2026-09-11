import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/views/sidebar_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
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
      expect(controller.documentTitle, 'SoGoodViewer Demo');
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
  });

  group('WorkspaceView Widget Tests', () {
    testWidgets('renders in Zen mode with sidebar closed by default', (tester) async {
      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      // Sidebar should NOT be rendered by default (pure Zen reading mode)
      expect(find.byType(SidebarView), findsNothing);

      // Document title should be displayed in the floating pill
      expect(find.text('SoGoodViewer Demo'), findsOneWidget);

      // Check floating pill action buttons
      expect(find.byTooltip('打开本地 Markdown (Cmd+O)'), findsOneWidget);
      expect(find.byTooltip('展开侧边栏 (Cmd+B)'), findsOneWidget);
      expect(find.byTooltip('导出出版级 PDF (Cmd+E)'), findsOneWidget);
      expect(find.byTooltip('隐藏工具栏 (Esc 或 Cmd+\\)'), findsOneWidget);
    });

    testWidgets('sidebar can be opened and closed interactively', (tester) async {
      final controller = ReaderController();
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
      expect(find.text('排版偏好'), findsOneWidget);

      // Close sidebar via header close button
      final closeBtn = find.byTooltip('收起侧边栏 (Cmd+B 或 Esc)');
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pump();

      // Sidebar is hidden again
      expect(find.byType(SidebarView), findsNothing);
    });

    testWidgets('mode and font size buttons trigger controller changes', (tester) async {
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

      // Adjust font size
      final initialFontSize = controller.renderOptions.fontSize;
      final addBtn = find.byTooltip('放大排版字号 (Cmd+=)');
      await tester.tap(addBtn);
      await tester.pump();

      expect(controller.renderOptions.fontSize, initialFontSize + 0.5);
    });

    testWidgets('font settings button opens font dialog with CJK status', (tester) async {
      final controller = ReaderController();
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      final fontBtn = find.byTooltip('字体排版与 CJK 1:2 等宽对齐设置 (Cmd+Shift+F)');
      expect(fontBtn, findsOneWidget);
      await tester.tap(fontBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('字体排版与中英文等宽对齐'), findsOneWidget);
      expect(find.text('正文排版字体 (Body Typography)'), findsOneWidget);
      expect(find.text('恢复默认字体'), findsOneWidget);

      // Close dialog
      final closeBtn = find.text('完成');
      await tester.tap(closeBtn);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('字体排版与中英文等宽对齐'), findsNothing);
    });
  });
}

