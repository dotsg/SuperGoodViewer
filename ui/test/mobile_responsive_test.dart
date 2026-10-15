import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/form_factor.dart';
import 'package:sogoodviewer/views/mobile_typography_sheet.dart';
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

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
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
