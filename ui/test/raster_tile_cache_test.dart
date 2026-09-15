import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/src/widgets/internals/raster_tile_cache.dart';

Image image() {
  final recorder = PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff123456), BlendMode.src);
  final picture = recorder.endRecording();
  final result = picture.toImageSync(16, 16);
  picture.dispose();
  return result;
}

RasterTileRegion region(int row) => RasterTileRegion((
  page: 1,
  pageRect: const Rect.fromLTWH(0, 0, 720, 40000),
  scale: 2,
  column: 0,
  row: row,
  grid: RasterTileRegion.defaultGrid,
));

Future<void> drain() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('scrolling within a grid cell preserves physical tile identities', () {
    const page = Rect.fromLTWH(0, 0, 720, 40000);
    final first = RasterTileRegion.covering(
      1,
      page,
      const Rect.fromLTWH(0, 10, 720, 600),
      2,
      grid: RasterTileRegion.defaultGrid,
    ).toList();
    final shifted = RasterTileRegion.covering(
      1,
      page,
      const Rect.fromLTWH(0, 11, 720, 600),
      2,
      grid: RasterTileRegion.defaultGrid,
    ).toList();
    expect(shifted.map((r) => r.key), first.map((r) => r.key));
    expect(first.every((r) => r.width <= 516 && r.height <= 516), isTrue);
    expect(first.first.rect.overlaps(first[1].rect), isTrue, reason: 'Filtering edges must overlap');
  });

  test('narrow long pages use stable strips and zoomed pages retain bounded square tiles', () {
    const page = Rect.fromLTWH(20, 30, 800, 40000);
    const viewport = Rect.fromLTWH(20, 1000, 800, 600);
    final strips = RasterTileRegion.covering(1, page, viewport, 2).toList();
    expect(strips.every((r) => r.key.column == 0 && r.width == 1600 && r.height <= 516), isTrue);
    final moved = RasterTileRegion.covering(1, page, viewport.translate(1, 1), 2).toList();
    expect(moved.map((r) => r.key), strips.map((r) => r.key));
    expect(strips.first.coreRect.bottom, strips[1].coreRect.top);
    expect(strips.first.rect.overlaps(strips[1].rect), isTrue);

    final zoomed = RasterTileRegion.covering(1, page, viewport, 4).toList();
    expect(zoomed.every((r) => r.width <= 516 && r.height <= 516), isTrue);
    expect(RasterTileRegion.gridFor(const Rect.fromLTWH(0, 0, 595, 842), 2), RasterTileRegion.defaultGrid);
    // Alternate grid strategies must not alias cached images at the same scale.
    final square = RasterTileRegion.covering(1, page, viewport, 2, grid: RasterTileRegion.defaultGrid).first;
    expect(square.key, isNot(strips.first.key));
  });

  test('in-flight tile is retained while viewport priority changes', () async {
    final jobs = <RasterTileJob>[];
    final gates = <Completer<Image?>>[];
    final cache = RasterTileCache(
      render: (job) {
        jobs.add(job);
        final gate = Completer<Image?>();
        gates.add(gate);
        return gate.future;
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    final a = region(0), b = region(1), c = region(2);
    cache.update([a, b], {a.key, b.key}, 16 * 1024 * 1024);
    await drain();
    for (var i = 0; i < 20; i++) {
      cache.update([c, a, b], {a.key, c.key}, 16 * 1024 * 1024);
      await drain();
    }
    expect(jobs.length, 1);
    expect(jobs.first.canceled, isFalse);
    gates.first.complete(image());
    await drain();
    expect(jobs[1].region.key, c.key, reason: 'New visible work precedes old speculative work');
    gates[1].complete(image());
    await drain();
    gates[2].complete(image());
    await drain();
    expect(cache.imageCount, 3);
  });

  test('offscreen images survive under budget and reverse scroll reuses them', () async {
    var renders = 0;
    final cache = RasterTileCache(
      render: (_) async {
        renders++;
        return image();
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    final a = region(0), b = region(8);
    cache.update([a], {a.key}, 8192);
    await drain();
    cache.update([b], {b.key}, 8192);
    await drain();
    expect(cache.contains(a.key), isTrue);
    cache.update([a], {a.key}, 8192);
    await drain();
    expect(renders, 2);
  });

  test('memory pressure evicts old tiles but keeps visible tiles', () async {
    final cache = RasterTileCache(render: (_) async => image(), onChanged: () {});
    addTearDown(cache.dispose);
    final a = region(0), b = region(1);
    cache.update([a], {a.key}, 1024);
    await drain();
    cache.update([b], {b.key}, 1024);
    await drain();
    expect(cache.contains(a.key), isFalse);
    expect(cache.contains(b.key), isTrue);
    expect(cache.bytes, 1024);
  });

  test('late native result cannot repopulate a replaced document', () async {
    final gate = Completer<Image?>();
    late RasterTileJob job;
    final cache = RasterTileCache(
      render: (j) {
        job = j;
        return gate.future;
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    final a = region(0);
    cache.update([a], {a.key}, 8192);
    await drain();
    cache.clear();
    expect(job.canceled, isTrue);
    gate.complete(image());
    await drain();
    expect(cache.imageCount, 0);
    expect(cache.bytes, 0);
  });

  test('a permanently failing tile has bounded retries', () async {
    var renders = 0;
    final cache = RasterTileCache(
      render: (_) async {
        renders++;
        return null;
      },
      onChanged: () {},
    );
    addTearDown(cache.dispose);
    final a = region(0);
    for (var i = 0; i < 10; i++) {
      cache.update([a], {a.key}, 8192);
      await drain();
    }
    expect(renders, 2);
    cache.invalidatePage(1);
    cache.update([a], {a.key}, 8192);
    await drain();
    expect(renders, 4, reason: 'A page update permits rendering again');
  });
}
