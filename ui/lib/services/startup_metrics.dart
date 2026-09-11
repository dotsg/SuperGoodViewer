import 'package:flutter/foundation.dart';

/// Startup timing probes.
///
/// The stopwatch must be started explicitly as the very first statement in
/// `main()`. Declaring it as a top-level `final` with an eager-looking
/// initializer does NOT work: Dart initializes top-level variables lazily, on
/// first read, so a `Stopwatch()..start()` initializer would only begin
/// counting when something first reads the variable — long after startup.
///
/// Note this still excludes Flutter engine and Dart VM initialization, which
/// happen before `main()` runs. For true cold-start figures use
/// `flutter run --profile --trace-startup`, which reports
/// `timeToFirstFrameMicros` measured from engine start.
class StartupMetrics {
  StartupMetrics._();

  static final Stopwatch _stopwatch = Stopwatch();
  static bool _loggedFirstFrame = false;
  static bool _loggedFirstDocument = false;

  /// Call as the first statement in `main()`.
  static void begin() {
    if (!_stopwatch.isRunning) _stopwatch.start();
  }

  /// Milliseconds since [begin], or null if [begin] was never called.
  static int? get elapsedMs => _stopwatch.isRunning ? _stopwatch.elapsedMilliseconds : null;

  /// First frame of the UI shell painted. Measured from `main()`.
  static void markFirstFrame() {
    if (_loggedFirstFrame) return;
    _loggedFirstFrame = true;
    _log('time to first UI frame (shell painted)', elapsedMs);
  }

  /// First document rasterized and on screen. Measured from `main()`.
  static void markFirstDocument() {
    if (_loggedFirstDocument) return;
    _loggedFirstDocument = true;
    _log('time to first document displayed', elapsedMs);
  }

  static void _log(String label, int? ms) {
    // Printed in debug and profile builds (so --trace-startup runs show it),
    // suppressed in release so shipped binaries stay quiet.
    if (kReleaseMode) return;
    debugPrint('[StartupMetrics] $label: ${ms ?? "unmeasured (begin() not called)"} ms');
  }

  @visibleForTesting
  static void resetForTesting() {
    _stopwatch.stop();
    _stopwatch.reset();
    _loggedFirstFrame = false;
    _loggedFirstDocument = false;
  }
}
