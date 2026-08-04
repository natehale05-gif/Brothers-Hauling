import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/mutation.dart';
import 'ids.dart';
import 'outbox.dart';
import 'seed_data.dart' show kCrew, seedJobs;
import 'store.dart';

/// How settled the board is. The UI shows this verbatim; it is never allowed to
/// imply that queued work has landed.
@immutable
class SyncState {
  const SyncState({
    this.pending = 0,
    this.failed = 0,
    this.lastSyncedAt,
    this.offline = false,
  });

  /// Changes written down and waiting for the server.
  final int pending;

  /// Changes the server refused, or that were retried until we gave up.
  /// These need a person.
  final int failed;

  final DateTime? lastSyncedAt;

  /// The last send attempt did not reach anything.
  final bool offline;

  bool get settled => pending == 0 && failed == 0;

  SyncState copyWith({
    int? pending,
    int? failed,
    DateTime? lastSyncedAt,
    bool? offline,
  }) => SyncState(
    pending: pending ?? this.pending,
    failed: failed ?? this.failed,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    offline: offline ?? this.offline,
  );
}

/// The board, and the only way to change it.
///
/// Everything that alters a job goes through [apply] as a [Mutation], which is
/// what lets the same change be shown instantly, written to disk, and sent to a
/// server later without three different code paths that can disagree.
abstract class BoardRepository extends ChangeNotifier {
  List<Job> get jobs;

  /// Who works here. Recorded the same way jobs are, so hiring someone in a
  /// dead zone survives the app dying exactly as a claimed load does.
  List<CrewMember> get crew;

  SyncState get syncState;

  /// Job ids carrying changes the server has not acknowledged.
  Set<String> get unsyncedJobIds;

  /// Reads whatever is on the device. Safe to call once at startup.
  Future<void> load();

  /// Applies [mutation] locally and queues it for the server.
  ///
  /// Returns false when the change could not be applied — the job had already
  /// moved on. The caller is expected to tell the driver, not to retry.
  Future<bool> apply(Mutation mutation, {JobPhoto? photo});

  /// Attempts to send anything queued. Cheap and safe to call often.
  ///
  /// [force] skips the backoff — for when the driver asked, or connectivity
  /// just came back.
  Future<void> sync({bool force = false});

  /// Re-queues work that was given up on.
  Future<void> retryFailed();
}

/// A board that lives on the device and pushes changes at a server when it can.
///
/// The order inside [apply] is the whole design:
///
///   1. apply to the in-memory board so the driver sees it immediately,
///   2. write the board and any photo pixels to disk,
///   3. queue the mutation,
///   4. *then* try to send.
///
/// Steps 1–3 cannot fail for lack of signal, which is why a driver in Blodgett
/// can work a whole job and lose nothing. Step 4 is allowed to fail forever.
class LocalBoardRepository extends BoardRepository {
  LocalBoardRepository({
    required Store store,
    SendMutation? send,
    this._seed,
    DateTime Function()? now,
    IdGenerator? idGenerator,
    Outbox? outbox,
  }) : _store = store,
       _now = now ?? DateTime.now,
       _ids = idGenerator ?? ids {
    // Seeded synchronously so nothing ever renders an empty board while the
    // read from disk is in flight; [load] replaces this with whatever the
    // device actually had.
    // Dates in the seed are relative to this repository's clock, not the wall
    // clock — otherwise a test that pins the date gets a board scheduled around
    // a different day than the one it is looking at.
    _jobs = List.of(_seed ?? seedJobs(_now()));
    _crew = List.of(kCrew);
    _outbox =
        outbox ??
        Outbox(
          store: store,
          // With no server configured the app is a single device: a change is
          // "sent" the moment it is safely on disk. Swapping this for a real
          // transport is the only change this class needs.
          send: send ?? ((_) async => SendOutcome.accepted),
          now: _now,
        );
  }

  static const _boardKey = 'board.v1';
  static const _crewKey = 'crew.v1';
  static String _photoKey(String id) => 'photo.v1.$id';

  final Store _store;
  final List<Job>? _seed;
  final DateTime Function() _now;
  final IdGenerator _ids;
  late final Outbox _outbox;

  List<Job> _jobs = [];
  List<CrewMember> _crew = [];
  SyncState _sync = const SyncState();
  bool _loaded = false;

  @override
  List<Job> get jobs => List.unmodifiable(_jobs);

  @override
  List<CrewMember> get crew => List.unmodifiable(_crew);

  @override
  SyncState get syncState => _sync;

  @override
  Set<String> get unsyncedJobIds => _outbox.pendingJobIds;

  @override
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;

    await _outbox.load();
    final text = await _store.readString(_boardKey);

    if (text == null) {
      // First run on this device: keep the seed and write it down.
      await _persistBoard();
    } else {
      _jobs = await _decodeBoard(text) ?? _jobs;
    }

    _crew = _decodeCrew(await _store.readString(_crewKey)) ?? _crew;

