import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/downloads/domain/services/gallery_default_quality_selector.dart';

void main() {
  Quality quality({
    required String encryptedUrl,
    MediaType mediaType = MediaType.image,
    String text = 'Image',
  }) => Quality(
    qualityText: text,
    size: '',
    encryptedUrl: encryptedUrl,
    mediaType: mediaType,
  );

  VideoInfo videoInfo({
    required List<Quality> qualities,
    String downloadMethod = 'gallerydl',
  }) => VideoInfo(
    url: 'https://example.com/post',
    title: 'Gallery',
    availableQualities: qualities,
    downloadMethod: downloadMethod,
  );

  group('GalleryDefaultQualitySelector', () {
    test('selects all-images quality for pure gallery-dl image carousel', () {
      final allImages = quality(
        encryptedUrl: 'gallerydl:all:3',
        text: 'All 3 images',
      );

      final selected = GalleryDefaultQualitySelector.allImagesQuality(
        videoInfo(
          qualities: [
            allImages,
            quality(encryptedUrl: 'gallerydl:1'),
            quality(encryptedUrl: 'gallerydl:2'),
          ],
        ),
      );

      expect(selected, same(allImages));
    });

    test('keeps dialog path for mixed image and video galleries', () {
      final selected = GalleryDefaultQualitySelector.allImagesQuality(
        videoInfo(
          qualities: [
            quality(encryptedUrl: 'gallerydl:all:2', text: 'All 2 images'),
            quality(encryptedUrl: 'gallerydl:1'),
            quality(
              encryptedUrl: 'gallerydl:2',
              mediaType: MediaType.video,
              text: 'Video 2',
            ),
          ],
        ),
      );

      expect(selected, isNull);
    });

    test('ignores non-gallery-dl results', () {
      final selected = GalleryDefaultQualitySelector.allImagesQuality(
        videoInfo(
          downloadMethod: 'ytdlp',
          qualities: [
            quality(encryptedUrl: 'gallerydl:all:2', text: 'All 2 images'),
          ],
        ),
      );

      expect(selected, isNull);
    });

    test('returns null when no all-images option is available', () {
      final selected = GalleryDefaultQualitySelector.allImagesQuality(
        videoInfo(
          qualities: [
            quality(encryptedUrl: 'gallerydl:1'),
            quality(encryptedUrl: 'gallerydl:2'),
          ],
        ),
      );

      expect(selected, isNull);
    });
  });
}
