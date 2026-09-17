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

  @override
  String toString() =>
      'UpdateInfo(hasUpdate: $hasUpdate, current: $currentVersion, latest: $latestVersion, asset: $assetName, size: $formattedSize)';
}
