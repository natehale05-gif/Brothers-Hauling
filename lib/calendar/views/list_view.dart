import 'package:flutter/material.dart';

import '../../models/job.dart';
import '../../state/app_state.dart';
import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';
import 'month_view.dart' show EventRow;

/// Everything ahead, as one running list.
///
/// Apple calls this the list view: no grid, no empty squares, just the next
/// piece of work and the one after it. On a hauling board it is the view
/// somebody actually reads in the morning.
class ScheduleView extends StatelessWidget {
  const ScheduleView({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    // From the focused day forward. A list that starts in the past is a
    // history; this one is a plan.
    final from = cal.focused;
    final ahead = events.where((e) => !dayOf(e.start).isBefore(from)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));

    // Work with no date on it. A calendar has nowhere to draw these — a job
    // booked on the website arrives without a day — and a grid that simply
    // omits them loses jobs silently. They go at the top, where somebody has
    // to deal with them.
    final undated = [
      for (final job in AppScope.of(context).jobs)
        if (job.scheduledFor == null && cal.isVisible(WorkCalendar.of(job)))
          job,
    ];

    if (ahead.isEmpty && undated.isEmpty) {
      return Container(
        color: p.bg,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Nothing booked from ${shortDate(from)} onwards.',
            textAlign: TextAlign.center,
            style: t.secondary,
          ),
        ),
      );
    }

    // Grouped under a heading per day, which is what makes a long list
    // scannable — you look for the day, not the job.
    final byDay = <DateTime, List<CalendarEvent>>{};
    for (final event in ahead) {
      byDay.putIfAbsent(dayOf(event.start), () => []).add(event);
    }
    final days = byDay.keys.toList()..sort();

    return Container(
      color: p.bg,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: days.length + (undated.isEmpty ? 0 : 1),
        itemBuilder: (context, index) {
          if (undated.isNotEmpty && index == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Heading(text: 'Not scheduled yet', colour: p.secondaryLabel),
                for (final job in undated) UndatedRow(job: job),
              ],
            );
          }

          final i = undated.isEmpty ? index : index - 1;
          final day = days[i];
          final today = sameDay(day, cal.today);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(
                text: today ? 'Today · ${longDay(day)}' : longDay(day),
                colour: today ? p.accent : p.secondaryLabel,
              ),
              for (final event in byDay[day]!) EventRow(event: event),
            ],
          );
        },
      ),
    );
  }
}

/// A day heading, or the one over the undated work.
class _Heading extends StatelessWidget {
  const _Heading({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Container(
      color: p.groupedBg,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: t.secondary.copyWith(
            fontWeight: FontWeight.w600,
            color: colour,
          ),
        ),
      ),
    );
  }
}

/// A job waiting for a date.
///
/// Shaped like an [EventRow] so the list reads as one thing, but with the
/// time replaced by what it is waiting for.
class UndatedRow extends StatelessWidget {
  const UndatedRow({super.key, required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final calendar = WorkCalendar.of(job);
    final where = job.city.isEmpty
        ? job.customer
        : '${job.customer} · ${job.city}';
    final waiting = job.status == JobStatus.requested
        ? 'Not priced yet'
        : 'No date';

    return Semantics(
      label: '${job.type} for $where. $waiting.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                // Hollow rather than solid: it has a kind of work but no
                // place on the calendar yet.
                border: Border.all(color: calendar.colour, width: 1.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    job.type,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body,
                  ),
                  Text(
                    where,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.secondary,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(waiting, style: t.secondary.copyWith(color: p.secondaryLabel)),
          ],
        ),
      ),
    );
  }
}
