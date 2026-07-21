import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../providers/youtube_autocomplete_provider.dart';

/// Autocomplete suggestions list widget
class AutocompleteSuggestions extends ConsumerWidget {
  final void Function(String suggestion) onSuggestionTap;

  const AutocompleteSuggestions({super.key, required this.onSuggestionTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final state = ref.watch(youtubeAutocompleteProvider);
    final borderColor =
        isDark
            ? AppColors.homeDarkBorderStrong
            : cs.outlineVariant.withValues(alpha: AppOpacity.scrim);
    final panelColor = isDark ? AppColors.homeDarkCardBg : cs.surface;
    final muted =
        isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurfaceVariant.withValues(alpha: AppOpacity.overlay);

    // Show loading
    if (state.isLoading) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpacing.smMd),
              Text(
                AppLocalizations.commonLoading,
                style: AppTypography.metadata.copyWith(
                  color: muted,
                  fontWeight: AppTypography.medium,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Show error (silently, no UI)
    if (state.error != null) {
      return const SizedBox.shrink();
    }

    // No suggestions
    if (state.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show suggestions
    final suggestions = state.suggestions.take(8).toList(growable: false);
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 420),
        decoration: BoxDecoration(
          color: panelColor,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
              blurRadius: isDark ? 24 : 18,
              offset: const Offset(0, 12),
              spreadRadius: -10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.smMd,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 14, color: muted),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      AppLocalizations.youtubeSearchSuggestions,
                      style: AppTypography.metadata.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  itemCount: suggestions.length,
                  itemBuilder: (context, index) {
                    final suggestion = suggestions[index];
                    return _AutocompleteSuggestionRow(
                      suggestion: suggestion,
                      onTap: () => onSuggestionTap(suggestion),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AutocompleteSuggestionRow extends StatefulWidget {
  final String suggestion;
  final VoidCallback onTap;

  const _AutocompleteSuggestionRow({
    required this.suggestion,
    required this.onTap,
  });

  @override
  State<_AutocompleteSuggestionRow> createState() =>
      _AutocompleteSuggestionRowState();
}

class _AutocompleteSuggestionRowState
    extends State<_AutocompleteSuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? AppColors.accentHighlight : AppColors.brand;
    final foreground = isDark ? AppColors.darkLightText : cs.onSurface;
    final muted =
        isDark
            ? AppColors.homeDarkTextMuted
            : cs.onSurfaceVariant.withValues(alpha: AppOpacity.overlay);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smMd,
          ),
          decoration: BoxDecoration(
            color:
                _hovered
                    ? accent.withValues(alpha: isDark ? 0.12 : 0.08)
                    : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: _hovered ? accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 18,
                color: _hovered ? accent : muted,
              ),
              const SizedBox(width: AppSpacing.smMd),
              Expanded(
                child: Text(
                  widget.suggestion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.input.copyWith(
                    color:
                        _hovered
                            ? foreground
                            : foreground.withValues(alpha: isDark ? 0.88 : 0.9),
                    fontWeight:
                        _hovered
                            ? AppTypography.semiBold
                            : AppTypography.regular,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                Icons.north_west_rounded,
                size: 14,
                color: _hovered ? accent : muted.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
