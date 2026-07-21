import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/conversion_job.dart';
import '../../domain/entities/conversion_status.dart';
import '../../domain/entities/output_format.dart';
import '../providers/converter_providers.dart';

/// Card displaying a single conversion job with progress, status, and actions.
class ConversionJobCard extends StatelessWidget {
  final ConversionJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final VoidCallback? onPlay;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRevealFile;
  final VoidCallback? onViewLog;
  final VoidCallback? onMoveToTop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const ConversionJobCard({
    super.key,
    required this.job,
    this.onCancel,
    this.onRetry,
    this.onRemove,
    this.onPlay,
    this.onOpenFolder,
    this.onRevealFile,
    this.onViewLog,
    this.onMoveToTop,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isConverting = job.status == ConversionStatus.converting;
    final borderColor =
        isConverting
            ? AppColors.accentHighlight.withValues(alpha: 0.40)
            : isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor, width: isConverting ? 1.5 : 1.0),
        boxShadow:
            isConverting
                ? [
                  BoxShadow(
                    color: AppColors.accentHighlight.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: thumbnail, status icon, filenames, badges, actions
          Row(
            children: [
              // Video thumbnail (lazy-loaded, falls back to status icon space)
              _JobThumbnail(inputPath: job.inputPath, status: job.status),
              const SizedBox(width: 10),

              // Filenames
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.inputFilename,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 12,
                          color:
                              isDark
                                  ? AppColors.homeDarkTextSecondary
                                  : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            job.outputFilename,
                            style: tt.labelSmall?.copyWith(
                              color:
                                  isDark
                                      ? AppColors.homeDarkTextSecondary
                                      : cs.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Preset badge
              if (job.presetName != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    job.presetName!,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // Actions
              _ActionButtons(
                job: job,
                onCancel: onCancel,
                onRetry: onRetry,
                onRemove: onRemove,
                onPlay: onPlay,
                onOpenFolder: onOpenFolder,
                onRevealFile: onRevealFile,
                onViewLog: onViewLog,
                onMoveToTop: onMoveToTop,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
              ),
            ],
          ),

          // Encoder telemetry strip (monospace, tabular)
          const SizedBox(height: 6),
          _EncoderTelemetryLine(job: job),

          // Progress bar (active jobs only)
          if (job.status == ConversionStatus.converting) ...[
            const SizedBox(height: 6),
            _ProgressSection(job: job),
          ],

          // Error message + recovery suggestion
          if (job.status == ConversionStatus.failed &&
              job.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              job.errorMessage!.startsWith('converter.errors.')
                  ? job.errorMessage!.tr()
                  : job.errorMessage!,
              style: tt.labelSmall?.copyWith(color: AppColors.errorRed),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            // Amber suggestion line — actionable recovery hint
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _recoverySuggestion(job.errorMessage!),
                style: tt.labelSmall?.copyWith(
                  color: AppColors.warningAmber.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // Completion info
          if (job.status == ConversionStatus.completed) ...[
            const SizedBox(height: 6),
            _CompletionInfo(job: job),
          ],
        ],
      ),
    );
  }

  String _recoverySuggestion(String error) {
    final lower = error.toLowerCase();
    if (lower.contains('codec') || lower.contains('encoder')) {
      return 'converter.suggestions.changeCodec'.tr();
    }
    if (lower.contains('no space') || lower.contains('disk full')) {
      return 'converter.suggestions.freeSpace'.tr();
    }
    if (lower.contains('permission') || lower.contains('access denied')) {
      return 'converter.suggestions.checkPermissions'.tr();
    }
    if (lower.contains('invalid data') || lower.contains('corrupt')) {
      return 'converter.suggestions.redownload'.tr();
    }
    if (lower.contains('not found') || lower.contains('no such file')) {
      return 'converter.suggestions.checkFile'.tr();
    }
    return 'converter.suggestions.retryOrChange'.tr();
  }
}

/// 36×36 video thumbnail with status overlay. Lazy-loads via the conversion
/// repository's cached extractor and falls back to a plain status icon when
/// the file is audio-only or extraction fails.
class _JobThumbnail extends ConsumerStatefulWidget {
  final String inputPath;
  final ConversionStatus status;

  const _JobThumbnail({required this.inputPath, required this.status});

  @override
  ConsumerState<_JobThumbnail> createState() => _JobThumbnailState();
}

class _JobThumbnailState extends ConsumerState<_JobThumbnail> {
  Future<String?>? _future;

  @override
  void initState() {
    super.initState();
    _future = ref
        .read(conversionRepositoryProvider)
        .getOrExtractInputThumbnail(widget.inputPath);
  }

  @override
  void didUpdateWidget(covariant _JobThumbnail old) {
    super.didUpdateWidget(old);
    if (old.inputPath != widget.inputPath) {
      _future = ref
          .read(conversionRepositoryProvider)
          .getOrExtractInputThumbnail(widget.inputPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 36,
      height: 36,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: cs.surfaceContainerHighest.withValues(alpha: 0.6)),
            FutureBuilder<String?>(
              future: _future,
              builder: (context, snap) {
                final path = snap.data;
                if (path != null && File(path).existsSync()) {
                  return Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder:
                        (_, __, ___) =>
                            Center(child: _StatusIcon(status: widget.status)),
                  );
                }
                return Center(child: _StatusIcon(status: widget.status));
              },
            ),
            // Tiny status pip in the corner so the badge isn't lost behind the
            // thumbnail when extraction succeeds.
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _statusDotColor(widget.status, cs),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusDotColor(ConversionStatus s, ColorScheme cs) {
    switch (s) {
      case ConversionStatus.queued:
      case ConversionStatus.probing:
        return AppColors.statusQueued;
      case ConversionStatus.converting:
        return AppColors.statusDownloading;
      case ConversionStatus.paused:
        return AppColors.warningAmber;
      case ConversionStatus.completed:
        return AppColors.successGreen;
      case ConversionStatus.failed:
        return AppColors.errorRed;
      case ConversionStatus.cancelled:
        return cs.outlineVariant;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final ConversionStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case ConversionStatus.queued:
        return const Icon(
          Icons.hourglass_empty_rounded,
          size: 18,
          color: AppColors.statusQueued,
        );
      case ConversionStatus.probing:
        return const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ConversionStatus.converting:
        return const Icon(
          Icons.sync_rounded,
          size: 18,
          color: AppColors.statusDownloading,
        );
      case ConversionStatus.paused:
        return const Icon(
          Icons.pause_circle_rounded,
          size: 18,
          color: AppColors.warningAmber,
        );
      case ConversionStatus.completed:
        return const Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: AppColors.successGreen,
        );
      case ConversionStatus.failed:
        return const Icon(
          Icons.error_rounded,
          size: 18,
          color: AppColors.errorRed,
        );
      case ConversionStatus.cancelled:
        return Icon(
          Icons.cancel_rounded,
          size: 18,
          color: AppColors.statusQueued,
        );
    }
  }
}

class _ProgressSection extends StatelessWidget {
  final ConversionJob job;

  const _ProgressSection({required this.job});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Crimson progress rail — 3px with glow
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(1),
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: job.progress.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.accentHighlight,
                    borderRadius: BorderRadius.circular(1),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentHighlight.withValues(
                          alpha: 0.50,
                        ),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),

        // Progress details — monospace tabular figures
        Row(
          children: [
            Text(
              job.progressPercent,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.accentHighlight,
                letterSpacing: 0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            if (job.speed != null) ...[
              _MonoChip(text: job.speed!, dim: cs.onSurfaceVariant),
              const SizedBox(width: 10),
            ],
            if (job.eta != null) ...[
              _MonoChip(text: job.etaLabel, dim: cs.onSurfaceVariant),
              const SizedBox(width: 10),
            ],
            _MonoChip(text: job.inputSizeLabel, dim: cs.onSurfaceVariant),
          ],
        ),
      ],
    );
  }
}

