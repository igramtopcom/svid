import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../domain/entities/media_info.dart';

/// Displays probed media file information in a compact card.
///
/// Shows codec, resolution, fps, bitrate, duration, and file size
/// with visual stream indicators (video/audio/subtitle).
class MediaInfoCard extends StatelessWidget {
  final MediaInfo info;
  final VoidCallback? onRemove;
  final Widget? footer;

  const MediaInfoCard({
    super.key,
    required this.info,
    this.onRemove,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : AppColors.border(context).withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filename + remove button
          Row(
            children: [
              Icon(
                info.hasVideo
                    ? Icons.video_file_rounded
                    : Icons.audio_file_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  info.filename,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onRemove != null)
                InkWell(
                  onTap: onRemove,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Stream badges
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (info.hasVideo)
                _StreamBadge(
                  label: info.videoCodec?.toUpperCase() ?? 'VIDEO',
                  color: AppColors.info(context),
                ),
              if (info.hasAudio)
                _StreamBadge(
                  label: info.audioCodec?.toUpperCase() ?? 'AUDIO',
                  color: AppColors.success(context),
                ),
              if (info.hasSubtitles)
                _StreamBadge(
                  label: AppLocalizations.converterSubsCount(info.subtitleLanguages.length),
                  color: AppColors.warning(context),
                ),
              if (info.containerFormat != null)
                _StreamBadge(
                  label: info.containerFormat!.toUpperCase(),
                  color: cs.tertiary,
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Properties grid
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              if (info.hasVideo && info.width != null)
                _InfoChip(
                  label: 'converter.resolution'.tr(),
                  value: info.resolutionLabel,
                ),
              if (info.duration != null)
                _InfoChip(
                  label: 'home.durationLabel'.tr(),
                  value: info.durationLabel,
                ),
              _InfoChip(
                label: 'mediaInfo.fileSize'.tr(),
                value: info.fileSizeLabel,
              ),
              if (info.fps != null)
                _InfoChip(label: 'converter.fps'.tr(), value: info.fpsLabel),
              if ((info.videoBitrate ?? 0) + (info.audioBitrate ?? 0) > 0)
                _InfoChip(
                  label: 'converter.audioBitrate'.tr(),
                  value: info.bitrateLabel,
                ),
              if (info.audioSampleRate != null)
                _InfoChip(
                  label: 'converter.sampleRate'.tr(),
                  value:
                      '${(info.audioSampleRate! / 1000).toStringAsFixed(1)} kHz',
                ),
            ],
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: footer!),
          ],
        ],
      ),
    );
  }
}

class _StreamBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StreamBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color:
                isDark
                    ? AppColors.homeDarkTextSecondary
                    : cs.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 10,
          ),
        ),
        Text(value, style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
      ],
    );
  }
}
