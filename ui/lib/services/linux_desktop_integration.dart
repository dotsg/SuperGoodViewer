import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../i18n/strings_en.dart';
import '../i18n/strings_zh_hans.dart';
import '../i18n/strings_zh_hant.dart';

enum DesktopEntryStatus {
  notInstalled,
  installed,

  /// An entry exists but differs from what this copy of the app would write,
  /// e.g. the bundle was moved or the entry predates an app update.
  outdated,
}

/// Adds the portable Linux bundle to the applications menu and to "Open With"
/// for Markdown and PDF files, without root: it writes a desktop entry and
/// icons under `$XDG_DATA_HOME` (default `~/.local/share`).
///
/// The entry launches `bin/sgv`, which hands files to an already running
/// window over the CLI IPC socket instead of starting a second instance.
class LinuxDesktopIntegration {
  /// Matches APPLICATION_ID in linux/CMakeLists.txt. The window's app id must
  /// equal the desktop file name for shells to pair the window with the entry.
  static const String appId = 'com.sogood.sogoodviewer';

  static const List<String> mimeTypes = [
    'text/markdown',
    'text/x-markdown',
    'application/pdf',
  ];

  /// Both are reassignable so tests can exercise the UI on any host.
  static bool isSupported = Platform.isLinux;
  static LinuxDesktopIntegration instance = LinuxDesktopIntegration();

  final String _dataHome;
  final String _bundleDir;

  LinuxDesktopIntegration({String? dataHome, String? bundleDir})
      : _dataHome = dataHome ?? _defaultDataHome(),
        _bundleDir = bundleDir ?? p.dirname(Platform.resolvedExecutable);

  static String _defaultDataHome() {
    final xdg = Platform.environment['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) return xdg;
    return p.join(Platform.environment['HOME'] ?? '', '.local', 'share');
  }

  String get desktopFilePath => p.join(_dataHome, 'applications', '$appId.desktop');

  String _installedIconPath(int size) =>
      p.join(_dataHome, 'icons', 'hicolor', '${size}x$size', 'apps', '$appId.png');

  String _bundledIconPath(int size) => p.join(_bundleDir, 'data', 'icons', 'app_icon_$size.png');

  static const List<int> _iconSizes = [256, 512];

  String get launcherPath => p.join(_bundleDir, 'bin', 'sgv');

  /// Quotes an Exec argument per the Desktop Entry spec: wrap it in double
  /// quotes, backslash-escape `"` `` ` `` `$` `\`, then escape the backslashes
  /// again for the string value itself.
  @visibleForTesting
  static String quoteExecArgument(String arg) {
    final quoted = arg.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}');
    return '"$quoted"'.replaceAll(r'\', r'\\');
  }

  String buildDesktopEntry() {
    const en = EnStrings();
    const hans = ZhHansStrings();
    const hant = ZhHantStrings();
    return [
      '[Desktop Entry]',
      'Type=Application',
      'Name=${en.appTitle}',
      'Name[zh_CN]=${hans.appTitle}',
      'Name[zh_TW]=${hant.appTitle}',
      'Name[zh_HK]=${hant.appTitle}',
      'GenericName=${en.desktopEntryGenericName}',
      'GenericName[zh_CN]=${hans.desktopEntryGenericName}',
      'GenericName[zh_TW]=${hant.desktopEntryGenericName}',
      'GenericName[zh_HK]=${hant.desktopEntryGenericName}',
      'Exec=${quoteExecArgument(launcherPath)} %F',
      'Icon=$appId',
      'Terminal=false',
      'Categories=Office;Viewer;',
      'MimeType=${mimeTypes.join(';')};',
      'Keywords=Markdown;PDF;Typst;Reader;Viewer;',
      'StartupWMClass=$appId',
      '',
    ].join('\n');
  }

  DesktopEntryStatus status() {
    final file = File(desktopFilePath);
    if (!file.existsSync()) return DesktopEntryStatus.notInstalled;
    try {
      return file.readAsStringSync() == buildDesktopEntry()
          ? DesktopEntryStatus.installed
          : DesktopEntryStatus.outdated;
    } catch (_) {
      return DesktopEntryStatus.outdated;
    }
  }

  /// Writes (or rewrites) the icons and the desktop entry.
  Future<void> install() async {
    for (final size in _iconSizes) {
      final target = File(_installedIconPath(size));
      await target.parent.create(recursive: true);
      await File(_bundledIconPath(size)).copy(target.path);
    }
    final entry = File(desktopFilePath);
    await entry.parent.create(recursive: true);
    await entry.writeAsString(buildDesktopEntry());
    await _refreshCaches();
  }

  Future<void> uninstall() async {
    for (final path in [desktopFilePath, for (final size in _iconSizes) _installedIconPath(size)]) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await _refreshCaches();
  }

  /// Best effort: menus pick up changes on their own, these only make it
  /// immediate where the tools are installed.
  Future<void> _refreshCaches() async {
    if (!isSupported) return;
    for (final command in [
      ['update-desktop-database', p.join(_dataHome, 'applications')],
      ['gtk-update-icon-cache', '-f', '-t', p.join(_dataHome, 'icons', 'hicolor')],
    ]) {
      try {
        await Process.run(command.first, command.sublist(1));
      } catch (_) {}
    }
  }
}
