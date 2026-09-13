import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';
import '../services/document_cache_service.dart';
import '../services/native_cli_service.dart';
import '../services/shortcut_service.dart';

/// Available tabs within the unified SettingsDialog.
enum SettingsTab {
  general,
  typography,
  shortcuts,
  cli,
  about,
}

/// Opens the unified SettingsDialog with an optional starting tab.
void showSettingsDialog(
  BuildContext context,
  ReaderController controller, {
  SettingsTab initialTab = SettingsTab.general,
}) {
  showDialog(
    context: context,
    builder: (ctx) => SettingsDialog(
      controller: controller,
      initialTab: initialTab,
    ),
  );
}

class SettingsDialog extends StatefulWidget {
  static const String appVersion = '1.0.4';

  final ReaderController controller;
  final SettingsTab initialTab;

  const SettingsDialog({
    super.key,
    required this.controller,
    this.initialTab = SettingsTab.general,
  });

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late SettingsTab _currentTab;

  // Typography state
  late String? _selectedBodyFont;
  late String? _selectedCodeFont;
  late double _selectedFontSize;
  bool _isScanningFonts = false;

  bool get _hasUnsavedTypographyChanges {
    final opts = widget.controller.renderOptions;
    return _selectedBodyFont != opts.bodyFont ||
        _selectedCodeFont != opts.codeFont ||
        (_selectedFontSize - opts.fontSize).abs() > 0.01;
  }

