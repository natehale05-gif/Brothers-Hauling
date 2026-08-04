import 'dart:async';
import 'dart:convert';

import '../models/mutation.dart';
import 'store.dart';

/// Why a send failed, which decides whether retrying is worth anything.
enum SendOutcome {
  /// The server has it. Drop it from the queue.
  accepted,

  /// Nothing reached the server — no signal, timeout, DNS. Keep it and retry;
  /// this is the ordinary case in a truck.
  retry,

  /// The server understood and refused: the job was already taken, the driver
  /// no longer has the rig, the payload is malformed. Retrying will fail
  /// identically forever, so it must not sit in the queue blocking the rest.
  rejected,
}

/// Sends a mutation somewhere durable. The queue does not care where.
typedef SendMutation = Future<SendOutcome> Function(Mutation mutation);

/// What a pass over the queue actually did.
///
/// The distinction that matters is between "tried and failed" and "did not
/// try". A queue sitting inside its backoff has not learned anything about the
/// network, and reporting that as offline would light up a warning the driver
/// can do nothing about.
class DrainReport {
  const DrainReport({this.attempted = 0, this.delivered = 0});

  /// Mutations actually handed to [SendMutation].
  final int attempted;

  /// Of those, how many the far end took.
  final int delivered;

  bool get reachedServer => delivered > 0;
  bool get triedAndFailed => attempted > 0 && delivered == 0;
}

/// A queued mutation and what has happened to it so far.
class PendingMutation {
  const PendingMutation({
    required this.mutation,
    this.attempts = 0,
    this.lastError,
    this.nextAttempt,
  });

  final Mutation mutation;
  final int attempts;
  final String? lastError;

  /// Earliest moment worth trying again — the backoff.
  final DateTime? nextAttempt;

  PendingMutation copyWith({
    int? attempts,
    String? lastError,
    DateTime? nextAttempt,
  }) => PendingMutation(
    mutation: mutation,
    attempts: attempts ?? this.attempts,
    lastError: lastError ?? this.lastError,
    nextAttempt: nextAttempt ?? this.nextAttempt,
  );

  Map<String, Object?> toJson() => {
    'mutation': mutation.toJson(),
    'attempts': attempts,
    if (lastError != null) 'lastError': lastError,
    if (nextAttempt != null)
      'nextAttempt': nextAttempt!.toUtc().toIso8601String(),
  };

  static PendingMutation? fromJson(Map<String, Object?> json) {
    final raw = json['mutation'];
    if (raw is! Map) return null;
    final mutation = Mutation.fromJson(raw.cast<String, Object?>());
    if (mutation == null) return null;
    return PendingMutation(
      mutation: mutation,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      nextAttempt: DateTime.tryParse(
        json['nextAttempt'] as String? ?? '',
      )?.toLocal(),
    );
  }
}

