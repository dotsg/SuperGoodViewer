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
/// 2. Fast O(1) SHA-256 content-addressable disk cache matching Typst's MemoryWorld lookups (no directory scans).
/// 3. In-flight request deduplication with clean URL keys and unique temporary filenames.
/// 4. Strict response validation: HTTP 200, Content-Length integrity (honoring gzip decompression), and image magic bytes.
/// 5. Negative caching with 10-minute TTL to prevent continuous network hammering on 404/broken URLs.
/// 6. Isolated session debounce states preventing cross-document re-render cancellations.
/// 7. Automatic oldest-first (FIFO) cache pruning to 75% when exceeding limit (default 250 MB) + orphan .tmp cleanup.
class RemoteImageService {
  static final RemoteImageService instance = RemoteImageService._();
  RemoteImageService._();

  static Directory? _customCacheDirForTesting;
  static Directory? _cachedDir;
  static int _tempFileCounter = 0;

  final _WorkerPool _pool = _WorkerPool(maxConcurrency: 5);
  final Map<String, Future<bool>> _inFlight = {};
  final Map<String, DateTime> _negativeCache = {};
  static const Duration _deterministicFailureTtl = Duration(minutes: 10);
  static const Duration _transientFailureTtl = Duration(seconds: 30);
  static const int _maxNegativeCacheEntries = 1000;
  DateTime? _lastPruneTime;

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  @visibleForTesting
  static void setCacheDirForTesting(Directory? dir) {
    _customCacheDirForTesting = dir;
    _cachedDir = dir;
  }

  /// Clears the negative cache, allowing previously failed URLs to be retried immediately.
  void clearNegativeCache() {
    _negativeCache.clear();
  }

  /// Resets testing-related singleton state (caches, throttles, and counters).
  @visibleForTesting
  void resetForTesting() {
    _negativeCache.clear();
    _lastPruneTime = null;
    _tempFileCounter = 0;
  }


  @visibleForTesting
  void recordFailureForTesting(String cleanUrl, Duration ttl) {
    _recordFailure(cleanUrl, ttl);
  }

