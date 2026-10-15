import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../controllers/reader_controller.dart';
import 'document_cache_service.dart';
import 'preferences_service.dart';
import 'remote_image_service.dart';

/// Service for one-click downloading & installing CJK-aligned fonts (such as Maple Mono)
/// and importing user local font files (.ttf, .otf, .ttc, .zip) into the application's
/// custom font directory, hot-reloading both the Rust Typst font store and Flutter's FontLoader.
class FontDownloadService extends ChangeNotifier {
  FontDownloadService._();
  static final FontDownloadService instance = FontDownloadService._();

  static const List<String> mapleMonoDownloadUrls = <String>[
    'https://gh-proxy.com/https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN-unhinted.zip',
    'https://ghfast.top/https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN-unhinted.zip',
    'https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN-unhinted.zip',
  ];

  bool _isDownloading = false;
  bool _isExtracting = false;
  double _progress = 0.0;
  String? _errorMessage;

  bool get isDownloading => _isDownloading;
  bool get isExtracting => _isExtracting;
  bool get isBusy => _isDownloading || _isExtracting;
  double get progress => _progress;
  int get progressPercent => (_progress * 100).round().clamp(0, 100);
  String? get errorMessage => _errorMessage;

  @visibleForTesting
  static Directory? customFontsDirForTesting;

  @visibleForTesting
  static Future<Uint8List> Function(void Function(double progress) onProgress)?
      debugDownloadOverride;

  /// Resolves the custom fonts directory that matches Rust's `world::custom_fonts_dir()`.
  Directory getCustomFontsDirectory() {
    if (customFontsDirForTesting != null) {
      if (!customFontsDirForTesting!.existsSync()) {
        customFontsDirForTesting!.createSync(recursive: true);
      }
      return customFontsDirForTesting!;
    }

    final appSupport = PreferencesService.appSupportDir;
    final Directory baseDir = appSupport ??
        RemoteImageService.instance.getCacheDirectory().parent;
    final fontsDir = Directory(p.join(baseDir.path, 'fonts'));
    if (!fontsDir.existsSync()) {
      fontsDir.createSync(recursive: true);
    }
    return fontsDir;
  }

