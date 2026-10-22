import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/pdf_page_analysis_service.dart';
import 'package:sogoodviewer/services/pdf_reflow_service.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final projectRoot = Directory.current.path.endsWith('/ui')
      ? Directory.current.parent.path
      : Directory.current.path;
  final attentionPdfPath = p.join(projectRoot, 'docs', 'samples', 'attention_is_all_you_need.pdf');
  final resnetPdfPath = p.join(projectRoot, 'docs', 'samples', 'resnet_cvpr2016.pdf');

  group('PdfPageAnalysisService Tests', () {
    test('Analyzes single-column PDF (Attention Is All You Need)', () async {
      expect(File(attentionPdfPath).existsSync(), isTrue);

      final doc = await PdfDocument.openFile(attentionPdfPath);
      expect(doc.pages.length, 11);

      final page = doc.pages[0];
      final analysis = await PdfPageAnalysisService.analyzePage(page, docKey: attentionPdfPath);

      expect(analysis.pageNumber, 1);
      expect(analysis.pageSize.width, closeTo(612.0, 1.0));
      expect(analysis.pageSize.height, closeTo(792.0, 1.0));

      // Single-column NeurIPS paper: text width is ~397pt with ~108pt side margins
      expect(analysis.isMultiColumn, isFalse);
      expect(analysis.columns.length, 1);
      expect(analysis.contentBounds.left, closeTo(108.0, 10.0));
      expect(analysis.contentBounds.right, closeTo(504.0, 10.0));
      expect(analysis.contentBounds.width, closeTo(397.0, 15.0));

      // Best column should cover the single content block
      final col = analysis.findBestColumn(const Offset(200.0, 300.0));
      expect(col.bounds, analysis.contentBounds);

      // Verify cached retrieval
      final cached = PdfPageAnalysisService.getCachedAnalysis(attentionPdfPath, 1);
      expect(cached, isNotNull);
      expect(cached!.contentBounds, analysis.contentBounds);

      await doc.dispose();
    });

    test('Analyzes multi-column PDF (ResNet CVPR 2016)', () async {
      expect(File(resnetPdfPath).existsSync(), isTrue);

      final doc = await PdfDocument.openFile(resnetPdfPath);
      expect(doc.pages.length, 12);

      // Page 2 is body text with classic 2 columns
      final page = doc.pages[1];
      final analysis = await PdfPageAnalysisService.analyzePage(page, docKey: resnetPdfPath);

      expect(analysis.pageNumber, 2);
      expect(analysis.isMultiColumn, isTrue);
      expect(analysis.columns.length, 2);

      final col0 = analysis.columns[0];
      final col1 = analysis.columns[1];

      // Columns should be side-by-side with gutter in between
      expect(col0.bounds.left, lessThan(col1.bounds.left));
      expect(col0.bounds.right, lessThan(col1.bounds.left));
      expect(col0.bounds.width, closeTo(240.0, 25.0));
      expect(col1.bounds.width, closeTo(240.0, 25.0));

      // Tapping on left column selects column 0
      final tappedLeft = analysis.findBestColumn(Offset(col0.bounds.center.dx, 400.0));
      expect(tappedLeft.index, 0);

      // Tapping on right column selects column 1
      final tappedRight = analysis.findBestColumn(Offset(col1.bounds.center.dx, 400.0));
      expect(tappedRight.index, 1);

      await doc.dispose();
    });
  });

  group('RenderOptions pdfCropMargins Tests', () {
    test('Default value is false', () {
      const opts = RenderOptions();
      expect(opts.pdfCropMargins, isFalse);
    });

    test('copyWith updates pdfCropMargins', () {
      const opts = RenderOptions();
      final updated = opts.copyWith(pdfCropMargins: true);
      expect(updated.pdfCropMargins, isTrue);

      final reverted = updated.copyWith(pdfCropMargins: false);
      expect(reverted.pdfCropMargins, isFalse);
    });

    test('toJsonString serializes pdf_crop_margins when true', () {
      const optsFalse = RenderOptions(pdfCropMargins: false);
      expect(optsFalse.toJsonString().contains('pdf_crop_margins'), isFalse);

      const optsTrue = RenderOptions(pdfCropMargins: true);
      expect(optsTrue.toJsonString().contains('"pdf_crop_margins":true'), isTrue);
    });

    test('Equality and hashCode reflect pdfCropMargins', () {
      const opt1 = RenderOptions(pdfCropMargins: false);
      const opt2 = RenderOptions(pdfCropMargins: true);
      const opt3 = RenderOptions(pdfCropMargins: false);

      expect(opt1 == opt2, isFalse);
      expect(opt1 == opt3, isTrue);
      expect(opt1.hashCode == opt3.hashCode, isTrue);
      expect(opt1.hashCode == opt2.hashCode, isFalse);
    });
  });

  group('ReaderController pdfCropMargins Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('sgv_pdf_analysis_test_');
      PreferencesService.setConfigFileForTesting(File(p.join(tempDir.path, 'preferences.json')));
    });

    tearDown(() {
      PreferencesService.setConfigFileForTesting(null);
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('ReaderController toggles pdfCropMargins', () {
      final controller = ReaderController();
      expect(controller.pdfCropMargins, isFalse);

      controller.togglePdfCropMargins();
      expect(controller.pdfCropMargins, isTrue);

      controller.setPdfCropMargins(false);
      expect(controller.pdfCropMargins, isFalse);

      controller.dispose();
    });
  });

  group('PdfPageAnalysisService Cache Key & LRU Tests', () {
    tearDown(() {
      PdfPageAnalysisService.clearCache();
    });

    test('keyFor reflects path and identity of currentPdfBytes', () {
      final controller = ReaderController();
      final key1 = PdfPageAnalysisService.keyFor(controller);
      expect(key1, contains('untitled#'));

      // Replacing PDF bytes updates keyFor and invalidates old cache entries
      controller.activeSession.pdfBytes = Uint8List.fromList([1, 2, 3, 4]);
      final key2 = PdfPageAnalysisService.keyFor(controller);
      expect(key2, isNot(equals(key1)));

      controller.dispose();
    });

    test('keyFor matches delegate lookup when cached analysis is present', () async {
      final controller = ReaderController();
      controller.setPdfCropMargins(true);
      final docKey = PdfPageAnalysisService.keyFor(controller);

      final doc = await PdfDocument.openFile(attentionPdfPath);
      final page = doc.pages[0];
      await PdfPageAnalysisService.analyzePage(page, docKey: docKey);

      final lookup = PdfPageAnalysisService.getCachedAnalysis(docKey, 1);
      expect(lookup, isNotNull);
      expect(lookup!.contentBounds.width, closeTo(397.0, 15.0));

      await doc.dispose();
      controller.dispose();
    });

    test('LRU cache evicts oldest and retains recently accessed documents', () async {
      PdfPageAnalysisService.clearCache();

      // We can open attention PDF to generate real analyses with different docKeys
      final doc = await PdfDocument.openFile(attentionPdfPath);
      final page = doc.pages[0];

      // Populate 10 documents
      for (int i = 0; i < 10; i++) {
        await PdfPageAnalysisService.analyzePage(page, docKey: 'doc_$i');
      }

      // All 10 are in cache
      for (int i = 0; i < 10; i++) {
        expect(PdfPageAnalysisService.getCachedAnalysis('doc_$i', 1), isNotNull);
      }

      // Access doc_0 to promote it to MRU
      final promoted = PdfPageAnalysisService.getCachedAnalysis('doc_0', 1);
      expect(promoted, isNotNull);

      // Add 11th document -> should evict doc_1 (oldest), NOT doc_0
      await PdfPageAnalysisService.analyzePage(page, docKey: 'doc_10');

      expect(PdfPageAnalysisService.getCachedAnalysis('doc_0', 1), isNotNull, reason: 'doc_0 was promoted and should not be evicted');
      expect(PdfPageAnalysisService.getCachedAnalysis('doc_1', 1), isNull, reason: 'doc_1 was oldest and should be evicted');
      expect(PdfPageAnalysisService.getCachedAnalysis('doc_10', 1), isNotNull);

      await doc.dispose();
    });
  });

  group('PdfReflowService & ReaderController Client-Side PDF Reflow Tests', () {
    test('Reflows single-column academic PDF (Attention Is All You Need) into semantic Markdown', () async {
      final bytes = File(attentionPdfPath).readAsBytesSync();
      final result = await PdfReflowService.reflowPdfBytes(
        bytes,
        documentTitle: 'Attention Is All You Need',
      );

      expect(result.hasContent, isTrue);
      expect(result.pageCount, equals(11));
      expect(result.elements.length, greaterThan(30));
      expect(result.markdown, contains('Attention Is All You Need'));
      expect(result.markdown, contains('Introduction'));
      expect(result.markdown, contains('#'));
    });

    test('Uncurls multi-column academic PDF (ResNet CVPR 2016) and toggles ReaderController reflow mode', () async {
      final bytes = File(resnetPdfPath).readAsBytesSync();
      final result = await PdfReflowService.reflowPdfBytes(
        bytes,
        documentTitle: 'Deep Residual Learning',
      );

      expect(result.hasContent, isTrue);
      expect(result.pageCount, equals(12));
      expect(result.elements.length, greaterThan(40));
      expect(result.markdown, contains('Deep Residual Learning'));

      final controller = ReaderController();
      addTearDown(controller.dispose);

      await controller.openFile(resnetPdfPath);
      expect(controller.isSourcePdfDocument, isTrue);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.isPdfReflowed, isFalse);

      final enabled = await controller.setPdfReflowMode(true);
      expect(enabled, isTrue);
      expect(controller.isSourcePdfDocument, isTrue);
      expect(controller.isPdfReflowed, isTrue);
      expect(controller.isPdfDocument, isFalse);
      expect(controller.isFluidLayout, isTrue);
      expect(controller.currentMarkdown, isNotEmpty);
      expect(controller.outlineItems, isNotEmpty);

      final disabled = await controller.setPdfReflowMode(false);
      expect(disabled, isTrue);
      expect(controller.isSourcePdfDocument, isTrue);
      expect(controller.isPdfReflowed, isFalse);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.currentPdfBytes?.length, equals(bytes.length));
    });
  });
}