  @visibleForTesting
  Duration? getRemainingFailureTtl(String cleanUrl) {
    final expiresAt = _negativeCache[cleanUrl];
    if (expiresAt == null) return null;
    final diff = expiresAt.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  void _cleanNegativeCache(DateTime now) {
    _negativeCache.removeWhere((_, expiresAt) => now.isAfter(expiresAt));
    if (_negativeCache.length > _maxNegativeCacheEntries) {
      final sorted = _negativeCache.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final removeCount = _negativeCache.length - _maxNegativeCacheEntries;
      for (int i = 0; i < removeCount; i++) {
        _negativeCache.remove(sorted[i].key);
      }
    }
  }

  void _recordFailure(String cleanUrl, Duration ttl) {
    final now = DateTime.now();
    _cleanNegativeCache(now);
    _negativeCache[cleanUrl] = now.add(ttl);
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

  /// Strips fragment/anchor (#...) from URLs for compliant HTTP requests and uniform cache keys.
  static String sanitizeImageUrl(String url) {
    final hashIdx = url.indexOf('#');
    return hashIdx >= 0 ? url.substring(0, hashIdx) : url;
  }

  /// Derives image extension from URL path last segment or query parameters (e.g. wx_fmt=png).
  /// Aligned with Rust's extract_url_extension.
  static String computeExtension(String cleanUrl) {
    final qIdx = cleanUrl.indexOf('?');
    final urlPath = qIdx >= 0 ? cleanUrl.substring(0, qIdx) : cleanUrl;
    final query = qIdx >= 0 ? cleanUrl.substring(qIdx + 1) : '';

    final segments = urlPath.split('/');
    if (segments.isNotEmpty) {
      final lastSegment = segments.last;
      final dotIdx = lastSegment.lastIndexOf('.');
      if (dotIdx >= 0 && dotIdx < lastSegment.length - 1) {
        final ext = lastSegment.substring(dotIdx + 1).toLowerCase();
        switch (ext) {
          case 'png':
            return 'png';
          case 'jpg':
          case 'jpeg':
            return 'jpg';
          case 'webp':
            return 'webp';
          case 'gif':
            return 'gif';
          case 'svg':
            return 'svg';
        }
      }
    }

    if (query.isNotEmpty) {
      final qLower = query.toLowerCase();
      for (final param in qLower.split('&')) {
        final parts = param.split('=');
        if (parts.length == 2 && (parts[0] == 'wx_fmt' || parts[0] == 'format')) {
          switch (parts[1]) {
            case 'png':
              return 'png';
            case 'jpg':
            case 'jpeg':
              return 'jpg';
            case 'webp':
              return 'webp';
            case 'gif':
              return 'gif';
            case 'svg':
              return 'svg';
          }
        }
      }
    }

    return 'png';
  }

  /// Calculates the 32-character SHA-256 hash cache filename for a URL.
  String urlToCacheFilename(String url) {
    final cleanUrl = sanitizeImageUrl(url);
    final bytes = utf8.encode(cleanUrl);
    final digest = sha256.convert(bytes);
    final prefix = digest.toString().substring(0, 32);
    final ext = computeExtension(cleanUrl);
    return '$prefix.$ext';
  }

  /// Fast O(1) check if an image is already cached on disk (no directory scanning).
  bool isCached(String url) {
    try {
      final cleanUrl = sanitizeImageUrl(url);
      final dir = getCacheDirectory();
      final predicted = urlToCacheFilename(cleanUrl);
      final predictedFile = File(p.join(dir.path, predicted));
      return predictedFile.existsSync();
    } catch (_) {}
    return false;
  }

  /// Checks if a URL recently failed and is within its negative cache TTL.
  bool isRecentlyFailed(String cleanUrl) {
    final expiresAt = _negativeCache[cleanUrl];
    if (expiresAt == null) return false;
    if (DateTime.now().isAfter(expiresAt)) {
      _negativeCache.remove(cleanUrl);
      return false;
    }
    return true;
  }

  /// Extracts all distinct HTTP/HTTPS image URLs from Markdown (both Markdown `![]()` and HTML `<img src="">`),
  /// normalizing each URL by removing client fragments.
  List<String> extractRemoteImageUrls(String markdown) {
    final urls = <String>{};

    // 1. Markdown images: ![alt](url)
    final mdImgRegex = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)');
    for (final match in mdImgRegex.allMatches(markdown)) {
      final rawUrl = match.group(1)?.trim();
      if (rawUrl != null && rawUrl.isNotEmpty) {
        urls.add(sanitizeImageUrl(rawUrl));
      }
    }

    // 2. HTML images: <img ... src="url" ...>
    final htmlImgRegex = RegExp(r'''<img[^>]+src=["'](https?://[^"'\s]+)["'][^>]*>''', caseSensitive: false);
    for (final match in htmlImgRegex.allMatches(markdown)) {
      final rawUrl = match.group(1)?.trim();
      if (rawUrl != null && rawUrl.isNotEmpty) {
        urls.add(sanitizeImageUrl(rawUrl));
      }
    }

    return urls.toList();
  }

  /// Validates file header magic bytes to prevent corrupted, truncated, or HTML error pages from being cached.
  static bool isValidImageBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // GIF: 47 49 46 38 ('GIF8')
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return true;
    // WEBP: 'RIFF' .... 'WEBP'
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }

