import 'package:flutter/material.dart';

import '../../state/app_state.dart';
import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';
import '../event_editor.dart';
import 'timed_grid.dart';

/// How far either way the day pager runs.
const int kDayRange = 400;

/// One day, hour by hour, with the week strip along the top.
class DayView extends StatefulWidget {
  const DayView({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  State<DayView> createState() => _DayViewState();
}

class _DayViewState extends State<DayView> {
  PageController? _pages;
  final ScrollController _hours = hourScrollController();
  int _lastIndex = kDayRange;

  @override
  void dispose() {
    _pages?.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final index = kDayRange + daysBetween(cal.today, cal.focused);

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WeekStrip(),
        Divider(height: 0.5, thickness: 0.5, color: p.separator),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: kDayRange * 2 + 1,
            onPageChanged: (page) {
              _lastIndex = page;
              cal.focus(cal.today.add(Duration(days: page - kDayRange)));
            },
            itemBuilder: (context, page) => _OneDay(
              day: cal.today.add(Duration(days: page - kDayRange)),
              events: widget.events,
              hours: _hours,
            ),
          ),
        ),
      ],
    );
  }
}

/// The seven days around the focused one, as a row of numbers.
///
/// Apple puts this above the day view so a day is never more than one tap
/// away, and so the day you are on has a context.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);
    final days = weekDays(cal.focused);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (final day in days)
            Expanded(
              child: Builder(
                builder: (context) {
                  final selected = sameDay(day, cal.focused);
                  final today = sameDay(day, cal.today);
                  return Semantics(
                    button: true,
                    selected: selected,
                    label: '${longDay(day)}${today ? ', today' : ''}',
                    onTap: () => cal.focus(day),
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => cal.focus(day),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            weekdayShort(day).substring(0, 1),
                            style: t.weekdayHeader,
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: selected
                                ? BoxDecoration(
                                    color: today ? p.accent : p.label,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              '${day.day}',
                              style: t.dayNumber.copyWith(
                                fontSize: 16,
                                color: selected
                                    ? (today ? p.onAccent : p.bg)
                                    : (today ? p.accent : p.label),
                                fontWeight: today || selected
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
        ],
      ),
    );
  }
}

class _OneDay extends StatelessWidget {
  const _OneDay({required this.day, required this.events, required this.hours});

  final DateTime day;
  final List<CalendarEvent> events;
  final ScrollController hours;

  @override
  Widget build(BuildContext context) {
    final onDay = eventsOn(events, day);
    final kinds = calendarsOn(onDay, day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AllDayBand(days: [day], events: onDay),
        // One kind needs no naming; the colour says it.
        if (kinds.length > 1) CalendarColumnHeader(kinds: kinds),
        Expanded(
          child: SingleChildScrollView(
            // Shared across pages so swiping to tomorrow keeps the same hour
            // in view rather than snapping back to seven.
            controller: hours,
            child: SizedBox(
              height: kHourHeight * 24,
              child: Stack(
                children: [
                  const HourGrid(),
                  // Under the blocks, so tapping a job opens it and tapping
                  // the space beside it books one.
                  if (AppScope.of(context).canEditJobs)
                    Positioned(
                      left: kGutterWidth,
                      right: kEdgeGutter,
                      top: 0,
                      bottom: 0,
                      child: NewJobSlot(
                        day: day,
                        onNew: (at) => showEventEditor(context, startAt: at),
                      ),
                    ),
                  Positioned(
                    left: kGutterWidth,
                    right: kEdgeGutter,
                    top: 0,
                    bottom: 0,
                    child: DayColumn(day: day, events: onDay, byCalendar: true),
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
