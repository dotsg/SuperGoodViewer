import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:pdfrx_engine/pdfrx_engine.dart';

/// A stable grid in physical pixels, independent of the scrolling viewport.
typedef RasterTileKey = ({int page, Rect pageRect, double scale, int column, int row});

class RasterTileRegion {
  RasterTileRegion(this.key);

  final RasterTileKey key;
  static const size = 512;
  static const gutter = 2;
  int get coreX => key.column * size;
  int get coreY => key.row * size;
  int get x => math.max(0, coreX - gutter);
  int get y => math.max(0, coreY - gutter);
  // Render a gutter on every edge so texture filtering does not sample
  // outside the bitmap when adjacent tiles are composited.
  int get width => math.min(coreX + size + gutter, (key.pageRect.width * key.scale).ceil()) - x;
  int get height => math.min(coreY + size + gutter, (key.pageRect.height * key.scale).ceil()) - y;
  Rect get coreRect => Rect.fromLTWH(
    key.pageRect.left + coreX / key.scale,
    key.pageRect.top + coreY / key.scale,
    size / key.scale,
    size / key.scale,
  ).intersect(key.pageRect);
  Rect get rect => Rect.fromLTWH(
    key.pageRect.left + x / key.scale,
    key.pageRect.top + y / key.scale,
    width / key.scale,
    height / key.scale,
  );

  static Iterable<RasterTileRegion> covering(int page, Rect pageRect, Rect target, double scale) sync* {
    if (!scale.isFinite || scale <= 0 || !pageRect.isFinite || !target.isFinite) return;
    final area = pageRect.intersect(target);
    if (area.isEmpty) return;
    final local = area.shift(-pageRect.topLeft);
    final left = (local.left * scale / size).floor();
    final top = (local.top * scale / size).floor();
    final right = (local.right * scale / size).ceil();
    final bottom = (local.bottom * scale / size).ceil();
    for (var row = top; row < bottom; row++) {
      for (var column = left; column < right; column++) {
        yield RasterTileRegion((page: page, pageRect: pageRect, scale: scale, column: column, row: row));
      }
    }
  }
}

class RasterTileJob {
  RasterTileJob(this.region);
  final RasterTileRegion region;
  bool canceled = false;
  PdfPageRenderCancellationToken? token;

  void cancel() {
    canceled = true;
    token?.cancel();
  }
}

/// One native render at a time, with a replaceable priority queue and byte LRU.
/// Updating the viewport retains in-flight work for tiles it still needs.
class RasterTileCache {
  RasterTileCache({required this.render, required this.onChanged});

  final Future<Image?> Function(RasterTileJob job) render;
  final void Function() onChanged;
  final _images = <RasterTileKey, Image>{};
  final _wanted = <RasterTileKey, RasterTileRegion>{};
  final _protected = <RasterTileKey>{};
  final _failures = <RasterTileKey, int>{};
  RasterTileJob? _running;
  bool _scheduled = false;
  bool _disposed = false;
  int _budget = 0;
  int bytes = 0;

  int get imageCount => _images.length;
  bool contains(RasterTileKey key) => _images.containsKey(key);

  void update(List<RasterTileRegion> ordered, Set<RasterTileKey> visible, int budget) {
    if (_disposed) return;
    _budget = math.max(0, budget);
    _wanted
      ..clear()
      ..addEntries(ordered.map((r) => MapEntry(r.key, r)));
    _protected
      ..clear()
      ..addAll(visible);
    _failures.removeWhere((key, _) => !_wanted.containsKey(key));
    final running = _running;
    if (running != null && !_wanted.containsKey(running.region.key)) running.cancel();
    // Touch visible entries, but retain recently visited offscreen entries until
    // the memory budget is actually exceeded.
    for (final key in visible) {
      final image = _images.remove(key);
      if (image != null) _images[key] = image;
    }
    _trim();
    _schedule();
  }

  void draw(Canvas canvas, int page, Rect pageRect, Rect target, double scale, FilterQuality quality) {
    // Retain lower-resolution tiles during zoom until replacements arrive.
    final entries =
        _images.entries
            .where(
              (e) => e.key.page == page && e.key.pageRect == pageRect && RasterTileRegion(e.key).rect.overlaps(target),
            )
            .toList()
          ..sort((a, b) => a.key.scale.compareTo(b.key.scale));
    canvas.save();
    canvas.clipRect(pageRect.intersect(target));
    for (final entry in entries) {
      final region = RasterTileRegion(entry.key);
      canvas.save();
      canvas.clipRect(region.coreRect);
      canvas.drawImageRect(
        entry.value,
        Rect.fromLTWH(0, 0, entry.value.width.toDouble(), entry.value.height.toDouble()),
        region.rect,
        Paint()..filterQuality = quality,
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _schedule() {
    if (_disposed || _scheduled || _running != null) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) _pump();
    });
  }

  Future<void> _pump() async {
    if (_running != null || _disposed) return;
    RasterTileRegion? next;
    for (final region in _wanted.values) {
      if (_images.containsKey(region.key) || (_failures[region.key] ?? 0) >= 2) continue;
      // Do not repeatedly render and evict speculative tiles under pressure.
      final cost = region.width * region.height * 4;
      if (!_protected.contains(region.key) && bytes + cost > _budget) {
        for (final key in _images.keys.toList()) {
          if (_wanted.containsKey(key) || _protected.contains(key)) continue;
          final old = _images.remove(key)!;
          bytes -= old.width * old.height * 4;
          old.dispose();
          if (bytes + cost <= _budget) break;
        }
        if (bytes + cost > _budget) continue;
      }
      next = region;
      break;
    }
    if (next == null) return;
    final job = _running = RasterTileJob(next);
    Image? image;
    try {
      image = await render(job);
      if (!_disposed && !job.canceled && image != null) {
        final old = _images.remove(next.key);
        if (old != null) {
          bytes -= old.width * old.height * 4;
          old.dispose();
        }
        bytes += image.width * image.height * 4;
        _images[next.key] = image;
        image = null;
        _failures.remove(next.key);
        _trim();
      } else if (!_disposed && !job.canceled) {
        _failures.update(next.key, (n) => n + 1, ifAbsent: () => 1);
      }
    } catch (_) {
      if (!_disposed && !job.canceled) {
        _failures.update(next.key, (n) => n + 1, ifAbsent: () => 1);
      }
    } finally {
      image?.dispose();
      _running = null;
      if (!_disposed) {
        onChanged();
        _schedule();
      }
    }
  }

  void _trim() {
    if (bytes <= _budget) return;
    for (final key in _images.keys.toList()) {
      if (_protected.contains(key)) continue;
      final image = _images.remove(key)!;
      bytes -= image.width * image.height * 4;
      image.dispose();
      if (bytes <= _budget) break;
    }
  }

  void invalidatePage(int page) {
    if (_running?.region.key.page == page) _running?.cancel();
    _wanted.removeWhere((key, _) => key.page == page);
    _failures.removeWhere((key, _) => key.page == page);
    for (final key in _images.keys.where((key) => key.page == page).toList()) {
      final image = _images.remove(key)!;
      bytes -= image.width * image.height * 4;
      image.dispose();
    }
  }

  void clear() {
    _running?.cancel();
    _wanted.clear();
    _protected.clear();
    _failures.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    bytes = 0;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
