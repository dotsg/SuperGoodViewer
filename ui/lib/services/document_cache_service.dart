import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/render_options.dart';

/// High-performance disk cache for pre-compiled PDF documents.
/// Enables 0ms instantaneous document open on cold start and document switching.
class DocumentCacheService {
  static Directory? _customCacheDirForTesting;
  static Directory? _cachedDir;

  @visibleForTesting
  static void setCacheDirForTesting(Directory? dir) {
    _customCacheDirForTesting = dir;
    _cachedDir = dir;
  }

  static Directory _getCacheDir() {
    if (_customCacheDirForTesting != null) return _customCacheDirForTesting!;
    if (_cachedDir != null) return _cachedDir!;

    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final String basePath;
        if (Platform.isMacOS) {
          basePath = p.join(home, 'Library', 'Caches', 'com.sogood.sogoodviewer', 'compiled');
        } else if (Platform.isWindows) {
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? home;
          basePath = p.join(localAppData, 'SuperGoodViewer', 'Cache', 'compiled');
        } else {
          basePath = p.join(home, '.cache', 'sogoodviewer', 'compiled');
        }
        final dir = Directory(basePath);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        _cachedDir = dir;
        return dir;
      }
    } catch (_) {}

    final fallback = Directory(p.join(Directory.current.path, '.cache', 'compiled'));
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    _cachedDir = fallback;
    return fallback;
  }

  static String _computeCacheFileName(String filePath, int mtime, int size, RenderOptions options) {
    final raw = '$filePath#$mtime#$size#${options.mode}#${options.theme}#${options.fontSize}#${options.bodyFont ?? ''}#${options.codeFont ?? ''}';
    int hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(raw)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final baseName = p.basenameWithoutExtension(filePath).replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    return '${baseName}_${hash.toRadixString(16)}.pdf';
  }

  /// Fast synchronous lookup for pre-compiled PDF bytes.
  /// Returns null if not cached or if source file was modified.
  static Uint8List? getCachedPdf(String filePath, RenderOptions options) {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final stat = file.statSync();
      final fileName = _computeCacheFileName(filePath, stat.modified.millisecondsSinceEpoch, stat.size, options);
      final cacheFile = File(p.join(_getCacheDir().path, fileName));
      if (cacheFile.existsSync()) {
        final bytes = cacheFile.readAsBytesSync();
        if (bytes.length > 100 &&
            bytes[0] == 0x25 && // '%'
            bytes[1] == 0x50 && // 'P'
            bytes[2] == 0x44 && // 'D'
            bytes[3] == 0x46) { // 'F'
          return bytes;
        }
      }
    } catch (e) {
      debugPrint('[DocumentCacheService] getCachedPdf error: $e');
    }
    return null;
  }

  /// Asynchronously persists compiled PDF bytes to disk cache.
  static Future<void> saveCachedPdf(String filePath, RenderOptions options, Uint8List pdfBytes) async {
    if (pdfBytes.isEmpty) return;
    try {
      final file = File(filePath);
      if (!await file.exists()) return;
      final stat = await file.stat();
      final fileName = _computeCacheFileName(filePath, stat.modified.millisecondsSinceEpoch, stat.size, options);
      final cacheDir = _getCacheDir();
      final cacheFile = File(p.join(cacheDir.path, fileName));
      final tmpFile = File(p.join(cacheDir.path, '$fileName.tmp'));
      await tmpFile.writeAsBytes(pdfBytes, flush: true);
      if (await tmpFile.exists()) {
        await tmpFile.rename(cacheFile.path);
      }
      _pruneCacheIfNeeded(cacheDir);
    } catch (e) {
      debugPrint('[DocumentCacheService] saveCachedPdf error: $e');
    }
  }

  static DateTime _lastPrune = DateTime.fromMillisecondsSinceEpoch(0);

  static void _pruneCacheIfNeeded(Directory cacheDir) {
    final now = DateTime.now();
    if (now.difference(_lastPrune).inMinutes < 10) return;
    _lastPrune = now;

    try {
      final entities = cacheDir.listSync().whereType<File>().toList();
      if (entities.length > 60) {
        entities.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
        final toDelete = entities.take(entities.length - 40);
        for (final f in toDelete) {
          try {
            f.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Returns the current cache directory path.
  static String get cacheDirectoryPath => _getCacheDir().path;

  /// Returns current statistics on the compiled PDF disk cache.
  static CacheStats getCacheStats() {
    try {
      final dir = _getCacheDir();
      if (!dir.existsSync()) {
        return CacheStats(fileCount: 0, totalBytes: 0, dirPath: dir.path);
      }
      final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList();
      var total = 0;
      for (final f in files) {
        try {
          total += f.lengthSync();
        } catch (_) {}
      }
      return CacheStats(fileCount: files.length, totalBytes: total, dirPath: dir.path);
    } catch (_) {
      return CacheStats(fileCount: 0, totalBytes: 0, dirPath: _getCacheDir().path);
    }
  }

  /// Clears all cached PDF files from disk.
  /// Returns the number of files deleted and total bytes freed.
  static Future<CacheStats> clearCache() async {
    try {
      final dir = _getCacheDir();
      if (!dir.existsSync()) {
        return CacheStats(fileCount: 0, totalBytes: 0, dirPath: dir.path);
      }
      final entities = dir.listSync();
      int deletedCount = 0;
      int freedBytes = 0;
      for (final entity in entities) {
        if (entity is File && (entity.path.endsWith('.pdf') || entity.path.endsWith('.tmp'))) {
          try {
            final len = entity.lengthSync();
            entity.deleteSync();
            deletedCount++;
            freedBytes += len;
          } catch (_) {}
        }
      }
      return CacheStats(fileCount: deletedCount, totalBytes: freedBytes, dirPath: dir.path);
    } catch (e) {
      debugPrint('[DocumentCacheService] clearCache error: $e');
      return CacheStats(fileCount: 0, totalBytes: 0, dirPath: _getCacheDir().path);
    }
  }

  /// Opens the cache directory in the system file manager (Finder on macOS / Explorer on Windows).
  static Future<bool> openCacheDirectory() async {
    try {
      final dir = _getCacheDir();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      if (Platform.isMacOS) {
        final res = await Process.run('open', [dir.path]);
        return res.exitCode == 0;
      } else if (Platform.isWindows) {
        final res = await Process.run('explorer.exe', [dir.path]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [dir.path]);
        return res.exitCode == 0;
      }
    } catch (e) {
      debugPrint('[DocumentCacheService] openCacheDirectory error: $e');
    }
    return false;
  }

  /// Human-readable formatting for bytes.
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Represents statistics about the compiled document disk cache.
class CacheStats {
  final int fileCount;
  final int totalBytes;
  final String dirPath;

  const CacheStats({
    required this.fileCount,
    required this.totalBytes,
    required this.dirPath,
  });

  String get formattedSize => DocumentCacheService.formatBytes(totalBytes);
}
