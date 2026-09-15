import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/document_cache_service.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';
import 'package:sogoodviewer/views/presentation_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempTestDir;
  final multipagePdfFile = File('packages/pdfrx/test/assets/multipage40.pdf').absolute;

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('sogoodviewer_e2e_test_');
    PreferencesService.setConfigFileForTesting(
      File(p.join(tempTestDir.path, 'preferences.json')),
    );
    final cacheDir = Directory(p.join(tempTestDir.path, 'cache'))..createSync(recursive: true);
    DocumentCacheService.setCacheDirForTesting(cacheDir);

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
    DocumentCacheService.setCacheDirForTesting(null);
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('Scenario 1: Layout Cache Keys & Auto-Refresh Isolation (Bug 2)', () {
    test('DocumentCacheService differentiates cache files across page formats', () async {
      final sampleDoc = File(p.join(tempTestDir.path, 'sample.md'))..writeAsStringSync('# Test Doc');

      const fluidOpts = RenderOptions(mode: 'fluid', pageFormat: PageFormat.fluid);
      const a4PortraitOpts = RenderOptions(mode: 'paged', pageFormat: PageFormat.a4Portrait);
      const a4LandscapeOpts = RenderOptions(mode: 'paged', pageFormat: PageFormat.a4Landscape);
      const slide16x9Opts = RenderOptions(mode: 'paged', pageFormat: PageFormat.slide16x9);
      const slide4x3Opts = RenderOptions(mode: 'paged', pageFormat: PageFormat.slide4x3);

      final dummyPdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, ...List.filled(120, 0)]);

      // Save cache for fluid
      await DocumentCacheService.saveCachedPdf(sampleDoc.path, fluidOpts, dummyPdfBytes);

      // Verify that looking up a4Portrait or slide16x9 does NOT hit fluid cache
      final hitFluid = DocumentCacheService.getCachedPdf(sampleDoc.path, fluidOpts);
      final hitA4 = DocumentCacheService.getCachedPdf(sampleDoc.path, a4PortraitOpts);
      final hitLandscape = DocumentCacheService.getCachedPdf(sampleDoc.path, a4LandscapeOpts);
      final hit16x9 = DocumentCacheService.getCachedPdf(sampleDoc.path, slide16x9Opts);
      final hit4x3 = DocumentCacheService.getCachedPdf(sampleDoc.path, slide4x3Opts);

      expect(hitFluid, isNotNull);
      expect(hitA4, isNull);
      expect(hitLandscape, isNull);
      expect(hit16x9, isNull);
      expect(hit4x3, isNull);
    });

    test('Header/Footer rule options differentiate cache file names', () async {
      final sampleDoc = File(p.join(tempTestDir.path, 'sample_hf.md'))..writeAsStringSync('# Test Header Footer');

      const baseOpts = RenderOptions(
        mode: 'paged',
        pageFormat: PageFormat.slide16x9,
        headerLeft: 'Header A',
      );
      const modifiedOpts = RenderOptions(
        mode: 'paged',
        pageFormat: PageFormat.slide16x9,
        headerLeft: 'Header B',
      );

      final dummyPdfBytes = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, ...List.filled(120, 0)]);
      await DocumentCacheService.saveCachedPdf(sampleDoc.path, baseOpts, dummyPdfBytes);

      expect(DocumentCacheService.getCachedPdf(sampleDoc.path, baseOpts), isNotNull);
      expect(DocumentCacheService.getCachedPdf(sampleDoc.path, modifiedOpts), isNull);
    });
  });

  group('Scenario 2: Presentation Mode Auto-Elevation & Slide Flipping (Bug 1 & Bug 3)', () {
    test('Entering presentation mode when fluid auto-elevates to slide16x9 and restores on exit', () {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      // Verify initial state is fluid
      expect(controller.renderOptions.isFluid, isTrue);
      expect(controller.isPresentationMode, isFalse);

      // Entering presentation mode
      controller.setPresentationMode(true);
      expect(controller.isPresentationMode, isTrue);
      // Auto-elevated to slide16x9 for paginated presentation slides
      expect(controller.renderOptions.effectivePageFormat, PageFormat.slide16x9);
      expect(controller.renderOptions.mode, 'paged');

      // Exiting presentation mode restores original fluid layout
      controller.setPresentationMode(false);
      expect(controller.isPresentationMode, isFalse);
      expect(controller.renderOptions.effectivePageFormat, PageFormat.fluid);
      expect(controller.renderOptions.mode, 'fluid');
    });

    testWidgets('PresentationView flips pages and responds to navigation keys and clicks', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(multipagePdfFile.path);
      expect(controller.currentPdfBytes, isNotNull);

      final presentationKey = GlobalKey<PresentationViewState>();
      bool exited = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PresentationView(
              key: presentationKey,
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

      // Initial page is 1
      expect(find.textContaining('1 / 40'), findsOneWidget);

      // Call public nextPage method on state
      presentationKey.currentState?.nextPage();
      await advance();
      expect(find.textContaining('2 / 40'), findsOneWidget);

      // Send ArrowRight
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await advance();
      expect(find.textContaining('3 / 40'), findsOneWidget);

      // Send Space
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await advance();
      expect(find.textContaining('4 / 40'), findsOneWidget);

      // Send ArrowLeft
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await advance();
      expect(find.textContaining('3 / 40'), findsOneWidget);

      // Click right 80% to advance forward
      await tester.tapAt(const Offset(1500, 540));
      await advance();
      expect(find.textContaining('4 / 40'), findsOneWidget);

      // Click left 20% to advance backward
      await tester.tapAt(const Offset(200, 540));
      await advance();
      expect(find.textContaining('3 / 40'), findsOneWidget);

      // Press Esc to exit
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance();
      expect(exited, isTrue);
    });
  });

  group('Scenario 3: Escape Key Hierarchy (Bug 1)', () {
    testWidgets('WorkspaceView Esc hierarchy unwinds search, presentation, and toolbars in order', (tester) async {
      const windowChannel = MethodChannel('com.sogoodviewer.window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (call) async {
        if (call.method == 'isFullScreen') return false;
        if (call.method == 'toggleFullScreen') return true;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(multipagePdfFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      Future<void> advance([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
      }

      await advance(30);

      // Step A: Trigger search bar via Cmd+F
      final canvasState = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));
      expect(canvasState.isSearchOpen, isFalse);

      canvasState.openSearch();
      await advance();
      expect(canvasState.isSearchOpen, isTrue);
      expect(find.byType(TextField), findsOneWidget);

      // Pressing Esc while search is open closes search bar
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance();
      expect(canvasState.isSearchOpen, isFalse);

      // Step B: Enter presentation mode
      controller.setPresentationMode(true);
      await advance(20);
      expect(controller.isPresentationMode, isTrue);
      expect(find.byType(PresentationView), findsOneWidget);

      // Pressing Esc while in presentation mode exits presentation
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance(20);
      expect(controller.isPresentationMode, isFalse);
      expect(find.byType(PresentationView), findsNothing);
    });
  });

  group('Scenario 4: Full-Text Search Feature (Cmd + F)', () {
    testWidgets('Search bar opens, accepts input, navigates matches, and closes via Esc', (tester) async {
      const windowChannel = MethodChannel('com.sogoodviewer.window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (call) async {
        if (call.method == 'isFullScreen') return false;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(multipagePdfFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      Future<void> advance([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
      }

      await advance(30);

      final canvasState = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));

      // 1. Open search bar
      canvasState.openSearch();
      await advance();
      expect(canvasState.isSearchOpen, isTrue);

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      expect(find.text('查找文档内容...'), findsOneWidget);
      expect(find.byTooltip('关闭 (Esc)'), findsOneWidget);
      expect(find.byTooltip('下一个 (Enter)'), findsOneWidget);
      expect(find.byTooltip('上一个 (Shift+Enter)'), findsOneWidget);

      // 2. Type search query
      await tester.enterText(searchField, 'Page');
      await advance(30);

      // 3. Navigate matches
      canvasState.searchNext();
      await advance(10);
      canvasState.searchPrev();
      await advance(10);

      // 4. Test closing via Esc key
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await advance();
      expect(canvasState.isSearchOpen, isFalse);

      // 5. Test reopen and close button
      canvasState.openSearch();
      await advance();
      expect(canvasState.isSearchOpen, isTrue);
      final closeBtn = find.byTooltip('关闭 (Esc)');
      await tester.tap(closeBtn);
      await advance();
      expect(canvasState.isSearchOpen, isFalse);
    });

    testWidgets('Search bar is positioned below menu/title bar and Space key does not flip pages when typing in search', (tester) async {
      final trafficLightCalls = <bool>[];
      const windowChannel = MethodChannel('com.sogoodviewer.window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (call) async {
        if (call.method == 'isFullScreen') return false;
        if (call.method == 'setTrafficLightsVisible') {
          trafficLightCalls.add(call.arguments as bool);
          return null;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await controller.openFile(multipagePdfFile.path);

      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );

      Future<void> advance([int frames = 20]) async {
        for (var i = 0; i < frames; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
        }
      }

      await advance(30);

      final canvasState = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));

      // 1. Open search bar
      canvasState.openSearch();
      await advance();
      expect(canvasState.isSearchOpen, isTrue);

      // Verify search bar Positioned widget top offset is 52 (not occluded by menu/title bar)
      final searchBarPositionedFinder = find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Positioned),
      );
      expect(searchBarPositionedFinder, findsWidgets);
      final positionedWidget = tester.widget<Positioned>(searchBarPositionedFinder.first);
      expect(positionedWidget.top, 52.0);

      // Verify search field is focused
      expect(canvasState.isSearchFocused, isTrue);

      // 2. Type Chinese search phrase with Space (simulating IME candidate confirmation or multi-word search)
      final searchField = find.byType(TextField);
      await tester.tap(searchField);
      await advance();

      final initialPage = controller.lastPageNumber;
      expect(initialPage, 1);

      // Send Space key while focused in search box
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await advance();

      // Ensure page did NOT flip to page 2 because of Space key
      expect(controller.lastPageNumber, initialPage);

      // Enter Chinese text with spaces
      await tester.enterText(searchField, '第 一 页');
      await advance(10);
      expect(controller.lastPageNumber, initialPage);

      // Close search
      canvasState.closeSearch();
      await advance();
      expect(canvasState.isSearchOpen, isFalse);
    });
  });
}
