/// Command-bar preset chip + popover — V2 mockup-aligned.
///
/// Wired both ways now:
///   - Read: chip label + popover row values derive from
///     [activePresetProvider]'s `currentConfig`. Renaming a preset or
///     editing a field in Settings → Quality reflects here within one
///     frame (StateNotifier rebuild).
///   - Write: profile selector switches active preset; format / quality
///     / fallback / save-location pickers update `currentConfig` via
///     [ActivePresetController.updateConfig]; the manual-mode row keeps
///     the legacy full [DownloadConfigDialog] in the download flow.
///
/// Pickers are stock Material widgets ([showDialog] + [SimpleDialog],
/// [FilePicker.platform.getDirectoryPath]) rather than custom-styled
/// flows so the UI agent (GPT 5.5) can swap visual presentation later
/// without touching the state-mutation contract.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../downloads/presentation/widgets/config_preferences_panel.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/data/datasources/builtin_presets_seeder.dart';
import '../../../settings/domain/entities/format_preset_extended.dart';
import '../../../settings/presentation/providers/active_preset_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

// ═════════════════════════════════════════════════════════════════════
// Chip
// ═════════════════════════════════════════════════════════════════════

/// Chip rendered in the command bar — `[icon] MP4 · 1080p ▾`.
///
/// Tapping anchors a popover ([showCommandBarPresetPopover]) on the
/// chip. Hover state mirrors the rest of the command bar's icon
/// buttons so the row reads as one cohesive control cluster.
class CommandBarPresetChip extends ConsumerStatefulWidget {
  /// Height should match the surrounding command bar so the chip
  /// aligns cleanly with the input field, icons, and CTA.
  final double height;

  /// Optional override for the popover content. Default = the
  /// V2 mockup's 5-row layout backed by [activePresetProvider].
  final WidgetBuilder? popoverBuilder;

  const CommandBarPresetChip({
    super.key,
    required this.height,
    this.popoverBuilder,
  });

  @override
  ConsumerState<CommandBarPresetChip> createState() =>
      _CommandBarPresetChipState();
}

