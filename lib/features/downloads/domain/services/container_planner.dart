import '../../../../core/utils/platform_detector.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import 'resolution_filter_utils.dart';

/// Pure-Dart decision function: `(pickedContainer, vcodec, acodec) → ContainerPlan`.
///
/// **Contract** (per Chairman's directive, locked by tests):
///   User chọn container X → final file phải có extension X. Always.
///   No silent swap. No "we know better". Slower/lossy is acceptable;
///   wrong container is not.
///
/// **Strategy (RC10 Q-round Codex 2026-05-25 refinement):**
///   - MP4/MKV are native download containers. Emit `--merge-output-format`
///     + `--remux-video` so yt-dlp/ffmpeg merge or stream-copy quickly.
///     Codec values are intentionally ignored — MKV accepts everything,
///     MP4 keeps existing behavior.
///   - WebM is a STRICT native container — only vp8/vp9/av1 video and
///     opus/vorbis audio are valid inside. Source codecs that don't fit
///     (H.264/HEVC video, AAC audio) used to silently fail the post-
///     remux step with "Postprocessing: Conversion failed!" because
///     ffmpeg refuses the invalid mux. New policy: when source codecs
///     are KNOWN to be incompatible, emit `--recode-video webm` instead
///     of `--remux-video webm` so ffmpeg transcodes to VP9/Opus and the
///     user gets a real .webm file. UX surfaces this via the existing
///     RC10.3 `converting` sub-state — no longer "hidden" because the
///     status is explicit. Null/unknown codecs stay permissive so the
///     YouTube "Best Available" path (acodec resolved at download time)
///     keeps its fast remux path.
///   - Recoded containers (avi/mov/m4v/flv) are explicit conversion
///     requests. Merge into a safe intermediate first, then recode.
///
/// **WebM detection at platform-fallback sites must use the source of
/// truth `pickedContainer == webm` / `recodeVideo == 'webm'` /
/// `videoFormat == 'webm'`, never `format.contains('[ext=webm]')` —
/// see [[feedback_webm_output_target_policy]] memory.**
class ContainerPlanner {
  const ContainerPlanner();

