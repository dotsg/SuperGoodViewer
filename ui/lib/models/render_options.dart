import 'dart:convert';

/// Represents rendering configuration for SuperGoodViewer.
class RenderOptions {
  final String mode; // "fluid" (continuous auto-height) or "paged" (A4 paginated)
  final String theme; // "light" or "dark"
  final double viewportWidth; // in points
  final double fontSize; // in points
  final String? bodyFont; // custom proportional font
  final String? codeFont; // custom monospace font
  final String? imageCacheDir; // custom remote image cache directory

  const RenderOptions({
    this.mode = 'fluid',
    this.theme = 'light',
    this.viewportWidth = 850.0,
    this.fontSize = 10.5,
    this.bodyFont,
    this.codeFont,
    this.imageCacheDir,
  });

  bool get isFluid => mode == 'fluid';
  bool get isDark => theme == 'dark';

  RenderOptions copyWith({
    String? mode,
    String? theme,
    double? viewportWidth,
    double? fontSize,
    String? bodyFont,
    String? codeFont,
    String? imageCacheDir,
  }) {
    return RenderOptions(
      mode: mode ?? this.mode,
      theme: theme ?? this.theme,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      fontSize: fontSize ?? this.fontSize,
      bodyFont: bodyFont ?? this.bodyFont,
      codeFont: codeFont ?? this.codeFont,
      imageCacheDir: imageCacheDir ?? this.imageCacheDir,
    );
  }

  String toJsonString() {
    final map = <String, dynamic>{
      'mode': mode,
      'theme': theme,
      'viewport_width': viewportWidth,
      'font_size': fontSize,
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
          other.imageCacheDir == imageCacheDir;

  @override
  int get hashCode => Object.hash(mode, theme, viewportWidth, fontSize, bodyFont, codeFont, imageCacheDir);
}

