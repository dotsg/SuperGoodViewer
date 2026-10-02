import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/i18n/locales.dart';
import 'package:sogoodviewer/services/linux_desktop_integration.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';
import 'package:sogoodviewer/views/workspace_view.dart';

/// Renders the main surfaces in every UI language at the minimum window size
/// (800x600, enforced by the macOS / Windows / Linux runners) and a typical
/// one, and fails on any layout overflow.
///
/// The default test font draws every glyph as a 1em square, which makes Latin
/// text about twice as wide as it really is. Roboto from the Flutter SDK gives
/// realistic English widths; CJK keeps the square fallback, which is close to
/// the real 1em width of CJK glyphs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowSizes = [Size(800, 600), Size(1280, 800)];

  setUpAll(() async {
    final fontsDir = p.join(
      Platform.environment['FLUTTER_ROOT'] ?? '',
      'bin', 'cache', 'artifacts', 'material_fonts',
    );
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File(p.join(fontsDir, file)).readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
    await load('MaterialIcons', ['MaterialIcons-Regular.otf']);

    // Show the Linux-only desktop integration card on every host, in its
    // widest state (an outdated entry: warning text plus two buttons).
    final dataHome = Directory.systemTemp.createTempSync('sgv_overflow_').path;
    File(p.join(dataHome, 'applications', '${LinuxDesktopIntegration.appId}.desktop'))
      ..createSync(recursive: true)
      ..writeAsStringSync('[Desktop Entry]\n');
    LinuxDesktopIntegration.isSupported = true;
    LinuxDesktopIntegration.instance = LinuxDesktopIntegration(dataHome: dataHome, bundleDir: dataHome);
  });

  tearDownAll(() {
    LinuxDesktopIntegration.isSupported = Platform.isLinux;
    LinuxDesktopIntegration.instance = LinuxDesktopIntegration();
  });

  Future<void> expectNoOverflow(
    WidgetTester tester,
    String surface,
    Widget Function(ReaderController controller) build, {
    void Function(ReaderController controller)? setup,
  }) async {
    final overflows = <String>[];
    for (final language in AppLanguage.values.where((l) => l != AppLanguage.system)) {
      for (final size in windowSizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        final controller = ReaderController(autoRestorePreferences: false, defaultLanguage: language.code);
        setup?.call(controller);

        final previousOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          final source = RegExp(r'lib/(?:views|controllers)/[^\s:]+\.dart:\d+').firstMatch(details.toString())?.group(0) ?? '';
          overflows.add('${language.code} ${size.width.toInt()}x${size.height.toInt()}: '
              '${details.exceptionAsString().split('\n').first} $source');
        };
        try {
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: build(controller),
          ));
          await tester.pump(const Duration(milliseconds: 300));
        } finally {
          FlutterError.onError = previousOnError;
        }

        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        // Let the controller's debounce and toolbar timers run out.
        await tester.pump(const Duration(seconds: 1));
      }
    }
    expect(overflows.toSet(), isEmpty, reason: '$surface overflows');
  }

  setUp(() {
    final binding = TestDefaultBinaryMessengerBinding.instance;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.sogoodviewer.app'),
      (call) async => call.method == 'checkCliStatus'
          ? {'isInstalled': false, 'path': '/usr/local/bin/sgv', 'target': '', 'isCurrentApp': false}
          : null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.sogoodviewer.app'), null);
  });

  for (final tab in SettingsTab.values) {
    testWidgets('Settings ${tab.name} tab fits in every language', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await expectNoOverflow(
        tester,
        'Settings ${tab.name} tab',
        (c) => Scaffold(body: SettingsDialog(controller: c, initialTab: tab)),
      );
    });
  }

  testWidgets('Workspace fits in every language', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await expectNoOverflow(tester, 'Workspace', (c) => WorkspaceView(controller: c));
  });

  testWidgets('Workspace with several tabs fits in every language', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final docs = Directory.systemTemp.createTempSync('sgv_overflow_tabs_');
    addTearDown(() => docs.deleteSync(recursive: true));
    final paths = [
      for (final name in ['a-rather-long-design-document-name', '第二份文档的标题也相当长', 'notes'])
        (File(p.join(docs.path, '$name.md'))..writeAsStringSync('# $name')).path,
    ];
    await expectNoOverflow(
      tester,
      'Workspace with tabs',
      (c) => WorkspaceView(controller: c),
      setup: (c) {
        for (final path in paths) {
          c.openFile(path);
        }
      },
    );
  });

  testWidgets('Workspace with sidebar fits in every language', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await expectNoOverflow(
      tester,
      'Workspace with sidebar',
      (c) => WorkspaceView(controller: c),
      setup: (c) => c.toggleSidebar(),
    );
  });
}
