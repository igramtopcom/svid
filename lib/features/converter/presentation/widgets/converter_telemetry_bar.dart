import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/conversion_status.dart';
import '../../domain/entities/hw_accel_info.dart';
import '../providers/conversion_queue_provider.dart';
import '../providers/converter_providers.dart';

/// Footer telemetry bar — Nocturne "diagnostic monitor" aesthetic.
///
/// Shows live hardware-acceleration status (from `hwAccelInfoProvider`) and
/// a real-time queue summary (converting / queued / completed / failed).
/// This bar is visible whenever the converter screen is open so users can see
/// at a glance which hardware encoder the engine will use and how many jobs
/// are in flight.
class ConverterTelemetryBar extends ConsumerWidget {
  const ConverterTelemetryBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final jobs = ref.watch(conversionQueueProvider);
    final hwAccelAsync = ref.watch(hwAccelInfoProvider);

    final converting = jobs.where((j) => j.status.isActive).length;
    final queued =
        jobs.where((j) => j.status == ConversionStatus.queued).length;
    final completed =
        jobs.where((j) => j.status == ConversionStatus.completed).length;
    final failed =
        jobs.where((j) => j.status == ConversionStatus.failed).length;

    final isLive = converting > 0;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        border: Border(
          top: BorderSide(
            color: AppColors.border(context).withValues(alpha: 0.55),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // LIVE / IDLE indicator
          _LiveIndicator(isLive: isLive),
          const SizedBox(width: 14),
          _Divider(color: cs.outlineVariant),
          const SizedBox(width: 14),

          // HW accel status
          hwAccelAsync.when(
            data: (accels) => _HwAccelChip(accels: accels),
            loading:
                () => _TelemetryChip(
                  label: 'converter.telemetry.hwAccel'.tr(),
                  value: 'converter.telemetry.detecting'.tr(),
                  valueColor: cs.onSurfaceVariant,
                ),
            error:
                (_, __) => _TelemetryChip(
                  label: 'converter.telemetry.hwAccel'.tr(),
                  value: 'converter.telemetry.unknown'.tr(),
                  valueColor: AppColors.warningAmber,
                ),
          ),
          const Spacer(),

          // Queue summary
          _Divider(color: cs.outlineVariant),
          const SizedBox(width: 14),
          _TelemetryChip(
            label: 'converter.telemetry.queue'.tr(),
            value: _queueSummary(
              converting: converting,
              queued: queued,
              completed: completed,
              failed: failed,
            ),
            valueColor: _queueColor(
              converting: converting,
              queued: queued,
              failed: failed,
              cs: cs,
            ),
          ),
        ],
      ),
    );
  }

  String _queueSummary({
    required int converting,
    required int queued,
    required int completed,
    required int failed,
  }) {
    final parts = <String>[];
    if (converting > 0) {
      parts.add('$converting ${'converter.telemetry.running'.tr()}');
    }
    if (queued > 0) {
      parts.add('$queued ${'converter.telemetry.pending'.tr()}');
    }
    if (completed > 0) {
      parts.add('$completed ${'converter.telemetry.done'.tr()}');
    }
    if (failed > 0) {
      parts.add('$failed ${'converter.telemetry.failed'.tr()}');
    }
    if (parts.isEmpty) return 'converter.telemetry.queueIdle'.tr();
    return parts.join(' • ');
  }

  Color _queueColor({
    required int converting,
    required int queued,
    required int failed,
    required ColorScheme cs,
  }) {
    if (failed > 0) return AppColors.errorRed;
    if (converting > 0) return AppColors.statusDownloading;
    if (queued > 0) return AppColors.warningAmber;
    return cs.onSurfaceVariant;
  }
}

/// Pulsing red dot + "LIVE" label when a conversion is running, muted "IDLE" otherwise.
class _LiveIndicator extends StatefulWidget {
  final bool isLive;
  const _LiveIndicator({required this.isLive});

  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dotColor =
        widget.isLive
            ? AppColors.accentHighlight
            : cs.onSurfaceVariant.withValues(alpha: 0.4);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (_, __) {
            final opacity =
                widget.isLive ? (0.4 + 0.6 * _controller.value) : 1.0;
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor.withValues(alpha: opacity),
                shape: BoxShape.circle,
                boxShadow:
                    widget.isLive
                        ? [
                          BoxShadow(
                            color: AppColors.accentHighlight.withValues(
                              alpha: 0.5 * opacity,
                            ),
                            blurRadius: 6,
                          ),
                        ]
                        : null,
              ),
            );
          },
        ),
        const SizedBox(width: 6),
        Text(
          widget.isLive
              ? 'converter.telemetry.live'.tr()
              : 'converter.telemetry.idle'.tr(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: dotColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Hardware acceleration chip — picks the best available accelerator to display.
class _HwAccelChip extends StatelessWidget {
  final List<HwAccelInfo> accels;
  const _HwAccelChip({required this.accels});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final best = _pickBest(accels);

    if (best == null) {
      return _TelemetryChip(
        label: 'converter.telemetry.hwAccel'.tr(),
        value: 'converter.telemetry.cpuOnly'.tr(),
        valueColor: cs.onSurfaceVariant,
      );
    }

    return _TelemetryChip(
      label: 'converter.telemetry.hwAccel'.tr(),
      value: _shortName(best.name),
      valueColor: AppColors.successGreen,
    );
  }

  /// Pick the most capable accelerator: prefer one that supports both H.264 and H.265.
  HwAccelInfo? _pickBest(List<HwAccelInfo> accels) {
    if (accels.isEmpty) return null;
    final usable = accels.where((a) => a.encoders.isNotEmpty).toList();
    if (usable.isEmpty) return null;
    usable.sort((a, b) {
      final scoreA = (a.supportsH264 ? 1 : 0) + (a.supportsH265 ? 1 : 0);
      final scoreB = (b.supportsH264 ? 1 : 0) + (b.supportsH265 ? 1 : 0);
      return scoreB.compareTo(scoreA);
    });
    return usable.first;
  }

  String _shortName(String name) {
    switch (name) {
      case 'videotoolbox':
        return 'VIDEOTOOLBOX';
      case 'cuda':
        return 'NVENC';
      case 'vaapi':
        return 'VAAPI';
      case 'qsv':
        return 'QUICKSYNC';
      case 'd3d11va':
        return 'D3D11VA';
      default:
        return name.toUpperCase();
    }
  }
}

/// Monospace telemetry chip: `LABEL: VALUE` with muted label + bold colored value.
class _TelemetryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _TelemetryChip({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  final Color color;
  const _Divider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 14, color: color.withValues(alpha: 0.5));
  }
}
