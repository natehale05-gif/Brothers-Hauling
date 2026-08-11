import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/photo_service.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// A job somebody is out on, at whatever stage the caller wants.
Job running(String id, {required String who, int stage = 0}) =>
    job(id, at: DateTime(2026, 8, 6, 9)).copyWith(
      status: JobStatus.active,
      assignedTo: who,
      stage: stage,
      startedAt: DateTime(2026, 8, 6, 8),
    );

Future<void> openJob(WidgetTester tester) async {
  await tester.tap(find.text('Debris haul').first);
  await settle(tester);
}

void main() {
  group('working a job', () {
    testWidgets('the person on it gets the stage and the way on', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [running('HL-1', who: kMeId)],
      );
      await openJob(tester);

      // Once in the panel the driver works from, once on the Status row that
      // everybody looking at this job can see.
      expect(find.text('Accepted'), findsNWidgets(2));
      expect(find.text('1 of 6'), findsOneWidget);
      expect(find.text('Roll out'), findsOneWidget);
    });

    testWidgets('and pressing it moves the job on', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [running('HL-1', who: kMeId)],
      );
      await openJob(tester);

      await tester.tap(find.text('Roll out'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').stage, 1);
      // The button is the next step now, not the one just taken.
      expect(find.text("I'm on site"), findsOneWidget);
      expect(find.text('Driving to site'), findsNWidgets(2));
    });

    testWidgets('somebody else on the board is only shown where it is up to', (
      tester,
    ) async {
      // The log, the hours and the photos are the record of what a driver did.
      // A record an owner can fill in from a desk is not one.
      await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [running('HL-1', who: 'somebody-else', stage: 2)],
      );
      await openJob(tester);

      expect(find.text('Loaded up'), findsNothing);
      expect(find.text('Take the Before photo'), findsNothing);
      // The Status row still says where it has got to.
      expect(find.text('Loading'), findsOneWidget);
    });

    testWidgets('a job nobody has taken shows none of it', (tester) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );
      await openJob(tester);

      expect(find.text('Roll out'), findsNothing);
    });
  });

  group('the two photos', () {
    testWidgets('are taken from the job and filed against it', (tester) async {
      final photos = FakePhotoService();
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        photos: photos,
        jobs: [running('HL-1', who: kMeId, stage: 2)],
      );
      await openJob(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Take the Before photo')));
      await settle(tester);
      expect(jobIn(app.state, 'HL-1').photosBefore, hasLength(1));

      // A second one goes on the same side rather than replacing the first.
      await tester.tap(find.bySemanticsLabel(RegExp('^Add another Before')));
      await settle(tester);
      expect(jobIn(app.state, 'HL-1').photosBefore, hasLength(2));
      expect(jobIn(app.state, 'HL-1').photosAfter, isEmpty);
    });

    testWidgets('a driver who backs out of the camera files nothing', (
      tester,
    ) async {
      final photos = FakePhotoService(cancel: true);
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        photos: photos,
        jobs: [running('HL-1', who: kMeId, stage: 2)],
      );
      await openJob(tester);

      await tester.tap(find.bySemanticsLabel(RegExp('^Take the Before photo')));
      await settle(tester);
      expect(jobIn(app.state, 'HL-1').photosBefore, isEmpty);
    });

    testWidgets('the before shot is called for once the driver is on site', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [running('HL-1', who: kMeId, stage: 2)],
      );
      expect(app.state.beforePhotoDue(jobIn(app.state, 'HL-1')), isTrue);

      await openJob(tester);
      expect(find.bySemanticsLabel(RegExp('you are on site')), findsOneWidget);
    });

    testWidgets('and is not, before anybody has got there', (tester) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [running('HL-1', who: kMeId)],
      );
      await openJob(tester);

      expect(find.bySemanticsLabel(RegExp('you are on site')), findsNothing);
    });
  });

  group('closing it out', () {
    /// A job one press from closed.
    Future<Harness> atTheDump(
      WidgetTester tester, {
      bool photos = false,
    }) async {
      final shots = FakePhotoService();
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        photos: shots,
        jobs: [running('HL-1', who: kMeId, stage: kStages.length - 2)],
      );
      if (photos) {
        await app.state.addPhoto(jobIn(app.state, 'HL-1'), before: true);
        await app.state.addPhoto(jobIn(app.state, 'HL-1'), before: false);
        await settle(tester);
      }
      return app;
    }

    testWidgets('is refused until both photos are on the job', (tester) async {
      final app = await atTheDump(tester);
      await openJob(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Close it out'),
      );
      expect(button.onPressed, isNull, reason: 'and says so before the press');
      expect(find.textContaining('before it can be closed'), findsOneWidget);
      expect(jobIn(app.state, 'HL-1').status, JobStatus.active);
    });

    testWidgets('and goes through once they are', (tester) async {
      final app = await atTheDump(tester, photos: true);
      await openJob(tester);

      expect(jobIn(app.state, 'HL-1').photosComplete, isTrue);
      await tester.tap(find.text('Close it out'));
      await settle(tester);

      final after = jobIn(app.state, 'HL-1');
      expect(after.status, JobStatus.done);
      expect(after.stage, kStages.length - 1);
    });
  });

  group('what the app says back', () {
    testWidgets('a refusal is drawn, not swallowed', (tester) async {
      // Every one of these messages went nowhere before there was anywhere to
      // put them, which reads as "that worked".
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [job('HL-1', at: DateTime(2026, 8, 6, 9))],
      );

      await app.state.publishJob(jobIn(app.state, 'HL-1'));
      await settle(tester);

      expect(
        find.text('Put a price on it before it goes to the crew.'),
        findsOne,
      );
    });
  });
}
