import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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

  /// Checks whether an updater process is alive, guarding against PID <= 1 and PID reuse.
  @visibleForTesting
  static bool isUpdaterProcessAlive(
    int? pid, {
    List<String>? expectedAppDirs,
  }) {
    if (pid == null || pid <= 1) return false;
    try {
      final res = Process.runSync('kill', ['-0', '$pid']);
      if (res.exitCode != 0) return false;
    } catch (_) {
      return false;
    }
    if (Platform.isLinux) {
      try {
        final cmdlineFile = File('/proc/$pid/cmdline');
        if (cmdlineFile.existsSync()) {
          final content = cmdlineFile.readAsStringSync().toLowerCase();
          final dirsToCheck = expectedAppDirs ?? const <String>[];
          final matchesApp = dirsToCheck.isEmpty ||
              dirsToCheck.any((d) => content.contains(d.toLowerCase()));
          final matchesBinary = content.contains('supergoodviewer') || content.contains('sogoodviewer');
          if (!matchesApp || !matchesBinary) {
            return false;
          }
        }
      } catch (_) {}
    }
    return true;
  }

  /// Asynchronously cleans up stale update artifacts off the main UI isolate.
  static Future<void> cleanupStaleUpdateArtifactsAsync({String? targetAppDirPath}) async {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      final appDirPath = targetAppDirPath ?? File(Platform.resolvedExecutable).parent.path;
      await Isolate.run(() {
        cleanupStaleUpdateArtifacts(targetAppDir: Directory(appDirPath));
      });
    } catch (_) {}
  }

  /// Cleans up any stale update artifacts or recovers interrupted updates left behind by previous runs.
  static void cleanupStaleUpdateArtifacts({Directory? targetAppDir}) {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      final appDir = targetAppDir ?? Directory(File(Platform.resolvedExecutable).parent.path);
      if (!appDir.existsSync()) return;

      String realAppDirPath;
      try {
        realAppDirPath = appDir.resolveSymbolicLinksSync();
      } catch (_) {
        realAppDirPath = p.canonicalize(appDir.path);
      }

      // 1. Check for journal recovery
      String? activeBackupDirPath;
      String? activeInstalledListPath;
      String? realBackupDirPath;
      String? realInstalledListPath;

      final journalFile = File('${appDir.path}/.sgv_journal');
      if (journalFile.existsSync()) {
        try {
          int? journalPid;
          String? rawBackupDir;
          String? rawInstalledList;
          bool isCommitted = false;

          final lines = journalFile.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('PID=')) {
              final val = trimmed.substring(4).trim();
              if (RegExp(r'^[1-9]\d{0,8}$').hasMatch(val)) {
                final parsed = int.tryParse(val);
                if (parsed != null && parsed > 1) {
                  journalPid = parsed;
                }
              }
            } else if (trimmed.startsWith('BACKUP_DIR=')) {
              rawBackupDir = trimmed.substring(11).trim();
            } else if (trimmed.startsWith('INSTALLED_LIST=')) {
              rawInstalledList = trimmed.substring(15).trim();
            } else if (trimmed == 'STATUS=COMMITTED' ||
                trimmed == 'COMMITTED=1' ||
                (trimmed.startsWith('STATUS=') && trimmed.substring(7).trim() == 'COMMITTED')) {
              isCommitted = true;
            } else if (rawBackupDir == null && trimmed.startsWith('/') && !trimmed.contains('=')) {
              // Legacy format: single-line absolute path
              rawBackupDir = trimmed;
            }
          }

          // Validate containment inside appDir
          String? backupDirPath;
          final bPath = rawBackupDir;
          if (bPath != null) {
            final bName = p.basename(bPath);
            final bParent = p.dirname(bPath);
            String? bParentReal;
            try {
              bParentReal = Directory(bParent).resolveSymbolicLinksSync();
            } catch (_) {
              bParentReal = p.canonicalize(bParent);
            }
            if (!RegExp(r'^\.sgv_backup\.\d+$').hasMatch(bName) ||
                Link(bPath).existsSync() ||
                (bParentReal != realAppDirPath && bParentReal != p.canonicalize(appDir.path))) {
              backupDirPath = null;
            } else {
              try {
                final resolved = Directory(bPath).resolveSymbolicLinksSync();
                if (resolved == p.join(realAppDirPath, bName)) {
                  realBackupDirPath = resolved;
                  backupDirPath = bPath;
                } else {
                  backupDirPath = null;
                }
              } catch (_) {
                if (bParentReal == realAppDirPath || bParentReal == p.canonicalize(appDir.path)) {
                  realBackupDirPath = p.join(realAppDirPath, bName);
                  backupDirPath = bPath;
                } else {
                  backupDirPath = null;
                }
              }
            }
          }

          if (journalPid == null && backupDirPath != null) {
            final ext = backupDirPath.split('.').last;
            if (RegExp(r'^[1-9]\d{0,8}$').hasMatch(ext)) {
              final parsed = int.tryParse(ext);
              if (parsed != null && parsed > 1) {
                journalPid = parsed;
              }
            }
          }
          String? installedListPath = rawInstalledList;
          if (installedListPath == null && journalPid != null) {
            final candidate = '${appDir.path}/.sgv_installed.$journalPid';
            if (File(candidate).existsSync() && !Link(candidate).existsSync()) {
              installedListPath = candidate;
            }
          }

          final iPath = installedListPath;
          if (iPath != null) {
            final iName = p.basename(iPath);
            final iParent = p.dirname(iPath);
            String? iParentReal;
            try {
              iParentReal = Directory(iParent).resolveSymbolicLinksSync();
            } catch (_) {
              iParentReal = p.canonicalize(iParent);
            }
            if (!RegExp(r'^\.sgv_installed\.\d+$').hasMatch(iName) ||
                Link(iPath).existsSync() ||
                (iParentReal != realAppDirPath && iParentReal != p.canonicalize(appDir.path))) {
              installedListPath = null;
            } else {
              try {
                final resolved = File(iPath).resolveSymbolicLinksSync();
                if (resolved == p.join(realAppDirPath, iName)) {
                  realInstalledListPath = resolved;
                } else {
                  installedListPath = null;
                }
              } catch (_) {
                if (iParentReal == realAppDirPath || iParentReal == p.canonicalize(appDir.path)) {
                  realInstalledListPath = p.join(realAppDirPath, iName);
                } else {
                  installedListPath = null;
                }
              }
            }
          }

          final isUpdaterAlive = isUpdaterProcessAlive(
            journalPid,
            expectedAppDirs: [appDir.path, realAppDirPath],
          );

          if (isUpdaterAlive) {
            // Updater is currently active! Do not touch its backup or installed files.
            activeBackupDirPath = backupDirPath;
            activeInstalledListPath = installedListPath;
          } else {
            // Updater process is dead or absent; attempt recovery or residue cleanup.
            if (isCommitted) {
              // Transaction committed: app payload is complete and verified.
              // Clean up residual backup directory and temporary lists without rolling back.
              if (backupDirPath != null) {
                try {
                  final bDir = Directory(backupDirPath);
                  if (bDir.existsSync()) bDir.deleteSync(recursive: true);
                } catch (_) {}
              }
              if (installedListPath != null) {
                try {
                  final iFile = File(installedListPath);
                  if (iFile.existsSync()) iFile.deleteSync();
                } catch (_) {}
              }
              try {
                journalFile.deleteSync();
              } catch (_) {}
              activeBackupDirPath = null;
              realBackupDirPath = null;
              activeInstalledListPath = null;
              realInstalledListPath = null;
            } else if (backupDirPath != null) {
              final backupDir = Directory(backupDirPath);
              if (backupDir.existsSync()) {
                // Only delete partially installed new files recorded in the paired INSTALLED_LIST
                if (installedListPath != null && File(installedListPath).existsSync()) {
                  try {
                    final installedFile = File(installedListPath);
                    final remainingLines = <String>[];
                    for (final line in installedFile.readAsLinesSync()) {
                      final trimmed = line.trim();
                      if (trimmed.isEmpty || p.isAbsolute(trimmed)) {
                        continue;
                      }
                      final normalized = p.normalize(trimmed);
                      final segments = p.split(normalized).where((s) => s.isNotEmpty).toList();
                      if (normalized == '.' ||
                          segments.isEmpty ||
                          segments.any((s) => s == '.' || s == '..')) {
                        continue;
                      }
                      final targetPath = p.join(appDir.path, normalized);
                      final parentDir = Directory(p.dirname(targetPath));
                      if (!parentDir.existsSync()) {
                        continue;
                      }
                      String parentReal;
                      try {
                        parentReal = parentDir.resolveSymbolicLinksSync();
                      } catch (_) {
                        continue;
                      }
                      if (parentReal != realAppDirPath && !p.isWithin(realAppDirPath, parentReal)) {
                        continue;
                      }
                      final link = Link(targetPath);
                      if (link.existsSync()) {
                        try {
                          link.deleteSync();
                        } catch (_) {}
                      } else {
                        final dir = Directory(targetPath);
                        if (dir.existsSync()) {
                          try {
                            dir.deleteSync(recursive: true);
                          } catch (_) {}
                          if (!link.existsSync() && dir.existsSync()) {
                            try {
                              Process.runSync('chmod', ['-R', 'u+rwx', targetPath]);
                            } catch (_) {}
                            try {
                              dir.deleteSync(recursive: true);
                            } catch (_) {}
                            if (dir.existsSync()) {
                              try {
                                Process.runSync('rm', ['-rf', targetPath]);
                              } catch (_) {}
                            }
                          }
                        } else {
                          final file = File(targetPath);
                          if (file.existsSync()) {
                            try {
                              file.deleteSync();
                            } catch (_) {}
                          }
                        }
                      }
                      if (link.existsSync() ||
                          Directory(targetPath).existsSync() ||
                          File(targetPath).existsSync()) {
                        remainingLines.add(line);
                      }
                    }
                    installedFile.writeAsStringSync(
                        remainingLines.isEmpty ? '' : '${remainingLines.join('\n')}\n');
                  } catch (_) {}
                }

                bool allRestored = true;
                for (final entity in backupDir.listSync()) {
                  final segs = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
                  if (segs.isNotEmpty) {
                    final name = segs.last;
                    if (name == '.' || name == '..' || name.isEmpty) {
                      continue;
                    }
                    final targetPath = '${appDir.path}/$name';
                    try {
                      final targetLink = Link(targetPath);
                      if (targetLink.existsSync()) {
                        targetLink.deleteSync();
                      } else {
                        final targetDir = Directory(targetPath);
                        if (targetDir.existsSync()) {
                          try {
                            targetDir.deleteSync(recursive: true);
                          } catch (_) {}
                          if (!targetLink.existsSync() && targetDir.existsSync()) {
                            try {
                              Process.runSync('chmod', ['-R', 'u+rwx', targetPath]);
                            } catch (_) {}
                            try {
                              targetDir.deleteSync(recursive: true);
                            } catch (_) {}
                            if (targetDir.existsSync()) {
                              try {
                                Process.runSync('rm', ['-rf', targetPath]);
                              } catch (_) {}
                            }
                          }
                        } else {
                          final targetFile = File(targetPath);
                          if (targetFile.existsSync()) {
                            try {
                              targetFile.deleteSync();
                            } catch (_) {}
                          }
                        }
                      }
                      if (targetLink.existsSync() ||
                          Directory(targetPath).existsSync() ||
                          File(targetPath).existsSync()) {
                        allRestored = false;
                        continue;
                      }
                      final mvRes = Process.runSync('mv', [entity.path, targetPath]);
                      if (mvRes.exitCode != 0) {
                        allRestored = false;
                      } else {
                        if (installedListPath != null && File(installedListPath).existsSync()) {
                          try {
                            final iFile = File(installedListPath);
                            final curLines =
                                iFile.readAsLinesSync().where((l) => l.trim() != name).toList();
                            iFile.writeAsStringSync(
                                curLines.isEmpty ? '' : '${curLines.join('\n')}\n');
                          } catch (_) {}
                        }
                      }
                    } catch (_) {
                      allRestored = false;
                    }
                  }
                }
                if (allRestored) {
                  try {
                    backupDir.deleteSync(recursive: true);
                  } catch (_) {}
                  try {
                    journalFile.deleteSync();
                  } catch (_) {}
                  if (installedListPath != null) {
                    try {
                      final f = File(installedListPath);
                      if (f.existsSync()) f.deleteSync();
                    } catch (_) {}
                  }
                  activeBackupDirPath = null;
                  realBackupDirPath = null;
                  activeInstalledListPath = null;
                  realInstalledListPath = null;
                } else {
                  // Recovery failed: preserve backupDir, journalFile, and installedListPath
                  activeBackupDirPath = backupDirPath;
                  activeInstalledListPath = installedListPath;
                }
              } else {
                // Dangling journal: backupDir does not exist and updater is dead.
                try {
                  journalFile.deleteSync();
                } catch (_) {}
                if (installedListPath != null) {
                  try {
                    final f = File(installedListPath);
                    if (f.existsSync()) f.deleteSync();
                  } catch (_) {}
                }
              }
            } else {
              // Dangling empty/corrupt journal with no backup path
              try {
                journalFile.deleteSync();
              } catch (_) {}
              if (installedListPath != null) {
                try {
                  final f = File(installedListPath);
                  if (f.existsSync()) f.deleteSync();
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      // 2. Sweep stale artifacts from dead processes
      for (final entity in appDir.listSync()) {
        final segs = entity.uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segs.isEmpty) continue;
        final name = segs.last;
        if (name.startsWith('.sgv_new.') ||
            name.startsWith('.sgv_backup.') ||
            name.startsWith('.sgv_installed.') ||
            name.startsWith('.sgv_manifest.') ||
            name.startsWith('.sgv_prune.') ||
            name.startsWith('.sgv_journal.tmp.') ||
            name.startsWith('.sgv_journal.commit.')) {
          String realEntityPath;
          try {
            realEntityPath = entity.resolveSymbolicLinksSync();
          } catch (_) {
            realEntityPath = p.canonicalize(entity.path);
          }

          if ((realBackupDirPath != null && realEntityPath == realBackupDirPath) ||
              (activeBackupDirPath != null &&
                  (entity.path == activeBackupDirPath ||
                      p.canonicalize(entity.path) == p.canonicalize(activeBackupDirPath)))) {
            continue;
          }
          if ((realInstalledListPath != null && realEntityPath == realInstalledListPath) ||
              (activeInstalledListPath != null &&
                  (entity.path == activeInstalledListPath ||
                      p.canonicalize(entity.path) == p.canonicalize(activeInstalledListPath)))) {
            continue;
          }

          final pidStr = name.split('.').last;
          final pid = int.tryParse(pidStr);
          if (pid != null &&
              isUpdaterProcessAlive(
                pid,
                expectedAppDirs: [appDir.path, realAppDirPath],
              )) {
            continue;
          }

          try {
            entity.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
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

LOG_FILE=""
for candidate_dir in "\${XDG_STATE_HOME:-\$HOME/.local/state}/supergoodviewer" "\${XDG_CACHE_HOME:-\$HOME/.cache}/supergoodviewer" "/tmp"; do
  if mkdir -p "\$candidate_dir" 2>/dev/null && [ -w "\$candidate_dir" ]; then
    candidate_file="\$candidate_dir/supergoodviewer_update.log"
    if touch "\$candidate_file" 2>/dev/null && [ -w "\$candidate_file" ]; then
      LOG_FILE="\$candidate_file"
      break
    fi
    candidate_file="\$candidate_dir/supergoodviewer_update_\${USER:-\$(id -u 2>/dev/null || echo \$\$)}.log"
    if touch "\$candidate_file" 2>/dev/null && [ -w "\$candidate_file" ]; then
      LOG_FILE="\$candidate_file"
      break
    fi
  fi
done

log() {
  if [ -n "\$LOG_FILE" ]; then
    echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" >> "\$LOG_FILE" 2>/dev/null || true
  fi
  echo "\$*" >&2
}

notify_error() {
  log "Critical: \$*"
  command -v notify-send >/dev/null 2>&1 && notify-send -u critical "SuperGoodViewer Update" "\$*" 2>/dev/null || true
}

cleanup_staging_payload() {
  rm -rf "$stagingDirPath"
}

# 1. Pre-flight payload validation
if [ ! -f "$stagingDirPath/supergoodviewer" ] && [ ! -L "$stagingDirPath/supergoodviewer" ]; then
  log "Error: Update payload missing supergoodviewer executable"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
fi

# 2. Pre-flight disk space check
REQUIRED_KB=\$(du -sk "$stagingDirPath" 2>/dev/null | awk '{print \$1}')
if [ -n "\$REQUIRED_KB" ] && [ "\$REQUIRED_KB" -gt 0 ] 2>/dev/null; then
  AVAIL_KB=\$(df -k -P "$appDir" 2>/dev/null | awk 'NR==2 {print \$4}')
  NEEDED_KB=\$(( REQUIRED_KB * 2 + 10240 ))
  if [ -n "\$AVAIL_KB" ] && [ "\$AVAIL_KB" -lt "\$NEEDED_KB" ] 2>/dev/null; then
    log "Error: Insufficient disk space in $appDir. Required: \${NEEDED_KB}KB, Available: \${AVAIL_KB}KB"
    cleanup_staging_payload
    if [ -x "$exePath" ]; then
      "$exePath" &
    fi
    exit 1
  fi
fi

# 3. Check for previous unfinished update journal and recover before starting new update
REAL_APP_DIR="\$(cd "$appDir" 2>/dev/null && pwd -P)"
if [ -f "$appDir/.sgv_journal" ]; then
  PREV_PID=""
  PREV_BACKUP=""
  PREV_INSTALLED=""
  PREV_COMMITTED=0
  while IFS='=' read -r key val || [ -n "\$key" ]; do
    case "\$key" in
      PID)
        case "\$val" in
          *[!0-9]* | "" | 0* | 1) ;;
          [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
          *) PREV_PID="\$val" ;;
        esac
        ;;
      BACKUP_DIR) PREV_BACKUP="\$val" ;;
      INSTALLED_LIST) PREV_INSTALLED="\$val" ;;
      STATUS)
        [ "\$val" = "COMMITTED" ] && PREV_COMMITTED=1
        ;;
      COMMITTED)
        [ "\$val" = "1" ] && PREV_COMMITTED=1
        ;;
      /*)
        if [ -z "\$PREV_BACKUP" ] && [ -z "\$val" ]; then
          PREV_BACKUP="\$key"
        fi
        ;;
    esac
  done < "$appDir/.sgv_journal"

  # Validate that PREV_BACKUP is a legitimate direct entry inside appDir
  case "\$PREV_BACKUP" in
    /*)
      b_name="\${PREV_BACKUP##*/}"
      b_parent="\${PREV_BACKUP%/*}"
      [ -z "\$b_parent" ] && b_parent="/"
      b_parent_real="\$(cd "\$b_parent" 2>/dev/null && pwd -P)" || b_parent_real=""
      case "\$b_name" in
        .sgv_backup.*[!0-9]* | .sgv_backup.) PREV_BACKUP="" ;;
        .sgv_backup.[0-9]*) ;;
        *) PREV_BACKUP="" ;;
      esac
      if [ -n "\$PREV_BACKUP" ]; then
        if [ "\$b_parent_real" != "\$REAL_APP_DIR" ] || [ -L "\$PREV_BACKUP" ]; then
          PREV_BACKUP=""
        elif [ -d "\$PREV_BACKUP" ]; then
          b_real="\$(cd "\$PREV_BACKUP" 2>/dev/null && pwd -P)" || b_real=""
          if [ "\$b_real" != "\$REAL_APP_DIR/\$b_name" ]; then
            PREV_BACKUP=""
          fi
        fi
      fi
      ;;
    *)
      PREV_BACKUP=""
      ;;
  esac

  # Validate that PREV_INSTALLED is a legitimate direct file inside appDir
  case "\$PREV_INSTALLED" in
    /*)
      i_name="\${PREV_INSTALLED##*/}"
      i_parent="\${PREV_INSTALLED%/*}"
      [ -z "\$i_parent" ] && i_parent="/"
      i_parent_real="\$(cd "\$i_parent" 2>/dev/null && pwd -P)" || i_parent_real=""
      case "\$i_name" in
        .sgv_installed.*[!0-9]* | .sgv_installed.) PREV_INSTALLED="" ;;
        .sgv_installed.[0-9]*) ;;
        *) PREV_INSTALLED="" ;;
      esac
      if [ -n "\$PREV_INSTALLED" ]; then
        if [ "\$i_parent_real" != "\$REAL_APP_DIR" ] || [ -L "\$PREV_INSTALLED" ]; then
          PREV_INSTALLED=""
        elif [ -e "\$PREV_INSTALLED" ] && [ ! -f "\$PREV_INSTALLED" ]; then
          PREV_INSTALLED=""
        fi
      fi
      ;;
    *)
      PREV_INSTALLED=""
      ;;
  esac


  if [ -z "\$PREV_PID" ] && [ -n "\$PREV_BACKUP" ]; then
    b_ext="\${PREV_BACKUP##*.}"
    case "\$b_ext" in
      *[!0-9]* | "" | 0* | 1) ;;
      [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*) ;;
      *) PREV_PID="\$b_ext" ;;
    esac
  fi
  if [ -z "\$PREV_INSTALLED" ] && [ -n "\$PREV_PID" ] && [ -f "$appDir/.sgv_installed.\$PREV_PID" ] && [ ! -L "$appDir/.sgv_installed.\$PREV_PID" ]; then
    PREV_INSTALLED="$appDir/.sgv_installed.\$PREV_PID"
  fi

  IS_PREV_ALIVE=0
  if [ -n "\$PREV_PID" ] && [ "\$PREV_PID" -gt 1 ] 2>/dev/null; then
    if kill -0 "\$PREV_PID" 2>/dev/null; then
      if [ -d "/proc/\$PREV_PID" ] && [ -f "/proc/\$PREV_PID/cmdline" ]; then
        if { grep -q -a -F "$appDir" "/proc/\$PREV_PID/cmdline" 2>/dev/null || \
             grep -q -a -F "\$REAL_APP_DIR" "/proc/\$PREV_PID/cmdline" 2>/dev/null; } && \
           grep -q -a -E "supergoodviewer|sogoodviewer" "/proc/\$PREV_PID/cmdline" 2>/dev/null; then
          IS_PREV_ALIVE=1
        fi
      else
        IS_PREV_ALIVE=1
      fi
    fi
  fi

  if [ \$IS_PREV_ALIVE -eq 1 ]; then
    log "Error: Another update process (\$PREV_PID) is currently active"
    cleanup_staging_payload
    if [ -x "$exePath" ]; then
      "$exePath" &
    fi
    exit 1
  fi

  if [ \$PREV_COMMITTED -eq 1 ]; then
    log "Notice: Found committed transaction from previous update, cleaning residues..."
    if [ -n "\$PREV_BACKUP" ] && [ -d "\$PREV_BACKUP" ]; then
      rm -rf "\$PREV_BACKUP" 2>/dev/null || true
    fi
    [ -n "\$PREV_INSTALLED" ] && rm -f "\$PREV_INSTALLED" 2>/dev/null || true
    rm -f "$appDir/.sgv_journal" 2>/dev/null || true
  elif [ -n "\$PREV_BACKUP" ] && [ -d "\$PREV_BACKUP" ]; then
    log "Notice: Found incomplete transaction from previous update, recovering..."
    if [ -n "\$PREV_INSTALLED" ] && [ -f "\$PREV_INSTALLED" ] && [ -n "\$REAL_APP_DIR" ]; then
      PREV_INST_TMP="\$PREV_INSTALLED.tmp.\$\$"
      : > "\$PREV_INST_TMP"
      while IFS= read -r n || [ -n "\$n" ]; do
        case "\$n" in
          "" | /* | . | .. | ./* | ../* | */. | */.. | */./* | */../* ) continue ;;
        esac
        target="$appDir/\$n"
        parent="\${target%/*}"
        [ -z "\$parent" ] && parent="$appDir"
        parent_real="\$(cd "\$parent" 2>/dev/null && pwd -P)" || continue
        case "\$parent_real" in
          "\$REAL_APP_DIR" | "\$REAL_APP_DIR"/*) ;;
          *) continue ;;
        esac
        if [ -L "\$target" ]; then
          rm -f "\$target" 2>/dev/null || true
        elif [ -d "\$target" ]; then
          rm -rf "\$target" 2>/dev/null || true
          if [ -d "\$target" ] && [ ! -L "\$target" ]; then
            chmod -R u+rwx "\$target" 2>/dev/null || true
            rm -rf "\$target" 2>/dev/null || true
          fi
        elif [ -e "\$target" ]; then
          rm -f "\$target" 2>/dev/null || true
        fi
        if [ -e "\$target" ] || [ -L "\$target" ]; then
          echo "\$n" >> "\$PREV_INST_TMP"
        fi
      done < "\$PREV_INSTALLED"
      mv -f "\$PREV_INST_TMP" "\$PREV_INSTALLED" 2>/dev/null || true
    fi
    PREV_FAILED=0
    for p in "\$PREV_BACKUP"/* "\$PREV_BACKUP"/.*; do
      n="\${p##*/}"
      if [ "\$n" = "." ] || [ "\$n" = ".." ] || [ "\$n" = "*" ] || { [ ! -e "\$p" ] && [ ! -L "\$p" ]; }; then
        continue
      fi
      if [ -L "$appDir/\$n" ]; then
        rm -f "$appDir/\$n" 2>/dev/null || true
      elif [ -d "$appDir/\$n" ]; then
        rm -rf "$appDir/\$n" 2>/dev/null || true
        if [ -d "$appDir/\$n" ] && [ ! -L "$appDir/\$n" ]; then
          chmod -R u+rwx "$appDir/\$n" 2>/dev/null || true
          rm -rf "$appDir/\$n" 2>/dev/null || true
        fi
      elif [ -e "$appDir/\$n" ]; then
        rm -f "$appDir/\$n" 2>/dev/null || true
      fi
      if [ -e "$appDir/\$n" ] || [ -L "$appDir/\$n" ]; then
        PREV_FAILED=1
        continue
      fi
      if mv "\$p" "$appDir/\$n" 2>/dev/null; then
        if [ -n "\$PREV_INSTALLED" ] && [ -f "\$PREV_INSTALLED" ]; then
          if grep -q -F -x "\$n" "\$PREV_INSTALLED" 2>/dev/null; then
            grep -v -F -x "\$n" "\$PREV_INSTALLED" > "\$PREV_INSTALLED.tmp.\$\$" 2>/dev/null && \
              mv -f "\$PREV_INSTALLED.tmp.\$\$" "\$PREV_INSTALLED" 2>/dev/null || \
              rm -f "\$PREV_INSTALLED.tmp.\$\$" 2>/dev/null
          fi
        fi
      else
        PREV_FAILED=1
      fi
    done
    if [ \$PREV_FAILED -eq 0 ]; then
      rm -rf "\$PREV_BACKUP" "$appDir/.sgv_journal"
      [ -n "\$PREV_INSTALLED" ] && rm -f "\$PREV_INSTALLED"
    else
      notify_error "Cannot start update: previous failed update at \$PREV_BACKUP could not be restored"
      cleanup_staging_payload
      if [ -x "$exePath" ]; then
        "$exePath" &
      fi
      exit 1
    fi
  else
    rm -f "$appDir/.sgv_journal"
    [ -n "\$PREV_INSTALLED" ] && rm -f "\$PREV_INSTALLED"
  fi