    _refreshSync();
    notifyListeners();
    await sync();
  }

  List<CrewMember>? _decodeCrew(String? text) {
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return null;
      return [
        for (final raw in decoded.whereType<Map>())
          CrewMember.fromJson(raw.cast<String, Object?>()),
      ];
    } on FormatException {
      // A truncated write. Keeping the seed roster beats starting the day with
      // nobody on the crew list.
      return null;
    }
  }

  Future<List<Job>?> _decodeBoard(String text) async {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return null;

      final maps = decoded.whereType<Map>().map(
        (e) => e.cast<String, Object?>(),
      );

      // Photo pixels live under their own keys; collect the ones this board
      // references so jobs come back whole.
      // Both shapes: the lists this build writes, and the single slots the
      // previous one did, so an existing board upgrades instead of losing its
      // photos.
      final wanted = <String>{
        for (final job in maps) ...[
          for (final slot in const ['photosBefore', 'photosAfter'])
            if (job[slot] case final List raw)
              for (final entry in raw.whereType<Map>())
                if (entry['id'] case final String id) id,
          for (final slot in const ['photoBefore', 'photoAfter'])
            if (job[slot] case final Map raw)
              if (raw['id'] case final String id) id,
        ],
      };
      final bytes = <String, Uint8List>{};
      for (final id in wanted) {
        final data = await _store.readBytes(_photoKey(id));
        if (data != null) bytes[id] = data;
      }

      return [for (final job in maps) Job.fromJson(job, photoBytes: bytes)];
    } on FormatException {
      // Truncated write. Falling back to the seed loses local history, so say
      // nothing was there and let the caller reseed rather than crash-loop.
      return null;
    }
  }

  Future<void> _persistBoard() async {
    await _store.writeString(
      _boardKey,
      jsonEncode([for (final job in _jobs) job.toJson()]),
    );
  }

  Future<void> _persistCrew() async {
    await _store.writeString(
      _crewKey,
      jsonEncode([for (final member in _crew) member.toJson()]),
    );
  }

  @override
  Future<bool> apply(Mutation mutation, {JobPhoto? photo}) async {
    switch (mutation) {
      case BoardMutation():
        final updated = mutation.apply(_jobs);
        if (updated == null) return false;
        _jobs = updated;
        await _persistBoard();

      case CrewMutation():
        final updated = mutation.apply(_crew);
        if (updated == null) return false;
        _crew = updated;
        await _persistCrew();

      case JobMutation():
        final index = _jobs.indexWhere((j) => j.id == mutation.jobId);
        if (index < 0) return false;

        // Pixels first. If the write fails we have not yet told anyone the
        // photo exists, which is the recoverable order to fail in.
        if (photo != null) {
          await _store.writeBytes(_photoKey(photo.id), photo.bytes);
        }

        final updated = mutation.apply(
          _jobs[index],
          photoBytes: {if (photo != null) photo.id: photo.bytes},
        );
        if (updated == null) return false;

        _jobs = [..._jobs]..[index] = updated;
        await _persistBoard();
    }

    await _outbox.add(mutation);

    _refreshSync();
    notifyListeners();

    // Deliberately not awaited: the driver's next tap must not wait on a
    // radio. Failures are recorded in the queue, not thrown at the caller.
    unawaited(sync());
    return true;
  }

  @override
  Future<void> sync({bool force = false}) async {
    final report = await _outbox.drain(force: force);

    _refreshSync(
      synced: report.reachedServer,
      // Only a failed attempt counts as offline. A queue that is merely
      // waiting out its backoff has learned nothing about the network.
      offline: report.triedAndFailed
          ? true
          : (report.reachedServer ? false : null),
    );
    notifyListeners();
  }

  @override
  Future<void> retryFailed() async {
    await _outbox.retryAbandoned();
    _refreshSync();
    notifyListeners();
    // Explicitly asked for, so it does not wait out a backoff.
    await sync(force: true);
  }

  void _refreshSync({bool synced = false, bool? offline}) {
    _sync = SyncState(
      pending: _outbox.pendingCount,
      failed: _outbox.abandoned.length,
      lastSyncedAt: synced ? _now() : _sync.lastSyncedAt,
      offline: offline ?? (_outbox.pendingCount > 0 && _sync.offline),
    );
  }

  /// Mints an id for a mutation about to be created.
  String newMutationId() => _ids.next('mut');

  /// Removes photo pixels no job references any more, so a long-lived install
  /// does not accumulate every photo ever taken.
  Future<int> sweepOrphanedPhotos() async {
    final referenced = {
      for (final job in _jobs)
        for (final photo in job.photos) _photoKey(photo.id),
    };
    final stored = (await _store.keys()).where(
      (k) => k.startsWith('photo.v1.'),
    );

    var removed = 0;
    for (final key in stored) {
      if (referenced.contains(key)) continue;
      await _store.delete(key);
      removed++;
    }
    return removed;
  }

  @override
  void dispose() {
    _outbox.dispose();
    super.dispose();
  }
}

/// Fire-and-forget without the lint noise, and without swallowing the intent.
void unawaited(Future<void> future) {
  future.catchError((_) {});
}
