/// Helpers for building yt-dlp selectors that cap a user-facing
/// resolution across both landscape and portrait media.
///
/// yt-dlp's `height` is the literal pixel height. For portrait
/// 1080x1920 clips that value is 1920, so a plain `[height<=1080]`
/// rejects a valid "1080p" stream. Keep height first to preserve the
/// long-standing landscape path, then add width as the portrait fallback.
class ResolutionFilterUtils {
  const ResolutionFilterUtils._();

  static List<String> boundedDimensionFilters(
    int resolution, {
    bool exactOnly = false,
    // RC-3 (07262027 follow-up): the width axis exists ONLY to keep
    // portrait (1080x1920) streams selectable in the video+audio MERGE
    // tier. On the format_selector single-file progressive net a
    // `[width<=R]` twin adds nothing for portrait and, on a 1920-wide
    // landscape source, matches ONLY itag-18 640x360 (short side 320) —
    // the silent-360p-labelled-1080p trap. The format_selector single-file
    // call sites pass widthAxis:false; every other caller (merge tier,
    // TikTok/ffmpeg-absent, Reddit/HLS, WebM-recode) keeps the default.
    bool widthAxis = true,
  }) {
    final operator = exactOnly ? '=' : '<=';
    return [
      '[height$operator$resolution]',
      if (widthAxis) '[width$operator$resolution]',
    ];
  }

  static List<String> boundedSelectorVariants(
    String selector,
    int? resolution, {
    bool exactOnly = false,
    bool widthAxis = true,
  }) {
    if (resolution == null) return [selector];
    return [
      for (final filter in boundedDimensionFilters(
        resolution,
        exactOnly: exactOnly,
        widthAxis: widthAxis,
      ))
        '$selector$filter',
    ];
  }

  static String joinVideoAudioVariants({
    required String videoSelector,
    required String audioSelector,
    int? resolution,
    bool exactOnly = false,
  }) {
    return boundedSelectorVariants(
      videoSelector,
      resolution,
      exactOnly: exactOnly,
    ).map((video) => '$video+$audioSelector').join('/');
  }

  static String joinSingleFileVariants({
    required String selector,
    int? resolution,
    bool exactOnly = false,
    // RC-3: widthAxis defaults TRUE — only the FormatSelectorService
    // single-file progressive sites (height-only net) pass false. Other
    // callers (TikTok/ffmpeg-absent, Reddit/HLS, WebM-recode) keep both
    // axes; some build their selector SOLELY from single-file variants
    // with no merge tier to fall back to, so dropping width there would
    // break portrait downloads.
    bool widthAxis = true,
  }) {
    return boundedSelectorVariants(
      selector,
      resolution,
      exactOnly: exactOnly,
      widthAxis: widthAxis,
    ).join('/');
  }
}
