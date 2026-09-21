import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../../pdfrx_flutter.dart';

/// Text and an optional vertical index, built together on the formatting isolate
/// for long pages. The index only narrows candidates; final hit testing retains
/// the viewer's original transformed rectangle, margin and edge semantics.
class IndexedPageText {
  IndexedPageText(this.text)
    : _index = text.fragments.length >= 512 ? TextFragmentIndex(text.fragments) : null;

  final PdfPageText text;
  final TextFragmentIndex? _index;

  @visibleForTesting
  bool get isIndexed => _index != null;

  @visibleForTesting
  TextFragmentIndex? get index => _index;

  bool hitTest({required PdfPage page, required Rect pageRect, required Offset position, required double margin}) {
    Iterable<PdfPageTextFragment> candidates = text.fragments;
    if (_index != null && page.height > 0 && pageRect.height > 0 && pageRect.isFinite && position.isFinite) {
      final query = Rect.fromCircle(center: position - pageRect.topLeft, radius: margin)
          .toPdfRect(page: page, scaledPageSize: pageRect.size);
      // Inverse transforms at fractional zoom can round the boundary a little.
      // Include these candidates and let the original contains() decide.
      final epsilon = math.max(query.bottom.abs(), query.top.abs()) * 1e-12 + 1e-7;
      candidates = _index.candidates(query.bottom - epsilon, query.top + epsilon).map((i) => text.fragments[i]);
    }
    for (final fragment in candidates) {
      if (fragment.bounds.toRectInDocument(page: page, pageRect: pageRect).inflate(margin).contains(position)) {
        return true;
      }
    }
    return false;
  }
}

/// Sorted lower bounds plus prefix upper bounds support overlapping fragments,
/// columns, vertical writing and arbitrary reading order without a grid's memory
/// duplication for tall fragments. Malformed coordinates fall back to a scan.
class TextFragmentIndex {
  TextFragmentIndex(List<PdfPageTextFragment> fragments) : _count = fragments.length {
    _finite = fragments.every((f) => f.bounds.bottom.isFinite && f.bounds.top.isFinite);
    if (!_finite) return;
    final order = List<int>.generate(_count, (i) => i)
      ..sort((a, b) => fragments[a].bounds.bottom.compareTo(fragments[b].bounds.bottom));
    _order = Int32List.fromList(order);
    _bottoms = Float64List(_count);
    _prefixTops = Float64List(_count);
    var top = double.negativeInfinity;
    for (var i = 0; i < _count; i++) {
      final bounds = fragments[order[i]].bounds;
      _bottoms[i] = bounds.bottom;
      top = math.max(top, bounds.top);
      _prefixTops[i] = top;
    }
  }

  final int _count;
  late final bool _finite;
  late final Int32List _order;
  late final Float64List _bottoms, _prefixTops;

  Iterable<int> candidates(double bottom, double top) sync* {
    if (!_finite || !bottom.isFinite || !top.isFinite) {
      for (var i = 0; i < _count; i++) {
        yield i;
      }
      return;
    }
    var left = 0, right = _count;
    while (left < right) {
      final middle = (left + right) >> 1;
      if (_prefixTops[middle] < bottom) {
        left = middle + 1;
      } else {
        right = middle;
      }
    }
    for (var i = left; i < _count && _bottoms[i] <= top; i++) {
      yield _order[i];
    }
  }
}
