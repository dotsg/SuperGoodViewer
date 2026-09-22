import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/update_info.dart';
import 'package:sogoodviewer/services/preferences_service.dart';
import 'package:sogoodviewer/services/update_service.dart';
import 'package:sogoodviewer/views/update_dialog.dart';

int _nextTestInactivePid = 8000000;

/// Finds a PID that is verified to NOT belong to any running process on the system.
int findInactivePid() {
  for (int attempt = 0; attempt < 200000; attempt++) {
    if (_nextTestInactivePid > 9900000) {
      _nextTestInactivePid = 8000000;
    }
    final candidate = _nextTestInactivePid++;
    if (!UpdateService.isUpdaterProcessAlive(candidate)) {
      try {
        final res = Process.runSync('kill', ['-0', candidate.toString()]);
        if (res.exitCode != 0) {
          return candidate;
        }
      } catch (_) {
        return candidate;
      }
    }
  }
  throw StateError('Unable to find an inactive PID after scanning range 8000000-9900000');
}

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

    test('resolvePlatformAsset differentiates macOS architectures (arm64, x64, universal)', () {
      final standaloneAssets = [
        {
          'name': 'SuperGoodViewer-v1.0.9-macos-arm64.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.9-macos-arm64.dmg',
          'size': 37000000,
        },
        {
          'name': 'SuperGoodViewer-v1.0.9-macos-x64.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.9-macos-x64.dmg',
          'size': 40000000,
        },
      ];

      // Apple Silicon Mac should resolve arm64 asset
      final armAsset = UpdateService.resolvePlatformAsset(
        standaloneAssets,
        targetIsMacOS: true,
        targetIsArm64: true,
      );
      expect(armAsset.name, 'SuperGoodViewer-v1.0.9-macos-arm64.dmg');

      // Intel Mac should resolve x64 asset
      final intelAsset = UpdateService.resolvePlatformAsset(
        standaloneAssets,
        targetIsMacOS: true,
        targetIsArm64: false,
      );
      expect(intelAsset.name, 'SuperGoodViewer-v1.0.9-macos-x64.dmg');

      // Intel Mac should also resolve x86_64 asset variant
      final x86Assets = [
        {
          'name': 'SuperGoodViewer-v1.0.9-macos-x86_64.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.9-macos-x86_64.dmg',
          'size': 40000000,
        },
      ];
      final intelX86Asset = UpdateService.resolvePlatformAsset(
        x86Assets,
        targetIsMacOS: true,
        targetIsArm64: false,
      );
      expect(intelX86Asset.name, 'SuperGoodViewer-v1.0.9-macos-x86_64.dmg');

      // Apple Silicon Mac can fallback to x86_64 when only Intel is available (via Rosetta 2)
      final armOnX64Only = UpdateService.resolvePlatformAsset(
        x86Assets,
        targetIsMacOS: true,
        targetIsArm64: true,
      );
      expect(armOnX64Only.name, 'SuperGoodViewer-v1.0.9-macos-x86_64.dmg');

      // Universal package should resolve for both architectures
      final universalAssets = [
        {
          'name': 'SuperGoodViewer-v1.0.8-macos.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.8-macos.dmg',
          'size': 52000000,
        },
      ];
      final armUniversal = UpdateService.resolvePlatformAsset(
        universalAssets,
        targetIsMacOS: true,
        targetIsArm64: true,
      );
      expect(armUniversal.name, 'SuperGoodViewer-v1.0.8-macos.dmg');

      final intelUniversal = UpdateService.resolvePlatformAsset(
        universalAssets,
        targetIsMacOS: true,
        targetIsArm64: false,
      );
      expect(intelUniversal.name, 'SuperGoodViewer-v1.0.8-macos.dmg');

      // If only arm64 is available, Intel Mac must NEVER download it (prevent breaking installation)
      final armOnlyAssets = [
        {
          'name': 'SuperGoodViewer-v1.0.9-macos-arm64.dmg',
          'browser_download_url': 'https://example.com/SuperGoodViewer-v1.0.9-macos-arm64.dmg',
          'size': 37000000,
        },
      ];
      final intelWithArmOnly = UpdateService.resolvePlatformAsset(
        armOnlyAssets,
        targetIsMacOS: true,
        targetIsArm64: false,
      );
      expect(intelWithArmOnly.name, isNull);
    });

    test('readMachOArchitectures parses thin and fat Mach-O headers accurately', () {
      final tempDir = Directory.systemTemp.createTempSync('macho_test_');
      try {
        // Thin arm64 (MH_MAGIC_64 little endian: 0xfeedfacf, CPU_TYPE_ARM64: 0x0100000c)
        final arm64File = File(p.join(tempDir.path, 'thin_arm64'));
        arm64File.writeAsBytesSync([
          0xcf, 0xfa, 0xed, 0xfe, // magic
          0x0c, 0x00, 0x00, 0x01, // cputype arm64
        ]);
        expect(UpdateService.readMachOArchitectures(arm64File), {'arm64'});

        // Thin x86_64 (MH_MAGIC_64 little endian: 0xfeedfacf, CPU_TYPE_X86_64: 0x01000007)
        final x64File = File(p.join(tempDir.path, 'thin_x64'));
        x64File.writeAsBytesSync([
          0xcf, 0xfa, 0xed, 0xfe, // magic
          0x07, 0x00, 0x00, 0x01, // cputype x86_64
        ]);
        expect(UpdateService.readMachOArchitectures(x64File), {'x86_64'});

        // Fat binary (FAT_MAGIC big endian: 0xcafebabe, 2 slices: x86_64 and arm64)
        final fatFile = File(p.join(tempDir.path, 'fat_universal'));
        final fatBytes = <int>[
          0xca, 0xfe, 0xba, 0xbe, // FAT_MAGIC
          0x00, 0x00, 0x00, 0x02, // nfat_arch = 2
          // slice 1: x86_64 (20 bytes)
          0x01, 0x00, 0x00, 0x07, // cputype
          0x00, 0x00, 0x00, 0x03, // cpusubtype
          0x00, 0x00, 0x10, 0x00, // offset
          0x00, 0x00, 0x40, 0x00, // size
          0x00, 0x00, 0x00, 0x0e, // align
          // slice 2: arm64 (20 bytes)
          0x01, 0x00, 0x00, 0x0c, // cputype
          0x00, 0x00, 0x00, 0x00, // cpusubtype
          0x00, 0x00, 0x50, 0x00, // offset
          0x00, 0x00, 0x40, 0x00, // size
          0x00, 0x00, 0x00, 0x0e, // align
        ];
        fatFile.writeAsBytesSync(fatBytes);
        expect(UpdateService.readMachOArchitectures(fatFile), {'x86_64', 'arm64'});

        // Non-existent or invalid file returns empty set
        final invalidFile = File(p.join(tempDir.path, 'invalid'));
        invalidFile.writeAsBytesSync([0x00, 0x01, 0x02]);
        expect(UpdateService.readMachOArchitectures(invalidFile), isEmpty);
        expect(UpdateService.readMachOArchitectures(File('nonexistent')), isEmpty);

        // IncompatibleArchitectureException message
        const ex = IncompatibleArchitectureException('Test error');
        expect(ex.toString(), contains('IncompatibleArchitectureException: Test error'));
      } finally {
        tempDir.deleteSync(recursive: true);
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
        server.idleTimeout = const Duration(seconds: 5);

        try {
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
        } finally {
          await server.close(force: true);
        }
      }, _RealHttpOverrides());
    });

    test('downloadUpdateAsset cancels cleanly while stream is in progress', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.idleTimeout = const Duration(seconds: 5);

        try {
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
        } finally {
          await server.close(force: true);
        }
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

    test('buildLinuxUpdateScript updates app, preserves non-bundle files, copies dotfiles, and launches supergoodviewer', () async {
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

      // User file that does not belong to bundle
      final userNote = File('$appDir/notes.txt');
      userNote.writeAsStringSync('user notes content');

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "new version"\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      // Dotfile in staging bundle
      final dotFile = File('$stagingDirPath/.release_metadata');
      dotFile.writeAsStringSync('metadata v1.0.8');

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
      // Verify non-bundle files were NOT deleted
      expect(File('$appDir/notes.txt').existsSync(), isTrue);
      expect(File('$appDir/notes.txt').readAsStringSync(), 'user notes content');
      // Verify dotfiles were transferred
      expect(File('$appDir/.release_metadata').existsSync(), isTrue);
      expect(File('$appDir/.release_metadata').readAsStringSync(), 'metadata v1.0.8');
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript migrates legacy sogoodviewer to supergoodviewer, removes old binary, and preserves user files', () async {
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

      final userConfig = File('$appDir/custom_config.json');
      userConfig.writeAsStringSync('{"key": "val"}');

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
      // User non-bundle file preserved
      expect(File('$appDir/custom_config.json').existsSync(), isTrue);
      expect(File('$appDir/custom_config.json').readAsStringSync(), '{"key": "val"}');
      // Staging directory cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript aborts without mutating appDir when payload is missing supergoodviewer', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_missing_supergoodviewer_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final legacyExe = File('$appDir/sogoodviewer');
      legacyExe.writeAsStringSync('echo "legacy sogoodviewer"\n');
      Process.runSync('chmod', ['+x', legacyExe.path]);

      // Payload has files, but NOT supergoodviewer (corrupt or misnamed payload)
      File('$stagingDirPath/corrupt_binary').writeAsStringSync('echo "bad"\n');

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
      expect(result.exitCode, isNot(0));

      // App bundle and legacy executable MUST be preserved completely!
      expect(File(legacyExe.path).existsSync(), isTrue);
      expect(File(legacyExe.path).readAsStringSync(), 'echo "legacy sogoodviewer"\n');
      // Staging directory must be cleaned up to prevent disk leak
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript preserves legacy binary and appDir if payload copy fails', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_copy_fail_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final legacyExe = File('$appDir/sogoodviewer');
      legacyExe.writeAsStringSync('echo "legacy sogoodviewer"\n');
      Process.runSync('chmod', ['+x', legacyExe.path]);

      // Stage new binary
      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "modern supergoodviewer"\n');

      // Mock `cp` to simulate an error (e.g. ENOSPC or permission failure) without depending on root/chmod
      final cpMock = File('${binDir.path}/cp');
      cpMock.writeAsStringSync('''#!/bin/sh
exit 1
''');
      Process.runSync('chmod', ['+x', cpMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: legacyExe.path,
        appDir: appDir,
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

      // Legacy executable and appDir MUST be preserved!
      expect(File(legacyExe.path).existsSync(), isTrue);
      expect(File(legacyExe.path).readAsStringSync(), 'echo "legacy sogoodviewer"\n');
      // Staging directory must be cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript succeeds when parent directory of appDir is read-only', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_ro_parent_test_');
      final parentDir = Directory('${testDir.path}/parent')..createSync(recursive: true);
      final appDir = '${parentDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      addTearDown(() {
        try {
          Process.runSync('chmod', ['755', parentDir.path]);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo "old version"\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "new version"\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      // Make parent directory read-only to simulate /opt owned by root
      Process.runSync('chmod', ['555', parentDir.path]);

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

    test('buildLinuxUpdateScript rolls back and preserves appDir when verification fails', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_verify_fail_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final legacyExe = File('$appDir/sogoodviewer');
      legacyExe.writeAsStringSync('echo "legacy sogoodviewer"\n');
      Process.runSync('chmod', ['+x', legacyExe.path]);

      // Staged binary is not executable
      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "broken supergoodviewer"\n');
      Process.runSync('chmod', ['-x', newExe.path]);

      // Mock `chmod` to fail so that `chmod +x` cannot make the binary executable
      final chmodMock = File('${binDir.path}/chmod');
      chmodMock.writeAsStringSync('''#!/bin/sh
exit 1
''');
      Process.runSync('chmod', ['+x', chmodMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: legacyExe.path,
        appDir: appDir,
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

      // Should have rolled back: legacy executable restored!
      expect(File(legacyExe.path).existsSync(), isTrue);
      expect(File(legacyExe.path).readAsStringSync(), 'echo "legacy sogoodviewer"\n');
      expect(File('$appDir/supergoodviewer').existsSync(), isFalse);
      // Staging directory must be cleaned up
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript preserves dangling symlinks and installs payload symlinks and writes update.log', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_symlink_test_');
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

      // User dangling symlink in appDir (must NOT be deleted or skipped)
      Process.runSync('ln', ['-s', 'target_does_not_exist', '$appDir/user_dangling_link']);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "new version"\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      // Payload dangling symlink (must be installed into appDir)
      Process.runSync('ln', ['-s', 'so_lib_missing_until_run', '$stagingDirPath/libcompat.so.1']);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final stateDir = '${testDir.path}/state';
      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: oldExe.path,
        appDir: appDir,
        stagingDirPath: stagingDirPath,
      );

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'XDG_STATE_HOME': stateDir,
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
      );
      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      expect(File('$appDir/supergoodviewer').existsSync(), isTrue);
      expect(Link('$appDir/user_dangling_link').existsSync(), isTrue);
      expect(Link('$appDir/libcompat.so.1').existsSync(), isTrue);
      expect(File('$stateDir/supergoodviewer/supergoodviewer_update.log').existsSync(), isTrue);
      expect(File('$appDir/.sgv_manifest').existsSync(), isTrue);
      expect(File('$appDir/.sgv_manifest').readAsStringSync(), contains('libcompat.so.1'));
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript prunes obsolete bundle files based on .sgv_manifest even with spaces in filenames', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_manifest_prune_test_');
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
      oldExe.writeAsStringSync('echo "v1.0.8"\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      // Obsolete bundle files from v1.0.8 that are dropped in v1.0.9 (including filename with spaces)
      final obsoleteFile = File('$appDir/deprecated_helper');
      obsoleteFile.writeAsStringSync('old helper binary');
      final obsoleteDesktop = File('$appDir/SuperGood Viewer.desktop');
      obsoleteDesktop.writeAsStringSync('old desktop entry');

      // User note that is NOT in manifest
      final userNote = File('$appDir/my_notes.txt');
      userNote.writeAsStringSync('important personal note');

      // Manifest of v1.0.8 listing bundle items
      File('$appDir/.sgv_manifest').writeAsStringSync('supergoodviewer\ndeprecated_helper\nSuperGood Viewer.desktop\n');

      // Staging payload for v1.0.9 (no longer contains deprecated_helper or desktop entry)
      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "v1.0.9"\n');
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

      expect(File('$appDir/supergoodviewer').readAsStringSync(), 'echo "v1.0.9"\n');
      // Deprecated helper and desktop entry must be pruned!
      expect(File('$appDir/deprecated_helper').existsSync(), isFalse);
      expect(File('$appDir/SuperGood Viewer.desktop').existsSync(), isFalse);
      // User note must be preserved!
      expect(File('$appDir/my_notes.txt').existsSync(), isTrue);
      expect(File('$appDir/my_notes.txt').readAsStringSync(), 'important personal note');
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript aborts cleanly without mutating appDir when df detects insufficient disk space', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_df_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo "original"\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo "new version"\n');

      // Mock `df` to report only 1 KB available
      final dfMock = File('${binDir.path}/df');
      dfMock.writeAsStringSync('''#!/bin/sh
echo "Filesystem 1024-blocks Used Available Capacity Mounted"
echo "/dev/mock 100000 99999 1 99% /"
''');
      Process.runSync('chmod', ['+x', dfMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: oldExe.path,
        appDir: appDir,
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
      expect(File(oldExe.path).readAsStringSync(), 'echo "original"\n');
      expect(Directory(stagingDirPath).existsSync(), isFalse);
    });

    test('UpdateService.cleanupStaleUpdateArtifacts sweeps dead directories, protects live updater PID, and recovers journal without nesting', () async {
      final testDir = Directory.systemTemp.createTempSync('linux_cleanup_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      File('${appDir.path}/dummy_exe').writeAsStringSync('bin');

      // Simulate stale leftover directory with dead PID (99999999)
      final deadDir = Directory('${appDir.path}/.sgv_new.99999999')..createSync();
      File('${deadDir.path}/old.tmp').writeAsStringSync('stale');

      // Simulate active updater directory with live updater process matching appDir and binary name
      final dummyExe = File('${appDir.path}/supergoodviewer');
      dummyExe.writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', dummyExe.path]);
      final liveProcess = await Process.start(dummyExe.path, []);
      final livePid = liveProcess.pid;
      addTearDown(() {
        try {
          liveProcess.kill();
        } catch (_) {}
      });

      final liveDir = Directory('${appDir.path}/.sgv_backup.$livePid')..createSync();
      File('${liveDir.path}/active.tmp').writeAsStringSync('active');

      // Setup journal with a directory (data/) waiting in backup to be restored over an existing data/ directory
      Directory('${appDir.path}/data').createSync(recursive: true);
      File('${appDir.path}/data/partially_installed.txt').writeAsStringSync('partial');
      final installedListFile = File('${appDir.path}/.sgv_installed.99999998');
      installedListFile.writeAsStringSync('data/partially_installed.txt\n');

      final journalFile = File('${appDir.path}/.sgv_journal');
      final backupDir = Directory('${appDir.path}/.sgv_backup.99999998')..createSync();
      final backupDataDir = Directory('${backupDir.path}/data')..createSync();
      File('${backupDataDir.path}/original.txt').writeAsStringSync('original');
      journalFile.writeAsStringSync('PID=99999998\nBACKUP_DIR=${backupDir.path}\nINSTALLED_LIST=${installedListFile.path}\n');

      // Call cleanupStaleUpdateArtifacts targeting appDir
      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Verify journal recovered the data directory without creating nested data/data!
      expect(File('${appDir.path}/data/original.txt').existsSync(), isTrue);
      expect(File('${appDir.path}/data/original.txt').readAsStringSync(), 'original');
      expect(File('${appDir.path}/data/partially_installed.txt').existsSync(), isFalse);
      expect(Directory('${appDir.path}/data/data').existsSync(), isFalse);
      expect(journalFile.existsSync(), isFalse);
      expect(installedListFile.existsSync(), isFalse);

      // Verify dead directory was swept
      expect(deadDir.existsSync(), isFalse);

      // Verify active directory with live PID was NOT deleted!
      expect(liveDir.existsSync(), isTrue);
    });

    test('UpdateService.cleanupStaleUpdateArtifacts protects active updater journal and artifacts when PID is alive', () async {
      final testDir = Directory.systemTemp.createTempSync('linux_active_cleanup_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final dummyExe = File('${appDir.path}/supergoodviewer');
      dummyExe.writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', dummyExe.path]);
      final liveProcess = await Process.start(dummyExe.path, []);
      final livePid = liveProcess.pid;
      addTearDown(() {
        try {
          liveProcess.kill();
        } catch (_) {}
      });

      final activeBackupDir = Directory('${appDir.path}/.sgv_backup.$livePid')..createSync();
      final activeInstalledList = File('${appDir.path}/.sgv_installed.$livePid')..writeAsStringSync('dummy.txt\n');
      final journalFile = File('${appDir.path}/.sgv_journal');
      journalFile.writeAsStringSync('PID=$livePid\nBACKUP_DIR=${activeBackupDir.path}\nINSTALLED_LIST=${activeInstalledList.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Because PID is the running test process, journal and its artifacts must NOT be touched!
      expect(journalFile.existsSync(), isTrue);
      expect(activeBackupDir.existsSync(), isTrue);
      expect(activeInstalledList.existsSync(), isTrue);
    });

    test('UpdateService.cleanupStaleUpdateArtifacts cleans dangling journal when backupDir does not exist and PID is dead', () async {
      final testDir = Directory.systemTemp.createTempSync('linux_dangling_cleanup_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final journalFile = File('${appDir.path}/.sgv_journal');
      journalFile.writeAsStringSync('PID=99999998\nBACKUP_DIR=${appDir.path}/.sgv_backup.99999998\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Dangling journal should be cleaned up
      expect(journalFile.existsSync(), isFalse);
    });

    test('UpdateService.cleanupStaleUpdateArtifactsAsync executes asynchronously in an isolate', () async {
      final testDir = Directory.systemTemp.createTempSync('linux_async_cleanup_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final deadDir = Directory('${appDir.path}/.sgv_new.99999999')..createSync();
      File('${deadDir.path}/dead.tmp').writeAsStringSync('dead');

      await UpdateService.cleanupStaleUpdateArtifactsAsync(targetAppDirPath: appDir.path);

      expect(deadDir.existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript falls back to cache or tmp when state directory is read-only', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_log_fallback_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['777', '${testDir.path}/state']);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final stateDir = '${testDir.path}/state';
      final cacheDir = '${testDir.path}/cache';
      Directory(stateDir).createSync(recursive: true);
      Directory(cacheDir).createSync(recursive: true);

      // Make state directory read-only
      Process.runSync('chmod', ['555', stateDir]);

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo old\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo new\n');
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

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'XDG_STATE_HOME': stateDir,
          'XDG_CACHE_HOME': cacheDir,
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
      );
      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      // Log file should have been written to cacheDir since stateDir was read-only
      expect(File('$cacheDir/supergoodviewer/supergoodviewer_update.log').existsSync(), isTrue);
    });

    test('ui/bin/sgv protects live updater PID, recovers dead PID journal, and cleans dangling journal', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('sgv_script_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      final originalSgv = File('bin/sgv');
      originalSgv.copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      // Mock uname to return "Linux" so sgv exercises the Linux branch on any host without backdoors
      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('''#!/bin/sh
echo "Linux"
''');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      // 1. Live PID test: journal belongs to currently running supergoodviewer process
      final appDir = testDir;
      final dummyExe = File('${appDir.path}/supergoodviewer');
      dummyExe.writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', dummyExe.path]);
      final liveProcess = await Process.start(dummyExe.path, []);
      final livePid = liveProcess.pid;
      addTearDown(() {
        try {
          liveProcess.kill();
        } catch (_) {}
      });

      final liveBackupDir = Directory('${appDir.path}/.sgv_backup.$livePid')..createSync();
      File('${liveBackupDir.path}/active.txt').writeAsStringSync('active');
      final liveJournalFile = File('${appDir.path}/.sgv_journal');
      liveJournalFile.writeAsStringSync('PID=$livePid\nBACKUP_DIR=${liveBackupDir.path}\nINSTALLED_LIST=${appDir.path}/.sgv_installed.$livePid\n');

      final liveResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(liveResult.exitCode, 0);
      // Live transaction must NOT be touched
      expect(liveJournalFile.existsSync(), isTrue);
      expect(liveBackupDir.existsSync(), isTrue);

      // Clean up live transaction manually for next test
      liveJournalFile.deleteSync();
      liveBackupDir.deleteSync(recursive: true);
      liveProcess.kill();

      // 2. Dead PID test: journal belongs to dead PID 99999998
      Directory('${appDir.path}/data').createSync(recursive: true);
      File('${appDir.path}/data/installed.txt').writeAsStringSync('new');
      final deadInstalledList = File('${appDir.path}/.sgv_installed.99999998');
      deadInstalledList.writeAsStringSync('data/installed.txt\n');

      final deadBackupDir = Directory('${appDir.path}/.sgv_backup.99999998')..createSync();
      final backupDataDir = Directory('${deadBackupDir.path}/data')..createSync();
      File('${backupDataDir.path}/restored.txt').writeAsStringSync('restored');

      final deadJournalFile = File('${appDir.path}/.sgv_journal');
      deadJournalFile.writeAsStringSync('PID=99999998\nBACKUP_DIR=${deadBackupDir.path}\nINSTALLED_LIST=${deadInstalledList.path}\n');

      final deadResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(deadResult.exitCode, 0);

      // Dead transaction recovered without directory nesting
      expect(File('${appDir.path}/data/restored.txt').existsSync(), isTrue);
      expect(File('${appDir.path}/data/installed.txt').existsSync(), isFalse);
      expect(Directory('${appDir.path}/data/data').existsSync(), isFalse);
      expect(deadJournalFile.existsSync(), isFalse);
      expect(deadBackupDir.existsSync(), isFalse);
      expect(deadInstalledList.existsSync(), isFalse);

      // 3. Dangling journal test: backupDir does not exist
      final danglingInstalled = File('${appDir.path}/.sgv_installed.99999998')..writeAsStringSync('dummy\n');
      final danglingJournal = File('${appDir.path}/.sgv_journal');
      danglingJournal.writeAsStringSync('PID=99999998\nBACKUP_DIR=${appDir.path}/.sgv_backup.99999998\nINSTALLED_LIST=${danglingInstalled.path}\n');

      final danglingResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(danglingResult.exitCode, 0);
      expect(danglingJournal.existsSync(), isFalse);
      expect(danglingInstalled.existsSync(), isFalse);
    });

    test('isUpdaterProcessAlive guards against invalid PIDs (<= 1 and negatives)', () {
      expect(UpdateService.isUpdaterProcessAlive(null), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(0), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(1), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(-1), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(-99), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(99999998), isFalse);
    });

    test('buildLinuxUpdateScript recovers legacy single-line journal under dash/POSIX sh', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_legacy_journal_dash_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      // Previous interrupted legacy backup
      final backupDir = Directory('$appDir/.sgv_backup.99999998')..createSync(recursive: true);
      final backupDataDir = Directory('${backupDir.path}/data')..createSync(recursive: true);
      File('${backupDataDir.path}/old_doc.txt').writeAsStringSync('legacy content');

      // Partially installed new file in appDir
      Directory('$appDir/data').createSync(recursive: true);
      File('$appDir/data/partial_new.txt').writeAsStringSync('partial new');

      // Paired installed list from legacy update
      final legacyInstalled = File('$appDir/.sgv_installed.99999998');
      legacyInstalled.writeAsStringSync('data/partial_new.txt\n');

      // Legacy single-line journal format
      final journalFile = File('$appDir/.sgv_journal');
      journalFile.writeAsStringSync('${backupDir.path}\n');

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo old\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo new\n');
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

      final shellBin = File('/bin/dash').existsSync() ? '/bin/dash' : '/bin/sh';
      final result = await Process.run(
        shellBin,
        ['-c', script],
        environment: {
          'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        },
      );
      expect(result.exitCode, 0, reason: 'Script stderr: ${result.stderr}');

      // Legacy backup was restored and update succeeded
      expect(File('$appDir/data/old_doc.txt').existsSync(), isTrue);
      expect(File('$appDir/supergoodviewer').existsSync(), isTrue);
      expect(File('$appDir/data/partial_new.txt').existsSync(), isFalse);
    });

    test('buildLinuxUpdateScript aborts cleanly when writing journal fails', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_journal_fail_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      final mvMock = File('${binDir.path}/mv');
      mvMock.writeAsStringSync('''#!/bin/sh
for arg in "\$@"; do
  if echo "\$arg" | grep -q "\\.sgv_journal"; then
    exit 1
  fi
done
exec /bin/mv "\$@"
''');
      Process.runSync('chmod', ['+x', mvMock.path]);

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo old\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo new\n');
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

      final result = await Process.run(
        '/bin/sh',
        ['-c', script],
        environment: {
          'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}',
        },
      );
      expect(result.exitCode, isNot(0));
      expect(File('$appDir/supergoodviewer').readAsStringSync(), 'echo old\n');
    });

    test('buildLinuxUpdateScript preserves INSTALLED_LIST and BACKUP_DIR when rollback fails', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_rollback_fail_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo old\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo new\n');
      Process.runSync('chmod', ['-x', newExe.path]); // Not executable to trigger rollback!

      // Mock `chmod` to fail
      final chmodMock = File('${binDir.path}/chmod');
      chmodMock.writeAsStringSync('''#!/bin/sh
exit 1
''');
      Process.runSync('chmod', ['+x', chmodMock.path]);

      // Mock mv: succeed first (during backup and phase 2), but fail when moving from BACKUP_DIR back to appDir
      final mvMock = File('${binDir.path}/mv');
      mvMock.writeAsStringSync('''#!/bin/sh
if echo "\$1" | grep -q "\\.sgv_backup\\."; then
  # Moving from backup to appDir during rollback: fail!
  exit 1
fi
exec /bin/mv "\$@"
''');
      Process.runSync('chmod', ['+x', mvMock.path]);

      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: oldExe.path,
        appDir: appDir,
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

      // Check that .sgv_journal exists and contains BACKUP_DIR
      final journal = File('$appDir/.sgv_journal');
      expect(journal.existsSync(), isTrue);

      // Check that BACKUP_DIR exists
      final backupDirs = Directory(appDir).listSync().where((e) => e.path.contains('.sgv_backup.'));
      expect(backupDirs.isNotEmpty, isTrue);

      // Check that INSTALLED_LIST was preserved because rollback failed!
      final installedLists = Directory(appDir).listSync().where((e) => e.path.contains('.sgv_installed.'));
      expect(installedLists.isNotEmpty, isTrue);
    });

    test('ui/bin/sgv strictly validates path containment and rejects traversal/symlink journals', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('sgv_containment_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final appDir = testDir;
      final victimDir = Directory.systemTemp.createTempSync('sgv_victim_dir_');
      addTearDown(() {
        try {
          victimDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final victimFile = File('${victimDir.path}/secret.txt')..writeAsStringSync('vital data');

      // 1. Journal with BACKUP_DIR attempting path traversal
      final traversalJournal = File('${appDir.path}/.sgv_journal');
      traversalJournal.writeAsStringSync(
        'PID=99999998\nBACKUP_DIR=${appDir.path}/.sgv_backup.1/../../../victim\n',
      );

      final result1 = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(result1.exitCode, 0);
      expect(victimFile.existsSync(), isTrue);
      expect(victimDir.existsSync(), isTrue);

      // 2. Journal with BACKUP_DIR as a symlink pointing to victimDir
      final symlinkBackup = Link('${appDir.path}/.sgv_backup.99999997');
      try {
        symlinkBackup.createSync(victimDir.path);
      } catch (_) {}
      if (symlinkBackup.existsSync()) {
        final symlinkJournal = File('${appDir.path}/.sgv_journal');
        symlinkJournal.writeAsStringSync(
          'PID=99999997\nBACKUP_DIR=${symlinkBackup.path}\n',
        );
        final result2 = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
        expect(result2.exitCode, 0);
        expect(victimFile.existsSync(), isTrue);
        expect(victimDir.existsSync(), isTrue);
      }

      // 3. Traversal inside INSTALLED_LIST should be skipped, but double-dot filenames should be deleted
      final installedList = File('${appDir.path}/.sgv_installed.99999996');
      final legitimateFileWithDots = File('${appDir.path}/libfoo..so')..writeAsStringSync('new lib');
      installedList.writeAsStringSync(
        '..\n'
        '../victim/secret.txt\n'
        '/etc/shadow\n'
        'libfoo..so\n',
      );

      final validBackupDir = Directory('${appDir.path}/.sgv_backup.99999996')..createSync();
      File('${validBackupDir.path}/restored.txt').writeAsStringSync('restored');

      final mixedJournal = File('${appDir.path}/.sgv_journal');
      mixedJournal.writeAsStringSync(
        'PID=99999996\nBACKUP_DIR=${validBackupDir.path}\nINSTALLED_LIST=${installedList.path}\n',
      );

      final result3 = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(result3.exitCode, 0);
      // Victim file must NOT be deleted
      expect(victimFile.existsSync(), isTrue);
      // Legitimate file with dots in its name MUST be deleted by installed list
      expect(legitimateFileWithDots.existsSync(), isFalse);
      // Restored file from backup must exist
      expect(File('${appDir.path}/restored.txt').existsSync(), isTrue);
    });

    test('buildLinuxUpdateScript strictly validates path containment and rejects traversal/symlink journals', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('linux_script_containment_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final stagingDirPath = '${testDir.path}/staging';
      final victimDir = '${testDir.path}/victim';
      Directory(appDir).createSync(recursive: true);
      Directory(stagingDirPath).createSync(recursive: true);
      Directory(victimDir).createSync(recursive: true);

      final victimFile = File('$victimDir/important.txt')..writeAsStringSync('safe');

      final oldExe = File('$appDir/supergoodviewer');
      oldExe.writeAsStringSync('echo old\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final newExe = File('$stagingDirPath/supergoodviewer');
      newExe.writeAsStringSync('echo new\n');
      Process.runSync('chmod', ['+x', newExe.path]);

      // Previous journal with path traversal in PREV_BACKUP
      final journal = File('$appDir/.sgv_journal');
      journal.writeAsStringSync('PID=99999998\nBACKUP_DIR=$appDir/.sgv_backup.1/../../../victim\n');

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
      expect(victimFile.existsSync(), isTrue);
      expect(Directory(victimDir).existsSync(), isTrue);
    });

    test('UpdateService.cleanupStaleUpdateArtifacts strictly validates path containment and rejects traversal/symlink journals', () {
      final testDir = Directory.systemTemp.createTempSync('dart_cleanup_containment_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final victimDir = Directory('${testDir.path}/victim')..createSync(recursive: true);
      final victimFile = File('${victimDir.path}/data.txt')..writeAsStringSync('vital');

      // Traversal journal
      final journal = File('${appDir.path}/.sgv_journal');
      journal.writeAsStringSync('PID=99999998\nBACKUP_DIR=${appDir.path}/.sgv_backup.1/../../../victim\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Victim must be untouched and dangling journal cleaned
      expect(victimFile.existsSync(), isTrue);
      expect(journal.existsSync(), isFalse);

      // Traversal in INSTALLED_LIST should delete legitimate dotfile but NOT victim
      final installedList = File('${appDir.path}/.sgv_installed.99999997');
      final dotFile = File('${appDir.path}/libtest..so')..writeAsStringSync('dot');
      installedList.writeAsStringSync(
        '..\n'
        '../victim/data.txt\n'
        'libtest..so\n',
      );

      final validBackup = Directory('${appDir.path}/.sgv_backup.99999997')..createSync();
      File('${validBackup.path}/restored.txt').writeAsStringSync('restored');
      journal.writeAsStringSync('PID=99999997\nBACKUP_DIR=${validBackup.path}\nINSTALLED_LIST=${installedList.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      expect(victimFile.existsSync(), isTrue);
      expect(dotFile.existsSync(), isFalse);
      expect(File('${appDir.path}/restored.txt').existsSync(), isTrue);
    });

    test('isUpdaterProcessAlive matches candidate expectedAppDirs', () {
      expect(UpdateService.isUpdaterProcessAlive(null), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(0), isFalse);
      expect(UpdateService.isUpdaterProcessAlive(1), isFalse);
      if (Platform.isLinux) {
        expect(UpdateService.isUpdaterProcessAlive(pid, expectedAppDirs: ['/nonexistent/app/dir']), isFalse);
      }
    });

    test('bare dot in INSTALLED_LIST does not wipe application directory in Dart or Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      // 1. Dart test
      final dartTestDir = Directory.systemTemp.createTempSync('dart_bare_dot_test_');
      addTearDown(() {
        try {
          dartTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dartAppDir = Directory('${dartTestDir.path}/app')..createSync(recursive: true);
      final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final dartKeep = File('${dartAppDir.path}/keep.txt')..writeAsStringSync('keep');

      final dartInstalled = File('${dartAppDir.path}/.sgv_installed.99999995');
      dartInstalled.writeAsStringSync('.\n./\n');

      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.99999995')..createSync();
      File('${dartBackup.path}/restored.txt').writeAsStringSync('restored');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=99999995\nBACKUP_DIR=${dartBackup.path}\nINSTALLED_LIST=${dartInstalled.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      // Entire application directory must NOT be wiped by bare dot!
      expect(dartExe.existsSync(), isTrue);
      expect(dartKeep.existsSync(), isTrue);
      expect(File('${dartAppDir.path}/restored.txt').existsSync(), isTrue);

      // 2. Shell test (sgv)
      final shellTestDir = Directory.systemTemp.createTempSync('shell_bare_dot_test_');
      addTearDown(() {
        try {
          shellTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${shellTestDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellAppDir = shellTestDir;
      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final shellKeep = File('${shellAppDir.path}/keep.txt')..writeAsStringSync('keep');

      final shellInstalled = File('${shellAppDir.path}/.sgv_installed.99999994');
      shellInstalled.writeAsStringSync('.\n./\n');

      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.99999994')..createSync();
      File('${shellBackup.path}/restored.txt').writeAsStringSync('restored');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=99999994\nBACKUP_DIR=${shellBackup.path}\nINSTALLED_LIST=${shellInstalled.path}\n');

      final result = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(result.exitCode, 0);

      expect(shellExe.existsSync(), isTrue);
      expect(shellKeep.existsSync(), isTrue);
      expect(File('${shellAppDir.path}/restored.txt').existsSync(), isTrue);
    });

    test('shared PID validation fixtures tested symmetrically across Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('shared_pid_fixtures_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);

      final outsideVictim = File('${testDir.path}/victim.txt')..writeAsStringSync('victim');

      final fixtures = <({
        String name,
        String Function(int deadPid) makePidLine,
      })>[
        (name: 'PID=0 (non-positive zero)', makePidLine: (d) => 'PID=0\n'),
        (name: 'PID=1 (init process ID)', makePidLine: (d) => 'PID=1\n'),
        (name: 'PID=-1 (negative integer)', makePidLine: (d) => 'PID=-1\n'),
        (name: 'PID=00123 (leading zero)', makePidLine: (d) => 'PID=00123\n'),
        (name: 'PID=x/../../../victim.txt (path traversal non-numeric)', makePidLine: (d) => 'PID=x/../../../victim.txt\n'),
        (name: 'PID=1234567890123456789012345 (25-digit integer overflow)', makePidLine: (d) => 'PID=1234567890123456789012345\n'),
        (name: 'all invalid PID lines (falls back to backup dir PID)', makePidLine: (d) => 'PID=not_a_number\nPID=garbage\n'),
      ];

      for (int i = 0; i < fixtures.length; i++) {
        final fix = fixtures[i];
        final suffix = findInactivePid();
        final pidLine = fix.makePidLine(suffix);

        // 1. Shell runner
        final shellAppDir = Directory('${testDir.path}/shell_$i')..createSync(recursive: true);
        final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
        final shellKeep = File('${shellAppDir.path}/keep.txt')..writeAsStringSync('keep');
        final shellPartial = File('${shellAppDir.path}/partial.txt')..writeAsStringSync('partial');

        final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$suffix')..createSync();
        File('${shellBackup.path}/restored.txt').writeAsStringSync('restored');

        final shellInstalled = File('${shellAppDir.path}/.sgv_installed.$suffix');
        shellInstalled.writeAsStringSync('partial.txt\n');

        final shellJournal = File('${shellAppDir.path}/.sgv_journal');
        shellJournal.writeAsStringSync('${pidLine}BACKUP_DIR=${shellBackup.path}\n');

        final localBin = Directory('${shellAppDir.path}/bin')..createSync();
        final localSgv = File('${localBin.path}/sgv');
        sgvFile.copySync(localSgv.path);
        Process.runSync('chmod', ['+x', localSgv.path]);
        final localUname = File('${localBin.path}/uname');
        unameMock.copySync(localUname.path);
        Process.runSync('chmod', ['+x', localUname.path]);
        final localEnv = {'PATH': '${localBin.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

        final shellResult = await Process.run(localSgv.path, ['-h'], environment: localEnv);
        expect(shellResult.exitCode, 0, reason: 'Shell failed for fixture ${fix.name}');
        expect(shellExe.existsSync(), isTrue, reason: 'Exe should exist for fixture ${fix.name}');
        expect(shellKeep.existsSync(), isTrue, reason: 'Keep should exist for fixture ${fix.name}');
        expect(shellPartial.existsSync(), isFalse, reason: 'Partial should be deleted for fixture ${fix.name}');
        expect(File('${shellAppDir.path}/restored.txt').existsSync(), isTrue, reason: 'Restored should exist for fixture ${fix.name}');
        expect(shellBackup.existsSync(), isFalse, reason: 'Backup should be removed for fixture ${fix.name}');
        expect(shellJournal.existsSync(), isFalse, reason: 'Journal should be removed for fixture ${fix.name}');
        expect(outsideVictim.existsSync(), isTrue, reason: 'Victim must be untouched for fixture ${fix.name}');

        // 2. Dart runner
        final dartAppDir = Directory('${testDir.path}/dart_$i')..createSync(recursive: true);
        final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
        final dartKeep = File('${dartAppDir.path}/keep.txt')..writeAsStringSync('keep');
        final dartPartial = File('${dartAppDir.path}/partial.txt')..writeAsStringSync('partial');

        final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$suffix')..createSync();
        File('${dartBackup.path}/restored.txt').writeAsStringSync('restored');

        final dartInstalled = File('${dartAppDir.path}/.sgv_installed.$suffix');
        dartInstalled.writeAsStringSync('partial.txt\n');

        final dartJournal = File('${dartAppDir.path}/.sgv_journal');
        dartJournal.writeAsStringSync('${pidLine}BACKUP_DIR=${dartBackup.path}\n');

        UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

        expect(dartExe.existsSync(), isTrue, reason: 'Dart exe should exist for fixture ${fix.name}');
        expect(dartKeep.existsSync(), isTrue, reason: 'Dart keep should exist for fixture ${fix.name}');
        expect(dartPartial.existsSync(), isFalse, reason: 'Dart partial should be deleted for fixture ${fix.name}');
        expect(File('${dartAppDir.path}/restored.txt').existsSync(), isTrue, reason: 'Dart restored should exist for fixture ${fix.name}');
        expect(dartBackup.existsSync(), isFalse, reason: 'Dart backup should be removed for fixture ${fix.name}');
        expect(dartJournal.existsSync(), isFalse, reason: 'Dart journal should be removed for fixture ${fix.name}');
        expect(outsideVictim.existsSync(), isTrue, reason: 'Dart victim must be untouched for fixture ${fix.name}');
      }
    });

    test('failed targetLink deletion aborts move and preserves backup directory and journal in Dart', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('target_link_failure_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', testDir.path]);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final outsideDir = Directory('${testDir.path}/outside_dir')..createSync(recursive: true);
      File('${outsideDir.path}/victim_file.txt').writeAsStringSync('victim');

      // Create a target symlink pointing to outsideDir
      final targetLink = Link('${appDir.path}/restored_item');
      targetLink.createSync(outsideDir.path);

      // Create a backup directory containing an item of the same name
      final deadPid = findInactivePid();
      final backup = Directory('${appDir.path}/.sgv_backup.$deadPid')..createSync();
      final backupSub = Directory('${backup.path}/restored_item')..createSync();
      File('${backupSub.path}/new_file.txt').writeAsStringSync('new');

      final journal = File('${appDir.path}/.sgv_journal');
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${backup.path}\n');

      // Make appDir read-only so targetLink.deleteSync() fails with permission error
      Process.runSync('chmod', ['555', appDir.path]);

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Restore write permissions to inspect and clean up
      Process.runSync('chmod', ['755', appDir.path]);

      // Since targetLink could not be deleted, it must NOT have moved backupSub into outsideDir!
      expect(File('${outsideDir.path}/new_file.txt').existsSync(), isFalse);
      expect(File('${outsideDir.path}/restored_item/new_file.txt').existsSync(), isFalse);

      // Backup directory and journal must be preserved because recovery failed!
      expect(backup.existsSync(), isTrue);
      expect(journal.existsSync(), isTrue);
    });

    test('failed existing target removal aborts move and preserves backup directory and journal in Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('shell_target_failure_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', testDir.path]);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final binDir = Directory('${appDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final exe = File('${appDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', exe.path]);

      final existingDir = Directory('${appDir.path}/restored_item')..createSync();
      File('${existingDir.path}/existing.txt').writeAsStringSync('old');

      final deadPid = findInactivePid();
      final backup = Directory('${appDir.path}/.sgv_backup.$deadPid')..createSync();
      final backupSub = Directory('${backup.path}/restored_item')..createSync();
      File('${backupSub.path}/new_file.txt').writeAsStringSync('new');

      final journal = File('${appDir.path}/.sgv_journal');
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${backup.path}\n');

      // Make appDir read-only so rm -rf "$candidate/restored_item" fails to unlink
      Process.runSync('chmod', ['555', appDir.path]);

      final result = await Process.run(sgvFile.path, ['-h'], environment: testEnv);

      // Restore write permissions to inspect
      Process.runSync('chmod', ['755', appDir.path]);

      expect(result.exitCode, 0);

      // It must NOT have moved backupSub into existingDir (no nested restored_item/restored_item)
      expect(File('${existingDir.path}/new_file.txt').existsSync(), isFalse);
      expect(File('${existingDir.path}/restored_item/new_file.txt').existsSync(), isFalse);

      // Backup directory and journal must be preserved because recovery failed!
      expect(backup.existsSync(), isTrue);
      expect(journal.existsSync(), isTrue);
    });

    test('damaged PID= line falls back to BACKUP_DIR suffix and protects live updater in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('live_pid_override_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 1. Dart test: live updater process running supergoodviewer inside dartAppDir
      final dartAppDir = Directory('${testDir.path}/dart_app')..createSync(recursive: true);
      final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', dartExe.path]);
      final dartProcess = await Process.start(dartExe.path, []);
      final dartLivePid = dartProcess.pid;
      addTearDown(() {
        try {
          dartProcess.kill();
        } catch (_) {}
      });

      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartLivePid')..createSync();
      File('${dartBackup.path}/restored.txt').writeAsStringSync('restored');
      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=garbage\nBACKUP_DIR=${dartBackup.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      // Since PID=garbage is invalid, it falls back to BACKUP_DIR suffix ($dartLivePid) which is alive!
      expect(dartBackup.existsSync(), isTrue, reason: 'Dart should preserve backup while PID is alive');
      expect(dartJournal.existsSync(), isTrue, reason: 'Dart should preserve journal while PID is alive');
      expect(File('${dartAppDir.path}/restored.txt').existsSync(), isFalse);

      // 2. Shell test: live updater process running supergoodviewer inside shellAppDir
      final shellAppDir = Directory('${testDir.path}/shell_app')..createSync(recursive: true);
      final binDir = Directory('${shellAppDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', shellExe.path]);
      final shellProcess = await Process.start(shellExe.path, []);
      final shellLivePid = shellProcess.pid;
      addTearDown(() {
        try {
          shellProcess.kill();
        } catch (_) {}
      });

      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellLivePid')..createSync();
      File('${shellBackup.path}/restored.txt').writeAsStringSync('restored');
      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=garbage\nBACKUP_DIR=${shellBackup.path}\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      // Shell should also preserve backup and journal while PID is alive!
      expect(shellBackup.existsSync(), isTrue, reason: 'Shell should preserve backup while PID is alive');
      expect(shellJournal.existsSync(), isTrue, reason: 'Shell should preserve journal while PID is alive');
      expect(File('${shellAppDir.path}/restored.txt').existsSync(), isFalse);
    });

    test('earlier valid PID= is preserved when later PID= line is damaged even without BACKUP_DIR in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('valid_pid_damaged_later_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 1. Dart test: earlier valid PID, damaged later line, NO valid BACKUP_DIR
      final dartAppDir = Directory('${testDir.path}/dart_app')..createSync(recursive: true);
      final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', dartExe.path]);
      final dartProcess = await Process.start(dartExe.path, []);
      final dartLivePid = dartProcess.pid;
      addTearDown(() {
        try {
          dartProcess.kill();
        } catch (_) {}
      });

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartLivePid\nPID=corrupted\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      // Since PID=$dartLivePid was preserved and is alive, journal must NOT be treated as dangling and deleted!
      expect(dartJournal.existsSync(), isTrue, reason: 'Dart should preserve journal while PID is alive even if trailing PID line is garbage');

      // 2. Shell test
      final shellAppDir = Directory('${testDir.path}/shell_app')..createSync(recursive: true);
      final binDir = Directory('${shellAppDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nsleep 30\n');
      Process.runSync('chmod', ['+x', shellExe.path]);
      final shellProcess = await Process.start(shellExe.path, []);
      final shellLivePid = shellProcess.pid;
      addTearDown(() {
        try {
          shellProcess.kill();
        } catch (_) {}
      });

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellLivePid\nPID=corrupted\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      // Shell should also preserve journal while PID is alive!
      expect(shellJournal.existsSync(), isTrue, reason: 'Shell should preserve journal while PID is alive even if trailing PID line is garbage');
    });

    test('recovery unlinks symlink target without chmodding outside directory in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('symlink_outside_chmod_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', testDir.path]);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 1. Dart test
      final dartOutside = Directory('${testDir.path}/dart_outside')..createSync(recursive: true);
      final dartOutsideFile = File('${dartOutside.path}/victim.txt')..writeAsStringSync('secret');
      Process.runSync('chmod', ['700', dartOutside.path]);
      Process.runSync('chmod', ['600', dartOutsideFile.path]);

      final dartAppDir = Directory('${testDir.path}/dart_app')..createSync(recursive: true);
      // Create a symlink in appDir pointing to outside directory
      Link('${dartAppDir.path}/shared_lib').createSync(dartOutside.path);

      final dartDeadPid = findInactivePid();
      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartDeadPid')..createSync();
      final dartBackupSub = Directory('${dartBackup.path}/shared_lib')..createSync();
      File('${dartBackupSub.path}/new_lib.txt').writeAsStringSync('new_lib');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartDeadPid\nBACKUP_DIR=${dartBackup.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      // Verify symlink was unlinked and replaced with restored dir
      expect(Link('${dartAppDir.path}/shared_lib').existsSync(), isFalse);
      expect(File('${dartAppDir.path}/shared_lib/new_lib.txt').existsSync(), isTrue);

      final dartStat = Process.runSync('ls', ['-ld', dartOutsideFile.path]).stdout.toString();
      expect(dartStat.contains('-rw-------'), isTrue, reason: 'Outside file permissions must remain 600, not chmodded to executable');

      // 2. Shell test
      final shellOutside = Directory('${testDir.path}/shell_outside')..createSync(recursive: true);
      final shellOutsideFile = File('${shellOutside.path}/victim.txt')..writeAsStringSync('secret');
      Process.runSync('chmod', ['700', shellOutside.path]);
      Process.runSync('chmod', ['600', shellOutsideFile.path]);

      final shellAppDir = Directory('${testDir.path}/shell_app')..createSync(recursive: true);
      final binDir = Directory('${shellAppDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', shellExe.path]);

      Link('${shellAppDir.path}/shared_lib').createSync(shellOutside.path);

      final shellDeadPid = findInactivePid();
      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellDeadPid')..createSync();
      final shellBackupSub = Directory('${shellBackup.path}/shared_lib')..createSync();
      File('${shellBackupSub.path}/new_lib.txt').writeAsStringSync('new_lib');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellDeadPid\nBACKUP_DIR=${shellBackup.path}\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      expect(Link('${shellAppDir.path}/shared_lib').existsSync(), isFalse);
      expect(File('${shellAppDir.path}/shared_lib/new_lib.txt').existsSync(), isTrue);

      final shellStat = Process.runSync('ls', ['-ld', shellOutsideFile.path]).stdout.toString();
      expect(shellStat.contains('-rw-------'), isTrue, reason: 'Outside file permissions must remain 600 in shell test');
    });

    test('Dart recovery loop recovers cleanly when existing target is a 0555 read-only directory', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('dart_ro_recovery_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', testDir.path]);
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = Directory('${testDir.path}/app')..createSync(recursive: true);
      final roDir = Directory('${appDir.path}/ro_dir')..createSync();
      File('${roDir.path}/old.txt').writeAsStringSync('old');
      Process.runSync('chmod', ['555', roDir.path]);

      final deadPid = findInactivePid();
      final backup = Directory('${appDir.path}/.sgv_backup.$deadPid')..createSync();
      final backupSub = Directory('${backup.path}/ro_dir')..createSync();
      File('${backupSub.path}/new.txt').writeAsStringSync('new');

      final journal = File('${appDir.path}/.sgv_journal');
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${backup.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);

      // Verify that ro_dir was replaced and backup was restored
      expect(File('${appDir.path}/ro_dir/new.txt').existsSync(), isTrue);
      expect(backup.existsSync(), isFalse);
      expect(journal.existsSync(), isFalse);
    });

    test('chmod 000 unreadable directory in INSTALLED_LIST is safely deleted by Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      // 1. Dart test
      final dartTestDir = Directory.systemTemp.createTempSync('dart_chmod000_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', dartTestDir.path]);
          dartTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dartAppDir = Directory('${dartTestDir.path}/app')..createSync(recursive: true);
      final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final dartKeep = File('${dartAppDir.path}/keep.txt')..writeAsStringSync('keep');

      final dartUnreadableDir = Directory('${dartAppDir.path}/unreadable_dir')..createSync();
      File('${dartUnreadableDir.path}/nested.txt').writeAsStringSync('nested');
      Process.runSync('chmod', ['000', dartUnreadableDir.path]);

      final dartBackupPid = findInactivePid();
      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartBackupPid')..createSync();
      File('${dartBackup.path}/restored.txt').writeAsStringSync('restored');

      final dartInstalled = File('${dartAppDir.path}/.sgv_installed.$dartBackupPid');
      dartInstalled.writeAsStringSync('unreadable_dir\n');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartBackupPid\nBACKUP_DIR=${dartBackup.path}\nINSTALLED_LIST=${dartInstalled.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      expect(dartUnreadableDir.existsSync(), isFalse);
      expect(dartExe.existsSync(), isTrue);
      expect(dartKeep.existsSync(), isTrue);
      expect(File('${dartAppDir.path}/restored.txt').existsSync(), isTrue);

      // 2. Shell test
      final shellTestDir = Directory.systemTemp.createTempSync('shell_chmod000_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', shellTestDir.path]);
          shellTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final shellAppDir = shellTestDir;
      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final shellKeep = File('${shellAppDir.path}/keep.txt')..writeAsStringSync('keep');

      final binDir = Directory('${shellAppDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellUnreadableDir = Directory('${shellAppDir.path}/unreadable_dir')..createSync();
      File('${shellUnreadableDir.path}/nested.txt').writeAsStringSync('nested');
      Process.runSync('chmod', ['000', shellUnreadableDir.path]);

      final shellBackupPid = findInactivePid();
      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellBackupPid')..createSync();
      File('${shellBackup.path}/restored.txt').writeAsStringSync('restored');

      final shellInstalled = File('${shellAppDir.path}/.sgv_installed.$shellBackupPid');
      shellInstalled.writeAsStringSync('unreadable_dir\n');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellBackupPid\nBACKUP_DIR=${shellBackup.path}\nINSTALLED_LIST=${shellInstalled.path}\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      expect(shellUnreadableDir.existsSync(), isFalse);
      expect(shellExe.existsSync(), isTrue);
      expect(shellKeep.existsSync(), isTrue);
      expect(File('${shellAppDir.path}/restored.txt').existsSync(), isTrue);
    });

    test('symlink parent directory in INSTALLED_LIST cannot escape appDir in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      // 1. Dart test
      final dartTestDir = Directory.systemTemp.createTempSync('dart_symlink_escape_test_');
      addTearDown(() {
        try {
          dartTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dartVictimDir = Directory.systemTemp.createTempSync('dart_victim_dir_');
      addTearDown(() {
        try {
          dartVictimDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final dartVictimFile = File('${dartVictimDir.path}/victim.txt')..writeAsStringSync('victim');

      final dartAppDir = Directory('${dartTestDir.path}/app')..createSync(recursive: true);
      final dartExe = File('${dartAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final dartKeep = File('${dartAppDir.path}/keep.txt')..writeAsStringSync('keep');

      // Create a directory symlink pointing outside appDir
      Link('${dartAppDir.path}/sub').createSync(dartVictimDir.path);
      // Create a leaf symlink pointing directly to the outside victim file
      Link('${dartAppDir.path}/leaf_link').createSync(dartVictimFile.path);

      final dartBackupPid = findInactivePid();
      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartBackupPid')..createSync();
      File('${dartBackup.path}/restored.txt').writeAsStringSync('restored');

      final dartInstalled = File('${dartAppDir.path}/.sgv_installed.$dartBackupPid');
      dartInstalled.writeAsStringSync('sub/victim.txt\nleaf_link\n');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartBackupPid\nBACKUP_DIR=${dartBackup.path}\nINSTALLED_LIST=${dartInstalled.path}\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      expect(dartVictimFile.existsSync(), isTrue);
      expect(Link('${dartAppDir.path}/leaf_link').existsSync(), isFalse);
      expect(dartVictimFile.existsSync(), isTrue); // still exists after leaf_link was deleted
      expect(dartExe.existsSync(), isTrue);
      expect(dartKeep.existsSync(), isTrue);
      expect(File('${dartAppDir.path}/restored.txt').existsSync(), isTrue);

      // 2. Shell test (sgv)
      final shellTestDir = Directory.systemTemp.createTempSync('shell_symlink_escape_test_');
      addTearDown(() {
        try {
          shellTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final shellVictimDir = Directory.systemTemp.createTempSync('shell_victim_dir_');
      addTearDown(() {
        try {
          shellVictimDir.deleteSync(recursive: true);
        } catch (_) {}
      });
      final shellVictimFile = File('${shellVictimDir.path}/victim.txt')..writeAsStringSync('victim');

      final binDir = Directory('${shellTestDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellAppDir = shellTestDir;
      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('binary');
      final shellKeep = File('${shellAppDir.path}/keep.txt')..writeAsStringSync('keep');

      Link('${shellAppDir.path}/sub').createSync(shellVictimDir.path);
      Link('${shellAppDir.path}/leaf_link').createSync(shellVictimFile.path);

      final shellBackupPid = findInactivePid();
      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellBackupPid')..createSync();
      File('${shellBackup.path}/restored.txt').writeAsStringSync('restored');

      final shellInstalled = File('${shellAppDir.path}/.sgv_installed.$shellBackupPid');
      shellInstalled.writeAsStringSync('sub/victim.txt\nleaf_link\n');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellBackupPid\nBACKUP_DIR=${shellBackup.path}\nINSTALLED_LIST=${shellInstalled.path}\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      expect(shellVictimFile.existsSync(), isTrue);
      expect(Link('${shellAppDir.path}/leaf_link').existsSync(), isFalse);
      expect(shellVictimFile.existsSync(), isTrue);
      expect(shellExe.existsSync(), isTrue);
      expect(shellKeep.existsSync(), isTrue);
      expect(File('${shellAppDir.path}/restored.txt').existsSync(), isTrue);
    });

    test('backup name with suffix like .sgv_backup.5.evil is rejected by both Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('name_parity_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${testDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final deadPid = findInactivePid();
      final appDir = testDir;
      final evilBackup = Directory('${appDir.path}/.sgv_backup.$deadPid.evil')..createSync();
      File('${evilBackup.path}/evil.txt').writeAsStringSync('evil');

      final journal = File('${appDir.path}/.sgv_journal');
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${evilBackup.path}\n');

      // 1. Shell test: evil backup must be rejected, not restored
      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);
      expect(File('${appDir.path}/evil.txt').existsSync(), isFalse);

      // 2. Dart test: evil backup must also be rejected
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${evilBackup.path}\n');
      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: appDir);
      expect(File('${appDir.path}/evil.txt').existsSync(), isFalse);
    });

    test('Issue 1: repeated recovery does not delete already-restored files in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      // 1. Dart test
      final dartTestDir = Directory.systemTemp.createTempSync('dart_issue1_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', dartTestDir.path]);
          dartTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dartAppDir = Directory('${dartTestDir.path}/app')..createSync(recursive: true);
      File('${dartAppDir.path}/supergoodviewer').writeAsStringSync('binary');
      final dartDeadPid = findInactivePid();
      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartDeadPid')..createSync();
      File('${dartBackup.path}/restored_a.txt').writeAsStringSync('original a');

      // Create fail_item as directory with a read-only target in appDir so first recovery restores a but fails on b
      final dartFailDir = Directory('${dartBackup.path}/fail_item')..createSync();
      File('${dartFailDir.path}/sub.txt').writeAsStringSync('sub');
      final dartAppFail = Directory('${dartAppDir.path}/fail_item')..createSync();
      File('${dartAppFail.path}/sub.txt').writeAsStringSync('sub');
      Process.runSync('chmod', ['555', dartAppFail.path]);

      final dartInstalled = File('${dartAppDir.path}/.sgv_installed.$dartDeadPid');
      dartInstalled.writeAsStringSync('restored_a.txt\nfail_item\n');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartDeadPid\nBACKUP_DIR=${dartBackup.path}\nINSTALLED_LIST=${dartInstalled.path}\n');

      // First recovery attempt: restores restored_a.txt, but fail_item fails.
      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      expect(File('${dartAppDir.path}/restored_a.txt').existsSync(), isTrue);
      expect(File('${dartAppDir.path}/restored_a.txt').readAsStringSync(), 'original a');
      // Notice: restored_a.txt was moved out of backup, so backup no longer has restored_a.txt!
      expect(File('${dartBackup.path}/restored_a.txt').existsSync(), isFalse);

      // Now run recovery a second time: restored_a.txt MUST NOT be deleted by INSTALLED_LIST!
      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);
      expect(File('${dartAppDir.path}/restored_a.txt').existsSync(), isTrue);
      expect(File('${dartAppDir.path}/restored_a.txt').readAsStringSync(), 'original a');

      // 2. Shell test (sgv)
      final shellTestDir = Directory.systemTemp.createTempSync('shell_issue1_test_');
      addTearDown(() {
        try {
          Process.runSync('chmod', ['-R', '777', shellTestDir.path]);
          shellTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${shellTestDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellAppDir = shellTestDir;
      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', shellExe.path]);

      final shellDeadPid = findInactivePid();
      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellDeadPid')..createSync();
      File('${shellBackup.path}/restored_a.txt').writeAsStringSync('original shell a');

      final shellFailDir = Directory('${shellBackup.path}/fail_item')..createSync();
      File('${shellFailDir.path}/sub.txt').writeAsStringSync('sub');
      final shellAppFail = Directory('${shellAppDir.path}/fail_item')..createSync();
      File('${shellAppFail.path}/sub.txt').writeAsStringSync('sub');
      Process.runSync('chmod', ['555', shellAppFail.path]);

      final shellInstalled = File('${shellAppDir.path}/.sgv_installed.$shellDeadPid');
      shellInstalled.writeAsStringSync('restored_a.txt\nfail_item\n');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellDeadPid\nBACKUP_DIR=${shellBackup.path}\nINSTALLED_LIST=${shellInstalled.path}\n');

      // First recovery
      await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(File('${shellAppDir.path}/restored_a.txt').existsSync(), isTrue);
      expect(File('${shellAppDir.path}/restored_a.txt').readAsStringSync(), 'original shell a');
      expect(File('${shellBackup.path}/restored_a.txt').existsSync(), isFalse);

      // Second recovery: restored_a.txt must NOT be deleted
      await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(File('${shellAppDir.path}/restored_a.txt').existsSync(), isTrue);
      expect(File('${shellAppDir.path}/restored_a.txt').readAsStringSync(), 'original shell a');
    });

    test('Issue 2: explicit transaction commit prevents rolling back to partial backup in Dart and Shell', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      // 1. Dart test
      final dartTestDir = Directory.systemTemp.createTempSync('dart_issue2_test_');
      addTearDown(() {
        try {
          dartTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final dartAppDir = Directory('${dartTestDir.path}/app')..createSync(recursive: true);
      File('${dartAppDir.path}/supergoodviewer').writeAsStringSync('new binary');
      final dataDir = Directory('${dartAppDir.path}/data')..createSync();
      File('${dataDir.path}/assets.txt').writeAsStringSync('new version data');

      final dartDeadPid = findInactivePid();
      // Partially deleted backup: does NOT have data/
      final dartBackup = Directory('${dartAppDir.path}/.sgv_backup.$dartDeadPid')..createSync();
      File('${dartBackup.path}/supergoodviewer').writeAsStringSync('old binary');

      final dartJournal = File('${dartAppDir.path}/.sgv_journal');
      dartJournal.writeAsStringSync('PID=$dartDeadPid\nBACKUP_DIR=${dartBackup.path}\nSTATUS=COMMITTED\n');

      UpdateService.cleanupStaleUpdateArtifacts(targetAppDir: dartAppDir);

      // Verify: data/ was NOT wiped, new version data remains intact!
      expect(File('${dartAppDir.path}/data/assets.txt').existsSync(), isTrue);
      expect(File('${dartAppDir.path}/data/assets.txt').readAsStringSync(), 'new version data');
      expect(File('${dartAppDir.path}/supergoodviewer').readAsStringSync(), 'new binary');
      // Residual backup and journal are deleted
      expect(dartBackup.existsSync(), isFalse);
      expect(dartJournal.existsSync(), isFalse);

      // 2. Shell test (sgv)
      final shellTestDir = Directory.systemTemp.createTempSync('shell_issue2_test_');
      addTearDown(() {
        try {
          shellTestDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final binDir = Directory('${shellTestDir.path}/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      final unameMock = File('${binDir.path}/uname');
      unameMock.writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${binDir.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final shellAppDir = shellTestDir;
      final shellExe = File('${shellAppDir.path}/supergoodviewer')..writeAsStringSync('#!/bin/sh\nexit 0\n');
      Process.runSync('chmod', ['+x', shellExe.path]);
      final shellDataDir = Directory('${shellAppDir.path}/data')..createSync();
      File('${shellDataDir.path}/assets.txt').writeAsStringSync('new version data');

      final shellDeadPid = findInactivePid();
      final shellBackup = Directory('${shellAppDir.path}/.sgv_backup.$shellDeadPid')..createSync();
      File('${shellBackup.path}/supergoodviewer').writeAsStringSync('old binary');

      final shellJournal = File('${shellAppDir.path}/.sgv_journal');
      shellJournal.writeAsStringSync('PID=$shellDeadPid\nBACKUP_DIR=${shellBackup.path}\nSTATUS=COMMITTED\n');

      final shellResult = await Process.run(sgvFile.path, ['-h'], environment: testEnv);
      expect(shellResult.exitCode, 0);

      // Verify: data/ was NOT wiped!
      expect(File('${shellAppDir.path}/data/assets.txt').existsSync(), isTrue);
      expect(File('${shellAppDir.path}/data/assets.txt').readAsStringSync(), 'new version data');
      expect(shellBackup.existsSync(), isFalse);
      expect(shellJournal.existsSync(), isFalse);
    });

    test('Issue 3: recovery entry remains runnable outside transaction replacement scope between phases', () async {
      if (!Platform.isMacOS && !Platform.isLinux) return;

      final testDir = Directory.systemTemp.createTempSync('issue3_recovery_entry_test_');
      addTearDown(() {
        try {
          testDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final appDir = '${testDir.path}/app';
      final binDir = Directory('$appDir/bin')..createSync(recursive: true);
      final sgvFile = File('${binDir.path}/sgv');
      File('bin/sgv').copySync(sgvFile.path);
      Process.runSync('chmod', ['+x', sgvFile.path]);

      // Create CLI symlink pointing to $appDir/bin/sgv
      final symlinkBin = Directory('${testDir.path}/sysbin')..createSync(recursive: true);
      final cliSymlink = Link('${symlinkBin.path}/sgv');
      cliSymlink.createSync(sgvFile.path);

      final oldExe = File('$appDir/supergoodviewer')..writeAsStringSync('#!/bin/sh\necho original_app\n');
      Process.runSync('chmod', ['+x', oldExe.path]);

      final libDir = Directory('$appDir/lib')..createSync(recursive: true);
      File('${libDir.path}/libflutter.so').writeAsStringSync('original flutter lib');

      // Staging payload
      final stagingDirPath = '${testDir.path}/staging';
      Directory(stagingDirPath).createSync(recursive: true);
      final stagedExe = File('$stagingDirPath/supergoodviewer')..writeAsStringSync('#!/bin/sh\necho updated_app\n');
      Process.runSync('chmod', ['+x', stagedExe.path]);
      final stagedLib = Directory('$stagingDirPath/lib')..createSync(recursive: true);
      File('${stagedLib.path}/libflutter.so').writeAsStringSync('updated flutter lib');
      final stagedBin = Directory('$stagingDirPath/bin')..createSync(recursive: true);
      File('bin/sgv').copySync('${stagedBin.path}/sgv');
      Process.runSync('chmod', ['+x', '${stagedBin.path}/sgv']);

      // Generate update script and verify Phase 1 excludes bin
      final dummyProcess = await Process.start('true', []);
      final dummyPid = dummyProcess.pid;
      await dummyProcess.exitCode;

      final script = UpdateService.buildLinuxUpdateScript(
        currentPid: dummyPid,
        exePath: oldExe.path,
        appDir: appDir,
        stagingDirPath: stagingDirPath,
      );

      expect(script.contains('if [ "\$n" = "bin" ]; then'), isTrue);
      expect(script.contains('STATUS=COMMITTED'), isTrue);

      // Fault injection: Simulate process interrupted right after Phase 1 (between Phase 1 and Phase 2)
      // Phase 1 moved supergoodviewer and lib into backup, bin was NOT moved.
      final deadPid = findInactivePid();
      final backupDir = Directory('$appDir/.sgv_backup.$deadPid')..createSync();
      oldExe.renameSync('${backupDir.path}/supergoodviewer');
      libDir.renameSync('${backupDir.path}/lib');

      // Create the recovery stub that Phase 1 places at $appDir/supergoodviewer
      final stubExe = File('$appDir/supergoodviewer');
      stubExe.writeAsStringSync('''#!/bin/sh
APP_DIR="\$(cd "\$(dirname "\$0")" 2>/dev/null && pwd)"
if [ -x "\$APP_DIR/bin/sgv" ]; then
  exec "\$APP_DIR/bin/sgv" "\$@"
fi
exit 1
''');
      Process.runSync('chmod', ['+x', stubExe.path]);

      final journal = File('$appDir/.sgv_journal');
      journal.writeAsStringSync('PID=$deadPid\nBACKUP_DIR=${backupDir.path}\n');

      // Verify condition:
      // 1. $appDir/bin/sgv still exists and symlink cliSymlink is valid!
      expect(sgvFile.existsSync(), isTrue);
      expect(cliSymlink.existsSync(), isTrue);

      // 2. $appDir/supergoodviewer exists and is executable!
      expect(stubExe.existsSync(), isTrue);

      // 3. Executing cliSymlink recovers the app from backup!
      final unameMock = File('${symlinkBin.path}/uname')..writeAsStringSync('#!/bin/sh\necho "Linux"\n');
      Process.runSync('chmod', ['+x', unameMock.path]);
      final testEnv = {'PATH': '${symlinkBin.path}:${Platform.environment['PATH'] ?? '/usr/bin:/bin'}'};

      final recResult = await Process.run(cliSymlink.path, ['-h'], environment: testEnv);
      expect(recResult.exitCode, 0);

      // Verify the original binary and lib were restored!
      expect(File('$appDir/supergoodviewer').existsSync(), isTrue);
      expect(File('$appDir/supergoodviewer').readAsStringSync(), contains('original_app'));
      expect(File('$appDir/lib/libflutter.so').existsSync(), isTrue);
      expect(File('$appDir/lib/libflutter.so').readAsStringSync(), 'original flutter lib');
      expect(backupDir.existsSync(), isFalse);
      expect(journal.existsSync(), isFalse);
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
