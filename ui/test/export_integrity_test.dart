import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

int computeChecksum(List<int> bytes) {
  var hash = 0xcbf29ce484222325;
  for (final b in bytes) {
    hash ^= b;
    hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
  }
  return hash;
}

void main() {
  late Directory tempTestDir;

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_export_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );
    Pdfrx.cacheDirectoryPath = tempTestDir.path;
    final candidatePaths = [
      p.normalize(p.join(Directory.current.path, 'build/native_assets/macos/libpdfium.dylib')),
      p.normalize(p.join(Directory.current.path, '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-arm64/libpdfium.dylib')),
      p.normalize(p.join(Directory.current.path, '.dart_tool/hooks_runner/shared/pdfium_dart/build/chromium_7811/mac-x64/libpdfium.dylib')),
    ];
    for (final path in candidatePaths) {
      if (File(path).existsSync()) {
        Pdfrx.pdfiumModulePath = path;
        break;
      }
    }
    await pdfrxFlutterInitialize();
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    if (tempTestDir.existsSync()) {
      tempTestDir.deleteSync(recursive: true);
    }
  });

  Future<void> waitCompile(ReaderController controller) async {
    while (controller.isCompiling || controller.currentPdfBytes == null) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  group('PDF Export and Byte-for-Byte Verification Tests', () {
    test('Fluid mode: exports valid PDF identical to in-memory bytes and hash', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      await waitCompile(controller);

      expect(controller.currentPdfBytes, isNotNull);
      final inMemoryBytes = controller.currentPdfBytes!;
      expect(inMemoryBytes.length, greaterThan(1000));
      expect(utf8.decode(inMemoryBytes.sublist(0, 5)), '%PDF-');

      final exportPath = p.join(tempTestDir.path, 'fluid_export.pdf');
      final success = await controller.exportPdf(exportPath);
      expect(success, true);

      final exportedFile = File(exportPath);
      expect(await exportedFile.exists(), true);
      final fileBytes = await exportedFile.readAsBytes();

      // Byte-for-byte exact equality
      expect(fileBytes.length, inMemoryBytes.length);
      expect(listEquals(fileBytes, inMemoryBytes), true);

      // Checksum match
      expect(computeChecksum(fileBytes), equals(computeChecksum(inMemoryBytes)));

      controller.dispose();
    });

    test('Paged mode: exports valid A4 PDF identical to in-memory bytes and hash', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      controller.toggleMode(); // switch to paged
      await waitCompile(controller);

      expect(controller.renderOptions.isFluid, false);
      expect(controller.currentPdfBytes, isNotNull);
      final inMemoryBytes = controller.currentPdfBytes!;

      final exportPath = p.join(tempTestDir.path, 'paged_export.pdf');
      final success = await controller.exportPdf(exportPath);
      expect(success, true);

      final exportedFile = File(exportPath);
      expect(await exportedFile.exists(), true);
      final fileBytes = await exportedFile.readAsBytes();

      expect(fileBytes.length, inMemoryBytes.length);
      expect(listEquals(fileBytes, inMemoryBytes), true);
      expect(computeChecksum(fileBytes), equals(computeChecksum(inMemoryBytes)));

      controller.dispose();
    });

    test('Dark theme: exports publication-grade dark PDF identical to in-memory bytes', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      controller.toggleTheme(); // switch to dark
      await waitCompile(controller);

      expect(controller.renderOptions.isDark, true);
      final inMemoryBytes = controller.currentPdfBytes!;

      final exportPath = p.join(tempTestDir.path, 'dark_export.pdf');
      final success = await controller.exportPdf(exportPath);
      expect(success, true);

      final exportedFile = File(exportPath);
      final fileBytes = await exportedFile.readAsBytes();

      expect(listEquals(fileBytes, inMemoryBytes), true);
      expect(computeChecksum(fileBytes), equals(computeChecksum(inMemoryBytes)));

      controller.dispose();
    });

    test('Export gracefully fails on invalid destination without throwing', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      await waitCompile(controller);

      final invalidPath = '/non_existent_system_dir_404_xyz/test.pdf';
      final success = await controller.exportPdf(invalidPath);

      expect(success, false);
      expect(controller.errorMessage, contains('Export failed'));

      controller.dispose();
    });
  });

  group('PDF Export Round-Trip Determinism (In-Memory Buffer vs Exported File)', () {
    test('PDFium renders in-memory bytes and re-read exported file with identical RGBA buffer', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      await waitCompile(controller);

      final inMemoryBytes = controller.currentPdfBytes!;
      final exportPath = p.join(tempTestDir.path, 'pixel_verification.pdf');
      await controller.exportPdf(exportPath);

      // Open in-memory PDF (what the viewer renders)
      final inMemoryDoc = await PdfDocument.openData(
        inMemoryBytes,
        sourceName: 'in_memory_verification',
      );

      // Open exported file PDF (what was written to disk)
      final fileDoc = await PdfDocument.openFile(exportPath);

      try {
        expect(inMemoryDoc.pages.length, equals(fileDoc.pages.length));
        expect(inMemoryDoc.pages.length, greaterThanOrEqualTo(1));

        final page1Memory = inMemoryDoc.pages[0];
        final page1File = fileDoc.pages[0];

        // Verify geometric dimensions
        expect(page1Memory.width, equals(page1File.width));
        expect(page1Memory.height, equals(page1File.height));

        // Render both to RGBA bitmaps with identical resolution
        const renderWidth = 800;
        const renderHeight = 1100;
        final imgMemory = await page1Memory.render(
          width: renderWidth,
          height: renderHeight,
        );
        final imgFile = await page1File.render(
          width: renderWidth,
          height: renderHeight,
        );

        try {
          expect(imgMemory, isNotNull);
          expect(imgFile, isNotNull);

          expect(imgMemory!.width, equals(imgFile!.width));
          expect(imgMemory.height, equals(imgFile.height));

          final pixelsMemory = imgMemory.pixels;
          final pixelsFile = imgFile.pixels;

          expect(pixelsMemory.length, equals(pixelsFile.length));

          // 100% Bit-for-bit, pixel-by-pixel RGBA buffer identity
          expect(listEquals(pixelsMemory, pixelsFile), true);

          // Checksum identity of the rendered pixel frame
          final hashMemory = computeChecksum(pixelsMemory);
          final hashFile = computeChecksum(pixelsFile);
          expect(hashMemory, equals(hashFile));

          debugPrint('[ExportIntegrity] Round-trip render identical: $renderWidth x $renderHeight (${pixelsMemory.length} bytes), checksum $hashMemory');
        } finally {
          imgMemory?.dispose();
          imgFile?.dispose();
        }
      } finally {
        await inMemoryDoc.dispose();
        await fileDoc.dispose();
        controller.dispose();
      }
    });
  });
}
