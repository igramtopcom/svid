import 'package:flutter_test/flutter_test.dart';
import 'package:ssvid/core/utils/platform_detector.dart';
import 'package:ssvid/features/downloads/domain/entities/video_preview.dart';

void main() {
  // Sample preview reused across tests.
  VideoPreview sample({
    String rawUrl = 'https://youtube.com/watch?v=abcdef12345',
    VideoPlatform platform = VideoPlatform.youtube,
    UrlType urlType = UrlType.video,
    String? itemId = 'abcdef12345',
    String? title = 'Sample Title',
    String? uploader = 'Sample Channel',
    String? thumbnailUrl =
        'https://img.youtube.com/vi/abcdef12345/maxresdefault.jpg',
    Duration? startTimestamp,
    String? playlistId,
    bool hasFetchedMetadata = true,
  }) {
    return VideoPreview(
      rawUrl: rawUrl,
      platform: platform,
      urlType: urlType,
      itemId: itemId,
      title: title,
      uploader: uploader,
      thumbnailUrl: thumbnailUrl,
      startTimestamp: startTimestamp,
      playlistId: playlistId,
      hasFetchedMetadata: hasFetchedMetadata,
    );
  }

  group('VideoPreview equality', () {
    test('identical instances are equal', () {
      final a = sample();
      final b = sample();
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different rawUrl breaks equality', () {
      final a = sample(rawUrl: 'https://youtube.com/watch?v=aaaaaaaaaaa');
      final b = sample(rawUrl: 'https://youtube.com/watch?v=bbbbbbbbbbb');
      expect(a, isNot(equals(b)));
    });

    test('different platform breaks equality', () {
      final a = sample(platform: VideoPlatform.youtube);
      final b = sample(platform: VideoPlatform.tiktok);
      expect(a, isNot(equals(b)));
    });

    test('different title breaks equality', () {
      final a = sample(title: 'Title A');
      final b = sample(title: 'Title B');
      expect(a, isNot(equals(b)));
    });

    test('null fields equal each other', () {
      final a = sample(title: null);
      final b = sample(title: null);
      expect(a, equals(b));
    });

    test('null vs non-null breaks equality', () {
      final a = sample(title: null);
      final b = sample(title: 'X');
      expect(a, isNot(equals(b)));
    });

    test('hasFetchedMetadata difference breaks equality', () {
      final a = sample(hasFetchedMetadata: true);
      final b = sample(hasFetchedMetadata: false);
      expect(a, isNot(equals(b)));
    });

    test('Duration timestamps compared correctly', () {
      final a = sample(startTimestamp: const Duration(seconds: 60));
      final b = sample(startTimestamp: const Duration(seconds: 60));
      final c = sample(startTimestamp: const Duration(seconds: 90));
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('identical reference is equal', () {
      final a = sample();
      // ignore: unrelated_type_equality_checks
      expect(identical(a, a), isTrue);
      expect(a == a, isTrue);
    });
  });

  group('VideoPreview JSON serialization', () {
    test('round-trip preserves all fields', () {
      final original = sample(
        startTimestamp: const Duration(seconds: 120),
        playlistId: 'PLxxxxx',
      );

      final json = original.toJson();
      final restored = VideoPreview.fromJson(json);

      expect(restored, equals(original));
    });

    test('null fields round-trip correctly', () {
      final original = sample(
        itemId: null,
        title: null,
        uploader: null,
        thumbnailUrl: null,
        startTimestamp: null,
        playlistId: null,
      );

      final json = original.toJson();
      final restored = VideoPreview.fromJson(json);

      expect(restored, equals(original));
      expect(restored.itemId, isNull);
      expect(restored.startTimestamp, isNull);
    });

    test('Duration serializes as microseconds int', () {
      final preview = sample(
        startTimestamp: const Duration(seconds: 60),
      );
      final json = preview.toJson();
      expect(json['startTimestampMicros'], 60 * 1000 * 1000);
    });

    test('platform and urlType serialize as enum names', () {
      final preview = sample();
      final json = preview.toJson();
      expect(json['platform'], 'youtube');
      expect(json['urlType'], 'video');
    });

    test('unknown enum value falls back to safe default (forward compat)', () {
      final json = {
        'rawUrl': 'https://example.com',
        'platform': 'futurePlatform99', // unknown value
        'urlType': 'futureType99',
        'hasFetchedMetadata': false,
      };

      final restored = VideoPreview.fromJson(json);
      expect(restored.platform, VideoPlatform.unknown);
      expect(restored.urlType, UrlType.unknown);
    });

    test('missing hasFetchedMetadata defaults to false', () {
      final json = {
        'rawUrl': 'https://example.com',
        'platform': 'youtube',
        'urlType': 'video',
      };

      final restored = VideoPreview.fromJson(json);
      expect(restored.hasFetchedMetadata, isFalse);
    });

    test('JSON output is map-like for MethodChannel transport', () {
      final preview = sample();
      final json = preview.toJson();

      // All values must be JSON-encodable primitives or nullable strings/ints
      for (final entry in json.entries) {
        final value = entry.value;
        expect(
          value == null ||
              value is String ||
              value is int ||
              value is bool,
          isTrue,
          reason: 'Field ${entry.key} has non-JSON-primitive type ${value.runtimeType}',
        );
      }
    });
  });

  group('VideoPreview helpers', () {
    test('isPreviewable true for video', () {
      final p = sample(urlType: UrlType.video);
      expect(p.isPreviewable, isTrue);
    });

    test('isPreviewable false for playlist', () {
      final p = sample(urlType: UrlType.playlist);
      expect(p.isPreviewable, isFalse);
    });

    test('isPreviewable false for channel/notUrl/unknown', () {
      expect(sample(urlType: UrlType.channel).isPreviewable, isFalse);
      expect(sample(urlType: UrlType.notUrl).isPreviewable, isFalse);
      expect(sample(urlType: UrlType.unknown).isPreviewable, isFalse);
    });

    test('hasMinimalDisplay true with platform + thumbnail', () {
      final p = sample(thumbnailUrl: 'https://example.com/thumb.jpg');
      expect(p.hasMinimalDisplay, isTrue);
    });

    test('hasMinimalDisplay false when platform unknown', () {
      final p = sample(platform: VideoPlatform.unknown);
      expect(p.hasMinimalDisplay, isFalse);
    });

    test('hasMinimalDisplay false when no thumbnail', () {
      final p = sample(thumbnailUrl: null);
      expect(p.hasMinimalDisplay, isFalse);
    });
  });

  group('VideoPreview copyWith', () {
    test('no args returns equal instance', () {
      final a = sample();
      final b = a.copyWith();
      expect(b, equals(a));
    });

    test('single field override changes only that field', () {
      final a = sample(title: 'Original');
      final b = a.copyWith(title: 'Updated');
      expect(b.title, 'Updated');
      expect(b.rawUrl, a.rawUrl);
      expect(b.platform, a.platform);
    });

    test('hasFetchedMetadata can be flipped', () {
      final a = sample(hasFetchedMetadata: false);
      final b = a.copyWith(hasFetchedMetadata: true);
      expect(b.hasFetchedMetadata, isTrue);
    });
  });

  group('VideoPreview toString', () {
    test('contains key identifying fields', () {
      final p = sample();
      final s = p.toString();
      expect(s, contains('youtube'));
      expect(s, contains('video'));
      expect(s, contains('abcdef12345'));
    });
  });
}
