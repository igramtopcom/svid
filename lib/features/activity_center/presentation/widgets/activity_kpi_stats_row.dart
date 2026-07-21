import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_center_providers.dart';

/// Row of 4 KPI stat cards: Total Downloads, Success Rate, Data Processed, Active Now.
class ActivityKpiStatsRow extends ConsumerWidget {
  const ActivityKpiStatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(activityKpiStatsProvider);

    return Row(
      children: [
        Expanded(
          child: _KpiCard(
            icon: Icons.download_rounded,
            label: AppLocalizations.activityCenterTotalDownloads,
            value: stats.totalDownloads.toString(),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(child: _SuccessRateCard(rate: stats.successRate)),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(
          child: _KpiCard(
            icon: Icons.storage_rounded,
            label: AppLocalizations.activityCenterDataProcessed,
            value: _formatBytes(stats.totalBytesProcessed),
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        Expanded(child: _ActiveNowCard(count: stats.activeCount)),
      ],
    );
  }
}

/// Standard KPI card with icon, label, and value.
class _KpiCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _KpiCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.overlay,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Success Rate card with a small circular indicator.
class _SuccessRateCard extends StatelessWidget {
  final double rate;

  const _SuccessRateCard({required this.rate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final successColor =
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  value: rate / 100,
                  strokeWidth: 2.5,
                  backgroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: AppOpacity.pressed,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(successColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${rate.toStringAsFixed(1)}%',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            AppLocalizations.activityCenterSuccessRate,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Active Now card with a pulsing green dot.
class _ActiveNowCard extends StatefulWidget {
  final int count;

  const _ActiveNowCard({required this.count});

  @override
  State<_ActiveNowCard> createState() => _ActiveNowCardState();
}

class _ActiveNowCardState extends State<_ActiveNowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final activeColor =
        isDark ? AppColors.successGreen : AppColors.lightStatusCompleted;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: borderColor),
        boxShadow:
            isDark
                ? null
                : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: AppOpacity.divider),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (widget.count > 0)
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: activeColor.withValues(
                          alpha: _pulseAnimation.value,
                        ),
                      ),
                    );
                  },
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.onSurface.withValues(
                      alpha: AppOpacity.quarter,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.count.toString(),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            AppLocalizations.activityCenterActiveNow,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(
                alpha: AppOpacity.overlay,
              ),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
}
