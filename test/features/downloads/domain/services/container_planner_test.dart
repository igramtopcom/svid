import 'package:flutter_test/flutter_test.dart';
import 'package:svid/core/utils/platform_detector.dart';
import 'package:svid/features/downloads/domain/services/container_planner.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';

/// Pin the planner output for every (pickedContainer × source codec
/// profile) cell. This is the regression net for the `pick X → get X`
/// contract: any future change that produces a different yt-dlp arg
/// shape will fail here, before it can reach a real download.
void main() {
  const planner = ContainerPlanner();

  group('ContainerPlanner — DASH H.264 + AAC (YouTube ≤1080p)', () {
    // The happy path: codecs already fit every native container.
    test('MP4 → merge=mp4, remux=mp4, no recode (fast)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.mergeFormat, 'mp4');
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.finalExtension, 'mp4');
      expect(p.requiresRecode, isFalse);
    });

    test('MKV → merge=mkv, remux=mkv, no recode', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mkv,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.mergeFormat, 'mkv');
      expect(p.remuxVideo, 'mkv');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test(
      'WebM + H.264/AAC source → recode to WebM (RC10 Q-round conditional)',
      () {
        // Pre-Q-round (RC10.2) this returned merge=webm/remux=webm with
        // no recode — but ffmpeg refuses to mux H.264 video + AAC audio
        // into a WebM container, so the post-remux step blew up with
        // "Postprocessing: Conversion failed!" on every TikTok/Facebook
        // WebM pick. New policy (2026-05-25): known-incompatible codecs
        // promote remux → recode so yt-dlp's FFmpegVideoConvertor
        // transcodes to VP9+Opus and the user gets a real .webm file.
        // UX surfaces this via the existing RC10.3 `converting` sub-
        // state.
        final p = planner.plan(
          pickedContainer: ContainerFormatPreference.webm,
          sourceVcodec: 'avc1.640028',
          sourceAcodec: 'mp4a.40.2',
        );
        // Wave A: webm-first runtime prover — plan-time evidence can be
        // wrong about the actual delivery (AUD-8); target-first lets a
        // webm-native delivery no-op while h264/aac still falls to mkv
        // and recodes exactly as before.
        expect(p.mergeFormat, 'webm/mkv/mp4');
        expect(p.remuxVideo, isNull);
        expect(p.recodeVideo, 'webm');
        expect(p.finalExtension, 'webm');
        expect(p.requiresRecode, isTrue);
        expect(p.recodeReason, RecodeReason.h264InWebm);
      },
    );

    test('AVI → recoded container, always recode', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.avi,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.recodeVideo, 'avi');
      expect(p.mergeFormat, 'mkv/mp4/webm');
      expect(p.finalExtension, 'avi');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.recodedContainer);
    });
  });

  group('ContainerPlanner — DASH VP9 + Opus (YouTube ≥1440p)', () {
    // CONTRACT (2026-06, "pick X → get X if technically possible"): MP4
    // CANNOT hold VP9, so a 1080p/≥1440p MP4 pick on a VP9-only source
    // must RECODE to H.264/AAC (surfaced `converting`), symmetric with
    // the WebM recode branch — NOT bail with a container-mismatch error.
    // The old "no hidden conversion → no recode for MP4" stance was an
    // INCOMPLETE branch (avc1@1080 used to be reliable); 2025-2026 PoT/
    // SABR gating broke that assumption. recode-surfaced != hidden.
    test('MP4 + VP9/Opus → RECODE to mp4 (symmetric with WebM)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      // Wave A: mp4-first runtime prover (register §06-12).
      expect(p.mergeFormat, 'mp4/mkv/webm');
      expect(p.remuxVideo, isNull);
      expect(p.recodeVideo, 'mp4');
      expect(p.finalExtension, 'mp4');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.vp9InMp4);
    });

    test('MP4 + H.264/AAC → fast remux, NO recode (common case guard)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MP4 + AV1 → fast remux, NO recode (AV1 is MP4-native)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'av01.0.08M.08',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MP4 + null vcodec → permissive remux (best-available path)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: null,
        sourceAcodec: null,
        isUnboundedQuality: true,
      );
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MKV → fast path (universal codec support)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mkv,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      expect(p.mergeFormat, 'mkv');
      expect(p.remuxVideo, 'mkv');
      expect(p.requiresRecode, isFalse);
    });

    test('WebM → fast path (VP9+Opus is WebM native)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      expect(p.mergeFormat, 'webm');
      expect(p.remuxVideo, 'webm');
      expect(p.requiresRecode, isFalse);
    });

    test('AV1 + Opus + MP4 → merge/remux only, no hidden conversion', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'av01.0.08M.08',
        sourceAcodec: 'opus',
      );
      expect(p.mergeFormat, 'mp4');
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });
  });

  group('ContainerPlanner — pre-muxed MP4 single file (TikTok)', () {
    // No DASH merge happens. yt-dlp's --merge-output-format is
    // "Ignored if no merge is required" — only --remux-video can
    // force the extension. This is the TikTok bug.
    test('MP4 → idempotent remux, source already MP4', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MKV → remux MP4 → MKV (stream-copy, fast)', () {
      // This is the TikTok bug fix: source MP4, user picks MKV, must
      // emit --remux-video mkv to enforce the .mkv extension.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mkv,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(p.remuxVideo, 'mkv');
      expect(p.recodeVideo, isNull);
      expect(p.finalExtension, 'mkv');
      expect(p.requiresRecode, isFalse);
    });

    test('WebM + h264/aac source (TikTok) → recode webm (RC10 Q-round)', () {
      // Updated for Q-round 2026-05-25 conditional WebM recode.
      // TikTok progressive MP4 source codecs are H.264 + AAC which
      // are NOT WebM-compatible; ffmpeg refuses to mux them into a
      // WebM container. Pre-Q-round this returned remux=webm and
      // blew up at the post-remux step with "Postprocessing:
      // Conversion failed!" — the exact production incident from
      // vidcombo_2026-05-25 (1).log. New behavior: emit
      // --recode-video webm so ffmpeg transcodes to VP9 + Opus.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      // Wave A: webm-first runtime prover.
      expect(p.mergeFormat, 'webm/mkv/mp4');
      expect(p.remuxVideo, isNull);
      expect(p.recodeVideo, 'webm');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.h264InWebm);
    });

    test('AVI from TikTok → recode AVI', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.avi,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(p.recodeVideo, 'avi');
      expect(p.requiresRecode, isTrue);
    });
  });

  group('ContainerPlanner — recoded containers (always recode)', () {
    test('AVI → recode=avi, finalExt=avi', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.avi,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      expect(p.recodeVideo, 'avi');
      expect(p.finalExtension, 'avi');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.recodedContainer);
    });

    test('MOV → recode=mov, finalExt=mov', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mov,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(p.recodeVideo, 'mov');
      expect(p.finalExtension, 'mov');
      expect(p.requiresRecode, isTrue);
    });

    test('M4V → recode target is "mp4" (yt-dlp does not accept m4v)', () {
      // yt-dlp's --recode-video FORMAT_RE validator rejects 'm4v'
      // (it's not in MEDIA_EXTENSIONS.common_video). Recode target
      // must be 'mp4'; the .mp4 → .m4v rename happens after the
      // process exits in ytdlp_datasource.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.m4v,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(
        p.recodeVideo,
        'mp4',
        reason: 'yt-dlp recode target for m4v MUST be "mp4"',
      );
      expect(
        p.finalExtension,
        'm4v',
        reason: 'User-facing extension after rename is .m4v',
      );
    });

    test('FLV → recode=flv, finalExt=flv', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.flv,
        sourceVcodec: 'h264',
        sourceAcodec: 'aac',
      );
      expect(p.recodeVideo, 'flv');
      expect(p.finalExtension, 'flv');
      expect(p.requiresRecode, isTrue);
    });
  });

  group('ContainerPlanner — unknown / unbounded codecs', () {
    test('Unbounded best + null codecs → no hidden conversion', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: null,
        sourceAcodec: null,
        isUnboundedQuality: true,
      );
      expect(p.mergeFormat, 'mp4');
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('Bounded specific quality + null codecs → no hidden conversion', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: null,
        sourceAcodec: null,
      );
      expect(p.mergeFormat, 'mp4');
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MKV + null codecs → still fast (universal)', () {
      // MKV's universal codec acceptance means we can remux anything,
      // including unknown codecs. The fast path stays open.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mkv,
        sourceVcodec: null,
        sourceAcodec: null,
      );
      expect(p.remuxVideo, 'mkv');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });
  });

  group('ContainerPlanner — codec string normalization', () {
    test('avc1 profile-suffix matches as h264', () {
      // YouTube reports e.g. 'avc1.640028' (H.264 high profile).
      // The codec-compat table must match the prefix to recognize it.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.requiresRecode, isFalse);
    });

    test('mp4a profile-suffix matches as AAC', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'h264',
        sourceAcodec: 'mp4a.40.5',
      );
      expect(p.requiresRecode, isFalse);
    });

    test('uppercase codec strings normalize', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'H264',
        sourceAcodec: 'AAC',
      );
      expect(p.requiresRecode, isFalse);
    });

    test('av01 profile-suffix matches as AV1 for WebM', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'av01.0.05M.08',
        sourceAcodec: 'opus',
      );
      expect(p.requiresRecode, isFalse);
    });
  });

  group('ContainerPlanner — contract invariants', () {
    test('finalExtension always matches user-picked container', () {
      // This is THE contract. Loop every container × every codec
      // profile and assert the final extension is ALWAYS the
      // user's pick.
      const profiles = [
        ('h264', 'aac'),
        ('vp9', 'opus'),
        ('av1', 'opus'),
        ('hevc', 'aac'),
        (null, null), // unbounded / unknown
      ];
      for (final container in ContainerFormatPreference.values) {
        for (final profile in profiles) {
          final p = planner.plan(
            pickedContainer: container,
            sourceVcodec: profile.$1,
            sourceAcodec: profile.$2,
          );
          expect(
            p.finalExtension,
            container.extension,
            reason:
                'pick=$container codecs=$profile must produce '
                'finalExtension=${container.extension}',
          );
        }
      }
    });

    test('remux and recode are mutually exclusive', () {
      // Planner emits at most ONE of remuxVideo / recodeVideo per
      // plan. Both being non-null would mean yt-dlp gets conflicting
      // postprocess directives.
      const profiles = [
        ('h264', 'aac'),
        ('vp9', 'opus'),
        ('av1', 'opus'),
        (null, null),
      ];
      for (final container in ContainerFormatPreference.values) {
        for (final profile in profiles) {
          final p = planner.plan(
            pickedContainer: container,
            sourceVcodec: profile.$1,
            sourceAcodec: profile.$2,
          );
          final hasRemux = p.remuxVideo != null;
          final hasRecode = p.recodeVideo != null;
          expect(
            hasRemux && hasRecode,
            isFalse,
            reason:
                'pick=$container codecs=$profile produced both '
                'remux=${p.remuxVideo} AND recode=${p.recodeVideo}',
          );
        }
      }
    });

    test('requiresRecode iff recodeVideo set', () {
      const profiles = [('h264', 'aac'), ('vp9', 'opus'), (null, null)];
      for (final container in ContainerFormatPreference.values) {
        for (final profile in profiles) {
          final p = planner.plan(
            pickedContainer: container,
            sourceVcodec: profile.$1,
            sourceAcodec: profile.$2,
          );
          expect(
            p.requiresRecode,
            p.recodeVideo != null,
            reason: 'requiresRecode flag must mirror recodeVideo presence',
          );
        }
      }
    });
  });

  group('ContainerPlanner — WebM conditional recode (RC10 Q-round 2026-05-25)', () {
    // Truth table per [[feedback_webm_output_target_policy]]. WebM
    // container spec only allows VP8/VP9/AV1 video + Opus/Vorbis
    // audio. Anything else must be recoded — but only when codecs
    // are KNOWN to be incompatible. Null codecs stay permissive
    // (YouTube adaptive Best Available legitimately has null acodec
    // because audio is a separate DASH stream).

    test('WebM + VP9/Opus → fast remux (regression: no recode)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      expect(p.remuxVideo, 'webm');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
      expect(p.recodeReason, isNull);
    });

    test('WebM + VP8/Vorbis → fast remux', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'vp8',
        sourceAcodec: 'vorbis',
      );
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('WebM + AV1/Opus → fast remux', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'av01.0.04M.08',
        sourceAcodec: 'opus',
      );
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('WebM + HEVC/AAC → recode webm, reason=hevcInWebm', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'hvc1.2.4.L120.B0',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.recodeVideo, 'webm');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.hevcInWebm);
    });

    test('WebM + VP9/AAC → recode webm, reason=aacInWebm', () {
      // Video codec IS WebM-compatible but audio isn't — recode is
      // still required (audio incompatibility is enough to break mux).
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'vp9',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.recodeVideo, 'webm');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.aacInWebm);
    });

    test(
      'WebM + null codecs → permissive fast path (YouTube Best Available)',
      () {
        // The Codex round-Q condition: don't force recode when
        // metadata is null. YouTube DASH adaptive often has
        // acodec=null because audio is a separate stream selected
        // at download time. Recoding every such case would burn
        // CPU on ≥50% of unbounded YouTube picks.
        final p = planner.plan(
          pickedContainer: ContainerFormatPreference.webm,
          sourceVcodec: null,
          sourceAcodec: null,
        );
        expect(p.recodeVideo, isNull);
        expect(p.requiresRecode, isFalse);
      },
    );

    test('WebM + VP9 video / null audio → permissive (YouTube adaptive)', () {
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'vp9',
        sourceAcodec: null,
      );
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('WebM + H.264 video / null audio → recode (video alone enough)', () {
      // Known-incompatible video codec is sufficient signal even
      // when audio is null. We're not going to silently mux H.264
      // into WebM regardless of audio.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.webm,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: null,
      );
      expect(p.recodeVideo, 'webm');
      expect(p.requiresRecode, isTrue);
      expect(p.recodeReason, RecodeReason.h264InWebm);
    });

    test('MP4 + H.264/AAC → unchanged fast path (no regression)', () {
      // C1 must not affect MP4 behavior — only WebM gets the
      // conditional recode logic. MP4 stays merge/remux always.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mp4,
        sourceVcodec: 'avc1.640028',
        sourceAcodec: 'mp4a.40.2',
      );
      expect(p.remuxVideo, 'mp4');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test('MKV + VP9/Opus → unchanged fast path (permissive container)', () {
      // MKV accepts every codec — must stay merge/remux always.
      final p = planner.plan(
        pickedContainer: ContainerFormatPreference.mkv,
        sourceVcodec: 'vp9',
        sourceAcodec: 'opus',
      );
      expect(p.remuxVideo, 'mkv');
      expect(p.recodeVideo, isNull);
      expect(p.requiresRecode, isFalse);
    });

    test(
      'promoteWebMRemuxToRecodeForPlatformFallback — WebM target swaps remux→recode',
      () {
        // The TikTok watermark / Facebook progressive / Reddit HLS
        // platform-fallback sites all reach this helper when the
        // user picked WebM AND a planner-emitted remuxVideo='webm'
        // would blow up because the override forces H.264/AAC.
        final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
          videoFormat: 'webm',
          recodeVideo: null,
          remuxVideo: 'webm',
        );
        expect(r.recodeVideo, 'webm');
        expect(r.remuxVideo, isNull);
      },
    );

    test('promote helper — non-WebM target passes through unchanged', () {
      final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
        videoFormat: 'mp4',
        recodeVideo: null,
        remuxVideo: 'mp4',
      );
      expect(r.recodeVideo, isNull);
      expect(r.remuxVideo, 'mp4');
    });

    test('promote helper — already-recoding WebM passes through', () {
      // Planner already decided convert (C1 truth-table case).
      // Don't double-promote.
      final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
        videoFormat: 'webm',
        recodeVideo: 'webm',
        remuxVideo: null,
      );
      expect(r.recodeVideo, 'webm');
      expect(r.remuxVideo, isNull);
    });

    test(
      'promote helper — recoded-tier (AVI) target ignored even if videoFormat=webm hint',
      () {
        // Defensive: if recodeVideo is set to a non-WebM target
        // (e.g., AVI), leave alone. Caller knows better.
        final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
          videoFormat: 'webm',
          recodeVideo: 'avi',
          remuxVideo: null,
        );
        expect(r.recodeVideo, 'avi');
        expect(r.remuxVideo, isNull);
      },
    );

    test('promote helper — detects WebM via recodeVideo source-of-truth', () {
      // Codex condition 1: detection source-of-truth includes
      // recodeVideo == 'webm' (not just videoFormat). This covers
      // the case where the call site has recodeVideo already set
      // by upstream but videoFormat is empty.
      final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
        videoFormat: null,
        recodeVideo: 'webm',
        remuxVideo: null,
      );
      expect(r.recodeVideo, 'webm');
    });

    test('promote helper — case-insensitive WebM detection', () {
      final r = ContainerPlanner.promoteWebMRemuxToRecodeForPlatformFallback(
        videoFormat: 'WebM',
        recodeVideo: null,
        remuxVideo: 'WEBM',
      );
      expect(r.recodeVideo, 'webm');
      expect(r.remuxVideo, isNull);
    });

    test('Codec normalization: case-insensitive prefix matching', () {
      // Spot-check that the normalizer handles real-world codec
      // strings (with profile/level suffixes) correctly.
      for (final variant in ['AVC1.640028', 'h264', 'AVC3.42E01E']) {
        final p = planner.plan(
          pickedContainer: ContainerFormatPreference.webm,
          sourceVcodec: variant,
          sourceAcodec: 'mp4a.40.2',
        );
        expect(
          p.recodeVideo,
          'webm',
          reason: 'variant "$variant" should normalize to h264',
        );
        expect(p.recodeReason, RecodeReason.h264InWebm);
      }
    });
  });

  // -----------------------------------------------------------------
  // Q+1 (2026-05-25): WebM-output-target source-selector policy.
  // These helpers are the single source of truth shared by BOTH
  // StartDownloadUseCase (fresh path) AND
  // DownloadsNotifier._buildRetryPlanFromSettings (retry path) so
  // the production failure on Facebook/Instagram WebM picks doesn't
  // come back via a fresh/retry drift. Pin them here.
  // -----------------------------------------------------------------
  group('shouldForceWebmOutputRecode — Q+1 cross-path policy', () {
    test('Facebook + WebM target + null codecs → FORCE recode', () {
      // The exact log.md 2026-05-25 #427 scenario. Source codecs are
      // not yet known (null on retry; SelectedQuality may also be
      // null on fresh adaptive selections). Pessimistic: assume
      // recode needed so a broad source selector kicks in.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.facebook,
          videoFormat: 'webm',
          remuxVideo: 'webm',
        ),
        isTrue,
      );
    });

    test('Instagram + WebM target + null codecs → FORCE recode', () {
      // log.md 2026-05-25 #430 scenario.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.instagram,
          videoFormat: 'webm',
          remuxVideo: 'webm',
        ),
        isTrue,
      );
    });

    test('TikTok + WebM + H.264/AAC source → FORCE recode', () {
      // C2 platform-fallback also catches this, but the helper must
      // independently make the right decision since C2 is bypassed
      // on the retry path.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.tiktok,
          videoFormat: 'webm',
          remuxVideo: 'webm',
          sourceVcodec: 'avc1.640028',
          sourceAcodec: 'mp4a.40.2',
        ),
        isTrue,
      );
    });

    test('YouTube + WebM target + null codecs → KEEP fast path', () {
      // YouTube has reliable WebM-native adaptive streams (VP9/Opus).
      // Forcing recode here would burn CPU on every YouTube WebM
      // pull. Helper short-circuits on platform == youtube.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'webm',
          remuxVideo: 'webm',
        ),
        isFalse,
      );
    });

    test('YouTube + WebM + AVC1 (rare) → still KEEP YouTube fast path', () {
      // YouTube-specific exception: even if codec metadata reports
      // AVC1 (e.g. unusual format ID), YouTube's selector still
      // picks WebM-native at download time. Avoid forcing recode.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'webm',
          remuxVideo: 'webm',
          sourceVcodec: 'avc1.640028',
          sourceAcodec: 'mp4a.40.2',
        ),
        isFalse,
      );
    });

    test('non-WebM target → no-op (returns false)', () {
      // MP4 / MKV picks must not be touched by this helper.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.facebook,
          videoFormat: 'mp4',
          remuxVideo: 'mp4',
        ),
        isFalse,
      );
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.facebook,
          videoFormat: 'mkv',
          remuxVideo: 'mkv',
        ),
        isFalse,
      );
    });

    test('Recode already decided as WebM → returns true (broad selector)', () {
      // ContainerPlanner.plan() may have already promoted remux→recode
      // because source codecs were known incompatible. In that case
      // the caller still needs to switch to the broad source selector.
      expect(
        ContainerPlanner.shouldForceWebmOutputRecode(
          platform: VideoPlatform.tiktok,
          videoFormat: 'webm',
          recodeVideo: 'webm',
          sourceVcodec: 'avc1.640028',
          sourceAcodec: 'mp4a.40.2',
        ),
        isTrue,
      );
    });

    test(
      'non-YouTube + WebM target + PROVEN WebM-native codecs → KEEP fast path',
      () {
        // Vimeo edge case: if extraction surfaces VP9+Opus, fast
        // remux is correct. Don't force unnecessary recode.
        expect(
          ContainerPlanner.shouldForceWebmOutputRecode(
            platform: VideoPlatform.vimeo,
            videoFormat: 'webm',
            remuxVideo: 'webm',
            sourceVcodec: 'vp09.00.51.08',
            sourceAcodec: 'opus',
          ),
          isFalse,
        );
      },
    );

    test('case-insensitive WebM detection across all 3 fields', () {
      for (final triple in [
        ('WebM', null, 'WEBM'),
        (null, 'webM', null),
        ('webm', null, null),
      ]) {
        expect(
          ContainerPlanner.shouldForceWebmOutputRecode(
            platform: VideoPlatform.facebook,
            videoFormat: triple.$1,
            recodeVideo: triple.$2,
            remuxVideo: triple.$3,
          ),
          isTrue,
          reason: 'triple=$triple should detect WebM target',
        );
      }
    });
  });

  group('buildWebmRecodeSourceSelector — Q+1 broad source selector', () {
    test('with both target + max height → uses min of the two', () {
      expect(
        ContainerPlanner.buildWebmRecodeSourceSelector(
          targetHeight: 2160,
          maxVideoHeight: 1080, // free-tier cap
        ),
        'bestvideo[height<=1080]+bestaudio/'
        'bestvideo[width<=1080]+bestaudio/'
        'best[height<=1080]/best[width<=1080]',
      );
    });

    test('with only target height → honors target', () {
      expect(
        ContainerPlanner.buildWebmRecodeSourceSelector(targetHeight: 1440),
        'bestvideo[height<=1440]+bestaudio/'
        'bestvideo[width<=1440]+bestaudio/'
        'best[height<=1440]/best[width<=1440]',
      );
    });

    test('with only max height → honors max', () {
      expect(
        ContainerPlanner.buildWebmRecodeSourceSelector(maxVideoHeight: 720),
        'bestvideo[height<=720]+bestaudio/'
        'bestvideo[width<=720]+bestaudio/'
        'best[height<=720]/best[width<=720]',
      );
    });

    test('with neither → unbounded best available', () {
      expect(
        ContainerPlanner.buildWebmRecodeSourceSelector(),
        'bestvideo+bestaudio/best',
      );
    });

    test('target < max → target wins (premium with explicit pick)', () {
      expect(
        ContainerPlanner.buildWebmRecodeSourceSelector(
          targetHeight: 720,
          maxVideoHeight: 4320,
        ),
        'bestvideo[height<=720]+bestaudio/'
        'bestvideo[width<=720]+bestaudio/'
        'best[height<=720]/best[width<=720]',
      );
    });
  });

  // ── N2/N4: shouldForceMp4OutputRecode truth table ──
  // Mirror of the WebM helper, but NOT pessimistic — only forces recode
  // for the narrow YouTube VP9-in-MP4 reality; never blanket-transcodes
  // the avc1 common case or non-YouTube platforms.
  group('shouldForceMp4OutputRecode — MP4 retry/SABR recode mirror', () {
    test('YouTube + null vcodec + remux=mp4 → recode (retry null-codec case)',
        () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'mp4',
          recodeVideo: null,
          remuxVideo: 'mp4',
          sourceVcodec: null,
        ),
        isTrue,
      );
    });

    test('YouTube + known vp9 → recode', () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'mp4',
          recodeVideo: null,
          remuxVideo: 'mp4',
          sourceVcodec: 'vp9',
        ),
        isTrue,
      );
    });

    test('anti-regression — fresh avc1 / AV1 → NO recode (fast remux)', () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'mp4',
          recodeVideo: null,
          remuxVideo: 'mp4',
          sourceVcodec: 'avc1.640028',
        ),
        isFalse,
      );
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'mp4',
          recodeVideo: null,
          remuxVideo: 'mp4',
          sourceVcodec: 'av01.0.08M.08',
        ),
        isFalse,
      );
    });

    test('anti-regression — non-YouTube MP4 with null vcodec → NO recode', () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.tiktok,
          videoFormat: 'mp4',
          recodeVideo: null,
          remuxVideo: 'mp4',
          sourceVcodec: null,
        ),
        isFalse,
      );
    });

    test('anti-regression — non-MP4 (webm) target → NO recode', () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'webm',
          recodeVideo: 'webm',
          remuxVideo: null,
          sourceVcodec: null,
        ),
        isFalse,
      );
    });

    test('recodeVideo already mp4 (planner saw known vp9) → keep true', () {
      expect(
        ContainerPlanner.shouldForceMp4OutputRecode(
          platform: VideoPlatform.youtube,
          videoFormat: 'mp4',
          recodeVideo: 'mp4',
          remuxVideo: null,
          sourceVcodec: null,
        ),
        isTrue,
      );
    });
  });
}