class _CommandBarPresetChipState extends ConsumerState<CommandBarPresetChip> {
  bool _hovered = false;
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _open() async {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    await showCommandBarPresetPopover(
      context: context,
      anchor: box,
      contentBuilder: widget.popoverBuilder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final bg = isDark ? AppColors.homeDarkCardBg : cs.surfaceContainerLowest;
    final hoverBg =
        isDark ? AppColors.homeDarkCardHover : cs.surfaceContainerHigh;
    final borderColor =
        isDark
            ? Colors.white.withValues(alpha: 0.14)
            : cs.outlineVariant.withValues(alpha: 0.72);
    final textColor = isDark ? AppColors.darkLightText : cs.onSurface;

    final activePresetState = ref.watch(activePresetProvider);
    final preset = activePresetState.currentConfig;
    final settings = ref.watch(settingsProvider);
    final defaults = PresetDisplayDefaults.fromSettings(settings);
    // When manual mode is on, the chip surfaces a distinct label so
    // the user has an at-a-glance signal that next download will
    // surface the dialog (instead of auto-picking via preset). Wording
    // stays i18n-backed because this chip is visible in every locale.
    final label =
        activePresetState.useManualMode
            ? AppLocalizations.homePresetManualModeShort
            : PresetDisplay.chipLabel(
              preset,
              defaults: defaults,
              bestQualityLabel: AppLocalizations.homePresetBestQualityShort,
            );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: AppLocalizations.homePresetPopoverTitle,
        waitDuration: AppDurations.tooltipWaitDuration,
        child: GestureDetector(
          onTap: _open,
          behavior: HitTestBehavior.opaque,
          child: KeyedSubtree(
            key: _anchorKey,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: widget.height,
              constraints: const BoxConstraints(minWidth: 150),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
              decoration: BoxDecoration(
                color: _hovered ? hoverBg : bg,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(color: borderColor),
              ),
              // Labeled control: a muted caption tells the user WHAT the chip
              // is ("Default download"), the value line tells them its state
              // ("Ask first" / "MP4 · 1080p").
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: AppColors.metaText(context),
                  ),
                  const SizedBox(width: AppSpacing.smMd),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppLocalizations.homeDownloadDefaultsLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.mini.copyWith(
                            color: AppColors.metaText(context),
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.buttonSecondary.copyWith(
                            fontSize: 14,
                            color: textColor,
                            fontWeight: FontWeight.w700,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: AppColors.metaText(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Position the V2 preset popover beneath [anchor] and pump it via
/// [showMenu]. Returns when the popover dismisses.
Future<void> showCommandBarPresetPopover({
  required BuildContext context,
  required RenderBox anchor,
  WidgetBuilder? contentBuilder,
}) async {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final cs = theme.colorScheme;
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

  await showMenu<void>(
    context: context,
    position: position,
    color: isDark ? AppColors.homeDarkCardBg : Colors.white,
    elevation: isDark ? 0 : 10,
    shadowColor: Colors.black.withValues(alpha: isDark ? 0.32 : 0.12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(BrandConfig.current.cardRadius),
      side: BorderSide(
        color:
            isDark
                ? AppColors.homeDarkBorderStrong
                : cs.outlineVariant.withValues(alpha: 0.72),
      ),
    ),
    constraints: const BoxConstraints(minWidth: 340, maxWidth: 340),
    menuPadding: EdgeInsets.zero,
    items: <PopupMenuEntry<void>>[
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: SizedBox(
          width: 340,
          child: Builder(
            builder:
                contentBuilder ??
                (ctx) => const _CommandBarPresetPopoverContent(),
          ),
        ),
      ),
    ],
  );
}

// ═════════════════════════════════════════════════════════════════════
// Advanced download defaults
// ═════════════════════════════════════════════════════════════════════

/// Opens the shared [ConfigPreferencesPanel] bound to GLOBAL settings, so the
/// user can set advanced download defaults (codec / frame rate / subtitles /
/// embed / SponsorBlock) once. Container + resolution are hidden — the
/// popover's Format and Quality rows already own those. Each change persists
/// live via [_persistAdvancedDefaults]; there's no per-video context, so trim
/// and chapter controls don't appear.
Future<void> showAdvancedDownloadDefaults(
  BuildContext context,
  WidgetRef ref,
) async {
  final settings = ref.read(settingsProvider);
  final ffmpeg =
      ref.read(binaryAvailableProvider(BinaryType.ffmpeg)).valueOrNull ?? false;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
      final surface = isDark ? AppColors.homeDarkCardBg : Colors.white;
      final borderColor =
          isDark
              ? AppColors.homeDarkBorderStrong
              : AppColors.border(dialogContext);
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Container(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(
                BrandConfig.current.cardRadius,
              ),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          AppLocalizations.configDialogAdvancedOptions,
                          style: AppTypography.appBarTitle.copyWith(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkLightText : null,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        visualDensity: VisualDensity.compact,
                        tooltip: AppLocalizations.commonClose,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.metaText(dialogContext),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: ConfigPreferencesPanel(
                      settings: settings,
                      platform: VideoPlatform.youtube,
                      ffmpegAvailable: ffmpeg,
                      showSaveAsDefault: false,
                      showContainerAndResolution: false,
                      // No video context yet — the available subtitle
                      // languages are unknowable, so don't pre-configure them.
                      showSubtitles: false,
                      onChanged: (o) => _persistAdvancedDefaults(ref, o),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Persist only the fields that actually changed vs the current global
/// settings (the panel hands us its full snapshot on every edit).
void _persistAdvancedDefaults(WidgetRef ref, PreferencesOverrides o) {
  final s = ref.read(settingsProvider);
  final n = ref.read(settingsProvider.notifier);
  if (o.videoCodec != s.videoCodecPreference) {
    n.updateVideoCodecPreference(o.videoCodec);
  }
  if (o.audioCodec != s.audioCodecPreference) {
    n.updateAudioCodecPreference(o.audioCodec);
  }
  if (o.fps != s.fpsPreference) n.updateFpsPreference(o.fps);
  if (o.subtitlesEnabled != s.subtitlesEnabled) n.toggleSubtitles();
  if (!listEquals(o.subtitlesLanguages, s.subtitlesLanguages)) {
    n.updateSubtitlesLanguages(o.subtitlesLanguages);
  }
  if (o.subtitlesFormat != s.subtitlesFormat) {
    n.updateSubtitlesFormat(o.subtitlesFormat);
  }
  if (o.includeAutoSubs != s.includeAutoSubs) n.toggleIncludeAutoSubs();
  if (o.embedThumbnail != s.embedThumbnail) n.toggleEmbedThumbnail();
  if (o.embedMetadata != s.embedMetadata) n.toggleEmbedMetadata();
  if (o.embedChapters != s.embedChapters) n.toggleEmbedChapters();
  if (o.sponsorBlockEnabled != s.sponsorBlockEnabled) n.toggleSponsorBlock();
  if (o.sponsorBlockAction != s.sponsorBlockAction) {
    n.updateSponsorBlockAction(o.sponsorBlockAction);
  }
  if (!listEquals(o.sponsorBlockCategories, s.sponsorBlockCategories)) {
    n.updateSponsorBlockCategories(o.sponsorBlockCategories);
  }
}

// ═════════════════════════════════════════════════════════════════════
// Popover content
// ═════════════════════════════════════════════════════════════════════

/// Type + Format + Quality + Save-location + Advanced, fed by
/// [activePresetProvider] / [settingsProvider]. Mutations route through the
/// controllers so persistence stays in sync.
class _CommandBarPresetPopoverContent extends ConsumerWidget {
  const _CommandBarPresetPopoverContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final dividerColor =
        isDark
            ? AppColors.homeDarkBorderSubtle
            : cs.outlineVariant.withValues(alpha: AppOpacity.subtle);

    final state = ref.watch(activePresetProvider);
    final preset = state.currentConfig;
    final settings = ref.watch(settingsProvider);
    final defaults = PresetDisplayDefaults.fromSettings(settings);
    final globalPath = ref.watch(downloadPathProvider);
    final saveLocationDisplay =
        preset.saveLocation ?? (globalPath.isEmpty ? '' : globalPath);

    // Quality shows "Ask first" while ask-mode is on; otherwise the concrete
    // default (Best / 1080p / 320kbps). Ask-mode and the fixed quality now
    // live in ONE control — no separate manual-mode toggle to reconcile.
    final qualityValue =
        state.useManualMode
            ? AppLocalizations.homePresetManualModeShort
            : PresetDisplay.popoverQuality(
              preset,
              defaults: defaults,
              bestQualityLabel: AppLocalizations.homePresetBestQualityShort,
              defaultQualityLabel: AppLocalizations.homePresetQualityDefault,
            );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              AppLocalizations.homePresetPopoverTitle,
              style: AppTypography.metadata.copyWith(
                color: AppColors.metaText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(height: 1, color: dividerColor),

          // Type → Format → Quality, in that order: you decide what kind of
          // file you want before its format, and its format before its
          // quality. Save location trails at the end.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.smMd,
              AppSpacing.lg,
              AppSpacing.smMd,
            ),
            child: _TypeToggle(
              audioOnly: preset.audioOnly,
              onChanged: (audio) => _setType(ref, preset, audio),
            ),
          ),
          Divider(height: 1, color: dividerColor),

          _PresetRow(
            icon:
                preset.audioOnly
                    ? Icons.graphic_eq_rounded
                    : Icons.video_library_outlined,
            label: AppLocalizations.homePresetFormat,
            value: PresetDisplay.popoverFormat(preset, defaults: defaults),
            onTap: () => _editContainerFormat(context, ref, preset),
          ),
          _PresetRow(
            icon: Icons.high_quality_outlined,
            label: AppLocalizations.homePresetQuality,
            value: qualityValue,
            onTap: () => _editQuality(context, ref, preset),
          ),
          _PresetRow(
            icon: Icons.folder_outlined,
            label: AppLocalizations.homePresetSaveLocation,
            value: saveLocationDisplay,
            onTap: () => _editSaveLocation(context, ref, preset),
          ),

          Divider(height: 1, color: dividerColor),

          // Shortcut to the same advanced controls the per-download sheet
          // exposes, but bound to the global defaults (codec / subtitles /
          // SponsorBlock…). Container + resolution are omitted — Format and
          // Quality above already own them.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showAdvancedDownloadDefaults(context, ref),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.smMd + 2,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 21,
                      color: AppColors.metaText(context),
                    ),
                    const SizedBox(width: AppSpacing.smMd),
                    Expanded(
                      child: Text(
                        AppLocalizations.configDialogAdvancedOptions,
                        style: AppTypography.buttonSecondary.copyWith(
                          fontSize: 14.5,
                          color: isDark ? AppColors.darkLightText : cs.onSurface,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.metaText(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Switch Video ↔ Audio, keeping a container that matches the new family
  /// (video → mp4, audio → mp3) unless the current one already fits.
  Future<void> _setType(
    WidgetRef ref,
    FormatPresetExtended preset,
    bool audio,
  ) async {
    if (preset.audioOnly == audio) return;
    const audioContainers = {'mp3', 'm4a', 'opus', 'wav', 'flac'};
    final isAudioContainer =
        audioContainers.contains(preset.containerFormat.toLowerCase());
    var container = preset.containerFormat;
    if (audio && !isAudioContainer) container = 'mp3';
    if (!audio && isAudioContainer) container = 'mp4';
    await ref
        .read(activePresetProvider.notifier)
        .updateConfig(preset.copyWith(audioOnly: audio, containerFormat: container));
  }

  // ── Picker handlers ──

  Future<void> _editContainerFormat(
    BuildContext context,
    WidgetRef ref,
    FormatPresetExtended preset,
  ) async {
    // Formats are scoped to the current type — the Type toggle owns
    // video↔audio, so picking a container here never changes the family.
    final videoOptions = <_Option<String>>[
      _Option(
        value: 'mp4',
        label: 'MP4',
        subtitle: AppLocalizations.homePresetFormatMp4Desc,
        leadingIcon: Icons.videocam_rounded,
      ),
      _Option(
        value: 'webm',
        label: 'WebM',
        subtitle: AppLocalizations.homePresetFormatWebmDesc,
        leadingIcon: Icons.videocam_rounded,
      ),
      _Option(
        value: 'mkv',
        label: 'MKV',
        subtitle: AppLocalizations.homePresetFormatMkvDesc,
        leadingIcon: Icons.videocam_rounded,
      ),
      _Option(
        value: 'avi',
        label: 'AVI',
        subtitle: AppLocalizations.settingsContainerAVIDesc,
        leadingIcon: Icons.sync_rounded,
        tone: _OptionTone.warning,
      ),
      _Option(
        value: 'mov',
        label: 'MOV',
        subtitle: AppLocalizations.settingsContainerMOVDesc,
        leadingIcon: Icons.sync_rounded,
        tone: _OptionTone.warning,
      ),
      _Option(
        value: 'm4v',
        label: 'M4V',
        subtitle: AppLocalizations.settingsContainerM4VDesc,
        leadingIcon: Icons.sync_rounded,
        tone: _OptionTone.warning,
      ),
      _Option(
        value: 'flv',
        label: 'FLV',
        subtitle: AppLocalizations.settingsContainerFLVDesc,
        leadingIcon: Icons.sync_rounded,
        tone: _OptionTone.warning,
      ),
    ];
    final audioOptions = <_Option<String>>[
      _Option(
        value: 'mp3',
        label: 'MP3',
        subtitle: AppLocalizations.homePresetFormatMp3Desc,
        leadingIcon: Icons.music_note_rounded,
      ),
      _Option(
        value: 'm4a',
        label: 'M4A',
        subtitle: AppLocalizations.homePresetFormatM4aDesc,
        leadingIcon: Icons.music_note_rounded,
      ),
      _Option(
        value: 'opus',
        label: 'OPUS',
        subtitle: AppLocalizations.homePresetFormatOpusDesc,
        leadingIcon: Icons.music_note_rounded,
      ),
      _Option(
        value: 'wav',
        label: 'WAV',
        subtitle: AppLocalizations.homePresetFormatWavDesc,
        leadingIcon: Icons.music_note_rounded,
      ),
      _Option(
        value: 'flac',
        label: 'FLAC',
        subtitle: AppLocalizations.homePresetFormatFlacDesc,
        leadingIcon: Icons.music_note_rounded,
      ),
    ];
    final picked = await _showOptionPicker<String>(
      context: context,
      title: AppLocalizations.homePresetFormat,
      options: preset.audioOnly ? audioOptions : videoOptions,
      currentValue: preset.containerFormat,
    );
    if (picked == null || picked == preset.containerFormat) return;
    await ref
        .read(activePresetProvider.notifier)
        .updateConfig(preset.copyWith(containerFormat: picked));
  }

  Future<void> _editQuality(
    BuildContext context,
    WidgetRef ref,
    FormatPresetExtended preset,
  ) async {
    final notifier = ref.read(activePresetProvider.notifier);
    final asking = ref.read(activePresetProvider).useManualMode;
    // Sentinel -1 = "Ask every time": picking it turns ask-mode ON (paste
    // opens the quick picker); any concrete value turns ask-mode OFF and
    // stores the fixed default. Ask-mode and quality are one control now.
    const askValue = -1;
    final askOption = _Option<int>(
      value: askValue,
      label: AppLocalizations.homePresetManualMode,
      leadingIcon: Icons.live_help_outlined,
    );

    if (preset.audioOnly) {
      final picked = await _showOptionPicker<int>(
        context: context,
        title: AppLocalizations.homePresetQuality,
        options: [
          askOption,
          _Option<int>(
            value: 0,
            label: AppLocalizations.homePresetQualityDefault,
          ),
          const _Option<int>(value: 128, label: '128 kbps'),
          const _Option<int>(value: 192, label: '192 kbps'),
          const _Option<int>(value: 256, label: '256 kbps'),
          const _Option<int>(value: 320, label: '320 kbps'),
        ],
        currentValue: asking ? askValue : (preset.audioBitrate ?? 0),
      );
      if (picked == null) return;
      if (picked == askValue) {
        await notifier.setManualMode(true);
        return;
      }
      await notifier.setManualMode(false);
      await notifier.updateConfig(
        preset.copyWith(audioBitrate: picked == 0 ? null : picked),
      );
      return;
    }

    // Premium gate at picker layer: free users see >1080p options as locked
    // (tapping opens the upgrade prompt instead of silently storing).
    final isPremium = ref.read(isPremiumProvider);
    final premiumLabel = AppLocalizations.premiumPremiumLabel;

    final picked = await _showOptionPicker<int>(
      context: context,
      title: AppLocalizations.homePresetQuality,
      options: [
        askOption,
        _Option<int>(
          value: 0,
          label: AppLocalizations.homePresetQualityBestAvailable,
          isLocked: !isPremium,
          badgeLabel: !isPremium ? premiumLabel : null,
          leadingIcon: !isPremium ? Icons.workspace_premium_rounded : null,
        ),
        const _Option<int>(value: 480, label: '480p'),
        const _Option<int>(value: 720, label: '720p'),
        const _Option<int>(value: 1080, label: '1080p'),
        _Option<int>(
          value: 1440,
          label: '1440p (2K)',
          isLocked: !isPremium,
          badgeLabel: !isPremium ? premiumLabel : null,
          leadingIcon: !isPremium ? Icons.workspace_premium_rounded : null,
        ),
        _Option<int>(
          value: 2160,
          label: '2160p (4K)',
          isLocked: !isPremium,
          badgeLabel: !isPremium ? premiumLabel : null,
          leadingIcon: !isPremium ? Icons.workspace_premium_rounded : null,
        ),
      ],
      currentValue: asking ? askValue : preset.maxResolution,
      onLockedTap: (value) async {
        if (!context.mounted) return;
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.highQuality4K,
        );
      },
    );
    if (picked == null) return;
    if (picked == askValue) {
      await notifier.setManualMode(true);
      return;
    }
    await notifier.setManualMode(false);
    await notifier.updateConfig(preset.copyWith(maxResolution: picked));
  }


  Future<void> _editSaveLocation(
    BuildContext context,
    WidgetRef ref,
    FormatPresetExtended preset,
  ) async {
    try {
      final globalPath = ref.read(downloadPathProvider);
      final effectiveCurrentPath =
          preset.saveLocation ?? (globalPath.isEmpty ? null : globalPath);
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: AppLocalizations.homePresetSaveLocationPickerTitle,
        initialDirectory: effectiveCurrentPath,
      );
      if (!context.mounted) return;
      // Cancellation or re-selecting the effective inherited folder is a no-op.
      if (dir == null || dir == effectiveCurrentPath) return;

      final canWrite = await FileUtils.canWriteToDirectory(dir);
      if (!context.mounted) return;
      if (!canWrite) {
        AppSnackBar.error(
          context,
          message: AppLocalizations.errorPermission(dir),
        );
        return;
      }

      await ref
          .read(activePresetProvider.notifier)
          .updateConfig(preset.copyWith(saveLocation: dir));
      if (!context.mounted) return;
      AppSnackBar.success(
        context,
        message: '${AppLocalizations.homePresetSaveLocation}: $dir',
      );
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.error(
        context,
        message:
            '${AppLocalizations.commonError}: ${AppExceptionX.readableMessage(e)}',
      );
    }
  }
}

// ═════════════════════════════════════════════════════════════════════
// Picker primitive — stock SimpleDialog-based option list
// ═════════════════════════════════════════════════════════════════════

/// A single option in [_showOptionPicker].
class _Option<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? sectionLabel;
  final IconData? leadingIcon;
  final String? badgeLabel;
  final _OptionTone tone;

  /// When true, tapping this option does NOT pop the dialog with its
  /// value — instead it triggers `_showOptionPicker.onLockedTap`. Used
  /// for premium-gated quality options (4K / 1440p) so free users see
  /// the upgrade prompt directly instead of silently storing the
  /// choice and getting upgrade-prompted at download time.
  final bool isLocked;

  const _Option({
    required this.value,
    required this.label,
    this.subtitle,
    this.sectionLabel,
    this.leadingIcon,
    this.badgeLabel,
    this.tone = _OptionTone.neutral,
    this.isLocked = false,
  });
}

enum _OptionTone { neutral, warning }

/// Shows a [SimpleDialog] of [options] and returns the picked value, or
/// null when the user dismisses without choosing.
///
/// Stock Material [SimpleDialog] / [SimpleDialogOption] — visual surface
/// owned by the UI agent. Logic contract: ✓ on the current value, return
/// value when tapped, null when dismissed (barrier + back).
///
/// [onLockedTap] fires when an `_Option(isLocked: true)` is tapped.
/// Caller is expected to surface a paywall / upgrade prompt; the
/// dialog stays open while the prompt is shown so the user can pick a
/// non-locked option after dismissing the prompt.
Future<T?> _showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<_Option<T>> options,
  required T currentValue,
  Future<void> Function(T value)? onLockedTap,
}) async {
  return showDialog<T>(
    context: context,
    builder:
        (ctx) => _PresetOptionPickerDialog<T>(
          title: title,
          options: options,
          currentValue: currentValue,
          onLockedTap: onLockedTap,
        ),
  );
}

class _PresetOptionPickerDialog<T> extends StatefulWidget {
  final String title;
  final List<_Option<T>> options;
  final T currentValue;
  final Future<void> Function(T value)? onLockedTap;

  const _PresetOptionPickerDialog({
    required this.title,
    required this.options,
    required this.currentValue,
    this.onLockedTap,
  });

  @override
  State<_PresetOptionPickerDialog<T>> createState() =>
      _PresetOptionPickerDialogState<T>();
}

class _PresetOptionPickerDialogState<T>
    extends State<_PresetOptionPickerDialog<T>> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final radius = BrandConfig.current.cardRadius;
    final surface = isDark ? AppColors.homeDarkCardBg : Colors.white;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant.withValues(alpha: 0.76);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.34 : 0.13),
                blurRadius: isDark ? 28 : 24,
                offset: const Offset(0, 18),
                spreadRadius: -14,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.smMd,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color:
                              isDark
                                  ? AppColors.homeDarkAccentSoft
                                  : AppColors.accentHighlight.withValues(
                                    alpha: AppOpacity.hover,
                                  ),
                          borderRadius: BorderRadius.circular(radius),
                          border: Border.all(color: borderColor),
                        ),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: AppColors.accentHighlight,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.smMd),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.buttonSecondary.copyWith(
                            fontSize: 16,
                            color:
                                isDark ? AppColors.darkLightText : cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop<T>(),
                        visualDensity: VisualDensity.compact,
                        tooltip: AppLocalizations.commonCancel,
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.metaText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: borderColor),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    itemCount: widget.options.length,
                    separatorBuilder:
                        (_, __) => Divider(
                          height: 1,
                          indent: 56,
                          color:
                              isDark
                                  ? AppColors.homeDarkBorderSubtle
                                  : borderColor.withValues(
                                    alpha: AppOpacity.secondary,
                                  ),
                        ),
                    itemBuilder: (ctx, index) {
                      final option = widget.options[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (option.sectionLabel != null)
                            _PresetOptionSectionHeader(
                              label: option.sectionLabel!,
                            ),
                          _PresetOptionRow<T>(
                            option: option,
                            selected: option.value == widget.currentValue,
                            hovered: _hoveredIndex == index,
                            onHoverStart:
                                () => setState(() => _hoveredIndex = index),
                            onHoverEnd:
                                () => setState(() {
                                  if (_hoveredIndex == index) {
                                    _hoveredIndex = null;
                                  }
                                }),
                            onTap: () async {
                              if (option.isLocked) {
                                await widget.onLockedTap?.call(option.value);
                                return;
                              }
                              if (ctx.mounted) {
                                Navigator.pop<T>(ctx, option.value);
                              }
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PresetOptionSectionHeader extends StatelessWidget {
  final String label;

  const _PresetOptionSectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.smMd,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.microLabel.copyWith(
          color: AppColors.accentHighlight,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PresetOptionRow<T> extends StatelessWidget {
  final _Option<T> option;
  final bool selected;
  final bool hovered;
  final VoidCallback onHoverStart;
  final VoidCallback onHoverEnd;
  final Future<void> Function() onTap;

  const _PresetOptionRow({
    required this.option,
    required this.selected,
    required this.hovered,
    required this.onHoverStart,
    required this.onHoverEnd,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final accent = AppColors.accentHighlight;
    final toneColor =
        option.tone == _OptionTone.warning
            ? AppColors.warning(context)
            : accent;
    final muted = AppColors.metaText(context);
    final textColor =
        option.isLocked
            ? muted
            : isDark
            ? AppColors.darkLightText
            : cs.onSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHoverStart(),
      onExit: (_) => onHoverEnd(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, 6),
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                selected
                    ? toneColor.withValues(alpha: isDark ? 0.16 : 0.08)
                    : hovered
                    ? (isDark
                        ? AppColors.homeDarkCardHover
                        : cs.surfaceContainerLow)
                    : (isDark
                        ? AppColors.homeDarkAppBg
                        : AppColors.surface2(context)),
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color: selected ? toneColor : AppColors.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              option.isLocked
                  ? Icon(Icons.lock_outline_rounded, size: 18, color: muted)
                  : Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? toneColor : muted,
                        width: selected ? 5 : 1.5,
                      ),
                    ),
                  ),
              const SizedBox(width: AppSpacing.smMd),
              if (option.leadingIcon != null) ...[
                Icon(
                  option.leadingIcon,
                  size: 18,
                  color: selected ? toneColor : muted,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.buttonSecondary.copyWith(
                        color: textColor,
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        option.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.metadata.copyWith(
                          color:
                              option.isLocked
                                  ? accent
                                  : option.tone == _OptionTone.warning
                                  ? AppColors.warningText(context)
                                  : AppColors.metaText(context),
                          fontWeight:
                              option.isLocked
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (option.badgeLabel != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _PresetOptionBadge(
                  label: option.badgeLabel!,
                  selected: selected,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetOptionBadge extends StatelessWidget {
  final String label;
  final bool selected;

  const _PresetOptionBadge({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentHighlight;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color:
            selected
                ? accent.withValues(alpha: 0.12)
                : AppColors.surface2(context),
        border: Border.all(
          color:
              selected
                  ? accent.withValues(alpha: 0.30)
                  : AppColors.border(context),
        ),
        borderRadius: BorderRadius.circular(BrandConfig.current.cardRadius),
      ),
      child: Text(
        label,
        style: AppTypography.metadata.copyWith(
          color: selected ? accent : AppColors.metaText(context),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
// Display formatters
// ═════════════════════════════════════════════════════════════════════

/// Pure formatters — derive display strings from a [FormatPresetExtended].
///
/// Public + `@visibleForTesting` so unit tests can pin the formatter
/// behaviour without booting a Riverpod harness. Kept on a dedicated
/// class (instead of free functions) so the widget file's import surface
/// stays one symbol per file.
class PresetDisplayDefaults {
  final String containerFormat;
  final int maxResolution;

  const PresetDisplayDefaults({
    required this.containerFormat,
    required this.maxResolution,
  });

  factory PresetDisplayDefaults.fromSettings(SettingsState settings) {
    return PresetDisplayDefaults(
      containerFormat: settings.containerFormatPreference.name,
      maxResolution: settings.maxResolution,
    );
  }
}

class PresetDisplay {
  PresetDisplay._();

  /// Compact label used in the command-bar chip — e.g.
  /// "MP4 · 1080p", "MP3 · 320kbps". When the active preset stores
  /// literal `auto` values, the command bar shows the effective global
  /// defaults instead of exposing the implementation sentinel.
  static String chipLabel(
    FormatPresetExtended p, {
    PresetDisplayDefaults? defaults,
    String bestQualityLabel = 'Best',
  }) {
    final fmt = _resolvedFormat(p, defaults);
    if (p.audioOnly) {
      final br = p.audioBitrate;
      return br != null ? '$fmt · ${br}kbps' : fmt;
    }
    final maxResolution = _resolvedMaxResolution(p, defaults);
    if (maxResolution == 0) {
      return defaults == null || fmt == 'AUTO'
          ? fmt
          : '$fmt · $bestQualityLabel';
    }
    return '$fmt · ${maxResolution}p';
  }

  /// Format value rendered in the popover "Định dạng" row.
  static String popoverFormat(
    FormatPresetExtended p, {
    PresetDisplayDefaults? defaults,
  }) => _resolvedFormat(p, defaults);

  /// Quality value rendered in the popover "Chất lượng" row. Returns
  /// `kbps` for audio-only, `Np` for video, empty string when both
  /// unset (auto / archive built-ins).
  static String popoverQuality(
    FormatPresetExtended p, {
    PresetDisplayDefaults? defaults,
    String bestQualityLabel = 'Best',
    String defaultQualityLabel = '',
  }) {
    if (p.audioOnly) {
      final br = p.audioBitrate;
      return br != null ? '${br}kbps' : defaultQualityLabel;
    }
    final maxResolution = _resolvedMaxResolution(p, defaults);
    if (maxResolution == 0) return defaults == null ? '' : bestQualityLabel;
    return '${maxResolution}p';
  }

  /// Fallback label. Only `nearest` has localized wording today; the
  /// other two enum branches surface their `.name` string until UX
  /// finalises the wording.
  static String popoverFallback(
    FormatPresetExtended p, {
    String? nearestLabel,
    String higherLabel = 'higher',
    String blockLabel = 'block',
  }) {
    switch (p.fallbackBehavior) {
      case FormatPresetFallback.nearest:
        return nearestLabel ?? AppLocalizations.homePresetFallbackNearest;
      case FormatPresetFallback.higher:
        return higherLabel;
      case FormatPresetFallback.block:
        return blockLabel;
    }
  }

  /// Compact profile name for the popover value column. Built-in names
  /// such as "Tự động (cao nhất)" already expose their detail in the
  /// dedicated format / quality rows, so the profile row stays scannable
  /// as "Tự động" or "Tự động · Đã chỉnh".
  static String profileName(
    String name, {
    required bool isModified,
    required String modifiedLabel,
  }) {
    final trimmed = name.trim();
    final parenIndex = trimmed.indexOf('(');
    final base =
        parenIndex > 0 ? trimmed.substring(0, parenIndex).trim() : trimmed;
    final displayName = base.isEmpty ? trimmed : base;
    return isModified ? '$displayName · $modifiedLabel' : displayName;
  }

  static String _resolvedFormat(
    FormatPresetExtended p,
    PresetDisplayDefaults? defaults,
  ) {
    final raw = p.containerFormat.trim().toLowerCase();
    final inherited = defaults?.containerFormat.trim().toLowerCase();
    final resolved =
        raw.isEmpty || raw == 'auto'
            ? (inherited == null || inherited.isEmpty ? raw : inherited)
            : raw;
    return resolved.isEmpty ? 'AUTO' : resolved.toUpperCase();
  }

  static int _resolvedMaxResolution(
    FormatPresetExtended p,
    PresetDisplayDefaults? defaults,
  ) {
    if (p.maxResolution > 0) return p.maxResolution;
    return defaults?.maxResolution ?? 0;
  }
}

// ═════════════════════════════════════════════════════════════════════
// Row widgets
// ═════════════════════════════════════════════════════════════════════

class _PresetRow extends StatefulWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PresetRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  State<_PresetRow> createState() => _PresetRowState();
}

class _PresetRowState extends State<_PresetRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final hoverBg =
        isDark ? AppColors.homeDarkCardHover : cs.surfaceContainerLow;
    final iconColor =
        isDark
            ? Color.lerp(AppColors.darkMetaText, AppColors.darkLightText, 0.38)!
            : Color.lerp(cs.onSurfaceVariant, cs.onSurface, 0.52)!;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 52),
          color: _hovered ? hoverBg : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 24,
                child: Center(
                  child: Icon(widget.icon, size: 21, color: iconColor),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                flex: 4,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.buttonSecondary.copyWith(
                    color: isDark ? AppColors.darkLightText : cs.onSurface,
                    fontSize: 14.5,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 5,
                child: Text(
                  widget.value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color:
                        isDark
                            ? Color.lerp(
                              AppColors.darkMetaText,
                              AppColors.darkLightText,
                              0.34,
                            )!
                            : Color.lerp(
                              cs.onSurfaceVariant,
                              cs.onSurface,
                              0.24,
                            )!,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Video / Audio segmented control for the download-defaults popover.
class _TypeToggle extends StatelessWidget {
  final bool audioOnly;
  final ValueChanged<bool> onChanged;

  const _TypeToggle({required this.audioOnly, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget seg(bool audio, IconData icon, String label) {
      final selected = audioOnly == audio;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(audio),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.accentHighlight : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color:
                      selected
                          ? AppColors.darkLightText
                          : AppColors.metaText(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.buttonSecondary.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color:
                        selected
                            ? AppColors.darkLightText
                            : AppColors.metaText(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: AppColors.border(context)),
      ),
      child: Row(
        children: [
          seg(
            false,
            Icons.videocam_rounded,
            AppLocalizations.configDialogVideo,
          ),
          seg(
            true,
            Icons.music_note_rounded,
            AppLocalizations.configDialogAudio,
          ),
        ],
      ),
    );
  }
}
