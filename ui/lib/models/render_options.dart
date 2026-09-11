import 'dart:convert';

/// Represents rendering configuration for SoGoodViewer.
class RenderOptions {
  final String mode; // "fluid" (continuous auto-height) or "paged" (A4 paginated)
  final String theme; // "light" or "dark"
  final double viewportWidth; // in points
  final double fontSize; // in points

  const RenderOptions({
    this.mode = 'fluid',
    this.theme = 'light',
    this.viewportWidth = 850.0,
    this.fontSize = 10.5,
  });

  bool get isFluid => mode == 'fluid';
  bool get isDark => theme == 'dark';

  RenderOptions copyWith({
    String? mode,
    String? theme,
    double? viewportWidth,
    double? fontSize,
  }) {
    return RenderOptions(
      mode: mode ?? this.mode,
      theme: theme ?? this.theme,
      viewportWidth: viewportWidth ?? this.viewportWidth,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  String toJsonString() {
    return jsonEncode({
      'mode': mode,
      'theme': theme,
      'viewport_width': viewportWidth,
      'font_size': fontSize,
    });
  }
}
