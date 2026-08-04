import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/screens/edit_job.dart';
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

    test('a manager may not', () {
      // Pricing and addresses are the owner's to change.
      expect(boot(role: Role.manager).canEditJobs, isFalse);
    });

    test('a driver may not', () {
      expect(boot(role: Role.employee).canEditJobs, isFalse);
    });

    test('nor may an owner standing in the crew view', () {
      final state = boot(role: Role.admin);
      state.toggleEmployeeView();
      expect(state.canEditJobs, isFalse);
    });

    test('the state refuses the edit, not just the button', () async {
      final state = boot(role: Role.manager);
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
        'type': 'Equipment move',
        'customer': 'Fairbanks Excavating',
        'address': '9 Mill Road',
        'city': 'Albany',
        'contact': 'Sam',
        'phone': '555-0199',
        'access': 'Gate code 4417',
        'material': 'Scrap steel',
        'volume': '2 yd',
        'weight': '~9,000 lb',
        'equipment': 'Lowboy 25t',
        'disposal': 'Pacific Recycling',
        'dumpFee': 45,
        'window': '6:00 – 8:00 AM',
        'miles': 41,
        'deadhead': 12,
        'billed': 640,
        'hazards': ['Sharp edges'],
      });

      final job = jobIn(state, 'HL-4471');
      expect(job.type, 'Equipment move');
      expect(job.address, '9 Mill Road');
      expect(job.city, 'Albany');
      expect(job.contact, 'Sam');
      expect(job.phone, '555-0199');
      expect(job.access, 'Gate code 4417');
      expect(job.material, 'Scrap steel');
      expect(job.volume, '2 yd');
      expect(job.weight, '~9,000 lb');
      expect(job.equipment, 'Lowboy 25t');
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
      await state.claim(jobIn(state, 'HL-4471'));
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
      final job = kSeedJobs.first.copyWith(stage: 3);
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

  group('the mutation', () {
    test('replaying it is a no-op once applied', () {
      final job = kSeedJobs.first;
      final edit = EditJob(
        id: 'm1',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
        fields: const {'customer': 'Fairbanks Excavating'},
      );

      final once = edit.apply(job)!;
      expect(once.customer, 'Fairbanks Excavating');
      expect(edit.apply(once), isNull);
    });

    test('it keeps the photos it says nothing about', () {
      final job = kSeedJobs.first.copyWith(
        photosBefore: [
          JobPhoto(
            id: 'p1',
            name: 'a.jpg',
            bytes: Uint8List.fromList(utf8.encode('one')),
          ),
        ],
      );
      final edit = EditJob(
        id: 'm1',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
        fields: const {'customer': 'Fairbanks Excavating'},
      );

      // An edit says nothing about photos and must not drop them on the floor.
      final after = edit.apply(job)!;
      expect(after.photosBefore, hasLength(1));
      expect(after.photosBefore.single.bytes, isNotEmpty);
    });

    test('it round-trips through the queue', () {
      final edit = EditJob(
        id: 'm1',
        jobId: 'HL-4471',
        actorId: 'c1',
        at: DateTime.utc(2026),
        fields: const {
          'payout': 210,
          'hazards': ['Loose gravel'],
        },
      );
      final copy = Mutation.fromJson(edit.toJson())! as EditJob;
      expect(copy.fields['payout'], 210);
      expect(copy.fields['hazards'], ['Loose gravel']);
      expect(copy.jobId, 'HL-4471');
    });
  });

  group('the form', () {
    testWidgets('an owner is offered it', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      expect(find.text('EDIT'), findsOneWidget);
    });

    testWidgets('a manager is not', (tester) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      expect(find.text('EDIT'), findsNothing);
    });

    testWidgets('it opens filled in with what the job already says', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.admin);
      final job = jobIn(harness.state, 'HL-4471');
      harness.state.openJobCard(job);
      await settle(tester);

      await tester.tap(find.text('EDIT'));
      await settle(tester);

      expect(find.byType(EditJobForm), findsOneWidget);
      expect(find.text(job.customer), findsWidgets);
      expect(find.text(job.address), findsWidgets);
    });

    testWidgets('changing a field saves it', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await tester.tap(find.text('EDIT'));
      await settle(tester);

      final customer = find.ancestor(
        of: find.text('Customer'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(customer, 'Fairbanks Excavating');
      await tester.tap(find.text('SAVE CHANGES'));
      await settle(tester);

      expect(jobIn(harness.state, 'HL-4471').customer, 'Fairbanks Excavating');
    });

    testWidgets('a number field will not take words', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await tester.tap(find.text('EDIT'));
      await settle(tester);

      final billed = find.ancestor(
        of: find.text('Bills at'),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(billed, '');
      await tester.tap(find.text('SAVE CHANGES'));
      await settle(tester);

      // The form stays open and says what to do rather than writing a zero.
      expect(find.text('Enter a number, or 0.'), findsOneWidget);
      expect(find.byType(EditJobForm), findsOneWidget);
    });
  });
}
