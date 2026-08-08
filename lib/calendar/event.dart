import 'package:flutter/material.dart';

import '../models/job.dart';
import 'date_math.dart';

/// How long a job takes when nobody has said.
///
/// A calendar has to draw a block, and a block needs an end. Two hours is the
/// middle of what a haul actually runs; the alternative — refusing to draw it —
/// loses the job off the screen entirely.
const Duration kAssumedJobLength = Duration(hours: 2);

/// The colour sets a calendar is grouped by.
///
/// Apple Calendar calls these calendars and gives each a colour; here they are
/// the kinds of work, which is the grouping somebody running a yard actually
/// thinks in. The colours are iOS's own system palette.
enum WorkCalendar {
  debris('Debris haul', Color(0xFFFF9500)),
  junk('Junk removal', Color(0xFFFF2D55)),
  gravel('Gravel delivery', Color(0xFF5856D6)),
  bark('Bark & soil', Color(0xFF34C759)),
  equipment('Equipment move', Color(0xFF007AFF)),
  other('Other work', Color(0xFF8E8E93));

  const WorkCalendar(this.label, this.colour);

  final String label;
  final Color colour;

  /// Which set a job belongs to, matched on its type.
  ///
  /// Falls through to [other] rather than guessing: a new kind of work should
  /// appear in grey on the calendar, not silently borrow another kind's colour
  /// and make two things look like one.
  static WorkCalendar of(Job job) {
    final type = job.type.trim().toLowerCase();
    for (final calendar in values) {
      if (calendar != other && calendar.label.toLowerCase() == type) {
        return calendar;
      }
    }
    return other;
  }
}

/// A job, as a calendar draws it.
///
/// Deliberately a view over [Job] rather than a second model. There is one
/// record of a job and it lives in the domain; this is the thing that knows a
/// block has a top and a height.
@immutable
class CalendarEvent {
  const CalendarEvent({
    required this.job,
    required this.start,
    required this.end,
    required this.calendar,
    required this.allDay,
  });

  final Job job;
  final DateTime start;
  final DateTime end;
  final WorkCalendar calendar;

  /// A job with no time on it, only a day.
  ///
  /// Real: dispatch books plenty of work as "Thursday" long before anybody
  /// says when. Those ride the all-day band rather than being pinned to
  /// midnight, which is where a naive calendar puts them and where nobody
  /// looks.
  final bool allDay;

  String get id => job.id;
  String get title => job.type;
  String get subtitle => job.customer;
  Color get colour => calendar.colour;

  Duration get length => end.difference(start);

  /// Builds the event for a job, or null when it has no day at all.
  ///
  /// A job nobody has scheduled is a real thing — it belongs on a list of work
  /// waiting for a date, not on a square of the grid.
  static CalendarEvent? of(Job job) {
    final at = job.scheduledFor;
    if (at == null) return null;

    // Midnight exactly is how a day-only booking arrives — the day picker
    // stores days at midnight on purpose. Anything else is a real time.
    final timed = at.hour != 0 || at.minute != 0;
    // A job that has been given a length uses it; one nobody has said falls
    // back to the assumption rather than refusing to draw a block.
    final runs = job.minutes == null
        ? kAssumedJobLength
        : Duration(minutes: job.minutes!);
    return CalendarEvent(
      job: job,
      start: at,
      end: timed ? at.add(runs) : dayOf(at),
      calendar: WorkCalendar.of(job),
      allDay: !timed,
    );
  }

  /// Does this event touch [day] at all?
  bool onDay(DateTime day) {
    if (allDay) return sameDay(start, day);
    final from = dayOf(day);
    final to = from.add(const Duration(days: 1));
    return start.isBefore(to) && end.isAfter(from);
  }

  /// Minutes from midnight to the start, clamped into the day.
  double topMinutes(DateTime day) {
    final from = dayOf(day);
    final offset = start.difference(from).inMinutes.toDouble();
    return offset.clamp(0, 24 * 60);
  }

  /// How many minutes of this event fall on [day].
  ///
  /// Clamped so an overnight job draws to the bottom of one day rather than
  /// off the end of it, and so a very short one is still tall enough to read.
  double lengthMinutes(DateTime day) {
    final from = dayOf(day);
    final to = from.add(const Duration(days: 1));
    final begin = start.isBefore(from) ? from : start;
    final finish = end.isAfter(to) ? to : end;
    final minutes = finish.difference(begin).inMinutes.toDouble();
    return minutes < 15 ? 15 : minutes;
  }

  /// What a screen reader reads instead of a coloured rectangle.
  String get spoken {
    final when = allDay ? 'All day' : timeRange(start, end);
    final where = job.city.isEmpty ? '' : ' in ${job.city}';
    return '$title for $subtitle$where. $when.';
  }
}

