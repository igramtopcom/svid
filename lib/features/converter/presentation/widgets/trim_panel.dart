import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/conversion_config.dart';

/// Panel with start/end time inputs for trimming video segments.
///
/// Shows a dual-handle range slider when duration is known, plus
/// manual time entry fields (HH:MM:SS.mmm).
class TrimPanel extends StatefulWidget {
  final Duration? mediaDuration;
  final TrimRange? initialTrim;
  final ValueChanged<TrimRange?> onTrimChanged;

  const TrimPanel({
    super.key,
    this.mediaDuration,
    this.initialTrim,
    required this.onTrimChanged,
  });

  @override
  State<TrimPanel> createState() => _TrimPanelState();
}

class _TrimPanelState extends State<TrimPanel> {
  late int _startMs;
  late int _endMs;

  @override
  void initState() {
    super.initState();
    _startMs = widget.initialTrim?.startMs ?? 0;
    _endMs = widget.initialTrim?.endMs ??
        (widget.mediaDuration?.inMilliseconds ?? 60000);
  }

  int get _maxMs => widget.mediaDuration?.inMilliseconds ?? 60000;

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
                'converter.enhance.trimCut'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _formatDuration(Duration(milliseconds: _endMs - _startMs)),
                style: tt.labelSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Range slider
          if (_maxMs > 0)
            SizedBox(
              height: 32,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  rangeThumbShape: const RoundRangeSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: RangeSlider(
                  values: RangeValues(
                    _startMs.toDouble().clamp(0, _maxMs.toDouble()),
                    _endMs.toDouble().clamp(0, _maxMs.toDouble()),
                  ),
                  min: 0,
                  max: _maxMs.toDouble(),
                  onChanged: (values) {
                    setState(() {
                      _startMs = values.start.round();
                      _endMs = values.end.round();
                    });
                    _emit();
                  },
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Time labels
          Row(
            children: [
              Expanded(
                child: _TimeInput(
                  label: 'converter.enhance.trimStart'.tr(),
                  milliseconds: _startMs,
                  onChanged: (ms) {
                    if (ms < _endMs) {
                      setState(() => _startMs = ms);
                      _emit();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TimeInput(
                  label: 'converter.enhance.trimEnd'.tr(),
                  milliseconds: _endMs,
                  onChanged: (ms) {
                    if (ms > _startMs && ms <= _maxMs) {
                      setState(() => _endMs = ms);
                      _emit();
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Quick presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickButton(
                label: 'converter.enhance.trimFirst30'.tr(),
                onTap: () => _setRange(0, 30000.clamp(0, _maxMs)),
              ),
              _QuickButton(
                label: 'converter.enhance.trimFirst60'.tr(),
                onTap: () => _setRange(0, 60000.clamp(0, _maxMs)),
              ),
              _QuickButton(
                label: 'converter.enhance.trimLast30'.tr(),
                onTap: () =>
                    _setRange((_maxMs - 30000).clamp(0, _maxMs), _maxMs),
              ),
              _QuickButton(
                label: 'converter.enhance.trimReset'.tr(),
                onTap: () => _setRange(0, _maxMs),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setRange(int start, int end) {
    setState(() {
      _startMs = start;
      _endMs = end;
    });
    _emit();
  }

  void _emit() {
    if (_startMs == 0 && _endMs == _maxMs) {
      widget.onTrimChanged(null); // Full range = no trim
    } else {
      widget.onTrimChanged(TrimRange(startMs: _startMs, endMs: _endMs));
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }
}

class _TimeInput extends StatefulWidget {
  final String label;
  final int milliseconds;
  final ValueChanged<int> onChanged;

  const _TimeInput({
    required this.label,
    required this.milliseconds,
    required this.onChanged,
  });

  @override
  State<_TimeInput> createState() => _TimeInputState();
}

class _TimeInputState extends State<_TimeInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatMs(widget.milliseconds));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _TimeInput old) {
    super.didUpdateWidget(old);
    if (old.milliseconds != widget.milliseconds && !_isEditing) {
      _controller.text = _formatMs(widget.milliseconds);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      setState(() => _isEditing = true);
      _controller.selection =
          TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
    } else {
      setState(() => _isEditing = false);
      _commit();
    }
  }

  void _commit() {
    final parsed = _parseTime(_controller.text);
    if (parsed != null) {
      widget.onChanged(parsed);
    }
    // Reset display to current value
    _controller.text = _formatMs(widget.milliseconds);
  }

  static String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inHours.toString().padLeft(2, '0')}:'
        '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
        '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  /// Parse HH:MM:SS or MM:SS or SS into milliseconds.
  static int? _parseTime(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final parts = trimmed.split(':');
    try {
      int hours = 0, minutes = 0, seconds = 0;
      if (parts.length == 3) {
        hours = int.parse(parts[0]);
        minutes = int.parse(parts[1]);
        seconds = int.parse(parts[2]);
      } else if (parts.length == 2) {
        minutes = int.parse(parts[0]);
        seconds = int.parse(parts[1]);
      } else if (parts.length == 1) {
        seconds = int.parse(parts[0]);
      } else {
        return null;
      }
      if (minutes < 0 || minutes > 59 || seconds < 0 || seconds > 59) {
        return null;
      }
      return ((hours * 3600) + (minutes * 60) + seconds) * 1000;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: tt.labelSmall?.copyWith(
            color: cs.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _isEditing
                  ? cs.primary.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            style: tt.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              border: InputBorder.none,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
            ],
            onSubmitted: (_) => _commit(),
          ),
        ),
      ],
    );
  }
}

class _QuickButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
