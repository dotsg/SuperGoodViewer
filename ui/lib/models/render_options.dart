import 'dart:convert';

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

  static String getDisplayName(String format) {
    switch (format) {
      case fluid:
        return '自适应流式';
      case a4Portrait:
        return 'A4 纵向';
      case a4Landscape:
        return 'A4 横向';
      case slide16x9:
        return '16:9 幻灯片';
      case slide4x3:
        return '4:3 幻灯片';
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

  RenderOptions copyWith({
    String? mode,
    String? theme,
    double? viewportWidth,
    double? fontSize,
    String? bodyFont,
    String? codeFont,
    String? imageCacheDir,
    String? pageFormat,
    String? headerLeft,
    String? headerCenter,
    String? headerRight,
    String? footerLeft,
    String? footerCenter,
    String? footerRight,
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
      bodyFont: bodyFont ?? this.bodyFont,
      codeFont: codeFont ?? this.codeFont,
      imageCacheDir: imageCacheDir ?? this.imageCacheDir,
      pageFormat: pageFormat ?? this.pageFormat,
      headerLeft: headerLeft ?? this.headerLeft,
      headerCenter: headerCenter ?? this.headerCenter,
      headerRight: headerRight ?? this.headerRight,
      footerLeft: footerLeft ?? this.footerLeft,
      footerCenter: footerCenter ?? this.footerCenter,
      footerRight: footerRight ?? this.footerRight,
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
