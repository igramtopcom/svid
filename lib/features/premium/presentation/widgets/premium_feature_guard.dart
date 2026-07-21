import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/premium_feature.dart';
import '../providers/premium_providers.dart';
import 'upgrade_prompt_dialog.dart';

/// Utility for guarding premium actions at the point of invocation.
///
/// Unlike [PremiumGate] which wraps UI, this guards action callbacks.
///
/// Usage:
/// ```dart
/// onTap: () => PremiumFeatureGuard.run(
///   ref: ref,
///   context: context,
///   feature: PremiumFeature.scheduledDownloads,
///   action: () => _showSchedulePicker(),
/// )
/// ```
class PremiumFeatureGuard {
  PremiumFeatureGuard._();

  /// Check if a feature is available, and if not, show upgrade dialog.
  /// Returns `true` if the action was executed, `false` if blocked.
  static Future<bool> run({
    required WidgetRef ref,
    required BuildContext context,
    required PremiumFeature feature,
    required VoidCallback action,
  }) async {
    final isAvailable = ref.read(premiumFeatureProvider(feature));
    if (isAvailable) {
      action();
      return true;
    }

    await UpgradePromptDialog.showAndNavigate(context, ref, feature: feature);
    return false;
  }

  /// Check if a feature is available without showing a dialog.
  static bool isAvailable(WidgetRef ref, PremiumFeature feature) {
    return ref.read(premiumFeatureProvider(feature));
  }
}
