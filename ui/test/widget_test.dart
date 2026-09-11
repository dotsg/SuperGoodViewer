import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/controllers/reader_controller.dart';
import 'package:sogoodviewer/models/render_options.dart';

void main() {
  group('RenderOptions Tests', () {
    test('default options are fluid and light', () {
      const options = RenderOptions();
      expect(options.mode, 'fluid');
      expect(options.theme, 'light');
      expect(options.isFluid, true);
      expect(options.isDark, false);
      expect(options.viewportWidth, 850.0);
      expect(options.fontSize, 10.5);
    });

    test('copyWith works correctly', () {
      const options = RenderOptions();
      final updated = options.copyWith(
        mode: 'paged',
        theme: 'dark',
        fontSize: 12.0,
      );
      expect(updated.mode, 'paged');
      expect(updated.theme, 'dark');
      expect(updated.isFluid, false);
      expect(updated.isDark, true);
      expect(updated.fontSize, 12.0);
      expect(updated.viewportWidth, 850.0);
    });

    test('toJsonString produces valid JSON', () {
      const options = RenderOptions(
        mode: 'paged',
        theme: 'dark',
        viewportWidth: 700.0,
        fontSize: 11.5,
      );
      final json = options.toJsonString();
      expect(json, contains('"mode":"paged"'));
      expect(json, contains('"theme":"dark"'));
      expect(json, contains('"viewport_width":700.0'));
      expect(json, contains('"font_size":11.5'));
    });
  });

  group('ReaderController State Tests', () {
    test('initializes with demo document', () {
      final controller = ReaderController();
      expect(controller.documentTitle, 'SoGoodViewer Demo');
      expect(controller.currentMarkdown, isNotEmpty);
      expect(controller.renderOptions.isFluid, true);
      expect(controller.renderOptions.isDark, false);
    });

    test('toggles mode and theme', () {
      final controller = ReaderController();
      controller.toggleMode();
      expect(controller.renderOptions.mode, 'paged');
      controller.toggleMode();
      expect(controller.renderOptions.mode, 'fluid');

      controller.toggleTheme();
      expect(controller.renderOptions.theme, 'dark');
      controller.toggleTheme();
      expect(controller.renderOptions.theme, 'light');
    });

    test('updates scroll ratio correctly within [0.0, 1.0]', () {
      final controller = ReaderController();
      controller.updateScrollRatio(0.45);
      expect(controller.lastScrollRatio, 0.45);

      // Out of bounds values should be ignored
      controller.updateScrollRatio(1.5);
      expect(controller.lastScrollRatio, 0.45);
    });
  });
}
