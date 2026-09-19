import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/bridge/native_engine.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('sgv_degraded_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  Future<void> waitCompile(
    ReaderController controller, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      if (!controller.isCompiling) return;
      await Future.delayed(const Duration(milliseconds: 20));
    }
    fail('Timed out waiting for compilation to complete within $timeout');
  }

  test('NativeEngine: reports degraded equation count and formulas', () async {
    expect(NativeEngine.instance.isAvailable, isTrue);

    const testMarkdown = '''# Degradation Test

\$\$\\brokencommand{xyz}\$\$

Normal equation:
\$\$E = mc^2\$\$

\$\$\\alsobroken{123}\$\$
''';

    final result = await NativeEngine.instance.compileMarkdownResultAsync(
      testMarkdown,
      title: 'Degradation Test',
    );

    expect(result.isSuccess, isTrue);
    expect(result.degradedEquationCount, equals(2));
    expect(result.degradedEquations.length, equals(2));
    expect(result.degradedEquations.any((eq) => eq.contains(r'\brokencommand{xyz}')), isTrue);
    expect(result.degradedEquations.any((eq) => eq.contains(r'\alsobroken{123}')), isTrue);
  });

  test('ReaderController: exposes degraded equations on compilation', () async {
    final controller = ReaderController(autoRestorePreferences: false);

    final testFile = File(p.join(tempTestDir.path, 'broken_eq.md'));
    testFile.writeAsStringSync('''# Broken Equation Doc

\$\$\\invalidmacro{formula}\$\$
''');

    await controller.openFile(testFile.path);
    await waitCompile(controller);

    expect(controller.currentPdfBytes, isNotNull);
    expect(controller.hasDegradedEquations, isTrue);
    expect(controller.degradedEquationCount, equals(1));
    expect(controller.degradedEquations.first, contains(r'\invalidmacro{formula}'));
  });

  testWidgets('WorkspaceView: displays floating amber banner when equations degrade and allows dismiss', (tester) async {
    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    final testFile = File(p.join(tempTestDir.path, 'broken_ui.md'));
    testFile.writeAsStringSync('''# Broken Doc

\$\$\\unsupportedcmd{abc}\$\$
''');

    await controller.openFile(testFile.path);
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (controller.isCompiling || controller.degradedEquationCount == 0) {
      if (DateTime.now().isAfter(end)) {
        fail(
          'Timed out waiting for broken doc compilation: isCompiling=${controller.isCompiling}, degradedCount=${controller.degradedEquationCount}',
        );
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceView(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('1 个公式渲染异常'), findsOneWidget);

    // While toolbar is visible on startup, banner floats at bannerTierToolbar
    final initialPos = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('degraded_warning_positioned')));
    expect(initialPos.bottom, equals(WorkspaceView.bannerTierToolbar));

    // When toolbar autohides in Zen mode (3500ms timer), banner smoothly slides down to bannerTierZen
    await tester.pump(const Duration(milliseconds: 3600));
    await tester.pumpAndSettle();
    final zenPos = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('degraded_warning_positioned')));
    expect(zenPos.bottom, equals(WorkspaceView.bannerTierZen));

    // Dismiss the banner
    await tester.tap(find.byKey(const ValueKey('degraded_warning_dismiss')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });

  testWidgets('WorkspaceView: banner elevates to bottom 140 when Zoom HUD is visible to avoid collision', (tester) async {
    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    final testFile = File(p.join(tempTestDir.path, 'broken_ui_zoom.md'));
    testFile.writeAsStringSync('''# Broken Doc
\$\$\\unsupportedcmd{xyz}\$\$
''');

    await controller.openFile(testFile.path);
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (controller.isCompiling || controller.degradedEquationCount == 0) {
      if (DateTime.now().isAfter(end)) {
        fail('Timed out waiting for broken doc compilation');
      }
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceView(controller: controller),
      ),
    );
    // Initial pump: toolbar is visible on startup, so banner sits at bannerTierToolbar
    await tester.pump();
    final startupPos = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('degraded_warning_positioned')));
    expect(startupPos.bottom, equals(WorkspaceView.bannerTierToolbar));

    // Tap zoom in to trigger transient Zoom HUD (at zoomHudBottom)
    final zoomInBtn = find.byIcon(Icons.add_rounded);
    expect(zoomInBtn, findsOneWidget);
    await tester.tap(zoomInBtn);
    await tester.pump();

    // With Zoom HUD active, banner elevates to bannerTierZoomHud to avoid mutual occlusion
    final zoomActivePos = tester.widget<AnimatedPositioned>(find.byKey(const ValueKey('degraded_warning_positioned')));
    expect(zoomActivePos.bottom, equals(WorkspaceView.bannerTierZoomHud));

    // Settle all remaining timers and animations
    await tester.pumpAndSettle();
  });
}
