import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/core.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/domain/services/smart_defaults_service.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_selection_intent.dart';
import '../../domain/entities/video_info.dart';

/// Right panel of DownloadConfigDialog: format, extras, platform preferences.
/// Nocturne Cinematic "Acquisition Theater" — angular dropdowns, uppercase
/// section headers, compact switches, monospace values.
/// All values default to current global settings. Changes are local overrides.
class ConfigPreferencesPanel extends StatefulWidget {
  final SettingsState settings;
  final VideoPlatform platform;
  final ValueChanged<PreferencesOverrides> onChanged;
  final VideoInfo? videoInfo;
  final bool ffmpegAvailable;
  // Suppress in-panel "Save as default" toggle when the host dialog renders
  // its own (PR #234 secondary-options-row pattern). Default true keeps
  // backward-compat for any caller that doesn't render its own toggle.
  final bool showSaveAsDefault;
  // Restrict format/codec sections relevant to the chosen file type. When
  // null, the panel renders every section (current behavior).
  final DownloadFileType? fileType;

  const ConfigPreferencesPanel({
    super.key,
    required this.settings,
    required this.platform,
    required this.onChanged,
    this.videoInfo,
    this.ffmpegAvailable = false,
    this.showSaveAsDefault = true,
    this.fileType,
  });

  @override
  State<ConfigPreferencesPanel> createState() => ConfigPreferencesPanelState();
}

/// Exposed state so the dialog can read current override values
class PreferencesOverrides {
  final VideoCodecPreference videoCodec;
  final AudioCodecPreference audioCodec;
  final ContainerFormatPreference containerFormat;
  final FpsPreference fps;
  final int maxResolution;
  final bool subtitlesEnabled;
  final List<String> subtitlesLanguages;
  final String subtitlesFormat;
  final bool includeAutoSubs;
  final bool embedThumbnail;
  final bool embedMetadata;
  final bool embedChapters;
  final bool sponsorBlockEnabled;
  final String sponsorBlockAction;
  final List<String> sponsorBlockCategories;
  final bool tiktokRemoveWatermark;
  final bool saveAsDefault;
  final Duration? sectionStartTime;
  final Duration? sectionEndTime;

  const PreferencesOverrides({
    required this.videoCodec,
    required this.audioCodec,
    required this.containerFormat,
    required this.fps,
    required this.maxResolution,
    required this.subtitlesEnabled,
    required this.subtitlesLanguages,
    required this.subtitlesFormat,
    required this.includeAutoSubs,
    required this.embedThumbnail,
    required this.embedMetadata,
    required this.embedChapters,
    required this.sponsorBlockEnabled,
    required this.sponsorBlockAction,
    required this.sponsorBlockCategories,
    required this.tiktokRemoveWatermark,
    required this.saveAsDefault,
    this.sectionStartTime,
    this.sectionEndTime,
  });
}

class ConfigPreferencesPanelState extends State<ConfigPreferencesPanel> {
  // Format
  late VideoCodecPreference _videoCodec;
  late AudioCodecPreference _audioCodec;
  late ContainerFormatPreference _containerFormat;
  late FpsPreference _fps;
  late int _maxResolution;

  // Extras
  late bool _subtitlesEnabled;
  late List<String> _subtitlesLanguages;
  late String _subtitlesFormat;
  late bool _includeAutoSubs;
  late bool _embedThumbnail;
  late bool _embedMetadata;
  late bool _embedChapters;

  // SponsorBlock
  late bool _sponsorBlockEnabled;
  late String _sponsorBlockAction;
  late List<String> _sponsorBlockCategories;

  // Platform
  late bool _tiktokRemoveWatermark;

  // Save
  bool _saveAsDefault = false;

  // Section selection (time range)
  bool _sectionEnabled = false;
  Duration _sectionStart = Duration.zero;
  Duration _sectionEnd = Duration.zero;
  final _startController = TextEditingController();
  final _endController = TextEditingController();

  // Section expansion state
  late bool _formatExpanded;
  late bool _extrasExpanded;
  late bool _sponsorBlockExpanded;
  late bool _platformExpanded;
  bool _timeRangeExpanded = false;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _videoCodec = s.videoCodecPreference;
    _audioCodec = s.audioCodecPreference;
    _containerFormat = s.containerFormatPreference;
    _fps = s.fpsPreference;
    _maxResolution = s.maxResolution;
    _subtitlesEnabled = s.subtitlesEnabled;
    _subtitlesLanguages = List<String>.from(s.subtitlesLanguages);
    _subtitlesFormat = s.subtitlesFormat;
    _includeAutoSubs = s.includeAutoSubs;
    _embedThumbnail = s.embedThumbnail;
    _embedMetadata = s.embedMetadata;
    _embedChapters = s.embedChapters;
    _sponsorBlockEnabled = s.sponsorBlockEnabled;
    _sponsorBlockAction = s.sponsorBlockAction;
    _sponsorBlockCategories = List<String>.from(s.sponsorBlockCategories);
    _tiktokRemoveWatermark = s.tiktokRemoveWatermark;