fi

# Clean up dead updater artifacts (only if owning PID is not running)
for d in "$appDir"/.sgv_new.* "$appDir"/.sgv_backup.* "$appDir"/.sgv_installed.* "$appDir"/.sgv_manifest.* "$appDir"/.sgv_prune.* "$appDir"/.sgv_journal.tmp.* "$appDir"/.sgv_journal.commit.*; do
  [ -e "\$d" ] || [ -L "\$d" ] || continue
  d_pid="\${d##*.}"
  IS_D_ALIVE=0
  if [ -n "\$d_pid" ] && [ "\$d_pid" -gt 1 ] 2>/dev/null; then
    if kill -0 "\$d_pid" 2>/dev/null; then
      if [ -d "/proc/\$d_pid" ] && [ -f "/proc/\$d_pid/cmdline" ]; then
        if { grep -q -a -F "$appDir" "/proc/\$d_pid/cmdline" 2>/dev/null || \
             grep -q -a -F "\$REAL_APP_DIR" "/proc/\$d_pid/cmdline" 2>/dev/null; } && \
           grep -q -a -E "supergoodviewer|sogoodviewer" "/proc/\$d_pid/cmdline" 2>/dev/null; then
          IS_D_ALIVE=1
        fi
      else
        IS_D_ALIVE=1
      fi
    fi
  fi
  if [ \$IS_D_ALIVE -eq 1 ]; then
    continue
  fi
  rm -rf "\$d"
