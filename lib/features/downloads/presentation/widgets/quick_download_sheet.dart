import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/binaries/binary_providers.dart';
import '../../../../core/binaries/binary_type.dart';
import '../../../../core/core.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/domain/entities/format_preset_extended.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/presentation/providers/active_preset_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_config.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/quality_resolution_parser.dart';
import 'config_preferences_panel.dart';

/// Compact, YouTube-style download picker — the everyday surface for a paste →
/// download. Shows only the essentials (Video/Audio, a quality list with
/// estimated sizes, a small format selector, and a "remember" toggle). The
/// full [DownloadConfigDialog] with codecs / trimming / subtitles / SponsorBlock
/// stays one tap away behind "Advanced options".
///
/// Returns a [DownloadConfig] — the exact same contract the full dialog
/// produces — so the download flow downstream is unchanged.
class QuickDownloadSheet extends ConsumerStatefulWidget {
  final VideoInfo videoInfo;
  final VideoPlatform platform;

  const QuickDownloadSheet({
    super.key,
    required this.videoInfo,
    required this.platform,
  });

  static Future<DownloadConfig?> show(
    BuildContext context,
    VideoInfo videoInfo,
    VideoPlatform platform,
  ) {
    return showDialog<DownloadConfig>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => QuickDownloadSheet(videoInfo: videoInfo, platform: platform),
    );
  }

  @override
  ConsumerState<QuickDownloadSheet> createState() => _QuickDownloadSheetState();
}

enum _DlMode { video, audio }

/// One selectable video resolution, backed by a concrete [Quality] so the
/// download always maps to a real stream from `availableQualities`.
class _VideoOption {
  final int height;
  final Quality quality;
  const _VideoOption(this.height, this.quality);
  int? get bytes => quality.filesizeBytes;
}

class _QuickDownloadSheetState extends ConsumerState<QuickDownloadSheet> {
  static const List<int> _audioBitrates = [320, 256, 192, 128];
  static const List<String> _audioFormats = ['mp3', 'm4a', 'opus', 'wav', 'flac'];

  late final List<_VideoOption> _videoOptions;
  late final bool _hasVideo;

  late _DlMode _mode;
  int? _height;
  late ContainerFormatPreference _videoFormat;
  int _bitrate = 320;
  String _audioFormat = 'mp3';
  bool _remember = false;
  bool _advancedExpanded = false;
  final _prefsKey = GlobalKey<ConfigPreferencesPanelState>();

  @override
  void initState() {
    super.initState();
    _videoOptions = _buildVideoOptions(widget.videoInfo);
    _hasVideo = _videoOptions.isNotEmpty;

    // Preselect from the active download default (the single source of truth
    // the command-bar popover also edits) so the sheet opens on the user's
    // current preference rather than a cold guess.
    final settings = ref.read(settingsProvider);
    final cur = ref.read(activePresetProvider).currentConfig;

    _videoFormat =
        ContainerFormatPreference.fromExtension(cur.containerFormat) ??
        settings.containerFormatPreference;
    if (cur.audioOnly) {
      final normalized = _normalizeAudioFormat(cur.containerFormat);
      if (_audioFormats.contains(normalized)) _audioFormat = normalized;
    }
    if (cur.audioBitrate != null && _audioBitrates.contains(cur.audioBitrate)) {
      _bitrate = cur.audioBitrate!;
    }

    _mode = (!_hasVideo || cur.audioOnly) ? _DlMode.audio : _DlMode.video;

    if (_hasVideo) {
      final isPremium = ref.read(isPremiumProvider);
      final settingCap =
          cur.maxResolution > 0 ? cur.maxResolution : settings.maxResolution;
      final cap =
          isPremium
              ? (settingCap > 0 ? settingCap : 1 << 30)
              : PremiumLimits.freeMaxResolutionP;
      final within = _videoOptions.where((o) => o.height <= cap);
      _height =
          within.isNotEmpty ? within.first.height : _videoOptions.last.height;
    }
  }

  // ── Data helpers ──────────────────────────────────────────────────────