/// Single-line monospace telemetry: `ENCODER: libx264 • COPY • AUDIO: aac`
/// for running jobs, with graceful fallbacks for non-encode operations.
class _EncoderTelemetryLine extends StatelessWidget {
  final ConversionJob job;
  const _EncoderTelemetryLine({required this.job});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final segments = _buildSegments();
    if (segments.isEmpty) return const SizedBox.shrink();

    return Row(
      children: [
        for (int i = 0; i < segments.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 6),
            Container(
              width: 2,
              height: 2,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          _MonoKeyValue(
            label: segments[i].$1,
            value: segments[i].$2,
            baseColor: cs.onSurfaceVariant,
          ),
        ],
      ],
    );
  }

  List<(String, String)> _buildSegments() {
    final cfg = job.config;
    final out = <(String, String)>[];

    // Format / container
    out.add((
      'converter.jobBadges.fmt'.tr(),
      cfg.outputFormat.name.toUpperCase(),
    ));

    // Video codec
    if (cfg.videoCodec != null) {
      final v = cfg.videoCodec!;
      if (v == VideoCodecOption.copy) {
        out.add((
          'converter.jobBadges.video'.tr(),
          'converter.jobBadges.copy'.tr(),
        ));
      } else if (v == VideoCodecOption.none) {
        // skip
      } else {
        out.add(('converter.jobBadges.video'.tr(), v.ffmpegName));
      }
    }

    // Audio codec
    if (cfg.audioCodec != null) {
      final a = cfg.audioCodec!;
      if (a == AudioCodecOption.copy) {
        out.add((
          'converter.jobBadges.audio'.tr(),
          'converter.jobBadges.copy'.tr(),
        ));
      } else if (a == AudioCodecOption.none) {
        // skip
      } else {
        out.add(('converter.jobBadges.audio'.tr(), a.ffmpegName));
      }
    }

    return out;
  }
}