/// The work a driver has done that the server has not acknowledged yet.
///
/// Written to disk on every change, because the failure this exists for is
/// exactly the one where the app does not get to run its cleanup: signal drops,
/// the phone is locked, the OS reaps the process, the battery dies. Anything
/// held only in memory at that moment is a job the driver did and will not get
/// paid for.
///
/// Order is preserved and sending is strictly sequential. Two mutations against
/// the same job are not independent — "arrived on site" then "loaded up" only
/// makes sense in that order — and sorting that out server-side is far harder
/// than simply not reordering them.
class Outbox {
  Outbox({
    required this._store,
    required this._send,
    DateTime Function()? now,
    this.maxAttempts = 8,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 5),
  }) : _now = now ?? DateTime.now;

  static const _key = 'outbox.v1';

  final Store _store;
  final SendMutation _send;
  final DateTime Function() _now;

  /// After this many failures a mutation is given up on and surfaced, rather
  /// than retried until the heat death of the phone battery.
  final int maxAttempts;

  final Duration baseBackoff;
  final Duration maxBackoff;

  List<PendingMutation> _pending = [];
  List<PendingMutation> _abandoned = [];

  /// The pass currently running, if any. Callers that arrive mid-pass wait on
  /// it rather than being told "nothing happened" — otherwise a caller that
  /// inspects the queue straight afterwards races the pass it just triggered.
  Future<DrainReport>? _draining;

  /// Waiting to be sent, oldest first.
  List<PendingMutation> get pending => List.unmodifiable(_pending);

  /// Given up on. These need a human — they are shown, never silently dropped.
  List<PendingMutation> get abandoned => List.unmodifiable(_abandoned);

  int get pendingCount => _pending.length;
  bool get isEmpty => _pending.isEmpty && _abandoned.isEmpty;

  /// Job ids with unsent work, so the UI can mark exactly those cards.
  /// Only job changes have a job to mark. Hiring someone is owed to dispatch
  /// too, but there is no card on the board to put a badge on.
  Set<String> get pendingJobIds => {
    for (final p in _pending)
      if (p.mutation case final JobMutation m) m.jobId,
    for (final p in _abandoned)
      if (p.mutation case final JobMutation m) m.jobId,
  };

  final _changes = StreamController<void>.broadcast();

  /// Fires whenever the queue's contents change.
  Stream<void> get changes => _changes.stream;

  Future<void> load() async {
    final text = await _store.readString(_key);
    if (text == null) return;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      _pending = _readList(decoded['pending']);
      _abandoned = _readList(decoded['abandoned']);
    } on FormatException {
      // A half-written queue is worse than none: it could replay a partial
      // mutation. Start clean rather than guess.
      _pending = [];
      _abandoned = [];
    }
  }

  static List<PendingMutation> _readList(Object? raw) => [
    if (raw is List)
      for (final entry in raw)
        if (entry is Map)
          ?PendingMutation.fromJson(entry.cast<String, Object?>()),
  ];

  Future<void> _persist() async {
    await _store.writeString(
      _key,
      jsonEncode({
        'pending': _pending.map((p) => p.toJson()).toList(),
        'abandoned': _abandoned.map((p) => p.toJson()).toList(),
      }),
    );
    _changes.add(null);
  }

  /// Queues [mutation] and persists before returning — the caller has already
  /// shown the driver the change as done, so it must be on disk by then.
  Future<void> add(Mutation mutation) async {
    _pending = [..._pending, PendingMutation(mutation: mutation)];
    await _persist();
  }

  /// Sends everything due, oldest first, stopping at the first one that needs
  /// retrying so ordering per job is never broken.
  ///
  /// Safe to call often; overlapping calls collapse into one.
  ///
  /// [force] ignores the backoff. Use it when something has changed that the
  /// backoff cannot know about — the driver asked, or the device just got
  /// signal back. Without it, a truck coming out of a dead zone would sit on a
  /// five-minute timer with a full queue and a working connection.
  Future<DrainReport> drain({bool force = false}) {
    final running = _draining;
    if (running != null) {
      // A forced request cannot be satisfied by an unforced pass already in
      // flight — that pass will stop at the first backoff, which is exactly
      // what the caller asked to skip. Queue a forced pass behind it instead.
      return force ? running.then((_) => drain(force: true)) : running;
    }

    late final Future<DrainReport> pass;
    pass = _drain(force: force).whenComplete(() {
      if (identical(_draining, pass)) _draining = null;
    });
    _draining = pass;
    return pass;
  }

  Future<DrainReport> _drain({required bool force}) async {
    var attempted = 0;
    var delivered = 0;
    try {
      while (_pending.isNotEmpty) {
        final head = _pending.first;

        final wait = head.nextAttempt;
        if (!force && wait != null && _now().isBefore(wait)) {
          break; // still backing off
        }

        attempted++;
        SendOutcome outcome;
        try {
          outcome = await _send(head.mutation);
        } catch (error) {
          outcome = SendOutcome.retry;
          _pending[0] = head.copyWith(lastError: error.toString());
        }

        switch (outcome) {
          case SendOutcome.accepted:
            delivered++;
            _pending = _pending.sublist(1);
            await _persist();

          case SendOutcome.rejected:
            // Understood and refused. Move it aside so the queue behind it can
            // still flow, but keep it for the driver to see.
            _abandoned = [
              ..._abandoned,
              _pending.first.copyWith(
                attempts: head.attempts + 1,
                lastError: head.lastError ?? 'Rejected by the server',
              ),
            ];
            _pending = _pending.sublist(1);
            await _persist();

          case SendOutcome.retry:
            final attempts = head.attempts + 1;
            if (attempts >= maxAttempts) {
              _abandoned = [
                ..._abandoned,
                _pending.first.copyWith(
                  attempts: attempts,
                  lastError: head.lastError ?? 'Gave up after $attempts tries',
                ),
              ];
              _pending = _pending.sublist(1);
              await _persist();
              continue;
            }
            _pending = [
              _pending.first.copyWith(
                attempts: attempts,
                nextAttempt: _now().add(_backoffFor(attempts)),
              ),
              ..._pending.sublist(1),
            ];
            await _persist();
            return DrainReport(attempted: attempted, delivered: delivered);
        }
      }
      return DrainReport(attempted: attempted, delivered: delivered);
    } catch (_) {
      return DrainReport(attempted: attempted, delivered: delivered);
    }
  }

  /// Exponential, capped. Deliberately not jittered here — a single device's
  /// queue is sequential, so there is no thundering herd to spread out.
  Duration _backoffFor(int attempts) {
    final millis = baseBackoff.inMilliseconds * (1 << (attempts - 1));
    return millis >= maxBackoff.inMilliseconds
        ? maxBackoff
        : Duration(milliseconds: millis);
  }

  /// Puts abandoned work back at the front of the queue — the "try again"
  /// a driver reaches for after reconnecting to something that works.
  Future<void> retryAbandoned() async {
    if (_abandoned.isEmpty) return;
    _pending = [
      ..._abandoned.map((p) => PendingMutation(mutation: p.mutation)),
      ..._pending,
    ];
    _abandoned = [];
    await _persist();
  }

  /// Throws the abandoned work away. Only ever driven by an explicit human
  /// decision — this is unrecoverable.
  Future<void> discardAbandoned() async {
    if (_abandoned.isEmpty) return;
    _abandoned = [];
    await _persist();
  }

  Future<void> dispose() async => _changes.close();
}
