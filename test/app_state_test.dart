import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

/// A fixed clock keeps event timestamps assertable.
DateTime _fixedNow() => DateTime(2026, 8, 2, 9, 5);

AppState makeState({List<Job>? jobs, FakePhotoService? photos}) => AppState(
  jobs: jobs,
  location: const SimulatedLocationService(),
  photos: photos ?? FakePhotoService(),
  now: _fixedNow,
);

Job jobById(AppState s, String id) => s.jobs.firstWhere((j) => j.id == id);

void main() {
  group('sign in', () {
    test('each role lands on its own first tab', () {
      final s = makeState();

      s.enter(Role.employee);
      expect(s.tab, HaulTab.board);

      s.enter(Role.manager);
      expect(s.tab, HaulTab.jobs);

      s.enter(Role.admin);
      expect(s.tab, HaulTab.overview);

      s.dispose();
    });

    test('signing out clears the session and stops location', () async {
      final s = makeState();
      s.enter(Role.admin);
      await Future<void>.delayed(Duration.zero);
      expect(s.gps.state, GpsState.simulated);

      s.signOut();
      expect(s.role, isNull);
      expect(s.gps.state, GpsState.off);
      s.dispose();
    });

    test('employee never sees money; manager does', () {
      final s = makeState();

      s.enter(Role.employee);
      expect(s.canSeeMoney, isFalse);

      s.enter(Role.manager);
      expect(s.canSeeMoney, isTrue);

      // Stepping into the crew's view hides it again — the whole point of the
      // toggle is seeing exactly what they see.
      s.toggleEmployeeView();
      expect(s.canSeeMoney, isFalse);
      expect(s.employeeView, isTrue);
      expect(s.navTabs, [HaulTab.board, HaulTab.mine]);

      s.dispose();
    });
  });

  group('claiming and accepting', () {
    test('claiming assigns the job to me and logs it', () async {
      final s = makeState()..enter(Role.employee);
      final job = jobById(s, 'HL-4471');

      await s.claim(job);

      final after = jobById(s, 'HL-4471');
      expect(after.status, JobStatus.active);
      expect(after.assignedTo, kMeId);
      expect(after.stage, 0);
      expect(after.events.single.label, 'Volunteered for this job');
      expect(after.events.single.time, '9:05 AM');
      expect(s.tab, HaulTab.mine, reason: "lands on the driver's own list");
      expect(s.toast, contains('HL-4471'));

      s.dispose();
    });

    test('accepting a pushed job flips it to active', () async {
      final s = makeState()..enter(Role.employee);
      final job = jobById(s, 'HL-4491');
      expect(job.status, JobStatus.assigned);

      await s.accept(job);

      expect(jobById(s, 'HL-4491').status, JobStatus.active);
      expect(s.toast, 'Accepted HL-4491.');
      s.dispose();
    });

    test('assigning pushes to a driver but leaves it unaccepted', () async {
      final s = makeState()..enter(Role.manager);
      await s.assign(jobById(s, 'HL-4471'), 'c2');

      final after = jobById(s, 'HL-4471');
      expect(after.status, JobStatus.assigned);
      expect(after.assignedTo, 'c2');
      expect(s.toast, contains('still have to accept'));
      s.dispose();
    });
  });

  group('stage pipeline', () {
    test('advancing walks the stages and writes the right log lines', () async {
      final s = makeState()..enter(Role.employee);
      await s.claim(jobById(s, 'HL-4471'));

      await s.advance(jobById(s, 'HL-4471'));
      expect(jobById(s, 'HL-4471').stage, 1);
      expect(
        jobById(s, 'HL-4471').events.last.label,
        'Left the yard — on the way to Philomath',
      );
      expect(jobById(s, 'HL-4471').events.last.kind, EventKind.depart);

      await s.advance(jobById(s, 'HL-4471'));
      expect(jobById(s, 'HL-4471').events.last.label, 'Arrived on site');
      expect(jobById(s, 'HL-4471').events.last.kind, EventKind.arrive);

      await s.advance(jobById(s, 'HL-4471'));
      expect(
        jobById(s, 'HL-4471').events.last.label,
        'Left the site — hauling to Coffin Butte Landfill',
      );

      await s.advance(jobById(s, 'HL-4471'));
      expect(jobById(s, 'HL-4471').stage, 4);
      s.dispose();
    });

    test('a job cannot close without both photos', () async {
      final photos = FakePhotoService();
      final s = makeState(photos: photos)..enter(Role.employee);
      await s.claim(jobById(s, 'HL-4471'));
      for (var i = 0; i < 4; i++) {
        await s.advance(jobById(s, 'HL-4471'));
      }
      expect(jobById(s, 'HL-4471').stage, 4);

      expect(await s.advance(jobById(s, 'HL-4471')), isFalse);
      expect(s.toast, contains('before and an after photo'));
      expect(jobById(s, 'HL-4471').status, JobStatus.active);

      // One photo is still not enough.
      await s.addPhoto(jobById(s, 'HL-4471'), before: true);
      expect(await s.advance(jobById(s, 'HL-4471')), isFalse);

      await s.addPhoto(jobById(s, 'HL-4471'), before: false);
      expect(await s.advance(jobById(s, 'HL-4471')), isTrue);

      final closed = jobById(s, 'HL-4471');
      expect(closed.status, JobStatus.done);
      expect(closed.stage, 5);
      expect(closed.progress, 1);
      expect(closed.events.last.label, 'Job closed');
      expect(s.closedJob?.id, 'HL-4471');
      s.dispose();
    });

    test('backing out of the camera files nothing', () async {
      final photos = FakePhotoService(cancel: true);
      final s = makeState(photos: photos)..enter(Role.employee);
      await s.claim(jobById(s, 'HL-4471'));

      await s.addPhoto(jobById(s, 'HL-4471'), before: true);

      expect(photos.captures, 1);
      expect(jobById(s, 'HL-4471').photoBefore, isNull);
      s.dispose();
    });
  });

  group('movement', () {
    test('only jobs in a travel phase advance', () {
      final s = makeState()..enter(Role.admin);
      final before = jobById(s, 'HL-4495').progress;
      final parked = jobById(s, 'HL-4491').progress;

      s.tick();

      expect(
        jobById(s, 'HL-4495').progress,
        greaterThan(before),
        reason: 'HL-4495 is on the way',
      );
      expect(
        jobById(s, 'HL-4491').progress,
        parked,
        reason: 'HL-4491 has not been accepted yet',
      );
      s.dispose();
    });

    test('progress stops at 1', () {
      final s = makeState()..enter(Role.admin);
      for (var i = 0; i < 500; i++) {
        s.tick();
      }
      expect(jobById(s, 'HL-4495').progress, 1.0);
      s.dispose();
    });

    test('ETA shrinks as a driver closes on the destination', () {
      final s = makeState()..enter(Role.admin);
      final first = jobById(s, 'HL-4495').etaMinutes();
      for (var i = 0; i < 10; i++) {
        s.tick();
      }
      expect(jobById(s, 'HL-4495').etaMinutes(), lessThan(first));
      s.dispose();
    });
  });

  group('rig matching', () {
    test(
      'a driver can only volunteer for equipment they are checked out on',
      () {
        final s = makeState()..enter(Role.employee);

        // Nate is on the dump trailer and the flatbed, not the lowboy.
        expect(s.canRun(jobById(s, 'HL-4471')), isTrue);
        expect(s.canRun(jobById(s, 'HL-4488')), isFalse);
        s.dispose();
      },
    );

    test('whitespace differences do not break the match', () {
      final me = kCrew.firstWhere((c) => c.id == kMeId);
      expect(me.canRun('Dump trailer14k'), isTrue);
      expect(me.canRun('Lowboy 25t'), isFalse);
    });
  });

  group('money roll-ups', () {
    test('revenue, cost and margin come off closed jobs only', () {
      final s = makeState()..enter(Role.admin);

      // HL-4468 is the only job closed in the seed data.
      expect(s.revenue, 470);
      expect(s.cost, 205 + 88);
      expect(s.revenue - s.cost, 177);
      s.dispose();
    });

    test("a driver's earnings only count their own closed jobs", () {
      final s = makeState()..enter(Role.employee);
      // HL-4468 belongs to K. Whitlow, not me.
      expect(s.myEarned, 0);
      s.dispose();
    });
  });

  test('leg target switches to the disposal site once loaded', () async {
    final s = makeState()..enter(Role.employee);
    await s.claim(jobById(s, 'HL-4471'));
    expect(jobById(s, 'HL-4471').legTarget.query, contains('Sunset Ridge'));

    for (var i = 0; i < 3; i++) {
      await s.advance(jobById(s, 'HL-4471'));
    }
    expect(jobById(s, 'HL-4471').stage, 3);
    expect(
      jobById(s, 'HL-4471').legTarget.query,
      'Coffin Butte Landfill, Oregon',
    );
    s.dispose();
  });

  test('a delivery never routes to a disposal site', () {
    final s = makeState()..enter(Role.employee);
    final delivery = jobById(s, 'HL-4482');
    expect(delivery.hasDisposalStop, isFalse);
    expect(delivery.legTarget.query, contains('Decker Rd'));
    s.dispose();
  });
}
