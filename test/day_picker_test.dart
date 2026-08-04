import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/screens/job_detail.dart';
import 'package:haul_board/services/link_service.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/widgets/day_picker.dart';

void main() {
  final now = DateTime(2026, 8, 2, 9);

  group('a day reads the way somebody says it', () {
    test('the near ones get their name', () {
      expect(sayDay(DateTime(2026, 8, 2), now), 'Today');
      expect(sayDay(DateTime(2026, 8, 3), now), 'Tomorrow');
      expect(sayDay(DateTime(2026, 8, 1), now), 'Yesterday');
    });

    test('the time of day does not make it a different day', () {
      // The board says "Thursday", never "Thursday at 14:07 because that is
      // when somebody typed it".
      expect(sayDay(DateTime(2026, 8, 2, 23, 59), now), 'Today');
    });

    test('further off gets a weekday and a date', () {
      expect(sayDay(DateTime(2026, 8, 6), now), 'Thu 6 Aug');
    });

    test('and the year only when it is not this one', () {
      expect(sayDay(DateTime(2027, 1, 4), now), 'Mon 4 Jan 2027');
    });

    test('nothing set says so, rather than showing an empty box', () {
      expect(sayDay(null, now), 'No day set');
    });

    test('a screen reader gets it in full words', () {
      expect(describeDay(DateTime(2026, 8, 6), now), 'Thursday 6 August 2026');
      expect(
        describeDay(DateTime(2026, 8, 3), now),
        'Tomorrow, Monday 3 August 2026',
      );
      expect(describeDay(null, now), 'No day set');
    });
  });

  group('the stored form', () {
    test('is midnight, so a day is a day and not a moment', () {
      final stored = dayToStored(DateTime(2026, 8, 6, 14, 7));
      expect(DateTime.parse(stored!), DateTime(2026, 8, 6));
    });

    test('nothing set stores nothing', () {
      expect(dayToStored(null), isNull);
    });
  });

  group('the picker', () {
    late DateTime clock;

    setUp(() => clock = DateTime(2026, 8, 2, 9));

    Future<DateTime?> pumpField(WidgetTester tester, DateTime? start) async {
      DateTime? got;
      var value = start;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => DayField(
                value: value,
                now: clock,
                onChanged: (day) => setState(() {
                  value = day;
                  got = day;
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return got;
    }

    testWidgets('says which day it is on', (tester) async {
      await pumpField(tester, DateTime(2026, 8, 6));
      expect(find.text('Thu 6 Aug'), findsOneWidget);
    });

    testWidgets('offers the three days anybody actually picks', (tester) async {
      await pumpField(tester, DateTime(2026, 8, 6));
      for (final name in ['Today', 'Tomorrow', 'Next week']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('one tap moves it to tomorrow', (tester) async {
      await pumpField(tester, DateTime(2026, 8, 6));

      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();

      // The whole point: no calendar, no typing, no format to remember.
      expect(find.text('Tomorrow'), findsWidgets);
      expect(find.text('Thu 6 Aug'), findsNothing);
    });

    testWidgets('and one tap clears it', (tester) async {
      await pumpField(tester, DateTime(2026, 8, 6));

      await tester.tap(find.text('No day'));
      await tester.pumpAndSettle();

      expect(find.text('No day set'), findsOneWidget);
    });

    testWidgets('there is nothing to clear when nothing is set', (
      tester,
    ) async {
      await pumpField(tester, null);
      expect(find.text('No day'), findsNothing);
    });

    testWidgets('the calendar is still there behind it', (tester) async {
      await pumpField(tester, DateTime(2026, 8, 6));

      await tester.tap(find.text('Thu 6 Aug'));
      await tester.pumpAndSettle();

      expect(find.text('PICK A DAY'), findsOneWidget);
    });
  });

  group('moving one job, without the rest of the form', () {
    late DateTime clock;

    setUp(() => clock = DateTime(2026, 8, 2, 9));

    /// The state first, so the job comes from the same seeded board the
    /// widget reads — a job picked off a differently-clocked AppState is
    /// scheduled on a different day than the one under test.
    AppState boot() {
      final store = MemoryStore();
      final state = AppState(
        board: LocalBoardRepository(store: store, now: () => clock),
        store: store,
        location: const SimulatedLocationService(),
        photos: FakePhotoService(),
        autoAdvance: false,
        toastDuration: null,
        now: () => clock,
      );
      addTearDown(state.dispose);
      state.enter(Role.admin);
      return state;
    }

    Future<void> pumpDetail(
      WidgetTester tester,
      AppState state,
      Job job,
    ) async {
      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: Scaffold(
              body: JobDetail(job: job, links: RecordingLinkService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the day is a button on the job itself', (tester) async {
      final state = boot();
      final job = state.jobs.firstWhere((j) => j.scheduledFor != null);
      await pumpDetail(tester, state, job);

      expect(
        find.text(sayDay(job.scheduledDay, state.today).toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('tapping it opens the mover, not the whole form', (
      tester,
    ) async {
      final state = boot();
      final job = state.jobs.firstWhere((j) => j.scheduledFor != null);
      await pumpDetail(tester, state, job);

      await tester.tap(
        find.text(sayDay(job.scheduledDay, state.today).toUpperCase()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Move ${job.id}'), findsOneWidget);
      // The point of a separate mover is that it is not twenty other fields.
      expect(find.text('Bills at'), findsNothing);
    });

    testWidgets('two taps put a job on tomorrow', (tester) async {
      final state = boot();
      final job = state.jobs.firstWhere((j) => j.scheduledFor != null);
      await pumpDetail(tester, state, job);

      await tester.tap(
        find.text(sayDay(job.scheduledDay, state.today).toUpperCase()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MOVE IT'));
      await tester.pumpAndSettle();

      expect(
        state.jobs.firstWhere((j) => j.id == job.id).scheduledDay,
        state.today.add(const Duration(days: 1)),
      );
    });

    testWidgets('a driver is not offered it', (tester) async {
      final store = MemoryStore();
      final state = AppState(
        board: LocalBoardRepository(store: store, now: () => clock),
        store: store,
        location: const SimulatedLocationService(),
        photos: FakePhotoService(),
        autoAdvance: false,
        toastDuration: null,
        now: () => clock,
      );
      addTearDown(state.dispose);
      state.enter(Role.employee);
      final job = state.jobs.first;

      await tester.pumpWidget(
        AppScope(
          state: state,
          child: MaterialApp(
            home: Scaffold(
              body: JobDetail(job: job, links: RecordingLinkService()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The schedule is dispatch's to change, not the person driving to it.
      expect(find.text('EDIT'), findsNothing);
    });
  });
}
