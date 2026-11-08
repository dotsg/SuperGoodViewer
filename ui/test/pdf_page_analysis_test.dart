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
      final controller = ReaderController(autoRestorePreferences: false);
      final key1 = PdfPageAnalysisService.keyFor(controller);
      expect(key1, contains('untitled#'));

      // Replacing PDF bytes updates keyFor and invalidates old cache entries
      controller.activeSession.pdfBytes = Uint8List.fromList([1, 2, 3, 4]);
      final key2 = PdfPageAnalysisService.keyFor(controller);
      expect(key2, isNot(equals(key1)));

      controller.dispose();
    });

    test('keyFor matches delegate lookup when cached analysis is present', () async {
      final controller = ReaderController(autoRestorePreferences: false);
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
    test('joinTextFlow handles soft hyphens, boundary emphasis markers, and compound words', () {
      const cases = <({String prev, String next, bool isCjk, String expected})>[
        (
          prev: '*as learn*\u00AD',
          next: '*ing residual functions*',
          isCjk: false,
          expected: '*as learning residual functions*',
        ),
        (
          prev: '**deep**\u00AD',
          next: '**er networks**',
          isCjk: false,
          expected: '**deeper networks**',
        ),
        (
          prev: 'on the WMT 2014 English\u00AD',
          next: 'to-German translation task',
          isCjk: false,
          expected: 'on the WMT 2014 English-to-German translation task',
        ),
        (
          prev: 'naturally integrates low/mid/high\u00AD',
          next: 'level features and classifiers',
          isCjk: false,
          expected: 'naturally integrates low/mid/high-level features and classifiers',
        ),
        (
          prev: 'dot-product (multi\u00AD',
          next: 'plicative) attention',
          isCjk: false,
          expected: 'dot-product (multiplicative) attention',
        ),
        (
          prev: 'in a semi-',
          next: 'supervised setting',
          isCjk: false,
          expected: 'in a semi-supervised setting',
        ),
        (
          prev: 'with my co-',
          next: 'author on the paper',
          isCjk: false,
          expected: 'with my co-author on the paper',
        ),
        (
          prev: 'using a pre-',
          next: 'trained model',
          isCjk: false,
          expected: 'using a pre-trained model',
        ),
        (
          prev: 'compared with high\u00AD',
          next: 'way networks',
          isCjk: false,
          expected: 'compared with highway networks',
        ),
        (
          prev: 'suggests that pre\u00AD',
          next: 'conditioning is useful',
          isCjk: false,
          expected: 'suggests that preconditioning is useful',
        ),
        (
          prev: 'attend to position\u00AD',
          next: 'Figure 1: The Transformer',
          isCjk: false,
          expected: 'attend to position Figure 1: The Transformer',
        ),
      ];

      for (final c in cases) {
        expect(
          PdfReflowService.joinTextFlow(c.prev, c.next, isCjk: c.isCjk),
          equals(c.expected),
          reason: 'joinTextFlow(${c.prev}, ${c.next})',
        );
      }
    });

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
      expect(result.markdown, contains('English-to-German'));
      expect(result.markdown, contains('(multiplicative)'));
      expect(result.markdown, isNot(contains('\u00AD')));
      // Verify Page 8 & Page 9 single-column prose is not split into fake 2-column fragments
      final idxCompetitive = result.markdown.indexOf(
        'at a fraction of the training cost of any of the competitive models.',
      );
      final idxEnsembles = result.markdown.indexOf(
        'In the former task our best model outperforms even all previously reported ensembles.',
      );
      expect(idxCompetitive, greaterThan(0));
      expect(idxEnsembles, greaterThan(idxCompetitive));
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
      expect(result.markdown, contains('low/mid/high-level'));
      expect(result.markdown, contains('highway networks'));
      expect(result.markdown, contains('preconditioning'));
      expect(result.markdown, isNot(contains('\u00AD')));
      // Ensure italic soft-hyphenated words are unwrapped without mid-word `**`
      expect(RegExp(r'[a-z]\*\*[a-z]').hasMatch(result.markdown), isFalse);
      // Ensure single-column CVPR tables are preserved
      final tableCount = result.elements.where((e) => e.text.startsWith('| ')).length;
      expect(tableCount, greaterThanOrEqualTo(12));
      // Ensure Figure 1 axis labels (56-layer / 20-layer) do not leak into the Abstract
      final abstractStart = result.markdown.indexOf('Abstract');
      final introStart = result.markdown.indexOf('1. Introduction');
      expect(abstractStart, greaterThanOrEqualTo(0));
      expect(introStart, greaterThan(abstractStart));
      final abstractSection = result.markdown.substring(abstractStart, introStart);
      expect(abstractSection, isNot(contains('56-layer')));

      final controller = ReaderController(autoRestorePreferences: false);
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
      expect(controller.isFluidLayout, isFalse);
      expect(
        controller.renderOptions.effectivePageFormat,
        equals(PageFormat.mobilePortrait),
      );
      // Attempting to switch page format while PDF reflow is active is ignored
      controller.setPageFormat(PageFormat.a4Portrait);
      expect(
        controller.renderOptions.effectivePageFormat,
        equals(PageFormat.mobilePortrait),
      );
      controller.toggleMode();
      expect(
        controller.renderOptions.effectivePageFormat,
        equals(PageFormat.mobilePortrait),
      );
      expect(controller.currentMarkdown, isNotEmpty);
      expect(controller.outlineItems, isNotEmpty);

      final disabled = await controller.setPdfReflowMode(false);
      expect(disabled, isTrue);
      expect(controller.isSourcePdfDocument, isTrue);
      expect(controller.isPdfReflowed, isFalse);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.currentPdfBytes?.length, equals(bytes.length));
    });

    test('Exports reflowed PDF in mobile-friendly Mobile Portrait (390x780pt) layout', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(resnetPdfPath);
      final enabled = await controller.setPdfReflowMode(true);
      expect(enabled, isTrue);
      expect(controller.isPdfReflowed, isTrue);
      expect(controller.isFluidLayout, isFalse);
      expect(
        controller.renderOptions.effectivePageFormat,
        equals(PageFormat.mobilePortrait),
      );

      final exportedBytes = await controller.getPdfBytesForExport();
      expect(exportedBytes, isNotNull);
      expect(exportedBytes!.isNotEmpty, isTrue);

      final exportedDoc = await PdfDocument.openData(exportedBytes);
      try {
        expect(exportedDoc.pages.length, greaterThan(1));
        expect(exportedDoc.pages.first.width, closeTo(390.0, 1.0));
        expect(exportedDoc.pages.first.height, closeTo(780.0, 1.0));
      } finally {
        await exportedDoc.dispose();
      }
    });

    test('Reflows 3-column magazine PDF (newyork.pdf) with drop caps and partial spanning headers when present', () async {
      final newyorkFile = File('/Users/wuvist/Desktop/newyork.pdf');
      if (!newyorkFile.existsSync()) return;

      final doc = await PdfDocument.openFile(newyorkFile.path);
      try {
        // Page 4 (index 3) is "CONTRIBUTORS" with 2 narrow-gutter columns
        final page4 = doc.pages[3];
        final page4Text = await page4.loadStructuredText();
        final analysis4 = PdfPageAnalysisService.computePageAnalysis(page4, page4Text);
        expect(analysis4.isMultiColumn, isTrue);
        expect(analysis4.columns.length, equals(2));

        // Page 14 (index 13) is "SCHMEAR CAMPAIGN" with 3 columns, 2-of-3 spanning header, and drop cap "E"
        final page14 = doc.pages[13];
        final page14Text = await page14.loadStructuredText();
        final analysis14 = PdfPageAnalysisService.computePageAnalysis(page14, page14Text);

        expect(analysis14.isMultiColumn, isTrue);
        expect(analysis14.columns.length, equals(3));
        expect(analysis14.columns[0].bounds.width, closeTo(160.4, 8.0));
        expect(analysis14.columns[1].bounds.width, closeTo(160.4, 8.0));
        expect(analysis14.columns[2].bounds.width, closeTo(160.4, 8.0));

        final result = await PdfReflowService.reflowDocument(
          doc,
          documentTitle: 'The New Yorker',
        );
        expect(result.hasContent, isTrue);
        expect(result.markdown, contains('SCHMEAR CAMPAIGN'));
        // Sunken drop-cap "T" on Page 9 merged with Line 1 ("The chaos") instead of Line 2
        expect(result.markdown, contains('The chaos of Donald Trump’s Presidency'));
        // Drop cap "E" + "very summer in France" merged cleanly
        expect(result.markdown, contains('Every summer in France, an exodus takes place.'));
        // Cross-column continuation from Col 1 bottom to Col 2 top
        expect(
          result.markdown,
          contains('an annual transmigration of people, money, goods, gifts, expectations'),
        );
        // Cross-page continuation + PDFium \x02 soft-hyphen unwrapping ("thou\x02sand" -> "thousand")
        expect(
          result.markdown,
          contains(
            'A shopkeeper in Cholet, a midsize town, reported that he had sold a thousand jars of El Mordjene in five hours.',
          ),
        );
        // Stick-up initial cap "W" on Page 16 normalized to body paragraph
        expect(
          result.markdown,
          contains('Was a Nutella conspiracy behind the strangest quarrel in Franco-Algerian memory?'),
        );
        // Standalone pronoun drop cap "I" on Page 17 ("I had hoped to visit")
        expect(
          result.markdown,
          contains('I had hoped to visit'),
        );
        // 2-column inset poems on 3-column Pages 36 ("INQUEST") and 49 ("AN OCEAN OF CLOUDS")
        expect(result.markdown, contains('INQUEST'));
        expect(result.markdown, contains('*—Ellen Bass*'));
        expect(result.markdown, contains('AN OCEAN OF CLOUDS'));
        expect(result.markdown, contains('*—Garrett Hongo*'));
        // Cross-page sentence continuation across Page 63 BRIEFLY NOTED sidebar and Page 64 ADVERTISEMENT column
        expect(
          result.markdown,
          contains('wrote, “I laid out above eight pounds of my own money for a suit of superfine clothes to dance with at my freedom.”'),
        );
        // Cross-column pdfrx hyphenated line-height repair on Page 66 ("fall-" + "ing" -> "falling")
        expect(
          result.markdown,
          contains('Brown began to gesticulate, his arms rising and falling in exasperation. He argued with Hood, growing more agitated.'),
        );
        // Standalone figures extracted as inline PNG data URIs across the entire magazine
        expect(
          result.markdown,
          contains('![Figure](data:image/png;base64,'),
        );
        final imageElements =
            result.elements.where((e) => e.type == ReflowElementType.image).toList();
        expect(imageElements.length, greaterThanOrEqualTo(85));
        // Page 45 full-page feature illustration (with light overlaid display text) and late-page figures preserved
        expect(imageElements.any((e) => e.pageNumber == 45), isTrue);
        expect(imageElements.where((e) => e.pageNumber >= 60).length, greaterThanOrEqualTo(20));
      } finally {
        await doc.dispose();
      }
    });

    test('Reflows structured resume PDF (cv.pdf) preserving bold, italic, links, and split headers when present', () async {
      final cvFile = File('/Users/wuvist/Desktop/cv.pdf');
      if (!cvFile.existsSync()) return;

      final bytes = cvFile.readAsBytesSync();
      final result = await PdfReflowService.reflowPdfBytes(
        bytes,
        documentTitle: 'XUE YuanHuang CV',
      );

      expect(result.hasContent, isTrue);
      // Title & H1 sections
      expect(result.markdown, contains('# XUE, YuanHuang'));
      expect(result.markdown, contains('## EDUCATION'));
      expect(result.markdown, contains('## EXPERIENCE'));
      expect(result.markdown, contains('## PROJECTS'));
      expect(result.markdown, contains('## ACTIVITIES & COMMUNITY'));
      expect(result.markdown, contains('## SKILLS'));

      // Hyperlinks preserved
      expect(result.markdown, contains('[LinkedIn](https://www.linkedin.com/in/xue-yuanhuang/)'));
      expect(result.markdown, contains('[GitHub](https://github.com/xueyuanhuang)'));
      expect(result.markdown, contains('[**HR Talent Pool**](https://hr-talent-pool.pages.dev/)'));
      expect(
        result.markdown,
        contains('[**API Diagnostics**](https://api-diagnostics.xue-yuanhuang.workers.dev/tests)'),
      );
      expect(result.markdown, contains('[**AI Relay**](https://xyhmail.xyz/)'));
      expect(
        result.markdown,
        contains('[**Poker Club Manager**](https://github.com/xueyuanhuang/texasholdem)'),
      );

      // Left-right split header lines & italic subheaders preserved
      expect(
        result.markdown,
        contains('**Xiamen University - Singapore Management University (Joint Program)** — *Sep 2022 - Aug 2024*'),
      );
      expect(result.markdown, contains('*Master of Science in Quantitative Finance*'));
      expect(result.markdown, contains('**Business Development, Asia - WorldRouter** — *Jun 2026 - Present*'));

      // Inline bold metrics & skill categories preserved
      expect(result.markdown, contains('**3.92/4.0**'));
      expect(result.markdown, contains('**First-class Scholarship**'));
      expect(result.markdown, contains('**AI & Development:**'));
      expect(result.markdown, contains('**Languages:**'));
    });

    test('Reflows Chinese document with multi-line tables (SolaRee_AI.pdf) into Markdown tables when present', () async {
      final solaFile = File('/Users/wuvist/Desktop/SolaRee_AI.pdf');
      if (!solaFile.existsSync()) return;

      final bytes = solaFile.readAsBytesSync();
      final result = await PdfReflowService.reflowPdfBytes(
        bytes,
        documentTitle: 'SolaRee.AI',
      );

      final doc = await PdfDocument.openData(bytes);
      addTearDown(doc.dispose);
      for (var i = 0; i < doc.pages.length; i++) {
        final pt = await doc.pages[i].loadStructuredText();
        final pa = PdfPageAnalysisService.computePageAnalysis(doc.pages[i], pt);
        expect(pa.isMultiColumn, isFalse, reason: 'Page ${i + 1} of SolaRee_AI.pdf is single-column');
      }
      expect(result.hasContent, isTrue);
      // Title & Chinese section headings
      expect(result.markdown, contains('# SolaRee.AI / 问天星'));
      expect(result.markdown, contains('### 一、产品定义'));
      expect(result.markdown, contains('### 五、功能矩阵'));
      expect(result.markdown, contains('### 七、商业模式与定价思路'));

      // Circled-number subheadings
      expect(result.markdown, contains('#### ① 零隐私架构（Zero PII）'));
      expect(result.markdown, contains('#### ② 换位推演功能'));

      // Table 1 (4 columns, multi-line wrapped cells & vertically centered cells)
      expect(result.markdown, contains('| 功能 | 状态 | 粘性 | 作用 |'));
      expect(
        result.markdown,
        contains('| 八字排盘 + 批命 + 喜忌 + 大运流年 | 已上线 | 低（一次性） | 引流入口，建立专业信任 |'),
      );
      expect(
        result.markdown,
        contains('| 换位推演（档案替换） | 已上线 | 高 | 核心差异化卖点，付费意愿最强 |'),
      );
      expect(
        result.markdown,
        contains('| 生日提醒 + 朋友档案管理 | 已上线/迭代中 | 高 | 将产品转化为人际关系 CRM |'),
      );
      expect(
        result.markdown,
        contains('| 定盘功能（通过问答确定时辰） | 计划中（\\~1 周开发） | 中 | 单独按次收费卖点，企业招聘场景切入点 |'),
      );

      // Table 2 (3 columns)
      expect(result.markdown, contains('| 收费模式 | 适用场景 | 参考定价 |'));
      expect(
        result.markdown,
        contains('| 按次收费 | 轻度用户、单次批命 | 基础模式 |'),
      );
      expect(
        result.markdown,
        contains('| 按时段收费 | 社交聚会场景（2 小时无限量） | 约 ¥100/次 |'),
      );
      expect(
        result.markdown,
        contains('| 月订阅 | 重度用户、人际关系管理 | 约 \\\$10-20/月 |'),
      );
      expect(
        result.markdown,
        contains('| 单次功能付费 | 定盘、企业招聘分析 | 按功能单独定价 |'),
      );

      // Ordered list items & Page 2 single-column reading order (tables stay in their exact sections)
      final idxSec5 = result.markdown.indexOf('### 五、功能矩阵');
      final idxTable1 = result.markdown.indexOf('| 功能 | 状态 | 粘性 | 作用 |');
      final idxSec6 = result.markdown.indexOf('### 六、成本结构');
      final idxSec7 = result.markdown.indexOf('### 七、商业模式与定价思路');
      final idxTable2 = result.markdown.indexOf('| 收费模式 | 适用场景 | 参考定价 |');
      final idxSec8 = result.markdown.indexOf('### 八、下一步计划');
      expect(idxSec5, greaterThan(0));
      expect(idxTable1, greaterThan(idxSec5));
      expect(idxSec6, greaterThan(idxTable1));
      expect(idxSec7, greaterThan(idxSec6));
      expect(idxTable2, greaterThan(idxSec7));
      expect(idxSec8, greaterThan(idxTable2));
      expect(
        result.markdown,
        contains('几位测试用户单日调用超过 100 次，花费约 1 美元。'),
      );
      expect(
        result.markdown,
        contains('需要确定市场定位和定价后，通过试推广来验证。'),
      );
      expect(result.markdown, contains('1. 接入支付系统，开始试运营'));
      final idxItem4 = result.markdown.indexOf('4. 观察用户是否自发将问天星作为人际关系管理工具使用，验证产品定位');
      final idxSec9 = result.markdown.indexOf('### 九、待验证的核心假设');
      expect(idxItem4, greaterThan(0));
      expect(idxSec9, greaterThan(idxItem4));
      expect(result.markdown, isNot(contains('SolaRee_AI_产品定位摘要')));
      expect(result.markdown.trimRight(), isNot(endsWith('\n2')));

      // Verify end-to-end compilation to mobile PDF via ReaderController
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(solaFile.path);
      final enabled = await controller.setPdfReflowMode(true);
      expect(enabled, isTrue);
      expect(controller.isPdfReflowed, isTrue);
      final exportedBytes = await controller.getPdfBytesForExport();
      expect(exportedBytes, isNotNull);
      expect(exportedBytes!.isNotEmpty, isTrue);
    });

    test('Detects and reflows 2-column academic first pages with long full-width abstracts (a_abstract.pdf, g_abs20.pdf)', () async {
      final absFile = File(p.join(projectRoot, 'docs', 'samples', 'a_abstract.pdf'));
      final gAbs20File = File(p.join(projectRoot, 'docs', 'samples', 'g_abs20.pdf'));
      expect(absFile.existsSync(), isTrue);
      expect(gAbs20File.existsSync(), isTrue);

      final absDoc = await PdfDocument.openFile(absFile.path);
      addTearDown(absDoc.dispose);
      final absText = await absDoc.pages[0].loadStructuredText();
      final absAnalysis = PdfPageAnalysisService.computePageAnalysis(absDoc.pages[0], absText);
      expect(absAnalysis.isMultiColumn, isTrue);
      expect(absAnalysis.columns.length, equals(2));

      final absResult = await PdfReflowService.reflowDocument(absDoc);
      final idxLeftEnd = absResult.markdown.indexOf('LEFTEND');
      final idxRightStart = absResult.markdown.indexOf('RIGHTSTART');
      expect(idxLeftEnd, greaterThan(0));
      expect(idxRightStart, greaterThan(idxLeftEnd));

      final gAbsDoc = await PdfDocument.openFile(gAbs20File.path);
      addTearDown(gAbsDoc.dispose);
      final gAbsText = await gAbsDoc.pages[0].loadStructuredText();
      final gAbsAnalysis = PdfPageAnalysisService.computePageAnalysis(gAbsDoc.pages[0], gAbsText);
      expect(gAbsAnalysis.isMultiColumn, isTrue);
      expect(gAbsAnalysis.columns.length, equals(2));

      final gAbsResult = await PdfReflowService.reflowDocument(gAbsDoc);
      final idxL69 = gAbsResult.markdown.indexOf('Leftside sentence L69');
      final idxR1 = gAbsResult.markdown.indexOf('Rightside sentence R1');
      expect(idxL69, greaterThan(0));
      expect(idxR1, greaterThan(idxL69));
    });
  });
}
