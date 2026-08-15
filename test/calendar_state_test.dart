import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/event.dart';

import 'calendar_event_test.dart' show job;

CalendarState stateAt(DateTime now, {CalView view = CalView.month}) =>
    CalendarState(now: () => now, view: view, tick: Duration.zero);

void main() {
  final now = DateTime(2026, 8, 6, 9, 30);

  test('opens on today, with today selected', () {
    final cal = stateAt(now);
    addTearDown(cal.dispose);
    expect(cal.today, DateTime(2026, 8, 6));
    expect(cal.focused, DateTime(2026, 8, 6));
    expect(cal.selected, DateTime(2026, 8, 6));
  });

  group('stepping', () {
    test('means what is on screen', () {
      for (final (view, expected) in [
        (CalView.day, DateTime(2026, 8, 7)),
        (CalView.list, DateTime(2026, 8, 7)),
        (CalView.week, DateTime(2026, 8, 13)),
        (CalView.month, DateTime(2026, 9, 6)),
        (CalView.year, DateTime(2027, 8, 1)),
      ]) {
        final cal = stateAt(now, view: view);
        addTearDown(cal.dispose);
        cal.step(1);
        expect(cal.focused, expected, reason: 'stepping in $view');
      }
    });

    test('a month step never lands in the wrong month', () {
      final cal = stateAt(DateTime(2026, 1, 31));
      addTearDown(cal.dispose);
      cal.step(1);
      expect(cal.focused, DateTime(2026, 2, 28));
    });

    test('Today comes back from anywhere', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      cal.step(5);
      cal.goToToday();
      expect(cal.focused, cal.today);
      expect(cal.selected, cal.today);
    });
  });

  group('focus and select', () {
    test('focus moves the view and the selection together', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      cal.focus(DateTime(2026, 9, 2, 16));
      expect(cal.focused, DateTime(2026, 9, 2));
      expect(cal.selected, DateTime(2026, 9, 2));
    });

    test('select picks a day without moving the view', () {
      // Tapping a cell in the month grid must not page the grid out from
      // under the finger that tapped it.
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      cal.select(DateTime(2026, 8, 20));
      expect(cal.selected, DateTime(2026, 8, 20));
      expect(cal.focused, DateTime(2026, 8, 6));
    });

    test('nothing is announced when nothing changed', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      var notices = 0;
      cal.addListener(() => notices++);

      cal.focus(DateTime(2026, 8, 6, 23));
      cal.select(DateTime(2026, 8, 6));
      cal.setView(CalView.month);
      cal.closeEvent();
      cal.showAllCalendars();
      expect(notices, 0);

      cal.focus(DateTime(2026, 8, 7));
      expect(notices, 1);
    });
  });

  group('titles', () {
    test('each view is titled the way Apple titles it', () {
      String titleIn(CalView view, DateTime at) {
        final cal = stateAt(now, view: view);
        addTearDown(cal.dispose);
        cal.focus(at);
        return cal.title;
      }

      expect(titleIn(CalView.month, DateTime(2026, 8, 6)), 'August 2026');
      // A day view names the day. Anything else is a bar to be ignored.
      expect(titleIn(CalView.day, DateTime(2026, 8, 6)), 'Thu 6 Aug');
      expect(titleIn(CalView.year, DateTime(2026, 8, 6)), '2026');
      expect(titleIn(CalView.week, DateTime(2026, 8, 6)), 'August 2026');
    });

    test('a week across two months says so', () {
      final cal = stateAt(now, view: CalView.week);
      addTearDown(cal.dispose);
      // 1 September 2026 is a Tuesday, so its week starts in August.
      cal.focus(DateTime(2026, 9, 1));
      expect(cal.title, 'Aug – Sep 2026');
    });
  });

  group('hiding a calendar', () {
    test('hides the work without touching it', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      final jobs = [
        job(
          'debris',
          equipment: ['Dump trailer 14k'],
          at: DateTime(2026, 8, 6, 9),
        ),
        job('junk', equipment: ['Flatbed 20ft'], at: DateTime(2026, 8, 6, 11)),
      ];

      expect(cal.visible(jobs), hasLength(2));
      cal.toggleCalendar(const WorkCalendar('Flatbed 20ft'));
      expect(cal.visible(jobs).map((e) => e.id), ['debris']);
      expect(cal.isVisible(const WorkCalendar('Flatbed 20ft')), isFalse);

      // The job itself is untouched — this is a view, not a filter on data.
      expect(jobs, hasLength(2));

      cal.showAllCalendars();
      expect(cal.visible(jobs), hasLength(2));
    });

    test('toggling twice puts it back', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      cal.toggleCalendar(const WorkCalendar('Utility trailer'));
      cal.toggleCalendar(const WorkCalendar('Utility trailer'));
      expect(cal.hidden, isEmpty);
    });

    test('undated jobs are never on the calendar', () {
      final cal = stateAt(now);
      addTearDown(cal.dispose);
      expect(cal.visible([job('nowhere')]), isEmpty);
    });
  });

  test('an open event closes', () {
    final cal = stateAt(now);
    addTearDown(cal.dispose);
    cal.openEvent('HL-1');
    expect(cal.openEventId, 'HL-1');
    cal.closeEvent();
    expect(cal.openEventId, isNull);
  });
}
