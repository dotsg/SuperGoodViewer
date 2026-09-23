import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/document_cache_service.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('supergoodviewer_duplicate_open_test_');
    PreferencesService.setConfigFileForTesting(File(p.join(tempTestDir.path, 'preferences.json')));
    DocumentCacheService.setCacheDirForTesting(Directory(p.join(tempTestDir.path, 'cache'))..createSync());
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    DocumentCacheService.setCacheDirForTesting(null);
    try {
      tempTestDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('Duplicate open', () {
    test('launch file delivered again under another spelling does not recompile', () async {
      final docDir = Directory(p.join(tempTestDir.path, 'docs'))..createSync();
      final doc = File(p.join(docDir.path, 'launch.md'))..writeAsStringSync('# Launch\n\nBody.');
      // macOS hands the Apple Event path over standardized (`/tmp` vs argv's
      // `/private/tmp`); a symlinked directory reproduces that on any platform.
      final alias = Link(p.join(tempTestDir.path, 'alias'))..createSync(docDir.path);
      final aliasedPath = p.join(alias.path, 'launch.md');

      final controller = ReaderController(initialFilePath: doc.path);
      final generation = controller.compileGeneration;

      await controller.openFile(aliasedPath);

      expect(controller.compileGeneration, generation);
      expect(controller.currentFilePath, doc.path);

      controller.dispose();
      await PreferencesService.pendingSave;
    });

    test('same path with changed content is reopened', () async {
      final doc = File(p.join(tempTestDir.path, 'changing.md'))..writeAsStringSync('# Before');

      final controller = ReaderController(initialFilePath: doc.path);
      final generation = controller.compileGeneration;

      doc.writeAsStringSync('# After');
      await controller.openFile(doc.path);

      expect(controller.compileGeneration, greaterThan(generation));
      expect(controller.currentMarkdown, '# After');

      controller.dispose();
      await PreferencesService.pendingSave;
    });
  });
}
