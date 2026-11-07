import 'dart:convert';
import '../i18n/app_strings.dart';

/// Predefined page layout formats for SuperGoodViewer.
class PageFormat {
  static const String fluid = 'fluid';
  static const String mobilePortrait = 'mobilePortrait';
  static const String a4Portrait = 'a4Portrait';
  static const String a4Landscape = 'a4Landscape';
  static const String slide16x9 = 'slide16x9';
  static const String slide4x3 = 'slide4x3';
  static const String pptSlides = 'pptSlides';
  static const String pptNotes = 'pptNotes';

  static const List<String> all = [
    fluid,
    mobilePortrait,
    a4Portrait,
    a4Landscape,
    slide16x9,
    slide4x3,
  ];

  static String getDisplayName(String format, AppStrings strings) {
    switch (format) {
      case fluid:
        return strings.layoutModeFluid;
      case mobilePortrait:
        return strings.layoutModeMobile;
      case a4Portrait:
        return strings.layoutModeA4Portrait;
      case a4Landscape:
        return strings.layoutModeA4Landscape;
      case slide16x9:
        return strings.layoutModeSlide169;
      case slide4x3:
        return strings.layoutModeSlide43;
      case pptSlides:
        return strings.layoutModePptSlides;
      case pptNotes:
        return strings.layoutModePptNotes;
      default:
        return format;
    }
  }
}

/// User-facing appearance preference. [RenderOptions.theme] always holds the
/// resolved "light" / "dark" value; [system] resolves it from the OS brightness.
class ThemePreference {
  static const String system = 'system';
  static const String light = 'light';
  static const String dark = 'dark';

  static const List<String> all = [system, light, dark];
}

/// Represents rendering configuration for SuperGoodViewer.
class RenderOptions {
  static const double defaultFontSize = 10.5;
  static const double minFontSize = 8.0;
  static const double maxFontSize = 24.0;

  static const double defaultLineSpacing = 0.85;
  static const double minLineSpacing = 0.50;
  static const double maxLineSpacing = 2.00;

  static const double defaultParagraphSpacing = 1.35;
  static const double minParagraphSpacing = 0.80;
  static const double maxParagraphSpacing = 2.50;

  final String mode; // "fluid" (continuous auto-height) or "paged" (paginated)
  final String theme; // "light" or "dark"
  final double viewportWidth; // in points
  final double fontSize; // in points
  final double lineSpacing; // Typst par leading in em
  final double paragraphSpacing; // Typst par spacing in em
  final String? bodyFont; // custom proportional font
  final String? codeFont; // custom monospace font
  final String? imageCacheDir; // custom remote image cache directory

  // Multi-layout formats
  final String? pageFormat; // e.g. fluid, a4Portrait, a4Landscape, slide16x9, slide4x3

  // Header & Footer customizable slots
  final String? headerLeft;
  final String? headerCenter;
  final String? headerRight;
  final String? footerLeft;
  final String? footerCenter;
  final String? footerRight;
  final bool? enableHeader;
  final bool? enableFooter;
  final bool? showHeaderRule;
  final bool? showFooterRule;
  final bool? skipFirstPageHeaderFooter;
  final bool? marpEnabled;
  final bool pdfCropMargins;
  final bool exportQuality;

  const RenderOptions({
    this.mode = 'fluid',
    this.theme = 'light',
    this.viewportWidth = 850.0,
    this.fontSize = defaultFontSize,
    this.lineSpacing = defaultLineSpacing,
    this.paragraphSpacing = defaultParagraphSpacing,
    this.bodyFont,
    this.codeFont,
    this.imageCacheDir,
    this.pageFormat,
    this.headerLeft,
    this.headerCenter,
    this.headerRight,
    this.footerLeft,
    this.footerCenter,
    this.footerRight,
    this.enableHeader,
    this.enableFooter,
    this.showHeaderRule,
    this.showFooterRule,
    this.skipFirstPageHeaderFooter,
    this.marpEnabled,
    this.pdfCropMargins = false,
    this.exportQuality = false,
  });

