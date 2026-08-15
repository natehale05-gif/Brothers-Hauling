import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/event_editor.dart';
import 'package:haul_board/calendar/views/timed_grid.dart';
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

/// Opens the job whose block reads [named] — which is the rig it takes, that
/// being what a job is called now.
Future<void> openEdit(
  WidgetTester tester, [
  String named = 'Dump trailer 14k',
]) async {
  // The block, not the column header over it — a day with two rigs on it
  // writes the same words in both places, and only one of them opens a job.
  final block = find.widgetWithText(EventBlock, named);
  await tester.tap(
    block.evaluate().isEmpty ? find.text(named).first : block.first,
  );
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

      // Shut, the row says nothing is picked and offers no list.
      expect(find.bySemanticsLabel('Rig needed, pick at least one'), findsOne);
      expect(find.text('Flatbed 20ft'), findsNothing);

      await tester.tap(find.bySemanticsLabel(RegExp('^Rig needed, ')));
      await settle(tester);

      // Open, it offers what the board has needed — read off the work, not a
      // fleet written into the app.
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Flatbed 20ft'),
        findsOne,
      );
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Lowboy 25t'),
        findsOne,
      );
    });

    testWidgets('more than one can be ticked on the same job', (tester) async {
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
      expect(
        app.state.jobs
            .firstWhere((j) => j.customer == 'Skyline Ranch')
            .equipment,
        ['Lowboy 25t', 'Ramps'],
      );
    });

    testWidgets('one picked twice comes off again', (tester) async {
      final app = await pumpApp(tester, jobs: [booked('HL-1')]);
      await openNew(tester);

      await pickRig(tester);
      expect(
        find.bySemanticsLabel('Rig needed, dump trailer 14k'),
        findsOne,
        reason: 'the row says what is on',
      );
      // Picking it again takes it off.
      await pickRig(tester);
      expect(find.bySemanticsLabel('Rig needed, pick at least one'), findsOne);

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
      await openEdit(tester, 'Lowboy 25t, Ramps');

      expect(find.bySemanticsLabel('Rig needed, lowboy 25t, ramps'), findsOne);
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
      await openEdit(tester, 'Lowboy 25t');

      // Off with one, on with the other.
      await pickRig(tester, 'Lowboy 25t');
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

      // A job with nothing on the truck is called exactly that.
      await openEdit(tester, kNoRig);
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
      await tester.tap(find.text('Lowboy 25t, Ramps').first);
      await settle(tester);

      // Once on the block behind, once in the row that lists them.
      expect(find.text('Lowboy 25t, Ramps'), findsNWidgets(2));
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
      await tester.tap(find.text('Lowboy 25t').first);
      await settle(tester);

      expect(find.text('Rig needed'), findsOneWidget);
      // Nothing about the rig keeps a job off anybody — but a driver is not
      // the one who decides who goes out on it.
      expect(app.state.canAssign, isFalse);
    });
  });
}
