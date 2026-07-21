import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/app_spacing.dart';

/// Letterbox aspect ratio selector.
///
/// Shows 3 target aspect ratios: 16:9, 4:3, 21:9.
/// Maps to [ConversionConfig.letterbox].
class LetterboxPanel extends StatefulWidget {
  final String? initialRatio;
  final ValueChanged<String?> onRatioChanged;

  const LetterboxPanel({
    super.key,
    this.initialRatio,
    required this.onRatioChanged,
  });

  @override
  State<LetterboxPanel> createState() => _LetterboxPanelState();
}

class _LetterboxPanelState extends State<LetterboxPanel> {
  late String _selected;

  static const _ratios = [
    _RatioInfo(value: '4:3', label: '4:3', desc: 'Standard'),
    _RatioInfo(value: '16:9', label: '16:9', desc: 'Widescreen'),
    _RatioInfo(value: '21:9', label: '21:9', desc: 'Cinematic'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialRatio ?? '16:9';
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
            'converter.enhance.letterbox'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'converter.enhance.letterboxDesc'.tr(),
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),

          // Aspect ratio visual selector
          Row(
            children: _ratios.map((ratio) {
              final isSelected = ratio.value == _selected;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: ratio != _ratios.last ? 8 : 0,
                  ),
                  child: Material(
                    color: isSelected
                        ? cs.primary.withValues(alpha: 0.15)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selected = ratio.value);
                        widget.onRatioChanged(ratio.value);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSelected
                                ? cs.primary
                                : cs.outlineVariant.withValues(alpha: 0.15),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Visual aspect ratio preview
                            _AspectPreview(
                              ratio: ratio.value,
                              isSelected: isSelected,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ratio.label,
                              style: tt.labelMedium?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? cs.primary
                                    : cs.onSurface,
                              ),
                            ),
                            Text(
                              ratio.desc,
                              style: tt.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _AspectPreview extends StatelessWidget {
  final String ratio;
  final bool isSelected;

  const _AspectPreview({required this.ratio, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Convert ratio string to aspect dimensions
    double w, h;
    switch (ratio) {
      case '4:3':
        w = 32;
        h = 24;
        break;
      case '16:9':
        w = 36;
        h = 20;
        break;
      case '21:9':
        w = 42;
        h = 18;
        break;
      default:
        w = 36;
        h = 20;
    }

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.2)
            : cs.onSurfaceVariant.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.5)
              : cs.onSurfaceVariant.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
    );
  }
}

class _RatioInfo {
  final String value;
  final String label;
  final String desc;

  const _RatioInfo({
    required this.value,
    required this.label,
    required this.desc,
  });
}
