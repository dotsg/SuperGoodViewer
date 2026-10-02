import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class OutlineItem {
  final String title;
  final int level;
  final String anchor;
  final int lineNumber;
  final int? pageNumber;
  final double? docY;

  const OutlineItem({
    required this.title,
    required this.level,
    required this.anchor,
    required this.lineNumber,
    this.pageNumber,
    this.docY,
  });

  OutlineItem copyWith({
    String? title,
    int? level,
    String? anchor,
    int? lineNumber,
    int? pageNumber,
    double? docY,
  }) {
    return OutlineItem(
      title: title ?? this.title,
      level: level ?? this.level,
      anchor: anchor ?? this.anchor,
      lineNumber: lineNumber ?? this.lineNumber,
      pageNumber: pageNumber ?? this.pageNumber,
      docY: docY ?? this.docY,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutlineItem &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          level == other.level &&
          anchor == other.anchor &&
          lineNumber == other.lineNumber &&
          pageNumber == other.pageNumber &&
          docY == other.docY;

  @override
  int get hashCode => Object.hash(title, level, anchor, lineNumber, pageNumber, docY);

  @override
  String toString() => 'OutlineItem(H$level: $title, line: $lineNumber, page: $pageNumber, docY: $docY)';
}

/// Everything that belongs to one open document: its source, compiled PDF,
/// reading position, outline and file watcher.
///
/// Compiles, file reloads and remote image downloads finish asynchronously,
/// so they keep a reference to the session they started for and write their
/// results there, even if a different document is on screen by then.
class DocumentSession {
  String? filePath;
  String markdown = '';
  String title = 'Welcome';
  Uint8List? pdfBytes;
  bool isRawPdf = false;

  bool isCompiling = false;
  int compileGeneration = 0;
  bool hasPendingCompile = false;
  String? errorMessage;
  int degradedEquationCount = 0;
  List<String> degradedEquations = const [];

  double scrollRatio = 0.0;
  double scrollOffset = 0.0;
  int pageNumber = 1;
  double zoom = 1.0;
  bool isReloading = false;
  Timer? reloadingSafetyTimer;

  StreamSubscription<FileSystemEvent>? watcherSubscription;
  Timer? reloadDebounceTimer;
  DateTime? firstStreamEventTime;

  List<OutlineItem> outlineItems = [];
  int activeOutlineIndex = -1;
  Timer? activeOutlineLockTimer;
  bool isActiveOutlineLocked = false;
  OutlineItem? requestedJumpItem;

  void dispose() {
    reloadingSafetyTimer?.cancel();
    reloadDebounceTimer?.cancel();
    activeOutlineLockTimer?.cancel();
    watcherSubscription?.cancel();
  }
}
