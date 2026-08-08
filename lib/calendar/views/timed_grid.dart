import 'package:flutter/material.dart';

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
  });

  final DateTime day;
  final List<CalendarEvent> events;

  /// A week view's columns are narrow, so the block shows less.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cal = CalendarScope.of(context);
    final placed = placeEvents(events, day);
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
                child: EventBlock(event: slot.event, compact: compact),
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

/// A job as a coloured block.
class EventBlock extends StatelessWidget {
  const EventBlock({super.key, required this.event, this.compact = false});

  final CalendarEvent event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = CalText.of(context);
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
            color: event.colour.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
            border: Border(left: BorderSide(color: event.colour, width: 3)),
          ),
          child: ClipRect(
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
                if (!compact)
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
    );
  }
}

/// The band above the hour grid, for work with a day but no time.
class AllDayBand extends StatelessWidget {
  const AllDayBand({super.key, required this.days, required this.events});

  final List<DateTime> days;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    final rows = <DateTime, List<CalendarEvent>>{
      for (final day in days)
        day: [
          for (final event in events)
            if (event.allDay && event.onDay(day)) event,
        ],
    };
    final deepest = rows.values.fold(0, (m, l) => l.length > m ? l.length : m);
    if (deepest == 0) return const SizedBox.shrink();

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
          for (final day in days)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final event in rows[day]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2, right: 2),
                      child: Semantics(
                        button: true,
                        label: 'All day. ${event.spoken}',
                        onTap: () => cal.openEvent(event.id),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => cal.openEvent(event.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
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
                    ),
                  // Keeps every column the same height when one day has more
                  // all-day work than its neighbours.
                  for (var i = rows[day]!.length; i < deepest; i++)
                    const SizedBox(height: 20),
                ],
              ),
            ),
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
