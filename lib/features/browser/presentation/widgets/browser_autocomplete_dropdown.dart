import '../../../../core/core.dart';
import 'package:flutter/material.dart';

import '../../domain/services/address_bar_autocomplete_service.dart';

/// Nocturne Cinematic autocomplete dropdown with platform detection,
/// hover effects, and visual source indicators.
///
/// Positioned via [CompositedTransformFollower] so it moves with the toolbar.
class BrowserAutocompleteDropdown extends StatelessWidget {
  final LayerLink layerLink;
  final List<AutocompleteSuggestion> suggestions;
  final int selectedIndex;
  final void Function(AutocompleteSuggestion) onSelect;

  const BrowserAutocompleteDropdown({
    super.key,
    required this.layerLink,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 38),
        child: Material(
          elevation: 0,
          borderRadius: BorderRadius.circular(AppRadius.card),
          color: AppColors.surface2(context),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          child: SizedBox(
            width: 520,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(
                  color:
                      isDark
                          ? AppColors.homeDarkBorderStrong
                          : cs.outline.withValues(alpha: AppOpacity.divider),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (int i = 0; i < suggestions.length; i++)
                      _SuggestionTile(
                        suggestion: suggestions[i],
                        isSelected: i == selectedIndex,
                        onTap: () => onSelect(suggestions[i]),
                        isFirst: i == 0,
                        isLast: i == suggestions.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionTile extends StatefulWidget {
  final AutocompleteSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;
  final bool isLast;

  const _SuggestionTile({
    required this.suggestion,
    required this.isSelected,
    required this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final platform = _detectPlatform(widget.suggestion.url);
    final hasPlatformIcon =
        platform.isNotEmpty && PlatformStyleHelper.hasSvgIcon(platform);
    final platformColor =
        platform.isNotEmpty
            ? PlatformStyleHelper.getColorForPlatform(platform)
            : null;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          color:
              widget.isSelected
                  ? AppColors.accentHighlight.withValues(
                    alpha: AppOpacity.pressed,
                  )
                  : _isHovered
                  ? cs.onSurface.withValues(alpha: AppOpacity.divider)
                  : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              // Source/platform icon
              SizedBox(
                width: 22,
                height: 22,
                child: Center(
                  child:
                      hasPlatformIcon
                          ? PlatformIcon(platform: platform, size: 14)
                          : Icon(
                            widget.suggestion.isBookmark
                                ? Icons.bookmark_rounded
                                : Icons.schedule_rounded,
                            size: 15,
                            color:
                                widget.suggestion.isBookmark
                                    ? AppColors.accentHighlight
                                    : platformColor ??
                                        cs.onSurface.withValues(
                                          alpha: AppOpacity.scrim,
                                        ),
                          ),
                ),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.suggestion.title.isNotEmpty)
                      Text(
                        widget.suggestion.title,
                        style: AppTypography.metadata.copyWith(
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface.withValues(
                            alpha: AppOpacity.nearOpaque,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      widget.suggestion.url
                          .replaceFirst(RegExp(r'^https?://'), '')
                          .replaceFirst(RegExp(r'^www\.'), ''),
                      style: AppTypography.statusBadge.copyWith(
                        fontWeight: FontWeight.w400,
                        color: cs.onSurface.withValues(
                          alpha: AppOpacity.medium,
                        ),
                        letterSpacing: 0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Source badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color:
                      widget.suggestion.isBookmark
                          ? AppColors.accentHighlight.withValues(
                            alpha: AppOpacity.hover,
                          )
                          : cs.onSurface.withValues(alpha: AppOpacity.divider),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  widget.suggestion.isBookmark
                      ? AppLocalizations.browserBookmarks
                      : AppLocalizations.browserHistory,
                  style: AppTypography.mini.copyWith(
                    fontWeight: FontWeight.w600,
                    color:
                        widget.suggestion.isBookmark
                            ? AppColors.accentHighlight
                            : cs.onSurface.withValues(alpha: AppOpacity.scrim),
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _detectPlatform(String url) {
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host.contains('youtube') || host.contains('youtu.be')) return 'youtube';
    if (host.contains('facebook') || host.contains('fb.com')) return 'facebook';
    if (host.contains('instagram')) return 'instagram';
    if (host.contains('tiktok')) return 'tiktok';
    if (host.contains('twitter') || host == 'x.com') return 'x';
    if (host.contains('reddit')) return 'reddit';
    if (host.contains('pinterest')) return 'pinterest';
    if (host.contains('vimeo')) return 'vimeo';
    if (host.contains('soundcloud')) return 'soundcloud';
    if (host.contains('github')) return 'github';
    if (host.contains('bilibili')) return 'bilibili';
    if (host.contains('dailymotion')) return 'dailymotion';
    return '';
  }
}