  /// Registers any custom font files in `getCustomFontsDirectory()` with Flutter's [FontLoader]
  /// so live typography previews in the UI can render them immediately.
  Future<void> loadInstalledCustomFontsIntoFlutter() async {
    try {
      final dir = getCustomFontsDirectory();
      if (!dir.existsSync()) return;
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => _isFontExtension(f.path))
          .toList();
      if (files.isEmpty) return;

      final mapleFiles = <File>[];
      for (final file in files) {
        final base = p.basenameWithoutExtension(file.path);
        if (base.toLowerCase().contains('maple')) {
          mapleFiles.add(file);
        } else {
          final familyGuess = base.split('-').first.trim();
          if (familyGuess.isNotEmpty) {
            final loader = FontLoader(familyGuess);
            final bytes = await file.readAsBytes();
            loader.addFont(Future.value(ByteData.sublistView(bytes)));
            await loader.load();
          }
        }
      }

      if (mapleFiles.isNotEmpty) {
        for (final family in const ['Maple Mono', 'Maple Mono NF CN', 'Maple Mono SC NF']) {
          final loader = FontLoader(family);
          for (final file in mapleFiles) {
            final bytes = await file.readAsBytes();
            loader.addFont(Future.value(ByteData.sublistView(bytes)));
          }
          await loader.load();
        }
      }
    } catch (e) {
      debugPrint('[FontDownloadService] Failed to load fonts into Flutter: $e');
    }
  }

  /// Downloads `MapleMono-NF-CN-unhinted.zip`, extracts core weights into the custom
  /// fonts directory, reloads the Rust Typst font index, and activates Maple Mono.
  Future<bool> downloadAndInstallMapleMono(ReaderController controller) async {
    if (isBusy) return false;

    _isDownloading = true;
    _isExtracting = false;
    _progress = 0.02;
    _errorMessage = null;
    notifyListeners();

    try {
      final Uint8List zipBytes;
      if (debugDownloadOverride != null) {
        zipBytes = await debugDownloadOverride!((p) {
          _progress = p.clamp(0.0, 1.0);
          notifyListeners();
        });
      } else {
        zipBytes = await _downloadWithFallback(mapleMonoDownloadUrls, (p) {
          _progress = p.clamp(0.02, 0.95);
          notifyListeners();
        });
      }

      _isDownloading = false;
      _isExtracting = true;
      _progress = 0.98;
      notifyListeners();

      final installedFiles = await _extractFontsFromZipBytes(
        zipBytes,
        onlyCoreMapleWeights: true,
      );
      if (installedFiles.isEmpty) {
        throw Exception('No valid .ttf/.otf font files found in archive');
      }

      await _activateInstalledFonts(controller, preferMapleMono: true);

      _isExtracting = false;
      _progress = 1.0;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[FontDownloadService] Maple Mono download/install failed: $e');
      _isDownloading = false;
      _isExtracting = false;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Opens the system file picker to let the user import a local `.ttf`, `.otf`, `.ttc`, or `.zip` font file.
  /// Returns the installed display name on success, or `null` if cancelled or failed.
  Future<String?> importLocalFontFile(ReaderController controller) async {
    if (isBusy) return null;

    try {
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['ttf', 'otf', 'ttc', 'zip'],
      );
      if (picked == null || picked.path == null) {
        return null;
      }

      _isDownloading = false;
      _isExtracting = true;
      _errorMessage = null;
      notifyListeners();

      final bytes = await File(picked.path!).readAsBytes();
      if (bytes.isEmpty) {
        throw Exception('Unable to read selected font file');
      }

      final fileName = picked.name.isNotEmpty
          ? picked.name
          : p.basename(picked.path!);
      final lowerName = fileName.toLowerCase();

      List<File> installed = const [];
      if (lowerName.endsWith('.zip')) {
        installed = await _extractFontsFromZipBytes(
          bytes,
          onlyCoreMapleWeights: lowerName.contains('maple'),
        );
      } else if (_isFontExtension(lowerName)) {
        final targetDir = getCustomFontsDirectory();
        final outFile = File(p.join(targetDir.path, p.basename(fileName)));
        await outFile.writeAsBytes(bytes, flush: true);
        installed = [outFile];
      } else {
        throw Exception('Unsupported font file format: $fileName');
      }

      if (installed.isEmpty) {
        throw Exception('No valid font files found');
      }

      final isMaple = lowerName.contains('maple') ||
          installed.any((f) => p.basename(f.path).toLowerCase().contains('maple'));
      await _activateInstalledFonts(controller, preferMapleMono: isMaple);

      _isExtracting = false;
      notifyListeners();
      return isMaple
          ? 'Maple Mono'
          : p.basenameWithoutExtension(installed.first.path).split('-').first;
    } catch (e) {
      debugPrint('[FontDownloadService] Local font import failed: $e');
      _isDownloading = false;
      _isExtracting = false;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  Future<void> _activateInstalledFonts(
    ReaderController controller, {
    required bool preferMapleMono,
  }) async {
    await loadInstalledCustomFontsIntoFlutter();
    await DocumentCacheService.clearCache();
    await controller.refreshFontReport();

    if (preferMapleMono) {
      final report = controller.fontReport;
      final detectedCjkMono = (report['detected_cjk_mono'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[];
      final mapleFamily = detectedCjkMono.firstWhere(
        (f) => f.toLowerCase().contains('maple mono'),
        orElse: () => 'Maple Mono',
      );
      controller.setTypography(
        bodyFont: controller.renderOptions.bodyFont,
        codeFont: mapleFamily,
        fontSize: controller.renderOptions.fontSize,
      );
    } else {
      await controller.compileDocument();
    }
  }

  Future<List<File>> _extractFontsFromZipBytes(
    Uint8List zipBytes, {
    required bool onlyCoreMapleWeights,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final targetDir = getCustomFontsDirectory();
    final extracted = <File>[];

    final fontEntries = archive.files.where((entry) {
      if (!entry.isFile) return false;
      final name = entry.name;
      if (name.contains('__MACOSX') || p.basename(name).startsWith('.')) {
        return false;
      }
      return _isFontExtension(name);
    }).toList();

    for (final entry in fontEntries) {
      final baseName = p.basename(entry.name);
      if (onlyCoreMapleWeights && fontEntries.length > 6) {
        final lower = baseName.toLowerCase();
        final isCoreWeight = lower.contains('-regular.') ||
            lower.contains('-bold.') ||
            lower.contains('-italic.') ||
            lower.contains('-bolditalic.') ||
            lower.contains('-medium.') ||
            lower.contains('-semibold.');
        if (!isCoreWeight) continue;
      }

      final content = entry.content;
      if (content.isEmpty) continue;
      final outFile = File(p.join(targetDir.path, baseName));
      await outFile.writeAsBytes(content, flush: true);
      extracted.add(outFile);
    }

    // Fallback if filtering skipped everything (e.g. non-standard filenames)
    if (extracted.isEmpty && fontEntries.isNotEmpty) {
      for (final entry in fontEntries) {
        final content = entry.content;
        if (content.isEmpty) continue;
        final outFile = File(p.join(targetDir.path, p.basename(entry.name)));
        await outFile.writeAsBytes(content, flush: true);
        extracted.add(outFile);
      }
    }

    return extracted;
  }

  Future<Uint8List> _downloadWithFallback(
    List<String> urls,
    void Function(double progress) onProgress,
  ) async {
    Object? lastError;
    for (final url in urls) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 12)
        ..userAgent = 'SuperGoodViewer-FontInstaller/1.1';
      try {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close().timeout(
          const Duration(seconds: 20),
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
        }

        final totalBytes = response.contentLength;
        final builder = BytesBuilder(copy: false);
        int received = 0;

        await for (final chunk in response.timeout(const Duration(seconds: 30))) {
          builder.add(chunk);
          received += chunk.length;
          if (totalBytes > 0) {
            onProgress(received / totalBytes);
          } else {
            // Estimate against ~18 MB archive when Content-Length is omitted
            onProgress((received / (18 * 1024 * 1024)).clamp(0.05, 0.92));
          }
        }

        final bytes = builder.takeBytes();
        if (bytes.length < 1024) {
          throw Exception('Downloaded archive is unexpectedly small (${bytes.length} B)');
        }
        return bytes;
      } catch (e) {
        debugPrint('[FontDownloadService] Mirror failed ($url): $e');
        lastError = e;
      } finally {
        client.close(force: true);
      }
    }
    throw Exception(lastError?.toString() ?? 'All download mirrors failed');
  }

  static bool _isFontExtension(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.ttc');
  }
}
