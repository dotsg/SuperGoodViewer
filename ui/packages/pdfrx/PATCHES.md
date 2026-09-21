# SuperGoodViewer rendering patches

This directory vendors the runtime, assets, command-line utilities and tests of
[`pdfrx` 2.6.1](https://pub.dev/packages/pdfrx/versions/2.6.1), under its original
MIT license. `UPSTREAM.sha256` records the unmodified files copied from that
release. The workspace-only pubspec setting and unavailable screenshot entry
are removed so the package can resolve as a standalone path dependency.

Local changes:

- `lib/src/widgets/internals/page_text_loader.dart` and `page_text_cache.dart`:
  reuse upstream text formatting with a handle-free text snapshot; native pages
  with at least 8192 characters format on a separate isolate. Selection and
  `PdfTextSearcher` share cached and in-flight text through
  `PdfViewerController.loadPageText`; page/document invalidation rejects stale
  results and the document is retained during extraction. Small pages format
  inline; text extraction starts at the same time as before, without delaying
  raster readiness. See `docs/TEXT_LOADING_BENCHMARK.md` in the repository root
  for responsiveness measurements and the total-latency tradeoff.
- `lib/src/widgets/internals/raster_tile_cache.dart`: stable 512-pixel tile grid
  with full-width 512-pixel-high strips for narrow tall pages (at most 2048 physical
  pixels wide, height at least twice the width); grid dimensions are part of the cache key,
  two-pixel filtering gutters, serial native rendering, replaceable priority
  queue, cancellation, bounded failure retries and memory-accounted LRU; secondary
  `_pageIndex` lookup to eliminate global cache scans during draw, single `RasterTileRegion`
  allocation per candidate tile, and conditional sort bypass when scales are homogeneous.
- `lib/src/widgets/pdf_viewer.dart`: opt-in tiled rendering at device resolution,
  directional look-ahead, visible tiles before speculative work, raster-ready
  notification after paint, document/page invalidation and correct preview
  eviction only when the byte budget is exceeded; `removeCacheImagesIfCacheBytesExceedsLimit`
  lifted out of the per-page loop to execute once per layout pass, and `dist:` metric
  updated from current page center to viewport center (`targetRect.center`). Original
  partial rendering remains available for non-tiled viewers and the selection magnifier;
  optional `targetPageNumber` parameter added to `goToPosition` to preserve page tracking
  during intra-page offset and two-page spread navigation, committed only when the target page
  is actually on screen and the navigation has not been superseded (`_goTo` resolves its future
  on cancellation as well as completion, and the destination matrix is clamped to the document
  bounds); `layoutOrNull` safe getter and `setValueWithoutNormalization` added to `PdfViewerController`;
  visible tiles in tiled rendering filtered by exact `coreRect` bounds rather than gutter-expanded
  `rect` to prevent gutter overlaps from delaying `rasterReady`; reuse page layout across pan/raster rebuilds;
  re-evaluate on parent updates, resize, zoom, page status changes, document replacement and explicit
  controller invalidation; skip the page overlay scan when neither legacy link widgets nor custom page
  overlays are configured.
- `lib/src/widgets/pdf_viewer_params.dart`: `enableTiledRendering` and
  `onVisiblePagesRendered`, included in parameter equality/hash.
- `test/lazy_loading_test.dart`: correct a stale documentation reference.

Application integration and regression tests live in the parent app:

```sh
cd ui
flutter test test/raster_tile_cache_test.dart test/tiled_viewer_test.dart test/pdf_reader_test.dart
flutter test test/viewer_layout_cache_test.dart test/page_text_cache_test.dart
```

The opt-in `benchmark/raster_grid_benchmark_test.dart` compares fixed squares,
full-width strips and adaptive selection using native PDFium rasterization plus
Flutter image decoding. See `docs/RASTER_GRID_BENCHMARK.md` in the repository root
for measurements and limitations.

When updating upstream, compare these files against the recorded release,
reapply only patches still needed, and run the app's complete analysis/test
suite. Do not edit the global Pub cache. Upstream tests are retained as reference;
some require their original example assets or HTTP fixtures and are not part of
the app's default test command.
