import '../entities/video_info.dart';
import 'quality_resolution_parser.dart';

/// Result of a quality fallback attempt.
class QualityFallbackResult {
  /// The selected quality (may be the original or a fallback).
  final Quality quality;

  /// Whether a fallback was applied (false = exact match found).
  final bool isFallback;

  /// Human-readable reason for the fallback (null if no fallback).
  final String? reason;

  const QualityFallbackResult({
    required this.quality,
    required this.isFallback,
    this.reason,
  });
}

/// Service for building quality fallback chains when the preferred quality
/// is unavailable. Used primarily in batch "Apply to All" downloads.
///
/// Fallback priority for video:
///   1. Exact match (same qualityText + mediaType)
///   2. Same codec + closest lower resolution
///   3. Same codec + closest higher resolution
///   4. Different codec + closest lower resolution
///   5. Different codec + closest higher resolution
///   6. Any available of same mediaType (first)
///
/// Fallback priority for audio:
///   1. Exact match
///   2. Closest bitrate (prefer higher)
///   3. Any available audio
class QualityFallbackService {
  const QualityFallbackService();

  /// Find the best matching quality for [preferred] from [available].
  /// Returns null if no quality of the same mediaType exists.
  QualityFallbackResult? findBestMatch(
    Quality preferred,
    List<Quality> available,
  ) {
    if (available.isEmpty) return null;

    // Filter to same media type
    final candidates =
        available.where((q) => q.mediaType == preferred.mediaType).toList();
    if (candidates.isEmpty) return null;

    // 1. Exact match by qualityText
    final exact =
        candidates
            .where((q) => q.qualityText == preferred.qualityText)
            .firstOrNull;
    if (exact != null) {
      return QualityFallbackResult(quality: exact, isFallback: false);
    }

    // Route to type-specific fallback
    if (preferred.mediaType == MediaType.video) {
      return _findVideoFallback(preferred, candidates);
    } else if (preferred.mediaType == MediaType.audio) {
      return _findAudioFallback(preferred, candidates);
    }

    // For image/subtitle: just return first available
    return QualityFallbackResult(
      quality: candidates.first,
      isFallback: true,
      reason: '${preferred.qualityText} unavailable',
    );
  }

  /// Build a prioritized fallback chain for video quality.
  /// Returns ordered list from best to worst match.
  List<Quality> buildFallbackChain(Quality preferred, List<Quality> available) {
    final candidates =
        available.where((q) => q.mediaType == preferred.mediaType).toList();
    if (candidates.isEmpty) return [];

    final preferredHeight = parseHeight(preferred.qualityText);
    final preferredCodec = _normalizeCodec(preferred.vcodec);

    // Score each candidate
    final scored =
        candidates.map((q) {
          final score = _scoreCandidate(
            q,
            preferredHeight: preferredHeight,
            preferredCodec: preferredCodec,
            preferred: preferred,
          );
          return (quality: q, score: score);
        }).toList();

    // Sort by score descending (higher = better match)
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored.map((s) => s.quality).toList();
  }

