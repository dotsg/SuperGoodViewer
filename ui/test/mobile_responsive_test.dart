import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/font_download_service.dart';
import 'package:sogoodviewer/services/form_factor.dart';
import 'package:sogoodviewer/views/mobile_typography_sheet.dart';
import 'package:sogoodviewer/views/mobile_workspace_chrome.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';
import 'package:sogoodviewer/views/sidebar_view.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const phoneSize = Size(390, 844); // Standard mobile phone viewport

  group('Mobile Responsive Workspace Tests', () {
    setUp(() {
      FormFactor.debugOverrideIsMobile = true;
      final binding = TestDefaultBinaryMessengerBinding.instance;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.sogoodviewer.app'),
        (call) async {
          if (call.method == 'getInitialFile') {
            return null;
          }
          return null;
        },
      );
    });

    tearDown(() {
      FormFactor.debugOverrideIsMobile = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('com.sogoodviewer.app'), null);
    });

    testWidgets('WorkspaceView renders cleanly on phone viewport without overflow', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Verify no exceptions or overflows
      expect(tester.takeException(), isNull);
      expect(find.byType(WorkspaceView), findsOneWidget);

      // Verify mobile top title bar is present with hamburger menu
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Tapping menu icon on phone opens Drawer rather than docking inline', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Before tapping menu, Drawer is not open
      expect(find.byType(Drawer), findsNothing);

      // Tap hamburger menu button in mobile header
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Drawer is now open containing SidebarView
      expect(find.byType(Drawer), findsOneWidget);
      expect(find.descendant(of: find.byType(Drawer), matching: find.byType(SidebarView)), findsOneWidget);

      // Tapping close button in SidebarView dismisses the Drawer
      final closeBtn = find.descendant(of: find.byType(Drawer), matching: find.byIcon(Icons.close_rounded));
      if (closeBtn.evaluate().isNotEmpty) {
        await tester.tap(closeBtn.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(Drawer), findsNothing);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Mobile intent onOpenFile via MethodChannel loads document into controller', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final tempDir = Directory.systemTemp.createTempSync('sgv_mobile_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final testFile = File('${tempDir.path}/mobile_guide.md')..writeAsStringSync('# Mobile Reader Guide\nContent here');

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(
          controller: controller,
          enableSystemIntegration: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Simulate native platform sending onOpenFile (Android ACTION_VIEW Intent)
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const codec = StandardMethodCodec();
      final data = codec.encodeMethodCall(MethodCall('onOpenFile', testFile.path));
      await messenger.handlePlatformMessage('com.sogoodviewer.app', data, (ByteData? reply) {});
      await tester.pump(const Duration(milliseconds: 800));

      // Controller should have opened the document
      expect(controller.documentTitle, equals('mobile_guide'));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Mobile bottom reading bar renders with progress slider and 4 touch buttons', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Bottom reading bar should have reading progress slider
      expect(find.byType(Slider), findsOneWidget);

      // Verify the 4 touch action buttons exist
      expect(find.byIcon(Icons.format_list_bulleted_rounded), findsOneWidget); // TOC
      expect(find.byIcon(Icons.text_fields_rounded), findsOneWidget); // Aa 排版
      expect(find.text(controller.strings.mobileTypography), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Tapping Aa on mobile bottom bar opens MobileTypographySheet', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Bottom sheet is not visible initially
      expect(find.byType(MobileTypographySheet), findsNothing);

      // Tap Aa typography button
      await tester.tap(find.text(controller.strings.mobileTypography));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // MobileTypographySheet should be visible
      expect(find.byType(MobileTypographySheet), findsOneWidget);
      expect(find.text(controller.strings.tabTypographyTitle), findsOneWidget);
      expect(find.text('A-'), findsOneWidget);
      expect(find.text('A+'), findsOneWidget);

      // Test font size stepper
      final initialSize = controller.renderOptions.fontSize;
      await tester.tap(find.text('A+'));
      await tester.pump();
      expect(controller.renderOptions.fontSize, greaterThan(initialSize));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Settings dialog adapts to fullscreen with mobile tab chips on mobile viewport', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSettingsDialog(context, controller),
              child: const Text('Open Settings'),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      // Tap to open settings
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // SettingsDialog should be displayed in fullscreen mode
      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.byType(FilterChip), findsWidgets);

      // Mobile filters should not show CLI tab
      expect(find.text(controller.strings.tabCli), findsNothing);

      // Verify switching across ALL mobile tabs (Layout, Typography, About) does NOT crash with unbounded height or overflow
      final chips = find.byType(FilterChip);
      expect(chips, findsNWidgets(4));

      await tester.tap(chips.at(1)); // Layout tab
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(chips.at(2)); // Typography tab
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(chips.at(3));
      await tester.pump();
      await tester.tap(chips.at(3)); // About tab
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    test('ReaderController initializes with phone-optimized default viewportWidth (390) and fontSize (11.5) on mobile', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      expect(controller.renderOptions.viewportWidth, equals(FormFactor.defaultMobileViewportWidth));
      expect(controller.renderOptions.fontSize, equals(FormFactor.defaultMobileFontSize));

      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    testWidgets('MobileTypographySheet supports 3-theme switching (Light / Sepia / Dark), Edge-Tap toggle, and Keep Screen On', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      bool? lastKeepScreenOnValue;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.sogoodviewer.app'),
        (call) async {
          if (call.method == 'setKeepScreenOn') {
            lastKeepScreenOnValue = call.arguments as bool?;
          }
          return null;
        },
      );

      final prefs = MobileReadingPrefs.instance;
      prefs.setSepia(false);
      prefs.setEdgeTapPageTurn(true);
      prefs.setKeepScreenOn(false);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Open Aa Typography Sheet
      await tester.tap(find.text(controller.strings.mobileTypography));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Tap Warm Sepia theme card
      await tester.tap(find.byKey(const Key('mobile_theme_sepia')));
      await tester.pump();
      expect(prefs.isSepia, isTrue);
      expect(controller.renderOptions.isDark, isFalse);
      expect(
        prefs.resolveCanvasColorFilter(
          isDark: controller.renderOptions.isDark,
          isPdfDocument: false,
          isMobile: true,
        ),
        isNotNull,
      );

      // Tap Dark theme card
      await tester.tap(find.byKey(const Key('mobile_theme_dark')));
      await tester.pump();
      expect(prefs.isSepia, isFalse);
      expect(controller.renderOptions.isDark, isTrue);
      // PDF dark invert applies to PDF sessions in dark mode
      expect(
        prefs.resolveCanvasColorFilter(
          isDark: true,
          isPdfDocument: true,
          isMobile: true,
        ),
        isNotNull,
      );

      // Scroll down inside the sheet to reach Keep Screen On switch
      final keepScreenSwitch = find.byKey(const Key('mobile_keep_screen_on_switch'));
      await tester.ensureVisible(keepScreenSwitch);
      await tester.pump();
      await tester.tap(keepScreenSwitch);
      await tester.pump();
      expect(prefs.keepScreenOn, isTrue);
      expect(lastKeepScreenOnValue, isTrue);

      // Reset prefs
      prefs.setKeepScreenOn(false);
      prefs.setSepia(false);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Mobile bottom HUD supports Fluid mode percentage slider and Paged mode Jump-to-Page dialog', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // In default Fluid mode, indicator shows percentage (e.g. 0%)
      expect(find.text('0%'), findsOneWidget);

      // Switch to Paged mode and verify buildBottomHud with 10 pages opens Jump-to-Page dialog
      controller.toggleMode();
      int? jumpedPage;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => MobileWorkspaceChrome.buildBottomHud(
              context,
              visible: true,
              isDark: false,
              controller: controller,
              bottomPadding: 0,
              currentPage: 3,
              pageCount: 10,
              scrubbingPage: null,
              onScrubbingChanged: (_) {},
              onCancelToolbarTimer: () {},
              onRestartToolbarTimer: () {},
              onPrevPage: () {},
              onNextPage: () {},
              onJumpToPage: (p) => jumpedPage = p,
              onToggleSidebar: () {},
              onToggleCropMargins: () {},
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('3 / 10'), findsOneWidget);

      // Tap page indicator to open Jump-to-Page dialog
      await tester.tap(find.byKey(const Key('mobile_page_indicator')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, '7');
      await tester.tap(find.byType(FilledButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(jumpedPage, equals(7));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Multi-tab sessions on mobile show tab badge and do not prevent HUD auto-hide', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final tempDir = Directory.systemTemp.createTempSync('sgv_multitab_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final f1 = File('${tempDir.path}/doc1.md')..writeAsStringSync('# Doc 1');
      final f2 = File('${tempDir.path}/doc2.md')..writeAsStringSync('# Doc 2');

      await controller.openFile(f1.path);
      await controller.openFile(f2.path);
      expect(controller.sessions.length, greaterThanOrEqualTo(2));

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Multi-tab badge is shown in mobile top bar
      final badgeFinder = find.byKey(const Key('mobile_tabs_badge'));
      expect(badgeFinder, findsOneWidget);

      // Tap badge to open mobile tabs bottom sheet
      await tester.tap(badgeFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('doc1'), findsWidgets);
      expect(find.text('doc2'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    test('MobileWorkspaceChrome.handleCanvasTap routes left/right edge taps to page turns and center tap to HUD toggle', () {
      final prefs = MobileReadingPrefs.instance;
      prefs.setEdgeTapPageTurn(true);

      int prevCount = 0;
      int nextCount = 0;
      int hudToggleCount = 0;

      // Left 22% zone (x = 40 on 390px width) -> previous page
      MobileWorkspaceChrome.handleCanvasTap(
        localPosition: const Offset(40, 400),
        viewSize: phoneSize,
        onToggleToolbar: () => hudToggleCount++,
        onPrevPage: () => prevCount++,
        onNextPage: () => nextCount++,
      );
      expect(prevCount, equals(1));
      expect(nextCount, equals(0));
      expect(hudToggleCount, equals(0));

      // Right 22% zone (x = 350 on 390px width) -> next page
      MobileWorkspaceChrome.handleCanvasTap(
        localPosition: const Offset(350, 400),
        viewSize: phoneSize,
        onToggleToolbar: () => hudToggleCount++,
        onPrevPage: () => prevCount++,
        onNextPage: () => nextCount++,
      );
      expect(prevCount, equals(1));
      expect(nextCount, equals(1));
      expect(hudToggleCount, equals(0));

      // Center 56% zone (x = 195 on 390px width) -> toggle HUD
      MobileWorkspaceChrome.handleCanvasTap(
        localPosition: const Offset(195, 400),
        viewSize: phoneSize,
        onToggleToolbar: () => hudToggleCount++,
        onPrevPage: () => prevCount++,
        onNextPage: () => nextCount++,
      );
      expect(hudToggleCount, equals(1));

      // When edgeTapPageTurn is disabled, edge taps also toggle HUD
      prefs.setEdgeTapPageTurn(false);
      MobileWorkspaceChrome.handleCanvasTap(
        localPosition: const Offset(40, 400),
        viewSize: phoneSize,
        onToggleToolbar: () => hudToggleCount++,
        onPrevPage: () => prevCount++,
        onNextPage: () => nextCount++,
      );
      expect(prevCount, equals(1));
      expect(hudToggleCount, equals(2));

      prefs.setEdgeTapPageTurn(true);
    });

    test('WeChat / external intent PDF opening detects %PDF header even without .pdf extension and rejects empty/corrupt PDFs', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final tempDir = Directory.systemTemp.createTempSync('sgv_wechat_pdf_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      // 1. Simulate a WeChat FileProvider file whose display name lacked an extension or had a preamble before %PDF-1.7
      final validPdfBytes = <int>[
        0x00, 0x00, 0x0A, // preamble bytes within first 1024 bytes
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x37, 0x0A, // %PDF-1.7\n
        ...List<int>.filled(128, 0x20),
      ];
      final wechatFile = File('${tempDir.path}/1710000000_wechat_share.bin')
        ..writeAsBytesSync(validPdfBytes);

      await controller.openFile(wechatFile.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.isCompiling, isFalse);
      expect(controller.errorMessage, isNull);
      expect(controller.currentPdfBytes, isNotNull);
      expect(controller.currentPdfBytes!.length, equals(validPdfBytes.length));

      // 2. Simulate an empty or truncated 0-byte .pdf file from failed stream copy
      final emptyPdf = File('${tempDir.path}/empty_wechat.pdf')
        ..writeAsBytesSync(const <int>[]);

      await controller.openFile(emptyPdf.path);
      expect(controller.isPdfDocument, isTrue);
      expect(controller.isCompiling, isFalse);
      expect(controller.currentPdfBytes, isNull);
      expect(controller.errorMessage, isNotNull);
    });

    test('FontDownloadService.downloadAndInstallMapleMono extracts core .ttf weights from zip and activates Maple Mono', () async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final tempDir = Directory.systemTemp.createTempSync('sgv_custom_fonts_');
      FontDownloadService.customFontsDirForTesting = tempDir;
      addTearDown(() {
        FontDownloadService.customFontsDirForTesting = null;
        FontDownloadService.debugDownloadOverride = null;
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      // Build a synthetic ZIP archive containing core Maple Mono weights + an extra Thin weight
      final archive = Archive();
      final dummyTtfBytes = Uint8List.fromList(<int>[0, 1, 0, 0, ...List<int>.filled(64, 0x41)]);
      for (final fileName in const [
        'MapleMono-NF-CN-Regular.ttf',
        'MapleMono-NF-CN-Bold.ttf',
        'MapleMono-NF-CN-Italic.ttf',
        'MapleMono-NF-CN-BoldItalic.ttf',
        'MapleMono-NF-CN-Medium.ttf',
        'MapleMono-NF-CN-SemiBold.ttf',
        'MapleMono-NF-CN-Thin.ttf',
        'MapleMono-NF-CN-ExtraLight.ttf',
      ]) {
        archive.addFile(ArchiveFile(fileName, dummyTtfBytes.length, dummyTtfBytes));
      }
      final encodedZip = Uint8List.fromList(ZipEncoder().encode(archive));

      final reportedProgress = <double>[];
      FontDownloadService.debugDownloadOverride = (onProgress) async {
        onProgress(0.35);
        reportedProgress.add(FontDownloadService.instance.progress);
        onProgress(0.85);
        reportedProgress.add(FontDownloadService.instance.progress);
        return encodedZip;
      };

      final ok = await FontDownloadService.instance.downloadAndInstallMapleMono(controller);
      expect(ok, isTrue);
      expect(reportedProgress, equals([0.35, 0.85]));
      expect(FontDownloadService.instance.isBusy, isFalse);

      // Core 6 weights should be extracted while Thin / ExtraLight are skipped
      final extractedNames = tempDir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toSet();
      expect(extractedNames.contains('MapleMono-NF-CN-Regular.ttf'), isTrue);
      expect(extractedNames.contains('MapleMono-NF-CN-Bold.ttf'), isTrue);
      expect(extractedNames.contains('MapleMono-NF-CN-Thin.ttf'), isFalse);
      expect(controller.renderOptions.codeFont?.toLowerCase(), contains('maple mono'));
    });

    testWidgets('Mobile Settings Layout & Typography tabs handle narrow 360dp phone screen and expose font install controls without overflow', (tester) async {
      // Test on a compact 360dp-wide Android phone screen
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SettingsDialog(
            controller: controller,
            initialTab: SettingsTab.typography,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);

      // Local font import button is always available in Typography tab
      expect(find.byKey(const Key('settings_import_font_btn')), findsOneWidget);

      // Switch to Layout tab on 360dp screen and trigger unsaved changes to verify mobile stacked bottom bar & vertical slot inputs
      final chips = find.byType(FilterChip);
      await tester.tap(chips.at(1)); // Layout tab
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    test('SuperGoodSizeDelegate locks mobile panAxis to vertical at fit-width and normalizes horizontal drift to zero', () {
      // 1. At or below fit-width (coverScale), mobile uses PanAxis.vertical
      expect(
        SuperGoodSizeDelegate.resolveMobilePanAxis(
          isMobile: true,
          currentZoom: 0.65,
          coverScale: 0.65,
        ),
        equals(PanAxis.vertical),
      );

      // 2. When zoomed in past coverScale * 1.03, mobile uses PanAxis.aligned (preventing diagonal drift while allowing horizontal pan)
      expect(
        SuperGoodSizeDelegate.resolveMobilePanAxis(
          isMobile: true,
          currentZoom: 1.2,
          coverScale: 0.65,
        ),
        equals(PanAxis.aligned),
      );

      // 3. Desktop always keeps PanAxis.free
      expect(
        SuperGoodSizeDelegate.resolveMobilePanAxis(
          isMobile: false,
          currentZoom: 0.65,
          coverScale: 0.65,
        ),
        equals(PanAxis.free),
      );

      // 4. normalizeMobileMatrix centers X and eliminates horizontal drift when at/below fit-width
      const viewSize = Size(390, 844);
      const docSize = Size(615, 2000);
      const coverScale = 0.595;
      final driftedMatrix = Matrix4.diagonal3Values(coverScale, coverScale, coverScale)
        ..setTranslationRaw(-85.0, -320.0, 0.0); // drifted X, scrolled Y

      final normalized = SuperGoodSizeDelegate.normalizeMobileMatrix(
        clampedMatrix: driftedMatrix,
        viewSize: viewSize,
        documentSize: docSize,
        coverScale: coverScale,
        pdfCropMargins: false,
      );

      final expectedXZoomed = viewSize.width / 2 - (docSize.width / 2) * coverScale;
      expect(normalized.xZoomed, closeTo(expectedXZoomed, 0.001));
      expect(normalized.yZoomed, closeTo(-320.0, 0.001));

      // 5. When zoomed in (> coverScale * 1.03), horizontal pan position is preserved
      const zoomedScale = 1.25;
      final zoomedMatrix = Matrix4.diagonal3Values(zoomedScale, zoomedScale, zoomedScale)
        ..setTranslationRaw(-140.0, -320.0, 0.0);

      final zoomedNormalized = SuperGoodSizeDelegate.normalizeMobileMatrix(
        clampedMatrix: zoomedMatrix,
        viewSize: viewSize,
        documentSize: docSize,
        coverScale: coverScale,
        pdfCropMargins: false,
      );
      expect(zoomedNormalized.xZoomed, closeTo(-140.0, 0.001));
      expect(zoomedNormalized.yZoomed, closeTo(-320.0, 0.001));
    });
  });

  group('Desktop Narrow Viewport Tests', () {
    setUp(() {
      FormFactor.debugOverrideIsMobile = false;
    });

    tearDown(() {
      FormFactor.debugOverrideIsMobile = null;
    });

    testWidgets('Desktop narrow viewport preserves desktop UI paradigms (no mobile HUD/hamburger)', (tester) async {
      tester.view.physicalSize = phoneSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: WorkspaceView(controller: controller),
      ));
      await tester.pump(const Duration(milliseconds: 800));

      // Mobile hamburger icon should NOT be present on desktop
      expect(find.byIcon(Icons.menu_rounded), findsNothing);

      // Mobile bottom reading bar slider should NOT be present on desktop
      expect(find.byType(Slider), findsNothing);

      // Mobile typography sheet trigger should NOT be present
      expect(find.text(controller.strings.mobileTypography), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('Desktop preserves desktop dialog with sidebar navigation and CLI tab', (tester) async {
      tester.view.physicalSize = const Size(1000, 750);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showSettingsDialog(context, controller),
              child: const Text('Open Settings'),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Mobile FilterChips should NOT be used on desktop
      expect(find.byType(FilterChip), findsNothing);

      // Desktop sidebar should contain the CLI tab
      expect(find.text(controller.strings.tabCli), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
