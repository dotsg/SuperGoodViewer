// Run explicitly: flutter test --no-pub benchmark/raster_grid_benchmark_test.dart
// Measures native rasterization + Flutter image decoding, NOT screen FPS/GPU upload.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/raster_tile_cache.dart';

import 'support/pdf_fixture.dart';

typedef Scenario = ({String name, Uint8List pdf, double scale, ui.Rect viewport});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('compare grids with the same raster scale, viewport and prefetch extent', () async {
    final cacheDir = Directory.systemTemp.createTempSync('sgv_grid_benchmark_');
    addTearDown(() => cacheDir.deleteSync(recursive: true));
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    // Match the project's native test setup; other platforms use pdfrx discovery.
    final module = File('build/native_assets/macos/libpdfium.dylib');
    if (module.existsSync()) Pdfrx.pdfiumModulePath = module.absolute.path;
    await pdfrxFlutterInitialize();

    final text = makeBenchmarkPdf();
    final scan = makeBenchmarkPdf(scanned: true);
    final scenarios = <Scenario>[
      (name: 'long-text-2x', pdf: text, scale: 2, viewport: const ui.Rect.fromLTWH(0, 1000, 800, 600)),
      (name: 'long-text-4x-crop', pdf: text, scale: 4, viewport: const ui.Rect.fromLTWH(180, 1000, 400, 300)),
      (name: 'synthetic-scan-2x', pdf: scan, scale: 2, viewport: const ui.Rect.fromLTWH(0, 1000, 800, 600)),
      (name: 'synthetic-scan-4x-crop', pdf: scan, scale: 4, viewport: const ui.Rect.fromLTWH(180, 1000, 400, 300)),
      (
        name: 'pdf-page-4x',
        pdf: File('packages/pdfrx/test/assets/multipage40.pdf').readAsBytesSync(),
        scale: 4,
        viewport: const ui.Rect.fromLTWH(50, 80, 400, 300),
      ),
    ];
    const strategies = ['square512', 'square1024', 'strip512', 'adaptive'];
    final results = <Map<String, Object>>[];
    for (final scenario in scenarios) {
      // Discard one warm-up for each strategy; rotate order to reduce order bias.
      for (var round = -1; round < 5; round++) {
        for (var offset = 0; offset < strategies.length; offset++) {
          final index = (offset + (round < 0 ? 0 : round)) % strategies.length;
          final strategy = strategies[index];
          final result = await measure(scenario, strategy);
          if (round >= 0) results.add({'scenario': scenario.name, 'strategy': strategy, 'round': round, ...result});
        }
      }
      // Print progress once per fixture, without distorting timed regions.
      stdout.writeln('Finished ${scenario.name}');
    }
    final summaries = <Map<String, Object>>[];
    for (final scenario in scenarios) {
      for (final strategy in strategies) {
        final samples = results.where((r) => r['scenario'] == scenario.name && r['strategy'] == strategy).toList();
        double median(String key) {
          final values = samples.map((r) => (r[key] as num).toDouble()).toList()..sort();
          return values[values.length ~/ 2];
        }

        final summary = <String, Object>{
          'scenario': scenario.name,
          'strategy': strategy,
          for (final key in [
            'coldVisibleMs',
            'allWorkMs',
            'nextVisibleMs',
            'maxJobMs',
            'jobs',
            'imageMiB',
            'reverseJobs',
          ])
            key: median(key),
        };
        summaries.add(summary);
        stdout.writeln(jsonEncode(summary));
      }
    }
    final output = Platform.environment['SGV_GRID_BENCH_OUTPUT'];
    if (output != null) {
      File(output).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'platform': Platform.operatingSystem,
          'dart': Platform.version,
          'scope': 'flutter test; native render + createImage; no GPU frame timing or process peak memory',
          'repetitions': 5,
          'summary': summaries,
          'samples': results,
        }),
      );
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}

Future<Map<String, Object>> measure(Scenario scenario, String strategy) async {
  final document = await PdfDocument.openData(scenario.pdf, useProgressiveLoading: false);
  final images = <RasterTileKey, ui.Image>{};
  try {
    final page = document.pages.first;
    final pageRect = ui.Rect.fromLTWH(0, 0, page.width, page.height);
    final RasterTileGrid grid = switch (strategy) {
      'square1024' => (width: 1024, height: 1024),
      'strip512' => (width: (page.width * scenario.scale).ceil(), height: 512),
      'adaptive' => RasterTileRegion.gridFor(pageRect, scenario.scale),
      _ => RasterTileRegion.defaultGrid,
    };
    var jobs = 0;
    var maxJobUs = 0;
    var allWorkUs = 0;
    var coldVisibleUs = 0;
    var nextVisibleUs = 0;
    var reverseJobs = 0;
    for (var step = 0; step < 3; step++) {
      final before = jobs;
      final visible = scenario.viewport.shift(ui.Offset(0, step == 1 ? scenario.viewport.height : 0));
      final target = visible.inflateHV(vertical: visible.height * 1.5, horizontal: 0);
      final visibleKeys = RasterTileRegion.covering(
        1,
        pageRect,
        visible,
        scenario.scale,
        grid: grid,
      ).map((r) => r.key).toSet();
      final regions = RasterTileRegion.covering(1, pageRect, target, scenario.scale, grid: grid).toList()
        ..sort((a, b) {
          final av = visibleKeys.contains(a.key), bv = visibleKeys.contains(b.key);
          if (av != bv) return av ? -1 : 1;
          return (a.rect.center - visible.center).distanceSquared.compareTo(
            (b.rect.center - visible.center).distanceSquared,
          );
        });
      final elapsed = Stopwatch()..start();
      var visibleUs = 0;
      var ready = visibleKeys.every(images.containsKey);
      for (final region in regions) {
        if (images.containsKey(region.key)) continue;
        final jobTime = Stopwatch()..start();
        final bitmap = await page.render(
          x: region.x,
          y: region.y,
          width: region.width,
          height: region.height,
          fullWidth: page.width * scenario.scale,
          fullHeight: page.height * scenario.scale,
          backgroundColor: 0xffffffff,
        );
        if (bitmap == null) throw StateError('Failed to render ${region.key}');
        try {
          images[region.key] = await bitmap.createImage();
        } finally {
          bitmap.dispose();
        }
        maxJobUs = math.max(maxJobUs, jobTime.elapsedMicroseconds);
        jobs++;
        if (!ready && visibleKeys.every(images.containsKey)) {
          visibleUs = elapsed.elapsedMicroseconds;
          ready = true;
        }
      }
      if (!ready) throw StateError('Missing visible raster');
      allWorkUs += elapsed.elapsedMicroseconds;
      if (step == 0) coldVisibleUs = visibleUs;
      if (step == 1) nextVisibleUs = visibleUs;
      if (step == 2) reverseJobs = jobs - before;
    }
    return {
      'coldVisibleMs': coldVisibleUs / 1000,
      'allWorkMs': allWorkUs / 1000,
      'nextVisibleMs': nextVisibleUs / 1000,
      'maxJobMs': maxJobUs / 1000,
      'jobs': jobs,
      'reverseJobs': reverseJobs,
      'imageMiB': images.values.fold<int>(0, (n, image) => n + image.width * image.height * 4) / (1024 * 1024),
    };
  } finally {
    for (final image in images.values) {
      image.dispose();
    }
    await document.dispose();
  }
}
