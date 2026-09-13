import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Worker pool for limiting concurrent asynchronous tasks.
class _WorkerPool {
  final int maxConcurrency;
  int _active = 0;
  final List<void Function()> _queue = [];

  _WorkerPool({this.maxConcurrency = 5});

  Future<T> run<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    void execute() async {
      _active++;
      try {
        final result = await task();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _active--;
        if (_queue.isNotEmpty) {
          final next = _queue.removeAt(0);
          next();
        }
      }
    }

    if (_active < maxConcurrency) {
      execute();
    } else {
      _queue.add(execute);
    }

    return completer.future;
  }
}

/// Service responsible for asynchronously fetching, caching, and managing remote images.
///
/// Features:
/// 1. Controlled worker pool concurrency (default 5 workers) to avoid CDN rate-limiting or socket exhaustion.
/// 2. Fast SHA-256 content-addressable disk cache matching Typst's MemoryWorld lookups.
/// 3. In-flight request deduplication so the same image is never fetched concurrently more than once.
/// 4. Debounced batch progressive re-rendering (250ms window) for smooth visual updates.
class RemoteImageService {
  static final RemoteImageService instance = RemoteImageService._();
  RemoteImageService._();

  static Directory? _customCacheDirForTesting;
  static Directory? _cachedDir;

  final _WorkerPool _pool = _WorkerPool(maxConcurrency: 5);
  final Map<String, Future<bool>> _inFlight = {};
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  @visibleForTesting
  static void setCacheDirForTesting(Directory? dir) {
    _customCacheDirForTesting = dir;
    _cachedDir = dir;
  }

