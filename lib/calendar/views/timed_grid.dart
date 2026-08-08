import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';

/// Pixels per hour in a day or week view.
///
/// Apple's is around this: tall enough that a one-hour block fits two lines of
/// text, short enough that a working day is roughly one screen.
const double kHourHeight = 52;

/// The width of the hour labels down the left.
const double kGutterWidth = 56;

/// The breathing room left down the right of a timed grid, so a block never
/// runs into the edge of the screen.
const double kEdgeGutter = 4;

/// Which quarter hour a vertical offset lands on.
///
/// Snapped to fifteen minutes: nobody books a haul at 9:07, and a grid that
/// let them would make every block sit a pixel off its neighbours.
DateTime timeAt(DateTime day, double dy, {int snap = 15}) {
  final minutes = (dy / kHourHeight * 60).clamp(0, 24 * 60 - snap);
  final rounded = (minutes / snap).round() * snap;
  return dayOf(day).add(Duration(minutes: rounded));
}

/// Books a job at whatever time the grid was tapped.
///
/// Apple's day view creates an event where you tap, and so does this — the
/// alternative is a form that opens on the wrong hour every time.
class NewJobSlot extends StatelessWidget {
  const NewJobSlot({super.key, required this.day, required this.onNew});

  final DateTime day;
  final void Function(DateTime at) onNew;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) => onNew(timeAt(day, details.localPosition.dy)),
      // No semantics of its own: a screen reader gets the New job button in
      // the bar, and an invisible full-height target announcing itself over
      // the whole day would bury every block underneath it.
      child: const SizedBox.expand(),
    );
  }
}

/// The hour rules and their labels — the paper a day is drawn on.
class HourGrid extends StatelessWidget {
  const HourGrid({super.key, this.showLabels = true});

  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Column(
      children: [
        for (var hour = 0; hour < 24; hour++)
          SizedBox(
            height: kHourHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: kGutterWidth,
                  child: showLabels && hour > 0
                      ? Transform.translate(
                          // Centred on the rule rather than sitting under it,
                          // which is what makes the label read as belonging to
                          // the line and not to the hour below it.
                          offset: const Offset(0, -6),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              hourLabel(hour),
                              textAlign: TextAlign.right,
                              style: t.hourLabel,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(child: Container(height: 0.5, color: p.hairline)),
              ],
            ),
          ),
      ],
    );
  }
}

/// The red line across now, with its dot.
///
/// Only drawn on a column that is actually today — a now-line on next Tuesday
/// is the kind of detail that makes a calendar feel wrong without anybody
/// being able to say why.
class NowLine extends StatelessWidget {
  const NowLine({super.key, required this.showDot});

  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);

    return IgnorePointer(
      child: Row(
        children: [
          if (showDot)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
          Expanded(child: Container(height: 2, color: p.accent)),
        ],
      ),
    );
  }
}

/// One day's worth of timed blocks, positioned over the hour grid.
class DayColumn extends StatelessWidget {
  const DayColumn({
    super.key,
    required this.day,
    required this.events,
    this.compact = false,
    this.byCalendar = false,
  });

  final DateTime day;
  final List<CalendarEvent> events;

  /// A week view's columns are narrow, so the block shows less.
  final bool compact;

  /// A column per kind of work rather than one shared column that only splits
  /// where jobs collide. The day view reads across as well as down this way;
  /// a week view has no room for it, its columns already being the days.
  final bool byCalendar;

  @override
  Widget build(BuildContext context) {
    final cal = CalendarScope.of(context);
    final placed = byCalendar
        ? placeByCalendar(events, day)
        : placeEvents(events, day);
    final isToday = sameDay(day, cal.today);
    final now = cal.now;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final minute = kHourHeight / 60;

        return Stack(
          children: [
            for (final slot in placed)
              Positioned(
                top: slot.event.topMinutes(day) * minute,
                left: slot.left * width,
                width: slot.width * width - 2,
                height: slot.event.lengthMinutes(day) * minute - 2,
                child: DraggableBlock(
                  event: slot.event,
                  day: day,
                  compact: compact,
                ),
              ),
            if (isToday)
              Positioned(
                top: (now.hour * 60 + now.minute) * minute - 1,
                left: -4,
                right: 0,
                child: const NowLine(showDot: true),
              ),
          ],
        );
      },
    );
  }
}

/// The height of the grab handle along the bottom of a block.
const double kResizeGrip = 14;

/// A block you can pick up and move, or take by the bottom edge and stretch.
///
/// Long press first, the way Apple's does: a calendar you can knock a job off
/// by brushing it while scrolling is worse than one you cannot drag at all.
/// Nothing moves until the press is held, and the block lifts to say so.
class DraggableBlock extends StatefulWidget {
  const DraggableBlock({
    super.key,
    required this.event,
    required this.day,
    this.compact = false,
  });

  final CalendarEvent event;
  final DateTime day;
  final bool compact;

  @override
  State<DraggableBlock> createState() => _DraggableBlockState();
}

