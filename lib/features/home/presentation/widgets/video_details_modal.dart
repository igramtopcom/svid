import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../../downloads/domain/entities/video_info.dart';

/// Bottom sheet for adaptive stream selection (Task 83.2).
/// Nocturne Cinematic "Stream Arsenal" — angular, crimson accents, slim rows.
///
/// Lets the user pick a specific video-only stream and a specific audio stream,
/// then combines them into a single `ytdlp:raw:{videoId}+{audioId}` download.
///
/// Returns a [Quality] to the caller via [show], or `null` if cancelled.
class VideoDetailsModal extends StatefulWidget {
  final VideoInfo videoInfo;

  const VideoDetailsModal({super.key, required this.videoInfo});

  /// Opens the modal and returns the selected combo [Quality], or `null`.
  static Future<Quality?> show(BuildContext context, VideoInfo videoInfo) {
    return showModalBottomSheet<Quality>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VideoDetailsModal(videoInfo: videoInfo),
    );
  }

  @override
  State<VideoDetailsModal> createState() => _VideoDetailsModalState();
}

class _VideoDetailsModalState extends State<VideoDetailsModal> {
  Quality? _selectedVideo;
  Quality? _selectedAudio;

  late final List<Quality> _videoTracks;
  late final List<Quality> _audioTracks;

  @override
  void initState() {
    super.initState();
    final qualities = widget.videoInfo.availableQualities;
    _videoTracks = qualities.where((q) => q.isVideoOnly).toList();
    _audioTracks = qualities
        .where((q) =>
            q.isAudioOnly &&
            q.encryptedUrl.startsWith('ytdlp:raw:'))
        .toList();

    if (_videoTracks.isNotEmpty) _selectedVideo = _videoTracks.first;
    if (_audioTracks.isNotEmpty) _selectedAudio = _audioTracks.first;
  }

  String _formatId(Quality q) {
    final parts = q.encryptedUrl.split(':');
    return parts.length >= 3 ? parts[2] : q.encryptedUrl;
  }

