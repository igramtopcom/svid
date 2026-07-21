import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';

/// Visual badge indicating download priority level.
///
/// Shows an icon for high (bolt) or low (arrow down) priority.
/// Normal priority shows nothing (returns SizedBox.shrink).
class PriorityBadge extends StatelessWidget {
  final bool isHigh;
  final bool isLow;
  final bool isSmartBoosted;

  const PriorityBadge({
    super.key,
    this.isHigh = false,
    this.isLow = false,
    this.isSmartBoosted = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isHigh || isSmartBoosted) {
      return Tooltip(
        message: isSmartBoosted
            ? AppLocalizations.smartQueueBoostedTooltip
            : AppLocalizations.smartQueuePriorityHigh,
        child: Icon(
          Icons.bolt,
          size: 16,
          color: AppColors.warningAmber,
        ),
      );
    }

    if (isLow) {
      return Tooltip(
        message: AppLocalizations.smartQueuePriorityLow,
        child: Icon(
          Icons.arrow_downward,
          size: 14,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.medium),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
