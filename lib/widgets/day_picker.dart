import 'package:flutter/material.dart';

import '../models/job.dart';
import '../state/app_state.dart';
import '../theme/haul_theme.dart';

/// The stored form of a day: an ISO timestamp, or null for no day set.
///
/// Days are held at midnight local so a job scheduled at all is scheduled to a
/// date and not to a moment. Dispatch says "Thursday", never "Thursday at
/// 14:07 because that is when I typed it".
String? dayToStored(DateTime? day) => day == null
    ? null
    : DateTime(day.year, day.month, day.day).toIso8601String();

/// Midnight local on the same day as [at], so two days can be compared.
DateTime startOfDay(DateTime at) => DateTime(at.year, at.month, at.day);

/// Whole days from [from] to [to], ignoring the time of day on either.
int daysBetween(DateTime from, DateTime to) =>
    startOfDay(to).difference(startOfDay(from)).inDays;

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Spoken in full for a screen reader, where "Wed" is read as a word.
const _weekdaysLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _monthsLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A day written the way somebody says it out loud.
///
/// Near days get their name — "Today", "Tomorrow" — because that is what makes
/// a schedule readable at a glance. Anything further off gets the weekday and
/// the date, and the year only when it is not this one.
String sayDay(DateTime? day, DateTime now) {
  if (day == null) return 'No day set';

  final gap = daysBetween(now, day);
  if (gap == 0) return 'Today';
  if (gap == 1) return 'Tomorrow';
  if (gap == -1) return 'Yesterday';

  final weekday = _weekdays[day.weekday - 1];
  final date = '$weekday ${day.day} ${_months[day.month - 1]}';
  return day.year == now.year ? date : '$date ${day.year}';
}

/// The same day, said in full for a screen reader.
String describeDay(DateTime? day, DateTime now) {
  if (day == null) return 'No day set';
  final gap = daysBetween(now, day);
  final named = switch (gap) {
    0 => 'Today, ',
    1 => 'Tomorrow, ',
    -1 => 'Yesterday, ',
    _ => '',
  };
  return '$named${_weekdaysLong[day.weekday - 1]} ${day.day} '
      '${_monthsLong[day.month - 1]} ${day.year}';
}

/// The window the calendar will open on.
///
/// Wide enough either way that a job can be backdated after the fact and
/// booked a long way out, which is the whole range a hauling board needs.
DateTime firstPickable(DateTime now) =>
    startOfDay(now).subtract(const Duration(days: 365));
DateTime lastPickable(DateTime now) =>
    startOfDay(now).add(const Duration(days: 365 * 2));

/// Opens the platform calendar on [current], or on today when nothing is set.
Future<DateTime?> pickDay(
  BuildContext context, {
  required DateTime? current,
  required DateTime now,
}) => showDatePicker(
  context: context,
  initialDate: current ?? startOfDay(now),
  firstDate: firstPickable(now),
  lastDate: lastPickable(now),
  helpText: 'PICK A DAY',
);

/// Picking a day: one line saying which day it is, and the shortcuts that
/// cover almost every change anybody actually makes.
///
/// The calendar is still there behind "Pick a date", but reaching for it is the
/// exception — most reschedules are "tomorrow" or "next week", and those are
/// one tap.
class DayField extends StatelessWidget {
  const DayField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.now,
    this.label = 'Day',
    this.helper,
  });

  /// The day currently set, or null for none.
  final DateTime? value;

  /// Called with the new day, or null when it is cleared.
  final ValueChanged<DateTime?> onChanged;

  final DateTime now;
  final String label;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);

    final today = startOfDay(now);
    final shortcuts = <(String, DateTime?)>[
      ('Today', today),
      ('Tomorrow', today.add(const Duration(days: 1))),
      ('Next week', today.add(const Duration(days: 7))),
      if (value != null) ('No day', null),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(label.toUpperCase(), style: ht.eyebrow),
        ),

        Semantics(
          button: true,
          label: '$label: ${describeDay(value, now)}. Opens a calendar.',
          onTap: () async {
            final picked = await pickDay(context, current: value, now: now);
            if (picked != null) onChanged(startOfDay(picked));
          },
          excludeSemantics: true,
          child: OutlinedButton(
            onPressed: () async {
              final picked = await pickDay(context, current: value, now: now);
              if (picked != null) onChanged(startOfDay(picked));
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, HaulSpace.tap + 6),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              side: BorderSide(color: hc.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HaulSpace.radiusSm),
              ),
              backgroundColor: hc.raised,
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 20, color: hc.brand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sayDay(value, now),
                    style: ht.body.copyWith(
                      // "No day set" is a state, not a value, so it reads as
                      // one rather than sitting there looking like a date.
                      color: value == null ? hc.inkSoft : hc.ink,
                      fontWeight: value == null
                          ? FontWeight.w400
                          : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.expand_more, size: 20, color: hc.inkSoft),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (name, day) in shortcuts)
              _DayChip(
                name: name,
                selected: day == null ? value == null : value == day,
                onTap: () => onChanged(day),
              ),
          ],
        ),

        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(helper!, style: ht.small),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);

    return Semantics(
      button: true,
      selected: selected,
      label: 'Set the day to $name',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? hc.brand : hc.raised,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? hc.brand : hc.line),
            ),
            alignment: Alignment.center,
            child: Text(
              name,
              style: ht.secondary.copyWith(
                color: selected ? hc.onBrand : hc.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moving one job to another day, without opening the whole edit form.
///
/// Changing the day is far and away the commonest correction a board takes —
/// weather, a late skip, a customer who is not in — and making it wait behind
/// twenty other fields is what turns a ten-second job into a chore.
Future<void> showMoveDaySheet(BuildContext context, Job job) {
  final state = AppScope.of(context);
  return showDialog<void>(
    context: context,
    builder: (_) => AppScope(
      state: state,
      child: _MoveDaySheet(job: job),
    ),
  );
}

class _MoveDaySheet extends StatefulWidget {
  const _MoveDaySheet({required this.job});

  final Job job;

  @override
  State<_MoveDaySheet> createState() => _MoveDaySheetState();
}

class _MoveDaySheetState extends State<_MoveDaySheet> {
  late DateTime? _day = widget.job.scheduledDay;
  bool _saving = false;

  Future<void> _save() async {
    final state = AppScope.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    // Nothing moved, so there is nothing to file — just close.
    if (_day == widget.job.scheduledDay) {
      navigator.pop();
      return;
    }

    await state.editJob(widget.job, {'scheduledFor': dayToStored(_day)});
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final hc = HaulColors.of(context);
    final ht = HaulText.of(context);
    final state = AppScope.of(context);

    return AlertDialog(
      backgroundColor: hc.surface,
      title: Text('Move ${widget.job.id}', style: ht.heading),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '${widget.job.customer} · ${widget.job.address}',
                style: ht.secondary,
              ),
            ),
            DayField(
              value: _day,
              now: state.today,
              onChanged: (day) => setState(() => _day = day),
              helper:
                  'A job with no day sits in its own bucket on the day view '
                  'rather than being guessed onto one.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: ht.action.copyWith(fontSize: 13, color: hc.inkSoft),
          ),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(
            backgroundColor: hc.brand,
            foregroundColor: hc.onBrand,
            minimumSize: const Size(0, HaulSpace.tap),
          ),
          child: Text(
            'MOVE IT',
            style: ht.action.copyWith(fontSize: 12, color: hc.onBrand),
          ),
        ),
      ],
    );
  }
}
