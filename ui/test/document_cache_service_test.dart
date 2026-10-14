import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/document_cache_service.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/remote_image_service.dart';

void main() {
  late Directory tempDir;
  late File sampleMdFile;
  final dummyPdfHeader = Uint8List.fromList([
    0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, // %PDF-1.7
    ...List.filled(120, 0x20),
  ]);

  // Exact 99-byte red and blue 32x32 PNGs from Issue #22
  final redTileBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGO4Y2REU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULAHsMAExPRcGKAAAAAElFTkSuQmCC',
  );
  final blueTileBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKklEQVR4nGPQSLlDU8QwasGoBaMWjFowasGoBaMWjFowasGoBaMWDBULADuXoEyJ6NMPAAAAAElFTkSuQmCC',
  );

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

    test('invalidates cache when referenced local image attachment is replaced, created, or deleted (#22)', () async {
      // Both red and blue PNGs are 99 bytes; replacing tile.png without touching cache-test.md must invalidate cache!
      expect(redTileBytes.length, 99);
      expect(blueTileBytes.length, 99);

      final tileFile = File(p.join(tempDir.path, 'tile.png'));
      final subDir = Directory(p.join(tempDir.path, 'assets', 'sub'))..createSync(recursive: true);
      final subTileFile = File(p.join(subDir.path, 'sub_tile.png'));

      tileFile.writeAsBytesSync(redTileBytes);
      subTileFile.writeAsBytesSync(redTileBytes);

      final mdFile = File(p.join(tempDir.path, 'cache-test.md'));
      mdFile.writeAsStringSync(
        '# 附件缓存测试\n\n![颜色方块](tile.png)\n\n<img src = "assets/sub/sub_tile.png" width="32">\n',
      );
      final originalMdStat = mdFile.statSync();

      const options = RenderOptions();
      await DocumentCacheService.saveCachedPdf(mdFile.path, options, dummyPdfHeader);
      expect(DocumentCacheService.getCachedPdf(mdFile.path, options), isNotNull);

      // 1. Replace tile.png with blueTileBytes (exact same 99-byte size, Markdown untouched)
      tileFile.writeAsBytesSync(blueTileBytes);
      expect(mdFile.statSync().modified, originalMdStat.modified);
      expect(
        DocumentCacheService.getCachedPdf(mdFile.path, options),
        isNull,
        reason: 'Replacing local image attachment with same-sized file must invalidate cached PDF',
      );

      // Save new PDF for blue tile
      await DocumentCacheService.saveCachedPdf(mdFile.path, options, dummyPdfHeader);
      expect(DocumentCacheService.getCachedPdf(mdFile.path, options), isNotNull);

      // 2. Replace subdirectory HTML <img> attachment
      subTileFile.writeAsBytesSync(blueTileBytes);
      expect(
        DocumentCacheService.getCachedPdf(mdFile.path, options),
        isNull,
        reason: 'Replacing subdirectory attachment referenced by HTML <img> must invalidate cached PDF',
      );

      // Save again, then delete tile.png
      await DocumentCacheService.saveCachedPdf(mdFile.path, options, dummyPdfHeader);
      expect(DocumentCacheService.getCachedPdf(mdFile.path, options), isNotNull);
      tileFile.deleteSync();
      expect(
        DocumentCacheService.getCachedPdf(mdFile.path, options),
        isNull,
        reason: 'Deleting local image attachment must invalidate cached PDF',
      );
    });

    test('invalidates placeholder PDF cache when remote image becomes cached on disk (#22)', () async {
      final imgCacheDir = Directory(p.join(tempDir.path, 'img_cache'))..createSync(recursive: true);
      final options = RenderOptions(imageCacheDir: imgCacheDir.path);

      const remoteUrl = 'https://example.com/shared_banner.png';
      final mdFile = File(p.join(tempDir.path, 'remote-cache-test.md'));
      mdFile.writeAsStringSync('# Remote Cache Test\n\n![Banner]($remoteUrl)\n');

      // 1. Save PDF while remote image is not yet downloaded (placeholder state)
      await DocumentCacheService.saveCachedPdf(mdFile.path, options, dummyPdfHeader);
      expect(DocumentCacheService.getCachedPdf(mdFile.path, options), isNotNull);

      // 2. Simulate the remote image being downloaded (e.g. by another document)
      final cacheFilename = RemoteImageService.instance.urlToCacheFilename(remoteUrl);
      File(p.join(imgCacheDir.path, cacheFilename)).writeAsBytesSync(redTileBytes);

      // 3. Old placeholder PDF must now be a cache miss!
      expect(
        DocumentCacheService.getCachedPdf(mdFile.path, options),
        isNull,
        reason: 'Once remote image is cached on disk, stale placeholder PDF must be invalidated',
      );
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

    test('openCacheDirectory creates cache directory if not existing without spawning OS window', () async {
      DocumentCacheService.directoryLauncherForTesting = (path) async => true;
      addTearDown(() => DocumentCacheService.directoryLauncherForTesting = null);

      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      expect(tempDir.existsSync(), isFalse);

      final result = await DocumentCacheService.openCacheDirectory();
      expect(result, isTrue);
      expect(tempDir.existsSync(), isTrue);
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
      addTearDown(controller.dispose);
      final options = controller.renderOptions;
      await DocumentCacheService.saveCachedPdf(sampleMdFile.path, options, dummyPdfHeader);

      await controller.openFile(sampleMdFile.path);

      // Controller should instantly have the cached PDF bytes
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.currentPdfBytes!.length, dummyPdfHeader.length);
      expect(controller.currentPdfBytes![0], 0x25); // '%'
    });

    test('reopening and live auto-reload both update PDF when local image attachment is replaced (#22)', () async {
      final docDir = Directory(p.join(tempDir.path, 'doc_workspace'))..createSync(recursive: true);
      final tileFile = File(p.join(docDir.path, 'tile.png'));
      final mdFile = File(p.join(docDir.path, 'cache-test.md'));

      tileFile.writeAsBytesSync(redTileBytes);
      mdFile.writeAsStringSync('# 附件缓存测试\n\n![颜色方块](tile.png)\n');

      final controller1 = ReaderController(autoRestorePreferences: false);
      addTearDown(controller1.dispose);

      await controller1.openFile(mdFile.path, newTab: false);
      while (controller1.isCompiling || controller1.currentPdfBytes == null) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      final redPdfBytes = Uint8List.fromList(controller1.currentPdfBytes!);
      expect(redPdfBytes, isNotEmpty);

      // Wait briefly for async saveCachedPdf to finish
      await Future.delayed(const Duration(milliseconds: 50));
      expect(
        DocumentCacheService.getCachedPdf(mdFile.path, controller1.renderOptions),
        isNotNull,
      );

      // Test 1: Live auto-reload when tile.png is replaced in-place while controller1 is open
      final genBeforeLiveReplace = controller1.compileGeneration;
      tileFile.writeAsBytesSync(blueTileBytes);

      final deadline = DateTime.now().add(const Duration(seconds: 4));
      while (DateTime.now().isBefore(deadline)) {
        if (controller1.compileGeneration > genBeforeLiveReplace && !controller1.isCompiling) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 30));
      }

      expect(
        controller1.compileGeneration,
        greaterThan(genBeforeLiveReplace),
        reason: 'Modifying referenced local image attachment must trigger live auto-reload',
      );
      final bluePdfBytes = Uint8List.fromList(controller1.currentPdfBytes!);
      expect(
        bluePdfBytes,
        isNot(equals(redPdfBytes)),
        reason: 'Compiled PDF after replacing red tile.png with blue tile.png must differ from red PDF',
      );

      // Test 2: Re-opening after replacing tile.png while closed (cold cache check)
      controller1.setAutoReload(false);
      await Future.delayed(const Duration(milliseconds: 50));
      // Replace back to red while auto-reload is off
      tileFile.writeAsBytesSync(redTileBytes);

      final controller2 = ReaderController(autoRestorePreferences: false);
      addTearDown(controller2.dispose);
      await controller2.openFile(mdFile.path, newTab: false);
      while (controller2.isCompiling || controller2.currentPdfBytes == null) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
      expect(
        controller2.currentPdfBytes,
        equals(redPdfBytes),
        reason: 'Reopening document after attachment replacement must not return stale blue PDF',
      );
    });
  });
}