done

# 4. Setup transaction staging and backup directories inside appDir
NEW_STAGING="$appDir/.sgv_new.\$\$"
BACKUP_DIR="$appDir/.sgv_backup.\$\$"
INSTALLED_LIST="$appDir/.sgv_installed.\$\$"
PRUNE_FILE="$appDir/.sgv_prune.\$\$"
JOURNAL_FILE="$appDir/.sgv_journal"
MANIFEST_FILE="$appDir/.sgv_manifest"

rollback() {
  trap '' HUP INT TERM
  log "Rolling back update..."
  ROLLBACK_FAILED=0
  if [ -f "\$INSTALLED_LIST" ] && [ -n "\$REAL_APP_DIR" ]; then
    ROLL_INST_TMP="\$INSTALLED_LIST.tmp.\$\$"
    : > "\$ROLL_INST_TMP"
    while IFS= read -r n || [ -n "\$n" ]; do
      case "\$n" in
        "" | /* | . | .. | ./* | ../* | */. | */.. | */./* | */../* ) continue ;;
      esac
      target="$appDir/\$n"
      parent="\${target%/*}"
      [ -z "\$parent" ] && parent="$appDir"
      parent_real="\$(cd "\$parent" 2>/dev/null && pwd -P)" || continue
      case "\$parent_real" in
        "\$REAL_APP_DIR" | "\$REAL_APP_DIR"/*) ;;
        *) continue ;;
      esac
      if [ -L "\$target" ]; then
        rm -f "\$target" 2>/dev/null || true
      elif [ -d "\$target" ]; then
        rm -rf "\$target" 2>/dev/null || true
        if [ -d "\$target" ] && [ ! -L "\$target" ]; then
          chmod -R u+rwx "\$target" 2>/dev/null || true
          rm -rf "\$target" 2>/dev/null || true
        fi
      elif [ -e "\$target" ]; then
        rm -f "\$target" 2>/dev/null || true
      fi
      if [ -e "\$target" ] || [ -L "\$target" ]; then
        echo "\$n" >> "\$ROLL_INST_TMP"
      fi
    done < "\$INSTALLED_LIST"
    mv -f "\$ROLL_INST_TMP" "\$INSTALLED_LIST" 2>/dev/null || true
  fi

  if [ -d "\$BACKUP_DIR" ]; then
    for p in "\$BACKUP_DIR"/* "\$BACKUP_DIR"/.*; do
      n="\${p##*/}"
      if [ "\$n" = "." ] || [ "\$n" = ".." ] || [ "\$n" = "*" ] || { [ ! -e "\$p" ] && [ ! -L "\$p" ]; }; then
        continue
      fi
      if [ -L "$appDir/\$n" ]; then
        rm -f "$appDir/\$n" 2>/dev/null || true
      elif [ -d "$appDir/\$n" ]; then
        rm -rf "$appDir/\$n" 2>/dev/null || true
        if [ -d "$appDir/\$n" ] && [ ! -L "$appDir/\$n" ]; then
          chmod -R u+rwx "$appDir/\$n" 2>/dev/null || true
          rm -rf "$appDir/\$n" 2>/dev/null || true
        fi
      elif [ -e "$appDir/\$n" ]; then
        rm -f "$appDir/\$n" 2>/dev/null || true
      fi
      if [ -e "$appDir/\$n" ] || [ -L "$appDir/\$n" ]; then
        notify_error "Failed to remove existing \$n in $appDir before rollback"
        ROLLBACK_FAILED=1
        continue
      fi
      if ! mv "\$p" "$appDir/\$n"; then
        notify_error "Failed to restore \$n to $appDir"
        ROLLBACK_FAILED=1
      else
        if [ -f "\$INSTALLED_LIST" ]; then
          if grep -q -F -x "\$n" "\$INSTALLED_LIST" 2>/dev/null; then
            grep -v -F -x "\$n" "\$INSTALLED_LIST" > "\$INSTALLED_LIST.tmp.\$\$" 2>/dev/null && \
              mv -f "\$INSTALLED_LIST.tmp.\$\$" "\$INSTALLED_LIST" 2>/dev/null || \
              rm -f "\$INSTALLED_LIST.tmp.\$\$" 2>/dev/null
          fi
        fi
      fi
    done
  fi

  if [ \$ROLLBACK_FAILED -eq 1 ]; then
    notify_error "Application rollback failed. Preserved backup directory: \$BACKUP_DIR"
  else
    rm -rf "\$BACKUP_DIR" "\$JOURNAL_FILE" "\$INSTALLED_LIST"
  fi

  rm -rf "\$NEW_STAGING" "\$PRUNE_FILE" "\$JOURNAL_FILE.tmp.\$\$" "\$JOURNAL_FILE.commit.\$\$"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
}

