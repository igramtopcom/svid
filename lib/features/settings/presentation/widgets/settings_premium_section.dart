import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/navigation/navigation_constants.dart';
import '../../../../core/providers/navigation_provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../premium/domain/entities/premium_license.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import 'settings_shared_widgets.dart';

class SettingsPremiumSection extends ConsumerWidget {
  const SettingsPremiumSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.watch(premiumLicenseProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(context, AppLocalizations.premiumTitle),
        const SizedBox(height: AppSpacing.md),
        settingsCard(
          context,
          children: [
            _PremiumStatusPanel(license: license),
            const Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
            ),
            const _PremiumFeatureStrip(),
            const Divider(
              height: 1,
              indent: AppSpacing.md,
              endIndent: AppSpacing.md,
            ),
            _PremiumLicenseShortcut(license: license),
          ],
        ),
      ],
    );
  }
}

class _PremiumStatusPanel extends ConsumerWidget {
  final PremiumLicense license;

  const _PremiumStatusPanel({required this.license});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final isPremium = license.isPremium;
    final accent = AppColors.accentHighlight;
    final statusLabel =
        isPremium
            ? AppLocalizations.premiumActiveSubscription
            : AppLocalizations.premiumFree;
    final title =
        isPremium
            ? AppLocalizations.premiumActiveSubscription
            : AppLocalizations.premiumUpgradeTitle;
    final subtitle =
        isPremium
            ? _premiumStatusSubtitle(license)
            : AppLocalizations.premiumUpgradeSubtitle;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accent.withValues(alpha: isDark ? 0.18 : 0.10),
              AppColors.surface2(context),
            ],
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.34 : 0.24),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: accent.withValues(alpha: 0.36)),
              ),
              child: Icon(
                isPremium
                    ? Icons.verified_rounded
                    : Icons.workspace_premium_rounded,
                color: accent,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                          color: cs.onSurface,
                        ),
                      ),
                      _StatusPill(label: statusLabel, isPremium: isPremium),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed:
                  () => ref
                      .read(navigationProvider.notifier)
                      .navigateToTab(NavigationConstants.premiumIndex),
              icon: Icon(
                isPremium
                    ? Icons.manage_accounts_rounded
                    : Icons.arrow_forward_rounded,
                size: 18,
              ),
              label: Text(
                isPremium
                    ? AppLocalizations.premiumManageSubscription
                    : AppLocalizations.premiumUpgrade,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool isPremium;

  const _StatusPill({required this.label, required this.isPremium});

  @override
  Widget build(BuildContext context) {
    final color =
        isPremium ? AppColors.success(context) : AppColors.accentHighlight;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: AppTypography.mini.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PremiumFeatureStrip extends StatelessWidget {
  const _PremiumFeatureStrip();

  @override
  Widget build(BuildContext context) {
    final features = [
      _FeatureTeaser(
        icon: Icons.all_inclusive_rounded,
        title: AppLocalizations.premiumFeatureUnlimitedDownloads,
        subtitle: AppLocalizations.premiumFeatureDescUnlimitedDownloads,
      ),
      _FeatureTeaser(
        icon: Icons.hd_rounded,
        title: AppLocalizations.premiumFeatureHighQuality4K,
        subtitle: AppLocalizations.premiumFeatureDescHighQuality4K,
      ),
      _FeatureTeaser(
        icon: Icons.shield_rounded,
        title: AppLocalizations.premiumFeatureBrowserShield,
        subtitle: AppLocalizations.premiumFeatureDescBrowserShield,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 3 : 1;
          final spacing = columns == 1 ? AppSpacing.sm : AppSpacing.smMd;
          final width =
              columns == 1
                  ? constraints.maxWidth
                  : (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: AppSpacing.sm,
            children: [
              for (final feature in features)
                SizedBox(width: width, child: feature),
            ],
          );
        },
      ),
    );
  }
}

class _FeatureTeaser extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTeaser({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final border =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context).withValues(alpha: 0.72);

    return Container(
      constraints: const BoxConstraints(minHeight: 118),
      padding: const EdgeInsets.all(AppSpacing.smMd),
      decoration: BoxDecoration(
        color: AppColors.surface1(context),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accentHighlight),
          const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumLicenseShortcut extends ConsumerWidget {
  final PremiumLicense license;

  const _PremiumLicenseShortcut({required this.license});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = license.licenseKey;
    final hasKey = key != null && key.isNotEmpty;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.accentHighlight.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Icon(Icons.key_rounded, size: 19),
      ),
      title: Text(
        hasKey
            ? AppLocalizations.premiumLicenseKey
            : AppLocalizations.premiumHaveLicenseKey,
      ),
      subtitle: Text(
        hasKey ? _maskLicenseKey(key) : AppLocalizations.premiumActivateKeyDesc,
      ),
      trailing: OutlinedButton.icon(
        onPressed:
            () => ref
                .read(navigationProvider.notifier)
                .navigateToTab(NavigationConstants.premiumIndex),
        icon: Icon(
          hasKey ? Icons.open_in_new_rounded : Icons.key_rounded,
          size: 16,
        ),
        label: Text(
          hasKey
              ? AppLocalizations.premiumManageSubscription
              : AppLocalizations.premiumActivateKey,
        ),
      ),
    );
  }
}

String _premiumStatusSubtitle(PremiumLicense license) {
  if (license.isExpired) return AppLocalizations.premiumExpiryWarningTitle;
  if (license.isCancelled) return AppLocalizations.premiumCancelledInfo;
  if (license.billingCycle?.isLifetime ?? false) {
    return '${AppLocalizations.premiumCurrentTier} · ${AppLocalizations.premiumLifetimeBadge}';
  }
  if (license.expiresAt != null && license.daysRemaining >= 0) {
    return AppLocalizations.premiumDaysRemaining(license.daysRemaining);
  }
  return AppLocalizations.premiumHaveLicenseKeyDesc;
}

String _maskLicenseKey(String key) {
  final compact = key.replaceAll(RegExp(r'\s+'), '');
  if (compact.length <= 10) return compact;
  return '${compact.substring(0, 6)}...${compact.substring(compact.length - 4)}';
}
