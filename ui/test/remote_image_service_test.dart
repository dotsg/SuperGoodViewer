import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sogoodviewer/services/remote_image_service.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sgv_remote_img_test_');
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

  group('RemoteImageService Tests', () {
    test('extractRemoteImageUrls extracts both Markdown and HTML remote images', () {
      const markdown = '''
# Blog with Images

Here is a markdown image:
![Diagram 1](https://mmbiz.qpic.cn/sz_mmbiz_png/arch1/640?wx_fmt=png)

Here is a local image that should NOT be extracted as remote:
![Local Logo](../images/logo.png)
![Another Local](./asset.jpg)

Here is an HTML image:
<div align="center">
  <img src="https://mmbiz.qpic.cn/sz_mmbiz_png/arch2/640?wx_fmt=png" width="800" />
</div>

And another one with single quotes:
<img src='http://example.com/cat.jpg' alt='cat'>
''';

      final urls = RemoteImageService.instance.extractRemoteImageUrls(markdown);
      expect(urls.length, 3);
      expect(urls, contains('https://mmbiz.qpic.cn/sz_mmbiz_png/arch1/640?wx_fmt=png'));
      expect(urls, contains('https://mmbiz.qpic.cn/sz_mmbiz_png/arch2/640?wx_fmt=png'));
      expect(urls, contains('http://example.com/cat.jpg'));
    });

    test('urlToCacheFilename generates consistent 32-char prefix and correct extension', () {
      const wechatUrl = 'https://mmbiz.qpic.cn/sz_mmbiz_png/demo/640?wx_fmt=png&from=appmsg';
      final filename = RemoteImageService.instance.urlToCacheFilename(wechatUrl);

      expect(filename.endsWith('.png'), isTrue);
      final parts = filename.split('.');
      expect(parts[0].length, 32); // 32 chars hex hash
      expect(parts[1], 'png');

      const jpegUrl = 'https://example.com/photo.jpeg?token=123';
      final jpegFilename = RemoteImageService.instance.urlToCacheFilename(jpegUrl);
      expect(jpegFilename.endsWith('.jpg'), isTrue);

      const webpUrl = 'https://example.com/banner.webp';
      final webpFilename = RemoteImageService.instance.urlToCacheFilename(webpUrl);
      expect(webpFilename.endsWith('.webp'), isTrue);
    });

    test('isCached accurately detects cached files', () {
      const testUrl = 'https://example.com/image.png';
      expect(RemoteImageService.instance.isCached(testUrl), isFalse);

      final filename = RemoteImageService.instance.urlToCacheFilename(testUrl);
      final cacheFile = File(p.join(tempDir.path, filename));
      cacheFile.writeAsBytesSync([1, 2, 3, 4]);

      expect(RemoteImageService.instance.isCached(testUrl), isTrue);
    });

    test('sanitizeImageUrl and urlToCacheFilename strip anchor fragments for RFC compliance', () {
      const wechatRawUrl = 'https://mmbiz.qpic.cn/sz_mmbiz_png/test/640?wx_fmt=png';
      const wechatUrlWithAnchor = '$wechatRawUrl#imgIndex=0';

      expect(RemoteImageService.sanitizeImageUrl(wechatUrlWithAnchor), wechatRawUrl);

      final filename1 = RemoteImageService.instance.urlToCacheFilename(wechatRawUrl);
      final filename2 = RemoteImageService.instance.urlToCacheFilename(wechatUrlWithAnchor);
      expect(filename1, filename2);

      // Verify isCached matches both
      final cacheFile = File(p.join(tempDir.path, filename1));
      cacheFile.writeAsBytesSync([1, 2, 3]);

      expect(RemoteImageService.instance.isCached(wechatRawUrl), isTrue);
      expect(RemoteImageService.instance.isCached(wechatUrlWithAnchor), isTrue);
    });
  });
}
