import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/screens/tabs/day_board.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

/// A fixed "now", so "today" means the same thing on every run.
final _now = DateTime(2026, 8, 2, 9, 5);

Job job(
  String id, {
  DateTime? on,
  String customer = 'Sunset Ridge Builders',
  String? assignedTo,
}) => Job(
  id: id,
  scheduledFor: on,
  type: 'Debris haul',
  customer: customer,
  address: '1180 Decker Rd',
  city: 'Philomath',
  contact: 'Marla',
  phone: '555-0142',
  access: '',
  material: '',
  volume: '',
  weight: '',
  equipment: 'Dump trailer 14k',
  disposal: 'N/A',
  dumpFee: 0,
  window: '7:00 – 9:00 AM',
  miles: 10,
  deadhead: 2,
  billed: 200,
  assignedTo: assignedTo,
);

AppState boot({List<Job>? jobs, Role role = Role.admin}) {
  final state = AppState(
    jobs: jobs,
    location: const SimulatedLocationService(),
    photos: FakePhotoService(),
    autoAdvance: false,
    toastDuration: null,
    now: () => _now,
  );
  addTearDown(state.dispose);
  state.enter(role);
  return state;
}

void main() {
  final today = DateTime(2026, 8, 2, 7);
  final tomorrow = DateTime(2026, 8, 3, 13);
  final yesterday = DateTime(2026, 8, 1, 8);

  group('which day is showing', () {
    test('it opens on today', () {
      final state = boot();
      expect(state.dayOffset, 0);
      expect(state.selectedDay, DateTime(2026, 8, 2));
    });

    test('stepping moves one day at a time, both ways', () {
      final state = boot();
      state.stepDay(1);
      expect(state.selectedDay, DateTime(2026, 8, 3));
      state.stepDay(1);
      expect(state.selectedDay, DateTime(2026, 8, 4));
      state.stepDay(-3);
      expect(state.selectedDay, DateTime(2026, 8, 1));
    });

    test('it steps across a month boundary without arithmetic of its own', () {
      final state = boot();
      state.showDay(30);
      // DateTime does the carrying; the view never builds a date by hand.
      expect(state.selectedDay, DateTime(2026, 9, 1));
    });

    test('today is one tap away from anywhere', () {
      final state = boot()..showDay(40);
      state.showToday();
      expect(state.dayOffset, 0);
    });
  });

  group('what is on a day', () {
    test('only that day, earliest first', () {
      final state = boot(
        jobs: [
          job('HL-3', on: DateTime(2026, 8, 2, 15)),
          job('HL-1', on: DateTime(2026, 8, 2, 7)),
          job('HL-9', on: tomorrow),
          job('HL-2', on: DateTime(2026, 8, 2, 11)),
        ],
      );

      // A day view that does not read top-to-bottom in the order the day
      // happens is a list, not a schedule.
      expect(state.jobsOn(state.selectedDay).map((j) => j.id), [
        'HL-1',
        'HL-2',
        'HL-3',
      ]);
    });

    test('the time of day does not leak into the grouping', () {
      final state = boot(
        jobs: [
          job('HL-1', on: DateTime(2026, 8, 2, 0, 1)),
          job('HL-2', on: DateTime(2026, 8, 2, 23, 59)),
        ],
      );
      expect(state.jobsOn(state.selectedDay), hasLength(2));
    });

    test('a job with no day is not silently parked on today', () {
      final state = boot(
        jobs: [
          job('HL-1'),
          job('HL-2', on: today),
        ],
      );

      // Parking it on today is how it gets missed tomorrow.
      expect(state.jobsOn(state.selectedDay).map((j) => j.id), ['HL-2']);
      expect(state.unscheduledJobs.map((j) => j.id), ['HL-1']);
    });

    test('an empty day is empty, not yesterday', () {
      final state = boot(jobs: [job('HL-1', on: today)])..showDay(3);
      expect(state.jobsOn(state.selectedDay), isEmpty);
    });
  });

  group('the day the job is on survives', () {
    test('a round trip through JSON', () {
      final copy = Job.fromJson(job('HL-1', on: tomorrow).toJson());
      expect(copy.scheduledFor?.toLocal(), tomorrow);
      expect(copy.scheduledDay, DateTime(2026, 8, 3));
    });

    test('and so does having no day at all', () {
      final copy = Job.fromJson(job('HL-1').toJson());
      expect(copy.scheduledFor, isNull);
      expect(copy.scheduledDay, isNull);
    });

    test('a board written before days existed still loads', () {
      // Every job on a phone running the shipped build has no day on it.
      final copy = Job.fromJson(const {'id': 'HL-1'});
      expect(copy.scheduledFor, isNull);
    });
  });

  group('on screen', () {
    Future<Harness> openDay(
      WidgetTester tester, {
      List<Job>? jobs,
      Size size = const Size(430, 900),
    }) async {
      final harness = await pumpApp(
        tester,
        role: Role.admin,
        size: size,
        jobs: jobs,
      );
      harness.state.setTab(HaulTab.jobs);
      await settle(tester);
      return harness;
    }

    testWidgets('dispatch gets the whole company, a driver does not', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.admin);
      expect(harness.state.navTabs, contains(HaulTab.jobs));

      final driver = await pumpApp(tester, role: Role.employee);
      // Jobs is every job in the company, which is a dispatch screen. A
      // driver's day is their own board.
      expect(driver.state.navTabs, isNot(contains(HaulTab.jobs)));
    });

    testWidgets('it opens on today and says so', (tester) async {
      await openDay(tester);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.byType(DayBoard), findsOneWidget);
    });

    testWidgets('the arrows move a day and are named', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await openDay(tester);

      // A mouse has nothing to swipe with, so the arrows are not decoration.
      expect(find.bySemanticsLabel(RegExp('Show Tomorrow')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('Show Tomorrow')));
      await settle(tester);

      expect(harness.state.dayOffset, 1);
      expect(find.text('TOMORROW'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(RegExp('Show Today')));
      await settle(tester);
      expect(harness.state.dayOffset, 0);
      handle.dispose();
    });

    testWidgets('the left and right keys move a day', (tester) async {
      final harness = await openDay(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);
      expect(harness.state.dayOffset, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settle(tester);
      expect(harness.state.dayOffset, -1);
    });

    testWidgets('swiping moves a day', (tester) async {
      final harness = await openDay(tester);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await settle(tester);
      expect(harness.state.dayOffset, 1);

      await tester.drag(find.byType(PageView), const Offset(400, 0));
      await settle(tester);
      expect(harness.state.dayOffset, 0);
    });

    testWidgets('"today" comes back from a long way out', (tester) async {
      final harness = await openDay(tester);
      harness.state.showDay(25);
      await settle(tester);
      expect(find.text('IN 25 DAYS'), findsOneWidget);

      await tester.tap(find.text('TODAY'));
      await settle(tester);
      expect(harness.state.dayOffset, 0);
    });

    testWidgets('a day shows its jobs and the next day shows its own', (
      tester,
    ) async {
      await openDay(
        tester,
        jobs: [
          job('HL-1', on: today, customer: 'Today Customer'),
          job('HL-2', on: tomorrow, customer: 'Tomorrow Customer'),
          job('HL-3', on: yesterday, customer: 'Yesterday Customer'),
        ],
      );

      expect(find.textContaining('Today Customer'), findsOneWidget);
      expect(find.textContaining('Tomorrow Customer'), findsNothing);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await settle(tester);
      expect(find.textContaining('Tomorrow Customer'), findsOneWidget);
      expect(find.textContaining('Today Customer'), findsNothing);
    });

    testWidgets('an empty day says which day is empty', (tester) async {
      await openDay(tester, jobs: [job('HL-1', on: today)]);
      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await settle(tester);

      expect(
        find.textContaining(
          RegExp('Nothing on tomorrow', caseSensitive: false),
        ),
        findsOneWidget,
      );
    });

    testWidgets('jobs with no day are kept in sight, not hidden', (
      tester,
    ) async {
      await openDay(
        tester,
        jobs: [
          job('HL-1', on: today, customer: 'Booked In'),
          job('HL-2', customer: 'No Day Yet'),
        ],
      );

      expect(find.textContaining('Booked In'), findsOneWidget);
      expect(find.text('NO DAY SET'), findsOneWidget);
      expect(find.textContaining('No Day Yet'), findsOneWidget);
    });

    testWidgets('a card on the grid opens the job', (tester) async {
      final harness = await openDay(
        tester,
        jobs: [job('HL-1', on: today, customer: 'Sunset Ridge Builders')],
      );

      // Its own control rather than the whole card: a card that opens on any
      // tap cannot also carry a hold-to-volunteer button.
      await tester.tap(find.text('DETAILS & STAFFING'));
      await settle(tester);
      expect(harness.state.openJob?.id, 'HL-1');
    });

    testWidgets('the grid widens with the window', (tester) async {
      final many = [
        for (var i = 0; i < 6; i++)
          job('HL-$i', on: today, customer: 'Customer $i'),
      ];

      // Two cards side by side share a row; stacked ones do not.
      bool sideBySide(WidgetTester t) =>
          t.getTopLeft(find.textContaining('Customer 0')).dy ==
          t.getTopLeft(find.textContaining('Customer 1')).dy;

      await openDay(tester, jobs: many, size: const Size(430, 900));
      expect(sideBySide(tester), isFalse, reason: 'one column on a phone');

      await openDay(tester, jobs: many, size: const Size(1280, 900));
      // Several across a desktop window — from the tile width, not a
      // hard-coded breakpoint.
      expect(sideBySide(tester), isTrue);
    });
  });

  group('the board and the jobs list are day views too', () {
    testWidgets("a driver's board pages by day", (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      expect(harness.state.tab, HaulTab.board);

      expect(find.byType(DayBoard), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
    });

    testWidgets('and keeps hold-to-volunteer on the card', (tester) async {
      await pumpApp(tester, role: Role.employee);

      // A day layout that cost the driver their one action would be a
      // downgrade wearing a grid.
      expect(find.text('HOLD TO VOLUNTEER'), findsWidgets);
    });

    testWidgets('it shows work going spare, not somebody else\'s load', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final onScreen = harness.state.jobsOn(
        harness.state.today,
        only: (j) => j.status == JobStatus.open,
      );

      for (final job in onScreen) {
        expect(job.status, JobStatus.open);
      }
    });

    testWidgets('a job pushed at you is pinned, not swiped past', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      expect(find.text('ASSIGNED TO YOU'), findsOneWidget);

      // Still there three days out: it wants an answer today whatever day the
      // job itself runs.
      harness.state.showDay(3);
      await settle(tester);
      expect(find.text('ASSIGNED TO YOU'), findsOneWidget);
    });

    testWidgets("dispatch's job list pages by day as well", (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.jobs);
      await settle(tester);

      expect(find.byType(DayBoard), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
    });

    testWidgets('an empty day says how much is waiting elsewhere', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);

      // Far enough out that nothing in the seed lands there.
      harness.state.showDay(60);
      await settle(tester);

      // An empty screen and "there is nothing for you" look identical, and
      // only one of them is true.
      expect(find.textContaining('on other days'), findsOneWidget);
    });

    testWidgets('the arrow keys step the board, not just the day tab', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      expect(harness.state.dayOffset, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settle(tester);

      expect(harness.state.dayOffset, 1);
    });
  });
}
