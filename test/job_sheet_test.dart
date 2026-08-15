import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// A job on the pinned day, with somewhere to go and somebody to ring.
Job reachable(String id, {String phone = '541-555-0148'}) => Job.fromJson({
  ...job(id, customer: 'Sunset Ridge', at: DateTime(2026, 8, 6, 9)).toJson(),
  'address': '3820 NW Sunset Ridge Dr',
  'city': 'Philomath',
  'phone': phone,
  'access': 'Gate code 4417#. Dogs on site — call ahead.',
  'billed': 300,
});

Future<void> openIt(WidgetTester tester) async {
  await tester.tap(find.text('Dump trailer 14k').first);
  await settle(tester);
}

void main() {
  group('the address goes to maps', () {
    testWidgets('tapping it opens directions to the site', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [reachable('HL-1')],
      );

      await openIt(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Directions to, ')));
      await settle(tester);

      expect(app.links.directions, hasLength(1));
      expect(app.links.directions.single, contains('3820 NW Sunset Ridge Dr'));
      expect(app.links.directions.single, contains('Philomath'));
    });

    testWidgets('and once loaded it heads for the disposal site instead', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          Job.fromJson({
            ...reachable('HL-1').toJson(),
            'disposal': 'Coffin Butte Landfill',
            'status': 'active',
            'assignedTo': 'c1',
            'stage': 3,
          }),
        ],
      );

      await openIt(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Directions to, ')));
      await settle(tester);

      expect(app.links.directions.single, contains('Coffin Butte'));
    });

    testWidgets('the shared crew login gets it too', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [reachable('HL-1')],
      );

      await openIt(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Directions to, ')));
      await settle(tester);

      expect(app.links.directions, hasLength(1));
    });
  });

  group('the number dials', () {
    testWidgets('tapping it starts the call', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [reachable('HL-1')],
      );

      await openIt(tester);
      await tester.tap(find.bySemanticsLabel('Call, 541-555-0148'));
      await settle(tester);

      expect(app.links.calls, ['541-555-0148']);
    });

    testWidgets('a job with no number has no row to tap', (tester) async {
      final app = await pumpApp(
        tester,
        view: CalView.day,
        jobs: [reachable('HL-1', phone: '')],
      );

      await openIt(tester);
      expect(find.text('Phone'), findsNothing);
      expect(app.links.calls, isEmpty);
    });
  });

  group('the photos', () {
    testWidgets('anybody on the job can file one', (tester) async {
      // Deliberately somebody else's job, on the shared login: half the work
      // on a site is done by whoever came along, and they are the one holding
      // a phone in front of the pile.
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [
          Job.fromJson({
            ...reachable('HL-1').toJson(),
            'status': 'active',
            'assignedTo': 'c3',
            'stage': 2,
          }),
        ],
      );

      await openIt(tester);
      await tester.tap(find.bySemanticsLabel(RegExp('^Take the Before photo')));
      await settle(tester);

      expect(app.photos.captures, 1);
      expect(jobIn(app.state, 'HL-1').photosBefore, hasLength(1));
    });

    testWidgets('but only the driver on it moves the job along', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [
          Job.fromJson({
            ...reachable('HL-1').toJson(),
            'status': 'active',
            'assignedTo': 'c3',
            'stage': 2,
          }),
        ],
      );

      await openIt(tester);
      expect(find.bySemanticsLabel(RegExp('^Take the Before photo')), findsOne);
      expect(find.text('Loaded up'), findsNothing);
    });

    testWidgets('a booking nobody has priced has nothing to photograph', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          Job.fromJson({
            ...reachable('HL-1').toJson(),
            'status': 'requested',
            'billed': 0,
          }),
        ],
      );

      await openIt(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Take the Before photo')),
        findsNothing,
      );
    });
  });

  group('the notes', () {
    testWidgets('are on the block, not just inside the job', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: [reachable('HL-1')]);

      // On the calendar itself, before anybody has opened anything.
      expect(find.textContaining('Gate code 4417#'), findsWidgets);
    });

    testWidgets('and a screen reader hears them too', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: [reachable('HL-1')]);

      expect(
        find.bySemanticsLabel(RegExp('Dogs on site')),
        findsWidgets,
        reason: 'the block reads out what it shows',
      );
    });

    testWidgets('are on the list row as well', (tester) async {
      await pumpApp(tester, view: CalView.list, jobs: [reachable('HL-1')]);

      expect(find.textContaining('Gate code 4417#'), findsWidgets);
    });

    testWidgets('a job with none says nothing rather than an empty line', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      expect(find.textContaining('Gate code'), findsNothing);
    });
  });
}
