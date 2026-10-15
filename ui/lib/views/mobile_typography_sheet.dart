import 'package:flutter/material.dart';
import '../controllers/reader_controller.dart';
import '../models/render_options.dart';

/// Shows the mobile-native typography and reading appearance bottom sheet.
void showMobileTypographySheet(BuildContext context, ReaderController controller) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? const Color(0xFF202022) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (ctx) => MobileTypographySheet(controller: controller),
  );
}

/// Mobile-native typography bottom sheet tailored for one-thumb reading adjustments.
class MobileTypographySheet extends StatefulWidget {
  final ReaderController controller;

  const MobileTypographySheet({
    super.key,
    required this.controller,
  });

  @override
  State<MobileTypographySheet> createState() => _MobileTypographySheetState();
}

class _MobileTypographySheetState extends State<MobileTypographySheet> {
  double? _scrubbingFontSize;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final strings = controller.strings;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final options = controller.renderOptions;
        final currentFontSize = options.fontSize;
        final displayFontSize = _scrubbingFontSize ?? currentFontSize;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Drag Handle Pill
                  Center(
                    child: Container(
                      width: 40,
                      height: 4.5,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF4A4A4E) : const Color(0xFFD6D6DB),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                  // Header Row
                  Row(
                    children: [
                      Icon(
                        Icons.text_fields_rounded,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        strings.tabTypographyTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Font Size Stepper & Slider
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              strings.fontSize,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${displayFontSize.toStringAsFixed(1)} pt',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // A- Button
                            IconButton(
                              icon: const Text(
                                'A-',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              onPressed: currentFontSize > 8.5
                                  ? () => controller.setFontSize(currentFontSize - 1.0)
                                  : null,
                            ),
                            // Font Size Slider
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                                ),
                                child: Slider(
                                  value: displayFontSize.clamp(8.0, 24.0),
                                  min: 8.0,
                                  max: 24.0,
                                  divisions: 32,
                                  onChanged: (val) {
                                    setState(() {
                                      _scrubbingFontSize = val;
                                    });
                                  },
                                  onChangeEnd: (val) {
                                    setState(() {
                                      _scrubbingFontSize = null;
                                    });
                                    controller.setFontSize(val);
                                  },
                                ),
                              ),
                            ),
                            // A+ Button
                            IconButton(
                              icon: const Text(
                                'A+',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                              onPressed: currentFontSize < 23.5
                                  ? () => controller.setFontSize(currentFontSize + 1.0)
                                  : null,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Reading Background & Theme Palettes
                  Text(
                    strings.themeMode,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      // Light Mode
                      Expanded(
                        child: _ThemeChoiceCard(
                          label: strings.themeLight,
                          background: const Color(0xFFFFFFFF),
                          textColor: const Color(0xFF1E1E1E),
                          borderColor: const Color(0xFFD0D0D5),
                          isSelected: !options.isDark,
                          onTap: () => controller.setThemePreference(ThemePreference.light),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Dark Mode
                      Expanded(
                        child: _ThemeChoiceCard(
                          label: strings.themeDark,
                          background: const Color(0xFF1C1C1E),
                          textColor: const Color(0xFFF2F2F7),
                          borderColor: const Color(0xFF38383A),
                          isSelected: options.isDark,
                          onTap: () => controller.setThemePreference(ThemePreference.dark),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Page Layout Modes (Markdown documents)
                  if (!controller.isPdfDocument) ...[
                    Text(
                      strings.tabLayoutTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _LayoutModeButton(
                            title: strings.layoutModeFluid,
                            icon: Icons.view_headline_rounded,
                            isSelected: options.isFluid,
                            isDark: isDark,
                            onTap: () => controller.setPageFormat(PageFormat.fluid),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _LayoutModeButton(
                            title: strings.layoutModeA4Portrait,
                            icon: Icons.description_outlined,
                            isSelected: options.effectivePageFormat == PageFormat.a4Portrait,
                            isDark: isDark,
                            onTap: () => controller.setPageFormat(PageFormat.a4Portrait),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],

                  // PDF Margin Crop (PDF documents)
                  if (controller.isPdfDocument) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            options.pdfCropMargins ? Icons.crop_rounded : Icons.crop_free_rounded,
                            size: 22,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  options.pdfCropMargins
                                      ? strings.mobileCropMarginsActiveTitle
                                      : strings.mobileCropMarginsTitle,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  strings.mobileCropMarginsDesc,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white60 : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: options.pdfCropMargins,
                            onChanged: (val) => controller.setPdfCropMargins(val),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Font Family Selection (detected system fonts)
                  Builder(
                    builder: (context) {
                      final rawFonts = (controller.fontReport['detected_body_fonts'] as List<dynamic>?)
                              ?.cast<String>() ??
                          const <String>[];
                      // Filter out dot-prefixed private fonts
                      final cleanFonts = rawFonts.where((f) => !f.startsWith('.')).toList();
                      if (cleanFonts.isEmpty) return const SizedBox.shrink();

                      bool isCjkOrOem(String name) {
                        final l = name.toLowerCase();
                        return l.contains('noto') ||
                            l.contains('sans sc') ||
                            l.contains('sans tc') ||
                            l.contains('sans hk') ||
                            l.contains('sans cjk') ||
                            l.contains('misans') ||
                            l.contains('mi sans') ||
                            l.contains('xiaomi') ||
                            l.contains('harmony') ||
                            l.contains('oppo') ||
                            l.contains('vivo') ||
                            l.contains('honor') ||
                            l.contains('pingfang') ||
                            l.contains('yahei') ||
                            l.contains('heiti') ||
                            l.contains('songti') ||
                            l.contains('kaiti') ||
                            l.contains('source han');
                      }

                      final cjkFonts = cleanFonts.where(isCjkOrOem).toList();
                      final otherFonts = cleanFonts.where((f) => !isCjkOrOem(f)).toList();
                      final prioritized = [...cjkFonts, ...otherFonts];

                      // Ensure current active font is included in display list
                      final currentFont = options.bodyFont;
                      final displayList = <String>[];
                      if (currentFont != null && currentFont.isNotEmpty && !currentFont.startsWith('.')) {
                        displayList.add(currentFont);
                      }
                      for (final f in prioritized) {
                        if (!displayList.contains(f) && displayList.length < 8) {
                          displayList.add(f);
                        }
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.bodyFont,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _FontChoiceChip(
                                label: strings.fontOptionSystemRecommended,
                                isSelected: options.bodyFont == null || options.bodyFont!.isEmpty,
                                isDark: isDark,
                                onTap: () => controller.setTypography(bodyFont: ''),
                              ),
                              ...displayList.map((font) {
                                return _FontChoiceChip(
                                  label: font,
                                  isSelected: options.bodyFont == font,
                                  isDark: isDark,
                                  onTap: () => controller.setTypography(bodyFont: font),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ThemeChoiceCard extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeChoiceCard({
    required this.label,
    required this.background,
    required this.textColor,
    required this.borderColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary : borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected) ...[
              Icon(Icons.check_circle_rounded, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayoutModeButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _LayoutModeButton({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? const Color(0xFF38383C) : const Color(0xFFE2E2E6)),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? theme.colorScheme.primary
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? theme.colorScheme.primary
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FontChoiceChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _FontChoiceChip({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? const Color(0xFF38383C) : const Color(0xFFE2E2E6)),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }
}
