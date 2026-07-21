import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/core.dart';
import '../../../downloads/domain/entities/download_entity.dart';
import 'media_info_helpers.dart';

/// Dialog showing live-updating video/audio codec information.
class MediaInfoDialog extends StatelessWidget {
  final Player player;
  final DownloadEntity? download;

  const MediaInfoDialog({
    super.key,
    required this.player,
    this.download,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 460,
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface1 : cs.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: cs.outline.withValues(alpha: AppOpacity.divider),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.12),
                blurRadius: isDark ? 28 : 22,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: AppSpacing.edgeInsets.lg,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.accentHighlight.withValues(
                          alpha: AppOpacity.subtle,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.accentHighlight,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Text(
                        AppLocalizations.mediaInfoTitle,
                        style: AppTypography.fileName.copyWith(
                          color: cs.onSurface,
                          fontWeight: AppTypography.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Flexible(
                  child: StreamBuilder<Tracks>(
                    stream: player.stream.tracks,
                    initialData: player.state.tracks,
                    builder: (context, snapshot) {
                      final currentTrack = player.state.track;
                      final videoParams = player.state.videoParams;
                      final audioParams = player.state.audioParams;

                      return SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildSectionHeader(
                              context,
                              AppLocalizations.mediaInfoVideo,
                              Icons.videocam_outlined,
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoCodec,
                              formatCodecName(currentTrack.video.codec),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoResolution,
                              formatResolution(
                                currentTrack.video.w ?? videoParams.w,
                                currentTrack.video.h ?? videoParams.h,
                              ),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoFrameRate,
                              currentTrack.video.fps != null
                                  ? '${currentTrack.video.fps!.toStringAsFixed(1)} fps'
                                  : '—',
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoBitrate,
                              formatBitrate(currentTrack.video.bitrate),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoPixelFormat,
                              videoParams.pixelformat ?? '—',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _buildSectionHeader(
                              context,
                              AppLocalizations.mediaInfoAudio,
                              Icons.audiotrack_outlined,
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoCodec,
                              formatCodecName(currentTrack.audio.codec),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoChannels,
                              formatChannels(
                                currentTrack.audio.channels ?? audioParams.hrChannels,
                                currentTrack.audio.channelscount ?? audioParams.channelCount,
                              ),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoSampleRate,
                              formatSampleRate(
                                currentTrack.audio.samplerate ?? audioParams.sampleRate,
                              ),
                            ),
                            _buildInfoRow(context,
                              AppLocalizations.mediaInfoBitrate,
                              formatBitrate(currentTrack.audio.bitrate),
                            ),
                            if (download != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildSectionHeader(
                                context,
                                AppLocalizations.mediaInfoFile,
                                Icons.insert_drive_file_outlined,
                              ),
                              _buildInfoRow(context,
                                AppLocalizations.mediaInfoFileName,
                                download!.filename,
                              ),
                              _buildInfoRow(context,
                                AppLocalizations.mediaInfoFileSize,
                                formatFileSize(download!.totalBytes),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accentHighlight),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: AppTypography.statusBadge.copyWith(
              color: cs.onSurface,
              fontWeight: AppTypography.bold,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: cs.outline.withValues(alpha: AppOpacity.divider),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTypography.metadata.copyWith(
                color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                fontWeight: AppTypography.medium,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.metadata.copyWith(
                color: cs.onSurface.withValues(alpha: AppOpacity.nearOpaque),
                fontWeight: AppTypography.medium,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
