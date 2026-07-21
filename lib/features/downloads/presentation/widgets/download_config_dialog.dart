import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/domain/enums/audio_codec_preference.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/domain/enums/fps_preference.dart';
import '../../../settings/domain/enums/video_codec_preference.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_config.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/quality_resolution_parser.dart';
import '../../domain/services/format_selector_service.dart'
    show FormatSelectionWarning, FormatSelectionWarningCode;
import '../providers/download_path_suggestion_provider.dart';
import '../utils/download_format_warning.dart';
import 'config_preferences_panel.dart';

/// Download configuration dialog — PR #234 contract on Mission Briefing chassis.
///
/// Layout: File Type chips → Quality intent (Recommended / Best available /
/// Choose) → Save location → Secondary toggles (Remember / Save as default /
/// Apply to all) → Advanced accordion (technical streams + chapter selection +
/// preferences panel). Returns a [DownloadConfig] with portable file type /
/// quality intent / quality target — backend resolves via
/// [FormatSelectorService].
class DownloadConfigDialog extends ConsumerStatefulWidget {
  final VideoInfo videoInfo;
  final VideoPlatform platform;
  final int? remainingCount;

  const DownloadConfigDialog({
    super.key,
    required this.videoInfo,
    required this.platform,
    this.remainingCount,
  });

  static Future<DownloadConfig?> show(
    BuildContext context,
    VideoInfo videoInfo,
    VideoPlatform platform, {
    int? remainingCount,
  }) {
    return showDialog<DownloadConfig>(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => DownloadConfigDialog(
            videoInfo: videoInfo,
            platform: platform,
            remainingCount: remainingCount,
          ),
    );
  }

  @override
  ConsumerState<DownloadConfigDialog> createState() =>
      _DownloadConfigDialogState();
}

enum _DialogFileType { video, audio, image, subtitle }

class _QualityIntentRow {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Quality? quality;
  final DownloadQualityIntent intent;
  final PortableQualityTarget? target;
  final bool opensMore;
  // True when this row exists only to advertise a Premium-gated capability
  // (e.g. "Best available" for a free user when every quality > 1080p).
  // Click handler fires the upgrade prompt instead of selecting a quality.
  final bool requiresUpgrade;

  const _QualityIntentRow({
    required this.label,
    required this.icon,
    required this.intent,
    this.subtitle,
    this.quality,
    this.target,
    this.opensMore = false,
    this.requiresUpgrade = false,
  });
}

class _DownloadConfigDialogState extends ConsumerState<DownloadConfigDialog> {
  static const List<int> _audioBitrateChoicesKbps = [
    320,
    256,
    192,
    160,
    128,
    96,
    64,
  ];

  late ContentMode _mode;

  // Primary selection state (PR #234 contract)
  late _DialogFileType _selectedFileType;
  DownloadQualityIntent _selectedQualityIntent =
      DownloadQualityIntent.recommended;
  PortableQualityTarget? _selectedQualityTarget;
  Quality? _selectedQuality;
  int _selectedAudioBitrateKbps = 320;
  String? _savePathOverride;
  int? _availableBytes;
  bool _advancedExpanded = false;

  // Flow control
  bool _rememberForPlatform = false;
  bool _applyToAll = false;
  bool _saveAsDefault = false;

  // Preferences panel sync (right side, inside advanced accordion)
  final _prefsKey = GlobalKey<ConfigPreferencesPanelState>();
  final _advancedSectionKey = GlobalKey();
  late VideoCodecPreference _videoCodec;
  late AudioCodecPreference _audioCodec;
  late ContainerFormatPreference _containerFormat;
  late FpsPreference _fps;
  late int _maxResolution;
  late bool _subtitlesEnabled;
  late List<String> _subtitlesLanguages;
  late String _subtitlesFormat;
  late bool _includeAutoSubs;
  late bool _embedThumbnail;
  late bool _embedMetadata;
  late bool _embedChapters;
  late bool _sponsorBlockEnabled;
  late String _sponsorBlockAction;
  late List<String> _sponsorBlockCategories;
  late bool _tiktokRemoveWatermark;
  Duration? _sectionStartTime;
  Duration? _sectionEndTime;

  // Per-chapter selection state. Default = empty (no filter, full download).
  // Resolved to time ranges via [_resolveSelectedChapterRanges] and
  // threaded into [DownloadConfig.selectedChapterRanges].
  final Set<int> _selectedChapterIndices = <int>{};

  // Captured during _initializePrimarySelection when a saved preference
  // (intent/target) couldn't be honored against the current video's
  // available qualities — e.g., user saved "Always 4K" for YouTube but
  // this video tops out at 1080p. Surfaced as a snackbar after the dialog
  // mounts so the user understands why the selection differs from what
  // they previously chose. One-shot per dialog open.
  String? _initWarningMessage;

