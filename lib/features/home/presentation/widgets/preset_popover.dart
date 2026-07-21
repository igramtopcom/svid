/// V2 — Preset popover (open state).
///
/// Layout per UI Spec §5.2 (header / Profile section / 4-field
/// quick-customize / Tier 2 toggle / "Mở cài đặt tải nâng cao →"
/// footer link). See the spec doc for the visual block diagram.
///
/// This widget is the **shell** for Phase 1A; profile data + 4 quick-
/// customize fields are stub rows that ship without wiring until Phase
/// §5 lands (FormatPreset 3-layer architecture). The Tier 2 toggle row
/// IS wired live since it depends only on SharedPreferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/brand_config.dart';
import '../../../../core/design/design_tokens.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/customize_preferences_provider.dart';

/// Show the popover anchored under [anchor]'s render box. Returns when
/// the popover is dismissed. The result is the [PresetPopoverIntent] the
/// user picked, or null when dismissed without action.
Future<PresetPopoverIntent?> showPresetPopover({
  required BuildContext context,
  required RenderBox anchor,
}) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      anchor.localToGlobal(
        anchor.size.bottomLeft(Offset.zero),
        ancestor: overlay,
      ),
      anchor.localToGlobal(
        anchor.size.bottomRight(Offset.zero),
        ancestor: overlay,
      ),
    ),
    Offset.zero & overlay.size,
  );

  return showMenu<PresetPopoverIntent>(
    context: context,
    position: position,
    color: AppColors.surface1(context),
    elevation: 4,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BrandConfig.current.cardRadius),
      side: BorderSide(color: AppColors.border(context)),
    ),
    constraints: const BoxConstraints(minWidth: 320, maxWidth: 360),
    items: <PopupMenuEntry<PresetPopoverIntent>>[
      PopupMenuItem<PresetPopoverIntent>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Consumer(
          builder:
              (ctx, ref, _) => _PresetPopoverContent(
                deepCustomizeOn: ref.watch(popoverDeepCustomizeProvider),
                onToggleDeepCustomize:
                    (value) => ref
                        .read(popoverDeepCustomizeProvider.notifier)
                        .setDeepCustomize(value),
                onIntent: (intent) => Navigator.of(ctx).pop(intent),
              ),
        ),
      ),
    ],
  );
}

/// Action the user took inside the popover; consumed by parent to apply
/// state mutations (active preset change, navigate to settings, etc.).
enum PresetPopoverIntent {
  openAdvancedSettings,
  createNewProfile,

  /// User toggled Tier 2 — parent typically just dismisses.
  toggledDeepCustomize,
}

class _PresetPopoverContent extends StatelessWidget {
  const _PresetPopoverContent({
    required this.deepCustomizeOn,
    required this.onToggleDeepCustomize,
    required this.onIntent,
  });

  final bool deepCustomizeOn;
  final ValueChanged<bool> onToggleDeepCustomize;
  final ValueChanged<PresetPopoverIntent> onIntent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = AppColors.border(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              AppLocalizations.homePresetPopoverTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
          Divider(height: 1, color: borderColor),

          // Profile section — stub for Phase §5.
          _SectionLabel(text: AppLocalizations.homePresetProfile),
          _PlaceholderRow(
            text: AppLocalizations.homePresetProfilePickerTitle,
            icon: Icons.lock_outline,
          ),
          TextButton.icon(
            onPressed: () => onIntent(PresetPopoverIntent.createNewProfile),
            icon: const Icon(Icons.add, size: AppIconSize.md),
            label: Text(AppLocalizations.homePresetCreateProfile),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  BrandConfig.current.buttonRadius,
                ),
              ),
            ),
          ),

          const SizedBox(height: AppSpacing.sm),
          _SectionLabel(text: AppLocalizations.homeCustomizeBeforeDownload),
          // Quick-customize rows — stub for Phase §5; visible structure only.
          _QuickCustomizeRow(
            label: AppLocalizations.homePresetFormat,
            value: AppLocalizations.homePresetFormatVideoLabel,
          ),
          _QuickCustomizeRow(
            label: AppLocalizations.homePresetQuality,
            value: AppLocalizations.homePresetQualityValueDefault,
          ),
          _QuickCustomizeRow(
            label: AppLocalizations.homePresetFallbackLabel,
            value: AppLocalizations.homePresetFallbackNearest,
          ),
          _QuickCustomizeRow(
            label: AppLocalizations.homePresetSaveLocation,
            value: 'Downloads/${BrandConfig.current.appName}',
            trailing: Text(AppLocalizations.homePresetChangeAction),
          ),

          const SizedBox(height: AppSpacing.sm),
          _SectionLabel(text: AppLocalizations.homePresetManualMode),
          // Tier 2 toggle — wired live.
          SwitchListTile.adaptive(
            value: deepCustomizeOn,
            onChanged: (v) {
              onToggleDeepCustomize(v);
              onIntent(PresetPopoverIntent.toggledDeepCustomize);
            },
            title: Text(AppLocalizations.homePresetManualMode),
            subtitle: Text(
              deepCustomizeOn
                  ? AppLocalizations.homePresetManualModeOnDescription
                  : AppLocalizations.homePresetManualModeOffDescription,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            dense: true,
            contentPadding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                BrandConfig.current.cardRadius,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => onIntent(PresetPopoverIntent.openAdvancedSettings),
            icon: const Icon(Icons.settings_outlined, size: AppIconSize.md),
            label: Text('${AppLocalizations.homePresetAdvancedSettings} →'),
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  BrandConfig.current.buttonRadius,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          letterSpacing: 0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _QuickCustomizeRow extends StatelessWidget {
  const _QuickCustomizeRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface2(context),
          borderRadius: BorderRadius.circular(BrandConfig.current.buttonRadius),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceholderRow extends StatelessWidget {
  const _PlaceholderRow({required this.text, required this.icon});
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface2(context),
          borderRadius: BorderRadius.circular(BrandConfig.current.buttonRadius),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: AppIconSize.md, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