    // Section time range
    final videoDuration = widget.videoInfo?.duration;
    if (videoDuration != null) {
      _sectionEnd = videoDuration;
      _startController.text = _formatTimestamp(Duration.zero);
      _endController.text = _formatTimestamp(videoDuration);
    }

    // Smart expansion: Format always open, others open if non-default
    _formatExpanded = true;
    _extrasExpanded = s.subtitlesEnabled ||
        !s.embedThumbnail ||
        !s.embedMetadata ||
        !s.embedChapters;
    _sponsorBlockExpanded = s.sponsorBlockEnabled;
    _platformExpanded = !s.tiktokRemoveWatermark;
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  /// Get current preferences state for the dialog to read.
  PreferencesOverrides get currentState {
    if (_sectionEnabled) {
      final videoDuration = widget.videoInfo?.duration;
      if (videoDuration != null) {
        final parsedStart = _parseTimestamp(_startController.text);
        if (parsedStart != null && parsedStart >= Duration.zero &&
            parsedStart < _sectionEnd && parsedStart < videoDuration) {
          _sectionStart = parsedStart;
        }
        final parsedEnd = _parseTimestamp(_endController.text);
        if (parsedEnd != null && parsedEnd > _sectionStart && parsedEnd <= videoDuration) {
          _sectionEnd = parsedEnd;
        }
      }
    }

    return PreferencesOverrides(
      videoCodec: _videoCodec,
      audioCodec: _audioCodec,
      containerFormat: _containerFormat,
      fps: _fps,
      maxResolution: _maxResolution,
      subtitlesEnabled: _subtitlesEnabled,
      subtitlesLanguages: _subtitlesLanguages,
      subtitlesFormat: _subtitlesFormat,
      includeAutoSubs: _includeAutoSubs,
      embedThumbnail: _embedThumbnail,
      embedMetadata: _embedMetadata,
      embedChapters: _embedChapters,
      sponsorBlockEnabled: _sponsorBlockEnabled,
      sponsorBlockAction: _sponsorBlockAction,
      sponsorBlockCategories: _sponsorBlockCategories,
      tiktokRemoveWatermark: _tiktokRemoveWatermark,
      saveAsDefault: _saveAsDefault,
      sectionStartTime: _sectionEnabled ? _sectionStart : null,
      sectionEndTime: _sectionEnabled ? _sectionEnd : null,
    );
  }

  void _notifyChanged() {
    widget.onChanged(currentState);
  }

  /// Public setter for the container format dropdown's internal state.
  ///
  /// Caller is the dialog's primary chip picker — it owns its own
  /// `_containerFormat` field for the chip render but the panel keeps an
  /// independent copy backing its advanced-accordion dropdown. Without
  /// this setter the two diverge silently:
  ///
  ///   * The chip shows AVI (dialog's state).
  ///   * The panel dropdown still shows MP4 (stale).
  ///   * If the user later tweaks ANY other panel field, the panel's
  ///     `_notifyChanged` callback overwrites the dialog's AVI selection
  ///     with the stale MP4 — silent data corruption: user picked AVI,
  ///     download starts as MP4 with zero UI signal.
  ///
  /// We deliberately do NOT call `_notifyChanged` here — the caller
  /// already holds the new value in its own state, so re-emitting would
  /// be a self-trigger loop. Pure state push.
  void setContainerFormat(ContainerFormatPreference value) {
    if (_containerFormat == value) return;
    setState(() => _containerFormat = value);
  }

  bool get _hasAnyOverride {
    final s = widget.settings;
    return _videoCodec != s.videoCodecPreference ||
        _audioCodec != s.audioCodecPreference ||
        _containerFormat != s.containerFormatPreference ||
        _fps != s.fpsPreference ||
        _maxResolution != s.maxResolution ||
        _subtitlesEnabled != s.subtitlesEnabled ||
        _subtitlesFormat != s.subtitlesFormat ||
        !_listEquals(_subtitlesLanguages, s.subtitlesLanguages) ||
        _includeAutoSubs != s.includeAutoSubs ||
        _embedThumbnail != s.embedThumbnail ||
        _embedMetadata != s.embedMetadata ||
        _embedChapters != s.embedChapters ||
        _sponsorBlockEnabled != s.sponsorBlockEnabled ||
        _sponsorBlockAction != s.sponsorBlockAction ||
        !_listEquals(_sponsorBlockCategories, s.sponsorBlockCategories) ||
        _tiktokRemoveWatermark != s.tiktokRemoveWatermark;
  }

  // ── Mission Briefing style constants ──
  static final _sectionHeaderStyle = AppTypography.briefingSection;
  static final _labelStyle = AppTypography.microLabel;
  static final _dropdownTextStyle = AppTypography.monoData;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isYouTube = widget.platform == VideoPlatform.youtube;
    final isTikTok = widget.platform == VideoPlatform.tiktok;
    final showPlatformSection = isTikTok;
    final showSponsorBlock = isYouTube;

    final videoDuration = widget.videoInfo?.duration;
    final hasChapters = widget.videoInfo?.hasChapters ?? false;

