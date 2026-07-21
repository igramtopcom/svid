import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ssvid/features/settings/data/datasources/format_presets_service.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  group('FormatPreset', () {
    test('toJson and fromJson roundtrip', () {
      final preset = FormatPreset(
        name: 'Test Preset',
        maxResolution: 1080,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime(2026, 3, 15),
      );

      final json = preset.toJson();
      final restored = FormatPreset.fromJson(json);

      expect(restored.name, 'Test Preset');
      expect(restored.maxResolution, 1080);
      expect(restored.videoCodec, 'h264');
      expect(restored.audioCodec, 'aac');
      expect(restored.containerFormat, 'mp4');
      expect(restored.fpsPreference, 'auto');
      expect(restored.createdAt, DateTime(2026, 3, 15));
    });

    test('toJson contains all fields', () {
      final preset = FormatPreset(
        name: 'Full',
        maxResolution: 2160,
        videoCodec: 'vp9',
        audioCodec: 'opus',
        containerFormat: 'webm',
        fpsPreference: 'fps60',
        createdAt: DateTime(2026, 1, 1),
      );

      final json = preset.toJson();
      expect(json.keys, containsAll([
        'name', 'maxResolution', 'videoCodec', 'audioCodec',
        'containerFormat', 'fpsPreference', 'createdAt',
      ]));
    });
  });

  group('FormatPresetsNotifier', () {
    test('starts empty', () {
      final notifier = FormatPresetsNotifier(prefs);
      expect(notifier.state, isEmpty);
    });

    test('add preset', () async {
      final notifier = FormatPresetsNotifier(prefs);
      await notifier.add(FormatPreset(
        name: 'My Preset',
        maxResolution: 720,
        videoCodec: 'h264',
        audioCodec: 'aac',
        containerFormat: 'mp4',
        fpsPreference: 'auto',
        createdAt: DateTime.now(),
      ));

      expect(notifier.state, hasLength(1));
      expect(notifier.state.first.name, 'My Preset');
      expect(notifier.state.first.maxResolution, 720);
    });

    test('add multiple presets', () async {
      final notifier = FormatPresetsNotifier(prefs);
      await notifier.add(_makePreset('A'));
      await notifier.add(_makePreset('B'));
      await notifier.add(_makePreset('C'));

      expect(notifier.state, hasLength(3));
    });

    test('remove preset by name', () async {
      final notifier = FormatPresetsNotifier(prefs);
      await notifier.add(_makePreset('Keep'));
      await notifier.add(_makePreset('Remove'));
      await notifier.add(_makePreset('AlsoKeep'));

      await notifier.remove('Remove');

      expect(notifier.state, hasLength(2));
      expect(notifier.state.map((p) => p.name), containsAll(['Keep', 'AlsoKeep']));
    });

    test('remove non-existent preset does nothing', () async {
      final notifier = FormatPresetsNotifier(prefs);
      await notifier.add(_makePreset('Existing'));
      await notifier.remove('NonExistent');

      expect(notifier.state, hasLength(1));
    });

    test('persists across instances', () async {
      final notifier1 = FormatPresetsNotifier(prefs);
      await notifier1.add(_makePreset('Persisted'));

      // New notifier with same prefs should load from storage
      final notifier2 = FormatPresetsNotifier(prefs);
      expect(notifier2.state, hasLength(1));
      expect(notifier2.state.first.name, 'Persisted');
    });
  });
}

FormatPreset _makePreset(String name) => FormatPreset(
      name: name,
      maxResolution: 1080,
      videoCodec: 'h264',
      audioCodec: 'aac',
      containerFormat: 'mp4',
      fpsPreference: 'auto',
      createdAt: DateTime.now(),
    );
