import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/media_info.dart';

/// Configuration panels for Tools presets:
/// - Thumbnail extraction (timestamp picker)
/// - Subtitle extraction (track selector)
/// - Video splitting (interval input)
class ThumbnailConfigPanel extends StatefulWidget {
  final Duration? mediaDuration;
  final double? initialTimestamp;
  final ValueChanged<double> onTimestampChanged;

  const ThumbnailConfigPanel({
    super.key,
    this.mediaDuration,
    this.initialTimestamp,
    required this.onTimestampChanged,
  });

  @override
  State<ThumbnailConfigPanel> createState() => _ThumbnailConfigPanelState();
}

class _ThumbnailConfigPanelState extends State<ThumbnailConfigPanel> {
  late double _timestamp;

  @override
  void initState() {
    super.initState();
    _timestamp = widget.initialTimestamp ?? 0.0;
  }

  double get _maxSeconds =>
      widget.mediaDuration?.inMilliseconds.toDouble() != null
          ? widget.mediaDuration!.inMilliseconds / 1000.0
          : 300.0;

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
                'converter.enhance.thumbnailTime'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatTime(_timestamp),
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Slider
          SizedBox(
            height: 28,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _timestamp.clamp(0, _maxSeconds),
                min: 0,
                max: _maxSeconds,
                onChanged: (v) {
                  setState(() => _timestamp = v);
                  widget.onTimestampChanged(v);
                },
              ),
            ),
          ),

          const SizedBox(height: 6),
          // Quick presets
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _QuickBtn(label: '0s', onTap: () => _set(0)),
              _QuickBtn(label: '5s', onTap: () => _set(5)),
              _QuickBtn(label: '10s', onTap: () => _set(10)),
              _QuickBtn(label: '30s', onTap: () => _set(30)),
              _QuickBtn(
                label: '50%',
                onTap: () => _set(_maxSeconds / 2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _set(double t) {
    final clamped = t.clamp(0.0, _maxSeconds);
    setState(() => _timestamp = clamped);
    widget.onTimestampChanged(clamped);
  }

  String _formatTime(double seconds) {
    final m = (seconds / 60).floor();
    final s = (seconds % 60).floor();
    final ms = ((seconds % 1) * 10).floor();
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}.$ms';
    return '$s.${ms}s';
  }
}

/// Subtitle track selector for extraction.
class SubtitleTrackPanel extends StatefulWidget {
  final MediaInfo? mediaInfo;
  final int? initialTrack;
  final ValueChanged<int> onTrackChanged;

  const SubtitleTrackPanel({
    super.key,
    this.mediaInfo,
    this.initialTrack,
    required this.onTrackChanged,
  });

  @override
  State<SubtitleTrackPanel> createState() => _SubtitleTrackPanelState();
}

class _SubtitleTrackPanelState extends State<SubtitleTrackPanel> {
  late int _selectedTrack;

  @override
  void initState() {
    super.initState();
    _selectedTrack = widget.initialTrack ?? 0;
  }

  int get _trackCount {
    final langs = widget.mediaInfo?.subtitleLanguages;
    if (langs != null && langs.isNotEmpty) return langs.length;
    return 3; // Default fallback
  }

  String _trackLabel(int index) {
    final langs = widget.mediaInfo?.subtitleLanguages;
    if (langs != null && index < langs.length && langs[index].isNotEmpty) {
      return langs[index];
    }
    return '${'converter.enhance.track'.tr()} ${index + 1}';
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
            'converter.enhance.subtitleTrack'.tr(),
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(_trackCount, (i) {
              final isSelected = i == _selectedTrack;
              return ChoiceChip(
                label: Text(
                  _trackLabel(i),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
                selected: isSelected,
                selectedColor: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _selectedTrack = i);
                  widget.onTrackChanged(i);
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Interval selector for video splitting.
class SplitIntervalPanel extends StatefulWidget {
  final int? initialInterval;
  final ValueChanged<int> onIntervalChanged;

  const SplitIntervalPanel({
    super.key,
    this.initialInterval,
    required this.onIntervalChanged,
  });

  @override
  State<SplitIntervalPanel> createState() => _SplitIntervalPanelState();
}

class _SplitIntervalPanelState extends State<SplitIntervalPanel> {
  late int _interval;

  static const _presets = [15, 30, 60, 120, 300, 600];

  @override
  void initState() {
    super.initState();
    _interval = widget.initialInterval ?? 60;
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
                'converter.enhance.splitInterval'.tr(),
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _formatInterval(_interval),
                style: tt.labelSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((seconds) {
              final isSelected = seconds == _interval;
              return ChoiceChip(
                label: Text(
                  _formatInterval(seconds),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
                selected: isSelected,
                selectedColor: cs.primary,
                backgroundColor: cs.surfaceContainerHighest,
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _interval = seconds);
                  widget.onIntervalChanged(seconds);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _formatInterval(int seconds) {
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      return '$m min';
    }
    return '${seconds}s';
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _QuickBtn({required this.label, required this.onTap});

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
