import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io' show Platform, zlib;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'pdf_page_analysis_service.dart';

/// Semantic element type classified by the client-side PDF reflow engine.
enum ReflowElementType {
  title,
  h1,
  h2,
  h3,
  bullet,
  orderedItem,
  paragraph,
  table,
  image,
}

/// A structured semantic block extracted from a PDF document.
class ReflowElement {
  final ReflowElementType type;
  String text;
  String richText;
  final int pageNumber;

  ReflowElement({
    required this.type,
    required this.text,
    String? richText,
    required this.pageNumber,
  }) : richText = richText ?? PdfReflowService.escapeMarkdownSpan(text);
}

/// Result of client-side PDF reflow analysis and Markdown generation.
class PdfReflowResult {
  final String markdown;
  final List<ReflowElement> elements;
  final bool isCjk;
  final double bodyFontSize;
  final int pageCount;

  const PdfReflowResult({
    required this.markdown,
    required this.elements,
    required this.isCjk,
    required this.bodyFontSize,
    required this.pageCount,
  });

  bool get hasContent => elements.isNotEmpty && markdown.trim().isNotEmpty;
}

class _StyledSpan {
  final Rect rect;
  final bool isBold;
  final bool isItalic;

  const _StyledSpan({
    required this.rect,
    required this.isBold,
    required this.isItalic,
  });
}

class _PageNativeInspection {
  final List<_StyledSpan> styledSpans;
  final List<Rect> imageRects;
  final List<({double y, double left, double right})> horizontalRules;

  const _PageNativeInspection({
    this.styledSpans = const [],
    this.imageRects = const [],
    this.horizontalRules = const [],
  });
}

class _PdfiumPageInspector {
  static ffi.DynamicLibrary? _lib;
  static bool _initFailed = false;

  static late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int) _fpdfLoadPage;
  static late final void Function(ffi.Pointer<ffi.Void>) _fpdfClosePage;
  static late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>) _fpdfTextLoadPage;
  static late final void Function(ffi.Pointer<ffi.Void>) _fpdfTextClosePage;
  static late final int Function(ffi.Pointer<ffi.Void>) _fpdfTextCountChars;
  static late final int Function(ffi.Pointer<ffi.Void>, int) _fpdfTextGetUnicode;
  static late final int Function(ffi.Pointer<ffi.Void>, int) _fpdfTextGetFontWeight;
  static late final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Uint8>,
    int,
    ffi.Pointer<ffi.Int32>,
  ) _fpdfTextGetFontInfo;
  static late final int Function(
    ffi.Pointer<ffi.Void>,
    int,
    ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>,
    ffi.Pointer<ffi.Double>,
  ) _fpdfTextGetCharBox;
  static late final int Function(ffi.Pointer<ffi.Void>) _fpdfPageCountObjects;
  static late final ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int) _fpdfPageGetObject;
  static late final int Function(ffi.Pointer<ffi.Void>) _fpdfPageObjGetType;
  static late final int Function(
    ffi.Pointer<ffi.Void>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
    ffi.Pointer<ffi.Float>,
  ) _fpdfPageObjGetBounds;

  static bool _ensureInitialized() {
    if (_lib != null) return true;
    if (_initFailed) return false;
    try {
      ffi.DynamicLibrary lib;
      if (Pdfrx.pdfiumModulePath != null) {
        lib = ffi.DynamicLibrary.open(Pdfrx.pdfiumModulePath!);
      } else if (Platform.isWindows) {
        lib = ffi.DynamicLibrary.open('pdfium.dll');
      } else if (Platform.isAndroid || Platform.isLinux) {
        lib = ffi.DynamicLibrary.open('libpdfium.so');
      } else {
        lib = ffi.DynamicLibrary.process();
      }
      _fpdfLoadPage = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
          >('FPDF_LoadPage');
      _fpdfClosePage = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('FPDF_ClosePage');
      _fpdfTextLoadPage = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>)
          >('FPDFText_LoadPage');
      _fpdfTextClosePage = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Void>),
            void Function(ffi.Pointer<ffi.Void>)
          >('FPDFText_ClosePage');
      _fpdfTextCountChars = lib
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('FPDFText_CountChars');
      _fpdfTextGetUnicode = lib
          .lookupFunction<
            ffi.Uint32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            int Function(ffi.Pointer<ffi.Void>, int)
          >('FPDFText_GetUnicode');
      _fpdfTextGetFontWeight = lib
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            int Function(ffi.Pointer<ffi.Void>, int)
          >('FPDFText_GetFontWeight');
      _fpdfTextGetFontInfo = lib
          .lookupFunction<
            ffi.Uint64 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Int32,
              ffi.Pointer<ffi.Uint8>,
              ffi.Uint64,
              ffi.Pointer<ffi.Int32>,
            ),
            int Function(
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<ffi.Uint8>,
              int,
              ffi.Pointer<ffi.Int32>,
            )
          >('FPDFText_GetFontInfo');
      _fpdfTextGetCharBox = lib
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Int32,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
            ),
            int Function(
              ffi.Pointer<ffi.Void>,
              int,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
              ffi.Pointer<ffi.Double>,
            )
          >('FPDFText_GetCharBox');
      _fpdfPageCountObjects = lib
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('FPDFPage_CountObjects');
      _fpdfPageGetObject = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, ffi.Int32),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void>, int)
          >('FPDFPage_GetObject');
      _fpdfPageObjGetType = lib
          .lookupFunction<
            ffi.Int32 Function(ffi.Pointer<ffi.Void>),
            int Function(ffi.Pointer<ffi.Void>)
          >('FPDFPageObj_GetType');
      _fpdfPageObjGetBounds = lib
          .lookupFunction<
            ffi.Int32 Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
            ),
            int Function(
              ffi.Pointer<ffi.Void>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
              ffi.Pointer<ffi.Float>,
            )
          >('FPDFPageObj_GetBounds');
      _lib = lib;
      return true;
    } catch (_) {
      _initFailed = true;
      return false;
    }
  }

  static _PageNativeInspection inspectPage(PdfPage page) {
    if (!_ensureInitialized()) return const _PageNativeInspection();
    try {
      final dynDoc = page.document as dynamic;
      final fpdfDoc = ffi.Pointer<ffi.Void>.fromAddress((dynDoc.document as ffi.Pointer).address);
      if (fpdfDoc == ffi.nullptr) return const _PageNativeInspection();

      final dynPage = page as dynamic;
      final bbLeft = (dynPage.bbLeft as num).toDouble();
      final bbBottom = (dynPage.bbBottom as num).toDouble();
      final pageH = page.height;
      final pageW = page.width;

      return using((arena) {
        final fpdfPage = _fpdfLoadPage(fpdfDoc, page.pageNumber - 1);
        if (fpdfPage == ffi.nullptr) return const _PageNativeInspection();
        try {
          final styledSpans = <_StyledSpan>[];
          final textPage = _fpdfTextLoadPage(fpdfPage);
          if (textPage != ffi.nullptr) {
            try {
              final nChars = _fpdfTextCountChars(textPage);
              final fontBuf = arena<ffi.Uint8>(256);
              final flagsPtr = arena<ffi.Int32>();
              final pL = arena<ffi.Double>();
              final pR = arena<ffi.Double>();
              final pB = arena<ffi.Double>();
              final pT = arena<ffi.Double>();

              Rect? curBounds;
              bool curBold = false;
              bool curItalic = false;

              void flushSpan() {
                if (curBounds != null && (curBold || curItalic)) {
                  styledSpans.add(_StyledSpan(
                    rect: curBounds!,
                    isBold: curBold,
                    isItalic: curItalic,
                  ));
                }
                curBounds = null;
                curBold = false;
                curItalic = false;
              }

              int styledChars = 0;
              int totalNonSpaceChars = 0;

              for (var i = 0; i < nChars; i++) {
                final ch = _fpdfTextGetUnicode(textPage, i);
                if (ch <= 0x20 || ch == 0xA0 || ch == 0xFFFE || ch == 0xFFFF) {
                  continue;
                }
                if (_fpdfTextGetCharBox(textPage, i, pL, pR, pB, pT) == 0) {
                  continue;
                }
                final left = pL.value - bbLeft;
                final right = pR.value - bbLeft;
                final top = pageH - (pT.value - bbBottom);
                final bottom = pageH - (pB.value - bbBottom);
                final cRect = Rect.fromLTRB(
                  math.min(left, right),
                  math.min(top, bottom),
                  math.max(left, right),
                  math.max(top, bottom),
                );
                if (cRect.width <= 0 && cRect.height <= 0) continue;

                final weight = _fpdfTextGetFontWeight(textPage, i);
                flagsPtr.value = 0;
                final nameLen = _fpdfTextGetFontInfo(textPage, i, fontBuf, 256, flagsPtr);
                String fontLower = '';
                if (nameLen > 1) {
                  final bytes = fontBuf.asTypedList(math.min(nameLen - 1, 255));
                  fontLower = String.fromCharCodes(bytes).toLowerCase();
                }
                final flags = flagsPtr.value;

                final isBold = weight >= 600 ||
                    fontLower.contains('bold') ||
                    fontLower.contains('black') ||
                    fontLower.contains('heavy') ||
                    fontLower.contains('semibold') ||
                    fontLower.contains('demibold') ||
                    (flags & 0x40000) != 0;
                final isItalic = fontLower.contains('italic') ||
                    fontLower.contains('oblique') ||
                    (flags & 0x40) != 0;

                totalNonSpaceChars++;
                if (isBold) styledChars++;

                if (curBounds == null) {
                  curBounds = cRect;
                  curBold = isBold;
                  curItalic = isItalic;
                } else {
                  final sameStyle = curBold == isBold && curItalic == isItalic;
                  final sameLine = (cRect.center.dy - curBounds!.center.dy).abs() <=
                      math.max(4.5, curBounds!.height * 0.75);
                  final closeHoriz = (cRect.left - curBounds!.right) <=
                          math.max(16.0, curBounds!.height * 1.8) &&
                      (cRect.left >= curBounds!.left - 4.0);
                  if (sameStyle && sameLine && closeHoriz) {
                    curBounds = curBounds!.expandToInclude(cRect);
                  } else {
                    flushSpan();
                    curBounds = cRect;
                    curBold = isBold;
                    curItalic = isItalic;
                  }
                }
              }
              flushSpan();

              // If >65% of characters on the page report bold, the base body font itself is bold-weighted;
              // suppress bold spans on that page so body paragraphs aren't wrapped in **...**.
              if (totalNonSpaceChars > 40 && styledChars / totalNonSpaceChars > 0.65) {
                for (var idx = 0; idx < styledSpans.length; idx++) {
                  final s = styledSpans[idx];
                  styledSpans[idx] = _StyledSpan(
                    rect: s.rect,
                    isBold: false,
                    isItalic: s.isItalic,
                  );
                }
                styledSpans.removeWhere((s) => !s.isBold && !s.isItalic);
              }
            } finally {
              _fpdfTextClosePage(textPage);
            }
          }

          final imageRects = <Rect>[];
          final horizontalRules = <({double y, double left, double right})>[];
          final nObjs = _fpdfPageCountObjects(fpdfPage);
          final fL = arena<ffi.Float>();
          final fB = arena<ffi.Float>();
          final fR = arena<ffi.Float>();
          final fT = arena<ffi.Float>();

          for (var i = 0; i < nObjs; i++) {
            final obj = _fpdfPageGetObject(fpdfPage, i);
            if (obj == ffi.nullptr) continue;
            final objType = _fpdfPageObjGetType(obj);
            // FPDF_PAGEOBJECT_PATH = 2, FPDF_PAGEOBJECT_IMAGE = 3
            if (objType != 2 && objType != 3) continue;
            if (_fpdfPageObjGetBounds(obj, fL, fB, fR, fT) == 0) continue;

            final left = (fL.value - bbLeft).clamp(0.0, pageW);
            final right = (fR.value - bbLeft).clamp(0.0, pageW);
            final top = (pageH - (fT.value - bbBottom)).clamp(0.0, pageH);
            final bottom = (pageH - (fB.value - bbBottom)).clamp(0.0, pageH);
            final rect = Rect.fromLTRB(
              math.min(left, right),
              math.min(top, bottom),
              math.max(left, right),
              math.max(top, bottom),
            );
            if (objType == 3) {
              if (rect.width >= 48.0 && rect.height >= 48.0) {
                final aspect = rect.width / rect.height;
                if (aspect >= 0.15 && aspect <= 7.5) {
                  imageRects.add(rect);
                }
              }
            } else if (objType == 2 && rect.width >= 18.0) {
              if (rect.height <= 4.5) {
                horizontalRules.add((
                  y: rect.center.dy,
                  left: rect.left,
                  right: rect.right,
                ));
              } else if (rect.height <= 360.0) {
                // Table cell / shaded row band / table frame rectangle
                horizontalRules.add((
                  y: rect.top,
                  left: rect.left,
                  right: rect.right,
                ));
                horizontalRules.add((
                  y: rect.bottom,
                  left: rect.left,
                  right: rect.right,
                ));
              }
            }
          }

          return _PageNativeInspection(
            styledSpans: styledSpans,
            imageRects: imageRects,
            horizontalRules: horizontalRules,
          );
        } finally {
          _fpdfClosePage(fpdfPage);
        }
      });
    } catch (_) {
      return const _PageNativeInspection();
    }
  }
}

