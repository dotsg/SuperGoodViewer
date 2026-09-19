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

  Future<void> waitCompile(ReaderController controller) async {
    while (controller.isCompiling) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
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
    while (controller.isCompiling || controller.degradedEquationCount == 0) {
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }

    await tester.pumpWidget(
      MaterialApp(
        home: WorkspaceView(controller: controller),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('1 个公式渲染异常'), findsOneWidget);

    // Dismiss the banner
    await tester.tap(find.byKey(const ValueKey('degraded_warning_dismiss')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    // Flush any pending debounce timers (e.g. _persistDebounced 600ms)
    await tester.pump(const Duration(milliseconds: 700));
  });
}
