import 'dart:io';
import 'package:flutter/services.dart';
import '../i18n/app_strings.dart';

class CliStatus {
  final bool isInstalled;
  final bool isPartial;
  final String path;
  final String target;
  final bool isCurrentApp;
  final String? warningCode;
  final String? warning;
  final String? error;

  const CliStatus({
    required this.isInstalled,
    this.isPartial = false,
    required this.path,
    required this.target,
    required this.isCurrentApp,
    this.warningCode,
    this.warning,
    this.error,
  });

  factory CliStatus.empty() {
    return const CliStatus(
      isInstalled: false,
      isPartial: false,
      path: '',
      target: '',
      isCurrentApp: false,
    );
  }

  String? localizedWarning(AppStrings s) {
    if (warningCode == 'missing_path') {
      return s.cliStatusPartialPath;
    } else if (warningCode == 'incomplete_tools') {
      return s.cliStatusPartialTools;
    }
    if (warning != null && warning!.isNotEmpty) {
      return warning;
    }
    if (isPartial) {
      return s.cliStatusPartialTools;
    }
    return null;
  }
}

class CliOperationResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? messageCode;
  final String? message;
  final String? warning;
  final String? warningCode;
  final List<String>? warningCodes;
  final String? path;

  const CliOperationResult({
    required this.isSuccess,
    this.isCancelled = false,
    this.messageCode,
    this.message,
    this.warning,
    this.warningCode,
    this.warningCodes,
    this.path,
  });

  String? localizedMessage(AppStrings s) {
    if (messageCode != null) {
      switch (messageCode) {
        case 'not_installed':
          return s.cliMsgNotInstalled;
        case 'user_cancelled':
          return s.cliAuthCancelled;
        case 'app_data_dir_failed':
          return s.cliErrorAppDataDirFailed;
        case 'app_path_failed':
          return s.cliErrorAppPathFailed;
        case 'write_cmd_failed':
          return s.cliErrorWriteCmdFailed;
        case 'locate_launcher_failed':
          return s.cliErrorLocateLauncherFailed;
        case 'symlink_failed':
          return s.cliErrorSymlinkFailed;
        case 'auth_script_init_failed':
          return s.cliErrorAuthScriptInitFailed;
        case 'platform_not_supported':
          return s.cliErrorPlatformNotSupported;
        case 'unknown_error':
          return s.cliErrorUnknown;
      }
    }
    return message;
  }

  String? localizedWarning(AppStrings s) {
    final codes = warningCodes ?? (warningCode != null ? [warningCode!] : null);
    if (codes != null && codes.isNotEmpty) {
      final parts = <String>[];
      for (final code in codes) {
        if (code == 'path_failed') {
          parts.add(s.cliWarningPathFailed);
        } else if (code == 'ps1_update_failed') {
          parts.add(s.cliWarningPs1UpdateFailed);
        } else if (code == 'ps1_create_failed') {
          parts.add(s.cliWarningPs1CreateFailed);
        } else if (code == 'cli_tool_failed') {
          parts.add(s.cliWarningCliToolFailed);
        }
      }
      if (parts.isNotEmpty) {
        return s.cliWarningCombined(parts);
      }
    }
    return warning;
  }
}

class NativeCliService {
  static const MethodChannel channel = MethodChannel('com.sogoodviewer.app');

  static bool get isSupported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Queries the current installation status of `sgv` CLI symlink in /usr/local/bin
  static Future<CliStatus> checkStatus() async {
    if (!isSupported) {
      return CliStatus.empty();
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('checkCliStatus');
      if (res != null) {
        final warningCode = res['warningCode'] as String?;
        final warning = res['warning'] as String?;
        return CliStatus(
          isInstalled: res['isInstalled'] == true,
          isPartial: res['isPartial'] == true,
          path: res['path'] as String? ?? '',
          target: res['target'] as String? ?? '',
          isCurrentApp: res['isCurrentApp'] == true,
          warningCode: warningCode,
          warning: warning,
        );
      }
    } catch (e) {
      return CliStatus(
        isInstalled: false,
        isPartial: false,
        path: '',
        target: '',
        isCurrentApp: false,
        error: e.toString(),
      );
    }
    return CliStatus.empty();
  }

  /// Installs or updates the `sgv` CLI symlink in /usr/local/bin
  static Future<CliOperationResult> install() async {
    if (!isSupported) {
      return const CliOperationResult(
        isSuccess: false,
        messageCode: 'platform_not_supported',
        message: '当前平台暂不支持一键安装 CLI 命令',
      );
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('installCli');
      if (res != null) {
        final status = res['status'] as String?;
        final messageCode = res['messageCode'] as String?;
        final message = res['message'] as String?;
        if (status == 'success') {
          final warningCodesRaw = res['warningCodes'];
          List<String>? warningCodes;
          if (warningCodesRaw is List) {
            warningCodes = warningCodesRaw.map((e) => e.toString()).toList();
          }
          final warningCode = res['warningCode'] as String? ??
              (warningCodes != null && warningCodes.isNotEmpty ? warningCodes.first : null);
          return CliOperationResult(
            isSuccess: true,
            messageCode: messageCode,
            message: message,
            warning: res['warning'] as String?,
            warningCode: warningCode,
            warningCodes: warningCodes,
            path: res['path'] as String?,
          );
        } else if (status == 'cancelled') {
          return CliOperationResult(
            isSuccess: false,
            isCancelled: true,
            messageCode: messageCode ?? 'user_cancelled',
            message: message ?? '已取消授权',
          );
        } else {
          return CliOperationResult(
            isSuccess: false,
            messageCode: messageCode,
            message: message ?? '安装失败',
          );
        }
      }
    } catch (e) {
      return CliOperationResult(
        isSuccess: false,
        message: e.toString(),
      );
    }
    return const CliOperationResult(
      isSuccess: false,
      messageCode: 'unknown_error',
      message: '未知错误',
    );
  }

  /// Uninstalls / removes the `sgv` CLI symlink from /usr/local/bin
  static Future<CliOperationResult> uninstall() async {
    if (!isSupported) {
      return const CliOperationResult(
        isSuccess: false,
        messageCode: 'platform_not_supported',
        message: '当前平台暂不支持',
      );
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('uninstallCli');
      if (res != null) {
        final status = res['status'] as String?;
        final messageCode = res['messageCode'] as String?;
        final message = res['message'] as String?;
        if (status == 'success') {
          return CliOperationResult(
            isSuccess: true,
            messageCode: messageCode,
            message: message,
            warning: res['warning'] as String?,
          );
        } else if (status == 'cancelled') {
          return CliOperationResult(
            isSuccess: false,
            isCancelled: true,
            messageCode: messageCode ?? 'user_cancelled',
            message: message ?? '已取消授权',
          );
        } else {
          return CliOperationResult(
            isSuccess: false,
            messageCode: messageCode,
            message: message ?? '卸载失败',
          );
        }
      }
    } catch (e) {
      return CliOperationResult(
        isSuccess: false,
        message: e.toString(),
      );
    }
    return const CliOperationResult(
      isSuccess: false,
      messageCode: 'unknown_error',
      message: '未知错误',
    );
  }

  /// Queries the initial file passed to the app via macOS openFiles on cold launch
  static Future<String?> getInitialFile() async {
    if (!isSupported) return null;
    try {
      return await channel.invokeMethod<String>('getInitialFile');
    } catch (_) {
      return null;
    }
  }
}
