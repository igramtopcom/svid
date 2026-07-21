import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Loop count picker (2 to 10 repetitions).
///
/// Maps to [ConversionConfig.loopCount] used by FFmpegCommandBuilder
/// to repeat the video N times via concat.
class LoopCountPanel extends StatefulWidget {
  final int? initialCount;
  final ValueChanged<int?> onCountChanged;

  const LoopCountPanel({
    super.key,
    this.initialCount,
    required this.onCountChanged,
  });

  @override
  State<LoopCountPanel> createState() => _LoopCountPanelState();
}

class _LoopCountPanelState extends State<LoopCountPanel> {
  late int _count;

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount ?? 2;
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
          Row(
            children: [
              Text(
                'converter.enhance.loopCount'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // Stepper
              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepperButton(
                      icon: Icons.remove_rounded,
                      enabled: _count > 2,
                      onTap: () {
                        if (_count > 2) {
                          setState(() => _count--);
                          widget.onCountChanged(_count);
                        }
                      },
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 36),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${_count}x',
                        style: tt.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    _StepperButton(
                      icon: Icons.add_rounded,
                      enabled: _count < 10,
                      onTap: () {
                        if (_count < 10) {
                          setState(() => _count++);
                          widget.onCountChanged(_count);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Quick presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _CountButton(
                  label: '2x', isSelected: _count == 2, onTap: () => _set(2)),
              _CountButton(
                  label: '3x', isSelected: _count == 3, onTap: () => _set(3)),
              _CountButton(
                  label: '4x', isSelected: _count == 4, onTap: () => _set(4)),
              _CountButton(
                  label: '5x', isSelected: _count == 5, onTap: () => _set(5)),
              _CountButton(
                  label: '8x', isSelected: _count == 8, onTap: () => _set(8)),
              _CountButton(
                  label: '10x',
                  isSelected: _count == 10,
                  onTap: () => _set(10)),
            ],
          ),

          if (_count >= 5)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'converter.enhance.loopSizeWarning'.tr(),
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _set(int n) {
    setState(() => _count = n);
    widget.onCountChanged(n);
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? cs.onSurface
              : cs.onSurface.withValues(alpha: 0.2),
        ),
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CountButton({
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
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: cs.primary, width: 1.5),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
