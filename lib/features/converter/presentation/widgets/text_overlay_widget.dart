import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../domain/entities/conversion_config.dart';

/// Text overlay configuration widget.
///
/// Text input, position dropdown (Top/Center/Bottom),
/// font size slider, color picker, and border toggle.
class TextOverlayWidget extends StatefulWidget {
  final String? initialText;
  final TextOverlayConfig? initialConfig;
  final ValueChanged<String?> onTextChanged;
  final ValueChanged<TextOverlayConfig> onConfigChanged;

  const TextOverlayWidget({
    super.key,
    this.initialText,
    this.initialConfig,
    required this.onTextChanged,
    required this.onConfigChanged,
  });

  @override
  State<TextOverlayWidget> createState() => _TextOverlayWidgetState();
}

class _TextOverlayWidgetState extends State<TextOverlayWidget> {
  late TextEditingController _textCtrl;
  late String _position;
  late int _fontSize;
  late String _fontColor;
  late bool _showBorder;
  late String _borderColor;
  late int _borderWidth;

  static const _colorOptions = [
    ('white', 'White', Colors.white),
    ('black', 'Black', Colors.black),
    ('red', 'Red', Colors.red),
    ('yellow', 'Yellow', Colors.yellow),
    ('blue', 'Blue', Colors.blue),
    ('green', 'Green', Colors.green),
  ];

  @override
  void initState() {
    super.initState();
    final cfg = widget.initialConfig ?? const TextOverlayConfig();
    _textCtrl = TextEditingController(text: widget.initialText ?? '');
    _position = cfg.position;
    _fontSize = cfg.fontSize;
    _fontColor = cfg.fontColor;
    _showBorder = cfg.borderColor != null;
    _borderColor = cfg.borderColor ?? 'black';
    _borderWidth = cfg.borderWidth;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha:0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'converter.enhance.textOverlay'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),

          // Text input
          TextField(
            controller: _textCtrl,
            style: tt.bodySmall,
            onChanged: (text) {
              widget.onTextChanged(text.isEmpty ? null : text);
            },
            decoration: InputDecoration(
              hintText: 'converter.enhance.enterText'.tr(),
              hintStyle: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha:0.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha:0.5),
            ),
          ),
          const SizedBox(height: 10),

          // Position + Font Size row
          Row(
            children: [
              // Position
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'converter.enhance.position'.tr(),
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 34,
                      child: DropdownButtonFormField<String>(
                        value: _position,
                        isExpanded: true,
                        isDense: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.15)),
                          ),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha:0.5),
                        ),
                        style: tt.bodySmall?.copyWith(color: cs.onSurface),
                        items: [
                          DropdownMenuItem(value: 'top', child: Text(AppLocalizations.converterOverlayPositionTop)),
                          DropdownMenuItem(value: 'center', child: Text(AppLocalizations.converterOverlayPositionCenter)),
                          DropdownMenuItem(value: 'bottom', child: Text(AppLocalizations.converterOverlayPositionBottom)),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => _position = v);
                            _emitConfig();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Font Size
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'converter.enhance.fontSize'.tr(),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          '$_fontSize',
                          style: tt.labelSmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: 28,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape:
                              const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _fontSize.toDouble(),
                          min: 12,
                          max: 72,
                          divisions: 60,
                          onChanged: (v) {
                            setState(() => _fontSize = v.round());
                            _emitConfig();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Font color
          Text(
            'converter.enhance.fontColor'.tr(),
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _colorOptions.map((opt) {
              final isSelected = opt.$1 == _fontColor;
              return GestureDetector(
                onTap: () {
                  setState(() => _fontColor = opt.$1);
                  _emitConfig();
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: opt.$3,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? cs.primary
                          : cs.outlineVariant.withValues(alpha:0.5),
                      width: isSelected ? 2.5 : 1,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),

          // Border toggle
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: Checkbox(
                  value: _showBorder,
                  onChanged: (v) {
                    setState(() => _showBorder = v ?? false);
                    _emitConfig();
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'converter.enhance.textBorder'.tr(),
                style: tt.bodySmall?.copyWith(color: cs.onSurface),
              ),
              if (_showBorder) ...[
                const SizedBox(width: 16),
                Text(
                  'converter.enhance.borderWidth'.tr(),
                  style: tt.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 80,
                  height: 20,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                    ),
                    child: Slider(
                      value: _borderWidth.toDouble(),
                      min: 1,
                      max: 6,
                      divisions: 5,
                      onChanged: (v) {
                        setState(() => _borderWidth = v.round());
                        _emitConfig();
                      },
                    ),
                  ),
                ),
                Text(
                  '$_borderWidth',
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _emitConfig() {
    widget.onConfigChanged(TextOverlayConfig(
      position: _position,
      fontSize: _fontSize,
      fontColor: _fontColor,
      borderColor: _showBorder ? _borderColor : null,
      borderWidth: _borderWidth,
    ));
  }
}
