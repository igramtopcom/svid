import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../../downloads/data/datasources/ytdlp_datasource.dart';
import '../../domain/entities/youtube_search_result.dart';

/// Right-side detail panel for the selected video.
/// Shows thumbnail, metadata, quality selector, and download button.
/// Quality data is lazy-loaded via ytdlpExtractInfo.
class VideoDetailPanel extends StatelessWidget {
  final YouTubeSearchResult video;
  final YtDlpVideoInfo? videoDetail;
  final bool isLoading;
  final String? error;
  final VoidCallback onDownload;
  final VoidCallback onClose;

  const VideoDetailPanel({
    super.key,
    required this.video,
    this.videoDetail,
    this.isLoading = false,
    this.error,
    required this.onDownload,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Command Center header
        Container(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smMd, AppSpacing.sm, AppSpacing.smMd),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? const Color(0xFF313A45)
                    : cs.outlineVariant.withValues(alpha: AppOpacity.quarter),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                AppLocalizations.youtubeSearchCurrentlySelected,
                style: AppTypography.compact.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.0,
                  color: isDark
                      ? AppColors.accentHighlight
                      : cs.primary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, size: 16,
                  color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.medium)),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  minimumSize: const Size(28, 28),
                ),
              ),
            ],
          ),
        ),
        // Scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Channel: circular avatar. Video: 16:9 thumbnail.
                if (video.isChannel) ...[
                  Center(
                    child: ClipOval(
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: CachedNetworkImage(
                          imageUrl: video.thumbnail ?? '',
                          fit: BoxFit.cover,
                          memCacheWidth: 160,
                          memCacheHeight: 160,
                          placeholder: (_, __) => Container(
                            color: isDark
                                ? const Color(0xFF1B2128)
                                : AppColors.lightSurface2,
                            child: Icon(
                              Icons.person_rounded,
                              size: 36,
                              color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: isDark
                                ? const Color(0xFF1B2128)
                                : AppColors.lightSurface2,
                            child: Icon(
                              Icons.person_rounded,
                              size: 36,
                              color: cs.onSurface.withValues(alpha: AppOpacity.quarter),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: video.maxResThumbnail ?? video.highQualityThumbnail ?? video.thumbnail ?? '',
                          fit: BoxFit.cover,
                          memCacheWidth: 640,
                          memCacheHeight: 360,
                          placeholder: (_, __) => Container(
                            color: isDark
                                ? const Color(0xFF1B2128)
                                : AppColors.lightSurface2,
                            child: Center(
                              child: Icon(
                                Icons.play_circle_outline,
                                size: 36,
                                color: cs.onSurface.withValues(alpha: AppOpacity.pressed),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => CachedNetworkImage(
                            imageUrl: video.highQualityThumbnail ?? video.thumbnail ?? '',
                            fit: BoxFit.cover,
                            memCacheWidth: 640,
                            memCacheHeight: 360,
                            placeholder: (_, __) => Container(
                              color: isDark ? const Color(0xFF1B2128) : AppColors.lightSurface2,
                            ),
                            errorWidget: (_, __, ___) => Container(
                              color: isDark ? const Color(0xFF1B2128) : AppColors.lightSurface2,
                              child: Center(
                                child: Icon(Icons.broken_image_outlined, size: 32,
                                  color: cs.onSurface.withValues(alpha: AppOpacity.subtle)),
                              ),
                            ),
                          ),
                        ),
                        // Play overlay
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: AppOpacity.scrim),
                            child: Center(
                              child: Icon(Icons.play_arrow_rounded, size: 48,
                                color: Colors.white.withValues(alpha: AppOpacity.nearOpaque)),
                            ),
                          ),
                        ),
                        // Duration badge
                        if (video.formattedDuration.isNotEmpty)
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: AppOpacity.nearOpaque),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                video.formattedDuration,
                                style: AppTypography.compact.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                // Title — bold, tight tracking
                Text(
                  video.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.25,
                    letterSpacing: -0.3,
                    color: isDark ? AppColors.darkLightText : cs.onSurface,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Channel + stats
                if (video.isChannel)
                  Row(
                    children: [
                      Icon(Icons.person_rounded, size: 14,
                          color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.medium)),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        AppLocalizations.youtubeSearchChannel,
                        style: AppTypography.statusBadge.copyWith(
                          color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.overlay),
                        ),
                      ),
                      if (video.formattedViewCount.isNotEmpty)
                        Text(
                          ' · ${video.formattedViewCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.medium),
                          ),
                        ),
                    ],
                  )
                else
                  Text(
                    [
                      if (video.channel != null) video.channel!,
                      if (video.formattedViewCount.isNotEmpty) video.formattedViewCount,
                    ].join(' · '),
                    style: AppTypography.statusBadge.copyWith(
                      letterSpacing: 0.5,
                      color: isDark ? AppColors.accentHighlight : cs.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                // Video-only: a slim one-line tech summary + the quality list.
                // The Download button is pinned in the fixed footer below so it
                // never falls under the fold.
                if (!video.isChannel) ...[
                  const SizedBox(height: AppSpacing.smMd),
                  if (videoDetail != null) ...[
                    _buildMetadataSection(context),
                    const SizedBox(height: AppSpacing.smMd),
                  ],
                  _buildQualitySection(context),
                ],

                // Channel description
                if (video.isChannel && video.description != null && video.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppLocalizations.youtubeSearchAbout,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: AppOpacity.strong),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    video.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: AppOpacity.overlay),
                      height: 1.4,
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
        // Pinned download footer — always visible, no scrolling to reach it.
        if (!video.isChannel)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppColors.border(context), width: 0.5),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(
                  AppLocalizations.youtubeSearchDownload,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.hovered)) {
                      return AppColors.accentHighlight;
                    }
                    return AppColors.brand;
                  }),
                  foregroundColor: const WidgetStatePropertyAll(Colors.white),
                  iconColor: const WidgetStatePropertyAll(Colors.white),
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Metadata (Codec, FPS, Bitrate, Audio) ──────────────────────────────

  Widget _buildMetadataSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final detail = videoDetail!;

    final bestVideo = detail.videoFormats.isNotEmpty ? detail.videoFormats.first : null;
    final bestAudio = detail.audioFormats.isNotEmpty ? detail.audioFormats.first : null;

    final metadataItems = <_MetaItem>[];

    if (bestVideo != null) {
      if (bestVideo.tbr != null && bestVideo.tbr! > 0) {
        final mbps = bestVideo.tbr! / 1000;
        metadataItems.add(_MetaItem(
          label: AppLocalizations.videoDetailMetaBitrate,
          value: mbps >= 1 ? '${mbps.toStringAsFixed(1)} Mbps' : '${bestVideo.tbr!.round()} kbps',
        ));
      }
    }

    if (bestAudio != null && bestAudio.acodec != null && bestAudio.acodec != 'none') {
      metadataItems.add(_MetaItem(
        label: AppLocalizations.videoDetailMetaAudio,
        value: _shortAudioCodec(bestAudio.acodec!),
      ));
    }

    metadataItems.add(_MetaItem(
      label: AppLocalizations.videoDetailMetaSource,
      value: AppLocalizations.videoDetailMetaSourceDirect,
    ));

    if (bestVideo != null && bestVideo.fps != null && bestVideo.fps! > 0) {
      metadataItems.add(_MetaItem(
        label: AppLocalizations.videoDetailMetaFrameRate,
        value: '${bestVideo.fps!.round()} FPS',
      ));
    } else if (detail.uploadDate != null) {
      metadataItems.add(_MetaItem(
        label: AppLocalizations.videoDetailMetaUploaded,
        value: _formatDate(detail.uploadDate!),
      ));
    }

    if (metadataItems.isEmpty) return const SizedBox.shrink();

    // Slim one-line summary (was a heavy boxed 2×2 grid). Drop the hardcoded
    // "Source: Direct" filler — the per-quality codec/size list below already
    // carries the technical detail.
    final summary = metadataItems
        .where((m) => m.value != AppLocalizations.videoDetailMetaSourceDirect)
        .map((m) => m.value)
        .join('  ·  ');
    if (summary.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(Icons.info_outline_rounded,
            size: 13, color: AppColors.metaText(context)),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.homeDarkTextSecondary
                  : AppColors.metaText(context),
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Quality section ────────────────────────────────────────────────────

  Widget _buildQualitySection(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Loading
    if (isLoading) {
      return _buildQualityShimmer(context);
    }

    // Error
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.smMd),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: isDark ? AppOpacity.subtle : AppOpacity.scrim),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_rounded, size: 16, color: cs.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                AppLocalizations.youtubeSearchQualityError,
                style: theme.textTheme.labelSmall?.copyWith(color: cs.error),
              ),
            ),
          ],
        ),
      );
    }

    // No detail yet
    if (videoDetail == null) {
      return const SizedBox.shrink();
    }

    // Build format groups
    final videoFormats = videoDetail!.videoFormats;
    final audioFormats = videoDetail!.audioFormats;

    // Deduplicate by height (keep best per resolution)
    final seenHeights = <int>{};
    final uniqueVideoFormats = <YtDlpFormat>[];
    for (final f in videoFormats) {
      if (f.height != null && seenHeights.add(f.height!)) {
        uniqueVideoFormats.add(f);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header — Command Center style
        Text(
          AppLocalizations.youtubeSearchAvailableQuality,
          style: AppTypography.compact.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
            color: isDark ? AppColors.accentHighlight : cs.primary,
          ),
        ),
        const SizedBox(height: AppSpacing.smMd),
        // Quality cards with accent bars
        if (uniqueVideoFormats.isNotEmpty) ...[
          ...uniqueVideoFormats.take(5).indexed.map(
            (entry) {
              final (i, f) = entry;
              final isBest = i == 0;
              return _QualityCard(
                format: f,
                isBest: isBest,
                type: _FormatType.video,
                onDownload: onDownload,
              );
            },
          ),
        ],
        // Audio formats
        if (audioFormats.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.smMd),
          Text(
            AppLocalizations.youtubeSearchAudioOnly,
            style: AppTypography.mini.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.scrim),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...audioFormats.take(3).map(
            (f) => _QualityCard(format: f, isBest: false, type: _FormatType.audio, onDownload: onDownload),
          ),
        ],
        if (uniqueVideoFormats.isEmpty && audioFormats.isEmpty)
          Container(
            padding: const EdgeInsets.all(AppSpacing.smMd),
            color: isDark ? const Color(0xFF1B2128) : AppColors.lightSurface2,
            child: Text(
              AppLocalizations.youtubeSearchNoFormats,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.medium),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQualityShimmer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accentHighlight.withValues(alpha: AppOpacity.overlay),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              AppLocalizations.youtubeSearchLoadingQuality,
              style: AppTypography.compact.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isDark ? const Color(0xFFA7B1BC) : Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.smMd),
        ...List.generate(
          3,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1B2128) : AppColors.lightSurface2,
                border: Border(
                  left: BorderSide(
                    color: i == 0
                        ? AppColors.brand.withValues(alpha: AppOpacity.scrim)
                        : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _shortAudioCodec(String codec) {
    if (codec.startsWith('mp4a')) return 'AAC';
    if (codec.startsWith('opus')) return 'Opus';
    if (codec.startsWith('vorbis')) return 'Vorbis';
    if (codec.startsWith('flac')) return 'FLAC';
    return codec;
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _MetaItem {
  final String label;
  final String value;
  const _MetaItem({required this.label, required this.value});
}

enum _FormatType { video, audio }

/// Quality card with Command Center accent bar — wine-red for best quality.
class _QualityCard extends StatefulWidget {
  final YtDlpFormat format;
  final bool isBest;
  final _FormatType type;
  final VoidCallback onDownload;

  const _QualityCard({
    required this.format,
    required this.isBest,
    required this.type,
    required this.onDownload,
  });

  @override
  State<_QualityCard> createState() => _QualityCardState();
}

class _QualityCardState extends State<_QualityCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    final quality = widget.format.qualityLabel;
    final ext = widget.format.ext.toUpperCase();
    final size = _formatFileSize(widget.format.filesize);
    final codec = widget.type == _FormatType.video && widget.format.vcodec != null && widget.format.vcodec != 'none'
        ? _shortCodec(widget.format.vcodec!)
        : null;
    final fps = widget.format.fps != null && widget.format.fps! > 0
        ? '${widget.format.fps!.round()} FPS'
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: MouseRegion(
        onEnter: (_) { if (mounted) setState(() => _hovered = true); },
        onExit: (_) { if (mounted) setState(() => _hovered = false); },
        child: GestureDetector(
          onTap: widget.onDownload,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
            decoration: BoxDecoration(
              color: _hovered
                  ? (isDark ? const Color(0xFF242C35) : cs.surfaceContainerHighest)
                  : (isDark ? const Color(0xFF1B2128) : AppColors.lightSurface2),
              border: Border(
                left: BorderSide(
                  color: widget.isBest
                      ? AppColors.brand
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                // Quality + codec info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$quality • $ext',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                          color: widget.isBest
                              ? (isDark ? AppColors.darkLightText : cs.onSurface)
                              : (isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.strong)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        [
                          if (codec != null) codec,
                          if (fps != null) fps,
                          if (size != null) size,
                        ].join(' • '),
                        style: AppTypography.compact.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFA7B1BC) : cs.onSurface.withValues(alpha: AppOpacity.scrim),
                        ),
                      ),
                    ],
                  ),
                ),
                // Download icon
                Icon(
                  widget.isBest ? Icons.download_for_offline_rounded : Icons.download_outlined,
                  size: 20,
                  color: widget.isBest
                      ? AppColors.brand
                      : (_hovered
                          ? AppColors.accentHighlight
                          : (isDark ? const Color(0xFF636D7A) : cs.onSurface.withValues(alpha: AppOpacity.quarter))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _formatFileSize(int? bytes) {
    if (bytes == null || bytes == 0) return null;
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String _shortCodec(String codec) {
    if (codec.startsWith('avc1')) return 'H.264';
    if (codec.startsWith('av01')) return 'AV1';
    if (codec.startsWith('vp9') || codec.startsWith('vp09')) return 'VP9';
    if (codec.startsWith('hev1') || codec.startsWith('hvc1')) return 'H.265';
    return codec;
  }
}
