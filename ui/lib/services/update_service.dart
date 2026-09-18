import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/update_info.dart';
import 'preferences_service.dart';

/// Service responsible for checking, downloading, and applying updates
/// from GitHub Releases across macOS, Windows, and Linux.
class UpdateService {
  static const String repoOwner = 'dotsg';
  static const String repoName = 'supergoodviewer';
  static const String defaultAppVersion = '1.0.7';

  static const String prefAutoCheck = 'autoCheckUpdates';
  static const String prefLastCheckTime = 'lastUpdateCheckTime';
  static const String prefIgnoredVersion = 'ignoredUpdateVersion';

  static const Duration checkCooldown = Duration(hours: 24);

  static UpdateService? _instance;
  static UpdateService get instance => _instance ??= UpdateService();

  @visibleForTesting
  static void setInstanceForTesting(UpdateService? service) {
    _instance = service;
  }

  /// Compares two semantic version strings (e.g. "1.0.7" vs "v1.0.8").
  /// Returns > 0 if [a] > [b], < 0 if [a] < [b], and 0 if equal.
  static int compareSemVer(String a, String b) {
    final cleanA = a.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '').split('+').first;
    final cleanB = b.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '').split('+').first;

    final partsA = cleanA.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = cleanB.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    final maxLen = math.max(partsA.length, partsB.length);
    for (int i = 0; i < maxLen; i++) {
      final vA = i < partsA.length ? partsA[i] : 0;
      final vB = i < partsB.length ? partsB[i] : 0;
      if (vA != vB) return vA.compareTo(vB);
    }
    return 0;
  }

  /// Resolves the optimal download asset for the current operating system and architecture.
  static ({String? url, String? name, int? size}) resolvePlatformAsset(List<dynamic> assets) {
    if (assets.isEmpty) return (url: null, name: null, size: null);

    final isMac = Platform.isMacOS;
    final isWin = Platform.isWindows;
    final isLinux = Platform.isLinux;

    final winArch = (Platform.environment['PROCESSOR_ARCHITECTURE'] ?? '').toLowerCase();
    final isWinArm = winArch.contains('arm') || Platform.version.toLowerCase().contains('arm');

    Map<String, dynamic>? candidate;

    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final name = (asset['name'] as String? ?? '').toLowerCase();

      if (isMac && (name.endsWith('.dmg') || name.endsWith('.zip')) && name.contains('macos')) {
        candidate = asset;
        break;
      } else if (isWin) {
        if (isWinArm && name.contains('windows-arm64') && name.endsWith('.zip')) {
          candidate = asset;
          break;
        } else if (!isWinArm && name.contains('windows-x64') && name.endsWith('.zip')) {
          candidate = asset;
          break;
        } else if (name.contains('windows') && (name.endsWith('.zip') || name.endsWith('.exe'))) {
          candidate ??= asset;
        }
      } else if (isLinux && (name.endsWith('.tar.gz') || name.endsWith('.appimage')) && name.contains('linux')) {
        candidate = asset;
        break;
      }
    }

    // Fallback if no architecture-specific asset was matched
    if (candidate == null) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (isMac && name.endsWith('.dmg')) candidate = asset;
        if (isWin && name.endsWith('.zip')) candidate = asset;
        if (isLinux && name.endsWith('.tar.gz')) candidate = asset;
      }
    }

    if (candidate != null) {
      return (
        url: candidate['browser_download_url'] as String?,
        name: candidate['name'] as String?,
        size: candidate['size'] as int?,
      );
    }

    return (url: null, name: null, size: null);
  }

  /// Checks GitHub Releases for new versions.
  /// [isManual] indicates user clicked "Check for Updates" manually.
  Future<UpdateInfo> checkUpdate({
    required String currentVersion,
    bool isManual = false,
  }) async {
    final prefs = PreferencesService.loadSync();
    final autoCheck = prefs[prefAutoCheck] as bool? ?? true;
    final lastCheckMs = (prefs[prefLastCheckTime] as num?)?.toInt() ?? 0;
    final ignoredVersion = prefs[prefIgnoredVersion] as String?;

    final now = DateTime.now();

    // In automatic mode, respect the user's toggle and 24-hour rate limiting
    if (!isManual) {
      if (!autoCheck) {
        return UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          title: '',
          releaseNotes: '',
          htmlUrl: '',
          hasUpdate: false,
        );
      }

      final elapsed = now.millisecondsSinceEpoch - lastCheckMs;
      if (elapsed < checkCooldown.inMilliseconds && lastCheckMs > 0) {
        return UpdateInfo(
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          title: '',
          releaseNotes: '',
          htmlUrl: '',
          hasUpdate: false,
        );
      }
    }

    // Persist check time
    await PreferencesService.saveKey(prefLastCheckTime, now.millisecondsSinceEpoch);

    final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, 'SuperGoodViewer/$currentVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github.v3+json');

      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('GitHub API returned status code ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final data = json.decode(body) as Map<String, dynamic>;

      final rawTagName = data['tag_name'] as String? ?? '';
      final latestVersion = rawTagName.replaceFirst(RegExp(r'^v', caseSensitive: false), '').trim();
      final title = data['name'] as String? ?? rawTagName;
      final releaseNotes = data['body'] as String? ?? '';
      final htmlUrl = data['html_url'] as String? ?? 'https://github.com/$repoOwner/$repoName/releases';
      final publishedStr = data['published_at'] as String?;
      final publishedAt = publishedStr != null ? DateTime.tryParse(publishedStr) : null;
      final assets = data['assets'] as List<dynamic>? ?? [];

      final platformAsset = resolvePlatformAsset(assets);

      final isNewer = compareSemVer(latestVersion, currentVersion) > 0;
      final isIgnored = (!isManual && ignoredVersion != null && compareSemVer(latestVersion, ignoredVersion) == 0);

      final hasUpdate = isNewer && !isIgnored;

      return UpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        title: title,
        releaseNotes: releaseNotes,
        htmlUrl: htmlUrl,
        assetUrl: platformAsset.url,
        assetName: platformAsset.name,
        assetSizeBytes: platformAsset.size,
        publishedAt: publishedAt,
        hasUpdate: hasUpdate,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Sets the version to ignore during automatic background checks.
  Future<void> ignoreVersion(String version) async {
    await PreferencesService.saveKey(prefIgnoredVersion, version);
  }

  /// Downloads the update asset from [url] into a temporary file.
  Future<String> downloadUpdateAsset(
    String url,
    String targetFileName, {
    required void Function(int received, int total) onProgress,
    UpdateCancellationToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw UpdateCancelledException('Update download was cancelled before starting');
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);

    final tempDir = Directory.systemTemp.createTempSync('sgv_download_');
    final targetFile = File(p.join(tempDir.path, targetFileName));
    final sink = targetFile.openWrite();

    HttpClientRequest? currentRequest;
    StreamSubscription<List<int>>? subscription;
    final completer = Completer<void>();
    completer.future.ignore(); // Prevent unhandled exception if completed with error before await

    void onCancel() {
      try {
        currentRequest?.abort();
      } catch (_) {}
      try {
        subscription?.cancel();
      } catch (_) {}
      try {
        client.close(force: true);
      } catch (_) {}
      if (!completer.isCompleted) {
        completer.completeError(UpdateCancelledException('Update download was cancelled'));
      }
    }

    cancelToken?.addListener(onCancel);

    try {
      if (cancelToken?.isCancelled == true) {
        throw UpdateCancelledException('Update download was cancelled');
      }

      final request = await client.getUrl(Uri.parse(url));
      currentRequest = request;
      request.headers.set(HttpHeaders.userAgentHeader, 'SuperGoodViewer-Updater');

      if (cancelToken?.isCancelled == true) {
        throw UpdateCancelledException('Update download was cancelled');
      }

      final response = await request.close();

      if (cancelToken?.isCancelled == true) {
        throw UpdateCancelledException('Update download was cancelled');
      }

      if (response.statusCode != 200) {
        throw HttpException('Failed to download update, server responded with ${response.statusCode}');
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      subscription = response.listen(
        (chunk) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          onProgress(receivedBytes, totalBytes);
        },
        onError: (e, st) {
          if (!completer.isCompleted) {
            if (cancelToken?.isCancelled == true) {
              completer.completeError(UpdateCancelledException('Update download was cancelled'));
            } else {
              completer.completeError(e, st);
            }
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        cancelOnError: true,
      );

      await completer.future;

      await sink.flush();
      await sink.close();
      return targetFile.path;
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      try {
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
      } catch (_) {}
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
      if (cancelToken?.isCancelled == true) {
        throw UpdateCancelledException('Update download was cancelled');
      }
      rethrow;
    } finally {
      cancelToken?.removeListener(onCancel);
      client.close(force: true);
    }
  }

  /// Resolves the running .app bundle path on macOS (e.g. /Applications/SuperGoodViewer.app).
  static String? resolveMacOSAppBundlePath() {
    if (!Platform.isMacOS) return null;
    var current = Directory(Platform.resolvedExecutable);
    while (current.path != '/' && current.path != '.') {
      if (current.path.endsWith('.app')) {
        return current.path;
      }
      current = current.parent;
    }
    return null;
  }

  /// Performs in-place atomic update and restarts the application across macOS, Windows, and Linux.
  Future<void> installAndRestart({
    required String downloadedFilePath,
  }) async {
    if (Platform.isMacOS) {
      await _installAndRestartMacOS(downloadedFilePath);
    } else if (Platform.isWindows) {
      await _installAndRestartWindows(downloadedFilePath);
    } else if (Platform.isLinux) {
      await _installAndRestartLinux(downloadedFilePath);
    }
  }

  @visibleForTesting
  static String buildMacOSUpdateScript({
    required int currentPid,
    required String targetAppPath,
    required String stagedAppPath,
    required String stagingDirPath,
  }) {
    return '''
while kill -0 $currentPid 2>/dev/null; do sleep 0.1; done
BACKUP_APP="$targetAppPath.backup.\$\$"
BACKUP_CREATED=0

if [ -d "$targetAppPath" ]; then
  if mv "$targetAppPath" "\$BACKUP_APP"; then
    BACKUP_CREATED=1
  else
    rm -rf "\$BACKUP_APP"
    if [ -d "$targetAppPath" ]; then
      open "$targetAppPath"
    fi
    rm -rf "$stagingDirPath"
    exit 1
  fi
fi

if mv "$stagedAppPath" "$targetAppPath"; then
  if [ \$BACKUP_CREATED -eq 1 ]; then
    rm -rf "\$BACKUP_APP"
  fi
  open "$targetAppPath"
  rm -rf "$stagingDirPath"
else
  rm -rf "$targetAppPath"
  if [ \$BACKUP_CREATED -eq 1 ] && [ -d "\$BACKUP_APP" ]; then
    if mv "\$BACKUP_APP" "$targetAppPath"; then
      open "$targetAppPath"
    fi
  fi
  rm -rf "$stagingDirPath"
  exit 1
fi
''';
  }

  @visibleForTesting
  static String buildLinuxUpdateScript({
    required int currentPid,
    required String exePath,
    required String appDir,
    required String stagingDirPath,
  }) {
    return '''
while kill -0 $currentPid 2>/dev/null; do sleep 0.1; done
set -e
if cp -rf "$stagingDirPath"/* "$appDir"/; then
  TARGET_EXE="$appDir/supergoodviewer"
  if [ ! -f "\$TARGET_EXE" ]; then
    TARGET_EXE="$exePath"
  fi
  chmod +x "\$TARGET_EXE"
  if [ "$exePath" != "\$TARGET_EXE" ] && [ -x "\$TARGET_EXE" ] && [ -f "$exePath" ]; then
    rm -f "$exePath"
  fi
  "\$TARGET_EXE" &
  rm -rf "$stagingDirPath"
else
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  rm -rf "$stagingDirPath"
  exit 1
fi
''';
  }

  Future<void> _installAndRestartMacOS(String dmgPath) async {
    final appPath = resolveMacOSAppBundlePath();
    final targetAppPath = (appPath != null && !appPath.startsWith('/Volumes/'))
        ? appPath
        : '/Applications/SuperGoodViewer.app';

    final tempMountDir = Directory.systemTemp.createTempSync('sgv_mount_');
    final stagingDir = Directory.systemTemp.createTempSync('sgv_staging_');

    try {
      // 1. Mount DMG silently without Finder browser window
      final attachResult = await Process.run('hdiutil', [
        'attach',
        dmgPath,
        '-nobrowse',
        '-mountpoint',
        tempMountDir.path,
      ]);

      if (attachResult.exitCode != 0) {
        throw Exception('Failed to attach update disk image: ${attachResult.stderr}');
      }

      // 2. Locate SuperGoodViewer.app inside mounted DMG
      final sourceApp = Directory(p.join(tempMountDir.path, 'SuperGoodViewer.app'));
      if (!sourceApp.existsSync()) {
        await Process.run('hdiutil', ['detach', tempMountDir.path, '-force']);
        throw Exception('SuperGoodViewer.app not found inside DMG payload');
      }

      // 3. Copy to staging directory
      final stagedAppPath = p.join(stagingDir.path, 'SuperGoodViewer.app');
      final cpResult = await Process.run('cp', ['-R', sourceApp.path, stagedAppPath]);
      if (cpResult.exitCode != 0) {
        throw Exception('Failed to stage update files: ${cpResult.stderr}');
      }

      // 4. Detach DMG and cleanup mount point
      await Process.run('hdiutil', ['detach', tempMountDir.path, '-force']);
      try {
        if (tempMountDir.existsSync()) {
          tempMountDir.deleteSync(recursive: true);
        }
      } catch (_) {}

      // 5. Strip quarantine attribute to avoid Gatekeeper warning
      await Process.run('xattr', ['-cr', stagedAppPath]);

      // 6. Spawn detached shell script to wait for old PID, backup, replace, and relaunch
      final currentPid = pid;
      final script = buildMacOSUpdateScript(
        currentPid: currentPid,
        targetAppPath: targetAppPath,
        stagedAppPath: stagedAppPath,
        stagingDirPath: stagingDir.path,
      );

      await Process.start(
        '/bin/sh',
        ['-c', script],
        mode: ProcessStartMode.detached,
      );

      // 7. Exit current instance cleanly
      exit(0);
    } catch (e) {
      try {
        await Process.run('hdiutil', ['detach', tempMountDir.path, '-force']);
      } catch (_) {}
      try {
        if (tempMountDir.existsSync()) {
          tempMountDir.deleteSync(recursive: true);
        }
      } catch (_) {}
      try {
        if (stagingDir.existsSync()) {
          stagingDir.deleteSync(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _installAndRestartWindows(String zipPath) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final stagingDir = Directory.systemTemp.createTempSync('sgv_staging_');

    try {
      // Extract zip via PowerShell Expand-Archive
      final extractResult = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        'Expand-Archive -Path "$zipPath" -DestinationPath "${stagingDir.path}" -Force',
      ]);

      if (extractResult.exitCode != 0) {
        throw Exception('Failed to extract Windows update package: ${extractResult.stderr}');
      }

      // Spawn detached powershell to wait for old PID, replace, and restart
      final currentPid = pid;
      final psCommand =
          'Wait-Process -Id $currentPid -ErrorAction SilentlyContinue; '
          'Start-Sleep -Milliseconds 200; '
          'Copy-Item -Path "${stagingDir.path}\\*" -Destination "$appDir" -Recurse -Force; '
          'Start-Process "$appDir\\SuperGoodViewer.exe"; '
          'Remove-Item "${stagingDir.path}" -Recurse -Force';

      await Process.start(
        'powershell',
        ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', psCommand],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      try {
        if (stagingDir.existsSync()) {
          stagingDir.deleteSync(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _installAndRestartLinux(String tarGzPath) async {
    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final stagingDir = Directory.systemTemp.createTempSync('sgv_staging_');

    try {
      // Extract tar.gz
      final tarResult = await Process.run('tar', [
        '-xzf',
        tarGzPath,
        '-C',
        stagingDir.path,
      ]);

      if (tarResult.exitCode != 0) {
        throw Exception('Failed to extract Linux update package: ${tarResult.stderr}');
      }

      final currentPid = pid;
      final script = buildLinuxUpdateScript(
        currentPid: currentPid,
        exePath: exePath,
        appDir: appDir,
        stagingDirPath: stagingDir.path,
      );

      await Process.start(
        '/bin/sh',
        ['-c', script],
        mode: ProcessStartMode.detached,
      );

      exit(0);
    } catch (e) {
      try {
        if (stagingDir.existsSync()) {
          stagingDir.deleteSync(recursive: true);
        }
      } catch (_) {}
      rethrow;
    }
  }
}

/// Exception thrown when an update download is cancelled by the user.
class UpdateCancelledException implements Exception {
  final String message;
  UpdateCancelledException([this.message = 'Update download cancelled']);

  @override
  String toString() => message;
}

/// Token used to cancel in-flight update downloads.
class UpdateCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}
