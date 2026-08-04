import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/outbox.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/mutation.dart';

/// A clock the test drives, so backoff can be verified without waiting for it.
class _Clock {
  DateTime value = DateTime.utc(2026, 8, 2, 9);
  DateTime call() => value;
  void advance(Duration d) => value = value.add(d);
}

/// Stands in for the server.
class _Server {
  SendOutcome outcome = SendOutcome.accepted;
  Object? throwWith;
  final List<Mutation> received = [];

  /// Per-mutation-id override, for "this one is refused, the rest are fine".
  final Map<String, SendOutcome> perMutation = {};

  Future<SendOutcome> call(Mutation mutation) async {
    received.add(mutation);
    final failure = throwWith;
    if (failure != null) {
      throwWith = null;
      throw failure;
    }
    return perMutation[mutation.id] ?? outcome;
  }
}

int _seq = 0;
Mutation advance(String jobId, {int toStage = 1, String? id}) => AdvanceStage(
  id: id ?? 'm${_seq++}',
  jobId: jobId,
  actorId: 'c1',
  at: DateTime.utc(2026, 8, 2, 9),
  toStage: toStage,
);

void main() {
  late MemoryStore store;
  late _Server server;
  late _Clock clock;

  Outbox makeOutbox({int maxAttempts = 8}) => Outbox(
    store: store,
    send: server.call,
    now: clock.call,
    maxAttempts: maxAttempts,
    baseBackoff: const Duration(seconds: 2),
  );

  setUp(() {
    store = MemoryStore();
    server = _Server();
    clock = _Clock();
  });

  group('durability', () {
    test('queued work survives the process dying', () async {
      final first = makeOutbox();
      await first.add(advance('HL-4471'));
      await first.add(advance('HL-4482'));

      // No dispose, no drain — the phone died mid-shift.
      final revived = makeOutbox();
      await revived.load();

      expect(revived.pendingCount, 2);
      // Only job changes carry a job — hiring someone does not.
      expect((revived.pending.first.mutation as JobMutation).jobId, 'HL-4471');
      expect((revived.pending.last.mutation as JobMutation).jobId, 'HL-4482');
    });

    test('the attempt count and backoff survive too', () async {
      server.outcome = SendOutcome.retry;
      final first = makeOutbox();
      await first.add(advance('HL-4471'));
      await first.drain();

      final revived = makeOutbox();
      await revived.load();

      expect(revived.pending.single.attempts, 1);
      expect(revived.pending.single.nextAttempt, isNotNull);
    });

    test(
      'a corrupt queue file starts clean instead of refusing to boot',
      () async {
        await store.writeString('outbox.v1', '{"pending": [ truncated');

        final outbox = makeOutbox();
        await outbox.load();

        expect(outbox.pendingCount, 0);
      },
    );

    test(
      'a mutation kind this build does not know is skipped, not fatal',
      () async {
        await store.writeString(
          'outbox.v1',
          jsonEncode({
            'pending': [
              {
                'mutation': {
                  'id': 'm1',
                  'kind': 'teleport',
                  'jobId': 'HL-4471',
                  'actorId': 'c1',
                  'at': '2026-08-02T09:00:00Z',
                },
              },
              {'mutation': advance('HL-4482', id: 'm2').toJson()},
            ],
          }),
        );

        final outbox = makeOutbox();
        await outbox.load();

        expect(outbox.pendingCount, 1);
        expect(outbox.pending.single.mutation.id, 'm2');
      },
    );
  });

  group('draining', () {
    test('sends in the order the driver did the work', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471', toStage: 1, id: 'a'));
      await outbox.add(advance('HL-4471', toStage: 2, id: 'b'));
      await outbox.add(advance('HL-4471', toStage: 3, id: 'c'));

      await outbox.drain();

      expect(server.received.map((m) => m.id), ['a', 'b', 'c']);
      expect(outbox.pendingCount, 0);
      expect(outbox.isEmpty, isTrue);
    });

    test('nothing behind a failing mutation is sent past it', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471', toStage: 1, id: 'a'));
      await outbox.add(advance('HL-4471', toStage: 2, id: 'b'));
      server.perMutation['a'] = SendOutcome.retry;

      await outbox.drain();

      // "Loaded up" must not reach the server before "arrived on site".
      expect(server.received.map((m) => m.id), ['a']);
      expect(outbox.pendingCount, 2);
    });

    test('backs off, then goes through once the wait has passed', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471', id: 'a'));
      server.perMutation['a'] = SendOutcome.retry;

      await outbox.drain();
      expect(outbox.pending.single.attempts, 1);

      // Too soon: the send is not even attempted again.
      await outbox.drain();
      expect(server.received.length, 1);

      clock.advance(const Duration(seconds: 3));
      server.perMutation.remove('a');
      await outbox.drain();

      expect(server.received.length, 2);
      expect(outbox.isEmpty, isTrue);
    });

    test('backoff grows and is capped', () async {
      final outbox = Outbox(
        store: store,
        send: server.call,
        now: clock.call,
        baseBackoff: const Duration(seconds: 1),
        maxBackoff: const Duration(seconds: 10),
      );
      server.outcome = SendOutcome.retry;
      await outbox.add(advance('HL-4471'));

      final waits = <Duration>[];
      for (var i = 0; i < 6; i++) {
        await outbox.drain();
        waits.add(outbox.pending.single.nextAttempt!.difference(clock.value));
        clock.advance(const Duration(hours: 1)); // clear the wait
      }

      expect(waits[0], const Duration(seconds: 1));
      expect(waits[1], const Duration(seconds: 2));
      expect(waits[2], const Duration(seconds: 4));
      expect(waits[3], const Duration(seconds: 8));
      expect(waits[4], const Duration(seconds: 10), reason: 'capped');
      expect(waits[5], const Duration(seconds: 10));
    });

    test('a thrown exception is treated as retryable and recorded', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471'));
      server.throwWith = Exception('SocketException: failed host lookup');

      await outbox.drain();

      expect(outbox.pendingCount, 1);
      expect(outbox.pending.single.attempts, 1);
      expect(outbox.pending.single.lastError, contains('failed host lookup'));
    });

    test('overlapping drains collapse into one pass', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471', id: 'a'));
      await outbox.add(advance('HL-4471', id: 'b'));

      await Future.wait([outbox.drain(), outbox.drain(), outbox.drain()]);

      // Each mutation goes exactly once, even with three callers.
      expect(server.received.map((m) => m.id), ['a', 'b']);
    });
  });

  group('work that will never succeed', () {
    test('a rejected mutation steps aside so the rest can flow', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471', id: 'a'));
      await outbox.add(advance('HL-4482', id: 'b'));
      server.perMutation['a'] = SendOutcome.rejected;

      await outbox.drain();

      expect(outbox.pendingCount, 0);
      expect(outbox.abandoned.single.mutation.id, 'a');
      expect(server.received.map((m) => m.id), ['a', 'b']);
    });

    test('a mutation is given up on rather than retried forever', () async {
      final outbox = makeOutbox(maxAttempts: 3);
      server.outcome = SendOutcome.retry;
      await outbox.add(advance('HL-4471', id: 'a'));

      for (var i = 0; i < 3; i++) {
        await outbox.drain();
        clock.advance(const Duration(minutes: 10));
      }

      expect(outbox.pendingCount, 0);
      expect(outbox.abandoned.single.attempts, 3);
      expect(outbox.abandoned.single.lastError, isNotNull);
    });

    test('abandoned work is never silently dropped', () async {
      final outbox = makeOutbox(maxAttempts: 1);
      server.outcome = SendOutcome.rejected;
      await outbox.add(advance('HL-4471', id: 'a'));
      await outbox.drain();

      // Still there after a restart — this is a driver's unpaid work.
      final revived = makeOutbox();
      await revived.load();
      expect(revived.abandoned.single.mutation.id, 'a');
      expect(revived.isEmpty, isFalse);
    });

    test('a driver can put abandoned work back in the queue', () async {
      final outbox = makeOutbox(maxAttempts: 1);
      server.outcome = SendOutcome.retry;
      await outbox.add(advance('HL-4471', id: 'a'));
      await outbox.drain();
      expect(outbox.abandoned, hasLength(1));

      server.outcome = SendOutcome.accepted;
      await outbox.retryAbandoned();
      expect(outbox.pending.single.attempts, 0, reason: 'a clean slate');

      await outbox.drain();
      expect(outbox.isEmpty, isTrue);
    });

    test('discarding is explicit and complete', () async {
      final outbox = makeOutbox(maxAttempts: 1);
      server.outcome = SendOutcome.rejected;
      await outbox.add(advance('HL-4471', id: 'a'));
      await outbox.drain();

      await outbox.discardAbandoned();
      expect(outbox.isEmpty, isTrue);

      final revived = makeOutbox();
      await revived.load();
      expect(revived.isEmpty, isTrue);
    });
  });

  group('what the UI needs to know', () {
    test('reports exactly which jobs carry unsent work', () async {
      final outbox = makeOutbox();
      await outbox.add(advance('HL-4471'));
      await outbox.add(advance('HL-4482'));
      await outbox.add(advance('HL-4471', toStage: 2));

      expect(outbox.pendingJobIds, {'HL-4471', 'HL-4482'});
    });

    test('abandoned jobs still count as unsettled', () async {
      final outbox = makeOutbox(maxAttempts: 1);
      server.outcome = SendOutcome.rejected;
      await outbox.add(advance('HL-4495'));
      await outbox.drain();

      expect(outbox.pendingJobIds, {'HL-4495'});
    });

    test('emits a change whenever the queue moves', () async {
      final outbox = makeOutbox();
      var changes = 0;
      final sub = outbox.changes.listen((_) => changes++);

      await outbox.add(advance('HL-4471'));
      await outbox.drain();
      await Future<void>.delayed(Duration.zero);

      expect(changes, greaterThanOrEqualTo(2)); // queued, then sent
      await sub.cancel();
      await outbox.dispose();
    });
  });

  group('mutations describe the work, not the call', () {
    test('every kind survives the queue file', () {
      final at = DateTime.utc(2026, 8, 2, 9, 5);
      final originals = <Mutation>[
        ClaimJob(id: 'a', jobId: 'J', actorId: 'c1', at: at),
        AcceptJob(id: 'b', jobId: 'J', actorId: 'c1', at: at),
        AssignJob(id: 'c', jobId: 'J', actorId: 'c9', at: at, driverId: 'c2'),
        AdvanceStage(id: 'd', jobId: 'J', actorId: 'c1', at: at, toStage: 3),
        AttachPhoto(
          id: 'e',
          jobId: 'J',
          actorId: 'c1',
          at: at,
          photoId: 'photo-1',
          photoName: 'before.jpg',
          before: true,
        ),
      ];

      for (final original in originals) {
        final copy = Mutation.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, Object?>,
        );
        expect(copy, isNotNull, reason: original.kind);
        expect(copy!.kind, original.kind);
        expect(copy.id, original.id);
        expect(copy.actorId, original.actorId);
        expect(copy.at.toUtc(), at);
        expect(jsonEncode(copy.toJson()), jsonEncode(original.toJson()));
      }
    });

    test(
      'advancing names an absolute stage, so a replay cannot double-step',
      () {
        final job = Job.fromJson(const {'id': 'J', 'stage': 1});
        final step = AdvanceStage(
          id: 'a',
          jobId: 'J',
          actorId: 'c1',
          at: DateTime.utc(2026),
          toStage: 2,
        );

        final once = step.apply(job)!;
        expect(once.stage, 2);
        // Delivered twice — the second is a no-op rather than stage 3.
        expect(step.apply(once), isNull);
      },
    );

    test('claiming a job someone else already took is refused locally', () {
      final taken = Job.fromJson(const {'id': 'J', 'status': 'active'});
      final claim = ClaimJob(
        id: 'a',
        jobId: 'J',
        actorId: 'c1',
        at: DateTime.utc(2026),
      );
      expect(claim.apply(taken), isNull);
    });

    test('a job cannot be closed by replaying a stage jump without photos', () {
      final job = Job.fromJson(const {'id': 'J', 'stage': 4});
      final close = AdvanceStage(
        id: 'a',
        jobId: 'J',
        actorId: 'c1',
        at: DateTime.utc(2026),
        toStage: 5,
      );
      // The photo rule holds on replay, not just in the UI.
      expect(close.apply(job), isNull);
    });

    test('a photo whose pixels are gone does not file an empty record', () {
      final job = Job.fromJson(const {'id': 'J'});
      final attach = AttachPhoto(
        id: 'a',
        jobId: 'J',
        actorId: 'c1',
        at: DateTime.utc(2026),
        photoId: 'photo-1',
        photoName: 'before.jpg',
        before: true,
      );
      expect(attach.apply(job), isNull, reason: 'no bytes supplied');
    });
  });
}
