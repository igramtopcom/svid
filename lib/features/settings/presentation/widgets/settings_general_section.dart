import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../core/services/notification_service.dart';
import '../../../floating_capture/presentation/widgets/floating_capture_settings_card.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsGeneralSection extends ConsumerStatefulWidget {
  const SettingsGeneralSection({super.key});

  @override
  ConsumerState<SettingsGeneralSection> createState() =>
      _SettingsGeneralSectionState();
}

class _SettingsGeneralSectionState
    extends ConsumerState<SettingsGeneralSection> {
  NotificationPermissionStatus _osPermission =
      NotificationPermissionStatus.granted;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final status = await notificationService.checkPermission();
    if (mounted) setState(() => _osPermission = status);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final currentLocale = context.locale;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(context, AppLocalizations.settingsSectionGeneral),
        const Gap.md(),

        // Theme
        settingsCard(context, children: [
          ListTile(
            leading: const Icon(Icons.palette, size: 20),
            title: Text(AppLocalizations.settingsTheme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(value: ThemeMode.light, label: Text(AppLocalizations.settingsThemeLight)),
                  ButtonSegment(value: ThemeMode.dark, label: Text(AppLocalizations.settingsThemeDark)),
                  ButtonSegment(value: ThemeMode.system, label: Text(AppLocalizations.settingsThemeSystem)),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (modes) {
                  ref.read(settingsProvider.notifier).updateThemeMode(modes.first);
                },
              ),
            ),
          ),
        ]),

        const Gap.md(),

        // Language
        settingsCard(context, children: [
          ListTile(
            leading: const Icon(Icons.language, size: 20),
            title: Text(AppLocalizations.settingsLanguage),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: DropdownButtonFormField<String>(
                value: currentLocale.languageCode,
                // Inherits from local Theme InputDecorationTheme (L4 fill, outlineVariant border)
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'vi', child: Text('Ti\u1EBFng Vi\u1EC7t')),
                  DropdownMenuItem(value: 'es', child: Text('Espa\u00F1ol')),
                  DropdownMenuItem(value: 'pt', child: Text('Portugu\u00EAs')),
                  DropdownMenuItem(value: 'ja', child: Text('\u65E5\u672C\u8A9E')),
                  DropdownMenuItem(value: 'ar', child: Text('\u0627\u0644\u0639\u0631\u0628\u064A\u0629')),
                  DropdownMenuItem(value: 'de', child: Text('Deutsch')),
                  DropdownMenuItem(value: 'fr', child: Text('Fran\u00E7ais')),
                  DropdownMenuItem(value: 'hi', child: Text('\u0939\u093F\u0928\u094D\u0926\u0940')),
                  DropdownMenuItem(value: 'id', child: Text('Bahasa Indonesia')),
                  DropdownMenuItem(value: 'ko', child: Text('\uD55C\uAD6D\uC5B4')),
                  DropdownMenuItem(value: 'ru', child: Text('\u0420\u0443\u0441\u0441\u043A\u0438\u0439')),
                  DropdownMenuItem(value: 'th', child: Text('\u0E44\u0E17\u0E22')),
                  DropdownMenuItem(value: 'tr', child: Text('T\u00FCrk\u00E7e')),
                  DropdownMenuItem(value: 'zh', child: Text('\u4E2D\u6587')),
                ],
                onChanged: (locale) {
                  if (locale != null) context.setLocale(Locale(locale));
                },
              ),
            ),
          ),
        ]),

        const Gap.md(),

        // Notifications
        settingsCard(context, children: [
          BrandSwitchListTile(
            secondary: const Icon(Icons.notifications, size: 20),
            title: Text(AppLocalizations.settingsEnableNotifications),
            subtitle: Text(AppLocalizations.settingsEnableNotificationsSubtitle),
            value: settings.notificationsEnabled,
            onChanged: (_) => ref.read(settingsProvider.notifier).toggleNotifications(),
          ),
          // OS-level permission warning
          if (_osPermission == NotificationPermissionStatus.denied)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppLocalizations.settingsNotificationsDisabledOS,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () async {
                        await notificationService
                            .openSystemNotificationSettings();
                        // Re-check after user returns from system settings
                        Future.delayed(
                          const Duration(seconds: 1),
                          _checkPermission,
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange.shade700,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        AppLocalizations.settingsNotificationsOpenSettings,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ]),

        const Gap.md(),

        // Floating capture (v2.1) — self-contained card from the
        // floating_capture feature module.
        const FloatingCaptureSettingsCard(),
      ],
    );
  }
}