  /// Compute the arg plan for a download given the user's container
  /// pick and the source codec profile. [sourceVcodec] and
  /// [sourceAcodec] may be null when the codec is unknown at planning
  /// time (e.g. unbounded "best available" intent where the selector
  /// resolves at download time). Null codecs are treated permissively
  /// for all native containers — including WebM — so the YouTube
  /// adaptive path keeps fast remux even when its quality-level
  /// metadata lacks acodec (audio is a separate DASH stream).
  ContainerPlan plan({
    required ContainerFormatPreference pickedContainer,
    String? sourceVcodec,
    String? sourceAcodec,
    bool isUnboundedQuality = false,
  }) {
    final pickedExt = pickedContainer.extension;

    // Recoded containers (avi/mov/m4v/flv) — yt-dlp's muxer cannot
    // emit these natively. Always merge into universal MKV first,
    // then recode to the user's target. m4v uses recode target 'mp4'
    // and the .mp4 → .m4v rename happens after yt-dlp exits.
    if (pickedContainer.requiresRecode) {
      final recodeTarget =
          pickedContainer == ContainerFormatPreference.m4v ? 'mp4' : pickedExt;
      // Wave A DELIBERATELY DEFERS M4V from the mp4-first runtime
      // prover: the UI sells M4V as "iTunes / Apple TV import", and a
      // no-op'd av01+aac source would yield av01-in-.m4v that iTunes
      // cannot import — a Tier-1 pick-X-get-X violation. The mkv-first
      // intermediate + recode keeps M4V producing H.264/AAC as promised
      // (at transcode cost — the UI copy already says "adds transcode
      // time"). A constrained fast path (mp4-first + avc1-biased
      // selector) is Wave-D design work, register §06-12.
      return ContainerPlan(
        mergeFormat: _universalIntermediate,
        remuxVideo: null,
        recodeVideo: recodeTarget,
        finalExtension: pickedExt,
        requiresRecode: true,
        recodeReason: RecodeReason.recodedContainer,
      );
    }

    // WebM conditional recode (RC10 Q-round 2026-05-25): when source
    // codecs are KNOWN to be incompatible with the WebM container,
    // promote remux → recode so the user gets a real .webm file
    // instead of "Postprocessing: Conversion failed!". Null codecs
    // stay permissive (no recode) — that path is for YouTube adaptive
    // Best Available where audio resolves at download time. Platform
    // fallbacks that explicitly force MP4 selection (TikTok watermark
    // override, Facebook progressive fallback, Reddit HLS-first) must
    // override this null-permissive default at THEIR call site, not
    // here — see [[feedback_webm_output_target_policy]].
    if (pickedContainer == ContainerFormatPreference.webm) {
      final webmReason = _webmIncompatibilityReason(sourceVcodec, sourceAcodec);
      if (webmReason != null) {
        // Wave A — webm-first runtime prover (see
        // [webmRecodeMergeFormatPriority]). Plan-time codec evidence
        // comes from the quality-row REPRESENTATIVE, not the format the
        // selector actually downloads (AUD-8): when the delivery turns
        // out webm-native, target-first lets the recode no-op; when it
        // is genuinely incompatible the merge falls to mkv and the
        // recode fires exactly as before.
        return ContainerPlan(
          mergeFormat: webmRecodeMergeFormatPriority,
          remuxVideo: null,
          recodeVideo: 'webm',
          finalExtension: pickedExt,
          requiresRecode: true,
          recodeReason: webmReason,
        );
      }
    }

    // MP4 conditional recode (2026-06, symmetric with the WebM branch
    // above). MP4's muxer CANNOT hold VP8/VP9 video — yt-dlp's
    // `--remux-video mp4` falls back to a `.mkv` on disk (get_compatible_ext),
    // which the C3 final-extension guard then rejects as a container
    // mismatch → the user's 1080p MP4 pick FAILS on a VP9-only source.
    // This is the 2025-2026 reality: YouTube increasingly gates avc1@1080
    // behind PO-Token/SABR, so a 1080p MP4 pick lands on VP9. Per the
    // "pick X → get X if technically possible" contract, promote
    // remux → recode so FFmpegVideoConvertor transcodes to H.264/AAC and
    // the user gets a REAL .mp4 — surfaced via the same RC10.3
    // `converting` sub-state as WebM (NOT hidden). H.264/H.265/AV1 are
    // MP4-native → fall through to fast remux (the common case, zero
    // quality loss). Null/unknown vcodec stays permissive (best-available
    // resolves codec at download time).
    if (pickedContainer == ContainerFormatPreference.mp4) {
      final mp4Reason = _mp4IncompatibilityReason(sourceVcodec);
      if (mp4Reason != null) {
        // Wave A — mp4-first runtime prover (see
        // [mp4RecodeMergeFormatPriority]); same AUD-8 rationale as the
        // webm arm above.
        return ContainerPlan(
          mergeFormat: mp4RecodeMergeFormatPriority,
          remuxVideo: null,
          recodeVideo: 'mp4',
          finalExtension: pickedExt,
          requiresRecode: true,
          recodeReason: mp4Reason,
        );
      }
    }

    // Native containers (mp4/mkv + webm with compatible/unknown codecs)
    // — fast merge/remux path. MKV stays permissive (accepts every
    // codec); MP4 stays unchanged per RC10.2 spirit; WebM falls through
    // here when codecs are vp8/vp9/av1 + opus/vorbis or unknown.
    return ContainerPlan(
      mergeFormat: pickedExt,
      remuxVideo: pickedExt,
      recodeVideo: null,
      finalExtension: pickedExt,
      requiresRecode: false,
      recodeReason: null,
    );
  }

