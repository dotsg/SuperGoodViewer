// Adapted from pdfrx 2.6.1 tests (MIT; see packages/pdfrx/LICENSE).
import 'dart:async';
import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

enum RasterDocumentEvent { loadComplete, missingFonts }

class RasterTestDocument extends PdfDocument {
  RasterTestDocument(
    int pageCount, {
    this.reloadError,
    this.replayedEvents = const [],
    this.emitCompletionOnProgressive = true,
    this.pageHeight = 800,
    super.sourceName = 'test:priority',
  }) {
    _pages = List.generate(pageCount, (index) => RasterTestPage(this, index + 1, isLoaded: index == 0));
  }

  final _events = StreamController<PdfDocumentEvent>.broadcast();
  final double pageHeight;
  final Object? reloadError;
  final List<RasterDocumentEvent> replayedEvents;
  final bool emitCompletionOnProgressive;
  late List<PdfPage> _pages;
  final reloadRequests = <List<int>?>[];
  bool progressiveLoadingStarted = false;
  int? progressiveLoadingStartPageNumber;

  void reportMissingFonts() {
    _events.add(
      PdfDocumentMissingFontsEvent(this, const [
        PdfFontQuery(face: 'Missing Font', weight: 400, isItalic: false, charset: PdfFontCharset.ansi, pitchFamily: 0),
      ]),
    );
  }

  @override
  Stream<PdfDocumentEvent> get events async* {
    for (final event in replayedEvents) {
      switch (event) {
        case RasterDocumentEvent.loadComplete:
          yield PdfDocumentLoadCompleteEvent(this);
        case RasterDocumentEvent.missingFonts:
          yield PdfDocumentMissingFontsEvent(this, const []);
      }
    }
    yield* _events.stream;
  }

  @override
  bool get isEncrypted => false;

  @override
  PdfPermissions? get permissions => null;

  @override
  List<PdfPage> get pages => List.unmodifiable(_pages);

  @override
  set pages(List<PdfPage> value) => _pages = List.of(value);

  @override
  Future<void> dispose() => _events.close();

  @override
  Future<void> loadPagesProgressively<T>({
    PdfPageLoadingCallback<T>? onPageLoadProgress,
    T? data,
    Duration loadUnitDuration = const Duration(milliseconds: 250),
    int? startPageNumber,
  }) async {
    progressiveLoadingStarted = true;
    progressiveLoadingStartPageNumber = startPageNumber;
    _loadPages([for (var pageNumber = 1; pageNumber <= _pages.length; pageNumber++) pageNumber]);
    await onPageLoadProgress?.call(_pages.length, _pages.length, data);
    if (emitCompletionOnProgressive) {
      _events.add(PdfDocumentLoadCompleteEvent(this));
    }
  }

  @override
  Future<void> reloadPages({List<int>? pageNumbersToReload}) async {
    reloadRequests.add(pageNumbersToReload?.toList());
    if (reloadError != null) throw reloadError!;
    final pageNumbers =
        pageNumbersToReload ?? [for (var pageNumber = 1; pageNumber <= _pages.length; pageNumber++) pageNumber];
    _loadPages(pageNumbers);
  }

  void _loadPages(List<int> pageNumbers) {
    final changes = <int, PdfPageStatusChange>{};
    for (final pageNumber in pageNumbers) {
      if (_pages[pageNumber - 1].isLoaded) continue;
      final previousPage = _pages[pageNumber - 1] as RasterTestPage;
      final page = RasterTestPage(this, pageNumber, isLoaded: true, renderControl: previousPage.renderControl);
      _pages[pageNumber - 1] = page;
      changes[pageNumber] = PdfPageStatusChange.modified(page: page);
    }
    if (changes.isNotEmpty) {
      _events.add(PdfDocumentPageStatusChangedEvent(this, changes: changes));
    }
  }

  @override
  Future<List<PdfOutlineNode>> loadOutline() async => const [];

  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);

  @override
  Future<bool> assemble() async => true;

  @override
  Future<Uint8List> encodePdf({bool incremental = false, bool removeSecurity = false}) async => Uint8List(0);

  @override
  Future<T> useNativeDocumentHandle<T>(FutureOr<T> Function(int nativeDocumentHandle) task) async => await task(0);
}

class RasterTestPage implements PdfPage {
  RasterTestPage(this.document, this.pageNumber, {required this.isLoaded, RasterRenderControl? renderControl})
    : renderControl = renderControl ?? RasterRenderControl();

  @override
  final PdfDocument document;

  @override
  final int pageNumber;

  @override
  final bool isLoaded;

  final RasterRenderControl renderControl;

  @override
  double get width => 600;

  @override
  double get height => (document as RasterTestDocument).pageHeight;

  @override
  PdfPageRotation get rotation => PdfPageRotation.none;

  @override
  PdfPageRenderCancellationToken createCancellationToken() => RasterCancellationToken();

  @override
  Future<List<PdfLink>> loadLinks({bool compact = false, bool enableAutoLinkDetection = true}) async => const [];

  @override
  Future<PdfPageRawText?> loadText() async => null;

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
  }) async {
    if (!isLoaded) return null;
    renderControl.requestedRegions.add((
      x: x,
      y: y,
      width: width,
      height: height,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    ));
    await renderControl.beforeRender();
    return PdfImage.createFromBgraData(Uint8List.fromList([255, 255, 255, 255]), width: 1, height: 1);
  }
}

class RasterRenderControl {
  Completer<void>? _gate;
  bool started = false;

  void block() => _gate = Completer<void>();

  void release() => _gate?.complete();

  Future<void> beforeRender() async {
    started = true;
    renderCount++;
    final gate = _gate;
    if (gate != null) await gate.future;
  }

  int renderCount = 0;
  final requestedRegions = <({int x, int y, int? width, int? height, double? fullWidth, double? fullHeight})>[];
}

class RasterCancellationToken implements PdfPageRenderCancellationToken {
  bool _isCanceled = false;

  @override
  bool get isCanceled => _isCanceled;

  @override
  void cancel() => _isCanceled = true;
}
