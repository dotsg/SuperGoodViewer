import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Lightweight local IPC service enabling the `sgv` CLI command to instantly
/// communicate target file paths to an already-running SuperGoodViewer instance.
class CliIpcService {
  static ServerSocket? _server;
  static StreamSubscription<Socket>? _serverSub;

  static String get socketPath {
    final user = Platform.environment['USER'] ?? 'user';
    return '/tmp/sgv_$user.sock';
  }

  /// Starts the Unix domain socket server and listens for incoming file path payloads.
  static Future<void> start(void Function(String filePath) onFileReceived) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return;
    }

    try {
      final file = File(socketPath);
      if (await file.exists()) {
        try {
          // Attempt to connect to check if another instance is alive
          final probe = await Socket.connect(
            InternetAddress(socketPath, type: InternetAddressType.unix),
            0,
            timeout: const Duration(milliseconds: 300),
          );
          probe.destroy();
          // Another instance is already listening on this socket
          return;
        } catch (_) {
          // Stale socket file from a previously killed instance; remove it
          await file.delete();
        }
      }

      final addr = InternetAddress(socketPath, type: InternetAddressType.unix);
      _server = await ServerSocket.bind(addr, 0);

      _serverSub = _server?.listen((Socket client) {
        client.listen(
          (List<int> bytes) {
            try {
              final rawPath = utf8.decode(bytes).trim();
              if (rawPath.isNotEmpty) {
                onFileReceived(rawPath);
              }
            } catch (_) {}
          },
          onError: (_) {},
          cancelOnError: true,
        );
      });
    } catch (_) {
      // Non-fatal: if socket cannot be created, falls back to native system events
    }
  }

  /// Closes the IPC server and cleans up the socket file.
  static Future<void> stop() async {
    try {
      await _serverSub?.cancel();
      _serverSub = null;
      await _server?.close();
      _server = null;
      final file = File(socketPath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