  static List<_VideoOption> _buildVideoOptions(VideoInfo info) {
    final byHeight = <int, Quality>{};
    for (final q in info.availableQualities) {
      if (q.mediaType != MediaType.video) continue;
      final h = QualityResolutionParser.heightForQuality(q);
      if (h == null) continue;
      final existing = byHeight[h];
      byHeight[h] = existing == null ? q : _preferQuality(existing, q);
    }
    final list =
        byHeight.entries.map((e) => _VideoOption(e.key, e.value)).toList()
          ..sort((a, b) => b.height.compareTo(a.height));
    return list;
  }

  /// Prefer a muxed (already has audio) stream over a video-only one; between
  /// two of the same kind, keep the one with a known/larger file size.
  static Quality _preferQuality(Quality a, Quality b) {
    if (a.isVideoOnly != b.isVideoOnly) return a.isVideoOnly ? b : a;
    return (b.filesizeBytes ?? 0) > (a.filesizeBytes ?? 0) ? b : a;
  }

  static String _normalizeAudioFormat(String format) {
    final f = format.trim().toLowerCase();
    return f == 'aac' ? 'm4a' : f;
  }

  bool get _isLosslessAudio =>
      _audioFormat == 'wav' || _audioFormat == 'flac';

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double value = bytes.toDouble();
    int unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
  }

  /// Universal, locale-neutral tier tag for a height (4K / 2K / Full HD / HD).
  static String? _tierTag(int height) {
    if (height >= 2160) return '4K';
    if (height >= 1440) return '2K';
    if (height >= 1080) return 'Full HD';
    if (height >= 720) return 'HD';
    return null;
  }

  String _bitrateHint(int kbps) {
    switch (kbps) {
      case 320:
        return AppLocalizations.configDialogAudioBitrateHighest;
      case 256:
        return AppLocalizations.configDialogAudioBitrateHigh;
      case 192:
        return AppLocalizations.configDialogAudioBitrateBalanced;
      case 128:
        return AppLocalizations.configDialogAudioBitrateSmaller;
      default:
        return AppLocalizations.configDialogAudioBitrateLowest;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _onDownload() async {
    final settings = ref.read(settingsProvider);
    final DownloadConfig config;

    // Branch picks the stream / type / target / container; everything else is
    // shared, so we build one DownloadConfig below.
    late final List<Quality> qualities;
    late final DownloadFileType fileType;
    late final PortableQualityTarget target;
    ContainerFormatPreference? containerOverride;

    if (_mode == _DlMode.video) {
      final height = _height;
      if (height == null) return;

      // Free-tier resolution cap with an upgrade nudge (parity with the
      // full dialog's gate).
      final isPremium = ref.read(isPremiumProvider);
      if (!isPremium && height > PremiumLimits.freeMaxResolutionP) {
        await UpgradePromptDialog.showAndNavigate(
          context,
          ref,
          feature: PremiumFeature.highQuality4K,
        );
        return;
      }

      final opt = _videoOptions.firstWhere((o) => o.height == height);
      qualities = [opt.quality];
      fileType = DownloadFileType.video;
      target = PortableQualityTarget.video(
        targetHeight: opt.height,
        targetFpsCap: opt.quality.fps?.round(),
      );
      containerOverride =
          _videoFormat != settings.containerFormatPreference
              ? _videoFormat
              : null;
    } else {
      final normalized = _normalizeAudioFormat(_audioFormat);
      final lossless = normalized == 'wav' || normalized == 'flac';
      final label =
          lossless
              ? '${normalized.toUpperCase()} · '
                  '${AppLocalizations.configDialogAudioLosslessLabel}'
              : '${normalized.toUpperCase()} · $_bitrate kbps';
      qualities = [
        Quality(
          qualityText: label,
          size: '',
          encryptedUrl: 'ytdlp:audio:$normalized',
          mediaType: MediaType.audio,
          isAudioOnly: true,
          tbr: lossless ? null : _bitrate.toDouble(),
        ),
      ];
      fileType = DownloadFileType.audio;
      target = PortableQualityTarget.audio(
        outputFormat: normalized,
        targetBitrateKbps: lossless ? null : _bitrate,
      );
      containerOverride = null;
    }

    // Advanced overrides from the inline panel — each sent only when it
    // genuinely differs from the global setting, so the sheet never
    // duplicates format/quality and only real deltas reach the download.
    final adv = _prefsKey.currentState?.currentState;
    config = DownloadConfig(
      selectedQualities: qualities,
      fileType: fileType,
      qualityIntent: DownloadQualityIntent.specific,
      qualityTarget: target,
      containerFormatOverride: containerOverride,
      videoCodecOverride:
          adv != null && adv.videoCodec != settings.videoCodecPreference
              ? adv.videoCodec
              : null,
      audioCodecOverride:
          adv != null && adv.audioCodec != settings.audioCodecPreference
              ? adv.audioCodec
              : null,
      fpsOverride:
          adv != null && adv.fps != settings.fpsPreference ? adv.fps : null,
      subtitlesEnabled:
          adv != null && adv.subtitlesEnabled != settings.subtitlesEnabled
              ? adv.subtitlesEnabled
              : null,
      subtitlesLanguages:
          adv != null &&
                  !listEquals(
                    adv.subtitlesLanguages,
                    settings.subtitlesLanguages,
                  )
              ? adv.subtitlesLanguages
              : null,
      subtitlesFormat:
          adv != null && adv.subtitlesFormat != settings.subtitlesFormat
              ? adv.subtitlesFormat
              : null,
      includeAutoSubs:
          adv != null && adv.includeAutoSubs != settings.includeAutoSubs
              ? adv.includeAutoSubs
              : null,
      embedThumbnail:
          adv != null && adv.embedThumbnail != settings.embedThumbnail
              ? adv.embedThumbnail
              : null,
      embedMetadata:
          adv != null && adv.embedMetadata != settings.embedMetadata
              ? adv.embedMetadata
              : null,
      embedChapters:
          adv != null && adv.embedChapters != settings.embedChapters
              ? adv.embedChapters
              : null,
      sponsorBlockEnabled:
          adv != null &&
                  adv.sponsorBlockEnabled != settings.sponsorBlockEnabled
              ? adv.sponsorBlockEnabled
              : null,
      sponsorBlockAction:
          adv != null && adv.sponsorBlockAction != settings.sponsorBlockAction
              ? adv.sponsorBlockAction
              : null,
      sponsorBlockCategories:
          adv != null &&
                  !listEquals(
                    adv.sponsorBlockCategories,
                    settings.sponsorBlockCategories,
                  )
              ? adv.sponsorBlockCategories
              : null,
      tiktokRemoveWatermark:
          adv != null &&
                  adv.tiktokRemoveWatermark != settings.tiktokRemoveWatermark
              ? adv.tiktokRemoveWatermark
              : null,
      sectionStartTime: adv?.sectionStartTime,
      sectionEndTime: adv?.sectionEndTime,
    );

    // "Remember this choice" makes it the default: write the selection into the
    // active download config and turn OFF ask-mode, so the next paste
    // auto-downloads (Rule 1.5) instead of re-opening this sheet. This is the
    // single lever that keeps "remember" and the command-bar popover in sync.
    if (_remember) {
      final presetCtrl = ref.read(activePresetProvider.notifier);
      final cur = ref.read(activePresetProvider).currentConfig;
      final FormatPresetExtended next;
      if (_mode == _DlMode.video) {
        next = cur.copyWith(
          audioOnly: false,
          containerFormat: _videoFormat.name,
          maxResolution: _height ?? cur.maxResolution,
        );
      } else {
        final normalized = _normalizeAudioFormat(_audioFormat);
        final lossless = normalized == 'wav' || normalized == 'flac';
        next = cur.copyWith(
          audioOnly: true,
          containerFormat: normalized,
          audioBitrate: lossless ? null : _bitrate,
        );
      }
      await presetCtrl.updateConfig(next);
      await presetCtrl.setManualMode(false);
    }

    if (!mounted) return;
    Navigator.pop(context, config);
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.homeDarkCardBg : Colors.white;
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : AppColors.border(context);

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
            borderRadius: BorderRadius.circular(BrandConfig.current.cardRadius),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, isDark),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_hasVideo) _buildModeToggle(context, isDark),
                      const SizedBox(height: AppSpacing.sm),
                      ..._buildQualityRows(context, isDark),
                      const SizedBox(height: AppSpacing.xs),
                      _buildFormatRow(context, isDark),
                      _buildRememberRow(context),
                      _buildAdvancedSection(context, isDark),
                    ],
                  ),
                ),
              ),
              _buildFooter(context, isDark),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.qualityDialogTitle,
                  style: AppTypography.appBarTitle.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkLightText : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.videoInfo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.metaText(context),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            visualDensity: VisualDensity.compact,
            tooltip: AppLocalizations.qualityDialogCancel,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.metaText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle(BuildContext context, bool isDark) {
    Widget seg(_DlMode mode, IconData icon, String label) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _mode = mode),
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
                  size: 17,
                  color:
                      selected
                          ? AppColors.darkLightText
                          : AppColors.metaText(context),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.buttonSecondary.copyWith(
                    fontSize: 13.5,
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
          seg(_DlMode.video, Icons.videocam_rounded, AppLocalizations.configDialogVideo),
          seg(_DlMode.audio, Icons.music_note_rounded, AppLocalizations.configDialogAudio),
        ],
      ),
    );
  }

  List<Widget> _buildQualityRows(BuildContext context, bool isDark) {
    if (_mode == _DlMode.video) {
      return [
        for (final opt in _videoOptions)
          _buildOptionRow(
            context,
            isDark: isDark,
            selected: _height == opt.height,
            title: '${opt.height}p',
            tag: _tierTag(opt.height),
            trailing: opt.bytes != null ? _formatBytes(opt.bytes!) : null,
            onTap: () => setState(() => _height = opt.height),
          ),
      ];
    }

    if (_isLosslessAudio) {
      return [
        _buildOptionRow(
          context,
          isDark: isDark,
          selected: true,
          title: AppLocalizations.configDialogAudioLosslessLabel,
          tag: _audioFormat.toUpperCase(),
          trailing: null,
          onTap: () {},
        ),
      ];
    }

    return [
      for (final kbps in _audioBitrates)
        _buildOptionRow(
          context,
          isDark: isDark,
          selected: _bitrate == kbps,
          title: '$kbps kbps',
          tag: _bitrateHint(kbps),
          trailing: null,
          onTap: () => setState(() => _bitrate = kbps),
        ),
    ];
  }

  Widget _buildOptionRow(
    BuildContext context, {
    required bool isDark,
    required bool selected,
    required String title,
    String? tag,
    String? trailing,
    required VoidCallback onTap,
  }) {
    final accent = AppColors.accentHighlight;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smMd,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                selected
                    ? accent.withValues(alpha: isDark ? 0.16 : 0.08)
                    : (isDark
                        ? AppColors.homeDarkAppBg
                        : AppColors.surface2(context)),
            borderRadius: BorderRadius.circular(AppRadius.input),
            border: Border.all(
              color: selected ? accent : AppColors.border(context),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              _radio(selected, accent),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.buttonSecondary.copyWith(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: isDark ? AppColors.darkLightText : null,
                  ),
                ),
              ),
              if (tag != null) ...[
                Text(
                  tag,
                  style: AppTypography.mini.copyWith(
                    color: selected ? accent : AppColors.metaText(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (trailing != null) const SizedBox(width: AppSpacing.smMd),
              ],
              if (trailing != null)
                Text(
                  trailing,
                  style: AppTypography.metadata.copyWith(
                    color: AppColors.metaText(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _radio(bool selected, Color accent) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? accent : AppColors.metaText(context),
          width: selected ? 5 : 1.5,
        ),
      ),
    );
  }

  Widget _buildFormatRow(BuildContext context, bool isDark) {
    final isVideo = _mode == _DlMode.video;
    final label =
        isVideo
            ? AppLocalizations.configDialogVideoFormat
            : AppLocalizations.configDialogAudioFormat;
    final current =
        isVideo ? _videoFormat.displayName : _audioFormat.toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.buttonSecondary.copyWith(
                fontSize: 13.5,
                color: AppColors.metaText(context),
              ),
            ),
          ),
          _formatMenu(context, isDark, isVideo, current),
        ],
      ),
    );
  }

  Widget _formatMenu(
    BuildContext context,
    bool isDark,
    bool isVideo,
    String current,
  ) {
    final border = AppColors.border(context);
    final pill = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smMd,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkAppBg : AppColors.surface2(context),
        borderRadius: BorderRadius.circular(AppRadius.input),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            current,
            style: AppTypography.buttonSecondary.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkLightText : null,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.expand_more_rounded,
            size: 17,
            color: AppColors.metaText(context),
          ),
        ],
      ),
    );

    if (isVideo) {
      return PopupMenuButton<ContainerFormatPreference>(
        tooltip: '',
        position: PopupMenuPosition.under,
        onSelected: (v) => setState(() => _videoFormat = v),
        itemBuilder:
            (_) => [
              for (final f in ContainerFormatPreference.values)
                PopupMenuItem<ContainerFormatPreference>(
                  value: f,
                  child: Text(f.displayName),
                ),
            ],
        child: pill,
      );
    }
    return PopupMenuButton<String>(
      tooltip: '',
      position: PopupMenuPosition.under,
      onSelected: (v) => setState(() => _audioFormat = v),
      itemBuilder:
          (_) => [
            for (final f in _audioFormats)
              PopupMenuItem<String>(value: f, child: Text(f.toUpperCase())),
          ],
      child: pill,
    );
  }

  Widget _buildRememberRow(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _remember = !_remember),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color:
                    _remember ? AppColors.accentHighlight : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color:
                      _remember
                          ? AppColors.accentHighlight
                          : AppColors.metaText(context),
                  width: 1.5,
                ),
              ),
              child:
                  _remember
                      ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: AppColors.darkLightText,
                      )
                      : null,
            ),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Text(
                AppLocalizations.qualityDialogRememberChoice(
                  widget.platform.displayName,
                ),
                style: AppTypography.buttonSecondary.copyWith(
                  fontSize: 13.5,
                  color: AppColors.metaText(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Advanced options as an INLINE expander — only processing overrides
  /// (trim, subtitles, embed, SponsorBlock, codec/fps). Container + resolution
  /// are hidden here because the sheet's Format + Quality already own them, so
  /// nothing duplicates. The panel stays mounted (Offstage) once built, so
  /// edits survive collapse/expand within the sheet.
  Widget _buildAdvancedSection(BuildContext context, bool isDark) {
    final ffmpegAvailable =
        ref.watch(binaryAvailableProvider(BinaryType.ffmpeg)).valueOrNull ??
        false;
    final settings = ref.watch(settingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Divider(height: 1, color: AppColors.border(context)),
        ),
        InkWell(
          onTap:
              () => setState(() => _advancedExpanded = !_advancedExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.smMd),
            child: Row(
              children: [
                Icon(
                  Icons.tune_rounded,
                  size: 17,
                  color: AppColors.metaText(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    AppLocalizations.configDialogAdvancedOptions,
                    style: AppTypography.buttonSecondary.copyWith(
                      fontSize: 13.5,
                      color: AppColors.metaText(context),
                    ),
                  ),
                ),
                Icon(
                  _advancedExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.metaText(context),
                ),
              ],
            ),
          ),
        ),
        Offstage(
          offstage: !_advancedExpanded,
          child: ConfigPreferencesPanel(
            key: _prefsKey,
            settings: settings,
            platform: widget.platform,
            onChanged: (_) {},
            videoInfo: widget.videoInfo,
            ffmpegAvailable: ffmpegAvailable,
            showSaveAsDefault: false,
            showContainerAndResolution: false,
            fileType:
                _mode == _DlMode.audio
                    ? DownloadFileType.audio
                    : DownloadFileType.video,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              AppLocalizations.qualityDialogCancel,
              style: AppTypography.buttonSecondary.copyWith(
                color: AppColors.metaText(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton.icon(
            onPressed: _onDownload,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(AppLocalizations.qualityDialogDownload),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentHighlight,
              foregroundColor: AppColors.darkLightText,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.smMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