  /// Decide whether a WebM pick must be promoted from remux → recode
  /// based on source codec compatibility. Returns the [RecodeReason]
  /// when the source codecs are KNOWN to be incompatible with WebM;
  /// returns null when codecs are compatible OR unknown (null) —
  /// permissive so the fast path is taken whenever it might work.
  ///
  /// WebM container spec: video = vp8/vp9/av1, audio = opus/vorbis.
  /// Anything else (H.264/HEVC video, AAC audio) requires re-encode.
  static RecodeReason? _webmIncompatibilityReason(
    String? sourceVcodec,
    String? sourceAcodec,
  ) {
    final v = _normalizeVideoCodec(sourceVcodec);
    final a = _normalizeAudioCodec(sourceAcodec);
    // Video codec is the dominant signal — prefer reporting the video
    // incompatibility when both are wrong (H.264 video carries the
    // primary "this is an MP4 source" semantic).
    if (v != null && !_webmCompatibleVideo.contains(v)) {
      if (v == 'h264') return RecodeReason.h264InWebm;
      if (v == 'hevc') return RecodeReason.hevcInWebm;
      // Unknown-but-not-compatible video codec — still recode, attribute
      // to h264InWebm as the most common case.
      return RecodeReason.h264InWebm;
    }
    if (a != null && !_webmCompatibleAudio.contains(a)) {
      return RecodeReason.aacInWebm;
    }
    return null;
  }

  /// Decide whether an MP4 pick must be promoted from remux → recode
  /// based on source video codec. MP4 natively holds H.264/H.265/AV1;
  /// VP8/VP9 are NOT muxable into MP4 by yt-dlp's remux step (it falls
  /// back to `.mkv` → C3 container-mismatch failure). Returns the reason
  /// when the source video is KNOWN incompatible; null when compatible
  /// OR unknown (permissive — keeps the fast remux path for the common
  /// H.264 case and the best-available codec-at-download-time path).
  ///
  /// Audio is intentionally NOT a trigger here: `--recode-video mp4`
  /// re-encodes the whole stream (video + audio → H.264/AAC), so a
  /// VP9-video trigger already fixes the audio; triggering on audio
  /// alone would needlessly re-encode good H.264 video.
  static RecodeReason? _mp4IncompatibilityReason(String? sourceVcodec) {
    final v = _normalizeVideoCodec(sourceVcodec);
    if (v == 'vp8' || v == 'vp9') {
      return RecodeReason.vp9InMp4;
    }
    return null;
  }

  /// Case-insensitive prefix normalization of a video codec string.
  /// Returns null for null / empty / 'none' input. Recognized values:
  /// 'h264' (matches avc1.*, avc3.*, h264), 'hevc' (matches hvc1.*,
  /// hev1.*, h265, hevc), 'vp8', 'vp9', 'av1' (matches av01.*).
  /// Unknown codec strings return their lowercase form so the caller
  /// can decide permissively.
  static String? _normalizeVideoCodec(String? vcodec) {
    if (vcodec == null) return null;
    final lower = vcodec.trim().toLowerCase();
    if (lower.isEmpty || lower == 'none') return null;
    if (lower.startsWith('avc1') ||
        lower.startsWith('avc3') ||
        lower.startsWith('h264')) {
      return 'h264';
    }
    if (lower.startsWith('hvc1') ||
        lower.startsWith('hev1') ||
        lower.startsWith('hevc') ||
        lower.startsWith('h265')) {
      return 'hevc';
    }
    if (lower.startsWith('vp8')) return 'vp8';
    if (lower.startsWith('vp9')) return 'vp9';
    if (lower.startsWith('av01') || lower.startsWith('av1')) return 'av1';
    return lower;
  }

  /// Case-insensitive prefix normalization of an audio codec string.
  /// Null/empty/'none' → null. mp4a.* → 'aac'. Recognized: opus, vorbis,
  /// aac, mp3, flac, ac3, eac3. Unknown strings → lowercase form.
  static String? _normalizeAudioCodec(String? acodec) {
    if (acodec == null) return null;
    final lower = acodec.trim().toLowerCase();
    if (lower.isEmpty || lower == 'none') return null;
    if (lower.startsWith('mp4a') || lower.startsWith('aac')) return 'aac';
    if (lower.startsWith('opus')) return 'opus';
    if (lower.startsWith('vorbis')) return 'vorbis';
    if (lower.startsWith('mp3')) return 'mp3';
    if (lower.startsWith('flac')) return 'flac';
    if (lower.startsWith('eac3')) return 'eac3';
    if (lower.startsWith('ac3')) return 'ac3';
    return lower;
  }

