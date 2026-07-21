import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../providers/settings_provider.dart';
import 'settings_platforms_section.dart';
import 'settings_shared_widgets.dart';

class SettingsNetworkSection extends ConsumerStatefulWidget {
  const SettingsNetworkSection({super.key});

  @override
  ConsumerState<SettingsNetworkSection> createState() =>
      _SettingsNetworkSectionState();
}

class _SettingsNetworkSectionState
    extends ConsumerState<SettingsNetworkSection> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionNetworkProxy,
        ),
        const Gap.md(),

        // Card: WiFi Only
        settingsCard(
          context,
          title: 'WIFI',
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.wifi, size: 20),
              title: Text(AppLocalizations.wifiOnlyTitle),
              subtitle: Text(AppLocalizations.wifiOnlyDesc),
              value: settings.wifiOnlyMode,
              onChanged:
                  (value) => ref
                      .read(settingsProvider.notifier)
                      .updateWifiOnlyMode(value),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Auto-Throttle
        settingsCard(
          context,
          title: AppLocalizations.settingsNetworkCardAutoThrottle.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.speed, size: 20),
              title: Text(AppLocalizations.autoThrottleTitle),
              subtitle: Text(AppLocalizations.autoThrottleDesc),
              value: settings.autoThrottle,
              onChanged:
                  (value) => ref
                      .read(settingsProvider.notifier)
                      .updateAutoThrottle(value),
            ),
            BrandSwitchListTile(
              secondary: const Icon(Icons.auto_graph, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdaptiveSegments),
              subtitle: const Text(
                'Automatically select segment count per download based on bandwidth',
              ),
              value: settings.adaptiveSegments,
              onChanged:
                  (value) => ref
                      .read(settingsProvider.notifier)
                      .updateAdaptiveSegments(value),
            ),
            BrandSwitchListTile(
              secondary: const Icon(Icons.swap_vert, size: 20),
              title: Text(AppLocalizations.smartQueueNetworkAwareReorder),
              subtitle: Text(
                AppLocalizations.smartQueueNetworkAwareReorderSubtitle,
              ),
              value: settings.networkAwareQueueReorder,
              onChanged:
                  (value) => ref
                      .read(settingsProvider.notifier)
                      .updateNetworkAwareQueueReorder(value),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Quiet Hours
        settingsCard(
          context,
          title: AppLocalizations.settingsNetworkCardQuietHours.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.bedtime, size: 20),
              title: Text(AppLocalizations.settingsNetworkQuietHours),
              subtitle: const Text(
                'Throttle downloads during a set time window',
              ),
              value: settings.quietHoursEnabled,
              onChanged:
                  (value) => ref
                      .read(settingsProvider.notifier)
                      .updateQuietHoursEnabled(value),
            ),
            if (settings.quietHoursEnabled) ...[
              ListTile(
                leading: const Icon(Icons.bedtime_outlined, size: 20),
                title: Text(AppLocalizations.settingsNetworkStartTime),
                subtitle: Text(_formatHour(settings.quietHoursStart)),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _pickQuietHour(
                      context,
                      ref,
                      current: settings.quietHoursStart,
                      onPicked:
                          (h) => ref
                              .read(settingsProvider.notifier)
                              .updateQuietHoursStart(h),
                    ),
              ),
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined, size: 20),
                title: Text(AppLocalizations.settingsNetworkEndTime),
                subtitle: Text(_formatHour(settings.quietHoursEnd)),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _pickQuietHour(
                      context,
                      ref,
                      current: settings.quietHoursEnd,
                      onPicked:
                          (h) => ref
                              .read(settingsProvider.notifier)
                              .updateQuietHoursEnd(h),
                    ),
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined, size: 20),
                title: Text(AppLocalizations.settingsNetworkBandwidthLimit),
                subtitle: Text('${settings.quietHoursBandwidthKbps} KB/s'),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _editQuietHoursBandwidth(
                      context,
                      ref,
                      settings.quietHoursBandwidthKbps,
                    ),
              ),
            ],
          ],
        ),

        const Gap.md(),

        // Card: Proxy
        settingsCard(
          context,
          title: AppLocalizations.settingsNetworkCardProxy.toUpperCase(),
          children: [
            // Single proxy
            ListTile(
              leading: const Icon(Icons.vpn_key, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedProxy),
              subtitle: Text(
                settings.proxyUrl ??
                    AppLocalizations.settingsNetworkAdvancedNotConfigured,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showProxyDialog(context, ref, settings.proxyUrl),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // Proxy rotation list
            ListTile(
              leading: const Icon(Icons.autorenew, size: 20),
              title: Text(AppLocalizations.settingsNetworkProxyRotation),
              subtitle: Text(
                settings.proxyList.isEmpty
                    ? 'No rotation proxies configured'
                    : '${settings.proxyList.length} proxies (round-robin)',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (settings.proxyList.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accentHighlight.withAlpha(30),
                        borderRadius: BorderRadius.circular(AppRadius.card),
                      ),
                      child: Text(
                        '${settings.proxyList.length}',
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap:
                  () => _showProxyListDialog(context, ref, settings.proxyList),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Geo-Bypass
        settingsCard(
          context,
          title: AppLocalizations.settingsNetworkCardGeoBypass.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.public, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedGeoBypass),
              subtitle: Text(
                AppLocalizations.settingsNetworkAdvancedGeoBypassDesc,
              ),
              value: settings.geoBypass,
              onChanged:
                  (_) => ref.read(settingsProvider.notifier).toggleGeoBypass(),
            ),
            if (settings.geoBypass) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.flag, size: 20),
                title: Text(
                  AppLocalizations.settingsNetworkAdvancedGeoBypassCountry,
                ),
                subtitle: Text(
                  settings.geoBypassCountry ??
                      AppLocalizations.settingsNetworkAdvancedAutoDetect,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => _showGeoBypassCountryDialog(
                      context,
                      ref,
                      settings.geoBypassCountry,
                    ),
              ),
            ],
          ],
        ),

        const Gap.md(),

        // Card: Filters
        settingsCard(
          context,
          title: AppLocalizations.settingsNetworkCardFilters.toUpperCase(),
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.replay, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedAutoRetry),
              subtitle: Text(
                AppLocalizations.settingsNetworkAdvancedAutoRetryDesc,
              ),
              value: settings.autoRetryEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleAutoRetryEnabled(),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            BrandSwitchListTile(
              secondary: const Icon(Icons.archive, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedArchiveMode),
              subtitle: Text(
                AppLocalizations.settingsNetworkAdvancedArchiveModeDesc,
              ),
              value: settings.archiveEnabled,
              onChanged:
                  (_) =>
                      ref
                          .read(settingsProvider.notifier)
                          .toggleArchiveEnabled(),
            ),
            if (settings.archiveEnabled) ...[
              const Divider(height: 1, indent: 16, endIndent: 16),
              SettingsDownloadArchiveSection(
                downloadPath: settings.downloadPath,
              ),
            ],
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.date_range, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedDateAfter),
              subtitle: Text(
                settings.dateAfter != null
                    ? _formatDateFilter(settings.dateAfter!)
                    : AppLocalizations.settingsNetworkAdvancedNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _showDateFilterDialog(
                    context,
                    ref,
                    'dateAfter',
                    settings.dateAfter,
                  ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.date_range, size: 20),
              title: Text(AppLocalizations.settingsNetworkAdvancedDateBefore),
              subtitle: Text(
                settings.dateBefore != null
                    ? _formatDateFilter(settings.dateBefore!)
                    : AppLocalizations.settingsNetworkAdvancedNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _showDateFilterDialog(
                    context,
                    ref,
                    'dateBefore',
                    settings.dateBefore,
                  ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.timer, size: 20),
              title: Text(
                AppLocalizations.settingsNetworkAdvancedMinimumDuration,
              ),
              subtitle: Text(
                settings.minDuration != null
                    ? _formatDuration(settings.minDuration!)
                    : AppLocalizations.settingsNetworkAdvancedNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _showDurationFilterDialog(
                    context,
                    ref,
                    'minDuration',
                    settings.minDuration,
                  ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.timer_off, size: 20),
              title: Text(
                AppLocalizations.settingsNetworkAdvancedMaximumDuration,
              ),
              subtitle: Text(
                settings.maxDuration != null
                    ? _formatDuration(settings.maxDuration!)
                    : AppLocalizations.settingsNetworkAdvancedNotSet,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap:
                  () => _showDurationFilterDialog(
                    context,
                    ref,
                    'maxDuration',
                    settings.maxDuration,
                  ),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Network Tuning
        settingsCard(
          context,
          title:
              AppLocalizations.advancedOptionsNetworkTuningTitle.toUpperCase(),
          children: [
            ListTile(
              leading: const Icon(Icons.timer, size: 20),
              title: Text(AppLocalizations.advancedOptionsSocketTimeout),
              subtitle: Text(AppLocalizations.advancedOptionsSocketTimeoutDesc),
              trailing: Text(
                AppLocalizations.advancedOptionsSocketTimeoutValue(
                  settings.socketTimeout,
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.accentHighlight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Slider(
                value: settings.socketTimeout.toDouble(),
                min: 10,
                max: 120,
                divisions: 11,
                label: '${settings.socketTimeout}s',
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateSocketTimeout(value.round());
                },
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.refresh, size: 20),
              title: Text(AppLocalizations.advancedOptionsMaxRetries),
              subtitle: Text(AppLocalizations.advancedOptionsMaxRetriesDesc),
              trailing: Text(
                '${settings.maxRetries}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.accentHighlight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Slider(
                value: settings.maxRetries.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                label: '${settings.maxRetries}',
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateMaxRetries(value.round());
                },
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.storage, size: 20),
              title: Text(AppLocalizations.advancedOptionsHttpChunkSize),
              subtitle: Text(AppLocalizations.advancedOptionsHttpChunkSizeDesc),
              trailing: Text(
                AppLocalizations.advancedOptionsHttpChunkSizeValue(
                  settings.httpChunkSizeMb,
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.accentHighlight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Slider(
                value: settings.httpChunkSizeMb.toDouble(),
                min: 1,
                max: 50,
                divisions: 49,
                label: '${settings.httpChunkSizeMb} MB',
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateHttpChunkSizeMb(value.round());
                },
              ),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Output Filename Template
        settingsCard(
          context,
          title: AppLocalizations.advancedOptionsFilenameTitle.toUpperCase(),
          children: [
            ListTile(
              leading: const Icon(Icons.text_fields, size: 20),
              title: Text(AppLocalizations.advancedOptionsFilenameTemplate),
              subtitle: Text(
                AppLocalizations.advancedOptionsFilenameTemplateDesc,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: TextField(
                controller: TextEditingController(
                  text: settings.filenameTemplate,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '%(title)s.%(ext)s',
                  errorText: _validateFilenameTemplate(
                    settings.filenameTemplate,
                  ),
                ),
                onSubmitted: (value) {
                  if (_validateFilenameTemplate(value) == null) {
                    ref
                        .read(settingsProvider.notifier)
                        .updateFilenameTemplate(value);
                  }
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                AppLocalizations.advancedOptionsFilenamePreview(
                  _previewFilenameTemplate(settings.filenameTemplate),
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.smMd,
              ),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  _filenameVariableChip('%(title)s', 'Title'),
                  _filenameVariableChip('%(uploader)s', 'Channel'),
                  _filenameVariableChip('%(upload_date)s', 'Date'),
                  _filenameVariableChip('%(id)s', 'ID'),
                  _filenameVariableChip('%(ext)s', 'Extension'),
                ],
              ),
            ),
          ],
        ),

        const Gap.md(),

        // Card: Custom FFmpeg Postprocessor Args
        settingsCard(
          context,
          title:
              AppLocalizations.advancedOptionsPostprocessorTitle.toUpperCase(),
          children: [
            ListTile(
              leading: const Icon(Icons.terminal, size: 20),
              title: Text(AppLocalizations.advancedOptionsPostprocessorArgs),
              subtitle: Text(
                AppLocalizations.advancedOptionsPostprocessorArgsDesc,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: TextField(
                controller: TextEditingController(
                  text: settings.customPostprocessorArgs,
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: AppLocalizations.advancedOptionsPostprocessorHint,
                ),
                maxLength: 500,
                onSubmitted: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .updateCustomPostprocessorArgs(value.trim());
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.smMd,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppLocalizations.advancedOptionsPostprocessorWarning,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  String _formatHour(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '$h:00 $period';
  }

  String _formatDateFilter(String date) {
    if (date.length != 8) return date;
    try {
      final year = date.substring(0, 4);
      final month = date.substring(4, 6);
      final day = date.substring(6, 8);
      return '$day/$month/$year';
    } catch (_) {
      return date;
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final mins = seconds ~/ 60;
      final secs = seconds % 60;
      return secs > 0 ? '${mins}m ${secs}s' : '${mins}m';
    } else {
      final hours = seconds ~/ 3600;
      final mins = (seconds % 3600) ~/ 60;
      return mins > 0 ? '${hours}h ${mins}m' : '${hours}h';
    }
  }

  String? _validateFilenameTemplate(String template) {
    if (template.isEmpty) return 'Template cannot be empty';
    if (!template.contains('%(ext)s')) return 'Must contain %(ext)s';
    if (template.contains('/') || template.contains('\\')) {
      return 'Cannot contain path separators';
    }
    if (template.length > 200) return 'Max 200 characters';
    return null;
  }

  String _previewFilenameTemplate(String template) {
    return template
        .replaceAll('%(title)s', 'Never Gonna Give You Up')
        .replaceAll('%(uploader)s', 'Rick Astley')
        .replaceAll('%(upload_date)s', '20091025')
        .replaceAll('%(id)s', 'dQw4w9WgXcQ')
        .replaceAll('%(ext)s', 'mp4');
  }

  Widget _filenameVariableChip(String variable, String label) {
    return ActionChip(
      label: Text(label, style: Theme.of(context).textTheme.bodySmall),
      avatar: const Icon(Icons.add, size: 14),
      onPressed: () {
        final settings = ref.read(settingsProvider);
        final current = settings.filenameTemplate;
        // Insert before %(ext)s if it exists, otherwise append
        final extIndex = current.indexOf('.%(ext)s');
        String newTemplate;
        if (extIndex > 0) {
          newTemplate =
              '${current.substring(0, extIndex)} - $variable${current.substring(extIndex)}';
        } else {
          newTemplate = '$current$variable';
        }
        if (newTemplate.length <= 200) {
          ref
              .read(settingsProvider.notifier)
              .updateFilenameTemplate(newTemplate);
        }
      },
    );
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  Future<void> _pickQuietHour(
    BuildContext context,
    WidgetRef ref, {
    required int current,
    required ValueChanged<int> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current, minute: 0),
      initialEntryMode: TimePickerEntryMode.input,
    );
    if (picked == null) return;
    onPicked(picked.hour);
  }

  Future<void> _editQuietHoursBandwidth(
    BuildContext context,
    WidgetRef ref,
    int current,
  ) async {
    final controller = TextEditingController(text: current.toString());
    final result = await showDialog<int>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(AppLocalizations.settingsNetworkQuietHoursBandwidth),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: AppLocalizations.settingsNetworkLimitLabel,
                  helperText: AppLocalizations.settingsNetworkLimitHelper,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final v = int.tryParse(controller.text);
                  if (v != null && v >= 64) {
                    Navigator.pop(context, v);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (!context.mounted) return;
    if (result != null) {
      ref.read(settingsProvider.notifier).updateQuietHoursBandwidthKbps(result);
    }
  }

  void _showProxyDialog(
    BuildContext context,
    WidgetRef ref,
    String? currentProxy,
  ) {
    final controller = TextEditingController(text: currentProxy);

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              AppLocalizations.settingsNetworkAdvancedProxyConfiguration,
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: AppLocalizations.settingsNetworkProxyUrl,
                      hintText:
                          AppLocalizations
                              .settingsNetworkAdvancedProxyPlaceholder,
                      helperText:
                          AppLocalizations.settingsNetworkAdvancedProxyHelper,
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    AppLocalizations.settingsNetworkAdvancedProxyFormats,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              if (currentProxy != null)
                TextButton(
                  onPressed: () {
                    ref.read(settingsProvider.notifier).updateProxyUrl(null);
                    Navigator.pop(context);
                  },
                  child: Text(AppLocalizations.settingsNetworkAdvancedClear),
                ),
              TextButton(
                onPressed: () {
                  final value = controller.text.trim();
                  ref
                      .read(settingsProvider.notifier)
                      .updateProxyUrl(value.isEmpty ? null : value);
                  Navigator.pop(context);
                },
                child: Text(AppLocalizations.settingsNetworkAdvancedSave),
              ),
            ],
          ),
    );
  }

  void _showProxyListDialog(
    BuildContext context,
    WidgetRef ref,
    List<String> currentList,
  ) {
    final proxies = List<String>.from(currentList);
    final addController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text(AppLocalizations.settingsNetworkProxyRotation),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 520,
                    maxHeight: MediaQuery.sizeOf(context).height * 0.68,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add multiple proxies for round-robin rotation. '
                        'Unhealthy proxies are automatically skipped.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Add proxy input
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: addController,
                              decoration: InputDecoration(
                                isDense: true,
                                border: const OutlineInputBorder(),
                                hintText: 'socks5://host:port',
                                labelText: AppLocalizations.settingsNetworkAddProxy,
                              ),
                              onSubmitted: (value) {
                                final trimmed = value.trim();
                                if (trimmed.isNotEmpty &&
                                    !proxies.contains(trimmed)) {
                                  setDialogState(() => proxies.add(trimmed));
                                  addController.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          IconButton.filled(
                            onPressed: () {
                              final trimmed = addController.text.trim();
                              if (trimmed.isNotEmpty &&
                                  !proxies.contains(trimmed)) {
                                setDialogState(() => proxies.add(trimmed));
                                addController.clear();
                              }
                            },
                            icon: const Icon(Icons.add, size: 20),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Proxy list
                      if (proxies.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No proxies added yet',
                              style: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.copyWith(
                                color:
                                    Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: proxies.length,
                            separatorBuilder:
                                (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final proxy = proxies[index];
                              return ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: AppColors.accentHighlight,
                                ),
                                title: Text(
                                  proxy,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontFamily: 'monospace'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  onPressed: () {
                                    setDialogState(
                                      () => proxies.removeAt(index),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.commonCancel),
                  ),
                  FilledButton(
                    onPressed: () {
                      ref
                          .read(settingsProvider.notifier)
                          .updateProxyList(proxies);
                      Navigator.pop(context);
                    },
                    child: Text(AppLocalizations.commonSave),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showGeoBypassCountryDialog(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) {
    final countries = [
      (
        null,
        AppLocalizations.settingsNetworkAdvancedAutoDetect,
        AppLocalizations.settingsNetworkAdvancedAutoDetectDesc,
      ),
      ('US', 'United States', 'US servers'),
      ('GB', 'United Kingdom', 'UK servers'),
      ('DE', 'Germany', 'German servers'),
      ('JP', 'Japan', 'Japanese servers'),
      ('KR', 'South Korea', 'Korean servers'),
      ('FR', 'France', 'French servers'),
      ('CA', 'Canada', 'Canadian servers'),
      ('AU', 'Australia', 'Australian servers'),
      ('IN', 'India', 'Indian servers'),
      ('BR', 'Brazil', 'Brazilian servers'),
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              AppLocalizations.settingsNetworkAdvancedGeoBypassCountry,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    countries.map((country) {
                      final (code, name, description) = country;
                      return RadioListTile<String?>(
                        title: Text(name),
                        subtitle: Text(description),
                        value: code,
                        groupValue: current,
                        onChanged: (value) {
                          ref
                              .read(settingsProvider.notifier)
                              .updateGeoBypassCountry(value);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
            ],
          ),
    );
  }

  void _showDateFilterDialog(
    BuildContext context,
    WidgetRef ref,
    String filterType,
    String? currentValue,
  ) {
    DateTime? initialDate;
    if (currentValue != null && currentValue.length == 8) {
      try {
        initialDate = DateTime(
          int.parse(currentValue.substring(0, 4)),
          int.parse(currentValue.substring(4, 6)),
          int.parse(currentValue.substring(6, 8)),
        );
      } catch (_) {}
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              filterType == 'dateAfter' ? 'Date After' : 'Date Before',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filterType == 'dateAfter'
                      ? 'Only download videos uploaded after this date'
                      : 'Only download videos uploaded before this date',
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: initialDate ?? DateTime.now(),
                      firstDate: DateTime(2005),
                      lastDate: DateTime.now(),
                    );
                    if (date != null && context.mounted) {
                      final formatted =
                          '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
                      if (filterType == 'dateAfter') {
                        ref
                            .read(settingsProvider.notifier)
                            .updateDateAfter(formatted);
                      } else {
                        ref
                            .read(settingsProvider.notifier)
                            .updateDateBefore(formatted);
                      }
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.calendar_today),
                  label: Text(
                    initialDate != null
                        ? _formatDateFilter(currentValue!)
                        : AppLocalizations.settingsNetworkAdvancedSelectDate,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
              if (currentValue != null)
                TextButton(
                  onPressed: () {
                    if (filterType == 'dateAfter') {
                      ref.read(settingsProvider.notifier).updateDateAfter(null);
                    } else {
                      ref
                          .read(settingsProvider.notifier)
                          .updateDateBefore(null);
                    }
                    Navigator.pop(context);
                  },
                  child: Text(AppLocalizations.settingsNetworkAdvancedClear),
                ),
            ],
          ),
    );
  }

  void _showDurationFilterDialog(
    BuildContext context,
    WidgetRef ref,
    String filterType,
    int? currentValue,
  ) {
    final presets = [
      (null, 'No limit', 'Download videos of any length'),
      (30, '30 seconds', 'Skip very short clips'),
      (60, '1 minute', 'Skip shorts/reels'),
      (180, '3 minutes', 'Skip short videos'),
      (300, '5 minutes', 'Medium length minimum'),
      (600, '10 minutes', 'Longer videos only'),
      (1800, '30 minutes', 'Long-form content'),
      (3600, '1 hour', 'Very long content'),
    ];

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              filterType == 'minDuration'
                  ? 'Minimum Duration'
                  : 'Maximum Duration',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    presets.map((preset) {
                      final (value, label, description) = preset;
                      return RadioListTile<int?>(
                        title: Text(label),
                        subtitle: Text(description),
                        value: value,
                        groupValue: currentValue,
                        onChanged: (val) {
                          if (filterType == 'minDuration') {
                            ref
                                .read(settingsProvider.notifier)
                                .updateMinDuration(val);
                          } else {
                            ref
                                .read(settingsProvider.notifier)
                                .updateMaxDuration(val);
                          }
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.commonCancel),
              ),
            ],
          ),
    );
  }
}