class _VisualFragment {
  final Rect rect;
  final String text;
  final bool hasTrailingSpace;
  final bool noSpaceBefore;
  final bool startsParagraph;
  final int? textStart;
  final int? textEnd;
  final bool isBold;
  final bool isItalic;
  final String? linkUrl;

  const _VisualFragment({
    required this.rect,
    required this.text,
    this.hasTrailingSpace = false,
    this.noSpaceBefore = false,
    this.startsParagraph = false,
    this.textStart,
    this.textEnd,
    this.isBold = false,
    this.isItalic = false,
    this.linkUrl,
  });
}

class _VisualLine {
  final Rect bounds;
  final String text;
  final String richText;
  final String headingRichText;
  final double maxHeight;
  final bool startsParagraph;
  final bool isSplitHeaderLine;
  final bool isAllBold;
  final bool isAllItalic;
  final bool startsWithBoldColon;
  final int? firstTextStart;
  final int? lastTextEnd;

  const _VisualLine({
    required this.bounds,
    required this.text,
    required this.richText,
    required this.headingRichText,
    required this.maxHeight,
    this.startsParagraph = false,
    this.isSplitHeaderLine = false,
    this.isAllBold = false,
    this.isAllItalic = false,
    this.startsWithBoldColon = false,
    this.firstTextStart,
    this.lastTextEnd,
  });
}

/// Client-side PDF Reflow Service for SuperGoodViewer.
///
/// Converts standard A4 / Letter / multi-column PDFs into clean, mobile-friendly
/// structured Markdown on-device using PDFium (`pdfrx`) text geometry and
/// [PdfPageAnalysisService] column detection, which is then compiled by the
/// native Rust Typst engine into a responsive Fluid or Paged document.
class PdfReflowService {
  static final Map<int, PdfReflowResult> _cache = {};
  static const int _maxCacheEntries = 6;

  /// Clears the in-memory reflow cache.
  static void clearCache() => _cache.clear();

  /// Returns true if [cp] is a CJK unified ideograph or punctuation character.
  static bool isCjkCodeUnit(int cp) {
    return (cp >= 0x4E00 && cp <= 0x9FFF) ||
        (cp >= 0x3400 && cp <= 0x4DBF) ||
        (cp >= 0xF900 && cp <= 0xFAFF) ||
        (cp >= 0x3000 && cp <= 0x303F) ||
        (cp >= 0xFF00 && cp <= 0xFFEF);
  }

  /// Returns true if [cp] is fullwidth CJK punctuation or em-dash/smart-quote where no space should be added.
  static bool isCjkPunctuation(int cp) {
    return (cp >= 0x3000 && cp <= 0x303F) ||
        (cp >= 0xFF00 && cp <= 0xFFEF) ||
        cp == 0x2014 ||
        cp == 0x201C ||
        cp == 0x201D;
  }

  /// Detects whether a collection of text samples is primarily CJK (>15% CJK chars).
  static bool detectIsCjk(Iterable<String> samples) {
    int cjkCount = 0;
    int totalCount = 0;
    for (final sample in samples) {
      for (final rune in sample.runes) {
        if (rune <= 0x20 || rune == 0xA0) continue;
        totalCount++;
        if (isCjkCodeUnit(rune)) {
          cjkCount++;
        }
      }
    }
    if (totalCount == 0) return false;
    return (cjkCount / totalCount) > 0.15;
  }

  /// Language-aware line joining with English hyphenation unwrapping and CJK stitching.
  static String joinTextFlow(
    String t1,
    String t2, {
    required bool isCjk,
    bool softHyphenWrap = false,
  }) {
    var a = t1.trimRight();
    var b = t2.trimLeft();
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;

    // If joining two rich-text lines that end and start with the exact same emphasis marker
    // (*, **, or ***), unwrap the boundary marker so multi-line emphasis and hyphenated
    // emphasized words (e.g. "*Times Mag*" + "*azine*" -> "*Times Magazine*") merge cleanly.
    for (final marker in const ['***', '**', '*']) {
      if (a.endsWith(marker) &&
          b.startsWith(marker) &&
          a.length > marker.length &&
          b.length > marker.length &&
          !a.endsWith('\\$marker')) {
        final nextLen = marker.length + 1;
        final aHasMore = a.length >= nextLen && a.endsWith('*' * nextLen);
        final bHasMore = b.length >= nextLen && b.startsWith('*' * nextLen);
        if (!aHasMore && !bHasMore) {
          a = a.substring(0, a.length - marker.length);
          b = b.substring(marker.length);
          break;
        }
      }
    }

    // Unwrap English line-break hyphenation (e.g. "dimen-" + "sion" -> "dimension",
    // or PDFium-stripped soft hyphen wrap where two line segments are adjacent in fullText)
    final hasExplicitHyphen = a.endsWith('-') || a.endsWith('\u00AD');
    if (hasExplicitHyphen || softHyphenWrap) {
      final prefix = hasExplicitHyphen ? a.substring(0, a.length - 1) : a;
      final lastSpace = prefix.lastIndexOf(' ');
      final rawWordBefore = lastSpace == -1 ? prefix : prefix.substring(lastSpace + 1);
      final wordBefore = rawWordBefore.replaceFirst(RegExp(r'^\*{1,3}'), '');
      final firstSpace = b.indexOf(' ');
      final rawWordAfter = firstSpace == -1 ? b : b.substring(0, firstSpace);
      final wordAfter = rawWordAfter.replaceFirst(RegExp(r'\*{1,3}(?=[.,;:!?”’\)\]]*$)'), '');
      final alphaOrHyphenBefore = RegExp(r'^[a-zA-Z]+(?:-[a-zA-Z]+)*$');
      final alphaAfter = RegExp(r'^[a-zA-Z]+(?:[.,;:!?”’\)\]]*)?$');
      if (alphaOrHyphenBefore.hasMatch(wordBefore) && alphaAfter.hasMatch(wordAfter)) {
        // Keep hyphen for compound modifiers like "multi-head", multi-hyphen "hard-of-hearing",
        // or capitalized second part
        final lowerBefore = wordBefore.toLowerCase();
        const compoundPrefixes = {
          'multi',
          'self',
          'cross',
          'non',
          'pre',
          'post',
          'sub',
          'co',
          'inter',
          'intra',
          'semi',
          'high',
          'low',
          'real',
          'end',
          'state',
          'fine',
          'zero',
          'one',
          'two',
          'three',
        };
        if (wordBefore.contains('-') ||
            compoundPrefixes.contains(lowerBefore) ||
            (wordAfter.isNotEmpty &&
                wordAfter[0] == wordAfter[0].toUpperCase() &&
                wordAfter[0] != wordAfter[0].toLowerCase())) {
          return '$prefix-$b';
        }
        return '$prefix$b';
      }
      if (hasExplicitHyphen) {
        return '$a$b';
      }
    }

    final aVisible = a.replaceFirst(RegExp(r'\*{1,3}$'), '');
    final bVisible = b.replaceFirst(RegExp(r'^\*{1,3}'), '');
    final lastRune = (aVisible.isNotEmpty ? aVisible : a).runes.last;
    final firstRune = (bVisible.isNotEmpty ? bVisible : b).runes.first;
    if (isCjk &&
        ((isCjkCodeUnit(lastRune) && isCjkCodeUnit(firstRune)) ||
            isCjkPunctuation(lastRune) ||
            isCjkPunctuation(firstRune))) {
      return '$a$b';
    }
    return '$a $b';
  }

  /// Escapes characters in raw PDF text that could be misinterpreted as broken
  /// Markdown or LaTeX math syntax while preserving readable prose.
  static String escapeMarkdownSpan(String input) {
    final cleaned = input
        .replaceAll('\x00', '')
        .replaceAll(RegExp(r'[\x01-\x08\x0B\x0C\x0E-\x1F\uE000-\uF8FF]'), '')
        .replaceAll(RegExp(r'(?:^|(?<=\s))1(?=[A-Z][a-zA-Z]{2,})'), '')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return '';

    final sb = StringBuffer();
    for (int i = 0; i < cleaned.length; i++) {
      final ch = cleaned[i];
      switch (ch) {
        case r'\':
          sb.write(r'\\');
        case r'$':
          sb.write(r'\$');
        case '*':
          sb.write(r'\*');
        case '_':
          sb.write(r'\_');
        case '`':
          sb.write(r'\`');
        case '<':
          sb.write('&lt;');
        case '>':
          sb.write('&gt;');
        case '[':
          sb.write(r'\[');
        case ']':
          sb.write(r'\]');
        case '~':
          sb.write(r'\~');
        default:
          sb.write(ch);
      }
    }
    var result = sb.toString();
    if (result.startsWith('#')) {
      result = '\\$result';
    }
    return result;
  }

