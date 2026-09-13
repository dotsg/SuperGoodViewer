import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/document_cache_service.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

void main() {
  late Directory tempDir;
  late File sampleMdFile;
  final dummyPdfHeader = Uint8List.fromList([
    0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, // %PDF-1.7
    ...List.filled(120, 0x20),
  ]);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sgv_cache_test_');
    DocumentCacheService.setCacheDirForTesting(tempDir);
    PreferencesService.setConfigFileForTesting(File(p.join(tempDir.path, 'preferences.json')));

    sampleMdFile = File(p.join(tempDir.path, 'sample.md'));
    sampleMdFile.writeAsStringSync('# Test Title\n\nContent here.');
  });

  tearDown(() {
    DocumentCacheService.setCacheDirForTesting(null);
    PreferencesService.setConfigFileForTesting(null);
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('DocumentCacheService Tests', () {
    test('returns null when cache does not exist', () {
      const options = RenderOptions();
      final cached = DocumentCacheService.getCachedPdf(sampleMdFile.path, options);
      expect(cached, isNull);
    });

    test('saves and retrieves cached PDF accurately', () async {
      const options = RenderOptions(mode: 'fluid', theme: 'light');
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      final cached = DocumentCacheService.getCachedPdf(sampleMdFile.path, options);
      expect(cached, isNotNull);
      expect(cached!.length, dummyPdfHeader.length);
      expect(cached[0], 0x25); // '%'
      expect(cached[1], 0x50); // 'P'
    });

    test('invalidates cache when file modification time changes', () async {
      const options = RenderOptions();
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      // Verify hit
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, options), isNotNull);

      // Modify source file content and bump mtime
      await Future.delayed(const Duration(milliseconds: 20));
      sampleMdFile.writeAsStringSync('# Updated Title\n\nNew content.');

      // Should now be a cache miss
      final cachedAfterEdit = DocumentCacheService.getCachedPdf(sampleMdFile.path, options);
      expect(cachedAfterEdit, isNull);
    });

    test('cache distinguishes different render options (mode, theme, fontSize)', () async {
      const optionsFluidLight = RenderOptions(mode: 'fluid', theme: 'light');
      const optionsPagedDark = RenderOptions(mode: 'paged', theme: 'dark');

      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, optionsFluidLight, dummyPdfHeader);

      // Hit for fluid light
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsFluidLight), isNotNull);
      // Miss for paged dark
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsPagedDark), isNull);
    });
  });

  group('PreferencesService Synchronous Loading Tests', () {
    test('loadSync returns empty map when config file does not exist', () {
      final prefs = PreferencesService.loadSync();
      expect(prefs, isEmpty);
    });

    test('loadSync reads persisted settings synchronously', () async {
      await PreferencesService.save({
        'theme': 'dark',
        'mode': 'paged',
        'fontSize': 12.0,
      });

      final prefs = PreferencesService.loadSync();
      expect(prefs['theme'], 'dark');
      expect(prefs['mode'], 'paged');
      expect(prefs['fontSize'], 12.0);
    });
  });

  group('ReaderController Instant Cache Integration', () {
    test('openFile uses cached PDF immediately without waiting for compileDocument', () async {
      const options = RenderOptions();
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      final controller = ReaderController(autoRestorePreferences: false);
      await controller.openFile(sampleMdFile.path);

      // Controller should instantly have the cached PDF bytes
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.currentPdfBytes!.length, dummyPdfHeader.length);
      expect(controller.currentPdfBytes![0], 0x25); // '%'
    });
  });
}
