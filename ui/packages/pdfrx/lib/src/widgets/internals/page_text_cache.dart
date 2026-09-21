import 'dart:async';
import 'dart:collection';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'page_text_loader.dart';
import 'indexed_page_text.dart';

/// Viewer-owned text shared by selection and search, including in-flight work.
/// Invalidated requests may finish, but cannot populate a replacement page.
///
/// Features:
/// - Priority queue: Interactive/visible requests run before background search tasks.
/// - LRU cache bounding: Caps retained pages to [maxCachedPages] to prevent full-document search leaks.
/// - In-flight deduplication (coalescing) and stale request invalidation.
class PageTextCache {
  PageTextCache({this.maxCachedPages = 100});

  final int maxCachedPages;
  final _texts = <int, IndexedPageText>{};
  final _requests = <int, _TextRequest>{};

  final _pendingPriority = ListQueue<_TextRequestItem>();
  final _pendingBackground = ListQueue<_TextRequestItem>();
  bool _isProcessing = false;

  @visibleForTesting
  int get cachedCount => _texts.length;

  /// Pure lookup without mutation or cache reordering on high-frequency paint paths.
  PdfPageText? operator [](int pageNumber) => _texts[pageNumber]?.text;

  /// Lookup page text with optional LRU refresh.
  PdfPageText? get(int pageNumber, {bool touch = false}) {
    final entry = _texts[pageNumber];
    if (entry != null) {
      if (touch) _touch(pageNumber);
      return entry.text;
    }
    return null;
  }

  void _touch(int pageNumber) {
    final entry = _texts.remove(pageNumber);
    if (entry != null) {
      _texts[pageNumber] = entry;
    }
  }

  bool hitTest({required PdfPage page, required Rect pageRect, required Offset position, required double margin}) =>
      _texts[page.pageNumber]?.hitTest(page: page, pageRect: pageRect, position: position, margin: margin) ?? false;

  Future<PdfPageText?> load(PdfPage page, {VoidCallback? onLoaded, bool isPriority = false}) {
    if (!page.isLoaded) return Future.value(null);
    final cached = _texts[page.pageNumber];
    if (cached != null) {
      _touch(page.pageNumber);
      return Future.value(cached.text);
    }
    final pending = _requests[page.pageNumber];
    if (pending != null) {
      if (onLoaded != null) pending.callbacks.add(onLoaded);
      if (isPriority && !pending.isPriority) {
        pending.isPriority = true;
        _TextRequestItem? found;
        for (final item in _pendingBackground) {
          if (identical(item.request, pending)) {
            found = item;
            break;
          }
        }
        if (found != null) {
          _pendingBackground.remove(found);
          _pendingPriority.add(found);
        }
      }
      return pending.completer.future;
    }
    final request = _TextRequest(isPriority: isPriority);
    if (onLoaded != null) request.callbacks.add(onLoaded);
    _requests[page.pageNumber] = request;
    final item = _TextRequestItem(page, request);
    if (isPriority) {
      _pendingPriority.add(item);
    } else {
      _pendingBackground.add(item);
    }
    _scheduleProcessing();
    return request.completer.future;
  }

  void _scheduleProcessing() {
    if (_isProcessing) return;
    _isProcessing = true;
    unawaited(_processQueue());
  }

  Future<void> _processQueue() async {
    while (true) {
      _TextRequestItem? next;
      if (_pendingPriority.isNotEmpty) {
        next = _pendingPriority.removeFirst();
      } else if (_pendingBackground.isNotEmpty) {
        next = _pendingBackground.removeFirst();
      } else {
        break;
      }
      if (identical(_requests[next.page.pageNumber], next.request)) {
        await _execute(next.page, next.request);
      } else {
        if (!next.request.completer.isCompleted) {
          next.request.completer.complete(null);
        }
      }
    }
    _isProcessing = false;
  }

  Future<void> _execute(PdfPage page, _TextRequest request) async {
    bool isCurrent() => identical(_requests[page.pageNumber], request);
    if (!isCurrent()) {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
      return;
    }
    IndexedPageText? text;
    try {
      text = await loadIndexedPageText(page);
    } catch (error, stack) {
      if (isCurrent()) {
        _requests.remove(page.pageNumber);
        request.completer.completeError(error, stack);
      } else {
        if (!request.completer.isCompleted) {
          request.completer.complete(null);
        }
      }
      return;
    }

    final current = isCurrent();
    if (current) {
      _requests.remove(page.pageNumber);
      _texts.remove(page.pageNumber);
      _texts[page.pageNumber] = text;
      while (_texts.length > maxCachedPages) {
        _texts.remove(_texts.keys.first);
      }
      request.completer.complete(text.text);
      for (final callback in request.callbacks) {
        callback();
      }
    } else {
      if (!request.completer.isCompleted) {
        request.completer.complete(null);
      }
    }
  }

  void _dropQueued(bool Function(_TextRequestItem) match) {
    for (final queue in [_pendingPriority, _pendingBackground]) {
      final matches = queue.where(match).toList();
      for (final item in matches) {
        if (!item.request.completer.isCompleted) {
          item.request.completer.complete(null);
        }
      }
      queue.removeWhere(match);
    }
  }

  void invalidatePage(int pageNumber) {
    _texts.remove(pageNumber);
    final req = _requests.remove(pageNumber);
    if (req != null && !req.completer.isCompleted) {
      req.completer.complete(null);
    }
    _dropQueued((item) => item.page.pageNumber == pageNumber);
  }

  void clear() {
    _texts.clear();
    for (final req in _requests.values) {
      if (!req.completer.isCompleted) {
        req.completer.complete(null);
      }
    }
    _requests.clear();
    _dropQueued((_) => true);
  }
}

class _TextRequest {
  _TextRequest({this.isPriority = false});
  bool isPriority;
  final completer = Completer<PdfPageText?>();
  // Uses Set<VoidCallback> to deduplicate identical tear-offs (e.g. State._invalidate passed on successive frames).
  final callbacks = <VoidCallback>{};
}

class _TextRequestItem {
  _TextRequestItem(this.page, this.request);
  final PdfPage page;
  final _TextRequest request;
}
