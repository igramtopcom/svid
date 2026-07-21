/// V2 — Maps an active [FormatPresetExtended] onto a video's available
/// [Quality] options so the home command bar can auto-pick a download
/// without showing the picker dialog (UI Spec §5.4 — "active preset
/// drives the download").
///
/// Pure logic — no Riverpod, no I/O — so the precedence rule
///
///   explicit sheet choice > active command preset > platform saved
///   preference > global settings
///
/// can be unit-tested independently. Caller (`HomeDownloadMixin
/// .handleDownloadDecision`) treats a null return as "no preset auto-
/// pick, fall through to the next rule".
library;

import '../../../../core/utils/platform_detector.dart';
import '../../../downloads/domain/entities/video_info.dart';
import '../../../downloads/domain/services/quality_resolution_parser.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../entities/format_preset_extended.dart';

/// Outcome of a preset → quality match attempt.
///
/// Three distinct outcomes, each with a different caller contract:
///   - [PresetMatched] — auto-download with this quality
///   - [PresetBlocked] — user explicit `block` fallback fired; skip
///     Rule 2, surface dialog so the user picks consciously
///   - [PresetScopeMismatch] — preset is platform-scoped but the URL
///     doesn't match its scope; fall through to the next rule (the
///     preset has nothing to say about this video)
///   - [PresetNoCandidate] — preset can't pick (wrong media type,
///     empty list); fall through to the next rule
sealed class PresetMatchOutcome {
  const PresetMatchOutcome();
}

/// Matcher found a quality that satisfies the preset.
final class PresetMatched extends PresetMatchOutcome {
  final Quality quality;
  const PresetMatched(this.quality);
}

/// Preset configured `fallbackBehavior == block`, the requested
/// resolution wasn't available, and the user explicitly opted in to
/// "don't auto-download a different quality". Caller MUST skip the
/// platform-saved-preference rule and surface the picker dialog so the
/// user makes a conscious choice.
final class PresetBlocked extends PresetMatchOutcome {
  const PresetBlocked();
}

/// Preset has a `platformScope` set (e.g. it's an imported saved-pref
/// shadow named "📌 TikTok (đã lưu)") but the URL the user just pasted
/// is for a different platform. The preset has no opinion on this
/// video — caller falls through to the next rule (savedPref / dialog)
/// without surprise UX. This is the resolution that prevents the
/// "TikTok preset bleeds into YouTube downloads" surprise.
final class PresetScopeMismatch extends PresetMatchOutcome {
  const PresetScopeMismatch();
}

/// Preset can't auto-pick on this video (wrong media type, empty
/// available list, etc.). Caller falls through to the next rule
/// (platform saved pref → dialog).
final class PresetNoCandidate extends PresetMatchOutcome {
  const PresetNoCandidate();
}

class PresetQualityMatcher {
  PresetQualityMatcher._();

  /// Selects a [Quality] from [available] that best matches [preset]
  /// and returns a [PresetMatchOutcome] describing the result.
  ///
  /// Resolution rules (in order):
  ///   1. **Scope check** — if `preset.platformScope` is set and
  ///      [videoPlatform] doesn't match it, return [PresetScopeMismatch]
  ///      immediately. This honours the per-platform semantic of
  ///      imported saved-pref shadows: a preset named "📌 TikTok"
  ///      auto-fires only on TikTok URLs even when activated.
  ///   2. **Media type filter** — `audioOnly` preset → audio
  ///      candidates only.
  ///   3. **Container preference** — soft-prefer matching container.
  ///   4. **Quality pick**:
  ///      - audio: closest bitrate to `audioBitrate` (or first if null)
  ///      - video w/ `maxResolution == 0`: highest available height
  ///      - video w/ explicit `maxResolution`: exact match → fallback
  ///        rule (`nearest` / `higher` / `block`)
  ///
  /// [videoPlatform] is the [VideoPlatform] of the URL being
  /// processed. Pass [VideoPlatform.unknown] when scope shouldn't be
  /// enforced (test environments / non-URL contexts).
  static PresetMatchOutcome match({
    required FormatPresetExtended preset,
    required List<Quality> available,
    VideoPlatform videoPlatform = VideoPlatform.unknown,
    bool isPremium = true,
  }) {
    // Scope gate — must run BEFORE media-type filter so a platform-
    // scoped preset never even looks at qualities for a different
    // platform's video. The matcher's contract is "this preset is
    // silent on this video"; the caller falls through to the next
    // rule (savedPref / dialog) instead of force-applying.
    final scope = preset.platformScope;
    if (scope != null && scope.isNotEmpty) {
      final urlPlatform = videoPlatform.toDbString();
      if (urlPlatform != scope) {
        return const PresetScopeMismatch();
      }
    }

    if (available.isEmpty) return const PresetNoCandidate();

    final wantAudio = preset.audioOnly;
    final candidates =
        available
            .where(
              (q) =>
                  wantAudio
                      ? q.mediaType == MediaType.audio
                      : q.mediaType == MediaType.video,
            )
            .toList();
    if (candidates.isEmpty) return const PresetNoCandidate();

    // Container preference soft-filter — prefer source candidates whose
    // qualityText already names the target container ('mp4', 'webm',
    // 'mkv', 'mp3', etc.). When the filter empties the pool we fall
    // back to the unfiltered list and let yt-dlp's container override
    // (`containerFormatOverride` in DownloadConfig) remux on the fly.
    // Soft instead of hard so a preset of "MP4" never returns
    // NoCandidate just because the source library happens to ship
    // WebM-only — the user still gets the video, yt-dlp just remuxes.
    final containerFiltered = _filterByContainer(candidates, preset.containerFormat);

    if (wantAudio) {
      return PresetMatched(_pickAudio(containerFiltered, preset.audioBitrate));
    }

    // Premium-aware effective target. The "Auto / Tự động (cao nhất)"
    // built-in is `maxResolution: 0` ("best available"). For free
    // users that resolves to 4K on YouTube → premium gate L2 fires
    // inside startDownloadWithQuality → upgrade prompt every paste.
    // Cap the effective target to the free-tier ceiling so the picked
    // Quality clears L2 silently. Explicit non-zero presets (1080p
    // MP4, 4K cao nhất) pass through unchanged — if a free user
    // explicitly chose 4K, the existing L2 dialog is correct UX
    // (their choice, not a default landing).
    final effectiveTarget =
        (preset.maxResolution == 0 && !isPremium)
            ? PremiumLimits.freeMaxResolutionP
            : preset.maxResolution;

    return _pickVideo(
      containerFiltered,
      effectiveTarget,
      preset.fallbackBehavior,
    );
  }

