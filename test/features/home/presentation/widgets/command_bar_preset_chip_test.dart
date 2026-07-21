import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/home/presentation/widgets/command_bar_preset_chip.dart';
import 'package:svid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';

/// Pure-formatter tests for [PresetDisplay] — no widget tree, no
/// Riverpod harness. Pins the chip + popover label derivation so any
/// schema field rename or fallback-rule change has to update these
/// expectations alongside the production code.
void main() {
  group('PresetDisplay.chipLabel', () {
    test('auto built-in (res=0, container=auto) → AUTO', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(PresetDisplay.chipLabel(p), 'AUTO');
    });

    test('auto built-in with inherited defaults shows effective label', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(
        PresetDisplay.chipLabel(
          p,
          defaults: const PresetDisplayDefaults(
            containerFormat: 'mp4',
            maxResolution: 1080,
          ),
        ),
        'MP4 · 1080p',
      );
    });

    test('auto built-in with inherited best quality avoids raw AUTO', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(
        PresetDisplay.chipLabel(
          p,
          defaults: const PresetDisplayDefaults(
            containerFormat: 'mp4',
            maxResolution: 0,
          ),
          bestQualityLabel: 'Best',
        ),
        'MP4 · Best',
      );
    });

    test('1080p MP4 built-in → MP4 · 1080p', () {
      final p = _builtinById(BuiltinPresetIds.mp4_1080p);
      expect(PresetDisplay.chipLabel(p), 'MP4 · 1080p');
    });

    test('720p compact → MP4 · 720p', () {
      final p = _builtinById(BuiltinPresetIds.compact_720p);
      expect(PresetDisplay.chipLabel(p), 'MP4 · 720p');
    });

    test('Audio MP3 320 → MP3 · 320kbps', () {
      final p = _builtinById(BuiltinPresetIds.audioMp3_320);
      expect(PresetDisplay.chipLabel(p), 'MP3 · 320kbps');
    });

    test('4K max → MP4 · 2160p', () {
      final p = _builtinById(BuiltinPresetIds.max_4k);
      expect(PresetDisplay.chipLabel(p), 'MP4 · 2160p');
    });

    test('Archive (mkv, res=0) → MKV', () {
      final p = _builtinById(BuiltinPresetIds.archive);
      expect(PresetDisplay.chipLabel(p), 'MKV');
    });

    test('audioOnly with null bitrate → container only', () {
      final p = _builtinById(
        BuiltinPresetIds.audioMp3_320,
      ).copyWith(audioBitrate: null);
      expect(PresetDisplay.chipLabel(p), 'MP3');
    });
  });

  group('PresetDisplay.popoverFormat', () {
    test('emits container in upper-case', () {
      final p = _builtinById(BuiltinPresetIds.mp4_1080p);
      expect(PresetDisplay.popoverFormat(p), 'MP4');
    });

    test('auto inherits global container when defaults are supplied', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(
        PresetDisplay.popoverFormat(
          p,
          defaults: const PresetDisplayDefaults(
            containerFormat: 'webm',
            maxResolution: 0,
          ),
        ),
        'WEBM',
      );
    });

    test('audioOnly preset still emits container only', () {
      final p = _builtinById(BuiltinPresetIds.audioMp3_320);
      expect(PresetDisplay.popoverFormat(p), 'MP3');
    });
  });

  group('PresetDisplay.popoverQuality', () {
    test('1080p MP4 → 1080p', () {
      final p = _builtinById(BuiltinPresetIds.mp4_1080p);
      expect(PresetDisplay.popoverQuality(p), '1080p');
    });

    test('audio preset → bitrate kbps', () {
      final p = _builtinById(BuiltinPresetIds.audioMp3_320);
      expect(PresetDisplay.popoverQuality(p), '320kbps');
    });

    test('auto preset (res=0, video) → empty', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(PresetDisplay.popoverQuality(p), '');
    });

    test('auto preset quality inherits global resolution', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(
        PresetDisplay.popoverQuality(
          p,
          defaults: const PresetDisplayDefaults(
            containerFormat: 'mp4',
            maxResolution: 720,
          ),
        ),
        '720p',
      );
    });

    test('auto preset quality with inherited best uses supplied label', () {
      final p = _builtinById(BuiltinPresetIds.auto);
      expect(
        PresetDisplay.popoverQuality(
          p,
          defaults: const PresetDisplayDefaults(
            containerFormat: 'mp4',
            maxResolution: 0,
          ),
          bestQualityLabel: 'Best',
        ),
        'Best',
      );
    });

    test('audio preset with null bitrate → empty', () {
      final p = _builtinById(
        BuiltinPresetIds.audioMp3_320,
      ).copyWith(audioBitrate: null);
      expect(PresetDisplay.popoverQuality(p), '');
    });
  });

  group('PresetDisplay.popoverFallback', () {
    test('higher → "higher" placeholder until UX wording lands', () {
      final p = _builtinById(
        BuiltinPresetIds.mp4_1080p,
      ).copyWith(fallbackBehavior: FormatPresetFallback.higher);
      expect(PresetDisplay.popoverFallback(p), 'higher');
    });

    test('block → "block" placeholder until UX wording lands', () {
      final p = _builtinById(
        BuiltinPresetIds.mp4_1080p,
      ).copyWith(fallbackBehavior: FormatPresetFallback.block);
      expect(PresetDisplay.popoverFallback(p), 'block');
    });

    // Note: `nearest` resolves through AppLocalizations which requires a
    // BuildContext + initialised i18n — covered by the widget test, not
    // here. The pure-formatter contract is "non-nearest → enum name".
  });

  group('PresetDisplay.profileName', () {
    test('trims built-in detail already shown in other rows', () {
      expect(
        PresetDisplay.profileName(
          'Tự động (cao nhất)',
          isModified: false,
          modifiedLabel: 'Đã chỉnh',
        ),
        'Tự động',
      );
    });

    test('adds compact modified suffix', () {
      expect(
        PresetDisplay.profileName(
          'Auto (best)',
          isModified: true,
          modifiedLabel: 'Edited',
        ),
        'Auto · Edited',
      );
    });
  });
}

FormatPresetExtended _builtinById(String id) =>
    BuiltinPresetsSeeder.canonicalBuiltins().firstWhere((p) => p.id == id);
