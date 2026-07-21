import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../data/datasources/format_presets_service.dart';
import '../../domain/enums/audio_codec_preference.dart';
import '../../domain/enums/container_format_preference.dart';
import '../../domain/enums/fps_preference.dart';
import '../../domain/enums/video_codec_preference.dart';
import '../../../downloads/presentation/providers/download_providers.dart';
import '../providers/settings_provider.dart';
import 'settings_shared_widgets.dart';

class SettingsQualitySection extends ConsumerWidget {
  const SettingsQualitySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionTitle(
          context,
          AppLocalizations.settingsSectionQualityFormat,
        ),
        const Gap.md(),

        // Format Presets
        _FormatPresetsBar(settings: settings),
        const Gap.md(),

        settingsCard(
          context,
          children: [
            // Max resolution - dropdown
            ListTile(
              leading: const Icon(Icons.high_quality, size: 20),
              title: Text(AppLocalizations.settingsMaxResolutionTitle),
              trailing: DropdownButton<int>(
                value: settings.maxResolution,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 0, child: Text(AppLocalizations.settingsQualityUnlimited)),
                  const DropdownMenuItem(value: 2160, child: Text('4K (2160p)')),
                  const DropdownMenuItem(value: 1440, child: Text('2K (1440p)')),
                  const DropdownMenuItem(value: 1080, child: Text('1080p')),
                  const DropdownMenuItem(value: 720, child: Text('720p')),
                  const DropdownMenuItem(value: 480, child: Text('480p')),
                  const DropdownMenuItem(value: 360, child: Text('360p')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(settingsProvider.notifier).updateMaxResolution(v);
                  }
                },
              ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Auto Quality Fallback toggle
            BrandSwitchListTile(
              secondary: const Icon(Icons.swap_vert_rounded, size: 20),
              title: Text(AppLocalizations.qualityFallbackTitle),
              subtitle: Text(AppLocalizations.qualityFallbackDescription),
              value: ref.watch(qualityFallbackEnabledProvider),
              onChanged: (v) async {
                final prefs = ref.read(sharedPreferencesProvider);
                await prefs.setBool('quality_fallback_enabled', v);
                ref.invalidate(qualityFallbackEnabledProvider);
              },
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Video codec (keep dialog - 5 options with descriptions)
            ListTile(
              leading: const Icon(Icons.videocam, size: 20),
              title: Text(AppLocalizations.settingsVideoCodecTitle),
              subtitle: Text(settings.videoCodecPreference.displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  settingsHelpTooltip(
                    context,
                    AppLocalizations.settingsVideoCodecHelp,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap:
                  () => _showVideoCodecDialog(
                    context,
                    ref,
                    settings.videoCodecPreference,
                  ),
            ),

            const Divider(height: 1, indent: 16, endIndent: 16),

            // Audio codec (keep dialog)
            ListTile(
              leading: const Icon(Icons.audiotrack, size: 20),
              title: Text(AppLocalizations.settingsAudioCodecTitle),
              subtitle: Text(settings.audioCodecPreference.displayName),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  settingsHelpTooltip(
                    context,
                    AppLocalizations.settingsAudioCodecHelp,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap:
                  () => _showAudioCodecDialog(
                    context,
                    ref,
                    settings.audioCodecPreference,
                  ),
            ),
          ],
        ),

        const Gap.md(),

        // Container format - inline segmented
        settingsCard(
          context,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_zip, size: 20),
              title: Text(AppLocalizations.settingsContainerFormatTitle),
              trailing: settingsHelpTooltip(
                context,
                AppLocalizations.settingsContainerFormatHelp,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              // Phase 1b: container list grew from 3 → 7 values. SegmentedButton
              // is Material 3-specified for ≤5 segments; squeezing 7 into one
              // row overflows on narrow window widths. Wrap of ChoiceChips
              // adapts to any width by wrapping to multiple rows and matches
              // the chip pattern used by the inline format picker in the
              // download config dialog.
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ContainerFormatPreference.values.map((f) {
                  final selected = settings.containerFormatPreference == f;
                  return ChoiceChip(
                    label: Text(
                      f.displayName.replaceAll(RegExp(r'\s*\(.*\)'), ''),
                    ),
                    selected: selected,
                    onSelected: (_) {
                      ref
                          .read(settingsProvider.notifier)
                          .updateContainerFormatPreference(f);
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ),

        const Gap.md(),

        // FPS preference - inline segmented
        settingsCard(
          context,
          children: [
            ListTile(
              leading: const Icon(Icons.speed, size: 20),
              title: Text(AppLocalizations.settingsFrameRateTitle),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<FpsPreference>(
                  segments:
                      FpsPreference.values.map((f) {
                        return ButtonSegment(
                          value: f,
                          label: Text(
                            f.displayName.replaceAll(RegExp(r'\s*\(.*\)'), ''),
                          ),
                        );
                      }).toList(),
                  selected: {settings.fpsPreference},
                  onSelectionChanged: (s) {
                    ref
                        .read(settingsProvider.notifier)
                        .updateFpsPreference(s.first);
                  },
                ),
              ),
            ),
          ],
        ),

        const Gap.md(),

        // Force Remux
        settingsCard(
          context,
          children: [
            BrandSwitchListTile(
              secondary: const Icon(Icons.sync_alt, size: 20),
              title: Text(AppLocalizations.settingsFormatPreferencesForceRemux),
              subtitle: Text(
                AppLocalizations.settingsFormatPreferencesForceRemuxDesc(
                  settings.containerFormatPreference.displayName,
                ),
              ),
              value: settings.forceRemux,
              onChanged:
                  (_) => ref.read(settingsProvider.notifier).toggleForceRemux(),
            ),
          ],
        ),

        const Gap.sm(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            AppLocalizations.settingsFormatPreferencesInfoText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // DIALOGS
  // ===========================================================================

  void _showVideoCodecDialog(
    BuildContext context,
    WidgetRef ref,
    VideoCodecPreference current,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            title: Text(AppLocalizations.settingsVideoCodecTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    VideoCodecPreference.values.map((codec) {
                      return RadioListTile<VideoCodecPreference>(
                        title: Text(codec.displayName),
                        subtitle: Text(codec.description),
                        value: codec,
                        groupValue: current,
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateVideoCodecPreference(value);
                            Navigator.pop(context);
                          }
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

  void _showAudioCodecDialog(
    BuildContext context,
    WidgetRef ref,
    AudioCodecPreference current,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            scrollable: true,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            title: Text(AppLocalizations.settingsAudioCodecTitle),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:
                    AudioCodecPreference.values.map((codec) {
                      return RadioListTile<AudioCodecPreference>(
                        title: Text(codec.displayName),
                        subtitle: Text(codec.description),
                        value: codec,
                        groupValue: current,
                        onChanged: (value) {
                          if (value != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateAudioCodecPreference(value);
                            Navigator.pop(context);
                          }
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

class _FormatPresetsBar extends ConsumerWidget {
  final SettingsState settings;
  const _FormatPresetsBar({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(formatPresetsProvider);

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        ...presets.map(
          (preset) => GestureDetector(
            onLongPress: () => _deletePreset(context, ref, preset.name),
            child: ActionChip(
              label: Text(preset.name),
              avatar: const Icon(Icons.tune, size: 16),
              onPressed: () => _applyPreset(context, ref, preset),
            ),
          ),
        ),
        ActionChip(
          label: Text(AppLocalizations.formatPresetsSaveCurrent),
          avatar: Icon(Icons.add, size: 16, color: AppColors.accentHighlight),
          onPressed: () => _saveCurrentAsPreset(context, ref),
        ),
      ],
    );
  }

  void _applyPreset(BuildContext context, WidgetRef ref, FormatPreset preset) {
    final notifier = ref.read(settingsProvider.notifier);
    notifier.updateMaxResolution(preset.maxResolution);

    final videoCodec = VideoCodecPreference.values.firstWhere(
      (e) => e.name == preset.videoCodec,
      orElse: () => VideoCodecPreference.h264,
    );
    notifier.updateVideoCodecPreference(videoCodec);

    final audioCodec = AudioCodecPreference.values.firstWhere(
      (e) => e.name == preset.audioCodec,
      orElse: () => AudioCodecPreference.aac,
    );
    notifier.updateAudioCodecPreference(audioCodec);

    final containerFormat = ContainerFormatPreference.values.firstWhere(
      (e) => e.name == preset.containerFormat,
      orElse: () => ContainerFormatPreference.mp4,
    );
    notifier.updateContainerFormatPreference(containerFormat);

    final fps = FpsPreference.values.firstWhere(
      (e) => e.name == preset.fpsPreference,
      orElse: () => FpsPreference.auto,
    );
    notifier.updateFpsPreference(fps);

    AppSnackBar.success(
      context,
      message: AppLocalizations.formatPresetsApplied,
    );
  }

  Future<void> _deletePreset(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: name,
      message: AppLocalizations.formatPresetsDeleteConfirm,
      confirmLabel: AppLocalizations.commonDelete,
      isDestructive: true,
    );
    if (confirmed) {
      ref.read(formatPresetsProvider.notifier).remove(name);
      if (context.mounted) {
        AppSnackBar.success(
          context,
          message: AppLocalizations.formatPresetsDeleted,
        );
      }
    }
  }

  void _saveCurrentAsPreset(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(AppLocalizations.formatPresetsTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: AppLocalizations.formatPresetsNameHint,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(AppLocalizations.commonCancel),
              ),
              FilledButton(
                onPressed: () {
                  final name = controller.text.trim();
                  if (name.isEmpty) return;
                  ref
                      .read(formatPresetsProvider.notifier)
                      .add(
                        FormatPreset(
                          name: name,
                          maxResolution: settings.maxResolution,
                          videoCodec: settings.videoCodecPreference.name,
                          audioCodec: settings.audioCodecPreference.name,
                          containerFormat:
                              settings.containerFormatPreference.name,
                          fpsPreference: settings.fpsPreference.name,
                          createdAt: DateTime.now(),
                        ),
                      );
                  Navigator.pop(ctx);
                  AppSnackBar.success(
                    context,
                    message: AppLocalizations.formatPresetsSaved,
                  );
                },
                child: Text(AppLocalizations.formatPresetsSaveButton),
              ),
            ],
          ),
    );
  }
}