    // SVG: strip UTF-8 BOM if present (EF BB BF)
    var svgBytes = bytes;
    if (svgBytes.length >= 3 && svgBytes[0] == 0xEF && svgBytes[1] == 0xBB && svgBytes[2] == 0xBF) {
      svgBytes = svgBytes.sublist(3);
    }
    if (svgBytes.length >= 4) {
      final head = String.fromCharCodes(svgBytes.take(256)).toLowerCase().trimLeft();
      if (head.startsWith('<svg') ||
          head.startsWith('<?xml') ||
          head.startsWith('<!doctype svg') ||
          (head.startsWith('<!doctype') && head.contains('<svg'))) {
        return true;
      }
    }
    return false;
  }

  /// Downloads a remote image and saves it to the cache directory.
  Future<bool> fetchAndCacheImage(String url) {
    final cleanUrl = sanitizeImageUrl(url);
    if (isCached(cleanUrl)) return Future.value(true);
    if (isRecentlyFailed(cleanUrl)) return Future.value(false);

    if (_inFlight.containsKey(cleanUrl)) {
      return _inFlight[cleanUrl]!;
    }

    final future = _pool.run(() => _downloadImageInternal(cleanUrl));
    _inFlight[cleanUrl] = future;

    future.whenComplete(() {
      _inFlight.remove(cleanUrl);
    });

    return future;
  }

  Future<bool> _downloadImageInternal(String cleanUrl) async {
    final cacheDir = getCacheDirectory();
    final hashPrefix = sha256.convert(utf8.encode(cleanUrl)).toString().substring(0, 32);
    final tempFilePath = p.join(
      cacheDir.path,
      '${hashPrefix}_${pid}_${DateTime.now().microsecondsSinceEpoch}_${_tempFileCounter++}.tmp',
    );

    try {
      final request = await _httpClient.getUrl(Uri.parse(cleanUrl)).timeout(const Duration(seconds: 8));
      final response = await request.close().timeout(const Duration(seconds: 8));

      // 1. Verify HTTP 200
      if (response.statusCode != 200) {
        debugPrint('[RemoteImageService] Non-200 HTTP status ${response.statusCode} for $cleanUrl');
        try {
          await response.drain<void>();
        } catch (_) {}
        final isDeterministic = response.statusCode >= 400 && response.statusCode < 500;
        _recordFailure(cleanUrl, isDeterministic ? _deterministicFailureTtl : _transientFailureTtl);
        return false;
      }

      // 2. Reject explicit HTML error/anti-leech pages or JSON error payloads
      // (allowing application/octet-stream, text/plain, and CDN fallbacks to be validated by magic bytes)
      final contentType = response.headers.value(HttpHeaders.contentTypeHeader)?.toLowerCase() ?? '';
      if (contentType.startsWith('text/html') ||
          contentType.startsWith('application/json')) {
        debugPrint('[RemoteImageService] Explicit non-image Content-Type ($contentType) for $cleanUrl');
        try {
          await response.drain<void>();
        } catch (_) {}
        _recordFailure(cleanUrl, _deterministicFailureTtl);
        return false;
      }

      final targetFilename = urlToCacheFilename(cleanUrl);
      final targetFile = File(p.join(cacheDir.path, targetFilename));
      final tempFile = File(tempFilePath);
      final sink = tempFile.openWrite();

      int bytesWritten = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        bytesWritten += chunk.length;
      }
      await sink.flush();
      await sink.close();

      // 3. Verify Content-Length match if declared (skip if response was automatically uncompressed by HttpClient)
      if (response.compressionState != HttpClientResponseCompressionState.decompressed &&
          response.contentLength > 0 &&
          bytesWritten != response.contentLength) {
        debugPrint('[RemoteImageService] Content-Length mismatch ($bytesWritten / ${response.contentLength}) for $cleanUrl');
        _recordFailure(cleanUrl, _transientFailureTtl);
        try {
          if (tempFile.existsSync()) tempFile.deleteSync();
        } catch (_) {}
        return false;
      }

      // 4. Verify magic bytes from downloaded file
      if (tempFile.existsSync()) {
        final headerBytes = await tempFile.openRead(0, 256).first;
        if (!isValidImageBytes(headerBytes)) {
          debugPrint('[RemoteImageService] Corrupted or unknown image signature for $cleanUrl');
          _recordFailure(cleanUrl, _deterministicFailureTtl);
          try {
            tempFile.deleteSync();
          } catch (_) {}
          return false;
        }

        // Atomically replace target cache file
        if (targetFile.existsSync()) {
          targetFile.deleteSync();
        }
        await tempFile.rename(targetFile.path);
        _negativeCache.remove(cleanUrl);
        debugPrint('[RemoteImageService] Cached valid image: $targetFilename ($bytesWritten bytes) for $cleanUrl');
        return true;
      }
      _recordFailure(cleanUrl, _deterministicFailureTtl);
      return false;
    } catch (e) {
      debugPrint('[RemoteImageService] Error downloading $cleanUrl: $e');
      final isTransient = e is SocketException ||
          e is TimeoutException ||
          e is HttpException ||
          e is HandshakeException ||
          e is TlsException;
      _recordFailure(cleanUrl, isTransient ? _transientFailureTtl : _deterministicFailureTtl);
      try {
        final tmp = File(tempFilePath);
        if (tmp.existsSync()) {
          tmp.deleteSync();
        }
      } catch (_) {}
      return false;
    }
  }

  /// Scans markdown for uncached remote images, downloads them with the worker pool,
  /// and fires [onBatchReady] in debounced batches (250ms) as images arrive.
  ///
  /// Each invocation encapsulates its own debounce timer and counter so concurrent
  /// sessions or rapid document reloads never cancel each other.
  void fetchImagesInMarkdown(String markdown, {required VoidCallback onBatchReady}) {
    // Check and prune cache in background (throttled to at most once per 5 minutes)
    unawaited(pruneCacheIfNeeded());

    final urls = extractRemoteImageUrls(markdown);
    final uncachedUrls = urls.where((u) => !isCached(u) && !isRecentlyFailed(u)).toList();

    if (uncachedUrls.isEmpty) return;

    debugPrint('[RemoteImageService] Found ${uncachedUrls.length} uncached remote images to fetch');

    // Local closure session state
    Timer? sessionDebounceTimer;
    int sessionNewImages = 0;
    int completedCount = 0;

    void triggerBatch(String reason) {
      if (sessionNewImages > 0) {
        debugPrint('[RemoteImageService] Re-render triggered ($reason, $sessionNewImages new images)');
        sessionNewImages = 0;
        onBatchReady();
      }
    }

    for (final url in uncachedUrls) {
      fetchAndCacheImage(url).then((success) {
        completedCount++;
        if (success) {
          sessionNewImages++;
          sessionDebounceTimer?.cancel();
          sessionDebounceTimer = Timer(const Duration(milliseconds: 250), () {
            triggerBatch('debounced batch');
          });
        }

        if (completedCount == uncachedUrls.length) {
          if (sessionNewImages > 0) {
            sessionDebounceTimer?.cancel();
            triggerBatch('all downloads complete');
          }
        }
      }).catchError((e) {
        completedCount++;
        debugPrint('[RemoteImageService] Fetch failed for $url: $e');
        if (completedCount == uncachedUrls.length && sessionNewImages > 0) {
          sessionDebounceTimer?.cancel();
          triggerBatch('all downloads complete');
        }
      });
    }
  }

  /// Asynchronously prunes old cached images if the cache directory exceeds [maxSizeBytes]
  /// and cleans up orphan .tmp files older than 1 hour.
  ///
  /// Default limit is 250 MB; when exceeded, evicts oldest-first (FIFO based on modification time)
  /// until under 75% of the limit. Throttled to at most once per 5 minutes.
  Future<void> pruneCacheIfNeeded({int maxSizeBytes = 250 * 1024 * 1024}) async {
    final now = DateTime.now();
    _cleanNegativeCache(now);

    if (_lastPruneTime != null && now.difference(_lastPruneTime!) < const Duration(minutes: 5)) {
      return;
    }
    _lastPruneTime = now;

    try {
      final dir = getCacheDirectory();
      if (!dir.existsSync()) return;

      final files = <File>[];
      int totalSize = 0;

      for (final entity in dir.listSync()) {
        if (entity is File) {
          if (entity.path.endsWith('.tmp')) {
            // Clean up orphan .tmp files older than 1 hour left behind by killed processes
            try {
              final mtime = entity.lastModifiedSync();
              if (now.difference(mtime) > const Duration(hours: 1)) {
                entity.deleteSync();
              }
            } catch (_) {}
          } else {
            files.add(entity);
            try {
              totalSize += entity.lengthSync();
            } catch (_) {}
          }
        }
      }

      if (totalSize > maxSizeBytes) {
        debugPrint('[RemoteImageService] Cache size (${totalSize ~/ 1024} KB) exceeds limit; pruning oldest items...');
        // Sort by last modified ascending (oldest-first FIFO)
        files.sort((a, b) {
          final aTime = a.lastModifiedSync();
          final bTime = b.lastModifiedSync();
          return aTime.compareTo(bTime);
        });

        final targetSize = (maxSizeBytes * 0.75).toInt();
        for (final file in files) {
          if (totalSize <= targetSize) break;
          try {
            final len = file.lengthSync();
            file.deleteSync();
            totalSize -= len;
          } catch (_) {}
        }
        debugPrint('[RemoteImageService] Pruning complete, new size: ${totalSize ~/ 1024} KB');
      }
    } catch (e) {
      debugPrint('[RemoteImageService] Prune cache failed: $e');
    }
  }
}
