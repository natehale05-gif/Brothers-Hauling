import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/crew_screen.dart';
import 'package:haul_board/calendar/form_bits.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:flutter/material.dart';

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

/// Scrolls the crew screen until [what] has been built and is on screen.
///
/// The roster is a lazy list and the hire form sits under all of it, so a
/// finder alone never sees it — there is nothing built to find.
Future<void> scrollTo(WidgetTester tester, Finder what) async {
  await tester.scrollUntilVisible(
    what,
    240,
    // Named, and named precisely: the calendar is still mounted behind this
    // screen, and every text field on it carries a scrollable of its own.
    scrollable: find
        .descendant(
          of: find.byType(CrewScreen),
          matching: find.byType(Scrollable),
        )
        .first,
    maxScrolls: 40,
  );
  await settle(tester);
}

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

  group('taking somebody on', () {
    testWidgets('an owner can, and they land on the roster', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      final before = app.state.crew.length;
      await scrollTo(tester, find.text('Take somebody on'));
      await tester.enterText(find.byType(TextField).first, 'R. Okafor');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Add to the crew'));
      await settle(tester);

      expect(app.state.crew, hasLength(before + 1));
      final hired = app.state.crew.firstWhere((c) => c.name == 'R. Okafor');
      expect(hired.role, Role.employee, reason: 'the first level offered');
      // Nobody is on shift the moment they are hired, and nobody has the app
      // open before they have installed it.
      expect(hired.onShift, isFalse);
      expect(hired.appOpen, isFalse);
    });

    testWidgets('a name is asked for before anybody is added', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);
      final before = app.state.crew.length;

      await scrollTo(tester, find.text('Take somebody on'));
      await tester.tap(find.bySemanticsLabel('Add to the crew'));
      await settle(tester);

      expect(app.state.crew, hasLength(before));
      expect(find.text('Say who you are taking on.'), findsOneWidget);
    });

    testWidgets('and the level can be picked off the menu', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      await scrollTo(tester, find.text('Take somebody on'));
      await tester.tap(find.bySemanticsLabel(RegExp('^Level, ')).last);
      await settle(tester);
      await tester.tap(find.text('Manager').last);
      await settle(tester);

      await tester.enterText(find.byType(TextField).first, 'J. Reyes');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Add to the crew'));
      await settle(tester);

      expect(
        app.state.crew.firstWhere((c) => c.name == 'J. Reyes').role,
        Role.manager,
      );
    });
  });

  group('moving somebody between levels', () {
    testWidgets('an owner can promote a driver', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      final them = app.state.crew.firstWhere((c) => c.id == 'c2');
      expect(them.role, Role.employee);

      // By the widget rather than by its label: several people on a roster
      // each have a level, and this names whose without depending on how the
      // row happens to word itself.
      final row = find.byWidgetPredicate(
        (w) =>
            w is ChoiceRow<Role> && w.spokenLabel == 'Level for ${them.name}',
      );
      await scrollTo(tester, row);
      await tester.tap(row);
      await settle(tester);
      await tester.tap(find.text('Manager').last);
      await settle(tester);

      expect(app.state.crew.firstWhere((c) => c.id == 'c2').role, Role.manager);
    });

    testWidgets('but not their own, which is a door with no handle', (
      tester,
    ) async {
      final app = await pumpApp(tester, role: Role.admin);
      await openCrew(tester);

      // Nothing is offered against the signed-in owner, so the only way to
      // lock yourself out is not there to press.
      final me = app.state.crew.firstWhere((c) => c.id == app.state.meId);
      expect(find.text(me.name), findsOneWidget);
      expect(await app.state.setCrewRole(me, Role.employee), isFalse);
    });
  });
}
