import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/shortcut_service.dart';
import 'package:sogoodviewer/views/tab_strip.dart';

Uint8List _pdf(String marker) =>
    Uint8List.fromList(utf8.encode('%PDF-1.4\n% $marker\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n'));

void main() {
  late Directory dir;
  late String a;
  late String b;
  late String c;

  String write(String name, String content) {
    final path = p.join(dir.path, name);
    File(path).writeAsStringSync(content);
    return path;
  }

  void createDocs() {
    dir = Directory.systemTemp.createTempSync('sgv_tabs_');
    PreferencesService.setConfigFileForTesting(File(p.join(dir.path, 'preferences.json')));
    a = write('alpha.md', '# Alpha\n\nfirst');
    b = write('beta.md', '# Beta\n\nsecond');
    c = write('gamma.md', '# Gamma\n\nthird');
  }

  void removeDocs() {
    PreferencesService.setConfigFileForTesting(null);
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  group('ReaderController tabs', () {
    setUp(createDocs);
    tearDown(() async {
      // Controllers persist preferences asynchronously on dispose; let that
      // finish before removing the directory it writes into.
      await PreferencesService.pendingSave;
      removeDocs();
    });

    test('opening a second file adds a tab and keeps the first', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(a);
      expect(controller.sessions, hasLength(1), reason: 'the welcome document is replaced, not kept');

      await controller.openFile(b);
      expect(controller.sessions.map((s) => s.filePath), [a, b]);
      expect(controller.activeSessionIndex, 1);
      expect(controller.currentFilePath, b);
    });

    test('opening a file that is already open switches to its tab', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      await controller.openFile(b);

      await controller.openFile(a);
      expect(controller.sessions, hasLength(2));
      expect(controller.activeSessionIndex, 0);
      expect(controller.currentMarkdown, contains('first'));
    });

    test('replace mode keeps a single tab, and newTab overrides it', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      controller.setOpenInNewTab(false);

      await controller.openFile(a);
      await controller.openFile(b);
      expect(controller.sessions.map((s) => s.filePath), [b]);

      await controller.openFile(c, newTab: true);
      expect(controller.sessions.map((s) => s.filePath), [b, c]);
    });

    test('new tabs open next to the active one', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      await controller.openFile(b);
      controller.activateSession(0);

      await controller.openFile(c);
      expect(controller.sessions.map((s) => s.filePath), [a, c, b]);
      expect(controller.activeSessionIndex, 1);
    });

    test('closing tabs activates a neighbour, then falls back to the welcome document', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      await controller.openFile(b);
      await controller.openFile(c);

      controller.activateSession(1);
      controller.closeActiveSession();
      expect(controller.sessions.map((s) => s.filePath), [a, c]);
      expect(controller.currentFilePath, c);

      controller.closeSession(0);
      controller.closeActiveSession();
      expect(controller.sessions, hasLength(1));
      expect(controller.currentFilePath, isNull);
      expect(controller.documentTitle, 'SuperGoodViewer Demo');
    });

    test('reopening restores the most recently closed tab first', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      await controller.openFile(b);
      await controller.openFile(c);
      controller.closeSession(2);
      controller.closeSession(1);
      expect(controller.canReopenClosedTab, isTrue);

      await controller.reopenClosedSession();
      expect(controller.currentFilePath, b);
      await controller.reopenClosedSession();
      expect(controller.currentFilePath, c);
      expect(controller.canReopenClosedTab, isFalse);
    });

    test('next and previous wrap around', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      await controller.openFile(b);

      controller.activateNextSession();
      expect(controller.currentFilePath, a);
      controller.activatePreviousSession();
      expect(controller.currentFilePath, b);
    });

    test('each tab keeps its own reading position', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(a);
      controller.updateScrollRatio(0.4, offset: 320);
      controller.updatePageNumber(3);

      await controller.openFile(b);
      expect(controller.lastScrollRatio, 0.0);
      controller.updateScrollRatio(0.9, offset: 700);

      controller.activateSession(0);
      expect(controller.lastScrollRatio, 0.4);
      expect(controller.lastScrollOffset, 320);
      expect(controller.lastPageNumber, 3);
      expect(controller.isReloading, isTrue, reason: 'the canvas restores the saved position');

      controller.activateSession(1);
      expect(controller.lastScrollRatio, 0.9);
    });

    test('a page format from front matter stays with its document', () async {
      final slides = write('slides.md', '---\npage_format: a4\n---\n# Slides');
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(slides);
      expect(controller.renderOptions.effectivePageFormat, PageFormat.a4Portrait);

      await controller.openFile(a);
      expect(controller.renderOptions.isFluid, isTrue, reason: 'front matter no longer changes the default');

      controller.activateSession(0);
      expect(controller.renderOptions.effectivePageFormat, PageFormat.a4Portrait);
    });

    test('tabs are restored on the next launch, loading only the active one', () async {
      final first = ReaderController(autoRestorePreferences: false);
      await first.openFile(a);
      await first.openFile(b);
      await first.openFile(c);
      first.activateSession(1);
      first.dispose();
      await PreferencesService.pendingSave;

      final restored = ReaderController();
      addTearDown(restored.dispose);
      expect(restored.sessions.map((s) => s.filePath), [a, b, c]);
      expect(restored.activeSessionIndex, 1);
      expect(restored.currentMarkdown, contains('second'));
      expect(restored.sessions[0].isLoaded, isFalse);

      restored.activateSession(0);
      expect(restored.sessions[0].isLoaded, isTrue);
      expect(restored.currentMarkdown, contains('first'));
    });

    test('a reload that lands after a tab switch updates its own tab', () async {
      final pdfA = p.join(dir.path, 'a.pdf');
      final pdfB = p.join(dir.path, 'b.pdf');
      File(pdfA).writeAsBytesSync(_pdf('a1'));
      File(pdfB).writeAsBytesSync(_pdf('b1'));
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      await controller.openFile(pdfA);
      await controller.openFile(pdfB);

      // Edit the background tab's file; its watcher reloads it.
      File(pdfA).writeAsBytesSync(_pdf('a2'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(deadline) &&
          !listEqualsBytes(controller.sessions[0].pdfBytes, _pdf('a2'))) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      expect(listEqualsBytes(controller.sessions[0].pdfBytes, _pdf('a2')), isTrue);
      expect(listEqualsBytes(controller.currentPdfBytes, _pdf('b1')), isTrue);
      expect(controller.currentFilePath, pdfB);
    });
  });

  group('Tab shortcuts', () {
    tearDown(() => ShortcutService.debugIsMacLayout = null);

    test('Alt+1..9 jump to tabs on Windows and Linux only', () {
      ShortcutService.debugIsMacLayout = false;
      final numbers = <int>[];
      final bindings = ShortcutService().buildTabNumberBindings(numbers.add);
      expect(bindings, hasLength(9));
      for (final callback in bindings.values) {
        callback();
      }
      expect(numbers, [1, 2, 3, 4, 5, 6, 7, 8, 9]);

      ShortcutService.debugIsMacLayout = true;
      expect(ShortcutService().buildTabNumberBindings(numbers.add), isEmpty);
    });

    test('tab actions use browser defaults', () {
      ShortcutService.debugIsMacLayout = true;
      final service = ShortcutService();
      expect(service.getShortcutLabel('closeTab'), 'Cmd+W');
      expect(service.getShortcutLabel('openFileInNewTab'), 'Cmd+T');
      expect(service.getShortcutLabel('reopenClosedTab'), 'Cmd+Shift+T');
      expect(service.getShortcutLabel('nextTab'), 'Cmd+Shift+]');
      expect(service.getShortcutLabel('previousTab'), 'Cmd+Shift+[');
    });
  });

  group('Tab strip', () {
    setUp(createDocs);
    tearDown(removeDocs);

    testWidgets('lists the documents, switches on click and closes from the close button', (tester) async {
      // PDFs open without compiling, so the test needs no real async work.
      final pdfA = p.join(dir.path, 'first.pdf');
      final pdfB = p.join(dir.path, 'second.pdf');
      File(pdfA).writeAsBytesSync(_pdf('a'));
      File(pdfB).writeAsBytesSync(_pdf('b'));
      final controller = ReaderController(autoRestorePreferences: false);
      controller.openFile(pdfA);
      controller.openFile(pdfB);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => DocumentTabStrip(controller: controller, isDark: false, maxWidth: 600),
          ),
        ),
      ));
      expect(find.text('first'), findsOneWidget);
      expect(find.text('second'), findsOneWidget);

      await tester.tap(find.text('first'));
      await tester.pump();
      expect(controller.currentFilePath, pdfA);

      // Only the active tab shows its close button.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await tester.pump();
      expect(controller.sessions.map((s) => s.filePath), [pdfB]);

      await tester.pumpWidget(const SizedBox());
      // dispose persists preferences; let that write finish off the fake clock.
      await tester.runAsync(() async {
        controller.dispose();
        await PreferencesService.pendingSave;
      });
    });
  });

  test('Ctrl+Tab and Ctrl+PageDown/PageUp are bound on every platform', () {
    for (final mac in [true, false]) {
      ShortcutService.debugIsMacLayout = mac;
      var next = 0;
      var previous = 0;
      void noop() {}
      final bindings = ShortcutService().buildBindings(
        onToggleMode: noop, onExportPdf: noop, onOpenFile: noop, onToggleSidebar: noop,
        onCompileDocument: noop, onToggleTheme: noop, onToggleTwoPage: noop, onZoomIn: noop,
        onZoomOut: noop, onResetZoom: noop, onFitWidth: noop, onFitPage: noop,
        onToggleToolbar: noop, onFontSettings: noop,
        onNextTab: () => next++, onPreviousTab: () => previous++,
      );
      void press(LogicalKeyboardKey key, {bool shift = false}) {
        bindings.entries
            .singleWhere((e) {
              final a = e.key;
              return a is SingleActivator && a.trigger == key && a.control && a.shift == shift && !a.meta;
            })
            .value();
      }

      press(LogicalKeyboardKey.tab);
      press(LogicalKeyboardKey.pageDown);
      press(LogicalKeyboardKey.tab, shift: true);
      press(LogicalKeyboardKey.pageUp);
      expect((next, previous), (2, 2));
    }
    ShortcutService.debugIsMacLayout = null;
  });
}

bool listEqualsBytes(Uint8List? x, Uint8List y) {
  if (x == null || x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