  String get effectivePageFormat {
    if (pageFormat != null && pageFormat!.isNotEmpty) {
      return pageFormat!;
    }
    return mode == 'fluid' ? PageFormat.fluid : PageFormat.a4Portrait;
  }

  bool get isFluid => effectivePageFormat == PageFormat.fluid;
  bool get isDark => theme == 'dark';
  bool get isSlide =>
      effectivePageFormat == PageFormat.slide16x9 ||
      effectivePageFormat == PageFormat.slide4x3 ||
      effectivePageFormat == PageFormat.pptSlides;
  bool get isA4 =>
      effectivePageFormat == PageFormat.a4Portrait ||
      effectivePageFormat == PageFormat.a4Landscape ||
      effectivePageFormat == PageFormat.pptNotes;

  double get aspectRatio {
    switch (effectivePageFormat) {
      case PageFormat.slide16x9:
      case PageFormat.pptSlides:
        return 16.0 / 9.0;
      case PageFormat.slide4x3:
        return 4.0 / 3.0;
      case PageFormat.a4Landscape:
        return 841.89 / 595.28;
      case PageFormat.a4Portrait:
      case PageFormat.pptNotes:
        return 595.28 / 841.89;
      case PageFormat.mobilePortrait:
        return 390.0 / 780.0;
      default:
        return 1.0;
    }
  }

  static const Object _undefined = Object();

  RenderOptions copyWith({
    String? mode,
    String? theme,
    double? viewportWidth,
    double? fontSize,
    double? lineSpacing,
    double? paragraphSpacing,
    Object? bodyFont = _undefined,
    Object? codeFont = _undefined,
    Object? imageCacheDir = _undefined,
    Object? pageFormat = _undefined,
    Object? headerLeft = _undefined,
    Object? headerCenter = _undefined,
    Object? headerRight = _undefined,
    Object? footerLeft = _undefined,
    Object? footerCenter = _undefined,
    Object? footerRight = _undefined,
    bool? enableHeader,
    bool? enableFooter,
    bool? showHeaderRule,
    bool? showFooterRule,
    bool? skipFirstPageHeaderFooter,
    bool? marpEnabled,
    bool? pdfCropMargins,
    bool? exportQuality,
  }) {
    return RenderOptions(
      mode: mode ?? this.mode,
      theme: theme ?? this.theme,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      fontSize: fontSize ?? this.fontSize,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      bodyFont: identical(bodyFont, _undefined) ? this.bodyFont : bodyFont as String?,
      codeFont: identical(codeFont, _undefined) ? this.codeFont : codeFont as String?,
      imageCacheDir: identical(imageCacheDir, _undefined) ? this.imageCacheDir : imageCacheDir as String?,
      pageFormat: identical(pageFormat, _undefined) ? this.pageFormat : pageFormat as String?,
      headerLeft: identical(headerLeft, _undefined) ? this.headerLeft : headerLeft as String?,
      headerCenter: identical(headerCenter, _undefined) ? this.headerCenter : headerCenter as String?,
      headerRight: identical(headerRight, _undefined) ? this.headerRight : headerRight as String?,
      footerLeft: identical(footerLeft, _undefined) ? this.footerLeft : footerLeft as String?,
      footerCenter: identical(footerCenter, _undefined) ? this.footerCenter : footerCenter as String?,
      footerRight: identical(footerRight, _undefined) ? this.footerRight : footerRight as String?,
      enableHeader: enableHeader ?? this.enableHeader,
      enableFooter: enableFooter ?? this.enableFooter,
      showHeaderRule: showHeaderRule ?? this.showHeaderRule,
      showFooterRule: showFooterRule ?? this.showFooterRule,
      skipFirstPageHeaderFooter:
          skipFirstPageHeaderFooter ?? this.skipFirstPageHeaderFooter,
      marpEnabled: marpEnabled ?? this.marpEnabled,
      pdfCropMargins: pdfCropMargins ?? this.pdfCropMargins,
      exportQuality: exportQuality ?? this.exportQuality,
    );
  }

