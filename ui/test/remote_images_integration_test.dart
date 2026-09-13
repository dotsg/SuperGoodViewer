import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/services/remote_image_service.dart';

void main() {
  late Directory tempDir;
  late HttpServer mockServer;
  late String serverBaseUrl;

  final samplePngBytes = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sgv_mock_img_test_');
    RemoteImageService.setCacheDirForTesting(tempDir);

    // Spin up lightweight loopback HttpServer for 100% offline & fast testing
    mockServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    serverBaseUrl = 'http://${mockServer.address.host}:${mockServer.port}';

    mockServer.listen((HttpRequest request) {
      final path = request.uri.path;
      if (path.contains('valid_png') || path.contains('wechat_style')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'png')
          ..add(samplePngBytes)
          ..close();
      } else if (path.contains('html_anti_leech')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'html')
          ..write('<html><body>Anti-Leech Warning</body></html>')
          ..close();
      } else if (path.contains('corrupted_signature')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('image', 'png')
          ..add([1, 2, 3, 4, 5]) // Invalid magic bytes
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  });

  tearDown(() async {
    await mockServer.close(force: true);
    RemoteImageService.setCacheDirForTesting(null);
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('extracts all 4 remote images from docs/WECHAT_BLOG.md and sanitizes anchor fragments offline', () {
    final blogFile = File(p.join(Directory.current.path, '..', 'docs', 'WECHAT_BLOG.md'));
    expect(blogFile.existsSync(), isTrue, reason: 'docs/WECHAT_BLOG.md should exist');

    final content = blogFile.readAsStringSync();
    final urls = RemoteImageService.instance.extractRemoteImageUrls(content);
    expect(urls.length, 4, reason: 'docs/WECHAT_BLOG.md should contain 4 remote images');

    for (final url in urls) {
      expect(url.startsWith('https://mmbiz.qpic.cn'), isTrue);
      final cleanUrl = RemoteImageService.sanitizeImageUrl(url);
      expect(cleanUrl.contains('#'), isFalse);
      expect(cleanUrl.startsWith('https://mmbiz.qpic.cn'), isTrue);

      final filename = RemoteImageService.instance.urlToCacheFilename(url);
      expect(filename.endsWith('.png'), isTrue);
      expect(filename.split('.')[0].length, 32);
    }
  });

  test('download and cache valid image succeeds against local server', () async {
    final testUrl = '$serverBaseUrl/wechat_style/640?wx_fmt=png&from=appmsg#imgIndex=0';

    expect(RemoteImageService.instance.isCached(testUrl), isFalse);

    final success = await RemoteImageService.instance.fetchAndCacheImage(testUrl);
    expect(success, isTrue);
    expect(RemoteImageService.instance.isCached(testUrl), isTrue);

    final filename = RemoteImageService.instance.urlToCacheFilename(testUrl);
    final cachedFile = File(p.join(tempDir.path, filename));
    expect(cachedFile.existsSync(), isTrue);
    expect(cachedFile.lengthSync(), samplePngBytes.length);
  });

  test('rejects non-image Content-Type and corrupted magic bytes without caching', () async {
    final htmlUrl = '$serverBaseUrl/html_anti_leech.png';
    final htmlSuccess = await RemoteImageService.instance.fetchAndCacheImage(htmlUrl);
    expect(htmlSuccess, isFalse, reason: 'HTML content-type should be rejected');
    expect(RemoteImageService.instance.isCached(htmlUrl), isFalse);

    final corruptUrl = '$serverBaseUrl/corrupted_signature.png';
    final corruptSuccess = await RemoteImageService.instance.fetchAndCacheImage(corruptUrl);
    expect(corruptSuccess, isFalse, reason: 'Corrupted magic bytes should be rejected');
    expect(RemoteImageService.instance.isCached(corruptUrl), isFalse);
  });

  test('fetchImagesInMarkdown concurrently fetches images with worker pool and debounces callback', () async {
    final markdown = '''
# Test Document with Multiple Images
![Img 1]($serverBaseUrl/valid_png_1.png)
![Img 2]($serverBaseUrl/valid_png_2.png)
![Img 3]($serverBaseUrl/valid_png_3.png)
![Img 4]($serverBaseUrl/valid_png_4.png)
''';

    int callbackCount = 0;
    final completer = Completer<void>();

    RemoteImageService.instance.fetchImagesInMarkdown(
      markdown,
      onBatchReady: () {
        callbackCount++;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future.timeout(const Duration(seconds: 3));
    expect(callbackCount, greaterThanOrEqualTo(1));

    final urls = RemoteImageService.instance.extractRemoteImageUrls(markdown);
    for (final url in urls) {
      expect(RemoteImageService.instance.isCached(url), isTrue);
    }
  });
}
