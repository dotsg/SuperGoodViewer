import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/indexed_page_text.dart';
import 'package:pdfrx/src/widgets/internals/page_text_cache.dart';
import 'package:pdfrx/src/widgets/internals/page_text_loader.dart';

import '../benchmark/support/pdf_fixture.dart';
import 'support/raster_document.dart';

class TextPage extends RasterTestPage {
  TextPage(PdfDocument document, this.text, {int pageNumber = 1})
    : super(document, pageNumber, isLoaded: true);
  final String text;
  Completer<void>? gate;
  int loads = 0;
  bool fail = false;

  @override
  Future<PdfPageRawText?> loadText() async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('text extraction failed');
    return PdfPageRawText(text, [
      for (var i = 0; i < text.length; i++) PdfRect(i * 6, 20, (i + 1) * 6, 10),
    ]);
  }
}

Future<void> advance(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

void expectSameText(PdfPageText actual, PdfPageText expected) {
  expect(actual.pageNumber, expected.pageNumber);
  expect(actual.fullText, expected.fullText);
  expect(actual.charRects, expected.charRects);
  expect(actual.fragments.length, expected.fragments.length);
  for (var i = 0; i < actual.fragments.length; i++) {
    final a = actual.fragments[i], b = expected.fragments[i];
    expect(
      (a.index, a.length, a.direction, a.bounds),
      (b.index, b.length, b.direction, b.bounds),
    );
    expect(a.charRects, b.charRects);
    expect(identical(a.pageText, actual), isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDir;
  setUpAll(() async {
    cacheDir = Directory.systemTemp.createTempSync('sgv_text_cache_');
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    final module = File('build/native_assets/macos/libpdfium.dylib');
    if (module.existsSync()) Pdfrx.pdfiumModulePath = module.absolute.path;
    await pdfrxFlutterInitialize();
  });
  tearDownAll(() => cacheDir.deleteSync(recursive: true));

  test(
    'coalesces text requests and retains all distinct completion callbacks',
    () async {
      final document = RasterTestDocument(1);
      addTearDown(document.dispose);
      final page = TextPage(document, 'Shared text')..gate = Completer<void>();
      final cache = PageTextCache();
      var paints = 0, selections = 0;
      void paint() => paints++;
      final first = cache.load(page, onLoaded: paint);
      final second = cache.load(page, onLoaded: paint);
      final third = cache.load(page, onLoaded: () => selections++);
      expect(identical(first, second), isTrue);
      page.gate!.complete();
      final results = await Future.wait([first, second, third]);
      expect(page.loads, 1);
      expect(results.every((text) => identical(text, results.first)), isTrue);
      expect(paints, 1);
      expect(selections, 1);
      expect(identical(await cache.load(page), results.first), isTrue);
    },
  );

  for (final clearDocument in [false, true]) {
    test(
      'rejects stale text after ${clearDocument ? 'document' : 'page'} replacement',
      () async {
        final document = RasterTestDocument(1);
        addTearDown(document.dispose);
        final oldPage = TextPage(document, 'Old')..gate = Completer<void>();
        final newPage = TextPage(document, 'New');
        final cache = PageTextCache();
        var oldCallbacks = 0;
        final old = cache.load(oldPage, onLoaded: () => oldCallbacks++);
        await Future<void>.delayed(Duration.zero);
        expect(oldPage.loads, 1);
        if (clearDocument) {
          cache.clear();
        } else {
          cache.invalidatePage(1);
        }
        final replacement = cache.load(newPage);
        oldPage.gate!.complete();
        expect(await old, isNull);
        expect((await replacement)!.fullText, 'New');
        expect(cache[1]!.fullText, 'New');
        expect(oldCallbacks, 0);
      },
    );
  }

  test('failed extraction can be retried', () async {
    final document = RasterTestDocument(1);
    addTearDown(document.dispose);
    final page = TextPage(document, 'Recovered')..fail = true;
    final cache = PageTextCache();
    await expectLater(cache.load(page), throwsStateError);
    page.fail = false;
    expect((await cache.load(page))!.fullText, 'Recovered');
    expect(page.loads, 2);
  });

  test('native long-page and ordinary-page text preserve selection/search geometry', () async {
    for (final bytes in [
      makeBenchmarkPdf(),
      File('packages/pdfrx/test/assets/multipage40.pdf').readAsBytesSync(),
    ]) {
      final document = await PdfDocument.openData(
        bytes,
        useProgressiveLoading: false,
      );
      try {
        final page = document.pages.first;
        final original = await page.loadStructuredText();
        final optimized = await loadStructuredPageText(page);
        expectSameText(optimized, original);
      } finally {
        await document.dispose();
      }
    }
  });

  testWidgets('painting and searching share a pending extraction', (
    tester,
  ) async {
    final document = RasterTestDocument(1);
    addTearDown(document.dispose);
    final page = TextPage(document, 'Read and search')
      ..gate = Completer<void>();
    document.pages = [page];
    final controller = PdfViewerController();
    var sharp = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: PdfViewerParams(
            enableTiledRendering: true,
            onVisiblePagesRendered: (ready) => sharp = ready,
            textSelectionParams: const PdfTextSelectionParams(enabled: true),
            behaviorControlParams: const PdfViewerBehaviorControlParams(
              trailingPageLoadingDelay: Duration.zero,
              pageImageCachingDelay: Duration.zero,
              partialImageLoadingDelay: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await advance(tester, 80);
    expect(page.loads, 1, reason: 'Paint requests text before search starts');
    expect(
      sharp,
      isTrue,
      reason: 'Pending text must not block visible raster readiness',
    );
    final searcher = PdfTextSearcher(controller);
    final searching = searcher.loadText(pageNumber: 1);
    page.gate!.complete();
    await advance(tester);
    final text = await searching;
    expect(text!.fullText, 'Read and search');
    expect(identical(await controller.loadPageText(1), text), isTrue);
    expect(page.loads, 1);
    searcher.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, 2);
    expect(tester.takeException(), isNull);
  });

  test('PageTextCache bounds memory with LRU eviction', () async {
    final document = RasterTestDocument(10);
    addTearDown(document.dispose);
    final cache = PageTextCache(maxCachedPages: 3);
    for (var i = 1; i <= 5; i++) {
      final page = TextPage(document, 'Page $i', pageNumber: i);
      await cache.load(page);
    }
    expect(cache.cachedCount, 3);
    // Oldest pages (1 and 2) should have been evicted
    expect(cache[1], isNull);
    expect(cache[2], isNull);
    // Pages 3, 4, 5 should be retained
    expect(cache[3]?.fullText, 'Page 3');
    expect(cache[4]?.fullText, 'Page 4');
    expect(cache[5]?.fullText, 'Page 5');
  });

  test('PageTextCache processes priority requests before pending background requests', () async {
    final document = RasterTestDocument(5);
    addTearDown(document.dispose);
    final cache = PageTextCache();
    final page1 = TextPage(document, 'Page 1', pageNumber: 1)..gate = Completer<void>();
    final page2 = TextPage(document, 'Page 2', pageNumber: 2);
    final page3 = TextPage(document, 'Page 3', pageNumber: 3);

    // Start background request 1 (held at gate)
    final f1 = cache.load(page1, isPriority: false);
    // Queue background request 2
    final f2 = cache.load(page2, isPriority: false);
    // Queue priority request 3
    final f3 = cache.load(page3, isPriority: true);

    final completedOrder = <int>[];
    f1.then((_) => completedOrder.add(1));
    f2.then((_) => completedOrder.add(2));
    f3.then((_) => completedOrder.add(3));

    // Release page 1
    page1.gate!.complete();
    await Future.wait([f1, f2, f3]);

    // Priority request 3 must complete before background request 2
    expect(completedOrder, [1, 3, 2]);
  });

  test('TextFragmentIndex boundary: threshold is 512 fragments', () {
    PdfPageText makeFakeText(int fragmentCount) {
      final fragments = <PdfPageTextFragment>[];
      final pageText = PdfPageText(
        pageNumber: 1,
        fullText: 'A' * fragmentCount,
        charRects: [for (var i = 0; i < fragmentCount; i++) PdfRect(0, (i + 1) * 10, 100, i * 10)],
        fragments: fragments,
      );
      for (var i = 0; i < fragmentCount; i++) {
        fragments.add(
          PdfPageTextFragment(
            pageText: pageText,
            index: i,
            length: 1,
            bounds: PdfRect(0, (i + 1) * 10, 100, i * 10),
            charRects: [PdfRect(0, (i + 1) * 10, 100, i * 10)],
            direction: PdfTextDirection.ltr,
          ),
        );
      }
      return pageText;
    }

    final sub512 = IndexedPageText(makeFakeText(511));
    expect(sub512.isIndexed, isFalse);

    final exact512 = IndexedPageText(makeFakeText(512));
    expect(exact512.isIndexed, isTrue);
  });

  test('PageTextCache resolves unstarted queued requests on invalidatePage', () async {
    final document = RasterTestDocument(5);
    addTearDown(document.dispose);
    final cache = PageTextCache();
    final p1 = TextPage(document, 'P1', pageNumber: 1)..gate = Completer<void>();
    final p2 = TextPage(document, 'P2', pageNumber: 2);

    final f1 = cache.load(p1);
    final f2 = cache.load(p2); // Queued, loads == 0

    expect(p2.loads, 0, reason: 'p2 has not started executing yet');

    cache.invalidatePage(2);
    // f2 MUST resolve to null rather than hanging forever
    final res2 = await f2.timeout(const Duration(milliseconds: 200));
    expect(res2, isNull);

    p1.gate!.complete();
    final res1 = await f1;
    expect(res1?.fullText, 'P1');
  });

  test('PageTextCache resolves unstarted queued requests on clear', () async {
    final document = RasterTestDocument(5);
    addTearDown(document.dispose);
    final cache = PageTextCache();
    final p1 = TextPage(document, 'P1', pageNumber: 1)..gate = Completer<void>();
    final p2 = TextPage(document, 'P2', pageNumber: 2);

    final f1 = cache.load(p1);
    final f2 = cache.load(p2); // Queued, loads == 0

    cache.clear();
    // Both f1 and f2 MUST resolve to null
    final res2 = await f2.timeout(const Duration(milliseconds: 200));
    expect(res2, isNull);

    p1.gate!.complete();
    final res1 = await f1.timeout(const Duration(milliseconds: 200));
    expect(res1, isNull);
  });

  testWidgets('queued searcher loadText resolves and does not hang on replacePage', (tester) async {
    final document = RasterTestDocument(2);
    addTearDown(document.dispose);
    final p1 = TextPage(document, 'P1', pageNumber: 1)..gate = Completer<void>();
    final p2 = TextPage(document, 'P2', pageNumber: 2);
    document.pages = [p1, p2];

    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: const PdfViewerParams(enableTiledRendering: true),
        ),
      ),
    );
    await advance(tester, 40);

    final searcher = PdfTextSearcher(controller);
    // Queue search for page 2 while page 1 extraction is held by gate
    final searching2 = searcher.loadText(pageNumber: 2);

    // Trigger page replacement while request 2 is queued
    final replacementP2 = TextPage(document, 'P2 replacement', pageNumber: 2);
    document.replacePage(replacementP2);
    await advance(tester, 5);

    // searching2 must resolve to null rather than hanging forever
    final text2 = await searching2.timeout(const Duration(milliseconds: 500));
    expect(text2, isNull);

    p1.gate!.complete();
    await advance(tester);
    searcher.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, 2);
    expect(tester.takeException(), isNull);
  });

  test('TextFragmentIndex parity with O(N) scan on real benchmark document and rotation', () async {
    final bytes = makeBenchmarkPdf();
    final document = await PdfDocument.openData(bytes);
    addTearDown(document.dispose);

    final page = document.pages.first;
    final indexed = await loadIndexedPageText(page);
    expect(indexed.isIndexed, isTrue);
    expect(indexed.text.fragments.length, greaterThan(512));

    const margin = 3.0;

    // Test across unrotated, 90-degree and 270-degree rotation
    for (final rot in [PdfPageRotation.none, PdfPageRotation.clockwise90, PdfPageRotation.clockwise270]) {
      final testPage = _RotatedPageWrapper(page, rot);
      final pageRect = Rect.fromLTWH(0, 0, testPage.width, testPage.height);

      final ySteps = testPage.height > 1000
          ? [for (final base in [0.0, 5000.0, 15000.0, 35000.0]) ...[for (var d = 0.0; d <= 400.0; d += 50.0) base + d]]
          : [for (var y = 0.0; y <= testPage.height; y += 40.0) y];

      for (var x = 0.0; x <= testPage.width + 30; x += (testPage.width > 1000 ? 500.0 : 80.0)) {
        for (final y in ySteps) {
          final pos = Offset(x, y);
          final indexedHit = indexed.hitTest(
            page: testPage,
            pageRect: pageRect,
            position: pos,
            margin: margin,
          );
          // Naive linear scan
          var linearHit = false;
          for (final f in indexed.text.fragments) {
            if (f.bounds.toRectInDocument(page: testPage, pageRect: pageRect).inflate(margin).contains(pos)) {
              linearHit = true;
              break;
            }
          }
          expect(
            indexedHit,
            linearHit,
            reason: 'Mismatch at rotation $rot point ($x, $y)',
          );
        }
      }
    }
  });
}

class _RotatedPageWrapper implements PdfPage {
  _RotatedPageWrapper(this._page, this.rotation);
  final PdfPage _page;
  @override
  final PdfPageRotation rotation;

  @override
  PdfDocument get document => _page.document;
  @override
  int get pageNumber => _page.pageNumber;
  @override
  double get width => rotation == PdfPageRotation.clockwise90 || rotation == PdfPageRotation.clockwise270 ? _page.height : _page.width;
  @override
  double get height => rotation == PdfPageRotation.clockwise90 || rotation == PdfPageRotation.clockwise270 ? _page.width : _page.height;
  @override
  bool get isLoaded => _page.isLoaded;
  @override
  Future<PdfPageRawText?> loadText() => _page.loadText();
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) =>
      _page.loadLinks(compact: compact, enableAutoLinkDetection: enableAutoLinkDetection);
  @override
  PdfPageRenderCancellationToken createCancellationToken() => _page.createCancellationToken();
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) => _page.render(
        x: x,
        y: y,
        width: width,
        height: height,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
        backgroundColor: backgroundColor,
        rotationOverride: rotationOverride,
        annotationRenderingMode: annotationRenderingMode,
        flags: flags,
        cancellationToken: cancellationToken,
      );
}
