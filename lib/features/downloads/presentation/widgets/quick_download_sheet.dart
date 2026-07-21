import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../premium/domain/entities/premium_feature.dart';
import '../../../premium/domain/entities/premium_limits.dart';
import '../../../premium/presentation/providers/premium_providers.dart';
import '../../../premium/presentation/widgets/upgrade_prompt_dialog.dart';
import '../../../settings/domain/enums/container_format_preference.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../domain/entities/download_config.dart';
import '../../domain/entities/video_info.dart';
import '../../domain/services/quality_resolution_parser.dart';
import 'download_config_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _videoOptions = _buildVideoOptions(widget.videoInfo);
    _hasVideo = _videoOptions.isNotEmpty;

    final settings = ref.read(settingsProvider);
    _videoFormat = settings.containerFormatPreference;

    final prefersAudio =
        settings.defaultDownloadFileType == DownloadFileType.audio;
    _mode = (!_hasVideo || prefersAudio) ? _DlMode.audio : _DlMode.video;

    if (_hasVideo) {
      final isPremium = ref.read(isPremiumProvider);
      final settingCap = settings.maxResolution; // 0 = unlimited
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
      config = DownloadConfig(
        selectedQualities: [opt.quality],
        fileType: DownloadFileType.video,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: PortableQualityTarget.video(
          targetHeight: opt.height,
          targetFpsCap: opt.quality.fps?.round(),
        ),
        containerFormatOverride:
            _videoFormat != settings.containerFormatPreference
                ? _videoFormat
                : null,
        rememberForPlatform: _remember,
      );
    } else {
      final normalized = _normalizeAudioFormat(_audioFormat);
      final lossless = normalized == 'wav' || normalized == 'flac';
      final label =
          lossless
              ? '${normalized.toUpperCase()} · '
                  '${AppLocalizations.configDialogAudioLosslessLabel}'
              : '${normalized.toUpperCase()} · $_bitrate kbps';
      final audioQuality = Quality(
        qualityText: label,
        size: '',
        encryptedUrl: 'ytdlp:audio:$normalized',
        mediaType: MediaType.audio,
        isAudioOnly: true,
        tbr: lossless ? null : _bitrate.toDouble(),
      );
      config = DownloadConfig(
        selectedQualities: [audioQuality],
        fileType: DownloadFileType.audio,
        qualityIntent: DownloadQualityIntent.specific,
        qualityTarget: PortableQualityTarget.audio(
          outputFormat: normalized,
          targetBitrateKbps: lossless ? null : _bitrate,
        ),
        rememberForPlatform: _remember,
      );
    }

    if (!mounted) return;
    Navigator.pop(context, config);
  }

  Future<void> _openAdvanced() async {
    final cfg = await DownloadConfigDialog.show(
      context,
      widget.videoInfo,
      widget.platform,
    );
    if (!mounted) return;
    if (cfg != null && cfg.selectedQualities.isNotEmpty) {
      Navigator.pop(context, cfg);
    }
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
                    ],
                  ),
                ),
              ),
              _buildAdvancedRow(context),
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

  Widget _buildAdvancedRow(BuildContext context) {
    return InkWell(
      onTap: _openAdvanced,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.smMd,
        ),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.border(context)),
          ),
        ),
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
              Icons.chevron_right_rounded,
              size: 18,
              color: AppColors.metaText(context),
            ),
          ],
        ),
      ),
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
