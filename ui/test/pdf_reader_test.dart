import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';
import 'package:sogoodviewer/views/sidebar_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempTestDir;
  late File samplePdfFile;
  late File sampleMdFile;

  // Minimal valid PDF binary
  const samplePdfContent = '%PDF-1.4\n'
      '1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n'
      '2 0 obj<</Type/Pages/Count 1/Kids[3 0 R]>>endobj\n'
      '3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<<>>>>endobj\n'
      'xref\n'
      '0 4\n'
      '0000000000 65535 f \n'
      '0000000009 00000 n \n'
      '0000000052 00000 n \n'
      '0000000101 00000 n \n'
      'trailer<</Size 4/Root 1 0 R>>\n'
      'startxref\n'
      '178\n'
      '%%EOF\n';

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('sgv_pdf_reader_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );

    samplePdfFile = File(p.join(tempTestDir.path, 'sample_doc.pdf'));
    samplePdfFile.writeAsBytesSync(Uint8List.fromList(samplePdfContent.codeUnits));

    sampleMdFile = File(p.join(tempTestDir.path, 'sample_doc.md'));
    sampleMdFile.writeAsStringSync('# Heading 1\nHello Markdown world');

    Pdfrx.cacheDirectoryPath = tempTestDir.path;
    final candidatePaths = [
      p.normalize(p.join(Directory.current.path, 'build/native_assets/macos/libpdfium.dylib')),
      p.normalize(p.join(Directory.current.path, '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-arm64/libpdfium.dylib')),
      p.normalize(p.join(Directory.current.path, '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-x64/libpdfium.dylib')),
    ];
    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        Pdfrx.pdfiumModulePath = path;
        break;
      }
    }
    await pdfrxFlutterInitialize();
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('PDF Reader Functionality Tests', () {
    test('ReaderController opens PDF file directly without Markdown transpilation', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      expect(controller.isPdfDocument, isFalse);

      await controller.openFile(samplePdfFile.path);

      expect(controller.isPdfDocument, isTrue);
      expect(controller.currentFilePath, samplePdfFile.path);
      expect(controller.documentTitle, 'sample_doc');
      expect(controller.currentMarkdown, isEmpty);
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.currentPdfBytes!.length, samplePdfFile.lengthSync());
      expect(controller.recentFiles.contains(samplePdfFile.path), isTrue);

      // Switching mode should be a no-op for fixed PDF documents
      final prevMode = controller.renderOptions.mode;
      controller.toggleMode();
      expect(controller.renderOptions.mode, prevMode);

      // PDF Outlines support with pageNumber
      controller.setPdfOutlines([
        const OutlineItem(
          title: 'Chapter 1',
          level: 1,
          anchor: 'Chapter 1',
          lineNumber: 0,
          pageNumber: 1,
        ),
        const OutlineItem(
          title: 'Section 1.1',
          level: 2,
          anchor: 'Section 1.1',
          lineNumber: 0,
          pageNumber: 2,
        ),
      ]);

      expect(controller.outlineItems.length, 2);
      expect(controller.outlineItems[0].pageNumber, 1);
      expect(controller.outlineItems[1].pageNumber, 2);

      // Exporting directly exports identical PDF bytes
      final exportPath = p.join(tempTestDir.path, 'exported.pdf');
      final exportSuccess = await controller.exportPdf(exportPath);
      expect(exportSuccess, isTrue);
      final exportedBytes = File(exportPath).readAsBytesSync();
      expect(exportedBytes, controller.currentPdfBytes);

      // Switching to a Markdown file resets isPdfDocument
      await controller.openFile(sampleMdFile.path);
      expect(controller.isPdfDocument, isFalse);
      expect(controller.currentMarkdown, contains('# Heading 1'));
    });

    testWidgets('WorkspaceView adapts toolbar for PDF reading (hides mode pill, shows two-page & page nav)', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));

      // Fluid/Paged mode toggle pill should NOT be rendered when viewing a PDF
      expect(find.text('自适应流式'), findsNothing);
      expect(find.text('A4 出版'), findsNothing);

      // Two-page toggle and page navigation should be present for PDF
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
    });

    testWidgets('SidebarView displays PDF icon in recent files and P1 badge for outlines', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);
      controller.setPdfOutlines([
        const OutlineItem(
          title: 'Introduction',
          level: 1,
          anchor: 'Introduction',
          lineNumber: 0,
          pageNumber: 1,
        ),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SidebarView(controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));

      // Outline badge should display P1 instead of H1
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('Introduction'), findsOneWidget);

      // Switch to Recent Files tab (tab index 1)
      await tester.tap(find.textContaining('最近文件'));
      await tester.pump(const Duration(milliseconds: 300));

      // Recent file item should show PDF icon
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsOneWidget);
      expect(find.text('sample_doc.pdf'), findsOneWidget);
    });

    test('ReaderController.isValidPdfBytes and hasPdfHeader check magic bytes and trailing EOF with tolerance', () {
      expect(ReaderController.isValidPdfBytes(Uint8List(0)), isFalse);
      expect(ReaderController.isValidPdfBytes(Uint8List.fromList('short'.codeUnits)), isFalse);
      expect(ReaderController.isValidPdfBytes(Uint8List.fromList('Not a PDF at all'.codeUnits)), isFalse);
      
      // Truncated document without %%EOF marker
      expect(
        ReaderController.isValidPdfBytes(Uint8List.fromList('%PDF-1.4 truncated document without eof marker'.codeUnits)),
        isFalse,
      );

      // Standard %PDF at offset 0 and %%EOF at end
      expect(
        ReaderController.isValidPdfBytes(Uint8List.fromList('%PDF-1.7 ... content ... %%EOF\n'.codeUnits)),
        isTrue,
      );

      // %PDF preceded by 48 bytes of headers/BOM/comments within first 1024 bytes
      final leadingBytes = List.filled(48, 0x20); // 48 spaces
      final prefixedPdf = Uint8List.fromList([...leadingBytes, ...'%PDF-1.5 ... content ... %%EOF\n'.codeUnits]);
      expect(ReaderController.hasPdfHeader(prefixedPdf), isTrue);
      expect(ReaderController.isValidPdfBytes(prefixedPdf), isTrue);

      // %%EOF followed by 2048 bytes of trailing metadata/padding
      final trailingPadding = List.filled(2048, 0x20);
      final paddedPdf = Uint8List.fromList([...'%PDF-1.6 content %%EOF'.codeUnits, ...trailingPadding]);
      expect(ReaderController.isValidPdfBytes(paddedPdf), isTrue);

      // %PDF beyond 1024 bytes is rejected
      final tooMuchLeading = List.filled(1030, 0x20);
      final invalidPrefix = Uint8List.fromList([...tooMuchLeading, ...'%PDF-1.4 content %%EOF'.codeUnits]);
      expect(ReaderController.hasPdfHeader(invalidPrefix), isFalse);
      expect(ReaderController.isValidPdfBytes(invalidPrefix), isFalse);
    });

    test('Markdown containing literal %PDF in first 1KB is NOT misclassified as PDF', () async {
      final mdWithPdfLiteral = File(p.join(tempTestDir.path, 'pdf-notes.md'));
      mdWithPdfLiteral.writeAsStringSync(
        '# PDF 格式笔记\n每个 PDF 文件都以 `%PDF-1.7` 开头。\n\n## 结构分析\n详见规范文档。',
      );

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(mdWithPdfLiteral.path);

      expect(controller.isPdfDocument, isFalse);
      expect(controller.currentMarkdown, contains('PDF 格式笔记'));
      expect(controller.outlineItems.any((item) => item.title == 'PDF 格式笔记'), isTrue);
      expect(controller.errorMessage, isNull);
    });

    test('Strict format detection: non-.pdf file starting with %PDF or UTF-8 BOM is detected as PDF', () async {
      final datFile = File(p.join(tempTestDir.path, 'raw_document.dat'));
      datFile.writeAsBytesSync(Uint8List.fromList(samplePdfContent.codeUnits));

      final bomDatFile = File(p.join(tempTestDir.path, 'bom_document.dat'));
      bomDatFile.writeAsBytesSync(Uint8List.fromList([
        0xEF, 0xBB, 0xBF, // UTF-8 BOM
        ...samplePdfContent.codeUnits,
      ]));

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(datFile.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.documentTitle, 'raw_document');

      await controller.openFile(bomDatFile.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.documentTitle, 'bom_document');
    });

    test('Opening non-existent file clears canvas state, resets loading, and sets error', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.currentPdfBytes, isNotNull);

      await controller.openFile(p.join(tempTestDir.path, 'missing_document.md'));
      expect(controller.currentFilePath, p.join(tempTestDir.path, 'missing_document.md'));
      expect(controller.documentTitle, 'missing_document');
      expect(controller.currentPdfBytes, isNull);
      expect(controller.outlineItems, isEmpty);
      expect(controller.isReloading, isFalse);
      expect(controller.errorMessage, contains('File not found:'));
    });

    test('Initial open hands bytes directly to PDFium and sets up watcher for live recovery', () async {
      final truncatedFile = File(p.join(tempTestDir.path, 'in_flight.pdf'));
      truncatedFile.writeAsStringSync('%PDF-1.4\n1 0 obj<</Type/Catalog>>endobj\n// in-flight download');

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      // Initial open gives bytes to PDFium and installs watcher (no hard rejection)
      await controller.openFile(truncatedFile.path);

      expect(controller.isPdfDocument, isTrue);
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.recentFiles.contains(truncatedFile.path), isTrue);

      // Manual refresh also attempts reload safely
      await controller.refreshDocument();
      expect(controller.currentPdfBytes, isNotNull);

      // Test error setter (English error message)
      controller.setErrorMessage('Failed to load PDF document');
      expect(controller.errorMessage, 'Failed to load PDF document');
    });

    test('TOC outline race condition guard prevents stale or cross-document outline pollution', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);
      expect(controller.isPdfDocument, isTrue);

      // Successfully sets outline for matching path
      controller.setPdfOutlines([
        const OutlineItem(title: 'PDF Header', level: 1, anchor: 'PDF Header', lineNumber: 0, pageNumber: 1),
      ], targetFilePath: samplePdfFile.path);
      expect(controller.outlineItems.length, 1);
      expect(controller.outlineItems.first.title, 'PDF Header');

      // Stale callback for a different path is rejected
      controller.setPdfOutlines([
        const OutlineItem(title: 'Stale Header', level: 1, anchor: 'Stale Header', lineNumber: 0, pageNumber: 1),
      ], targetFilePath: '/path/to/another.pdf');
      expect(controller.outlineItems.first.title, 'PDF Header');

      // Switching to Markdown resets outlines to Markdown headings
      await controller.openFile(sampleMdFile.path);
      expect(controller.isPdfDocument, isFalse);
      expect(controller.outlineItems.first.title, 'Heading 1');

      // Late arriving PDF outline callback while in Markdown mode is rejected
      controller.setPdfOutlines([
        const OutlineItem(title: 'Late PDF Header', level: 1, anchor: 'Late PDF Header', lineNumber: 0, pageNumber: 1),
      ], targetFilePath: samplePdfFile.path);
      expect(controller.outlineItems.first.title, 'Heading 1');
    });

    test('Settings and theme modifications in PDF mode do not trigger reloads or pollute renderOptionsChanged', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);

      // Typography setters
      controller.setFontSize(18.0);
      expect(controller.renderOptions.fontSize, 18.0);
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);

      controller.setBodyFont('PingFang SC');
      expect(controller.renderOptions.bodyFont, 'PingFang SC');
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);

      controller.setCodeFont('JetBrains Mono');
      expect(controller.renderOptions.codeFont, 'JetBrains Mono');
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);

      controller.setTypography(bodyFont: 'Songti SC', fontSize: 15.0);
      expect(controller.renderOptions.bodyFont, 'Songti SC');
      expect(controller.renderOptions.fontSize, 15.0);
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);

      // Viewport width change
      controller.setViewportWidth(1200.0);
      expect(controller.isReloading, isFalse);

      // Theme toggle
      final initialTheme = controller.renderOptions.theme;
      controller.toggleTheme();
      expect(controller.renderOptions.theme, isNot(initialTheme));
      expect(controller.isReloading, isFalse);
      expect(controller.renderOptionsChanged, isFalse);
    });

    testWidgets('SettingsDialog displays PDF information banner in Typography tab when viewing a PDF', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(samplePdfFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsDialog(controller: controller),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Switch to typography tab
      await tester.tap(find.text('排版与字体'));
      await tester.pumpAndSettle();

      expect(find.textContaining('当前正在阅读独立 PDF 文档'), findsOneWidget);
    });
  });
}
