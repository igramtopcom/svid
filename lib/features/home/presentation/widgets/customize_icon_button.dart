/// V2 — ⚙️ Tuỳ chỉnh icon (Tier 1 customization access).
///
/// Per UI Spec §4 + §5.6, this icon opens [DownloadConfigDialog] one-shot
/// for the next download (config not saved). Visibility / disabled state
/// matrix:
///   - hidden when input type ∈ {channel, searchKeyword}
///   - disabled while reclassifying or when input is empty
///   - quota=0 does NOT disable this icon (Spec §7) — only the primary
///     CTA is gated by quota
///
/// Wiring to the actual dialog happens at the call site so this widget
/// stays decoupled from settings/config plumbing.
library;

import 'package:flutter/material.dart';

import '../../../../core/design/design_tokens.dart';
import '../../../../core/l10n/app_localizations.dart';
import '../../domain/services/url_classifier_service.dart';
import '../providers/smart_input_provider.dart';

class CustomizeIconButton extends StatelessWidget {
  const CustomizeIconButton({
    required this.state,
    required this.onPressed,
    super.key,
  });

  final SmartInputState state;
  final VoidCallback? onPressed;

  bool get _hidden =>
      state.type == SmartInputType.channel ||
      state.type == SmartInputType.searchKeyword;

  bool get _enabled =>
      !state.isReclassifying && state.type != SmartInputType.empty;

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    return SizedBox(
      width: AppComponentSize.iconButtonSize,
      height: AppComponentSize.iconButtonSize,
      child: IconButton(
        onPressed: _enabled ? onPressed : null,
        tooltip: AppLocalizations.homeCustomizeBeforeDownload,
        icon: const Icon(Icons.tune, size: AppComponentSize.iconButtonGlyph),
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(
            AppMinWidth.iconOnlyButton,
            AppMinWidth.iconOnlyButton,
          ),
        ),
      ),
    );
  }
}
