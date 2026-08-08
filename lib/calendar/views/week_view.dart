import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';
import '../event_editor.dart';
import 'timed_grid.dart';

/// How far either way the week pager runs.
const int kWeekRange = 60;

/// Seven columns of hours — the view a dispatcher plans a week on.
class WeekView extends StatefulWidget {
  const WeekView({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  PageController? _pages;
  final ScrollController _hours = hourScrollController();
  int _lastIndex = kWeekRange;

  int _indexFor(DateTime day, DateTime anchor) =>
      kWeekRange + (daysBetween(anchor, weekStart(day)) ~/ 7);

  @override
  void dispose() {
    _pages?.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cal = CalendarScope.of(context);
    final anchor = weekStart(cal.today);
    final index = _indexFor(cal.focused, anchor);

    _pages ??= PageController(initialPage: index);

    if (index != _lastIndex) {
      _lastIndex = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = _pages;
        if (controller == null || !controller.hasClients) return;
        if (controller.page?.round() != index) controller.jumpToPage(index);
      });
    }

    return PageView.builder(
      controller: _pages,
      itemCount: kWeekRange * 2 + 1,
      onPageChanged: (page) {
        _lastIndex = page;
        // Keeps the weekday you were on rather than jumping to Sunday.
        final offset = daysBetween(weekStart(cal.focused), cal.focused);
        cal.focus(anchor.add(Duration(days: (page - kWeekRange) * 7 + offset)));
      },
      itemBuilder: (context, page) => _OneWeek(
        start: anchor.add(Duration(days: (page - kWeekRange) * 7)),
        events: widget.events,
        hours: _hours,
      ),
    );
  }
}

class _OneWeek extends StatelessWidget {
  const _OneWeek({
    required this.start,
    required this.events,
    required this.hours,
  });

  final DateTime start;
  final List<CalendarEvent> events;
  final ScrollController hours;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final days = [for (var i = 0; i < 7; i++) start.add(Duration(days: i))];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekHeader(days: days),
        Divider(height: 0.5, thickness: 0.5, color: p.separator),
        AllDayBand(days: days, events: events),
        Expanded(
          child: SingleChildScrollView(
            controller: hours,
            child: SizedBox(
              height: kHourHeight * 24,
              child: Stack(
                children: [
                  const HourGrid(),
                  Positioned(
                    left: kGutterWidth,
                    right: kEdgeGutter,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        for (final day in days)
                          Expanded(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: p.hairline,
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Stack(
                                children: [
                                  if (AppScope.of(context).canEditJobs)
                                    Positioned.fill(
                                      child: NewJobSlot(
                                        day: day,
                                        onNew: (at) => showEventEditor(
                                          context,
                                          startAt: at,
                                        ),
                                      ),
                                    ),
                                  DayColumn(
                                    day: day,
                                    events: eventsOn(events, day),
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.days});

  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const SizedBox(width: kGutterWidth),
          for (final day in days)
            Expanded(
              child: Builder(
                builder: (context) {
                  final today = sameDay(day, cal.today);
                  return Semantics(
                    button: true,
                    label: '${longDay(day)}${today ? ', today' : ''}',
                    onTap: () {
                      cal.focus(day);
                      cal.setView(CalView.day);
                    },
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        cal.focus(day);
                        cal.setView(CalView.day);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            weekdayShort(day).substring(0, 1),
                            style: t.weekdayHeader,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 26,
                            height: 26,
                            alignment: Alignment.center,
                            decoration: today
                                ? BoxDecoration(
                                    color: p.accent,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              '${day.day}',
                              style: t.dayNumber.copyWith(
                                fontSize: 15,
                                color: today ? p.onAccent : p.label,
                                fontWeight: today
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          // Matches the gutter the columns leave, so a heading sits over its
          // own column rather than half a column to the right of it.
          const SizedBox(width: kEdgeGutter),
        ],
      ),
    );
  }
}