  static const _webmCompatibleVideo = {'vp8', 'vp9', 'av1'};
  static const _webmCompatibleAudio = {'opus', 'vorbis'};

  /// RC10 Q+1 (2026-05-25 retry-mirror fix) — single source of truth
  /// for "WebM output target needs forced recode + broad source
  /// selector" across BOTH fresh download path
  /// ([StartDownloadUseCase]) and retry path
  /// (`DownloadsNotifier._buildRetryPlanFromSettings`). Without a
  /// shared helper the two paths drifted: fresh got a fix, retry
  /// kept the broken WebM-native-strict selector and still emitted
  /// `bestvideo[vcodec^=vp9]+bestaudio[acodec^=opus]/...[ext=webm]`
  /// which Facebook / Instagram / Reddit reject with "Requested
  /// format is not available" before yt-dlp can recode.
  ///
  /// Returns true when the caller MUST:
  ///   1. Force `recodeVideo = 'webm'` (override planner's
  ///      permissive `remuxVideo='webm'` default).
  ///   2. Replace the WebM-native-strict selector with the broad
  ///      source selector built by [buildWebmRecodeSourceSelector].
  ///   3. Set mergeFormatPriority to the universal intermediate
  ///      `'mkv/mp4/webm'` so yt-dlp's DASH merge step doesn't get
  ///      stuck looking for a WebM container before recode runs.
  ///
  /// Decision rules:
  ///   - Not a WebM target (videoFormat/recodeVideo/remuxVideo all
  ///     non-webm) → returns false. No-op.
  ///   - Recode already set to webm by planner (incompatible codecs
  ///     known) → returns true so caller switches selector to broad.
  ///   - YouTube → returns false. YouTube has reliable WebM-native
  ///     adaptive streams (VP9/Opus); fast remux is correct.
  ///   - Any non-YouTube platform where source codecs don't PROVE
  ///     WebM-native (vp8/vp9/vp09/av1/av01 video AND opus/vorbis
  ///     audio) → returns true. Pessimistic: if we can't confirm
  ///     the source is WebM-compatible, assume recode is needed
  ///     (Facebook/Instagram/Reddit are MP4/H.264/AAC in practice).
  static bool shouldForceWebmOutputRecode({
    required VideoPlatform platform,
    String? videoFormat,
    String? recodeVideo,
    String? remuxVideo,
    String? sourceVcodec,
    String? sourceAcodec,
  }) {
    final targetsWebm =
        videoFormat?.toLowerCase() == 'webm' ||
        recodeVideo?.toLowerCase() == 'webm' ||
        remuxVideo?.toLowerCase() == 'webm';
    if (!targetsWebm) return false;
    if (recodeVideo?.toLowerCase() == 'webm') return true;
    if (platform == VideoPlatform.youtube) return false;
    return !_looksWebmNative(
      sourceVcodec: sourceVcodec,
      sourceAcodec: sourceAcodec,
    );
  }

