# SuperGoodViewer rendering patches

This directory vendors the runtime, assets, command-line utilities and tests of
[`pdfrx` 2.6.1](https://pub.dev/packages/pdfrx/versions/2.6.1), under its original
MIT license. `UPSTREAM.sha256` records the unmodified files copied from that
release. The workspace-only pubspec setting and unavailable screenshot entry
are removed so the package can resolve as a standalone path dependency.

Local changes:

- `lib/src/widgets/internals/raster_tile_cache.dart`: stable 512-pixel tile grid,
  two-pixel filtering gutters, serial native rendering, replaceable priority
  queue, cancellation, bounded failure retries and memory-accounted LRU.
- `lib/src/widgets/pdf_viewer.dart`: opt-in tiled rendering at device resolution,
  directional look-ahead, visible tiles before speculative work, raster-ready
  notification after paint, document/page invalidation and correct preview
  eviction only when the byte budget is exceeded. Original partial rendering
  remains available for non-tiled viewers and the selection magnifier.
- `lib/src/widgets/pdf_viewer_params.dart`: `enableTiledRendering` and
  `onVisiblePagesRendered`, included in parameter equality/hash.
- `test/lazy_loading_test.dart`: correct a stale documentation reference.

Application integration and regression tests live in the parent app:

```sh
cd ui
flutter test test/raster_tile_cache_test.dart test/tiled_viewer_test.dart test/pdf_reader_test.dart
```

When updating upstream, compare these files against the recorded release,
reapply only patches still needed, and run the app's complete analysis/test
suite. Do not edit the global Pub cache. Upstream tests are retained as reference;
some require their original example assets or HTTP fixtures and are not part of
the app's default test command.
