import 'package:flutter/material.dart';
import '../../../../core/core.dart';
import '../../domain/entities/recurrence_rule.dart';

/// Result type returned by [SchedulePickerDialog.show].
typedef ScheduleResult = ({DateTime dateTime, RecurrenceRule recurrence});

/// Dialog for picking a scheduled start date/time and optional recurrence rule.
///
/// Returns a [ScheduleResult] when the user confirms, or null when cancelled.
class SchedulePickerDialog extends StatefulWidget {
  final DateTime? initialDateTime;

  const SchedulePickerDialog({this.initialDateTime, super.key});

  /// Convenience method: shows the dialog and returns the picked [ScheduleResult].
  static Future<ScheduleResult?> show(
    BuildContext context, {
    DateTime? initialDateTime,
  }) {
    return showDialog<ScheduleResult?>(
      context: context,
      builder: (_) => SchedulePickerDialog(initialDateTime: initialDateTime),
    );
  }

  @override
  State<SchedulePickerDialog> createState() => _SchedulePickerDialogState();
}

class _SchedulePickerDialogState extends State<SchedulePickerDialog> {
  late DateTime _selected;
  RecurrenceType _recurrenceType = RecurrenceType.none;
  Set<int> _selectedDays = {}; // ISO weekdays: 1=Mon..7=Sun

  static const _dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _dayValues = [1, 2, 3, 4, 5, 6, 7];

  @override
  void initState() {
    super.initState();
    // Default to 1 hour from now, rounded to the next 5-minute mark.
    final now = DateTime.now();
    _selected = widget.initialDateTime ??
        DateTime(
          now.year,
          now.month,
          now.day,
          now.hour + 1,
          (now.minute ~/ 5 + 1) * 5 % 60,
        );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _selected = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selected.hour,
        _selected.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selected),
    );
    if (picked == null) return;
    setState(() {
      _selected = DateTime(
        _selected.year,
        _selected.month,
        _selected.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  String _formatDate() {
    final d = _selected;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatTime() {
    final d = _selected;
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  bool get _isInPast => _selected.isBefore(DateTime.now());

  RecurrenceRule get _buildRecurrenceRule {
    switch (_recurrenceType) {
      case RecurrenceType.none:
        return RecurrenceRule.none;
      case RecurrenceType.weekly:
        return RecurrenceRule(type: _recurrenceType, daysOfWeek: Set.from(_selectedDays));
      default:
        return RecurrenceRule(type: _recurrenceType);
    }
  }

  void _confirm() {
    Navigator.pop(context, (dateTime: _selected, recurrence: _buildRecurrenceRule));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      backgroundColor: isDark ? AppColors.darkSurface1 : AppColors.lightElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: isDark ? BorderSide(color: AppColors.darkElevated) : BorderSide.none,
      ),
      title: Text(AppLocalizations.scheduleTitle),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, size: 20),
              title: Text(_formatDate()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            ),
            // Time row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.access_time, size: 20),
              title: Text(_formatTime()),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickTime,
            ),
            if (_isInPast)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Scheduled time is in the past.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),

            const Divider(),

            // Recurrence section
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.sm),
              child: Text(
                'Repeat',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            _RecurrenceSelector(
              selected: _recurrenceType,
              onChanged: (t) => setState(() {
                _recurrenceType = t;
                if (t == RecurrenceType.weekly && _selectedDays.isEmpty) {
                  _selectedDays = {_selected.weekday};
                }
              }),
            ),

            // Day-of-week chips (only for weekly)
            if (_recurrenceType == RecurrenceType.weekly) ...[
              const SizedBox(height: AppSpacing.smMd),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (int i = 0; i < 7; i++)
                    _DayChip(
                      label: _dayLabels[i],
                      selected: _selectedDays.contains(_dayValues[i]),
                      onTap: () => setState(() {
                        final day = _dayValues[i];
                        if (_selectedDays.contains(day)) {
                          if (_selectedDays.length > 1) _selectedDays.remove(day);
                        } else {
                          _selectedDays.add(day);
                        }
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
          ),
          onPressed: _isInPast ? null : _confirm,
          child: Text(AppLocalizations.scheduleAction),
        ),
      ],
    );
  }
}

/// Horizontal segmented selector for recurrence type.
class _RecurrenceSelector extends StatelessWidget {
  final RecurrenceType selected;
  final ValueChanged<RecurrenceType> onChanged;

  const _RecurrenceSelector({required this.selected, required this.onChanged});

  static List<({String label, RecurrenceType type})> get _options => [
    (label: AppLocalizations.scheduleRecurrenceNone, type: RecurrenceType.none),
    (label: AppLocalizations.scheduleRecurrenceDaily, type: RecurrenceType.daily),
    (label: AppLocalizations.scheduleRecurrenceWeekdays, type: RecurrenceType.weekdays),
    (label: AppLocalizations.scheduleRecurrenceWeekends, type: RecurrenceType.weekends),
    (label: AppLocalizations.scheduleRecurrenceCustom, type: RecurrenceType.weekly),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        for (final opt in _options)
          GestureDetector(
            onTap: () => onChanged(opt.type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smMd),
              decoration: BoxDecoration(
                color: selected == opt.type
                    ? AppColors.brand
                    : isDark
                        ? AppColors.darkSurface1.withValues(alpha: AppOpacity.medium)
                        : AppColors.lightSurface2,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: selected == opt.type
                    ? null
                    : Border.all(
                        color: isDark
                            ? AppColors.darkElevated
                            : cs.outlineVariant.withValues(alpha: AppOpacity.overlay),
                      ),
              ),
              alignment: Alignment.center,
              child: Text(
                opt.label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: selected == opt.type
                          ? Colors.white
                          : cs.onSurface.withValues(alpha: AppOpacity.strong),
                      fontWeight: selected == opt.type ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 12,
                    ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small circular day toggle chip used for weekly day selection.
class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DayChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.brand : Colors.transparent,
          border: Border.all(
            color: selected
                ? AppColors.brand
                : isDark
                    ? AppColors.darkElevated
                    : Theme.of(context).colorScheme.outline,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}
