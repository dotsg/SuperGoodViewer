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

          final rawImageTiles = <Rect>[];
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
              if (rect.width >= 12.0 && rect.height >= 12.0) {
                rawImageTiles.add(rect);
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

          // Merge touching/overlapping image tiles before filtering by composite figure size
          final mergedTiles = List<Rect>.from(rawImageTiles);
          bool mergedAny = true;
          while (mergedAny && mergedTiles.length > 1) {
            mergedAny = false;
            for (var i = 0; i < mergedTiles.length; i++) {
              for (var j = i + 1; j < mergedTiles.length; j++) {
                if (mergedTiles[i].inflate(1.0).overlaps(mergedTiles[j])) {
                  mergedTiles[i] = mergedTiles[i].expandToInclude(mergedTiles[j]);
                  mergedTiles.removeAt(j);
                  mergedAny = true;
                  break;
                }
              }
              if (mergedAny) break;
            }
          }

          final imageRects = <Rect>[];
          for (final rect in mergedTiles) {
            if (rect.width >= 34.0 &&
                rect.height >= 34.0 &&
                rect.width * rect.height >= 1350.0) {
              final aspect = rect.width / rect.height;
              if (aspect >= 0.14 && aspect <= 7.5) {
                imageRects.add(rect);
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
  final bool endsParagraph;
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
    this.endsParagraph = false,
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
  final bool endsParagraph;
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
    this.endsParagraph = false,
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

  static final RegExp _softHyphenSuffixRegex = RegExp(r'\u00AD(\*{1,3})?$');
  static final RegExp _leadingWrapPunctOrStarsRegex = RegExp(r'^(?:\*{1,3}|["“‘(\[\{])+');
  static final RegExp _trailingStarsRegex = RegExp(r'\*{1,3}$');
  static final RegExp _leadingStarsRegex = RegExp(r'^\*{1,3}');
  static final RegExp _trailingWordPunctOrStarsRegex =
      RegExp(r"(?:['’]s)?\*{0,3}[.,;:!?”’'\)\]\}]*$");
  static final RegExp _alphaOrHyphenBeforeRegex = RegExp(r'^[a-zA-Z]+(?:[-/][a-zA-Z]+)*$');
  static final RegExp _alphaAfterRegex = RegExp(r'^[a-zA-Z]+(?:-[a-zA-Z]+)*$');

  static const Set<String> _compoundConnectors = {
    'of',
    'to',
    'in',
    'on',
    'at',
    'by',
    'for',
    'and',
    'or',
    'a',
    'the',
    'up',
    'out',
    'off',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
    'hundred',
    'thousand',
    'million',
    'billion',
  };

  static const Set<String> _capitalizedCompoundPrefixes = {
    'un',
    'non',
    'pre',
    'post',
    'anti',
    'pro',
    'sub',
    'inter',
    'intra',
    'trans',
    'pan',
    'neo',
    'mid',
    'ex',
    'self',
    'all',
    'half',
    'quasi',
    'ultra',
    'super',
    'hyper',
    'meta',
    'pseudo',
    'counter',
    'co',
    're',
    'de',
    'multi',
    'cross',
    'bi',
    'tri',
    'vice',
    'arch',
    'mini',
    'macro',
    'micro',
    'auto',
    'out',
    'over',
    'under',
    'up',
    'down',
    'ill',
    'well',
    'high',
    'low',
    'full',
    'part',
    'single',
    'double',
    'triple',
    'first',
    'second',
    'third',
  };

  static const Set<String> _numberCompoundPrefixes = {
    'zero',
    'one',
    'two',
    'three',
    'four',
    'five',
    'six',
    'seven',
    'eight',
    'nine',
    'ten',
    'eleven',
    'twelve',
    'thirteen',
    'fourteen',
    'fifteen',
    'sixteen',
    'seventeen',
    'eighteen',
    'nineteen',
    'twenty',
    'thirty',
    'forty',
    'fifty',
    'sixty',
    'seventy',
    'eighty',
    'ninety',
    'hundred',
    'thousand',
    'million',
    'billion',
    'first',
    'second',
    'third',
    'fourth',
    'fifth',
    'sixth',
    'seventh',
    'eighth',
    'ninth',
    'tenth',
    'single',
    'double',
    'triple',
    'half',
    'quarter',
  };

  static const List<String> _nonBoundSuffixes = [
    'sense',
    'sensic',
    'chalant',
    'conform',
    'entity',
    'ethe',
    'pareil',
    'plussed',
    'agenarian',
    'agon',
    'illion',
  ];

  static const List<String> _multiBoundSuffixes = [
    'plicat',
    'plici',
    'ply',
    'plie',
    'plier',
    'ple',
    'plex',
    'tude',
    'tud',
    'lateral',
    'fari',
    'form',
    'valen',
    'nomial',
    'verse',
    'vitamin',
  ];

  static const List<String> _highBoundSuffixes = [
    'way',
    'light',
    'land',
    'ly',
    'er',
    'est',
    'ness',
    'brow',
    'jack',
    'born',
    'chair',
    'falutin',
  ];

  static const List<String> _lowBoundSuffixes = [
    'er',
    'est',
    'ly',
    'ness',
    'land',
    'brow',
    'down',
    'boy',
    'life',
  ];

  static const List<String> _numberBoundSuffixes = [
    'th',
    'ths',
    'tieth',
    'teen',
    'teens',
    'teenth',
    'fold',
    'ly',
    'some',
    'ence',
    'ness',
    'time',
    'times',
    'self',
    'selves',
    'another',
  ];

  static const Map<String, Set<String>> _prefixSecondWordAllowlist = {
    'pre': {
      'trained',
      'training',
      'train',
      'trains',
      'existing',
      'war',
      'modern',
      'trial',
      'school',
      'med',
      'law',
      'date',
      'dates',
      'dated',
      'dating',
      'approved',
      'order',
      'paid',
      'packaged',
      'processing',
      'processed',
      'process',
      'defined',
      'determined',
      'computed',
      'configured',
      'populated',
      'built',
      'eminent',
      'empt',
      'emptive',
      'emptively',
      'activation',
    },
    'post': {
      'war',
      'modern',
      'hoc',
      'mortem',
      'doctoral',
      'doc',
      'graduate',
      'operative',
      'production',
      'processing',
      'processed',
      'process',
      'training',
      'trained',
      'script',
      'apocalyptic',
      'colonial',
      'industrial',
      'pandemic',
      'truth',
      'facto',
      'game',
      'season',
      'election',
      'impressionism',
      'impressionist',
      'structuralism',
      'structuralist',
      'partum',
    },
    'co': {
      'author',
      'authors',
      'authored',
      'authoring',
      'founder',
      'founders',
      'founded',
      'worker',
      'workers',
      'pilot',
      'star',
      'stars',
      'starred',
      'host',
      'hosts',
      'hosted',
      'chair',
      'chairs',
      'owner',
      'owners',
      'owned',
      'exist',
      'exists',
      'existed',
      'existence',
      'occurring',
      'occurrence',
      'occur',
      'operating',
      'operation',
      'operative',
      'opt',
      'opted',
      'ordinate',
      'ordinates',
      'pay',
      'produce',
      'produced',
      'producer',
      'sign',
      'signed',
      'signer',
      'sponsor',
      'sponsored',
      'write',
      'writer',
      'written',
      'wrote',
      'adapted',
      'adaptation',
      'training',
      'trained',
      'design',
      'designed',
      'created',
      'creation',
      'creator',
      'ed',
    },
    'semi': {
      'supervised',
      'autonomous',
      'automatic',
      'annual',
      'annually',
      'final',
      'finals',
      'finalist',
      'circle',
      'circular',
      'colon',
      'conductor',
      'conductors',
      'conducting',
      'detached',
      'formal',
      'official',
      'permanent',
      'private',
      'professional',
      'pro',
      'public',
      'retired',
      'skilled',
      'solid',
      'sweet',
      'transparent',
      'trailer',
      'truck',
      'arid',
      'tropical',
      'conscious',
      'literate',
      'monthly',
      'weekly',
    },
    'sub': {
      'layer',
      'layers',
      'network',
      'networks',
      'net',
      'nets',
      'pixel',
      'pixels',
      'word',
      'words',
      'graph',
      'graphs',
      'tree',
      'trees',
      'problem',
      'problems',
      'task',
      'tasks',
      'module',
      'modules',
      'system',
      'systems',
      'region',
      'regions',
      'block',
      'blocks',
      'band',
      'bands',
      'group',
      'groups',
      'category',
      'categories',
      'class',
      'classes',
      'type',
      'types',
      'set',
      'sets',
      'space',
      'spaces',
      'field',
      'fields',
      'topic',
      'topics',
      'section',
      'sections',
      'heading',
      'headings',
      'title',
      'titles',
      'plot',
      'plots',
      'routine',
      'routines',
      'process',
      'processes',
      'domain',
      'domains',
      'optimal',
      'linear',
      'quadratic',
      'gaussian',
      'exponential',
      'millimeter',
      'micron',
      'wavelength',
      'atomic',
      'zero',
      'prime',
      'par',
      'standard',
      'contractor',
      'let',
      'lease',
      'committee',
      'culture',
      'genre',
      'human',
      'acute',
      'clinical',
      'threshold',
      'sampling',
      'sampled',
      'sample',
    },
    'inter': {
      'layer',
      'frame',
      'class',
      'channel',
      'node',
      'cluster',
      'sentence',
      'word',
      'token',
      'pixel',
      'subject',
      'speaker',
      'annotator',
      'rater',
      'observer',
      'agency',
      'departmental',
      'institutional',
      'disciplinary',
      'generational',
      'marriage',
      'racial',
      'ethnic',
      'faith',
      'collegiate',
      'scholastic',
      'varsity',
      'city',
      'state',
      'continental',
      'galactic',
      'planetary',
      'stellar',
      'island',
      'tribal',
      'clan',
      'party',
      'personal',
    },
    'intra': {
      'layer',
      'frame',
      'class',
      'channel',
      'node',
      'cluster',
      'sentence',
      'word',
      'token',
      'pixel',
      'subject',
      'cellular',
      'venous',
      'mural',
      'state',
      'day',
      'net',
      'party',
      'group',
      'team',
      'company',
      'department',
      'industry',
    },
    'per': {
      'class',
      'pixel',
      'layer',
      'channel',
      'frame',
      'sample',
      'image',
      'instance',
      'object',
      'person',
      'capita',
      'day',
      'week',
      'month',
      'year',
      'hour',
      'second',
      'unit',
      'user',
      'page',
      'word',
      'token',
      'sentence',
      'document',
      'item',
      'row',
      'column',
      'cell',
      'node',
      'edge',
      'task',
      'group',
      'category',
      'cent',
    },
    'well': {
      'known',
      'suited',
      'defined',
      'established',
      'founded',
      'grounded',
      'behaved',
      'formed',
      'posed',
      'conditioned',
      'balanced',
      'structured',
      'organized',
      'designed',
      'engineered',
      'crafted',
      'written',
      'read',
      'spoken',
      'educated',
      'informed',
      'versed',
      'trained',
      'prepared',
      'equipped',
      'funded',
      'paid',
      'heeled',
      'off',
      'being',
      'wisher',
      'wishers',
      'meaning',
      'intentioned',
      'intended',
      'deserved',
      'earned',
      'merited',
      'received',
      'regarded',
      'respected',
      'liked',
      'loved',
      'preserved',
      'maintained',
      'kept',
      'dressed',
      'groomed',
      'fed',
      'lit',
      'ventilated',
      'timed',
      'placed',
      'chosen',
      'matched',
      'adjusted',
      'rounded',
      'developed',
      'documented',
      'tested',
      'understood',
      'worn',
      'used',
      'traveled',
      'built',
      'made',
      'done',
      'nigh',
    },
    'fine': {
      'tune',
      'tuned',
      'tuning',
      'tunes',
      'grained',
      'scale',
      'tooth',
      'toothed',
      'spun',
      'drawn',
    },
    'real': {
      'time',
      'world',
      'life',
      'estate',
      'valued',
    },
    'cross': {
      'entropy',
      'validation',
      'validated',
      'lingual',
      'modal',
      'domain',
      'dataset',
      'task',
      'corpus',
      'cultural',
      'national',
      'sectional',
      'section',
      'stitch',
      'reference',
      'referenced',
      'referencing',
      'check',
      'checked',
      'checking',
      'examine',
      'examined',
      'examination',
      'examiner',
      'pollination',
      'pollinate',
      'breed',
      'breeding',
      'bred',
      'country',
      'cutting',
      'disciplinary',
      'dressing',
      'eyed',
      'fertilization',
      'fire',
      'functional',
      'grained',
      'hairs',
      'hatch',
      'hatching',
      'legged',
      'link',
      'linked',
      'linking',
      'party',
      'platform',
      'posting',
      'purpose',
      'questioning',
      'reactive',
      'reactivity',
      'talk',
      'train',
      'training',
      'wind',
      'winds',
      'wise',
      'walk',
    },
    'mid': {
      'level',
      'range',
      'size',
      'sized',
      'term',
      'point',
      'way',
      'air',
      'career',
      'century',
      'day',
      'life',
      'night',
      'morning',
      'afternoon',
      'evening',
      'week',
      'month',
      'year',
      'season',
      'summer',
      'winter',
      'spring',
      'autumn',
      'fall',
      'flight',
      'sentence',
      'stride',
      'stream',
      'section',
      'west',
      'western',
      'atlantic',
      'east',
      'eastern',
      'town',
      'field',
      'fielder',
      'nineties',
      'eighties',
      'seventies',
      'sixties',
      'fifties',
      'forties',
      'thirties',
      'twenties',
    },
    'end': {
      'user',
      'users',
      'point',
      'points',
      'game',
      'zone',
      'result',
      'results',
      'product',
      'products',
      'stage',
      'state',
      'stop',
      'plate',
      'cap',
      'note',
      'notes',
      'paper',
      'papers',
      'piece',
      'table',
      'tables',
      'run',
    },
    'state': {
      'owned',
      'sponsored',
      'run',
      'sanctioned',
      'backed',
      'controlled',
      'mandated',
      'funded',
      'level',
      'wide',
      'side',
      'room',
      'craft',
      'house',
      'line',
    },
  };

  static bool _isCompoundPrefixPair(String lowerBefore, String lowerAfter) {
    if (lowerBefore == 'self') {
      return !lowerAfter.startsWith('ish') &&
          !lowerAfter.startsWith('less') &&
          lowerAfter != 'same';
    }
    if (lowerBefore == 'non') {
      return !_nonBoundSuffixes.any(lowerAfter.startsWith);
    }
    if (lowerBefore == 'multi') {
      return !_multiBoundSuffixes.any(lowerAfter.startsWith);
    }
    if (lowerBefore == 'high') {
      return !_highBoundSuffixes.any(lowerAfter.startsWith);
    }
    if (lowerBefore == 'low') {
      return !_lowBoundSuffixes.any(lowerAfter.startsWith);
    }
    if (_numberCompoundPrefixes.contains(lowerBefore)) {
      return !_numberBoundSuffixes.any(lowerAfter.startsWith);
    }
    final allowed = _prefixSecondWordAllowlist[lowerBefore];
    if (allowed != null) {
      return allowed.contains(lowerAfter);
    }
    return false;
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

    // Detect and strip trailing soft hyphen (\u00AD) BEFORE unwrapping boundary emphasis
    // markers so "*as learn*\u00AD" + "*ing residual*" cleanly unwraps to "*as learning residual*".
    bool hasSoftHyphenChar = false;
    final softHyphenSuffixMatch = _softHyphenSuffixRegex.firstMatch(a);
    if (softHyphenSuffixMatch != null) {
      hasSoftHyphenChar = true;
      final stars = softHyphenSuffixMatch.group(1) ?? '';
      a = '${a.substring(0, softHyphenSuffixMatch.start)}$stars';
    }

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

    // Check again in case \u00AD was originally inside the unwrapped emphasis marker (e.g. "*learn\u00AD*")
    final innerSoftMatch = _softHyphenSuffixRegex.firstMatch(a);
    if (innerSoftMatch != null) {
      hasSoftHyphenChar = true;
      final stars = innerSoftMatch.group(1) ?? '';
      a = '${a.substring(0, innerSoftMatch.start)}$stars';
    }

    // Unwrap English line-break hyphenation (e.g. "dimen-" + "sion" -> "dimension",
    // or PDFium soft hyphen wrap where two line segments are adjacent in fullText)
    final hasLiteralHyphen = a.endsWith('-');
    final hasExplicitHyphen = hasLiteralHyphen || hasSoftHyphenChar;
    if (hasExplicitHyphen || softHyphenWrap) {
      final prefix = hasLiteralHyphen ? a.substring(0, a.length - 1) : a;
      final lastSpace = prefix.lastIndexOf(' ');
      final rawWordBefore = lastSpace == -1 ? prefix : prefix.substring(lastSpace + 1);
      final wordBefore = rawWordBefore
          .replaceFirst(_leadingWrapPunctOrStarsRegex, '')
          .replaceFirst(_trailingStarsRegex, '');
      final firstSpace = b.indexOf(' ');
      final rawWordAfter = firstSpace == -1 ? b : b.substring(0, firstSpace);
      final wordAfter = rawWordAfter
          .replaceFirst(_leadingStarsRegex, '')
          .replaceFirst(_trailingWordPunctOrStarsRegex, '');
      if (_alphaOrHyphenBeforeRegex.hasMatch(wordBefore) && _alphaAfterRegex.hasMatch(wordAfter)) {
        final lastSegBefore = wordBefore.split('/').last;
        final lowerBefore = lastSegBefore.toLowerCase();
        final lowerAfter = wordAfter.toLowerCase();
        final isMultiHyphenCompound = wordAfter.contains('-') ||
            (lastSegBefore.contains('-') &&
                _compoundConnectors.contains(lowerBefore.split('-').last));
        final afterStartsUpper = wordAfter.isNotEmpty &&
            wordAfter[0] == wordAfter[0].toUpperCase() &&
            wordAfter[0] != wordAfter[0].toLowerCase();
        if (afterStartsUpper) {
          final keepCapitalizedHyphen = hasLiteralHyphen ||
              lastSegBefore.length == 1 ||
              (lastSegBefore[0] == lastSegBefore[0].toUpperCase() &&
                  lastSegBefore[0] != lastSegBefore[0].toLowerCase()) ||
              _capitalizedCompoundPrefixes.contains(lowerBefore);
          return keepCapitalizedHyphen ? '$prefix-$b' : '$prefix $b';
        }
        if (isMultiHyphenCompound || _isCompoundPrefixPair(lowerBefore, lowerAfter)) {
          return '$prefix-$b';
        }
        return '$prefix$b';
      }
      if (hasExplicitHyphen) {
        return '$prefix-$b';
      }
    }

    final aVisible = a.replaceFirst(_trailingStarsRegex, '');
    final bVisible = b.replaceFirst(_leadingStarsRegex, '');
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

  static final RegExp _brokenFlLigatureRegex = RegExp(
    r'\bf\s+(?=(?:light|lights|lew|lying|lown|loor|lag|lame|lash|leet|lesh|loat|lock|lood|luid|lush)\b)',
  );
  static final RegExp _brokenFiLigatureRegex = RegExp(
    r'\bfi\s+(?=rst\b)',
  );
  static final RegExp _controlAndPuaRegex =
      RegExp(r'[\x01\x03-\x08\x0B\x0C\x0E-\x1F\uE000-\uF8FF]');
  static final RegExp _strayLeadingOneDropCapRegex =
      RegExp(r'(?:^|(?<=\s))1(?=[A-Z][a-zA-Z]{2,})');
  static final RegExp _multiWhitespaceRegex = RegExp(r'\s+');

  /// Escapes characters in raw PDF text that could be misinterpreted as broken
  /// Markdown or LaTeX math syntax while preserving readable prose.
  static String escapeMarkdownSpan(String input) {
    final cleaned = input
        .replaceAll('\x00', '')
        .replaceAll('\x02', '')
        .replaceAll(_controlAndPuaRegex, '')
        .replaceAll(_strayLeadingOneDropCapRegex, '')
        .replaceAll(_brokenFlLigatureRegex, 'f')
        .replaceAll(_brokenFiLigatureRegex, 'fi')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(_multiWhitespaceRegex, ' ')
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
    final trimmed = text
        .replaceAll('\u00AD', '')
        .trimRight()
        .replaceFirst(_trailingCloseQuoteOrBracket, '');
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
    final trimmed = text
        .replaceAll('\u00AD', '')
        .trimRight()
        .replaceFirst(_trailingCloseQuoteOrBracket, '');
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

    // Extract standalone embedded figures (up to 600 per document, 16 per page, and 60MB total base64 budget)
    const maxDocumentFigures = 600;
    const maxFiguresPerPage = 16;
    const maxDocumentFigureChars = 60000000;
    final pageFiguresList = List<List<({Rect rect, String markdownImage})>>.generate(
      doc.pages.length,
      (_) => [],
    );
    int extractedFigureCount = 0;
    int extractedFigureChars = 0;
    for (var pno = 0;
        pno < doc.pages.length &&
            extractedFigureCount < maxDocumentFigures &&
            extractedFigureChars < maxDocumentFigureChars;
        pno++) {
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
        remainingQuota: math.min(maxFiguresPerPage, maxDocumentFigures - extractedFigureCount),
      );
      final keptFigures = <({Rect rect, String markdownImage})>[];
      for (final fig in figures) {
        if (extractedFigureCount > 0 &&
            extractedFigureChars + fig.markdownImage.length > maxDocumentFigureChars) {
          break;
        }
        keptFigures.add(fig);
        extractedFigureCount++;
        extractedFigureChars += fig.markdownImage.length;
      }
      pageFiguresList[pno] = keptFigures;
    }

    final elements = <ReflowElement>[];
    final deferredElements = <ReflowElement>[];
    ReflowElement? curBullet;
    ReflowElement? curParagraph;
    bool curParagraphForceFlushNext = false;
    bool deferFlushedBlocks = false;

    void flushBlock() {
      final targetList = deferFlushedBlocks ? deferredElements : elements;
      if (curBullet != null) {
        curBullet!.text = curBullet!.text.replaceAll('\u00AD', '');
        curBullet!.richText = curBullet!.richText.replaceAll('\u00AD', '');
        targetList.add(curBullet!);
        curBullet = null;
      }
      if (curParagraph != null) {
        curParagraph!.text = curParagraph!.text.replaceAll('\u00AD', '');
        curParagraph!.richText = curParagraph!.richText.replaceAll('\u00AD', '');
        targetList.add(curParagraph!);
        curParagraph = null;
      }
      if (!deferFlushedBlocks && deferredElements.isNotEmpty) {
        for (final d in deferredElements) {
          d.text = d.text.replaceAll('\u00AD', '');
          d.richText = d.richText.replaceAll('\u00AD', '');
          elements.add(d);
        }
        deferredElements.clear();
      }
      curParagraphForceFlushNext = false;
    }

    final bulletRegex = _bulletLineRegex;
    final orderedItemRegex = _orderedItemLineRegex;
    final circledHeadingRegex = _circledHeadingRegex;
    final h1SectionRegex = _h1SectionRegex;
    final h2SectionRegex = _h2SectionRegex;
    final allCapsHeadingRegex = _allCapsHeadingRegex;
    final lowercaseStartRegex = _lowercaseStartRegex;
    final openingQuoteRegex = _openingQuoteStartRegex;
    final quotedLineRegex = _quotedLineRegex;

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
      String firstPageLineText = '';
      for (final r in regions) {
        for (final l in r.lines) {
          final vt = l.text.replaceAll('\u00AD', '').trim();
          if (vt.isNotEmpty) {
            firstPageLineText = vt;
            break;
          }
        }
        if (firstPageLineText.isNotEmpty) break;
      }
      final isSingleColInterruptionPage = totalPageLines > 0 &&
          totalPageLines <= 12 &&
          !analysis.isMultiColumn &&
          pno > 0 &&
          pno + 1 < doc.pages.length &&
          !lowercaseStartRegex.hasMatch(firstPageLineText) &&
          (pageAnalyses[pno - 1].isMultiColumn || pageAnalyses[pno + 1].isMultiColumn);

      void emitDueBlocks(double upToY, {int? curRegionIdx}) {
        bool isBlockDueInRegion(Rect rect) {
          if (rect.top > upToY) return false;
          if (curRegionIdx == null || !analysis.isMultiColumn) return true;
          final curRegion = regions[curRegionIdx];
          if (curRegion.isBottomSpanning) return true;

          if (rect.left >= curRegion.regionBounds.right - 8.0) {
            final overlapsRightCol = regions.skip(curRegionIdx + 1).any(
                  (nr) =>
                      !nr.isBottomSpanning &&
                      rect.right > nr.regionBounds.left + 8.0 &&
                      rect.left < nr.regionBounds.right - 8.0,
                );
            if (overlapsRightCol) return false;
          }

          final hasLaterColAbove = regions.skip(curRegionIdx + 1).any(
                (nr) =>
                    !nr.isBottomSpanning &&
                    rect.right > nr.regionBounds.left + 12.0 &&
                    rect.left < nr.regionBounds.right - 12.0 &&
                    nr.regionBounds.top < rect.top - 8.0,
              );
          if (hasLaterColAbove) return false;

          return true;
        }

        final targetList = deferFlushedBlocks ? deferredElements : elements;
        while (true) {
          final figIdx = pendingFigures.indexWhere((f) => isBlockDueInRegion(f.rect));
          final tabIdx = pendingTables.indexWhere((t) => isBlockDueInRegion(t.rect));
          final hasFig = figIdx != -1;
          final hasTab = tabIdx != -1;
          if (!hasFig && !hasTab) break;
          if (hasTab && (!hasFig || pendingTables[tabIdx].rect.top <= pendingFigures[figIdx].rect.top)) {
            final tab = pendingTables.removeAt(tabIdx);
            targetList.add(ReflowElement(
              type: ReflowElementType.table,
              text: tab.markdownTable,
              richText: tab.markdownTable,
              pageNumber: pno + 1,
            ));
          } else {
            final fig = pendingFigures.removeAt(figIdx);
            targetList.add(ReflowElement(
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

      for (var rIdx = 0; rIdx < regions.length; rIdx++) {
        final region = regions[rIdx];
        final lines = region.lines;
        if (lines.isEmpty) continue;

        // If this region is a bottom figure caption, an inset box, a full-page photo caption,
        // or a short 1-column interruption page between multi-column pages, and the previous
        // column ended mid-sentence, hold curParagraph across the interruption so cross-page
        // sentences continue seamlessly onto the next multi-column body region.
        final holdCrossPageSentence =
            (region.isBottomSpanning || isFullPageCaptionOnly || isSingleColInterruptionPage) &&
                curParagraph != null &&
                !_endsWithParagraphPunctuation(curParagraph!.text);
        ReflowElement? savedParagraph;
        if (holdCrossPageSentence) {
          savedParagraph = curParagraph;
          curParagraph = null;
          deferFlushedBlocks = true;
          emitDueBlocks(region.regionBounds.top + 12.0, curRegionIdx: rIdx);
        } else if (region.isBottomSpanning || (curParagraph == null && curBullet == null)) {
          flushBlock();
          emitDueBlocks(region.regionBounds.top + 12.0, curRegionIdx: rIdx);
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
          final visibleLineText = lineText.replaceAll('\u00AD', '');
          if (visibleLineText.isEmpty) continue;

          // If a table starts above this line, flush any open block and emit the table first
          if (pendingTables.isNotEmpty && pendingTables.first.rect.top <= line.bounds.top) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
          }

          // Skip isolated page numbers (in top 8% / bottom 10% margin or multi-line regions)
          // and single-digit section ornaments
          final isNearPageMargin =
              line.bounds.top >= page.height * 0.90 || line.bounds.bottom <= page.height * 0.08;
          if (_pageNumberOnlyRegex.hasMatch(visibleLineText) &&
              (lines.length > 2 || isNearPageMargin)) {
            if (curParagraph != null && _endsWithParagraphPunctuation(curParagraph!.text)) {
              flushBlock();
              emitDueBlocks(line.bounds.bottom, curRegionIdx: rIdx);
            }
            continue;
          }

          final maxSize = line.maxHeight;
          final verticalGap = prevLineBottom != null ? (line.bounds.top - prevLineBottom) : 0.0;
          final isLargeVerticalGap = prevLineBottom != null && verticalGap > bodyHeight * 0.85;

          // If curParagraph is mid-sentence (or mid-hyphenated-word) and we encounter a
          // standalone italic cartoon quote or vertically separated italic photo caption inside
          // a multi-column body column, defer the caption until curParagraph finishes!
          if (analysis.isMultiColumn &&
              !region.isBottomSpanning &&
              curParagraph != null &&
              !curParagraphForceFlushNext &&
              !_endsWithParagraphPunctuation(curParagraph!.text) &&
              line.isAllItalic &&
              _quoteOrUpperStartRegex.hasMatch(visibleLineText)) {
            int capEnd = i;
            String capText = lineText;
            String capRich = line.richText;
            while (capEnd + 1 < lines.length &&
                lines[capEnd + 1].isAllItalic &&
                (lines[capEnd + 1].bounds.top - lines[capEnd].bounds.bottom) <= bodyHeight * 0.85) {
              capEnd++;
              capText = joinTextFlow(capText, lines[capEnd].text.trim(), isCjk: isCjk);
              capRich = joinTextFlow(capRich, lines[capEnd].richText, isCjk: isCjk);
            }
            final nextGap = (capEnd + 1 < lines.length)
                ? (lines[capEnd + 1].bounds.top - lines[capEnd].bounds.bottom)
                : double.infinity;
            final isQuotedCartoonCaption =
                quotedLineRegex.hasMatch(capText.replaceAll('\u00AD', '')) &&
                    (isLargeVerticalGap ||
                        i == 0 ||
                        capEnd == lines.length - 1 ||
                        nextGap > bodyHeight * 0.45);
            final isSeparatedItalicCaption = _endsWithParagraphPunctuation(capText) &&
                ((isLargeVerticalGap && nextGap > bodyHeight * 0.45) ||
                    (i == 0 && nextGap > bodyHeight * 0.85) ||
                    (capEnd == lines.length - 1 && isLargeVerticalGap));
            if (isQuotedCartoonCaption || isSeparatedItalicCaption) {
              final prevDefer = deferFlushedBlocks;
              deferFlushedBlocks = true;
              emitDueBlocks(line.bounds.top + 12.0, curRegionIdx: rIdx);
              deferFlushedBlocks = prevDefer;
              deferredElements.add(ReflowElement(
                type: ReflowElementType.paragraph,
                text: capText.replaceAll('\u00AD', ''),
                richText: capRich.replaceAll('\u00AD', ''),
                pageNumber: pno + 1,
              ));
              i = capEnd;
              continue;
            }
          }

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

          final canBeHeading = !lowercaseStartRegex.hasMatch(visibleLineText) &&
              !(line.isAllItalic && openingQuoteRegex.hasMatch(visibleLineText)) &&
              !(curParagraph != null &&
                  (curParagraph!.text.endsWith('-') || curParagraph!.text.endsWith('\u00AD')));

          // 1. Document Title detection on page 1
          if (pno == 0 &&
              canBeHeading &&
              maxSize >= math.min(titleSize * 0.94, bodyHeight * 1.42) &&
              visibleLineText.length < 140) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
            if (elements.isNotEmpty &&
                elements.last.type == ReflowElementType.title &&
                elements.last.pageNumber == 1) {
              elements.last.text = joinTextFlow(elements.last.text, visibleLineText, isCjk: isCjk);
              elements.last.richText = joinTextFlow(
                elements.last.richText,
                line.headingRichText.replaceAll('\u00AD', ''),
                isCjk: isCjk,
              );
            } else {
              elements.add(ReflowElement(
                type: ReflowElementType.title,
                text: visibleLineText,
                richText: line.headingRichText.replaceAll('\u00AD', ''),
                pageNumber: pno + 1,
              ));
            }
            continue;
          }

          final endsWithSentencePunct = _endsWithSentenceClausePunctuation(visibleLineText);

          // 2. Heading 1 detection
          // Note: All-caps lines have no lowercase descenders (g, j, p, q, y), so their glyph
          // cap-height box is ~72% of a mixed-case line's ascender+descender box at the same point size.
          final isAllCapsSection = line.isAllBold &&
              maxSize >= bodyHeight * 0.82 &&
              visibleLineText.length >= 4 &&
              allCapsHeadingRegex.hasMatch(visibleLineText);
          final h1HeightThreshold = math.max(
            bodyHeight * 1.24,
            math.min(h1Size * 0.94, bodyHeight * 1.32),
          );
          if (canBeHeading &&
              !endsWithSentencePunct &&
              visibleLineText.length < 90 &&
              (maxSize >= h1HeightThreshold ||
                  isAllCapsSection ||
                  (maxSize >= bodyHeight * 1.08 && h1SectionRegex.hasMatch(visibleLineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
            final targetList = deferFlushedBlocks ? deferredElements : elements;
            if (targetList.isNotEmpty &&
                targetList.last.type == ReflowElementType.h1 &&
                targetList.last.pageNumber == pno + 1 &&
                !isLargeVerticalGap &&
                maxSize >= h1HeightThreshold) {
              targetList.last.text = joinTextFlow(targetList.last.text, visibleLineText, isCjk: isCjk);
              targetList.last.richText = joinTextFlow(
                targetList.last.richText,
                line.headingRichText.replaceAll('\u00AD', ''),
                isCjk: isCjk,
              );
            } else {
              targetList.add(ReflowElement(
                type: ReflowElementType.h1,
                text: visibleLineText,
                richText: line.headingRichText.replaceAll('\u00AD', ''),
                pageNumber: pno + 1,
              ));
            }
            continue;
          }

          // 3. Heading 2 detection
          final h2HeightThreshold = line.isAllBold
              ? math.max(bodyHeight * 1.08, math.min(h2Size * 0.95, bodyHeight * 1.14))
              : math.max(bodyHeight * 1.18, math.min(h2Size * 0.95, bodyHeight * 1.22));
          if (canBeHeading &&
              !endsWithSentencePunct &&
              visibleLineText.length < 80 &&
              (maxSize >= h2HeightThreshold ||
                  (maxSize >= bodyHeight * 0.96 && h2SectionRegex.hasMatch(visibleLineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
            final targetList = deferFlushedBlocks ? deferredElements : elements;
            targetList.add(ReflowElement(
              type: ReflowElementType.h2,
              text: visibleLineText,
              richText: line.headingRichText.replaceAll('\u00AD', ''),
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 4. Heading 3 detection (including circled-number subheadings ①..⑳)
          if (canBeHeading &&
              !endsWithSentencePunct &&
              visibleLineText.length < 65 &&
              ((maxSize >= math.min(h3Size * 0.96, bodyHeight * 1.09) && isLargeVerticalGap) ||
                  (line.isAllBold && circledHeadingRegex.hasMatch(visibleLineText)))) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
            final targetList = deferFlushedBlocks ? deferredElements : elements;
            targetList.add(ReflowElement(
              type: ReflowElementType.h3,
              text: visibleLineText,
              richText: line.headingRichText.replaceAll('\u00AD', ''),
              pageNumber: pno + 1,
            ));
            continue;
          }

          // 5. Bullet & Ordered list item detection
          final bulletMatch = bulletRegex.firstMatch(lineText);
          if (bulletMatch != null) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
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
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
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
              (pno == 0 && visibleLineText.contains(' | ') && visibleLineText.length < 120) ||
              (!endsWithSentencePunct &&
                  line.bounds.width < region.regionBounds.width * 0.76 &&
                  (line.isAllBold || (!analysis.isMultiColumn && line.isAllItalic)));

          if (curParagraphForceFlushNext ||
              isStandaloneSubheader ||
              line.startsWithBoldColon ||
              line.startsParagraph ||
              isLargeVerticalGap) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
          } else if (curParagraph != null &&
              (isFirstLineIndented || prevWasShortLine) &&
              _endsWithParagraphPunctuation(curParagraph!.text)) {
            flushBlock();
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
          } else if (curParagraph == null && curBullet == null) {
            emitDueBlocks(line.bounds.top, curRegionIdx: rIdx);
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
            if (line.endsParagraph) {
              curParagraphForceFlushNext = true;
            }
          } else {
            curParagraph = ReflowElement(
              type: ReflowElementType.paragraph,
              text: lineText,
              richText: line.richText,
              pageNumber: pno + 1,
            );
            if (isStandaloneSubheader || line.endsParagraph) {
              curParagraphForceFlushNext = true;
            }
          }
        }

        if (holdCrossPageSentence) {
          flushBlock();
          deferFlushedBlocks = false;
          emitDueBlocks(region.regionBounds.bottom + 20.0, curRegionIdx: rIdx);
          curParagraph = savedParagraph;
        } else if (region.isBottomSpanning ||
            curParagraphForceFlushNext ||
            (curParagraph != null && _endsWithParagraphPunctuation(curParagraph!.text))) {
          flushBlock();
          emitDueBlocks(region.regionBounds.bottom + 20.0, curRegionIdx: rIdx);
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
      final content = (el.richText.trim().isNotEmpty
              ? el.richText.trim()
              : escapeMarkdownSpan(el.text))
          .replaceAll('\u00AD', '');
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

    // Filter out background images/templates that have dense body text or tables overlapping their interior,
    // while keeping large editorial illustrations that only have a few overlaid display/caption lines.
    final candidates = <Rect>[];
    for (final r in rawImageRects) {
      final interior = r.deflate(math.min(12.0, math.min(r.width, r.height) * 0.12));
      int overlappingLines = 0;
      double overlapTextArea = 0.0;
      for (final lineRect in pageLineRects) {
        if (interior.overlaps(lineRect)) {
          final inter = interior.intersect(lineRect);
          if (inter.width > 12.0 && inter.height > 4.0) {
            overlappingLines++;
            overlapTextArea += inter.width * inter.height;
          }
        }
      }
      final interiorArea = math.max(1.0, interior.width * interior.height);
      final overlapFraction = overlapTextArea / interiorArea;
      final isLargeIllustrationWithLightOverlay = r.width >= 180.0 &&
          r.height >= 180.0 &&
          overlappingLines <= 6 &&
          overlapFraction < 0.08;
      if (overlappingLines <= 2 || isLargeIllustrationWithLightOverlay) {
        candidates.add(r);
      }
    }
    if (candidates.isEmpty) return const [];

    // Merge overlapping or touching image tiles into composite figure bounds
    final merged = <Rect>[];
    for (final cand in candidates) {
      bool combined = false;
      for (var i = 0; i < merged.length; i++) {
        if (merged[i].inflate(1.0).overlaps(cand)) {
          merged[i] = merged[i].expandToInclude(cand);
          combined = true;
          break;
        }
      }
      if (!combined) {
        merged.add(cand);
      }
    }

    merged.sort((a, b) {
      if ((a.top - b.top).abs() <= 16.0) {
        return a.left.compareTo(b.left);
      }
      return a.top.compareTo(b.top);
    });
    final results = <({Rect rect, String markdownImage})>[];

    for (final figRect in merged) {
      if (results.length >= remainingQuota) break;
      // Target Mobile Portrait (390x780pt, 350pt body width) at ~1.5x clarity (up to 520px)
      final maxDim = math.max(figRect.width, figRect.height);
      final scale = (440.0 / maxDim).clamp(0.75, 1.35);
      final targetW = (figRect.width * scale).round().clamp(32, 520);
      final targetH = (figRect.height * scale).round().clamp(32, 520);
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

  @pragma('vm:prefer-inline')
  static int _paethPredictor(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
  }

  static String? _encodePdfImageToPngDataUri(PdfImage img) {
    final w = img.width;
    final h = img.height;
    final bgra = img.pixels;
    if (w <= 0 || h <= 0 || bgra.length < w * h * 4) return null;

    final rowBytes = w * 3;
    final rowStride = 1 + rowBytes;
    final rawScanlines = Uint8List(h * rowStride);
    var prevRow = Uint8List(rowBytes);
    var curRow = Uint8List(rowBytes);
    var srcIdx = 0;
    var dstIdx = 0;
    for (var y = 0; y < h; y++) {
      rawScanlines[dstIdx++] = 4; // Filter type 4 (Paeth)
      var prevR = 0;
      var prevG = 0;
      var prevB = 0;
      var upLeftR = 0;
      var upLeftG = 0;
      var upLeftB = 0;
      var colIdx = 0;
      for (var x = 0; x < w; x++) {
        final b = bgra[srcIdx];
        final g = bgra[srcIdx + 1];
        final r = bgra[srcIdx + 2];
        srcIdx += 4;

        final upR = prevRow[colIdx];
        final upG = prevRow[colIdx + 1];
        final upB = prevRow[colIdx + 2];

        rawScanlines[dstIdx++] = (r - _paethPredictor(prevR, upR, upLeftR)) & 0xFF;
        rawScanlines[dstIdx++] = (g - _paethPredictor(prevG, upG, upLeftG)) & 0xFF;
        rawScanlines[dstIdx++] = (b - _paethPredictor(prevB, upB, upLeftB)) & 0xFF;

        curRow[colIdx] = r;
        curRow[colIdx + 1] = g;
        curRow[colIdx + 2] = b;
        colIdx += 3;

        prevR = r;
        prevG = g;
        prevB = b;
        upLeftR = upR;
        upLeftG = upG;
        upLeftB = upB;
      }
      final tmp = prevRow;
      prevRow = curRow;
      curRow = tmp;
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

  static final RegExp _bulletLineRegex =
      RegExp(r'^(?:[•●○▪◆Ø\-\*]|(?:\(\d+\))|(?:\d+\)))\s+(.*)$');
  static final RegExp _orderedItemLineRegex = RegExp(r'^(\d{1,2})\.\s+(\S+.*)$');
  static final RegExp _circledHeadingRegex = RegExp(r'^[\u2460-\u2473]\s*\S+.*$');
  static final RegExp _h1SectionRegex = RegExp(
    r'^(?:(?:Abstract|Introduction|Conclusion|Conclusions|References|Acknowledgments|Acknowledgements|Appendix|摘要|引言|结论|参考文献|致谢)|(?:[IVX]+\.\s+[A-Z].*)|(?:\d+\.?\s+[A-Z\u4e00-\u9fa5].*)|(?:第[一二三四五六七八九十百千万0-9]+[章节篇部]\s*.*))$',
  );
  static final RegExp _h2SectionRegex = RegExp(
    r'^(?:(?:\d+\.\d+(?:\.\d+)?\.?\s+\S+.*)|(?:[一二三四五六七八九十]+、\s*\S+.*)|(?:\([一二三四五六七八九十]+\)\s*\S+.*))$',
  );
  static final RegExp _allCapsHeadingRegex =
      RegExp(r"^[A-Z][A-Z0-9\s&,/\-–—:'’\.]{2,44}$");
  static final RegExp _allCapsRubricHeaderRegex =
      RegExp(r"^[A-Z][A-Z0-9\s&\-\—\/:,\.'’]{2,44}$");
  static final RegExp _lowercaseStartRegex = RegExp(r'^[a-z]');
  static final RegExp _openingQuoteStartRegex = RegExp(r'^["“‘\x27]');
  static final RegExp _quotedLineRegex =
      RegExp(r'^(?:\*)?[“"‘\x27].*[”"’\x27\.!\?](?:\*)?$');
  static final RegExp _pageNumberOnlyRegex = RegExp(r'^\d{1,3}$');
  static final RegExp _quoteOrUpperStartRegex = RegExp(r'^["“‘\x27(\[]?[A-Z]');
  static final RegExp _openingQuoteRegex = RegExp(r'^["“‘\x27]$');
  static final RegExp _singleUpperRegex = RegExp(r'^[A-Z]$');
  static final RegExp _dropCapRegex = RegExp(r'^["“‘\x27]?[A-Z]$');
  static final RegExp _pronounIFollowersRegex = RegExp(
    r'^(?:[hwkyjquaieo]|(?:had|have|has|was|were|went|want|wanted|will|would|can|could|should|shall|may|might|must|did|didn|don|do|does|am|asked|saw|met|knew|know|think|thought|felt|found|heard|hoped|learned|lived|looked|loved|made|mean|meant|need|needed|never|once|often|always|still|also|just|only|even|already|almost|really|said|see|seem|seemed|spoke|started|stayed|stopped|took|told|tried|turned|used|visited|walked|watched|wished|wondered|worked|wrote)\b)',
    caseSensitive: false,
  );
  static final RegExp _articleANonFollowersRegex = RegExp(
    r'^(?:fter|bout|mong|round|gainst|lthough|lways|nother|lready|lmost|lso|long|cross|bove|head|way|part|side|live|lone|loud|llow|ppear|pproach|rriv|rtist|lger|meric|ttack|ttempt|ttend|ttract|uthor|vailab)',
    caseSensitive: false,
  );

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
      if (dc.rect.height < 14.5 || !_dropCapRegex.hasMatch(dc.text)) continue;

      int? bestTargetIdx;
      double bestGap = double.infinity;

      for (var j = 0; j < list.length; j++) {
        if (i == j || consumed[j]) continue;
        final cand = list[j];
        if (dc.rect.height < cand.rect.height * 1.35) continue;
        if ((cand.rect.top - dc.rect.top).abs() > 7.5) continue;
        final gap = cand.rect.left - dc.rect.right;
        if (gap >= -12.0 && gap <= 14.0 && gap.abs() < bestGap) {
          bestGap = gap.abs();
          bestTargetIdx = j;
        }
      }

      if (bestTargetIdx != null) {
        final target = list[bestTargetIdx];
        final letter = dc.text.substring(dc.text.length - 1);
        final isPronounI = letter == 'I' &&
            (dc.hasTrailingSpace || _pronounIFollowersRegex.hasMatch(target.text));
        final isArticleA = letter == 'A' &&
            (dc.hasTrailingSpace ||
                (target.rect.left - dc.rect.right > 2.2 &&
                    target.text.length >= 3 &&
                    !_articleANonFollowersRegex.hasMatch(target.text)));
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

  static final RegExp _puaEndMarkRegex =
      RegExp(r'[.!?…;:”’"\x27\)\]]\s*[\uE000-\uF8FF]+\s*$');
  static final RegExp _controlAndPuaStripRegex =
      RegExp(r'[\x01\x03-\x08\x0B\x0C\x0E-\x1F\uE000-\uF8FF]');
  static final RegExp _bulletOnlyRegex = RegExp(r'^[•●◆▪\s]+$');
  static final RegExp _trailingOrnamentBulletRegex =
      RegExp(r'(?<=[a-zA-Z,\.;:!”’\x02\u00AD])\s+[•●]\s*$');

  static ({String text, bool endsParagraph}) _cleanRawPdfFragmentText(String raw) {
    final endsPara = _puaEndMarkRegex.hasMatch(raw);
    final cleaned = raw
        .replaceAll('\x00', '')
        .replaceAll('\x02', '\u00AD')
        .replaceAll(_controlAndPuaStripRegex, '')
        .replaceAll(_trailingOrnamentBulletRegex, '')
        .replaceAll(_brokenFlLigatureRegex, 'f')
        .replaceAll(_brokenFiLigatureRegex, 'fi')
        .trim();
    return (text: cleaned, endsParagraph: endsPara);
  }

  static List<_VisualFragment> _splitFragmentByStylesAndLinks(
    PdfPage page,
    PdfPageText pageText,
    Rect fragRect,
    int start,
    int end,
    bool fragHasTrailingSpace,
    List<_StyledSpan> pageStyledSpans,
    List<({Rect rect, String url})> pageLinks, {
    ({String text, bool endsParagraph})? preCleaned,
  }) {
    final overSpans = <_StyledSpan>[
      for (final s in pageStyledSpans)
        if (s.rect.inflate(1.5).overlaps(fragRect)) s,
    ];
    final overLinks = <({Rect rect, String url})>[
      for (final l in pageLinks)
        if (l.rect.inflate(1.5).overlaps(fragRect)) l,
    ];

    final n = end - start;
    final wideGapThreshold = fragRect.height > 36.0
        ? 11.5
        : math.max(13.0, math.min(fragRect.height, 18.0) * 1.25);

    // Inspect charRects for stick-up initial caps (e.g. 20pt 'W' followed by 8pt 'hat' on the same baseline)
    // or sunken drop-caps (e.g. 30pt 'S' followed by 8pt 'am' near the top of a multi-line fragment)
    bool hasStickUpInitialCap = false;
    bool hasSunkenDropCap = false;
    double bodyLineHeight = fragRect.height;
    if (n >= 2 &&
        fragRect.height >= 14.0 &&
        fragRect.height <= 45.0 &&
        end <= pageText.charRects.length) {
      Rect? firstLetterRect;
      int firstLetterEndIdx = 0;
      double restMaxCharH = 0.0;
      int restCharCount = 0;
      for (var i = 0; i < n; i++) {
        final cp = pageText.fullText.codeUnitAt(start + i);
        if (cp <= 0x20 || cp == 0xA0 || cp == 0x02) continue;
        final cr = pageText.charRects[start + i].toRect(page: page);
        if (cr.width <= 0 || cr.height <= 0) continue;
        if (firstLetterRect == null) {
          if (i == 0 && (cp == 0x22 || cp == 0x27 || cp == 0x201C || cp == 0x2018)) {
            continue;
          }
          if (cp >= 0x41 && cp <= 0x5A) {
            firstLetterRect = cr;
            firstLetterEndIdx = i;
          }
          break;
        }
      }
      if (firstLetterRect != null && firstLetterRect.height >= 10.2) {
        final restCharWidths = <double>[];
        bool hasLowercase = false;
        for (var i = firstLetterEndIdx + 1; i < n; i++) {
          final cp = pageText.fullText.codeUnitAt(start + i);
          if (cp <= 0x20 || cp == 0xA0 || cp == 0x02) continue;
          if (cp >= 0x61 && cp <= 0x7A) hasLowercase = true;
          final cr = pageText.charRects[start + i].toRect(page: page);
          if (cr.width <= 0 || cr.height <= 0) continue;
          if (cr.height > restMaxCharH) restMaxCharH = cr.height;
          restCharWidths.add(cr.width);
          restCharCount++;
        }
        if (restCharCount >= 1 &&
            restMaxCharH >= 3.5 &&
            restMaxCharH <= 10.2 &&
            firstLetterRect.height >= restMaxCharH * 1.35) {
          if (fragRect.height >= 18.5 &&
              firstLetterRect.height >= 18.0 &&
              (firstLetterRect.bottom - fragRect.bottom).abs() > 4.0) {
            hasSunkenDropCap = true;
          } else if (fragRect.height <= 28.0) {
            hasStickUpInitialCap = true;
            bodyLineHeight = math.max(9.5, math.min(11.8, restMaxCharH / 0.68));
          }
        } else if (fragRect.height <= 28.0 && restCharWidths.length >= 8 && hasLowercase) {
          restCharWidths.sort();
          final restMedianCharW = restCharWidths[restCharWidths.length ~/ 2];
          if (restMedianCharW >= 3.2 &&
              restMedianCharW <= 5.6 &&
              fragRect.height >= restMedianCharW * 3.0) {
            hasStickUpInitialCap = true;
            bodyLineHeight = (restMedianCharW * 2.2).clamp(9.5, 11.8);
          }
        }
      }
    }

    final normalizedFragRect = hasStickUpInitialCap
        ? Rect.fromLTRB(
            fragRect.left,
            fragRect.bottom - bodyLineHeight,
            fragRect.right,
            fragRect.bottom,
          )
        : fragRect;

    final isTallMultiLineFrag =
        hasSunkenDropCap || (fragRect.height > 14.5 && !hasStickUpInitialCap);

    if (overSpans.isEmpty && overLinks.isEmpty && !hasSunkenDropCap) {
      bool hasWideInternalGap = false;
      if (n > 1 &&
          end <= pageText.charRects.length &&
          (fragRect.width > 60.0 || isTallMultiLineFrag)) {
        double? prevRight;
        double? prevCenterY;
        for (var i = 0; i < n; i++) {
          final cp = pageText.fullText.codeUnitAt(start + i);
          if (cp != 0x02 && (cp <= 0x20 || cp == 0xA0)) continue;
          final cr = pageText.charRects[start + i].toRect(page: page);
          if (cr.width <= 0 || cr.height <= 0) continue;
          if (prevRight != null && (cr.left - prevRight) > wideGapThreshold) {
            hasWideInternalGap = true;
            break;
          }
          if (isTallMultiLineFrag &&
              prevCenterY != null &&
              ((cr.center.dy - prevCenterY).abs() > 5.5 ||
                  (prevRight != null && cr.left < prevRight - 12.0))) {
            hasWideInternalGap = true;
            break;
          }
          prevRight = cr.right;
          prevCenterY = cr.center.dy;
        }
      }
      if (!hasWideInternalGap) {
        final cleaned = preCleaned ?? _cleanRawPdfFragmentText(pageText.fullText.substring(start, end));
        if (cleaned.text.isEmpty) return const [];
        return [
          _VisualFragment(
            rect: normalizedFragRect,
            text: cleaned.text,
            hasTrailingSpace: fragHasTrailingSpace,
            startsParagraph: hasStickUpInitialCap,
            endsParagraph: cleaned.endsParagraph,
            textStart: start,
            textEnd: end,
          ),
        ];
      }
    }

    if (n <= 0 || end > pageText.charRects.length) {
      final cleaned = preCleaned ?? _cleanRawPdfFragmentText(pageText.fullText.substring(start, end));
      if (cleaned.text.isEmpty) return const [];
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
          rect: normalizedFragRect,
          text: cleaned.text,
          hasTrailingSpace: fragHasTrailingSpace,
          startsParagraph: hasStickUpInitialCap,
          endsParagraph: cleaned.endsParagraph,
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
      return cp != 0x02 && (cp <= 0x20 || cp == 0xA0);
    });

    for (var i = 0; i < n; i++) {
      if (isSpace[i]) continue;
      final cp = pageText.fullText.codeUnitAt(start + i);
      if (cp == 0x02 || _isBulletChar(cp)) continue;
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

    // Inherit style/link onto soft-hyphen control code (\x02) from the preceding non-space character
    for (var i = 0; i < n; i++) {
      if (pageText.fullText.codeUnitAt(start + i) == 0x02) {
        int prev = i - 1;
        while (prev >= 0 && isSpace[prev]) {
          prev--;
        }
        if (prev >= 0) {
          charBold[i] = charBold[prev];
          charItalic[i] = charItalic[prev];
          charLink[i] = charLink[prev];
        }
      }
    }

    // Keep spaces between two identically styled/linked characters in the same run
    // unless the horizontal gap across the space exceeds wideGapThreshold (column/split gap)
    // or wraps vertically to a new line
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
          charRects[next].left >= charRects[prev].left - 8.0 &&
          (!isTallMultiLineFrag ||
              (charRects[next].center.dy - charRects[prev].center.dy).abs() <= 5.5) &&
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
          charRects[runStart].left >= charRects[runStart - 1].left - 6.0 &&
          (!isTallMultiLineFrag ||
              (charRects[runStart].center.dy - charRects[runStart - 1].center.dy).abs() <= 5.5) &&
          (charRects[runStart].left - charRects[runStart - 1].right) <= wideGapThreshold;

      Rect runRect = charRects[idx];
      final firstCharH = charRects[idx].height;
      double lastNonSpaceRight = charRects[idx].right;
      double lastNonSpaceCenterY = charRects[idx].center.dy;
      idx++;
      while (idx < n) {
        if (isSpace[idx]) {
          int nextNonSpace = idx + 1;
          while (nextNonSpace < n && isSpace[nextNonSpace]) {
            nextNonSpace++;
          }
          if (nextNonSpace < n) {
            final nextRect = charRects[nextNonSpace];
            final wrapsMultiLine = isTallMultiLineFrag &&
                nextRect.width > 0 &&
                nextRect.height > 0 &&
                (nextRect.left < lastNonSpaceRight - 12.0 ||
                    (nextRect.center.dy - lastNonSpaceCenterY).abs() > 5.5);
            if (wrapsMultiLine || (nextRect.left - lastNonSpaceRight) > wideGapThreshold) {
              break;
            }
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
        final cr = charRects[idx];
        if ((cr.left - lastNonSpaceRight) > wideGapThreshold) {
          break;
        }
        if (isTallMultiLineFrag && cr.width > 0 && cr.height > 0) {
          final wrapsMultiLine = cr.left < lastNonSpaceRight - 12.0 ||
              (cr.center.dy - lastNonSpaceCenterY).abs() > 5.5;
          final isDropCapTransition =
              idx <= runStart + 2 && firstCharH >= 14.2 && firstCharH >= cr.height * 1.35;
          if (wrapsMultiLine || isDropCapTransition) {
            break;
          }
        }
        if (charBold[idx] == rBold &&
            charItalic[idx] == rItalic &&
            charLink[idx] == rLink) {
          if (cr.width > 0 && cr.height > 0) {
            runRect = runRect.expandToInclude(cr);
            lastNonSpaceRight = cr.right;
            lastNonSpaceCenterY = cr.center.dy;
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

      final rawSub = pageText.fullText.substring(start + runStart, start + runEnd);
      final cleaned = _cleanRawPdfFragmentText(rawSub);
      if (cleaned.text.isNotEmpty) {
        final effectiveRect = isTallMultiLineFrag
            ? (runRect.width > 0 && runRect.height > 0 ? runRect : normalizedFragRect)
            : (runRect.width > 0
                ? Rect.fromLTRB(
                    runRect.left,
                    normalizedFragRect.top,
                    runRect.right,
                    normalizedFragRect.bottom,
                  )
                : normalizedFragRect);
        String outText = cleaned.text;
        bool outTrailingSpace = trailingSpace;
        if (fragRect.height > 36.0 &&
            idx < n &&
            _lowercaseEndRegex.hasMatch(outText)) {
          int nextNonSpace = idx;
          while (nextNonSpace < n && isSpace[nextNonSpace]) {
            nextNonSpace++;
          }
          if (nextNonSpace < n &&
              (charRects[nextNonSpace].left - lastNonSpaceRight) > wideGapThreshold) {
            final nextCp = pageText.fullText.codeUnitAt(start + nextNonSpace);
            if (nextCp >= 0x61 && nextCp <= 0x7A) {
              outText = '$outText\u00AD';
              outTrailingSpace = false;
            }
          }
        }
        result.add(_VisualFragment(
          rect: effectiveRect,
          text: outText,
          hasTrailingSpace: outTrailingSpace,
          noSpaceBefore: noSpaceBefore,
          startsParagraph: hasStickUpInitialCap && result.isEmpty,
          endsParagraph: cleaned.endsParagraph,
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

  static final RegExp _lowercaseEndRegex = RegExp(r'[a-z]$');

  /// Detects 2D structured tables bounded by horizontal rules/bands on a page,
  /// reconstructs them into Markdown GFM tables, and returns remaining non-table fragments.
  static ({
    List<({Rect rect, String markdownTable})> tables,
    List<_VisualFragment> remainingFragments,
  }) _extractPageTables(
    List<_VisualFragment> fragments,
    List<({double y, double left, double right})> horizontalRules, {
    required bool isCjk,
    List<({double left, double right, double mid})> gutters = const [],
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
      double tLeft = c.left - 8.0;
      double tRight = c.right + 8.0;
      // Do not expand a single-column table's horizontal capture bounds across an adjacent column gutter
      for (final g in gutters) {
        if (c.left >= g.mid - 4.0 && tLeft < g.mid) {
          tLeft = math.max(tLeft, g.mid + 1.0);
        }
        if (c.right <= g.mid + 4.0 && tRight > g.mid) {
          tRight = math.min(tRight, g.mid - 1.0);
        }
      }

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
          final sanitized = cellText.replaceAll('\u00AD', '').replaceAll('|', r'\|').trim();
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

    final initialFragments = <_VisualFragment>[];
    for (final f in pageText.fragments) {
      final rect = f.bounds.toRect(page: page);
      if (!rect.left.isFinite || !rect.top.isFinite || rect.width <= 0 || rect.height <= 0) {
        continue;
      }
      final start = f.index.clamp(0, pageText.fullText.length);
      final end = f.end.clamp(start, pageText.fullText.length);
      final rawSub = pageText.fullText.substring(start, end);
      // Strip 90°-rotated vertical side-margin or interior photo credits
      if (PdfPageAnalysisService.isVerticalMarginFragment(page, f, rect, rawText: rawSub)) {
        continue;
      }
      // Strip running headers & footers (except on page 1 top where title may sit near top)
      if ((page.pageNumber > 1 && rect.bottom < headerCutoff) || rect.top > footerCutoff) {
        continue;
      }
      final cleanedCheck = _cleanRawPdfFragmentText(rawSub);
      if (cleanedCheck.text.isEmpty) continue;
      if (page.pageNumber > 1 &&
          rect.bottom < runningHeaderSmallFontCutoff &&
          rect.height < 9.8 &&
          !(analysis.isMultiColumn && _allCapsRubricHeaderRegex.hasMatch(cleanedCheck.text))) {
        continue;
      }
      // Skip decorative full-column single-char ornaments (e.g. 40pt rule glyphs) or "1i" icon glyphs
      if (rect.height > 28.0 && cleanedCheck.text.length == 1 && rect.width > 80.0) {
        continue;
      }
      if (cleanedCheck.text == '1i') {
        continue;
      }
      final hasTrailingSpace = rawSub.endsWith(' ') ||
          (end < pageText.fullText.length && pageText.fullText.codeUnitAt(end) == 0x20);
      initialFragments.addAll(_splitFragmentByStylesAndLinks(
        page,
        pageText,
        rect,
        start,
        end,
        hasTrailingSpace,
        styledSpans,
        linkRects,
        preCleaned: cleanedCheck,
      ));
    }

    if (initialFragments.isEmpty) {
      return (regions: const [], tables: const []);
    }

    // Repair pdfrx cross-column hyphenated line-height inflation (e.g. when the bottom line of col c
    // is hyphenated into the top line of col c+1 and pdfrx sets top..bottom of both lines to the union)
    if (analysis.isMultiColumn && analysis.columns.length >= 2) {
      final normalHeights = <double>[
        for (final frag in initialFragments)
          if (frag.rect.height >= 7.5 && frag.rect.height <= 14.0) frag.rect.height,
      ]..sort();
      final medianBodyFragH = normalHeights.isNotEmpty
          ? normalHeights[normalHeights.length ~/ 2]
          : 10.5;
      var i = 0;
      while (i < initialFragments.length) {
        final f = initialFragments[i];
        if (f.rect.height > 36.0 &&
            f.rect.width / math.max(1, f.text.length) <= 8.5) {
          var j = i + 1;
          while (j < initialFragments.length &&
              (initialFragments[j].rect.top - f.rect.top).abs() <= 1.5 &&
              (initialFragments[j].rect.bottom - f.rect.bottom).abs() <= 1.5) {
            j++;
          }
          int minCol = 999;
          int maxCol = -1;
          for (var k = i; k < j; k++) {
            final cIdx = analysis.findBestColumn(initialFragments[k].rect.center).index;
            if (cIdx < minCol) minCol = cIdx;
            if (cIdx > maxCol) maxCol = cIdx;
          }
          if (maxCol > minCol) {
            for (var k = i; k < j; k++) {
              final cur = initialFragments[k];
              final cIdx = analysis.findBestColumn(cur.rect.center).index;
              final repairedRect = cIdx == minCol
                  ? Rect.fromLTRB(
                      cur.rect.left,
                      cur.rect.bottom - medianBodyFragH,
                      cur.rect.right,
                      cur.rect.bottom,
                    )
                  : Rect.fromLTRB(
                      cur.rect.left,
                      cur.rect.top,
                      cur.rect.right,
                      cur.rect.top + medianBodyFragH,
                    );
              initialFragments[k] = _VisualFragment(
                rect: repairedRect,
                text: cur.text,
                hasTrailingSpace: cur.hasTrailingSpace,
                noSpaceBefore: cur.noSpaceBefore,
                startsParagraph: cur.startsParagraph,
                endsParagraph: cur.endsParagraph,
                textStart: cur.textStart,
                textEnd: cur.textEnd,
                isBold: cur.isBold,
                isItalic: cur.isItalic,
                linkUrl: cur.linkUrl,
              );
            }
          }
          i = j;
        } else {
          i++;
        }
      }
    }

    // Filter out decorative section-break bullets (`•   •`) while keeping genuine list bullets
    // (a genuine list bullet has non-bullet text immediately to its right in the same column)
    final rawFragments = <_VisualFragment>[];
    for (var i = 0; i < initialFragments.length; i++) {
      final f = initialFragments[i];
      if (_bulletOnlyRegex.hasMatch(f.text)) {
        final fCol = analysis.isMultiColumn
            ? analysis.findBestColumn(f.rect.center).index
            : 0;
        bool hasRightTextNear = false;
        for (var j = 0; j < initialFragments.length; j++) {
          if (i == j) continue;
          final o = initialFragments[j];
          final dy = (o.rect.center.dy - f.rect.center.dy).abs();
          if (dy > math.max(3.5, math.min(f.rect.height, o.rect.height) * 0.55)) continue;
          final rightGap = o.rect.left - f.rect.right;
          if (rightGap >= -2.0 && rightGap <= 36.0 && !_bulletOnlyRegex.hasMatch(o.text)) {
            final oCol = analysis.isMultiColumn
                ? analysis.findBestColumn(o.rect.center).index
                : 0;
            if (oCol == fCol) {
              hasRightTextNear = true;
              break;
            }
          }
        }
        if (!hasRightTextNear) {
          continue;
        }
      }
      rawFragments.add(f);
    }

    if (rawFragments.isEmpty) {
      return (regions: const [], tables: const []);
    }

    // Compute column gutters before table extraction so single-column tables don't bleed across gutters
    final cols = analysis.columns;
    final gutters = <({double left, double right, double mid})>[];
    double maxColWidth = 0.0;
    if (analysis.isMultiColumn && cols.length >= 2) {
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
    }

    final tableExtraction = _extractPageTables(
      rawFragments,
      horizontalRules,
      isCjk: isCjk,
      gutters: gutters,
    );
    final extractedTables = tableExtraction.tables;
    if (tableExtraction.remainingFragments.isEmpty) {
      return (regions: const [], tables: extractedTables);
    }

    final mergedFragments = _mergeDropCaps(tableExtraction.remainingFragments);

    if (!analysis.isMultiColumn || cols.length < 2) {
      final lines = _groupFragmentsIntoLines(mergedFragments);
      return (
        regions: [
          (lines: lines, regionBounds: analysis.contentBounds, isBottomSpanning: false),
        ],
        tables: extractedTables,
      );
    }

    final allLines = _groupFragmentsIntoLines(mergedFragments, gutters: gutters);

    // Detect full-width horizontal rules that divide stacked multi-column stories (e.g. Goings On About Town)
    final dividerYs = <double>[];
    for (final r in horizontalRules) {
      final rW = r.right - r.left;
      if (rW < analysis.contentBounds.width * 0.88) continue;
      if (r.y <= pageHeight * 0.16 || r.y >= pageHeight * 0.88) continue;
      final insideTable = extractedTables.any((t) => r.y >= t.rect.top - 6.0 && r.y <= t.rect.bottom + 6.0);
      if (insideTable) continue;
      final intersectsAnyLine = allLines.any((l) => l.bounds.top < r.y - 1.5 && l.bounds.bottom > r.y + 1.5);
      if (intersectsAnyLine) continue;
      dividerYs.add(r.y);
    }

    // Also detect full-width horizontal whitespace bands separating stacked multi-column stories
    // (e.g. Page 10 where COMMENT occupies the top half of all 3 columns and FIRST THINGS FIRST DEPT.
    // occupies the bottom half across a >= 18pt full-width horizontal whitespace gap)
    if (allLines.length >= cols.length * 6) {
      final topSortedLines = List<_VisualLine>.from(allLines)
        ..sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
      double maxBottomSoFar = topSortedLines.first.bounds.bottom;
      for (var i = 0; i < topSortedLines.length - 1; i++) {
        if (topSortedLines[i].bounds.bottom > maxBottomSoFar) {
          maxBottomSoFar = topSortedLines[i].bounds.bottom;
        }
        final nextTop = topSortedLines[i + 1].bounds.top;
        final gapH = nextTop - maxBottomSoFar;
        if (gapH >= 18.0 &&
            maxBottomSoFar > pageHeight * 0.20 &&
            nextTop < pageHeight * 0.82) {
          final midY = (maxBottomSoFar + nextTop) / 2.0;
          final insideTable = extractedTables.any(
            (t) => midY >= t.rect.top - 6.0 && midY <= t.rect.bottom + 6.0,
          );
          if (insideTable) continue;
          bool allColsAboveAndBelow = true;
          for (var c = 0; c < cols.length; c++) {
            final cLeft = cols[c].bounds.left - 8.0;
            final cRight = cols[c].bounds.right + 8.0;
            int aboveCount = 0;
            int belowCount = 0;
            for (final l in allLines) {
              final cx = l.bounds.center.dx;
              if (cx >= cLeft && cx <= cRight) {
                if (l.bounds.bottom <= maxBottomSoFar + 1.0) aboveCount++;
                if (l.bounds.top >= nextTop - 1.0) belowCount++;
              }
            }
            if (aboveCount < 3 || belowCount < 3) {
              allColsAboveAndBelow = false;
              break;
            }
          }
          if (allColsAboveAndBelow) {
            _VisualLine? firstBelowCol0;
            _VisualLine? lastAboveLastCol;
            for (final l in topSortedLines) {
              if (l.bounds.top >= nextTop - 1.0 &&
                  l.bounds.center.dx <= cols.first.bounds.right + 8.0) {
                firstBelowCol0 ??= l;
              }
              if (l.bounds.bottom <= maxBottomSoFar + 1.0 &&
                  l.bounds.center.dx >= cols.last.bounds.left - 8.0) {
                lastAboveLastCol = l;
              }
            }
            final belowStartsRubricOrHeading = firstBelowCol0 != null &&
                ((firstBelowCol0.text == firstBelowCol0.text.toUpperCase() &&
                        _hasWordLettersRegex.hasMatch(firstBelowCol0.text)) ||
                    firstBelowCol0.maxHeight >= 13.5);
            final aboveEndsWithBylineDash = lastAboveLastCol != null &&
                (lastAboveLastCol.text.startsWith('—') || lastAboveLastCol.text.startsWith('--'));
            if (belowStartsRubricOrHeading || aboveEndsWithBylineDash) {
              dividerYs.add(midY);
            }
          }
        }
      }
    }
    dividerYs.sort();
    final mergedDividers = <double>[];
    for (final y in dividerYs) {
      if (mergedDividers.isEmpty || (y - mergedDividers.last) > 24.0) {
        mergedDividers.add(y);
      }
    }

    final bandBoundaries = <double>[0.0, ...mergedDividers, pageHeight + 100.0];
    final result = <({List<_VisualLine> lines, Rect regionBounds, bool isBottomSpanning})>[];

    for (var bIdx = 0; bIdx < bandBoundaries.length - 1; bIdx++) {
      final bTop = bandBoundaries[bIdx];
      final bBottom = bandBoundaries[bIdx + 1];
      var bandLines = <_VisualLine>[
        for (final l in allLines)
          if (l.bounds.center.dy >= bTop && l.bounds.center.dy < bBottom) l,
      ];
      if (bandLines.isEmpty) continue;

      // Detect 2-column inset poem/sidebar box in cols[1..2] or cols[0..1] on a 3-column page
      // (e.g. Pages 36 & 49 where an inset poem box spans two of the three columns)
      final insetRegions = <({List<_VisualLine> lines, Rect regionBounds, bool isBottomSpanning})>[];
      if (cols.length == 3) {
        final twoColSpanWidth = cols[2].bounds.right - cols[1].bounds.left;
        double? insetBottomRuleY;
        for (final r in horizontalRules) {
          final rW = r.right - r.left;
          if (r.left >= cols[0].bounds.right - 14.0 &&
              rW >= twoColSpanWidth * 0.65 &&
              r.y > bTop + 70.0 &&
              r.y < bBottom - 70.0) {
            if (insetBottomRuleY == null || r.y > insetBottomRuleY) {
              insetBottomRuleY = r.y;
            }
          }
        }
        for (final isRightPair in [true, false]) {
          final g = isRightPair ? gutters[1] : gutters[0];
          final crossLines = <_VisualLine>[
            for (final l in bandLines)
              if ((isRightPair
                      ? l.bounds.left >= cols[0].bounds.right - 10.0
                      : l.bounds.right <= cols[2].bounds.left + 10.0) &&
                  l.bounds.left < g.mid - 6.0 &&
                  l.bounds.right > g.mid + 6.0)
                l,
          ];
          if (crossLines.length < 12) continue;

          final boxTop = crossLines.map((l) => l.bounds.top).reduce(math.min) - 38.0;
          final boxBottom = (isRightPair ? insetBottomRuleY : null) ??
              (crossLines.map((l) => l.bounds.bottom).reduce(math.max) + 28.0);
          final hasOuterColAlongside = bandLines.any(
            (l) =>
                (isRightPair
                    ? l.bounds.right <= cols[0].bounds.right + 12.0
                    : l.bounds.left >= cols[2].bounds.left - 12.0) &&
                l.bounds.top < boxBottom - 40.0,
          );
          if (!hasOuterColAlongside) continue;

          final insetLines = <_VisualLine>[];
          final remainingBandLines = <_VisualLine>[];
          for (final l in bandLines) {
            final inHorizSpan = isRightPair
                ? l.bounds.left >= cols[1].bounds.left - 12.0
                : l.bounds.right <= cols[1].bounds.right + 12.0;
            if (inHorizSpan && l.bounds.top >= boxTop && l.bounds.center.dy <= boxBottom) {
              insetLines.add(l);
            } else {
              remainingBandLines.add(l);
            }
          }
          if (insetLines.isNotEmpty) {
            bandLines = remainingBandLines;
            insetLines.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
            insetRegions.add((
              lines: insetLines,
              regionBounds: Rect.fromLTRB(
                isRightPair ? cols[1].bounds.left : cols[0].bounds.left,
                boxTop,
                isRightPair ? cols[2].bounds.right : cols[1].bounds.right,
                boxBottom,
              ),
              isBottomSpanning: true,
            ));
            break;
          }
        }
      }

      // Check for a 2-column story header spanning ONLY cols[1..2] (gutters[1]) on a 3-column page
      // while col0 contains the preceding story (e.g. Pages 10 & 13).
      if (cols.length == 3) {
        final g0 = gutters[0];
        final g1 = gutters[1];
        final hasFullSpanTop = bandLines.any(
          (l) =>
              l.bounds.top < pageHeight * 0.50 &&
              l.bounds.left < g0.mid - 14.0 &&
              l.bounds.right > g1.mid + 14.0,
        );
        final g1HeaderLines = <_VisualLine>[
          for (final l in bandLines)
            if (l.bounds.top < pageHeight * 0.50 &&
                l.bounds.left >= cols[0].bounds.right - 10.0 &&
                l.bounds.left < g1.mid - 10.0 &&
                l.bounds.right > g1.mid + 10.0)
              l,
        ];
        if (!hasFullSpanTop && g1HeaderLines.isNotEmpty && g1HeaderLines.length <= 5) {
          final spanMinTop = g1HeaderLines.map((l) => l.bounds.top).reduce(math.min);
          final spanMaxBottom = g1HeaderLines.map((l) => l.bounds.bottom).reduce(math.max);
          final hasCol1AboveRubric = bandLines.any(
            (l) =>
                l.bounds.left >= cols[0].bounds.right - 10.0 &&
                l.bounds.right <= g1.mid + 10.0 &&
                l.bounds.bottom < spanMinTop - 36.0,
          );
          final col0Lines = <_VisualLine>[];
          final col1Above = <_VisualLine>[];
          final col2Above = <_VisualLine>[];
          final cols12Header = <_VisualLine>[];
          final col1Below = <_VisualLine>[];
          final col2Below = <_VisualLine>[];
          final bottomSpan = <_VisualLine>[];

          for (final l in bandLines) {
            final r = l.bounds;
            final spansGutter = gutters.any((g) => r.left < g.mid - 14.0 && r.right > g.mid + 14.0);
            if (spansGutter && r.top >= pageHeight * 0.50) {
              bottomSpan.add(l);
              continue;
            }
            if (r.right <= cols[0].bounds.right + 12.0) {
              col0Lines.add(l);
              continue;
            }
            final inHeaderBand = r.top >= spanMinTop - 34.0 &&
                r.bottom <= spanMaxBottom + 34.0 &&
                (spansGutter ||
                    r.top >= spanMinTop - 2.0 ||
                    !hasCol1AboveRubric ||
                    l.text == l.text.toUpperCase());
            if (inHeaderBand) {
              cols12Header.add(l);
            } else if (r.bottom <= spanMinTop) {
              if (r.center.dx < g1.mid) {
                col1Above.add(l);
              } else {
                col2Above.add(l);
              }
            } else {
              if (r.center.dx < g1.mid) {
                col1Below.add(l);
              } else {
                col2Below.add(l);
              }
            }
          }

          for (final bucket in [
            (lines: col0Lines, bounds: cols[0].bounds),
            (lines: col1Above, bounds: cols[1].bounds),
            (lines: col2Above, bounds: cols[2].bounds),
            (
              lines: cols12Header,
              bounds: Rect.fromLTRB(cols[1].bounds.left, spanMinTop - 34.0, cols[2].bounds.right, spanMaxBottom + 34.0),
            ),
            (lines: col1Below, bounds: cols[1].bounds),
            (lines: col2Below, bounds: cols[2].bounds),
          ]) {
            if (bucket.lines.isNotEmpty) {
              bucket.lines.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
              result.add((
                lines: bucket.lines,
                regionBounds: bucket.bounds,
                isBottomSpanning: false,
              ));
            }
          }
          result.addAll(insetRegions);
          if (bottomSpan.isNotEmpty) {
            bottomSpan.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
            result.add((
              lines: bottomSpan,
              regionBounds: analysis.contentBounds,
              isBottomSpanning: true,
            ));
          }
          continue;
        }
      }

      // Identify advertisement columns before computing body tops and header zones
      final isAdCol = List<bool>.generate(cols.length, (cIdx) {
        if (cols.length < 2 || cols[cIdx].bounds.width >= maxColWidth - 10.0) {
          return false;
        }
        return bandLines.any(
          (l) =>
              analysis.findBestColumn(l.bounds.center).index.clamp(0, cols.length - 1) == cIdx &&
              l.text.trim() == 'ADVERTISEMENT',
        );
      });

      // Find the top Y of normal left-aligned body prose in each column of this band
      final colBodyTop = List<double?>.filled(cols.length, null);
      for (final l in bandLines) {
        final r = l.bounds;
        final spansGutter = gutters.any((g) => r.left < g.mid - 14.0 && r.right > g.mid + 14.0);
        if (spansGutter || r.width > maxColWidth * 1.18) continue;
        final colIdx = analysis.findBestColumn(r.center).index.clamp(0, cols.length - 1);
        if (isAdCol[colIdx]) continue;
        final isAllCapsLine =
            l.text == l.text.toUpperCase() && _hasWordLettersRegex.hasMatch(l.text);
        final isFullColItalicBody =
            l.isAllItalic && r.width >= cols[colIdx].bounds.width * 0.65 && l.maxHeight <= 12.5;
        final isNormalBodyLine = (!l.isAllItalic || isFullColItalicBody) &&
            !isAllCapsLine &&
            r.left <= cols[colIdx].bounds.left + 28.0 &&
            (colIdx == 0 || (r.width >= cols[colIdx].bounds.width * 0.62 && l.maxHeight <= 13.5));
        if (isNormalBodyLine) {
          if (colBodyTop[colIdx] == null || r.top < colBodyTop[colIdx]!) {
            colBodyTop[colIdx] = r.top;
          }
        }
      }
      final col0BodyTop = colBodyTop[0];

      final topSpanCutoff = col0BodyTop != null ? (col0BodyTop + 18.0) : (pageHeight * 0.48);
      final topSpanning = <_VisualLine>[];
      final colBuckets = List<List<_VisualLine>>.generate(cols.length, (_) => <_VisualLine>[]);
      final bottomSpanning = <_VisualLine>[];

      double maxTopSpanBottom = -1.0;
      double maxTopSpanRight = -1.0;
      for (final line in bandLines) {
        final r = line.bounds;
        final spansGutter = gutters.any((g) => r.left < g.mid - 14.0 && r.right > g.mid + 14.0);
        final isWide = r.width > maxColWidth * 1.18;
        if (spansGutter || isWide) {
          if (r.top <= topSpanCutoff || r.top < pageHeight * 0.45) {
            topSpanning.add(line);
            if (r.bottom > maxTopSpanBottom) maxTopSpanBottom = r.bottom;
            if (r.right > maxTopSpanRight) maxTopSpanRight = r.right;
          } else {
            bottomSpanning.add(line);
          }
        } else {
          final colIdx = analysis.findBestColumn(r.center).index.clamp(0, cols.length - 1);
          colBuckets[colIdx].add(line);
        }
      }

      // Promote narrow centered rubrics/bylines/headers (e.g. "PROFILES", "BY AVA KOFMAN",
      // "ANNALS OF AVIATION", "THE CRITICS") that sit above their column's body prose into topSpanning
      final headerZoneBottom = math.max(
        maxTopSpanBottom >= 0 ? maxTopSpanBottom + 56.0 : -1.0,
        col0BodyTop != null ? col0BodyTop - 2.0 : -1.0,
      );
      if (headerZoneBottom > 0) {
        for (var cIdx = 0; cIdx < cols.length; cIdx++) {
          if (isAdCol[cIdx]) continue;
          if (cIdx > 0 &&
              (maxTopSpanBottom < 0 || maxTopSpanRight <= cols[cIdx].bounds.left + 10.0)) {
            continue;
          }
          final cBodyTop = colBodyTop[cIdx];
          final cCutoff = cBodyTop != null
              ? math.min(headerZoneBottom, cBodyTop - 2.0)
              : headerZoneBottom;
          if (cCutoff <= 0) continue;
          final kept = <_VisualLine>[];
          for (final l in colBuckets[cIdx]) {
            final isAboveSpanningTitle = maxTopSpanBottom >= 0 && l.bounds.bottom <= maxTopSpanBottom + 2.0;
            final isHeaderStyleLine = (l.text == l.text.toUpperCase() &&
                    _hasWordLettersRegex.hasMatch(l.text)) ||
                l.text.toUpperCase().startsWith('BY ') ||
                l.maxHeight >= 13.8;
            if (l.bounds.bottom <= cCutoff &&
                (cIdx == 0 || isAboveSpanningTitle || isHeaderStyleLine)) {
              topSpanning.add(l);
            } else {
              kept.add(l);
            }
          }
          colBuckets[cIdx] = kept;
        }
      }

      final nonEmptyColCount = colBuckets.where((b) => b.isNotEmpty).length;
      if (nonEmptyColCount < 2 && bottomSpanning.isNotEmpty) {
        bandLines.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
        result.add((
          lines: bandLines,
          regionBounds: analysis.contentBounds,
          isBottomSpanning: false,
        ));
        result.addAll(insetRegions);
        continue;
      }

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
        if (bucket.isEmpty) continue;
        bucket.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
        final isWideSidebarCol = cols.length == 2 &&
            i == 1 &&
            cols[1].bounds.width > cols[0].bounds.width * 1.35 &&
            bucket.first.text == bucket.first.text.toUpperCase() &&
            _hasWordLettersRegex.hasMatch(bucket.first.text);
        if (isWideSidebarCol || isAdCol[i]) {
          insetRegions.add((
            lines: bucket,
            regionBounds: cols[i].bounds,
            isBottomSpanning: true,
          ));
        } else {
          result.add((
            lines: bucket,
            regionBounds: cols[i].bounds,
            isBottomSpanning: false,
          ));
        }
      }
      result.addAll(insetRegions);
      if (bottomSpanning.isNotEmpty) {
        bottomSpanning.sort((a, b) => a.bounds.top.compareTo(b.bounds.top));
        result.add((
          lines: bottomSpanning,
          regionBounds: analysis.contentBounds,
          isBottomSpanning: true,
        ));
      }
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
        final isContiguousInText =
            !prev.hasTrailingSpace && f.textStart != null && prev.textEnd != null && f.textStart == prev.textEnd;
        final minSpaceGap = isContiguousInText
            ? math.max(2.6, math.min(prev.rect.height, f.rect.height) * 0.28)
            : 1.2;
        needSpace = !f.noSpaceBefore && (prev.hasTrailingSpace || gap > minSpaceGap);
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
      bool endsPara = false;
      bool isSplitHeader = false;
      int? firstStart;
      int? lastEnd;
      final sb = StringBuffer();
      final segFragments = <_VisualFragment>[];
      double? prevRight;
      double? prevHeight;
      int? prevTextEnd;
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

          double effectiveMaxH = maxH;
          if (segFragments.length >= 2) {
            final letterFragItems = <({double height, int weight})>[];
            for (var i = 0; i < segFragments.length; i++) {
              final f = segFragments[i];
              if (_hasWordLettersRegex.hasMatch(f.text)) {
                letterFragItems.add((
                  height: f.rect.height,
                  weight: math.max(1, f.text.trim().length),
                ));
              }
            }
            if (letterFragItems.length >= 2) {
              final firstH = segFragments.first.rect.height;
              final restHeights = [
                for (var i = 1; i < segFragments.length; i++)
                  if (_hasWordLettersRegex.hasMatch(segFragments[i].text))
                    segFragments[i].rect.height,
              ]..sort();
              if (restHeights.isNotEmpty) {
                final restMedianH = restHeights[restHeights.length ~/ 2];
                if (firstH >= 14.5 && restMedianH <= 13.0 && firstH >= restMedianH * 1.35) {
                  startsPara = true;
                  effectiveMaxH = restMedianH;
                  bounds = Rect.fromLTRB(
                    bounds!.left,
                    bounds!.bottom - restMedianH,
                    bounds!.right,
                    bounds!.bottom,
                  );
                }
              }
              if (effectiveMaxH == maxH) {
                letterFragItems.sort((a, b) => a.height.compareTo(b.height));
                final totalWeight = letterFragItems.fold<int>(0, (s, e) => s + e.weight);
                int acc = 0;
                for (final item in letterFragItems) {
                  acc += item.weight;
                  if (acc * 2 >= totalWeight) {
                    effectiveMaxH = item.height;
                    break;
                  }
                }
              }
            }
          }

          // Scope: 9-11pt magazine/book body prose (e.g. The New Yorker) where pdfrx_engine
          // unifies top..bottom across all word fragments on the same baseline when the line
          // starts with a 16-24pt stick-up initial cap (causing effectiveMaxH >= 14.0 across
          // every fragment on the line). Genuine 14-18pt single-column headings/prose have
          // wider character spacing (avgCharW > 6.4pt or effectiveMaxH < avgCharW * 2.6) and
          // do not match this check.
          final avgCharW = bounds!.width / math.max(1, text.length);
          if (effectiveMaxH >= 14.0 &&
              !isAllBold &&
              text.length >= 12 &&
              text != text.toUpperCase() &&
              _quoteOrUpperStartRegex.hasMatch(text) &&
              avgCharW <= 6.4 &&
              effectiveMaxH >= avgCharW * 2.6) {
            final estimatedBodyH = (avgCharW * 2.05).clamp(9.5, 11.5);
            startsPara = true;
            effectiveMaxH = estimatedBodyH;
            bounds = Rect.fromLTRB(
              bounds!.left,
              bounds!.bottom - estimatedBodyH,
              bounds!.right,
              bounds!.bottom,
            );
          }

          lines.add(_VisualLine(
            bounds: bounds!,
            text: text,
            richText: _buildRichLineMarkdown(segFragments, isHeading: false),
            headingRichText: _buildRichLineMarkdown(segFragments, isHeading: true),
            maxHeight: effectiveMaxH,
            startsParagraph: startsPara,
            endsParagraph: endsPara,
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
        endsPara = false;
        isSplitHeader = false;
        firstStart = null;
        lastEnd = null;
        sb.clear();
        segFragments.clear();
        prevRight = null;
        prevHeight = null;
        prevTextEnd = null;
        prevHasTrailingSpace = false;
      }

      for (final item in cluster) {
        if (prevRight != null) {
          final gap = item.rect.left - prevRight!;
          final lineH = math.max(maxH, item.rect.height);
          final minAdjH = math.min(prevHeight ?? item.rect.height, item.rect.height);
          final isWideHorizontalGap = gap > math.max(28.0, lineH * 2.2);
          bool crossesGutterGap = gutters.isNotEmpty && isWideHorizontalGap;
          if (maxIntraSegmentGapFactor != null &&
              gap > math.max(12.0, lineH * maxIntraSegmentGapFactor)) {
            crossesGutterGap = true;
          }
          if (!crossesGutterGap && gutters.isNotEmpty) {
            for (final g in gutters) {
              final gutterWidth = math.max(6.0, g.right - g.left);
              final minGutterGap = minAdjH >= 13.5
                  ? math.max(6.5, minAdjH * 0.65)
                  : math.max(4.5, gutterWidth * 0.50);
              if (prevRight! <= g.mid + 3.0 &&
                  item.rect.left >= g.mid - 3.0 &&
                  gap >= minGutterGap) {
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
        if (item.endsParagraph) endsPara = true;
        firstStart ??= item.textStart;
        if (item.textEnd != null) lastEnd = item.textEnd;
        if (prevRight != null) {
          final gap = item.rect.left - prevRight!;
          final isContiguousInText = !prevHasTrailingSpace &&
              item.textStart != null &&
              prevTextEnd != null &&
              item.textStart == prevTextEnd;
          final minSpaceGap = isContiguousInText
              ? math.max(2.6, math.min(prevHeight ?? item.rect.height, item.rect.height) * 0.28)
              : 1.2;
          if (!item.noSpaceBefore &&
              (prevHasTrailingSpace || gap > minSpaceGap) &&
              !sb.toString().endsWith(' ')) {
            sb.write(' ');
          }
        }
        sb.write(item.text);
        segFragments.add(item);
        prevRight = item.rect.right;
        prevHeight = item.rect.height;
        prevTextEnd = item.textEnd;
        prevHasTrailingSpace = item.hasTrailingSpace;
      }

      flushSegment();
    }
    return lines;
  }
}