  void _saveTypography() {
    widget.controller.setTypography(
      bodyFont: _selectedBodyFont,
      codeFont: _selectedCodeFont,
      fontSize: _selectedFontSize,
    );
    setState(() {});
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null && Scaffold.maybeOf(context) != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('字体排版设置已保存，正在重新渲染当前文档...'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  void _revertTypography() {
    setState(() {
      _selectedBodyFont = widget.controller.renderOptions.bodyFont;
      _selectedCodeFont = widget.controller.renderOptions.codeFont;
      _selectedFontSize = widget.controller.renderOptions.fontSize;
    });
  }

  // Shortcuts state
  String? _listeningActionId;
  String? _conflictMessage;

  // CLI state
  bool _isLoadingCli = true;
  bool _isOperatingCli = false;
  CliStatus _cliStatus = CliStatus.empty();

  // Cache state
  CacheStats _cacheStats = CacheStats(
    fileCount: 0,
    totalBytes: 0,
    dirPath: DocumentCacheService.cacheDirectoryPath,
  );
  bool _isLoadingCache = true;
  bool _isClearingCache = false;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _selectedBodyFont = widget.controller.renderOptions.bodyFont;
    _selectedCodeFont = widget.controller.renderOptions.codeFont;
    _selectedFontSize = widget.controller.renderOptions.fontSize;
    _loadCacheStats();
    _loadCliStatus();
  }

  Future<void> _loadCacheStats() async {
    final stats = await DocumentCacheService.getCacheStats();
    if (mounted) {
      setState(() {
        _cacheStats = stats;
        _isLoadingCache = false;
      });
    }
  }

  Future<void> _handleClearCache() async {
    setState(() => _isClearingCache = true);
    final cleared = await DocumentCacheService.clearCache();
    final newStats = await DocumentCacheService.getCacheStats();
    if (mounted) {
      setState(() {
        _isClearingCache = false;
        _cacheStats = newStats;
      });
      try {
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger != null) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('已清理 ${cleared.deletedCount} 个编译缓存文件 (${cleared.formattedFreedSize})'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _loadCliStatus() async {
    setState(() => _isLoadingCli = true);
    final s = await NativeCliService.checkStatus();
    if (mounted) {
      setState(() {
        _cliStatus = s;
        _isLoadingCli = false;
      });
    }
  }

  Future<void> _handleInstallCli() async {
    setState(() => _isOperatingCli = true);
    final res = await NativeCliService.install();
    if (mounted) {
      setState(() => _isOperatingCli = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 \'sgv\' 命令行工具已成功安装！可在终端直接使用。'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 3),
          ),
        );
      } else if (!res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('安装失败: ${res.message}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _loadCliStatus();
    }
  }

  Future<void> _handleUninstallCli() async {
    setState(() => _isOperatingCli = true);
    final res = await NativeCliService.uninstall();
    if (mounted) {
      setState(() => _isOperatingCli = false);
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功卸载 \'sgv\' 命令行工具'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      } else if (!res.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('卸载失败: ${res.message}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      _loadCliStatus();
    }
  }

  void _copyCliCommand(String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制命令: $cmd'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openMapleGitHub() async {
    final uri = Uri.parse('https://github.com/subframe7536/maple-font/releases');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _copyMapleDownloadLink() {
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

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF222222) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 880,
        height: 640,
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Navigation Sidebar
            _buildSidebar(theme, isDark),

            // Vertical Divider
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),

            // Right Tab Content
            Expanded(
              child: ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) => _buildTabContent(theme, isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, bool isDark) {
    return Container(
      width: 180,
      color: isDark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F7F7),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Settings Title Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.settings_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  '偏好设置',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Nav Items
          _buildNavItem(
            tab: SettingsTab.general,
            label: '常规阅读',
            icon: Icons.tune_rounded,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.typography,
            label: '排版与字体',
            icon: Icons.font_download_outlined,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.shortcuts,
            label: '快捷键',
            icon: Icons.keyboard_outlined,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.cli,
            label: '命令行 (sgv)',
            icon: Icons.terminal_rounded,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.about,
            label: '关于软件',
            icon: Icons.info_outline_rounded,
            theme: theme,
            isDark: isDark,
          ),

          const Spacer(),

          // Version hint at bottom of sidebar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              'SuperGoodViewer v${SettingsDialog.appVersion}',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required SettingsTab tab,
    required String label,
    required IconData icon,
    required ThemeData theme,
    required bool isDark,
  }) {
    final isSelected = _currentTab == tab;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              _currentTab = tab;
              _listeningActionId = null;
              _conflictMessage = null;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header of Current Tab
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getTabTitle(_currentTab),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getTabSubtitle(_currentTab),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
        ),

        // Tab Body
        Expanded(
          child: _currentTab == SettingsTab.typography
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                  child: _buildTypographyTab(theme, isDark),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: _buildActiveTabBody(theme, isDark),
                ),
        ),
      ],
    );
  }

  String _getTabTitle(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.general:
        return '常规与阅读偏好';
      case SettingsTab.typography:
        return '字体排版与中英文等宽对齐';
      case SettingsTab.shortcuts:
        return '快捷键自定义设置';
      case SettingsTab.cli:
        return '命令行工具 (sgv) 集成';
      case SettingsTab.about:
        return '关于 SuperGoodViewer';
    }
  }

  String _getTabSubtitle(SettingsTab tab) {
    switch (tab) {
      case SettingsTab.general:
        return '配置文件外部修改自动重载与阅读历史记录';
      case SettingsTab.typography:
        return '定制正文与等宽字体，支持全角半角 1:2 等宽对齐与实时渲染预览';
      case SettingsTab.shortcuts:
        return '自定义各常用操作的键盘快捷键，点击键位直接录制';
      case SettingsTab.cli:
        return '在终端中随时通过 sgv 命令秒级预览任何 Markdown';
      case SettingsTab.about:
        return '基于现代 Typst 0.13.1 编译器与无损矢量 PDFium 引擎构建';
    }
  }

  Widget _buildActiveTabBody(ThemeData theme, bool isDark) {
    switch (_currentTab) {
      case SettingsTab.general:
        return _buildGeneralTab(theme, isDark);
      case SettingsTab.typography:
        return _buildTypographyTab(theme, isDark);
      case SettingsTab.shortcuts:
        return _buildShortcutsTab(theme, isDark);
      case SettingsTab.cli:
        return _buildCliTab(theme, isDark);
      case SettingsTab.about:
        return _buildAboutTab(theme, isDark);
    }
  }

  // ==================== 1. GENERAL TAB ====================
  Widget _buildGeneralTab(ThemeData theme, bool isDark) {
    final controller = widget.controller;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Auto Reload Switch
        _buildSectionHeader('文档自动重载 (Hot Reload)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.sync_rounded, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '文件修改自动热重载 (Auto Reload)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '外部编辑器（如 VS Code / Cursor / Obsidian）保存文档时立即无缝重绘',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: controller.autoReload,
                onChanged: (val) => controller.setAutoReload(val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Session & History
        _buildSectionHeader('会话与历史记录 (Session & History)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.history_rounded, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '最近打开文档记录',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '已记录 ${controller.recentFiles.length} 个历史文档',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                    label: const Text('清空历史', style: TextStyle(fontSize: 12)),
                    onPressed: controller.recentFiles.isEmpty
                        ? null
                        : () {
                            controller.clearRecentFiles();
                            setState(() {});
                          },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(
                  height: 1,
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFEAEAEA),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.restore_page_outlined, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '启动恢复上次会话',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '重新启动应用时自动还原上次浏览文档与阅读进度',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '已启用',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Compiled Document Cache Section
        _buildSectionHeader('预编译 PDF 缓存 (Compiled Cache)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: isDark ? Colors.white70 : Colors.black87),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '本地磁盘缓存',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoadingCache
                              ? '正在读取缓存统计...'
                              : (_cacheStats.fileCount > 0
                                  ? '已缓存 ${_cacheStats.fileCount} 个文档 (${_cacheStats.formattedSize})'
                                  : '暂无缓存文件 (0 B)'),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 15),
                    label: const Text('打开目录', style: TextStyle(fontSize: 12)),
                    onPressed: () => DocumentCacheService.openCacheDirectory(),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: _isClearingCache
                        ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cleaning_services_outlined, size: 15),
                    label: const Text('清理缓存', style: TextStyle(fontSize: 12)),
                    onPressed: _isLoadingCache || _cacheStats.fileCount == 0 || _isClearingCache
                        ? null
                        : _handleClearCache,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(
                  height: 1,
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFEAEAEA),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: isDark ? const Color(0xFF666666) : const Color(0xFF999999)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '编译生成的矢量 PDF 会缓存到本地磁盘，用于实现秒级极速冷启动与历史切换。源文件编辑保存时会自动失效重编。',
                      style: TextStyle(
                        fontSize: 11.0,
                        color: isDark ? const Color(0xFF666666) : const Color(0xFF888888),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 2. TYPOGRAPHY TAB ====================
  Widget _buildTypographyTab(ThemeData theme, bool isDark) {
    final controller = widget.controller;
    final report = controller.fontReport;
    final hasCjkMono = report['has_cjk_monospace'] == true;
    final mapleInstalled = report['maple_mono_installed'] == true;

    final bodyFontOptions = <Map<String, String?>>[
      {'label': '系统出版推荐 (Inter + SF Pro + 苹方/微软雅黑)', 'value': null},
      {'label': '苹方 (PingFang SC)', 'value': 'PingFang SC'},
      {'label': '宋体 (Songti SC)', 'value': 'Songti SC'},
      {'label': '冬青黑体 (Hiragino Sans GB)', 'value': 'Hiragino Sans GB'},
      {'label': '微软雅黑 (Microsoft YaHei)', 'value': 'Microsoft YaHei'},
      {'label': '思源黑体 (Source Han Sans SC)', 'value': 'Source Han Sans SC'},
      {'label': 'Inter (现代无衬线)', 'value': 'Inter'},
    ];
    if (_selectedBodyFont != null &&
        !bodyFontOptions.any((opt) => opt['value'] == _selectedBodyFont)) {
      bodyFontOptions.add({
        'label': '$_selectedBodyFont (自定义)',
        'value': _selectedBodyFont,
      });
    }

    final detectedMono = (report['detected_monospace_fonts'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final baseCodeFonts = <Map<String, String?>>[
      {'label': 'Maple Mono (推荐: 1:2 严格等宽对齐)', 'value': null},
      {'label': 'Menlo (macOS 系统默认等宽)', 'value': 'Menlo'},
      {'label': 'Monaco (macOS 经典等宽)', 'value': 'Monaco'},
      {'label': 'Courier New (经典衬线等宽)', 'value': 'Courier New'},
      {'label': 'JetBrains Mono', 'value': 'JetBrains Mono'},
      {'label': 'Fira Code', 'value': 'Fira Code'},
      {'label': 'Cascadia Code', 'value': 'Cascadia Code'},
      {'label': 'Consolas', 'value': 'Consolas'},
    ];
    final codeFontOptions = <Map<String, String?>>[...baseCodeFonts];
    final knownValues = baseCodeFonts.map((m) => m['value']?.toLowerCase()).toSet();
    for (final monoName in detectedMono) {
      if (!knownValues.contains(monoName.toLowerCase()) &&
          !monoName.toLowerCase().contains('maple')) {
        codeFontOptions.add({
          'label': '$monoName (系统已安装)',
          'value': monoName,
        });
      }
    }
    if (_selectedCodeFont != null &&
        !codeFontOptions.any((opt) => opt['value'] == _selectedCodeFont)) {
      codeFontOptions.add({
        'label': '$_selectedCodeFont (自定义)',
        'value': _selectedCodeFont,
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Two-column side-by-side main area
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Column: Controls (fixed width, internally scrollable)
              SizedBox(
                width: 280,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Maple Mono / CJK Monospace Health Banner (compact)
                      _buildMapleHealthBanner(theme, isDark, hasCjkMono, mapleInstalled),
                      const SizedBox(height: 12),

                      // Body Font Dropdown
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              '正文排版字体 (Body Typography)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedBodyFont != null)
                            TextButton(
                              onPressed: () => setState(() => _selectedBodyFont = null),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              child: const Text('恢复推荐', style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildDropdown(
                        value: _selectedBodyFont,
                        items: bodyFontOptions,
                        onChanged: (val) => setState(() => _selectedBodyFont = val),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),

                      // Code Font Dropdown
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              '代码与 ASCII 表格字体 (Monospace Typography)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedCodeFont != null)
                            TextButton(
                              onPressed: () => setState(() => _selectedCodeFont = null),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                              ),
                              child: const Text('恢复默认', style: TextStyle(fontSize: 11)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildDropdown(
                        value: _selectedCodeFont,
                        items: codeFontOptions,
                        onChanged: (val) => setState(() => _selectedCodeFont = val),
                        isDark: isDark,
                      ),
                      const SizedBox(height: 12),

                      // Font Size Stepper & Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text(
                              '排版基础字号 (Base Typesetting Font Size)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedFontSize = 10.5),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            child: const Text('恢复默认 (10.5 pt)', style: TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark ? const Color(0xFF333333) : const Color(0xFFE0E0E0),
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_rounded, size: 16),
                              tooltip: '缩小字号',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () {
                                setState(() {
                                  _selectedFontSize = (_selectedFontSize - 0.5).clamp(8.0, 24.0);
                                });
                              },
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                ),
                                child: Slider(
                                  value: _selectedFontSize.clamp(8.0, 24.0),
                                  min: 8.0,
                                  max: 24.0,
                                  divisions: 32,
                                  label: '${_selectedFontSize.toStringAsFixed(1)} pt',
                                  onChanged: (val) {
                                    setState(() => _selectedFontSize = val);
                                  },
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              tooltip: '放大字号',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () {
                                setState(() {
                                  _selectedFontSize = (_selectedFontSize + 0.5).clamp(8.0, 24.0);
                                });
                              },
                            ),
                            Container(
                              width: 50,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 4),
                              child: Text(
                                '${_selectedFontSize.toStringAsFixed(1)} pt',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Reset Defaults Button
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _selectedBodyFont = null;
                                _selectedCodeFont = null;
                                _selectedFontSize = 10.5;
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 13),
                            label: const Text('恢复默认字体', style: TextStyle(fontSize: 11.5)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 14),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
              ),
              const SizedBox(width: 14),

              // Right Column: Live Typography Preview Card (Expanded)
              Expanded(
                child: _buildTypographyPreviewCard(theme, isDark),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
        ),
        const SizedBox(height: 8),

        // Bottom Bar: Save & Apply Button
        _buildTypographyBottomBar(theme, isDark),
      ],
    );
  }

  Widget _buildMapleHealthBanner(
    ThemeData theme,
    bool isDark,
    bool hasCjkMono,
    bool mapleInstalled,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: hasCjkMono
            ? (isDark ? const Color(0x1F22C55E) : const Color(0x1416A34A))
            : (isDark ? const Color(0x28F59E0B) : const Color(0x1AF59E0B)),
        borderRadius: BorderRadius.circular(8),
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
                hasCjkMono ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: hasCjkMono ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                size: 15,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasCjkMono
                      ? (mapleInstalled
                          ? 'Maple Mono 就绪 (1:2 严格等宽)'
                          : '检测到 CJK 严格等宽字体')
                      : '建议安装 Maple Mono 字体',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: hasCjkMono
                        ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            hasCjkMono
                ? 'CJK 严格等宽已生效，ASCII 表格与代码中英文严格 1:2 对齐。'
                : '缺少 CJK 等宽字体，ASCII 表格或混排代码可能有微弱错位。',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 12),
                label: const Text('下载字体', style: TextStyle(fontSize: 11)),
                onPressed: _openMapleGitHub,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 12),
                label: const Text('复制链接', style: TextStyle(fontSize: 11)),
                onPressed: _copyMapleDownloadLink,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                ),
              ),
              TextButton.icon(
                icon: _isScanningFonts
                    ? const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 12),
                label: Text(_isScanningFonts ? '检测中...' : '重新检测', style: const TextStyle(fontSize: 11)),
                onPressed: _isScanningFonts
                    ? null
                    : () async {
                        setState(() => _isScanningFonts = true);
                        try {
                          await widget.controller.refreshFontReport();
                        } finally {
                          if (mounted) {
                            setState(() => _isScanningFonts = false);
                          }
                        }
                      },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<Map<String, String?>> items,
    required ValueChanged<String?> onChanged,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          value: value,
          items: items.map((opt) {
            return DropdownMenuItem<String?>(
              value: opt['value'],
              child: Text(
                opt['label'] as String,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildTypographyBottomBar(ThemeData theme, bool isDark) {
    final hasChanges = _hasUnsavedTypographyChanges;

    return Row(
      children: [
        Icon(
          hasChanges ? Icons.edit_note_rounded : Icons.check_circle_outline_rounded,
          size: 16,
          color: hasChanges ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            hasChanges ? '排版设置有变动 (未保存到文档)' : '排版设置与当前文档一致',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: hasChanges
                  ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706))
                  : (isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
              fontWeight: hasChanges ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const Spacer(),
        if (hasChanges) ...[
          OutlinedButton(
            onPressed: _revertTypography,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            child: const Text('放弃修改', style: TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 15),
          label: const Text('保存并刷新文档', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            backgroundColor: hasChanges ? const Color(0xFF0284C7) : null,
          ),
          onPressed: hasChanges ? _saveTypography : null,
        ),
      ],
    );
  }

  Widget _buildTypographyPreviewCard(ThemeData theme, bool isDark) {
    final fontSize = _selectedFontSize;
    final bodyFont = _selectedBodyFont;
    final codeFont = _selectedCodeFont;
    final displayCodeFont = codeFont ?? 'Maple Mono (默认)';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF191919) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF383838) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Preview Top Status Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF222222) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '实时排版预览 (Live Preview)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Opacity(
                        opacity: 0.0,
                        child: SizedBox(
                          width: 0,
                          height: 0,
                          child: Text(
                            '排版实时渲染预览 (Live Typography Preview)',
                            style: TextStyle(fontSize: 0),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${fontSize.toStringAsFixed(1)} pt',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Preview Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Body Typography Sample
                  Text(
                    '现代出版级技术文档排版 (Publisher-Grade Typography)',
                    style: TextStyle(
                      fontFamily: bodyFont,
                      fontFamilyFallback: const [
                        'PingFang SC',
                        'Microsoft YaHei',
                        'Hiragino Sans GB',
                        'sans-serif',
                      ],
                      fontSize: (fontSize * 1.15).clamp(11.0, 20.0),
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SuperGoodViewer 专为高密度技术文档、工程规格说明书与论文设计。本段文字实时应用当前设置的正文字体与基础字号，展示精致的中西文混排字距、行高节奏与标点间隙。The quick brown fox jumps over the lazy dog.',
                    style: TextStyle(
                      fontFamily: bodyFont,
                      fontFamilyFallback: const [
                        'PingFang SC',
                        'Microsoft YaHei',
                        'Hiragino Sans GB',
                        'sans-serif',
                      ],
                      fontSize: fontSize,
                      height: 1.45,
                      color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 2. Monospace Code Sample (Pure English/ASCII to immediately exhibit monospace font switch)
                  Row(
                    children: [
                      Icon(
                        Icons.code_rounded,
                        size: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '代码字体渲染: $displayCodeFont',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: Text(
                      'fn quick_sort<T: Ord>(arr: &mut [T]) {\n'
                      '    if arr.len() <= 1 { return; }\n'
                      '    let pivot = partition(arr);\n'
                      '    quick_sort(&mut arr[0..pivot]);\n'
                      '    quick_sort(&mut arr[pivot + 1..]);\n'
                      '}',
                      style: TextStyle(
                        fontFamily: codeFont,
                        fontFamilyFallback: const [
                          'Menlo',
                          'Monaco',
                          'Courier New',
                          'Maple Mono',
                          'monospace',
                        ],
                        fontSize: (fontSize * 0.88).clamp(9.0, 15.0),
                        height: 1.35,
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. Monospace & ASCII Table 1:2 Alignment Sample
                  Row(
                    children: [
                      Icon(
                        Icons.table_chart_outlined,
                        size: 13,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      const SizedBox(width: 4),
                      const Expanded(
                        child: Text(
                          'ASCII 表格全角/半角严格 1:2 等宽对齐校验',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF141414) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFCBD5E1),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        '┌─────────────────────┬─────────────────────┐\n'
                        '│ 量子纠缠分发网关    │ 相对论时空频率同步  │\n'
                        '├─────────────────────┼─────────────────────┤\n'
                        '│ 贝尔态多粒子纯化    │ 史瓦西引力场膨胀修正│\n'
                        '│ 拓扑容错量子表面码  │ 零知识量子密钥分发  │\n'
                        '└─────────────────────┴─────────────────────┘',
                        style: TextStyle(
                          fontFamily: codeFont,
                          fontFamilyFallback: const [
                            'Maple Mono CN',
                            'Maple Mono NF CN',
                            'Maple Mono',
                            'Menlo',
                            'Monaco',
                            'monospace',
                          ],
                          fontSize: (fontSize * 0.85).clamp(8.5, 14.0),
                          height: 1.35,
                          letterSpacing: 0.0,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 3. SHORTCUTS TAB ====================
  Widget _buildShortcutsTab(ThemeData theme, bool isDark) {
    final shortcutService = widget.controller.shortcutService;

    // Group actions by category
    final categories = <String, List<AppShortcutAction>>{};
    for (final action in ShortcutService.allActions) {
      categories.putIfAbsent(action.category, () => []).add(action);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Conflict banner if any
        if (_conflictMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _conflictMessage!,
                    style: const TextStyle(fontSize: 12, color: Colors.amber),
                  ),
                ),
              ],
            ),
          ),

        // Action Categories and Rows
        for (final category in categories.keys) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Text(
              category,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (final action in categories[category]!)
            _buildShortcutActionRow(action, shortcutService, isDark, theme),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 12),
        // Reset all shortcuts button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                shortcutService.resetAll();
                _listeningActionId = null;
                _conflictMessage = null;
              });
            },
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            label: const Text('恢复全部默认快捷键', style: TextStyle(fontSize: 12.5)),
            style: TextButton.styleFrom(
              foregroundColor: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutActionRow(
    AppShortcutAction action,
    ShortcutService shortcutService,
    bool isDark,
    ThemeData theme,
  ) {
    final isListening = _listeningActionId == action.id;
    final isCustomized = shortcutService.isCustomized(action.id);
    final shortcutLabel = shortcutService.getShortcutLabel(action.id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isListening
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isListening
              ? theme.colorScheme.primary
              : (isDark ? const Color(0xFF333333) : const Color(0xFFECECEC)),
          width: isListening ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      action.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isCustomized) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '已修改',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  action.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF888888) : const Color(0xFF777777),
                  ),
                ),
              ],
            ),
          ),

          // Shortcut Key Badge / Key Listener
          Focus(
            autofocus: isListening,
            onKeyEvent: (node, event) {
              if (!isListening) return KeyEventResult.ignored;
              if (event is KeyDownEvent) {
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.escape) {
                  setState(() => _listeningActionId = null);
                  return KeyEventResult.handled;
                }
                if (ShortcutService.isModifierKey(key)) {
                  return KeyEventResult.handled;
                }
                if (ShortcutService.isSupportedKey(key)) {
                  final conflict = shortcutService.findConflict(action.id, key);
                  shortcutService.setKey(action.id, key);
                  setState(() {
                    _listeningActionId = null;
                    if (conflict != null) {
                      _conflictMessage = '快捷键已绑定为 $key，与「$conflict」存在相同主键，请留意避免冲突';
                    } else {
                      _conflictMessage = null;
                    }
                  });
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _listeningActionId = isListening ? null : action.id;
                  _conflictMessage = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isListening
                      ? theme.colorScheme.primary
                      : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isListening
                        ? theme.colorScheme.primary
                        : (isDark ? const Color(0xFF444444) : const Color(0xFFCCCCCC)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isListening ? Icons.hearing_rounded : Icons.keyboard_outlined,
                      size: 13,
                      color: isListening
                          ? Colors.white
                          : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isListening ? '请直接按下新按键...' : shortcutLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: isListening
                            ? Colors.white
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Reset button if customized
          if (isCustomized) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.undo_rounded, size: 16),
              tooltip: '恢复此项默认',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () {
                setState(() {
                  shortcutService.resetKey(action.id);
                  if (_listeningActionId == action.id) {
                    _listeningActionId = null;
                  }
                  _conflictMessage = null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  // ==================== 4. CLI TAB ====================
  Widget _buildCliTab(ThemeData theme, bool isDark) {
    if (!NativeCliService.isSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            '命令行工具功能仅在 macOS 系统上支持',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54),
          ),
        ),
      );
    }

    if (_isLoadingCli) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isInstalled = _cliStatus.isInstalled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isInstalled
                ? (isDark ? const Color(0x1F22C55E) : const Color(0x1416A34A))
                : (isDark ? const Color(0x28F59E0B) : const Color(0x1AF59E0B)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isInstalled ? const Color(0x4022C55E) : const Color(0x60F59E0B),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isInstalled ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                color: isInstalled ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isInstalled ? '命令行工具 \'sgv\' 已成功就绪' : '尚未安装 \'sgv\' 命令行工具',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isInstalled
                            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                            : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isInstalled
                          ? (Platform.isWindows ? '脚本路径: ${_cliStatus.path}' : '符号链接路径: ${_cliStatus.path}')
                          : '安装后可直接在终端中输入 sgv README.md 极速预览任何文档',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              if (_isOperatingCli)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (isInstalled)
                OutlinedButton(
                  onPressed: _handleUninstallCli,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('卸载', style: TextStyle(fontSize: 12)),
                )
              else
                ElevatedButton(
                  onPressed: _handleInstallCli,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('一键安装', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        _buildSectionHeader('终端使用范例 (Terminal Usage)'),
        const SizedBox(height: 8),

        _buildCliCodeSnippet('查看本地文件', 'sgv README.md', isDark),
        const SizedBox(height: 8),
        _buildCliCodeSnippet('以 A4 出版模式打开', 'sgv --a4 report.md', isDark),
        const SizedBox(height: 8),
        _buildCliCodeSnippet('通过管道即时预览 stdin', 'cat note.md | sgv', isDark),
      ],
    );
  }

  Widget _buildCliCodeSnippet(String desc, String cmd, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  cmd,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16),
            tooltip: '复制命令',
            onPressed: () => _copyCliCommand(cmd),
          ),
        ],
      ),
    );
  }

  // ==================== 5. ABOUT TAB ====================
  Widget _buildAboutTab(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App Identity Box
        Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'SuperGoodViewer',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '版本 ${SettingsDialog.appVersion} (Build 2026.09)',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Engine highlights card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '核心排版渲染引擎',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildTechItem('Typst 0.13.1', '毫秒级编译内核，完美支持高级数学公式、表格与代码块'),
              const SizedBox(height: 6),
              _buildTechItem('PDFium 矢量渲染', '无损 120 FPS 丝滑视口平移与部分预渲染技术'),
              const SizedBox(height: 6),
              _buildTechItem('CJK 1:2 等宽保障', '内置 CJK 等宽字体感知，杜绝 ASCII 表格与图表锯齿撕裂'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Load Sample Action Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '载入精选排版样例 (Sample Document)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '即刻体验包含复杂数学公式、Mermaid 图表、Callout 标注与代码高亮的演示文档',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.description_outlined, size: 15),
                label: const Text('载入体验', style: TextStyle(fontSize: 12)),
                onPressed: () {
                  widget.controller.loadSampleDocument();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTechItem(String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}
