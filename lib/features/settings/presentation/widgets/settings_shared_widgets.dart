import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../providers/settings_provider.dart';

// =============================================================================
// SHARED BUILDER HELPERS
// =============================================================================

/// Section title with a compact brand marker.
Widget settingsSectionTitle(BuildContext context, String title) {
  final theme = Theme.of(context);
  return Row(
    children: [
      Container(
        width: 4,
        height: 20,
        decoration: BoxDecoration(
          color: AppColors.accentHighlight,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    ],
  );
}

/// Card wrapper using the same V2 surface ladder as the rest of the app.
Widget settingsCard(
  BuildContext context, {
  String? title,
  required List<Widget> children,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  final borderColor =
      isDark
          ? AppColors.homeDarkBorderStrong
          : AppColors.border(context).withValues(alpha: 0.78);

  return Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AppColors.surface2(context),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: borderColor, width: 1),
      boxShadow:
          isDark
              ? null
              : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.smMd,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ...children,
      ],
    ),
  );
}

/// Small help icon with a tooltip — crimson tint.
Widget settingsHelpTooltip(BuildContext context, String message) {
  return Tooltip(
    message: message,
    child: Icon(
      Icons.help_outline,
      size: 16,
      color: AppColors.metaText(context),
    ),
  );
}

// =============================================================================
// COMPACT STEPPER WIDGET — Angular Nocturne
// =============================================================================

class SettingsCompactStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const SettingsCompactStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant, width: 1),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(
            icon: Icons.remove,
            enabled: value > min,
            onTap: () => onChanged(value - 1),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            alignment: Alignment.center,
            child: Text(
              '$value',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
                color: textColor,
              ),
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            enabled: value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = cs.onSurfaceVariant;
    final disabledColor = cs.outlineVariant;

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(2),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? activeColor : disabledColor,
        ),
      ),
    );
  }
}

// =============================================================================
// BANDWIDTH LIMIT TILE — Nocturne crimson slider
// =============================================================================

class SettingsBandwidthLimitTile extends ConsumerStatefulWidget {
  final SettingsState settings;

  const SettingsBandwidthLimitTile({super.key, required this.settings});

  @override
  ConsumerState<SettingsBandwidthLimitTile> createState() =>
      _SettingsBandwidthLimitTileState();
}

class _SettingsBandwidthLimitTileState
    extends ConsumerState<SettingsBandwidthLimitTile> {
  static const int _maxSteps = 100;
  static const int _kbsPerStep = 100;

  late double _sliderValue;

  @override
  void initState() {
    super.initState();
    _sliderValue = _kbpsToSlider(widget.settings.globalBandwidthLimit);
  }

  @override
  void didUpdateWidget(SettingsBandwidthLimitTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.globalBandwidthLimit !=
        widget.settings.globalBandwidthLimit) {
      _sliderValue = _kbpsToSlider(widget.settings.globalBandwidthLimit);
    }
  }

  double _kbpsToSlider(int kbps) =>
      (kbps ~/ _kbsPerStep).clamp(0, _maxSteps).toDouble();

  int _sliderToKbps(double v) => v.round() * _kbsPerStep;

  String _displayValue(int kbps) =>
      kbps == 0
          ? AppLocalizations.bandwidthUnlimited
          : AppLocalizations.bandwidthLimitKbps(kbps);

  @override
  Widget build(BuildContext context) {
    final kbps = widget.settings.globalBandwidthLimit;
    final textPrimary = Theme.of(context).colorScheme.onSurface;
    final textSecondary = AppColors.muted(context);
    final isPremium = ref.watch(isPremiumProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(Icons.speed, size: 20, color: textSecondary),
          title: Text(
            AppLocalizations.bandwidthTitle,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: textPrimary),
          ),
          subtitle: Text(
            AppLocalizations.bandwidthCurrentLimit(_displayValue(kbps)),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.wifi, size: 14, color: textSecondary),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor:
                        isPremium
                            ? AppColors.accentHighlight
                            : AppColors.accentHighlight.withAlpha(100),
                    inactiveTrackColor:
                        Theme.of(context).colorScheme.outlineVariant,
                    thumbColor:
                        isPremium
                            ? AppColors.accentHighlight
                            : AppColors.accentHighlight.withAlpha(100),
                    overlayColor: AppColors.accentHighlight.withAlpha(40),
                    trackHeight: 3,
                  ),
                  child: GestureDetector(
                    // Tap anywhere on the slider track to show upgrade dialog
                    onTap:
                        isPremium
                            ? null
                            : () => UpgradePromptDialog.showAndNavigate(
                              context,
                              ref,
                              feature: PremiumFeature.bandwidthControl,
                            ),
                    child: Slider(
                      value: _sliderValue,
                      min: 0,
                      max: _maxSteps.toDouble(),
                      divisions: _maxSteps,
                      label: _displayValue(_sliderToKbps(_sliderValue)),
                      onChanged:
                          isPremium
                              ? (v) => setState(() => _sliderValue = v)
                              : null,
                      onChangeEnd:
                          isPremium
                              ? (v) => ref
                                  .read(settingsProvider.notifier)
                                  .updateGlobalBandwidthLimit(_sliderToKbps(v))
                              : null,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 90,
                child: Text(
                  _displayValue(_sliderToKbps(_sliderValue)),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: textSecondary,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (!isPremium)
          Padding(
            padding: const EdgeInsets.only(
              left: 56,
              right: AppSpacing.md,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              'Premium feature · Upgrade to control bandwidth',
              style: AppTypography.compact.copyWith(
                color: AppColors.accentHighlight.withAlpha(150),
              ),
            ),
          ),
      ],
    );
  }
}
