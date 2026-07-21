import 'package:flutter_test/flutter_test.dart';
import 'package:svid/features/downloads/data/datasources/ytdlp_datasource.dart';
import 'package:svid/features/downloads/domain/entities/download_selection_intent.dart';
import 'package:svid/features/downloads/domain/services/format_selector_service.dart';
import 'package:svid/features/settings/domain/enums/audio_codec_preference.dart';
import 'package:svid/features/settings/domain/enums/container_format_preference.dart';
import 'package:svid/features/settings/domain/enums/fps_preference.dart';
import 'package:svid/features/settings/domain/enums/video_codec_preference.dart';

void main() {
  late FormatSelectorService svc;

  setUp(() => svc = const FormatSelectorService());

  group('selector API contract', () {
    test('represents recommended video request and selector result', () {
      const request = FormatSelectionRequest(
        qualityIntent: DownloadQualityIntent.recommended,
        fileType: DownloadFileType.video,
        videoCodecPreference: VideoCodecPreference.h264,
        audioCodecPreference: AudioCodecPreference.aac,
        containerFormatPreference: ContainerFormatPreference.mp4,
        fpsPreference: FpsPreference.auto,
        fallbackPolicy: QualityFallbackPolicy.nearestWithWarning,
        forceRemuxPreference: false,
      );
      const result = FormatSelectionResult(
        formatSelector: 'bestvideo[height<=1080]+bestaudio/best',
        sortOptions: 'res,ext:mp4:m4a',
        videoFormat: 'mp4',
        audioFormat: 'm4a',
        forceRemux: false,
      );

      expect(request.qualityIntent, DownloadQualityIntent.recommended);
      expect(request.fileType, DownloadFileType.video);
      expect(result.formatSelector, contains('height<=1080'));
      expect(result.warning, isNull);
    });

    test('represents best available with container warning', () {
      const warning = FormatSelectionWarning(
        code: FormatSelectionWarningCode.containerChanged,
        requestedLabel: 'MP4',
        resolvedLabel: 'MKV',
        messageKey: 'configDialog.containerChangedWarning',
      );
      const result = FormatSelectionResult(
        formatSelector: 'bestvideo+bestaudio/best',
        sortOptions: 'res',
        videoFormat: 'mkv',
        forceRemux: false,
        warning: warning,
      );

      expect(result.warning, warning);
      expect(result.warning!.code, FormatSelectionWarningCode.containerChanged);
    });

    test('builds best available result without compatibility caps', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.bestAvailable,
          fileType: DownloadFileType.video,
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.mp4,
          fpsPreference: FpsPreference.prefer30,
        ),
      );

      // Pick X → get X contract v3 (post-RC10 Codex-catch C): MP4
      // stays MP4-first; selector NO LONGER falls back to any-codec
      // `/bestvideo+bestaudio/best` because RC10.2 forbids hidden
      // recode for native containers. Final fallback is now
      // container-compatible (`ext=mp4`) so a free user picking MP4
      // who hits a VP9/Opus-only source gets a clear "no MP4-
      // compatible source" failure rather than a silent wrong-codec
      // download or a long hidden transcode.
      expect(result.formatSelector, contains('bestvideo[vcodec^=avc]'));
      expect(result.formatSelector, contains('bestaudio[acodec^=aac]'));
      expect(
        result.formatSelector,
        // RC10 Codex-round-2 catch 2: MP4 audio is m4a (AAC in
        // MPEG-4 audio container), not mp4. Video stays mp4.
        endsWith('/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]'),
      );
      // Wave B: prefer30 now reaches -S as a soft key (after res).
      expect(result.sortOptions, 'res,fps:30,vcodec:avc,acodec:aac,ext:mp4:m4a');
      expect(result.videoFormat, 'mp4');
      expect(result.mergeFormatPriority, 'mp4/mkv/webm');
      expect(result.forceRemux, isFalse);
      expect(
        result.warning,
        isNull,
        reason: 'No more containerChanged warning — planner notice replaces',
      );
    });

    test('best available with concrete 1080p target stays MP4', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.bestAvailable,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1080),
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.mp4,
          fpsPreference: FpsPreference.prefer30,
        ),
      );

      expect(result.formatSelector, contains('[height<=1080]'));
      expect(
        result.formatSelector,
        contains('[width<=1080]'),
        reason: 'portrait 1080x1920 streams must remain selectable',
      );
      // Wave B: prefer30 now reaches -S as a soft key (after res).
      expect(
        result.sortOptions,
        'res:1080,fps:30,vcodec:avc,acodec:aac,ext:mp4:m4a',
      );
      expect(result.videoFormat, 'mp4');
      expect(result.mergeFormatPriority, 'mp4/mkv/webm');
      expect(result.warning, isNull);
    });

    test('normalizes incompatible codecs before building webm selector', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1080),
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.webm,
        ),
      );

      expect(result.formatSelector, contains('[height<=1080]'));
      expect(result.formatSelector, contains('[width<=1080]'));
      expect(result.formatSelector, isNot(contains('vcodec^=avc')));
      expect(result.formatSelector, isNot(contains('acodec^=aac')));
      expect(result.sortOptions, 'res:1080,ext:webm:opus');
      expect(result.videoFormat, 'webm');
    });

    test('normalizes incompatible codecs before building mp4 selector', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.recommended,
          fileType: DownloadFileType.video,
          videoCodecPreference: VideoCodecPreference.vp9,
          audioCodecPreference: AudioCodecPreference.opus,
          containerFormatPreference: ContainerFormatPreference.mp4,
        ),
      );

      expect(result.formatSelector, contains('[height<=1080]'));
      expect(result.formatSelector, contains('[width<=1080]'));
      expect(result.formatSelector, isNot(contains('vcodec^=vp9')));
      expect(result.formatSelector, isNot(contains('acodec^=opus')));
      // DL-002 fix #0: demoted-to-auto on an MP4 target now carries the
      // soft MP4-native preference instead of no vcodec token at all.
      expect(result.sortOptions, 'res:1080,vcodec:h264,ext:mp4:m4a');
      expect(result.videoFormat, 'mp4');
    });

    test('honors exactOnly fallback policy for specific video target', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1080),
          fallbackPolicy: QualityFallbackPolicy.exactOnly,
        ),
      );

      expect(result.formatSelector, contains('[height=1080]'));
      expect(result.formatSelector, contains('[width=1080]'));
      expect(result.formatSelector, isNot(contains('[height<=1080]')));
    });

    test(
      'represents specific, audio, subtitle, and technical stream targets',
      () {
        const specific = FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1080),
          fallbackPolicy: QualityFallbackPolicy.nearestLower,
        );
        const audio = FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.audio,
          target: PortableQualityTarget.audio(
            outputFormat: 'mp3',
            targetBitrateKbps: 192,
          ),
        );
        const subtitle = FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.subtitle,
          target: PortableQualityTarget.subtitle(
            languageCode: 'vi',
            subtitleFormat: 'srt',
          ),
        );
        const technical = FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.technicalStream,
          fileType: DownloadFileType.video,
          fallbackPolicy: QualityFallbackPolicy.exactOnly,
        );

        expect(specific.target!.targetHeight, 1080);
        expect(audio.target!.outputFormat, 'mp3');
        expect(subtitle.target!.languageCode, 'vi');
        expect(technical.qualityIntent, DownloadQualityIntent.technicalStream);
      },
    );

    test('DL-003: audio extract selector excludes storyboards (acodec!=none)',
        () {
      // A storyboard row (vcodec=none/acodec=none) must never be picked for
      // an audio extract via the config-dialog/preset path — otherwise
      // yt-dlp emits `.mhtml` instead of the requested audio. Mirror of the
      // raw-audio fix in StartDownloadUseCase.
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.audio,
          target: PortableQualityTarget.audio(
            outputFormat: 'mp3',
            targetBitrateKbps: 192,
          ),
        ),
      );
      expect(
        result.formatSelector,
        'bestaudio[acodec!=none]/best[acodec!=none]',
      );
      expect(result.audioFormat, 'mp3');
    });
  });

  // ---------------------------------------------------------------------------
  // buildBestFormatSelector
  // ---------------------------------------------------------------------------

  group('buildBestFormatSelector', () {
    test(
      'auto codec produces bestvideo+bestaudio/best (no duplicate fallback)',
      () {
        final f = svc.buildBestFormatSelector();
        expect(f, equals('bestvideo+bestaudio/best'));
      },
    );

    test('h264 preference adds vcodec^=avc filter', () {
      final f = svc.buildBestFormatSelector(
        videoCodec: VideoCodecPreference.h264,
      );
      expect(f, contains('[vcodec^=avc]'));
      // Still has ultimate fallback
      expect(f, contains('bestvideo+bestaudio/best'));
    });

    test('av1 preference adds vcodec^=av01 filter', () {
      final f = svc.buildBestFormatSelector(
        videoCodec: VideoCodecPreference.av1,
      );
      expect(f, contains('[vcodec^=av01]'));
    });

    test('aac audio preference adds acodec^=aac filter', () {
      final f = svc.buildBestFormatSelector(
        audioCodec: AudioCodecPreference.aac,
      );
      expect(f, contains('[acodec^=aac]'));
    });

    test('Wave B (AUD-7): fps NEVER appears as a hard -f filter — as the '
        'first tier of the unbounded best path, [fps<=30] silently tanked '
        'a 4K60 source to 480p30 (B7-class downgrade, live-reproduced)', () {
      final f = svc.buildBestFormatSelector(fps: FpsPreference.prefer30);
      expect(f, isNot(contains('fps<=')));
    });

    test('Wave B: fps lives in -S as a SOFT key after res — prefers lower '
        'fps inside the resolution pool, never sacrifices resolution', () {
      expect(
        svc.buildSortOptions(
          fps: FpsPreference.prefer30,
          container: ContainerFormatPreference.mp4,
          targetHeight: 1080,
        ),
        'res:1080,fps:30,vcodec:h264,ext:mp4:m4a',
      );
      expect(
        svc.buildSortOptions(
          fps: FpsPreference.prefer30,
          container: ContainerFormatPreference.mkv,
        ),
        'res,fps:30',
      );
      // auto = no token (unchanged behavior)
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mkv,
          targetHeight: 1080,
        ),
        'res:1080',
      );
    });

    test('combined: h264 + aac + fps30 — codec filters stay in -f, fps '
        'does not', () {
      final f = svc.buildBestFormatSelector(
        videoCodec: VideoCodecPreference.h264,
        audioCodec: AudioCodecPreference.aac,
        fps: FpsPreference.prefer30,
      );
      expect(f, contains('[vcodec^=avc]'));
      expect(f, contains('[acodec^=aac]'));
      expect(f, isNot(contains('fps<=')));
      expect(f, contains('bestvideo+bestaudio/best'));
    });

    test('maxHeight constrains all best-quality fallbacks', () {
      final f = svc.buildBestFormatSelector(maxHeight: 1080);

      expect(f, contains('bestvideo[height<=1080]+bestaudio'));
      expect(f, contains('bestvideo[width<=1080]+bestaudio'));
      // RC-3: single-file progressive net is now HEIGHT-ONLY (the width
      // twin matched only itag-18 640x360 on landscape). The width axis
      // survives via the merge tiers asserted above.
      expect(f, endsWith('/best[height<=1080]'));
      expect(f, isNot(contains('/bestvideo+bestaudio/best')));
    });
  });

  // ---------------------------------------------------------------------------
  // buildResolutionFormatSelector
  // ---------------------------------------------------------------------------

  group('buildResolutionFormatSelector', () {
    test('uses sort-first lead tier for resolution picks', () {
      final f = svc.buildResolutionFormatSelector(height: 1080);
      expect(f, startsWith('bestvideo+bestaudio'));
    });

    test('does not encode portrait fallback as first-match slash OR', () {
      final f = svc.buildResolutionFormatSelector(height: 720);
      expect(f, 'bestvideo+bestaudio');
    });

    test('does not have unrestricted best fallback', () {
      final f = svc.buildResolutionFormatSelector(height: 1080);
      expect(f, isNot(contains('/bestvideo+bestaudio/best')));
      expect(f, isNot(contains('/best[')));
    });

    test('h264 + 720p: codec filter applied with height constraint', () {
      final f = svc.buildResolutionFormatSelector(
        height: 720,
        videoCodec: VideoCodecPreference.h264,
      );
      expect(f, contains('[height<=720]'));
      expect(f, contains('[width<=720]'));
      expect(f, contains('[vcodec^=avc]'));
      expect(f, isNot(endsWith('/bestvideo+bestaudio/best')));
    });

    test('Wave B: fps never enters the resolution selector belts either '
        '(they were shadowed by the lead tier anyway — dead code)', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        fps: FpsPreference.prefer60,
      );
      expect(f, isNot(contains('fps<=')));
    });

    test('does NOT contain best[height<=H] (removed problematic fallback)', () {
      final f = svc.buildResolutionFormatSelector(height: 1080);
      // Old broken fallback that fails on DASH-only streams
      expect(f, isNot(contains('best[height<=1080]')));
      expect(f, isNot(contains('best[width<=1080]')));
    });

    test('can disable unbounded fallback for free-tier cap enforcement', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        allowUnboundedFallback: false,
      );

      // RC-3: free-tier single-file safety net is now HEIGHT-ONLY. The
      // resolution cap still holds (height<=1080); the width-axis 640x360
      // landscape trap is removed.
      expect(f, endsWith('/best[height<=1080]'));
      expect(f, isNot(contains('/bestvideo+bestaudio/best')));
    });
  });

  // ---------------------------------------------------------------------------
  // buildSortOptions
  // ---------------------------------------------------------------------------

  group('buildSortOptions', () {
    test('auto always starts with res', () {
      final s = svc.buildSortOptions();
      expect(s, startsWith('res'));
    });

    test('h264 preference adds vcodec:avc', () {
      final s = svc.buildSortOptions(videoCodec: VideoCodecPreference.h264);
      expect(s, contains('vcodec:avc'));
    });

    test('aac preference adds acodec:aac', () {
      final s = svc.buildSortOptions(audioCodec: AudioCodecPreference.aac);
      expect(s, contains('acodec:aac'));
    });

    test('mp4 container ends with ext:mp4:m4a', () {
      final s = svc.buildSortOptions(
        videoCodec: VideoCodecPreference.h264,
        audioCodec: AudioCodecPreference.aac,
        container: ContainerFormatPreference.mp4,
      );
      expect(s, endsWith('ext:mp4:m4a'));
    });

    test('webm container does not prefer mp4 streams', () {
      final s = svc.buildSortOptions(container: ContainerFormatPreference.webm);
      expect(s, contains('ext:webm:opus'));
      expect(s, isNot(contains('ext:mp4:m4a')));
    });

    test('webm container drops incompatible h264/aac codec preferences', () {
      final s = svc.buildSortOptions(
        videoCodec: VideoCodecPreference.h264,
        audioCodec: AudioCodecPreference.aac,
        container: ContainerFormatPreference.webm,
      );
      expect(s, 'res,ext:webm:opus');
      expect(s, isNot(contains('vcodec:avc')));
      expect(s, isNot(contains('acodec:aac')));
    });

    test('mp4 container drops incompatible vp9/opus codec preferences', () {
      final s = svc.buildSortOptions(
        videoCodec: VideoCodecPreference.vp9,
        audioCodec: AudioCodecPreference.opus,
        container: ContainerFormatPreference.mp4,
      );
      // Wave A height-aware: uncapped MP4 carries no vcodec token (the
      // demoted prefs are dropped; av01-first default is correct with
      // the mp4-first merge prover).
      expect(s, 'res,ext:mp4:m4a');
      expect(s, isNot(contains('vcodec:vp9')));
      expect(s, isNot(contains('acodec:opus')));
    });

    test('mkv container does not force extension preference', () {
      final s = svc.buildSortOptions(container: ContainerFormatPreference.mkv);
      expect(s, 'res');
      expect(s, isNot(contains('ext:mp4:m4a')));
    });

    test('mkv container keeps explicit codec preferences', () {
      final s = svc.buildSortOptions(
        videoCodec: VideoCodecPreference.vp9,
        audioCodec: AudioCodecPreference.opus,
        container: ContainerFormatPreference.mkv,
      );
      expect(s, 'res,vcodec:vp9,acodec:opus');
    });

    test('auto codec adds no USER vcodec entry (MKV — outside the DL-002 '
        'mp4 soft pref)', () {
      final s = svc.buildSortOptions(container: ContainerFormatPreference.mkv);
      expect(s, isNot(contains('vcodec:')));
    });
  });

  // ===========================================================================
  // DL-002 fix #0 — soft MP4-native codec preference in -S.
  // Mechanism (register §06-10): the RC-2-v3 `bestvideo+bestaudio` lead tier
  // + a vcodec-less -S let yt-dlp's default ranking pick av01/vp9 inside the
  // res pool (av01 is ext=mp4 too, so `ext:mp4:m4a` can't tiebreak it away),
  // and shouldForceMp4OutputRecode then full-recoded every such pick → the
  // 1.7.3 recode/timeout storm. The fix adds `vcodec:h264` as a SOFT sort
  // pref for MP4 targets with auto codec — never a hard -f filter.
  // Live-verified (yt-dlp 2026.06.09, aqz-KE-bpKQ): 1080p MP4 flips
  // av01(f399)→avc1(299)+m4a; 4K stays 2160p vp9 (no downgrade, no fail).
  // ===========================================================================
  group('DL-002 fix #0 — MP4 soft vcodec:h264 sort preference', () {
    test('GOLDEN: capped MP4 + auto codecs → res:H,vcodec:h264,ext:mp4:m4a',
        () {
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mp4,
          targetHeight: 1080,
        ),
        'res:1080,vcodec:h264,ext:mp4:m4a',
      );
    });

    test('GOLDEN (Wave A height-aware): uncapped MP4 carries NO vcodec '
        'token — default av01-first IS the fast path once the mp4-first '
        'merge prover lands (av01+aac merges to .mp4, recode no-ops)', () {
      expect(
        svc.buildSortOptions(container: ContainerFormatPreference.mp4),
        'res,ext:mp4:m4a',
      );
    });

    test('GOLDEN (Wave A height-aware): MP4 targets ABOVE 1080p carry NO '
        'vcodec token — YouTube has no h264 there and vcodec:h264 would '
        'invert the ranking to vp9-over-av01, forcing a genuine transcode '
        'where av01 would no-op', () {
      for (final h in [1440, 2160]) {
        expect(
          svc.buildSortOptions(
            container: ContainerFormatPreference.mp4,
            targetHeight: h,
          ),
          'res:$h,ext:mp4:m4a',
        );
      }
    });

    test('explicit codec pref on MP4 is untouched — exactly ONE vcodec token',
        () {
      final s = svc.buildSortOptions(
        videoCodec: VideoCodecPreference.h264,
        audioCodec: AudioCodecPreference.aac,
        container: ContainerFormatPreference.mp4,
        targetHeight: 1080,
      );
      expect(s, 'res:1080,vcodec:avc,acodec:aac,ext:mp4:m4a');
      expect('vcodec:'.allMatches(s).length, 1);
    });

    test('MKV unaffected: no vcodec token added (Case C of the packet)', () {
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mkv,
          targetHeight: 1080,
        ),
        'res:1080',
      );
    });

    test('WebM unaffected by this packet: ext pref only, no vcodec token', () {
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.webm,
          targetHeight: 1080,
        ),
        'res:1080,ext:webm:opus',
      );
    });

    test('recoded-tier containers (avi/mov/m4v/flv) gain no vcodec token', () {
      for (final c in [
        ContainerFormatPreference.avi,
        ContainerFormatPreference.mov,
        ContainerFormatPreference.m4v,
        ContainerFormatPreference.flv,
      ]) {
        expect(svc.buildSortOptions(container: c, targetHeight: 1080), 'res:1080');
      }
    });

    test('SOFT not HARD: the -f chain still leads with the any-codec tier '
        '(vp9/av01-only sources stay reachable at the requested res — S6) and '
        'gains no new vcodec filter', () {
      final before = svc.buildResolutionFormatSelector(
        height: 1080,
        container: ContainerFormatPreference.mp4,
      );
      expect(before, startsWith('bestvideo+bestaudio/'));
      // The preference lives ONLY in -S; the selector chain is unchanged
      // by DL-002 (same tiers, same order — the LEAD tier carries no
      // [vcodec^=...] gate, so any-codec sources remain reachable).
      expect(before.split('/').first, 'bestvideo+bestaudio');
    });

    test('bare call inherits the mp4 DEFAULT container and thus the soft '
        'pref — every production caller passes container explicitly '
        '(verified: usecase x2, selector x3, retry notifier x1)', () {
      expect(
        svc.buildSortOptions(targetHeight: 720),
        'res:720,vcodec:h264,ext:mp4:m4a',
      );
    });
  });

  // Pick X → get X contract: resolveMergeFormatPriority NEVER silently
  // promotes MP4 to MKV anymore. Native containers stay merge/remux-only;
  // explicit conversion containers are handled by ContainerPlanner.
  group('resolveMergeFormatPriority — pick X → get X (no swap)', () {
    test('MP4 returns mp4-first at every height', () {
      for (final h in [720, 1080, 1440, 2160]) {
        expect(
          svc.resolveMergeFormatPriority(
            container: ContainerFormatPreference.mp4,
            targetHeight: h,
            videoCodec: VideoCodecPreference.h264,
          ),
          'mp4/mkv/webm',
          reason: 'MP4 must stay MP4-first at $h; swap removed in v2',
        );
      }
    });

    test('MP4 stays MP4-first under unbounded best (premium path)', () {
      expect(
        svc.resolveMergeFormatPriority(
          container: ContainerFormatPreference.mp4,
          targetHeight: null,
          isUnboundedQuality: true,
        ),
        'mp4/mkv/webm',
        reason: 'No more isUnboundedQuality swap; planner handles codec fit',
      );
    });

    test('MKV preference always lists MKV first', () {
      for (final h in [720, 1440, 2160]) {
        expect(
          svc.resolveMergeFormatPriority(
            container: ContainerFormatPreference.mkv,
            targetHeight: h,
          ),
          'mkv/mp4/webm',
        );
      }
    });

    test('WebM preference always lists WebM first', () {
      for (final h in [720, 1080, 1440]) {
        expect(
          svc.resolveMergeFormatPriority(
            container: ContainerFormatPreference.webm,
            targetHeight: h,
          ),
          'webm/mkv/mp4',
        );
      }
    });

    test('recoded containers route through universal MKV intermediate — '
        'incl. M4V (Wave A DEFER: M4V is sold as iTunes/Apple TV import, '
        'so output must stay H.264/AAC; an av01 no-op into .m4v would '
        'break that promise)', () {
      for (final c in [
        ContainerFormatPreference.avi,
        ContainerFormatPreference.mov,
        ContainerFormatPreference.m4v,
        ContainerFormatPreference.flv,
      ]) {
        expect(
          svc.resolveMergeFormatPriority(container: c),
          'mkv/mp4/webm',
          reason: 'recoded $c must merge to universal native first',
        );
      }
    });
  });

  group('resolveEffectiveContainer — always returns user pick', () {
    test('MP4 stays MP4 at every height (no swap)', () {
      for (final h in [720, 1080, 1440, 2160]) {
        expect(
          svc.resolveEffectiveContainer(
            container: ContainerFormatPreference.mp4,
            targetHeight: h,
          ),
          ContainerFormatPreference.mp4,
        );
      }
    });

    test('Unbounded MP4 still stays MP4 (planner handles codec fit)', () {
      expect(
        svc.resolveEffectiveContainer(
          container: ContainerFormatPreference.mp4,
          isUnboundedQuality: true,
        ),
        ContainerFormatPreference.mp4,
      );
    });

    test('Every container returns itself verbatim', () {
      for (final c in ContainerFormatPreference.values) {
        expect(svc.resolveEffectiveContainer(container: c), c);
      }
    });
  });

  group('buildSelection — pick X → get X (no warning swap)', () {
    test('1080p MP4 specific: MP4-first, no warning', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1080),
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.mp4,
        ),
      );
      expect(result.mergeFormatPriority, 'mp4/mkv/webm');
      expect(result.videoFormat, 'mp4');
      expect(result.warning, isNull);
    });

    test(
      '1440p MP4 specific: STILL MP4-first, NO container-change warning',
      () {
        // Contract change in v2: pick X → get X. At 1440p the planner
        // (downstream of buildSelection) will detect codec mismatch
        // and emit --recode-video mp4; the selector itself should
        // not swap or warn.
        final result = svc.buildSelection(
          const FormatSelectionRequest(
            qualityIntent: DownloadQualityIntent.specific,
            fileType: DownloadFileType.video,
            target: PortableQualityTarget.video(targetHeight: 1440),
            videoCodecPreference: VideoCodecPreference.h264,
            audioCodecPreference: AudioCodecPreference.aac,
            containerFormatPreference: ContainerFormatPreference.mp4,
          ),
        );
        expect(
          result.mergeFormatPriority,
          'mp4/mkv/webm',
          reason: 'MP4 selection must NOT auto-promote to MKV',
        );
        expect(
          result.videoFormat,
          'mp4',
          reason: 'on-disk extension must match user pick',
        );
        expect(
          result.warning,
          isNull,
          reason: 'Planner generates recode notice; selector does not warn',
        );
      },
    );

    test('2160p MP4 specific: same — no swap, no warning', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 2160),
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.mp4,
        ),
      );
      expect(result.mergeFormatPriority, 'mp4/mkv/webm');
      expect(result.videoFormat, 'mp4');
      expect(result.warning, isNull);
    });

    test('1440p MKV specific: MKV-first (already correct)', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.specific,
          fileType: DownloadFileType.video,
          target: PortableQualityTarget.video(targetHeight: 1440),
          videoCodecPreference: VideoCodecPreference.vp9,
          audioCodecPreference: AudioCodecPreference.opus,
          containerFormatPreference: ContainerFormatPreference.mkv,
        ),
      );
      expect(result.mergeFormatPriority, 'mkv/mp4/webm');
      expect(result.videoFormat, 'mkv');
      expect(result.warning, isNull);
    });

    test('recommended (default 1080p) MP4: no swap', () {
      final result = svc.buildSelection(
        const FormatSelectionRequest(
          qualityIntent: DownloadQualityIntent.recommended,
          fileType: DownloadFileType.video,
          videoCodecPreference: VideoCodecPreference.h264,
          audioCodecPreference: AudioCodecPreference.aac,
          containerFormatPreference: ContainerFormatPreference.mp4,
        ),
      );
      expect(result.mergeFormatPriority, 'mp4/mkv/webm');
      expect(result.videoFormat, 'mp4');
      expect(result.warning, isNull);
    });
  });

  // Phase 1b — recoded containers (avi/mov/m4v/flv) trigger --recode-video
  // post-process so yt-dlp can emit a container its muxer does not support
  // natively. Lock the recode-target string + merge-into-native invariant.
  group('resolveRecodeVideo — Phase 1b transcode containers', () {
    test('native mp4/mkv/webm returns null (no transcode)', () {
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.mp4), isNull);
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.mkv), isNull);
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.webm), isNull);
    });

    test('avi returns "avi"', () {
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.avi), 'avi');
    });

    test('mov returns "mov"', () {
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.mov), 'mov');
    });

    test('m4v returns "mp4" (yt-dlp has no .m4v target — extension swap)', () {
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.m4v), 'mp4');
    });

    test('flv returns "flv"', () {
      expect(svc.resolveRecodeVideo(ContainerFormatPreference.flv), 'flv');
    });

    test('recoded containers merge into mkv/mp4/webm (universal safety)', () {
      // yt-dlp cannot merge directly into avi/mov/m4v/flv; the recode flow
      // requires a native intermediate. mkv is universal so it leads the
      // priority — works for any codec the source serves. M4V mp4-first
      // was considered in Wave A and DEFERRED (iTunes/Apple-compat
      // promise requires H.264/AAC output — see ContainerPlanner note).
      for (final c in [
        ContainerFormatPreference.avi,
        ContainerFormatPreference.mov,
        ContainerFormatPreference.m4v,
        ContainerFormatPreference.flv,
      ]) {
        expect(
          svc.resolveMergeFormatPriority(container: c),
          'mkv/mp4/webm',
          reason: 'recoded container $c must merge into universal native first',
        );
      }
    });

    test('recoded containers report requiresRecode=true', () {
      for (final c in [
        ContainerFormatPreference.avi,
        ContainerFormatPreference.mov,
        ContainerFormatPreference.m4v,
        ContainerFormatPreference.flv,
      ]) {
        expect(c.requiresRecode, isTrue, reason: '$c must require recode');
      }
    });

    test('native containers report requiresRecode=false', () {
      for (final c in [
        ContainerFormatPreference.mp4,
        ContainerFormatPreference.mkv,
        ContainerFormatPreference.webm,
      ]) {
        expect(c.requiresRecode, isFalse, reason: '$c must NOT require recode');
      }
    });

    test('recoded containers accept full codec matrix at merge stage', () {
      for (final c in [
        ContainerFormatPreference.avi,
        ContainerFormatPreference.mov,
        ContainerFormatPreference.m4v,
        ContainerFormatPreference.flv,
      ]) {
        expect(
          svc.videoCodecOptionsForContainer(c).length,
          VideoCodecPreference.values.length,
        );
        expect(
          svc.audioCodecOptionsForContainer(c).length,
          AudioCodecPreference.values.length,
        );
      }
    });

    test('extension getter is honest for each new container', () {
      expect(ContainerFormatPreference.avi.extension, 'avi');
      expect(ContainerFormatPreference.mov.extension, 'mov');
      expect(ContainerFormatPreference.m4v.extension, 'm4v');
      expect(ContainerFormatPreference.flv.extension, 'flv');
    });
  });

  // ===========================================================================
  // P0 1080p-regression GOLDEN LOCK — RC-1 / RC-2 / RC-3
  // Invariant: a 1080p pick yields a real >=1080 short-side merged file OR a
  // clear error — NEVER a silent <=480p progressive labelled 1080p.
  // ===========================================================================
  group('P0 golden (b) — YouTube high-res -f has NO progressive /best net', () {
    test(
      'stripped buildBestFormatSelector(1080,mp4,h264/aac) has NO /best[...] tier',
      () {
        // Assemble exactly as the YouTube high-res path does: build the best
        // selector, then apply the YouTube progressive strip (RC-1). NOTE:
        // the accessor strips UNCONDITIONALLY — this locks the STRIP
        // transform, not the production isYouTube gate (which only strips
        // when isYouTube && !extractAudio at ytdlp_datasource:2817-2820).
        final assembled =
            YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest(
              svc.buildBestFormatSelector(
                maxHeight: 1080,
                videoCodec: VideoCodecPreference.h264,
                audioCodec: AudioCodecPreference.aac,
                container: ContainerFormatPreference.mp4,
              ),
            );
        expect(
          assembled,
          isNot(contains('/best[')),
          reason:
              'no single-file progressive /best[...] net on YouTube high-res',
        );
        expect(assembled, isNot(endsWith('/best')));
        // Bounded MERGE tiers must survive so 1080p can still resolve.
        expect(
          assembled,
          contains(
            'bestvideo[vcodec^=avc][height<=1080]+bestaudio[acodec^=aac]',
          ),
        );
        expect(
          assembled,
          contains('bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]'),
        );
      },
    );
  });

  group('P0 golden (c) — sort-first any-codec MERGE tier for native 1080p', () {
    test('native-container 1080p has sort-first lead, NO bare /best', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        videoCodec: VideoCodecPreference.vp9,
        audioCodec: AudioCodecPreference.opus,
        container: ContainerFormatPreference.mkv,
      );
      expect(f, startsWith('bestvideo+bestaudio'));
      expect(f, isNot(endsWith('/best')));
      expect(f, isNot(contains('/best[')));
    });

    test(
      'native MP4 1080p LEADS with one sort-first merge tier; avc1/ext belts follow',
      () {
        final f = svc.buildResolutionFormatSelector(
          height: 1080,
          container: ContainerFormatPreference.mp4,
        );
        expect(f, startsWith('bestvideo+bestaudio/'));
        // The avc1 belt is RETAINED below as a null-safe -f filter (S1).
        expect(
          f,
          contains(
            'bestvideo[vcodec^=avc1][height<=1080]+bestaudio[acodec^=mp4a]',
          ),
        );
        // The codec-biased tiers must NOT precede the any-codec lead tier.
        expect(f, isNot(startsWith('bestvideo[vcodec^=avc1]')));
        expect(f, isNot(contains('/best['))); // no single-file progressive
        expect(f, isNot(endsWith('/best')));
      },
    );
  });

  group('P0 golden (d) — free-tier cap drops the WIDTH-axis single-file net '
      '(RC-3); height-axis net remains as a last-resort progressive', () {
    test(
      'free-tier cap (mp4) has NO width-axis single-file progressive (RC-3)',
      () {
        // 1920-wide landscape: /best[ext=mp4][width<=1080] would match itag-18
        // (640x360) — the short-side-320 silent downgrade. Must be absent.
        final f = svc.buildResolutionFormatSelector(
          height: 1080,
          container: ContainerFormatPreference.mp4,
          allowUnboundedFallback: false,
        );
        expect(
          f,
          isNot(contains('/best[ext=mp4][width<=1080]')),
          reason:
              'width-axis single-file progressive matches 640x360 on landscape',
        );
        // Height-only single-file net survives (RC-3).
        expect(f, endsWith('/best[ext=mp4][height<=1080]'));
        // The legitimate portrait MERGE tier (+bestaudio) must remain — it is
        // the Facebook-portrait path and is PICKFIRST-unreachable on landscape.
        expect(
          f,
          contains('bestvideo[ext=mp4][width<=1080]+bestaudio[ext=m4a]'),
        );
      },
    );

    test(
      'default (allowUnboundedFallback:null) 1080p mp4 has NO /best[...]',
      () {
        final f = svc.buildResolutionFormatSelector(
          height: 1080,
          container: ContainerFormatPreference.mp4,
        );
        expect(f, isNot(contains('/best[')));
        expect(f, isNot(endsWith('/best')));
      },
    );
  });

  // ===========================================================================
  // RC-2-v3 SELECTOR-LAB — S1..S6 scenario matrix. The blocker invariant is
  // structural: the lead tier must be a SINGLE `bestvideo+bestaudio` pool.
  // yt-dlp `/` is first-match-wins, so height/width slash-OR cannot express
  // short-side semantics for multi-rendition portrait. `-S res:1080` carries
  // the target and sorts landscape/portrait inside that single pool.
  // ===========================================================================
  group('RC-2-v3 selector-lab S1..S6', () {
    // Shorthand tier fragments.
    const anyLead = 'bestvideo+bestaudio';
    const avcH =
        'bestvideo[vcodec^=avc1][height<=1080]+bestaudio[acodec^=mp4a]';
    const extH = 'bestvideo[ext=mp4][height<=1080]+bestaudio[ext=m4a]';

    test('S1 COMMON — MP4 1080p: one any-codec lead tier, avc1 belt below', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        container: ContainerFormatPreference.mp4,
      );
      expect(f, startsWith('$anyLead/'));
      // avc1 belt retained (null-safe -f) BUT strictly AFTER the lead tier.
      expect(f, contains('/$avcH'));
      expect(f.indexOf(anyLead), lessThan(f.indexOf(avcH)));
      // FAILS on Blocker-1 HEAD where f started with the avc1 tier.
      expect(f, isNot(startsWith('bestvideo[vcodec^=avc1]')));
      // S1 sort: equal-res tiebreak resolves to avc1 via the DL-002
      // soft vcodec:h264 pref (ext:mp4 alone could NOT — YouTube av01
      // is also ext=mp4 and outranked h264 in the default ordering).
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mp4,
          targetHeight: 1080,
        ),
        'res:1080,vcodec:h264,ext:mp4:m4a',
      );
    });

    test('S2 BLOCKER1 — avc1@720 cannot short-circuit vp9@1080', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        container: ContainerFormatPreference.mp4,
      );
      // The structural guarantee: tier 1 is unfiltered, so vp9@1080 and
      // avc1@720 are in the SAME pool; -S res:1080 chooses the 1080 stream.
      expect(f.indexOf(anyLead), 0);
      expect(f.indexOf(avcH), greaterThan(0));
      expect(f.indexOf(extH), greaterThan(f.indexOf(avcH)));
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mp4,
          targetHeight: 1080,
        ),
        startsWith('res:1080'),
      );
    });

    test('S3 EMPTY-MKV — MKV 1080p: pure sort-first any-codec merge', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        container: ContainerFormatPreference.mkv,
      );
      expect(f, anyLead);
      expect(f, isNot(contains('vcodec')));
      expect(f, isNot(contains('/best['))); // no single-file progressive net
      expect(f, isNot(endsWith('/best'))); // no bare unbounded tail
    });

    test(
      'S4 EMPTY-MP4 — MP4 1080p: vp9-only@1080 is reachable via the lead '
      'tier (1080p attempted, never silent lower); avc1/ext tiers empty out',
      () {
        final f = svc.buildResolutionFormatSelector(
          height: 1080,
          container: ContainerFormatPreference.mp4,
        );
        // The lead any-codec tier matches vp9@1080 when no avc1/mp4-ext exists.
        expect(f, startsWith('$anyLead/'));
        // Resolution cap holds: bounded, no unbounded /best net at default.
        expect(f, isNot(contains('/best['))); // no single-file progressive net
        expect(f, isNot(endsWith('/best'))); // no bare unbounded tail
      },
    );

    test('S5 PORTRAIT — no height/width slash-OR before sort-first lead', () {
      final f = svc.buildResolutionFormatSelector(
        height: 1080,
        container: ContainerFormatPreference.mp4,
      );
      expect(f, startsWith('$anyLead/'));
      expect(
        svc.buildSortOptions(
          container: ContainerFormatPreference.mp4,
          targetHeight: 1080,
        ),
        'res:1080,vcodec:h264,ext:mp4:m4a',
      );
    });

    test('S6 BEST/RECOMMENDED — buildBestFormatSelector(maxHeight:1080,mp4): '
        'any-codec lead tier FIRST survives the YouTube strip → vp9-only@1080 '
        'NOT formatUnavailable (Blocker 2)', () {
      final raw = svc.buildBestFormatSelector(
        maxHeight: 1080,
        container: ContainerFormatPreference.mp4,
      );
      // Lead any-codec merge tier ahead of avc1 (mirrors the resolution
      // builder). FAILS on Blocker-2 HEAD (best builder had NO any-codec
      // merge tier — avc1 → ext → single-file only).
      expect(raw, startsWith('$anyLead/'));
      // After the production YouTube progressive strip removes the
      // single-file /best[ext=mp4][height<=1080] net, the lead merge tier
      // SURVIVES → a vp9-only@1080 source still resolves at 1080p.
      final stripped =
          YtDlpDataSource.stripYouTubeProgressiveBestFallbackForTest(raw)!;
      expect(stripped, startsWith('$anyLead/'));
      expect(stripped, isNot(contains('/best[')));
      expect(stripped, contains(anyLead));
    });
  });

  // ===========================================================================
  // RC-2-v2 PRODUCTION-PATH — exercises the REAL datasource -f assembly
  // (isYouTube && !extractAudio strip applied to the assembled -f via the
  // @visibleForTesting buildYouTubeFormatArgsForTest seam). The strip-helper
  // test alone does NOT prove the production gate routes the strip onto the
  // real -f (Codex flag); this does.
  // ===========================================================================
  group('RC-2-v2 production -f assembly (datasource seam)', () {
    test('YouTube video pick: strip removes the /best net, the any-codec lead '
        'merge tier reaches yt-dlp -f; -S defaults to res,ext:mp4:m4a', () {
      final selector = svc.buildBestFormatSelector(
        maxHeight: 1080,
        container: ContainerFormatPreference.mp4,
      );
      final args = YtDlpDataSource.buildYouTubeFormatArgsForTest(
        url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        format: selector,
        // DL-002: production sortOptions for MP4 now carries vcodec:h264.
        sortOptions: 'res:1080,vcodec:h264,ext:mp4:m4a',
      );
      expect(args.first, '-f');
      final fArg = args[1];
      // Strip APPLIED on the production path: no progressive single-file net.
      expect(fArg, isNot(contains('/best[')));
      expect(fArg, isNot(endsWith('/best')));
      // The any-codec lead tier survived → 1080p still resolvable.
      expect(fArg, startsWith('bestvideo+bestaudio/'));
      // -S present, res-primary, passed through verbatim (DL-002 string).
      expect(args[2], '-S');
      expect(args[3], 'res:1080,vcodec:h264,ext:mp4:m4a');
    });

    test(
      'non-YouTube (TikTok) pick: strip NOT applied — /best net preserved',
      () {
        final selector = svc.buildBestFormatSelector(
          maxHeight: 1080,
          container: ContainerFormatPreference.mp4,
        );
        final args = YtDlpDataSource.buildYouTubeFormatArgsForTest(
          url: 'https://www.tiktok.com/@u/video/123',
          format: selector,
          sortOptions: 'res,ext:mp4:m4a',
        );
        // Gate is isYouTube — TikTok keeps the single-file net intact.
        expect(args[1], contains('/best[ext=mp4][height<=1080]'));
      },
    );

    test(
      'YouTube audio-extract: strip NOT applied (gate is !extractAudio)',
      () {
        final selector = svc.buildBestFormatSelector(
          maxHeight: 1080,
          container: ContainerFormatPreference.mp4,
        );
        final args = YtDlpDataSource.buildYouTubeFormatArgsForTest(
          url: 'https://youtu.be/dQw4w9WgXcQ',
          format: selector,
          sortOptions: null,
          extractAudio: true,
        );
        // extractAudio bypasses the video strip; net survives.
        expect(args[1], contains('/best[ext=mp4][height<=1080]'));
        // Null sortOptions → literal default.
        expect(args[3], 'res,ext:mp4:m4a');
      },
    );
  });
}
