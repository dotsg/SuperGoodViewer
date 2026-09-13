import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/services/remote_image_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sgv_wechat_test_');
    RemoteImageService.setCacheDirForTesting(tempDir);
  });

  tearDown(() {
    RemoteImageService.setCacheDirForTesting(null);
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('extracts all 4 remote images from docs/WECHAT_BLOG.md and sanitizes anchor fragments', () {
    final blogFile = File(p.join(Directory.current.path, '..', 'docs', 'WECHAT_BLOG.md'));
    expect(blogFile.existsSync(), isTrue, reason: 'docs/WECHAT_BLOG.md should exist');

    final content = blogFile.readAsStringSync();
    final urls = RemoteImageService.instance.extractRemoteImageUrls(content);
    expect(urls.length, 4, reason: 'docs/WECHAT_BLOG.md should contain 4 remote images');

    for (final url in urls) {
      expect(url.startsWith('https://mmbiz.qpic.cn'), isTrue);
      // Ensure sanitizeImageUrl strips any #imgIndex=... fragment
      final cleanUrl = RemoteImageService.sanitizeImageUrl(url);
      expect(cleanUrl.contains('#'), isFalse);
      expect(cleanUrl.startsWith('https://mmbiz.qpic.cn'), isTrue);

      // Verify filename generation
      final filename = RemoteImageService.instance.urlToCacheFilename(url);
      expect(filename.endsWith('.png'), isTrue);
      expect(filename.split('.')[0].length, 32);
    }
  });

  test('download and cache WeChat image without fragment succeeds', () async {
    const testUrl = 'https://mmbiz.qpic.cn/sz_mmbiz_png/yVwYcibHCQbUhbtEib78gzlSRsHicerMcIao6Kvxeib6EtnWkS8KypicuPrSdJteTt5VxQgpPs7k9Bhgr6GdymmPvrxVnD3Q7Jdp98nhnvNmDfHY/640?wx_fmt=png&from=appmsg&tp=wxpic&wxfrom=5&wx_lazy=1#imgIndex=0';

    expect(RemoteImageService.instance.isCached(testUrl), isFalse);

    final success = await RemoteImageService.instance.fetchAndCacheImage(testUrl);
    expect(success, isTrue);
    expect(RemoteImageService.instance.isCached(testUrl), isTrue);

    final filename = RemoteImageService.instance.urlToCacheFilename(testUrl);
    final cachedFile = File(p.join(tempDir.path, filename));
    expect(cachedFile.existsSync(), isTrue);
    expect(cachedFile.lengthSync(), greaterThan(10000));
  });

  test('fetchImagesInMarkdown concurrently fetches images with worker pool and debounces callback', () async {
    final blogFile = File(p.join(Directory.current.path, '..', 'docs', 'WECHAT_BLOG.md'));
    final content = blogFile.readAsStringSync();

    int callbackCount = 0;
    final completer = Completer<void>();

    RemoteImageService.instance.fetchImagesInMarkdown(
      content,
      onBatchReady: () {
        callbackCount++;
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await completer.future.timeout(const Duration(seconds: 20));
    expect(callbackCount, greaterThanOrEqualTo(1));

    // Verify all 4 images are cached
    final urls = RemoteImageService.instance.extractRemoteImageUrls(content);
    for (final url in urls) {
      expect(RemoteImageService.instance.isCached(url), isTrue);
    }
  });
}