/// `LABEL: value` — label in muted tone, value in stronger weight.
class _MonoKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final Color baseColor;

  const _MonoKeyValue({
    required this.label,
    required this.value,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
              color: baseColor.withValues(alpha: 0.55),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              color: baseColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tight monospace chip for speed/eta/size telemetry.
class _MonoChip extends StatelessWidget {
  final String text;
  final Color dim;
  const _MonoChip({required this.text, required this.dim});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: dim,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _CompletionInfo extends StatelessWidget {
  final ConversionJob job;

  const _CompletionInfo({required this.job});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Text(
          '${job.inputSizeLabel} → ${job.outputSizeLabel}',
          style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (job.outputSize != null && job.inputSize > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.successGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: AppColors.successGreen.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Text(
              job.spaceSaved,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.successGreen,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ConversionJob job;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;
  final VoidCallback? onPlay;
  final VoidCallback? onOpenFolder;
  final VoidCallback? onRevealFile;
  final VoidCallback? onViewLog;
  final VoidCallback? onMoveToTop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _ActionButtons({
    required this.job,
    this.onCancel,
    this.onRetry,
    this.onRemove,
    this.onPlay,
    this.onOpenFolder,
    this.onRevealFile,
    this.onViewLog,
    this.onMoveToTop,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isQueued = job.status == ConversionStatus.queued;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reorder controls (queued jobs only)
        if (isQueued && onMoveToTop != null)
          _ActionIcon(
            icon: Icons.vertical_align_top_rounded,
            tooltip: 'converter.jobActions.moveToTop'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onMoveToTop!,
          ),
        if (isQueued && onMoveUp != null)
          _ActionIcon(
            icon: Icons.arrow_upward_rounded,
            tooltip: 'converter.jobActions.moveUp'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onMoveUp!,
          ),
        if (isQueued && onMoveDown != null)
          _ActionIcon(
            icon: Icons.arrow_downward_rounded,
            tooltip: 'converter.jobActions.moveDown'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onMoveDown!,
          ),

        // Cancel (active jobs)
        if (job.status.isActive && onCancel != null)
          _ActionIcon(
            icon: Icons.stop_rounded,
            tooltip: 'converter.jobActions.cancel'.tr(),
            color: AppColors.errorRed,
            onTap: onCancel!,
          ),

        // Retry (failed/cancelled)
        if ((job.status == ConversionStatus.failed ||
                job.status == ConversionStatus.cancelled) &&
            onRetry != null)
          _ActionIcon(
            icon: Icons.refresh_rounded,
            tooltip: 'converter.jobActions.retry'.tr(),
            color: cs.primary,
            onTap: onRetry!,
          ),

        // View ffmpeg log (any state with a log buffer)
        if (onViewLog != null)
          _ActionIcon(
            icon: Icons.terminal_rounded,
            tooltip: 'converter.jobActions.viewLog'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onViewLog!,
          ),

        // Play converted media (completed)
        if (job.status == ConversionStatus.completed && onPlay != null)
          _ActionIcon(
            icon: Icons.play_circle_fill_rounded,
            tooltip: 'Play',
            color: AppColors.accentHighlight,
            onTap: onPlay!,
          ),

        // Reveal file (completed)
        if (job.status == ConversionStatus.completed && onRevealFile != null)
          _ActionIcon(
            icon: Icons.find_in_page_rounded,
            tooltip: 'converter.jobActions.revealFile'.tr(),
            color: cs.primary,
            onTap: onRevealFile!,
          ),

        // Open folder (completed)
        if (job.status == ConversionStatus.completed && onOpenFolder != null)
          _ActionIcon(
            icon: Icons.folder_open_rounded,
            tooltip: 'converter.jobActions.openFolder'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onOpenFolder!,
          ),

        // Remove (terminal states)
        if (job.status.isTerminal && onRemove != null)
          _ActionIcon(
            icon: Icons.close_rounded,
            tooltip: 'converter.jobActions.remove'.tr(),
            color: cs.onSurfaceVariant,
            onTap: onRemove!,
          ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }
}
