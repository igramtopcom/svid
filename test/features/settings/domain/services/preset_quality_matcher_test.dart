import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/entities/video_info.dart';
import 'package:svid/features/settings/data/datasources/builtin_presets_seeder.dart';
import 'package:svid/features/settings/domain/entities/format_preset_extended.dart';
import 'package:svid/features/settings/domain/services/preset_quality_matcher.dart';

/// Pure-logic tests for [PresetQualityMatcher]. Pins the precedence
/// rule wiring (active command preset → quality auto-pick) so any
/// schema change to FormatPresetExtended or fallback semantics has to
/// update these expectations alongside production code.
///
/// The sealed [PresetMatchOutcome] return type is exercised
/// explicitly so a regression that collapses Blocked / NoCandidate /
/// Matched into a single null return surfaces here, not in production.
void main() {
  // ── helpers ──

  Quality video(String label, {required int height}) => Quality(
        qualityText: '$label [${height * 16 ~/ 9}x$height]',
        size: '50 MB',
        encryptedUrl: 'https://example/$label',
        mediaType: MediaType.video,
      );

  Quality audio(String label, {double? tbr}) => Quality(
        qualityText: label,
        size: '5 MB',
        encryptedUrl: 'https://example/$label',
        mediaType: MediaType.audio,
        tbr: tbr,
      );

  FormatPresetExtended preset({
    int maxResolution = 1080,
    bool audioOnly = false,
    int? audioBitrate,
    FormatPresetFallback fallback = FormatPresetFallback.nearest,
    String containerFormat = 'mp4',
  }) =>
      BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.mp4_1080p)
          .copyWith(
            maxResolution: maxResolution,
            audioOnly: audioOnly,
            audioBitrate: audioBitrate,
            fallbackBehavior: fallback,
            containerFormat: containerFormat,
          );

  /// Convenience: assert the outcome is a Matched and return its quality.
  Quality assertMatched(PresetMatchOutcome o) {
    expect(o, isA<PresetMatched>());
    return (o as PresetMatched).quality;
  }

  group('PresetQualityMatcher — empty / mediaType filter', () {
    test('empty available → NoCandidate', () {
      final o = PresetQualityMatcher.match(
        preset: preset(),
        available: const [],
      );
      expect(o, isA<PresetNoCandidate>());
    });

    test('video preset + only audio available → NoCandidate', () {
      final o = PresetQualityMatcher.match(
        preset: preset(),
        available: [audio('mp3 320', tbr: 320)],
      );
      expect(o, isA<PresetNoCandidate>());
    });

    test('audio preset + only video available → NoCandidate', () {
      final o = PresetQualityMatcher.match(
        preset: preset(audioOnly: true, audioBitrate: 320),
        available: [video('1080p', height: 1080)],
      );
      expect(o, isA<PresetNoCandidate>());
    });
  });

  group('PresetQualityMatcher — video, exact match', () {
    test('exact 1080p available → Matched(1080p)', () {
      final o = PresetQualityMatcher.match(
        preset: preset(maxResolution: 1080),
        available: [
          video('480p', height: 480),
          video('1080p', height: 1080),
          video('720p', height: 720),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1080p'));
    });

    test('maxResolution 0 → picks highest available', () {
      final o = PresetQualityMatcher.match(
        preset: preset(maxResolution: 0),
        available: [
          video('480p', height: 480),
          video('2160p', height: 2160),
          video('720p', height: 720),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('2160p'));
    });
  });

  group('PresetQualityMatcher — video fallback: nearest', () {
    test('1080p target, only 720p+1440p → picks one (tied distance)', () {
      // Distances: 720→360, 1440→360. Either is acceptable; assert match.
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.nearest,
        ),
        available: [
          video('720p', height: 720),
          video('1440p', height: 1440),
        ],
      );
      assertMatched(o);
    });

    test('1080p target, only 720p+1200p → picks 1200p (closer by 120)', () {
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.nearest,
        ),
        available: [
          video('720p', height: 720),
          video('1200p', height: 1200),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1200p'));
    });
  });

  group('PresetQualityMatcher — video fallback: higher', () {
    test('1080p target, only 720p+1440p → picks 1440p (smallest ≥ target)',
        () {
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.higher,
        ),
        available: [
          video('720p', height: 720),
          video('2160p', height: 2160),
          video('1440p', height: 1440),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1440p'));
    });

    test('1080p target, only lower heights → NoCandidate', () {
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.higher,
        ),
        available: [
          video('480p', height: 480),
          video('720p', height: 720),
        ],
      );
      expect(o, isA<PresetNoCandidate>());
    });
  });

  group('PresetQualityMatcher — video fallback: block (explicit intent)', () {
    test('no exact match → Blocked (caller skips Rule 2 → dialog)', () {
      // CRITICAL contract test: distinguish Blocked from NoCandidate so
      // the caller honours user intent ("don't auto-download a different
      // quality") and doesn't silently fall through to a savedPref.
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.block,
        ),
        available: [
          video('720p', height: 720),
          video('1440p', height: 1440),
        ],
      );
      expect(o, isA<PresetBlocked>());
      expect(o, isNot(isA<PresetNoCandidate>()));
    });

    test('exact match present → still Matched (block only fires on miss)',
        () {
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.block,
        ),
        available: [
          video('720p', height: 720),
          video('1080p', height: 1080),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1080p'));
    });

    test('mediaType mismatch → NoCandidate, not Blocked', () {
      // Block fires only when the resolution can't be honoured. If the
      // preset wants video but the platform offers only audio, that's
      // a structural NoCandidate (not "user blocked") — the caller
      // should fall through to Rule 2 / Rule 3 normally.
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.block,
        ),
        available: [audio('mp3 320', tbr: 320)],
      );
      expect(o, isA<PresetNoCandidate>());
    });
  });

  group('PresetQualityMatcher — audio path', () {
    test('audioOnly preset, null bitrate → first audio candidate', () {
      final o = PresetQualityMatcher.match(
        preset: preset(audioOnly: true, audioBitrate: null),
        available: [
          audio('mp3 128', tbr: 128),
          audio('mp3 320', tbr: 320),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, 'mp3 128');
    });

    test('audioOnly 320kbps target → picks closest by tbr', () {
      final o = PresetQualityMatcher.match(
        preset: preset(audioOnly: true, audioBitrate: 320),
        available: [
          audio('mp3 128', tbr: 128),
          audio('mp3 256', tbr: 256),
          audio('mp3 320', tbr: 320),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, 'mp3 320');
    });

    test('audioOnly 320kbps, no exact → picks 256 (closer than 128)', () {
      final o = PresetQualityMatcher.match(
        preset: preset(audioOnly: true, audioBitrate: 320),
        available: [
          audio('mp3 128', tbr: 128),
          audio('mp3 256', tbr: 256),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, 'mp3 256');
    });
  });

  group('PresetQualityMatcher — container preference (soft filter)', () {
    Quality videoTagged(String tag, {required int height}) => Quality(
          qualityText: '$tag $height [${height * 16 ~/ 9}x$height]',
          size: '50 MB',
          encryptedUrl: 'https://example/$tag-$height',
          mediaType: MediaType.video,
        );

    test('preset MP4 + sources [WebM 1080p, MP4 1080p] → picks MP4', () {
      final o = PresetQualityMatcher.match(
        preset: preset(maxResolution: 1080, containerFormat: 'mp4'),
        available: [
          videoTagged('WebM', height: 1080),
          videoTagged('MP4', height: 1080),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('MP4'));
    });

    test('preset MP4 + only WebM source → picks WebM (soft fallback)', () {
      // yt-dlp will remux WebM → MP4 via containerFormatOverride; matcher
      // doesn\'t fail just because the source library ships WebM-only.
      final o = PresetQualityMatcher.match(
        preset: preset(maxResolution: 1080, containerFormat: 'mp4'),
        available: [videoTagged('WebM', height: 1080)],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('WebM'));
    });

    test('preset auto container → no filter applied, pick highest', () {
      final o = PresetQualityMatcher.match(
        preset: preset(maxResolution: 0, containerFormat: 'auto'),
        available: [
          videoTagged('WebM', height: 720),
          videoTagged('MP4', height: 2160),
        ],
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('MP4'));
      expect(q.qualityText, contains('2160'));
    });

    test('preset MP4 + block fallback + no MP4 at target res → Blocked',
        () {
      // Container filter empties → falls back to all candidates → no
      // exact-height match → block fires. Tests that container soft-
      // filter doesn\'t accidentally bypass the explicit-block contract.
      final o = PresetQualityMatcher.match(
        preset: preset(
          maxResolution: 1080,
          containerFormat: 'mp4',
          fallback: FormatPresetFallback.block,
        ),
        available: [
          videoTagged('WebM', height: 720),
          videoTagged('WebM', height: 1440),
        ],
      );
      expect(o, isA<PresetBlocked>());
    });
  });

  group('PresetQualityMatcher — platform scope (synthesis)', () {
    Quality video1080() => Quality(
          qualityText: 'MP4 1080p [1920x1080]',
          size: '50 MB',
          encryptedUrl: 'https://example/1080p',
          mediaType: MediaType.video,
        );

    test('scoped preset + matching platform → Matched', () {
      final p = preset(maxResolution: 1080).copyWith(platformScope: 'tiktok');
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        videoPlatform: VideoPlatform.tiktok,
      );
      expect(o, isA<PresetMatched>());
    });

    test('scoped preset + non-matching platform → ScopeMismatch (no UX surprise)',
        () {
      // Imported "📌 TikTok (đã lưu)" preset, user pastes YouTube URL.
      // Matcher must NOT bleed TikTok preset into YouTube download
      // — that was the original review concern.
      final p = preset(maxResolution: 1080).copyWith(platformScope: 'tiktok');
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        videoPlatform: VideoPlatform.youtube,
      );
      expect(o, isA<PresetScopeMismatch>());
      expect(o, isNot(isA<PresetMatched>()));
      expect(o, isNot(isA<PresetNoCandidate>()));
    });

    test('null scope = universal → matches any platform', () {
      // Built-in presets have null platformScope — must keep universal
      // behavior so nothing regresses for users who never imported a
      // saved-pref.
      final p = preset(maxResolution: 1080); // platformScope = null default
      expect(p.platformScope, isNull);
      final o1 = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        videoPlatform: VideoPlatform.tiktok,
      );
      expect(o1, isA<PresetMatched>());
      final o2 = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        videoPlatform: VideoPlatform.youtube,
      );
      expect(o2, isA<PresetMatched>());
    });

    test('empty platformScope string = universal (defensive)', () {
      // Defensive: explicit empty string treated same as null. Avoids
      // a malformed import (`platformScope: ""`) silently scoping to
      // nothing and looking like a no-candidate.
      final p = preset(maxResolution: 1080).copyWith(platformScope: '');
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        videoPlatform: VideoPlatform.youtube,
      );
      expect(o, isA<PresetMatched>());
    });

    test('scope check fires BEFORE media-type filter', () {
      // Preset audioOnly + TikTok scope, URL is YouTube but only audio
      // is available. Without the scope-first ordering the matcher
      // would search audio candidates (succeed) and surprise the user.
      // With scope-first the preset cleanly says "not my platform".
      final p = preset(audioOnly: true, audioBitrate: 320)
          .copyWith(platformScope: 'tiktok');
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [
          Quality(
            qualityText: 'mp3 320',
            size: '5 MB',
            encryptedUrl: 'https://example/audio',
            mediaType: MediaType.audio,
            tbr: 320,
          ),
        ],
        videoPlatform: VideoPlatform.youtube,
      );
      expect(o, isA<PresetScopeMismatch>());
    });

    test('default videoPlatform=unknown + scoped preset → ScopeMismatch', () {
      // Strict scope semantics: an unidentified URL doesn't silently
      // satisfy a scoped preset. Better to fall through than wrongly
      // apply. Real callers (Rule 1.5) always pass videoPlatform; this
      // default only affects test harnesses + legacy `matchOrFallback`
      // shim callers, both of which prefer fall-through over surprise.
      final p = preset(maxResolution: 1080).copyWith(platformScope: 'tiktok');
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [video1080()],
        // videoPlatform defaults to unknown
      );
      expect(o, isA<PresetScopeMismatch>());
    });
  });

  group('PresetQualityMatcher — premium-aware (G1 fix)', () {
    Quality video(String label, {required int height}) => Quality(
          qualityText: '$label [${height * 16 ~/ 9}x$height]',
          size: '50 MB',
          encryptedUrl: 'https://example/$label',
          mediaType: MediaType.video,
        );

    test(
        'Auto preset (maxRes=0) + free user + 4K available → caps to 1080p '
        '(prevents upgrade-prompt loop on default first-paste)', () {
      // The G1 catastrophe: pre-fix, default Auto preset → matcher
      // returns 4K → premium gate L2 fires → upgrade dialog every
      // paste for free users. Post-fix, matcher caps the effective
      // target to PremiumLimits.freeMaxResolutionP (1080) so the
      // picked Quality clears L2 silently.
      final autoPreset = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.auto);
      final o = PresetQualityMatcher.match(
        preset: autoPreset,
        available: [
          video('480p', height: 480),
          video('720p', height: 720),
          video('1080p', height: 1080),
          video('1440p', height: 1440),
          video('2160p', height: 2160),
        ],
        isPremium: false,
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1080p'));
      expect(q.qualityText, isNot(contains('2160p')));
      expect(q.qualityText, isNot(contains('1440p')));
    });

    test('Auto preset (maxRes=0) + premium user → still picks highest', () {
      final autoPreset = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.auto);
      final o = PresetQualityMatcher.match(
        preset: autoPreset,
        available: [
          video('1080p', height: 1080),
          video('2160p', height: 2160),
        ],
        isPremium: true,
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('2160p'));
    });

    test(
        'Explicit 4K preset (maxRes=2160) + free user → still picks 4K '
        '(L2 dialog correct UX since user explicitly chose)', () {
      // Premium-aware cap ONLY applies to maxResolution=0 (Auto). If
      // a free user explicitly activated the "4K cao nhất" preset,
      // matcher honours that — premium gate L2 then fires the upgrade
      // dialog at download time, which is the correct UX (the user's
      // explicit choice deserves an explicit prompt, not a silent
      // downgrade to 1080p).
      final fourK = preset(maxResolution: 2160);
      final o = PresetQualityMatcher.match(
        preset: fourK,
        available: [
          video('1080p', height: 1080),
          video('2160p', height: 2160),
        ],
        isPremium: false,
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('2160p'));
    });

    test(
        'Explicit 1080p preset + free user → 1080p (no cap interference)',
        () {
      final p = preset(maxResolution: 1080);
      final o = PresetQualityMatcher.match(
        preset: p,
        available: [
          video('720p', height: 720),
          video('1080p', height: 1080),
          video('2160p', height: 2160),
        ],
        isPremium: false,
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('1080p'));
    });

    test('Auto preset + free user + only 720p available → 720p (cap moot)',
        () {
      // Cap = 1080. _pickVideo with target=1080, available=[720] →
      // exact-match miss → fallback nearest → picks 720. No regression
      // for free users on low-res sources.
      final autoPreset = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.auto);
      final o = PresetQualityMatcher.match(
        preset: autoPreset,
        available: [video('720p', height: 720)],
        isPremium: false,
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('720p'));
    });

    test('Audio-only preset + free user → cap doesn\'t apply (audio path)',
        () {
      // Cap is video-only. Audio-only presets pass through unchanged
      // (audio bitrate isn't premium-gated by PremiumLimits).
      final audioPreset = preset(audioOnly: true, audioBitrate: 320);
      final o = PresetQualityMatcher.match(
        preset: audioPreset,
        available: [
          Quality(
            qualityText: 'mp3 320',
            size: '5 MB',
            encryptedUrl: 'https://example/audio',
            mediaType: MediaType.audio,
            tbr: 320,
          ),
        ],
        isPremium: false,
      );
      assertMatched(o);
    });

    test('Default isPremium=true preserves backwards-compat behavior', () {
      // Existing tests don't pass isPremium — they get the default
      // (true) which means "no cap, behave like pre-G1-fix". This
      // sentinel guards against accidental regression to the old
      // signature.
      final autoPreset = BuiltinPresetsSeeder.canonicalBuiltins()
          .firstWhere((p) => p.id == BuiltinPresetIds.auto);
      final o = PresetQualityMatcher.match(
        preset: autoPreset,
        available: [
          video('1080p', height: 1080),
          video('2160p', height: 2160),
        ],
        // isPremium not specified → defaults to true
      );
      final q = assertMatched(o);
      expect(q.qualityText, contains('2160p'));
    });
  });

  group('PresetQualityMatcher — backwards-compat shim', () {
    test('matchOrFallback returns Quality on Matched', () {
      // ignore: deprecated_member_use_from_same_package
      final q = PresetQualityMatcher.matchOrFallback(
        preset: preset(maxResolution: 1080),
        available: [video('1080p', height: 1080)],
      );
      expect(q, isNotNull);
      expect(q!.qualityText, contains('1080p'));
    });

    test('matchOrFallback returns null on Blocked (legacy lossy contract)',
        () {
      // ignore: deprecated_member_use_from_same_package
      final q = PresetQualityMatcher.matchOrFallback(
        preset: preset(
          maxResolution: 1080,
          fallback: FormatPresetFallback.block,
        ),
        available: [video('720p', height: 720)],
      );
      expect(q, isNull);
    });

    test('matchOrFallback returns null on NoCandidate', () {
      // ignore: deprecated_member_use_from_same_package
      final q = PresetQualityMatcher.matchOrFallback(
        preset: preset(),
        available: const [],
      );
      expect(q, isNull);
    });
  });
}
