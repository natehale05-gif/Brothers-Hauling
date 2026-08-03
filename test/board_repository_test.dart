import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/outbox.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/mutation.dart';

/// A server that can be switched off, the way a truck's signal is.
class _Link {
  SendOutcome outcome = SendOutcome.accepted;
  final List<Mutation> received = [];

  Future<SendOutcome> call(Mutation mutation) async {
    if (outcome == SendOutcome.accepted) received.add(mutation);
    return outcome;
  }
}

int _seq = 0;
String _id() => 'mut-${_seq++}';

void main() {
  late MemoryStore store;
  late _Link link;

  setUp(() {
    store = MemoryStore();
    link = _Link();
    _seq = 0;
  });

  /// A fresh repository over the same storage — i.e. the app relaunching.
  Future<LocalBoardRepository> open() async {
    final repo = LocalBoardRepository(store: store, send: link.call);
    await repo.load();
    return repo;
  }

  Job jobIn(BoardRepository repo, String id) =>
      repo.jobs.firstWhere((j) => j.id == id);

  Mutation claim(String jobId) =>
      ClaimJob(id: _id(), jobId: jobId, actorId: 'c1', at: DateTime.utc(2026));

  Mutation advance(String jobId, int toStage) => AdvanceStage(
    id: _id(),
    jobId: jobId,
    actorId: 'c1',
    at: DateTime.utc(2026),
    toStage: toStage,
  );

  group('the board outlives the process', () {
    test('a claim is still there after a relaunch', () async {
      final first = await open();
      expect(await first.apply(claim('HL-4471')), isTrue);
      expect(jobIn(first, 'HL-4471').status, JobStatus.active);

      final second = await open();
      final job = jobIn(second, 'HL-4471');
      expect(job.status, JobStatus.active);
      expect(job.assignedTo, 'c1');
      expect(job.events.single.label, 'Volunteered for this job');
    });

    test('a whole shift of stage changes replays in order', () async {
      final first = await open();
      await first.apply(claim('HL-4471'));
      for (var stage = 1; stage <= 3; stage++) {
        await first.apply(advance('HL-4471', stage));
      }

      final second = await open();
      final job = jobIn(second, 'HL-4471');
      expect(job.stage, 3);
      expect(
        job.events.map((e) => e.label),
        containsAllInOrder([
          'Volunteered for this job',
          'Left the yard — on the way to Philomath',
          'Arrived on site',
        ]),
      );
    });

    test('photo pixels come back, not just the record', () async {
      final pixels = Uint8List.fromList(utf8.encode('a real photograph'));
      final photo = JobPhoto(id: 'photo-1', name: 'before.jpg', bytes: pixels);

      final first = await open();
      await first.apply(claim('HL-4471'));
      await first.apply(
        AttachPhoto(
          id: _id(),
          jobId: 'HL-4471',
          actorId: 'c1',
          at: DateTime.utc(2026),
          photoId: photo.id,
          photoName: photo.name,
          before: true,
        ),
        photo: photo,
      );

      final second = await open();
      final restored = jobIn(second, 'HL-4471').photoBefore;
      expect(restored, isNotNull);
      expect(utf8.decode(restored!.bytes), 'a real photograph');
    });

    test('a board file that was half-written falls back to the seed', () async {
      await store.writeString('board.v1', '[{"id": "HL-4471", trunc');

      final repo = await open();
      // The app comes up on today's board rather than refusing to start.
      expect(repo.jobs, isNotEmpty);
      expect(repo.jobs.first.id, 'HL-4471');
    });
  });

  group('a driver with no signal', () {
    test('sees the change immediately and keeps it', () async {
      link.outcome = SendOutcome.retry;

      final repo = await open();
      expect(await repo.apply(claim('HL-4471')), isTrue);

      // Applied locally despite nothing reaching the server.
      expect(jobIn(repo, 'HL-4471').status, JobStatus.active);
      expect(link.received, isEmpty);
      expect(repo.syncState.pending, 1);
      expect(repo.syncState.settled, isFalse);
    });

    test('the queued work survives a relaunch in the dead zone', () async {
      link.outcome = SendOutcome.retry;
      final first = await open();
      await first.apply(claim('HL-4471'));
      await first.apply(advance('HL-4471', 1));

      final second = await open();
      expect(jobIn(second, 'HL-4471').stage, 1);
      expect(second.syncState.pending, 2);
    });

    test('everything lands, in order, once signal returns', () async {
      link.outcome = SendOutcome.retry;
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      await repo.apply(advance('HL-4471', 1));
      await repo.apply(advance('HL-4471', 2));
      expect(repo.syncState.pending, 3);

      link.outcome = SendOutcome.accepted;
      // Signal is back: retry now rather than waiting out the backoff.
      await repo.sync(force: true);

      expect(link.received.map((m) => m.kind), ['claim', 'advance', 'advance']);
      expect(repo.syncState.pending, 0);
      expect(repo.syncState.settled, isTrue);
      expect(repo.syncState.lastSyncedAt, isNotNull);
    });

    test('names exactly which jobs are unsettled', () async {
      link.outcome = SendOutcome.retry;
      final repo = await open();
      await repo.apply(claim('HL-4471'));

      expect(repo.unsyncedJobIds, {'HL-4471'});
      expect(repo.unsyncedJobIds.contains('HL-4482'), isFalse);
    });

    test('reports being offline only after a send actually failed', () async {
      final repo = await open();
      expect(repo.syncState.offline, isFalse);

      link.outcome = SendOutcome.retry;
      await repo.apply(claim('HL-4471'));
      await repo.sync();
      expect(repo.syncState.offline, isTrue);

      link.outcome = SendOutcome.accepted;
      await repo.sync(force: true);
      expect(repo.syncState.offline, isFalse);
    });
  });

  group('work the server refuses', () {
    test('is surfaced as failed rather than retried forever', () async {
      link.outcome = SendOutcome.rejected;
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      await repo.sync();

      expect(repo.syncState.pending, 0);
      expect(repo.syncState.failed, 1);
      expect(repo.syncState.settled, isFalse);
    });

    test('can be put back in the queue by hand', () async {
      link.outcome = SendOutcome.rejected;
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      await repo.sync();
      expect(repo.syncState.failed, 1);

      link.outcome = SendOutcome.accepted;
      await repo.retryFailed();

      expect(repo.syncState.failed, 0);
      expect(repo.syncState.pending, 0);
      expect(link.received, hasLength(1));
    });
  });

  group('mutations that no longer make sense are refused', () {
    test('claiming a job that is already taken', () async {
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      await repo.sync(force: true);
      expect(repo.syncState.pending, 0);

      expect(await repo.apply(claim('HL-4471')), isFalse);
      // Nothing queued for a change that was not made.
      expect(repo.syncState.pending, 0);
    });

    test('advancing to a stage already passed', () async {
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      await repo.apply(advance('HL-4471', 2));

      expect(await repo.apply(advance('HL-4471', 1)), isFalse);
      expect(jobIn(repo, 'HL-4471').stage, 2);
    });

    test('a mutation for a job that is not on this board', () async {
      final repo = await open();
      expect(await repo.apply(claim('HL-9999')), isFalse);
    });

    test('closing without both photos, even by replay', () async {
      final repo = await open();
      await repo.apply(claim('HL-4471'));
      for (var stage = 1; stage <= 4; stage++) {
        await repo.apply(advance('HL-4471', stage));
      }
      expect(await repo.apply(advance('HL-4471', 5)), isFalse);
      expect(jobIn(repo, 'HL-4471').status, isNot(JobStatus.done));
    });
  });

  group('housekeeping', () {
    test('photo pixels nobody references any more are swept', () async {
      final repo = await open();
      await store.writeBytes(
        'photo.v1.orphan',
        Uint8List.fromList(const [1, 2, 3]),
      );

      final photo = JobPhoto(
        id: 'photo-kept',
        name: 'after.jpg',
        bytes: Uint8List.fromList(const [4, 5, 6]),
      );
      await repo.apply(claim('HL-4471'));
      await repo.apply(
        AttachPhoto(
          id: _id(),
          jobId: 'HL-4471',
          actorId: 'c1',
          at: DateTime.utc(2026),
          photoId: photo.id,
          photoName: photo.name,
          before: true,
        ),
        photo: photo,
      );

      expect(await repo.sweepOrphanedPhotos(), 1);
      expect(await store.readBytes('photo.v1.orphan'), isNull);
      expect(await store.readBytes('photo.v1.photo-kept'), isNotNull);
    });

    test('listeners hear about every board change', () async {
      final repo = await open();
      var notifications = 0;
      repo.addListener(() => notifications++);

      await repo.apply(claim('HL-4471'));
      expect(notifications, greaterThan(0));
    });
  });
}
