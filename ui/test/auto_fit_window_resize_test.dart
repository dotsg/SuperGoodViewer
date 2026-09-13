import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AutoFitMode Controller State Tests', () {
    test('autoFitMode initializes to none and notifies listeners on change', () {
      final controller = ReaderController(autoRestorePreferences: false);
      expect(controller.autoFitMode, equals(AutoFitMode.none));

      var notified = false;
      controller.addListener(() => notified = true);

      controller.setAutoFitMode(AutoFitMode.fitWidth);
      expect(controller.autoFitMode, equals(AutoFitMode.fitWidth));
      expect(notified, isTrue);

      notified = false;
      controller.setAutoFitMode(AutoFitMode.fitPage);
      expect(controller.autoFitMode, equals(AutoFitMode.fitPage));
      expect(notified, isTrue);

      notified = false;
      controller.setAutoFitMode(AutoFitMode.none);
      expect(controller.autoFitMode, equals(AutoFitMode.none));
      expect(notified, isTrue);
    });
  });

  group('SuperGoodSizeDelegate calculateMetrics Tests', () {
    test('Fluid mode: coverScale matches fitWidth and alternativeFitScale is comfortable fit', () {
      final controller = ReaderController(autoRestorePreferences: false);
      final delegate = SuperGoodSizeDelegate(
        readerController: controller,
        isFluid: true,
        isTwoPage: false,
        minScale: 0.35,
        maxScale: 5.0,
      );

      // View size 1000 x 800, margin 8.0, document width 720.0
      // Expected fit width = (1000 - 0 - 16) / 720 = 984 / 720 = 1.3666...
      final metrics = delegate.calculateMetrics(
        viewSize: const Size(1000, 800),
        layout: PdfPageLayout(
          pageLayouts: const [Rect.fromLTWH(0, 0, 720, 2000)],
          documentSize: const Size(720, 2000),
        ),
        pageNumber: 1,
        pageMargin: 8.0,
        boundaryMargin: EdgeInsets.zero,
      );

      expect(metrics.coverScale, closeTo(984 / 720, 0.001));
      // Comfortable fit is capped at 1.15 in fluid mode
      expect(metrics.alternativeFitScale, closeTo(1.15, 0.001));
    });

    test('A4 mode single page: coverScale is fitWidth, alternativeFitScale is fitPage', () {
      final controller = ReaderController(autoRestorePreferences: false);
      final delegate = SuperGoodSizeDelegate(
        readerController: controller,
        isFluid: false,
        isTwoPage: false,
        minScale: 0.2,
        maxScale: 5.0,
      );

      // View size 800 x 1000, A4 page: 595 x 842, margin 10.0, boundary margin 16 horizontal, 20 vertical
      // sX = (800 - 16 - 20) / 595 = 764 / 595 = 1.284
      // sY = (1000 - 20 - 20) / 842 = 960 / 842 = 1.140
      final metrics = delegate.calculateMetrics(
        viewSize: const Size(800, 1000),
        layout: PdfPageLayout(
          pageLayouts: const [Rect.fromLTWH(0, 0, 595, 842)],
          documentSize: const Size(595, 842),
        ),
        pageNumber: 1,
        pageMargin: 10.0,
        boundaryMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      );

      expect(metrics.coverScale, closeTo(764 / 595, 0.001));
      expect(metrics.alternativeFitScale, closeTo(960 / 842, 0.001));
    });

    test('A4 mode two-page spread: calculates spread dimensions accurately', () {
      final controller = ReaderController(autoRestorePreferences: false);
      final delegate = SuperGoodSizeDelegate(
        readerController: controller,
        isFluid: false,
        isTwoPage: true,
        minScale: 0.2,
        maxScale: 5.0,
      );

      // Two A4 pages (595x842 each) with 12px gap = 1202px total spread width
      final metrics = delegate.calculateMetrics(
        viewSize: const Size(1600, 1000),
        layout: PdfPageLayout(
          pageLayouts: const [
            Rect.fromLTWH(0, 0, 595, 842),
            Rect.fromLTWH(607, 0, 595, 842),
          ],
          documentSize: const Size(1202, 842),
        ),
        pageNumber: 1,
        pageMargin: 10.0,
        boundaryMargin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      );

      final expectedWidth = 595.0 + 595.0 + 12.0; // 1202
      final expectedSx = (1600 - 16 - 20) / expectedWidth;
      final expectedSy = (1000 - 20 - 20) / 842;

      expect(metrics.coverScale, closeTo(expectedSx, 0.001));
      expect(metrics.alternativeFitScale, closeTo(expectedSy < expectedSx ? expectedSy : expectedSx, 0.001));
    });
  });

  group('WorkspaceView AutoFit Toolbar & Resize Integration', () {
    testWidgets('toolbar fit buttons update selection and AutoFitMode', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = ReaderController(autoRestorePreferences: false);
      await tester.pumpWidget(
        MaterialApp(
          home: WorkspaceView(controller: controller),
        ),
      );
      await tester.pump();

      final mod = Platform.isMacOS ? 'Cmd' : 'Ctrl';
      final zoomBadge = find.byTooltip('页面缩放比例与预设');
      final zoomInBtn = find.byTooltip('放大页面 ($mod+=)');

      expect(zoomBadge, findsOneWidget);
      expect(controller.autoFitMode, equals(AutoFitMode.none));

      // Click Fit Width from zoom dropdown -> autoFitMode becomes fitWidth
      await tester.tap(zoomBadge);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('满窗口 (适应宽度)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.autoFitMode, equals(AutoFitMode.fitWidth));

      // Click Fit Page from zoom dropdown -> autoFitMode becomes fitPage
      await tester.tap(zoomBadge);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('满屏 (适应整页)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.autoFitMode, equals(AutoFitMode.fitPage));

      // Click Zoom In -> autoFitMode becomes none (manual zoom)
      await tester.tap(zoomInBtn);
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.autoFitMode, equals(AutoFitMode.none));

      await tester.pump(const Duration(seconds: 1));
      controller.dispose();
    });
  });
}
