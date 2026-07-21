import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/conversion_config.dart';

/// Rotate / flip direction selector.
///
/// Shows 5 options: CW 90°, CCW 90°, 180°, Flip H, Flip V.
/// Maps to [ConversionConfig.rotate] (RotateOption enum).
class RotateFlipPanel extends StatefulWidget {
  final RotateOption? initialOption;
  final ValueChanged<RotateOption?> onChanged;

  const RotateFlipPanel({
    super.key,
    this.initialOption,
    required this.onChanged,
  });

  @override
  State<RotateFlipPanel> createState() => _RotateFlipPanelState();
}

class _RotateFlipPanelState extends State<RotateFlipPanel> {
  late RotateOption _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialOption ?? RotateOption.cw90;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'converter.enhance.rotateFlip'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // Option grid
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: RotateOption.values.map((opt) {
              final isSelected = opt == _selected;
              return _OptionChip(
                icon: _iconFor(opt),
                label: _labelFor(opt),
                isSelected: isSelected,
                onTap: () {
                  setState(() => _selected = opt);
                  widget.onChanged(opt);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(RotateOption opt) {
    switch (opt) {
      case RotateOption.cw90:
        return Icons.rotate_right_rounded;
      case RotateOption.ccw90:
        return Icons.rotate_left_rounded;
      case RotateOption.rotate180:
        return Icons.screen_rotation_rounded;
      case RotateOption.flipH:
        return Icons.flip_rounded;
      case RotateOption.flipV:
        return Icons.flip_rounded;
    }
  }

  String _labelFor(RotateOption opt) {
    switch (opt) {
      case RotateOption.cw90:
        return 'converter.enhance.rotateCw90'.tr();
      case RotateOption.ccw90:
        return 'converter.enhance.rotateCcw90'.tr();
      case RotateOption.rotate180:
        return 'converter.enhance.rotate180'.tr();
      case RotateOption.flipH:
        return 'converter.enhance.flipHorizontal'.tr();
      case RotateOption.flipV:
        return 'converter.enhance.flipVertical'.tr();
    }
  }
}

class _OptionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionChip({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? cs.primary.withValues(alpha: 0.15)
          : cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: 0.15),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
