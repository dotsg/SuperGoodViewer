import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/reader_controller.dart';
import '../i18n/locales.dart';
import '../models/render_options.dart';
import '../services/document_cache_service.dart';
import '../services/linux_desktop_integration.dart';
import '../services/native_cli_service.dart';
import '../services/shortcut_service.dart';
import '../services/update_service.dart';
import '../services/preferences_service.dart';
import 'cli_feedback.dart';
import 'update_dialog.dart';

/// Available tabs within the unified SettingsDialog.
enum SettingsTab {
  general,
  layout,
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
  static const String appVersion = '1.0.9';
  static const String projectHomepage = 'https://github.com/dotsg/SuperGoodViewer';

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

  // Linux desktop integration state
  DesktopEntryStatus _desktopEntryStatus = DesktopEntryStatus.notInstalled;
  bool _isUpdatingDesktopEntry = false;

  Future<void> _changeDesktopEntry({required bool install}) async {
    final s = widget.controller.strings;
    final integration = LinuxDesktopIntegration.instance;
    setState(() => _isUpdatingDesktopEntry = true);
    String message;
    try {
      if (install) {
        await integration.install();
      } else {
        await integration.uninstall();
      }
      message = install ? s.desktopEntryAdded : s.desktopEntryRemoved;
    } catch (e) {
      message = s.desktopEntryFailed('$e');
    }
    if (!mounted) return;
    setState(() {
      _isUpdatingDesktopEntry = false;
      _desktopEntryStatus = integration.status();
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Layout & Header/Footer state
  late String _selectedPageFormat;
  late TextEditingController _headerLeftController;
  late TextEditingController _headerCenterController;
  late TextEditingController _headerRightController;
  late TextEditingController _footerLeftController;
  late TextEditingController _footerCenterController;
  late TextEditingController _footerRightController;
  late bool _showHeaderRule;
  late bool _showFooterRule;
  late bool _skipFirstPage;
  late bool _marpEnabled;

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
          SnackBar(
            content: Text(widget.controller.strings.typographySavedSuccess),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  void _saveLayout() {
    widget.controller.setPageFormat(_selectedPageFormat);
    widget.controller.setHeaderFooterOptions(
      headerLeft: _headerLeftController.text.trim().isEmpty ? null : _headerLeftController.text.trim(),
      headerCenter: _headerCenterController.text.trim().isEmpty ? null : _headerCenterController.text.trim(),
      headerRight: _headerRightController.text.trim().isEmpty ? null : _headerRightController.text.trim(),
      footerLeft: _footerLeftController.text.trim().isEmpty ? null : _footerLeftController.text.trim(),
      footerCenter: _footerCenterController.text.trim().isEmpty ? null : _footerCenterController.text.trim(),
      footerRight: _footerRightController.text.trim().isEmpty ? null : _footerRightController.text.trim(),
      showHeaderRule: _showHeaderRule,
      showFooterRule: _showFooterRule,
      skipFirstPageHeaderFooter: _skipFirstPage,
      marpEnabled: _marpEnabled,
    );
    setState(() {});
    try {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger != null && Scaffold.maybeOf(context) != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(widget.controller.strings.layoutSavedSuccess),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {}
  }

  bool get _hasUnsavedLayoutChanges {
    final opts = widget.controller.renderOptions;
    if (_selectedPageFormat != opts.effectivePageFormat) return true;
    final hL = _headerLeftController.text.trim().isEmpty ? null : _headerLeftController.text.trim();
    if (hL != opts.headerLeft) return true;
    final hC = _headerCenterController.text.trim().isEmpty ? null : _headerCenterController.text.trim();
    if (hC != opts.headerCenter) return true;
    final hR = _headerRightController.text.trim().isEmpty ? null : _headerRightController.text.trim();
    if (hR != opts.headerRight) return true;
    final fL = _footerLeftController.text.trim().isEmpty ? null : _footerLeftController.text.trim();
    if (fL != opts.footerLeft) return true;
    final fC = _footerCenterController.text.trim().isEmpty ? null : _footerCenterController.text.trim();
    if (fC != opts.footerCenter) return true;
    final fR = _footerRightController.text.trim().isEmpty ? null : _footerRightController.text.trim();
    if (fR != opts.footerRight) return true;
    if (_showHeaderRule != (opts.showHeaderRule ?? false)) return true;
    if (_showFooterRule != (opts.showFooterRule ?? false)) return true;
    if (_skipFirstPage != (opts.skipFirstPageHeaderFooter ?? true)) return true;
    if (_marpEnabled != (opts.marpEnabled ?? true)) return true;
    return false;
  }

  void _revertLayout() {
    final opts = widget.controller.renderOptions;
    setState(() {
      _selectedPageFormat = opts.effectivePageFormat;
      _headerLeftController.text = opts.headerLeft ?? '';
      _headerCenterController.text = opts.headerCenter ?? '';
      _headerRightController.text = opts.headerRight ?? '';
      _footerLeftController.text = opts.footerLeft ?? '';
      _footerCenterController.text = opts.footerCenter ?? '';
      _footerRightController.text = opts.footerRight ?? '';
      _showHeaderRule = opts.showHeaderRule ?? false;
      _showFooterRule = opts.showFooterRule ?? false;
      _skipFirstPage = opts.skipFirstPageHeaderFooter ?? true;
      _marpEnabled = opts.marpEnabled ?? true;
    });
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

  // Auto-update state
  bool _isCheckingUpdate = false;
  String? _updateStatusMessage;
  bool _autoCheckUpdates = true;

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
    if (LinuxDesktopIntegration.isSupported) {
      _desktopEntryStatus = LinuxDesktopIntegration.instance.status();
    }
    final opts = widget.controller.renderOptions;
    _selectedBodyFont = opts.bodyFont;
    _selectedCodeFont = opts.codeFont;
    _selectedFontSize = opts.fontSize;
    _selectedPageFormat = opts.effectivePageFormat;
    _headerLeftController = TextEditingController(text: opts.headerLeft ?? '');
    _headerCenterController = TextEditingController(text: opts.headerCenter ?? '');
    _headerRightController = TextEditingController(text: opts.headerRight ?? '');
    _footerLeftController = TextEditingController(text: opts.footerLeft ?? '');
    _footerCenterController = TextEditingController(text: opts.footerCenter ?? '');
    _footerRightController = TextEditingController(text: opts.footerRight ?? '');
    _showHeaderRule = opts.showHeaderRule ?? false;
    _showFooterRule = opts.showFooterRule ?? false;
    _skipFirstPage = opts.skipFirstPageHeaderFooter ?? true;
    _marpEnabled = opts.marpEnabled ?? true;

    _headerLeftController.addListener(_onLayoutFieldChanged);
    _headerCenterController.addListener(_onLayoutFieldChanged);
    _headerRightController.addListener(_onLayoutFieldChanged);
    _footerLeftController.addListener(_onLayoutFieldChanged);
    _footerCenterController.addListener(_onLayoutFieldChanged);
    _footerRightController.addListener(_onLayoutFieldChanged);

    _loadCacheStats();
    _loadCliStatus();

    final prefs = PreferencesService.loadSync();
    _autoCheckUpdates = prefs[UpdateService.prefAutoCheck] as bool? ?? true;
  }

  void _onLayoutFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _headerLeftController.removeListener(_onLayoutFieldChanged);
    _headerCenterController.removeListener(_onLayoutFieldChanged);
    _headerRightController.removeListener(_onLayoutFieldChanged);
    _footerLeftController.removeListener(_onLayoutFieldChanged);
    _footerCenterController.removeListener(_onLayoutFieldChanged);
    _footerRightController.removeListener(_onLayoutFieldChanged);

    _headerLeftController.dispose();
    _headerCenterController.dispose();
    _headerRightController.dispose();
    _footerLeftController.dispose();
    _footerCenterController.dispose();
    _footerRightController.dispose();
    super.dispose();
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
              content: Text(widget.controller.strings.cacheCleared(cleared.formattedFreedSize)),
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
      showCliOperationFeedback(
        context,
        result: res,
        strings: widget.controller.strings,
        isInstall: true,
      );
      _loadCliStatus();
    }
  }

  Future<void> _handleUninstallCli() async {
    setState(() => _isOperatingCli = true);
    final res = await NativeCliService.uninstall();
    if (mounted) {
      setState(() => _isOperatingCli = false);
      showCliOperationFeedback(
        context,
        result: res,
        strings: widget.controller.strings,
        isInstall: false,
      );
      _loadCliStatus();
    }
  }

  void _copyCliCommand(String cmd) {
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(widget.controller.strings.copiedCommand(cmd)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openMapleGitHub() => _openUrl('https://github.com/subframe7536/maple-font/releases');

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
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
      SnackBar(
        content: Text(widget.controller.strings.mapleLinkCopied),
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
                Expanded(
                  child: Text(
                    widget.controller.strings.settingsTitle,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Nav Items
          _buildNavItem(
            tab: SettingsTab.general,
            label: widget.controller.strings.tabGeneral,
            icon: Icons.tune_rounded,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.layout,
            label: widget.controller.strings.tabLayout,
            icon: Icons.auto_stories_outlined,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.typography,
            label: widget.controller.strings.tabTypography,
            icon: Icons.font_download_outlined,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.shortcuts,
            label: widget.controller.strings.tabShortcuts,
            icon: Icons.keyboard_outlined,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.cli,
            label: widget.controller.strings.tabCli,
            icon: Icons.terminal_rounded,
            theme: theme,
            isDark: isDark,
          ),
          _buildNavItem(
            tab: SettingsTab.about,
            label: widget.controller.strings.tabAbout,
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
                tooltip: widget.controller.strings.close,
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
              : _currentTab == SettingsTab.layout
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
                      child: _buildLayoutTab(theme, isDark),
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
    final s = widget.controller.strings;
    switch (tab) {
      case SettingsTab.general:
        return s.tabGeneralTitle;
      case SettingsTab.layout:
        return s.tabLayoutTitle;
      case SettingsTab.typography:
        return s.tabTypographyTitle;
      case SettingsTab.shortcuts:
        return s.tabShortcutsTitle;
      case SettingsTab.cli:
        return s.tabCliTitle;
      case SettingsTab.about:
        return s.tabAboutTitle;
    }
  }

  String _getTabSubtitle(SettingsTab tab) {
    final s = widget.controller.strings;
    switch (tab) {
      case SettingsTab.general:
        return s.displayLanguageDesc;
      case SettingsTab.layout:
        return s.twoPageSpreadDesc;
      case SettingsTab.typography:
        return s.pdfTypographyNotice;
      case SettingsTab.shortcuts:
        return s.shortcutsDesc;
      case SettingsTab.cli:
        return Platform.isWindows ? s.cliDescWin : s.cliDescMac;
      case SettingsTab.about:
        return s.appSubtitle;
    }
  }

  Widget _buildActiveTabBody(ThemeData theme, bool isDark) {
    switch (_currentTab) {
      case SettingsTab.general:
        return _buildGeneralTab(theme, isDark);
      case SettingsTab.layout:
        return _buildLayoutTab(theme, isDark);
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

  // ==================== LAYOUT TAB ====================
  Widget _buildDesktopEntryCard(ThemeData theme, bool isDark) {
    final s = widget.controller.strings;
    final status = _desktopEntryStatus;
    final buttonStyle = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    );
    final busy = _isUpdatingDesktopEntry;

    return Container(
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
          Icon(Icons.apps_rounded, size: 22, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.desktopEntryTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  status == DesktopEntryStatus.outdated ? s.desktopEntryOutdated : s.desktopEntryDesc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: status == DesktopEntryStatus.outdated
                        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
                        : (isDark ? const Color(0xFF888888) : const Color(0xFF666666)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (status == DesktopEntryStatus.notInstalled)
            FilledButton(
              onPressed: busy ? null : () => _changeDesktopEntry(install: true),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: Text(s.desktopEntryAdd, style: const TextStyle(fontSize: 11.5)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (status == DesktopEntryStatus.outdated)
                  FilledButton(
                    onPressed: busy ? null : () => _changeDesktopEntry(install: true),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                    child: Text(s.desktopEntryUpdate, style: const TextStyle(fontSize: 11.5)),
                  ),
                OutlinedButton(
                  onPressed: busy ? null : () => _changeDesktopEntry(install: false),
                  style: buttonStyle,
                  child: Text(s.desktopEntryRemove, style: const TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLayoutTab(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionHeader(widget.controller.strings.pageFormatSection),
        const SizedBox(height: 6),
        Text(
          widget.controller.strings.pageFormatDesc,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 12),
        ...PageFormat.all.map((fmt) {
          final isSelected = _selectedPageFormat == fmt;
          String desc;
          IconData icon;
          switch (fmt) {
            case PageFormat.fluid:
              desc = widget.controller.strings.pageFormatFluidDesc;
              icon = Icons.view_stream_rounded;
              break;
            case PageFormat.a4Portrait:
              desc = widget.controller.strings.pageFormatA4PortraitDesc;
              icon = Icons.description_outlined;
              break;
            case PageFormat.a4Landscape:
              desc = widget.controller.strings.pageFormatA4LandscapeDesc;
              icon = Icons.landscape_outlined;
              break;
            case PageFormat.slide16x9:
              desc = widget.controller.strings.pageFormatSlide169Desc;
              icon = Icons.slideshow_rounded;
              break;
            case PageFormat.slide4x3:
              desc = widget.controller.strings.pageFormatSlide43Desc;
              icon = Icons.tv_rounded;
              break;
            default:
              desc = '';
              icon = Icons.auto_stories_rounded;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _selectedPageFormat = fmt),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primary.withValues(alpha: 0.1)
                        : (isDark ? const Color(0xFF222222) : const Color(0xFFF9F9F9)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5)),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark ? Colors.white38 : Colors.black38),
                      ),
                      const SizedBox(width: 12),
                      Icon(
                        icon,
                        size: 18,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PageFormat.getDisplayName(fmt, widget.controller.strings),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight:
                                    isSelected ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              desc,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF888888)
                                    : const Color(0xFF777777),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),

        const SizedBox(height: 18),
        _buildSectionHeader(widget.controller.strings.headerFooterSection),
        const SizedBox(height: 6),
        Text(
          widget.controller.strings.headerFooterDesc,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF9E9E9E) : const Color(0xFF666666),
          ),
        ),
        const SizedBox(height: 12),

        SwitchListTile(
          value: _skipFirstPage,
          onChanged: (val) => setState(() => _skipFirstPage = val),
          title: Text(widget.controller.strings.skipFirstPage, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(widget.controller.strings.skipFirstPageDesc, style: const TextStyle(fontSize: 11.5)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _showHeaderRule,
          onChanged: (val) => setState(() => _showHeaderRule = val),
          title: Text(widget.controller.strings.showHeaderRule, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _showFooterRule,
          onChanged: (val) => setState(() => _showFooterRule = val),
          title: Text(widget.controller.strings.showFooterRule, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),

        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.controller.strings.headerSlotsTitle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
            TextButton.icon(
              icon: const Icon(Icons.clear_all_rounded, size: 14),
              label: Text(widget.controller.strings.clearHeaderSlots, style: const TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                _headerLeftController.clear();
                _headerCenterController.clear();
                _headerRightController.clear();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildSlotField(
                controller: _headerLeftController,
                label: widget.controller.strings.slotLeft,
                hintText: widget.controller.strings.slotHintCustom,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlotField(
                controller: _headerCenterController,
                label: widget.controller.strings.slotCenter,
                hintText: widget.controller.strings.slotHintEmpty,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlotField(
                controller: _headerRightController,
                label: widget.controller.strings.slotRight,
                hintText: '{title}',
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.controller.strings.footerSlotsTitle, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: theme.colorScheme.primary)),
            TextButton.icon(
              icon: const Icon(Icons.clear_all_rounded, size: 14),
              label: Text(widget.controller.strings.clearFooterSlots, style: const TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                _footerLeftController.clear();
                _footerCenterController.clear();
                _footerRightController.clear();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildSlotField(
                controller: _footerLeftController,
                label: widget.controller.strings.slotLeft,
                hintText: widget.controller.strings.slotHintCopyright,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlotField(
                controller: _footerCenterController,
                label: widget.controller.strings.slotCenter,
                hintText: '{page}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSlotField(
                controller: _footerRightController,
                label: widget.controller.strings.slotRight,
                hintText: widget.controller.strings.slotHintPageTotal,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
        _buildSectionHeader(widget.controller.strings.marpCompatibility),
        const SizedBox(height: 6),
        SwitchListTile(
          value: _marpEnabled,
          onChanged: (val) => setState(() => _marpEnabled = val),
          title: Text(widget.controller.strings.marpCompatibility, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(widget.controller.strings.marpCompatibilityDesc, style: const TextStyle(fontSize: 11.5)),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),

                const SizedBox(height: 12),
              ],
            ),
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
        _buildLayoutBottomBar(theme, isDark),
      ],
    );
  }

  Widget _buildLayoutBottomBar(ThemeData theme, bool isDark) {
    final s = widget.controller.strings;
    final hasChanges = _hasUnsavedLayoutChanges;

    return Row(
      children: [
        Icon(
          hasChanges ? Icons.edit_note_rounded : Icons.check_circle_outline_rounded,
          size: 16,
          color: hasChanges ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasChanges ? s.layoutHasChanges : s.layoutUpToDate,
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
        const SizedBox(width: 8),
        if (hasChanges) ...[
          OutlinedButton(
            onPressed: _revertLayout,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            child: Text(s.discardChanges, style: const TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 15),
          label: Text(s.saveAndApplyLayout, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            backgroundColor: hasChanges ? const Color(0xFF0284C7) : null,
          ),
          onPressed: hasChanges ? _saveLayout : null,
        ),
      ],
    );
  }

  Widget _buildSlotField({
    required TextEditingController controller,
    required String label,
    required String hintText,
  }) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hintText,
            isDense: true,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            suffixIcon: value.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 14),
                    splashRadius: 12,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: widget.controller.strings.clearSlotTooltip,
                    onPressed: controller.clear,
                  )
                : null,
          ),
          style: const TextStyle(fontSize: 12),
        );
      },
    );
  }

  // ==================== 1. GENERAL TAB ====================
  Widget _buildGeneralTab(ThemeData theme, bool isDark) {
    final controller = widget.controller;
    final strings = controller.strings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Language Selector
        _buildSectionHeader(strings.languageSection),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.translate_rounded, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.displayLanguage,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.displayLanguageDesc,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                      ),
                    ),
                  ],
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: controller.language,
                  borderRadius: BorderRadius.circular(8),
                  items: AppLanguage.values.map((lang) {
                    return DropdownMenuItem<String>(
                      value: lang.code,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(lang.icon, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            lang.nativeLabel,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      controller.setLanguage(val);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Appearance Theme Selector
        _buildSectionHeader(strings.appearanceSection),
        const SizedBox(height: 6),
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
              Row(
                children: [
                  Icon(Icons.contrast_rounded, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.themeMode,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          strings.themeModeDesc,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: ThemePreference.system,
                      icon: const Icon(Icons.brightness_auto_outlined, size: 15),
                      label: Text(strings.themeSystem, style: const TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<String>(
                      value: ThemePreference.light,
                      icon: const Icon(Icons.light_mode_outlined, size: 15),
                      label: Text(strings.themeLight, style: const TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<String>(
                      value: ThemePreference.dark,
                      icon: const Icon(Icons.dark_mode_outlined, size: 15),
                      label: Text(strings.themeDark, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {controller.themePreference},
                  onSelectionChanged: (newSelection) {
                    controller.setThemePreference(newSelection.first);
                    setState(() {});
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 2. Sidebar Placement Selector
        _buildSectionHeader(strings.sidebarPositionSection),
        const SizedBox(height: 6),
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
              Row(
                children: [
                  Transform.flip(
                    flipX: controller.isSidebarOnRight,
                    child: Icon(Icons.view_sidebar_outlined, size: 22, color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.sidebarPosition,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          strings.sidebarPositionDesc,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'left',
                      icon: const Icon(Icons.view_sidebar_outlined, size: 15),
                      label: Text(strings.sidebarPositionLeft, style: const TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<String>(
                      value: 'right',
                      icon: Transform.flip(
                        flipX: true,
                        child: const Icon(Icons.view_sidebar_outlined, size: 15),
                      ),
                      label: Text(strings.sidebarPositionRight, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {controller.sidebarPosition},
                  onSelectionChanged: (newSelection) {
                    controller.setSidebarPosition(newSelection.first);
                    setState(() {});
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Open behavior: new tab or replace the current document
        _buildSectionHeader(strings.openBehaviorTitle),
        const SizedBox(height: 6),
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
              Row(
                children: [
                  Icon(Icons.tab_rounded, size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.openBehaviorDesc,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF888888) : const Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment<bool>(
                      value: true,
                      icon: const Icon(Icons.add_box_outlined, size: 15),
                      label: Text(strings.openInNewTab, style: const TextStyle(fontSize: 12)),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 15),
                      label: Text(strings.openReplaceCurrent, style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                  selected: {controller.openInNewTab},
                  onSelectionChanged: (newSelection) {
                    controller.setOpenInNewTab(newSelection.first);
                    setState(() {});
                  },
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Auto Reload Switch
        _buildSectionHeader(strings.autoReloadSection),
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
                    Text(
                      strings.autoReload,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      strings.autoReloadDesc,
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

        if (LinuxDesktopIntegration.isSupported) ...[
          _buildSectionHeader(strings.desktopIntegrationSection),
          const SizedBox(height: 6),
          _buildDesktopEntryCard(theme, isDark),
          const SizedBox(height: 18),
        ],

        // Session & History
        _buildSectionHeader(strings.sessionSection),
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
                        Text(
                          strings.recentDocsRecord,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          strings.recentFilesCount(controller.recentFiles.length),
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
                    label: Text(strings.clearRecentHistory, style: const TextStyle(fontSize: 12)),
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
                        Text(
                          widget.controller.strings.restoreSession,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.controller.strings.restoreSessionDesc,
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
                      widget.controller.strings.enabledBadge,
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
        _buildSectionHeader(strings.cacheSection),
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
                        Text(
                          strings.localDiskCache,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLoadingCache
                              ? strings.loadingCacheStats
                              : (_cacheStats.fileCount > 0
                                  ? strings.currentCacheSize(_cacheStats.fileCount, _cacheStats.formattedSize)
                                  : strings.noCacheFiles),
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
                    label: Text(strings.openCacheDirectory, style: const TextStyle(fontSize: 12)),
                    onPressed: () async {
                      final ok = await DocumentCacheService.openCacheDirectory();
                      if (!ok && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.openCacheDirectoryFailed),
                            duration: const Duration(seconds: 3),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: _isClearingCache
                        ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cleaning_services_outlined, size: 15),
                    label: Text(strings.clearCache, style: const TextStyle(fontSize: 12)),
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
                      strings.cacheDesc,
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
      {'label': widget.controller.strings.fontOptionSystemRecommended, 'value': null},
      {'label': widget.controller.strings.fontOptionPingFang, 'value': 'PingFang SC'},
      {'label': widget.controller.strings.fontOptionSongti, 'value': 'Songti SC'},
      {'label': widget.controller.strings.fontOptionHiragino, 'value': 'Hiragino Sans GB'},
      {'label': widget.controller.strings.fontOptionYaHei, 'value': 'Microsoft YaHei'},
      {'label': widget.controller.strings.fontOptionSourceHanSans, 'value': 'Source Han Sans SC'},
      {'label': widget.controller.strings.fontOptionInter, 'value': 'Inter'},
    ];
    if (_selectedBodyFont != null &&
        !bodyFontOptions.any((opt) => opt['value'] == _selectedBodyFont)) {
      bodyFontOptions.add({
        'label': widget.controller.strings.fontOptionCustom(_selectedBodyFont!),
        'value': _selectedBodyFont,
      });
    }

    final detectedMono = (report['detected_monospace_fonts'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    final baseCodeFonts = <Map<String, String?>>[
      {'label': widget.controller.strings.fontOptionMapleMono, 'value': null},
      {'label': widget.controller.strings.fontOptionMenlo, 'value': 'Menlo'},
      {'label': widget.controller.strings.fontOptionMonaco, 'value': 'Monaco'},
      {'label': widget.controller.strings.fontOptionCourierNew, 'value': 'Courier New'},
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
          'label': widget.controller.strings.fontOptionInstalled(monoName),
          'value': monoName,
        });
      }
    }
    if (_selectedCodeFont != null &&
        !codeFontOptions.any((opt) => opt['value'] == _selectedCodeFont)) {
      codeFontOptions.add({
        'label': widget.controller.strings.fontOptionCustom(_selectedCodeFont!),
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
                      if (controller.isPdfDocument) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0x2838BDF8) : const Color(0x1A0284C7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark ? const Color(0x6038BDF8) : const Color(0x400284C7),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  widget.controller.strings.pdfTypographyInlineNotice,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Maple Mono / CJK Monospace Health Banner (compact)
                      _buildMapleHealthBanner(theme, isDark, hasCjkMono, mapleInstalled),
                      const SizedBox(height: 12),

                      // Body Font Dropdown
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              widget.controller.strings.bodyTypographyTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
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
                              child: Text(widget.controller.strings.useRecommended, style: const TextStyle(fontSize: 11)),
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
                          Flexible(
                            child: Text(
                              widget.controller.strings.monoTypographyTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                              child: Text(widget.controller.strings.restoreDefault, style: const TextStyle(fontSize: 11)),
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
                          Flexible(
                            child: Text(
                              widget.controller.strings.baseFontSizeTitle,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _selectedFontSize = 10.5),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                            child: Text(widget.controller.strings.restoreDefaultFontSize('10.5'), style: const TextStyle(fontSize: 11)),
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
                              tooltip: widget.controller.strings.decreaseFontSize,
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
                              tooltip: widget.controller.strings.increaseFontSize,
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
                            label: Text(widget.controller.strings.restoreDefaultFonts, style: const TextStyle(fontSize: 11.5)),
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
                          ? widget.controller.strings.mapleMonoReady
                          : widget.controller.strings.cjkMonoDetected)
                      : widget.controller.strings.mapleMonoSuggested,
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
                ? widget.controller.strings.cjkMonoActiveDesc
                : widget.controller.strings.cjkMonoMissingDesc,
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.open_in_new_rounded, size: 12),
                label: Text(widget.controller.strings.downloadFont, style: const TextStyle(fontSize: 11)),
                onPressed: _openMapleGitHub,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy_rounded, size: 12),
                label: Text(widget.controller.strings.copyLink, style: const TextStyle(fontSize: 11)),
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
                label: Text(_isScanningFonts ? widget.controller.strings.detectingFonts : widget.controller.strings.redetectFonts, style: const TextStyle(fontSize: 11)),
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
    final s = widget.controller.strings;
    final hasChanges = _hasUnsavedTypographyChanges;

    return Row(
      children: [
        Icon(
          hasChanges ? Icons.edit_note_rounded : Icons.check_circle_outline_rounded,
          size: 16,
          color: hasChanges ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hasChanges ? s.typographyHasChanges : s.typographyUpToDate,
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
        const SizedBox(width: 8),
        if (hasChanges) ...[
          OutlinedButton(
            onPressed: _revertTypography,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            ),
            child: Text(s.discardChanges, style: const TextStyle(fontSize: 11.5)),
          ),
          const SizedBox(width: 8),
        ],
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 15),
          label: Text(s.saveAndApplyTypography, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
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
    final displayCodeFont = codeFont ?? widget.controller.strings.mapleMonoDefault;

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
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.controller.strings.livePreviewBadge,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
                            widget.controller.strings.livePreviewTitle,
                            style: const TextStyle(fontSize: 0),
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
                    widget.controller.strings.previewSpecimenHeading,
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
                    widget.controller.strings.previewSpecimenBody,
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
                          widget.controller.strings.previewCodeFont(displayCodeFont),
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
                      Expanded(
                        child: Text(
                          widget.controller.strings.asciiAlignmentCheck,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
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
                      // Not localized: the specimen needs full-width CJK cells
                      // to show the 1:2 alignment in every UI language.
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
    final strings = widget.controller.strings;

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
              strings.shortcutCategoryName(category),
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
            label: Text(strings.resetAllShortcuts, style: const TextStyle(fontSize: 12.5)),
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
    final strings = widget.controller.strings;
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
                      strings.shortcutActionName(action.id, action.name),
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
                          widget.controller.strings.shortcutModified,
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
                  strings.shortcutActionDesc(action.id, action.description),
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
                      _conflictMessage = strings.shortcutConflict(conflict);
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
                      isListening
                          ? strings.pressNewShortcut
                          : (shortcutLabel.isEmpty ? strings.shortcutUnassigned : shortcutLabel),
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
              tooltip: widget.controller.strings.resetShortcutToDefault,
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
    final s = widget.controller.strings;

    if (!NativeCliService.isSupported) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.controller.strings.cliErrorPlatformNotSupported,
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
    final isPartial = _cliStatus.isPartial;

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
                      isInstalled
                          ? s.cliStatusReady
                          : (isPartial
                              ? (_cliStatus.localizedWarning(s) ?? s.cliStatusPartialTools)
                              : s.cliStatusNotInstalled),
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
                          ? (Platform.isWindows ? 'PATH: ${_cliStatus.path}' : s.cliSymlinkPath(_cliStatus.path))
                          : s.cliHintQuickPreview,
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
                  child: Text(s.cliUninstall, style: const TextStyle(fontSize: 12)),
                )
              else ...[
                ElevatedButton(
                  onPressed: _handleInstallCli,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(isPartial ? s.cliReinstallRepair : s.cliInstall, style: const TextStyle(fontSize: 12)),
                ),
                if (isPartial) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _handleUninstallCli,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(s.cliCleanUninstall, style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        _buildSectionHeader(s.cliUsageExamples),
        const SizedBox(height: 8),

        _buildCliCodeSnippet(s.cliExampleCurrentDir, 'sgv README.md', isDark),
        const SizedBox(height: 8),
        _buildCliCodeSnippet(s.cliExampleAnyFile, 'sgv --a4 report.md', isDark),
        const SizedBox(height: 8),
        _buildCliCodeSnippet(s.cliExampleStdin, 'cat note.md | sgv', isDark),
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
            tooltip: widget.controller.strings.copyCommandTooltip,
            onPressed: () => _copyCliCommand(cmd),
          ),
        ],
      ),
    );
  }

  // ==================== 5. ABOUT TAB ====================
  Widget _buildAboutTab(ThemeData theme, bool isDark) {
    final s = widget.controller.strings;

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.aboutVersion(SettingsDialog.appVersion),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_isCheckingUpdate)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _handleManualCheckUpdate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Text(
                              s.checkForUpdates,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Tooltip(
                message: s.openProjectHomepage,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => _openUrl(SettingsDialog.projectHomepage),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new_rounded, size: 13, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          SettingsDialog.projectHomepage.replaceFirst('https://', ''),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_updateStatusMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _updateStatusMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _updateStatusMessage!.contains(s.upToDate) ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Auto check updates toggle card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF9F9F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isDark ? const Color(0xFF333333) : const Color(0xFFE5E5E5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_alt_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.autoCheckUpdates,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch.adaptive(
                  value: _autoCheckUpdates,
                  onChanged: (val) {
                    setState(() => _autoCheckUpdates = val);
                    PreferencesService.saveKey(UpdateService.prefAutoCheck, val);
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

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
              Text(
                widget.controller.strings.aboutEngineSection,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _buildTechItem('Typst 0.13.1', widget.controller.strings.aboutTypstDesc),
              const SizedBox(height: 6),
              _buildTechItem(widget.controller.strings.aboutPdfiumTitle, widget.controller.strings.aboutPdfiumDesc),
              const SizedBox(height: 6),
              _buildTechItem(widget.controller.strings.aboutCjkTitle, widget.controller.strings.aboutCjkDesc),
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
                    Text(
                      widget.controller.strings.loadSampleDocument,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.controller.strings.loadSampleDocumentDesc,
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
                label: Text(s.loadSampleDoc, style: const TextStyle(fontSize: 12)),
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

  Future<void> _handleManualCheckUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() {
      _isCheckingUpdate = true;
      _updateStatusMessage = widget.controller.strings.checkingForUpdates;
    });

    try {
      final info = await UpdateService.instance.checkUpdate(
        currentVersion: SettingsDialog.appVersion,
        isManual: true,
      );

      if (!mounted) return;
      setState(() => _isCheckingUpdate = false);

      if (info.hasUpdate) {
        setState(() => _updateStatusMessage = null);
        await UpdateDialog.show(context, widget.controller, info);
      } else {
        setState(() {
          _updateStatusMessage = widget.controller.strings.upToDate;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
          _updateStatusMessage = '${widget.controller.strings.updateFailed}: $e';
        });
      }
    }
  }
}
