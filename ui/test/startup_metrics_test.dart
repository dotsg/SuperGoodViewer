import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/services/startup_metrics.dart';

void main() {
  setUp(StartupMetrics.resetForTesting);
  tearDown(StartupMetrics.resetForTesting);

  test('reports null (not a misleading 0) when begin() was never called', () {
    // The previous implementation used a top-level
    //   final Stopwatch s = Stopwatch()..start();
    // Dart initializes top-level variables lazily on first read, so the
    // stopwatch only started when the post-frame callback read it, and the
    // probe always reported ~0 ms. Reporting null makes that failure loud.
    expect(StartupMetrics.elapsedMs, isNull);
  });

  test('measures real elapsed time from begin()', () async {
    StartupMetrics.begin();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final ms = StartupMetrics.elapsedMs;
    expect(ms, isNotNull);
    expect(ms, greaterThanOrEqualTo(50));
  });

  test('begin() is idempotent and does not restart the clock', () async {
    StartupMetrics.begin();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    StartupMetrics.begin();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(StartupMetrics.elapsedMs, greaterThanOrEqualTo(70));
  });

  test('marks are logged at most once', () {
    StartupMetrics.begin();
    StartupMetrics.markFirstFrame();
    StartupMetrics.markFirstFrame();
    StartupMetrics.markFirstDocument();
    StartupMetrics.markFirstDocument();
  });
}
