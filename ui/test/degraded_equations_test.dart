import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/bridge/native_engine.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

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
    if (!NativeEngine.instance.isAvailable) {
      return;
    }

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
}
