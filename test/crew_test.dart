import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/crew_screen.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// A job somebody is out on right now.
Job inHand(String id, {required String who, int stage = 1}) =>
    job(
      id,
      customer: 'Sunset Ridge Builders',
      at: DateTime(2026, 8, 6, 9),
    ).copyWith(
      status: JobStatus.active,
      assignedTo: who,
      stage: stage,
      startedAt: DateTime(2026, 8, 6, 8),
    );

/// Opens the Calendars sheet, then the crew screen.
Future<void> openCrew(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Calendars'));
  await settle(tester);
  // The account row is below the fold of the sheet on a phone.
  await tester.ensureVisible(find.bySemanticsLabel('Crew'));
  await settle(tester);
  await tester.tap(find.bySemanticsLabel('Crew'));
  await settle(tester);
}

void main() {
  group('who may watch the crew', () {
    testWidgets('an owner is offered it', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      expect(app.state.canTrackCrew, isTrue);

      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
      expect(find.bySemanticsLabel('Crew'), findsOneWidget);
    });

    for (final role in [Role.manager, Role.employee]) {
      testWidgets('a ${role.label} is not', (tester) async {
        final app = await pumpApp(tester, role: role);
        expect(app.state.canTrackCrew, isFalse);

        await tester.tap(find.bySemanticsLabel('Calendars'));
        await settle(tester);
        expect(find.bySemanticsLabel('Crew'), findsNothing);
      });
    }

    testWidgets('nor an owner standing in the crew view', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      app.state.toggleEmployeeView();
      await settle(tester);

      expect(app.state.canTrackCrew, isFalse);
    });
  });

  group('what the screen says', () {
    testWidgets('everyone on the books is on it', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      expect(find.byType(CrewScreen), findsOneWidget);
      for (final member in app.state.crew) {
        expect(
          find.text(member.name),
          findsOneWidget,
          reason: '${member.name} is on the roster',
        );
      }
    });

    testWidgets('somebody out on a job says which one and what stage', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.admin,
        jobs: [inHand('HL-1', who: 'c2', stage: 3)],
      );
      await openCrew(tester);

      // Stage three is hauling, and the job number is what gets said aloud.
      expect(find.textContaining('HL-1 · Hauling'), findsOneWidget);
    });

    testWidgets('work pushed at somebody reads as waiting on a yes', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.admin,
        jobs: [
          inHand(
            'HL-1',
            who: 'c2',
          ).copyWith(status: JobStatus.assigned, startedAt: null),
        ],
      );
      await openCrew(tester);

      expect(find.textContaining('waiting on a yes'), findsOneWidget);
    });

    testWidgets('empty hands are said plainly', (tester) async {
      await pumpApp(tester, role: Role.admin, jobs: []);
      await openCrew(tester);

      expect(find.text('Nothing in hand'), findsWidgets);
    });

    testWidgets('a closed app is said, not dressed up as a live fix', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      // K. Whitlow has the app closed with a last known place.
      expect(
        find.textContaining('App closed. Last seen Hwy 20 near Philomath'),
        findsOneWidget,
      );
    });

    testWidgets('hours come off the job stamps, with no timer to forget', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        jobs: [inHand('HL-1', who: 'c2')],
      );

      final worker = app.state.crew.firstWhere((c) => c.id == 'c2');
      expect(
        app.state.hoursToday(worker),
        greaterThan(Duration.zero),
        reason: 'started at eight, still running',
      );

      await openCrew(tester);
      expect(find.textContaining('today ·'), findsWidgets);
    });

    testWidgets('the standing count is the first thing on it', (tester) async {
      await pumpApp(
        tester,
        role: Role.admin,
        jobs: [inHand('HL-1', who: 'c2')],
      );
      await openCrew(tester);

      expect(find.textContaining('out on a job'), findsOneWidget);
    });

    testWidgets('and says so when nobody is out', (tester) async {
      await pumpApp(tester, role: Role.admin, jobs: []);
      await openCrew(tester);

      expect(find.textContaining('Nobody has a job in hand'), findsOneWidget);
    });
  });

  group('who is at the top', () {
    testWidgets('whoever is out, before whoever is idle', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        // M. Sood is off shift and last in the roster; give them the job.
        jobs: [inHand('HL-1', who: 'c4')],
      );

      expect(app.state.crew.first.id, isNot('c4'), reason: 'not already first');
      expect(crewInOrder(app.state).first.id, 'c4');
    });

    testWidgets('then whoever is on shift, then everybody else', (
      tester,
    ) async {
      final app = await pumpApp(tester, role: Role.admin, jobs: []);

      final order = crewInOrder(app.state);
      final offShift = order.indexWhere((c) => !c.onShift);
      final onShift = order.lastIndexWhere((c) => c.onShift);
      expect(
        onShift,
        lessThan(offShift),
        reason: 'nobody off shift sits above somebody on it',
      );
    });
  });
}
