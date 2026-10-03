import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/services/linux_desktop_integration.dart';
import 'package:sogoodviewer/views/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late String dataHome;
  late String bundleDir;

  String createBundle(String name) {
    final dir = p.join(root.path, name);
    for (final size in [256, 512]) {
      File(p.join(dir, 'data', 'icons', 'app_icon_$size.png'))
        ..createSync(recursive: true)
        ..writeAsStringSync('icon $size');
    }
    return dir;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('sgv_desktop_entry_');
    dataHome = p.join(root.path, 'share');
    bundleDir = createBundle('Super Good Viewer');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('LinuxDesktopIntegration', () {
    test('desktop entry launches the bundled sgv launcher and declares file types', () {
      final entry = LinuxDesktopIntegration(dataHome: dataHome, bundleDir: bundleDir).buildDesktopEntry();
      final lines = entry.split('\n');

      expect(lines.first, '[Desktop Entry]');
      expect(lines, contains('Exec=${LinuxDesktopIntegration.quoteExecArgument(p.join(bundleDir, 'bin', 'sgv'))} %F'));
      expect(lines, contains('Icon=com.sogood.sogoodviewer'));
      expect(lines, contains('StartupWMClass=com.sogood.sogoodviewer'));
      expect(lines, contains('MimeType=text/markdown;text/x-markdown;application/pdf;'));
      expect(lines, containsAll(['Name=SuperGoodViewer', 'Name[zh_CN]=超好读', 'Name[zh_TW]=超好讀']));
    });

    test('Exec arguments are quoted and escaped per the Desktop Entry spec', () {
      expect(LinuxDesktopIntegration.quoteExecArgument('/opt/a b/sgv'), '"/opt/a b/sgv"');
      expect(LinuxDesktopIntegration.quoteExecArgument(r'/x/$HOME/"q"'), r'"/x/\\$HOME/\\"q\\""');
      expect(LinuxDesktopIntegration.quoteExecArgument(r'/x\y'), r'"/x\\\\y"');
    });

    test('install, status and uninstall round-trip', () async {
      final integration = LinuxDesktopIntegration(dataHome: dataHome, bundleDir: bundleDir);
      expect(integration.status(), DesktopEntryStatus.notInstalled);

      await integration.install();
      expect(integration.status(), DesktopEntryStatus.installed);
      for (final size in [256, 512]) {
        final icon = File(p.join(dataHome, 'icons', 'hicolor', '${size}x$size', 'apps', 'com.sogood.sogoodviewer.png'));
        expect(icon.readAsStringSync(), 'icon $size');
      }

      await integration.uninstall();
      expect(integration.status(), DesktopEntryStatus.notInstalled);
      expect(Directory(p.join(dataHome, 'icons')).listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('an entry written by another copy of the app is reported as outdated', () async {
      await LinuxDesktopIntegration(dataHome: dataHome, bundleDir: createBundle('old-copy')).install();

      final current = LinuxDesktopIntegration(dataHome: dataHome, bundleDir: bundleDir);
      expect(current.status(), DesktopEntryStatus.outdated);

      await current.install();
      expect(current.status(), DesktopEntryStatus.installed);
    });
  });

  group('Settings desktop integration card', () {
    late bool wasSupported;
    late LinuxDesktopIntegration previousInstance;

    setUp(() {
      wasSupported = LinuxDesktopIntegration.isSupported;
      previousInstance = LinuxDesktopIntegration.instance;
      LinuxDesktopIntegration.isSupported = true;
      LinuxDesktopIntegration.instance = LinuxDesktopIntegration(dataHome: dataHome, bundleDir: bundleDir);
    });

    tearDown(() {
      LinuxDesktopIntegration.isSupported = wasSupported;
      LinuxDesktopIntegration.instance = previousInstance;
    });

    testWidgets('adds and removes the applications menu entry', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      final entryFile = File(LinuxDesktopIntegration.instance.desktopFilePath);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsDialog(controller: controller)),
      ));

      expect(find.text('桌面集成'), findsOneWidget);
      expect(find.text('添加到应用菜单'), findsOneWidget);

      await tester.ensureVisible(find.text('添加'));
      await tester.runAsync(() async {
        await tester.tap(find.text('添加'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(entryFile.existsSync(), isTrue);
      expect(find.text('已添加到应用菜单'), findsOneWidget);

      await tester.ensureVisible(find.text('移除'));
      await tester.runAsync(() async {
        await tester.tap(find.text('移除'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      expect(entryFile.existsSync(), isFalse);
      expect(find.text('添加'), findsOneWidget);
    });

    testWidgets('offers an update when the entry belongs to another copy', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.runAsync(
        () => LinuxDesktopIntegration(dataHome: dataHome, bundleDir: createBundle('old-copy')).install(),
      );
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SettingsDialog(controller: controller)),
      ));

      expect(find.text('菜单项指向其他位置或旧版本，建议更新'), findsOneWidget);
      expect(find.text('更新'), findsOneWidget);
      expect(find.text('移除'), findsOneWidget);
    });
  });
}
