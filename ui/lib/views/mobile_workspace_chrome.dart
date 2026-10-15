import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../controllers/reader_controller.dart';
import 'mobile_typography_sheet.dart';
import 'settings_dialog.dart';
import 'sidebar_view.dart';

/// Mobile-specific workspace chrome (top app bar, drawer wrapper, bottom reading HUD,
/// and vertical HUD tier math), extracted from `WorkspaceView` to keep shared desktop
/// code free of inline mobile widget trees.
class MobileWorkspaceChrome {
  static const double titleBarHeight = 48.0;

  static void setDrawerOpen(GlobalKey<ScaffoldState> scaffoldKey, bool open) {
    if (!open) {
      if (scaffoldKey.currentState?.isDrawerOpen ?? false) {
        scaffoldKey.currentState?.closeDrawer();
      }
      if (scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
        scaffoldKey.currentState?.closeEndDrawer();
      }
    }
  }

  static void toggleDrawer(
    GlobalKey<ScaffoldState> scaffoldKey, {
    required bool isRight,
  }) {
    if (isRight) {
      if (scaffoldKey.currentState?.isEndDrawerOpen ?? false) {
        scaffoldKey.currentState?.closeEndDrawer();
      } else {
        scaffoldKey.currentState?.openEndDrawer();
      }
    } else {
      if (scaffoldKey.currentState?.isDrawerOpen ?? false) {
        scaffoldKey.currentState?.closeDrawer();
      } else {
        scaffoldKey.currentState?.openDrawer();
      }
    }
  }

  static Widget buildDrawer(
    BuildContext context, {
    required ReaderController controller,
    required ValueChanged<OutlineItem> onJumpToOutline,
  }) {
    return Drawer(
      width: math.min(MediaQuery.sizeOf(context).width * 0.85, 320.0),
      child: SafeArea(
        child: SidebarView(
          controller: controller,
          width: double.infinity,
          showResizeHandle: false,
          onClose: () => Navigator.of(context).pop(),
          onJumpToOutline: (item) {
            Navigator.of(context).pop();
            onJumpToOutline(item);
          },
        ),
      ),
    );
  }

  static double computeBottomBarHeight([double bottomPadding = 0.0]) {
    return 104.0 + bottomPadding;
  }

  static double computeZoomHudBottom({
    required bool isMobile,
    required bool isToolbarVisible,
    required double bottomPadding,
    required double desktopDefault,
  }) {
    if (!isMobile) {
      return desktopDefault + bottomPadding;
    }
    final barH = computeBottomBarHeight(bottomPadding);
    return isToolbarVisible ? (barH + 12.0) : (24.0 + bottomPadding);
  }

  static double computeDegradedBannerBottom({
    required bool isMobile,
    required bool isToolbarVisible,
    required bool isZoomHudVisible,
    required double bottomPadding,
    required double desktopDefault,
  }) {
    if (!isMobile) {
      return desktopDefault + bottomPadding;
    }
    final zoomBottom = computeZoomHudBottom(
      isMobile: true,
      isToolbarVisible: isToolbarVisible,
      bottomPadding: bottomPadding,
      desktopDefault: desktopDefault,
    );
    if (isZoomHudVisible) {
      return zoomBottom + 44.0;
    }
    final barH = computeBottomBarHeight(bottomPadding);
    return isToolbarVisible ? (barH + 12.0) : (24.0 + bottomPadding);
  }

