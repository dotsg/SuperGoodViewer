import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  static Future<File> _getConfigFile() async {
    if (testConfigFileOverride != null) return testConfigFileOverride!;
    if (_cachedConfigFile != null) return _cachedConfigFile!;
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      if (!await appSupportDir.exists()) {
        await appSupportDir.create(recursive: true);
      }
      _cachedConfigFile = File(p.join(appSupportDir.path, _prefFileName));
    } catch (_) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final dir = Directory(p.join(home, '.sogoodviewer'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      _cachedConfigFile = File(p.join(dir.path, _prefFileName));
    }
    return _cachedConfigFile!;
  }

  static Future<Map<String, dynamic>> load() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isEmpty) return {};
        final data = json.decode(content);
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
    } catch (e) {
      debugPrint('PreferencesService.load error: $e');
    }
    return {};
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
