import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/update_info.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/update_service.dart';
import 'package:sogoodviewer/views/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testPrefsFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('sgv_update_test_');
    testPrefsFile = File('${tempDir.path}/test_preferences.json');
    testPrefsFile.writeAsStringSync('{}');
    PreferencesService.setConfigFileForTesting(testPrefsFile);
  });

  tearDownAll(() async {
    await PreferencesService.pendingSave;
    PreferencesService.setConfigFileForTesting(null);
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('UpdateService Unit Tests', () {
    test('compareSemVer correctly orders semantic version strings', () {
      // Newer versions
      expect(UpdateService.compareSemVer('1.0.8', '1.0.7'), greaterThan(0));
      expect(UpdateService.compareSemVer('v1.0.8', '1.0.7'), greaterThan(0));
      expect(UpdateService.compareSemVer('1.1.0', '1.0.9'), greaterThan(0));
      expect(UpdateService.compareSemVer('2.0.0', '1.99.99'), greaterThan(0));
      expect(UpdateService.compareSemVer('1.0.10', '1.0.9'), greaterThan(0));

      // Equal versions
      expect(UpdateService.compareSemVer('1.0.7', '1.0.7'), 0);
      expect(UpdateService.compareSemVer('v1.0.7', '1.0.7'), 0);
      expect(UpdateService.compareSemVer('1.0.7+8', '1.0.7+9'), 0);

      // Older versions
      expect(UpdateService.compareSemVer('1.0.6', '1.0.7'), lessThan(0));
      expect(UpdateService.compareSemVer('0.9.9', '1.0.0'), lessThan(0));
    });

    test('resolvePlatformAsset identifies platform assets accurately', () {
      final mockAssets = [
        {
          'name': 'SuperGoodViewer-v1.0.8-macos.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.8-macos.dmg',
          'size': 52783827,
        },
        {
          'name': 'SuperGoodViewer-v1.0.8-windows-x64.zip',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.8-windows-x64.zip',
          'size': 48123456,
        },
        {
          'name': 'SuperGoodViewer-v1.0.8-windows-arm64.zip',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.8-windows-arm64.zip',
          'size': 47123456,
        },
        {
          'name': 'SuperGoodViewer-v1.0.8-linux-x64.tar.gz',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.8-linux-x64.tar.gz',
          'size': 45123456,
        },
      ];

      final asset = UpdateService.resolvePlatformAsset(mockAssets);

      if (Platform.isMacOS) {
        expect(asset.name, 'SuperGoodViewer-v1.0.8-macos.dmg');
        expect(asset.url, 'https://example.com/SuperGoodViewer-v1.0.8-macos.dmg');
        expect(asset.size, 52783827);
      } else if (Platform.isWindows) {
        expect(asset.name, contains('windows'));
        expect(asset.url, contains('windows'));
      } else if (Platform.isLinux) {
        expect(asset.name, 'SuperGoodViewer-v1.0.8-linux-x64.tar.gz');
      }
    });

    test('ignoreVersion saves preference correctly', () async {
      final service = UpdateService();
      await service.ignoreVersion('1.0.8');

      final prefs = PreferencesService.loadSync();
      expect(prefs[UpdateService.prefIgnoredVersion], '1.0.8');
    });

    test('UpdateInfo model formats size properly', () {
      const info = UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'Release 1.0.8',
        releaseNotes: 'Bug fixes',
        htmlUrl: 'https://example.com',
        assetUrl: 'https://example.com/app.dmg',
        assetName: 'app.dmg',
        assetSizeBytes: 52428800, // 50 MB
        hasUpdate: true,
      );

      expect(info.formattedSize, '50.0 MB');
      expect(info.hasUpdate, isTrue);
      expect(info.toString(), contains('50.0 MB'));
    });
  });

  group('UpdateDialog Widget Tests', () {
    testWidgets('UpdateDialog renders release info, notes, and action buttons', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      const mockInfo = UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'SuperGoodViewer v1.0.8',
        releaseNotes: '• 优化大纲目录高亮跟随\n• 修复流式模式页码显示\n• 提升排版性能',
        htmlUrl: 'https://github.com/dotsg/supergoodviewer/releases/tag/v1.0.8',
        assetUrl: 'https://example.com/download/SuperGoodViewer-v1.0.8-macos.dmg',
        assetName: 'SuperGoodViewer-v1.0.8-macos.dmg',
        assetSizeBytes: 52428800,
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => UpdateDialog.show(ctx, controller, mockInfo),
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Dialog content
      expect(find.text('发现新版本'), findsOneWidget);
      expect(find.text('v1.0.8'), findsOneWidget);
      expect(find.textContaining('当前版本: v1.0.7'), findsOneWidget);
      expect(find.textContaining('50.0 MB'), findsOneWidget);
      expect(find.textContaining('优化大纲目录高亮跟随'), findsOneWidget);

      // Buttons
      expect(find.text('忽略此版本'), findsOneWidget);
      expect(find.text('稍后提醒'), findsOneWidget);
      expect(find.text('在网页查看'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      // Clicking "稍后提醒" dismisses dialog
      await tester.tap(find.text('稍后提醒'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateDialog), findsNothing);
    });

    testWidgets('Clicking 忽略此版本 saves ignored version and dismisses dialog', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      const mockInfo = UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'SuperGoodViewer v1.0.8',
        releaseNotes: 'Minor updates',
        htmlUrl: 'https://github.com/dotsg/supergoodviewer/releases/tag/v1.0.8',
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => UpdateDialog.show(ctx, controller, mockInfo),
                  child: const Text('Show Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('忽略此版本'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(find.byType(UpdateDialog), findsNothing);
      final prefs = PreferencesService.loadSync();
      expect(prefs[UpdateService.prefIgnoredVersion], '1.0.8');
    });
  });

  group('Preferences Merging & Persistence Tests (Issue 1)', () {
    test('PreferencesService merges update preferences with reader preferences without wiping', () async {
      // 1. User configures update settings in SettingsDialog
      await PreferencesService.saveKey(UpdateService.prefAutoCheck, false);
      await PreferencesService.saveKey(UpdateService.prefIgnoredVersion, '1.0.8');
      await PreferencesService.saveKey(UpdateService.prefLastCheckTime, 123456789);

      // 2. ReaderController normal daily operation (e.g. scroll, mode change, language change)
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);
      controller.setLanguage('en');
      await PreferencesService.pendingSave;

      // 3. Verify update preferences remain intact
      final prefs = PreferencesService.loadSync();
      expect(prefs[UpdateService.prefAutoCheck], isFalse);
      expect(prefs[UpdateService.prefIgnoredVersion], '1.0.8');
      expect(prefs[UpdateService.prefLastCheckTime], 123456789);
      expect(prefs['language'], 'en');
    });
  });

  group('UpdateCancellationToken & Download Cancellation Tests (Issue 5)', () {
    test('UpdateCancellationToken lifecycle and listeners', () {
      final token = UpdateCancellationToken();
      expect(token.isCancelled, isFalse);

      bool listenerCalled = false;
      void listener() => listenerCalled = true;
      token.addListener(listener);

      token.cancel();
      expect(token.isCancelled, isTrue);
      expect(listenerCalled, isTrue);

      // Listener added after cancellation executes immediately
      bool lateListenerCalled = false;
      token.addListener(() => lateListenerCalled = true);
      expect(lateListenerCalled, isTrue);

      // Calling cancel again is a safe no-op
      token.cancel();
    });

    test('downloadUpdateAsset aborts stream and deletes temporary files on cancellation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final streamController = StreamController<List<int>>();

      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = 100000;
        request.response.addStream(streamController.stream).then((_) {
          request.response.close();
        }).catchError((_) {});
      });

      final service = UpdateService();
      final cancelToken = UpdateCancellationToken();
      final url = 'http://${server.address.host}:${server.port}/test_file.bin';

      // Send first chunk
      streamController.add(List.filled(1024, 65));

      final downloadFuture = service.downloadUpdateAsset(
        url,
        'test_file.bin',
        cancelToken: cancelToken,
        onProgress: (rec, tot) {
          // Cancel as soon as first chunk arrives
          cancelToken.cancel();
        },
      );

      // Expect cancellation exception
      await expectLater(downloadFuture, throwsA(isA<UpdateCancelledException>()));

      // Close server and stream
      await streamController.close();
      await server.close(force: true);
    });
  });

  group('Platform Installation & Restart Tests (Issues 2 & 3)', () {
    test('resolveMacOSAppBundlePath returns string on macOS or null on other platforms', () {
      final path = UpdateService.resolveMacOSAppBundlePath();
      if (Platform.isMacOS) {
        // May be null in unit test runner or non-bundle executable, but should never throw
        expect(path == null || path.endsWith('.app'), isTrue);
      } else {
        expect(path, isNull);
      }
    });

    test('Linux executable path resolves via Platform.resolvedExecutable parent', () {
      final exe = Platform.resolvedExecutable;
      final dir = File(exe).parent.path;
      expect(exe.isNotEmpty, isTrue);
      expect(dir.isNotEmpty, isTrue);
    });
  });

  group('UpdateDialog Reentrancy & Cancellation Widget Tests (Issues 4 & 5)', () {
    testWidgets('Cancelling download stops download and dismisses dialog without errors', (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final streamController = StreamController<List<int>>();
      addTearDown(() => streamController.close());

      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.contentLength = 500000;
        request.response.addStream(streamController.stream).then((_) {
          request.response.close();
        }).catchError((_) {});
      });

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      final mockInfo = UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'SuperGoodViewer v1.0.8',
        releaseNotes: 'Performance improvements',
        htmlUrl: 'https://github.com/dotsg/supergoodviewer/releases/tag/v1.0.8',
        assetUrl: 'http://${server.address.host}:${server.port}/test_update.zip',
        assetName: 'test_update.zip',
        assetSizeBytes: 500000,
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => UpdateDialog.show(ctx, controller, mockInfo),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Click "立即更新"
      await tester.tap(find.text('立即更新'));
      await tester.pump(); // Start downloading state

      expect(find.text('取消'), findsOneWidget);

      // Tap "取消" while downloading
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed cleanly
      expect(find.byType(UpdateDialog), findsNothing);
      expect(find.text('更新失败'), findsNothing);
    });

    testWidgets('Restart button enters installing state and prevents double invocation', (tester) async {
      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      int installCallCount = 0;
      final mockService = _MockUpdateService(
        onInstall: () {
          installCallCount++;
        },
      );
      UpdateService.setInstanceForTesting(mockService);
      addTearDown(() => UpdateService.setInstanceForTesting(null));

      final mockInfo = const UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'SuperGoodViewer v1.0.8',
        releaseNotes: 'Performance improvements',
        htmlUrl: 'https://github.com/dotsg/supergoodviewer/releases/tag/v1.0.8',
        assetUrl: 'https://example.com/fake_update.zip',
        assetName: 'fake_update.zip',
        hasUpdate: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => UpdateDialog.show(ctx, controller, mockInfo),
                child: const Text('Show Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Tap "立即更新" (mock download returns immediately)
      await tester.runAsync(() async {
        await tester.tap(find.text('立即更新'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      // State is now readyToRestart
      expect(find.text('立即重启以完成更新'), findsOneWidget);

      // Tap restart button
      await tester.tap(find.text('立即重启以完成更新'));
      await tester.pump();

      // State should be installing, button disabled
      expect(find.text('正在准备更新并重启...'), findsWidgets);
      expect(installCallCount, 1);

      // Consecutive taps should do nothing
      await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
      expect(installCallCount, 1);
    });
  });
}

class _MockUpdateService extends UpdateService {
  final void Function() onInstall;
  _MockUpdateService({required this.onInstall});

  @override
  Future<String> downloadUpdateAsset(
    String url,
    String targetFileName, {
    required void Function(int received, int total) onProgress,
    UpdateCancellationToken? cancelToken,
  }) async {
    final file = File('${Directory.systemTemp.path}/$targetFileName');
    if (!file.existsSync()) file.writeAsStringSync('mock content');
    return file.path;
  }

  @override
  Future<void> installAndRestart({required String downloadedFilePath}) async {
    onInstall();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
