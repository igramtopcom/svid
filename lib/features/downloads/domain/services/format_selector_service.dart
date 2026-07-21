import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../entities/download_selection_intent.dart';
import 'resolution_filter_utils.dart';

enum QualityFallbackPolicy { exactOnly, nearestLower, nearestWithWarning }

enum FormatSelectionWarningCode {
  exactUnavailable,
  containerChanged,
  authRequired,
  formatUnavailable,
}

class FormatSelectionRequest {
  final DownloadQualityIntent qualityIntent;
  final DownloadFileType fileType;
  final PortableQualityTarget? target;
  final VideoCodecPreference videoCodecPreference;
  final AudioCodecPreference audioCodecPreference;
  final ContainerFormatPreference containerFormatPreference;
  final FpsPreference fpsPreference;
  final QualityFallbackPolicy fallbackPolicy;
  final bool forceRemuxPreference;

  const FormatSelectionRequest({
    required this.qualityIntent,
    required this.fileType,
    this.target,
    this.videoCodecPreference = VideoCodecPreference.auto,
    this.audioCodecPreference = AudioCodecPreference.auto,
    this.containerFormatPreference = ContainerFormatPreference.mp4,
    this.fpsPreference = FpsPreference.auto,
    this.fallbackPolicy = QualityFallbackPolicy.nearestWithWarning,
    this.forceRemuxPreference = false,
  });
}

class FormatSelectionResult {
  final String? formatSelector;
  final String? sortOptions;
  final String? videoFormat;
  final String? audioFormat;
  final bool? forceRemux;
  final PortableQualityTarget? selectedTarget;
  final FormatSelectionWarning? warning;

  /// yt-dlp `--merge-output-format` priority list (e.g. `mkv/mp4/webm`).
  /// When set, the datasource passes this verbatim instead of building a
  /// list from [videoFormat]. The priority is computed by
  /// [FormatSelectorService] which knows when the literal user-preferred
  /// container cannot hold the codec yt-dlp will likely pick — most
  /// notably MP4 at YouTube heights ≥1440p, where the only available
  /// streams are VP9/AV1 video + Opus audio (MP4 cannot hold Opus, so
  /// silently keeping MP4 produces either ffmpeg merge failure or a
  /// silent-audio output file). Putting MKV first lets yt-dlp produce a
  /// honest container that matches the actual content.
  final String? mergeFormatPriority;

  const FormatSelectionResult({
    this.formatSelector,
    this.sortOptions,
    this.videoFormat,
    this.audioFormat,
    this.forceRemux,
    this.selectedTarget,
    this.warning,
    this.mergeFormatPriority,
  });
}

class FormatSelectionWarning {
  final FormatSelectionWarningCode code;
  final String requestedLabel;
  final String? resolvedLabel;
  final String messageKey;

  const FormatSelectionWarning({
    required this.code,
    required this.requestedLabel,
    this.resolvedLabel,
    required this.messageKey,
  });

  @override
  bool operator ==(Object other) {
    return other is FormatSelectionWarning &&
        other.code == code &&
        other.requestedLabel == requestedLabel &&
        other.resolvedLabel == resolvedLabel &&
        other.messageKey == messageKey;
  }

  @override
  int get hashCode =>
      Object.hash(code, requestedLabel, resolvedLabel, messageKey);
}

