import 'package:flutter/material.dart';

import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';

/// How far either way the month pager runs.
///
/// Bounded so the controller has a real index. Four years each way is longer
/// than anybody scrolls and short enough to stay honest about being finite.
const int kMonthRange = 48;

/// The month grid, and the day's events underneath it.
///
/// This is the iPhone's month screen: six rows of days that never change
/// height as you page, and a list below showing whichever day is selected.
class MonthView extends StatefulWidget {
  const MonthView({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  State<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends State<MonthView> {
  PageController? _pages;
  int _lastIndex = kMonthRange;

  int _indexFor(DateTime month, DateTime anchor) =>
      kMonthRange +
      (month.year - anchor.year) * 12 +
      (month.month - anchor.month);

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final anchor = monthOf(cal.today);
    final index = _indexFor(monthOf(cal.focused), anchor);

    _pages ??= PageController(initialPage: index);

    // The state owns which month is showing; the pager is brought into line
    // when something else — the Today button, a year cell — moves it.
    if (index != _lastIndex) {
      _lastIndex = index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final controller = _pages;
        if (controller == null || !controller.hasClients) return;
        if (controller.page?.round() != index) controller.jumpToPage(index);
      });
    }

    final pager = PageView.builder(
      controller: _pages,
      itemCount: kMonthRange * 2 + 1,
      onPageChanged: (page) {
        _lastIndex = page;
        final month = DateTime(anchor.year, anchor.month + page - kMonthRange);
        // Paging keeps the selected day-of-month where sensible, which is what
        // makes flicking through a year feel like one gesture rather than a
        // series of jumps back to the first.
        final day = cal.selected.day <= daysInMonth(month)
            ? cal.selected.day
            : daysInMonth(month);
        cal.focus(DateTime(month.year, month.month, day));
      },
      itemBuilder: (context, page) => _MonthGrid(
        month: DateTime(anchor.year, anchor.month + page - kMonthRange),
        events: widget.events,
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Two month views, and Apple ships both. A phone's cells are too small
        // to hold anything but dots, so the day you pick is spelled out in a
        // list underneath. Give the same grid a window and the cells hold the
        // work itself — at which point the list below is repeating what is
        // already on screen, and the Mac drops it.
        final whole = box.maxWidth >= 700 && box.maxHeight >= 560;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const WeekdayHeader(),
            Divider(height: 0.5, thickness: 0.5, color: p.separator),
            Expanded(flex: whole ? 1 : 3, child: pager),
            if (!whole) ...[
              Divider(height: 0.5, thickness: 0.5, color: p.separator),
              Expanded(flex: 2, child: _SelectedDayList(events: widget.events)),
            ],
          ],
        );
      },
    );
  }
}

/// S M T W T F S, over the grid.
class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final t = CalText.of(context);
    final initials = weekdayInitials();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Semantics(
                // Two of them read "S". The full name is what a screen reader
                // needs; the letter is only for the eye.
                label: kWeekdayNames[(kWeekStartsOn - 1 + i) % 7],
                excludeSemantics: true,
                child: Center(child: Text(initials[i], style: t.weekdayHeader)),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.events});

  final DateTime month;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final cal = CalendarScope.of(context);
    final days = monthGrid(month);

    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    // The first row's rule is the header's, already drawn.
                    color: row == 0 ? Colors.transparent : p.hairline,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                // Cells fill the row so the numbers sit along the top of it,
                // rather than floating in the middle of whatever height the
                // month happens to have.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: DayCell(
                        day: days[row * 7 + col],
                        month: month,
                        events: events,
                        selected: sameDay(days[row * 7 + col], cal.selected),
                        today: sameDay(days[row * 7 + col], cal.today),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// One square of the month grid.
class DayCell extends StatelessWidget {
  const DayCell({
    super.key,
    required this.day,
    required this.month,
    required this.events,
    required this.selected,
    required this.today,
  });

