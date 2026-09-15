import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/raster_tile_cache.dart';

import 'support/raster_document.dart';

Future<void> advance(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory cacheDir;
  setUpAll(() async {
    cacheDir = Directory.systemTemp.createTempSync('sgv_tiled_viewer_');
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    for (final path in [
      'build/native_assets/macos/libpdfium.dylib',
      '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-arm64/libpdfium.dylib',
      '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-x64/libpdfium.dylib',
    ]) {
      if (File(path).existsSync()) {
        Pdfrx.pdfiumModulePath = File(path).absolute.path;
        break;
      }
    }
    await pdfrxFlutterInitialize();
  });
  tearDownAll(() => cacheDir.deleteSync(recursive: true));

  testWidgets('long page prefetches sharp tiles and retains them while scrolling', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final document = RasterTestDocument(1, pageHeight: 40000);
    addTearDown(document.dispose);
    final page = document.pages.first as RasterTestPage;
    page.renderControl.block();
    final controller = PdfViewerController();
    var sharp = false;
    var loaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: PdfViewerParams(
            enableTiledRendering: true,
            verticalCacheExtent: 1.5,
            sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: (_, _, _, _) => 1),
            onVisiblePagesRendered: (ready) => sharp = ready,
            onDocumentLoadFinished: (_, ready) => loaded = ready,
            behaviorControlParams: const PdfViewerBehaviorControlParams(
              enableLowResolutionPagePreview: false,
              trailingPageLoadingDelay: Duration.zero,
            ),
          ),
        ),
      ),
    );
    await advance(tester, 5);
    expect(controller.isReady, isTrue);
    expect(sharp, isFalse, reason: 'Layout readiness must not imply raster readiness');
    expect(loaded, isFalse);
    page.renderControl.release();
    await advance(tester, 80);
    expect(sharp, isTrue);
    expect(loaded, isTrue, reason: 'Completion must also work with previews disabled');
    final renders = page.renderControl.requestedRegions;
    expect(renders.every((r) => r.width! <= 2048 && r.height! <= 516), isTrue);
    expect(
      renders.every((r) => r.x == 0 && r.width == r.fullWidth),
      isTrue,
      reason: 'Narrow long pages use full-width raster strips without virtual PDF pages',
    );
    expect(renders.every((r) => r.fullHeight == 80000), isTrue, reason: 'Tiles must use Retina resolution');
    expect(
      renders.any((r) => r.y > controller.visibleRect.bottom * 2),
      isTrue,
      reason: 'Full resolution must be rendered outside the visible viewport',
    );
    final renderedBeforeScroll = renders.toSet();
    for (var y = 10.0; y <= 300; y += 10) {
      controller.goToPosition(documentOffset: Offset(0, y));
      await advance(tester, 1);
      expect(sharp, isTrue, reason: 'Scrolling inside the prefetched region should stay sharp');
    }
    await advance(tester, 40);
    final countBeforeReturn = renders.length;
    controller.goToPosition(documentOffset: const Offset(0, 10));
    await advance(tester, 20);
    expect(sharp, isTrue);
    expect(renders.length, countBeforeReturn, reason: 'Returning to cached tiles must not render again');
    for (final cached in renderedBeforeScroll) {
      expect(renders.where((r) => r == cached).length, 1, reason: 'Previously cached tiles must not be rerendered');
    }
    expect(renderedBeforeScroll.length, greaterThan(1));
    final beforeZoom = renders.length;
    controller.goToPosition(documentOffset: const Offset(0, 10), zoom: 3);
    await advance(tester, 80);
    expect(sharp, isTrue);
    final zoomRenders = renders.skip(beforeZoom).toList();
    expect(zoomRenders, isNotEmpty);
    expect(
      zoomRenders.every((r) => r.width! <= 516 && r.height! <= 516),
      isTrue,
      reason: 'Zooming past the strip width limit must switch to square tiles',
    );
    controller.goToPosition(documentOffset: const Offset(0, 10), zoom: 1);
    await advance(tester, 30);
    expect(sharp, isTrue);
    for (final cached in renderedBeforeScroll) {
      expect(
        renders.where((r) => r == cached).length,
        1,
        reason: 'Returning from squares to strips must reuse the earlier scale',
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, 2);
    expect(tester.takeException(), isNull);
  });

  test('native PDFium tiles preserve raster geometry at fractional scale', () async {
    final document = await PdfDocument.openData(
      File('packages/pdfrx/test/assets/multipage40.pdf').readAsBytesSync(),
      sourceName: 'tile-pixel-comparison',
      useProgressiveLoading: false,
    );
    addTearDown(document.dispose);
    final page = document.pages.first;
    const scale = 2.125;
    final rect = Rect.fromLTWH(0, 0, page.width, page.height);
    final full = (await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: 0xffffffff,
    ))!;
    addTearDown(full.dispose);
    for (final grid in [
      RasterTileRegion.defaultGrid,
      (width: 1024, height: 1024),
      (width: (page.width * scale).ceil(), height: 512),
    ]) {
      final regions = RasterTileRegion.covering(1, rect, rect, scale, grid: grid).toList();
      // Check both sides of horizontal/vertical boundaries and the last edge tile.
      for (final index in {0, 1, 3, regions.length - 1}.where((i) => i < regions.length)) {
        final region = regions[index];
        final tile = (await page.render(
          x: region.x,
          y: region.y,
          width: region.width,
          height: region.height,
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          backgroundColor: 0xffffffff,
        ))!;
        try {
          final startRow = region.coreY - region.y;
          final startColumn = region.coreX - region.x;
          final rows = grid.height.clamp(0, full.height - region.coreY);
          final columns = grid.width.clamp(0, full.width - region.coreX);
          var deltaSum = 0, largeDeltas = 0;
          for (var row = 0; row < rows; row++) {
            final start = ((region.coreY + row) * full.width + region.coreX) * 4;
            final tileStart = ((startRow + row) * tile.width + startColumn) * 4;
            for (var col = 0; col < columns * 4; col++) {
              final delta = (tile.pixels[tileStart + col] - full.pixels[start + col]).abs();
              deltaSum += delta;
              if (delta > 32) largeDeltas++;
            }
          }
          final channels = rows * columns * 4;
          // Native PDFium's translated text antialiasing can differ at a few
          // glyph pixels. This tolerance rejects coordinate/scale errors without
          // requiring byte-identical antialiasing (observed mean delta < 0.007).
          expect(deltaSum / channels, lessThan(0.05));
          expect(largeDeltas / channels, lessThan(0.0005));
        } finally {
          tile.dispose();
        }
      }
    }
  });

  testWidgets('ordinary page previews survive leaving the cache extent under budget', (tester) async {
    final document = RasterTestDocument(8);
    addTearDown(document.dispose);
    final controller = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfViewer(
          PdfDocumentRefDirect(document, autoDispose: false),
          controller: controller,
          params: PdfViewerParams(
            enableTiledRendering: true,
            verticalCacheExtent: 0,
            sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(calculateInitialZoom: (_, _, _, _) => 1),
            getPageRenderingScale: (_, _, _, _) => 3,
            behaviorControlParams: const PdfViewerBehaviorControlParams(trailingPageLoadingDelay: Duration.zero),
          ),
        ),
      ),
    );
    await advance(tester, 40);
    final first = (document.pages.first as RasterTestPage).renderControl;
    final before = first.renderCount;
    expect(before, greaterThan(0));
    controller.goToPage(pageNumber: 7, duration: Duration.zero);
    await advance(tester, 40);
    controller.goToPage(pageNumber: 1, duration: Duration.zero);
    await advance(tester, 40);
    expect(first.renderCount, before, reason: 'Below-budget previews must not be evicted');
    await tester.pumpWidget(const SizedBox.shrink());
    await advance(tester, 2);
  });
}
