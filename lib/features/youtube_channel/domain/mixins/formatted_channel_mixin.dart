/// Mixin for channel formatting methods
/// Provides common formatting for subscriber count, video count, and thumbnails
mixin FormattedChannelMixin {
  // Abstract getters that must be implemented by classes using this mixin
  int? get subscriberCount;
  int? get videoCount;
  String? get thumbnail;

  /// Format subscriber count (e.g., "1.2M subscribers")
  String get formattedSubscriberCount {
    final count = subscriberCount;
    if (count == null || count == 0) return '';

    if (count >= 1000000) {
      final millions = count / 1000000;
      return '${millions.toStringAsFixed(millions >= 10 ? 0 : 1)}M subscribers';
    } else if (count >= 1000) {
      final thousands = count / 1000;
      return '${thousands.toStringAsFixed(thousands >= 10 ? 0 : 1)}K subscribers';
    }
    return '$count subscribers';
  }

  /// Format video count (e.g., "50 videos")
  String get formattedVideoCount {
    final count = videoCount;
    if (count == null || count == 0) return '';
    return '$count videos';
  }

  /// Get high quality thumbnail URL
  String? get highQualityThumbnail {
    if (thumbnail == null) return null;

    // If already maxres, return as is
    if (thumbnail!.contains('maxresdefault')) return thumbnail;

    // Try to upgrade to maxresdefault
    return thumbnail!
        .replaceAll('hqdefault', 'maxresdefault')
        .replaceAll('mqdefault', 'maxresdefault')
        .replaceAll('sddefault', 'maxresdefault');
  }
}