trap 'log "Interrupted by signal"; rollback' HUP INT TERM

if ! mkdir -p "\$NEW_STAGING"; then
  log "Error: Failed to create temporary staging directory inside $appDir"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
fi

if ! cp -a "$stagingDirPath/." "\$NEW_STAGING/"; then
  log "Error: Failed to stage update payload"
  rm -rf "\$NEW_STAGING"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
fi

if ! mkdir -p "\$BACKUP_DIR"; then
  log "Error: Failed to create temporary backup directory inside $appDir"
  rm -rf "\$NEW_STAGING"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
fi

JOURNAL_TMP="\$JOURNAL_FILE.tmp.\$\$"
{
  echo "PID=\$\$"
  echo "BACKUP_DIR=\$BACKUP_DIR"
  echo "INSTALLED_LIST=\$INSTALLED_LIST"
} > "\$JOURNAL_TMP"
if ! mv "\$JOURNAL_TMP" "\$JOURNAL_FILE"; then
  log "Error: Failed to write update journal file"
  rm -f "\$JOURNAL_TMP"
  rm -rf "\$NEW_STAGING" "\$BACKUP_DIR"
  cleanup_staging_payload
  if [ -x "$exePath" ]; then
    "$exePath" &
  fi
  exit 1
fi
: > "\$INSTALLED_LIST"
: > "\$PRUNE_FILE"

