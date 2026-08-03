import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/data/seed_data.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

void main() {
  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  AppState boot({Store? store}) {
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
    return state;
  }

  group('a job takes as many shots as it needs', () {
    test('before photos stack up instead of replacing each other', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));

      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);

      // One photo rarely covers a job — the pile, the access, and the thing
      // the customer will later say was already broken.
      expect(jobIn(state, 'HL-4471').photosBefore, hasLength(3));
      expect(jobIn(state, 'HL-4471').photosAfter, isEmpty);
    });

    test('before and after stay in their own slots', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: false);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: false);

      final job = jobIn(state, 'HL-4471');
      expect(job.photosBefore, hasLength(1));
      expect(job.photosAfter, hasLength(2));
      expect(job.photos, hasLength(3), reason: 'before shots come first');
      expect(job.photos.first.id, job.photosBefore.first.id);
    });

    test('one of each is still all the gate asks for', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      expect(jobIn(state, 'HL-4471').photosComplete, isFalse);

      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      expect(
        jobIn(state, 'HL-4471').photosComplete,
        isFalse,
        reason: 'two before shots and no after shot is not a closed job',
      );

      await state.addPhoto(jobIn(state, 'HL-4471'), before: false);
      expect(jobIn(state, 'HL-4471').photosComplete, isTrue);
    });

    test('replaying a filed photo does not duplicate it', () {
      final job = kSeedJobs.first.copyWith(
        photosBefore: [JobPhoto(id: 'p1', name: 'a.jpg', bytes: bytes('one'))],
      );
      final again = AttachPhoto(
        id: 'm1',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
        photoId: 'p1',
        photoName: 'a.jpg',
        before: true,
      );

      // Idempotent by photo id now, not by slot — because "there is already a
      // before photo" has stopped being a reason to drop one.
      expect(again.apply(job, photoBytes: {'p1': bytes('one')}), isNull);
    });

    test('a second distinct photo is not mistaken for a replay', () {
      final job = kSeedJobs.first.copyWith(
        photosBefore: [JobPhoto(id: 'p1', name: 'a.jpg', bytes: bytes('one'))],
      );
      final second = AttachPhoto(
        id: 'm2',
        jobId: job.id,
        actorId: 'c1',
        at: DateTime.utc(2026),
        photoId: 'p2',
        photoName: 'b.jpg',
        before: true,
      );

      final after = second.apply(job, photoBytes: {'p2': bytes('two')});
      expect(after!.photosBefore.map((p) => p.id), ['p1', 'p2']);
    });

    test('every shot survives a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store);
      await first.restore();
      await first.claim(jobIn(first, 'HL-4471'));
      for (var i = 0; i < 3; i++) {
        await first.addPhoto(jobIn(first, 'HL-4471'), before: true);
      }

      final second = boot(store: store);
      await second.restore();
      expect(jobIn(second, 'HL-4471').photosBefore, hasLength(3));
      for (final p in jobIn(second, 'HL-4471').photosBefore) {
        expect(p.bytes, isNotEmpty);
      }
    });
  });

  group('a board written by the previous build still loads', () {
    // A phone running the shipped version has a board on it in the old shape.
    // Losing a driver's before shot on upgrade would be the exact failure the
    // outbox exists to prevent.
    test('the old single-slot keys are read into the lists', () {
      final job = Job.fromJson(
        {
          'id': 'HL-1',
          'photoBefore': {'id': 'old-b', 'name': 'before.jpg'},
          'photoAfter': {'id': 'old-a', 'name': 'after.jpg'},
        },
        photoBytes: {'old-b': bytes('b'), 'old-a': bytes('a')},
      );

      expect(job.photosBefore.single.id, 'old-b');
      expect(job.photosAfter.single.id, 'old-a');
      expect(job.photosComplete, isTrue);
    });

    test('a board saved by this build round-trips its lists', () {
      final job = kSeedJobs.first.copyWith(
        photosBefore: [
          JobPhoto(id: 'p1', name: 'a.jpg', bytes: bytes('1')),
          JobPhoto(id: 'p2', name: 'b.jpg', bytes: bytes('2')),
        ],
        photosAfter: [JobPhoto(id: 'p3', name: 'c.jpg', bytes: bytes('3'))],
      );
      final copy = Job.fromJson(
        jsonDecode(jsonEncode(job.toJson())) as Map<String, Object?>,
        photoBytes: {'p1': bytes('1'), 'p2': bytes('2'), 'p3': bytes('3')},
      );

      expect(copy.photosBefore.map((p) => p.id), ['p1', 'p2']);
      expect(copy.photosAfter.map((p) => p.id), ['p3']);
    });
  });

  group('arriving on site asks for the before photo', () {
    test('it is not due before the driver gets there', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      expect(jobIn(state, 'HL-4471').stage, lessThan(kOnSiteStage));
      expect(state.beforePhotoDue(jobIn(state, 'HL-4471')), isFalse);
    });

    test('it comes due on arrival', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      while (jobIn(state, 'HL-4471').stage < kOnSiteStage) {
        await state.advance(jobIn(state, 'HL-4471'));
      }
      expect(state.beforePhotoDue(jobIn(state, 'HL-4471')), isTrue);
    });

    test('taking the photo answers it', () async {
      final state = boot();
      await state.claim(jobIn(state, 'HL-4471'));
      while (jobIn(state, 'HL-4471').stage < kOnSiteStage) {
        await state.advance(jobIn(state, 'HL-4471'));
      }

      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      expect(state.beforePhotoDue(jobIn(state, 'HL-4471')), isFalse);
    });

    test("'not yet' silences it for this sitting only", () async {
      final store = MemoryStore();
      final first = boot(store: store);
      await first.restore();
      await first.claim(jobIn(first, 'HL-4471'));
      while (jobIn(first, 'HL-4471').stage < kOnSiteStage) {
        await first.advance(jobIn(first, 'HL-4471'));
      }

      first.waiveBeforePhotoPrompt('HL-4471');
      expect(first.beforePhotoDue(jobIn(first, 'HL-4471')), isFalse);

      // Next launch it asks again: the photo is still missing and the load is
      // still sitting there.
      final second = boot(store: store);
      await second.restore();
      expect(second.beforePhotoDue(jobIn(second, 'HL-4471')), isTrue);
    });

    test("it never asks about someone else's job", () async {
      final state = boot();
      final mine = jobIn(state, 'HL-4471');
      await state.claim(mine);
      while (jobIn(state, 'HL-4471').stage < kOnSiteStage) {
        await state.advance(jobIn(state, 'HL-4471'));
      }

      final theirs = state.jobs.firstWhere(
        (j) => j.assignedTo != null && j.assignedTo != 'c1',
      );
      expect(state.beforePhotoDue(theirs), isFalse);
    });
  });

  group('the prompt on screen', () {
    testWidgets('appears on the job card once the driver is on site', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final state = harness.state;
      await state.claim(jobIn(state, 'HL-4471'));
      while (jobIn(state, 'HL-4471').stage < kOnSiteStage) {
        await state.advance(jobIn(state, 'HL-4471'));
      }
      state.openJobCard(jobIn(state, 'HL-4471'));
      await settle(tester);

      expect(find.textContaining("You're on site"), findsOneWidget);
      expect(find.text('TAKE THE BEFORE PHOTO'), findsOneWidget);
    });

    testWidgets('taking the shot clears it', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final state = harness.state;
      await state.claim(jobIn(state, 'HL-4471'));
      while (jobIn(state, 'HL-4471').stage < kOnSiteStage) {
        await state.advance(jobIn(state, 'HL-4471'));
      }
      state.openJobCard(jobIn(state, 'HL-4471'));
      await settle(tester);

      await tester.tap(find.text('TAKE THE BEFORE PHOTO'));
      await settle(tester);

      expect(find.textContaining("You're on site"), findsNothing);
      expect(jobIn(state, 'HL-4471').photosBefore, hasLength(1));
    });

    testWidgets('the strip counts the shots it is holding', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final state = harness.state;
      await state.claim(jobIn(state, 'HL-4471'));
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      state.openJobCard(jobIn(state, 'HL-4471'));
      await settle(tester);
      // The card's body is a lazy list; the photo strips are below the fold.
      await scrollTo(tester, find.text('BEFORE · 2 PHOTOS'));

      expect(find.text('BEFORE · 2 PHOTOS'), findsOneWidget);
      expect(find.text('AFTER — NONE YET'), findsOneWidget);
    });

    testWidgets('each filed shot is named for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpApp(tester, role: Role.employee);
      final state = harness.state;
      await state.claim(jobIn(state, 'HL-4471'));
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      await state.addPhoto(jobIn(state, 'HL-4471'), before: true);
      state.openJobCard(jobIn(state, 'HL-4471'));
      await settle(tester);
      await scrollTo(tester, find.text('BEFORE · 2 PHOTOS'));

      expect(find.bySemanticsLabel('before photo 1 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('before photo 2 of 2'), findsOneWidget);
      expect(find.bySemanticsLabel('Add another before photo'), findsOneWidget);
      handle.dispose();
    });
  });
}
