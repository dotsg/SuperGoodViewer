import 'dart:convert';
import '../i18n/app_strings.dart';

/// Predefined page layout formats for SuperGoodViewer.
class PageFormat {
  static const String fluid = 'fluid';
  static const String a4Portrait = 'a4Portrait';
  static const String a4Landscape = 'a4Landscape';
  static const String slide16x9 = 'slide16x9';
  static const String slide4x3 = 'slide4x3';

  static const List<String> all = [
    fluid,
    a4Portrait,
    a4Landscape,
    slide16x9,
    slide4x3,
  ];

  static String getDisplayName(String format, AppStrings strings) {
    switch (format) {
      case fluid:
        return strings.layoutModeFluid;
      case a4Portrait:
        return strings.layoutModeA4Portrait;
      case a4Landscape:
        return strings.layoutModeA4Landscape;
      case slide16x9:
        return strings.layoutModeSlide169;
      case slide4x3:
        return strings.layoutModeSlide43;
      default:
        return format;
    }
  }
}

/// Represents rendering configuration for SuperGoodViewer.
class RenderOptions {
  final String mode; // "fluid" (continuous auto-height) or "paged" (paginated)
  final String theme; // "light" or "dark"
  final double viewportWidth; // in points
  final double fontSize; // in points
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
  final bool? showHeaderRule;
  final bool? showFooterRule;
  final bool? skipFirstPageHeaderFooter;
  final bool? marpEnabled;

  const RenderOptions({
    this.mode = 'fluid',
    this.theme = 'light',
    this.viewportWidth = 850.0,
    this.fontSize = 10.5,
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
    this.showHeaderRule,
    this.showFooterRule,
    this.skipFirstPageHeaderFooter,
    this.marpEnabled,
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
      effectivePageFormat == PageFormat.slide4x3;
  bool get isA4 =>
      effectivePageFormat == PageFormat.a4Portrait ||
      effectivePageFormat == PageFormat.a4Landscape;

  double get aspectRatio {
    switch (effectivePageFormat) {
      case PageFormat.slide16x9:
        return 16.0 / 9.0;
      case PageFormat.slide4x3:
        return 4.0 / 3.0;
      case PageFormat.a4Landscape:
        return 841.89 / 595.28;
      case PageFormat.a4Portrait:
        return 595.28 / 841.89;
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
    bool? showHeaderRule,
    bool? showFooterRule,
    bool? skipFirstPageHeaderFooter,
    bool? marpEnabled,
  }) {
    return RenderOptions(
      mode: mode ?? this.mode,
      theme: theme ?? this.theme,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      fontSize: fontSize ?? this.fontSize,
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
      showHeaderRule: showHeaderRule ?? this.showHeaderRule,
      showFooterRule: showFooterRule ?? this.showFooterRule,
      skipFirstPageHeaderFooter:
          skipFirstPageHeaderFooter ?? this.skipFirstPageHeaderFooter,
      marpEnabled: marpEnabled ?? this.marpEnabled,
    );
  }

  String toJsonString() {
    final effectiveFmt = effectivePageFormat;
    final map = <String, dynamic>{
      'mode': isFluid ? 'fluid' : 'paged',
      'theme': theme,
      'viewport_width': viewportWidth,
      'font_size': fontSize,
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
    if (headerLeft != null) map['header_left'] = headerLeft;
    if (headerCenter != null) map['header_center'] = headerCenter;
    if (headerRight != null) map['header_right'] = headerRight;
    if (footerLeft != null) map['footer_left'] = footerLeft;
    if (footerCenter != null) map['footer_center'] = footerCenter;
    if (footerRight != null) map['footer_right'] = footerRight;
    if (showHeaderRule != null) map['show_header_rule'] = showHeaderRule;
    if (showFooterRule != null) map['show_footer_rule'] = showFooterRule;
    if (skipFirstPageHeaderFooter != null) {
      map['skip_first_page_header_footer'] = skipFirstPageHeaderFooter;
    }
    if (marpEnabled != null) map['marp_enabled'] = marpEnabled;

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
          other.showHeaderRule == showHeaderRule &&
          other.showFooterRule == showFooterRule &&
          other.skipFirstPageHeaderFooter == skipFirstPageHeaderFooter &&
          other.marpEnabled == marpEnabled;

  @override
  int get hashCode => Object.hashAll([
        mode,
        theme,
        viewportWidth,
        fontSize,
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
        showHeaderRule,
        showFooterRule,
        skipFirstPageHeaderFooter,
        marpEnabled,
      ]);
}
