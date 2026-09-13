import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sogoodviewer/views/pdf_canvas_view.dart';

void main() {
  group('Clipboard Sanitization & Crash Prevention Tests', () {
    test('sanitizeForClipboard preserves clean ASCII and standard CJK text', () {
      const input = 'Hello World! 这是中文测试。123456';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(input);
      expect(sanitized, equals(input));
    });

    test('sanitizeForClipboard preserves valid UTF-16 surrogate pairs (emojis)', () {
      // 😀 is U+1F600, represented in UTF-16 as \uD83D\uDE00
      const emojiText = 'Title: 文档 😀 🚀';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(emojiText);
      expect(sanitized, equals(emojiText));
      expect(() => utf8.encode(json.encode({'text': sanitized})), returnsNormally);
    });

    test('sanitizeForClipboard strips embedded null bytes from PDF fonts', () {
      const input = 'Header\u0000\u0000Text\u0000123';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(input);
      expect(sanitized, equals('HeaderText123'));
    });

    test('sanitizeForClipboard replaces unpaired high surrogate with replacement char', () {
      // High surrogate \uD800 followed by non-surrogate 'A'
      const input = 'Invalid\uD800Character';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(input);
      expect(sanitized, equals('Invalid\uFFFDCharacter'));
      // Verify strict UTF-8 / JSON encoding succeeds
      expect(() => utf8.encode(json.encode({'text': sanitized})), returnsNormally);
    });

    test('sanitizeForClipboard replaces trailing high surrogate with replacement char', () {
      // High surrogate \uD83D at the very end of string
      const input = 'EndingHighSurrogate\uD83D';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(input);
      expect(sanitized, equals('EndingHighSurrogate\uFFFD'));
      expect(() => utf8.encode(json.encode({'text': sanitized})), returnsNormally);
    });

    test('sanitizeForClipboard replaces unpaired low surrogate with replacement char', () {
      // Low surrogate \uDC00 alone
      const input = 'Low\uDC00Surrogate';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(input);
      expect(sanitized, equals('Low\uFFFDSurrogate'));
      expect(() => utf8.encode(json.encode({'text': sanitized})), returnsNormally);
    });

    test('sanitizeForClipboard handles empty string and single character strings', () {
      expect(PdfCanvasViewState.sanitizeForClipboard(''), equals(''));
      expect(PdfCanvasViewState.sanitizeForClipboard('A'), equals('A'));
      expect(PdfCanvasViewState.sanitizeForClipboard('\u0000'), equals(''));
      expect(PdfCanvasViewState.sanitizeForClipboard('\uD800'), equals('\uFFFD'));
      expect(PdfCanvasViewState.sanitizeForClipboard('\uDC00'), equals('\uFFFD'));
    });

    test('Sanitized string produces 100% compliant RFC-3629 UTF-8 bytes for Apple NSJSONSerialization', () {
      // Stress test with mixed broken surrogates, null bytes, and valid math symbols
      const chaoticPdfExtraction = '∫_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2} \u0000 \uD835\uDC00 \uD800 \uDC00 test \uD83D\uDE00';
      final sanitized = PdfCanvasViewState.sanitizeForClipboard(chaoticPdfExtraction);
      
      // Strict UTF-8 decoding without allowMalformed must pass
      final encoded = utf8.encode(json.encode({'text': sanitized}));
      final decoded = const Utf8Decoder(allowMalformed: false).convert(encoded);
      expect(decoded, contains('test'));
      expect(decoded, contains('😀'));
    });
  });

  group('Scroll Physics & Acceleration Delegate Tests', () {
    test('SuperGoodScrollInteractionDelegateProvider equality and instance creation', () {
      const p1 = SuperGoodScrollInteractionDelegateProvider(panFriction: 13.5, zoomFriction: 12.0);
      const p2 = SuperGoodScrollInteractionDelegateProvider(panFriction: 13.5, zoomFriction: 12.0);
      const p3 = SuperGoodScrollInteractionDelegateProvider(panFriction: 10.0, zoomFriction: 12.0);

      expect(p1, equals(p2));
      expect(p1.hashCode, equals(p2.hashCode));
      expect(p1 == p3, isFalse);

      final delegate = p1.create();
      expect(delegate, isNotNull);
      delegate.dispose();
    });
  });
}