  Quality _buildCombo() {
    final vid = _selectedVideo!;
    final aud = _selectedAudio!;
    final comboId = '${_formatId(vid)}+${_formatId(aud)}';
    return Quality(
      qualityText: '${vid.qualityText} + ${aud.qualityText}',
      size: '',
      encryptedUrl: 'ytdlp:raw:$comboId',
      mediaType: MediaType.video,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Design system colors
    final surfaceBg = isDark ? AppColors.darkBg : AppColors.lightBase;
    final headerBg = isDark ? AppColors.darkSurface1 : AppColors.lightSurface1;
    final rowBg = isDark ? AppColors.darkSurface1 : AppColors.lightSurface2;
    final rowSelectedBg = isDark ? AppColors.accentHighlight.withValues(alpha: AppOpacity.pressed) : AppColors.accentHighlight.withAlpha(20);
    final textPrimary = isDark ? AppColors.darkLightText : Theme.of(context).colorScheme.onSurface;
    final textSecondary = AppColors.metaText(context);
    final dividerColor = isDark ? AppColors.darkElevated : AppColors.lightBorder;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: surfaceBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
          child: Column(
            children: [
              // Drag handle — angular
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: textSecondary.withAlpha(80),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Header — Nocturne title bar
              Container(
                padding: const EdgeInsets.fromLTRB(AppSpacing.mdLg, AppSpacing.smMd, AppSpacing.smMd, AppSpacing.smMd),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(
                    bottom: BorderSide(color: dividerColor, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune, color: AppColors.accentHighlight, size: 18),
                    const SizedBox(width: AppSpacing.smMd),
                    Text(
                      AppLocalizations.streamSelectionAdvancedTitle,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: textPrimary,
                      ),
                    ),
                    const Spacer(),
                    _buildCloseButton(isDark, textSecondary),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.smMd),
                  children: [
                    if (_videoTracks.isEmpty && _audioTracks.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Text(
                            AppLocalizations.streamSelectionNoRawStreams,
                            textAlign: TextAlign.center,
                            style: AppTypography.metadata.copyWith(color: textSecondary),
                          ),
                        ),
                      )
                    else ...[
                      // Video tracks section
                      if (_videoTracks.isNotEmpty) ...[
                        _buildSectionHeader(
                          icon: Icons.videocam_outlined,
                          label: AppLocalizations.streamSelectionVideoTracks,
                          count: _videoTracks.length,
                          isDark: isDark,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._videoTracks.map(
                          (q) => _buildTrackTile(
                            quality: q,
                            selected: _selectedVideo == q,
                            onTap: () =>
                                setState(() => _selectedVideo = q),
                            isDark: isDark,
                            rowBg: rowBg,
                            rowSelectedBg: rowSelectedBg,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.smMd),
                      ],
                      // Audio tracks section
                      if (_audioTracks.isNotEmpty) ...[
                        _buildSectionHeader(
                          icon: Icons.audio_file_outlined,
                          label: AppLocalizations.streamSelectionAudioTracks,
                          count: _audioTracks.length,
                          isDark: isDark,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ..._audioTracks.map(
                          (q) => _buildTrackTile(
                            quality: q,
                            selected: _selectedAudio == q,
                            onTap: () =>
                                setState(() => _selectedAudio = q),
                            isDark: isDark,
                            rowBg: rowBg,
                            rowSelectedBg: rowSelectedBg,
                            textPrimary: textPrimary,
                            textSecondary: textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.smMd),
                      ],
                      // Info note — angular with crimson left bar
                      if (_videoTracks.isNotEmpty && _audioTracks.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkBg : AppColors.lightSurface3,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                            border: Border(
                              left: BorderSide(
                                color: AppColors.accentHighlight,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 14, color: AppColors.accentHighlight),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  AppLocalizations.streamSelectionComboHint,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              // Action buttons — Nocturne bottom bar
              if (_videoTracks.isNotEmpty || _audioTracks.isNotEmpty)
                Container(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.smMd, AppSpacing.md, AppSpacing.md),
                  decoration: BoxDecoration(
                    color: headerBg,
                    border: Border(
                      top: BorderSide(color: dividerColor, width: 1),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      children: [
                        // Cancel — angular wine border
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: AppColors.brand, width: 1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.card),
                                ),
                              ),
                              child: Text(
                                AppLocalizations.commonCancel.toUpperCase(),
                                style: AppTypography.sectionHeader.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0,
                                  color: isDark ? AppColors.accentHighlight : AppColors.brand,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.smMd),
                        // Download combo — crimson CTA
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: (_selectedVideo != null &&
                                      _selectedAudio != null)
                                  ? () =>
                                      Navigator.of(context).pop(_buildCombo())
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.accentHighlight,
                                disabledBackgroundColor: isDark
                                    ? AppColors.darkElevated
                                    : AppColors.lightSurface3,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.card),
                                ),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.merge_type, size: 16),
                              label: Text(
                                AppLocalizations.streamSelectionDownloadCombo.toUpperCase(),
                                style: AppTypography.sectionHeader.copyWith(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Close button (angular) ──

  Widget _buildCloseButton(bool isDark, Color textSecondary) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkElevated : AppColors.lightSurface3,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Icon(Icons.close, size: 16, color: textSecondary),
      ),
    );
  }

  // ── Section header (uppercase Nocturne) ──

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required int count,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.accentHighlight),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '${label.toUpperCase()} ($count)',
          style: AppTypography.compact.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: AppColors.accentHighlight,
          ),
        ),
      ],
    );
  }

  // ── Track tile (slim row, crimson left accent when selected) ──

  Widget _buildTrackTile({
    required Quality quality,
    required bool selected,
    required VoidCallback onTap,
    required bool isDark,
    required Color rowBg,
    required Color rowSelectedBg,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final formatId = _formatId(quality);
    final codecText = quality.vcodec ?? quality.acodec ?? '';
    final badgeColor = _codecColor(codecText);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.smMd),
        decoration: BoxDecoration(
          color: selected ? rowSelectedBg : rowBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: selected
              ? Border(
                  left: BorderSide(color: AppColors.accentHighlight, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.accentHighlight : textSecondary,
                  width: selected ? 2 : 1.5,
                ),
                color: selected ? AppColors.accentHighlight : Colors.transparent,
              ),
              child: selected
                  ? Center(
                      child: const Icon(Icons.circle, size: 8, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quality.qualityText,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (quality.size.isNotEmpty)
                        _chip(quality.size,
                            isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                            textColor: textSecondary),
                      if (codecText.isNotEmpty)
                        _chip(
                            _shortCodec(codecText),
                            badgeColor.withAlpha(30),
                            textColor: badgeColor),
                      if (quality.fps != null && quality.fps! > 0)
                        _chip('${quality.fps!.round()}fps',
                            isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                            textColor: textSecondary),
                      _chip('ID: $formatId',
                          isDark ? AppColors.darkElevated : AppColors.lightSurface3,
                          textColor: textSecondary),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Angular chip (2px radius) ──

  Widget _chip(String text, Color bg, {Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: AppTypography.mini.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: textColor,
        ),
      ),
    );
  }

  Color _codecColor(String codec) {
    final lower = codec.toLowerCase();
    if (lower.startsWith('avc') || lower.startsWith('h264')) {
      return AppColors.infoBlue;
    }
    if (lower.startsWith('vp9') || lower.startsWith('vp09')) {
      return AppColors.successGreen;
    }
    if (lower.startsWith('av01') || lower.startsWith('av1')) {
      return AppColors.audioFormatMP3; // orange
    }
    if (lower.startsWith('hevc') || lower.startsWith('hev')) {
      return AppColors.statusPostProcessing; // purple
    }
    return AppColors.accentHighlight;
  }

  String _shortCodec(String codec) {
    final lower = codec.toLowerCase();
    if (lower.startsWith('avc') || lower.startsWith('h264')) return 'H.264';
    if (lower.startsWith('vp9') || lower.startsWith('vp09')) return 'VP9';
    if (lower.startsWith('av01') || lower.startsWith('av1')) return 'AV1';
    if (lower.startsWith('hevc') || lower.startsWith('hev')) return 'H.265';
    if (lower == 'opus') return 'Opus';
    if (lower.startsWith('mp4a') || lower == 'aac') return 'AAC';
    return codec.split('.').first.toUpperCase();
  }
}
