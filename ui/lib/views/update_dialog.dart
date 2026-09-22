import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';
import '../models/update_info.dart';
import '../services/update_service.dart';

enum _UpdateState {
  idle,
  downloading,
  readyToRestart,
  installing,
  error,
}

/// A publication-grade modal dialog presenting release notes, download progress,
/// and in-place restart controls for SuperGoodViewer.
class UpdateDialog extends StatefulWidget {
  final ReaderController controller;
  final UpdateInfo info;

  const UpdateDialog({
    super.key,
    required this.controller,
    required this.info,
  });

  static Future<void> show(
    BuildContext context,
    ReaderController controller,
    UpdateInfo info,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(controller: controller, info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateState _state = _UpdateState.idle;
  double _progress = 0.0;
  String _progressText = '';
  String _errorMessage = '';
  String? _downloadedFilePath;
  UpdateCancellationToken? _cancelToken;
  bool _isInstalling = false;

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    final assetUrl = widget.info.assetUrl;
    final assetName = widget.info.assetName ?? 'SuperGoodViewer-update';

    if (assetUrl == null || assetUrl.isEmpty) {
      // Fallback: open release page in browser
      final uri = Uri.parse(widget.info.htmlUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
      return;
    }

    final token = UpdateCancellationToken();
    _cancelToken = token;

    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0.0;
      _progressText = '0.0%';
    });

    try {
      final path = await UpdateService.instance.downloadUpdateAsset(
        assetUrl,
        assetName,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            final p = (received / total).clamp(0.0, 1.0);
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = p;
              _progressText = '$recMb MB / $totMb MB (${(p * 100).toStringAsFixed(0)}%)';
            });
          } else {
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            setState(() {
              _progress = 0.5;
              _progressText = '$recMb MB';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadedFilePath = path;
          _state = _UpdateState.readyToRestart;
        });
      }
    } on UpdateCancelledException {
      // User cancelled download, don't set error state
      return;
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = e.toString();
        });
      }
    } finally {
      if (_cancelToken == token) {
        _cancelToken = null;
      }
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel();
    _cancelToken = null;
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _applyAndRestart() async {
    if (_isInstalling || _downloadedFilePath == null) return;
    setState(() {
      _isInstalling = true;
      _state = _UpdateState.installing;
    });

    try {
      await UpdateService.instance.installAndRestart(
        downloadedFilePath: _downloadedFilePath!,
      );
    } on IncompatibleArchitectureException catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _state = _UpdateState.error;
          _errorMessage = '${e.message}\n请前往 GitHub Releases 页面手动下载匹配当前硬件架构的安装包。';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _state = _UpdateState.error;
          _errorMessage = '安装更新时出错: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final s = widget.controller.strings;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 16,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: PopScope(
        canPop: _state != _UpdateState.installing,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop && _state == _UpdateState.downloading) {
            _cancelToken?.cancel();
          }
        },
        child: Container(
          width: 520,
          constraints: const BoxConstraints(maxHeight: 580),
          padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Icon + Title + Version pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colorScheme.primary,
                        theme.colorScheme.secondary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            s.updateAvailable,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v${widget.info.latestVersion}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '当前版本: v${widget.info.currentVersion}${widget.info.formattedSize.isNotEmpty ? '  •  大小: ${widget.info.formattedSize}' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Release notes container
            const Text(
              '更新内容与优化 (Release Notes)',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262626) : const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark ? const Color(0xFF383838) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    widget.info.releaseNotes.isNotEmpty
                        ? widget.info.releaseNotes
                        : '包含性能优化与稳定性提升。',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Progress Bar / State view
            if (_state == _UpdateState.downloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 6,
                      backgroundColor: isDark ? Colors.white10 : Colors.black12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        s.downloadingUpdate,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      Text(
                        _progressText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ] else if (_state == _UpdateState.readyToRestart) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '更新包已就绪！重启软件后将瞬间生效。',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (_state == _UpdateState.installing) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        s.installingUpdate,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ] else if (_state == _UpdateState.error) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage.isNotEmpty ? _errorMessage : s.updateFailed,
                        style: const TextStyle(fontSize: 11.5, color: Colors.red),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // Action Buttons
            Row(
              children: [
                if (_state == _UpdateState.idle) ...[
                  TextButton(
                    onPressed: () {
                      unawaited(UpdateService.instance.ignoreVersion(widget.info.latestVersion));
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      s.skipThisVersion,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      s.remindMeLater,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 14),
                    label: Text(s.viewOnWeb, style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final uri = Uri.parse(widget.info.htmlUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 15),
                    label: Text(s.updateNow, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    onPressed: _startDownload,
                  ),
                ] else if (_state == _UpdateState.downloading) ...[
                  const Spacer(),
                  OutlinedButton(
                    onPressed: _cancelDownload,
                    child: Text(s.cancel, style: const TextStyle(fontSize: 12)),
                  ),
                ] else if (_state == _UpdateState.readyToRestart) ...[
                  const Spacer(),
                  TextButton(
                    onPressed: _isInstalling ? null : () => Navigator.of(context).pop(),
                    child: Text(s.remindMeLater, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: Text(
                      s.restartToUpdate,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _isInstalling ? null : _applyAndRestart,
                  ),
                ] else if (_state == _UpdateState.installing) ...[
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: null,
                    icon: const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                    label: Text(
                      s.installingUpdate,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ] else if (_state == _UpdateState.error) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 14),
                    label: Text(s.viewOnWeb, style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final uri = Uri.parse(widget.info.htmlUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.close, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: Text(s.retry, style: const TextStyle(fontSize: 12.5)),
                    onPressed: _startDownload,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
}
