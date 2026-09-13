import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_cli_service.dart';

void showCliToolsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => const _CliToolsDialog(),
  );
}

class _CliToolsDialog extends StatefulWidget {
  const _CliToolsDialog();

  @override
  State<_CliToolsDialog> createState() => _CliToolsDialogState();
}

class _CliToolsDialogState extends State<_CliToolsDialog> {
  bool _isLoading = true;
  bool _isOperating = false;
  CliStatus _status = CliStatus.empty();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() => _isLoading = true);
    final s = await NativeCliService.checkStatus();
    if (mounted) {
      setState(() {
        _status = s;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleInstall() async {
    setState(() => _isOperating = true);
    final res = await NativeCliService.install();
    if (mounted) {
      setState(() => _isOperating = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 \'sgv\' 命令行工具已成功安装！可在终端直接使用。'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 3),
          ),
        );
      } else if (res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已取消授权操作'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('安装失败: ${res.message}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _loadStatus();
    }
  }

  Future<void> _handleUninstall() async {
    setState(() => _isOperating = true);
    final res = await NativeCliService.uninstall();
    if (mounted) {
      setState(() => _isOperating = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功卸载 \'sgv\' 命令行工具'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      } else if (res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已取消授权操作'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('卸载失败: ${res.message}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _loadStatus();
    }
  }

  void _copyCommand(String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制命令: $cmd'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.terminal_rounded,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '命令行工具 (sgv)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Platform.isWindows
                              ? '在终端 (CMD / PowerShell) 中随时通过 sgv 命令打开 Markdown'
                              : '在 macOS 终端中随时通过 sgv 命令打开 Markdown',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Status Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF3F3F46) : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: _isLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _status.isInstalled
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _status.isInstalled ? '已就绪 (已安装在系统 PATH)' : '尚未安装到系统终端',
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: _status.isInstalled
                                      ? (_status.isCurrentApp ? null : Colors.orange)
                                      : theme.textTheme.bodyMedium?.color,
                                ),
                              ),
                            ],
                          ),
                          if (_status.isInstalled) ...[
                            const SizedBox(height: 8),
                            Text(
                              '软链接路径: ${_status.path}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              if (!_status.isInstalled)
                                FilledButton.icon(
                                  onPressed: _isOperating ? null : _handleInstall,
                                  icon: _isOperating
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.download_done_rounded, size: 16),
                                  label: const Text('一键安装到终端'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else ...[
                                OutlinedButton.icon(
                                  onPressed: _isOperating ? null : _handleInstall,
                                  icon: const Icon(Icons.sync_rounded, size: 15),
                                  label: const Text('重新链接 / 修复'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  onPressed: _isOperating ? null : _handleUninstall,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 15,
                                    color: Colors.redAccent,
                                  ),
                                  label: const Text(
                                    '卸载',
                                    style: TextStyle(color: Colors.redAccent),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 18),

              // Usage Guide
              const Text(
                '使用示例',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _CommandRow(
                command: 'sgv README.md',
                description: '打开当前目录下的 Markdown 文档',
                onCopy: () => _copyCommand('sgv README.md'),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _CommandRow(
                command: Platform.isWindows ? 'sgv .\\notes\\todo.md' : 'sgv ~/notes/todo.md',
                description: '支持绝对路径与相对路径',
                onCopy: () => _copyCommand(Platform.isWindows ? 'sgv .\\notes\\todo.md' : 'sgv ~/notes/todo.md'),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _CommandRow(
                command: 'sgv',
                description: '快速激活或启动超好读',
                onCopy: () => _copyCommand('sgv'),
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              Text(
                Platform.isWindows
                    ? '提示：安装后可在命令提示符、PowerShell 或 Windows Terminal 中直接运行 sgv 命令。'
                    : '提示：点击安装若系统需要权限，macOS 会自动弹出指纹或管理员密码授权窗口，无需您手动打开终端输入任何命令。',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  final String command;
  final String description;
  final VoidCallback onCopy;
  final bool isDark;

  const _CommandRow({
    required this.command,
    required this.description,
    required this.onCopy,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  command,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8),
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 14),
            tooltip: '复制命令',
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
