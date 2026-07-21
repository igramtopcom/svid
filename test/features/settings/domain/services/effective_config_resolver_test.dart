import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';
import 'package:svid/features/settings/domain/services/effective_config_resolver.dart';

void main() {
  const resolver = EffectiveConfigResolver();
  final builtins = BuiltinPresetsSeeder.canonicalBuiltins();
  final mp4_1080p = builtins
      .firstWhere((p) => p.id == BuiltinPresetIds.mp4_1080p);
  final autoPreset = builtins
      .firstWhere((p) => p.id == BuiltinPresetIds.auto);

  group('EffectiveConfigResolver.resolve — preset values pass through', () {
    test('1080p MP4 preset surfaces all preset fields verbatim', () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p,
        defaults: const GlobalDownloadDefaults(),
      );

      expect(config.maxResolution, 1080);
      expect(config.videoCodec, 'h264');
      expect(config.audioCodec, 'aac');
      expect(config.containerFormat, 'mp4');
      expect(config.audioOnly, false);
      expect(config.fallbackBehavior, FormatPresetFallback.nearest);
      expect(config.sourcePresetId, BuiltinPresetIds.mp4_1080p);
      expect(config.sourcePresetName, '1080p MP4');
      expect(config.appliedPlatformOverride, false);
    });

    test('audio_mp3_320 surfaces audioOnly + 320kbps bitrate', () {
      final audio = builtins
          .firstWhere((p) => p.id == BuiltinPresetIds.audioMp3_320);
      final config = resolver.resolve(
        presetWithOverrides: audio,
        defaults: const GlobalDownloadDefaults(),
      );

      expect(config.audioOnly, true);
      expect(config.audioBitrate, 320);
      expect(config.containerFormat, 'mp3');
    });
  });

  group('EffectiveConfigResolver.resolve — Layer 3 fallback for "auto"', () {
    test('preset videoCodec=auto + defaults.videoCodec=h265 → h265', () {
      final config = resolver.resolve(
        presetWithOverrides: autoPreset, // every codec field is "auto"
        defaults: const GlobalDownloadDefaults(
          videoCodec: 'h265',
          containerFormat: 'mkv',
          fpsPreference: '60',
        ),
      );

      expect(config.videoCodec, 'h265');
      expect(config.containerFormat, 'mkv');
      expect(config.fpsPreference, '60');
    });

    test('preset maxResolution=0 + defaults.preferredQuality=720 → 720', () {
      final config = resolver.resolve(
        presetWithOverrides: autoPreset, // maxResolution = 0
        defaults: const GlobalDownloadDefaults(preferredQuality: 720),
      );
      expect(config.maxResolution, 720);
    });

    test('preset maxResolution=1080 wins over defaults.preferredQuality=720',
        () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p,
        defaults: const GlobalDownloadDefaults(preferredQuality: 720),
      );
      expect(config.maxResolution, 1080);
    });
  });

  group('EffectiveConfigResolver.resolve — nullable boolean inheritance', () {
    test('preset.subtitlesEnabled=null + defaults.subtitlesEnabled=true → true',
        () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p, // subtitlesEnabled is null
        defaults: const GlobalDownloadDefaults(subtitlesEnabled: true),
      );
      expect(config.subtitlesEnabled, true);
    });

    test('preset.embedMetadata=true overrides defaults=false', () {
      final archive = builtins
          .firstWhere((p) => p.id == BuiltinPresetIds.archive);
      final config = resolver.resolve(
        presetWithOverrides: archive, // embedMetadata = true
        defaults: const GlobalDownloadDefaults(embedMetadata: false),
      );
      expect(config.embedMetadata, true);
    });

    test('all-null bools default to false when defaults also null', () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p,
        defaults: const GlobalDownloadDefaults(),
      );
      expect(config.subtitlesEnabled, false);
      expect(config.embedThumbnail, false);
      expect(config.embedMetadata, false);
      expect(config.embedChapters, false);
    });
  });

  group('EffectiveConfigResolver.resolve — saveLocation precedence', () {
    test('preset.saveLocation wins over defaults + globalSaveLocation', () {
      final preset = mp4_1080p.copyWith(saveLocation: '/Custom/Folder');
      final config = resolver.resolve(
        presetWithOverrides: preset,
        defaults:
            const GlobalDownloadDefaults(saveLocation: '/Default/Folder'),
        globalSaveLocation: '/Global/Folder',
      );
      expect(config.saveLocation, '/Custom/Folder');
    });

    test('defaults.saveLocation wins when preset.saveLocation null', () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p, // saveLocation = null
        defaults:
            const GlobalDownloadDefaults(saveLocation: '/Default/Folder'),
        globalSaveLocation: '/Global/Folder',
      );
      expect(config.saveLocation, '/Default/Folder');
    });

    test('globalSaveLocation wins when preset + defaults both null', () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p,
        defaults: const GlobalDownloadDefaults(),
        globalSaveLocation: '/Global/Folder',
      );
      expect(config.saveLocation, '/Global/Folder');
    });
  });

  group('EffectiveConfigResolver.resolve — telemetry signal', () {
    test('appliedPlatformOverride=false when no platform pref passed', () {
      final config = resolver.resolve(
        presetWithOverrides: mp4_1080p,
        defaults: const GlobalDownloadDefaults(),
      );
      expect(config.appliedPlatformOverride, false);
    });

    // Note: Layer 1 PlatformQualityPreference field-merge is not yet
    // wired into the resolver implementation (see effective_config_resolver
    // .dart docstring). When it lands, add a positive-case test here.
  });
}
