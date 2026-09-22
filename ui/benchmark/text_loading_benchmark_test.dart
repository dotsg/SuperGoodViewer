// Native extraction + formatting latency and caller-isolate event-loop gaps.
// This is not a GPU/frame-rate benchmark. Run separately from the test suite.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdfrx/src/widgets/internals/page_text_loader.dart';

import 'support/pdf_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('text loading latency and event-loop responsiveness', () async {
    final cacheDir = Directory.systemTemp.createTempSync('sgv_text_benchmark_');
    addTearDown(() => cacheDir.deleteSync(recursive: true));
    Pdfrx.cacheDirectoryPath = cacheDir.path;
    final module = File('build/native_assets/macos/libpdfium.dylib');
    if (module.existsSync()) Pdfrx.pdfiumModulePath = module.absolute.path;
    await pdfrxFlutterInitialize();

    final samples = <Map<String, Object>>[];
    final fixtures = {
      'long-text': makeBenchmarkPdf(),
      'ordinary-page': File('packages/pdfrx/test/assets/multipage40.pdf')
          .readAsBytesSync(),
    };
    for (final fixture in fixtures.entries) {
      for (var round = -1; round < 5; round++) {
        // Warm both paths, then alternate order. Each sample opens a fresh PDF.
        for (final optimized in round.isEven ? [true, false] : [false, true]) {
          final document = await PdfDocument.openData(
            fixture.value,
            useProgressiveLoading: false,
          );
          try {
            final clock = Stopwatch()..start();
            var lastTick = clock.elapsedMicroseconds;
            var maxGapUs = 0;
            final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
              final now = clock.elapsedMicroseconds;
              maxGapUs = math.max(maxGapUs, now - lastTick);
              lastTick = now;
            });
            late PdfPageText text;
            late int elapsedUs;
            try {
              await Future<void>.delayed(const Duration(milliseconds: 3));
              final start = clock.elapsedMicroseconds;
              text = optimized
                  ? await loadStructuredPageText(document.pages.first)
                  : await document.pages.first.loadStructuredText();
              elapsedUs = clock.elapsedMicroseconds - start;
              // Let the heartbeat observe a blocking completion before stopping.
              await Future<void>.delayed(const Duration(milliseconds: 3));
            } finally {
              timer.cancel();
            }
            if (round >= 0) {
              samples.add({
                'fixture': fixture.key,
                'strategy': optimized ? 'background-long-text' : 'upstream',
                'round': round,
                'characters': text.fullText.length,
                'totalMs': elapsedUs / 1000,
                'maxEventLoopGapMs': maxGapUs / 1000,
              });
            }
          } finally {
            await document.dispose();
          }
        }
      }
    }
    final summary = <Map<String, Object>>[];
    for (final fixture in fixtures.keys) {
      for (final strategy in ['upstream', 'background-long-text']) {
        final group = samples
            .where((s) => s['fixture'] == fixture && s['strategy'] == strategy)
            .toList();
        double median(String key) {
          final values = group.map((s) => (s[key] as num).toDouble()).toList()
            ..sort();
          return values[values.length ~/ 2];
        }

        final row = <String, Object>{
          'fixture': fixture,
          'strategy': strategy,
          'totalMs': median('totalMs'),
          'maxEventLoopGapMs': median('maxEventLoopGapMs'),
        };
        summary.add(row);
        stdout.writeln(jsonEncode(row));
      }
    }
    final output = Platform.environment['SGV_TEXT_BENCH_OUTPUT'];
    if (output != null) {
      File(output).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'scope': 'flutter test; native extraction + formatting, not GPU frame timing',
          'dart': Platform.version,
          'platform': Platform.operatingSystem,
          'summary': summary,
          'samples': samples,
        }),
      );
    }
  });
}
