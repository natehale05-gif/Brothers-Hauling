import 'package:flutter/material.dart';

import '../calendar_state.dart';
import '../calendar_theme.dart';
import '../date_math.dart';
import '../event.dart';

/// How far either way the year pager runs.
const int kYearRange = 8;

/// Twelve mini months. Tapping one drops into it.
class YearView extends StatefulWidget {
  const YearView({super.key, required this.events});

  final List<CalendarEvent> events;

  @override
  State<YearView> createState() => _YearViewState();
}

class _YearViewState extends State<YearView> {
  PageController? _pages;
  int _lastIndex = kYearRange;

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cal = CalendarScope.of(context);
    final index = kYearRange + (cal.focused.year - cal.today.year);

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
      itemCount: kYearRange * 2 + 1,
      onPageChanged: (page) {
        _lastIndex = page;
        cal.focus(DateTime(cal.today.year + page - kYearRange, 1, 1));
      },
      itemBuilder: (context, page) => _OneYear(
        year: cal.today.year + page - kYearRange,
        events: widget.events,
      ),
    );
  }
}

class _OneYear extends StatelessWidget {
  const _OneYear({required this.year, required this.events});

  final int year;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    // Three across on a phone, four on anything wider — the same rule Apple
    // uses, expressed as a width rather than a device check.
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 4 : 3;

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        childAspectRatio: 0.78,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
      ),
      itemCount: 12,
      itemBuilder: (context, i) =>
          _MiniMonth(month: DateTime(year, i + 1), events: events),
    );
  }
}

class _MiniMonth extends StatelessWidget {
  const _MiniMonth({required this.month, required this.events});

  final DateTime month;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);
    final cal = CalendarScope.of(context);
    final days = monthGrid(month);
    final isThisMonth = sameMonth(month, cal.today);

    return Semantics(
      button: true,
      label: '${monthName(month)} ${month.year}',
      onTap: () {
        cal.focus(DateTime(month.year, month.month, 1));
        cal.setView(CalView.month);
      },
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          cal.focus(DateTime(month.year, month.month, 1));
          cal.setView(CalView.month);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 4),
              child: Text(
                monthName(month),
                style: t.miniMonth.copyWith(
                  // The current month's name is red in the year view, which is
                  // the only way you find today in a wall of numbers.
                  color: isThisMonth ? p.accent : p.label,
                ),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  for (var row = 0; row < 6; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < 7; col++)
                            Expanded(
                              child: _MiniDay(
                                day: days[row * 7 + col],
                                month: month,
                                today: sameDay(days[row * 7 + col], cal.today),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDay extends StatelessWidget {
  const _MiniDay({required this.day, required this.month, required this.today});

  final DateTime day;
  final DateTime month;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final p = CalPalette.of(context);
    final t = CalText.of(context);

    // Days outside the month are blank rather than grey. At this size a grey
    // number is noise, and the shape of the month is the information.
    if (!sameMonth(day, month)) return const SizedBox.shrink();

    return Center(
      child: Container(
        width: 14,
        height: 14,
        alignment: Alignment.center,
        decoration: today
            ? BoxDecoration(color: p.accent, shape: BoxShape.circle)
            : null,
        child: Text(
          '${day.day}',
          style: t.miniDay.copyWith(color: today ? p.onAccent : p.label),
        ),
      ),
    );
  }
}
