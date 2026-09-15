import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../controllers/reader_controller.dart';
import 'settings_dialog.dart';

class SidebarView extends StatefulWidget {
  final ReaderController controller;
  final VoidCallback? onClose;
  final ValueChanged<OutlineItem>? onJumpToOutline;

  const SidebarView({
    super.key,
    required this.controller,
    this.onClose,
    this.onJumpToOutline,
  });

  @override
  State<SidebarView> createState() => _SidebarViewState();
}

class _SidebarViewState extends State<SidebarView> {
  int _selectedTab = 0; // 0: 大纲目录, 1: 最近文件

  Future<void> _pickAndOpenFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt', 'pdf'],
    );

    if (result != null && result.files.single.path != null) {
      await widget.controller.openFile(result.files.single.path!);
    }
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required int count,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF383838) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? (isDark ? Colors.white : Colors.black87)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withValues(alpha: 0.15)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOutlineList(ThemeData theme, bool isDark) {
    final items = widget.controller.outlineItems;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.format_list_bulleted_rounded,
              size: 28,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 8),
            Text(
              widget.controller.strings.noOutlineFound,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final indent = ((item.level - 1) * 12.0).clamp(0.0, 48.0);
        return Padding(
          padding: EdgeInsets.only(left: indent, bottom: 2),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                widget.onJumpToOutline?.call(item);
                widget.controller.jumpToOutline(item);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2, right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: item.level == 1
                            ? theme.colorScheme.primary.withValues(alpha: 0.15)
                            : (isDark ? const Color(0xFF333333) : const Color(0xFFE8E8E8)),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        item.pageNumber != null ? 'P${item.pageNumber}' : 'H${item.level}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: (item.pageNumber != null || item.level == 1)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: item.level == 1 ? FontWeight.w600 : FontWeight.normal,
                          color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF222222),
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentFilesList(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Text(
                widget.controller.strings.recentFilesCount(widget.controller.recentFiles.length),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              if (widget.controller.recentFiles.isNotEmpty)
                InkWell(
                  onTap: widget.controller.clearRecentFiles,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      widget.controller.strings.clearRecentHistory,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: widget.controller.recentFiles.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          size: 32,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.controller.strings.noRecentFiles,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.auto_awesome, size: 14),
                          label: Text(widget.controller.strings.loadSampleDoc, style: const TextStyle(fontSize: 11.5)),
                          onPressed: widget.controller.loadSampleDocument,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: widget.controller.recentFiles.length,
                  itemBuilder: (context, index) {
                    final path = widget.controller.recentFiles[index];
                    final isSelected = path == widget.controller.currentFilePath;
                    final isPdf = path.toLowerCase().endsWith('.pdf');
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      leading: Icon(
                        isPdf ? Icons.picture_as_pdf_outlined : Icons.article_outlined,
                        size: 16,
                        color: isPdf ? Colors.redAccent.withValues(alpha: 0.8) : null,
                      ),
                      title: Text(
                        p.basename(path),
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        path,
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => widget.controller.openFile(path),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final controller = widget.controller;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
      child: Container(
        width: 270,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE0E0E0),
              width: 1,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sidebar Top Header (Aligned with macOS Traffic Lights)
            Container(
              height: 32,
              padding: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Dedicated safe spacing for macOS traffic lights (Close/Miniaturize/Zoom)
                  if (Platform.isMacOS) const SizedBox(width: 78),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onPanStart: (_) {
                        try {
                          const MethodChannel('com.sogoodviewer.window').invokeMethod('startDragging');
                        } catch (_) {}
                      },
                      onDoubleTap: () {
                        try {
                          const MethodChannel('com.sogoodviewer.window').invokeMethod('zoom');
                        } catch (_) {}
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: IconButton(
                      tooltip: '${controller.strings.openDocument} (${controller.shortcutService.getShortcutLabel('openFile')})',
                      icon: const Icon(Icons.folder_open_rounded, size: 16),
                      onPressed: () => _pickAndOpenFile(context),
                      style: IconButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(24, 24),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ),
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: IconButton(
                        tooltip: controller.strings.sidebarCloseTooltip(controller.shortcutService.getShortcutLabel('toggleSidebar')),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: widget.onClose,
                        style: IconButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(24, 24),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // File status / info card
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262626) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xFF333333) : const Color(0xFFE8E8E8),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.description_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            controller.documentTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (controller.currentFilePath != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        controller.currentFilePath!,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            controller.renderOptions.isFluid ? '流式视窗' : 'A4 出版',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (controller.isCompiling)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text(
                            controller.strings.statusReady,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade600,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Segmented Navigation Tabs: [ 目录大纲 ] / [ 最近文件 ]
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF282828) : const Color(0xFFECECEC),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        title: controller.strings.sidebarTabOutline,
                        icon: Icons.format_list_bulleted_rounded,
                        count: controller.outlineItems.length,
                        isSelected: _selectedTab == 0,
                        onTap: () => setState(() => _selectedTab = 0),
                        isDark: isDark,
                        theme: theme,
                      ),
                    ),
                    Expanded(
                      child: _buildTabButton(
                        title: controller.strings.sidebarTabRecent,
                        icon: Icons.history_rounded,
                        count: controller.recentFiles.length,
                        isSelected: _selectedTab == 1,
                        onTap: () => setState(() => _selectedTab = 1),
                        isDark: isDark,
                        theme: theme,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 4),

            // Main Tab Content: Outline or Recents
            Expanded(
              child: _selectedTab == 0
                  ? _buildOutlineList(theme, isDark)
                  : _buildRecentFilesList(theme, isDark),
            ),

            // Compact macOS-style 38px Footer Bar
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Unified Settings Entry
                  Expanded(
                    child: Tooltip(
                      message: controller.strings.settingsTooltip(controller.shortcutService.getShortcutLabel('openSettings')),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => showSettingsDialog(context, controller),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.settings_outlined,
                                size: 14,
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                controller.strings.settingsTitle,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (controller.recentFiles.isNotEmpty) ...[
                    Container(
                      width: 1,
                      height: 14,
                      color: isDark ? const Color(0x22FFFFFF) : const Color(0x18000000),
                    ),
                    Tooltip(
                      message: controller.strings.clearRecentHistory,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: controller.clearRecentFiles,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          child: Icon(
                            Icons.delete_sweep_outlined,
                            size: 15,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
