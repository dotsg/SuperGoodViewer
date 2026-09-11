import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Lightweight cross-platform preferences service.
/// Persists user settings, last opened document, and layout state.
class PreferencesService {
  static const String _prefFileName = 'preferences.json';

  static Future<File> _getConfigFile() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      if (!await appSupportDir.exists()) {
        await appSupportDir.create(recursive: true);
      }
      return File(p.join(appSupportDir.path, _prefFileName));
    } catch (_) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final dir = Directory(p.join(home, '.sogoodviewer'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File(p.join(dir.path, _prefFileName));
    }
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
    try {
      final file = await _getConfigFile();
      await file.writeAsString(json.encode(prefs));
    } catch (e) {
      debugPrint('PreferencesService.save error: $e');
    }
  }

  static Future<void> saveKey(String key, dynamic value) async {
    final prefs = await load();
    prefs[key] = value;
    await save(prefs);
  }
}
