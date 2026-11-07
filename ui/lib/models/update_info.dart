/// Represents the result of an update check against GitHub Releases.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String title;
  final String releaseNotes;
  final String htmlUrl;
  final String? assetUrl;
  final String? assetName;
  final int? assetSizeBytes;
  final DateTime? publishedAt;
  final bool hasUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.title,
    required this.releaseNotes,
    required this.htmlUrl,
    this.assetUrl,
    this.assetName,
    this.assetSizeBytes,
    this.publishedAt,
    required this.hasUpdate,
  });

  String get formattedSize {
    if (assetSizeBytes == null || assetSizeBytes! <= 0) return '';
    final mb = assetSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Extracts the concise highlight summary from release titles formatted like
  /// `v1.1.2 — Word/PPT 预览、Quick Look 与公式增强`.
  String get versionSummary {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'^v?\d+\.\d+\.\d+\s*(?:—|--|·|-|:|：)\s*(.+)$').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!.trim();
    }
    return '';
  }

  /// Returns release notes tailored for in-app display, stripping out manual
  /// download/installation instructions, `<details>` blocks, and trailing horizontal rules.
  String get displayReleaseNotes => cleanReleaseNotes(releaseNotes);

  static String cleanReleaseNotes(String raw) {
    if (raw.trim().isEmpty) return '';
    var text = raw.replaceAll('\r\n', '\n');

    // Cut off collapsible installation guide or horizontal divider before download guide
    final cutMarkers = [
      '\n<details>',
      '\n### 📦',
      '\n## 📦',
      '\n**Full Changelog**:',
      '\nFull Changelog:',
    ];
    for (final marker in cutMarkers) {
      final idx = text.indexOf(marker);
      if (idx != -1) {
        text = text.substring(0, idx);
      }
    }

    // Strip legacy boilerplate banner at the top if present
    text = text.replaceFirst(
      RegExp(
        r'^##\s*🚀[^\n]*\n+(?:\*\*只读 Markdown[^\n]*\n+)?(?:\*Publication-Grade[^\n]*\n+)?(?:\s*---\s*\n+)?',
      ),
      '',
    );

    // Strip trailing horizontal rule lines (`---`)
    text = text.replaceAll(RegExp(r'(\n\s*---\s*)+\s*$'), '');

    return text.trim();
  }

  @override
  String toString() =>
      'UpdateInfo(hasUpdate: $hasUpdate, current: $currentVersion, latest: $latestVersion, asset: $assetName, size: $formattedSize)';
}
