import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../i18n/app_localizations.dart';
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
    final s = context.strings;
    setState(() => _isOperating = true);
    final res = await NativeCliService.install();
    if (mounted) {
      setState(() => _isOperating = false);
      if (res.isSuccess) {
        final warnMsg = res.localizedWarning(s);
        if (warnMsg != null && warnMsg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ $warnMsg'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          final customMsg = res.localizedMessage(s);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (customMsg != null && customMsg.isNotEmpty)
                    ? customMsg
                    : s.cliInstallSuccess,
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else if (res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.cliAuthCancelled),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        final detail = res.localizedMessage(s) ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.cliInstallFailed(detail)),
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
    final s = context.strings;
    setState(() => _isOperating = true);
    final res = await NativeCliService.uninstall();
    if (mounted) {
      setState(() => _isOperating = false);
      if (res.isSuccess) {
        final warnMsg = res.localizedWarning(s);
        if (warnMsg != null && warnMsg.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ $warnMsg'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          final customMsg = res.localizedMessage(s);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (customMsg != null && customMsg.isNotEmpty)
                    ? customMsg
                    : s.cliUninstallSuccess,
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else if (res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.cliAuthCancelled),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        final detail = res.localizedMessage(s) ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.cliUninstallFailed(detail)),
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
        content: Text(context.strings.copiedCommand(cmd)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = context.strings;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 12,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
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
                        Text(
                          s.cliTitle,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          Platform.isWindows
                              ? s.cliDescWin
                              : Platform.isLinux
                                  ? s.cliDescLinux
                                  : s.cliDescMac,
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
                                      : (_status.isPartial
                                          ? Colors.orange
                                          : const Color(0xFF94A3B8)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _status.isInstalled
                                      ? s.cliStatusReady
                                      : (_status.isPartial
                                          ? (_status.localizedWarning(s) ?? s.cliStatusPartialTools)
                                          : s.cliStatusNotInstalled),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: _status.isInstalled
                                        ? (_status.isCurrentApp ? null : Colors.orange)
                                        : (_status.isPartial
                                            ? Colors.orange
                                            : theme.textTheme.bodyMedium?.color),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if ((_status.isInstalled || _status.isPartial) && _status.path.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              s.cliSymlinkPath(_status.path),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: Colors.grey,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (!_status.isInstalled) ...[
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
                                  label: Text(_status.isPartial ? s.cliReinstallRepair : s.cliInstall),
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
                                ),
                                if (_status.isPartial)
                                  OutlinedButton.icon(
                                    onPressed: _isOperating ? null : _handleUninstall,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 15,
                                      color: Colors.redAccent,
                                    ),
                                    label: Text(
                                      s.cliCleanUninstall,
                                      style: const TextStyle(color: Colors.redAccent),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      textStyle: const TextStyle(fontSize: 12.5),
                                    ),
                                  ),
                              ] else ...[
                                OutlinedButton.icon(
                                  onPressed: _isOperating ? null : _handleInstall,
                                  icon: const Icon(Icons.sync_rounded, size: 15),
                                  label: Text(s.cliRelink),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    textStyle: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _isOperating ? null : _handleUninstall,
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 15,
                                    color: Colors.redAccent,
                                  ),
                                  label: Text(
                                    s.cliUninstall,
                                    style: const TextStyle(color: Colors.redAccent),
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
              Text(
                s.cliUsageExamples,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _CommandRow(
                command: 'sgv README.md',
                description: s.cliExampleOpenMarkdown,
                onCopy: () => _copyCommand('sgv README.md'),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _CommandRow(
                command: 'sgv export README.md -o output.pdf',
                description: s.cliExampleExportSingle,
                onCopy: () => _copyCommand('sgv export README.md -o output.pdf'),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _CommandRow(
                command: Platform.isWindows ? 'sgv export .\\docs -o .\\dist' : 'sgv export ./docs -o ./dist',
                description: s.cliExampleExportBatch,
                onCopy: () => _copyCommand(Platform.isWindows ? 'sgv export .\\docs -o .\\dist' : 'sgv export ./docs -o ./dist'),
                isDark: isDark,
              ),
              const SizedBox(height: 6),
              _CommandRow(
                command: 'sgv',
                description: s.cliExampleLaunch,
                onCopy: () => _copyCommand('sgv'),
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              Text(
                Platform.isWindows
                    ? s.cliTipWin
                    : Platform.isLinux
                        ? s.cliTipLinux
                        : s.cliTipMac,
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
    final s = context.strings;
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
            tooltip: s.copyCommandTooltip,
            visualDensity: VisualDensity.compact,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