class _DraggableBlockState extends State<DraggableBlock> {
  /// Minutes the block has been dragged, before snapping.
  double _shift = 0;

  /// Minutes added to the length while stretching the bottom edge.
  double _stretch = 0;

  bool _moving = false;
  bool _resizing = false;

  static const int _snap = 15;

  int get _snapped => (_shift / _snap).round() * _snap;
  int get _snappedStretch => (_stretch / _snap).round() * _snap;

  double get _pixelsPerMinute => kHourHeight / 60;

  /// Where the block would land, as words, for the label while dragging.
  DateTime get _wouldStart =>
      widget.event.start.add(Duration(minutes: _snapped));

  Future<void> _commitMove() async {
    // Read where it landed before letting go of the drag: clearing the offset
    // first would move the job to exactly where it already was.
    final minutes = _snapped;
    final target = _wouldStart;
    setState(() {
      _moving = false;
      _shift = 0;
    });
    if (minutes == 0) return;

    final app = AppScope.read(context);
    await app.rescheduleJob(widget.event.job, startsAt: target);
  }

  Future<void> _commitResize() async {
    final added = _snappedStretch;
    setState(() {
      _resizing = false;
      _stretch = 0;
    });
    if (added == 0) return;

    final was = widget.event.end.difference(widget.event.start).inMinutes;
    final now = was + added;
    final app = AppScope.read(context);
    await app.rescheduleJob(
      widget.event.job,
      startsAt: widget.event.start,
      // A quarter hour is the floor: below that a block cannot show its own
      // name, and the grid draws it at that height anyway.
      minutes: now < 15 ? 15 : now,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cal = CalendarScope.of(context);
    final movable = app.canEditJobs && !widget.event.allDay;
    final dragging = _moving || _resizing;

    // While it is being dragged the block says where it would land, because
    // the grid underneath it is hidden by the finger doing the dragging.
    final String? note;
    if (_moving) {
      note = clockLabel(_wouldStart);
    } else if (_resizing) {
      final end = widget.event.end.add(Duration(minutes: _snappedStretch));
      note = timeRange(widget.event.start, end);
    } else {
      note = null;
    }

    final block = EventBlock(
      event: widget.event,
      compact: widget.compact,
      lifted: dragging,
      note: note,
    );

    if (!movable) return block;

    return Transform.translate(
      offset: Offset(0, _moving ? _snapped * _pixelsPerMinute : 0),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => cal.openEvent(widget.event.id),
              onLongPressStart: (_) => setState(() {
                _moving = true;
                _shift = 0;
              }),
              onLongPressMoveUpdate: (details) => setState(
                () => _shift = details.offsetFromOrigin.dy / _pixelsPerMinute,
              ),
              onLongPressEnd: (_) => _commitMove(),
              onLongPressCancel: () => setState(() {
                _moving = false;
                _shift = 0;
              }),
              child: const SizedBox.expand(),
            ),
          ),
          // The block itself is drawn under the gesture layer so the whole of
          // it is grabbable, not just the parts without text on them.
          Positioned.fill(child: IgnorePointer(child: block)),
          // The bottom edge, for changing how long it runs. Small, and only
          // ever on a block tall enough to have an edge worth grabbing.
          if (!_moving)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: kResizeGrip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // Measured from where the finger first landed rather than
                // from where the drag was recognised, so the twenty-odd
                // pixels of slop are not silently thrown away — on a grip
                // that is a quarter of an hour the edge did not follow.
                dragStartBehavior: DragStartBehavior.down,
                onVerticalDragStart: (_) => setState(() {
                  _resizing = true;
                  _stretch = 0;
                }),
                onVerticalDragUpdate: (details) => setState(
                  () => _stretch += details.delta.dy / _pixelsPerMinute,
                ),
                onVerticalDragEnd: (_) => _commitResize(),
                onVerticalDragCancel: () => setState(() {
                  _resizing = false;
                  _stretch = 0;
                }),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: _Grip(showing: _resizing),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The little bar that says an edge can be taken hold of.
class _Grip extends StatelessWidget {
  const _Grip({required this.showing});

  final bool showing;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Container(
        width: 26,
        height: 3,
        decoration: BoxDecoration(
          color: showing ? p.accent : p.secondaryLabel.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// A job as a coloured block.
class EventBlock extends StatelessWidget {
  const EventBlock({
    super.key,
    required this.event,
    this.compact = false,
    this.lifted = false,
    this.note,
  });

  final CalendarEvent event;
  final bool compact;

  /// Being dragged: raised off the grid, so it reads as picked up.
  final bool lifted;

  /// Shown in place of the subtitle while dragging — where it would land.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = CalText.of(context);
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);

    return Semantics(
      button: true,
      label: event.spoken,
      onTap: () => cal.openEvent(event.id),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => cal.openEvent(event.id),
        child: Container(
          padding: EdgeInsets.fromLTRB(compact ? 3 : 6, 2, 3, 2),
          decoration: BoxDecoration(
            // A tinted fill with a solid bar down the leading edge, which is
            // how Apple draws one and why a block reads at a glance even when
            // it is too short for its own text.
            color: event.colour.withValues(alpha: lifted ? 0.32 : 0.18),
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: event.colour, width: 3)),
            boxShadow: lifted
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          // A quarter-hour block is barely taller than one line of text. The
          // overflow box lets the label be as tall as it needs and the clip
          // trims what will not fit, which is what "draw as much as there is
          // room for" has to mean — a Column alone would report an overflow
          // and paint a stripe across the grid instead.
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              maxHeight: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.eventTitle.copyWith(color: event.colour),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.eventDetail.copyWith(
                        color: p.label,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else if (!compact)
                    Text(
                      event.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.eventDetail,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The band above the hour grid, for work with a day but no time.
class AllDayBand extends StatelessWidget {
  const AllDayBand({
    super.key,
    required this.days,
    required this.events,
    this.kinds,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;

  /// Lay one day's all-day work out in a column per kind, lining up with the
  /// grid underneath, instead of stacking it into one wide list.
  ///
  /// Null in a week view, whose columns are already the days and which has no
  /// width left to divide again.
  final List<WorkCalendar>? kinds;

  @override
  Widget build(BuildContext context) {
    final columns = kinds;
    if (columns != null && days.length == 1) {
      // No all-day work, no band — not an empty strip with a label on it.
      if (_allDayOn(days.single).isEmpty) return const SizedBox.shrink();
      return _shell(context, _byKind(days.single, columns));
    }

    final rows = <DateTime, List<CalendarEvent>>{
      for (final day in days) day: _allDayOn(day),
    };
    final deepest = rows.values.fold(0, (m, l) => l.length > m ? l.length : m);
    if (deepest == 0) return const SizedBox.shrink();

    return _shell(context, [
      for (final day in days)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final event in rows[day]!) AllDayChip(event: event),
                // Keeps every column the same height when one day has more
                // all-day work than its neighbours.
                for (var i = rows[day]!.length; i < deepest; i++)
                  const SizedBox(height: 20),
              ],
            ),
          ),
        ),
    ]);
  }

  List<CalendarEvent> _allDayOn(DateTime day) => [
    for (final event in events)
      if (event.allDay && event.onDay(day)) event,
  ];

  /// One day's all-day work, a column per kind.
  ///
  /// The columns are the same ones the grid below is drawn in, edge gutter and
  /// all, so a job booked as "sometime Thursday" sits over the hours its own
  /// kind of work would have run in. Two of the same kind still stack, because
  /// they are the same column — but that is one bar over another bar of the
  /// same colour, which reads as two of a thing rather than as a wall.
  List<Widget> _byKind(DateTime day, List<WorkCalendar> columns) {
    final onDay = _allDayOn(day);
    return [
      for (final kind in columns)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final event in onDay)
                  if (event.calendar == kind) AllDayChip(event: event),
              ],
            ),
          ),
        ),
      const SizedBox(width: kEdgeGutter),
    ];
  }

