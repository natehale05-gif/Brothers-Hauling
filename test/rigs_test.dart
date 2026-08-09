import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/event_editor.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

Job booked(String id, {List<String> rigs = const ['Dump trailer 14k']}) =>
    job(id, at: DateTime(2026, 8, 6, 9), equipment: rigs);

Future<void> openNew(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('New job'));
  await settle(tester);
  await tester.enterText(find.byType(TextField).first, 'Skyline Ranch');
  await settle(tester);
}

Future<void> openEdit(WidgetTester tester) async {
  await tester.tap(find.text('Debris haul').first);
  await settle(tester);
  await tester.tap(find.bySemanticsLabel('Edit job'));
  await settle(tester);
}

void main() {
  group('a job says what it takes to do it', () {
    test('the rigs are a list, not a line of text', () {
      final j = booked('HL-1', rigs: const ['Lowboy 25t', 'Ramps']);
      expect(j.equipment, ['Lowboy 25t', 'Ramps']);
      expect(j.equipmentLabel, 'Lowboy 25t, Ramps');
    });

    test('a board written before the field was a list still reads', () {
      // Boards live in browser storage, on the yard laptop and in outboxes
      // that outlive a build. Two rigs typed into the old single box come
      // back as two, not as one string with a comma in it.
      final old = Job.fromJson({
        ...booked('HL-1').toJson(),
        'equipment': 'Lowboy 25t, Ramps',
      });
      expect(old.equipment, ['Lowboy 25t', 'Ramps']);

      final empty = Job.fromJson({...booked('HL-1').toJson(), 'equipment': ''});
      expect(empty.equipment, isEmpty);
    });

    test('and a round trip keeps every rig', () {
      final j = booked('HL-1', rigs: const ['Lowboy 25t', 'Ramps']);
      expect(Job.fromJson(j.toJson()).equipment, j.equipment);
    });
  });

  group('choosing the rigs', () {
    testWidgets('the board offers what it has already needed', (tester) async {
      await pumpApp(
        tester,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t']),
          booked('HL-2', rigs: const ['Flatbed 20ft']),
        ],
      );
      await openNew(tester);

      // Read off the work, not a fleet written into the app.
      expect(find.bySemanticsLabel('Flatbed 20ft'), findsOneWidget);
      expect(find.bySemanticsLabel('Lowboy 25t'), findsOneWidget);
    });

    testWidgets('more than one can be picked', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t']),
          booked('HL-2', rigs: const ['Ramps']),
        ],
      );
      await openNew(tester);
      await pickRig(tester, 'Lowboy 25t');
      await pickRig(tester, 'Ramps');
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.firstWhere(
        (j) => j.customer == 'Skyline Ranch',
      );
      expect(made.equipment, ['Lowboy 25t', 'Ramps']);
    });

    testWidgets('one picked twice comes off again', (tester) async {
      final app = await pumpApp(tester, jobs: [booked('HL-1')]);
      await openNew(tester);

      await pickRig(tester);
      expect(find.bySemanticsLabel('Dump trailer 14k, chosen'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Dump trailer 14k, chosen'));
      await settle(tester);

      // Nothing chosen, so the form refuses to book it.
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(find.text('Say what rig the job needs.'), findsOneWidget);
      expect(
        app.state.jobs.where((j) => j.customer == 'Skyline Ranch'),
        isEmpty,
      );
    });

    testWidgets('a rig the board has never seen can be typed in', (
      tester,
    ) async {
      final app = await pumpApp(tester, jobs: [booked('HL-1')]);
      await openNew(tester);

      await tester.enterText(find.byKey(kRigField), 'Chipper');
      await tester.tap(find.bySemanticsLabel('Add this rig'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.firstWhere(
        (j) => j.customer == 'Skyline Ranch',
      );
      expect(made.equipment, ['Chipper']);
      // And the board knows it from now on.
      expect(app.state.knownRigs, contains('Chipper'));
    });

    testWidgets('the same rig is never added twice', (tester) async {
      final app = await pumpApp(tester, jobs: [booked('HL-1')]);
      await openNew(tester);

      await pickRig(tester);
      // Typed again in a different case — the same rig, not a second one.
      await tester.enterText(find.byKey(kRigField), 'dump TRAILER 14k');
      await tester.tap(find.bySemanticsLabel('Add this rig'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.firstWhere(
        (j) => j.customer == 'Skyline Ranch',
      );
      expect(made.equipment, ['Dump trailer 14k']);
    });
  });

  group('the form will not book work nobody can load for', () {
    testWidgets('it says so, and books nothing', (tester) async {
      final app = await pumpApp(tester, jobs: [booked('HL-1')]);
      final before = app.state.jobs.length;
      await openNew(tester);

      await tester.tap(find.text('Add'));
      await settle(tester);

      expect(find.text('Say what rig the job needs.'), findsOneWidget);
      expect(app.state.jobs, hasLength(before));
      expect(find.text('New Job'), findsOneWidget, reason: 'still on the form');
    });

    testWidgets('the customer is still asked for first', (tester) async {
      await pumpApp(tester, jobs: [booked('HL-1')]);
      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      expect(find.text('Give the job a customer.'), findsOneWidget);
    });
  });

  group('changing them later', () {
    testWidgets('an existing job opens with its rigs already chosen', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t', 'Ramps']),
        ],
      );
      await openEdit(tester);

      expect(find.bySemanticsLabel('Lowboy 25t, chosen'), findsOneWidget);
      expect(find.bySemanticsLabel('Ramps, chosen'), findsOneWidget);
    });

    testWidgets('and one can be taken off and another put on', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t']),
          booked('HL-2', rigs: const ['Flatbed 20ft']),
        ],
      );
      await openEdit(tester);

      await tester.tap(find.bySemanticsLabel('Lowboy 25t, chosen'));
      await settle(tester);
      await pickRig(tester, 'Flatbed 20ft');
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').equipment, ['Flatbed 20ft']);
    });

    testWidgets('a website booking has none until dispatch says', (
      tester,
    ) async {
      // The customer cannot know what it takes, so the domain allows none —
      // the rule lives on the form, where somebody who does know is standing.
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [booked('HL-1', rigs: const [])],
      );
      expect(jobIn(app.state, 'HL-1').equipment, isEmpty);

      await openEdit(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(find.text('Say what rig the job needs.'), findsOneWidget);
      expect(jobIn(app.state, 'HL-1').equipment, isEmpty);
    });
  });

  group('what the job sheet shows', () {
    testWidgets('every rig, on one line', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t', 'Ramps']),
        ],
      );
      await tester.tap(find.text('Debris haul').first);
      await settle(tester);

      expect(find.text('Lowboy 25t, Ramps'), findsOneWidget);
    });

    testWidgets('a driver sees it too — stated, never enforced', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [
          booked('HL-1', rigs: const ['Lowboy 25t']),
        ],
      );
      await tester.tap(find.text('Debris haul').first);
      await settle(tester);

      expect(find.text('Lowboy 25t'), findsOneWidget);
      // Nothing about the rig keeps anybody off the job.
      expect(app.state.canTake(jobIn(app.state, 'HL-1')), isTrue);
    });
  });
}