  /// N2/N4 mirror (2026-06) — MP4 analogue of [shouldForceWebmOutputRecode].
  /// Decide whether an MP4 pick must be promoted from remux → recode so
  /// the user gets a REAL .mp4 instead of a `.mkv` that the C3 guard
  /// rejects.
  ///
  /// UNLIKE the WebM helper this is NOT pessimistic: MP4 sources are
  /// overwhelmingly H.264-native, so a blanket "can't prove native →
  /// recode" would needlessly transcode the common case. Force recode
  /// ONLY for the narrow VP9-in-MP4 reality:
  ///   1. Not an MP4 target → false (no-op).
  ///   2. recodeVideo already 'mp4' (planner saw KNOWN vp8/vp9 via
  ///      [_mp4IncompatibilityReason]) → true so the caller keeps it.
  ///   3. Source PROVES MP4-native (h264/hevc/av1) → false. This is the
  ///      fresh MP4+avc1 fast-remux common case — DO NOT recode.
  ///   4. Non-YouTube platform → false. TikTok/IG/Facebook/Reddit serve
  ///      H.264/AAC MP4 in practice; never blanket-transcode them, and
  ///      do NOT diverge from the planner's permissive null-vcodec intent
  ///      (`_mp4IncompatibilityReason` returns null for null/unknown).
  ///   5. Otherwise (YouTube + cannot prove native) → true. This is the
  ///      retry null-vcodec case (codecs not persisted on the DB row)
  ///      AND the PO-Token/SABR fresh edge where extraction advertised
  ///      avc1 but the source row's vcodec is unknown/absent. On YouTube
  ///      a 1080p+ MP4 pick increasingly lands VP9, so recode is the only
  ///      way to honor the pick.
  static bool shouldForceMp4OutputRecode({
    required VideoPlatform platform,
    String? videoFormat,
    String? recodeVideo,
    String? remuxVideo,
    String? sourceVcodec,
  }) {
    final targetsMp4 =
        videoFormat?.toLowerCase() == 'mp4' ||
        recodeVideo?.toLowerCase() == 'mp4' ||
        remuxVideo?.toLowerCase() == 'mp4';
    if (!targetsMp4) return false;
    if (recodeVideo?.toLowerCase() == 'mp4') return true;
    if (_looksMp4Native(sourceVcodec)) return false;
    if (platform != VideoPlatform.youtube) return false;
    return true;
  }

  /// True when the source video codec PROVES the stream is MP4-native
  /// (H.264 / HEVC / AV1). Used by [shouldForceMp4OutputRecode]. A null
  /// or unknown codec is NOT proof — returns false so the YouTube rule
  /// can decide. Reuses the planner's [_normalizeVideoCodec].
  static bool _looksMp4Native(String? sourceVcodec) {
    final v = _normalizeVideoCodec(sourceVcodec);
    return v == 'h264' || v == 'hevc' || v == 'av1';
  }

  /// Merge target for [shouldForceMp4OutputRecode] callers when they
  /// swap remux → recode.
  ///
  /// Wave A (register §06-12 audit) — TARGET-FIRST, not mkv-first.
  /// yt-dlp's `get_compatible_ext` walks `--merge-output-format`
  /// preferences IN ORDER and returns the first ext that is 'mkv' OR
  /// codec-compatible; `FFmpegVideoConvertorPP` never stream-copies and
  /// only NO-OPs when the merged ext already equals the recode target.
  /// With the old `'mkv/mp4/webm'` the merge ALWAYS landed .mkv, so
  /// `--recode-video mp4` fully transcoded even avc1/av01+aac streams
  /// that were already MP4-native — the avoidable half of the 1.7.3
  /// recode storm. With mp4 FIRST the merger's own codec check becomes
  /// the RUNTIME PROVER the plan-time null-vcodec arm never has:
  /// native streams merge straight to .mp4 → recode no-ops (remux
  /// speed); vp9/opus → falls to mkv → recode fires (genuinely
  /// unavoidable). Final extension is .mp4 in BOTH arms — pick-X-get-X
  /// intact. Proven by the A/B/C/D real-download matrix (register
  /// §06-12). Deliberately a DEDICATED value: `_universalIntermediate`
  /// stays mkv-first for the avi/mov/flv tier which always transcodes.
  static const mp4RecodeMergeFormatPriority = 'mp4/mkv/webm';

  /// Build the broad source selector for the WebM-output-target
  /// recode path. yt-dlp picks the best video + best audio at (or
  /// below) the requested user-facing resolution regardless of codec, then
  /// `--recode-video webm` transcodes to VP9 + Opus.
  ///
  /// Caps the requested height by [maxVideoHeight] when a non-null
  /// free-tier limit is in effect, otherwise honors the user pick.
  /// Returns an unbounded selector when both values are
  /// null (true "best available").
  static String buildWebmRecodeSourceSelector({
    int? targetHeight,
    int? maxVideoHeight,
  }) {
    final effectiveHeight = switch ((targetHeight, maxVideoHeight)) {
      (final int target, final int max) => target < max ? target : max,
      (final int target, null) => target,
      (null, final int max) => max,
      (null, null) => null,
    };
    if (effectiveHeight == null) {
      return 'bestvideo+bestaudio/best';
    }
    return '${ResolutionFilterUtils.joinVideoAudioVariants(videoSelector: 'bestvideo', audioSelector: 'bestaudio', resolution: effectiveHeight)}/${ResolutionFilterUtils.joinSingleFileVariants(selector: 'best', resolution: effectiveHeight)}';
  }