# 5. Prune obsolete bundle files based on manifest (or legacy sogoodviewer)
if [ -f "\$MANIFEST_FILE" ]; then
  while IFS= read -r item || [ -n "\$item" ]; do
    [ -z "\$item" ] && continue
    if [ ! -e "\$NEW_STAGING/\$item" ] && [ ! -L "\$NEW_STAGING/\$item" ]; then
      echo "\$item" >> "\$PRUNE_FILE"
    fi
  done < "\$MANIFEST_FILE"
else
  if [ ! -e "\$NEW_STAGING/sogoodviewer" ] && [ ! -L "\$NEW_STAGING/sogoodviewer" ]; then
    echo "sogoodviewer" >> "\$PRUNE_FILE"
  fi
fi

if [ -f "\$PRUNE_FILE" ]; then
  while IFS= read -r item || [ -n "\$item" ]; do
    [ -z "\$item" ] && continue
    if [ -e "$appDir/\$item" ] || [ -L "$appDir/\$item" ]; then
      if ! mv "$appDir/\$item" "\$BACKUP_DIR/\$item"; then
        log "Error: Failed to backup obsolete item \$item"
        rollback
      fi
    fi
  done < "\$PRUNE_FILE"
fi

# Ensure a runnable recovery entry point exists in $appDir/bin/sgv outside transaction replacement scope
if [ ! -x "$appDir/bin/sgv" ] && [ -f "\$NEW_STAGING/bin/sgv" ]; then
  mkdir -p "$appDir/bin" 2>/dev/null || true
  cp "\$NEW_STAGING/bin/sgv" "$appDir/bin/sgv" 2>/dev/null || true
  chmod +x "$appDir/bin/sgv" 2>/dev/null || true
