import 'dart:convert';
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
    test('extractRemoteImageUrls extracts and sanitizes both Markdown and HTML remote images', () {
      const markdown = '''
# Blog with Images

Here is a markdown image with anchor:
![Diagram 1](https://mmbiz.qpic.cn/sz_mmbiz_png/arch1/640?wx_fmt=png#imgIndex=0)

Duplicate image with different anchor should be deduplicated:
![Diagram 1 Dup](https://mmbiz.qpic.cn/sz_mmbiz_png/arch1/640?wx_fmt=png#imgIndex=3)

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

    test('computeExtension uses path last segment and handles deceptive directory names', () {
      expect(RemoteImageService.computeExtension('https://cdn.x/.png-assets/a.jpg'), 'jpg');
      expect(RemoteImageService.computeExtension('https://cdn.x/.png-assets/a.jpeg?token=123'), 'jpg');
      expect(RemoteImageService.computeExtension('https://cdn.x/dir.jpg/image.png'), 'png');
      expect(RemoteImageService.computeExtension('https://cdn.x/vector.svg'), 'svg');
      expect(RemoteImageService.computeExtension('https://cdn.x/anim.gif'), 'gif');
      expect(RemoteImageService.computeExtension('https://cdn.x/photo.webp'), 'webp');
      expect(RemoteImageService.computeExtension('https://mmbiz.qpic.cn/sz_mmbiz_png/demo/640?wx_fmt=png'), 'png');
      expect(RemoteImageService.computeExtension('https://mmbiz.qpic.cn/sz_mmbiz_jpeg/demo/640?wx_fmt=jpeg'), 'jpg');
      expect(RemoteImageService.computeExtension('https://example.com/raw-image'), 'png'); // fallback
    });

    test('isValidImageBytes accurately verifies image magic bytes', () {
      // PNG: 89 50 4E 47
      expect(RemoteImageService.isValidImageBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]), isTrue);
      // JPEG: FF D8 FF
      expect(RemoteImageService.isValidImageBytes([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]), isTrue);
      // GIF: 47 49 46 38 ('GIF8')
      expect(RemoteImageService.isValidImageBytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]), isTrue);
      // WEBP: 'RIFF' .... 'WEBP'
      expect(RemoteImageService.isValidImageBytes([
        0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50,
      ]), isTrue);
      // SVG
      expect(RemoteImageService.isValidImageBytes(utf8.encode('<svg width="100" height="100"></svg>')), isTrue);
      expect(RemoteImageService.isValidImageBytes(utf8.encode('<?xml version="1.0"?><svg></svg>')), isTrue);

      // Rejections: HTML error page
      expect(RemoteImageService.isValidImageBytes(utf8.encode('<!DOCTYPE html><html><body>Error 403</body></html>')), isFalse);
      expect(RemoteImageService.isValidImageBytes(utf8.encode('{"error": "not found"}')), isFalse);
      expect(RemoteImageService.isValidImageBytes([0x00, 0x01, 0x02]), isFalse);
    });

    test('urlToCacheFilename generates consistent 32-char prefix and correct extension', () {
      const wechatUrl = 'https://mmbiz.qpic.cn/sz_mmbiz_png/demo/640?wx_fmt=png&from=appmsg';
      final filename = RemoteImageService.instance.urlToCacheFilename(wechatUrl);

      expect(filename.endsWith('.png'), isTrue);
      final parts = filename.split('.');
      expect(parts[0].length, 32);
      expect(parts[1], 'png');

      const jpegUrl = 'https://example.com/photo.jpeg?token=123';
      final jpegFilename = RemoteImageService.instance.urlToCacheFilename(jpegUrl);
      expect(jpegFilename.endsWith('.jpg'), isTrue);
    });

    test('isCached accurately detects cached files in O(1)', () {
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

      final cacheFile = File(p.join(tempDir.path, filename1));
      cacheFile.writeAsBytesSync([1, 2, 3]);

      expect(RemoteImageService.instance.isCached(wechatRawUrl), isTrue);
      expect(RemoteImageService.instance.isCached(wechatUrlWithAnchor), isTrue);
    });

    test('pruneCacheIfNeeded evicts oldest modified files when limit is exceeded', () async {
      final file1 = File(p.join(tempDir.path, 'img1.png'));
      final file2 = File(p.join(tempDir.path, 'img2.png'));
      final file3 = File(p.join(tempDir.path, 'img3.png'));

      file1.writeAsBytesSync(List.filled(1000, 1));
      await Future.delayed(const Duration(milliseconds: 10));
      file2.writeAsBytesSync(List.filled(1000, 2));
      await Future.delayed(const Duration(milliseconds: 10));
      file3.writeAsBytesSync(List.filled(1000, 3));

      // Total size: 3000 bytes. If limit is 2800 bytes, target is 2800 * 0.75 = 2100 bytes.
      // img1 is oldest and will be evicted, leaving 2000 bytes.
      await RemoteImageService.instance.pruneCacheIfNeeded(maxSizeBytes: 2800);

      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isTrue);
      expect(file3.existsSync(), isTrue);
    });
  });
}