  /// True when the source codec metadata PROVES the stream is
  /// WebM-native (VP8/VP9/AV1 video AND Opus/Vorbis audio). Used
  /// by [shouldForceWebmOutputRecode]; pessimistic — both codec
  /// strings must be present and recognized as WebM-compatible.
  static bool _looksWebmNative({String? sourceVcodec, String? sourceAcodec}) {
    final v = sourceVcodec?.trim().toLowerCase();
    final a = sourceAcodec?.trim().toLowerCase();
    final videoOk =
        v != null &&
        v.isNotEmpty &&
        v != 'none' &&
        (v.startsWith('vp8') ||
            v.startsWith('vp9') ||
            v.startsWith('vp09') ||
            v.startsWith('av01') ||
            v.startsWith('av1'));
    final audioOk =
        a != null &&
        a.isNotEmpty &&
        a != 'none' &&
        (a.startsWith('opus') || a.startsWith('vorbis'));
    return videoOk && audioOk;
  }

  /// Merge target for [shouldForceWebmOutputRecode] callers when they
  /// swap to the recode path.
  ///
  /// Wave A (register §06-12 AUD-1) — TARGET-FIRST mirror of
  /// [mp4RecodeMergeFormatPriority]: with the old mkv-first value,
  /// WebM-NATIVE picks (vp9/av01 + opus — yt-dlp's webm codec set is
  /// {av1, vp9, vp8, opus, ...}) merged into .mkv and were then fully
  /// re-encoded by libvpx-vp9 (the slowest encoder in the family) for
  /// nothing. webm FIRST = native streams merge straight to .webm →
  /// `--recode-video webm` no-ops; h264/aac → mkv → recode fires
  /// legitimately. Pairs with the forced-arm sort restore
  /// (`ext:webm:opus`) — without that bias the broad selector picks
  /// AAC audio and defeats this constant on its own (AUD-2).
  static const webmRecodeMergeFormatPriority = 'webm/mkv/mp4';

  /// RC10 Q-round C2 — platform-fallback WebM-target swap.
  ///
  /// When a platform-specific selector override (TikTok watermark-free
  /// branch, Facebook progressive fallback, Reddit HLS-first) FORCES
  /// the format selector to a non-WebM source (typically MP4/H.264/AAC
  /// or HLS-MP4), the planner's null-permissive default (remuxVideo
  /// = 'webm') becomes wrong — yt-dlp will download MP4 then refuse
  /// the --remux-video webm step because H.264/AAC don't fit WebM.
  ///
  /// This helper detects that case and promotes remux → recode so
  /// the override path produces a real .webm file via FFmpegVideoConvertor
  /// (VP9 + Opus). Call from EACH platform-fallback site that overrides
  /// the user's format selector.
  ///
  /// WebM target source-of-truth (Codex condition 1 — never use
  /// `format.contains('[ext=webm]')` because format mutates across
  /// fallbacks): `videoFormat == 'webm'` OR existing `recodeVideo
  /// == 'webm'` OR `remuxVideo == 'webm'`.
  ///
  /// Returns a tuple `(recodeVideo, remuxVideo)`. When the input is
  /// not a WebM-target+remux-only case, returns the inputs unchanged.
  static ({String? recodeVideo, String? remuxVideo})
  promoteWebMRemuxToRecodeForPlatformFallback({
    String? videoFormat,
    String? recodeVideo,
    String? remuxVideo,
  }) {
    final targetsWebm =
        (videoFormat?.toLowerCase() == 'webm') ||
        (recodeVideo?.toLowerCase() == 'webm') ||
        (remuxVideo?.toLowerCase() == 'webm');
    if (!targetsWebm) {
      return (recodeVideo: recodeVideo, remuxVideo: remuxVideo);
    }
    // If recode is already 'webm', planner already decided convert —
    // nothing to promote.
    if (recodeVideo?.toLowerCase() == 'webm') {
      return (recodeVideo: recodeVideo, remuxVideo: remuxVideo);
    }
    // If a NON-WebM recode is already set, leave alone — caller knows
    // better than us (e.g. recoded-tier AVI/MOV path that happens to
    // also have a WebM hint somewhere).
    if (recodeVideo != null && recodeVideo.toLowerCase() != 'webm') {
      return (recodeVideo: recodeVideo, remuxVideo: remuxVideo);
    }
    // Swap remux → recode.
    return (recodeVideo: 'webm', remuxVideo: null);
  }

