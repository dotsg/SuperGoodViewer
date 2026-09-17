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
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
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

    test('ignores PDFs from the unversioned renderer cache', () async {
      const options = RenderOptions();
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);
      final cacheFile = tempDir.listSync().whereType<File>().singleWhere(
        (file) => file.path.endsWith('.pdf'),
      );
      final legacyName = p.basename(cacheFile.path).replaceFirst(RegExp(r'_v\d+_'), '_');
      expect(legacyName, isNot(p.basename(cacheFile.path)));
      await cacheFile.rename(p.join(tempDir.path, legacyName));

      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, options), isNull);
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, options), dummyPdfHeader);
    });

    test('cache distinguishes different render options (mode, theme, fontSize, viewportWidth)', () async {
      const optionsFluidLight800 = RenderOptions(mode: 'fluid', theme: 'light', viewportWidth: 800.0);
      const optionsFluidLight805 = RenderOptions(mode: 'fluid', theme: 'light', viewportWidth: 805.0); // Within 20pt bucket -> quantizes to 800
      const optionsFluidLight1200 = RenderOptions(mode: 'fluid', theme: 'light', viewportWidth: 1200.0);
      const optionsPagedDark = RenderOptions(mode: 'paged', theme: 'dark');

      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, optionsFluidLight800, dummyPdfHeader);

      // Hit for exact match (viewportWidth 800)
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsFluidLight800), isNotNull);
      // Hit for minor resize jitter within 20pt quantization bucket (805 -> 800)
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsFluidLight805), isNotNull);
      // Miss for different viewportWidth bucket (1200)
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsFluidLight1200), isNull);
      // Miss for paged dark
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, optionsPagedDark), isNull);
    });

    test('getCacheStats and clearCache calculate and purge cache files accurately', () async {
      const options = RenderOptions();
      // Initially 0 files in temp dir
      var stats = await DocumentCacheService.getCacheStats();
      expect(stats.fileCount, 0);
      expect(stats.totalBytes, 0);
      expect(stats.formattedSize, '0 B');
      expect(DocumentCacheService.getCacheStatsSync().fileCount, 0);

      // Save a file
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      stats = await DocumentCacheService.getCacheStats();
      expect(stats.fileCount, 1);
      expect(stats.totalBytes, dummyPdfHeader.length);
      expect(stats.formattedSize, contains('B'));

      // Clear cache
      final cleared = await DocumentCacheService.clearCache();
      expect(cleared.deletedCount, 1);
      expect(cleared.freedBytes, dummyPdfHeader.length);
      expect(cleared.formattedFreedSize, contains('B'));

      // Verify empty after clear
      stats = await DocumentCacheService.getCacheStats();
      expect(stats.fileCount, 0);
      expect(stats.totalBytes, 0);
      expect(DocumentCacheService.getCachedPdf(sampleMdFile.path, options), isNull);
    });

    test('formatBytes formats various sizes properly', () {
      expect(DocumentCacheService.formatBytes(0), '0 B');
      expect(DocumentCacheService.formatBytes(512), '512 B');
      expect(DocumentCacheService.formatBytes(2048), '2.0 KB');
      expect(DocumentCacheService.formatBytes(15 * 1024 * 1024), '15.0 MB');
      expect(DocumentCacheService.formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
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
      final controller = ReaderController(autoRestorePreferences: false);
      final options = controller.renderOptions;
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      await controller.openFile(sampleMdFile.path);

      // Controller should instantly have the cached PDF bytes
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.currentPdfBytes!.length, dummyPdfHeader.length);
      expect(controller.currentPdfBytes![0], 0x25); // '%'
    });
  });
}
