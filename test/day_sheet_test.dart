import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/day_sheet.dart';
import 'package:haul_board/calendar/event_sheet.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// The day every fixture below sits on — the one the pinned clock selects.
final DateTime kSheetDay = DateTime(2026, 8, 6);

/// A job on the sheet's day, with money on it.
///
/// Money is not in [Job.copyWith] — dispatch corrects a figure through an
/// EditJob, never by rebuilding the record — so the fixture goes round through
/// the wire format the same way the pricing tests do.
Job onSheet(
  String id, {
  String customer = 'Someone',
  List<String> equipment = const ['Dump trailer 14k'],
  DateTime? at,
  int billed = 0,
  int paid = 0,
  String paymentMethod = '',
  String? assignedTo,
}) {
  final base =
      job(
        id,
        customer: customer,
        equipment: equipment,
        at: at ?? DateTime(2026, 8, 6, 9),
      ).copyWith(
        status: assignedTo == null ? JobStatus.open : JobStatus.active,
        assignedTo: assignedTo,
      );
  return Job.fromJson({
    ...base.toJson(),
    'billed': billed,
    'paid': paid,
    'paymentMethod': paymentMethod,
  });
}

/// Opens the Calendars sheet, then the day sheet.
Future<void> openDaySheet(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Calendars'));
  await settle(tester);
  // The account row is below the fold of the sheet on a phone.
  await tester.ensureVisible(find.bySemanticsLabel('Day sheet'));
  await settle(tester);
  await tester.tap(find.bySemanticsLabel('Day sheet'));
  await settle(tester);
}

/// A finder for something on the sheet and nowhere else.
Finder onIt(Finder what) =>
    find.descendant(of: find.byType(DaySheetScreen), matching: what);

