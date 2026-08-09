import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/date_math.dart';
import 'package:haul_board/calendar/search.dart';
import 'package:haul_board/calendar/views/timed_grid.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'calendar_view_test.dart' show bookedJobs;
import 'helpers.dart';

void main() {
  group('repeat dates', () {
    final from = DateTime(2026, 8, 6, 9);

    test('never repeating is just the one', () {
      expect(repeatDates(from, Repeat.never, count: 5), [from]);
    });

    test('daily, weekly and fortnightly walk by days', () {
      expect(repeatDates(from, Repeat.daily, count: 3), [
        from,
        DateTime(2026, 8, 7, 9),
        DateTime(2026, 8, 8, 9),
      ]);
      expect(
        repeatDates(from, Repeat.weekly, count: 3).last,
        DateTime(2026, 8, 20, 9),
      );
      expect(
        repeatDates(from, Repeat.fortnightly, count: 3).last,
        DateTime(2026, 9, 3, 9),
      );
    });

    test('monthly walks by calendar months, not by thirty days', () {
      final dates = repeatDates(
        DateTime(2026, 1, 31, 9),
        Repeat.monthly,
        count: 3,
      );
      // The 31st clamps into February rather than sliding into March.
      expect(dates[1], DateTime(2026, 2, 28, 9));
      expect(dates[2], DateTime(2026, 3, 31, 9));
    });

    test('yearly crosses the year', () {
      expect(
        repeatDates(from, Repeat.yearly, count: 2).last,
        DateTime(2027, 8, 6, 9),
      );
    });

    test('an end date cuts it short', () {
      final dates = repeatDates(
        from,
        Repeat.weekly,
        count: 10,
        until: DateTime(2026, 8, 20),
      );
      expect(dates, hasLength(3));
      expect(dates.last, DateTime(2026, 8, 20, 9));
    });

    test('the time of day is kept every time', () {
      for (final rule in Repeat.values) {
        for (final at in repeatDates(from, rule, count: 4)) {
          expect(at.hour, 9, reason: '$rule kept the hour');
          expect(at.minute, 0);
        }
      }
    });
  });

  group('searching', () {
    final jobs = [
      ...bookedJobs(),
      job('HL-9', type: 'Equipment move', customer: 'Fairbanks Excavating'),
    ];

    test('matches any field', () {
      expect(searchJobs(jobs, 'harrison').map((j) => j.id), ['HL-2']);
      expect(searchJobs(jobs, 'philomath').map((j) => j.id), ['HL-1']);
      expect(searchJobs(jobs, 'HL-3').map((j) => j.id), ['HL-3']);
    });

    test('every word has to land, in any order', () {
      expect(searchJobs(jobs, 'junk corvallis').map((j) => j.id), ['HL-2']);
      expect(searchJobs(jobs, 'corvallis junk').map((j) => j.id), ['HL-2']);
      expect(searchJobs(jobs, 'junk philomath'), isEmpty);
    });

    test('case and stray spaces do not matter', () {
      expect(searchJobs(jobs, '  HARRISON  ').map((j) => j.id), ['HL-2']);
    });

    test('an empty query matches nothing rather than everything', () {
      expect(searchJobs(jobs, ''), isEmpty);
      expect(searchJobs(jobs, '   '), isEmpty);
    });

    test('soonest first, and undated work last', () {
      final hits = searchJobs(jobs, 'a');
      expect(hits.last.id, 'HL-9', reason: 'the one with no date');
      final dated = hits.where((j) => j.scheduledFor != null).toList();
      for (var i = 1; i < dated.length; i++) {
        expect(
          dated[i].scheduledFor!.isBefore(dated[i - 1].scheduledFor!),
          isFalse,
        );
      }
    });
  });

  group('which minute the grid was tapped on', () {
    final day = DateTime(2026, 8, 6);

    test('reads the offset as a time', () {
      expect(timeAt(day, 0), day);
      expect(timeAt(day, kHourHeight * 9), DateTime(2026, 8, 6, 9));
    });

    test('snaps to the quarter hour', () {
      // Twenty past nine rounds to the quarter, not to 9:20.
      final at = timeAt(day, kHourHeight * 9 + kHourHeight / 3);
      expect(at.minute % 15, 0);
      expect(at, DateTime(2026, 8, 6, 9, 15));
    });

    test('never runs off the end of the day', () {
      final at = timeAt(day, kHourHeight * 40);
      expect(at.day, 6);
      expect(at.hour, 23);
    });
  });

  group('a job with a length', () {
    testWidgets('is drawn for as long as it runs', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9)).copyWith(minutes: 30)],
      );

      final event = app.calendar.visible(app.state.jobs).single;
      expect(event.end, DateTime(2026, 8, 6, 9, 30));
      expect(event.lengthMinutes(DateTime(2026, 8, 6)), 30);
    });

    testWidgets('falls back to the assumption when nobody has said', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      final event = app.calendar.visible(app.state.jobs).single;
      expect(event.end, DateTime(2026, 8, 6, 11));
    });
  });

  group('writing from the calendar', () {
    testWidgets('adds a job, and it lands on the day it was booked for', (
      tester,
    ) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      final made = await app.state.addJob(
        type: 'Gravel delivery',
        customer: 'Skyline Ranch',
        city: 'Alsea',
        scheduledFor: DateTime(2026, 8, 12, 13),
        minutes: 90,
      );
      await settle(tester);

      expect(made, isNotNull);
      expect(app.state.jobs.any((j) => j.customer == 'Skyline Ranch'), isTrue);
      expect(made!.minutes, 90);
      // A fresh id, not one already on the board.
      expect(app.state.jobs.where((j) => j.id == made.id), hasLength(1));
    });

    testWidgets('deletes one that has not been worked', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      final target = jobIn(app.state, 'HL-2');

      expect(app.state.canDelete(target), isTrue);
      expect(await app.state.deleteJob(target), isTrue);
      await settle(tester);

      expect(app.state.jobs.any((j) => j.id == 'HL-2'), isFalse);
    });

    testWidgets('refuses to delete work that has been done', (tester) async {
      final worked = job('HL-5', at: DateTime(2026, 8, 6, 9)).copyWith(
        status: JobStatus.active,
        startedAt: DateTime(2026, 8, 6, 9, 5),
      );
      final app = await pumpApp(tester, jobs: [worked]);

      expect(app.state.canDelete(jobIn(app.state, 'HL-5')), isFalse);
      expect(await app.state.deleteJob(jobIn(app.state, 'HL-5')), isFalse);
      await settle(tester);

      expect(app.state.jobs.any((j) => j.id == 'HL-5'), isTrue);
    });

    testWidgets('moving a job carries it to the new time', (tester) async {
      final app = await pumpApp(tester, view: CalView.day, jobs: bookedJobs());

      await app.state.rescheduleJob(
        jobIn(app.state, 'HL-2'),
        startsAt: DateTime(2026, 8, 6, 14),
        minutes: 45,
      );
      await settle(tester);

      final moved = jobIn(app.state, 'HL-2');
      expect(moved.scheduledFor, DateTime(2026, 8, 6, 14));
      expect(moved.minutes, 45);
    });

    testWidgets('a crew member is not offered the tools to change it', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        jobs: bookedJobs(),
        role: Role.employee,
      );

      expect(app.state.canEditJobs, isFalse);
      expect(find.bySemanticsLabel('New job'), findsNothing);

      expect(await app.state.deleteJob(jobIn(app.state, 'HL-2')), isFalse);
      expect(app.state.jobs.any((j) => j.id == 'HL-2'), isTrue);
    });

    testWidgets('a manager sees the work but cannot rewrite it', (
      tester,
    ) async {
      final app = await pumpApp(tester, jobs: bookedJobs(), role: Role.manager);

      expect(app.state.canEditJobs, isFalse);
      expect(find.bySemanticsLabel('New job'), findsNothing);
      // The board is still theirs to read.
      expect(find.text('Debris haul'), findsWidgets);
    });

    testWidgets('an owner can', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs(), role: Role.admin);
      expect(app.state.canEditJobs, isTrue);
      expect(find.bySemanticsLabel('New job'), findsOneWidget);
    });
  });

  group('dragging a block', () {
    /// Picks the block up, moves it, and lets go.
    Future<void> dragBy(WidgetTester tester, Offset by, {Offset? from}) async {
      final at = from ?? tester.getCenter(find.byType(EventBlock).first);
      final gesture = await tester.startGesture(at);
      // Held, not brushed — nothing moves until the long press lands.
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.moveBy(by);
      await tester.pump();
      await gesture.up();
      await settle(tester);
    }

    testWidgets('moves the job to where it was dropped', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      await dragBy(tester, const Offset(0, kHourHeight));

      expect(jobIn(app.state, 'HL-1').scheduledFor, DateTime(2026, 8, 6, 10));
    });

    testWidgets('snaps to the quarter hour', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      // Twenty minutes' worth of drag lands on the quarter, not on 9:20.
      await dragBy(tester, Offset(0, kHourHeight / 3));

      expect(
        jobIn(app.state, 'HL-1').scheduledFor,
        DateTime(2026, 8, 6, 9, 15),
      );
    });

    testWidgets('a nudge too small to mean anything changes nothing', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      await dragBy(tester, const Offset(0, 2));

      expect(jobIn(app.state, 'HL-1').scheduledFor, DateTime(2026, 8, 6, 9));
    });

    testWidgets('a tap still opens the job rather than moving it', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      await tester.tap(find.byType(EventBlock).first);
      await settle(tester);

      expect(app.calendar.openEventId, 'HL-1');
      expect(jobIn(app.state, 'HL-1').scheduledFor, DateTime(2026, 8, 6, 9));
    });

    testWidgets('the bottom edge changes how long it runs', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      final box = tester.getRect(find.byType(EventBlock).first);
      final grip = Offset(box.center.dx, box.bottom - 4);
      final gesture = await tester.startGesture(grip);
      await gesture.moveBy(const Offset(0, kHourHeight));
      await tester.pump();
      await gesture.up();
      await settle(tester);

      // Two hours by default, an hour longer after the stretch.
      expect(jobIn(app.state, 'HL-1').minutes, 180);
      expect(jobIn(app.state, 'HL-1').scheduledFor, DateTime(2026, 8, 6, 9));
    });

    testWidgets('a crew member cannot drag anything', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        role: Role.employee,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      await dragBy(tester, const Offset(0, kHourHeight));

      expect(jobIn(app.state, 'HL-1').scheduledFor, DateTime(2026, 8, 6, 9));
    });
  });

  group('the editor', () {
    testWidgets('opens on the day you were looking at', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      app.calendar.select(DateTime(2026, 8, 20));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);

      expect(find.text('New Job'), findsOneWidget);
      // Both Starts and Ends land on that day.
      expect(find.textContaining('Thursday, 20 August'), findsNWidgets(2));
    });

    testWidgets('books a job typed into it', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Skyline Ranch');
      await tester.tap(find.bySemanticsLabel('Gravel delivery calendar'));
      await settle(tester);
      await pickRig(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.where((j) => j.customer == 'Skyline Ranch');
      expect(made, hasLength(1));
      expect(made.single.type, 'Gravel delivery');
      expect(made.single.scheduledFor, isNotNull);
      // Back on the calendar afterwards.
      expect(find.text('New Job'), findsNothing);
    });

    testWidgets('will not book a job with nobody to do it for', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      final before = app.state.jobs.length;

      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      expect(app.state.jobs, hasLength(before));
      expect(find.text('New Job'), findsOneWidget);
      expect(find.text('Give the job a customer.'), findsOneWidget);
    });

    testWidgets('a repeat writes a real job every time round', (tester) async {
      final app = await pumpApp(tester, jobs: const []);
      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Weekly gravel');
      // Nothing on the board yet, so there is no chip to tap — it gets typed.
      // Done before the repeat, because choosing a rig grows the form and
      // pushes the repeat chips further down it.
      await pickRig(tester, 'Lowboy 25t');
      await tester.ensureVisible(find.bySemanticsLabel('Every week'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Every week'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made =
          app.state.jobs.where((j) => j.customer == 'Weekly gravel').toList()
            ..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
      expect(made, hasLength(4), reason: 'four is the default');
      expect(made[1].scheduledFor!.difference(made[0].scheduledFor!).inDays, 7);
      // Each is a job in its own right, with its own id.
      expect({for (final j in made) j.id}, hasLength(4));
    });

    testWidgets('cancelling changes nothing', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      final before = app.state.jobs.length;

      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Never happened');
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(app.state.jobs, hasLength(before));
      expect(find.text('New Job'), findsNothing);
    });

    testWidgets('edits an existing job from its sheet', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());

      await tester.tap(find.text('Junk removal').last);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Edit job'));
      await settle(tester);

      expect(find.text('Edit Job'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Harrison St flats');
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-2').customer, 'Harrison St flats');
    });

    testWidgets('an all-day job keeps no length', (tester) async {
      final app = await pumpApp(tester, jobs: bookedJobs());
      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'Sometime Tuesday');
      await tester.tap(find.byType(Switch));
      await settle(tester);
      await pickRig(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.firstWhere(
        (j) => j.customer == 'Sometime Tuesday',
      );
      expect(made.minutes, isNull);
      expect(made.scheduledFor!.hour, 0);
      expect(made.scheduledFor!.minute, 0);
    });

    testWidgets('survives a small screen at 1.6x text', (tester) async {
      await pumpApp(
        tester,
        jobs: bookedJobs(),
        size: const Size(320, 640),
        textScale: 1.6,
      );
      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);

      expect(find.text('New Job'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the nav bar fits with every control showing', (tester) async {
    // Off today, so the Today button is in the bar as well as the rest.
    final app = await pumpApp(
      tester,
      jobs: bookedJobs(),
      size: const Size(320, 640),
      textScale: 1.6,
    );
    app.calendar.step(1);
    await settle(tester);

    expect(find.bySemanticsLabel('Back to today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
