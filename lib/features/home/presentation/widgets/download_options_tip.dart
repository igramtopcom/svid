import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/core.dart';
import '../../../settings/presentation/providers/settings_provider.dart';

/// One-time, dismissible hint that introduces the advanced download options
/// (trim / subtitles / SponsorBlock) reachable from the Download button's ▾.
/// Shown until the user dismisses it once, then never again.
class DownloadOptionsTip extends ConsumerStatefulWidget {
  const DownloadOptionsTip({super.key});

  @override
  ConsumerState<DownloadOptionsTip> createState() => _DownloadOptionsTipState();
}

class _DownloadOptionsTipState extends ConsumerState<DownloadOptionsTip> {
  static const _prefsKey = 'seen_download_options_tip_v1';

  // Start hidden; reveal only after we confirm the user hasn't dismissed it.
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    _dismissed = ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? false;
  }

  Future<void> _dismiss() async {
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, true);
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColors.accentHighlight;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.smMd,
          AppSpacing.sm,
          AppSpacing.smMd,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: isDark ? 0.12 : 0.07),
          borderRadius: BorderRadius.circular(AppRadius.input),
          border: Border.all(
            color: accent.withValues(alpha: isDark ? 0.34 : 0.24),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.content_cut_rounded, size: 18, color: accent),
            const SizedBox(width: AppSpacing.smMd),
            Expanded(
              child: Text(
                AppLocalizations.homeDownloadOptionsTip,
                style: AppTypography.buttonSecondary.copyWith(
                  fontSize: 13,
                  color: isDark ? AppColors.darkLightText : null,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              onPressed: _dismiss,
              visualDensity: VisualDensity.compact,
              tooltip: AppLocalizations.commonClose,
              icon: Icon(
                Icons.close_rounded,
                size: 16,
                color: AppColors.metaText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
