import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/preferences_service.dart';

void main() {
  late Directory tempTestDir;

  setUpAll(() {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_session_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );
  });

  setUp(() {
    final testFile = File(p.join(tempTestDir.path, 'preferences.json'));
    if (testFile.existsSync()) {
      testFile.deleteSync();
    }
  });

  tearDownAll(() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Session & Preferences Persistence Tests', () {
    test('persists and restores last file, position, zoom, and typography', () async {
      // 1. Create a dummy markdown file
      final dummyDoc = File(p.join(tempTestDir.path, 'doc1.md'));
      dummyDoc.writeAsStringSync('# Test Doc 1\n\nSome content.');

      // 2. Initialize controller, open doc, update settings
      final controller1 = ReaderController(autoRestorePreferences: false);
      await controller1.openFile(dummyDoc.path, preservePosition: false);
      controller1.finishReloading();
      controller1.updateScrollRatio(0.45);
      controller1.updatePageNumber(3);
      controller1.updateZoom(1.75);
      controller1.setTypography(fontSize: 14.0, bodyFont: 'CustomBody', codeFont: 'CustomCode');

      // Trigger dispose to persist immediately
      controller1.dispose();
      await PreferencesService.pendingSave;

      // 3. Verify preferences JSON saved the data
      final prefs = PreferencesService.loadSync();
      expect(prefs['lastOpenedFile'], dummyDoc.path);
      expect(prefs['lastScrollRatio'], 0.45);
      expect(prefs['lastPageNumber'], 3);
      expect(prefs['lastZoom'], 1.75);
      expect(prefs['fontSize'], 14.0);
      expect(prefs['bodyFont'], 'CustomBody');
      expect(prefs['codeFont'], 'CustomCode');

      final history = prefs['fileHistory'] as Map<String, dynamic>?;
      expect(history, isNotNull);
      expect(history![dummyDoc.path], isNotNull);
      expect(history[dummyDoc.path]['scrollRatio'], 0.45);
      expect(history[dummyDoc.path]['pageNumber'], 3);
      expect(history[dummyDoc.path]['zoom'], 1.75);

      // 4. Launch a new controller instance with session restoration enabled
      final controller2 = ReaderController(autoRestorePreferences: true);
      expect(controller2.currentFilePath, dummyDoc.path);
      expect(controller2.lastScrollRatio, 0.45);
      expect(controller2.lastPageNumber, 3);
      expect(controller2.lastZoom, 1.75);
      expect(controller2.renderOptions.fontSize, 14.0);
      expect(controller2.renderOptions.bodyFont, 'CustomBody');
      expect(controller2.renderOptions.codeFont, 'CustomCode');

      controller2.dispose();
      await PreferencesService.pendingSave;
    });

    test('reloading safety timer unlocks isReloading within duration', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      controller.startReloading();
      expect(controller.isReloading, isTrue);

      // Wait for the safety timer (800ms) to fire
      await Future.delayed(const Duration(milliseconds: 900));
      expect(controller.isReloading, isFalse);

      controller.dispose();
    });

    test('per-file history restores position when switching between multiple files', () async {
      final docA = File(p.join(tempTestDir.path, 'docA.md'));
      docA.writeAsStringSync('# Doc A\n\nAlpha content.');

      final docB = File(p.join(tempTestDir.path, 'docB.md'));
      docB.writeAsStringSync('# Doc B\n\nBeta content.');

      final controller = ReaderController(autoRestorePreferences: false);

      // Open Doc A and record progress
      await controller.openFile(docA.path, preservePosition: false);
      controller.finishReloading();
      controller.updateScrollRatio(0.3);
      controller.updatePageNumber(2);
      controller.updateZoom(1.2);

      // Open Doc B and record progress
      await controller.openFile(docB.path, preservePosition: false);
      controller.finishReloading();
      controller.updateScrollRatio(0.8);
      controller.updatePageNumber(5);
      controller.updateZoom(1.6);

      // Switch back to Doc A: should automatically restore Doc A's position and zoom from history!
      await controller.openFile(docA.path, preservePosition: false);
      expect(controller.currentFilePath, docA.path);
      expect(controller.lastScrollRatio, 0.3);
      expect(controller.lastPageNumber, 2);
      expect(controller.lastZoom, 1.2);

      controller.dispose();
      await PreferencesService.pendingSave;
    });

    test('persists and restores sidebar open state across sessions', () async {
      final controller1 = ReaderController(autoRestorePreferences: false);
      expect(controller1.isSidebarOpen, isFalse);
      controller1.setSidebarOpen(true);
      expect(controller1.isSidebarOpen, isTrue);

      controller1.dispose();
      await PreferencesService.pendingSave;

      final prefs = PreferencesService.loadSync();
      expect(prefs['isSidebarOpen'], isTrue);

      final controller2 = ReaderController(autoRestorePreferences: true);
      expect(controller2.isSidebarOpen, isTrue);

      controller2.setSidebarOpen(false);
      controller2.dispose();
      await PreferencesService.pendingSave;

      final prefs2 = PreferencesService.loadSync();
      expect(prefs2['isSidebarOpen'], isFalse);

      final controller3 = ReaderController(autoRestorePreferences: true);
      expect(controller3.isSidebarOpen, isFalse);
      controller3.dispose();
    });
  });
}
