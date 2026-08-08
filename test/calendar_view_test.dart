import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/event.dart';
import 'package:haul_board/calendar/views/list_view.dart';
import 'package:haul_board/calendar/views/month_view.dart';
import 'package:haul_board/calendar/views/timed_grid.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// A day's work around the pinned clock — Thursday 6 August 2026.
List<Job> bookedJobs() => [
  job(
    'HL-1',
    type: 'Debris haul',
    customer: 'Sunset Ridge Builders',
    city: 'Philomath',
    at: DateTime(2026, 8, 6, 7),
  ),
  job(
    'HL-2',
    type: 'Junk removal',
    customer: 'Harrison St rental',
    city: 'Corvallis',
    at: DateTime(2026, 8, 6, 9),
  ),
  job(
    'HL-3',
    type: 'Gravel delivery',
    customer: 'Decker Rd residence',
    at: DateTime(2026, 8, 9, 13),
  ),
  // Booked for a day with no time on it — the all-day band.
  job(
    'HL-4',
    type: 'Bark & soil',
    customer: 'Airlie Rd residence',
    at: DateTime(2026, 8, 6),
  ),
];

void main() {
  group('the month view', () {
    testWidgets('opens on this month with today marked', (tester) async {
      await pumpApp(tester, jobs: bookedJobs());

      expect(find.text('August 2026'), findsOneWidget);
      // Six rows of seven, always — including the days either side, which is
      // why 31 turns up twice: July's and August's.
      expect(find.byType(DayCell), findsNWidgets(42));
      expect(find.text('31'), findsNWidgets(2));
      // The selected day's work is listed underneath.
      expect(find.text('Debris haul'), findsWidgets);
      expect(find.text('Sunset Ridge Builders · Philomath'), findsOneWidget);
    });

    testWidgets('tapping a day changes the list but not the month', (
      tester,
    ) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.tap(find.bySemanticsLabel(RegExp('^Sunday, 9 August')));
      await settle(tester);

      expect(app.calendar.selected, DateTime(2026, 8, 9));
      expect(app.calendar.focused, DateTime(2026, 8, 6));
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('Gravel delivery'), findsWidgets);
    });

    testWidgets('a day announces what is on it', (tester) async {
      await pumpApp(tester, jobs: bookedJobs());

      expect(
        find.bySemanticsLabel('Thursday, 6 August, today. 3 jobs.'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Friday, 7 August. Nothing on.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Sunday, 9 August. 1 job.'), findsOneWidget);
    });

    testWidgets('an empty day says so rather than showing nothing', (
      tester,
    ) async {
      await pumpApp(tester, jobs: bookedJobs());
      await tester.tap(find.bySemanticsLabel(RegExp('^Friday, 7 August')));
      await settle(tester);

      expect(find.text('No jobs'), findsOneWidget);
    });

    testWidgets('a window with room writes the work into the cells', (
      tester,
    ) async {
      await pumpApp(tester, jobs: bookedJobs(), size: const Size(1280, 900));

      // Mac Calendar's month view: titles in the cells, and no list below
      // repeating what is already on screen.
      expect(find.byType(EventRow), findsNothing);
      expect(find.text('Junk removal'), findsOneWidget);
      expect(find.text('Bark & soil'), findsOneWidget);
      // And what is written in the cell is what gets read out of it.
      expect(
        find.bySemanticsLabel(
          'Thursday, 6 August, today. 3 jobs. '
          'Bark & soil, Debris haul, Junk removal.',
        ),
        findsOneWidget,
      );
    });
  });

  group('the day view', () {
    testWidgets('draws the hours and the jobs on them', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: bookedJobs());

      expect(find.text('noon'), findsOneWidget);
      expect(find.text('7 AM'), findsWidgets);
      expect(find.byType(EventBlock), findsNWidgets(2));
      // The day-only booking rides the band, not a block at midnight.
      expect(find.text('all-day'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('^All day. Bark & soil')),
        findsOneWidget,
      );
    });

    testWidgets('a block says what it is out loud', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: bookedJobs());

      expect(
        find.bySemanticsLabel(
          'Junk removal for Harrison St rental in Corvallis. '
          '9 AM – 11 AM.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the now-line is only on today', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: bookedJobs());
      expect(find.byType(NowLine), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('^Next')));
      await settle(tester);
      expect(find.byType(NowLine), findsNothing);
    });
  });

  group('the week view', () {
    testWidgets('shows seven days at once', (tester) async {
      await pumpApp(tester, view: CalView.week, jobs: bookedJobs());

      for (final day in ['Sunday, 2 August', 'Saturday, 8 August']) {
        expect(find.bySemanticsLabel(RegExp('^$day')), findsOneWidget);
      }
      expect(find.byType(EventBlock), findsNWidgets(2));
    });

    testWidgets('tapping a heading drills into that day', (tester) async {
      final app = await pumpApp(tester, view: CalView.week, jobs: bookedJobs());

      await tester.tap(find.bySemanticsLabel(RegExp('^Tuesday, 4 August')));
      await settle(tester);

      expect(app.calendar.view, CalView.day);
      expect(app.calendar.focused, DateTime(2026, 8, 4));
    });
  });

  group('the year view', () {
    testWidgets('shows twelve months', (tester) async {
      await pumpApp(tester, view: CalView.year, jobs: bookedJobs());

      expect(find.text('2026'), findsOneWidget);
      expect(find.text('January'), findsOneWidget);
      expect(find.text('December'), findsOneWidget);
    });

    testWidgets('tapping a month opens it', (tester) async {
      final app = await pumpApp(tester, view: CalView.year, jobs: bookedJobs());

      await tester.tap(find.text('October'));
      await settle(tester);

      expect(app.calendar.view, CalView.month);
      expect(app.calendar.focused.month, 10);
    });
  });

  group('the list view', () {
    testWidgets('runs forward from today, grouped by day', (tester) async {
      await pumpApp(tester, view: CalView.list, jobs: bookedJobs());

      expect(find.text('Today · Thursday, 6 August'), findsOneWidget);
      expect(find.text('Sunday, 9 August'), findsOneWidget);
      expect(find.text('Gravel delivery'), findsOneWidget);
    });

    testWidgets('says so when there is nothing ahead', (tester) async {
      await pumpApp(
        tester,
        view: CalView.list,
        jobs: [job('HL-1', at: DateTime(2026, 7, 1, 9))],
      );

      expect(find.textContaining('Nothing booked'), findsOneWidget);
    });

    testWidgets('work with no date is listed rather than lost', (tester) async {
      // A booking from the website arrives without a day. A calendar has
      // nowhere to draw that, so the list is where it has to surface.
      await pumpApp(
        tester,
        view: CalView.list,
        jobs: [
          ...bookedJobs(),
          job('HL-9', type: 'Equipment move', customer: 'Fairbanks'),
        ],
      );

      expect(find.text('Not scheduled yet'), findsOneWidget);
      expect(find.byType(UndatedRow), findsOneWidget);
      expect(find.text('Fairbanks'), findsOneWidget);
    });

    testWidgets('an undated job on its own still shows', (tester) async {
      await pumpApp(
        tester,
        view: CalView.list,
        jobs: [job('HL-9', customer: 'Fairbanks')],
      );

      expect(find.textContaining('Nothing booked'), findsNothing);
      expect(find.byType(UndatedRow), findsOneWidget);
    });
  });

  group('moving around', () {
    testWidgets('the arrows step by whatever is on screen', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.tap(find.bySemanticsLabel('Next'));
      await settle(tester);
      expect(find.text('September 2026'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous'));
      await settle(tester);
      expect(app.calendar.focused, DateTime(2026, 8, 6));
    });

    testWidgets('Today appears only once you have left it', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      expect(find.bySemanticsLabel('Back to today'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Next'));
      await settle(tester);
      expect(find.bySemanticsLabel('Back to today'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Back to today'));
      await settle(tester);
      expect(app.calendar.focused, app.calendar.today);
      expect(find.bySemanticsLabel('Back to today'), findsNothing);
    });

    testWidgets('the switcher changes view', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      for (final view in CalView.values) {
        await tester.tap(find.bySemanticsLabel(RegExp('^${view.label} view')));
        await settle(tester);
        expect(app.calendar.view, view);
      }
    });

    testWidgets('the keyboard drives it too', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(app.calendar.focused, DateTime(2026, 9, 6));

      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await settle(tester);
      expect(app.calendar.focused, app.calendar.today);
    });
  });

  group('a job opened from the calendar', () {
    testWidgets('opens over the calendar and closes again', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.tap(find.text('Junk removal').last);
      await settle(tester);

      expect(find.text('Harrison St rental'), findsWidgets);
      expect(find.text('HL-2'), findsOneWidget);
      // The calendar is still behind the sheet.
      expect(find.text('August 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.text('HL-2'), findsNothing);
      expect(app.calendar.openEventId, isNull);
    });

    testWidgets('says what rig is needed without assigning one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        jobs: [
          Job(
            id: 'HL-9',
            type: 'Debris haul',
            customer: 'Someone',
            address: '1 Main St',
            city: 'Corvallis',
            contact: '',
            phone: '',
            access: '',
            material: '',
            volume: '',
            weight: '',
            equipment: 'Dump trailer 14k',
            disposal: '',
            dumpFee: 0,
            window: '',
            miles: 0,
            deadhead: 0,
            billed: 0,
            scheduledFor: DateTime(2026, 8, 6, 9),
          ),
        ],
      );

      await tester.tap(find.text('Debris haul').last);
      await settle(tester);

      expect(find.text('Rig needed'), findsOneWidget);
      expect(find.text('Dump trailer 14k'), findsOneWidget);
      // Never who is allowed to drive it.
      expect(find.textContaining('Assigned rig'), findsNothing);
    });

    testWidgets('money is only shown to people who may see it', (tester) async {
      final jobs = bookedJobs();
      // Tall enough that the whole sheet is on screen — the money row is near
      // the bottom of it, and a lazy list would not build it otherwise.
      const tall = Size(500, 1200);

      await pumpApp(tester, jobs: jobs, role: Role.employee, size: tall);
      await tester.tap(find.text('Junk removal').last);
      await settle(tester);
      expect(find.text('Bills at'), findsNothing);

      await pumpApp(tester, jobs: jobs, role: Role.manager, size: tall);
      await tester.tap(find.text('Junk removal').last);
      await settle(tester);
      expect(find.text('Bills at'), findsOneWidget);
    });
  });

  group('the calendars sheet', () {
    testWidgets('hides a colour set and puts it back', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Junk removal, shown')));
      await settle(tester);
      expect(app.calendar.isVisible(WorkCalendar.junk), isFalse);

      await tester.tap(find.text('Show all'));
      await settle(tester);
      expect(app.calendar.hidden, isEmpty);
    });

    testWidgets('a hidden calendar is not drawn', (tester) async {
      final app = await pumpApp(tester, view: CalView.day, jobs: bookedJobs());
      expect(find.byType(EventBlock), findsNWidgets(2));

      app.calendar.toggleCalendar(WorkCalendar.junk);
      await settle(tester);
      expect(find.byType(EventBlock), findsOneWidget);
    });
  });

  group('layout', () {
    // The sweep that has caught every overflow in this app so far: each view,
    // on a small phone, at the largest text the app allows.
    for (final view in CalView.values) {
      testWidgets('${view.label} survives a small screen at 1.6x text', (
        tester,
      ) async {
        await pumpApp(
          tester,
          view: view,
          jobs: bookedJobs(),
          size: const Size(320, 640),
          textScale: 1.6,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a job sheet survives it too', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: bookedJobs(),
        size: const Size(320, 640),
        textScale: 1.6,
      );
      // Opened through the state rather than by tapping: on a screen this
      // small the row is below the fold, and this test is about the sheet.
      app.calendar.openEvent('HL-2');
      await settle(tester);

      expect(find.text('HL-2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('and a tablet in landscape', (tester) async {
      for (final view in CalView.values) {
        await pumpApp(
          tester,
          view: view,
          jobs: bookedJobs(),
          size: const Size(1194, 834),
        );
        expect(tester.takeException(), isNull);
      }
    });
  });
}
