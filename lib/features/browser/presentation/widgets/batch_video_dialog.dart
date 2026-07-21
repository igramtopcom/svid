import '../../../../core/core.dart';
import 'package:flutter/material.dart';

import '../../domain/services/page_video_scanner_service.dart';

/// Nocturne Cinematic batch video selection dialog.
///
/// Shows detected video links with platform-colored cards, checkboxes,
/// and a crimson download action. Full visual overhaul from generic AlertDialog.
class BatchVideoDialog extends StatefulWidget {
  const BatchVideoDialog({
    super.key,
    required this.videos,
    required this.onDownload,
  });

  final List<DetectedVideoLink> videos;
  final ValueChanged<List<DetectedVideoLink>> onDownload;

  /// Show the dialog and return the selected videos, or null if cancelled.
  static Future<List<DetectedVideoLink>?> show(
    BuildContext context, {
    required List<DetectedVideoLink> videos,
    required ValueChanged<List<DetectedVideoLink>> onDownload,
  }) {
    return showDialog<List<DetectedVideoLink>>(
      context: context,
      builder: (_) => BatchVideoDialog(
        videos: videos,
        onDownload: onDownload,
      ),
    );
  }

  @override
  State<BatchVideoDialog> createState() => _BatchVideoDialogState();
}

class _BatchVideoDialogState extends State<BatchVideoDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.videos.map((v) => v.url).toSet();
  }

  void _selectAll() {
    setState(() {
      _selected.addAll(widget.videos.map((v) => v.url));
    });
  }

  void _deselectAll() {
    setState(() => _selected.clear());
  }

  void _toggle(String url) {
    setState(() {
      if (_selected.contains(url)) {
        _selected.remove(url);
      } else {
        _selected.add(url);
      }
    });
  }

  void _download() {
    final selectedVideos =
        widget.videos.where((v) => _selected.contains(v.url)).toList();
    widget.onDownload(selectedVideos);
    Navigator.of(context).pop(selectedVideos);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allSelected = _selected.length == widget.videos.length;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
      child: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.mdLg, AppSpacing.mdLg, AppSpacing.md, AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: cs.onSurface.withValues(alpha: AppOpacity.divider)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.accentHighlight.withValues(alpha: AppOpacity.pressed),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Icon(Icons.video_library_rounded,
                        size: 17, color: AppColors.accentHighlight),
                  ),
                  const SizedBox(width: AppSpacing.smMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.batchVideoTitle,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          AppLocalizations.batchVideoVideosFound(
                              widget.videos.length),
                          style: AppTypography.metadata.copyWith(
                            color: cs.onSurface.withValues(alpha: AppOpacity.medium),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded,
                        size: 20,
                        color: cs.onSurface.withValues(alpha: AppOpacity.medium)),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),

            // Select all / counter toolbar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              color: cs.surfaceContainerHigh.withValues(alpha: AppOpacity.scrim),
              child: Row(
                children: [
                  SizedBox(
                    height: 30,
                    child: TextButton.icon(
                      onPressed: allSelected ? _deselectAll : _selectAll,
                      icon: Icon(
                        allSelected
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: 15,
                      ),
                      label: Text(
                        allSelected
                            ? AppLocalizations.batchVideoDeselectAll
                            : AppLocalizations.batchVideoSelectAll,
                        style: AppTypography.metadata,
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: AppColors.accentHighlight.withValues(alpha: AppOpacity.pressed),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Text(
                      '${_selected.length} / ${widget.videos.length} SELECTED',
                      style: AppTypography.compact.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentHighlight,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Video list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemCount: widget.videos.length,
                itemBuilder: (context, index) {
                  final video = widget.videos[index];
                  final isSelected = _selected.contains(video.url);
                  return _VideoItem(
                    video: video,
                    isSelected: isSelected,
                    onToggle: () => _toggle(video.url),
                  );
                },
              ),
            ),

            // Footer with download button
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                      color: cs.onSurface.withValues(alpha: AppOpacity.divider)),
                ),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(AppLocalizations.batchVideoCancel),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 38,
                    child: FilledButton.icon(
                      onPressed: _selected.isEmpty ? null : _download,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        AppLocalizations.batchVideoDownloadSelected(
                            _selected.length),
                        style: AppTypography.buttonPrimary,
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentHighlight,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            cs.onSurface.withValues(alpha: AppOpacity.hover),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.mdLg),
                      ),
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
}

/// Individual video item with platform-colored icon and selection state.
class _VideoItem extends StatefulWidget {
  final DetectedVideoLink video;
  final bool isSelected;
  final VoidCallback onToggle;

  const _VideoItem({
    required this.video,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  State<_VideoItem> createState() => _VideoItemState();
}

class _VideoItemState extends State<_VideoItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platformName = widget.video.platform.name;
    final hasSvg = PlatformStyleHelper.hasSvgIcon(platformName);
    final platformColor =
        PlatformStyleHelper.getColorForPlatform(platformName);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color: widget.isSelected
              ? AppColors.accentHighlight.withValues(alpha: AppOpacity.divider)
              : _isHovered
                  ? cs.onSurface.withValues(alpha: AppOpacity.divider)
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              // Checkbox
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: widget.isSelected,
                  onChanged: (_) => widget.onToggle(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: AppColors.accentHighlight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              // Platform icon
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: AppOpacity.pressed),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child: hasSvg
                      ? PlatformIcon(platform: platformName, size: 14)
                      : Icon(
                          _platformIcon(widget.video.platform),
                          size: 14,
                          color: widget.isSelected
                              ? platformColor
                              : cs.onSurface.withValues(alpha: AppOpacity.medium),
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              // Title + URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.video.title.isNotEmpty
                          ? widget.video.title
                          : 'Video ${widget.video.platform.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.platformName.copyWith(
                        color: widget.isSelected
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: AppOpacity.strong),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      widget.video.url
                          .replaceFirst(RegExp(r'^https?://'), '')
                          .replaceFirst(RegExp(r'^www\.'), ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.statusBadge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface.withValues(alpha: AppOpacity.scrim),
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              // Platform badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: platformColor.withValues(alpha: AppOpacity.hover),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  widget.video.platform.name.toUpperCase(),
                  style: AppTypography.mini.copyWith(
                    fontWeight: FontWeight.w600,
                    color: platformColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _platformIcon(VideoPlatform platform) {
    return switch (platform) {
      VideoPlatform.youtube => Icons.play_circle_filled_rounded,
      VideoPlatform.tiktok => Icons.music_note_rounded,
      VideoPlatform.instagram => Icons.camera_alt_rounded,
      VideoPlatform.facebook => Icons.facebook_rounded,
      VideoPlatform.twitter => Icons.alternate_email_rounded,
      VideoPlatform.vimeo => Icons.video_library_rounded,
      VideoPlatform.dailymotion => Icons.ondemand_video_rounded,
      VideoPlatform.reddit => Icons.forum_rounded,
      VideoPlatform.soundcloud => Icons.headphones_rounded,
      VideoPlatform.bilibili => Icons.live_tv_rounded,
      _ => Icons.link_rounded,
    };
  }
}