/// Every job that has a day, as events.
List<CalendarEvent> eventsFrom(Iterable<Job> jobs) => [
  for (final job in jobs) ?CalendarEvent.of(job),
];

/// The events on one day, in the order the day happens.
///
/// All-day work first, then by start time — which is what the eye expects and
/// what makes a column of blocks readable top to bottom.
List<CalendarEvent> eventsOn(List<CalendarEvent> events, DateTime day) {
  final out = events.where((e) => e.onDay(day)).toList()
    ..sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });
  return out;
}

/// Where a block sits across the width of a day column.
///
/// Two jobs at nine o'clock have to share the column, and the arithmetic for
/// that is the only genuinely fiddly part of drawing a calendar: events are
/// grouped into runs that overlap transitively, then each run is divided into
/// as many lanes as its worst pile-up needs.
class Placed {
  const Placed({
    required this.event,
    required this.lane,
    required this.lanes,
    this.leftOverride,
    this.widthOverride,
  });

  final CalendarEvent event;

  /// Which column within the group, from zero.
  final int lane;

  /// How many columns the group was split into.
  final int lanes;

  /// Set only when a layout divides the width unevenly — a column per kind of
  /// work, where one kind may be split again inside its own column and another
  /// may not. Even lanes leave these null and derive their fractions from
  /// [lane] and [lanes].
  final double? leftOverride;
  final double? widthOverride;

  double get left => leftOverride ?? lane / lanes;
  double get width => widthOverride ?? 1 / lanes;
}

/// Lays timed events out into lanes so overlapping work sits side by side.
List<Placed> placeEvents(List<CalendarEvent> events, DateTime day) {
  final timed = events.where((e) => !e.allDay && e.onDay(day)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  if (timed.isEmpty) return const [];

  final out = <Placed>[];
  var group = <CalendarEvent>[];
  DateTime? groupEnd;

  void flush() {
    if (group.isEmpty) return;
    // Within a group, walk the events in order and drop each into the first
    // lane whose last event has already finished.
    final laneEnds = <DateTime>[];
    final laneOf = <int>[];
    for (final event in group) {
      var lane = laneEnds.indexWhere((end) => !end.isAfter(event.start));
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(event.end);
      } else {
        laneEnds[lane] = event.end;
      }
      laneOf.add(lane);
    }
    final lanes = laneEnds.length;
    for (var i = 0; i < group.length; i++) {
      out.add(Placed(event: group[i], lane: laneOf[i], lanes: lanes));
    }
    group = [];
    groupEnd = null;
  }

  for (final event in timed) {
    // A gap with nothing running ends the group: what happens after it cannot
    // overlap anything before it, so it starts its own full-width run.
    if (groupEnd != null && !event.start.isBefore(groupEnd!)) flush();
    group.add(event);
    groupEnd = groupEnd == null || event.end.isAfter(groupEnd!)
        ? event.end
        : groupEnd;
  }
  flush();

  return out;
}

/// The kinds of work on a day, in the calendar's own order.
///
/// Order comes from [WorkCalendar.values] rather than from what happens to
/// start first, so a column does not change place when a job moves.
List<WorkCalendar> calendarsOn(List<CalendarEvent> events, DateTime day) {
  final timed = events.where((e) => !e.allDay && e.onDay(day));
  return [
    for (final calendar in WorkCalendar.values)
      if (timed.any((e) => e.calendar == calendar)) calendar,
  ];
}

/// Lays a day out with a column per kind of work.
///
/// Different from [placeEvents], which only splits a column when two jobs
/// actually collide. Here every kind gets its own column whether or not
/// anything overlaps, so a day reads across as well as down: all the gravel is
/// one line of the page, all the junk another, and a glance says what sort of
/// day it is before you have read a single time.
///
/// Two jobs of the same kind at the same time still cannot be drawn on top of
/// each other, so a column splits again inside itself — which is why the
/// fractions are worked out here rather than left to lane arithmetic that
/// assumes every column is the same width.
List<Placed> placeByCalendar(List<CalendarEvent> events, DateTime day) {
  final timed = events.where((e) => !e.allDay && e.onDay(day)).toList();
  if (timed.isEmpty) return const [];

  final kinds = calendarsOn(events, day);
  final columnWidth = 1 / kinds.length;

  final out = <Placed>[];
  for (var i = 0; i < kinds.length; i++) {
    final column = [
      for (final event in timed)
        if (event.calendar == kinds[i]) event,
    ];
    for (final slot in placeEvents(column, day)) {
      out.add(
        Placed(
          event: slot.event,
          lane: i,
          lanes: kinds.length,
          leftOverride: i * columnWidth + slot.lane * columnWidth / slot.lanes,
          widthOverride: columnWidth / slot.lanes,
        ),
      );
    }
  }
  return out;
}
