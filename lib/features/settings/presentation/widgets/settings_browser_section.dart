import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/core.dart';
import '../../../browser/domain/services/search_engine_service.dart';
import '../../../browser/presentation/providers/content_filter_providers.dart';
import '../providers/settings_provider.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import 'settings_shared_widgets.dart';

class SettingsBrowserSection extends ConsumerStatefulWidget {
  const SettingsBrowserSection({super.key});

  @override
  ConsumerState<SettingsBrowserSection> createState() =>
      _SettingsBrowserSectionState();
}

class _SettingsBrowserSectionState
    extends ConsumerState<SettingsBrowserSection> {
  @override
  Widget build(BuildContext context) {
    ref.watch(settingsProvider); // keep rebuild on settings change
    final isAdBlockEnabled = ref.watch(adBlockEnabledProvider);
    final isPopupBlockEnabled = ref.watch(popupBlockEnabledProvider);
    final isPhishingEnabled = ref.watch(phishingDetectionEnabledProvider);
    final isHttpsEnabled = ref.watch(httpsEnforcementEnabledProvider);
    final isFingerprintEnabled = ref.watch(
      fingerprintProtectionEnabledProvider,
    );
    final isMediaSniffEnabled = ref.watch(mediaSniffingEnabledProvider);
    final selectedEngine = ref.watch(selectedSearchEngineProvider);
    final homePage = ref.watch(browserHomePageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(context, AppLocalizations.settingsSectionBrowser),
        const Gap.md(),

        // Card: Search & Home Page
        settingsCard(
          context,
          children: [
            ListTile(
              title: Text(AppLocalizations.browserSettingsSearchEngine),
              trailing: DropdownButton<SearchEngine>(
                value: selectedEngine,
                underline: const SizedBox.shrink(),
                onChanged: (engine) {
                  if (engine != null) {
                    ref
                        .read(selectedSearchEngineProvider.notifier)
                        .setEngine(engine);
                  }
                },
                items:
                    SearchEngine.values
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e, child: Text(e.label)),
                        )
                        .toList(),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              title: Text(AppLocalizations.browserSettingsHomePage),
              subtitle: Text(
                homePage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit, size: 18),
              onTap: () => _showHomePageDialog(homePage),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Content Filtering
        settingsCard(
          context,
          children: [
            BrandSwitchListTile(
              title: Text(AppLocalizations.adBlockToggle),
              subtitle: Text(AppLocalizations.adBlockDescription),
              value: isAdBlockEnabled,
              onChanged: (_) {
                if (!isAdBlockEnabled && !ref.read(isPremiumProvider)) {
                  UpgradePromptDialog.showAndNavigate(
                    context,
                    ref,
                    feature: PremiumFeature.browserShield,
                  );
                  return;
                }
                ref.read(adBlockEnabledProvider.notifier).toggle();
              },
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              title: Text(AppLocalizations.popupBlockerToggle),
              subtitle: Text(AppLocalizations.popupBlockerDescription),
              value: isPopupBlockEnabled,
              onChanged:
                  (_) => ref.read(popupBlockEnabledProvider.notifier).toggle(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              title: Text(AppLocalizations.browserMediaSniffEnabled),
              subtitle: const Text(
                'Detect downloadable media from browser network traffic (IDM mode)',
              ),
              value: isMediaSniffEnabled,
              onChanged: (_) {
                if (!isMediaSniffEnabled && !ref.read(isPremiumProvider)) {
                  UpgradePromptDialog.showAndNavigate(
                    context,
                    ref,
                    feature: PremiumFeature.browserShield,
                  );
                  return;
                }
                ref.read(mediaSniffingEnabledProvider.notifier).toggle();
              },
            ),
          ],
        ),

        const Gap.md(),

        // Card: Security & Privacy
        settingsSectionTitle(
          context,
          AppLocalizations.browserSettingsSecuritySection,
        ),
        const Gap.sm(),
        settingsCard(
          context,
          children: [
            BrandSwitchListTile(
              title: Text(AppLocalizations.phishingToggle),
              subtitle: Text(AppLocalizations.phishingDescription),
              value: isPhishingEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(phishingDetectionEnabledProvider.notifier)
                          .toggle(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              title: Text(AppLocalizations.httpsToggle),
              subtitle: Text(AppLocalizations.httpsDescription),
              value: isHttpsEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(httpsEnforcementEnabledProvider.notifier)
                          .toggle(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              title: Text(AppLocalizations.fingerprintToggle),
              subtitle: Text(AppLocalizations.fingerprintDescription),
              value: isFingerprintEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(fingerprintProtectionEnabledProvider.notifier)
                          .toggle(),
            ),
          ],
        ),

        const Gap.md(),

        // Clear Browsing Data
        settingsCard(
          context,
          children: [
            ListTile(
              leading: Icon(Icons.delete_sweep, color: AppColors.errorRed),
              title: Text(AppLocalizations.browserSettingsClearData),
              onTap: () => _showClearBrowsingDataDialog(),
            ),
          ],
        ),
      ],
    );
  }

  void _showHomePageDialog(String currentHomePage) {
    final controller = TextEditingController(text: currentHomePage);
    showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.browserSettingsHomePage),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: SearchEngineService.defaultHomePage,
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                onSubmitted: (_) {
                  ref
                      .read(browserHomePageProvider.notifier)
                      .setHomePage(controller.text);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  ref
                      .read(browserHomePageProvider.notifier)
                      .setHomePage(SearchEngineService.defaultHomePage);
                  Navigator.of(ctx).pop();
                },
                child: Text(AppLocalizations.browserSettingsResetDefault),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppLocalizations.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  ref
                      .read(browserHomePageProvider.notifier)
                      .setHomePage(controller.text);
                  Navigator.of(ctx).pop();
                },
                child: Text(AppLocalizations.commonSave),
              ),
            ],
          ),
    );
  }

  Future<void> _showClearBrowsingDataDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.browserSettingsClearData),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(AppLocalizations.browserSettingsClearDataConfirm),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(AppLocalizations.commonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.errorRed,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(AppLocalizations.browserSettingsClearDataAction),
              ),
            ],
          ),
    );
    if (confirmed == true && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final service = SearchEngineService(prefs);
      await service.clearBrowsingData();
      if (mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.browserSettingsClearDataSuccess,
        );
      }
    }
  }
}
