import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
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
  });
}