  /// Returns the platform-specific cache directory for remote images.
  Directory getCacheDirectory() {
    if (_customCacheDirForTesting != null) return _customCacheDirForTesting!;
    if (_cachedDir != null) return _cachedDir!;

    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final String basePath;
        if (Platform.isMacOS) {
          basePath = p.join(home, 'Library', 'Caches', 'com.sogood.sogoodviewer', 'remote_images');
        } else if (Platform.isWindows) {
          final localAppData = Platform.environment['LOCALAPPDATA'] ?? home;
          basePath = p.join(localAppData, 'SuperGoodViewer', 'Cache', 'remote_images');
        } else {
          basePath = p.join(home, '.cache', 'sogoodviewer', 'remote_images');
        }
        final dir = Directory(basePath);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        _cachedDir = dir;
        return dir;
      }
    } catch (_) {}

    final fallback = Directory(p.join(Directory.current.path, '.cache', 'remote_images'));
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    _cachedDir = fallback;
    return fallback;
  }

  /// Derives extension from URL and optional Content-Type header.
  static String computeExtension(String url, [String? contentType]) {
    final lower = url.toLowerCase();
    if (lower.contains('.png') || lower.contains('wx_fmt=png')) return 'png';
    if (lower.contains('.jpg') || lower.contains('.jpeg') || lower.contains('wx_fmt=jpeg') || lower.contains('wx_fmt=jpg')) return 'jpg';
    if (lower.contains('.webp') || lower.contains('wx_fmt=webp')) return 'webp';
    if (lower.contains('.gif') || lower.contains('wx_fmt=gif')) return 'gif';
    if (lower.contains('.svg') || lower.contains('wx_fmt=svg')) return 'svg';

    if (contentType != null) {
      final ct = contentType.toLowerCase();
      if (ct.contains('image/jpeg')) return 'jpg';
      if (ct.contains('image/png')) return 'png';
      if (ct.contains('image/webp')) return 'webp';
      if (ct.contains('image/gif')) return 'gif';
      if (ct.contains('image/svg')) return 'svg';
    }

    return 'png';
  }

  /// Strips fragment/anchor (#...) from URLs for compliant HTTP requests and uniform cache keys.
  static String sanitizeImageUrl(String url) {
    final hashIdx = url.indexOf('#');
    return hashIdx >= 0 ? url.substring(0, hashIdx) : url;
  }

  /// Calculates the 32-character SHA-256 hash cache filename for a URL.
  String urlToCacheFilename(String url, [String? contentType]) {
    final cleanUrl = sanitizeImageUrl(url);
    final bytes = utf8.encode(cleanUrl);
    final digest = sha256.convert(bytes);
    final prefix = digest.toString().substring(0, 32);
    final ext = computeExtension(cleanUrl, contentType);
    return '$prefix.$ext';
  }

  /// Checks if an image is already cached on disk.
  bool isCached(String url) {
    try {
      final cleanUrl = sanitizeImageUrl(url);
      final dir = getCacheDirectory();
      final predicted = urlToCacheFilename(cleanUrl);
      final predictedFile = File(p.join(dir.path, predicted));
      if (predictedFile.existsSync()) return true;

      // Check prefix match in case content-type derived a different extension
      final bytes = utf8.encode(cleanUrl);
      final prefix = sha256.convert(bytes).toString().substring(0, 32);
      if (dir.existsSync()) {
        for (final entry in dir.listSync()) {
          if (entry is File && p.basename(entry.path).startsWith(prefix)) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// Extracts all HTTP/HTTPS image URLs from Markdown (both Markdown `![]()` and HTML `<img src="">`).
  List<String> extractRemoteImageUrls(String markdown) {
    final urls = <String>{};

    // 1. Markdown images: ![alt](url)
    final mdImgRegex = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)');
    for (final match in mdImgRegex.allMatches(markdown)) {
      final url = match.group(1)?.trim();
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }

    // 2. HTML images: <img ... src="url" ...>
    final htmlImgRegex = RegExp(r'''<img[^>]+src=["'](https?://[^"'\s]+)["'][^>]*>''', caseSensitive: false);
    for (final match in htmlImgRegex.allMatches(markdown)) {
      final url = match.group(1)?.trim();
      if (url != null && url.isNotEmpty) {
        urls.add(url);
      }
    }

    return urls.toList();
  }

  /// Downloads a remote image and saves it to the cache directory.
  Future<bool> fetchAndCacheImage(String url) {
    if (isCached(url)) return Future.value(true);

    if (_inFlight.containsKey(url)) {
      return _inFlight[url]!;
    }

    final future = _pool.run(() => _downloadImageInternal(url));
    _inFlight[url] = future;

    future.whenComplete(() {
      _inFlight.remove(url);
    });

    return future;
  }

  Future<bool> _downloadImageInternal(String url) async {
    final cleanUrl = sanitizeImageUrl(url);
    final cacheDir = getCacheDirectory();
    final tempFilePath = p.join(cacheDir.path, '${sha256.convert(utf8.encode(cleanUrl)).toString().substring(0, 32)}.tmp');

    try {
      final request = await _httpClient.getUrl(Uri.parse(cleanUrl)).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[RemoteImageService] HTTP ${response.statusCode} for $cleanUrl');
        return false;
      }

      final contentType = response.headers.value(HttpHeaders.contentTypeHeader);
      final filename = urlToCacheFilename(cleanUrl, contentType);
      final targetFile = File(p.join(cacheDir.path, filename));

      final tempFile = File(tempFilePath);
      final sink = tempFile.openWrite();
      await response.pipe(sink);

      if (await tempFile.exists()) {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await tempFile.rename(targetFile.path);
        debugPrint('[RemoteImageService] Successfully cached remote image: $filename for $url');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[RemoteImageService] Error downloading $url: $e');
      try {
        final tmp = File(tempFilePath);
        if (tmp.existsSync()) {
          tmp.deleteSync();
        }
      } catch (_) {}
      return false;
    }
  }

  Timer? _batchDebounceTimer;
  int _currentBatchNewImages = 0;

  /// Scans markdown for uncached remote images, downloads them with the worker pool,
  /// and fires [onBatchReady] in debounced batches (250ms) as images arrive.
  void fetchImagesInMarkdown(String markdown, {required VoidCallback onBatchReady}) {
    final urls = extractRemoteImageUrls(markdown);
    final uncachedUrls = urls.where((u) => !isCached(u)).toList();

    if (uncachedUrls.isEmpty) return;

    debugPrint('[RemoteImageService] Found ${uncachedUrls.length} uncached remote images to fetch');
    int completedCount = 0;

    for (final url in uncachedUrls) {
      fetchAndCacheImage(url).then((success) {
        completedCount++;
        if (success) {
          _currentBatchNewImages++;
          _batchDebounceTimer?.cancel();
          _batchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
            if (_currentBatchNewImages > 0) {
              debugPrint('[RemoteImageService] Debounced batch re-render triggered ($_currentBatchNewImages new images)');
              _currentBatchNewImages = 0;
              onBatchReady();
            }
          });
        }

        if (completedCount == uncachedUrls.length) {
          // If the timer hasn't fired yet but all downloads finished, trigger immediately if any succeeded
          if (_currentBatchNewImages > 0) {
            _batchDebounceTimer?.cancel();
            debugPrint('[RemoteImageService] All downloads complete; final re-render triggered ($_currentBatchNewImages images)');
            _currentBatchNewImages = 0;
            onBatchReady();
          }
        }
      }).catchError((e) {
        completedCount++;
        debugPrint('[RemoteImageService] Fetch failed for $url: $e');
      });
    }
  }
}
