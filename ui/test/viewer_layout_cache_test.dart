import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'support/raster_document.dart';

Future<void> advance(WidgetTester tester, [int frames = 15]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
  }
}

class ResizedPage extends RasterTestPage {
  ResizedPage(PdfDocument document) : super(document, 1, isLoaded: true);

  @override
  double get height => 1200;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDir;
  setUpAll(() async {
    cacheDir = Directory.systemTemp.createTempSync('sgv_layout_cache_');
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    final module = File('build/native_assets/macos/libpdfium.dylib');
    if (module.existsSync()) Pdfrx.pdfiumModulePath = module.absolute.path;
    await pdfrxFlutterInitialize();
  });
  tearDownAll(() => cacheDir.deleteSync(recursive: true));

  for (final pageCount in [1, 1000]) {
    testWidgets(
      'reuses $pageCount page layout on scroll; invalidates on real changes',
      (tester) async {
        final document = RasterTestDocument(
          pageCount,
          pageHeight: pageCount == 1 ? 40000 : 800,
        );
        addTearDown(document.dispose);
        final controller = PdfViewerController();
        var layouts = 0;
        var extraGap = 0.0;
        final params = PdfViewerParams(
          enableTiledRendering: true,
          textSelectionParams: const PdfTextSelectionParams(enabled: false),
          layoutPages: (pages, params) {
            layouts++;
            var y = 0.0;
            final rects = <Rect>[];
            for (final page in pages) {
              rects.add(Rect.fromLTWH(0, y, page.width, page.height));
              y += page.height + extraGap;
            }
            return PdfPageLayout(
              pageLayouts: rects,
              documentSize: Size(600, y),
            );
          },
        );
        Widget viewer() => MaterialApp(
          home: PdfViewer(
            PdfDocumentRefDirect(document, autoDispose: false),
            controller: controller,
            params: params,
          ),
        );
        await tester.pumpWidget(viewer());
        await advance(tester, 40);
        expect(controller.isReady, isTrue);
        final initial = layouts;
        final initialLayout = controller.layout;
        for (var i = 0; i < 60; i++) {
          final matrix = controller.value.clone();
          matrix.storage[13] -= 1;
          controller.value = matrix;
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          layouts,
          initial,
          reason: 'Panning and raster completion must reuse page geometry',
        );
        expect(identical(controller.layout, initialLayout), isTrue);

        tester.view.physicalSize = const Size(900, 700);
        addTearDown(tester.view.resetPhysicalSize);
        await advance(tester);
        expect(
          layouts,
          greaterThan(initial),
          reason: 'Resize must re-evaluate custom layouts',
        );

        var before = layouts;
        extraGap = 5;
        await tester.pumpWidget(viewer());
        await advance(tester);
        expect(
          layouts,
          greaterThan(before),
          reason: 'Parent updates can change captured layout inputs',
        );
        expect(
          controller.documentSize.height,
          initialLayout.documentSize.height + 5 * pageCount,
        );

        before = layouts;
        extraGap = 10;
        controller.invalidate();
        await advance(tester);
        expect(layouts, greaterThan(before));
        expect(
          controller.documentSize.height,
          initialLayout.documentSize.height + 10 * pageCount,
        );

        before = layouts;
        document.replacePage(ResizedPage(document));
        await advance(tester);
        expect(
          layouts,
          greaterThan(before),
          reason: 'Page measurement/replacement must invalidate layout',
        );
        expect(controller.layout.pageLayouts.first.height, 1200);

        before = layouts;
        await controller.goToPosition(
          documentOffset: Offset.zero,
          zoom: controller.currentZoom * 1.1,
        );
        await advance(tester);
        expect(
          layouts,
          greaterThan(before),
          reason: 'Zoom-dependent custom layouts must still update',
        );

        final replacement = RasterTestDocument(
          2,
          pageHeight: 500,
          sourceName: 'test:layout-replacement',
        );
        addTearDown(replacement.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: PdfViewer(
              PdfDocumentRefDirect(replacement, autoDispose: false),
              controller: controller,
              params: params,
            ),
          ),
        );
        await advance(tester, 40);
        expect(controller.layout.pageLayouts.length, 2);
        expect(controller.documentSize.height, 1020);

        await tester.pumpWidget(const SizedBox.shrink());
        await advance(tester, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