fi

# 6. Phase 1: Backup existing entries that match new payload
for p in "\$NEW_STAGING"/* "\$NEW_STAGING"/.*; do
  n="\${p##*/}"
  if [ "\$n" = "." ] || [ "\$n" = ".." ] || [ "\$n" = "*" ] || { [ ! -e "\$p" ] && [ ! -L "\$p" ]; }; then
    continue
  fi
  if [ "\$n" = "bin" ]; then
    continue
  fi
  if [ -e "$appDir/\$n" ] || [ -L "$appDir/\$n" ]; then
    if ! mv "$appDir/\$n" "\$BACKUP_DIR/\$n"; then
      log "Error: Failed to backup \$n"
      rollback
    fi
  fi
done

# If supergoodviewer was moved to backup, retain an executable recovery entry stub
if [ -f "\$BACKUP_DIR/supergoodviewer" ] && [ ! -e "$appDir/supergoodviewer" ]; then
  cat << 'EOF' > "$appDir/supergoodviewer"
#!/bin/sh
APP_DIR="\$(cd "\$(dirname "\$0")" 2>/dev/null && pwd)"
if [ -x "\$APP_DIR/bin/sgv" ]; then
  exec "\$APP_DIR/bin/sgv" "\$@"
fi
if [ -f "\$APP_DIR/.sgv_journal" ]; then
  BACKUP=""
  while IFS='=' read -r k v || [ -n "\$k" ]; do
    [ "\$k" = "BACKUP_DIR" ] && BACKUP="\$v"
  done < "\$APP_DIR/.sgv_journal"
  if [ -n "\$BACKUP" ] && [ -f "\$BACKUP/supergoodviewer" ]; then
    rm -f "\$APP_DIR/supergoodviewer" 2>/dev/null || true
    mv "\$BACKUP/supergoodviewer" "\$APP_DIR/supergoodviewer" 2>/dev/null || true
    [ -f "\$APP_DIR/supergoodviewer" ] && exec "\$APP_DIR/supergoodviewer" "\$@"
  fi
