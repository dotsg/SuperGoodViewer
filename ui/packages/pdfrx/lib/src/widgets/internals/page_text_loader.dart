import 'package:flutter/foundation.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'indexed_page_text.dart';

/// Retain the upstream text formatter and its selection geometry. Large pages
/// are formatted away from the UI isolate on native platforms; small pages
/// avoid isolate startup/transfer costs. compute uses the same callback on web.
Future<PdfPageText> loadStructuredPageText(PdfPage page) async => (await loadIndexedPageText(page)).text;

Future<IndexedPageText> loadIndexedPageText(PdfPage page) async {
  final clock = Pdfrx.debugLazyLoading ? (Stopwatch()..start()) : null;
  final bytesAtStart = Pdfrx.debugBytesFetched;
  final raw = await page.loadText();
  final extractionMs = clock?.elapsedMilliseconds;
  final snapshot = _TextSnapshotPage(raw, page.pageNumber, page.width, page.height, page.rotation);
  final background = !kIsWeb && raw != null && raw.fullText.length >= 8192;
  final text = background
      ? await compute(_formatSnapshot, snapshot, debugLabel: 'pdfrx.formatText')
      : await _formatSnapshot(snapshot);
  if (clock != null) {
    pdfrxLazyLog(
      'TEXT p${page.pageNumber} ${text.text.fragments.length} fragments: '
      'extract ${extractionMs}ms, format ${clock.elapsedMilliseconds - extractionMs!}ms '
      '(${background ? 'background' : 'inline'}), '
      '${Pdfrx.debugBytesFetched - bytesAtStart} bytes fetched',
    );
  }
  return text;
}

Future<IndexedPageText> _formatSnapshot(_TextSnapshotPage page) async => IndexedPageText(await page.loadStructuredText());

/// The engine's public formatter takes a PdfPage rather than raw text. This
/// adapter exposes only an immutable snapshot, with no document/native handle
/// that could accidentally cross isolate boundaries or outlive its document.
class _TextSnapshotPage implements PdfPage {
  const _TextSnapshotPage(this.raw, this.pageNumber, this.width, this.height, this.rotation);

  final PdfPageRawText? raw;
  @override
  final int pageNumber;
  @override
  final double width;
  @override
  final double height;
  @override
  final PdfPageRotation rotation;
  @override
  bool get isLoaded => true;
  @override
  Future<PdfPageRawText?> loadText() async => raw;

  @override
  PdfDocument get document => throw UnsupportedError('Text snapshots have no PDF document');
  @override
  PdfPageRenderCancellationToken createCancellationToken() => throw UnsupportedError('Text snapshots cannot render');
  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) =>
      throw UnsupportedError('Text snapshots have no links');
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    int? backgroundColor,
    PdfPageRotation? rotationOverride,
    PdfAnnotationRenderingMode annotationRenderingMode = PdfAnnotationRenderingMode.annotationAndForms,
    int flags = PdfPageRenderFlags.none,
    PdfPageRenderCancellationToken? cancellationToken,
  }) => throw UnsupportedError('Text snapshots cannot render');
}
