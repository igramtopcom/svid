/// V2 — Smart CTA button.
///
/// Adaptive label + state machine driven by [SmartInputState] per UI
/// Spec §4.1 + §4.2:
///   - empty                    → label "Tải xuống", disabled
///   - singleVideo              → label "Tải xuống"
///   - multipleUrls             → label "Tải hàng loạt"
///   - playlist                 → label "Xem playlist"
///   - channel                  → label "Xem kênh"
///   - searchKeyword            → label "Tìm kiếm"
///   - unsupportedUrl           → label "Mở trình duyệt"
///   - isReclassifying          → label "Đang phân tích…", disabled spinner
///
/// Wires to onPressed when not disabled. Uses brand primary color via
/// [Theme.of(context).colorScheme.primary] so Svid Wine Red and
/// VidCombo Arctic Blue both render correctly without per-brand code.
library;

import 'package:flutter/material.dart';

import '../../../../core/design/design_tokens.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../domain/services/url_classifier_service.dart';
import '../providers/smart_input_provider.dart';

/// Visual + interaction state for the Smart CTA button.
class SmartCtaButton extends StatelessWidget {
  const SmartCtaButton({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final SmartInputState state;
  final VoidCallback? onPressed;

  bool get _enabled =>
      !state.isReclassifying && state.type != SmartInputType.empty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = _label(state);
    final iconData = _icon(state.type);

    return SizedBox(
      height: AppComponentSize.primaryButtonHeight,
      child: ElevatedButton.icon(
        onPressed: _enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.primary.withValues(alpha: 0.40),
          disabledForegroundColor: scheme.onPrimary.withValues(alpha: 0.70),
          minimumSize: const Size(
            AppMinWidth.primaryCta,
            AppComponentSize.primaryButtonHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        ),
        icon: state.isReclassifying
            ? SizedBox(
                width: AppIconSize.md,
                height: AppIconSize.md,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(scheme.onPrimary),
                ),
              )
            : Icon(iconData, size: AppIconSize.lg),
        label: Text(label),
      ),
    );
  }

  String _label(SmartInputState s) {
    if (s.isReclassifying) return AppLocalizations.smartCtaAnalyzing;
    switch (s.type) {
      case SmartInputType.empty:
      case SmartInputType.singleVideo:
        return AppLocalizations.smartCtaDownload;
      case SmartInputType.multipleUrls:
        return AppLocalizations.smartCtaBatchDownload;
      case SmartInputType.playlist:
        return AppLocalizations.smartCtaViewPlaylist;
      case SmartInputType.channel:
        return AppLocalizations.smartCtaViewChannel;
      case SmartInputType.searchKeyword:
        return AppLocalizations.smartCtaSearch;
      case SmartInputType.unsupportedUrl:
        return AppLocalizations.smartCtaOpenBrowser;
    }
  }

  IconData _icon(SmartInputType t) {
    switch (t) {
      case SmartInputType.multipleUrls:
        return Icons.layers_outlined;
      case SmartInputType.playlist:
        return Icons.playlist_play;
      case SmartInputType.channel:
        return Icons.subscriptions_outlined;
      case SmartInputType.searchKeyword:
        return Icons.search;
      case SmartInputType.unsupportedUrl:
        return Icons.public;
      case SmartInputType.empty:
      case SmartInputType.singleVideo:
        return Icons.download;
    }
  }
}
