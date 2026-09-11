import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../controllers/reader_controller.dart';
import 'font_settings_dialog.dart';

class SidebarView extends StatelessWidget {
  final ReaderController controller;
  final VoidCallback? onClose;

  const SidebarView({super.key, required this.controller, this.onClose});

  Future<void> _pickAndOpenFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['md', 'markdown', 'txt'],
    );

    if (result != null && result.files.single.path != null) {
      await controller.openFile(result.files.single.path!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
      child: Container(
        width: 260,
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
          // Sidebar Top Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text(
                      'S',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'SoGoodViewer',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '打开本地 Markdown 文件 (Cmd+O)',
                  icon: const Icon(Icons.folder_open_rounded, size: 19),
                  onPressed: () => _pickAndOpenFile(context),
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(5),
                    minimumSize: const Size(28, 28),
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '收起侧边栏 (Cmd+B 或 Esc)',
                    icon: const Icon(Icons.close_rounded, size: 19),
                    onPressed: onClose,
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(5),
                      minimumSize: const Size(28, 28),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // File status / info card
          Padding(
            padding: const EdgeInsets.all(12),
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
                          '就绪',
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

          // Reading Preferences Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              '排版偏好',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('字号大小', style: TextStyle(fontSize: 12.5)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove, size: 14),
                        onPressed: () => controller.setFontSize(
                          controller.renderOptions.fontSize - 0.5,
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(24, 24),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      Text(
                        '${controller.renderOptions.fontSize.toStringAsFixed(1)}pt',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, size: 14),
                        onPressed: () => controller.setFontSize(
                          controller.renderOptions.fontSize + 0.5,
                        ),
                        style: IconButton.styleFrom(
                          minimumSize: const Size(24, 24),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: const Text('修改自动热重载', style: TextStyle(fontSize: 12.5)),
                  value: controller.autoReload,
                  onChanged: controller.setAutoReload,
                ),
              ],
            ),
          ),

          const Divider(height: 16),

          // Recent Files Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Text(
              '最近打开',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),

          // Recent Files List
          Expanded(
            child: controller.recentFiles.isEmpty
                ? Center(
                    child: Text(
                      '暂无历史文件',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: controller.recentFiles.length,
                    itemBuilder: (context, index) {
                      final path = controller.recentFiles[index];
                      final isSelected = path == controller.currentFilePath;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        leading: const Icon(Icons.article_outlined, size: 16),
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
                        onTap: () => controller.openFile(path),
                      );
                    },
                  ),
          ),


          // Bottom Actions: Typography & Sample Document
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.font_download_outlined, size: 15),
                  label: const Text('字体与 CJK 对齐', style: TextStyle(fontSize: 12)),
                  onPressed: () => showFontSettingsDialog(context, controller),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 15),
                  label: const Text('载入精选样例', style: TextStyle(fontSize: 12)),
                  onPressed: controller.loadSampleDocument,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