  QualityFallbackResult _findVideoFallback(
    Quality preferred,
    List<Quality> candidates,
  ) {
    final preferredHeight = parseHeight(preferred.qualityText);
    final preferredCodec = _normalizeCodec(preferred.vcodec);

    if (preferredHeight == null) {
      // Can't determine resolution — return first candidate
      return QualityFallbackResult(
        quality: candidates.first,
        isFallback: true,
        reason: '${preferred.qualityText} unavailable',
      );
    }

    // Score all candidates
    final scored = <(Quality, double)>[];
    for (final q in candidates) {
      final height = parseHeight(q.qualityText);
      if (height == null) continue;

      final codec = _normalizeCodec(q.vcodec);
      final sameCodec =
          preferredCodec != null && codec != null && preferredCodec == codec;

      // Score components:
      // - Codec match: +1000
      // - Resolution closeness: higher weight for lower diff
      // - Prefer lower resolution over higher (downscale safer than upscale)
      double score = 0;
      if (sameCodec) score += 1000;

      final diff = (height - preferredHeight).abs();
      score += 10000.0 / (1 + diff); // Closer = higher score

      // Slight preference for lower resolution (safer fallback)
      if (height <= preferredHeight) score += 50;

      scored.add((q, score));
    }

    if (scored.isEmpty) {
      // No candidates with parseable height
      return QualityFallbackResult(
        quality: candidates.first,
        isFallback: true,
        reason: '${preferred.qualityText} unavailable',
      );
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final best = scored.first.$1;
    final bestHeight = parseHeight(best.qualityText);

    return QualityFallbackResult(
      quality: best,
      isFallback: true,
      reason: '${preferredHeight}p unavailable, using ${bestHeight}p',
    );
  }

  QualityFallbackResult _findAudioFallback(
    Quality preferred,
    List<Quality> candidates,
  ) {
    final preferredBitrate =
        parseAudioBitrate(preferred.qualityText) ?? preferred.tbr?.round();

    if (preferredBitrate == null) {
      return QualityFallbackResult(
        quality: candidates.first,
        isFallback: true,
        reason: '${preferred.qualityText} unavailable',
      );
    }

    // Sort by bitrate closeness, prefer higher bitrate
    final scored = <(Quality, double)>[];
    for (final q in candidates) {
      final bitrate = parseAudioBitrate(q.qualityText) ?? q.tbr?.round();
      if (bitrate == null) continue;

      final diff = (bitrate - preferredBitrate).abs();
      double score = 10000.0 / (1 + diff);
      // Prefer higher bitrate
      if (bitrate >= preferredBitrate) score += 50;

      scored.add((q, score));
    }

    if (scored.isEmpty) {
      return QualityFallbackResult(
        quality: candidates.first,
        isFallback: true,
        reason: '${preferred.qualityText} unavailable',
      );
    }

    scored.sort((a, b) => b.$2.compareTo(a.$2));
    final best = scored.first.$1;

    return QualityFallbackResult(
      quality: best,
      isFallback: true,
      reason: '${preferred.qualityText} unavailable, using ${best.qualityText}',
    );
  }

  double _scoreCandidate(
    Quality candidate, {
    required int? preferredHeight,
    required String? preferredCodec,
    required Quality preferred,
  }) {
    double score = 0;

    // Exact text match = perfect score
    if (candidate.qualityText == preferred.qualityText) return 100000;

    final candidateHeight = parseHeight(candidate.qualityText);
    final candidateCodec = _normalizeCodec(candidate.vcodec);

    // Codec match bonus
    if (preferredCodec != null &&
        candidateCodec != null &&
        preferredCodec == candidateCodec) {
      score += 1000;
    }

    // Resolution closeness
    if (preferredHeight != null && candidateHeight != null) {
      final diff = (candidateHeight - preferredHeight).abs();
      score += 10000.0 / (1 + diff);
      if (candidateHeight <= preferredHeight) score += 50;
    }

    return score;
  }

  /// Parse resolution height from quality text (e.g., "1080p" → 1080, "4K" → 2160).
  static int? parseHeight(String qualityText) {
    return QualityResolutionParser.parseHeight(qualityText);
  }

  /// Parse audio bitrate from quality text (e.g., "320kbps" → 320, "128k" → 128).
  static int? parseAudioBitrate(String qualityText) {
    final match = RegExp(
      r'(\d+)\s*k(?:bps|b/s)?',
      caseSensitive: false,
    ).firstMatch(qualityText);
    if (match != null) return int.tryParse(match.group(1)!);
    return null;
  }

  /// Normalize codec name for comparison.
  static String? _normalizeCodec(String? codec) {
    if (codec == null || codec.isEmpty || codec == 'none') return null;
    final lower = codec.toLowerCase();
    if (lower.startsWith('avc') || lower == 'h264' || lower == 'h.264') {
      return 'h264';
    }
    if (lower == 'vp9' || lower == 'vp09') return 'vp9';
    if (lower == 'av1' || lower == 'av01') return 'av1';
    if (lower == 'aac') return 'aac';
    if (lower == 'opus') return 'opus';
    if (lower == 'mp3') return 'mp3';
    if (lower == 'vorbis') return 'vorbis';
    return lower;
  }
}