  /// The gutter label and the rule underneath, around whatever the columns are.
  Widget _shell(BuildContext context, List<Widget> columns) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.separator, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: kGutterWidth,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              // For the eye only. Each chip already announces "All day", and
              // leaving this in the tree makes a screen reader say it twice
              // before it gets to the job.
              child: ExcludeSemantics(
                child: Text(
                  'all-day',
                  textAlign: TextAlign.right,
                  style: t.hourLabel,
                ),
              ),
            ),
          ),
          ...columns,
        ],
      ),
    );
  }
}

/// One all-day job, as a solid bar.
class AllDayChip extends StatelessWidget {
  const AllDayChip({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        label: 'All day. ${event.spoken}',
        onTap: () => cal.openEvent(event.id),
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => cal.openEvent(event.id),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: event.colour,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.eventTitle.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// Names the columns a day has been split into, and rules between them.
///
/// Without it the columns are unlabelled and their number changes with the
/// day, which is the difference between a layout that tells you something and
/// one you have to decode. A day of one kind needs no header, and the caller
/// leaves it out rather than this drawing nothing — one place decides.
class CalendarColumnHeader extends StatelessWidget {
  const CalendarColumnHeader({super.key, required this.kinds});

  final List<WorkCalendar> kinds;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.separator, width: 0.5)),
      ),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: kGutterWidth),
          for (final kind in kinds)
            Expanded(
              child: Semantics(
                label: '${kind.label} column',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(height: 2, color: kind.colour),
                      const SizedBox(height: 3),
                      Text(
                        kind.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: t.weekdayHeader.copyWith(color: kind.colour),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(width: kEdgeGutter),
        ],
      ),
    );
  }
}

/// Scrolls an hour grid so the working day is on screen when it opens.
///
/// Seven in the morning rather than midnight: a hauling day starts early, and
/// a calendar that opens on eight hours of empty night is one somebody has to
/// scroll before they can use it.
ScrollController hourScrollController({int openAt = 7}) =>
    ScrollController(initialScrollOffset: openAt * kHourHeight);
