import '../../../../core/core.dart';
import 'package:flutter/material.dart';

import '../../domain/services/contextual_suggestion_service.dart';

/// Non-intrusive banner shown when a playlist/series/channel page is detected.
///
/// Dismissed by tapping ×. Shows max once per URL (caller manages session set).
class ContextualSuggestionBanner extends StatelessWidget {
  final DownloadSuggestion suggestion;
  final VoidCallback onDownload;
  final VoidCallback onDismiss;

  const ContextualSuggestionBanner({
    super.key,
    required this.suggestion,
    required this.onDownload,
    required this.onDismiss,
  });

  String _label(BuildContext context) {
    switch (suggestion.type) {
      case SuggestionType.youtubePlaylist:
        return AppLocalizations.browserSuggestionPlaylist;
      case SuggestionType.youtubeChannel:
        return AppLocalizations.browserSuggestionChannel;
      case SuggestionType.vimeoShowcase:
        return AppLocalizations.browserSuggestionShowcase;
      case SuggestionType.genericSeries:
        return AppLocalizations.browserSuggestionSeries;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface;
    return Material(
      color: AppColors.accentHighlight.withAlpha(30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Icons.playlist_play_rounded, size: 18, color: AppColors.accentHighlight),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _label(context),
                style: AppTypography.metadata.copyWith(
                  color: textColor,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onDownload,
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                AppLocalizations.browserSuggestionDownloadAll,
                style: AppTypography.metadata.copyWith(color: AppColors.accentHighlight),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close_rounded,
                  size: 16, color: cs.onSurfaceVariant),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.browserSuggestionDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