/// Service for building yt-dlp format selector strings.
///
/// Extracted from [StartDownloadUseCase] for standalone testability.
///
/// **Fallback chain design for [buildResolutionFormatSelector]:**
/// 1. Preferred codec + height constraint — best match.
/// 2. Any codec + height constraint       — codec unavailable.
///
/// It intentionally avoids unrestricted `best` fallback. A specific resolution
/// should choose the nearest compatible stream at or below that height, not
/// silently upgrade to a higher quality.
class FormatSelectorService {
  const FormatSelectorService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  List<VideoCodecPreference> videoCodecOptionsForContainer(
    ContainerFormatPreference container,
  ) {
    // Recoded containers (avi/mov/m4v/flv) are produced AFTER yt-dlp merges
    // into a native container, so codec restrictions follow the intermediate.
    // We merge into MKV (universal) for recode flows, so any codec is OK at
    // the pre-recode stage.
    if (container.requiresRecode) return VideoCodecPreference.values;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return const [
          VideoCodecPreference.auto,
          VideoCodecPreference.h264,
          VideoCodecPreference.h265,
        ];
      case ContainerFormatPreference.webm:
        return const [
          VideoCodecPreference.auto,
          VideoCodecPreference.vp9,
          VideoCodecPreference.av1,
        ];
      case ContainerFormatPreference.mkv:
        return VideoCodecPreference.values;
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        // Unreachable — `requiresRecode` early-return covers these. Returning
        // the full set defensively keeps the switch exhaustive for the
        // analyzer + makes future native-container additions noisy.
        return VideoCodecPreference.values;
    }
  }

  List<AudioCodecPreference> audioCodecOptionsForContainer(
    ContainerFormatPreference container,
  ) {
    if (container.requiresRecode) return AudioCodecPreference.values;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return const [AudioCodecPreference.auto, AudioCodecPreference.aac];
      case ContainerFormatPreference.webm:
        return const [AudioCodecPreference.auto, AudioCodecPreference.opus];
      case ContainerFormatPreference.mkv:
        return AudioCodecPreference.values;
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return AudioCodecPreference.values;
    }
  }

  VideoCodecPreference normalizeVideoCodecForContainer(
    VideoCodecPreference codec,
    ContainerFormatPreference container,
  ) {
    return videoCodecOptionsForContainer(container).contains(codec)
        ? codec
        : VideoCodecPreference.auto;
  }

  AudioCodecPreference normalizeAudioCodecForContainer(
    AudioCodecPreference codec,
    ContainerFormatPreference container,
  ) {
    return audioCodecOptionsForContainer(container).contains(codec)
        ? codec
        : AudioCodecPreference.auto;
  }

  /// Compute the actual container priority list for yt-dlp's
  /// `--merge-output-format`. Returns a `/`-joined merge priority list
  /// that honors the user's container pick AS-IS. No silent swap.
  ///
  /// **Codec compatibility is no longer this method's responsibility.**
  /// Previously this method auto-swapped MP4 → MKV at ≥1440p to dodge
  /// the YouTube Opus-in-MP4 issue. That swap violated the "pick X →
  /// get X" contract: a user picking MP4 ended up with .mkv on disk.
  ///
  /// The current pipeline keeps native containers (mp4/mkv/webm) as
  /// merge/remux-only downloads. Explicit conversion containers
  /// (avi/mov/m4v/flv) still use a universal intermediate and recode
  /// after merge. Legacy parameters [targetHeight] and
  /// [isUnboundedQuality] are kept for binary compatibility but no
  /// longer drive any container swap.
  String resolveMergeFormatPriority({
    required ContainerFormatPreference container,
    int? targetHeight,
    VideoCodecPreference videoCodec = VideoCodecPreference.auto,
    bool isUnboundedQuality = false,
  }) {
    // Recoded containers (avi/mov/m4v/flv) cannot be yt-dlp's merge
    // target — yt-dlp's muxer only emits mp4/mkv/webm. Universal MKV
    // intermediate is the safe path; ContainerPlanner's recodeVideo
    // step transcodes to the user's final extension after merging.
    //
    // Wave A deliberately KEEPS M4V on the universal intermediate (the
    // mp4-first prover was considered and DEFERRED): M4V is sold as
    // "iTunes / Apple TV import", so the output must stay H.264/AAC —
    // an av01 no-op into .m4v would break that promise. See the
    // matching note in ContainerPlanner.plan.
    if (container.requiresRecode) {
      return 'mkv/mp4/webm';
    }
    switch (container) {
      case ContainerFormatPreference.mkv:
        return 'mkv/mp4/webm';
      case ContainerFormatPreference.webm:
        return 'webm/mkv/mp4';
      case ContainerFormatPreference.mp4:
        // No swap and no hidden full conversion. User picked MP4 → merge
        // priority starts with MP4, then the planner adds an idempotent
        // remux to keep the final extension stable. Integrity checks catch
        // unusable outputs instead of silently running a long transcode.
        return 'mp4/mkv/webm';
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        // Unreachable — handled by the `requiresRecode` early-return above.
        return 'mkv/mp4/webm';
    }
  }

  /// Returns the `--recode-video` extension when the user-chosen container
  /// cannot be produced by yt-dlp's merger and needs an ffmpeg transcode
  /// after merge. Returns `null` for native containers (mp4/mkv/webm),
  /// meaning the merge output is the final file with no extra processing.
  ///
  /// Caller wires the returned string straight into the yt-dlp arg list
  /// as `['--recode-video', <ext>]`. yt-dlp accepts: mp4, mkv, mov, avi,
  /// flv, webm, mpg — we restrict to the subset our enum models.
  ///
  /// .m4v note: yt-dlp's `--recode-video m4v` is NOT a registered alias.
  /// We instead recode to `mp4` and rename the extension downstream via
  /// the file extension from `ContainerFormatPreference.extension`, since
  /// .m4v is structurally identical to .mp4 (iTunes wrapper convention).
  String? resolveRecodeVideo(ContainerFormatPreference container) {
    switch (container) {
      case ContainerFormatPreference.mp4:
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.webm:
        return null;
      case ContainerFormatPreference.avi:
        return 'avi';
      case ContainerFormatPreference.mov:
        return 'mov';
      case ContainerFormatPreference.m4v:
        // yt-dlp recode target is mp4; the extension swap happens via the
        // output template using ContainerFormatPreference.extension = 'm4v'.
        return 'mp4';
      case ContainerFormatPreference.flv:
        return 'flv';
    }
  }

  /// Returns the effective output container — the literal user pref is
  /// honored unless [resolveMergeFormatPriority] indicates the priority
  /// list has been reordered. Used by call sites that construct
  /// [FormatSelectionResult] to attach a `containerChanged` warning so
  /// the UI can disclose the swap, AND by the legacy parser
  /// [`StartDownloadUseCase._parseYtdlpFormat`] so its sort-options +
  /// extension stay aligned with the merge priority.
  /// Returns the effective output container — under the new
  /// `pick X → get X` contract this is ALWAYS the user's pick, no
  /// swap. Kept as a method (returns the input verbatim) so existing
  /// callers compile unchanged during the planner migration. The
  /// height/isUnboundedQuality parameters are accepted for binary
  /// compatibility but ignored — ContainerPlanner is the new source
  /// of truth for the codec-vs-container decision.
  ContainerFormatPreference resolveEffectiveContainer({
    required ContainerFormatPreference container,
    int? targetHeight,
    bool isUnboundedQuality = false,
  }) => container;

  /// Build format selector for "best quality" with codec preferences.
  ///
  /// Generates: `{preferred}+{audio}/{any codec video}+{any audio}/best`
  ///
  /// V2 reconcile: [maxHeight] caps the resolution for free-tier users
  /// (e.g. premium gate clamps to 1080p). Null = no cap (premium / OK
  /// to download highest available).
  String buildBestFormatSelector({
    VideoCodecPreference videoCodec = VideoCodecPreference.auto,
    AudioCodecPreference audioCodec = AudioCodecPreference.auto,
    FpsPreference fps = FpsPreference.auto,
    int? maxHeight,
    // RC10 Blocker 4 — same container-aware codec inject as
    // `buildResolutionFormatSelector`. When picked container is
    // MP4/WebM and user hasn't explicitly chosen a codec, derive
    // the codec filter from the container so the selector picks
    // a format that ContainerPlanner can merge/remux without
    // hidden recode.
    ContainerFormatPreference? container,
  }) {
    final videoParts = <String>['bestvideo'];
    final audioParts = <String>['bestaudio'];

    final vcodecFilter =
        videoCodec.ytdlpFilter ?? _vcodecFilterForContainer(container);
    final acodecFilter =
        audioCodec.ytdlpFilter ?? _acodecFilterForContainer(container);

    if (vcodecFilter != null) {
      videoParts.add('[vcodec^=$vcodecFilter]');
    }
    // Wave B (AUD-7) — fps moved OUT of the -f filters into -S as a
    // soft sort key (see buildSortOptions). As a hard `[fps<=N]`
    // filter here it was destructive on the unbounded best path
    // (no any-codec lead tier when maxHeight==null → the filter
    // landed in the FIRST tier → 'Best' + prefer30 on a 60fps-only
    // source silently tanked to 480p30, a B7-class downgrade) and
    // dead code on bounded paths (the unfiltered lead tier always
    // matched first).
    if (acodecFilter != null) {
      audioParts.add('[acodec^=$acodecFilter]');
    }

    final videoSelectorBase = videoParts.join('');
    final audioSelector = audioParts.join('');
    final preferredCandidates = ResolutionFilterUtils.joinVideoAudioVariants(
      videoSelector: videoSelectorBase,
      audioSelector: audioSelector,
      resolution: maxHeight,
    );
    // RC-2-v2 Blocker 2 — RESOLUTION-DOMINANT LEAD TIER, mirrored from
    // `buildResolutionFormatSelector`. The "best" path also front-loads
    // avc1/ext tiers; after the YouTube progressive-strip removes the
    // single-file net, a vp9-only@1080 source would empty all codec
    // tiers → formatUnavailable (S6). Lead with a sort-first any-codec
    // merge tier (only when maxHeight is set — unbounded "best" already
    // resolves any-codec by default) so vp9-only "best" still merges at
    // the requested target. `-S res:H` is a soft target; the datasource
    // ffprobe guard enforces the hard selected-height/free-tier cap before
    // moving the file. The codec tiers below stay as a null-safe belt.
    // Emitted only for capped picks; uncapped "best" keeps the original chain
    // (avc1 first is harmless — no `/` early-stop trap exists without a
    // height bound to strand below).
    final anyCodecLeadTier = maxHeight != null ? 'bestvideo+bestaudio/' : '';
    final hasFilters =
        videoParts.length > 1 || audioParts.length > 1 || maxHeight != null;

    // RC10 Codex-catch C — when container is a NATIVE container
    // (MP4/WebM), the any-codec fallback `/bestvideo+bestaudio/best`
    // CAN match incompatible codecs (e.g., VP9/Opus for MP4) that
    // ContainerPlanner's RC10.2 policy refuses to silently recode.
    // For native containers, keep the fallback chain
    // codec-compatible: prefer ext=<container>, then container-
    // compatible bare codec filters. Avoids "fail with weird codec"
    // outcomes when the source doesn't have the preferred codec.
    final videoExt = _nativeVideoExt(container);
    final audioExt = _nativeAudioExt(container);
    if (hasFilters) {
      // Premium gate: when maxHeight is set, append bounded dimension filters
      // to generic-codec fallbacks too so they don't silently upgrade past cap.
      if (videoExt != null && audioExt != null) {
        // Container-compatible fallback chain — keeps the output a
        // legitimate <container>-codec stream all the way down. yt-dlp
        // resolves `[ext=mp4]` against the format's container, which
        // includes the codec implicitly.
        //
        // RC10 Codex-round-2 catch 2 — video and audio extensions
        // differ per container: MP4 video is `mp4`, but its AAC
        // audio is delivered as `m4a` (separate stream container on
        // YouTube), so `bestaudio[ext=mp4]` rarely matched. WebM is
        // symmetrical (`webm` for both video + Opus audio).
        final extVideoFallback = ResolutionFilterUtils.joinVideoAudioVariants(
          videoSelector: 'bestvideo[ext=$videoExt]',
          audioSelector: 'bestaudio[ext=$audioExt]',
          resolution: maxHeight,
        );
        final extSingleFileFallback =
            ResolutionFilterUtils.joinSingleFileVariants(
              selector: 'best[ext=$videoExt]',
              resolution: maxHeight,
              // RC-3: single-file progressive net is HEIGHT-ONLY. The
              // width twin matched only itag-18 640x360 on landscape
              // (360p labelled 1080p). Portrait stays via the preceding
              // merge tier (joinVideoAudioVariants keeps both axes).
              widthAxis: false,
            );
        return '$anyCodecLeadTier$preferredCandidates'
            '/$extVideoFallback'
            '/$extSingleFileFallback';
      }
      // MKV / recoded-tier — current any-codec fallback is fine
      // because MKV accepts everything (and recoded tier will
      // transcode anyway).
      final anyCodecFallback = ResolutionFilterUtils.joinVideoAudioVariants(
        videoSelector: 'bestvideo',
        audioSelector: 'bestaudio',
        resolution: maxHeight,
      );
      final singleFileFallback = ResolutionFilterUtils.joinSingleFileVariants(
        selector: 'best',
        resolution: maxHeight,
        // RC-3: height-only single-file net (see extSingleFileFallback).
        widthAxis: false,
      );
      // RC-2-v2 — MKV-auto: `preferredCandidates` ALREADY equals the
      // any-codec lead tier (no vcodec filter), so the lead prefix would
      // triple it; skip the prefix and rely on the existing any-codec
      // fallback. MKV-with-explicit-codec: prepend the lead tier so a
      // higher-res non-preferred-codec stream still wins via res-
      // dominance before the explicit-codec tier.
      final mkvLead =
          (videoParts.length > 1 || audioParts.length > 1)
              ? anyCodecLeadTier
              : '';
      return '$mkvLead$preferredCandidates/$anyCodecFallback/$singleFileFallback';
    }
    // No codec filters applied → simplest fallback. Same
    // container-aware path so an MP4 picker with `auto/auto`
    // codecs (which em now bias to `avc1` via Blocker 4) still
    // doesn't silently fall to VP9/Opus.
    if (videoExt != null) {
      return '$preferredCandidates/best[ext=$videoExt]';
    }
    return '$preferredCandidates/best';
  }

  /// RC10 Codex-catch C — return the VIDEO file-extension token for
  /// native containers whose fallback chain MUST stay codec-compatible.
  /// Returns null for null container OR MKV (MKV accepts every
  /// codec — fallback can be any-codec) OR recoded-tier (those go
  /// through the planner's recode path which transcodes anyway).
  static String? _nativeVideoExt(ContainerFormatPreference? container) {
    if (container == null) return null;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return 'mp4';
      case ContainerFormatPreference.webm:
        return 'webm';
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return null;
    }
  }

  /// RC10 Codex-round-2 catch 2 — AUDIO ext for native containers.
  /// MP4 video container pairs with `m4a` audio (AAC in MPEG-4
  /// container — that's how YouTube serves it). WebM is symmetric
  /// (`webm` for Opus audio too). Returning the correct ext means
  /// the fallback selector `bestaudio[ext=...]` actually matches.
  static String? _nativeAudioExt(ContainerFormatPreference? container) {
    if (container == null) return null;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return 'm4a';
      case ContainerFormatPreference.webm:
        return 'webm';
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return null;
    }
  }

  FormatSelectionResult buildSelection(FormatSelectionRequest request) {
    final normalizedVideoCodec = normalizeVideoCodecForContainer(
      request.videoCodecPreference,
      request.containerFormatPreference,
    );
    final normalizedAudioCodec = normalizeAudioCodecForContainer(
      request.audioCodecPreference,
      request.containerFormatPreference,
    );

    switch (request.qualityIntent) {
      case DownloadQualityIntent.bestAvailable:
        final targetHeight = request.target?.targetHeight;
        final isUnbounded = targetHeight == null;
        final effectiveContainer = resolveEffectiveContainer(
          container: request.containerFormatPreference,
          targetHeight: targetHeight,
          isUnboundedQuality: isUnbounded,
        );
        final mergePriority = resolveMergeFormatPriority(
          container: request.containerFormatPreference,
          targetHeight: targetHeight,
          videoCodec: normalizedVideoCodec,
          isUnboundedQuality: isUnbounded,
        );
        return FormatSelectionResult(
          formatSelector: buildBestFormatSelector(
            videoCodec: normalizedVideoCodec,
            audioCodec: normalizedAudioCodec,
            fps: request.fpsPreference,
            maxHeight: targetHeight,
            // RC10 Blocker 4: bias selector toward container's
            // native codec set when user hasn't explicitly chosen.
            container: effectiveContainer,
          ),
          sortOptions: buildSortOptions(
            videoCodec: normalizedVideoCodec,
            audioCodec: normalizedAudioCodec,
            fps: request.fpsPreference,
            container: effectiveContainer,
            targetHeight: targetHeight,
          ),
          videoFormat: effectiveContainer.extension,
          mergeFormatPriority: mergePriority,
          forceRemux: false,
          selectedTarget: request.target,
          warning:
              request.containerFormatPreference == effectiveContainer
                  ? null
                  : FormatSelectionWarning(
                    code: FormatSelectionWarningCode.containerChanged,
                    requestedLabel:
                        request.containerFormatPreference.extension
                            .toUpperCase(),
                    resolvedLabel: effectiveContainer.extension.toUpperCase(),
                    messageKey: 'configDialog.containerChangedWarning',
                  ),
        );
      case DownloadQualityIntent.specific:
        final target = request.target;
        if (request.fileType == DownloadFileType.video &&
            target?.targetHeight != null) {
          final effectiveContainerSpec = resolveEffectiveContainer(
            container: request.containerFormatPreference,
            targetHeight: target!.targetHeight,
          );
          final formatSelector = buildResolutionFormatSelector(
            height: target.targetHeight!,
            videoCodec: normalizedVideoCodec,
            audioCodec: normalizedAudioCodec,
            fps: request.fpsPreference,
            exactOnly:
                request.fallbackPolicy == QualityFallbackPolicy.exactOnly,
            // RC10 Blocker 4: container-aware codec bias.
            container: effectiveContainerSpec,
          );
          final mergePriority = resolveMergeFormatPriority(
            container: request.containerFormatPreference,
            targetHeight: target.targetHeight,
            videoCodec: normalizedVideoCodec,
          );
          // Reuse the already-resolved effective container from
          // before the format-selector build (avoids double work).
          final effectiveContainer = effectiveContainerSpec;
          final containerChangedWarning =
              effectiveContainer == request.containerFormatPreference
                  ? null
                  : FormatSelectionWarning(
                    code: FormatSelectionWarningCode.containerChanged,
                    requestedLabel:
                        request.containerFormatPreference.extension
                            .toUpperCase(),
                    resolvedLabel: effectiveContainer.extension.toUpperCase(),
                    messageKey: 'configDialog.containerChangedWarning',
                  );
          return FormatSelectionResult(
            formatSelector: formatSelector,
            sortOptions: buildSortOptions(
              videoCodec: normalizedVideoCodec,
              audioCodec: normalizedAudioCodec,
              fps: request.fpsPreference,
              container: effectiveContainer,
              targetHeight: target.targetHeight,
            ),
            videoFormat: effectiveContainer.extension,
            mergeFormatPriority: mergePriority,
            forceRemux: request.forceRemuxPreference,
            selectedTarget: target,
            warning: containerChangedWarning,
          );
        }
        if (request.fileType == DownloadFileType.audio) {
          return FormatSelectionResult(
            // DL-003 defense C: `[acodec!=none]` keeps the config-dialog /
            // preset audio path (this selector service) from ever picking
            // a storyboard (vcodec=none/acodec=none) for an audio extract
            // — mirrors the raw-audio fix in StartDownloadUseCase so both
            // audio routes are storyboard-safe.
            formatSelector: 'bestaudio[acodec!=none]/best[acodec!=none]',
            audioFormat: request.target?.outputFormat ?? 'mp3',
            selectedTarget: request.target,
          );
        }
        return FormatSelectionResult(selectedTarget: request.target);
      case DownloadQualityIntent.recommended:
        final recommendedHeight = request.target?.targetHeight ?? 1080;
        final mergePriority = resolveMergeFormatPriority(
          container: request.containerFormatPreference,
          targetHeight: recommendedHeight,
          videoCodec: normalizedVideoCodec,
        );
        final effectiveContainer = resolveEffectiveContainer(
          container: request.containerFormatPreference,
          targetHeight: recommendedHeight,
        );
        return FormatSelectionResult(
          formatSelector: buildResolutionFormatSelector(
            height: recommendedHeight,
            videoCodec: normalizedVideoCodec,
            audioCodec: normalizedAudioCodec,
            fps: request.fpsPreference,
            // RC10 Blocker 4: container-aware codec bias.
            container: effectiveContainer,
          ),
          sortOptions: buildSortOptions(
            videoCodec: normalizedVideoCodec,
            audioCodec: normalizedAudioCodec,
            fps: request.fpsPreference,
            container: effectiveContainer,
            targetHeight: recommendedHeight,
          ),
          videoFormat: effectiveContainer.extension,
          mergeFormatPriority: mergePriority,
          forceRemux: request.forceRemuxPreference,
          selectedTarget:
              request.target ??
              const PortableQualityTarget.video(targetHeight: 1080),
          warning:
              effectiveContainer == request.containerFormatPreference
                  ? null
                  : FormatSelectionWarning(
                    code: FormatSelectionWarningCode.containerChanged,
                    requestedLabel:
                        request.containerFormatPreference.extension
                            .toUpperCase(),
                    resolvedLabel: effectiveContainer.extension.toUpperCase(),
                    messageKey: 'configDialog.containerChangedWarning',
                  ),
        );
      case DownloadQualityIntent.technicalStream:
        return FormatSelectionResult(selectedTarget: request.target);
    }
  }

  /// Build format selector for a specific user-facing [height].
  ///
  /// The lead tier lets yt-dlp rank all orientations in one pool via
  /// `-S res:<height>`, avoiding slash-fallback first-match traps. That sort is
  /// a soft target, so the datasource enforces the hard selected-height /
  /// free-tier cap with an ffprobe guard before moving the final file.
  String buildResolutionFormatSelector({
    required int height,
    VideoCodecPreference videoCodec = VideoCodecPreference.auto,
    AudioCodecPreference audioCodec = AudioCodecPreference.auto,
    FpsPreference fps = FpsPreference.auto,
    bool exactOnly = false,
    bool? allowUnboundedFallback,
    // RC10 Blocker 4 of Ultra Plan v3 — when the user picked a
    // NATIVE container (MP4/WebM), the selector must prefer formats
    // whose codecs fit that container so the ContainerPlanner's
    // "no hidden conversion" policy holds. Without this, free-tier
    // users picking MP4 might get a VP9/Opus stream from YouTube,
    // which the planner now refuses to silently recode → result
    // would be fail instead of a working MP4. Passing the container
    // here lets the selector inject codec preferences ONLY when the
    // user has not explicitly chosen a codec.
    ContainerFormatPreference? container,
  }) {
    final videoParts = <String>['bestvideo'];
    final audioParts = <String>['bestaudio'];

    // Resolve effective codec filters: user choice wins; otherwise
    // derive from container per native-compatibility map.
    final vcodecFilter =
        videoCodec.ytdlpFilter ?? _vcodecFilterForContainer(container);
    final acodecFilter =
        audioCodec.ytdlpFilter ?? _acodecFilterForContainer(container);

    if (vcodecFilter != null) {
      videoParts.add('[vcodec^=$vcodecFilter]');
    }
    // Wave B (AUD-7) — fps lives in -S now, not in -f belts (which the
    // unfiltered lead tier shadowed anyway). See buildSortOptions.
    if (acodecFilter != null) {
      audioParts.add('[acodec^=$acodecFilter]');
    }

    final videoSelector = videoParts.join('');
    final audioSelector = audioParts.join('');
    final hasCodecFilters = videoParts.length > 1 || audioParts.length > 1;

    // RC-2-v3 — RESOLUTION-DOMINANT LEAD TIER. The lead tier must be a
    // SINGLE yt-dlp tier (`bestvideo+bestaudio`) when fallback is allowed.
    // A slash-joined `[height<=H]/[width<=H]` pseudo-OR is still
    // first-match-wins: portrait 540x960 matches the height branch and
    // prevents yt-dlp from ever seeing the 1080x1920 width branch. The
    // target is carried by `-S res:<height>` at production call sites, so
    // yt-dlp sorts landscape and portrait by short-side inside one pool.
    final leadTier =
        exactOnly
            ? ResolutionFilterUtils.joinVideoAudioVariants(
              videoSelector: 'bestvideo',
              audioSelector: 'bestaudio',
              resolution: height,
              exactOnly: true,
            )
            : 'bestvideo+bestaudio';
    final buffer = StringBuffer(leadTier);
    if (hasCodecFilters) {
      // Level 2: preferred codec + bounded dimension, retained as a
      // null-safe `-f` belt BELOW the any-codec lead tier. On YouTube
      // the lead tier already grabbed the highest-res format, so this
      // tier only ever fires when the lead tier is empty — keeping the
      // avc1/container preference deterministic even if `-S` were
      // dropped (3 production -S sites default to a literal string with
      // no vcodec token). Skipped when no codec filters (MKV-auto):
      // the lead tier already IS the any-codec tier; a duplicate would
      // be byte-identical.
      buffer.write('/');
      buffer.write(
        ResolutionFilterUtils.joinVideoAudioVariants(
          videoSelector: videoSelector,
          audioSelector: audioSelector,
          resolution: height,
          exactOnly: exactOnly,
        ),
      );
      // RC10 Codex-catch C — for native containers, also keep an
      // ext=<container> belt so a same-res mp4-wrapped format is
      // reachable by `-f` even without `-S`. MKV / recoded-tier skip
      // this (MKV holds everything + recoded tier transcodes anyway).
      // RC10 Codex-round-2 catch 2 — split video/audio ext (MP4 video
      // pairs with m4a audio, not mp4 audio).
      final videoExt = _nativeVideoExt(container);
      final audioExt = _nativeAudioExt(container);
      if (videoExt != null && audioExt != null) {
        buffer.write('/');
        buffer.write(
          ResolutionFilterUtils.joinVideoAudioVariants(
            videoSelector: 'bestvideo[ext=$videoExt]',
            audioSelector: 'bestaudio[ext=$audioExt]',
            resolution: height,
            exactOnly: exactOnly,
          ),
        );
      }
    }
    // V2 reconcile: [allowUnboundedFallback] gates the FINAL fallback tier.
    //   - null (default)  → no `/best` extra; only the bounded selectors
    //     above. PR #234 strict-by-default contract preserved.
    //   - true (premium)  → unbounded `/best` safety net.
    //   - false (free)    → height-bounded `/best[height<=H]` so the
    //     premium cap is enforced even at the safety-net level.
    // RC10 Codex-catch C — final safety net also stays
    // container-compatible for native containers.
    // Final safety net uses video ext (the wrapper format is what
    // `/best[ext=...]` resolves against).
    final finalVideoExt = _nativeVideoExt(container);
    final containerExtFilter =
        finalVideoExt != null ? '[ext=$finalVideoExt]' : '';
    if (allowUnboundedFallback == true) {
      buffer.write('/best$containerExtFilter');
    } else if (allowUnboundedFallback == false) {
      buffer.write('/');
      buffer.write(
        ResolutionFilterUtils.joinSingleFileVariants(
          selector: 'best$containerExtFilter',
          resolution: height,
          exactOnly: exactOnly,
          // RC-3: height-only single-file free-tier net (see
          // extSingleFileFallback). The bounded merge tiers above keep
          // the width axis for portrait.
          widthAxis: false,
        ),
      );
    }
    return buffer.toString();
  }

  /// Build sort options string for yt-dlp `-S` flag.
  ///
  /// Resolution is always the primary sort key. Codec and extension
  /// preferences are appended when specified.
  String buildSortOptions({
    VideoCodecPreference videoCodec = VideoCodecPreference.auto,
    AudioCodecPreference audioCodec = AudioCodecPreference.auto,
    FpsPreference fps = FpsPreference.auto,
    ContainerFormatPreference container = ContainerFormatPreference.mp4,
    int? targetHeight,
  }) {
    final parts = <String>[
      targetHeight != null ? 'res:$targetHeight' : 'res',
    ]; // Resolution is always primary

    // Wave B (AUD-6/AUD-7) — fps as a SOFT sort key, directly after
    // res. `fps:30` prefers ≤30fps INSIDE the resolution pool and
    // falls back gracefully when no such variant exists — it can
    // reduce file size per the setting's promise but can never
    // downgrade resolution (res stays dominant) and never excludes
    // formats (it is not a filter). Replaces the old hard `[fps<=N]`
    // -f filter that was dead on bounded paths and tanked 'Best' to
    // 480p30 on unbounded ones. Placed BEFORE the codec/ext biases:
    // an explicit user setting outranks internal compatibility
    // preferences.
    if (fps.maxFps != null) {
      parts.add('fps:${fps.maxFps}');
    }
    final normalizedVideoCodec = normalizeVideoCodecForContainer(
      videoCodec,
      container,
    );
    final normalizedAudioCodec = normalizeAudioCodecForContainer(
      audioCodec,
      container,
    );

    if (normalizedVideoCodec != VideoCodecPreference.auto) {
      parts.add('vcodec:${normalizedVideoCodec.ytdlpFilter ?? "avc"}');
    } else if (container == ContainerFormatPreference.mp4 &&
        targetHeight != null &&
        targetHeight <= 1080) {
      // DL-002 fix #0 (height-aware, Wave A) — soft MP4-native codec
      // preference for capped picks ≤1080p ONLY. Without a vcodec
      // token, yt-dlp's default ranking puts av01/vp9 above h264
      // inside the res-capped pool (`ext:mp4:m4a` does NOT exclude
      // av01 — YouTube serves AV1 in mp4), so the lead tier picked a
      // codec the forced-recode arm then transcoded — the 1.7.3
      // recode/timeout storm. ≤1080p, h264 exists on YouTube → avc1
      // pick = fast remux + widest device compatibility at equal
      // speed.
      //
      // ABOVE 1080p the token is deliberately ABSENT: YouTube has no
      // h264 there, and `vcodec:h264` inverts the remaining ranking
      // to vp9-over-av01 — exactly wrong once the runtime-prover
      // merge priority (fix #1, 'mp4/mkv/webm') lands, because
      // av01+aac merges straight into .mp4 (recode no-ops, fast)
      // while vp9 forces a genuine transcode. Default av01-first IS
      // the fast path >1080p. Soft preference, not a filter: no
      // downgrade, no formatUnavailable (S6 intact). Verified live
      // (yt-dlp 2026.06.09-11): 1080p flips av01(f399)→avc1(299);
      // 4K keeps 2160p; av01+m4a → .mp4 merge no-op proven by the
      // A/B/C/D real-download matrix (register §06-12).
      parts.add('vcodec:h264');
    }
    if (normalizedAudioCodec != AudioCodecPreference.auto) {
      parts.add('acodec:${normalizedAudioCodec.ytdlpFilter ?? "mp4a"}');
    }

    switch (container) {
      case ContainerFormatPreference.mp4:
        parts.add('ext:mp4:m4a');
        break;
      case ContainerFormatPreference.webm:
        parts.add('ext:webm:opus');
        break;
      case ContainerFormatPreference.mkv:
        break;
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        // Recoded containers merge into MKV first (see resolveMergeFormatPriority),
        // so sort options match the MKV path — no ext hint needed.
        break;
    }

    return parts.join(',');
  }

  /// RC10 Blocker 4 — yt-dlp `vcodec^=` filter for a native
  /// container when the user has NOT explicitly chosen a video codec
  /// (i.e., `VideoCodecPreference.auto`).
  ///
  /// Returns null for:
  ///   - null container (no preference info available)
  ///   - MKV (universal — no constraint needed)
  ///   - AVI/MOV/M4V/FLV (recoded tier — codec doesn't matter, the
  ///     post-process step transcodes to target encoder anyway)
  ///
  /// Returns the preferred yt-dlp filter for:
  ///   - MP4 → `avc1` (H.264, most-compatible MP4 video codec)
  ///   - WebM → `vp9` (most-common WebM video codec on YouTube)
  ///
  /// This bias means a user picking MP4 on a YouTube video that
  /// offers BOTH avc1+aac AND vp9+opus formats will get the avc1
  /// stream — which the ContainerPlanner can merge into MP4 without
  /// any hidden conversion (Codex's RC10.2 policy).
  static String? _vcodecFilterForContainer(
    ContainerFormatPreference? container,
  ) {
    if (container == null) return null;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return 'avc1';
      case ContainerFormatPreference.webm:
        return 'vp9';
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return null;
    }
  }

  /// RC10 Blocker 4 — yt-dlp `acodec^=` filter for native containers.
  ///
  ///   - MP4 → `mp4a` (AAC — the canonical MP4 audio codec)
  ///   - WebM → `opus` (the canonical WebM audio codec)
  ///
  /// Other containers return null (no constraint).
  static String? _acodecFilterForContainer(
    ContainerFormatPreference? container,
  ) {
    if (container == null) return null;
    switch (container) {
      case ContainerFormatPreference.mp4:
        return 'mp4a';
      case ContainerFormatPreference.webm:
        return 'opus';
      case ContainerFormatPreference.mkv:
      case ContainerFormatPreference.avi:
      case ContainerFormatPreference.mov:
      case ContainerFormatPreference.m4v:
      case ContainerFormatPreference.flv:
        return null;
    }
  }
}
