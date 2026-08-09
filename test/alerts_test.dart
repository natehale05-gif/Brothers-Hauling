import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/services/alert_service.dart';

import 'calendar_event_test.dart' show job;
import 'calendar_view_test.dart' show bookedJobs;
import 'helpers.dart';

/// Records what it was asked to schedule, and can refuse the way a phone does.
class FakeAlertService extends AlertService {
  FakeAlertService({this.allow = true});

  bool allow;
  int asks = 0;
  int syncs = 0;
  final List<Alert> _scheduled = [];

  @override
  List<Alert> get scheduled => List.unmodifiable(_scheduled);

  @override
  Future<bool> ensureAllowed() async {
    asks++;
    return allow;
  }

  @override
  Future<void> sync(List<Alert> alerts) async {
    syncs++;
    _scheduled
      ..clear()
      ..addAll(alerts);
  }
}

void main() {
  final now = DateTime(2026, 8, 6, 9, 30);

  group('when a reminder is due', () {
    test('a job with no alert is owed nothing', () {
      expect(job('HL-1', at: DateTime(2026, 8, 7, 9)).alertAt, isNull);
      expect(alertFor(job('HL-1', at: DateTime(2026, 8, 7, 9))), isNull);
    });

    test('a job with no date is owed nothing either', () {
      expect(job('HL-1').copyWith(alertMinutes: 30).alertAt, isNull);
    });

    test('counts back from the start', () {
      final booked = job(
        'HL-1',
        at: DateTime(2026, 8, 7, 9),
      ).copyWith(alertMinutes: 30);
      expect(booked.alertAt, DateTime(2026, 8, 7, 8, 30));
    });

    test('zero means when it starts', () {
      final booked = job(
        'HL-1',
        at: DateTime(2026, 8, 7, 9),
      ).copyWith(alertMinutes: 0);
      expect(booked.alertAt, DateTime(2026, 8, 7, 9));
    });

    test('a day before crosses the midnight properly', () {
      final booked = job(
        'HL-1',
        at: DateTime(2026, 8, 7, 7),
      ).copyWith(alertMinutes: 1440);
      expect(booked.alertAt, DateTime(2026, 8, 6, 7));
    });
  });

  group('what the reminder says', () {
    test('carries the work, the customer, the place and the time', () {
      final booked = job(
        'HL-1',
        type: 'Junk removal',
        customer: 'Harrison St rental',
        city: 'Corvallis',
        at: DateTime(2026, 8, 7, 9),
      ).copyWith(alertMinutes: 30);

      final alert = alertFor(booked)!;
      expect(alert.title, 'Junk removal for Harrison St rental');
      expect(alert.body, 'Corvallis, at 9:00 AM');
      expect(alert.at, DateTime(2026, 8, 7, 8, 30));
    });

    test('an all-day job says the day rather than a made-up hour', () {
      final booked = job(
        'HL-1',
        city: 'Alsea',
        at: DateTime(2026, 8, 7),
      ).copyWith(alertMinutes: 0);
      expect(alertFor(booked)!.body, 'Alsea, today');
    });

    test('falls back to the job number when there is no address', () {
      final booked = job(
        'HL-1',
        at: DateTime(2026, 8, 7, 9),
      ).copyWith(alertMinutes: 0);
      expect(alertFor(booked)!.body, contains('HL-1'));
    });

    test('the same job always lands on the same slot', () {
      final a = alertFor(
        job('HL-1', at: DateTime(2026, 8, 7, 9)).copyWith(alertMinutes: 30),
      )!;
      final b = alertFor(
        job('HL-1', at: DateTime(2026, 8, 9, 14)).copyWith(alertMinutes: 60),
      )!;
      // Moving the job must reuse the slot, or the old reminder is orphaned.
      expect(a.id, b.id);
      expect(a.id, isNot(0));
    });
  });

  group('what a board is owed', () {
    test('only work with an alert still ahead of it', () {
      final jobs = [
        // Already gone by.
        job('past', at: DateTime(2026, 8, 6, 9)).copyWith(alertMinutes: 30),
        // Still to come.
        job('soon', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 30),
        // No alert asked for.
        job('quiet', at: DateTime(2026, 8, 7, 9)),
      ];
      expect(alertsFor(jobs, now).map((a) => a.jobId), ['soon']);
    });

    test('a closed job never buzzes', () {
      final jobs = [
        job(
          'done',
          at: DateTime(2026, 8, 8, 9),
        ).copyWith(alertMinutes: 30, status: JobStatus.done),
      ];
      expect(alertsFor(jobs, now), isEmpty);
    });

    test('soonest first', () {
      final jobs = [
        job('later', at: DateTime(2026, 8, 9, 9)).copyWith(alertMinutes: 30),
        job('sooner', at: DateTime(2026, 8, 7, 9)).copyWith(alertMinutes: 30),
      ];
      expect(alertsFor(jobs, now).map((a) => a.jobId), ['sooner', 'later']);
    });
  });

  group('the device', () {
    testWidgets('is told again every time the board moves', (tester) async {
      final alerts = FakeAlertService();
      final app = await pumpApp(tester, jobs: bookedJobs(), alerts: alerts);

      final before = alerts.syncs;
      await app.state.addJob(
        type: 'Gravel delivery',
        customer: 'Skyline Ranch',
        scheduledFor: DateTime(2026, 8, 12, 13),
        alertMinutes: 60,
      );
      await settle(tester);

      expect(alerts.syncs, greaterThan(before));
      expect(alerts.scheduled.map((a) => a.jobId), contains(isNotNull));
      expect(
        alerts.scheduled.any((a) => a.title.contains('Skyline Ranch')),
        isTrue,
      );
    });

    testWidgets('drops a reminder when the job is deleted', (tester) async {
      final alerts = FakeAlertService();
      final app = await pumpApp(
        tester,
        alerts: alerts,
        jobs: [
          job('HL-1', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 30),
        ],
      );
      await app.state.syncAlerts();
      expect(alerts.scheduled, hasLength(1));

      await app.state.deleteJob(jobIn(app.state, 'HL-1'));
      await settle(tester);

      expect(alerts.scheduled, isEmpty);
    });

    testWidgets('moves a reminder when the job moves', (tester) async {
      final alerts = FakeAlertService();
      final app = await pumpApp(
        tester,
        alerts: alerts,
        jobs: [
          job('HL-1', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 30),
        ],
      );
      await app.state.syncAlerts();
      expect(alerts.scheduled.single.at, DateTime(2026, 8, 6, 13, 30));

      await app.state.rescheduleJob(
        jobIn(app.state, 'HL-1'),
        startsAt: DateTime(2026, 8, 6, 17),
      );
      await settle(tester);

      expect(alerts.scheduled.single.at, DateTime(2026, 8, 6, 16, 30));
    });

    testWidgets('says so when the phone refuses', (tester) async {
      final alerts = FakeAlertService(allow: false);
      final app = await pumpApp(tester, jobs: bookedJobs(), alerts: alerts);

      expect(await app.state.enableAlerts(), isFalse);
      expect(app.state.alertsAllowed, isFalse);
      expect(alerts.asks, 1);
    });

    testWidgets('the sheet says how many are set', (tester) async {
      final alerts = FakeAlertService();
      final app = await pumpApp(
        tester,
        alerts: alerts,
        jobs: [
          job('HL-1', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 30),
        ],
      );
      await app.state.syncAlerts();
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);

      expect(find.text('Reminders'), findsOneWidget);
      expect(find.textContaining('1 reminder set'), findsOneWidget);
    });
  });

  group('setting one from the editor', () {
    testWidgets('carries onto the job, and asks the phone', (tester) async {
      final alerts = FakeAlertService();
      final app = await pumpApp(tester, jobs: bookedJobs(), alerts: alerts);

      await tester.tap(find.bySemanticsLabel('New job'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Skyline Ranch');
      await settle(tester);
      // The rig first, while its row is still on screen: the form is a list,
      // and what has scrolled off the top of one is not in the tree to tap.
      await pickRig(tester);
      // Settled before scrolling: ensureVisible measures the layout it is
      // given, and the one mid-keystroke is not the one that gets tapped.
      await settle(tester);
      // Fifteen, not thirty: the form opens the job at ten and the clock is
      // half past nine, so a half-hour warning would be due exactly now —
      // which counts as gone by, and would not be scheduled at all.
      // The chip, not the row above it that names the current choice.
      await tester.ensureVisible(find.text('15 min before').last);
      await settle(tester);
      await tester.tap(find.text('15 min before').last);
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);

      final made = app.state.jobs.firstWhere(
        (j) => j.customer == 'Skyline Ranch',
      );
      expect(made.alertMinutes, 15);
      expect(alerts.asks, greaterThan(0));
      expect(
        alerts.scheduled.any((a) => a.title.contains('Skyline Ranch')),
        isTrue,
      );
    });

    testWidgets('none by default, and can be taken off again', (tester) async {
      final app = await pumpApp(
        tester,
        jobs: [
          job('HL-1', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 30),
        ],
      );

      await tester.tap(find.text('Debris haul').last);
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Edit job'));
      await settle(tester);

      expect(find.text('30 min before'), findsWidgets);
      await tester.ensureVisible(find.text('None').last);
      await settle(tester);
      await tester.tap(find.text('None').last);
      await settle(tester);
      await tester.tap(find.text('Done'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').alertMinutes, isNull);
    });

    testWidgets('shows on the job sheet', (tester) async {
      await pumpApp(
        tester,
        jobs: [
          job('HL-1', at: DateTime(2026, 8, 6, 14)).copyWith(alertMinutes: 60),
        ],
      );

      await tester.tap(find.text('Debris haul').last);
      await settle(tester);

      expect(find.text('Alert'), findsOneWidget);
      expect(find.text('1 hour before'), findsOneWidget);
    });
  });
}
