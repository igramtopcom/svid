import 'package:flutter/material.dart';

import '../../../../core/core.dart';

/// Explore search bar shared by the Explore tab and search sheet.
class YouTubeSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback onSearch;
  final bool isLoading;

  const YouTubeSearchBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.onSearch,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final fieldBg =
        isDark ? AppColors.homeDarkAppBg : AppColors.surface1(context);
    final fieldBorder =
        isDark
            ? AppColors.homeDarkInputBorder
            : cs.outlineVariant.withValues(alpha: AppOpacity.scrim);
    final muted =
        isDark
            ? AppColors.homeDarkTextSecondary
            : cs.onSurface.withValues(alpha: AppOpacity.secondary);

    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return SizedBox(
                height: 52,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: AppTypography.input.copyWith(
                    color: isDark ? AppColors.darkLightText : cs.onSurface,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.youtubeSearchPlaceholder,
                    hintStyle: AppTypography.inputHint.copyWith(color: muted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: muted,
                    ),
                    suffixIcon:
                        value.text.isNotEmpty
                            ? IconButton(
                              icon: Icon(
                                Icons.clear_rounded,
                                size: 16,
                                color: muted,
                              ),
                              onPressed: () {
                                controller.clear();
                                focusNode?.requestFocus();
                              },
                              tooltip: AppLocalizations.homeClear,
                            )
                            : null,
                    filled: true,
                    fillColor: fieldBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: BorderSide(color: fieldBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: BorderSide(color: fieldBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.input),
                      borderSide: BorderSide(
                        color: AppColors.accentHighlight,
                        width: 1.5,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => onSearch(),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: AppSpacing.smMd),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: isLoading ? null : onSearch,
            icon:
                isLoading
                    ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.darkLightText,
                        ),
                      ),
                    )
                    : const Icon(Icons.search_rounded, size: 18),
            label: Text(
              AppLocalizations.youtubeSearchSearch,
              style: AppTypography.buttonPrimary,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: AppColors.darkLightText,
              disabledBackgroundColor: AppColors.brand.withValues(
                alpha: AppOpacity.pressed,
              ),
              disabledForegroundColor: AppColors.darkLightText.withValues(
                alpha: AppOpacity.medium,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.mdLg,
                vertical: AppSpacing.smMd,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