  @override
  void initState() {
    super.initState();
    _initializeFromSettings();
    _detectContentMode();
    _initializePrimarySelection();
    if (widget.remainingCount != null && widget.remainingCount! > 1) {
      _applyToAll = true;
    }
    // Seed chapter selection with the full set so the header toggle starts
    // in "Clear" state and the checkbox column reflects the default
    // "download everything" intent. Resolver still emits null ranges when
    // every index is selected (no --download-sections), preserving the
    // bit-for-bit full-download behavior.
    _selectedChapterIndices.addAll(
      List.generate(widget.videoInfo.chapters.length, (i) => i),
    );
    // Simplicity-first default: the dialog opens showing only the essentials
    // (file type / quality / save location). Everything technical — codecs,
    // container, fps, max resolution, section-clip, chapters, extras,
    // SponsorBlock — lives behind this "Advanced options" accordion, collapsed
    // by default so a normal user is never confronted with the full surface.
    _advancedExpanded = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshFreeSpace();
      _surfaceInitWarning();
    });
  }

  void _surfaceInitWarning() {
    final message = _initWarningMessage;
    if (message == null) return;
    if (!mounted) return;
    AppSnackBar.warning(context, message: message);
    // Consume — never repeat on rebuild.
    _initWarningMessage = null;
  }

  void _initializeFromSettings() {
    final settings = ref.read(settingsProvider);
    _videoCodec = settings.videoCodecPreference;
    _audioCodec = settings.audioCodecPreference;
    _containerFormat = settings.containerFormatPreference;
    _fps = settings.fpsPreference;
    _maxResolution = settings.maxResolution;
    _subtitlesEnabled = settings.subtitlesEnabled;
    _subtitlesLanguages = List<String>.from(settings.subtitlesLanguages);
    _subtitlesFormat = settings.subtitlesFormat;
    _includeAutoSubs = settings.includeAutoSubs;
    _embedThumbnail = settings.embedThumbnail;
    _embedMetadata = settings.embedMetadata;
    _embedChapters = settings.embedChapters;
    _sponsorBlockEnabled = settings.sponsorBlockEnabled;
    _sponsorBlockAction = settings.sponsorBlockAction;
    _sponsorBlockCategories = List<String>.from(
      settings.sponsorBlockCategories,
    );
    _tiktokRemoveWatermark = settings.tiktokRemoveWatermark;
  }

  void _detectContentMode() {
    final qualities = widget.videoInfo.availableQualities;
    if (qualities.length == 1) {
      _mode = ContentMode.singleItem;
      return;
    }
    final hasImages = qualities.any((q) => q.mediaType == MediaType.image);
    final hasVideos = qualities.any((q) => q.mediaType == MediaType.video);
    if (hasImages && hasVideos) {
      _mode = ContentMode.mixedContent;
    } else {
      _mode = ContentMode.multiItems;
    }
  }

  void _initializePrimarySelection() {
    final settings = ref.read(settingsProvider);
    _selectedFileType = _defaultFileType();
    final savedIntent = settings.defaultDownloadQualityIntent;
    final savedTarget = settings.defaultDownloadQualityTarget;
    final savedQuality = _qualityForIntent(
      _selectedFileType,
      savedIntent,
      savedTarget,
    );
    if (savedQuality != null) {
      _selectedQualityIntent = savedIntent;
      _selectedQualityTarget = savedTarget;
      _selectedQuality = savedQuality;
      final savedBitrate = savedTarget?.targetBitrateKbps;
      if (_selectedFileType == _DialogFileType.audio && savedBitrate != null) {
        _selectedAudioBitrateKbps = savedBitrate;
      }
      return;
    }
    // Saved intent/target couldn't be honored against this video's
    // formats. Detect specifically the "user saved a target but we had to
    // fall back" case so we can surface a [FormatSelectionWarning] to the
    // user instead of silently downgrading the selection.
    if (savedTarget != null) {
      final fallback = _recommendedQualityFor(_selectedFileType);
      _initWarningMessage = formatSelectionWarningMessage(
        FormatSelectionWarning(
          code: FormatSelectionWarningCode.exactUnavailable,
          requestedLabel: _portableTargetLabel(savedTarget),
          resolvedLabel:
              fallback == null ? null : _qualityResolutionLabel(fallback),
          messageKey: 'configDialog.qualityFallbackWarning',
        ),
      );
    } else if (savedIntent == DownloadQualityIntent.bestAvailable &&
        _bestAvailableVideoQuality() == null) {
      // Saved "best available" preference but no eligible quality exists
      // (free-tier ceiling, or video has no video formats at all). Don't
      // pretend we honored it — surface a warning.
      _initWarningMessage = formatSelectionWarningMessage(
        FormatSelectionWarning(
          code: FormatSelectionWarningCode.formatUnavailable,
          requestedLabel: AppLocalizations.configDialogBestAvailable,
          messageKey: 'errorFeedback.formatUnavailable',
        ),
      );
    }
    _selectedQualityIntent = DownloadQualityIntent.recommended;
    _selectedQualityTarget = null;
    _selectedQuality = _recommendedQualityFor(_selectedFileType);
    if (_selectedFileType == _DialogFileType.audio &&
        _selectedQuality != null) {
      _selectedQualityIntent = DownloadQualityIntent.specific;
      _selectedQualityTarget = _targetForQuality(_selectedQuality!);
    }
  }

  /// Human-readable label for a [PortableQualityTarget] — used as the
  /// "requested" half of a [FormatSelectionWarning] message.
  String _portableTargetLabel(PortableQualityTarget target) {
    switch (target.fileType) {
      case DownloadFileType.video:
        final h = target.targetHeight;
        if (h == null) return AppLocalizations.configDialogVideo;
        if (h >= 4320) return '8K';
        if (h >= 2160) return '4K';
        if (h >= 1440) return '1440p';
        return '${h}p';
      case DownloadFileType.audio:
        final bits = target.targetBitrateKbps;
        final fmt = target.outputFormat ?? 'mp3';
        return bits == null
            ? _audioOutputFormatLabel(fmt)
            : '${_audioOutputFormatLabel(fmt)} · $bits kbps';
      case DownloadFileType.subtitle:
        return target.languageCode ?? AppLocalizations.configDialogSubtitle;
      case DownloadFileType.image:
        return AppLocalizations.configDialogImage;
    }
  }

  List<Quality> _getSelectedQualities() {
    final q = _selectedQuality;
    return q == null ? const [] : [q];
  }

  void _onPreferencesChanged(PreferencesOverrides _) {
    final panel = _prefsKey.currentState;
    if (panel == null) return;
    final s = panel.currentState;
    setState(() {
      _videoCodec = s.videoCodec;
      _audioCodec = s.audioCodec;
      _containerFormat = s.containerFormat;
      _fps = s.fps;
      _maxResolution = s.maxResolution;
      _subtitlesEnabled = s.subtitlesEnabled;
      _subtitlesLanguages = s.subtitlesLanguages;
      _subtitlesFormat = s.subtitlesFormat;
      _includeAutoSubs = s.includeAutoSubs;
      _embedThumbnail = s.embedThumbnail;
      _embedMetadata = s.embedMetadata;
      _embedChapters = s.embedChapters;
      _sponsorBlockEnabled = s.sponsorBlockEnabled;
      _sponsorBlockAction = s.sponsorBlockAction;
      _sponsorBlockCategories = s.sponsorBlockCategories;
      _tiktokRemoveWatermark = s.tiktokRemoveWatermark;
      _sectionStartTime = s.sectionStartTime;
      _sectionEndTime = s.sectionEndTime;
    });
  }

  Future<void> _onDownload() async {
    final selected = _getSelectedQualities();
    if (selected.isEmpty) return;

    // Free-tier resolution cap with upgrade nudge (Mission Briefing preserve).
    final isPremium = ref.read(isPremiumProvider);
    if (!isPremium) {
      final blocked =
          selected.where(QualityResolutionParser.isAboveFreeLimit).firstOrNull;
      if (blocked != null) {
        final height = QualityResolutionParser.heightForQuality(blocked) ?? 0;
        appLogger.info(
          '🚫 [Premium] Dialog blocked ${height}p quality for free tier',
        );
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.highQuality4K,
        );
        return;
      }
    }

    if (_applyToAll &&
        widget.remainingCount != null &&
        widget.remainingCount! > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _buildApplyToAllConfirm(ctx),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }

    // Final sync from panel (captures mid-typing values).
    final panel = _prefsKey.currentState;
    if (panel != null) {
      final s = panel.currentState;
      _sectionStartTime = s.sectionStartTime;
      _sectionEndTime = s.sectionEndTime;
    }

    final settings = ref.read(settingsProvider);
    final chapterRanges = _resolveSelectedChapterRanges();

    final config = DownloadConfig(
      selectedQualities: selected,
      fileType: _downloadFileTypeFor(_selectedFileType),
      qualityIntent: _selectedQualityIntent,
      qualityTarget: _selectedQualityTarget,
      videoCodecOverride:
          _videoCodec != settings.videoCodecPreference ? _videoCodec : null,
      audioCodecOverride:
          _audioCodec != settings.audioCodecPreference ? _audioCodec : null,
      containerFormatOverride:
          _containerFormat != settings.containerFormatPreference
              ? _containerFormat
              : null,
      fpsOverride: _fps != settings.fpsPreference ? _fps : null,
      maxResolutionOverride:
          _maxResolution != settings.maxResolution ? _maxResolution : null,
      subtitlesEnabled:
          _subtitlesEnabled != settings.subtitlesEnabled
              ? _subtitlesEnabled
              : null,
      subtitlesLanguages:
          !_listEquals(_subtitlesLanguages, settings.subtitlesLanguages)
              ? _subtitlesLanguages
              : null,
      subtitlesFormat:
          _subtitlesFormat != settings.subtitlesFormat
              ? _subtitlesFormat
              : null,
      includeAutoSubs:
          _includeAutoSubs != settings.includeAutoSubs
              ? _includeAutoSubs
              : null,
      embedThumbnail:
          _embedThumbnail != settings.embedThumbnail ? _embedThumbnail : null,
      embedMetadata:
          _embedMetadata != settings.embedMetadata ? _embedMetadata : null,
      embedChapters:
          _embedChapters != settings.embedChapters ? _embedChapters : null,
      sponsorBlockEnabled:
          _sponsorBlockEnabled != settings.sponsorBlockEnabled
              ? _sponsorBlockEnabled
              : null,
      sponsorBlockAction:
          _sponsorBlockAction != settings.sponsorBlockAction
              ? _sponsorBlockAction
              : null,
      sponsorBlockCategories:
          !_listEquals(_sponsorBlockCategories, settings.sponsorBlockCategories)
              ? _sponsorBlockCategories
              : null,
      tiktokRemoveWatermark:
          _tiktokRemoveWatermark != settings.tiktokRemoveWatermark
              ? _tiktokRemoveWatermark
              : null,
      sectionStartTime: _sectionStartTime,
      sectionEndTime: _sectionEndTime,
      // Chapter selection suppressed when explicit time-range is set —
      // section selection is more granular and wins in the yt-dlp arg
      // builder.
      selectedChapterRanges: _sectionStartTime != null ? null : chapterRanges,
      applyToAll: _applyToAll,
      rememberForPlatform: _rememberForPlatform,
      saveAsDefault: _saveAsDefault,
      savePathOverride: _savePathOverride,
    );

    if (!mounted) return;
    Navigator.pop(context, config);
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final ffmpegAvailable =
        ref.watch(binaryAvailableProvider(BinaryType.ffmpeg)).valueOrNull ??
        false;
    final screenSize = MediaQuery.of(context).size;
    final selectedQualities = _getSelectedQualities();
    final canDownload = selectedQualities.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: screenSize.width * 0.06,
        vertical: screenSize.height * 0.06,
      ),
      clipBehavior: Clip.antiAlias,
      backgroundColor: AppColors.base(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(
          color: AppColors.accentHighlight.withValues(
            alpha: isDark ? 0.18 : 0.12,
          ),
          width: 1,
        ),
      ),
      child: SizedBox(
        width: screenSize.width * 0.88,
        height: screenSize.height * 0.88,
        child: Column(
          children: [
            _buildTitleBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMediaPreviewStrip(context),
                    const SizedBox(height: AppSpacing.md),
                    _buildPrimaryOptionsPanel(context),
                    const SizedBox(height: AppSpacing.md),
                    _buildSecondaryOptionsRow(context),
                    const SizedBox(height: AppSpacing.md),
                    _buildAdvancedAccordion(context, settings, ffmpegAvailable),
                  ],
                ),
              ),
            ),
            _buildFooter(context, canDownload, selectedQualities),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TITLE BAR (Mission Briefing aesthetic)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildTitleBar(BuildContext context) {
    final accent = AppColors.accentHighlight;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.base(context),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.15), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.download_for_offline_outlined, color: accent, size: 28),
          const SizedBox(width: AppSpacing.smMd),
          Text(
            AppLocalizations.configDialogTitle,
            style: AppTypography.commandTitle.copyWith(color: accent),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              border: Border.all(
                color: accent.withValues(alpha: 0.30),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'READY',
                  style: AppTypography.microLabel.copyWith(
                    letterSpacing: 1.5,
                    fontSize: 9,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.smMd),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close, color: AppColors.metaText(context)),
            iconSize: 22,
            visualDensity: VisualDensity.compact,
            tooltip: AppLocalizations.commonClose,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // MEDIA PREVIEW STRIP
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildMediaPreviewStrip(BuildContext context) {
    final info = widget.videoInfo;
    final metadata = <String>[
      info.effectivePlatform,
      if (info.effectiveUploader != null && info.effectiveUploader!.isNotEmpty)
        info.effectiveUploader!,
      if (info.uploadDate != null)
        '${info.uploadDate!.day.toString().padLeft(2, '0')}/${info.uploadDate!.month.toString().padLeft(2, '0')}/${info.uploadDate!.year}',
    ].where((s) => s.trim().isNotEmpty && s != 'unknown').join(' • ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          children: [
            AppCachedImage(
              imageUrl: info.thumbnail,
              width: 192,
              height: 108,
              borderRadius: BorderRadius.circular(2),
            ),
            if (info.duration != null)
              Positioned(
                right: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    _formatDuration(info.duration!),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                info.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.metaText(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // PRIMARY OPTIONS PANEL (FileType + Quality + SaveLocation, 3-col)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildPrimaryOptionsPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest(context),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 860;
          if (stack) {
            return Column(
              children: [
                _buildFileTypeColumn(context),
                Divider(height: 1, color: AppColors.border(context)),
                _buildQualityColumn(context),
                Divider(height: 1, color: AppColors.border(context)),
                _buildSaveLocationColumn(context),
              ],
            );
          }
          // Stack-pattern lifted from PR #234 — Row of columns (start-aligned,
          // so individual columns size to their natural height) PLUS a
          // Positioned.fill Row of vertical dividers that stretches to the
          // tallest column. Avoids the LayoutBuilder + IntrinsicHeight cycle
          // that the framework forbids.
          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _buildFileTypeColumn(context)),
                  Expanded(child: _buildQualityColumn(context)),
                  Expanded(child: _buildSaveLocationColumn(context)),
                ],
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Expanded(child: SizedBox.shrink()),
                      SizedBox(
                        width: 1,
                        child: ColoredBox(color: AppColors.border(context)),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                      SizedBox(
                        width: 1,
                        child: ColoredBox(color: AppColors.border(context)),
                      ),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFileTypeColumn(BuildContext context) {
    final types = _availableFileTypes();
    final formatPicker = _buildPrimaryFormatPicker(context);
    return _buildOptionColumn(
      context,
      title: AppLocalizations.configDialogFileType,
      children: [
        for (final type in types)
          _buildSelectableOption(
            context,
            selected: _selectedFileType == type,
            icon: _fileTypeIcon(type),
            title: _fileTypeLabel(type),
            subtitle: _fileTypeHint(type),
            onTap: () => _selectFileType(type),
          ),
        if (formatPicker != null) ...[
          const SizedBox(height: AppSpacing.xs),
          formatPicker,
        ],
      ],
    );
  }

  Widget? _buildPrimaryFormatPicker(BuildContext context) {
    // Video container (MP4 by default) is a power-user choice — it lives in
    // Advanced → Format → Container so the essentials view stays clean. Audio
    // output format, by contrast, has no Advanced equivalent and is a genuine
    // primary decision for an audio download, so it stays inline below.
    if (_selectedFileType == _DialogFileType.audio) {
      final formats = _availableAudioOutputFormats();
      if (formats.isEmpty) return null;
      final currentFormat = _selectedAudioOutputFormat() ?? formats.first;
      return _buildInlineFormatGroup(
        context,
        title: AppLocalizations.configDialogAudioFormat,
        icon: Icons.graphic_eq_rounded,
        children: [
          for (final format in formats)
            _buildFormatChip(
              context,
              label: _audioOutputFormatLabel(format),
              subtitle: _audioFormatSubtitle(format),
              selected: currentFormat == format,
              onTap: () => _selectAudioOutputFormat(format),
            ),
        ],
      );
    }

    return null;
  }

  Widget _buildInlineFormatGroup(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
    Widget? footer,
  }) {
    final accent = AppColors.accentHighlight;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface2(context).withValues(alpha: 0.52),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: children,
          ),
          if (footer != null) ...[
            const SizedBox(height: AppSpacing.sm),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _buildFormatChip(
    BuildContext context, {
    required String label,
    required String subtitle,
    required bool selected,
    bool warning = false,
    required VoidCallback onTap,
  }) {
    // RC10 UX polish (Codex round-4) — `warning` here historically
    // meant "container requires recoding" (AVI/MOV/M4V/FLV). The
    // amber warning palette read as "danger/error" to testers when
    // recoding is actually expected and supported behavior. Render
    // recode chips with a NEUTRAL tone: same base background as
    // regular chips, a soft outline, and a `sync_rounded` icon to
    // signal "this format converts" without alarming the user.
    // Keeping the bool param name for call-site stability; the
    // semantic is "needs recoding" not "user error".
    final recodes = warning;
    final accent = AppColors.accentHighlight;
    final neutralIcon = AppColors.metaText(context);
    final neutralBorder = AppColors.border(context);
    return Tooltip(
      message: subtitle,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minWidth: 74, minHeight: 38),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.12)
                : AppColors.base(context),
            border: Border.all(
              color: selected ? accent : neutralBorder,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : recodes
                        ? Icons.sync_rounded
                        : Icons.circle_outlined,
                size: 15,
                color: selected ? accent : neutralIcon,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.metadata.copyWith(
                  color: selected ? accent : null,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildQualityColumn(BuildContext context) {
    final intents = _qualityIntentsFor(_selectedFileType);
    return _buildOptionColumn(
      context,
      title: AppLocalizations.configDialogQuality,
      children: [
        for (final intent in intents)
          _buildSelectableOption(
            context,
            selected: _isIntentSelected(intent),
            icon: intent.icon,
            title: intent.label,
            subtitle:
                intent.requiresUpgrade
                    ? '${intent.subtitle ?? ''} · ${AppLocalizations.premiumUpgrade}'
                    : intent.subtitle,
            trailing:
                intent.opensMore
                    ? Icon(
                      Icons.chevron_right,
                      color: AppColors.metaText(context),
                    )
                    : intent.requiresUpgrade
                    ? Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.accentHighlight,
                    )
                    : null,
            onTap: () {
              if (intent.requiresUpgrade) {
                _promptUpgradeForBestAvailable();
              } else if (intent.opensMore) {
                _showMoreQualities();
              } else if (intent.quality != null) {
                setState(() {
                  _selectedQuality = intent.quality;
                  _selectedQualityIntent = intent.intent;
                  _selectedQualityTarget = intent.target;
                  if (_selectedFileType == _DialogFileType.audio &&
                      intent.target?.targetBitrateKbps != null) {
                    _selectedAudioBitrateKbps =
                        intent.target!.targetBitrateKbps!;
                  }
                });
                _refreshFreeSpace();
              }
            },
          ),
      ],
    );
  }

  bool _isIntentSelected(_QualityIntentRow intent) {
    if (intent.requiresUpgrade) return false;
    if (intent.opensMore) {
      // "Choose quality" highlights only when the user has explicitly picked
      // a specific quality from the More dialog (specific intent, no target
      // match in the visible rows).
      if (_selectedQualityIntent != DownloadQualityIntent.specific) {
        return false;
      }
      final intents = _qualityIntentsFor(
        _selectedFileType,
      ).where((i) => !i.opensMore && i.quality != null);
      return !intents.any(
        (i) => i.quality!.encryptedUrl == _selectedQuality?.encryptedUrl,
      );
    }
    if (intent.quality == null) return false;
    if (_selectedFileType == _DialogFileType.audio) {
      final target = intent.target;
      if (target?.fileType != DownloadFileType.audio) return false;
      final selectedFormat = _selectedAudioOutputFormat();
      final targetFormat = _normalizeAudioOutputFormat(target!.outputFormat);
      if (_isLosslessAudioFormat(targetFormat)) {
        return selectedFormat == targetFormat &&
            target.targetBitrateKbps == null;
      }
      return selectedFormat == targetFormat &&
          _selectedAudioBitrateKbps == target.targetBitrateKbps;
    }
    return _selectedQuality?.encryptedUrl == intent.quality!.encryptedUrl &&
        _selectedQualityIntent == intent.intent;
  }

  Widget _buildSaveLocationColumn(BuildContext context) {
    final String basePath =
        _savePathOverride ?? ref.watch(downloadPathProvider);
    final outputPath = _resolvedOutputPath(basePath);
    final estimatedBytes = _selectedEstimatedBytes();
    return _buildOptionColumn(
      context,
      title: AppLocalizations.configDialogDownloadLocation,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 300;
            final pathField = _buildPathField(context, outputPath);
            final changeButton = _buildChangeFolderButton(context);
            if (stack) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  pathField,
                  const SizedBox(height: AppSpacing.sm),
                  changeButton,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: pathField),
                const SizedBox(width: AppSpacing.sm),
                changeButton,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        if (outputPath != basePath)
          _buildLocationHelper(
            context,
            Icons.folder_open_outlined,
            '${AppLocalizations.configDialogSelectedFolder}: ${_compactPath(basePath)}',
          ),
        _buildLocationHelper(
          context,
          Icons.storage_outlined,
          _availableBytes != null
              ? '${AppLocalizations.configDialogFreeSpace}: ${_formatBytes(_availableBytes!)}'
              : AppLocalizations.configDialogFreeSpaceUnknown,
        ),
        if (estimatedBytes != null)
          _buildLocationHelper(
            context,
            Icons.download_outlined,
            '${AppLocalizations.configDialogEstimatedSize}: ${_formatBytes(estimatedBytes)}',
          ),
      ],
    );
  }

  Widget _buildPathField(BuildContext context, String path) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface2(context).withValues(alpha: 0.55),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 20,
            color: AppColors.metaText(context),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Tooltip(
              message: path,
              waitDuration: const Duration(milliseconds: 450),
              child: Text(
                _compactPath(path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChangeFolderButton(BuildContext context) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: _pickSaveFolder,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
        child: Text(AppLocalizations.configDialogChangeFolder),
      ),
    );
  }

  Widget _buildLocationHelper(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.metaText(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.metaText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // SECONDARY OPTIONS ROW (Remember / SaveAsDefault / ApplyToAll)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildSecondaryOptionsRow(BuildContext context) {
    final children = <Widget>[
      if (_canShowRemember())
        _buildSecondaryToggle(
          context,
          selected: _rememberForPlatform,
          icon: Icons.history_toggle_off_rounded,
          title: AppLocalizations.qualityDialogRememberChoice(
            widget.platform.displayName,
          ),
          onChanged: (v) => setState(() => _rememberForPlatform = v),
        ),
      if (_canShowSaveAsDefault())
        _buildSecondaryToggle(
          context,
          selected: _saveAsDefault,
          icon: Icons.star_border_rounded,
          title: AppLocalizations.configDialogSaveAsDefault,
          onChanged: (v) => setState(() => _saveAsDefault = v),
        ),
      if (widget.remainingCount != null && widget.remainingCount! > 1)
        _buildSecondaryToggle(
          context,
          selected: _applyToAll,
          icon: Icons.library_add_check_outlined,
          title: AppLocalizations.configDialogApplyToAll(
            widget.remainingCount!,
          ),
          onChanged: (v) => setState(() => _applyToAll = v),
        ),
    ];

    if (children.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest(context),
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 720;
          if (stack) {
            return Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Divider(height: 1, color: AppColors.border(context)),
                ],
              ],
            );
          }
          return Row(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i < children.length - 1)
                  const SizedBox(width: AppSpacing.xs),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildSecondaryToggle(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String title,
    required ValueChanged<bool> onChanged,
  }) {
    final accent = AppColors.accentHighlight;
    final muted = AppColors.metaText(context);
    return Semantics(
      label: title,
      checked: selected,
      enabled: true,
      onTap: () => onChanged(!selected),
      child: ExcludeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(2),
          onTap: () => onChanged(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                // Mission Briefing-style 14×14 hard square checkbox.
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? accent : muted.withValues(alpha: 0.50),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child:
                      selected
                          ? Container(width: 6, height: 6, color: accent)
                          : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(icon, size: 18, color: selected ? accent : muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: selected ? accent : muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // ADVANCED ACCORDION
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildAdvancedAccordion(
    BuildContext context,
    SettingsState settings,
    bool ffmpegAvailable,
  ) {
    final muted = AppColors.metaText(context);
    return Container(
      key: _advancedSectionKey,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border(context)),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          Semantics(
            button: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(2),
              onTap: _toggleAdvancedExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: muted),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.configDialogAdvancedOptions,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            AppLocalizations.configDialogAdvancedSummary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.bodySmall?.copyWith(color: muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _advancedExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTechnicalStreamsSection(context),
                    _buildChapterSection(context),
                    ConfigPreferencesPanel(
                      key: _prefsKey,
                      settings: settings,
                      platform: widget.platform,
                      onChanged: _onPreferencesChanged,
                      videoInfo: widget.videoInfo,
                      ffmpegAvailable: ffmpegAvailable,
                      showSaveAsDefault: false,
                      fileType: _downloadFileTypeFor(_selectedFileType),
                    ),
                  ],
                ),
              ),
            ),
            crossFadeState:
                _advancedExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 220),
          ),
        ],
      ),
    );
  }

  Widget _buildTechnicalStreamsSection(BuildContext context) {
    final qualities = _technicalQualitiesFor(_selectedFileType);
    if (qualities.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(Icons.developer_board_outlined),
        title: Text(AppLocalizations.configDialogTechnicalStreams),
        subtitle: Text(
          AppLocalizations.configDialogTechnicalStreamsSummary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          for (final quality in qualities)
            if (_qualityRequiresPremiumUpgrade(quality))
              _buildPremiumLockedQualityTile(
                context,
                title: quality.qualityText,
                subtitle: _qualitySubtitle(quality),
                dense: true,
              )
            else
              RadioListTile<String>(
                value: quality.encryptedUrl,
                groupValue: _selectedQuality?.encryptedUrl,
                contentPadding: EdgeInsets.zero,
                title: Text(quality.qualityText),
                subtitle:
                    _qualitySubtitle(quality).isNotEmpty
                        ? Text(_qualitySubtitle(quality))
                        : null,
                onChanged: (_) {
                  setState(() {
                    _selectedQuality = quality;
                    _selectedQualityIntent =
                        DownloadQualityIntent.technicalStream;
                    _selectedQualityTarget = null;
                    _rememberForPlatform = false;
                    _saveAsDefault = false;
                  });
                  _refreshFreeSpace();
                },
              ),
        ],
      ),
    );
  }

  Widget _buildPremiumLockedQualityTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    bool dense = false,
  }) {
    final accent = AppColors.accentHighlight;
    final muted = AppColors.metaText(context);
    final parts = <String>[
      if (subtitle.isNotEmpty) subtitle,
      AppLocalizations.premiumPremiumLabel,
    ];
    return ListTile(
      dense: dense,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.lock_outline_rounded, color: accent),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: muted,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        parts.join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: accent),
      ),
      trailing: Icon(Icons.workspace_premium_rounded, color: accent),
      onTap: _promptUpgradeForBestAvailable,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // CHAPTER SECTION (Mission Briefing preserve)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildChapterSection(BuildContext context) {
    final chapters = widget.videoInfo.chapters;
    if (chapters.isEmpty) return const SizedBox.shrink();
    final muted = AppColors.metaText(context);
    final accent = AppColors.accentHighlight;
    // Three explicit visual states (full / partial / empty). Empty and full
    // are both no-filter for download (see [_resolveSelectedChapterRanges]),
    // but UX-wise we want the header toggle to be honest about what the
    // checkbox column shows. The dialog seeds `_selectedChapterIndices` with
    // all indices in `initState` so the implicit-all case never actually
    // reaches the UI — we still defend against it defensively.
    final fullSelected = _selectedChapterIndices.length == chapters.length;

    void onHeaderTap() {
      setState(() {
        if (fullSelected) {
          // Full → empty. Resolves to "no filter" via the resolver, same as
          // full, but the checkbox column now reflects user intent honestly.
          _selectedChapterIndices.clear();
        } else {
          // Empty or partial → fill all.
          _selectedChapterIndices
            ..clear()
            ..addAll(List.generate(chapters.length, (i) => i));
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border(context)),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onHeaderTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.bookmarks_outlined, color: muted, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppLocalizations.configDialogChapters(
                          _selectedChapterIndices.length,
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      fullSelected
                          ? AppLocalizations.commonClear
                          : AppLocalizations.qualityDialogSelectAll,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 1, color: AppColors.border(context)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chapters.length,
                itemBuilder: (context, index) {
                  final chapter = chapters[index];
                  final selected = _selectedChapterIndices.contains(index);
                  return CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    value: selected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedChapterIndices.add(index);
                        } else {
                          _selectedChapterIndices.remove(index);
                        }
                      });
                    },
                    title: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      '${_formatChapterTime(_secondsToDuration(chapter.startTime))} → '
                      '${_formatChapterTime(_secondsToDuration(chapter.endTime))}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolve current chapter selection into a single yt-dlp section.
  ///
  /// Returns `null` when the selection equals the full chapter list (or
  /// is empty) — both cases mean "download everything", and the consumer
  /// pipeline skips emitting `--download-sections` to preserve full-download
  /// behavior bit-for-bit.
  ///
  /// Defensive against non-chronological chapter order: takes min(startTime)
  /// + max(endTime) across selected chapters. Single-range coalescing — any
  /// unselected chapter that falls *between* the first and last selected
  /// chapter is silently included. Proper "skip middle chapter" support
  /// would require multi-pass yt-dlp invocation.
  List<(Duration, Duration)>? _resolveSelectedChapterRanges() {
    final chapters = widget.videoInfo.chapters;
    if (chapters.isEmpty) return null;
    final count = _selectedChapterIndices.length;
    if (count == 0 || count == chapters.length) return null;
    final selected = _selectedChapterIndices.map((i) => chapters[i]).toList();
    final startSec = selected
        .map((c) => c.startTime)
        .reduce((a, b) => a < b ? a : b);
    final endSec = selected
        .map((c) => c.endTime)
        .reduce((a, b) => a > b ? a : b);
    return [(_secondsToDuration(startSec), _secondsToDuration(endSec))];
  }

  Duration _secondsToDuration(double seconds) =>
      Duration(milliseconds: (seconds * 1000).round());

  String _formatChapterTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  // ─────────────────────────────────────────────────────────────────────
  // OPTION COLUMN PRIMITIVES
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildOptionColumn(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppTypography.briefingSection.copyWith(
              color: AppColors.accentHighlight,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSelectableOption(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Widget? trailing,
  }) {
    final accent = AppColors.accentHighlight;
    final muted = AppColors.metaText(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(2),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  selected
                      ? accent.withValues(alpha: 0.08)
                      : AppColors.base(context),
              border: Border.all(
                color: selected ? accent : AppColors.border(context),
                width: selected ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? accent.withValues(alpha: 0.14)
                            : AppColors.surface2(context),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(
                      color:
                          selected
                              ? accent.withValues(alpha: 0.30)
                              : Colors.transparent,
                    ),
                  ),
                  child: Icon(icon, size: 19, color: selected ? accent : muted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? accent : null,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing
                else
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: selected ? accent : AppColors.border(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // FOOTER (SafeUseNote + ABORT + INITIALIZE)
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildFooter(
    BuildContext context,
    bool canDownload,
    List<Quality> selected,
  ) {
    final accent = AppColors.accentHighlight;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.base(context),
        border: Border(
          top: BorderSide(color: accent.withValues(alpha: 0.20), width: 1),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = _buildFooterActions(context, canDownload, selected);
          final note = _buildSafeUseNote(context);
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                note,
                const SizedBox(height: AppSpacing.md),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: note),
              const SizedBox(width: AppSpacing.lg),
              actions,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSafeUseNote(BuildContext context) {
    final muted = AppColors.metaText(context);
    return Row(
      children: [
        Icon(Icons.verified_user_outlined, color: muted, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            AppLocalizations.configDialogSafeUseNote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterActions(
    BuildContext context,
    bool canDownload,
    List<Quality> selected,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildAbortButton(context),
        const SizedBox(width: AppSpacing.smMd),
        _buildInitializeButton(context, canDownload, selected),
      ],
    );
  }

  Widget _buildAbortButton(BuildContext context) {
    final muted = AppColors.metaText(context);
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: muted.withValues(alpha: 0.40), width: 1),
          foregroundColor: muted,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
        ),
        child: Text(
          AppLocalizations.commonCancel,
          style: AppTypography.briefingAction.copyWith(color: muted),
        ),
      ),
    );
  }

  Widget _buildInitializeButton(
    BuildContext context,
    bool canDownload,
    List<Quality> selected,
  ) {
    final gradient = BrandConfig.current.premiumGradient;
    final disabledColor = AppColors.metaText(context).withValues(alpha: 0.20);
    final accent = AppColors.accentHighlight;
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: canDownload ? _onDownload : null,
          borderRadius: BorderRadius.circular(2),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              gradient: canDownload ? gradient : null,
              color: canDownload ? null : disabledColor,
              borderRadius: BorderRadius.circular(2),
              boxShadow:
                  canDownload
                      ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 2),
                        ),
                      ]
                      : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_outlined,
                  size: 18,
                  color:
                      canDownload
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.40),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  _getDownloadButtonText(selected),
                  style: AppTypography.briefingAction.copyWith(
                    color:
                        canDownload
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.40),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // APPLY-TO-ALL CONFIRMATION
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildApplyToAllConfirm(BuildContext ctx) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    final accent = AppColors.accentHighlight;
    final muted = AppColors.metaText(ctx);
    return Dialog(
      backgroundColor: AppColors.base(ctx),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(
          color: accent.withValues(alpha: isDark ? 0.30 : 0.20),
          width: 1,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    color: accent,
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                  ),
                  Expanded(
                    child: Text(
                      AppLocalizations.configDialogApplyToAllConfirmTitle,
                      style: AppTypography.briefingSection.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.smMd),
              Text(
                AppLocalizations.configDialogApplyToAllConfirmBody(
                  widget.remainingCount!,
                ),
                style: Theme.of(
                  ctx,
                ).textTheme.bodyMedium?.copyWith(color: muted, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: muted.withValues(alpha: 0.40),
                        width: 1,
                      ),
                      foregroundColor: muted,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    child: Text(AppLocalizations.commonCancel),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.all(Radius.circular(2)),
                      ),
                    ),
                    child: Text(
                      AppLocalizations.configDialogApplyToAllConfirmAction,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // FILE TYPE HELPERS
  // ─────────────────────────────────────────────────────────────────────

  _DialogFileType _defaultFileType() {
    if ((widget.videoInfo.isCarousel ||
            widget.videoInfo.downloadMethod == 'gallerydl') &&
        _qualitiesFor(_DialogFileType.image).isNotEmpty) {
      return _DialogFileType.image;
    }
    final preferred = _dialogFileTypeFor(
      ref.read(settingsProvider).defaultDownloadFileType,
    );
    if (_qualitiesFor(preferred).isNotEmpty) return preferred;
    if (_qualitiesFor(_DialogFileType.video).isNotEmpty) {
      return _DialogFileType.video;
    }
    if (_qualitiesFor(_DialogFileType.audio).isNotEmpty) {
      return _DialogFileType.audio;
    }
    if (_qualitiesFor(_DialogFileType.image).isNotEmpty) {
      return _DialogFileType.image;
    }
    return _DialogFileType.subtitle;
  }

  List<_DialogFileType> _availableFileTypes() {
    return [
      if (_qualitiesFor(_DialogFileType.video).isNotEmpty)
        _DialogFileType.video,
      if (_qualitiesFor(_DialogFileType.audio).isNotEmpty)
        _DialogFileType.audio,
      if (_qualitiesFor(_DialogFileType.image).isNotEmpty)
        _DialogFileType.image,
      if (_qualitiesFor(_DialogFileType.subtitle).isNotEmpty)
        _DialogFileType.subtitle,
    ];
  }

  List<Quality> _qualitiesFor(_DialogFileType type) {
    switch (type) {
      case _DialogFileType.video:
        return widget.videoInfo.availableQualities
            .where((q) => q.mediaType == MediaType.video)
            .toList();
      case _DialogFileType.audio:
        return widget.videoInfo.availableQualities
            .where((q) => q.mediaType == MediaType.audio)
            .toList();
      case _DialogFileType.image:
        return widget.videoInfo.availableQualities
            .where((q) => q.mediaType == MediaType.image)
            .toList();
      case _DialogFileType.subtitle:
        return widget.videoInfo.availableQualities
            .where((q) => q.mediaType == MediaType.subtitle)
            .toList();
    }
  }

  List<Quality> _primaryQualitiesFor(_DialogFileType type) {
    final primary =
        _qualitiesFor(
          type,
        ).where((quality) => !_isTechnicalQuality(quality)).toList();
    return primary.isNotEmpty ? primary : _qualitiesFor(type);
  }

  List<Quality> _technicalQualitiesFor(_DialogFileType type) {
    return _qualitiesFor(type).where(_isTechnicalQuality).toList();
  }

  bool _isTechnicalQuality(Quality quality) {
    final text = quality.qualityText.toLowerCase();
    return quality.isVideoOnly ||
        quality.isAudioOnly ||
        quality.encryptedUrl.startsWith('ytdlp:raw:') ||
        quality.encryptedUrl.contains('split_chapters') ||
        text.startsWith('video only') ||
        text.startsWith('audio stream');
  }

  bool _qualityRequiresPremiumUpgrade(Quality quality) {
    if (quality.mediaType != MediaType.video) return false;
    if (ref.read(isPremiumProvider)) return false;
    return QualityResolutionParser.isAboveFreeLimit(quality) ||
        _isGenericBestVideoQuality(quality);
  }

  bool _isGenericBestVideoQuality(Quality quality) {
    return quality.mediaType == MediaType.video &&
        quality.encryptedUrl == 'ytdlp:best:mp4';
  }

  DownloadFileType _downloadFileTypeFor(_DialogFileType type) {
    switch (type) {
      case _DialogFileType.video:
        return DownloadFileType.video;
      case _DialogFileType.audio:
        return DownloadFileType.audio;
      case _DialogFileType.image:
        return DownloadFileType.image;
      case _DialogFileType.subtitle:
        return DownloadFileType.subtitle;
    }
  }

  _DialogFileType _dialogFileTypeFor(DownloadFileType type) {
    switch (type) {
      case DownloadFileType.video:
        return _DialogFileType.video;
      case DownloadFileType.audio:
        return _DialogFileType.audio;
      case DownloadFileType.image:
        return _DialogFileType.image;
      case DownloadFileType.subtitle:
        return _DialogFileType.subtitle;
    }
  }

  void _selectFileType(_DialogFileType type) {
    setState(() {
      _selectedFileType = type;
      _selectedQualityIntent = DownloadQualityIntent.recommended;
      _selectedQualityTarget = null;
      _selectedQuality = _recommendedQualityFor(type);
      if (type == _DialogFileType.audio && _selectedQuality != null) {
        _selectedQualityIntent = DownloadQualityIntent.specific;
        _selectedQualityTarget = _targetForQuality(_selectedQuality!);
      }
    });
    _refreshFreeSpace();
  }

  // ─────────────────────────────────────────────────────────────────────
  // QUALITY INTENT RESOLUTION
  // ─────────────────────────────────────────────────────────────────────

  Quality? _qualityForIntent(
    _DialogFileType type,
    DownloadQualityIntent intent,
    PortableQualityTarget? target,
  ) {
    switch (intent) {
      case DownloadQualityIntent.recommended:
        return _recommendedQualityFor(type);
      case DownloadQualityIntent.bestAvailable:
        return type == _DialogFileType.video
            ? _bestAvailableVideoQuality()
            : _recommendedQualityFor(type);
      case DownloadQualityIntent.specific:
        return _qualityForTarget(type, target);
      case DownloadQualityIntent.technicalStream:
        return _qualityForTarget(type, target);
    }
  }

  Quality? _qualityForTarget(
    _DialogFileType type,
    PortableQualityTarget? target,
  ) {
    if (target == null) return null;
    if (target.fileType != _downloadFileTypeFor(type)) return null;
    final qualities = _qualitiesFor(type);
    if (qualities.isEmpty) return null;
    switch (target.fileType) {
      case DownloadFileType.video:
        final targetHeight = target.targetHeight;
        if (targetHeight == null) return null;
        return qualities.cast<Quality?>().firstWhere(
          (q) =>
              q != null &&
              QualityResolutionParser.heightForQuality(q) == targetHeight,
          orElse: () => null,
        );
      case DownloadFileType.audio:
        return _audioOutputQualityFor(
          target.outputFormat,
          bitrateKbps: target.targetBitrateKbps,
        );
      case DownloadFileType.subtitle:
        return qualities.cast<Quality?>().firstWhere(
          (q) =>
              q != null &&
              target.languageCode != null &&
              q.qualityText.contains('(${target.languageCode})'),
          orElse: () => null,
        );
      case DownloadFileType.image:
        return qualities.cast<Quality?>().firstWhere(
          (q) =>
              q != null &&
              target.imageSelectionMode == ImageSelectionMode.all &&
              q.encryptedUrl.startsWith('gallerydl:all:'),
          orElse: () => null,
        );
    }
  }

  PortableQualityTarget? _targetForQuality(Quality quality) {
    switch (quality.mediaType) {
      case MediaType.video:
        final height = QualityResolutionParser.heightForQuality(quality);
        if (height == null) return null;
        return PortableQualityTarget.video(
          targetHeight: height,
          targetFpsCap: quality.fps?.round(),
        );
      case MediaType.audio:
        return PortableQualityTarget.audio(
          outputFormat: _audioFormatForQuality(quality),
          targetBitrateKbps: _audioBitrateForQuality(quality),
        );
      case MediaType.subtitle:
        return PortableQualityTarget.subtitle(
          languageCode: _subtitleLanguageCodeForQuality(quality),
          subtitleFormat: _subtitlesFormat,
          isAutoGenerated: quality.qualityText.toLowerCase().contains('auto'),
        );
      case MediaType.image:
        return const PortableQualityTarget.image();
    }
  }

  String _audioFormatForQuality(Quality quality) {
    final parts = quality.encryptedUrl.toLowerCase().split(':');
    if (parts.length >= 3 && parts[0] == 'ytdlp' && parts[1] == 'audio') {
      return _normalizeAudioOutputFormat(parts[2]) ?? 'mp3';
    }
    final haystack =
        '${quality.qualityText} ${quality.encryptedUrl}'.toLowerCase();
    for (final fmt in const ['mp3', 'm4a', 'aac', 'opus', 'wav', 'flac']) {
      if (haystack.contains(fmt)) return _normalizeAudioOutputFormat(fmt)!;
    }
    return 'mp3';
  }

  String? _normalizeAudioOutputFormat(String? format) {
    final normalized = format?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'aac') return 'm4a';
    return normalized;
  }

  String _audioOutputFormatLabel(String format) {
    switch (_normalizeAudioOutputFormat(format)) {
      case 'm4a':
        return 'AAC';
      case 'mp3':
        return 'MP3';
      case 'opus':
        return 'Opus';
      case 'wav':
        return 'WAV';
      case 'flac':
        return 'FLAC';
      default:
        return format.toUpperCase();
    }
  }

  bool _isLosslessAudioFormat(String? format) {
    switch (_normalizeAudioOutputFormat(format)) {
      case 'wav':
      case 'flac':
        return true;
      default:
        return false;
    }
  }

  List<Quality> _audioQualitiesForFormat(String? format) {
    final normalized = _normalizeAudioOutputFormat(format);
    if (normalized == null) return const [];
    if (!_availableAudioOutputFormats().contains(normalized)) return const [];
    if (_isLosslessAudioFormat(normalized)) {
      return [
        _audioOutputQualityFor(normalized, bitrateKbps: null),
      ].whereType<Quality>().toList(growable: false);
    }
    return [
      for (final bitrate in _audioBitrateChoicesKbps)
        _audioOutputQualityFor(normalized, bitrateKbps: bitrate),
    ].whereType<Quality>().toList(growable: false);
  }

  List<String> _availableAudioOutputFormats() {
    final formats = <String>{};
    for (final quality in _primaryQualitiesFor(_DialogFileType.audio)) {
      final parts = quality.encryptedUrl.toLowerCase().split(':');
      if (parts.length >= 3 && parts[0] == 'ytdlp' && parts[1] == 'audio') {
        final normalized = _normalizeAudioOutputFormat(parts[2]);
        if (normalized != null) formats.add(normalized);
      }
    }
    if (formats.isEmpty &&
        _primaryQualitiesFor(_DialogFileType.audio).isNotEmpty) {
      formats.addAll(const ['mp3', 'm4a', 'opus', 'wav']);
    }
    const preferredOrder = ['mp3', 'm4a', 'opus', 'wav', 'flac'];
    final result = formats.toList();
    result.sort((a, b) {
      final ai = preferredOrder.indexOf(a);
      final bi = preferredOrder.indexOf(b);
      if (ai == -1 && bi == -1) return a.compareTo(b);
      if (ai == -1) return 1;
      if (bi == -1) return -1;
      return ai.compareTo(bi);
    });
    return result;
  }

  String? _selectedAudioOutputFormat() {
    final targetFormat = _normalizeAudioOutputFormat(
      _selectedQualityTarget?.outputFormat,
    );
    if (_selectedFileType == _DialogFileType.audio && targetFormat != null) {
      return targetFormat;
    }
    final quality = _selectedQuality;
    if (_selectedFileType == _DialogFileType.audio &&
        quality != null &&
        quality.mediaType == MediaType.audio) {
      return _audioFormatForQuality(quality);
    }
    return null;
  }

  String _audioFormatSubtitle(String format) {
    switch (_normalizeAudioOutputFormat(format)) {
      case 'mp3':
        return AppLocalizations.homePresetFormatMp3Desc;
      case 'm4a':
        return AppLocalizations.homePresetFormatM4aDesc;
      case 'flac':
        return AppLocalizations.homePresetFormatFlacDesc;
      case 'opus':
        return 'Modern codec with strong quality at smaller sizes';
      case 'wav':
        return 'Uncompressed audio, large file';
      default:
        return AppLocalizations.configDialogAudioHint;
    }
  }

  String _audioBitrateSubtitle(int bitrateKbps) {
    if (bitrateKbps >= 320) {
      return AppLocalizations.configDialogAudioBitrateHighest;
    }
    if (bitrateKbps >= 256) {
      return AppLocalizations.configDialogAudioBitrateHigh;
    }
    if (bitrateKbps >= 192) {
      return AppLocalizations.configDialogAudioBitrateBalanced;
    }
    if (bitrateKbps >= 128) {
      return AppLocalizations.configDialogAudioBitrateSmaller;
    }
    return AppLocalizations.configDialogAudioBitrateLowest;
  }

  Quality? _audioOutputQualityFor(String? format, {int? bitrateKbps}) {
    final normalized = _normalizeAudioOutputFormat(format);
    if (normalized == null) return null;
    if (_isLosslessAudioFormat(normalized)) {
      return Quality(
        qualityText: AppLocalizations.configDialogAudioQualityLossless(
          _audioOutputFormatLabel(normalized),
        ),
        size: AppLocalizations.configDialogAudioSizeLossless,
        encryptedUrl: 'ytdlp:audio:$normalized',
        mediaType: MediaType.audio,
        isAudioOnly: true,
      );
    }
    final bitrate = bitrateKbps ?? _selectedAudioBitrateKbps;
    return Quality(
      qualityText: AppLocalizations.configDialogAudioQualityBitrate(
        _audioOutputFormatLabel(normalized),
        bitrate,
      ),
      size: _audioBitrateSubtitle(bitrate),
      encryptedUrl: 'ytdlp:audio:$normalized',
      mediaType: MediaType.audio,
      isAudioOnly: true,
      tbr: bitrate.toDouble(),
    );
  }

  void _selectAudioOutputFormat(String format) {
    final normalized = _normalizeAudioOutputFormat(format);
    if (normalized == null) return;
    final quality = _audioOutputQualityFor(
      normalized,
      bitrateKbps: _selectedAudioBitrateKbps,
    );
    if (quality == null) return;

    setState(() {
      _selectedFileType = _DialogFileType.audio;
      _selectedQuality = quality;
      _selectedQualityIntent = DownloadQualityIntent.specific;
      _selectedQualityTarget = PortableQualityTarget.audio(
        outputFormat: normalized,
        targetBitrateKbps:
            _isLosslessAudioFormat(normalized)
                ? null
                : _selectedAudioBitrateKbps,
      );
    });
    _refreshFreeSpace();
  }

  int? _audioBitrateForQuality(Quality quality) {
    final match = RegExp(
      r'(\d+)\s*k(?:bps|b/s)?',
      caseSensitive: false,
    ).firstMatch(quality.qualityText);
    return match != null ? int.tryParse(match.group(1)!) : quality.tbr?.round();
  }

  String _subtitleLanguageCodeForQuality(Quality quality) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(quality.qualityText);
    return match?.group(1) ?? _subtitlesLanguages.firstOrNull ?? 'en';
  }

  Quality? _recommendedQualityFor(_DialogFileType type) {
    final qualities = _qualitiesFor(type);
    if (qualities.isEmpty) return null;
    switch (type) {
      case _DialogFileType.video:
        // Both helpers return null for free users when nothing fits the
        // 1080p cap — the final qualities.first fallback could be 4K, so
        // we suppress it for free tier and let the UI surface "Best
        // available (Premium)" + Choose quality picker instead.
        final isPremium = ref.read(isPremiumProvider);
        final recommended = _recommendedVideoQuality();
        if (recommended != null) return recommended;
        final bestAvailable = _bestAvailableVideoQuality();
        if (bestAvailable != null &&
            !_qualityRequiresPremiumUpgrade(bestAvailable)) {
          return bestAvailable;
        }
        return isPremium ? qualities.first : null;
      case _DialogFileType.audio:
        final formats = _availableAudioOutputFormats();
        final format =
            _selectedAudioOutputFormat() ??
            (formats.isEmpty ? null : formats.first);
        return _audioOutputQualityFor(
          format,
          bitrateKbps: _selectedAudioBitrateKbps,
        );
      case _DialogFileType.image:
        return qualities.firstWhere(
          (q) => q.encryptedUrl.startsWith('gallerydl:all:'),
          orElse: () => qualities.first,
        );
      case _DialogFileType.subtitle:
        return qualities.first;
    }
  }

  Quality? _recommendedVideoQuality() {
    final qualities =
        _primaryQualitiesFor(
          _DialogFileType.video,
        ).where((q) => q.encryptedUrl != 'ytdlp:best:mp4').toList();
    if (qualities.isEmpty) return null;
    final isPremium = ref.read(isPremiumProvider);
    final userMax = _maxResolution;
    // Free-tier hard cap at 1080p regardless of user setting.
    final ceiling =
        isPremium
            ? (userMax == 0 ? 1080 : userMax.clamp(0, 1080))
            : (userMax == 0
                ? PremiumLimits.freeMaxResolutionP
                : userMax.clamp(0, PremiumLimits.freeMaxResolutionP));
    final withHeights =
        qualities
            .map(
              (q) => (
                quality: q,
                height: QualityResolutionParser.heightForQuality(q),
              ),
            )
            .where((e) => e.height != null)
            .toList()
          ..sort((a, b) => b.height!.compareTo(a.height!));
    if (withHeights.isEmpty) {
      // No height metadata at all — preselect the first listed quality only
      // for premium so we don't strand a free user on something the start
      // flow would just block. The premium block runs in _onDownload.
      return isPremium ? qualities.first : null;
    }
    for (final entry in withHeights) {
      if (entry.height! <= ceiling) return entry.quality;
    }
    // No quality fits inside the ceiling. Premium users see the lowest
    // available height — still legal; free users see null so the dialog
    // shows the "Best available (Premium required)" row + Choose quality
    // picker instead of pre-selecting an out-of-tier quality that the
    // download flow will refuse.
    return isPremium ? withHeights.last.quality : null;
  }

  Quality? _bestAvailableVideoQuality() {
    final qualities = _primaryQualitiesFor(_DialogFileType.video);
    if (qualities.isEmpty) return null;
    final isPremium = ref.read(isPremiumProvider);
    final best = qualities.cast<Quality?>().firstWhere(
      (q) => q?.encryptedUrl == 'ytdlp:best:mp4',
      orElse: () => null,
    );
    if (best != null) return best;
    final withHeights =
        qualities
            .map(
              (q) => (
                quality: q,
                height: QualityResolutionParser.heightForQuality(q),
              ),
            )
            .where((e) => e.height != null)
            .toList()
          ..sort((a, b) => b.height!.compareTo(a.height!));
    if (withHeights.isEmpty) return qualities.first;
    // Free tier — cap at free limit so the dialog never preselects a quality
    // the user can't actually download. Returns null if EVERY quality
    // exceeds the cap (rare: e.g. video only has 1440p + 2160p) so the
    // intent row can render in "Premium required" mode instead of stranding
    // the user on a quality that always triggers the upgrade prompt.
    if (!isPremium) {
      for (final entry in withHeights) {
        if (entry.height! <= PremiumLimits.freeMaxResolutionP) {
          return entry.quality;
        }
      }
      return null;
    }
    return withHeights.first.quality;
  }

  /// Top-most quality available — used to surface the "Best available
  /// (Premium required)" row in the dialog when the free-tier user has
  /// nothing legal to select. Separated from [_bestAvailableVideoQuality]
  /// so the legal path stays clean.
  Quality? _highestVideoQualityIgnoringPremium() {
    final qualities = _primaryQualitiesFor(_DialogFileType.video);
    if (qualities.isEmpty) return null;
    final best = qualities.cast<Quality?>().firstWhere(
      (q) => q?.encryptedUrl == 'ytdlp:best:mp4',
      orElse: () => null,
    );
    if (best != null) return best;
    final withHeights =
        qualities
            .map(
              (q) => (
                quality: q,
                height: QualityResolutionParser.heightForQuality(q),
              ),
            )
            .where((e) => e.height != null)
            .toList()
          ..sort((a, b) => b.height!.compareTo(a.height!));
    if (withHeights.isEmpty) return qualities.first;
    return withHeights.first.quality;
  }

  /// Tap handler for the "Best available (Premium required)" row — fires
  /// the upgrade prompt instead of selecting an out-of-tier quality.
  Future<void> _promptUpgradeForBestAvailable() async {
    await UpgradePromptDialog.showAndNavigate(
      context,
      ref,
      feature: PremiumFeature.highQuality4K,
    );
  }

  List<_QualityIntentRow> _qualityIntentsFor(_DialogFileType type) {
    final qualities = _primaryQualitiesFor(type);
    if (qualities.isEmpty) return const [];

    if (type == _DialogFileType.video) {
      final recommended = _recommendedQualityFor(type);
      final bestAvailable = _bestAvailableVideoQuality();
      final usedUrls = <String>{};
      final intents = <_QualityIntentRow>[];
      if (recommended != null) {
        intents.add(
          _QualityIntentRow(
            label: AppLocalizations.configDialogRecommended,
            subtitle: _qualityChoiceSubtitle(recommended),
            icon: Icons.star_rounded,
            intent: DownloadQualityIntent.recommended,
            quality: recommended,
          ),
        );
        usedUrls.add(recommended.encryptedUrl);
      }
      if (bestAvailable != null && usedUrls.add(bestAvailable.encryptedUrl)) {
        final bestRequiresUpgrade = _qualityRequiresPremiumUpgrade(
          bestAvailable,
        );
        intents.add(
          _QualityIntentRow(
            label: AppLocalizations.configDialogBestAvailable,
            subtitle: _qualityChoiceSubtitle(bestAvailable),
            icon:
                bestRequiresUpgrade
                    ? Icons.workspace_premium_outlined
                    : Icons.vertical_align_top_rounded,
            intent: DownloadQualityIntent.bestAvailable,
            quality: bestRequiresUpgrade ? null : bestAvailable,
            requiresUpgrade: bestRequiresUpgrade,
          ),
        );
      } else if (bestAvailable == null) {
        // Free-tier user with no quality ≤ 1080p (e.g. video only has
        // 1440p + 2160p). Show "Best available" as a Premium-gated row
        // so they understand WHY they can't pick it, instead of either
        // hiding it entirely (looks broken) or selecting a quality the
        // download flow will refuse anyway.
        final highest = _highestVideoQualityIgnoringPremium();
        if (highest != null && !ref.read(isPremiumProvider)) {
          intents.add(
            _QualityIntentRow(
              label: AppLocalizations.configDialogBestAvailable,
              subtitle: _qualityChoiceSubtitle(highest),
              icon: Icons.workspace_premium_outlined,
              intent: DownloadQualityIntent.bestAvailable,
              requiresUpgrade: true,
            ),
          );
        }
      }
      intents.add(
        _QualityIntentRow(
          label: AppLocalizations.configDialogChooseQuality,
          subtitle: AppLocalizations.configDialogChooseQualityHint,
          icon: Icons.tune,
          intent: DownloadQualityIntent.specific,
          opensMore: true,
        ),
      );
      return intents;
    }

    if (type == _DialogFileType.image) {
      final recommended = _recommendedQualityFor(type);
      final visible = [
        if (recommended != null) recommended,
        ...qualities.where((q) => q != recommended).take(3),
      ];
      return [
        for (var i = 0; i < visible.length; i++)
          _QualityIntentRow(
            label:
                i == 0
                    ? AppLocalizations.configDialogRecommended
                    : visible[i].qualityText,
            subtitle: _qualitySubtitle(visible[i]),
            icon: Icons.image_outlined,
            intent:
                i == 0
                    ? DownloadQualityIntent.recommended
                    : DownloadQualityIntent.specific,
            target: i == 0 ? null : _targetForQuality(visible[i]),
            quality: visible[i],
          ),
        if (qualities.length > 4)
          _QualityIntentRow(
            label: AppLocalizations.configDialogMore,
            icon: Icons.tune,
            intent: DownloadQualityIntent.specific,
            opensMore: true,
          ),
      ];
    }

    if (type == _DialogFileType.audio) {
      final formats = _availableAudioOutputFormats();
      final currentFormat =
          _selectedAudioOutputFormat() ??
          (formats.isEmpty ? null : formats.first);
      if (currentFormat == null) return const [];
      if (_isLosslessAudioFormat(currentFormat)) {
        return [
          _QualityIntentRow(
            label: AppLocalizations.configDialogAudioLosslessLabel,
            subtitle: AppLocalizations.configDialogAudioLosslessSubtitle,
            icon: Icons.graphic_eq_rounded,
            intent: DownloadQualityIntent.specific,
            target: PortableQualityTarget.audio(outputFormat: currentFormat),
            quality: _audioOutputQualityFor(currentFormat, bitrateKbps: null),
          ),
        ];
      }
      return [
        for (final bitrate in _audioBitrateChoicesKbps)
          _QualityIntentRow(
            label: '$bitrate kbps',
            subtitle: _audioBitrateSubtitle(bitrate),
            icon: Icons.graphic_eq_rounded,
            intent: DownloadQualityIntent.specific,
            target: PortableQualityTarget.audio(
              outputFormat: currentFormat,
              targetBitrateKbps: bitrate,
            ),
            quality: _audioOutputQualityFor(
              currentFormat,
              bitrateKbps: bitrate,
            ),
          ),
      ];
    }

    // Subtitles
    final visible = qualities.take(3).toList();
    return [
      for (final quality in visible)
        _QualityIntentRow(
          label: quality.qualityText,
          subtitle: quality.size,
          icon: Icons.closed_caption_outlined,
          intent: DownloadQualityIntent.specific,
          target: _targetForQuality(quality),
          quality: quality,
        ),
      if (qualities.length > 3)
        _QualityIntentRow(
          label: AppLocalizations.configDialogMore,
          icon: Icons.tune,
          intent: DownloadQualityIntent.specific,
          opensMore: true,
        ),
    ];
  }

  Future<void> _showMoreQualities() async {
    final isAudioPicker = _selectedFileType == _DialogFileType.audio;
    final audioFormats =
        isAudioPicker ? _availableAudioOutputFormats() : const <String>[];
    final audioFormat =
        isAudioPicker
            ? (_selectedAudioOutputFormat() ??
                (audioFormats.isEmpty ? null : audioFormats.first))
            : null;
    final qualities =
        isAudioPicker
            ? _audioQualitiesForFormat(audioFormat)
            : _primaryQualitiesFor(_selectedFileType);
    if (qualities.isEmpty) return;
    var selectedUrl = _selectedQuality?.encryptedUrl;
    if (!isAudioPicker && selectedUrl != null) {
      final selectedQuality = qualities.cast<Quality?>().firstWhere(
        (quality) => quality?.encryptedUrl == selectedUrl,
        orElse: () => null,
      );
      if (selectedQuality != null &&
          _qualityRequiresPremiumUpgrade(selectedQuality)) {
        selectedUrl = null;
      }
    }
    final title =
        isAudioPicker && audioFormat != null
            ? '${AppLocalizations.configDialogChooseQuality} · ${audioFormat.toUpperCase()}'
            : AppLocalizations.configDialogChooseQuality;

    final selected = await showDialog<Quality>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(title),
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
              content: SizedBox(
                width: 520,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 460),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: qualities.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final quality = qualities[index];
                      final locked =
                          !isAudioPicker &&
                          _qualityRequiresPremiumUpgrade(quality);
                      if (locked) {
                        return _buildPremiumLockedQualityTile(
                          context,
                          title: quality.qualityText,
                          subtitle: _qualitySubtitle(quality),
                        );
                      }
                      return RadioListTile<String>(
                        value: quality.encryptedUrl,
                        groupValue: selectedUrl,
                        controlAffinity: ListTileControlAffinity.leading,
                        secondary: Icon(_fileTypeIcon(_selectedFileType)),
                        title: Text(
                          isAudioPicker
                              ? _audioQualityTitle(quality)
                              : quality.qualityText,
                        ),
                        subtitle:
                            (isAudioPicker
                                        ? _audioQualitySubtitle(quality)
                                        : _qualitySubtitle(quality))
                                    .isNotEmpty
                                ? Text(
                                  isAudioPicker
                                      ? _audioQualitySubtitle(quality)
                                      : _qualitySubtitle(quality),
                                )
                                : null,
                        onChanged: (v) => setDialogState(() => selectedUrl = v),
                      );
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.commonCancel),
                ),
                FilledButton(
                  onPressed:
                      selectedUrl == null
                          ? null
                          : () => Navigator.pop(
                            context,
                            qualities.firstWhere(
                              (q) => q.encryptedUrl == selectedUrl,
                            ),
                          ),
                  child: Text(AppLocalizations.commonOk),
                ),
              ],
            );
          },
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedQuality = selected;
        _selectedQualityIntent = DownloadQualityIntent.specific;
        _selectedQualityTarget = _targetForQuality(selected);
      });
      _refreshFreeSpace();
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // SAVE LOCATION HELPERS
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _pickSaveFolder() async {
    final currentPath = _baseSavePath();
    final initialDirectory = await _existingDirectoryOrNull(currentPath);
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: AppLocalizations.configDialogDownloadLocation,
      initialDirectory: initialDirectory,
    );
    if (path == null) return;

    final canWrite = await FileUtils.canWriteToDirectory(path);
    if (!canWrite) {
      if (!mounted) return;
      AppSnackBar.error(
        context,
        message: AppLocalizations.downloadPathPermissionError,
      );
      return;
    }

    setState(() => _savePathOverride = path);
    _refreshFreeSpace();
  }

  Future<void> _refreshFreeSpace() async {
    final path = _baseSavePath();
    if (path.isEmpty) {
      if (mounted) setState(() => _availableBytes = null);
      return;
    }
    final bytes = await FileUtils.getAvailableBytes(path);
    if (!mounted) return;
    if (_baseSavePath() != path) return;
    setState(() => _availableBytes = bytes);
  }

  String _baseSavePath() => _savePathOverride ?? ref.read(downloadPathProvider);

  String _resolvedOutputPath(String basePath) {
    final quality = _selectedQuality;
    if (basePath.isEmpty || quality == null) return basePath;
    final pathService = ref.read(downloadPathSuggestionServiceProvider);
    final subdirectory = pathService.suggestSubdirectory(
      widget.platform,
      quality.mediaType,
    );
    return pathService.buildOutputPath(basePath, subdirectory);
  }

  int? _selectedEstimatedBytes() {
    final selected = _getSelectedQualities();
    if (selected.isEmpty || selected.any((q) => q.filesizeBytes == null)) {
      return null;
    }
    return selected.fold<int>(0, (sum, q) => sum + q.filesizeBytes!);
  }

  Future<String?> _existingDirectoryOrNull(String path) async {
    if (path.isEmpty) return null;
    try {
      return await Directory(path).exists() ? path : null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // FORMATTING / LABELS
  // ─────────────────────────────────────────────────────────────────────

  void _toggleAdvancedExpanded() {
    final willExpand = !_advancedExpanded;
    setState(() => _advancedExpanded = willExpand);
    if (!willExpand) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _advancedSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  String _compactPath(String path) {
    if (path.length <= 34) return path;
    final start = path.substring(0, 14);
    final end = path.substring(path.length - 16);
    return '$start...$end';
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${duration.inMinutes}:$seconds';
  }

  String _qualityResolutionLabel(Quality quality) {
    final height = QualityResolutionParser.heightForQuality(quality);
    if (height == null) return quality.qualityText;
    if (height >= 4320) return '8K';
    if (height >= 2160) return '4K';
    if (height >= 1440) return '1440p';
    return '${height}p';
  }

  String _qualityChoiceSubtitle(Quality quality) {
    final resolution = _qualityResolutionLabel(quality);
    final detail = _qualitySubtitle(quality);
    if (detail.isEmpty || detail == resolution) return resolution;
    return '$resolution · $detail';
  }

  String _audioQualityTitle(Quality quality) {
    final bitrate = _audioBitrateForQuality(quality);
    if (bitrate != null) return '$bitrate kbps';
    final label = _audioLabel(quality);
    final format = _audioFormatForQuality(quality).toUpperCase();
    if (label.toLowerCase().contains(format.toLowerCase())) {
      return AppLocalizations.homePresetQualityDefault;
    }
    return label.isEmpty ? AppLocalizations.homePresetQualityDefault : label;
  }

  String _audioQualitySubtitle(Quality quality) {
    final parts = <String>[
      _audioOutputFormatLabel(_audioFormatForQuality(quality)),
    ];
    if (quality.size.isNotEmpty &&
        quality.size != 'Highest quality available') {
      parts.add(quality.size);
    }
    return parts.join(' · ');
  }

  String _qualitySubtitle(Quality quality) {
    if (quality.size.isNotEmpty &&
        quality.size != 'Highest quality available') {
      return quality.size;
    }
    if (quality.mediaType == MediaType.video) return 'MP4';
    if (quality.mediaType == MediaType.audio) return 'MP3';
    if (quality.mediaType == MediaType.image) return 'Original';
    if (quality.mediaType == MediaType.subtitle) return 'SRT';
    return '';
  }

  String _audioLabel(Quality quality) {
    final text = quality.qualityText;
    // Audio qualityText follows pattern "<localized Audio> - <format-info>"
    // across all 15 locales (en "Audio -", vi "Âm thanh -", ja "オーディオ -", ...).
    // Strip everything up to and including the first " - " separator.
    if (quality.mediaType == MediaType.audio) {
      final dashIdx = text.indexOf(' - ');
      if (dashIdx > 0) {
        return text.substring(dashIdx + 3);
      }
    }
    if (text.startsWith('Audio Stream - ')) {
      return text.replaceFirst('Audio Stream - ', '');
    }
    return text;
  }

  String _fileTypeLabel(_DialogFileType type) {
    switch (type) {
      case _DialogFileType.video:
        return AppLocalizations.configDialogVideo;
      case _DialogFileType.audio:
        return AppLocalizations.configDialogAudio;
      case _DialogFileType.image:
        return AppLocalizations.configDialogImage;
      case _DialogFileType.subtitle:
        return AppLocalizations.configDialogSubtitle;
    }
  }

  String _fileTypeHint(_DialogFileType type) {
    switch (type) {
      case _DialogFileType.video:
        return AppLocalizations.configDialogVideoHint;
      case _DialogFileType.audio:
        return AppLocalizations.configDialogAudioHint;
      case _DialogFileType.image:
        return AppLocalizations.configDialogImageHint;
      case _DialogFileType.subtitle:
        return AppLocalizations.configDialogSubtitleHint;
    }
  }

  IconData _fileTypeIcon(_DialogFileType type) {
    switch (type) {
      case _DialogFileType.video:
        return Icons.videocam_rounded;
      case _DialogFileType.audio:
        return Icons.music_note_rounded;
      case _DialogFileType.image:
        return Icons.image_rounded;
      case _DialogFileType.subtitle:
        return Icons.closed_caption_rounded;
    }
  }

  bool _canShowRemember() {
    if (_mode == ContentMode.singleItem) return false;
    if (widget.videoInfo.isCarousel) return false;
    if (_mode == ContentMode.mixedContent) return false;
    if (_selectedQualityIntent == DownloadQualityIntent.technicalStream) {
      return false;
    }
    return true;
  }

  bool _canShowSaveAsDefault() {
    return _selectedQualityIntent != DownloadQualityIntent.technicalStream;
  }

  String _getDownloadButtonText(List<Quality> qualities) {
    if (qualities.isEmpty) return AppLocalizations.qualityDialogSelectQuality;
    if (qualities.length == 1) return AppLocalizations.qualityDialogDownload;
    final images =
        qualities.where((q) => q.mediaType == MediaType.image).length;
    final videos =
        qualities.where((q) => q.mediaType == MediaType.video).length;
    final hasOnlyImages = images == qualities.length;
    final hasOnlyVideos = videos == qualities.length;
    final hasOnlyImagesAndVideos = images + videos == qualities.length;
    if (hasOnlyImagesAndVideos && images > 0 && videos > 0) {
      return AppLocalizations.qualityDialogDownloadMixed(images, videos);
    } else if (hasOnlyImages) {
      return AppLocalizations.qualityDialogDownloadImages(images);
    } else if (hasOnlyVideos) {
      return AppLocalizations.qualityDialogDownloadVideos(videos);
    }
    return AppLocalizations.qualityDialogDownloadItems(qualities.length);
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
