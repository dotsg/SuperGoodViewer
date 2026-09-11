import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../models/render_options.dart';

// Native C structs matching Rust #[repr(C)] SogoodBuffer
final class CSogoodBuffer extends Struct {
  external Pointer<Uint8> data;

  @UintPtr()
  external int len;

  @UintPtr()
  external int capacity;
}

// Typedefs for C functions
typedef SogoodGetVersionC = Pointer<Utf8> Function();
typedef SogoodGetVersionDart = Pointer<Utf8> Function();

typedef SogoodGetLastErrorC = Pointer<Utf8> Function();
typedef SogoodGetLastErrorDart = Pointer<Utf8> Function();

typedef SogoodFreeStringC = Void Function(Pointer<Utf8>);
typedef SogoodFreeStringDart = void Function(Pointer<Utf8>);

typedef SogoodFreeBufferC = Void Function(Pointer<CSogoodBuffer>);
typedef SogoodFreeBufferDart = void Function(Pointer<CSogoodBuffer>);

typedef SogoodCompileMarkdownC = Pointer<CSogoodBuffer> Function(
  Pointer<Utf8> markdown,
  Pointer<Utf8> title,
  Pointer<Utf8> docDir,
  Pointer<Utf8> optionsJson,
);
typedef SogoodCompileMarkdownDart = Pointer<CSogoodBuffer> Function(
  Pointer<Utf8> markdown,
  Pointer<Utf8> title,
  Pointer<Utf8> docDir,
  Pointer<Utf8> optionsJson,
);

typedef SogoodDetectFontsC = Pointer<CSogoodBuffer> Function();
typedef SogoodDetectFontsDart = Pointer<CSogoodBuffer> Function();

/// Singleton bridge communicating with the Rust `sogood_core` library.
class NativeEngine {
  static final NativeEngine instance = NativeEngine._();

  DynamicLibrary? _dylib;
  late final SogoodGetVersionDart _getVersion;
  late final SogoodGetLastErrorDart _getLastError;
  late final SogoodFreeStringDart _freeString;
  late final SogoodFreeBufferDart _freeBuffer;
  late final SogoodCompileMarkdownDart _compileMarkdown;
  late final SogoodDetectFontsDart _detectFonts;

  bool _initialized = false;
  String? _initError;

  bool get isAvailable => _initialized && _dylib != null;
  String? get initError => _initError;

  NativeEngine._() {
    _init();
  }

  void _init() {
    if (_initialized) return;

    final libraryPath = _resolveLibraryPath();
    try {
      _dylib = DynamicLibrary.open(libraryPath);
    } catch (e) {
      // Fallback attempt with standard system loader
      try {
        if (Platform.isMacOS) {
          _dylib = DynamicLibrary.open('libsogood_core.dylib');
        } else if (Platform.isWindows) {
          _dylib = DynamicLibrary.open('sogood_core.dll');
        } else {
          _dylib = DynamicLibrary.open('libsogood_core.so');
        }
      } catch (e2) {
        _initError = 'Failed to load native engine library at $libraryPath: $e ($e2)';
        debugPrint('[NativeEngine] $_initError');
        return;
      }
    }

    try {
      final lib = _dylib!;
      _getVersion = lib.lookupFunction<SogoodGetVersionC, SogoodGetVersionDart>(
        'sogood_get_version',
      );
      _getLastError = lib.lookupFunction<SogoodGetLastErrorC, SogoodGetLastErrorDart>(
        'sogood_get_last_error',
      );
      _freeString = lib.lookupFunction<SogoodFreeStringC, SogoodFreeStringDart>(
        'sogood_free_string',
      );
      _freeBuffer = lib.lookupFunction<SogoodFreeBufferC, SogoodFreeBufferDart>(
        'sogood_free_buffer',
      );
      _compileMarkdown = lib.lookupFunction<
        SogoodCompileMarkdownC,
        SogoodCompileMarkdownDart
      >('sogood_compile_markdown');
      _detectFonts = lib.lookupFunction<
        SogoodDetectFontsC,
        SogoodDetectFontsDart
      >('sogood_detect_fonts');

      _initialized = true;
    } catch (e) {
      _initError = 'Failed to bind native engine functions: $e';
      debugPrint('[NativeEngine] $_initError');
    }
  }

