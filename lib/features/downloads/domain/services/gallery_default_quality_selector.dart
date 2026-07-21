import '../entities/video_info.dart';

/// Centralizes default selection for gallery-dl results.
class GalleryDefaultQualitySelector {
  const GalleryDefaultQualitySelector._();

  /// Pure image carousels should default to the explicit all-images quality.
  /// Mixed image/video galleries return null so the caller surfaces the picker.
  static Quality? allImagesQuality(VideoInfo videoInfo) {
    if (videoInfo.downloadMethod != 'gallerydl') return null;

    final qualities = videoInfo.availableQualities;
    if (qualities.isEmpty) return null;
    if (qualities.any((q) => q.mediaType != MediaType.image)) return null;

    for (final quality in qualities) {
      if (quality.encryptedUrl.startsWith('gallerydl:all:')) {
        return quality;
      }
    }
    return null;
  }
}