    // Mission Briefing panel colors — surfaceLowest wells, accent stripes
    final sectionBarBg = AppColors.surfaceLowest(context);
    final sectionBarHover = AppColors.accentHighlight.withValues(alpha: 0.06);
    final dropdownBg = AppColors.surfaceLowest(context);
    final dropdownBorder = AppColors.accentHighlight.withValues(alpha: 0.20);
    final cs = Theme.of(context).colorScheme;
    final labelColor = AppColors.metaText(context);
    final headerColor = cs.onSurface;
    final textPrimary = cs.onSurface;
    final textSecondary = AppColors.muted(context);

    // Column (not ListView) so the panel can be hosted inside an outer
    // SingleChildScrollView in the PR #234 dialog (accordion content). The
    // host dialog supplies scrolling; this panel sizes naturally.
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd, vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // CONFIGURATION CONSOLE eyebrow heading
        Padding(
          padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.md,
              top: AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                color: AppColors.accentHighlight,
                margin: const EdgeInsets.only(right: AppSpacing.sm),
              ),
              Text(
                AppLocalizations.downloadOptionsSettings,
                style: AppTypography.microLabel.copyWith(
                  letterSpacing: 2.0,
                  color: AppColors.accentHighlight,
                ),
              ),
            ],
          ),
        ),
        // Time Range section (only when video has duration)
        if (videoDuration != null)
          _buildSection(
            context,
            title: AppLocalizations.configDialogSectionTimeRange,
            icon: Icons.content_cut,
            iconColor: AppColors.accentSecondary,
            expanded: _timeRangeExpanded,
            onToggle: () =>
                setState(() => _timeRangeExpanded = !_timeRangeExpanded),
            pinnedOpen: true,
            sectionBarBg: sectionBarBg,
            sectionBarHover: sectionBarHover,
            headerColor: headerColor,
            textSecondary: textSecondary,
            children: [
              _buildSwitch(context, AppLocalizations.configDialogDownloadSection, _sectionEnabled, (v) {
                setState(() => _sectionEnabled = v);
                _notifyChanged();
              }, textPrimary: textPrimary),
              if (_sectionEnabled) ...[
                if (!widget.ffmpegAvailable)
                  _buildFFmpegWarning(context, isDark),
                const SizedBox(height: AppSpacing.sm),
                _buildTimeRangeSlider(context, videoDuration),
                const SizedBox(height: AppSpacing.sm),
                _buildTimeInputRow(context, videoDuration, dropdownBg: dropdownBg, dropdownBorder: dropdownBorder),
                const SizedBox(height: AppSpacing.sm),
                _buildSelectedDuration(context, videoDuration, textSecondary: textSecondary),
                if (hasChapters) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _buildChapterChips(context, isDark: isDark),
                ],
              ],
            ],
          ),

        // Codec hint
        _buildCodecHint(context, isDark),

        // Format section
        _buildSection(
          context,
          title: AppLocalizations.configDialogSectionFormat,
          icon: Icons.tune,
          iconColor: AppColors.accentSecondary,
          expanded: _formatExpanded,
          onToggle: () => setState(() => _formatExpanded = !_formatExpanded),
          pinnedOpen: true,
          sectionBarBg: sectionBarBg,
          sectionBarHover: sectionBarHover,
          headerColor: headerColor,
          textSecondary: textSecondary,
          children: [
            _buildDropdown<VideoCodecPreference>(
              context,
              label: AppLocalizations.settingsVideoCodec,
              value: _videoCodec,
              items: VideoCodecPreference.values,
              displayName: (v) => v.displayName,
              onChanged: (v) {
                setState(() => _videoCodec = v);
                _notifyChanged();
              },
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
            ),
            _buildDropdown<AudioCodecPreference>(
              context,
              label: AppLocalizations.settingsAudioCodec,
              value: _audioCodec,
              items: AudioCodecPreference.values,
              displayName: (v) => v.displayName,
              onChanged: (v) {
                setState(() => _audioCodec = v);
                _notifyChanged();
              },
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
            ),
            _buildDropdown<ContainerFormatPreference>(
              context,
              label: AppLocalizations.settingsContainerFormat,
              value: _containerFormat,
              items: ContainerFormatPreference.values,
              displayName: (v) => v.displayName,
              onChanged: (v) {
                setState(() => _containerFormat = v);
                _notifyChanged();
              },
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
            ),
            _buildDropdown<FpsPreference>(
              context,
              label: AppLocalizations.settingsFrameRate,
              value: _fps,
              items: FpsPreference.values,
              displayName: (v) => v.displayName,
              onChanged: (v) {
                setState(() => _fps = v);
                _notifyChanged();
              },
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
            ),
            _buildResolutionDropdown(context,
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
            ),
          ],
        ),

        // Extras section
        _buildSection(
          context,
          title: AppLocalizations.configDialogSectionExtras,
          icon: Icons.auto_awesome,
          iconColor: AppColors.accentTertiary,
          expanded: _extrasExpanded,
          onToggle: () => setState(() => _extrasExpanded = !_extrasExpanded),
          sectionBarBg: sectionBarBg,
          sectionBarHover: sectionBarHover,
          headerColor: headerColor,
          textSecondary: textSecondary,
          children: [
            _buildSwitch(context, AppLocalizations.configDialogEmbedThumbnail, _embedThumbnail, (v) {
              setState(() => _embedThumbnail = v);
              _notifyChanged();
            }, textPrimary: textPrimary),
            _buildSwitch(context, AppLocalizations.configDialogEmbedMetadata, _embedMetadata, (v) {
              setState(() => _embedMetadata = v);
              _notifyChanged();
            }, textPrimary: textPrimary),
            _buildSwitch(context, AppLocalizations.configDialogEmbedChapters, _embedChapters, (v) {
              setState(() => _embedChapters = v);
              _notifyChanged();
            }, textPrimary: textPrimary),
            _buildSwitch(
                context, AppLocalizations.configDialogDownloadSubtitles, _subtitlesEnabled, (v) {
              setState(() => _subtitlesEnabled = v);
              _notifyChanged();
            }, textPrimary: textPrimary),
            if (_subtitlesEnabled) _buildSubtitleControls(context,
              isDark: isDark,
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ],
        ),

        // SponsorBlock section (YouTube only)
        if (showSponsorBlock)
          _buildSection(
            context,
            title: AppLocalizations.configDialogSectionSponsorBlock,
            icon: Icons.skip_next,
            iconColor: AppColors.accentSecondary,
            expanded: _sponsorBlockExpanded,
            onToggle: () => setState(
                () => _sponsorBlockExpanded = !_sponsorBlockExpanded),
            sectionBarBg: sectionBarBg,
            sectionBarHover: sectionBarHover,
            headerColor: headerColor,
            textSecondary: textSecondary,
            children: [
              _buildSwitch(
                  context, AppLocalizations.configDialogEnableSponsorBlock, _sponsorBlockEnabled, (v) {
                setState(() => _sponsorBlockEnabled = v);
                _notifyChanged();
              }, textPrimary: textPrimary),
              if (_sponsorBlockEnabled) ...[
                _buildDropdown<String>(
                  context,
                  label: AppLocalizations.settingsSponsorBlockAction,
                  value: _sponsorBlockAction,
                  items: const ['skip', 'remove', 'chapter'],
                  displayName: (v) {
                    switch (v) {
                      case 'skip': return AppLocalizations.settingsSponsorBlockActionSkip;
                      case 'remove': return AppLocalizations.settingsSponsorBlockActionRemove;
                      case 'chapter': return AppLocalizations.settingsSponsorBlockActionChapter;
                      default: return v;
                    }
                  },
                  onChanged: (v) {
                    setState(() => _sponsorBlockAction = v);
                    _notifyChanged();
                  },
                  labelColor: labelColor,
                  dropdownBg: dropdownBg,
                  dropdownBorder: dropdownBorder,
                  textPrimary: textPrimary,
                ),
                _buildSponsorBlockCategories(context, isDark: isDark, textSecondary: textSecondary),
              ],
            ],
          ),

        // Platform section (conditional)
        if (showPlatformSection)
          _buildSection(
            context,
            title: AppLocalizations.configDialogSectionPlatform,
            icon: Icons.phone_android,
            iconColor: AppColors.accentTertiary,
            expanded: _platformExpanded,
            onToggle: () =>
                setState(() => _platformExpanded = !_platformExpanded),
            sectionBarBg: sectionBarBg,
            sectionBarHover: sectionBarHover,
            headerColor: headerColor,
            textSecondary: textSecondary,
            children: [
              _buildSwitch(context, AppLocalizations.configDialogRemoveTiktokWatermark,
                  _tiktokRemoveWatermark, (v) {
                setState(() => _tiktokRemoveWatermark = v);
                _notifyChanged();
              }, textPrimary: textPrimary),
            ],
          ),

        const SizedBox(height: AppSpacing.sm),

        // Save as default — angular checkbox
        if (_hasAnyOverride && widget.showSaveAsDefault)
          _buildSaveAsDefault(context, isDark: isDark, textPrimary: textPrimary, textSecondary: textSecondary),
        ],
      ),
    );
  }

  // ── Codec Hint (Mission Briefing alert) ──

  Widget _buildCodecHint(BuildContext context, bool isDark) {
    final shouldShow = SmartDefaultsService.shouldShowCodecHint(_videoCodec);
    if (!shouldShow) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.warningBgDark : AppColors.warningBgLight,
        border: Border(
          left: BorderSide(color: AppColors.warningAmber, width: 2),
          top: BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.2)),
          right:
              BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.2)),
          bottom:
              BorderSide(color: AppColors.warningAmber.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline,
              size: 14, color: AppColors.warningAmber),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.settingsSmartHintsCodecUpgrade,
              style: AppTypography.briefingCardSubtitle.copyWith(
                color: isDark
                    ? AppColors.warningTextDark
                    : AppColors.warningTextLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section Builder (Mission Briefing collapsible) ──

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    required Color sectionBarBg,
    required Color sectionBarHover,
    required Color headerColor,
    required Color textSecondary,
    bool pinnedOpen = false,
  }) {
    // Pinned sections always render content and omit the chevron/tap toggle —
    // they are the primary controls (Time Range, Format) and should read as
    // "live panel", not "click to expand".
    final effectivelyExpanded = pinnedOpen || expanded;
    final header = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.accentHighlight.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title.toUpperCase(),
            style: _sectionHeaderStyle.copyWith(color: headerColor),
          ),
          const Spacer(),
          if (!pinnedOpen)
            AnimatedRotation(
              turns: effectivelyExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                size: 16,
                color: textSecondary,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pinnedOpen)
            header
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                hoverColor: sectionBarHover,
                child: header,
              ),
            ),
          if (effectivelyExpanded)
            Padding(
              padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  right: AppSpacing.xs,
                  top: AppSpacing.sm,
                  bottom: AppSpacing.xs),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }

  // ── Dropdown Builder (Nocturne angular style) ──

  Widget _buildDropdown<T>(
    BuildContext context, {
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) displayName,
    required ValueChanged<T> onChanged,
    required Color labelColor,
    required Color dropdownBg,
    required Color dropdownBorder,
    required Color textPrimary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label.toUpperCase(),
              style: _labelStyle.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 192px (w-48) fixed dropdown with active stripe
          SizedBox(
            width: 192,
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dropdownBg,
                border: Border(
                  left: BorderSide(
                      color: AppColors.accentHighlight, width: 2),
                  top: BorderSide(color: dropdownBorder),
                  right: BorderSide(color: dropdownBorder),
                  bottom: BorderSide(color: dropdownBorder),
                ),
              ),
              child: DropdownButtonFormField<T>(
                value: value,
                isExpanded: true,
                dropdownColor: dropdownBg,
                icon: Icon(Icons.expand_more,
                    size: 14, color: AppColors.accentHighlight),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                items: items
                    .map((item) => DropdownMenuItem<T>(
                          value: item,
                          child: Text(displayName(item),
                              style: _dropdownTextStyle.copyWith(
                                  color: textPrimary)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onChanged(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionDropdown(BuildContext context, {
    required Color labelColor,
    required Color dropdownBg,
    required Color dropdownBorder,
    required Color textPrimary,
  }) {
    final resOptions = [0, 2160, 1440, 1080, 720, 480, 360];
    final labels = {
      0: AppLocalizations.settingsUnlimited,
      2160: AppLocalizations.settingsResolution4K,
      1440: AppLocalizations.settingsResolution2K,
      1080: AppLocalizations.settingsResolution1080p,
      720: AppLocalizations.settingsResolution720p,
      480: AppLocalizations.settingsResolution480p,
      360: AppLocalizations.settingsResolution360p,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              AppLocalizations.settingsMaxResolution.toUpperCase(),
              style: _labelStyle.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 192,
            height: 34,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dropdownBg,
                border: Border(
                  left: BorderSide(
                      color: AppColors.accentHighlight, width: 2),
                  top: BorderSide(color: dropdownBorder),
                  right: BorderSide(color: dropdownBorder),
                  bottom: BorderSide(color: dropdownBorder),
                ),
              ),
              child: DropdownButtonFormField<int>(
                value: resOptions.contains(_maxResolution) ? _maxResolution : 0,
                isExpanded: true,
                dropdownColor: dropdownBg,
                icon: Icon(Icons.expand_more,
                    size: 14, color: AppColors.accentHighlight),
                decoration: const InputDecoration(
                  isDense: true,
                  filled: false,
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                items: resOptions
                    .map((res) => DropdownMenuItem<int>(
                          value: res,
                          child: Text(labels[res] ?? '${res}p',
                              style: _dropdownTextStyle.copyWith(
                                  color: textPrimary)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _maxResolution = v);
                    _notifyChanged();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Switch Builder (compact Nocturne) ──

  /// Mission Briefing toggle row — hard 14×14 square checkbox + label.
  /// Replaces Material Switch for consistency with dialog footer toggles.
  Widget _buildSwitch(BuildContext context, String label, bool value,
      ValueChanged<bool> onChanged, {required Color textPrimary}) {
    final accent = AppColors.accentHighlight;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Row(
            children: [
              // Hard 14×14 square checkbox (operator hatch)
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: value ? accent : Colors.transparent,
                  border: Border.all(
                    color: value ? accent : AppColors.metaText(context),
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check, size: 10, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.briefingCardSubtitle.copyWith(
                    color: textPrimary,
                    fontSize: 11,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Subtitle Controls ──

  Widget _buildSubtitleControls(BuildContext context, {
    required bool isDark,
    required Color labelColor,
    required Color dropdownBg,
    required Color dropdownBorder,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    const subtitleFormats = ['srt', 'vtt', 'ass'];
    final videoInfo = widget.videoInfo;
    final hasVideoSubtitleData = videoInfo != null && videoInfo.hasSubtitleInfo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasVideoSubtitleData) ...[
          if (videoInfo.availableSubtitles.isNotEmpty)
            _buildSubtitleSection(
              context,
              label: AppLocalizations.configDialogSubtitleOriginal,
              tracks: videoInfo.availableSubtitles,
              icon: Icons.subtitles,
              isDark: isDark,
              textSecondary: textSecondary,
            ),
          _buildSwitch(
            context,
            AppLocalizations.configDialogIncludeAutoTranslated,
            _includeAutoSubs,
            (v) {
              setState(() => _includeAutoSubs = v);
              _notifyChanged();
            },
            textPrimary: textPrimary,
          ),
          if (_includeAutoSubs && videoInfo.availableAutoSubtitles.isNotEmpty)
            _buildSubtitleSection(
              context,
              label: AppLocalizations.configDialogSubtitleAutoTranslated,
              tracks: videoInfo.availableAutoSubtitles,
              icon: Icons.translate,
              isDark: isDark,
              textSecondary: textSecondary,
            ),
        ] else ...[
          _buildFallbackLanguageChips(context, isDark: isDark, textSecondary: textSecondary),
          _buildSwitch(context, 'Include auto-translated', _includeAutoSubs, (v) {
            setState(() => _includeAutoSubs = v);
            _notifyChanged();
          }, textPrimary: textPrimary),
        ],
        _buildDropdown<String>(
          context,
          label: AppLocalizations.configDialogSubtitleFormat,
          value: _subtitlesFormat,
          items: subtitleFormats,
          displayName: (v) => v.toUpperCase(),
          onChanged: (v) {
            setState(() => _subtitlesFormat = v);
            _notifyChanged();
          },
          labelColor: labelColor,
          dropdownBg: dropdownBg,
          dropdownBorder: dropdownBorder,
          textPrimary: textPrimary,
        ),
      ],
    );
  }

  Widget _buildSubtitleSection(
    BuildContext context, {
    required String label,
    required List<SubtitleTrackInfo> tracks,
    required IconData icon,
    required bool isDark,
    required Color textSecondary,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(icon, size: 12, color: textSecondary),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      style: _labelStyle.copyWith(color: textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: tracks.map((track) {
                final isSelected = _subtitlesLanguages.contains(track.lang);
                return _buildAngularChip(
                  context,
                  label: track.displayName,
                  selected: isSelected,
                  isDark: isDark,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _subtitlesLanguages.add(track.lang);
                      } else {
                        _subtitlesLanguages.remove(track.lang);
                      }
                    });
                    _notifyChanged();
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackLanguageChips(BuildContext context, {required bool isDark, required Color textSecondary}) {
    const availableLanguages = ['en', 'vi', 'ja', 'ko', 'zh', 'es', 'fr', 'de', 'pt', 'ru', 'ar', 'hi'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                AppLocalizations.configDialogSubtitleLanguages.toUpperCase(),
                style: _labelStyle.copyWith(color: textSecondary),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: availableLanguages.map((lang) {
                final isSelected = _subtitlesLanguages.contains(lang);
                return _buildAngularChip(
                  context,
                  label: lang.toUpperCase(),
                  selected: isSelected,
                  isDark: isDark,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _subtitlesLanguages.add(lang);
                      } else {
                        _subtitlesLanguages.remove(lang);
                      }
                    });
                    _notifyChanged();
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSponsorBlockCategories(BuildContext context, {required bool isDark, required Color textSecondary}) {
    const allCategories = [
      'sponsor', 'selfpromo', 'interaction', 'intro',
      'outro', 'preview', 'music_offtopic', 'filler',
    ];
    final displayNames = {
      'sponsor': AppLocalizations.settingsSponsorBlockCategorySponsor,
      'selfpromo': AppLocalizations.settingsSponsorBlockCategorySelfpromo,
      'interaction': AppLocalizations.settingsSponsorBlockCategoryInteraction,
      'intro': AppLocalizations.settingsSponsorBlockCategoryIntro,
      'outro': AppLocalizations.settingsSponsorBlockCategoryOutro,
      'preview': AppLocalizations.settingsSponsorBlockCategoryPreview,
      'music_offtopic': AppLocalizations.settingsSponsorBlockCategoryMusic,
      'filler': AppLocalizations.settingsSponsorBlockCategoryFiller,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                AppLocalizations.configDialogSponsorBlockCategories.toUpperCase(),
                style: _labelStyle.copyWith(color: textSecondary),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: allCategories.map((cat) {
                final isSelected = _sponsorBlockCategories.contains(cat);
                return _buildAngularChip(
                  context,
                  label: displayNames[cat] ?? cat,
                  selected: isSelected,
                  isDark: isDark,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _sponsorBlockCategories.add(cat);
                      } else {
                        _sponsorBlockCategories.remove(cat);
                      }
                    });
                    _notifyChanged();
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mission Briefing operator chip — square, no radius, accent stripe ──

  Widget _buildAngularChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required bool isDark,
    required ValueChanged<bool> onSelected,
  }) {
    final accent = AppColors.accentHighlight;
    return GestureDetector(
      onTap: () => onSelected(!selected),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : AppColors.surfaceLowest(context),
          border: Border(
            left: BorderSide(
              color: selected ? accent : Colors.transparent,
              width: 2,
            ),
            top: BorderSide(color: accent.withValues(alpha: 0.15)),
            right: BorderSide(color: accent.withValues(alpha: 0.15)),
            bottom: BorderSide(color: accent.withValues(alpha: 0.15)),
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: AppTypography.briefingMicroBadge.copyWith(
            fontSize: 10,
            color: selected ? accent : AppColors.metaText(context),
          ),
        ),
      ),
    );
  }

  // ── FFmpeg Warning (Mission Briefing alert) ──

  Widget _buildFFmpegWarning(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? AppColors.dangerBgDark : AppColors.dangerBgLight,
        border: Border(
          left: BorderSide(color: AppColors.errorRed, width: 2),
          top: BorderSide(color: AppColors.errorRed.withValues(alpha: 0.2)),
          right: BorderSide(color: AppColors.errorRed.withValues(alpha: 0.2)),
          bottom: BorderSide(color: AppColors.errorRed.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, size: 14, color: AppColors.errorRed),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              AppLocalizations.configDialogSectionRequiresFFmpeg,
              style: AppTypography.briefingCardSubtitle.copyWith(
                color: isDark
                    ? AppColors.dangerTextDark
                    : AppColors.dangerTextLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Time Range ──

  Widget _buildTimeRangeSlider(BuildContext context, Duration videoDuration) {
    final maxSeconds = videoDuration.inSeconds.toDouble();
    if (maxSeconds <= 0) return const SizedBox.shrink();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: AppColors.accentHighlight,
        inactiveTrackColor: AppColors.accentHighlight.withValues(alpha: 0.15),
        thumbColor: AppColors.accentHighlight,
        overlayColor: AppColors.accentHighlight.withValues(alpha: 0.20),
        trackHeight: 2,
        // Operator-grade square thumbs (Mission Briefing aesthetic)
        rangeThumbShape: const _SquareRangeThumb(thumbWidth: 10),
        rangeTrackShape: const RectangularRangeSliderTrackShape(),
      ),
      child: RangeSlider(
        values: RangeValues(
          _sectionStart.inSeconds.toDouble().clamp(0, maxSeconds),
          _sectionEnd.inSeconds.toDouble().clamp(0, maxSeconds),
        ),
        min: 0,
        max: maxSeconds,
        divisions: maxSeconds.toInt().clamp(1, 10000),
        labels: RangeLabels(
          _formatTimestamp(_sectionStart),
          _formatTimestamp(_sectionEnd),
        ),
        onChanged: (values) {
          setState(() {
            _sectionStart = Duration(seconds: values.start.toInt());
            _sectionEnd = Duration(seconds: values.end.toInt());
            _startController.text = _formatTimestamp(_sectionStart);
            _endController.text = _formatTimestamp(_sectionEnd);
          });
          _notifyChanged();
        },
      ),
    );
  }

  void _syncStartFromText(Duration videoDuration) {
    final parsed = _parseTimestamp(_startController.text);
    if (parsed != null && parsed >= Duration.zero && parsed < _sectionEnd && parsed < videoDuration) {
      setState(() => _sectionStart = parsed);
      _notifyChanged();
    }
  }

  void _syncEndFromText(Duration videoDuration) {
    final parsed = _parseTimestamp(_endController.text);
    if (parsed != null && parsed > _sectionStart && parsed <= videoDuration) {
      setState(() => _sectionEnd = parsed);
      _notifyChanged();
    }
  }

  void _finalizeStartField(Duration videoDuration) {
    final parsed = _parseTimestamp(_startController.text);
    if (parsed != null && parsed >= Duration.zero && parsed < _sectionEnd && parsed < videoDuration) {
      setState(() {
        _sectionStart = parsed;
        _startController.text = _formatTimestamp(parsed);
      });
      _notifyChanged();
    } else {
      _startController.text = _formatTimestamp(_sectionStart);
    }
  }

  void _finalizeEndField(Duration videoDuration) {
    final parsed = _parseTimestamp(_endController.text);
    if (parsed != null && parsed > _sectionStart && parsed <= videoDuration) {
      setState(() {
        _sectionEnd = parsed;
        _endController.text = _formatTimestamp(parsed);
      });
      _notifyChanged();
    } else {
      _endController.text = _formatTimestamp(_sectionEnd);
    }
  }

  Widget _buildTimeInputRow(BuildContext context, Duration videoDuration, {
    required Color dropdownBg,
    required Color dropdownBorder,
  }) {
    // Mission Briefing operator-grade square TextField (no radius)
    final inputDecoration = InputDecoration(
      isDense: true,
      filled: true,
      fillColor: dropdownBg,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide.none,
      ),
    );

    Widget buildField({
      required TextEditingController controller,
      required String label,
      required ValueChanged<String> onChanged,
      required ValueChanged<String> onSubmitted,
      required VoidCallback onFocusLost,
    }) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: dropdownBg,
          border: Border(
            left: BorderSide(color: AppColors.accentHighlight, width: 2),
            top: BorderSide(color: dropdownBorder),
            right: BorderSide(color: dropdownBorder),
            bottom: BorderSide(color: dropdownBorder),
          ),
        ),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) onFocusLost();
          },
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: controller,
              decoration: inputDecoration.copyWith(
                labelText: label.toUpperCase(),
                labelStyle: AppTypography.microLabel.copyWith(
                  color: AppColors.metaText(context),
                ),
              ),
              style: _dropdownTextStyle.copyWith(
                color: AppColors.accentHighlight,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d:]'))
              ],
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: buildField(
            controller: _startController,
            label: AppLocalizations.configDialogSectionStart,
            onChanged: (_) => _syncStartFromText(videoDuration),
            onSubmitted: (_) => _finalizeStartField(videoDuration),
            onFocusLost: () => _finalizeStartField(videoDuration),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Icon(Icons.arrow_forward,
              size: 14, color: AppColors.accentHighlight),
        ),
        Expanded(
          child: buildField(
            controller: _endController,
            label: AppLocalizations.configDialogSectionEnd,
            onChanged: (_) => _syncEndFromText(videoDuration),
            onSubmitted: (_) => _finalizeEndField(videoDuration),
            onFocusLost: () => _finalizeEndField(videoDuration),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedDuration(BuildContext context, Duration videoDuration, {required Color textSecondary}) {
    final selected = _sectionEnd - _sectionStart;
    return Text(
      AppLocalizations.configDialogSectionSelected(
        _formatTimestamp(selected),
        _formatTimestamp(videoDuration),
      ),
      style: AppTypography.statusBadge.copyWith(fontWeight: FontWeight.w400, color: textSecondary),
    );
  }

  Widget _buildChapterChips(BuildContext context, {required bool isDark}) {
    final chapters = widget.videoInfo?.chapters ?? [];
    if (chapters.isEmpty) return const SizedBox.shrink();

    final accent = AppColors.accentHighlight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.configDialogSectionSelectChapter.toUpperCase(),
          style: _labelStyle.copyWith(
            color: AppColors.metaText(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: chapters.map((chapter) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  _sectionStart = Duration(seconds: chapter.startTime.toInt());
                  _sectionEnd = Duration(seconds: chapter.endTime.toInt());
                  _startController.text = _formatTimestamp(_sectionStart);
                  _endController.text = _formatTimestamp(_sectionEnd);
                });
                _notifyChanged();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLowest(context),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  chapter.title.toUpperCase(),
                  style: AppTypography.briefingMicroBadge.copyWith(
                    fontSize: 10,
                    color: AppColors.metaText(context),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Save As Default (Mission Briefing operator card) ──

  Widget _buildSaveAsDefault(BuildContext context, {
    required bool isDark,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final accent = AppColors.accentHighlight;
    return GestureDetector(
      onTap: () {
        setState(() => _saveAsDefault = !_saveAsDefault);
        _notifyChanged();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd, vertical: AppSpacing.smMd),
        decoration: BoxDecoration(
          color: _saveAsDefault
              ? accent.withValues(alpha: 0.08)
              : AppColors.surfaceLowest(context),
          border: Border(
            left: BorderSide(
              color: _saveAsDefault ? accent : Colors.transparent,
              width: 2,
            ),
            top: BorderSide(color: accent.withValues(alpha: 0.15)),
            right: BorderSide(color: accent.withValues(alpha: 0.15)),
            bottom: BorderSide(color: accent.withValues(alpha: 0.15)),
          ),
        ),
        child: Row(
          children: [
            // Hard 14×14 square checkbox (operator hatch)
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: _saveAsDefault ? accent : Colors.transparent,
                border: Border.all(
                  color: _saveAsDefault
                      ? accent
                      : AppColors.metaText(context),
                  width: 1.5,
                ),
              ),
              child: _saveAsDefault
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.configDialogSaveAsDefault.toUpperCase(),
                    style: AppTypography.briefingCardTitle.copyWith(
                      color: _saveAsDefault ? accent : textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.configDialogSaveAsDefaultSubtitle,
                    style: AppTypography.briefingCardSubtitle.copyWith(
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Utility ──

  static String _formatTimestamp(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  static Duration? _parseTimestamp(String text) {
    final parts = text.split(':').map((p) => int.tryParse(p)).toList();
    if (parts.any((p) => p == null)) return null;
    final nums = parts.cast<int>();
    if (nums.length == 2) {
      return Duration(minutes: nums[0], seconds: nums[1]);
    } else if (nums.length == 3) {
      return Duration(hours: nums[0], minutes: nums[1], seconds: nums[2]);
    }
    return null;
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Mission Briefing operator-grade square thumb for RangeSlider.
/// Replaces default rounded thumb with hard 10×10 square.
class _SquareRangeThumb extends RangeSliderThumbShape {
  final double thumbWidth;
  const _SquareRangeThumb({required this.thumbWidth});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size(thumbWidth, thumbWidth);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool? isOnTop,
    TextDirection? textDirection,
    required SliderThemeData sliderTheme,
    Thumb? thumb,
    bool? isPressed,
  }) {
    final canvas = context.canvas;
    // Brand-aware fallback — never hardcode SSvid wine red.
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? AppColors.accentHighlight
      ..style = PaintingStyle.fill;
    final rect = Rect.fromCenter(
      center: center,
      width: thumbWidth,
      height: thumbWidth,
    );
    canvas.drawRect(rect, paint);
  }
}
