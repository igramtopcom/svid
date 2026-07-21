import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../providers/activity_center_providers.dart';

/// Horizontal bar chart showing download format distribution.
/// Video formats: brand color, Audio: purple, Image: teal.
class ActivityFormatBars extends ConsumerWidget {
  const ActivityFormatBars({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final formatData = ref.watch(formatDistributionProvider);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    if (formatData.isEmpty) {
      return _buildEmpty(context);
    }

    final total = formatData.values.fold<int>(0, (sum, c) => sum + c);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.smMd),
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
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ],
      ),
      child: Column(
        children:
            formatData.entries.map((entry) {
              final percentage = total > 0 ? entry.value / total : 0.0;
              final barColor = _formatColor(entry.key);

              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    // Format label
                    SizedBox(
                      width: 54,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),

                    // Bar
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final barWidth = constraints.maxWidth * percentage;
                          return Stack(
                            children: [
                              // Track
                              Container(
                                height: 14,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: AppOpacity.divider,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.card,
                                  ),
                                ),
                              ),
                              // Fill
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeOut,
                                width: barWidth.clamp(
                                  0.0,
                                  constraints.maxWidth,
                                ),
                                height: 14,
                                decoration: BoxDecoration(
                                  color: barColor,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.card,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Percentage
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${(percentage * 100).toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: AppOpacity.overlay,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : AppColors.border(context).withValues(alpha: 0.72),
        ),
      ),
      child: Center(
        child: Text(
          AppLocalizations.activityCenterNoCompletedDownloads,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(
              alpha: AppOpacity.scrim,
            ),
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  /// Color for a format category.
  /// Video formats: brand (#8D021F), Audio: purple (#7C3AED), Image: teal (#0891B2).
  Color _formatColor(String format) {
    const videoFormats = {
      'MP4',
      'MKV',
      'WEBM',
      'AVI',
      'MOV',
      'FLV',
      'WMV',
      'M4V',
    };
    const audioFormats = {
      'MP3',
      'FLAC',
      'M4A',
      'AAC',
      'OGG',
      'OPUS',
      'WAV',
      'WMA',
    };

    if (videoFormats.contains(format)) return AppColors.brand;
    if (audioFormats.contains(format)) return const Color(0xFF7C3AED);
    if (format == 'Image') return const Color(0xFF0891B2);
    return AppColors.statusQueued; // Other
  }
}
