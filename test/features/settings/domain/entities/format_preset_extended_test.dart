import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';

void main() {
  group('FormatPresetExtended — JSON round-trip', () {
    test('full record survives toJson + fromJson', () {
      final original = FormatPresetExtended(
        id: 'auto',
        name: 'Tự động (cao nhất)',
        isBuiltIn: true,
        maxResolution: 0,
        videoCodec: 'auto',
        audioCodec: 'auto',
        containerFormat: 'auto',
        fpsPreference: 'auto',
        audioOnly: false,
        audioBitrate: null,
        fallbackBehavior: FormatPresetFallback.nearest,
        saveLocation: null,
        subtitlesEnabled: null,
        embedThumbnail: null,
        embedMetadata: null,
        embedChapters: null,
        schemaVersion: 1,
        createdAt: DateTime.utc(2026, 5, 5),
      );

      final restored = FormatPresetExtended.fromJson(original.toJson());

      expect(restored.id, 'auto');
      expect(restored.name, 'Tự động (cao nhất)');
      expect(restored.isBuiltIn, true);
      expect(restored.maxResolution, 0);
      expect(restored.fallbackBehavior, FormatPresetFallback.nearest);
      expect(restored.schemaVersion, 1);
      expect(restored.createdAt.toUtc(), DateTime.utc(2026, 5, 5));
    });
  });

  group('FormatPresetExtended — backward-compat parse', () {
    test('legacy 7-field record (no UUID, no isBuiltIn) parses with defaults',
        () {
      // Mimics a v1.x SharedPreferences record before the v2 migration runs.
      final legacyJson = <String, dynamic>{
        'name': '1080p MP4',
        'maxResolution': 1080,
        'videoCodec': 'h264',
        'audioCodec': 'aac',
        'containerFormat': 'mp4',
        'fpsPreference': 'auto',
        'createdAt': '2025-12-01T10:00:00.000Z',
      };

      final parsed = FormatPresetExtended.fromJson(legacyJson);

      expect(parsed.name, '1080p MP4');
      expect(parsed.id, ''); // empty until migration assigns UUID
      expect(parsed.isBuiltIn, false);
      expect(parsed.audioOnly, false);
      expect(parsed.audioBitrate, null);
      expect(parsed.fallbackBehavior, FormatPresetFallback.nearest);
      expect(parsed.saveLocation, null);
      expect(parsed.schemaVersion, 1); // defaults to current
    });

    test('v2 record with extra unknown fields is tolerated', () {
      // Forward-compat: v2.x reading a v2.1 record with new fields.
      final futureJson = <String, dynamic>{
        'id': 'abc-123',
        'name': 'Future Preset',
        'isBuiltIn': false,
        'maxResolution': 720,
        'videoCodec': 'auto',
        'audioCodec': 'auto',
        'containerFormat': 'mp4',
        'fpsPreference': '60',
        'createdAt': '2026-05-05T00:00:00.000Z',
        'unknownFutureField': {'nested': true},
      };

      expect(
        () => FormatPresetExtended.fromJson(futureJson),
        returnsNormally,
      );
    });
  });

  group('FormatPresetExtended — copyWith', () {
    final base = FormatPresetExtended(
      id: 'base',
      name: 'Base',
      isBuiltIn: false,
      maxResolution: 1080,
      videoCodec: 'h264',
      audioCodec: 'aac',
      containerFormat: 'mp4',
      fpsPreference: 'auto',
      audioBitrate: 320,
      saveLocation: '/Downloads/Svid',
      createdAt: DateTime.utc(2026, 5, 5),
    );

    test('non-nullable field replacement', () {
      final updated = base.copyWith(name: 'Renamed');
      expect(updated.name, 'Renamed');
      expect(updated.id, 'base');
      expect(updated.maxResolution, 1080);
    });

    test('nullable field can be set to null explicitly', () {
      final cleared = base.copyWith(audioBitrate: null);
      expect(cleared.audioBitrate, isNull);
      expect(base.audioBitrate, 320); // original untouched
    });

    test('nullable field unchanged when not passed', () {
      final touched = base.copyWith(name: 'X');
      expect(touched.audioBitrate, 320);
      expect(touched.saveLocation, '/Downloads/Svid');
    });
  });

  group('FormatPresetFallback enum', () {
    test('round-trip through string', () {
      for (final v in FormatPresetFallback.values) {
        expect(FormatPresetFallback.fromJson(v.name), v);
      }
    });

    test('unknown value falls back to nearest', () {
      expect(FormatPresetFallback.fromJson('garbage'), FormatPresetFallback.nearest);
      expect(FormatPresetFallback.fromJson(null), FormatPresetFallback.nearest);
      expect(FormatPresetFallback.fromJson(42), FormatPresetFallback.nearest);
    });
  });
}
