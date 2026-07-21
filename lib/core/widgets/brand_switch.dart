import 'package:flutter/material.dart';
import '../config/brand_config.dart';
import '../theme/app_colors.dart';

/// Drop-in replacement for [Switch] that renders a brand-appropriate toggle.
///
/// - **SSvid (Nocturne Cinematic)**: angular tactical toggle — rectangular
///   track (3px radius), square thumb (2px radius), no pill shape. Matches the
///   "control room" language of the rest of the brand.
/// - **VidCombo (Arctic Command)**: Material [Switch] — soft pill/rounded
///   thumb, friendly and approachable.
class BrandSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const BrandSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (BrandConfig.current.brand == Brand.ssvid) {
      return _TacticalToggle(value: value, onChanged: onChanged);
    }
    return Switch(value: value, onChanged: onChanged);
  }
}

/// Drop-in replacement for [SwitchListTile] using [BrandSwitch] as the trailing
/// control. Ensures both brands share the same tap target / layout behavior.
class BrandSwitchListTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;

  const BrandSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.contentPadding,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: secondary,
      title: title,
      subtitle: subtitle,
      contentPadding: contentPadding,
      dense: dense,
      enabled: onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      trailing: BrandSwitch(value: value, onChanged: onChanged),
    );
  }
}

// =============================================================================
// SSVID TACTICAL TOGGLE — Angular "control room" toggle
// =============================================================================

class _TacticalToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double _trackWidth = 48;
  static const double _trackHeight = 26;
  static const double _thumbSize = 18;
  static const double _thumbPadding = 4;

  const _TacticalToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final accent = AppColors.accentHighlight;

    final trackColorOn = enabled ? accent : accent.withValues(alpha: 0.35);
    final trackColorOff = cs.surfaceContainerHighest;
    final borderColorOff = cs.outline;

    // Thumb — brighter in off-state for affordance than plain onSurfaceVariant.
    final thumbColorOn = Colors.white;
    final thumbColorOff = Color.lerp(cs.onSurfaceVariant, cs.onSurface, 0.35)!;

    return Semantics(
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Opacity(
            opacity: enabled ? 1.0 : 0.45,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: _trackWidth,
              height: _trackHeight,
              decoration: BoxDecoration(
                color: value ? trackColorOn : trackColorOff,
                borderRadius: BorderRadius.circular(3),
                border: value
                    ? null
                    : Border.all(color: borderColorOff, width: 1),
                boxShadow: value
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // OFF-state track marker: small "O" circle at the ON-destination
                  // end, hinting where the thumb will travel when flipped.
                  if (!value)
                    Positioned(
                      right: 6,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    alignment:
                        value ? Alignment.centerRight : Alignment.centerLeft,
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: _thumbPadding),
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        decoration: BoxDecoration(
                          color: value ? thumbColorOn : thumbColorOff,
                          borderRadius: BorderRadius.circular(2),
                          boxShadow: value
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        // ON-state "throw switch" marker: vertical crimson bar
                        // centered in the white thumb — reads as "lever engaged".
                        child: value
                            ? Center(
                                child: Container(
                                  width: 2,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
