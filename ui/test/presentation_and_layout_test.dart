import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/presentation_view.dart';

void main() {
  late Directory tempTestDir;
  final multipagePdfFile = File('packages/pdfrx/test/assets/multipage40.pdf').absolute;

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_layout_test_');
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

  group('PageFormat & ReaderController Layout State Tests', () {
    test('PageFormat constants and helpers are properly defined', () {
      expect(PageFormat.all, [
        PageFormat.fluid,
        PageFormat.a4Portrait,
        PageFormat.a4Landscape,
        PageFormat.slide16x9,
        PageFormat.slide4x3,
      ]);

      expect(PageFormat.getDisplayName(PageFormat.fluid), contains('流式'));
      expect(PageFormat.getDisplayName(PageFormat.a4Portrait), contains('A4'));
      expect(PageFormat.getDisplayName(PageFormat.a4Landscape), contains('横向'));
      expect(PageFormat.getDisplayName(PageFormat.slide16x9), contains('16:9'));
      expect(PageFormat.getDisplayName(PageFormat.slide4x3), contains('4:3'));
    });

    test('RenderOptions serialization and copyWith handle pageFormat and headers/footers', () {
      final options = const RenderOptions().copyWith(
        mode: 'paged',
        pageFormat: PageFormat.slide16x9,
        headerLeft: 'Company Presentation',
        headerRight: '{date}',
        footerCenter: 'Page {page} of {total}',
        showHeaderRule: true,
        showFooterRule: false,
        skipFirstPageHeaderFooter: true,
        marpEnabled: true,
      );

      expect(options.mode, 'paged');
      expect(options.pageFormat, PageFormat.slide16x9);
      expect(options.isSlide, isTrue);
      expect(options.isFluid, isFalse);
      expect(options.aspectRatio, closeTo(16.0 / 9.0, 0.01));
      expect(options.headerLeft, 'Company Presentation');
      expect(options.headerRight, '{date}');
      expect(options.footerCenter, 'Page {page} of {total}');
      expect(options.showHeaderRule, isTrue);
      expect(options.showFooterRule, isFalse);
      expect(options.skipFirstPageHeaderFooter, isTrue);
      expect(options.marpEnabled, isTrue);

      final json = options.toJsonString();
      expect(json, contains('"page_format":"slide16x9"'));
      expect(json, contains('"header_left":"Company Presentation"'));
      expect(json, contains('"header_right":"{date}"'));
      expect(json, contains('"footer_center":"Page {page} of {total}"'));
      expect(json, contains('"show_header_rule":true'));
      expect(json, contains('"show_footer_rule":false'));
      expect(json, contains('"skip_first_page_header_footer":true'));
      expect(json, contains('"marp_enabled":true'));
    });

    test('ReaderController setPageFormat and cyclePageFormat cycle through all 5 formats', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      expect(controller.renderOptions.effectivePageFormat, PageFormat.fluid);
      expect(controller.renderOptions.isFluid, isTrue);

      // Explicit setPageFormat
      controller.setPageFormat(PageFormat.slide16x9);
      expect(controller.renderOptions.effectivePageFormat, PageFormat.slide16x9);
      expect(controller.renderOptions.mode, 'paged');
      expect(controller.renderOptions.isSlide, isTrue);

      // cyclePageFormat from slide16x9 -> slide4x3 -> fluid -> a4Portrait -> a4Landscape -> slide16x9
      controller.cyclePageFormat();
      expect(controller.renderOptions.effectivePageFormat, PageFormat.slide4x3);

      controller.cyclePageFormat();
      expect(controller.renderOptions.effectivePageFormat, PageFormat.fluid);
      expect(controller.renderOptions.isFluid, isTrue);

      controller.cyclePageFormat();
      expect(controller.renderOptions.effectivePageFormat, PageFormat.a4Portrait);

      controller.cyclePageFormat();
      expect(controller.renderOptions.effectivePageFormat, PageFormat.a4Landscape);

      controller.cyclePageFormat();
      expect(controller.renderOptions.effectivePageFormat, PageFormat.slide16x9);
    });

    test('ReaderController presentation mode toggle and setHeaderFooterOptions work correctly', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      expect(controller.isPresentationMode, isFalse);

      controller.setPresentationMode(true);
      expect(controller.isPresentationMode, isTrue);

      controller.togglePresentationMode();
      expect(controller.isPresentationMode, isFalse);

      controller.setHeaderFooterOptions(
        headerLeft: 'My Slide Deck',
        footerRight: '{page} / {total}',
        showHeaderRule: true,
        marpEnabled: true,
      );

      expect(controller.renderOptions.headerLeft, 'My Slide Deck');
      expect(controller.renderOptions.footerRight, '{page} / {total}');
      expect(controller.renderOptions.showHeaderRule, isTrue);
      expect(controller.renderOptions.marpEnabled, isTrue);

      // Verify clearing header and footer slots
      controller.setHeaderFooterOptions(
        headerLeft: null,
        footerRight: null,
      );

      expect(controller.renderOptions.headerLeft, isNull);
      expect(controller.renderOptions.footerRight, isNull);
    });
  });

  group('PresentationView Widget Tests', () {
    testWidgets('renders presentation view HUD and responds to navigation, screen blanking and exit', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(multipagePdfFile.path);
      expect(controller.currentPdfBytes, isNotNull);

      bool exited = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresentationView(
              controller: controller,
              onExit: () => exited = true,
            ),
          ),
        ),
      );

      Future<void> advance([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
      }

      await advance(30);

      // Presenter HUD should be visible initially with slide counter
      expect(find.textContaining('1 / 40'), findsOneWidget);
      expect(find.byTooltip('上一页 (← / PageUp)'), findsOneWidget);
      expect(find.byTooltip('下一页 (→ / Space)'), findsOneWidget);
      expect(find.byTooltip('退出放映 (Esc)'), findsOneWidget);
      // Black / White screen pause buttons have been removed
      expect(find.text('黑屏 (B)'), findsNothing);
      expect(find.text('白屏 (W)'), findsNothing);

      // Verify presentation view background color matches default theme (light mode -> 0xFFEBEBEB)
      final scaffoldFinder = find.descendant(
        of: find.byType(PresentationView),
        matching: find.byType(Scaffold),
      );
      expect(scaffoldFinder, findsOneWidget);
      final scaffold = tester.widget<Scaffold>(scaffoldFinder);
      expect(scaffold.backgroundColor, const Color(0xFFEBEBEB));

      // Tap next page button
      final nextBtn = find.byTooltip('下一页 (→ / Space)');
      await tester.tap(nextBtn);
      await advance();
      expect(find.textContaining('2 / 40'), findsOneWidget);

      // Tap previous page button
      final prevBtn = find.byTooltip('上一页 (← / PageUp)');
      await tester.tap(prevBtn);
      await advance();
      expect(find.textContaining('1 / 40'), findsOneWidget);

      // Exit button triggers onExit callback
      final exitBtn = find.byTooltip('退出放映 (Esc)');
      await tester.tap(exitBtn);
      await advance(50);
      expect(exited, isTrue);
    });

    testWidgets('presentation view background adapts to dark theme and handles keyboard navigation', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      // Switch to dark theme
      controller.toggleTheme();

      await controller.openFile(multipagePdfFile.path);

      bool exited = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresentationView(
              controller: controller,
              onExit: () => exited = true,
            ),
          ),
        ),
      );

      Future<void> advance([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
      }

      await advance(30);
      expect(find.textContaining('1 / 40'), findsOneWidget);

      // Verify dark theme background color (0xFF141414)
      final scaffoldFinder = find.descendant(
        of: find.byType(PresentationView),
        matching: find.byType(Scaffold),
      );
      final scaffold = tester.widget<Scaffold>(scaffoldFinder);
      expect(scaffold.backgroundColor, const Color(0xFF141414));

      // Send Space key -> should advance to page 2
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await advance();
      expect(find.textContaining('2 / 40'), findsOneWidget);

      // Send ArrowRight key -> should advance to page 3
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await advance();
      expect(find.textContaining('3 / 40'), findsOneWidget);

      // Send ArrowLeft key -> should go back to page 2
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await advance();
      expect(find.textContaining('2 / 40'), findsOneWidget);

      // Send Escape -> should exit presentation
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance(50);
      expect(exited, isTrue);
    });
  });
}