void main() {
  group('who may open the day sheet', () {
    for (final (who, role) in [
      ('an owner', Role.admin),
      ('a manager', Role.admin),
    ]) {
      testWidgets('$who is offered it', (tester) async {
        final app = await pumpApp(tester, role: role);
        expect(app.state.canSeeMoney, isTrue);

        await tester.tap(find.bySemanticsLabel('Calendars'));
        await settle(tester);
        expect(find.bySemanticsLabel('Day sheet'), findsOneWidget);
      });
    }

    testWidgets('a driver is not', (tester) async {
      final app = await pumpApp(tester, role: Role.employee);
      expect(app.state.canSeeMoney, isFalse);

      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
      expect(find.bySemanticsLabel('Day sheet'), findsNothing);
    });

    testWidgets('nor an owner standing in the crew view', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      app.state.toggleEmployeeView();
      await settle(tester);

      expect(app.state.canSeeMoney, isFalse);
      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
      expect(find.bySemanticsLabel('Day sheet'), findsNothing);
    });
  });

  group('the lanes', () {
    testWidgets('one per rig, in alphabetical order', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet('HL-1', equipment: ['Utility trailer']),
          onSheet('HL-2', equipment: ['Dump trailer 14k']),
          onSheet('HL-3', equipment: ['Enclosed trailer']),
        ],
      );

      final lanes = lanesFor(app.state, kSheetDay);
      expect(lanes.map((l) => l.rig), [
        'Dump trailer 14k',
        'Enclosed trailer',
        'Utility trailer',
      ]);
    });

    testWidgets('a job needing two rigs stands in both', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet(
            'HL-1',
            customer: 'Sunset Ridge',
            equipment: ['Dump trailer 14k', 'Enclosed trailer'],
          ),
        ],
      );

      final lanes = lanesFor(app.state, kSheetDay);
      expect(lanes.length, 2);
      for (final lane in lanes) {
        expect(lane.jobs.single.id, 'HL-1');
      }

      await openDaySheet(tester);
      // Once under each rig, because it occupies both of them.
      expect(onIt(find.text('Sunset Ridge')), findsNWidgets(2));
    });

    testWidgets('yesterday and tomorrow are not on it', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet('HL-1', at: DateTime(2026, 8, 5, 9)),
          onSheet('HL-2', at: DateTime(2026, 8, 6, 9)),
          onSheet('HL-3', at: DateTime(2026, 8, 7, 9)),
        ],
      );

      final lanes = lanesFor(app.state, kSheetDay);
      expect(lanes.single.jobs.map((j) => j.id), ['HL-2']);
    });

    testWidgets('the work is in the order of the day', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet('HL-late', at: DateTime(2026, 8, 6, 15)),
          onSheet('HL-early', at: DateTime(2026, 8, 6, 7)),
          onSheet('HL-noon', at: DateTime(2026, 8, 6, 12)),
        ],
      );

      expect(lanesFor(app.state, kSheetDay).single.jobs.map((j) => j.id), [
        'HL-early',
        'HL-noon',
        'HL-late',
      ]);
    });
  });

  group('the money', () {
    testWidgets('a lane is owed what its jobs have not settled', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet('HL-1', billed: 300, paid: 100),
          onSheet('HL-2', billed: 250),
          // Another rig, so it must not land in the first lane's total.
          onSheet('HL-3', billed: 900, equipment: ['Enclosed trailer']),
        ],
      );

      final lanes = lanesFor(app.state, kSheetDay);
      expect(lanes.first.owed, 450, reason: '200 still out plus 250');
      expect(lanes.last.owed, 900);

      await openDaySheet(tester);
      expect(onIt(find.text('Still owed')), findsNWidgets(2));
      // Only in the foot of the lane: no single row on it owes 450.
      expect(onIt(find.text('\$450')), findsOneWidget);
      // The row and the foot both, the lane having one job on it.
      expect(onIt(find.text('\$900')), findsNWidgets(2));
    });

    testWidgets('a settled job shows a dash, not a nought', (tester) async {
      await pumpApp(
        tester,
        jobs: [onSheet('HL-1', billed: 400, paid: 400, paymentMethod: 'Card')],
      );

      await openDaySheet(tester);
      expect(onIt(find.text('—')), findsOneWidget);
      expect(onIt(find.textContaining('Card')), findsOneWidget);
    });

    testWidgets('an overpayment is shown owing back, not hidden', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        jobs: [onSheet('HL-1', billed: 300, paid: 400)],
      );

      expect(jobIn(app.state, 'HL-1').owes, -100);
      await openDaySheet(tester);
      // On the row and in the foot: one job, so the lane owes what it owes.
      expect(onIt(find.text('\$-100')), findsNWidgets(2));
    });

    testWidgets('a day-only booking says so instead of a time', (tester) async {
      await pumpApp(tester, jobs: [onSheet('HL-1', at: DateTime(2026, 8, 6))]);

      await openDaySheet(tester);
      expect(onIt(find.text('All day')), findsOneWidget);
    });
  });

  group("who's working", () {
    testWidgets('whoever has a job in hand is on the last column', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        jobs: [onSheet('HL-1', assignedTo: 'c3')],
      );

      final crew = workingOn(app.state, kSheetDay);
      expect(crew.single.id, 'c3');

      await openDaySheet(tester);
      expect(onIt(find.text("Who's working")), findsOneWidget);
      expect(onIt(find.text(crew.single.name)), findsOneWidget);
    });

    testWidgets('nobody having taken anything is said plainly', (tester) async {
      final app = await pumpApp(tester, jobs: [onSheet('HL-1')]);

      expect(workingOn(app.state, kSheetDay), isEmpty);
      await openDaySheet(tester);
      expect(onIt(find.textContaining('Nobody has taken')), findsOneWidget);
    });
  });

  group('the shape of it', () {
    testWidgets('a phone stacks the lanes', (tester) async {
      await pumpApp(
        tester,
        size: const Size(420, 900),
        jobs: [
          onSheet('HL-1', equipment: ['Dump trailer 14k']),
          onSheet('HL-2', equipment: ['Enclosed trailer']),
        ],
      );

      await openDaySheet(tester);
      final dump = tester.getTopLeft(onIt(find.text('Dump trailer 14k')));
      final enclosed = tester.getTopLeft(onIt(find.text('Enclosed trailer')));
      expect(dump.dx, enclosed.dx, reason: 'the same column');
      expect(enclosed.dy, greaterThan(dump.dy), reason: 'one under the other');
    });

    testWidgets('a desk puts them side by side', (tester) async {
      await pumpApp(
        tester,
        size: const Size(1280, 900),
        jobs: [
          onSheet('HL-1', equipment: ['Dump trailer 14k']),
          onSheet('HL-2', equipment: ['Enclosed trailer']),
        ],
      );

      await openDaySheet(tester);
      final dump = tester.getTopLeft(onIt(find.text('Dump trailer 14k')));
      final enclosed = tester.getTopLeft(onIt(find.text('Enclosed trailer')));
      expect(dump.dy, enclosed.dy, reason: 'the same rule across the page');
      expect(enclosed.dx, greaterThan(dump.dx), reason: 'one beside the other');
    });

    testWidgets('it survives a small screen at 1.6x text', (tester) async {
      await pumpApp(
        tester,
        size: const Size(320, 640),
        textScale: 1.6,
        jobs: [
          onSheet('HL-1', billed: 300, paid: 100, assignedTo: 'c3'),
          onSheet('HL-2', billed: 250, equipment: ['Enclosed trailer']),
        ],
      );

      await openDaySheet(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DaySheetScreen), findsOneWidget);
    });
  });

  group('getting about', () {
    testWidgets('an empty day says so rather than showing a blank sheet', (
      tester,
    ) async {
      await pumpApp(tester, jobs: []);

      await openDaySheet(tester);
      expect(onIt(find.textContaining('Nothing booked')), findsOneWidget);
    });

    testWidgets('the arrows walk the days, and the board follows', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        jobs: [
          onSheet('HL-1', customer: 'Today', at: DateTime(2026, 8, 6, 9)),
          onSheet('HL-2', customer: 'Tomorrow', at: DateTime(2026, 8, 7, 9)),
        ],
      );

      await openDaySheet(tester);
      expect(onIt(find.text('Today')), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('The day after'));
      await settle(tester);

      expect(onIt(find.text('Tomorrow')), findsOneWidget);
      expect(onIt(find.text('Today')), findsNothing);
      expect(app.calendar.selected.day, 7);
    });

    testWidgets('a row opens the job it stands for', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [onSheet('HL-1', customer: 'Sunset Ridge', billed: 300)],
      );

      await openDaySheet(tester);
      await tester.tap(onIt(find.text('Sunset Ridge')));
      await settle(tester);

      expect(
        find.byType(DaySheetScreen),
        findsNothing,
        reason: 'the sheet let go',
      );
      expect(find.byType(EventSheet), findsOneWidget);
    });
  });
}