  final DateTime day;
  final DateTime month;
  final List<CalendarEvent> events;
  final bool selected;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);

    final outside = !sameMonth(day, month);
    final onDay = eventsOn(events, day);

    // Today is red; the day you picked is a filled disc. Today *and* picked is
    // a filled red disc, which is the one combination Apple treats specially.
    final Color numberColour;
    final Color? discColour;
    if (selected && today) {
      numberColour = p.onAccent;
      discColour = p.accent;
    } else if (selected) {
      numberColour = p.bg;
      discColour = p.label;
    } else if (today) {
      numberColour = p.accent;
      discColour = null;
    } else {
      numberColour = outside ? p.tertiaryLabel : p.label;
      discColour = null;
    }

    final counted =
        '${longDay(day)}'
        '${today ? ', today' : ''}. '
        '${onDay.isEmpty ? 'Nothing on' : '${onDay.length} '
                  '${onDay.length == 1 ? 'job' : 'jobs'}'}.';

    return LayoutBuilder(
      builder: (context, box) {
        // A cell with room shows what the work actually is, the way the Mac
        // and iPad do; a phone's cell has room for dots and no more.
        final room = ((box.maxHeight - 40) / kChipHeight).floor();
        // Two lines is the floor: one for a job and one to own up to the
        // rest. A cell that can only fit "3 more" says less than a dot.
        final roomy = box.maxWidth >= 84 && room >= 2;

        return Semantics(
          button: true,
          selected: selected,
          // When the titles are on screen they are read out too. A cell that
          // shows three jobs and announces "3 jobs" tells a screen reader
          // less than the same cell tells everybody else.
          label: roomy && onDay.isNotEmpty
              ? '$counted ${onDay.map((e) => e.title).join(', ')}.'
              : counted,
          onTap: () => cal.select(day),
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => cal.select(day),
            // A second tap on the day already chosen opens it, the way the
            // real one drills from month into day.
            onDoubleTap: () {
              cal.focus(day);
              cal.setView(CalView.day);
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: discColour == null
                        ? null
                        : BoxDecoration(
                            color: discColour,
                            shape: BoxShape.circle,
                          ),
                    child: Text(
                      '${day.day}',
                      style: t.dayNumber.copyWith(
                        color: numberColour,
                        fontWeight: today || selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (roomy)
                    _Chips(events: onDay, room: room, dimmed: outside)
                  else
                    _Dots(events: onDay, dimmed: outside),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The height of one title inside a month cell.
const double kChipHeight = 17;

/// The jobs on a day, written out inside its cell.
///
/// Display only: the cell owns the tap, and the list under the grid is where a
/// job is opened from. A chip that swallowed the tap would make picking a day
/// depend on hitting the gap between two of them.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.events,
    required this.room,
    required this.dimmed,
  });

  final List<CalendarEvent> events;
  final int room;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox.shrink();

    // The last slot goes to "3 more" when it is needed, so nothing is hidden
    // without saying so.
    final overflowing = events.length > room;
    final shown = overflowing ? events.take(room - 1).toList() : events;
    final t = CalText.of(context);
    final p = CalPalette.of(context);
    final fade = dimmed ? 0.45 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final event in shown)
            Container(
              height: kChipHeight - 2,
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: event.colour.withValues(alpha: 0.16 * fade),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.eventTitle.copyWith(
                  fontSize: 11,
                  color: event.colour.withValues(alpha: fade),
                ),
              ),
            ),
          if (overflowing)
            SizedBox(
              height: kChipHeight - 2,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '${events.length - shown.length} more',
                  style: t.eventDetail.copyWith(
                    color: p.secondaryLabel.withValues(alpha: fade),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The dots under a day number.
///
/// Up to three, coloured by calendar. Apple shows a single grey dot; colours
/// carry more here because a hauling day is a handful of jobs rather than a
/// dozen meetings, and which kind they are is the thing worth seeing.
class _Dots extends StatelessWidget {
  const _Dots({required this.events, required this.dimmed});

  final List<CalendarEvent> events;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const SizedBox(height: 6);

    final shown = events.take(3).toList();
    return SizedBox(
      height: 6,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final event in shown)
            Container(
              width: 5,
              height: 5,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: dimmed
                    ? event.colour.withValues(alpha: 0.4)
                    : event.colour,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

/// The list under the grid: whatever day is selected, in order.
class _SelectedDayList extends StatelessWidget {
  const _SelectedDayList({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);
    final onDay = eventsOn(events, cal.selected);

    if (onDay.isEmpty) {
      return Container(
        color: p.bg,
        alignment: Alignment.center,
        child: Text('No jobs', style: t.secondary),
      );
    }

    return Container(
      color: p.bg,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: onDay.length,
        separatorBuilder: (_, _) => Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Divider(height: 0.5, thickness: 0.5, color: p.hairline),
        ),
        itemBuilder: (context, i) => EventRow(event: onDay[i]),
      ),
    );
  }
}

/// One job as a list row — the shape Apple uses under the month grid and in
/// the list view.
class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: event.colour,
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
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body,
                    ),
                    Text(
                      event.job.city.isEmpty
                          ? event.subtitle
                          : '${event.subtitle} · ${event.job.city}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                event.allDay ? 'all-day' : clockLabel(event.start),
                style: t.secondary.copyWith(color: p.secondaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