  /// Returns [candidates] filtered to entries whose [Quality.qualityText]
  /// (case-insensitive) names [containerFormat]. When the literal
  /// `'auto'` / empty container is passed, or the filter produces an
  /// empty list, the original [candidates] are returned unchanged so
  /// the caller still has something to pick from.
  static List<Quality> _filterByContainer(
    List<Quality> candidates,
    String containerFormat,
  ) {
    if (containerFormat.isEmpty || containerFormat == 'auto') {
      return candidates;
    }
    final needle = containerFormat.toLowerCase();
    final filtered = candidates
        .where((q) => q.qualityText.toLowerCase().contains(needle))
        .toList();
    return filtered.isEmpty ? candidates : filtered;
  }

  /// Backwards-compat helper used by the original Tier B Rule 1.5 wire.
  /// Returns the matched [Quality] for the success case and null for
  /// blocked / no-candidate / scope-mismatch — callers that need the
  /// full outcome (e.g. to honour `block` or `scope-mismatch` distinct
  /// from no-candidate) should switch to [match] which exposes the
  /// sealed [PresetMatchOutcome].
  ///
  /// Scope check is applied with [videoPlatform] (defaults to
  /// `VideoPlatform.unknown` so universal presets still match).
  @Deprecated('Use match() to distinguish blocked / scope-mismatch / no-candidate')
  static Quality? matchOrFallback({
    required FormatPresetExtended preset,
    required List<Quality> available,
    VideoPlatform videoPlatform = VideoPlatform.unknown,
    bool isPremium = true,
  }) {
    final outcome = match(
      preset: preset,
      available: available,
      videoPlatform: videoPlatform,
      isPremium: isPremium,
    );
    return outcome is PresetMatched ? outcome.quality : null;
  }

  static Quality _pickAudio(List<Quality> candidates, int? targetKbps) {
    if (targetKbps == null) return candidates.first;
    // Sort by absolute bitrate distance — `tbr` is kbps when present.
    candidates.sort((a, b) {
      final aBr = (a.tbr ?? 0).round();
      final bBr = (b.tbr ?? 0).round();
      return (aBr - targetKbps).abs().compareTo((bBr - targetKbps).abs());
    });
    return candidates.first;
  }

  static PresetMatchOutcome _pickVideo(
    List<Quality> candidates,
    int targetHeight,
    FormatPresetFallback fallback,
  ) {
    if (targetHeight == 0) {
      // "Best available" — pick highest height we can parse.
      candidates.sort((a, b) {
        final ah = QualityResolutionParser.heightForQuality(a) ?? 0;
        final bh = QualityResolutionParser.heightForQuality(b) ?? 0;
        return bh.compareTo(ah);
      });
      return PresetMatched(candidates.first);
    }

    final exact = candidates
        .where(
          (q) => QualityResolutionParser.heightForQuality(q) == targetHeight,
        )
        .toList();
    if (exact.isNotEmpty) return PresetMatched(exact.first);

    switch (fallback) {
      case FormatPresetFallback.block:
        return const PresetBlocked();
      case FormatPresetFallback.higher:
        final higher = candidates
            .where(
              (q) =>
                  (QualityResolutionParser.heightForQuality(q) ?? 0) >=
                  targetHeight,
            )
            .toList();
        if (higher.isEmpty) return const PresetNoCandidate();
        higher.sort((a, b) {
          final ah = QualityResolutionParser.heightForQuality(a) ?? 0;
          final bh = QualityResolutionParser.heightForQuality(b) ?? 0;
          return ah.compareTo(bh);
        });
        return PresetMatched(higher.first);
      case FormatPresetFallback.nearest:
        candidates.sort((a, b) {
          final ah = QualityResolutionParser.heightForQuality(a) ?? 0;
          final bh = QualityResolutionParser.heightForQuality(b) ?? 0;
          return (ah - targetHeight).abs().compareTo(
            (bh - targetHeight).abs(),
          );
        });
        return PresetMatched(candidates.first);
    }
  }
}
