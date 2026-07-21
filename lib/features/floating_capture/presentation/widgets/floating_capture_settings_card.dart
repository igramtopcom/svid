import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/snooze_duration.dart';
import '../../domain/entities/snooze_state.dart';
import '../providers/capture_preferences_provider.dart';
import '../providers/floating_capture_providers.dart';

/// Settings card for the floating capture feature.
///
/// Renders:
///   - A toggle for enabling/disabling capture entirely.
///   - The current snooze status (timed / manual / inactive) with a
///     "Resume now" action when paused.
///
/// Designed to drop into the existing General settings section without
/// requiring changes to the settings repository or its many test fakes.
/// Self-contained: only depends on capture-feature providers.
class FloatingCaptureSettingsCard extends ConsumerWidget {
  const FloatingCaptureSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(capturePreferencesNotifierProvider);
    // Reactive snooze view — auto-updates when the popup snoozes via
    // SnoozeSelected event or the user taps "Resume" below. Initial
    // sync value is seeded by the provider so first paint is correct.
    final snoozeAsync = ref.watch(captureSnoozeStreamProvider);
    final snooze =
        snoozeAsync.value ?? ref.read(captureServiceProvider).currentSnooze;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: AppOpacity.strong);

    return Card(
      margin: EdgeInsets.zero,
      elevation: isDark ? 0 : 1,
      color: isDark ? AppColors.homeDarkCardBg : AppColors.surface2(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandConfig.current.cardRadius),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.copy_all_rounded, size: 20),
            title: Text(AppLocalizations.floatingCaptureSettingsTitle),
            subtitle: Text(AppLocalizations.floatingCaptureSettingsSubtitle),
            value: prefs.enabled,
            onChanged: (value) => _onEnabledChanged(ref, value),
          ),
          if (prefs.enabled) ...[
            Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
              color: borderColor,
            ),
            _SnoozeStatusTile(snooze: snooze),
            Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
              color: borderColor,
            ),
            const _ResetCooldownsTile(),
          ],
        ],
      ),
    );
  }

  Future<void> _onEnabledChanged(WidgetRef ref, bool value) async {
    // Persist the new preference first so a crash mid-toggle doesn't
    // leave the user with a service running against their wishes.
    await ref
        .read(capturePreferencesNotifierProvider.notifier)
        .setEnabled(value);

    final lifecycle = ref.read(captureLifecycleControllerProvider);
    try {
      if (value) {
        await lifecycle.resume();
      } else {
        await lifecycle.pause();
      }
    } catch (e, s) {
      appLogger.error('[CaptureSettings] toggle action failed', e, s);
    }
  }
}

class _SnoozeStatusTile extends ConsumerWidget {
  final SnoozeState snooze;

  const _SnoozeStatusTile({required this.snooze});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManual = snooze.duration == SnoozeDuration.untilManuallyResumed;
    final isTimed = snooze.endsAt != null && !isManual;
    final isActive = snooze.isActive(DateTime.now());

    String subtitleText;
    if (!isActive) {
      subtitleText = AppLocalizations.floatingCaptureStatusActive;
    } else if (isManual) {
      subtitleText = AppLocalizations.floatingCaptureStatusManualSnooze;
    } else if (isTimed) {
      final h = snooze.endsAt!.hour.toString().padLeft(2, '0');
      final m = snooze.endsAt!.minute.toString().padLeft(2, '0');
      subtitleText = AppLocalizations.floatingCaptureStatusTimedSnooze('$h:$m');
    } else {
      subtitleText = AppLocalizations.floatingCaptureStatusActive;
    }

    return ListTile(
      leading: Icon(
        isActive ? Icons.snooze : Icons.notifications_active_outlined,
        size: 20,
      ),
      title: Text(AppLocalizations.floatingCaptureStatusLabel),
      subtitle: Text(subtitleText),
      trailing:
          isActive
              ? TextButton(
                onPressed: () => _resume(ref),
                child: Text(AppLocalizations.floatingCaptureActionResume),
              )
              : null,
    );
  }

  Future<void> _resume(WidgetRef ref) async {
    try {
      await ref.read(captureServiceProvider).resumeFromSnooze();
    } catch (e, s) {
      appLogger.error('[CaptureSettings] resume failed', e, s);
    }
  }
}

/// v2.2 Phase 2A: Settings safety valve to clear all anti-spam cooldowns
/// (RecentUrlTracker Layer 1 + post-action blocklist Layer 4).
///
/// Use case: user reports popup not appearing for legit URL — they hit
/// this button to reset all dedupe state without restarting the app.
class _ResetCooldownsTile extends ConsumerWidget {
  const _ResetCooldownsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.refresh_rounded, size: 20),
      title: Text(AppLocalizations.floatingCaptureResetCooldownsLabel),
      subtitle: Text(AppLocalizations.floatingCaptureResetCooldownsSubtitle),
      trailing: TextButton(
        onPressed: () => _onPressed(context, ref),
        child: Text(AppLocalizations.floatingCaptureResetCooldownsAction),
      ),
    );
  }

  void _onPressed(BuildContext context, WidgetRef ref) {
    try {
      ref.read(captureServiceProvider).resetCooldowns();
      // Brief snackbar feedback so user knows the action took effect.
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.floatingCaptureResetCooldownsDone),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, s) {
      appLogger.error('[CaptureSettings] resetCooldowns failed', e, s);
    }
  }
}
