import 'package:flutter/material.dart';

import '../models/job.dart';
import 'date_math.dart';

/// How long a job takes when nobody has said.
///
/// A calendar has to draw a block, and a block needs an end. Two hours is the
/// middle of what a haul actually runs; the alternative — refusing to draw it —
/// loses the job off the screen entirely.
const Duration kAssumedJobLength = Duration(hours: 2);

/// The palette the rigs are coloured from. iOS's own system colours.
///
/// Grey is deliberately last: it is where [kNoRig] lands most of the time and
/// it reads as "not decided" next to the others.
const List<Color> kRigColours = [
  Color(0xFFFF9500), // orange
  Color(0xFFFF2D55), // pink
  Color(0xFF5856D6), // indigo
  Color(0xFF34C759), // green
  Color(0xFF007AFF), // blue
  Color(0xFFAF52DE), // purple
  Color(0xFF00C7BE), // teal
  Color(0xFFFF3B30), // red
  Color(0xFF8E8E93), // grey
];

/// Spreads a rig's name across [kRigColours], the same way every time.
///
/// FNV-1a rather than [Object.hashCode], which Dart does not promise to keep
/// stable between releases or across platforms. A trailer that is orange on
/// the office iPad and green on a driver's phone is worse than no colour at
/// all — the whole point is that a glance at either says the same thing.
int _spread(String key) {
  var hash = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

/// The colour sets a calendar is grouped by — one per rig.
///
/// Apple Calendar calls these calendars and gives each a colour. Here they are
/// the rigs, which is what a yard actually schedules: there is one dump trailer
/// and it can only be in one place at nine o'clock. There used to be a "kind of
/// work" beside this — debris haul, gravel delivery — and it was the same fact
/// written twice, because what goes on the truck is what the job is.
///
/// Not an enum any more, for the same reason the rig field is free text: a yard
/// buys a trailer without waiting for a new build.
@immutable
class WorkCalendar {
  const WorkCalendar(this.label);

  /// The rig, as it is written on the job.
  final String label;

  /// What two spellings of the same trailer are matched on.
  String get key => label.trim().toLowerCase();

  /// Stable for the life of the name, and the same on every device.
  Color get colour => kRigColours[_spread(key) % kRigColours.length];

  /// Which set a job belongs to: the first rig on it.
  ///
  /// First rather than all of them, because a block on a grid is one colour. A
  /// job needing a trailer and a skid steer is drawn as the trailer's — and it
  /// still stands in both lanes of the day sheet, which is the screen that
  /// exists to answer "what is each rig doing today".
  static WorkCalendar of(Job job) =>
      WorkCalendar(job.equipment.isEmpty ? kNoRig : job.equipment.first);

  @override
  bool operator ==(Object other) => other is WorkCalendar && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'WorkCalendar($label)';
}

/// Every rig the given work needs, in one order, alphabetically.
///
/// The same order the day sheet rules its lanes in, so a rig is in the same
/// place on both screens.
List<WorkCalendar> calendarsFrom(Iterable<Job> jobs) {
  final seen = <String, WorkCalendar>{};
  for (final job in jobs) {
    for (final rig in job.equipment.isEmpty ? const [kNoRig] : job.equipment) {
      final calendar = WorkCalendar(rig);
      seen.putIfAbsent(calendar.key, () => calendar);
    }
  }
  return seen.values.toList()..sort((a, b) => a.key.compareTo(b.key));
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

  /// What the job is called: the rig it takes.
  String get title => job.title;

  String get subtitle => job.customer;
  Color get colour => calendar.colour;

  /// The job's notes, flattened onto one line.
  ///
  /// Gate codes, which drive to use, dogs on site, do not back down the hill.
  /// Shown on the block and on the row rather than only inside the job,
  /// because it is what a driver needs before they set off and what dispatch
  /// is asked about on the phone — and neither should have to open a job and
  /// scroll to find it.
  String get notes => job.access.replaceAll(RegExp(r'\s+'), ' ').trim();

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
  ///
  /// The notes are read out too. They are on the block for everybody else, and
  /// leaving them off here would be the one case where looking at the calendar
  /// tells you more than listening to it.
  String get spoken {
    final when = allDay ? 'All day' : timeRange(start, end);
    final where = job.city.isEmpty ? '' : ' in ${job.city}';
    return '$title for $subtitle$where. $when.'
        '${notes.isEmpty ? '' : ' $notes'}';
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

/// The rigs working a day, in a fixed order.
///
/// Alphabetical rather than by whatever happens to start first, so a column
/// does not change place when a job moves.
///
/// All-day work counts. It is never drawn in the hour grid, but it is drawn in
/// the band above it, and the two have to agree on what the columns are — a rig
/// that is only ever booked as "sometime Thursday" still needs somewhere to
/// sit, and its column standing empty below the band is the honest picture of a
/// day with nothing timed in it.
List<WorkCalendar> calendarsOn(List<CalendarEvent> events, DateTime day) {
  final seen = <String, WorkCalendar>{};
  for (final event in events) {
    if (event.onDay(day)) {
      seen.putIfAbsent(event.calendar.key, () => event.calendar);
    }
  }
  return seen.values.toList()..sort((a, b) => a.key.compareTo(b.key));
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
///
/// A kind whose only work today is all-day gets a column with nothing in it.
/// That is deliberate: the band above the grid draws that job over this
/// column, and it would sit over the wrong kind if the grid quietly dropped
/// the empty one.
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
