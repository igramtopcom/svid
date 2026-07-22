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
  // Hide the Container Format + Max Resolution rows. Set false when the host
  // already owns those choices (e.g. the QuickDownloadSheet picks format +
  // quality), so this panel shows only processing overrides and never
  // duplicates the outer surface. Default true keeps the full dialog intact.
  final bool showContainerAndResolution;
  // Hide the whole Subtitles section. Subtitles are inherently video-specific
  // (which languages exist depends on the actual video), so configuring them
  // as a blind default — before any URL is entered — is ambiguous. The
  // Default-download-options dialog sets this false; the per-download config
  // dialog (which has videoInfo) keeps it true.
  final bool showSubtitles;

  const ConfigPreferencesPanel({
    super.key,
    required this.settings,
    required this.platform,
    required this.onChanged,
    this.videoInfo,
    this.ffmpegAvailable = false,
    this.showSaveAsDefault = true,
    this.fileType,
    this.showContainerAndResolution = true,
    this.showSubtitles = true,
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
  // Which subtitle language groups (keyed by section label) are showing their
  // full list vs. the capped preview. Long auto-translated lists (~100 langs)
  // are collapsed by default to keep the panel scannable.
  final Set<String> _expandedSubGroups = {};
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
  late bool _platformExpanded;

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

    // Simplicity-first: every panel section starts collapsed so opening
    // "Advanced options" reveals a tidy list of section headers, not a wall of
    // dropdowns. A section still auto-opens when it holds a non-default value
    // (below) so the user can see what they've already customised.
    _formatExpanded = false;
    _extrasExpanded = !s.embedThumbnail ||
        !s.embedMetadata ||
        !s.embedChapters;
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

  // Clean, readable styles — sentence/title-case headers, no monospace values.
  static final _sectionHeaderStyle = AppTypography.buttonSecondary.copyWith(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );
  static final _labelStyle = AppTypography.metadata.copyWith(fontSize: 13);
  static final _dropdownTextStyle = AppTypography.buttonSecondary.copyWith(
    fontSize: 13.5,
  );

  // Row-level field labels (Action, Categories, Subtitle languages, …).
  // Uses metaText (WCAG-AA, full opacity) + w600 so they read clearly next
  // to the bright chips — muted() is reserved for disabled/inactive UI, not
  // real labels, and made "Categories" look washed out.
  TextStyle _rowLabelStyle(BuildContext context) => _labelStyle.copyWith(
        color: AppColors.metaText(context),
        fontWeight: FontWeight.w600,
      );

  // Small explanatory caption under a section (info icon + subtle text).
  Widget _buildInlineHint(BuildContext context, String text) {
    // metaText (full-opacity, WCAG-AA) not muted() — a hint the user can't
    // read is worse than no hint.
    final color = AppColors.metaText(context);
    return Padding(
      padding: const EdgeInsets.only(
          left: AppSpacing.xs, top: 2, bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 13, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: _labelStyle.copyWith(
                color: color,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTikTok = widget.platform == VideoPlatform.tiktok;
    final showPlatformSection = isTikTok;

    final videoDuration = widget.videoInfo?.duration;
    final hasChapters = widget.videoInfo?.hasChapters ?? false;

    // Mission Briefing panel colors — surfaceLowest wells, accent stripes
    final sectionBarBg = AppColors.surfaceLowest(context);
    final sectionBarHover = AppColors.accentHighlight.withValues(alpha: 0.06);
    final dropdownBg = AppColors.surfaceLowest(context);
    final dropdownBorder = AppColors.border(context);
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
        const SizedBox(height: AppSpacing.xs),
        // Time Range section (only when video has duration)
        if (videoDuration != null)
          _buildSection(
            context,
            title: AppLocalizations.configDialogSectionTimeRange,
            icon: Icons.content_cut,
            iconColor: AppColors.accentSecondary,
            expanded: false,
            onToggle: () {},
            toggleValue: _sectionEnabled,
            onToggleChanged: (v) {
              setState(() => _sectionEnabled = v);
              _notifyChanged();
            },
            sectionBarBg: sectionBarBg,
            sectionBarHover: sectionBarHover,
            headerColor: headerColor,
            textSecondary: textSecondary,
            children: [
              if (!widget.ffmpegAvailable) _buildFFmpegWarning(context, isDark),
              const SizedBox(height: AppSpacing.sm),
              _buildTimeRangeSlider(context, videoDuration),
              const SizedBox(height: AppSpacing.sm),
              _buildTimeInputRow(context, videoDuration,
                  dropdownBg: dropdownBg, dropdownBorder: dropdownBorder),
              const SizedBox(height: AppSpacing.sm),
              _buildSelectedDuration(context, videoDuration,
                  textSecondary: textSecondary),
              if (hasChapters) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildChapterChips(context, isDark: isDark),
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
          pinnedOpen: false,
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
            if (widget.showContainerAndResolution)
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
            if (widget.showContainerAndResolution)
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
          ],
        ),

        // Subtitles — promoted to its own section (it carries a whole
        // sub-panel of options: languages, format, auto-translate). The
        // header switch is the enable toggle; controls appear when ON.
        // Hidden in the blind-defaults dialog: which subtitle languages a
        // video has is unknowable until a URL is entered.
        if (widget.showSubtitles)
          _buildSection(
          context,
          title: AppLocalizations.configDialogSectionSubtitles,
          icon: Icons.closed_caption,
          iconColor: AppColors.accentTertiary,
          expanded: false,
          onToggle: () {},
          toggleValue: _subtitlesEnabled,
          onToggleChanged: (v) {
            setState(() => _subtitlesEnabled = v);
            _notifyChanged();
          },
          sectionBarBg: sectionBarBg,
          sectionBarHover: sectionBarHover,
          headerColor: headerColor,
          textSecondary: textSecondary,
          children: [
            _buildSubtitleControls(context,
              isDark: isDark,
              labelColor: labelColor,
              dropdownBg: dropdownBg,
              dropdownBorder: dropdownBorder,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),
          ],
        ),

        // SponsorBlock section removed (Chairman 2026-07): the feature
        // confused users more than it helped. The state fields stay at their
        // (off) defaults and still flow through to overrides, so nothing
        // downstream changes behaviour.

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
    // When provided, the section is an on/off feature: the header carries a
    // switch and its controls appear directly when ON (no extra "enable"
    // checkbox to hunt for). Otherwise it's a plain expand/collapse section.
    bool? toggleValue,
    ValueChanged<bool>? onToggleChanged,
  }) {
    final isToggle = toggleValue != null;
    final effectivelyExpanded =
        isToggle ? toggleValue : (pinnedOpen || expanded);
    final header = Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.smMd),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.border(context)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: iconColor),
          const SizedBox(width: AppSpacing.smMd),
          Expanded(
            child: Text(
              title,
              style: _sectionHeaderStyle.copyWith(color: headerColor),
            ),
          ),
          if (isToggle)
            _sectionSwitch(context, toggleValue)
          else if (!pinnedOpen)
            AnimatedRotation(
              turns: effectivelyExpanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(
                Icons.chevron_right,
                size: 18,
                color: textSecondary,
              ),
            ),
        ],
      ),
    );

    final onTap =
        isToggle ? () => onToggleChanged!(!toggleValue) : onToggle;

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
                onTap: onTap,
                hoverColor: sectionBarHover,
                child: header,
              ),
            ),
          if (effectivelyExpanded)
            Padding(
              padding: const EdgeInsets.only(
                  left: AppSpacing.sm,
                  right: AppSpacing.xs,
                  top: AppSpacing.smMd,
                  bottom: AppSpacing.xs),
              child: Column(children: children),
            ),
        ],
      ),
    );
  }

  /// Compact pill switch shown in a toggle-headed section's header.
  Widget _sectionSwitch(BuildContext context, bool value) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 38,
      height: 22,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color:
            value
                ? AppColors.accentHighlight
                : AppColors.metaText(context).withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 18,
          height: 18,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
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
              label,
              style: _rowLabelStyle(context),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 192,
            height: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dropdownBg,
                border: Border.all(color: dropdownBorder),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: DropdownButtonFormField<T>(
                value: value,
                isExpanded: true,
                dropdownColor: dropdownBg,
                borderRadius: BorderRadius.circular(AppRadius.input),
                icon: Icon(Icons.expand_more_rounded,
                    size: 18, color: AppColors.metaText(context)),
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
              AppLocalizations.settingsMaxResolution,
              style: _labelStyle.copyWith(color: labelColor),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 192,
            height: 38,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: dropdownBg,
                border: Border.all(color: dropdownBorder),
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              child: DropdownButtonFormField<int>(
                value: resOptions.contains(_maxResolution) ? _maxResolution : 0,
                isExpanded: true,
                dropdownColor: dropdownBg,
                borderRadius: BorderRadius.circular(AppRadius.input),
                icon: Icon(Icons.expand_more_rounded,
                    size: 18, color: AppColors.metaText(context)),
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
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: value ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: value ? accent : AppColors.metaText(context),
                    width: 1.5,
                  ),
                ),
                child: value
                    ? const Icon(Icons.check_rounded,
                        size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.buttonSecondary.copyWith(
                    color: textPrimary,
                    fontSize: 13.5,
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

    // videoInfo present but ZERO subtitle tracks (human + auto) → there is
    // nothing to configure. Show only an honest "no subtitles" line; the
    // 12-language grid, auto-translate switch and format dropdown would all be
    // meaningless and misleading for a video that has no subtitles.
    if (videoInfo != null && !videoInfo.hasSubtitleInfo) {
      return _buildInlineHint(
          context, AppLocalizations.configDialogSubtitleNone);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Real tracks → explain multi-select; unknown (no videoInfo) → the
        // language grid is a "try these" list, not a claim the video has them.
        _buildInlineHint(
            context,
            hasVideoSubtitleData
                ? AppLocalizations.configDialogSubtitleMultiHint
                : AppLocalizations.configDialogSubtitleFallbackHint),
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
          _buildSwitch(context, AppLocalizations.configDialogIncludeAutoTranslated, _includeAutoSubs, (v) {
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

  // Long language lists (auto-translated can be ~100 items) are capped to this
  // many chips; the rest hide behind a "Show all" pill so the panel stays scannable.
  static const int _subtitleChipCap = 14;

  Widget _buildSubtitleSection(
    BuildContext context, {
    required String label,
    required List<SubtitleTrackInfo> tracks,
    required IconData icon,
    required bool isDark,
    required Color textSecondary,
  }) {
    final selectedCount =
        tracks.where((t) => _subtitlesLanguages.contains(t.lang)).length;
    final needsCap = tracks.length > _subtitleChipCap;
    final expanded = _expandedSubGroups.contains(label);

    // Keep any selected chips visible even when collapsed, then fill the
    // remaining preview slots with unselected tracks.
    List<SubtitleTrackInfo> visible;
    if (expanded || !needsCap) {
      visible = tracks;
    } else {
      final selected =
          tracks.where((t) => _subtitlesLanguages.contains(t.lang)).toList();
      final unselected =
          tracks.where((t) => !_subtitlesLanguages.contains(t.lang)).toList();
      final room =
          (_subtitleChipCap - selected.length).clamp(0, unselected.length);
      visible = [...selected, ...unselected.take(room)];
    }
    final hiddenCount = tracks.length - visible.length;

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
                  Icon(icon, size: 12, color: AppColors.metaText(context)),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: _rowLabelStyle(context),
                    ),
                  ),
                  if (selectedCount > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _buildSelectedCountBadge(context, selectedCount),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                ...visible.map((track) {
                  final isSelected =
                      _subtitlesLanguages.contains(track.lang);
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
                }),
                if (needsCap)
                  _buildShowMorePill(
                    context,
                    expanded: expanded,
                    hiddenCount: hiddenCount,
                    onTap: () => setState(() {
                      if (expanded) {
                        _expandedSubGroups.remove(label);
                      } else {
                        _expandedSubGroups.add(label);
                      }
                    }),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Compact count badge shown next to a subtitle group label.
  Widget _buildSelectedCountBadge(BuildContext context, int count) {
    final accent = AppColors.accentHighlight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '$count',
        style: AppTypography.buttonSecondary.copyWith(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
    );
  }

  // "Show all (N)" / "Show less" pill that toggles a capped language list.
  Widget _buildShowMorePill(
    BuildContext context, {
    required bool expanded,
    required int hiddenCount,
    required VoidCallback onTap,
  }) {
    final label = expanded
        ? AppLocalizations.configDialogSubtitleShowLess
        : '${AppLocalizations.configDialogSubtitleShowAll} ($hiddenCount)';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: AppColors.border(context),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 13,
              color: AppColors.metaText(context),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: AppTypography.buttonSecondary.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.metaText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackLanguageChips(BuildContext context, {required bool isDark, required Color textSecondary}) {
    const availableLanguages = ['en', 'vi', 'ja', 'ko', 'zh', 'es', 'fr', 'de', 'pt', 'ru', 'ar', 'hi'];
    final selectedCount =
        availableLanguages.where(_subtitlesLanguages.contains).length;

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
                  Flexible(
                    child: Text(
                      AppLocalizations.configDialogSubtitleLanguages,
                      style: _rowLabelStyle(context),
                    ),
                  ),
                  if (selectedCount > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _buildSelectedCountBadge(context, selectedCount),
                  ],
                ],
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

  // ── Rounded selectable chip (categories, languages) ──

  Widget _buildAngularChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required bool isDark,
    required ValueChanged<bool> onSelected,
    String? tooltip,
  }) {
    final accent = AppColors.accentHighlight;
    Widget chip = GestureDetector(
      onTap: () => onSelected(!selected),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.16 : 0.10)
              : AppColors.surface2(context),
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: selected ? accent : AppColors.border(context),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.buttonSecondary.copyWith(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: selected ? accent : AppColors.metaText(context),
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      chip = Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 400),
        child: chip,
      );
    }
    return chip;
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
        trackHeight: 4,
        // Friendly round thumbs — larger and easier to grab than the old
        // 10px squares, with a soft white ring so they read on any track.
        rangeThumbShape: const RoundRangeSliderThumbShape(
          enabledThumbRadius: 9,
          elevation: 2,
          pressedElevation: 4,
        ),
        rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
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
    // Rounded time field — the DecoratedBox draws the border/fill, so the
    // TextField itself is borderless and unfilled (no square corners peeking
    // through the rounded box).
    final inputDecoration = InputDecoration(
      isDense: true,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
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
          border: Border.all(color: dropdownBorder),
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) onFocusLost();
          },
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: controller,
              decoration: inputDecoration.copyWith(
                labelText: label,
                labelStyle: AppTypography.metadata.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.metaText(context),
                ),
                floatingLabelStyle: AppTypography.metadata.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accentHighlight,
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
    return Row(
      children: [
        Icon(Icons.content_cut,
            size: 12, color: AppColors.metaText(context)),
        const SizedBox(width: AppSpacing.xs),
        Text(
          AppLocalizations.configDialogSectionSelected(
            _formatTimestamp(selected),
            _formatTimestamp(videoDuration),
          ),
          style: AppTypography.metadata.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.metaText(context),
          ),
        ),
      ],
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
          AppLocalizations.configDialogSectionSelectChapter,
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
                  chapter.title,
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
                    AppLocalizations.configDialogSaveAsDefault,
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

