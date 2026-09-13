import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Lightweight cross-platform preferences service.
/// Persists user settings, last opened document, and layout state.
class PreferencesService {
  static const String _prefFileName = 'preferences.json';
  static File? _cachedConfigFile;
  static Future<void>? _pendingSave;

  @visibleForTesting
  static File? testConfigFileOverride;

  @visibleForTesting
  static void setConfigFileForTesting(File? file) {
    testConfigFileOverride = file;
    _cachedConfigFile = file;
    _pendingSave = null;
  }

  static File _resolveConfigFileSync() {
    if (testConfigFileOverride != null) return testConfigFileOverride!;
    if (_cachedConfigFile != null) return _cachedConfigFile!;

    try {
      final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null) {
        final Directory appSupportDir;
        if (Platform.isMacOS) {
          appSupportDir = Directory(p.join(home, 'Library', 'Application Support', 'com.sogood.sogoodviewer'));
        } else if (Platform.isWindows) {
          final appData = Platform.environment['APPDATA'] ?? home;
          appSupportDir = Directory(p.join(appData, 'com.sogood.sogoodviewer'));
        } else {
          appSupportDir = Directory(p.join(home, '.sogoodviewer'));
        }
        if (!appSupportDir.existsSync()) {
          appSupportDir.createSync(recursive: true);
        }
        _cachedConfigFile = File(p.join(appSupportDir.path, _prefFileName));
        return _cachedConfigFile!;
      }
    } catch (_) {}

    final dir = Directory(p.join(Directory.current.path, '.sogoodviewer'));
    _cachedConfigFile = File(p.join(dir.path, _prefFileName));
    return _cachedConfigFile!;
  }

  static Future<File> _getConfigFile() async {
    if (testConfigFileOverride != null) return testConfigFileOverride!;
    if (_cachedConfigFile != null) return _cachedConfigFile!;
    return _resolveConfigFileSync();
  }

  static Map<String, dynamic> loadSync() {
    try {
      final file = _resolveConfigFileSync();
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final data = json.decode(content);
          if (data is Map<String, dynamic>) {
            return data;
          }
        }
      }
    } catch (e) {
      debugPrint('PreferencesService.loadSync error: $e');
    }
    return {};
  }

  static Future<Map<String, dynamic>> load() async {
    return loadSync();
  }

  static Future<void> save(Map<String, dynamic> prefs) async {
    // Snapshot and serialize immediately so caller modifications don't race
    final String jsonStr;
    try {
      jsonStr = json.encode(prefs);
    } catch (e) {
      debugPrint('PreferencesService.save serialization error: $e');
      return;
    }

    final prev = _pendingSave;
    final completer = Completer<void>();
    _pendingSave = completer.future;

    try {
      if (prev != null) {
        await prev.catchError((_) {});
      }
      final file = await _getConfigFile();
      final tmpFile = File('${file.path}.tmp');
      await tmpFile.writeAsString(jsonStr, flush: true);
      if (await tmpFile.exists()) {
        await tmpFile.rename(file.path);
      } else {
        await file.writeAsString(jsonStr, flush: true);
      }
    } catch (e) {
      debugPrint('PreferencesService.save error: $e');
    } finally {
      completer.complete();
    }
  }

  static Future<void> saveKey(String key, dynamic value) async {
    final prefs = await load();
    prefs[key] = value;
    await save(prefs);
  }
}
