// Manual-QA style walkthrough of the tab feature in the real macOS app.
// Run: flutter test integration_test/tabs_scenarios_test.dart -d macos
// --dart-define=SGV_IT_DIR=<scratch dir> (holds cwd/test/libsogood_core.dylib, receives
// shots/*.png and report.txt).
import 'dart:io';
import 'dart:ui' as ui;
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/main.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/tab_strip.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

String _longDoc(String name, {String frontMatter = ''}) {
  final b = StringBuffer(frontMatter)..writeln('# $name')..writeln();
  for (var i = 1; i <= 40; i++) {
    b
      ..writeln('## $name section $i')
      ..writeln()
      ..writeln('This is paragraph $i of $name. ' * 6)
      ..writeln();
  }
  return b.toString();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var itDir = const String.fromEnvironment('SGV_IT_DIR');
  if (itDir.isEmpty) {
    final tempDir = Directory.systemTemp.createTempSync('sgv_it_');
    itDir = tempDir.path;
    final testDir = Directory(p.join(itDir, 'cwd', 'test'))..createSync(recursive: true);
    for (final candidate in [
      'test/libsogood_core.dylib',
      'ui/test/libsogood_core.dylib',
      'macos/libsogood_core.dylib',
      'ui/macos/libsogood_core.dylib',
      '../ui/test/libsogood_core.dylib',
    ]) {
      final f = File(candidate);
      if (f.existsSync()) {
        try {
          f.copySync(p.join(testDir.path, 'libsogood_core.dylib'));
          break;
        } catch (_) {}
      }
    }
  }

  final cwd = Directory(p.join(itDir, 'cwd'))..createSync(recursive: true);
  Directory.current = cwd; // NativeEngine finds test/libsogood_core.dylib here

  final results = <String>[];
  var failures = 0;
  void check(String name, bool ok, [String detail = '']) {
    if (!ok) failures++;
    final line = '${ok ? 'PASS' : 'FAIL'}  $name${detail.isEmpty ? '' : '  ($detail)'}';
    results.add(line);
    // ignore: avoid_print
    print('[IT] $line');
  }

  testWidgets('tab scenarios', (tester) async {
    binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
    final docs = Directory(p.join(itDir, 'docs'))..createSync(recursive: true);
    Directory(p.join(itDir, 'shots')).createSync(recursive: true);
    String write(String rel, String content) {
      final f = File(p.join(docs.path, rel))..createSync(recursive: true);
      f.writeAsStringSync(content);
      return f.path;
    }

    final alpha = write('alpha.md', _longDoc('Alpha'));
    final beta = write('beta.md', _longDoc('Beta'));
    final gamma = write('gamma.md', _longDoc('Gamma'));
    final readme1 = write('project-one/README.md', _longDoc('Project One readme'));
    final readme2 = write('project-two/README.md', _longDoc('Project Two readme'));
    final a4 = write('a4-paper.md', _longDoc('A4 paper', frontMatter: '---\npage_format: a4\n---\n'));
    final many = [
      for (final n in [
        'quarterly-business-review-with-a-very-long-name',
        '第二季度产品规划与路线图评审会议纪要',
        'notes',
        'architecture-decision-records',
        'api',
        '会议记录',
        'release-checklist-v1.1.0',
      ])
        write('many/$n.md', _longDoc(n)),
    ];
    PreferencesService.setConfigFileForTesting(File(p.join(itDir, 'preferences.json')));

    final shotKey = GlobalKey();
    var shotIndex = 0;
    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 100));
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      shotIndex++;
      File(p.join(itDir, 'shots', '${shotIndex.toString().padLeft(2, '0')}-$name.png'))
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    ReaderController controller() => tester.widget<WorkspaceView>(find.byType(WorkspaceView)).controller;

    Future<void> settle({Duration max = const Duration(seconds: 12)}) async {
      final end = DateTime.now().add(max);
      // Let compiles start, then wait for them and the viewer swap.
      await tester.pump(const Duration(milliseconds: 300));
      while (DateTime.now().isBefore(end)) {
        final c = controller();
        if (!c.isCompiling && c.currentPdfBytes != null && !c.isReloading) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> keys(List<LogicalKeyboardKey> modifiers, LogicalKeyboardKey key) async {
      for (final m in modifiers) {
        await tester.sendKeyDownEvent(m);
      }
      await tester.sendKeyEvent(key);
      for (final m in modifiers.reversed) {
        await tester.sendKeyUpEvent(m);
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    Finder tab(String title) =>
        find.descendant(of: find.byType(DocumentTabStrip), matching: find.text(title));

    Future<void> launch({String? file}) async {
      await tester.pumpWidget(RepaintBoundary(key: shotKey, child: SuperGoodViewerApp(initialFile: file)));
      await settle();
    }

    Future<void> relaunch({String? file}) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
      await PreferencesService.pendingSave;
      await launch(file: file);
    }

    // 1. Single document: no tab strip
    await launch(file: alpha);
    check('1 single document shows no tab strip', find.byType(DocumentTabStrip).evaluate().isEmpty);
    await shot('single-document');

    // 2. Second file opens a tab next to the first
    await controller().openFile(beta);
    await settle();
    check('2 opening a second file adds a tab', controller().sessions.length == 2 && controller().activeSessionIndex == 1,
        'sessions=${controller().sessions.length}');
    check('2 tab strip visible with both titles', tab('alpha').evaluate().isNotEmpty && tab('beta').evaluate().isNotEmpty);
    await shot('two-tabs');

    // 3. Click a tab
    await tester.tap(tab('alpha'));
    await settle();
    check('3 clicking a tab switches document', controller().currentFilePath == alpha);
    check('3 canvas shows the clicked document', controller().currentMarkdown.contains('# Alpha'));
    await shot('clicked-alpha');

    // 4. Keyboard switching
    await keys([LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.tab);
    await settle();
    check('4 Ctrl+Tab goes to next tab', controller().currentFilePath == beta);
    await keys([LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.bracketLeft);
    await settle();
    check('4 Cmd+Shift+[ goes to previous tab', controller().currentFilePath == alpha);
    await keys([LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.tab);
    await settle();
    check('4 Ctrl+Shift+Tab wraps to last tab', controller().currentFilePath == beta);

    // 5. Reading position survives a round trip
    await tester.tap(tab('alpha'));
    await settle();
    final canvasCenter = tester.getCenter(find.byType(WorkspaceView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(canvasCenter));
    for (var i = 0; i < 6; i++) {
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 600));
    final scrolledOffset = controller().lastScrollOffset;
    await shot('alpha-scrolled');
    await tester.tap(tab('beta'));
    await settle();
    final betaOffset = controller().lastScrollOffset;
    await tester.tap(tab('alpha'));
    await settle();
    final restored = controller().lastScrollOffset;
    check('5 scrolled alpha moved', scrolledOffset > 200, 'offset=${scrolledOffset.toStringAsFixed(0)}');
    check('5 beta keeps its own position', betaOffset < 50, 'beta=${betaOffset.toStringAsFixed(0)}');
    check('5 alpha position restored after switching back', (restored - scrolledOffset).abs() < 60,
        'before=${scrolledOffset.toStringAsFixed(0)} after=${restored.toStringAsFixed(0)}');
    await shot('alpha-restored');

    // 6. Re-opening an open file switches instead of duplicating
    await controller().openFile(beta);
    await settle();
    check('6 opening an open file just switches', controller().sessions.length == 2 && controller().currentFilePath == beta);

    // 7. Same file name in two folders
    await controller().openFile(readme1);
    await settle();
    await controller().openFile(readme2);
    await settle();
    final one = tab('README · project-one');
    final two = tab('README · project-two');
    check('7 same-named tabs are labelled with their folder', one.evaluate().length == 1 && two.evaluate().length == 1);
    await tester.tap(one);
    await settle();
    check('7 first README tab shows project one', controller().currentMarkdown.contains('Project One'));
    await tester.tap(two);
    await settle();
    check('7 second README tab shows project two', controller().currentMarkdown.contains('Project Two'));
    await shot('same-name-readmes');

    // 8. Per-document page format
    await controller().openFile(a4);
    await settle();
    check('8 front matter document is A4', !controller().renderOptions.isFluid);
    await shot('a4-tab');
    await tester.tap(tab('alpha'));
    await settle();
    check('8 other tab stays fluid', controller().renderOptions.isFluid);

    // 9. Theme change while other tabs are in the background
    await keys([LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.keyL);
    await settle();
    final dark = controller().renderOptions.isDark;
    await tester.tap(tab('beta'));
    await settle();
    check('9 background tab re-rendered in new theme',
        controller().activeSession.renderedWith?.theme == controller().renderOptions.theme,
        'dark=$dark rendered=${controller().activeSession.renderedWith?.theme}');
    await shot('dark-beta');
    await keys([LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.keyL);
    await settle();

    // 10. Close, close with Cmd+W, reopen
    var count = controller().sessions.length;
    final clickableClose = find
        .descendant(of: find.byType(DocumentTabStrip), matching: find.byIcon(Icons.close_rounded))
        .hitTestable();
    check('10 only the active tab offers a clickable close button', clickableClose.evaluate().length == 1,
        'clickable=${clickableClose.evaluate().length}');
    final focusBefore = FocusManager.instance.primaryFocus?.toStringShort();
    await tester.tap(clickableClose.first);
    await settle();
    check('10 close button closes the active tab', controller().sessions.length == count - 1);
    final focusAfter = FocusManager.instance.primaryFocus;
    check('10 keyboard focus stays inside the workspace after a mouse close',
        focusAfter != null && focusAfter.context != null &&
            focusAfter.context!.findAncestorWidgetOfExactType<WorkspaceView>() != null,
        'before=$focusBefore after=${focusAfter?.toStringShort()}');
    count = controller().sessions.length;
    await keys([LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyW);
    await settle();
    check('10 Cmd+W closes a tab', controller().sessions.length == count - 1,
        'count=$count now=${controller().sessions.length}');
    count = controller().sessions.length;
    await keys([LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.keyT);
    await settle();
    check('10 Cmd+Shift+T reopens a closed tab', controller().sessions.length == count + 1);
    await shot('after-reopen');

    // 11. Many tabs with long names
    for (final path in many) {
      await controller().openFile(path);
    }
    await settle();
    check('11 many tabs open', controller().sessions.length >= 10, 'sessions=${controller().sessions.length}');
    await shot('many-tabs');
    final lastTab = tab('release-checklist-v1.1.0');
    check('11 active last tab title rendered', lastTab.evaluate().isNotEmpty);

    // 12. Sidebar open alongside tabs
    controller().setSidebarOpen(true);
    await settle();
    await shot('tabs-with-sidebar');
    controller().setSidebarOpen(false);
    await settle();

    // 13. Background file modified on disk
    final gammaIndexBefore = controller().sessions.indexWhere((s) => s.filePath == gamma);
    if (gammaIndexBefore == -1) {
      await controller().openFile(gamma);
      await settle();
    }
    await tester.tap(tab('alpha'));
    await settle();
    File(gamma).writeAsStringSync('${_longDoc('Gamma')}\n\n## Edited while in background\n');
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final gammaSession = controller().sessions.firstWhere((s) => s.filePath == gamma);
    check('13 background tab picked up the edit', gammaSession.markdown.contains('Edited while in background'));
    check('13 active tab unaffected', controller().currentFilePath == alpha);

    // 14. Replace mode
    controller().setOpenInNewTab(false);
    final countBefore = controller().sessions.length;
    final delta = write('delta.md', _longDoc('Delta'));
    await controller().openFile(delta);
    await settle();
    check('14 replace mode keeps tab count', controller().sessions.length == countBefore);
    check('14 replace mode shows the new file', controller().currentFilePath == delta);
    controller().setOpenInNewTab(true);

    // 15. Drop two files
    final drop1 = write('dropped-one.md', _longDoc('Dropped one'));
    final drop2 = write('dropped-two.md', _longDoc('Dropped two'));
    final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
    dropTarget.onDragDone?.call(DropDoneDetails(
      files: [DropItemFile(drop1), DropItemFile(drop2)],
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ));
    await settle();
    final paths = controller().sessions.map((s) => s.filePath).toList();
    check('15 dropping two files opens both', paths.contains(drop1) && paths.contains(drop2));

    // 16. Relaunch restores tabs
    final openBefore = controller().sessions.map((s) => s.filePath).toList();
    final activeBefore = controller().currentFilePath;
    await relaunch();
    final openAfter = controller().sessions.map((s) => s.filePath).toList();
    check('16 relaunch restores all tabs', openAfter.join('|') == openBefore.join('|'),
        '${openBefore.length} -> ${openAfter.length}');
    check('16 relaunch restores the active tab', controller().currentFilePath == activeBefore);
    await shot('after-relaunch');

    // 17. Close everything -> welcome document
    while (controller().sessions.length > 1) {
      await keys([LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyW);
    }
    await keys([LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyW);
    await settle();
    check('17 closing every tab shows the welcome document',
        controller().currentFilePath == null && find.byType(DocumentTabStrip).evaluate().isEmpty);
    await shot('welcome-after-closing-all');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
    await PreferencesService.pendingSave;
    PreferencesService.setConfigFileForTesting(null);

    final reportPath = p.join(itDir, 'report.txt');
    File(reportPath).writeAsStringSync('${results.join('\n')}\n');
    // ignore: avoid_print
    print('[IT] Test artifacts and report written to: $itDir');
    expect(failures, 0, reason: results.where((r) => r.startsWith('FAIL')).join('\n'));
  });
}
