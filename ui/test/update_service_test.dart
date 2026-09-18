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

    test('downloadUpdateAsset throws UpdateCancelledException when token cancelled beforehand', () async {
      final service = UpdateService();
      final cancelToken = UpdateCancellationToken()..cancel();
      expect(
        service.downloadUpdateAsset(
          'https://example.com/test.bin',
          'test.bin',
          cancelToken: cancelToken,
          onProgress: (_, _) {},
        ),
        throwsA(isA<UpdateCancelledException>()),
      );
    });

    test('downloadUpdateAsset cancels cleanly before response headers arrive', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final requestReceived = Completer<void>();
        final allowHeaders = Completer<void>();

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.idleTimeout = Duration.zero;
        addTearDown(() => server.close(force: true));

        server.listen((HttpRequest req) async {
          requestReceived.complete();
          try {
            await allowHeaders.future;
            req.response.statusCode = 200;
            req.response.contentLength = 1000;
            req.response.add(List.filled(1000, 42));
            await req.response.close();
          } catch (_) {}
        });

        final service = UpdateService();
        final cancelToken = UpdateCancellationToken();

        final downloadFuture = service.downloadUpdateAsset(
          'http://127.0.0.1:${server.port}/test_file.bin',
          'test_file.bin',
          cancelToken: cancelToken,
          onProgress: (_, _) {},
        );

        await requestReceived.future;
        // Cancel while client is awaiting response headers
        cancelToken.cancel();
        if (!allowHeaders.isCompleted) {
          allowHeaders.complete();
        }

        await expectLater(
          downloadFuture,
          throwsA(isA<UpdateCancelledException>()),
        );
      }, _RealHttpOverrides());
    });

    test('downloadUpdateAsset cancels cleanly while stream is in progress', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.idleTimeout = Duration.zero;
        addTearDown(() => server.close(force: true));

        server.listen((HttpRequest req) async {
          try {
            req.response.statusCode = 200;
            req.response.contentLength = 100000;
            for (int i = 0; i < 20; i++) {
              req.response.add(List.filled(5000, 42));
              await req.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            await req.response.close();
          } catch (_) {}
        });

        final service = UpdateService();
        final cancelToken = UpdateCancellationToken();

        final downloadFuture = service.downloadUpdateAsset(
          'http://127.0.0.1:${server.port}/test_file_stream.bin',
          'test_file_stream.bin',
          cancelToken: cancelToken,
          onProgress: (received, total) {
            if (received > 0 && !cancelToken.isCancelled) {
              cancelToken.cancel();
            }
          },
        );

        await expectLater(
          downloadFuture,
          throwsA(isA<UpdateCancelledException>()),
        );
      }, _RealHttpOverrides());
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

    test('buildMacOSUpdateScript cleans up partial directory and restores backup on failed staged move', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('macos_script_test_rollback_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final targetAppPath = '${testDir.path}/SuperGoodViewer.app';
      final stagedAppPath = '${testDir.path}/staging/SuperGoodViewer.app';
      final stagingDirPath = '${testDir.path}/staging';

      // 1. Initial state: target app exists with version 1.0.7
      final targetDir = Directory(targetAppPath)..createSync(recursive: true);
      File('${targetDir.path}/version.txt').writeAsStringSync('1.0.7');

      // 2. Staged app exists with version 1.0.8
      final stagedDir = Directory(stagedAppPath)..createSync(recursive: true);
      File('${stagedDir.path}/version.txt').writeAsStringSync('1.0.8');

      // Create dummy bin directory with mock `open` and mock `mv`
      final binDir = Directory('${testDir.path}/bin')..createSync();
      final openMock = File('${binDir.path}/open');
      openMock.writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', openMock.path]);

      // Mock `mv`: simulates partial failure across filesystems when moving stagedAppPath to targetAppPath
      final mvMock = File('${binDir.path}/mv');
      mvMock.writeAsStringSync('''#!/bin/sh
if [ "\$1" = "$stagedAppPath" ]; then
  mkdir -p "$targetAppPath/corrupted_part"
  exit 1
fi
exec /bin/mv "\$@"
''');
      Process.runSync('chmod', ['+x', mvMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildMacOSUpdateScript(
        currentPid: dummyPid,
        targetAppPath: targetAppPath,
        stagedAppPath: stagedAppPath,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        },
      );

      expect(result.exitCode, isNot(0));

      // Verify targetAppPath was restored to original 1.0.7
      expect(Directory(targetAppPath).existsSync(), isTrue);
      expect(File('$targetAppPath/version.txt').readAsStringSync(), '1.0.7');

      // Verify partial corrupted files are cleaned up and NOT containing backup nested inside
      expect(Directory('$targetAppPath/corrupted_part').existsSync(), isFalse);

      // Verify stagingDir was cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildMacOSUpdateScript preserves original app and aborts when initial backup fails', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('macos_script_test_backup_fail_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final targetAppPath = '${testDir.path}/SuperGoodViewer.app';
      final stagedAppPath = '${testDir.path}/staging/SuperGoodViewer.app';
      final stagingDirPath = '${testDir.path}/staging';

      // 1. Target app exists with version 1.0.7
      final targetDir = Directory(targetAppPath)..createSync(recursive: true);
      File('${targetDir.path}/version.txt').writeAsStringSync('1.0.7');

      // 2. Staged app exists with version 1.0.8
      final stagedDir = Directory(stagedAppPath)..createSync(recursive: true);
      File('${stagedDir.path}/version.txt').writeAsStringSync('1.0.8');

      // Create dummy bin directory with mock `open` and mock `mv`
      final binDir = Directory('${testDir.path}/bin')..createSync();
      final openLog = File('${testDir.path}/open.log');
      final openMock = File('${binDir.path}/open');
      openMock.writeAsStringSync('''#!/bin/sh
echo "\$@" >> "${openLog.path}"
exit 0
''');
      Process.runSync('chmod', ['+x', openMock.path]);

      // Mock `mv`: fails when attempting to backup targetAppPath
      final mvMock = File('${binDir.path}/mv');
      mvMock.writeAsStringSync('''#!/bin/sh
if [ "\$1" = "$targetAppPath" ]; then
  exit 1
fi
exec /bin/mv "\$@"
''');
      Process.runSync('chmod', ['+x', mvMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildMacOSUpdateScript(
        currentPid: dummyPid,
        targetAppPath: targetAppPath,
        stagedAppPath: stagedAppPath,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        },
      );

      // Script should exit with non-zero failure code
      expect(result.exitCode, isNot(0));

      // Original targetAppPath MUST be preserved and untouched!
      expect(Directory(targetAppPath).existsSync(), isTrue);
      expect(File('$targetAppPath/version.txt').readAsStringSync(), '1.0.7');

      // Staging directory should be cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);

      // Original app should be relaunched
      expect(openLog.existsSync(), isTrue);
      expect(openLog.readAsStringSync(), contains(targetAppPath));
    });

    test('buildMacOSUpdateScript succeeds and moves staged app when move is successful', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('macos_script_test_success_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final targetAppPath = '${testDir.path}/SuperGoodViewer.app';
      final stagedAppPath = '${testDir.path}/staging/SuperGoodViewer.app';
      final stagingDirPath = '${testDir.path}/staging';

      // 1. Initial state: target app exists with version 1.0.7
      final targetDir = Directory(targetAppPath)..createSync(recursive: true);
      File('${targetDir.path}/version.txt').writeAsStringSync('1.0.7');

      // 2. Staged app exists with version 1.0.8
      final stagedDir = Directory(stagedAppPath)..createSync(recursive: true);
      File('${stagedDir.path}/version.txt').writeAsStringSync('1.0.8');

      // Create dummy bin directory with mock `open`
      final binDir = Directory('${testDir.path}/bin')..createSync();
      final openMock = File('${binDir.path}/open');
      openMock.writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', openMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildMacOSUpdateScript(
        currentPid: dummyPid,
        targetAppPath: targetAppPath,
        stagedAppPath: stagedAppPath,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        },
      );

      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      // Verify targetAppPath now contains 1.0.8
      expect(Directory(targetAppPath).existsSync(), isTrue);
      expect(File('$targetAppPath/version.txt').readAsStringSync(), '1.0.8');

      // Verify stagingDir was cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript updates app and launches supergoodviewer', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_script_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo "old version"\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "new version"\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: oldExe.path,
        appDir: appDir,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run('/bin/sh', ['-c', script]);
      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      expect(File('$appDir/supergoodviewer').existsSync(), isTrue);
      expect(File('$appDir/supergoodviewer').readAsStringSync(), 'echo "new version"\n');
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript migrates legacy sogoodviewer to supergoodviewer and removes old binary', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_legacy_migration_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      // Legacy installation has 'sogoodviewer' binary
      final legacyExe = File('$appDir/sogoodviewer');
      legacyExe.writeAsStringSync('echo "legacy sogoodviewer"\n');
      Process.runSync('chmod', ['+x', legacyExe.path]);

      // New staged package has 'supergoodviewer'
      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "modern supergoodviewer"\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: legacyExe.path,
        appDir: appDir,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run('/bin/sh', ['-c', script]);
      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      // New binary installed
      expect(File('$appDir/supergoodviewer').existsSync(), isTrue);
      expect(File('$appDir/supergoodviewer').readAsStringSync(), 'echo "modern supergoodviewer"\n');
      // Legacy binary cleaned up
      expect(File('$appDir/sogoodviewer').existsSync(), isFalse);
      // Staging directory cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });
  });

  group('UpdateDialog Reentrancy & Cancellation Widget Tests (Issues 4 & 5)', () {
    testWidgets('Cancelling download stops download and dismisses dialog without errors', (tester) async {
      final downloadCompleter = Completer<void>();
      bool cancellationNotified = false;

      final mockService = _MockUpdateService(
        onDownload: (token) {
          token?.addListener(() {
            cancellationNotified = true;
            if (!downloadCompleter.isCompleted) {
              downloadCompleter.completeError(UpdateCancelledException());
            }
          });
        },
        downloadFuture: downloadCompleter.future,
      );
      UpdateService.setInstanceForTesting(mockService);
      addTearDown(() => UpdateService.setInstanceForTesting(null));

      final controller = ReaderController(autoRestorePreferences: false);
      addTearDown(controller.dispose);

      const mockInfo = UpdateInfo(
        currentVersion: '1.0.7',
        latestVersion: '1.0.8',
        title: 'SuperGoodViewer v1.0.8',
        releaseNotes: 'Performance improvements',
        htmlUrl: 'https://github.com/dotsg/supergoodviewer/releases/tag/v1.0.8',
        assetUrl: 'https://example.com/test_update.zip',
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
      expect(cancellationNotified, isTrue);
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

      const mockInfo = UpdateInfo(
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
  final void Function()? onInstall;
  final void Function(UpdateCancellationToken? token)? onDownload;
  final Future<void>? downloadFuture;

  _MockUpdateService({
    this.onInstall,
    this.onDownload,
    this.downloadFuture,
  });

  @override
  Future<String> downloadUpdateAsset(
    String url,
    String targetFileName, {
    required void Function(int received, int total) onProgress,
    UpdateCancellationToken? cancelToken,
  }) async {
    onDownload?.call(cancelToken);
    if (downloadFuture != null) {
      await downloadFuture;
    }
    final file = File('${Directory.systemTemp.path}/$targetFileName');
    if (!file.existsSync()) file.writeAsStringSync('mock content');
    return file.path;
  }

  @override
  Future<void> installAndRestart({required String downloadedFilePath}) async {
    onInstall?.call();
  }
}

class _RealHttpOverrides extends HttpOverrides {}