  String toJsonString() {
    final effectiveFmt = effectivePageFormat;
    final map = <String, dynamic>{
      'mode': isFluid ? 'fluid' : 'paged',
      'theme': theme,
      'viewport_width': viewportWidth,
      'font_size': fontSize,
      'line_spacing': lineSpacing,
      'paragraph_spacing': paragraphSpacing,
      'page_format': effectiveFmt,
    };
    if (bodyFont != null && bodyFont!.isNotEmpty) {
      map['body_font'] = bodyFont;
    }
    if (codeFont != null && codeFont!.isNotEmpty) {
      map['code_font'] = codeFont;
    }
    if (imageCacheDir != null && imageCacheDir!.isNotEmpty) {
      map['image_cache_dir'] = imageCacheDir;
    }
    if (enableHeader != null) map['enable_header'] = enableHeader;
    if (enableFooter != null) map['enable_footer'] = enableFooter;
    if (enableHeader == false) {
      map['header_left'] = '';
      map['header_center'] = '';
      map['header_right'] = '';
      map['show_header_rule'] = false;
    } else {
      if (headerLeft != null) map['header_left'] = headerLeft;
      if (headerCenter != null) map['header_center'] = headerCenter;
      if (headerRight != null) map['header_right'] = headerRight;
      if (showHeaderRule != null) map['show_header_rule'] = showHeaderRule;
    }
    if (enableFooter == false) {
      map['footer_left'] = '';
      map['footer_center'] = '';
      map['footer_right'] = '';
      map['show_footer_rule'] = false;
    } else {
      if (footerLeft != null) map['footer_left'] = footerLeft;
      if (footerCenter != null) map['footer_center'] = footerCenter;
      if (footerRight != null) map['footer_right'] = footerRight;
      if (showFooterRule != null) map['show_footer_rule'] = showFooterRule;
    }
    if (skipFirstPageHeaderFooter != null) {
      map['skip_first_page_header_footer'] = skipFirstPageHeaderFooter;
    }
    if (marpEnabled != null) map['marp_enabled'] = marpEnabled;
    if (pdfCropMargins) map['pdf_crop_margins'] = pdfCropMargins;
    if (exportQuality) map['export_quality'] = exportQuality;

    return jsonEncode(map);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RenderOptions &&
          other.mode == mode &&
          other.theme == theme &&
          other.viewportWidth == viewportWidth &&
          other.fontSize == fontSize &&
          other.lineSpacing == lineSpacing &&
          other.paragraphSpacing == paragraphSpacing &&
          other.bodyFont == bodyFont &&
          other.codeFont == codeFont &&
          other.imageCacheDir == imageCacheDir &&
          other.pageFormat == pageFormat &&
          other.headerLeft == headerLeft &&
          other.headerCenter == headerCenter &&
          other.headerRight == headerRight &&
          other.footerLeft == footerLeft &&
          other.footerCenter == footerCenter &&
          other.footerRight == footerRight &&
          other.enableHeader == enableHeader &&
          other.enableFooter == enableFooter &&
          other.showHeaderRule == showHeaderRule &&
          other.showFooterRule == showFooterRule &&
          other.skipFirstPageHeaderFooter == skipFirstPageHeaderFooter &&
          other.marpEnabled == marpEnabled &&
          other.pdfCropMargins == pdfCropMargins &&
          other.exportQuality == exportQuality;

  @override
  int get hashCode => Object.hashAll([
        mode,
        theme,
        viewportWidth,
        fontSize,
        lineSpacing,
        paragraphSpacing,
        bodyFont,
        codeFont,
        imageCacheDir,
        pageFormat,
        headerLeft,
        headerCenter,
        headerRight,
        footerLeft,
        footerCenter,
        footerRight,
        enableHeader,
        enableFooter,
        showHeaderRule,
        showFooterRule,
        skipFirstPageHeaderFooter,
        marpEnabled,
        pdfCropMargins,
        exportQuality,
      ]);
}
