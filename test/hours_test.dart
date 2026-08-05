import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/crew_member.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/models/time_entry.dart';
import 'package:haul_board/screens/tabs/dispatch_tabs.dart';
import 'package:haul_board/widgets/hours_section.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

void main() {
  /// A clock the test moves by hand, so hours are arithmetic and not a race.
  late DateTime clock;

  setUp(() => clock = DateTime(2026, 8, 2, 8));

  AppState boot({Store? store, Role role = Role.employee}) {
    final shared = store ?? MemoryStore();
    final state = AppState(
      board: LocalBoardRepository(store: shared, now: () => clock),
      store: shared,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
      now: () => clock,
    );
    addTearDown(state.dispose);
    state.enter(role);
    return state;
  }

  group('the clock runs off the job itself', () {
    test('it starts when the driver takes the job on', () async {
      final state = boot();
      expect(jobIn(state, 'HL-4471').startedAt, isNull);

      await state.claim(jobIn(state, 'HL-4471'));

      // No timer to remember to start — taking the job is starting the clock.
      expect(jobIn(state, 'HL-4471').startedAt, clock);
      expect(jobIn(state, 'HL-4471').onTheClock, isTrue);
    });

    test('accepting a pushed job starts it too', () async {
      final state = boot();
      await state.accept(jobIn(state, 'HL-4491'));
      expect(jobIn(state, 'HL-4491').startedAt, clock);
    });

    test('it stops when the job closes, and only then', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));

      clock = clock.add(const Duration(hours: 2));
      for (var i = 0; i < 4; i++) {
        await state.advance(jobIn(state, 'HL-4471'));
      }
      // Four stages in and still running: the middle of a job is not the end.
      expect(jobIn(state, 'HL-4471').finishedAt, isNull);

      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: false);
      clock = clock.add(const Duration(minutes: 30));
      await state.advance(jobIn(state, 'HL-4471'));

      expect(jobIn(state, 'HL-4471').finishedAt, clock);
      expect(jobIn(state, 'HL-4471').onTheClock, isFalse);
      expect(
        jobIn(state, 'HL-4471').workedBy(clock),
        const Duration(hours: 2, minutes: 30),
      );
    });

    test('a running job counts up to now', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      clock = clock.add(const Duration(minutes: 45));

      expect(
        jobIn(state, 'HL-4471').workedBy(clock),
        const Duration(minutes: 45),
      );
    });

    test('a job nobody has taken has no hours', () {
      final state = boot();
      expect(jobIn(state, 'HL-4471').workedBy(clock), Duration.zero);
    });

    test('a clock that appears to run backwards reads as zero', () {
      final job = kJobFor(
        startedAt: DateTime(2026, 8, 2, 10),
        finishedAt: DateTime(2026, 8, 2, 9),
      );
      // Two devices, two clocks. A negative shift is not a credit.
      expect(job.workedBy(clock), Duration.zero);
    });

    test('the hours survive a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store);
      await first.restore();
      await first.claim(jobIn(first, 'HL-4471'));
      final started = jobIn(first, 'HL-4471').startedAt;

      final second = boot(store: store);
      await second.restore();
      expect(jobIn(second, 'HL-4471').startedAt, started);
    });
  });

  group('the timesheet', () {
    test('adds a person up across their jobs', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      clock = clock.add(const Duration(hours: 1));
      await state.accept(jobIn(state, 'HL-4491'));
      clock = clock.add(const Duration(hours: 1));

      final me = state.crew.firstWhere((c) => c.id == 'c1');
      // Two jobs running: one for two hours, one for one.
      expect(state.timesheetFor(me).worked, const Duration(hours: 3));
      expect(state.timesheetFor(me).onTheClock, isTrue);
    });

    test('it only counts the person it belongs to', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      clock = clock.add(const Duration(hours: 2));

      final other = state.crew.firstWhere((c) => c.id != 'c1');
      expect(
        state.timesheetFor(other).entries.map((e) => e.job.id),
        isNot(contains('HL-4471')),
      );
    });

    test('pay is hours times the rate', () {
      final member = const CrewMember(
        id: 'c9',
        name: 'Dale Whitlow',
        initials: 'DW',
        unit: 'Truck 12',
        onShift: true,
        appOpen: true,
        rig: [],
        hourlyRate: 30,
      );
      final sheet = Timesheet(
        member: member,
        entries: [
          TimeEntry(
            crewId: 'c9',
            job: kJobFor(
              startedAt: DateTime(2026, 8, 2, 8),
              finishedAt: DateTime(2026, 8, 2, 14, 30),
            ),
            startedAt: DateTime(2026, 8, 2, 8),
            finishedAt: DateTime(2026, 8, 2, 14, 30),
          ),
        ],
        now: clock,
      );

      expect(sheet.minutes, 390);
      expect(sheet.pay, 195); // 6.5 hours at $30
    });

    test('no rate reads as missing, never as free', () {
      final member = const CrewMember(
        id: 'c9',
        name: 'Nobody Priced',
        initials: 'NP',
        unit: '',
        onShift: true,
        appOpen: false,
        rig: [],
      );
      final sheet = Timesheet(member: member, entries: const [], now: clock);

      // Zero would read as "worked for nothing" rather than "nobody has said
      // what they earn".
      expect(sheet.pay, isNull);
    });

    test('everyone appears, even at nothing', () {
      final state = boot(role: Role.admin);
      expect(
        state.timesheets.map((t) => t.member.id).toSet(),
        state.crew.map((c) => c.id).toSet(),
      );
    });
  });

  group('who may see hours and pay', () {
    test('an owner may', () {
      expect(boot(role: Role.admin).canSeeHoursAndPay, isTrue);
    });

    test('a manager may not', () {
      // Rates are the owner's business.
      expect(boot(role: Role.manager).canSeeHoursAndPay, isFalse);
    });

    test('a driver may not', () {
      expect(boot(role: Role.employee).canSeeHoursAndPay, isFalse);
    });

    test('nor may an owner in the crew view', () {
      final state = boot(role: Role.admin)..toggleEmployeeView();
      expect(state.canSeeHoursAndPay, isFalse);
    });
  });

  group('a driver sees their time and no money', () {
    testWidgets('their own hours start counting the moment they claim', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final state = harness.state;
      expect(state.timeEntries.where((e) => e.crewId == 'c1'), isEmpty);

      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);

      // The harness clock does not move, so the figure is zero — what matters
      // is that the entry exists and is running.
      final mine = state.timeEntries.where((e) => e.crewId == 'c1');
      expect(mine, hasLength(1));
      expect(mine.single.running, isTrue);
      expect(state.myHoursToday, Duration.zero);
    });

    testWidgets('and no figure anywhere on it', (tester) async {
      await pumpApp(tester, role: Role.employee);

      // Pay is hourly and what an hour is worth is between the driver and
      // payroll, so there is nothing here for the app to announce.
      expect(find.textContaining(RegExp(r'\$\d')), findsNothing);
      expect(find.textContaining('your cut'), findsNothing);
    });

    testWidgets('the hours section is not on their crew screen', (
      tester,
    ) async {
      // A driver has no crew screen at all, so there is nowhere for it to be.
      final harness = await pumpApp(tester, role: Role.employee);
      expect(harness.state.navTabs, isNot(contains(HaulTab.crew)));
      expect(find.byType(HoursSection), findsNothing);
    });

    testWidgets('nor on a manager\'s, who does have one', (tester) async {
      final harness = await pumpApp(tester, role: Role.manager);
      expect(harness.state.navTabs, contains(HaulTab.crew));

      harness.state.setTab(HaulTab.crew);
      await settle(tester);

      // The roster is a manager's business. What people earn is not.
      expect(find.byType(CrewTab), findsOneWidget);
      expect(find.text('Hours'), findsNothing);
      expect(find.text('Hours on the books'), findsNothing);
    });
  });

  group('the owner reads everyone individually', () {
    /// Claiming switches the tab to "My jobs", so any work is done before the
    /// hours screen is opened rather than after.
    Future<Harness> openHours(
      WidgetTester tester, {
      bool withWork = false,
    }) async {
      final harness = await pumpApp(
        tester,
        role: Role.admin,
        size: const Size(1280, 900),
      );
      if (withWork) {
        await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      }
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      return harness;
    }

    testWidgets('everyone on the crew has a row', (tester) async {
      final harness = await openHours(tester);
      expect(find.byType(HoursSection), findsOneWidget);
      for (final member in harness.state.crew) {
        expect(find.text(member.name), findsWidgets);
      }
    });

    testWidgets('a row says the hours and what they come to', (tester) async {
      final handle = tester.ensureSemantics();
      await openHours(tester, withWork: true);

      expect(find.bySemanticsLabel(RegExp('Open their hours')), findsWidgets);
      handle.dispose();
    });

    testWidgets('opening a person lists every job they worked', (tester) async {
      await openHours(tester, withWork: true);

      // Scoped to the tab: the top bar carries the signed-in name too. The
      // roster row is the way in — hours are not a second list of the same
      // people further down the same screen.
      await tester.tap(
        find.descendant(
          of: find.byType(CrewTab),
          matching: find.text('Nate R.'),
        ),
      );
      await settle(tester);

      expect(find.text('Nate R. — hours'), findsOneWidget);
      expect(find.text('EVERY JOB'), findsOneWidget);
      expect(find.textContaining('HL-4471'), findsWidgets);
    });

    testWidgets('someone with no hours says so rather than showing nothing', (
      tester,
    ) async {
      final harness = await openHours(tester);
      final idle = harness.state.crew.firstWhere(
        (c) => harness.state.timesheetFor(c).entries.isEmpty,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(CrewTab),
          matching: find.text(idle.name),
        ),
      );
      await settle(tester);
      expect(find.text('No hours on the books yet.'), findsOneWidget);
    });
  });

  group('formatting', () {
    test('reads like a timesheet, not a decimal', () {
      expect(formatWorked(const Duration(hours: 6, minutes: 20)), '6h 20m');
      expect(formatWorked(const Duration(minutes: 20)), '20m');
      expect(formatWorked(const Duration(hours: 6)), '6h');
      expect(formatWorked(Duration.zero), '0m');
    });

    test('and says it in words for a screen reader', () {
      expect(
        describeWorked(const Duration(hours: 1, minutes: 1)),
        '1 hour 1 minute',
      );
      expect(describeWorked(const Duration(hours: 2)), '2 hours');
      expect(describeWorked(Duration.zero), 'no time yet');
    });
  });
}

/// A job with nothing on it but a clock.
Job kJobFor({DateTime? startedAt, DateTime? finishedAt}) => Job(
  id: 'HL-1',
  type: 'Debris haul',
  customer: 'Someone',
  address: '',
  city: '',
  contact: '',
  phone: '',
  access: '',
  material: '',
  volume: '',
  weight: '',
  equipment: '',
  disposal: 'N/A',
  dumpFee: 0,
  window: '',
  miles: 0,
  deadhead: 0,
  billed: 0,
  startedAt: startedAt,
  finishedAt: finishedAt,
);