fi
exit 1
EOF
  chmod +x "$appDir/supergoodviewer" 2>/dev/null || true
fi

# 7. Phase 2: Move new entries into appDir
for p in "\$NEW_STAGING"/* "\$NEW_STAGING"/.*; do
  n="\${p##*/}"
  if [ "\$n" = "." ] || [ "\$n" = ".." ] || [ "\$n" = "*" ] || { [ ! -e "\$p" ] && [ ! -L "\$p" ]; }; then
    continue
  fi
  if [ "\$n" = "bin" ]; then
    continue
  fi
  if ! mv "\$p" "$appDir/\$n"; then
    log "Error: Failed to install \$n"
    rollback
  fi
  echo "\$n" >> "\$INSTALLED_LIST"
done

# 8. Phase 3: Verify target executable before committing
chmod +x "$appDir/supergoodviewer" || true
if [ ! -x "$appDir/supergoodviewer" ]; then
  log "Error: Installed supergoodviewer is not executable"
  rollback
fi

# 9. Success: write new manifest, commit transaction, clean up, launch new binary
NEW_MANIFEST="$appDir/.sgv_manifest.\$\$"
: > "\$NEW_MANIFEST"
for p in "$stagingDirPath"/* "$stagingDirPath"/.*; do
  n="\${p##*/}"
  if [ "\$n" = "." ] || [ "\$n" = ".." ] || [ "\$n" = "*" ] || { [ ! -e "\$p" ] && [ ! -L "\$p" ]; }; then
    continue
  fi
  echo "\$n" >> "\$NEW_MANIFEST"
done
mv "\$NEW_MANIFEST" "\$MANIFEST_FILE"

# Atomic transaction commit: mark STATUS=COMMITTED before removing backups
COMMIT_TMP="\$JOURNAL_FILE.commit.\$\$"
{
  echo "PID=\$\$"
  echo "BACKUP_DIR=\$BACKUP_DIR"
  echo "INSTALLED_LIST=\$INSTALLED_LIST"
  echo "STATUS=COMMITTED"
} > "\$COMMIT_TMP"
mv -f "\$COMMIT_TMP" "\$JOURNAL_FILE"

if [ -d "\$NEW_STAGING/bin" ]; then
  mkdir -p "$appDir/bin" 2>/dev/null || true
  cp -a "\$NEW_STAGING/bin/." "$appDir/bin/" 2>/dev/null || true
  chmod +x "$appDir/bin"/* 2>/dev/null || true
fi

rm -rf "\$BACKUP_DIR" "\$NEW_STAGING" "\$INSTALLED_LIST" "\$PRUNE_FILE" "\$COMMIT_TMP" "\$JOURNAL_FILE"
cleanup_staging_payload
log "SuperGoodViewer update installed successfully."
"$appDir/supergoodviewer" &
exit 0
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
