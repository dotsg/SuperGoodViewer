import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  late Directory tempTestDir;
  final multipagePdfFile = File('packages/pdfrx/test/assets/multipage40.pdf').absolute;

  setUpAll(() async {
    tempTestDir = Directory.systemTemp.createTempSync('sgv_nav_scroll_test_');
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
    try {
      tempTestDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('Space scrolls down and preserves intra-page position without jumping page', (tester) async {
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    await controller.openFile(multipagePdfFile.path);
    controller.setPageFormat(PageFormat.a4Portrait);

    await tester.pumpWidget(MaterialApp(home: WorkspaceView(controller: controller)));

    Future<void> advance([int frames = 30]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      }
    }

    await advance(60);
    final canvas = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));
    expect(canvas.isReady, isTrue);
    expect(canvas.pageNumber, 1);

    // Zoom in to 150%
    await canvas.pdfController.setZoom(Offset.zero, 1.5, duration: Duration.zero);
    await advance(10);
    expect(canvas.currentZoom, closeTo(1.5, 0.05));

    // Initial position on Page 1
    final initialTop = canvas.pdfController.visibleRect.top;

    // Press Space: should scroll screen down, still on Page 1
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await advance(30);

    final scrolledTop = canvas.pdfController.visibleRect.top;
    expect(scrolledTop, greaterThan(initialTop));
    expect(canvas.pageNumber, 1, reason: 'Space scrolls within the page without skipping to next page');

    // Press Shift+Space: should scroll screen up back towards initial
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await advance(30);

    final backTop = canvas.pdfController.visibleRect.top;
    expect(backTop, lessThan(scrolledTop));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('PageDown and ArrowRight jump to next page preserving intra-page offset and zoom', (tester) async {
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    await controller.openFile(multipagePdfFile.path);
    controller.setPageFormat(PageFormat.a4Portrait);

    await tester.pumpWidget(MaterialApp(home: WorkspaceView(controller: controller)));

    Future<void> advance([int frames = 30]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      }
    }

    await advance(60);
    final canvas = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));
    expect(canvas.isReady, isTrue);
    expect(canvas.pageNumber, 1);

    // Zoom to 150%
    await canvas.pdfController.setZoom(Offset.zero, 1.5, duration: Duration.zero);
    await advance(10);
    expect(canvas.currentZoom, closeTo(1.5, 0.05));

    // Scroll down 200 points in Page 1
    await canvas.scrollByDelta(200);
    await advance(30);

    final page1Rect = canvas.pdfController.layout.pageLayouts[0];
    final page1RelY = canvas.pdfController.visibleRect.top - page1Rect.top;
    expect(page1RelY, greaterThan(100));

    // Press PageDown: should jump to Page 2 at same relative offset
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await advance(30);

    expect(canvas.pageNumber, 2);
    expect(canvas.currentZoom, closeTo(1.5, 0.05), reason: 'Zoom must be preserved across PageDown');

    final page2Rect = canvas.pdfController.layout.pageLayouts[1];
    final page2RelY = canvas.pdfController.visibleRect.top - page2Rect.top;
    expect(page2RelY, closeTo(page1RelY, 5.0), reason: 'Intra-page relative Y offset must be preserved');

    // Press ArrowRight: should jump to Page 3 at same relative offset
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await advance(30);

    expect(canvas.pageNumber, 3);
    expect(canvas.currentZoom, closeTo(1.5, 0.05));

    final page3Rect = canvas.pdfController.layout.pageLayouts[2];
    final page3RelY = canvas.pdfController.visibleRect.top - page3Rect.top;
    expect(page3RelY, closeTo(page1RelY, 5.0));

    // Press ArrowLeft: should jump back to Page 2 at same relative offset
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await advance(30);

    expect(canvas.pageNumber, 2);
    expect(canvas.currentZoom, closeTo(1.5, 0.05));

    // Press PageUp: should jump back to Page 1 at same relative offset
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await advance(30);

    expect(canvas.pageNumber, 1);
    expect(canvas.currentZoom, closeTo(1.5, 0.05));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Space flips page when page fits viewport in paged mode', (tester) async {
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    await controller.openFile(multipagePdfFile.path);
    controller.setPageFormat(PageFormat.a4Portrait);

    // Set screen size large enough so A4 page fits viewport
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(home: WorkspaceView(controller: controller)));

    Future<void> advance([int frames = 30]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      }
    }

    await advance(60);
    final canvas = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));
    expect(canvas.isReady, isTrue);
    expect(canvas.pageNumber, 1);
    expect(canvas.isCurrentPageFittingViewport, isTrue);

    // Space should flip to Page 2 because the page fits in the viewport
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await advance(30);
    expect(canvas.pageNumber, 2);

    // Shift+Space should flip back to Page 1
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await advance(30);
    expect(canvas.pageNumber, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Two-page spread navigation preserves horizontal offset without drift', (tester) async {
    const windowChannel = MethodChannel('com.sogoodviewer.window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, null));

    final controller = ReaderController(autoRestorePreferences: false);
    addTearDown(controller.dispose);
    await controller.openFile(multipagePdfFile.path);
    controller.setPageFormat(PageFormat.a4Portrait);
    controller.setTwoPage(true);

    await tester.pumpWidget(MaterialApp(home: WorkspaceView(controller: controller)));

    Future<void> advance([int frames = 30]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
      }
    }

    await advance(60);
    final canvas = tester.state<PdfCanvasViewState>(find.byType(PdfCanvasView));
    expect(canvas.isReady, isTrue);

    final initialLeft = canvas.pdfController.visibleRect.left;

    // Navigate to next spread
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await advance(30);

    // Horizontal offset should match initial visibleRect.left without drifting
    expect(canvas.pdfController.visibleRect.left, closeTo(initialLeft, 1.0));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