  /// Universal merge target for explicit conversion containers that
  /// yt-dlp's muxer cannot produce natively. Native containers use their
  /// picked extension directly and never request a hidden transcode.
  static const _universalIntermediate = 'mkv/mp4/webm';
}

/// Result of the planner — describes the yt-dlp args required to
/// honor the user's container pick AND the UX signals the dialog
/// surface needs to render (`requiresRecode` + `recodeReason`).
class ContainerPlan {
  /// Value for `--merge-output-format` (DASH merge step).
  final String mergeFormat;

  /// Value for `--remux-video` when stream-copy remux is sufficient.
  /// Mutually exclusive with [recodeVideo] — yt-dlp accepts both
  /// flags but `--recode-video` overrides, so for clarity we emit
  /// only one. Null when the picked container needs re-encoding.
  final String? remuxVideo;

  /// Value for `--recode-video` for explicit conversion containers
  /// (avi/mov/m4v/flv). Null for native mp4/mkv/webm downloads.
  final String? recodeVideo;

  /// The user-facing extension of the final on-disk file. For m4v
  /// this is `m4v` even though [recodeVideo] is `mp4` — the .mp4 →
  /// .m4v rename happens after the yt-dlp process exits.
  final String finalExtension;

  /// True when [recodeVideo] is set — the UI should surface a
  /// pre-commit notice telling the user this is an explicit conversion.
  final bool requiresRecode;

  /// Why recode is required. Native mp4/mkv/webm downloads leave this
  /// null because they never request hidden conversion.
  final RecodeReason? recodeReason;

  const ContainerPlan({
    required this.mergeFormat,
    required this.remuxVideo,
    required this.recodeVideo,
    required this.finalExtension,
    required this.requiresRecode,
    required this.recodeReason,
  });
}

/// Why the planner returned `requiresRecode = true`.
enum RecodeReason {
  /// The user picked a non-native container (avi/mov/m4v/flv) that
  /// yt-dlp's muxer cannot produce directly. Always recoded.
  recodedContainer,

  /// WebM target with H.264 / AVC1 / AVC3 video codec. WebM container
  /// spec only allows VP8/VP9/AV1 — ffmpeg refuses the mux. Planner
  /// emits `--recode-video webm` so yt-dlp's FFmpegVideoConvertor
  /// transcodes to VP9 (libvpx-vp9) + Opus (libopus).
  h264InWebm,

  /// WebM target with HEVC / HVC1 / H.265 video codec. Same constraint
  /// as [h264InWebm] — WebM container rejects HEVC; auto-recode to VP9.
  hevcInWebm,

  /// WebM target with AAC / MP4a audio codec (and a video codec that
  /// IS WebM-compatible). WebM only allows Opus/Vorbis audio; ffmpeg
  /// refuses the mux. Recode emits VP9 + Opus to produce a valid file.
  aacInWebm,

  /// MP4 target with VP8 / VP9 video codec. MP4's muxer cannot hold
  /// VP9, so yt-dlp's `--remux-video mp4` silently produces a `.mkv`
  /// that the C3 guard rejects. Auto-recode (`--recode-video mp4` →
  /// H.264 + AAC) delivers a real `.mp4` for the user's 1080p MP4 pick
  /// on a VP9-only source (the 2025-2026 PoT/SABR-gated-avc1 reality).
  vp9InMp4,
}
