/// V2 — Preset dropdown trigger.
///
/// Renders the "MP4 · 1080p ▾" chip per UI Spec §4 control bar. Clicking
/// opens [PresetPopover] (positioned by the parent). The label appends
/// `*` when [popoverDeepCustomizeProvider] is ON (per §5.6 hint that
/// Tier 2 deep customize is active). The actual preset value still comes
/// from §5 architecture which lands in Phase §5; until then the label
/// stays a constant "MP4 · 1080p" placeholder.
library;

import 'package:flutter/material.dart';

import '../../../../core/design/design_tokens.dart';

class PresetDropdownButton extends StatelessWidget {
  const PresetDropdownButton({
    required this.label,
    required this.onPressed,
    this.deepCustomizeActive = false,
    super.key,
  });

  /// Visible text — defaults to "MP4 · 1080p" until §5 wiring lands.
  final String label;

  /// Tap handler; parent typically opens the [PresetPopover].
  final VoidCallback? onPressed;

  /// When `true`, append a `*` indicator next to the label per Spec §5.6.
  final bool deepCustomizeActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayLabel = deepCustomizeActive ? '$label *' : label;

    return SizedBox(
      height: AppComponentSize.presetDropdownHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          minimumSize: const Size(
            AppMinWidth.presetDropdownTrigger,
            AppComponentSize.presetDropdownHeight,
          ),
        ),
        icon: const SizedBox.shrink(),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(displayLabel),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.expand_more, size: AppIconSize.md),
          ],
        ),
      ),
    );
  }
}