  static final RegExp _trailingCloseQuoteOrBracket = RegExp(r'''["'”’」』)）\]]+$''');

  static bool _endsWithParagraphPunctuation(String text) {
    final trimmed = text.trimRight().replaceFirst(_trailingCloseQuoteOrBracket, '');
    if (trimmed.isEmpty) return false;
    return trimmed.endsWith('.') ||
        trimmed.endsWith('。') ||
        trimmed.endsWith('!') ||
        trimmed.endsWith('！') ||
        trimmed.endsWith('?') ||
        trimmed.endsWith('？') ||
        trimmed.endsWith(':') ||
        trimmed.endsWith('：') ||
        trimmed.endsWith('…');
  }

  static bool _endsWithSentenceClausePunctuation(String text) {
    final trimmed = text.trimRight().replaceFirst(_trailingCloseQuoteOrBracket, '');
    if (trimmed.isEmpty) return false;
    return trimmed.endsWith('.') ||
        trimmed.endsWith('。') ||
        trimmed.endsWith(',') ||
        trimmed.endsWith('，') ||
        trimmed.endsWith(';') ||
        trimmed.endsWith('；');
  }

  /// Extracts and reflows a PDF byte buffer into structured Markdown.
  static Future<PdfReflowResult> reflowPdfBytes(
    Uint8List pdfBytes, {
    String? documentTitle,
  }) async {
    final cacheKey = Object.hash(pdfBytes.length, identityHashCode(pdfBytes), documentTitle);
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    final doc = await PdfDocument.openData(pdfBytes);
    try {
      final result = await reflowDocument(doc, documentTitle: documentTitle);
      if (result.hasContent) {
        _cache[cacheKey] = result;
        if (_cache.length > _maxCacheEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return result;
    } finally {
      await doc.dispose();
    }
  }

  /// Extracts and reflows an already opened [PdfDocument] into structured Markdown.
  static Future<PdfReflowResult> reflowDocument(
    PdfDocument doc, {
    String? documentTitle,
  }) async {
    if (doc.pages.isEmpty) {
      return const PdfReflowResult(
        markdown: '',
        elements: [],
        isCjk: false,
        bodyFontSize: 10.0,
        pageCount: 0,
      );
    }

    final unloaded = <int>[
      for (final p in doc.pages)
        if (!p.isLoaded) p.pageNumber,
    ];
    if (unloaded.isNotEmpty) {
      await doc.reloadPages(pageNumbersToReload: unloaded);
    }

    final pageTexts = <PdfPageText>[];
    final pageLinksList = <List<({Rect rect, String url})>>[];
    final pageInspections = <_PageNativeInspection>[];
    final pageAnalyses = <PdfPageAnalysis>[];
    final sampleStrings = <String>[];

    for (var i = 0; i < doc.pages.length; i++) {
      final page = doc.pages[i];
      final pageText = await page.loadStructuredText();
      final rawLinks = await page.loadLinks(enableAutoLinkDetection: true);
      final linkRects = <({Rect rect, String url})>[];
      for (final link in rawLinks) {
        final url = link.url?.toString();
        if (url == null || url.isEmpty) continue;
        for (final r in link.rects) {
          final rect = r.toRect(page: page);
          if (rect.width > 0 && rect.height > 0) {
            linkRects.add((rect: rect, url: url));
          }
        }
      }
      pageTexts.add(pageText);
      pageLinksList.add(linkRects);
      pageInspections.add(_PdfiumPageInspector.inspectPage(page));
      pageAnalyses.add(PdfPageAnalysisService.computePageAnalysis(page, pageText));
      if (i < 5 && pageText.fullText.isNotEmpty) {
        sampleStrings.add(pageText.fullText);
      }
    }

    final isCjk = detectIsCjk(sampleStrings);

    // Collect ordered visual lines and extracted tables per page, and profile line heights
    final heightHistogram = <double, int>{};
    final pageLinesList = <List<({List<_VisualLine> lines, Rect regionBounds, bool isBottomSpanning})>>[];
    final pageTablesList = <List<({Rect rect, String markdownTable})>>[];

    for (var pno = 0; pno < doc.pages.length; pno++) {
      final page = doc.pages[pno];
      final pageText = pageTexts[pno];
      final analysis = pageAnalyses[pno];
      final extracted = _extractOrderedRegionLines(
        page,
        pageText,
        analysis,
        isCjk: isCjk,
        styledSpans: pageInspections[pno].styledSpans,
        linkRects: pageLinksList[pno],
        horizontalRules: pageInspections[pno].horizontalRules,
      );
      pageLinesList.add(extracted.regions);
      pageTablesList.add(extracted.tables);

      for (final region in extracted.regions) {
        for (final line in region.lines) {
          final textLen = line.text.trim().length;
          if (textLen > 1 && line.maxHeight > 4.0 && line.maxHeight < 72.0) {
            final bucket = (line.maxHeight * 2).round() / 2.0;
            heightHistogram[bucket] = (heightHistogram[bucket] ?? 0) + textLen;
          }
        }
      }
    }

    double bodyHeight = 10.0;
    if (heightHistogram.isNotEmpty) {
      var bestBucket = 10.0;
      var bestWeight = -1;
      heightHistogram.forEach((bucket, weight) {
        if (weight > bestWeight) {
          bestWeight = weight;
          bestBucket = bucket;
        }
      });
      bodyHeight = bestBucket;
    }

    final largerSizes = heightHistogram.keys
        .where((s) => s > bodyHeight * 1.08 && (heightHistogram[s] ?? 0) >= 4)
        .toList()
      ..sort();

    double h3Size = bodyHeight * 1.10;
    double h2Size = bodyHeight * 1.18;
    double h1Size = bodyHeight * 1.32;
    double titleSize = bodyHeight * 1.50;

    if (largerSizes.length == 1) {
      h1Size = largerSizes[0];
      h2Size = largerSizes[0];
    } else if (largerSizes.length == 2) {
      if (largerSizes[1] >= bodyHeight * 1.42) {
        // Larger bucket is document title, smaller bucket is H1 section heading
        h1Size = largerSizes[0];
        h2Size = largerSizes[0];
        titleSize = largerSizes[1];
      } else {
        h2Size = largerSizes[0];
        h1Size = largerSizes[1];
        titleSize = largerSizes[1];
      }
    } else if (largerSizes.length >= 3) {
      h3Size = largerSizes[0];
      h2Size = largerSizes[1];
      h1Size = largerSizes[2];
      titleSize = largerSizes.last;
    }

    // Extract standalone embedded figures (up to 12 per document)
    final pageFiguresList = List<List<({Rect rect, String markdownImage})>>.generate(
      doc.pages.length,
      (_) => [],
    );
    int extractedFigureCount = 0;
    for (var pno = 0; pno < doc.pages.length && extractedFigureCount < 12; pno++) {
      final rawRects = pageInspections[pno].imageRects;
      if (rawRects.isEmpty) continue;
      final page = doc.pages[pno];
      final allPageLines = <Rect>[
        for (final r in pageLinesList[pno])
          for (final l in r.lines) l.bounds,
        for (final t in pageTablesList[pno]) t.rect,
      ];
      final figures = await _extractStandalonePageFigures(
        page,
        rawRects,
        allPageLines,
        remainingQuota: 12 - extractedFigureCount,
      );
      pageFiguresList[pno] = figures;
      extractedFigureCount += figures.length;
    }

    final elements = <ReflowElement>[];
    ReflowElement? curBullet;
    ReflowElement? curParagraph;
    bool curParagraphForceFlushNext = false;

    void flushBlock() {
      if (curBullet != null) {
        elements.add(curBullet!);
        curBullet = null;
      }
      if (curParagraph != null) {
        elements.add(curParagraph!);
        curParagraph = null;
      }
      curParagraphForceFlushNext = false;
    }

    final bulletRegex = RegExp(r'^(?:[•●○▪◆Ø\-\*]|(?:\(\d+\))|(?:\d+\)))\s+(.*)$');
    final orderedItemRegex = RegExp(r'^(\d{1,2})\.\s+(\S+.*)$');
    final circledHeadingRegex = RegExp(r'^[\u2460-\u2473]\s*\S+.*$');
    final h1SectionRegex = RegExp(
      r'^(?:(?:Abstract|Introduction|Conclusion|Conclusions|References|Acknowledgments|Acknowledgements|Appendix|摘要|引言|结论|参考文献|致谢)|(?:[IVX]+\.\s+[A-Z].*)|(?:\d+\.?\s+[A-Z\u4e00-\u9fa5].*)|(?:第[一二三四五六七八九十百千万0-9]+[章节篇部]\s*.*))$',
    );
    final h2SectionRegex = RegExp(
      r'^(?:(?:\d+\.\d+(?:\.\d+)?\.?\s+\S+.*)|(?:[一二三四五六七八九十]+、\s*\S+.*)|(?:\([一二三四五六七八九十]+\)\s*\S+.*))$',
    );
    final allCapsHeadingRegex = RegExp(r'^[A-Z][A-Z0-9\s&,/\-–—]{2,44}$');

    for (var pno = 0; pno < doc.pages.length; pno++) {
      final page = doc.pages[pno];
      final analysis = pageAnalyses[pno];
      final regions = pageLinesList[pno];
      final pendingFigures = List<({Rect rect, String markdownImage})>.from(pageFiguresList[pno]);
      final pendingTables = List<({Rect rect, String markdownTable})>.from(pageTablesList[pno]);
      final totalPageLines = regions.fold<int>(0, (sum, r) => sum + r.lines.length);
      final isFullPageCaptionOnly = totalPageLines > 0 &&
          totalPageLines <= 3 &&
          regions.every((r) => r.regionBounds.top > page.height * 0.78);

      void emitDueBlocks(double upToY) {
        while (true) {
          final hasFig = pendingFigures.isNotEmpty && pendingFigures.first.rect.top <= upToY;
          final hasTab = pendingTables.isNotEmpty && pendingTables.first.rect.top <= upToY;
          if (!hasFig && !hasTab) break;
          if (hasTab && (!hasFig || pendingTables.first.rect.top <= pendingFigures.first.rect.top)) {
            final tab = pendingTables.removeAt(0);
            elements.add(ReflowElement(
              type: ReflowElementType.table,
              text: tab.markdownTable,
              richText: tab.markdownTable,
              pageNumber: pno + 1,
            ));
          } else {
            final fig = pendingFigures.removeAt(0);
            elements.add(ReflowElement(
              type: ReflowElementType.image,
              text: fig.markdownImage,
              richText: fig.markdownImage,
              pageNumber: pno + 1,
            ));
          }
        }
      }

      if (regions.isEmpty && (pendingFigures.isNotEmpty || pendingTables.isNotEmpty)) {
        final holdCrossPage = curParagraph != null && !_endsWithParagraphPunctuation(curParagraph!.text);
        final saved = holdCrossPage ? curParagraph : null;
        if (holdCrossPage) {
          curParagraph = null;
        } else {
          flushBlock();
        }
        emitDueBlocks(double.infinity);
        if (holdCrossPage) {
          curParagraph = saved;
        }
        continue;
      }

      for (final region in regions) {
        final lines = region.lines;
        if (lines.isEmpty) continue;

        // If this region is a bottom figure caption or a full-page photo caption
        // and the previous column ended mid-sentence, hold curParagraph across the caption
        // so cross-page sentences continue seamlessly onto the next page's first column.
        final holdCrossPageSentence = (region.isBottomSpanning || isFullPageCaptionOnly) &&
            curParagraph != null &&
            !_endsWithParagraphPunctuation(curParagraph!.text);
        ReflowElement? savedParagraph;
        if (holdCrossPageSentence) {
          savedParagraph = curParagraph;
          curParagraph = null;
          emitDueBlocks(region.regionBounds.top + 12.0);
        }

        // Compute base left margin of body lines in this column/region for first-line-indent detection
        double? colBaseLeft;
        if (!region.isBottomSpanning && lines.length >= 3) {
          final bodyLefts = <double>[
            for (final l in lines)
              if (l.maxHeight <= bodyHeight * 1.16) l.bounds.left,
          ]..sort();
          if (bodyLefts.length >= 3) {
            colBaseLeft = bodyLefts[(bodyLefts.length * 0.15).floor()];
          }
        }

        final regionRight = region.regionBounds.right;
        double? prevLineBottom;
        double? prevLineRight;
        int? prevLineTextEnd;

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;

          // If a table starts above this line, flush any open block and emit the table first
          if (pendingTables.isNotEmpty && pendingTables.first.rect.top <= line.bounds.top) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
          }

          // Skip isolated page numbers or single-digit section ornaments
          if (RegExp(r'^\d{1,4}$').hasMatch(lineText) && lines.length > 2) {
            if (curParagraph != null && _endsWithParagraphPunctuation(curParagraph!.text)) {
              flushBlock();
              emitDueBlocks(line.bounds.bottom);
            }
            continue;
          }

          final maxSize = line.maxHeight;
          final verticalGap = prevLineBottom != null ? (line.bounds.top - prevLineBottom) : 0.0;
          final isLargeVerticalGap = prevLineBottom != null && verticalGap > bodyHeight * 0.85;
          final prevWasShortLine = prevLineRight != null &&
              region.regionBounds.width > 100 &&
              (regionRight - prevLineRight) > region.regionBounds.width * 0.22;
          final indent = colBaseLeft != null ? (line.bounds.left - colBaseLeft) : 0.0;
          final isFirstLineIndented = i > 0 &&
              colBaseLeft != null &&
              region.regionBounds.width > 100 &&
              indent >= bodyHeight * 0.65 &&
              indent <= bodyHeight * 3.2;
          final isSoftHyphenWrap = prevLineTextEnd != null &&
              line.firstTextStart != null &&
              line.firstTextStart == prevLineTextEnd;

          prevLineBottom = line.bounds.bottom;
          prevLineRight = line.bounds.right;
          prevLineTextEnd = line.lastTextEnd;

          // 1. Document Title detection on page 1
          if (pno == 0 &&
              maxSize >= math.min(titleSize * 0.94, bodyHeight * 1.42) &&
              lineText.length < 140) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            if (elements.isNotEmpty &&
                elements.last.type == ReflowElementType.title &&
                elements.last.pageNumber == 1) {
              elements.last.text = joinTextFlow(elements.last.text, lineText, isCjk: isCjk);
              elements.last.richText = joinTextFlow(
                elements.last.richText,
                line.headingRichText,
                isCjk: isCjk,
              );
            } else {
              elements.add(ReflowElement(
                type: ReflowElementType.title,
                text: lineText,
                richText: line.headingRichText,
                pageNumber: pno + 1,
              ));
            }
            continue;
          }

          final endsWithSentencePunct = _endsWithSentenceClausePunctuation(lineText);

          // 2. Heading 1 detection
          // Note: All-caps lines have no lowercase descenders (g, j, p, q, y), so their glyph
          // cap-height box is ~72% of a mixed-case line's ascender+descender box at the same point size.
          final isAllCapsSection = line.isAllBold &&
              maxSize >= bodyHeight * 0.82 &&
              lineText.length >= 4 &&
              allCapsHeadingRegex.hasMatch(lineText);
          if (!endsWithSentencePunct &&
              lineText.length < 90 &&
              (maxSize >= math.min(h1Size * 0.94, bodyHeight * 1.26) ||
                  isAllCapsSection ||
                  (maxSize >= bodyHeight * 1.08 && h1SectionRegex.hasMatch(lineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            if (elements.isNotEmpty &&
                elements.last.type == ReflowElementType.h1 &&
                elements.last.pageNumber == pno + 1 &&
                !isLargeVerticalGap &&
                maxSize >= math.min(h1Size * 0.94, bodyHeight * 1.26)) {
              elements.last.text = joinTextFlow(elements.last.text, lineText, isCjk: isCjk);
              elements.last.richText = joinTextFlow(
                elements.last.richText,
                line.headingRichText,
                isCjk: isCjk,
              );
            } else {
              elements.add(ReflowElement(
                type: ReflowElementType.h1,
                text: lineText,
                richText: line.headingRichText,
                pageNumber: pno + 1,
              ));
            }
            continue;
          }

          // 3. Heading 2 detection
          if (!endsWithSentencePunct &&
              lineText.length < 80 &&
              ((maxSize >= math.min(h2Size * 0.95, bodyHeight * 1.14) && maxSize >= bodyHeight * 1.08) ||
                  (maxSize >= bodyHeight * 0.96 && h2SectionRegex.hasMatch(lineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            elements.add(ReflowElement(
              type: ReflowElementType.h2,
              text: lineText,
              richText: line.headingRichText,
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 4. Heading 3 detection (including circled-number subheadings ①..⑳)
          if (!endsWithSentencePunct &&
              lineText.length < 65 &&
              ((maxSize >= math.min(h3Size * 0.96, bodyHeight * 1.09) && isLargeVerticalGap) ||
                  (line.isAllBold && circledHeadingRegex.hasMatch(lineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            elements.add(ReflowElement(
              type: ReflowElementType.h3,
              text: lineText,
              richText: line.headingRichText,
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 5. Bullet & Ordered list item detection
          final bulletMatch = bulletRegex.firstMatch(lineText);
          if (bulletMatch != null) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            curBullet = ReflowElement(
              type: ReflowElementType.bullet,
              text: bulletMatch.group(1)!.trim(),
              richText: _stripLeadingBulletMarker(line.richText),
              pageNumber: pno + 1,
            );
            continue;
          }

          final orderedMatch = orderedItemRegex.firstMatch(lineText);
          if (orderedMatch != null && maxSize <= bodyHeight * 1.08) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
            curBullet = ReflowElement(
              type: ReflowElementType.orderedItem,
              text: lineText,
              richText: line.richText,
              pageNumber: pno + 1,
            );
            continue;
          }

          // 6. Structured subheader / metadata line detection (split left-right headers,
          // short standalone bold/italic subheaders, pipe-delimited contact bars, or BoldLabel: lines)
          final isStandaloneSubheader = line.isSplitHeaderLine ||
              (pno == 0 && lineText.contains(' | ') && lineText.length < 120) ||
              (!endsWithSentencePunct &&
                  line.bounds.width < region.regionBounds.width * 0.76 &&
                  (line.isAllBold || (!analysis.isMultiColumn && line.isAllItalic)));

          if (curParagraphForceFlushNext ||
              isStandaloneSubheader ||
              line.startsWithBoldColon ||
              line.startsParagraph ||
              isLargeVerticalGap) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
          } else if (curParagraph != null &&
              (isFirstLineIndented || prevWasShortLine) &&
              _endsWithParagraphPunctuation(curParagraph!.text)) {
            flushBlock();
            emitDueBlocks(line.bounds.top);
          }

          if (curBullet != null) {
            curBullet!.text = joinTextFlow(
              curBullet!.text,
              lineText,
              isCjk: isCjk,
              softHyphenWrap: isSoftHyphenWrap,
            );
            curBullet!.richText = joinTextFlow(
              curBullet!.richText,
              line.richText,
              isCjk: isCjk,
              softHyphenWrap: isSoftHyphenWrap,
            );
          } else if (curParagraph != null) {
            curParagraph!.text = joinTextFlow(
              curParagraph!.text,
              lineText,
              isCjk: isCjk,
              softHyphenWrap: isSoftHyphenWrap,
            );
            curParagraph!.richText = joinTextFlow(
              curParagraph!.richText,
              line.richText,
              isCjk: isCjk,
              softHyphenWrap: isSoftHyphenWrap,
            );
          } else {
            curParagraph = ReflowElement(
              type: ReflowElementType.paragraph,
              text: lineText,
              richText: line.richText,
              pageNumber: pno + 1,
            );
            if (isStandaloneSubheader) {
              curParagraphForceFlushNext = true;
            }
          }
        }

        if (holdCrossPageSentence) {
          flushBlock();
          emitDueBlocks(region.regionBounds.bottom + 20.0);
          curParagraph = savedParagraph;
        } else if (region.isBottomSpanning ||
            (curParagraph != null && _endsWithParagraphPunctuation(curParagraph!.text))) {
          flushBlock();
          emitDueBlocks(region.regionBounds.bottom + 20.0);
        }
      }

      if (pendingFigures.isNotEmpty || pendingTables.isNotEmpty) {
        final holdCrossPage = curParagraph != null && !_endsWithParagraphPunctuation(curParagraph!.text);
        final saved = holdCrossPage ? curParagraph : null;
        if (holdCrossPage) {
          curParagraph = null;
        } else {
          flushBlock();
        }
        emitDueBlocks(double.infinity);
        if (holdCrossPage) {
          curParagraph = saved;
        }
      }
    }
    flushBlock();

    final markdown = buildMarkdownFromElements(
      elements,
      documentTitle: documentTitle,
    );

    return PdfReflowResult(
      markdown: markdown,
      elements: elements,
      isCjk: isCjk,
      bodyFontSize: bodyHeight,
      pageCount: doc.pages.length,
    );
  }

  static final RegExp _richBulletPrefixRegex = RegExp(
    r'^(?:(?:\*{1,3})?(?:[•●○▪◆Ø\-\*]|\\\*|(?:\(\d+\))|(?:\d+\)))(?:\*{1,3})?)\s+(.*)$',
  );

  static String _stripLeadingBulletMarker(String richText) {
    final trimmed = richText.trim();
    final match = _richBulletPrefixRegex.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return trimmed;
  }

  /// Generates clean Markdown from classified [ReflowElement] blocks.
  static String buildMarkdownFromElements(
    List<ReflowElement> elements, {
    String? documentTitle,
  }) {
    if (elements.isEmpty) return '';

    final lines = <String>[];
    bool titleRendered = false;

    for (var i = 0; i < elements.length; i++) {
      final el = elements[i];
      final content = el.richText.trim().isNotEmpty
          ? el.richText.trim()
          : escapeMarkdownSpan(el.text);
      if (content.isEmpty) continue;

      switch (el.type) {
        case ReflowElementType.title:
          if (!titleRendered) {
            lines.add('# $content\n');
            titleRendered = true;
          } else {
            lines.add('## $content\n');
          }
        case ReflowElementType.h1:
          lines.add('## $content\n');
        case ReflowElementType.h2:
          lines.add('### $content\n');
        case ReflowElementType.h3:
          lines.add('#### $content\n');
        case ReflowElementType.bullet:
          final nextType = i + 1 < elements.length ? elements[i + 1].type : null;
          final suffix = nextType == ReflowElementType.bullet ? '' : '\n';
          lines.add('- $content$suffix');
        case ReflowElementType.orderedItem:
          final nextType = i + 1 < elements.length ? elements[i + 1].type : null;
          final suffix = nextType == ReflowElementType.orderedItem ? '' : '\n';
          lines.add('$content$suffix');
        case ReflowElementType.paragraph:
          lines.add('$content\n');
        case ReflowElementType.table:
          lines.add('$content\n');
        case ReflowElementType.image:
          lines.add('$content\n');
      }
    }

    if (!titleRendered && documentTitle != null && documentTitle.trim().isNotEmpty) {
      final cleanTitle = escapeMarkdownSpan(documentTitle.replaceAll('_', ' ').trim());
      if (cleanTitle.isNotEmpty) {
        lines.insert(0, '# $cleanTitle\n');
      }
    }

    return lines.join('\n').trim();
  }

  static Future<List<({Rect rect, String markdownImage})>> _extractStandalonePageFigures(
    PdfPage page,
    List<Rect> rawImageRects,
    List<Rect> pageLineRects, {
    required int remainingQuota,
  }) async {
    if (rawImageRects.isEmpty || remainingQuota <= 0) return const [];

    // Filter out background images/templates that have >2 body text lines overlapping their interior
    final candidates = <Rect>[];
    for (final r in rawImageRects) {
      final interior = r.deflate(math.min(12.0, math.min(r.width, r.height) * 0.12));
      int overlappingLines = 0;
      for (final lineRect in pageLineRects) {
        if (interior.overlaps(lineRect)) {
          final inter = interior.intersect(lineRect);
          if (inter.width > 12.0 && inter.height > 4.0) {
            overlappingLines++;
            if (overlappingLines > 2) break;
          }
        }
      }
      if (overlappingLines <= 2) {
        candidates.add(r);
      }
    }
    if (candidates.isEmpty) return const [];

    // Merge overlapping or touching image tiles into composite figure bounds
    final merged = <Rect>[];
    for (final cand in candidates) {
      bool combined = false;
      for (var i = 0; i < merged.length; i++) {
        if (merged[i].inflate(4.0).overlaps(cand)) {
          merged[i] = merged[i].expandToInclude(cand);
          combined = true;
          break;
        }
      }
      if (!combined) {
        merged.add(cand);
      }
    }

    merged.sort((a, b) => a.top.compareTo(b.top));
    final results = <({Rect rect, String markdownImage})>[];

    for (final figRect in merged) {
      if (results.length >= remainingQuota) break;
      final maxDim = math.max(figRect.width, figRect.height);
      final scale = (560.0 / maxDim).clamp(0.75, 1.5);
      final targetW = (figRect.width * scale).round().clamp(32, 720);
      final targetH = (figRect.height * scale).round().clamp(32, 720);
      final fullW = page.width * (targetW / figRect.width);
      final fullH = page.height * (targetH / figRect.height);

      PdfImage? pdfImg;
      try {
        pdfImg = await page.render(
          x: (figRect.left * (targetW / figRect.width)).round(),
          y: (figRect.top * (targetH / figRect.height)).round(),
          width: targetW,
          height: targetH,
          fullWidth: fullW,
          fullHeight: fullH,
          backgroundColor: 0xFFFFFFFF,
        );
        if (pdfImg == null) continue;
        final dataUri = _encodePdfImageToPngDataUri(pdfImg);
        if (dataUri != null) {
          results.add((rect: figRect, markdownImage: '![Figure]($dataUri)'));
        }
      } catch (_) {
        // Ignore individual figure render errors
      } finally {
        pdfImg?.dispose();
      }
    }

    return results;
  }

  static final List<int> _crc32Table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    return c;
  });

  static int _crc32(List<int> typeBytes, List<int> dataBytes) {
    var c = 0xFFFFFFFF;
    for (final b in typeBytes) {
      c = _crc32Table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    for (final b in dataBytes) {
      c = _crc32Table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _writePngChunk(BytesBuilder out, String type, List<int> data) {
    final len = data.length;
    out.add([
      (len >>> 24) & 0xFF,
      (len >>> 16) & 0xFF,
      (len >>> 8) & 0xFF,
      len & 0xFF,
    ]);
    final typeBytes = type.codeUnits;
    out.add(typeBytes);
    out.add(data);
    final crc = _crc32(typeBytes, data);
    out.add([
      (crc >>> 24) & 0xFF,
      (crc >>> 16) & 0xFF,
      (crc >>> 8) & 0xFF,
      crc & 0xFF,
    ]);
  }

  static String? _encodePdfImageToPngDataUri(PdfImage img) {
    final w = img.width;
    final h = img.height;
    final bgra = img.pixels;
    if (w <= 0 || h <= 0 || bgra.length < w * h * 4) return null;

    final rowStride = 1 + w * 3;
    final rawScanlines = Uint8List(h * rowStride);
    var srcIdx = 0;
    var dstIdx = 0;
    for (var y = 0; y < h; y++) {
      rawScanlines[dstIdx++] = 0; // Filter type 0 (None)
      for (var x = 0; x < w; x++) {
        final b = bgra[srcIdx];
        final g = bgra[srcIdx + 1];
        final r = bgra[srcIdx + 2];
        srcIdx += 4;
        rawScanlines[dstIdx++] = r;
        rawScanlines[dstIdx++] = g;
        rawScanlines[dstIdx++] = b;
      }
    }

    final compressed = zlib.encode(rawScanlines);
    final png = BytesBuilder(copy: false);
    png.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    final ihdr = [
      (w >>> 24) & 0xFF,
      (w >>> 16) & 0xFF,
      (w >>> 8) & 0xFF,
      w & 0xFF,
      (h >>> 24) & 0xFF,
      (h >>> 16) & 0xFF,
      (h >>> 8) & 0xFF,
      h & 0xFF,
      8, // bit depth
      2, // color type 2 = Truecolor RGB
      0, // compression
      0, // filter
      0, // interlace
    ];
    _writePngChunk(png, 'IHDR', ihdr);
    _writePngChunk(png, 'IDAT', compressed);
    _writePngChunk(png, 'IEND', const []);

    final b64 = base64Encode(png.toBytes());
    return 'data:image/png;base64,$b64';
  }

  static final RegExp _openingQuoteRegex = RegExp(r'^["“‘\x27]$');
  static final RegExp _singleUpperRegex = RegExp(r'^[A-Z]$');
  static final RegExp _dropCapRegex = RegExp(r'^["“‘\x27]?[A-Z]$');

  /// Detects magazine/book drop caps (spanning 2-3 lines vertically at the start of a paragraph)
  /// and merges them directly into the adjacent first-line word fragment using the first line's height.
  static List<_VisualFragment> _mergeDropCaps(List<_VisualFragment> input) {
    if (input.length < 2) return input;

    final list = List<_VisualFragment>.from(input);
    final consumed = List<bool>.filled(list.length, false);

    // Pass 1: Combine large opening quote (e.g. “) with adjacent drop-cap letter (e.g. S -> “S)
    for (var i = 0; i < list.length; i++) {
      if (consumed[i]) continue;
      final q = list[i];
      if (q.rect.height < 14.5 || !_openingQuoteRegex.hasMatch(q.text)) continue;

      for (var j = 0; j < list.length; j++) {
        if (i == j || consumed[j]) continue;
        final dc = list[j];
        if (dc.rect.height < 17.5 || !_singleUpperRegex.hasMatch(dc.text)) continue;
        final gap = dc.rect.left - q.rect.right;
        if (gap >= -3.0 && gap <= 4.5 && (dc.rect.top - q.rect.top).abs() <= 5.5) {
          list[j] = _VisualFragment(
            rect: q.rect.expandToInclude(dc.rect),
            text: '${q.text}${dc.text}',
            hasTrailingSpace: dc.hasTrailingSpace,
            startsParagraph: true,
            textStart: q.textStart ?? dc.textStart,
            textEnd: dc.textEnd,
          );
          consumed[i] = true;
          break;
        }
      }
    }

    // Pass 2: Merge drop-cap letter into the adjacent first-line word fragment
    for (var i = 0; i < list.length; i++) {
      if (consumed[i]) continue;
      final dc = list[i];
      if (dc.rect.height < 17.5 || !_dropCapRegex.hasMatch(dc.text)) continue;

      int? bestTargetIdx;
      double bestGap = double.infinity;

      for (var j = 0; j < list.length; j++) {
        if (i == j || consumed[j]) continue;
        final cand = list[j];
        if (dc.rect.height < cand.rect.height * 1.45) continue;
        if ((cand.rect.top - dc.rect.top).abs() > 7.5) continue;
        final gap = cand.rect.left - dc.rect.right;
        if (gap >= -9.0 && gap <= 14.0 && gap.abs() < bestGap) {
          bestGap = gap.abs();
          bestTargetIdx = j;
        }
      }

      if (bestTargetIdx != null) {
        final target = list[bestTargetIdx];
        final letter = dc.text.substring(dc.text.length - 1);
        final isPronounI = letter == 'I' &&
            (dc.hasTrailingSpace ||
                RegExp(
                  r'^(?:[hwkyjquaieo]|(?:had|have|has|was|were|went|want|wanted|will|would|can|could|should|shall|may|might|must|did|didn|don|do|does|am|asked|saw|met|knew|know|think|thought|felt|found|heard|hoped|learned|lived|looked|loved|made|mean|meant|need|needed|never|once|often|always|still|also|just|only|even|already|almost|really|said|see|seem|seemed|spoke|started|stayed|stopped|took|told|tried|turned|used|visited|walked|watched|wished|wondered|worked|wrote)\b)',
                  caseSensitive: false,
                ).hasMatch(target.text));
        final isArticleA = letter == 'A' &&
            (dc.hasTrailingSpace ||
                (target.rect.left - dc.rect.right > 2.2 &&
                    target.text.length >= 3 &&
                    !RegExp(
                      r'^(?:fter|bout|mong|round|gainst|lthough|lways|nother|lready|lmost|lso|long|cross|bove|head|way|part|side|live|lone|loud|llow|ppear|pproach|rriv|rtist|lger|meric|ttack|ttempt|ttend|ttract|uthor|vailab)',
                      caseSensitive: false,
                    ).hasMatch(target.text)));
        final joinWithSpace = isPronounI || isArticleA;
        final mergedText = joinWithSpace ? '${dc.text} ${target.text}' : '${dc.text}${target.text}';
        list[bestTargetIdx] = _VisualFragment(
          rect: Rect.fromLTRB(
            math.min(dc.rect.left, target.rect.left),
            target.rect.top,
            target.rect.right,
            target.rect.bottom,
          ),
          text: mergedText,
          hasTrailingSpace: target.hasTrailingSpace,
          startsParagraph: true,
          textStart: dc.textStart ?? target.textStart,
          textEnd: target.textEnd,
          isBold: target.isBold,
          isItalic: target.isItalic,
          linkUrl: target.linkUrl,
        );
        consumed[i] = true;
      }
    }

    return [
      for (var i = 0; i < list.length; i++)
        if (!consumed[i]) list[i],
    ];
  }

  static bool _isBulletChar(int cp) {
    return cp == 0x2022 || // •
        cp == 0x25CF || // ●
        cp == 0x25CB || // ○
        cp == 0x25AA || // ▪
        cp == 0x25C6 || // ◆
        cp == 0x00D8; // Ø
  }

  static List<_VisualFragment> _splitFragmentByStylesAndLinks(
    PdfPage page,
    PdfPageText pageText,
    Rect fragRect,
    int start,
    int end,
    bool fragHasTrailingSpace,
    List<_StyledSpan> pageStyledSpans,
    List<({Rect rect, String url})> pageLinks,
  ) {
    final overSpans = <_StyledSpan>[
      for (final s in pageStyledSpans)
        if (s.rect.inflate(1.5).overlaps(fragRect)) s,
    ];
    final overLinks = <({Rect rect, String url})>[
      for (final l in pageLinks)
        if (l.rect.inflate(1.5).overlaps(fragRect)) l,
    ];

    final n = end - start;
    final wideGapThreshold = math.max(13.0, fragRect.height * 1.25);

    if (overSpans.isEmpty && overLinks.isEmpty) {
      bool hasWideInternalGap = false;
      if (n > 1 && end <= pageText.charRects.length && fragRect.width > 60.0) {
        double? prevRight;
        for (var i = 0; i < n; i++) {
          final cp = pageText.fullText.codeUnitAt(start + i);
          if (cp <= 0x20 || cp == 0xA0) continue;
          final cr = pageText.charRects[start + i].toRect(page: page);
          if (prevRight != null && (cr.left - prevRight) > wideGapThreshold) {
            hasWideInternalGap = true;
            break;
          }
          if (cr.width > 0) prevRight = cr.right;
        }
      }
      if (!hasWideInternalGap) {
        final text = pageText.fullText.substring(start, end).trim();
        if (text.isEmpty) return const [];
        return [
          _VisualFragment(
            rect: fragRect,
            text: text,
            hasTrailingSpace: fragHasTrailingSpace,
            textStart: start,
            textEnd: end,
          ),
        ];
      }
    }

    if (n <= 0 || end > pageText.charRects.length) {
      final text = pageText.fullText.substring(start, end).trim();
      if (text.isEmpty) return const [];
      bool isBold = false;
      bool isItalic = false;
      for (final s in overSpans) {
        final inter = s.rect.intersect(fragRect);
        if (inter.width >= math.min(fragRect.width, s.rect.width) * 0.45 &&
            inter.height >= math.min(fragRect.height, s.rect.height) * 0.35) {
          isBold = isBold || s.isBold;
          isItalic = isItalic || s.isItalic;
        }
      }
      String? linkUrl;
      for (final l in overLinks) {
        final inter = l.rect.intersect(fragRect);
        if (inter.width >= math.min(fragRect.width, l.rect.width) * 0.45 &&
            inter.height >= math.min(fragRect.height, l.rect.height) * 0.35) {
          linkUrl = l.url;
          break;
        }
      }
      return [
        _VisualFragment(
          rect: fragRect,
          text: text,
          hasTrailingSpace: fragHasTrailingSpace,
          textStart: start,
          textEnd: end,
          isBold: isBold,
          isItalic: isItalic,
          linkUrl: linkUrl,
        ),
      ];
    }

    final charBold = List<bool>.filled(n, false);
    final charItalic = List<bool>.filled(n, false);
    final charLink = List<String?>.filled(n, null);
    final charRects = List<Rect>.generate(
      n,
      (i) => pageText.charRects[start + i].toRect(page: page),
    );
    final isSpace = List<bool>.generate(n, (i) {
      final cp = pageText.fullText.codeUnitAt(start + i);
      return cp <= 0x20 || cp == 0xA0;
    });

    for (var i = 0; i < n; i++) {
      if (isSpace[i]) continue;
      final cp = pageText.fullText.codeUnitAt(start + i);
      if (_isBulletChar(cp)) continue;
      final cr = charRects[i];
      final center = cr.center;
      for (final s in overSpans) {
        if (s.rect.inflate(1.2).contains(center)) {
          charBold[i] = charBold[i] || s.isBold;
          charItalic[i] = charItalic[i] || s.isItalic;
        }
      }
      for (final l in overLinks) {
        if (l.rect.inflate(1.8).contains(center)) {
          charLink[i] = l.url;
          break;
        }
      }
    }

    // Keep spaces between two identically styled/linked characters in the same run
    // unless the horizontal gap across the space exceeds wideGapThreshold (column/split gap)
    for (var i = 0; i < n; i++) {
      if (!isSpace[i]) continue;
      int prev = i - 1;
      while (prev >= 0 && isSpace[prev]) {
        prev--;
      }
      int next = i + 1;
      while (next < n && isSpace[next]) {
        next++;
      }
      if (prev >= 0 &&
          next < n &&
          (charRects[next].left - charRects[prev].right) <= wideGapThreshold &&
          charBold[prev] == charBold[next] &&
          charItalic[prev] == charItalic[next] &&
          charLink[prev] == charLink[next]) {
        charBold[i] = charBold[prev];
        charItalic[i] = charItalic[prev];
        charLink[i] = charLink[prev];
      }
    }

    final result = <_VisualFragment>[];
    int idx = 0;
    while (idx < n) {
      while (idx < n && isSpace[idx]) {
        idx++;
      }
      if (idx >= n) break;

      final runStart = idx;
      final rBold = charBold[idx];
      final rItalic = charItalic[idx];
      final rLink = charLink[idx];
      final noSpaceBefore = runStart > 0 &&
          !isSpace[runStart - 1] &&
          (charRects[runStart].left - charRects[runStart - 1].right) <= wideGapThreshold;

      Rect runRect = charRects[idx];
      double lastNonSpaceRight = charRects[idx].right;
      idx++;
      while (idx < n) {
        if (isSpace[idx]) {
          int nextNonSpace = idx + 1;
          while (nextNonSpace < n && isSpace[nextNonSpace]) {
            nextNonSpace++;
          }
          if (nextNonSpace < n &&
              (charRects[nextNonSpace].left - lastNonSpaceRight) > wideGapThreshold) {
            break;
          }
          // Only include space if it was assigned the exact same style/link
          if (charBold[idx] == rBold &&
              charItalic[idx] == rItalic &&
              charLink[idx] == rLink &&
              (rBold || rItalic || rLink != null ||
                  (idx + 1 < n &&
                      !charBold[idx + 1] &&
                      !charItalic[idx + 1] &&
                      charLink[idx + 1] == null))) {
            if (charRects[idx].width > 0 && charRects[idx].height > 0) {
              runRect = runRect.expandToInclude(charRects[idx]);
            }
            idx++;
            continue;
          }
          break;
        }
        if ((charRects[idx].left - lastNonSpaceRight) > wideGapThreshold) {
          break;
        }
        if (charBold[idx] == rBold &&
            charItalic[idx] == rItalic &&
            charLink[idx] == rLink) {
          if (charRects[idx].width > 0 && charRects[idx].height > 0) {
            runRect = runRect.expandToInclude(charRects[idx]);
            lastNonSpaceRight = charRects[idx].right;
          }
          idx++;
        } else {
          break;
        }
      }

      int runEnd = idx;
      bool trailingSpace = false;
      while (runEnd > runStart && isSpace[runEnd - 1]) {
        runEnd--;
        trailingSpace = true;
      }
      if (idx < n && isSpace[idx]) {
        trailingSpace = true;
      } else if (idx == n && fragHasTrailingSpace) {
        trailingSpace = true;
      }

      final subText = pageText.fullText.substring(start + runStart, start + runEnd).trim();
      if (subText.isNotEmpty) {
        final effectiveRect = (runRect.width > 0 &&
                runRect.height > 0 &&
                fragRect.height <= runRect.height * 2.2)
            ? Rect.fromLTRB(runRect.left, fragRect.top, runRect.right, fragRect.bottom)
            : (runRect.width > 0 && runRect.height > 0 ? runRect : fragRect);
        result.add(_VisualFragment(
          rect: effectiveRect,
          text: subText,
          hasTrailingSpace: trailingSpace,
          noSpaceBefore: noSpaceBefore,
          textStart: start + runStart,
          textEnd: start + runEnd,
          isBold: rBold,
          isItalic: rItalic,
          linkUrl: rLink,
        ));
      }
    }

    return result;
  }

  /// Detects 2D structured tables bounded by horizontal rules/bands on a page,
  /// reconstructs them into Markdown GFM tables, and returns remaining non-table fragments.
  static ({
    List<({Rect rect, String markdownTable})> tables,
    List<_VisualFragment> remainingFragments,
  }) _extractPageTables(
    List<_VisualFragment> fragments,
    List<({double y, double left, double right})> horizontalRules, {
    required bool isCjk,
  }) {
    if (fragments.isEmpty || horizontalRules.length < 2) {
      return (tables: const [], remainingFragments: fragments);
    }

    final rawSortedRules = List<({double y, double left, double right})>.from(horizontalRules)
      ..sort((a, b) {
        final dy = (a.y - b.y).abs();
        if (dy <= 2.5) return a.left.compareTo(b.left);
        return a.y.compareTo(b.y);
      });

    // Merge collinear horizontal rule segments on the same Y line (e.g. per-cell borders)
    final sortedRules = <({double y, double left, double right})>[];
    for (final r in rawSortedRules) {
      if (sortedRules.isNotEmpty) {
        final prev = sortedRules.last;
        if ((r.y - prev.y).abs() <= 2.5 && r.left <= prev.right + 14.0) {
          sortedRules[sortedRules.length - 1] = (
            y: (prev.y + r.y) / 2.0,
            left: math.min(prev.left, r.left),
            right: math.max(prev.right, r.right),
          );
          continue;
        }
      }
      sortedRules.add(r);
    }

    final clusters = <({double left, double right, List<double> ys})>[];
    for (final r in sortedRules) {
      final rW = r.right - r.left;
      if (rW < 90.0) continue;
      bool added = false;
      for (var i = 0; i < clusters.length; i++) {
        final c = clusters[i];
        final cW = c.right - c.left;
        final overlap = math.min(c.right, r.right) - math.max(c.left, r.left);
        final maxW = math.max(cW, rW);
        final dy = r.y - c.ys.last;
        if (overlap >= maxW * 0.78 && (cW - rW).abs() <= maxW * 0.22 && dy <= 52.0) {
          if (dy.abs() <= 4.0) {
            c.ys[c.ys.length - 1] = (c.ys.last + r.y) / 2.0;
          } else {
            c.ys.add(r.y);
          }
          clusters[i] = (
            left: math.min(c.left, r.left),
            right: math.max(c.right, r.right),
            ys: c.ys,
          );
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add((left: r.left, right: r.right, ys: [r.y]));
      }
    }

    final consumed = List<bool>.filled(fragments.length, false);
    final extractedTables = <({Rect rect, String markdownTable})>[];

    List<_VisualLine> cellSegsInBand(double left, double right, double yTop, double yBottom) {
      final bandFrags = <_VisualFragment>[];
      for (var i = 0; i < fragments.length; i++) {
        if (consumed[i]) continue;
        final f = fragments[i];
        final c = f.rect.center;
        if (c.dx >= left && c.dx <= right && c.dy >= yTop && c.dy <= yBottom) {
          bandFrags.add(f);
        }
      }
      return _groupFragmentsIntoLines(
        bandFrags,
        enableSplitHeaders: false,
        maxIntraSegmentGapFactor: 1.25,
      );
    }

    for (final c in clusters) {
      if (c.ys.length < 2) continue;
      final ys = List<double>.from(c.ys);
      final tLeft = c.left - 8.0;
      final tRight = c.right + 8.0;

      // Check for unbordered header row immediately above ys.first
      final aboveSegs = cellSegsInBand(tLeft, tRight, ys.first - 26.0, ys.first);
      if (aboveSegs.length >= 2) {
        final minTop = aboveSegs.map((s) => s.bounds.top).reduce(math.min);
        ys.insert(0, minTop - 2.0);
      }

      // Check for unbordered bottom row immediately below ys.last
      final belowSegs = cellSegsInBand(tLeft, tRight, ys.last, ys.last + 26.0);
      if (belowSegs.length >= 2) {
        final maxBottom = belowSegs.map((s) => s.bounds.bottom).reduce(math.max);
        ys.add(maxBottom + 2.0);
      }

      if (ys.length < 3) continue; // Need at least header row + 1 data row

      // Discover column left anchors from the header row [ys[0], ys[1]]
      final headerSegs = cellSegsInBand(tLeft, tRight, ys[0], ys[1])
        ..sort((a, b) => a.bounds.left.compareTo(b.bounds.left));
      final colLefts = <double>[];
      for (final seg in headerSegs) {
        if (colLefts.isEmpty || (seg.bounds.left - colLefts.last) > 16.0) {
          colLefts.add(seg.bounds.left);
        }
      }
      final numCols = colLefts.length;
      if (numCols < 2) continue;

      final tableRows = <List<String>>[];
      int multiCellRowCount = 0;
      bool hasBulletCell = false;

      for (var r = 0; r < ys.length - 1; r++) {
        final yTop = ys[r];
        final yBottom = ys[r + 1];
        final rowFrags = <_VisualFragment>[];
        for (var i = 0; i < fragments.length; i++) {
          if (consumed[i]) continue;
          final f = fragments[i];
          final center = f.rect.center;
          if (center.dx >= tLeft && center.dx <= tRight && center.dy >= yTop && center.dy <= yBottom) {
            rowFrags.add(f);
          }
        }
        if (rowFrags.isEmpty) continue;

        final colBuckets = List<List<_VisualFragment>>.generate(numCols, (_) => []);
        for (final f in rowFrags) {
          int colIdx = 0;
          for (var k = numCols - 1; k >= 0; k--) {
            if (f.rect.left >= colLefts[k] - 10.0) {
              colIdx = k;
              break;
            }
          }
          colBuckets[colIdx].add(f);
        }

        final rowCells = <String>[];
        int nonEmptyCols = 0;
        for (var col = 0; col < numCols; col++) {
          final bucket = colBuckets[col];
          if (bucket.isEmpty) {
            rowCells.add('');
            continue;
          }
          final cellLines = _groupFragmentsIntoLines(
            bucket,
            enableSplitHeaders: false,
            maxIntraSegmentGapFactor: 1.5,
          )..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
          String cellText = '';
          for (final cl in cellLines) {
            final piece = r == 0 ? cl.headingRichText : cl.richText;
            cellText = cellText.isEmpty
                ? piece
                : joinTextFlow(cellText, piece, isCjk: isCjk);
          }
          if (cellText.startsWith('•') || cellText.startsWith('●')) {
            hasBulletCell = true;
          }
          final sanitized = cellText.replaceAll('|', r'\|').trim();
          if (sanitized.isNotEmpty) nonEmptyCols++;
          rowCells.add(sanitized);
        }

        if (nonEmptyCols > 0) {
          if (nonEmptyCols >= 2) multiCellRowCount++;
          tableRows.add(rowCells);
        }
      }

      if (hasBulletCell || tableRows.length < 2 || multiCellRowCount < 2) {
        continue;
      }

      // Mark fragments in this table region as consumed
      final tableBounds = Rect.fromLTRB(tLeft, ys.first, tRight, ys.last);
      for (var i = 0; i < fragments.length; i++) {
        if (tableBounds.contains(fragments[i].rect.center)) {
          consumed[i] = true;
        }
      }

      final mdBuf = StringBuffer();
      mdBuf.writeln('| ${tableRows.first.join(' | ')} |');
      mdBuf.writeln('| ${List.filled(numCols, '---').join(' | ')} |');
      for (var r = 1; r < tableRows.length; r++) {
        mdBuf.writeln('| ${tableRows[r].join(' | ')} |');
      }
      extractedTables.add((
        rect: tableBounds,
        markdownTable: mdBuf.toString().trim(),
      ));
    }

    final remaining = <_VisualFragment>[
      for (var i = 0; i < fragments.length; i++)
        if (!consumed[i]) fragments[i],
    ];
    return (tables: extractedTables, remainingFragments: remaining);
  }

  /// Partitions page fragments into reading-order regions (1-column or uncurled N-column)
  /// and merges horizontally adjacent fragments into visual lines, while extracting 2D tables.
  static ({
    List<({List<_VisualLine> lines, Rect regionBounds, bool isBottomSpanning})> regions,
    List<({Rect rect, String markdownTable})> tables,
  }) _extractOrderedRegionLines(
    PdfPage page,
    PdfPageText pageText,
    PdfPageAnalysis analysis, {
    required bool isCjk,
    List<_StyledSpan> styledSpans = const [],
    List<({Rect rect, String url})> linkRects = const [],
    List<({double y, double left, double right})> horizontalRules = const [],
  }) {
    if (pageText.fragments.isEmpty) {
      return (regions: const [], tables: const []);
    }

    final pageHeight = page.height;
    final headerCutoff = pageHeight * 0.042;
    final runningHeaderSmallFontCutoff = pageHeight * 0.068;
    final footerCutoff = pageHeight * 0.958;

    final rawFragments = <_VisualFragment>[];
    for (final f in pageText.fragments) {
      final rect = f.bounds.toRect(page: page);
      if (!rect.left.isFinite || !rect.top.isFinite || rect.width <= 0 || rect.height <= 0) {
        continue;
      }
      // Strip 90°-rotated vertical side-margin photo credits
      if (PdfPageAnalysisService.isVerticalMarginFragment(page, f, rect)) {
        continue;
      }
      // Strip running headers & footers (except on page 1 top where title may sit near top)
      if ((page.pageNumber > 1 &&
              (rect.bottom < headerCutoff ||
                  (rect.bottom < runningHeaderSmallFontCutoff && rect.height <= 9.2))) ||
          rect.top > footerCutoff) {
        continue;
      }
      final start = f.index.clamp(0, pageText.fullText.length);
      final end = f.end.clamp(start, pageText.fullText.length);
      final rawSub = pageText.fullText.substring(start, end);
      final text = rawSub.trim();
      if (text.isEmpty) continue;
      // Skip decorative full-column single-char ornaments (e.g. 40pt rule glyphs)
      if (rect.height > 28.0 && text.length == 1 && rect.width > 80.0) {
        continue;
      }
      final hasTrailingSpace = rawSub.endsWith(' ') ||
          (end < pageText.fullText.length && pageText.fullText.codeUnitAt(end) == 0x20);
      rawFragments.addAll(_splitFragmentByStylesAndLinks(
        page,
        pageText,
        rect,
        start,
        end,
        hasTrailingSpace,
        styledSpans,
        linkRects,
      ));
    }

    if (rawFragments.isEmpty) {
      return (regions: const [], tables: const []);
    }

    final tableExtraction = _extractPageTables(
      rawFragments,
      horizontalRules,
      isCjk: isCjk,
    );
    final extractedTables = tableExtraction.tables;
    if (tableExtraction.remainingFragments.isEmpty) {
      return (regions: const [], tables: extractedTables);
    }

    final mergedFragments = _mergeDropCaps(tableExtraction.remainingFragments);

    if (extractedTables.isNotEmpty || !analysis.isMultiColumn || analysis.columns.length < 2) {
      final lines = _groupFragmentsIntoLines(mergedFragments);
      return (
        regions: [
          (lines: lines, regionBounds: analysis.contentBounds, isBottomSpanning: false),
        ],
        tables: extractedTables,
      );
    }

    // N-Column layout (2, 3, or 4 columns): compute column gutters and build gutter-aware line segments
    final cols = analysis.columns;
    final gutters = <({double left, double right, double mid})>[];
    double maxColWidth = 0.0;
    for (var i = 0; i < cols.length; i++) {
      if (cols[i].bounds.width > maxColWidth) {
        maxColWidth = cols[i].bounds.width;
      }
      if (i + 1 < cols.length) {
        final left = cols[i].bounds.right;
        final right = cols[i + 1].bounds.left;
        gutters.add((left: left, right: right, mid: (left + right) / 2.0));
      }
    }

    final allLines = _groupFragmentsIntoLines(mergedFragments, gutters: gutters);

    final topSpanning = <_VisualLine>[];
    final colBuckets = List<List<_VisualLine>>.generate(cols.length, (_) => <_VisualLine>[]);
    final bottomSpanning = <_VisualLine>[];

    for (final line in allLines) {
      final r = line.bounds;
      final spansGutter = gutters.any((g) => r.left < g.mid - 14.0 && r.right > g.mid + 14.0);
      final isWide = r.width > maxColWidth * 1.18;
      if (spansGutter || isWide) {
        if (r.top < pageHeight * 0.45) {
          topSpanning.add(line);
        } else {
          bottomSpanning.add(line);
        }
      } else {
        final colIdx = analysis.findBestColumn(r.center).index.clamp(0, cols.length - 1);
        colBuckets[colIdx].add(line);
      }
    }

    final result = <({List<_VisualLine> lines, Rect regionBounds, bool isBottomSpanning})>[];
    if (topSpanning.isNotEmpty) {
      topSpanning.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      result.add((
        lines: topSpanning,
        regionBounds: analysis.contentBounds,
        isBottomSpanning: false,
      ));
    }
    for (var i = 0; i < cols.length; i++) {
      final bucket = colBuckets[i];
      if (bucket.isNotEmpty) {
        bucket.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
        result.add((
          lines: bucket,
          regionBounds: cols[i].bounds,
          isBottomSpanning: false,
        ));
      }
    }
    if (bottomSpanning.isNotEmpty) {
      bottomSpanning.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      result.add((
        lines: bottomSpanning,
        regionBounds: analysis.contentBounds,
        isBottomSpanning: true,
      ));
    }
    return (regions: result, tables: extractedTables);
  }

  static final RegExp _hasWordLettersRegex = RegExp(r'[A-Za-z\u4e00-\u9fa5]');
  static final RegExp _trailingUnstyledCommaRegex = RegExp(r'^(.*?\S)([,;]+)$');

  static String _formatRichRun(
    String rawText, {
    required bool isBold,
    required bool isItalic,
    required String? linkUrl,
  }) {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) return '';

    String core = trimmed;
    String trailingPunct = '';
    if ((isBold || isItalic) && linkUrl == null) {
      final m = _trailingUnstyledCommaRegex.firstMatch(trimmed);
      if (m != null) {
        core = m.group(1)!;
        trailingPunct = escapeMarkdownSpan(m.group(2)!);
      }
    }

    final escaped = escapeMarkdownSpan(core);
    if (escaped.isEmpty) return trailingPunct;

    String styled = escaped;
    if (isBold && isItalic) {
      styled = '***$escaped***';
    } else if (isBold) {
      styled = '**$escaped**';
    } else if (isItalic) {
      styled = '*$escaped*';
    }

    if (linkUrl != null && linkUrl.isNotEmpty) {
      final safeUrl = linkUrl.replaceAll(')', r'\)');
      return '[$styled]($safeUrl)$trailingPunct';
    }
    return '$styled$trailingPunct';
  }

  static String _buildRichLineMarkdown(
    List<_VisualFragment> frags, {
    required bool isHeading,
  }) {
    if (frags.isEmpty) return '';

    final runs = <({
      String text,
      bool isBold,
      bool isItalic,
      String? linkUrl,
      bool spaceBefore,
      bool isSplitSep,
    })>[];

    for (var i = 0; i < frags.length; i++) {
      final f = frags[i];
      if (f.text == '—' && f.noSpaceBefore == false && f.textStart == null) {
        runs.add((
          text: '—',
          isBold: false,
          isItalic: false,
          linkUrl: null,
          spaceBefore: true,
          isSplitSep: true,
        ));
        continue;
      }

      final effBold = isHeading ? false : f.isBold;
      final effItalic = f.isItalic;
      final effLink = f.linkUrl;

      bool needSpace = false;
      if (i > 0) {
        final prev = frags[i - 1];
        final gap = f.rect.left - prev.rect.right;
        needSpace = !f.noSpaceBefore && (prev.hasTrailingSpace || gap > 1.2);
      }

      if (runs.isNotEmpty &&
          !runs.last.isSplitSep &&
          runs.last.isBold == effBold &&
          runs.last.isItalic == effItalic &&
          runs.last.linkUrl == effLink) {
        final prevRun = runs.removeLast();
        final joined = needSpace ? '${prevRun.text} ${f.text}' : '${prevRun.text}${f.text}';
        runs.add((
          text: joined,
          isBold: effBold,
          isItalic: effItalic,
          linkUrl: effLink,
          spaceBefore: prevRun.spaceBefore,
          isSplitSep: false,
        ));
      } else {
        runs.add((
          text: f.text,
          isBold: effBold,
          isItalic: effItalic,
          linkUrl: effLink,
          spaceBefore: needSpace,
          isSplitSep: false,
        ));
      }
    }

    final sb = StringBuffer();
    for (var i = 0; i < runs.length; i++) {
      final r = runs[i];
      if (r.isSplitSep) {
        if (!sb.toString().endsWith(' ')) sb.write(' ');
        sb.write('— ');
        continue;
      }
      if (i > 0 && r.spaceBefore && !sb.toString().endsWith(' ')) {
        sb.write(' ');
      }
      sb.write(_formatRichRun(
        r.text,
        isBold: r.isBold,
        isItalic: r.isItalic,
        linkUrl: r.linkUrl,
      ));
    }
    return sb.toString().trim();
  }

  static List<_VisualLine> _groupFragmentsIntoLines(
    List<_VisualFragment> fragments, {
    List<({double left, double right, double mid})> gutters = const [],
    bool enableSplitHeaders = true,
    double? maxIntraSegmentGapFactor,
  }) {
    if (fragments.isEmpty) return <_VisualLine>[];

    final sorted = List<_VisualFragment>.from(fragments)
      ..sort((a, b) {
        final dy = (a.rect.center.dy - b.rect.center.dy).abs();
        final tol = math.max(2.5, math.min(a.rect.height, b.rect.height) * 0.45);
        if (dy <= tol) {
          return a.rect.left.compareTo(b.rect.left);
        }
        return a.rect.center.dy.compareTo(b.rect.center.dy);
      });

    final lineClusters = <List<_VisualFragment>>[];
    for (final frag in sorted) {
      if (lineClusters.isEmpty) {
        lineClusters.add([frag]);
        continue;
      }
      final currentCluster = lineClusters.last;
      final clusterCenterY = currentCluster.fold<double>(
            0.0,
            (sum, item) => sum + item.rect.center.dy,
          ) /
          currentCluster.length;
      final clusterHeight = currentCluster.fold<double>(
        0.0,
        (maxH, item) => math.max(maxH, item.rect.height),
      );
      final tol = math.max(3.0, math.min(clusterHeight, frag.rect.height) * 0.5);
      if ((frag.rect.center.dy - clusterCenterY).abs() <= tol) {
        currentCluster.add(frag);
      } else {
        lineClusters.add([frag]);
      }
    }

    final lines = <_VisualLine>[];
    for (final cluster in lineClusters) {
      cluster.sort((a, b) => a.rect.left.compareTo(b.rect.left));
      Rect? bounds;
      double maxH = 0.0;
      bool startsPara = false;
      bool isSplitHeader = false;
      int? firstStart;
      int? lastEnd;
      final sb = StringBuffer();
      final segFragments = <_VisualFragment>[];
      double? prevRight;
      bool prevHasTrailingSpace = false;

      void flushSegment() {
        final text = sb.toString().trim();
        if (text.isNotEmpty && bounds != null) {
          int letterFrags = 0;
          int boldFrags = 0;
          int italicFrags = 0;
          for (final f in segFragments) {
            if (_hasWordLettersRegex.hasMatch(f.text)) {
              letterFrags++;
              if (f.isBold) boldFrags++;
              if (f.isItalic) italicFrags++;
            }
          }
          final isAllBold = letterFrags > 0 && boldFrags == letterFrags;
          final isAllItalic = letterFrags > 0 && italicFrags == letterFrags;
          bool startsWithBoldColon = false;
          if (segFragments.isNotEmpty && segFragments.first.isBold && !isAllBold) {
            final firstBoldBuf = StringBuffer();
            for (final f in segFragments) {
              if (f.isBold) {
                if (firstBoldBuf.isNotEmpty) firstBoldBuf.write(' ');
                firstBoldBuf.write(f.text);
              } else {
                if (f.text.startsWith(':')) {
                  firstBoldBuf.write(':');
                }
                break;
              }
            }
            final fb = firstBoldBuf.toString().trim();
            startsWithBoldColon =
                (fb.endsWith(':') || fb.endsWith('：') || fb.contains('：')) && fb.length <= 36;
          }

          lines.add(_VisualLine(
            bounds: bounds!,
            text: text,
            richText: _buildRichLineMarkdown(segFragments, isHeading: false),
            headingRichText: _buildRichLineMarkdown(segFragments, isHeading: true),
            maxHeight: maxH,
            startsParagraph: startsPara,
            isSplitHeaderLine: isSplitHeader,
            isAllBold: isAllBold,
            isAllItalic: isAllItalic,
            startsWithBoldColon: startsWithBoldColon,
            firstTextStart: firstStart,
            lastTextEnd: lastEnd,
          ));
        }
        bounds = null;
        maxH = 0.0;
        startsPara = false;
        isSplitHeader = false;
        firstStart = null;
        lastEnd = null;
        sb.clear();
        segFragments.clear();
        prevRight = null;
        prevHasTrailingSpace = false;
      }

      for (final item in cluster) {
        if (prevRight != null) {
          final gap = item.rect.left - prevRight!;
          final lineH = math.max(maxH, item.rect.height);
          final isWideHorizontalGap = gap > math.max(28.0, lineH * 2.2);
          bool crossesGutterGap = gutters.isNotEmpty && isWideHorizontalGap;
          if (maxIntraSegmentGapFactor != null &&
              gap > math.max(12.0, lineH * maxIntraSegmentGapFactor)) {
            crossesGutterGap = true;
          }
          if (!crossesGutterGap && gutters.isNotEmpty) {
            for (final g in gutters) {
              final gutterWidth = math.max(6.0, g.right - g.left);
              if (prevRight! <= g.mid + 2.5 &&
                  item.rect.left >= g.mid - 2.5 &&
                  gap >= math.max(5.5, math.max(gutterWidth * 0.58, lineH * 0.55))) {
                crossesGutterGap = true;
                break;
              }
            }
          }
          if (crossesGutterGap) {
            flushSegment();
          } else if (enableSplitHeaders &&
              gutters.isEmpty &&
              isWideHorizontalGap &&
              sb.isNotEmpty) {
            // Single-column left-right split line (e.g. Institution/Role on left, Date range on right)
            sb.write(' — ');
            segFragments.add(_VisualFragment(
              rect: Rect.fromLTRB(prevRight!, item.rect.top, item.rect.left, item.rect.bottom),
              text: '—',
              hasTrailingSpace: true,
            ));
            isSplitHeader = true;
            startsPara = true;
            prevRight = item.rect.left;
            prevHasTrailingSpace = false;
          }
        }

        bounds = bounds == null ? item.rect : bounds!.expandToInclude(item.rect);
        if (item.rect.height > maxH) maxH = item.rect.height;
        if (item.startsParagraph) startsPara = true;
        firstStart ??= item.textStart;
        if (item.textEnd != null) lastEnd = item.textEnd;
        if (prevRight != null) {
          final gap = item.rect.left - prevRight!;
          if (!item.noSpaceBefore &&
              (prevHasTrailingSpace || gap > 1.2) &&
              !sb.toString().endsWith(' ')) {
            sb.write(' ');
          }
        }
        sb.write(item.text);
        segFragments.add(item);
        prevRight = item.rect.right;
        prevHasTrailingSpace = item.hasTrailingSpace;
      }

      flushSegment();
    }
    return lines;
  }
}
