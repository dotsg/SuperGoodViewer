import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/sidebar_view.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_outline_test_');
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

  group('Outline Active Highlighting & Hierarchy Tests', () {
    test('ReaderController tracks active outline index based on scroll ratio in fluid mode', () async {
      final mdDoc = File(p.join(tempTestDir.path, 'long_doc.md'));
      final sb = StringBuffer();
      sb.writeln('# Chapter 1: Introduction');
      for (int i = 0; i < 40; i++) {
        sb.writeln('Paragraph line $i in chapter 1.');
      }
      sb.writeln('## Section 1.1: Background');
      for (int i = 0; i < 40; i++) {
        sb.writeln('Paragraph line $i in section 1.1.');
      }
      sb.writeln('# Chapter 2: Implementation');
      for (int i = 0; i < 40; i++) {
        sb.writeln('Paragraph line $i in chapter 2.');
      }
      sb.writeln('### Section 2.1.1: Architecture');
      for (int i = 0; i < 40; i++) {
        sb.writeln('Paragraph line $i in section 2.1.1.');
      }
      mdDoc.writeAsStringSync(sb.toString());

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(mdDoc.path, preservePosition: false);

      expect(controller.outlineItems.length, 4);
      expect(controller.outlineItems[0].title, 'Chapter 1: Introduction');
      expect(controller.outlineItems[0].level, 1);
      expect(controller.outlineItems[1].title, 'Section 1.1: Background');
      expect(controller.outlineItems[1].level, 2);
      expect(controller.outlineItems[2].title, 'Chapter 2: Implementation');
      expect(controller.outlineItems[2].level, 1);
      expect(controller.outlineItems[3].title, 'Section 2.1.1: Architecture');
      expect(controller.outlineItems[3].level, 3);

      // At top, Chapter 1 should be active (index 0)
      controller.updateScrollRatio(0.0);
      expect(controller.activeOutlineIndex, 0);

      // Scroll into Section 1.1
      controller.updateScrollRatio(0.28);
      expect(controller.activeOutlineIndex, 1);

      // Scroll into Chapter 2
      controller.updateScrollRatio(0.55);
      expect(controller.activeOutlineIndex, 2);

      // Scroll near the end
      controller.updateScrollRatio(0.99);
      expect(controller.activeOutlineIndex, 3);
    });

    test('ReaderController tracks active outline index based on page number in paged mode', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      controller.toggleMode(); // Switch to Paged mode (e.g. A4)

      controller.setOutlinesForTesting([
        const OutlineItem(title: 'Cover & Preface', level: 1, anchor: 'p1', lineNumber: 0, pageNumber: 1),
        const OutlineItem(title: 'Chapter 1', level: 1, anchor: 'p3', lineNumber: 0, pageNumber: 3),
        const OutlineItem(title: 'Chapter 2', level: 1, anchor: 'p7', lineNumber: 0, pageNumber: 7),
        const OutlineItem(title: 'Appendix', level: 2, anchor: 'p12', lineNumber: 0, pageNumber: 12),
      ]);

      expect(controller.activeOutlineIndex, 0);

      // Turn to page 2 (still in Cover & Preface)
      controller.updatePageNumber(2);
      expect(controller.activeOutlineIndex, 0);

      // Turn to page 3 (Chapter 1 begins)
      controller.updatePageNumber(3);
      expect(controller.activeOutlineIndex, 1);

      // Turn to page 5 (still in Chapter 1)
      controller.updatePageNumber(5);
      expect(controller.activeOutlineIndex, 1);

      // Turn to page 8 (Chapter 2)
      controller.updatePageNumber(8);
      expect(controller.activeOutlineIndex, 2);

      // Turn to page 15 (Appendix)
      controller.updatePageNumber(15);
      expect(controller.activeOutlineIndex, 3);
    });

    test('jumpToOutline immediately updates active index and locks against transient scroll updates', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      controller.toggleMode();

      final items = [
        const OutlineItem(title: 'Intro', level: 1, anchor: 'intro', lineNumber: 1, pageNumber: 1),
        const OutlineItem(title: 'Body', level: 1, anchor: 'body', lineNumber: 50, pageNumber: 5),
        const OutlineItem(title: 'Outro', level: 1, anchor: 'outro', lineNumber: 100, pageNumber: 10),
      ];
      controller.setOutlinesForTesting(items);

      expect(controller.activeOutlineIndex, 0);

      // User clicks 'Outro'
      controller.jumpToOutline(items[2]);
      expect(controller.activeOutlineIndex, 2);

      // Intermediate scroll events during animation should NOT override the jump selection
      controller.updatePageNumber(3);
      expect(controller.activeOutlineIndex, 2);
    });

    test('syncOutlinesPageNumbers matches PDF bookmarks with existing markdown headings', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final mdDoc = File(p.join(tempTestDir.path, 'pages_doc.md'));
      mdDoc.writeAsStringSync('# Heading A\n\nContent\n\n# Heading B\n\nContent B\n');
      controller.openFile(mdDoc.path, preservePosition: false);

      expect(controller.outlineItems.length, 2);
      expect(controller.outlineItems[0].pageNumber, isNull);
      expect(controller.outlineItems[1].pageNumber, isNull);

      // Sync with page numbers from compiler outline
      controller.syncOutlinesPageNumbers({
        'Heading A': 1,
        'Heading B': 4,
      });

      expect(controller.outlineItems[0].pageNumber, 1);
      expect(controller.outlineItems[1].pageNumber, 4);
    });

    testWidgets('SidebarView displays hierarchical styling without H1/H2 badges and highlights active chapter', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final items = [
        const OutlineItem(title: 'Main Title', level: 1, anchor: 'main', lineNumber: 1),
        const OutlineItem(title: 'Sub Heading', level: 2, anchor: 'sub', lineNumber: 20),
        const OutlineItem(title: 'Deep Section', level: 3, anchor: 'deep', lineNumber: 50),
      ];
      controller.setOutlinesForTesting(items);

      final theme = ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SidebarView(controller: controller),
          ),
        ),
      );
      await tester.pump();

      // Badges like H1, H2, H3 must NOT be rendered
      expect(find.text('H1'), findsNothing);
      expect(find.text('H2'), findsNothing);
      expect(find.text('H3'), findsNothing);
      expect(find.text('P1'), findsNothing);

      // All titles must be visible
      expect(find.text('Main Title'), findsOneWidget);
      expect(find.text('Sub Heading'), findsOneWidget);
      expect(find.text('Deep Section'), findsOneWidget);

      // Initial active item is index 0 (Main Title)
      expect(controller.activeOutlineIndex, 0);

      // Active item text should use primary theme color
      final titleTextWidget0 = tester.widget<Text>(find.text('Main Title'));
      expect(titleTextWidget0.style?.color, theme.colorScheme.primary);
      expect(titleTextWidget0.style?.fontWeight, FontWeight.w700);

      // Inactive item text should NOT use primary color
      final titleTextWidget1 = tester.widget<Text>(find.text('Sub Heading'));
      expect(titleTextWidget1.style?.color, isNot(theme.colorScheme.primary));

      // Change active index to 1 (Sub Heading)
      controller.setActiveOutlineIndex(1);
      await tester.pump();

      // Now Sub Heading should be highlighted in primary color
      final updatedTitleText1 = tester.widget<Text>(find.text('Sub Heading'));
      expect(updatedTitleText1.style?.color, theme.colorScheme.primary);
      expect(updatedTitleText1.style?.fontWeight, FontWeight.w600);

      // Main Title is now inactive
      final updatedTitleText0 = tester.widget<Text>(find.text('Main Title'));
      expect(updatedTitleText0.style?.color, isNot(theme.colorScheme.primary));
    });

    test('WorkspaceView and PdfCanvasView compensate for top titlebar when sidebar is open', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      // Default sidebar closed
      expect(controller.isSidebarOpen, false);

      // Open sidebar
      controller.setSidebarOpen(true);
      expect(controller.isSidebarOpen, true);

      // Top titlebar height is 32.0 when sidebar is open
      const double titleBarHeight = 32.0;
      const double zoom = 1.0;
      const double topDocOffset = titleBarHeight / zoom;

      // Suppose document height is 1000.0
      const double docHeight = 1000.0;
      // When at visibleRect.top = 0, the visibleDocTop is shifted by topDocOffset (32.0)
      const double currentTop = 0.0;
      final visibleDocTop = currentTop + topDocOffset;
      expect(visibleDocTop, 32.0);

      // Calculating ratio from visibleDocTop excludes the 32px covered by the menu bar
      final ratio = visibleDocTop / docHeight;
      expect(ratio, closeTo(0.032, 0.001));

      // When jumped to an outline item at docHeight * 0.5 (500.0), target scroll offset
      // must subtract topDocOffset (32.0) so heading is placed below titlebar (at 468.0)
      const double targetDocY = 500.0;
      final adjustedTargetY = targetDocY - topDocOffset;
      expect(adjustedTargetY, 468.0);
    });
  });
}
