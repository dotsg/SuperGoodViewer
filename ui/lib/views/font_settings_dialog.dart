import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';

void showFontSettingsDialog(BuildContext context, ReaderController controller) {
  showDialog(
    context: context,
    builder: (ctx) => _FontSettingsDialog(controller: controller),
  );
}

class _FontSettingsDialog extends StatefulWidget {
  final ReaderController controller;

  const _FontSettingsDialog({required this.controller});

  @override
  State<_FontSettingsDialog> createState() => _FontSettingsDialogState();
}

class _FontSettingsDialogState extends State<_FontSettingsDialog> {
  late String? _selectedBodyFont;
  late String? _selectedCodeFont;

  @override
  void initState() {
    super.initState();
    _selectedBodyFont = widget.controller.renderOptions.bodyFont;
    _selectedCodeFont = widget.controller.renderOptions.codeFont;
  }

  Future<void> _openMapleGitHub() async {
    final uri = Uri.parse('https://github.com/subframe7536/maple-font/releases');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _copyDownloadLink() {
    Clipboard.setData(
      const ClipboardData(text: 'https://github.com/subframe7536/maple-font'),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制 Maple Mono GitHub 链接到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final report = widget.controller.fontReport;
    final hasCjkMono = report['has_cjk_monospace'] == true;
    final mapleInstalled = report['maple_mono_installed'] == true;

    final bodyFontOptions = [
      {'label': '系统出版推荐 (Inter + SF Pro + 苹方/微软雅黑)', 'value': null},
      {'label': '苹方 (PingFang SC)', 'value': 'PingFang SC'},
      {'label': '宋体 (Songti SC)', 'value': 'Songti SC'},
      {'label': '冬青黑体 (Hiragino Sans GB)', 'value': 'Hiragino Sans GB'},
      {'label': '微软雅黑 (Microsoft YaHei)', 'value': 'Microsoft YaHei'},
      {'label': '思源黑体 (Source Han Sans SC)', 'value': 'Source Han Sans SC'},
      {'label': 'Inter (现代无衬线)', 'value': 'Inter'},
    ];

    final codeFontOptions = [
      {'label': 'Maple Mono (推荐: 1:2 严格等宽对齐)', 'value': null},
      {'label': 'JetBrains Mono', 'value': 'JetBrains Mono'},
      {'label': 'Fira Code', 'value': 'Fira Code'},
      {'label': 'Menlo (系统默认等宽)', 'value': 'Menlo'},
      {'label': 'Cascadia Code', 'value': 'Cascadia Code'},
      {'label': 'Consolas', 'value': 'Consolas'},
    ];

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF242424) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.font_download_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '字体排版与中英文等宽对齐',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '定制正文与代码等宽字体，保证 ASCII 字符画与表格严格 1:2 对齐',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 18),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Maple Mono / CJK Monospace Status Banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hasCjkMono
                            ? (isDark ? const Color(0x1F22C55E) : const Color(0x1416A34A))
                            : (isDark ? const Color(0x28F59E0B) : const Color(0x1AF59E0B)),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasCjkMono
                              ? const Color(0x4022C55E)
                              : const Color(0x60F59E0B),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                hasCjkMono
                                    ? Icons.check_circle_rounded
                                    : Icons.info_outline_rounded,
                                color: hasCjkMono
                                    ? const Color(0xFF22C55E)
                                    : const Color(0xFFF59E0B),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  hasCjkMono
                                      ? (mapleInstalled
                                          ? '系统已就绪 Maple Mono (1:2 严格等宽)'
                                          : '系统已检测到 CJK 严格等宽字体')
                                      : '建议安装 Maple Mono 字体以获得最佳对齐',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5,
                                    color: hasCjkMono
                                        ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                                        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hasCjkMono
                              ? '当前系统已加载 CJK 等宽字体，文档中包含的 ASCII 字符表格、流程图与代码行可实现 1 个全角汉字严格等于 2 个半角英文字符，边框绝不发生锯齿撕裂。'
                              : '检测到当前环境缺少 CJK 严格等宽字体。源码中的 ASCII 字符画表格或包含中英文混合的代码行可能会出现轻微对齐偏移。推荐下载安装开源 Maple Mono 字体。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                                label: const Text('前往 GitHub 下载 Maple Mono', style: TextStyle(fontSize: 11.5)),
                                onPressed: _openMapleGitHub,
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.copy_rounded, size: 14),
                                label: const Text('复制链接', style: TextStyle(fontSize: 11.5)),
                                onPressed: _copyDownloadLink,
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.refresh_rounded, size: 14),
                                label: const Text('重新检测', style: TextStyle(fontSize: 11.5)),
                                onPressed: () {
                                  widget.controller.refreshFontReport();
                                  setState(() {});
                                },
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Body Font Selection
                    const Text(
                      '正文排版字体 (Body Typography)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: _selectedBodyFont,
                          items: bodyFontOptions.map((opt) {
                            return DropdownMenuItem<String?>(
                              value: opt['value'],
                              child: Text(
                                opt['label'] as String,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedBodyFont = val);
                            widget.controller.setBodyFont(val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Code / ASCII Font Selection
                    Row(
                      children: [
                        const Flexible(
                          child: Text(
                            '代码与 ASCII 表格字体 (Monospace Typography)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (mapleInstalled)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Maple Mono 已激活',
                              style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: _selectedCodeFont,
                          items: codeFontOptions.map((opt) {
                            return DropdownMenuItem<String?>(
                              value: opt['value'],
                              child: Text(
                                opt['label'] as String,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedCodeFont = val);
                            widget.controller.setCodeFont(val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Live Alignment Preview Card
                    const Text(
                      'ASCII 表格全角/半角对齐预览 (Live Alignment Preview)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF181818) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF333333) : const Color(0xFFCBD5E1),
                        ),
                      ),
                      child: const SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Text(
                          '┌─────────────────────────────────────┬─────────────────────────────────────┐\n'
                          '│ 1. Token 資產治理與商業分銷         │ 2. 可插拔合規安全護欄               │\n'
                          '│  · 基於 Envoy AI Gateway 雲原生底座 │  · 基於 Go ext_proc 高性能自研中間件│\n'
                          '│  · 官方渠道加價轉售 + 租戶 BYOK 雙軌│  · 香港 PDPO 專屬合規套件 (L0~L3)   │\n'
                          '└─────────────────────────────────────┴─────────────────────────────────────┘',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.3,
                            letterSpacing: 0.0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Footer actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedBodyFont = null;
                      _selectedCodeFont = null;
                    });
                    widget.controller.setBodyFont(null);
                    widget.controller.setCodeFont(null);
                  },
                  child: const Text('恢复默认字体'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('完成'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