  static String _resolveLibraryPath() {
    final String libName;
    if (Platform.isMacOS) {
      libName = 'libsogood_core.dylib';
    } else if (Platform.isWindows) {
      libName = 'sogood_core.dll';
    } else {
      libName = 'libsogood_core.so';
    }

    // Paths next to the executable come FIRST, and are the only ones consulted in
    // release builds. The working-directory candidates below are a development
    // convenience, but resolving them ahead of the bundle means a packaged app
    // launched from a directory that happens to contain `ui/test/<lib>` or
    // `core/target/release/<lib>` loads that copy instead of its own engine —
    // silently running a stale or foreign library.
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
      p.join(exeDir, libName),
      p.join(exeDir, '..', 'Frameworks', libName),
      p.join(exeDir, 'Frameworks', libName),
      p.join(exeDir, 'lib', libName),
    ];

    if (!kReleaseMode) {
      final currentDir = Directory.current.path;
      candidates.addAll([
        // Local folders used by `flutter test` and `flutter run`
        p.join(currentDir, 'test', libName),
        p.join(currentDir, 'macos', libName),
        p.join(currentDir, 'ui', 'test', libName),
        p.join(currentDir, 'ui', 'macos', libName),
        // When running from repo root or ui dir
        p.join(currentDir, '..', 'core', 'target', 'release', libName),
        p.join(currentDir, 'core', 'target', 'release', libName),
        p.join(currentDir, '..', 'core', 'target', 'debug', libName),
        p.join(currentDir, 'core', 'target', 'debug', libName),
      ]);
    }

    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (File(normalized).existsSync()) {
        return normalized;
      }
    }

    return libName;
  }

  String getVersion() {
    if (!isAvailable) return '0.0.0 (uninitialized)';
    final ptr = _getVersion();
    return ptr.toDartString();
  }

  String? getLastError() {
    if (!isAvailable) return _initError;
    final ptr = _getLastError();
    if (ptr.address == 0) return null;
    final msg = ptr.toDartString();
    _freeString(ptr);
    return msg;
  }

  Uint8List? compileMarkdown(
    String markdown, {
    String title = 'Document',
    String docDir = '.',
    RenderOptions options = const RenderOptions(),
  }) {
    if (!isAvailable) return null;

    final mdPtr = markdown.toNativeUtf8();
    final titlePtr = title.toNativeUtf8();
    final docDirPtr = docDir.toNativeUtf8();
    final optionsPtr = options.toJsonString().toNativeUtf8();

    try {
      final bufferPtr = _compileMarkdown(
        mdPtr,
        titlePtr,
        docDirPtr,
        optionsPtr,
      );

      if (bufferPtr.address == 0) {
        return null;
      }

      try {
        final buffer = bufferPtr.ref;
        if (buffer.len == 0 || buffer.data.address == 0) {
          return null;
        }

        // Copy bytes to managed Uint8List
        final bytes = Uint8List(buffer.len);
        bytes.setAll(0, buffer.data.asTypedList(buffer.len));
        return bytes;
      } finally {
        _freeBuffer(bufferPtr);
      }
    } finally {
      calloc.free(mdPtr);
      calloc.free(titlePtr);
      calloc.free(docDirPtr);
      calloc.free(optionsPtr);
    }
  }

  /// Compiles markdown in a background Dart isolate so the UI thread never drops frames.
  Future<Uint8List?> compileMarkdownAsync(
    String markdown, {
    String title = 'Document',
    String docDir = '.',
    RenderOptions options = const RenderOptions(),
  }) async {
    if (!isAvailable) return null;

    return await Isolate.run(() {
      return NativeEngine.instance.compileMarkdown(
        markdown,
        title: title,
        docDir: docDir,
        options: options,
      );
    });
  }

  /// Queries the system and embedded font store for available fonts,
  /// specifically checking for CJK monospace fonts like Maple Mono.
  Map<String, dynamic> detectFonts() {
    if (!isAvailable) return {};

    final bufferPtr = _detectFonts();
    if (bufferPtr.address == 0) {
      return {};
    }
    try {
      final buffer = bufferPtr.ref;
      if (buffer.len == 0 || buffer.data.address == 0) {
        return {};
      }
      final bytes = Uint8List(buffer.len);
      bytes.setAll(0, buffer.data.asTypedList(buffer.len));
      final jsonString = utf8.decode(bytes);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      return {};
    } finally {
      _freeBuffer(bufferPtr);
    }
  }
}

