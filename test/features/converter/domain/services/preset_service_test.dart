import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/converter/domain/entities/conversion_preset.dart';
import 'package:svid/features/converter/domain/entities/output_format.dart';
import 'package:svid/features/converter/domain/services/preset_service.dart';

void main() {
  late PresetService service;

  setUp(() {
    service = PresetService();
  });

  group('allPresets', () {
    test('returns non-empty list', () {
      expect(service.allPresets, isNotEmpty);
    });

    test('every preset has unique id', () {
      final ids = service.allPresets.map((p) => p.id).toSet();
      expect(ids.length, service.allPresets.length);
    });

    test('every preset has non-empty name and description', () {
      for (final preset in service.allPresets) {
        expect(preset.name, isNotEmpty, reason: 'Preset ${preset.id} has empty name');
        expect(preset.description, isNotEmpty,
            reason: 'Preset ${preset.id} has empty description');
      }
    });

    test('every preset has non-empty icon', () {
      for (final preset in service.allPresets) {
        expect(preset.icon, isNotEmpty,
            reason: 'Preset ${preset.id} has empty icon');
      }
    });

    test('every preset has a valid category', () {
      for (final preset in service.allPresets) {
        expect(PresetCategory.values, contains(preset.category),
            reason: 'Preset ${preset.id} has invalid category');
      }
    });

    test('allPresets = freePresets + premiumPresets', () {
      expect(
        service.allPresets.length,
        service.freePresets.length + service.premiumPresets.length,
      );
    });
  });

  group('freePresets', () {
    test('all free presets have isPremium false', () {
      for (final preset in service.freePresets) {
        expect(preset.isPremium, isFalse,
            reason: 'Free preset ${preset.id} is marked premium');
      }
    });

    test('includes MP4 Universal', () {
      final mp4 = service.freePresets.where((p) => p.id == 'mp4_universal');
      expect(mp4, hasLength(1));
      expect(mp4.first.config.outputFormat, OutputFormat.mp4);
      expect(mp4.first.config.videoCodec, VideoCodecOption.h264);
    });

    test('includes MP3 Audio', () {
      final mp3 = service.freePresets.where((p) => p.id == 'mp3_audio');
      expect(mp3, hasLength(1));
      expect(mp3.first.config.outputFormat, OutputFormat.mp3);
      expect(mp3.first.config.audioBitrate, 320);
    });

    test('includes MKV Remux (stream copy)', () {
      final remux = service.freePresets.where((p) => p.id == 'mkv_remux');
      expect(remux, hasLength(1));
      expect(remux.first.config.videoCodec, VideoCodecOption.copy);
      expect(remux.first.config.audioCodec, AudioCodecOption.copy);
    });

    test('includes AVI Legacy (Jordana feedback path)', () {
      final avi = service.freePresets.where((p) => p.id == 'avi_legacy');
      expect(avi, hasLength(1));
      expect(avi.first.config.outputFormat, OutputFormat.avi);
      expect(avi.first.config.videoCodec, VideoCodecOption.h264);
      expect(avi.first.config.audioCodec, AudioCodecOption.mp3);
      expect(avi.first.isPopular, isTrue);
      expect(avi.first.category, PresetCategory.format);
    });

    test('includes MP4 Mobile (compact share)', () {
      final mob = service.freePresets.where((p) => p.id == 'mp4_mobile');
      expect(mob, hasLength(1));
      expect(mob.first.config.outputFormat, OutputFormat.mp4);
      expect(mob.first.config.resolution, ResolutionOption.p480);
      expect(mob.first.config.audioBitrate, 96);
      expect(mob.first.isPopular, isTrue);
    });
  });

  group('premiumPresets', () {
    test('premium list contains presets', () {
      expect(service.premiumPresets, isNotEmpty);
    });

    test('most premium-list presets are marked isPremium', () {
      final premiumMarked =
          service.premiumPresets.where((p) => p.isPremium).length;
      // Majority should be premium (a few free presets may live in this list)
      expect(premiumMarked, greaterThan(service.premiumPresets.length ~/ 2));
    });
  });

  group('getByCategory', () {
    test('returns only presets from requested category', () {
      for (final category in PresetCategory.values) {
        final presets = service.getByCategory(category);
        for (final preset in presets) {
          expect(preset.category, category,
              reason:
                  'Preset ${preset.id} has category ${preset.category} but was returned for $category');
        }
      }
    });

    test('format category has presets', () {
      final formats = service.getByCategory(PresetCategory.format);
      expect(formats, isNotEmpty);
    });

    test('audio category has presets', () {
      final audio = service.getByCategory(PresetCategory.audio);
      expect(audio, isNotEmpty);
    });

    test('enhance category has presets', () {
      final enhance = service.getByCategory(PresetCategory.enhance);
      expect(enhance, isNotEmpty);
    });

    test('edit category has presets', () {
      final edit = service.getByCategory(PresetCategory.edit);
      expect(edit, isNotEmpty);
    });

    test('creative category has presets', () {
      final creative = service.getByCategory(PresetCategory.creative);
      expect(creative, isNotEmpty);
    });

    test('tools category has presets', () {
      final tools = service.getByCategory(PresetCategory.tools);
      expect(tools, isNotEmpty);
    });

    test('all presets are accounted for across all categories', () {
      int total = 0;
      for (final category in PresetCategory.values) {
        total += service.getByCategory(category).length;
      }
      expect(total, service.allPresets.length);
    });
  });

  group('getById', () {
    test('finds existing preset', () {
      final preset = service.getById('mp4_universal');
      expect(preset, isNotNull);
      expect(preset!.id, 'mp4_universal');
    });

    test('returns null for non-existent id', () {
      expect(service.getById('nonexistent_preset'), isNull);
      expect(service.getById(''), isNull);
    });

    test('every preset can be found by its id', () {
      for (final preset in service.allPresets) {
        final found = service.getById(preset.id);
        expect(found, isNotNull, reason: 'Cannot find preset ${preset.id}');
        expect(found!.id, preset.id);
      }
    });
  });

  group('preset configs are valid', () {
    test('audio presets output audio formats or strip video', () {
      final audioPresets = service.getByCategory(PresetCategory.audio);
      for (final preset in audioPresets) {
        final config = preset.config;
        // Audio presets should either: output audio format, remove video, have no video codec,
        // or use copy (for presets that modify audio only while keeping video)
        expect(
          config.outputFormat.isAudioOnly ||
              config.removeVideo ||
              config.videoCodec == null ||
              config.videoCodec == VideoCodecOption.none ||
              config.videoCodec == VideoCodecOption.copy,
          isTrue,
          reason: 'Audio preset ${preset.id} unexpectedly re-encodes video: ${config.videoCodec}',
        );
      }
    });

    test('format presets output video formats', () {
      final formatPresets = service.getByCategory(PresetCategory.format);
      for (final preset in formatPresets) {
        // Format presets should use video container formats
        expect(
          preset.config.outputFormat.isVideo ||
              preset.config.outputFormat.isAnimatedImage,
          isTrue,
          reason:
              'Format preset ${preset.id} uses audio format ${preset.config.outputFormat}',
        );
      }
    });

    test('stream copy presets do not set CRF', () {
      for (final preset in service.allPresets) {
        if (preset.config.videoCodec == VideoCodecOption.copy) {
          expect(preset.config.crf, isNull,
              reason: 'Copy preset ${preset.id} should not have CRF');
        }
      }
    });

    test('trim preset uses stream copy for speed', () {
      final trim = service.getById('trim_cut');
      expect(trim, isNotNull);
      expect(trim!.config.videoCodec, VideoCodecOption.copy);
      expect(trim.config.audioCodec, AudioCodecOption.copy);
    });

    test('denoise presets enable denoise flag', () {
      for (final preset in service.allPresets) {
        if (preset.id.contains('denoise')) {
          expect(preset.config.denoise, isTrue,
              reason: 'Denoise preset ${preset.id} should have denoise=true');
        }
      }
    });
  });

  group('specific presets', () {
    test('watermark preset exists and is premium', () {
      final wm = service.getById('watermark');
      expect(wm, isNotNull);
      expect(wm!.isPremium, isTrue);
      expect(wm.category, PresetCategory.edit);
    });

    test('burn_subtitles preset exists and is premium', () {
      final subs = service.getById('burn_subtitles');
      expect(subs, isNotNull);
      expect(subs!.isPremium, isTrue);
      expect(subs.category, PresetCategory.edit);
    });

    test('trim_cut preset exists and is free', () {
      final trim = service.getById('trim_cut');
      expect(trim, isNotNull);
      expect(trim!.isPremium, isFalse);
      expect(trim.category, PresetCategory.edit);
    });

    test('merge_join preset exists', () {
      final merge = service.getById('merge_join');
      expect(merge, isNotNull);
    });

    test('extract_thumbnail preset exists', () {
      final thumb = service.getById('extract_thumbnail');
      expect(thumb, isNotNull);
      expect(thumb!.config.extractThumbnail, isTrue);
    });

    test('extract_subtitles preset exists', () {
      final subs = service.getById('extract_subtitles');
      expect(subs, isNotNull);
      expect(subs!.config.extractSubtitles, isTrue);
    });

    test('split_video preset exists', () {
      final split = service.getById('split_video');
      expect(split, isNotNull);
      expect(split!.config.splitInterval, isNotNull);
    });
  });
}
