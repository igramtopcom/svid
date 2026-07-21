import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/core.dart';
import '../../domain/entities/media_info.dart';

/// Center preview area for the standalone editor.
///
/// Displays a thumbnail of the loaded media file with overlay info
/// (resolution, duration, codec). Falls back to a file icon for
/// audio-only or unprobed files.
class EditorCanvas extends StatelessWidget {
  final String filePath;
  final MediaInfo? mediaInfo;
  final bool isProbing;
  final String? thumbnailPath;

  const EditorCanvas({
    super.key,
    required this.filePath,
    this.mediaInfo,
    this.isProbing = false,
    this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.homeDarkCardBg : AppColors.surface2(context),
        border: Border.all(
          color:
              isDark
                  ? AppColors.homeDarkBorderStrong
                  : AppColors.border(context).withValues(alpha: 0.55),
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child:
            isProbing
                ? Center(child: _buildProbing(context))
                : mediaInfo != null
                ? _buildPreview(context)
                : Center(child: _buildPlaceholder(context)),
      ),
    );
  }

  Widget _buildProbing(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.accentHighlight,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'converter.analyzing'.tr(),
          style: TextStyle(
            fontSize: 11,
            color:
                isDark
                    ? AppColors.homeDarkTextSecondary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    final info = mediaInfo!;
    final hasVideo = info.hasVideo;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Thumbnail or audio icon
        if (hasVideo)
          _buildVideoThumbnail(context)
        else
          Center(
            child: Icon(
              Icons.audiotrack_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),

        // Bottom overlay bar with media info
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
            child: Row(
              children: [
                // Filename
                Expanded(
                  child: Text(
                    info.filename,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // Resolution
                if (hasVideo) ...[
                  Flexible(child: _infoBadge(info.qualityLabel)),
                  const SizedBox(width: 6),
                ],
                // Duration
                if (info.duration != null)
                  Flexible(child: _infoBadge(info.durationLabel)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoThumbnail(BuildContext context) {
    // Use extracted thumbnail from ffmpeg cache
    if (thumbnailPath != null) {
      final thumbFile = File(thumbnailPath!);
      if (thumbFile.existsSync()) {
        return Image.file(
          thumbFile,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _videoPlaceholder(context),
        );
      }
    }
    return _videoPlaceholder(context);
  }

  Widget _videoPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.movie_rounded,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.30),
            ),
            const SizedBox(height: 8),
            Text(
              mediaInfo?.resolutionLabel ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isDark
                        ? AppColors.homeDarkTextSecondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_rounded,
            size: 48,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.30),
          ),
          const SizedBox(height: 8),
          Text(
            File(filePath).uri.pathSegments.last,
            style: TextStyle(
              fontSize: 11,
              color:
                  isDark
                      ? AppColors.homeDarkTextSecondary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _infoBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: Colors.white,
        ),
      ),
    );
  }
}