  static Widget buildTitleBar(
    BuildContext context, {
    required bool show,
    required bool isDark,
    required ReaderController controller,
    required VoidCallback onToggleSidebar,
    required VoidCallback onOpenSearch,
    required VoidCallback onOpenFile,
    required VoidCallback onExportPdf,
  }) {
    final topPadding = MediaQuery.paddingOf(context).top;
    const barHeight = titleBarHeight;
    final totalHeight = topPadding + barHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      height: show ? totalHeight : 0.0,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7))
            .withValues(alpha: 0.95),
        border: show
            ? Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE5E5E5),
                  width: 1,
                ),
              )
            : null,
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: OverflowBox(
            minHeight: totalHeight,
            maxHeight: totalHeight,
            alignment: Alignment.topCenter,
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: EdgeInsets.only(top: topPadding, left: 6, right: 6),
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.menu_rounded),
                        iconSize: 22,
                        tooltip: controller.strings.toggleSidebarTooltip(''),
                        onPressed: onToggleSidebar,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          controller.documentTitle,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.search_rounded),
                        iconSize: 22,
                        tooltip: controller.strings.searchPlaceholder,
                        onPressed: onOpenSearch,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert_rounded),
                        iconSize: 22,
                        onSelected: (action) {
                          switch (action) {
                            case 'open':
                              onOpenFile();
                              break;
                            case 'export':
                              onExportPdf();
                              break;
                            case 'refresh':
                              controller.refreshDocument();
                              break;
                            case 'settings':
                              showSettingsDialog(context, controller);
                              break;
                            case 'about':
                              showSettingsDialog(
                                context,
                                controller,
                                initialTab: SettingsTab.about,
                              );
                              break;
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'open',
                            child: Row(
                              children: [
                                const Icon(Icons.folder_open_rounded, size: 18),
                                const SizedBox(width: 10),
                                Text(controller.strings.openDocument),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'export',
                            child: Row(
                              children: [
                                const Icon(Icons.download_rounded, size: 18),
                                const SizedBox(width: 10),
                                Text(controller.strings.exportPdf),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'refresh',
                            child: Row(
                              children: [
                                const Icon(Icons.refresh_rounded, size: 18),
                                const SizedBox(width: 10),
                                Text(controller.strings.reloadDocument),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'settings',
                            child: Row(
                              children: [
                                const Icon(Icons.settings_outlined, size: 18),
                                const SizedBox(width: 10),
                                Text(controller.strings.settingsTitle),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'about',
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, size: 18),
                                const SizedBox(width: 10),
                                Text(controller.strings.tabAboutTitle),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget buildBottomHud(
    BuildContext context, {
    required bool visible,
    required bool isDark,
    required ReaderController controller,
    required double bottomPadding,
    required int currentPage,
    required int pageCount,
    required int? scrubbingPage,
    required ValueChanged<int?> onScrubbingChanged,
    required VoidCallback onCancelToolbarTimer,
    required VoidCallback onRestartToolbarTimer,
    required VoidCallback onPrevPage,
    required VoidCallback onNextPage,
    required ValueChanged<int> onJumpToPage,
    required VoidCallback onToggleSidebar,
    required VoidCallback onToggleCropMargins,
  }) {
    final theme = Theme.of(context);
    final strings = controller.strings;
    final totalPages = math.max(1, pageCount);
    final currentPageClamped = currentPage.clamp(1, totalPages);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, 1.2),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7))
                  .withValues(alpha: 0.96),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFE2E2E5),
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 10 + bottomPadding),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            iconSize: 26,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: strings.previousPage,
                            onPressed: currentPage > 1
                                ? () {
                                    onPrevPage();
                                    onRestartToolbarTimer();
                                  }
                                : null,
                          ),
                          Expanded(
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                activeTrackColor: theme.colorScheme.primary,
                                thumbColor: theme.colorScheme.primary,
                              ),
                              child: Slider(
                                value: (scrubbingPage ?? currentPageClamped).toDouble(),
                                min: 1.0,
                                max: totalPages.toDouble(),
                                divisions: totalPages > 1 ? totalPages - 1 : 1,
                                onChangeStart: totalPages > 1
                                    ? (_) => onCancelToolbarTimer()
                                    : null,
                                onChanged: totalPages > 1
                                    ? (val) => onScrubbingChanged(val.round())
                                    : null,
                                onChangeEnd: totalPages > 1
                                    ? (val) {
                                        final target = val.round();
                                        onScrubbingChanged(null);
                                        if (target != currentPage) {
                                          onJumpToPage(target);
                                        }
                                        onRestartToolbarTimer();
                                      }
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            iconSize: 26,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            tooltip: strings.nextPage,
                            onPressed: currentPage < totalPages
                                ? () {
                                    onNextPage();
                                    onRestartToolbarTimer();
                                  }
                                : null,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${scrubbingPage ?? currentPageClamped} / $totalPages',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _MobileActionButton(
                            icon: Icons.format_list_bulleted_rounded,
                            label: strings.sidebarTabOutline,
                            onTap: () {
                              onToggleSidebar();
                              onRestartToolbarTimer();
                            },
                            isDark: isDark,
                          ),
                          if (controller.isPdfDocument)
                            _MobileActionButton(
                              icon: controller.pdfCropMargins
                                  ? Icons.crop_rounded
                                  : Icons.crop_free_rounded,
                              label: controller.pdfCropMargins
                                  ? strings.mobileCropActive
                                  : strings.mobileCropInactive,
                              isSelected: controller.pdfCropMargins,
                              onTap: () {
                                onToggleCropMargins();
                                onRestartToolbarTimer();
                              },
                              isDark: isDark,
                            )
                          else
                            _MobileActionButton(
                              icon: controller.renderOptions.isFluid
                                  ? Icons.view_headline_rounded
                                  : Icons.description_outlined,
                              label: controller.renderOptions.isFluid
                                  ? strings.mobileLayoutFluid
                                  : strings.mobileLayoutPaged,
                              isSelected: controller.renderOptions.isFluid,
                              onTap: () {
                                controller.toggleMode();
                                onRestartToolbarTimer();
                              },
                              isDark: isDark,
                            ),
                          _MobileActionButton(
                            icon: controller.renderOptions.isDark
                                ? Icons.light_mode_rounded
                                : Icons.dark_mode_rounded,
                            label: controller.renderOptions.isDark
                                ? strings.mobileThemeLight
                                : strings.mobileThemeDark,
                            onTap: () {
                              controller.toggleTheme();
                              onRestartToolbarTimer();
                            },
                            isDark: isDark,
                          ),
                          _MobileActionButton(
                            icon: Icons.text_fields_rounded,
                            label: strings.mobileTypography,
                            onTap: () {
                              onRestartToolbarTimer();
                              showMobileTypographySheet(context, controller);
                            },
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final bool isSelected;

  const _MobileActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary;
    final defaultColor = isDark ? Colors.white70 : Colors.black87;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? activeColor : defaultColor,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : defaultColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
