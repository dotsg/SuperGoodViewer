import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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

/// Singleton bridge communicating with the Rust `sogood_core` library.
class NativeEngine {
  static final NativeEngine instance = NativeEngine._();

  DynamicLibrary? _dylib;
  late final SogoodGetVersionDart _getVersion;
  late final SogoodGetLastErrorDart _getLastError;
  late final SogoodFreeStringDart _freeString;
  late final SogoodFreeBufferDart _freeBuffer;
  late final SogoodCompileMarkdownDart _compileMarkdown;

  bool _initialized = false;

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
        throw StateError(
          'Failed to load native engine library at $libraryPath: $e ($e2)',
        );
      }
    }

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

    _initialized = true;
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

    // Check multiple candidate locations
    final currentDir = Directory.current.path;
    final candidates = [
      // When running from repo root or ui dir
      p.join(currentDir, '..', 'core', 'target', 'release', libName),
      p.join(currentDir, 'core', 'target', 'release', libName),
      p.join(currentDir, '..', 'core', 'target', 'debug', libName),
      p.join(currentDir, 'core', 'target', 'debug', libName),
      // App bundle directory (release packaged)
      p.join(p.dirname(Platform.resolvedExecutable), libName),
      p.join(p.dirname(Platform.resolvedExecutable), '..', 'Frameworks', libName),
      p.join(p.dirname(Platform.resolvedExecutable), 'Frameworks', libName),
      p.join(p.dirname(Platform.resolvedExecutable), 'lib', libName),

    ];

    for (final candidate in candidates) {
      final normalized = p.normalize(candidate);
      if (File(normalized).existsSync()) {
        return normalized;
      }
    }

    return libName;
  }

  String getVersion() {
    final ptr = _getVersion();
    return ptr.toDartString();
  }

  String? getLastError() {
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
    return await Isolate.run(() {
      return NativeEngine.instance.compileMarkdown(
        markdown,
        title: title,
        docDir: docDir,
        options: options,
      );
    });
  }
}
