import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';

import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

void main() {
  AppState boot({Store? store, Role? role}) {
    final shared = store ?? MemoryStore();
    final state = AppState(
      board: LocalBoardRepository(store: shared),
      store: shared,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
    );
    addTearDown(state.dispose);
    if (role != null) state.enter(role);
    return state;
  }

  group('who may correct a job', () {
    test('an owner may', () {
      expect(boot(role: Role.admin).canEditJobs, isTrue);
    });

    test('a driver may not', () {
      // Prices and addresses are the owner's to change.
      expect(boot(role: Role.driver).canEditJobs, isFalse);
    });

    test('nor may the shared crew login', () {
      expect(boot(role: Role.employee).canEditJobs, isFalse);
    });

    test('nor may an owner standing in the crew view', () {
      final state = boot(role: Role.admin);
      state.toggleEmployeeView();
      expect(state.canEditJobs, isFalse);
    });

    test('the state refuses the edit, not just the button', () async {
      final state = boot(role: Role.driver);
      final before = jobIn(state, 'HL-4471').billed;

      final ok = await state.editJob(jobIn(state, 'HL-4471'), {'billed': 999});

      expect(ok, isFalse);
      expect(jobIn(state, 'HL-4471').billed, before);
      expect(state.toast, contains('Only an owner'));
    });
  });

  group('editing', () {
    test('changes exactly the fields it names', () async {
      final state = boot(role: Role.admin);
      final before = jobIn(state, 'HL-4471');

      await state.editJob(before, {
        'customer': 'Fairbanks Excavating',
        'billed': 610,
      });

      final after = jobIn(state, 'HL-4471');
      expect(after.customer, 'Fairbanks Excavating');
      expect(after.billed, 610);
      // Everything unnamed is untouched.
      expect(after.address, before.address);
      expect(after.dumpFee, before.dumpFee);
      expect(after.equipment, before.equipment);
    });

    test('every editable field can actually be edited', () async {
      final state = boot(role: Role.admin);

      await state.editJob(jobIn(state, 'HL-4471'), {
        'type': 'Lowboy 25t',
        'customer': 'Fairbanks Excavating',
        'address': '9 Mill Road',
        'city': 'Albany',
        'contact': 'Sam',
        'phone': '555-0199',
        'access': 'Gate code 4417',
        'material': 'Scrap steel',
        'volume': '2 yd',
        'weight': '~9,000 lb',
        'equipment': ['Lowboy 25t', 'Ramps'],
        'disposal': 'Pacific Recycling',
        'dumpFee': 45,
        'window': '6:00 – 8:00 AM',
        'miles': 41,
        'deadhead': 12,
        'billed': 640,
        'hazards': ['Sharp edges'],
      });

      final job = jobIn(state, 'HL-4471');
      expect(job.address, '9 Mill Road');
      expect(job.city, 'Albany');
      expect(job.contact, 'Sam');
      expect(job.phone, '555-0199');
      expect(job.access, 'Gate code 4417');
      expect(job.material, 'Scrap steel');
      expect(job.volume, '2 yd');
      expect(job.weight, '~9,000 lb');
      expect(job.equipment, ['Lowboy 25t', 'Ramps']);
      expect(job.disposal, 'Pacific Recycling');
      expect(job.dumpFee, 45);
      expect(job.window, '6:00 – 8:00 AM');
      expect(job.miles, 41);
      expect(job.deadhead, 12);
      expect(job.billed, 640);
      expect(job.hazards, ['Sharp edges']);
    });

    test('it lands in the movement log', () async {
      final state = boot(role: Role.admin);
      await state.editJob(jobIn(state, 'HL-4471'), {'billed': 610});

      // Dispatch quietly changing a job's terms is exactly the thing a driver
      // needs to be able to see afterwards.
      expect(jobIn(state, 'HL-4471').events.last.label, contains('Dispatch'));
      expect(jobIn(state, 'HL-4471').events.last.label, contains('bills at'));
    });

    test('it survives a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store, role: Role.admin);
      await first.restore();
      await first.editJob(jobIn(first, 'HL-4471'), {
        'customer': 'Fairbanks Excavating',
      });

      final second = boot(store: store, role: Role.admin);
      await second.restore();
      expect(jobIn(second, 'HL-4471').customer, 'Fairbanks Excavating');
    });

    test('an edit that changes nothing is not recorded', () async {
      final state = boot(role: Role.admin);
      final job = jobIn(state, 'HL-4471');
      final events = job.events.length;

      final ok = await state.editJob(job, {'customer': job.customer});

      expect(ok, isFalse);
      expect(jobIn(state, 'HL-4471').events, hasLength(events));
    });
  });

  group('what an edit may not touch', () {
    test('the record of what the driver did is out of reach', () async {
      final state = boot(role: Role.admin);
      await takeOn(state, 'HL-4471');
      await state.advance(jobIn(state, 'HL-4471'));
      final before = jobIn(state, 'HL-4471');

      await state.editJob(before, {
        'stage': 0,
        'status': 'open',
        'assignedTo': null,
        'photosBefore': const [],
        'events': const [],
        // ...alongside one that is allowed, so the call is not simply a no-op.
        'customer': 'Fairbanks Excavating',
      });

      final after = jobIn(state, 'HL-4471');
      expect(after.customer, 'Fairbanks Excavating');
      expect(after.stage, before.stage, reason: 'the stage is the driver\'s');
      expect(after.status, before.status);
      expect(after.assignedTo, before.assignedTo);
      expect(after.events.length, greaterThan(before.events.length - 1));
    });

    test('the mutation filters again on the way out of the queue', () {
      // The queue survives an upgrade, so a mutation written by a build with a
      // different idea of what is editable still cannot reach past the list.
      final job = seedJobs(DateTime(2026, 8, 2)).first.copyWith(stage: 3);
      final forged = EditJob(
        id: 'm1',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
        fields: const {'stage': 0, 'status': 'open'},
      );

      expect(forged.apply(job), isNull);
    });
  });
}
