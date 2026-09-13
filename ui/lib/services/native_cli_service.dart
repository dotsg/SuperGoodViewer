import 'dart:io';
import 'package:flutter/services.dart';

class CliStatus {
  final bool isInstalled;
  final String path;
  final String target;
  final bool isCurrentApp;
  final String? error;

  const CliStatus({
    required this.isInstalled,
    required this.path,
    required this.target,
    required this.isCurrentApp,
    this.error,
  });

  factory CliStatus.empty() {
    return const CliStatus(
      isInstalled: false,
      path: '',
      target: '',
      isCurrentApp: false,
    );
  }
}

class CliOperationResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? message;
  final String? path;

  const CliOperationResult({
    required this.isSuccess,
    this.isCancelled = false,
    this.message,
    this.path,
  });
}

class NativeCliService {
  static const MethodChannel channel = MethodChannel('com.sogoodviewer.app');

  static bool get isSupported => Platform.isMacOS || Platform.isWindows;

  /// Queries the current installation status of `sgv` CLI symlink in /usr/local/bin
  static Future<CliStatus> checkStatus() async {
    if (!isSupported) {
      return CliStatus.empty();
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('checkCliStatus');
      if (res != null) {
        return CliStatus(
          isInstalled: res['isInstalled'] == true,
          path: res['path'] as String? ?? '',
          target: res['target'] as String? ?? '',
          isCurrentApp: res['isCurrentApp'] == true,
        );
      }
    } catch (e) {
      return CliStatus(
        isInstalled: false,
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
        message: '当前平台暂不支持一键安装 CLI 命令',
      );
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('installCli');
      if (res != null) {
        final status = res['status'] as String?;
        if (status == 'success') {
          return CliOperationResult(
            isSuccess: true,
            path: res['path'] as String?,
          );
        } else if (status == 'cancelled') {
          return const CliOperationResult(
            isSuccess: false,
            isCancelled: true,
            message: '已取消授权',
          );
        } else {
          return CliOperationResult(
            isSuccess: false,
            message: res['message'] as String? ?? '安装失败',
          );
        }
      }
    } catch (e) {
      return CliOperationResult(
        isSuccess: false,
        message: e.toString(),
      );
    }
    return const CliOperationResult(isSuccess: false, message: '未知错误');
  }

  /// Uninstalls / removes the `sgv` CLI symlink from /usr/local/bin
  static Future<CliOperationResult> uninstall() async {
    if (!isSupported) {
      return const CliOperationResult(
        isSuccess: false,
        message: '当前平台暂不支持',
      );
    }
    try {
      final res = await channel.invokeMapMethod<String, dynamic>('uninstallCli');
      if (res != null) {
        final status = res['status'] as String?;
        if (status == 'success') {
          return const CliOperationResult(isSuccess: true);
        } else if (status == 'cancelled') {
          return const CliOperationResult(
            isSuccess: false,
            isCancelled: true,
            message: '已取消授权',
          );
        } else {
          return CliOperationResult(
            isSuccess: false,
            message: res['message'] as String? ?? '卸载失败',
          );
        }
      }
    } catch (e) {
      return CliOperationResult(
        isSuccess: false,
        message: e.toString(),
      );
    }
    return const CliOperationResult(isSuccess: false, message: '未知错误');
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
