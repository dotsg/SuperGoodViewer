import 'package:flutter/material.dart';
import '../controllers/reader_controller.dart';
import '../models/render_options.dart';
import '../services/font_download_service.dart';
import '../services/form_factor.dart';

/// Shows the mobile-native typography and reading appearance bottom sheet.
void showMobileTypographySheet(
  BuildContext context,
  ReaderController controller, {
  VoidCallback? onFitWidth,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: isDark ? const Color(0xFF202022) : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (ctx) => MobileTypographySheet(
      controller: controller,
      onFitWidth: onFitWidth,
    ),
  );
}

/// Mobile-native typography bottom sheet tailored for one-thumb reading adjustments.
class MobileTypographySheet extends StatefulWidget {
  final ReaderController controller;
  final VoidCallback? onFitWidth;

  const MobileTypographySheet({
    super.key,
    required this.controller,
    this.onFitWidth,
  });

  @override
  State<MobileTypographySheet> createState() => _MobileTypographySheetState();
}

class _MobileTypographySheetState extends State<MobileTypographySheet> {
  double? _scrubbingFontSize;
  double? _scrubbingLineSpacing;
  double? _scrubbingParagraphSpacing;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final strings = controller.strings;
    final mobilePrefs = MobileReadingPrefs.instance;
    final fontService = FontDownloadService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([controller, mobilePrefs, fontService]),
      builder: (context, _) {
        final options = controller.renderOptions;
        final currentFontSize = options.fontSize;
        final displayFontSize = _scrubbingFontSize ?? currentFontSize;
        final currentLineSpacing = options.lineSpacing;
        final displayLineSpacing = _scrubbingLineSpacing ?? currentLineSpacing;
        final currentParagraphSpacing = options.paragraphSpacing;
        final displayParagraphSpacing =
            _scrubbingParagraphSpacing ?? currentParagraphSpacing;
        final isSepia = !options.isDark && mobilePrefs.isSepia;
        final hasMapleMono = controller.fontReport['has_maple_mono'] == true;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
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
                        Expanded(
                          child: Text(
                            strings.tabTypographyTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        if (widget.onFitWidth != null)
                          TextButton.icon(
                            key: const ValueKey('mobile_fit_width_btn'),
                            onPressed: () {
                              final screenW = MediaQuery.sizeOf(context).width.clamp(320.0, 960.0);
                              if (!controller.isPdfDocument && options.isFluid) {
                                controller.setViewportWidth(screenW);
                              }
                              widget.onFitWidth?.call();
                            },
                            icon: const Icon(Icons.fit_screen_rounded, size: 16),
                            label: Text(
                              strings.mobileFitWidth,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // PDF Smart Reflow Card (available for any source PDF document)
                    if (controller.isSourcePdfDocument) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: controller.isPdfReflowed
                              ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                              : (isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6)),
                          borderRadius: BorderRadius.circular(16),
                          border: controller.isPdfReflowed
                              ? Border.all(
                                  color: theme.colorScheme.primary.withValues(alpha: 0.4),
                                  width: 1,
                                )
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_stories_rounded,
                                  size: 22,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        controller.isPdfReflowed
                                            ? strings.mobilePdfReflowActiveTitle
                                            : strings.mobilePdfReflowTitle,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                         controller.isReflowingPdf
                                            ? strings.mobilePdfReflowing
                                            : strings.mobilePdfReflowDesc,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (controller.isReflowingPdf)
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: theme.colorScheme.primary,
                                    ),
                                  )
                                else
                                  Switch(
                                    key: const ValueKey('mobile_pdf_reflow_switch'),
                                    value: controller.isPdfReflowed,
                                    onChanged: (val) async {
                                      final ok = await controller.setPdfReflowMode(val);
                                      if (!ok && val && context.mounted) {
                                        controller.setPdfCropMargins(true);
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(strings.mobilePdfReflowScannedFallback),
                                            duration: const Duration(seconds: 3),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Font Size Stepper & Slider (Markdown / Typst documents)
                    if (!controller.isPdfDocument) ...[
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
                                      value: displayFontSize.clamp(
                                        RenderOptions.minFontSize,
                                        RenderOptions.maxFontSize,
                                      ),
                                      min: RenderOptions.minFontSize,
                                      max: RenderOptions.maxFontSize,
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
                            const Divider(height: 16),
                            // Line Spacing Slider
                            Row(
                              children: [
                                Text(
                                  strings.lineSpacingTitle,
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
                                    '${displayLineSpacing.toStringAsFixed(2)} em',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                key: const ValueKey('mobile_line_spacing_slider'),
                                value: displayLineSpacing.clamp(
                                  RenderOptions.minLineSpacing,
                                  RenderOptions.maxLineSpacing,
                                ),
                                min: RenderOptions.minLineSpacing,
                                max: RenderOptions.maxLineSpacing,
                                divisions: 30,
                                onChanged: (val) {
                                  setState(() {
                                    _scrubbingLineSpacing = (val * 20).round() / 20.0;
                                  });
                                },
                                onChangeEnd: (val) {
                                  final rounded = (val * 20).round() / 20.0;
                                  setState(() {
                                    _scrubbingLineSpacing = null;
                                  });
                                  controller.setLineSpacing(rounded);
                                },
                              ),
                            ),
                            // Paragraph Spacing Slider
                            Row(
                              children: [
                                Text(
                                  strings.paragraphSpacingTitle,
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
                                    '${displayParagraphSpacing.toStringAsFixed(2)} em',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                key: const ValueKey('mobile_paragraph_spacing_slider'),
                                value: displayParagraphSpacing.clamp(
                                  RenderOptions.minParagraphSpacing,
                                  RenderOptions.maxParagraphSpacing,
                                ),
                                min: RenderOptions.minParagraphSpacing,
                                max: RenderOptions.maxParagraphSpacing,
                                divisions: 34,
                                onChanged: (val) {
                                  setState(() {
                                    _scrubbingParagraphSpacing = (val * 20).round() / 20.0;
                                  });
                                },
                                onChangeEnd: (val) {
                                  final rounded = (val * 20).round() / 20.0;
                                  setState(() {
                                    _scrubbingParagraphSpacing = null;
                                  });
                                  controller.setParagraphSpacing(rounded);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Reading Background & Theme Palettes (Light / Sepia / Dark)
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
                            key: const ValueKey('mobile_theme_light'),
                            label: strings.themeLight,
                            background: const Color(0xFFFFFFFF),
                            textColor: const Color(0xFF1E1E1E),
                            borderColor: const Color(0xFFD0D0D5),
                            isSelected: !options.isDark && !isSepia,
                            onTap: () {
                              mobilePrefs.setSepia(false);
                              controller.setThemePreference(ThemePreference.light);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Sepia Warm Eye-Care Mode
                        Expanded(
                          child: _ThemeChoiceCard(
                            key: const ValueKey('mobile_theme_sepia'),
                            label: strings.mobileThemeSepiaCard,
                            background: const Color(0xFFF6EEDD),
                            textColor: const Color(0xFF3A2F23),
                            borderColor: const Color(0xFFD8CBB3),
                            isSelected: isSepia,
                            onTap: () {
                              mobilePrefs.setSepia(true);
                              if (options.isDark) {
                                controller.setThemePreference(ThemePreference.light);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Dark Mode
                        Expanded(
                          child: _ThemeChoiceCard(
                            key: const ValueKey('mobile_theme_dark'),
                            label: strings.themeDark,
                            background: const Color(0xFF1C1C1E),
                            textColor: const Color(0xFFF2F2F7),
                            borderColor: const Color(0xFF38383A),
                            isSelected: options.isDark,
                            onTap: () {
                              mobilePrefs.setSepia(false);
                              controller.setThemePreference(ThemePreference.dark);
                            },
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

                    // PDF Reading Enhancements (Margin Crop + Smart Dark Invert)
                    if (controller.isPdfDocument) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  options.pdfCropMargins
                                      ? Icons.crop_rounded
                                      : Icons.crop_free_rounded,
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
                                          fontSize: 13.5,
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
                            if (options.isDark) ...[
                              const Divider(height: 16),
                              Row(
                                children: [
                                  Icon(
                                    Icons.invert_colors_on_rounded,
                                    size: 22,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          strings.mobilePdfDarkInvertTitle,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          strings.mobilePdfDarkInvertDesc,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: isDark ? Colors.white60 : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    key: const ValueKey('mobile_pdf_dark_invert_switch'),
                                    value: mobilePrefs.pdfDarkInvert,
                                    onChanged: (val) => mobilePrefs.setPdfDarkInvert(val),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Mobile Pro Reading Ergonomics (Edge-tap page turn + Keep screen on)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2A2A2E) : const Color(0xFFF3F3F6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.mobileEdgeTapTitle,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      strings.mobileEdgeTapDesc,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                key: const ValueKey('mobile_edge_tap_switch'),
                                value: mobilePrefs.edgeTapPageTurn,
                                onChanged: (val) => mobilePrefs.setEdgeTapPageTurn(val),
                              ),
                            ],
                          ),
                          const Divider(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.wb_sunny_outlined,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      strings.mobileKeepScreenOnTitle,
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      strings.mobileKeepScreenOnDesc,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                key: const ValueKey('mobile_keep_screen_on_switch'),
                                value: mobilePrefs.keepScreenOn,
                                onChanged: (val) => mobilePrefs.setKeepScreenOn(val),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Font Family Selection (detected system fonts)
                    if (!controller.isPdfDocument)
                      Builder(
                        builder: (context) {
                          final rawFonts = (controller.fontReport['detected_body_fonts']
                                      as List<dynamic>?)
                                  ?.cast<String>() ??
                              const <String>[];
                          final cleanFonts =
                              rawFonts.where((f) => !f.startsWith('.')).toList();

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
                          final otherFonts =
                              cleanFonts.where((f) => !isCjkOrOem(f)).toList();
                          final prioritized = [...cjkFonts, ...otherFonts];

                          final currentFont = options.bodyFont;
                          final displayList = <String>[];
                          if (currentFont != null &&
                              currentFont.isNotEmpty &&
                              !currentFont.startsWith('.')) {
                            displayList.add(currentFont);
                          }
                          for (final f in prioritized) {
                            if (!displayList.contains(f) && displayList.length < 8) {
                              displayList.add(f);
                            }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (cleanFonts.isNotEmpty) ...[
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
                                      isSelected: options.bodyFont == null ||
                                          options.bodyFont!.isEmpty,
                                      isDark: isDark,
                                      onTap: () => controller.setTypography(bodyFont: ''),
                                    ),
                                    ...displayList.map((font) {
                                      return _FontChoiceChip(
                                        label: font,
                                        isSelected: options.bodyFont == font,
                                        isDark: isDark,
                                        onTap: () =>
                                            controller.setTypography(bodyFont: font),
                                      );
                                    }),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],

                              // Maple Mono One-Click Install & Local Font Import Card
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A2E)
                                      : const Color(0xFFF3F3F6),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: hasMapleMono
                                        ? Colors.green.withValues(alpha: 0.35)
                                        : theme.colorScheme.primary.withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          hasMapleMono
                                              ? Icons.verified_rounded
                                              : Icons.font_download_outlined,
                                          size: 18,
                                          color: hasMapleMono
                                              ? Colors.green
                                              : theme.colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            hasMapleMono
                                                ? strings.mapleMonoReady
                                                : strings.mapleMonoSuggested,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      hasMapleMono
                                          ? strings.cjkMonoActiveDesc
                                          : strings.cjkMonoMissingDesc,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? Colors.white60 : Colors.black54,
                                      ),
                                    ),
                                    if (fontService.isBusy) ...[
                                      const SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: fontService.isDownloading
                                              ? fontService.progress
                                              : null,
                                          minHeight: 5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        fontService.isDownloading
                                            ? strings.downloadingFontProgress(
                                                fontService.progressPercent,
                                              )
                                            : strings.extractingAndInstallingFont,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.primary,
                                        ),
                                      ),
                                    ] else ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (!hasMapleMono)
                                            FilledButton.icon(
                                              key: const ValueKey(
                                                'mobile_sheet_install_maple_btn',
                                              ),
                                              icon: const Icon(
                                                Icons.download_for_offline_rounded,
                                                size: 16,
                                              ),
                                              label: Text(
                                                strings.oneClickInstallMapleMono,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                visualDensity: VisualDensity.compact,
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 8,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                              ),
                                              onPressed: () async {
                                                final ok = await fontService
                                                    .downloadAndInstallMapleMono(
                                                  controller,
                                                );
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      ok
                                                          ? strings.fontInstallSuccess(
                                                              'Maple Mono',
                                                            )
                                                          : strings.fontInstallFailed(
                                                              fontService.errorMessage ?? '',
                                                            ),
                                                    ),
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              },
                                            ),
                                          OutlinedButton.icon(
                                            key: const ValueKey(
                                              'mobile_sheet_import_font_btn',
                                            ),
                                            icon: const Icon(
                                              Icons.folder_open_rounded,
                                              size: 16,
                                            ),
                                            label: Text(
                                              strings.importLocalFont,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: OutlinedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: () async {
                                              final installedName = await fontService
                                                  .importLocalFontFile(controller);
                                              if (!context.mounted) return;
                                              if (installedName != null) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.fontInstallSuccess(
                                                        installedName,
                                                      ),
                                                    ),
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              } else if (fontService.errorMessage != null) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      strings.fontInstallFailed(
                                                        fontService.errorMessage!,
                                                      ),
                                                    ),
                                                    behavior: SnackBarBehavior.floating,
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          );
                        },
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
}

class _ThemeChoiceCard extends StatelessWidget {
  final String label;
  final Color background;
  final Color textColor;
  final Color borderColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeChoiceCard({
    super.key,
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
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
              Icon(Icons.check_circle_rounded, size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
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
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.white : Colors.black87),
                ),
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
