import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';
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
  bool _isScanningFonts = false;

  // Shortcuts state
  String? _listeningActionId;
  String? _conflictMessage;

  // CLI state
  bool _isLoadingCli = true;
  bool _isOperatingCli = false;
  CliStatus _cliStatus = CliStatus.empty();

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    _selectedBodyFont = widget.controller.renderOptions.bodyFont;
    _selectedCodeFont = widget.controller.renderOptions.codeFont;
    _loadCliStatus();
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
        width: 760,
        height: 600,
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 660),
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
              'SuperGoodViewer v0.1.0',
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

        // Scrollable Body
        Expanded(
          child: SingleChildScrollView(
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
        return '配置文档默认视图版式、阅读主题外观与自动重载';
      case SettingsTab.typography:
        return '定制正文与代码等宽字体，保证 ASCII 字符画与表格严格 1:2 对齐';
      case SettingsTab.shortcuts:
        return '自定义各常用操作的键盘快捷键，点击键位直接录制';
      case SettingsTab.cli:
        return '在 macOS 终端中随时通过 sgv 命令秒级预览任何 Markdown';
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
        // Default View Mode
        _buildSectionHeader('默认排版模式 (Default View Mode)'),
        const SizedBox(height: 6),
        _buildRadioGroup<String>(
          value: controller.renderOptions.mode,
          options: const [
            {'value': 'fluid', 'label': '自适应流式 (Fluid)', 'desc': '无缝长卷轴排版，适配任意窗口视口'},
            {'value': 'paged', 'label': 'A4 出版模式 (Paged)', 'desc': '严格遵循标准 A4 页面分页与页码编排'},
          ],
          onChanged: (val) {
            if (val != null && val != controller.renderOptions.mode) {
              controller.toggleMode();
            }
          },
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // Appearance Theme
        _buildSectionHeader('阅读外观主题 (Appearance Theme)'),
        const SizedBox(height: 6),
        _buildRadioGroup<String>(
          value: controller.renderOptions.theme,
          options: const [
            {'value': 'light', 'label': '明亮主题 (Light)', 'desc': '清新纸质白底，适合日间光线充足环境'},
            {'value': 'dark', 'label': '暗黑主题 (Dark)', 'desc': '沉浸深邃暗夜，护眼高对比度配色'},
          ],
          onChanged: (val) {
            if (val != null && val != controller.renderOptions.theme) {
              controller.toggleTheme();
            }
          },
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // Auto Reload Switch
        _buildSectionHeader('文档自动重载 (Hot Reload)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.sync_rounded, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '文件修改自动热重载 (Auto Reload)',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
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

        // A4 Layout Preference
        _buildSectionHeader('A4 页面展示偏好 (Spread Layout)'),
        const SizedBox(height: 6),
        _buildRadioGroup<bool>(
          value: controller.isTwoPage,
          options: const [
            {'value': false, 'label': '单页纵向滚动', 'desc': '标准单张 A4 居中纵向连续浏览'},
            {'value': true, 'label': '双页对开浏览 (Two-Page Spread)', 'desc': '模拟精装书籍左右跨页排版'},
          ],
          onChanged: (val) {
            if (val != null && val != controller.isTwoPage) {
              controller.toggleTwoPage();
            }
          },
          theme: theme,
          isDark: isDark,
        ),
        const SizedBox(height: 18),

        // Recent Files Cache Clear
        _buildSectionHeader('阅读历史记录 (Recent Documents)'),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.history_rounded, size: 20, color: isDark ? Colors.white60 : Colors.black54),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '最近打开历史：已记录 ${controller.recentFiles.length} 个文件',
                  style: const TextStyle(fontSize: 12.5),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Maple Mono / CJK Monospace Health Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                    hasCjkMono ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                    color: hasCjkMono ? const Color(0xFF22C55E) : const Color(0xFFF59E0B),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasCjkMono
                          ? (mapleInstalled
                              ? '系统已就绪 Maple Mono (1:2 严格等宽)'
                              : '系统已检测到 CJK 严格等宽字体')
                          : '建议安装 Maple Mono 字体以获得最佳对齐',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: hasCjkMono
                            ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                            : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                hasCjkMono
                    ? '当前系统已加载 CJK 等宽字体，文档中包含的 ASCII 字符表格、流程图与代码行可实现 1 个全角汉字严格等于 2 个半角英文字符，边框绝不发生锯齿撕裂。'
                    : '检测到当前环境缺少 CJK 严格等宽字体。源码中的 ASCII 字符画表格或包含中英文混合的代码行可能会出现轻微对齐偏移。推荐下载安装开源 Maple Mono 字体。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
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
                    onPressed: _copyMapleDownloadLink,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  TextButton.icon(
                    icon: _isScanningFonts
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 14),
                    label: Text(_isScanningFonts ? '正在检测...' : '重新检测', style: const TextStyle(fontSize: 11.5)),
                    onPressed: _isScanningFonts
                        ? null
                        : () async {
                            setState(() => _isScanningFonts = true);
                            try {
                              await controller.refreshFontReport();
                            } finally {
                              if (mounted) {
                                setState(() => _isScanningFonts = false);
                              }
                            }
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
        const SizedBox(height: 18),

        // Body Font Dropdown
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '正文排版字体 (Body Typography)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            if (_selectedBodyFont != null)
              TextButton(
                onPressed: () {
                  setState(() => _selectedBodyFont = null);
                  controller.setBodyFont(null);
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text('恢复默认字体', style: TextStyle(fontSize: 11.5)),
              ),
          ],
        ),
        const SizedBox(height: 4),
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
                controller.setBodyFont(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Code Font Dropdown
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
        const SizedBox(height: 4),
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
                controller.setCodeFont(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Base Font Size
        Row(
          children: [
            const Expanded(
              child: Text(
                '排版基础字号 (Base Typesetting Font Size)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                controller.setFontSize(10.5);
                setState(() {});
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('恢复默认 (10.5 pt)', style: TextStyle(fontSize: 11.5)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                icon: const Icon(Icons.remove_rounded, size: 18),
                tooltip: '缩小字号',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final newSize = (controller.renderOptions.fontSize - 0.5).clamp(8.0, 24.0);
                  controller.setFontSize(newSize);
                  setState(() {});
                },
              ),
              Expanded(
                child: Slider(
                  value: controller.renderOptions.fontSize.clamp(8.0, 24.0),
                  min: 8.0,
                  max: 24.0,
                  divisions: 32,
                  label: '${controller.renderOptions.fontSize.toStringAsFixed(1)} pt',
                  onChanged: (val) {
                    controller.setFontSize(val);
                    setState(() {});
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 18),
                tooltip: '放大字号',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final newSize = (controller.renderOptions.fontSize + 0.5).clamp(8.0, 24.0);
                  controller.setFontSize(newSize);
                  setState(() {});
                },
              ),
              Container(
                width: 58,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  '${controller.renderOptions.fontSize.toStringAsFixed(1)} pt',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedBodyFont = null;
                  _selectedCodeFont = null;
                });
                controller.setBodyFont(null);
                controller.setCodeFont(null);
              },
              icon: const Icon(Icons.refresh_rounded, size: 14),
              label: const Text('恢复默认字体', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
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
                          ? '符号链接路径: ${_cliStatus.path}'
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
                '版本 0.1.0 (Build 2026.09)',
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

  // ==================== HELPERS ====================
  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildRadioGroup<T>({
    required T value,
    required List<Map<String, dynamic>> options,
    required ValueChanged<T?> onChanged,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Material(
      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RadioGroup<T>(
        groupValue: value,
        onChanged: onChanged,
        child: Column(
          children: [
            for (int i = 0; i < options.length; i++) ...[
              RadioListTile<T>(
                value: options[i]['value'] as T,
                title: Text(
                options[i]['label'] as String,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                options[i]['desc'] as String,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                ),
              ),
              dense: true,
              visualDensity: VisualDensity.compact,
            ),
            if (i < options.length - 1)
              Divider(
                height: 1,
                color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
              ),
          ],
        ],
      ),
    ),
  );
  }
}
