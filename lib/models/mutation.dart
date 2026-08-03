import 'dart:typed_data';

import '../models/job.dart';

/// A change to the board, as a thing rather than a method call.
///
/// This is the pivot the whole offline story turns on. When a driver taps
/// "I'm on site" in a dead zone, the app cannot call a server — but it can
/// write down *what the driver did*, apply it locally, and send it when the
/// signal comes back. A mutation is that written-down intent: serializable,
/// replayable, and carrying the moment it actually happened rather than the
/// moment it eventually uploads.
///
/// Applying one is a pure function of (board, mutation), so the same code
/// produces the same result on the device now and on the server later.
sealed class Mutation {
  const Mutation({
    required this.id,
    required this.jobId,
    required this.actorId,
    required this.at,
  });

  /// Device-minted, and the server's idempotency key. A retry after a reply
  /// that never arrived must not advance a job twice.
  final String id;

  final String jobId;

  /// Who did it. Not "the signed-in user at upload time" — the driver may have
  /// handed the phone over by then.
  final String actorId;

  /// When the driver did it, not when it synced.
  final DateTime at;

  String get kind;

  /// Applies this change to [job], returning the new job.
  ///
  /// Returns null when the mutation cannot apply — already applied, or the job
  /// moved on underneath it. The caller drops it rather than forcing it.
  ///
  /// [photoBytes] supplies pixels by photo id for the mutations that need
  /// them, so applying stays a pure function of its inputs.
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}});

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'jobId': jobId,
    'actorId': actorId,
    'at': at.toUtc().toIso8601String(),
    ...payload,
  };

  /// Fields beyond the common envelope.
  Map<String, Object?> get payload => const {};

  static Mutation? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final jobId = json['jobId'] as String?;
    final actorId = json['actorId'] as String?;
    final at = DateTime.tryParse(json['at'] as String? ?? '')?.toLocal();
    if (id == null || jobId == null || actorId == null || at == null) {
      return null;
    }

    return switch (json['kind']) {
      'claim' => ClaimJob(id: id, jobId: jobId, actorId: actorId, at: at),
      'accept' => AcceptJob(id: id, jobId: jobId, actorId: actorId, at: at),
      'assign' => AssignJob(
        id: id,
        jobId: jobId,
        actorId: actorId,
        at: at,
        driverId: json['driverId'] as String? ?? '',
      ),
      'advance' => AdvanceStage(
        id: id,
        jobId: jobId,
        actorId: actorId,
        at: at,
        toStage: (json['toStage'] as num?)?.toInt() ?? 0,
      ),
      'photo' => AttachPhoto(
        id: id,
        jobId: jobId,
        actorId: actorId,
        at: at,
        photoId: json['photoId'] as String? ?? '',
        photoName: json['photoName'] as String? ?? '',
        before: json['before'] as bool? ?? true,
      ),
      // An unknown kind means this queue was written by a newer build. Skip it
      // rather than refusing to start; the newer build will resend.
      _ => null,
    };
  }
}

/// A driver takes an unclaimed job off the board.
class ClaimJob extends Mutation {
  const ClaimJob({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
  });

  @override
  String get kind => 'claim';

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    // Somebody else got there first. The server is the authority on who won;
    // locally we simply refuse to overwrite an existing claim.
    if (job.status != JobStatus.open) return null;
    return job.copyWith(
      status: JobStatus.active,
      assignedTo: actorId,
      stage: 0,
      progress: 0,
      events: [
        ...job.events,
        JobEvent(
          at: at,
          label: 'Volunteered for this job',
          kind: EventKind.flat,
        ),
      ],
    );
  }
}

/// A driver says yes to a job dispatch pushed at them.
class AcceptJob extends Mutation {
  const AcceptJob({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
  });

  @override
  String get kind => 'accept';

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    if (job.status != JobStatus.assigned) return null;
    return job.copyWith(
      status: JobStatus.active,
      stage: 0,
      progress: 0,
      events: [
        ...job.events,
        JobEvent(at: at, label: 'Accepted the job', kind: EventKind.flat),
      ],
    );
  }
}

/// Dispatch pushes a job at a driver. They still have to accept it.
class AssignJob extends Mutation {
  const AssignJob({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
    required this.driverId,
  });

  final String driverId;

  @override
  String get kind => 'assign';

  @override
  Map<String, Object?> get payload => {'driverId': driverId};

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    if (job.status == JobStatus.done) return null;
    return job.copyWith(status: JobStatus.assigned, assignedTo: driverId);
  }
}

/// A driver steps a job forward. [toStage] is absolute, not "+1", so a
/// mutation replayed out of order cannot double-advance.
class AdvanceStage extends Mutation {
  const AdvanceStage({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
    required this.toStage,
  });

  final int toStage;

  @override
  String get kind => 'advance';

  @override
  Map<String, Object?> get payload => {'toStage': toStage};

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    // Already there, or past it: this is a duplicate delivery.
    if (job.stage >= toStage) return null;
    final closing = toStage >= kStages.length - 1;
    if (closing && !job.photosComplete) return null;

    return job.copyWith(
      status: closing ? JobStatus.done : job.status,
      stage: toStage,
      progress: closing ? 1 : 0,
      events: [...job.events, job.transitionEvent(toStage, at)],
    );
  }
}

/// A before/after photo is filed against a job.
///
/// Carries the photo's identity, not its pixels — those go to storage on their
/// own schedule, and a 3 MB image has no business sitting in a queue that gets
/// rewritten on every change.
class AttachPhoto extends Mutation {
  const AttachPhoto({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
    required this.photoId,
    required this.photoName,
    required this.before,
  });

  final String photoId;
  final String photoName;
  final bool before;

  @override
  String get kind => 'photo';

  @override
  Map<String, Object?> get payload => {
    'photoId': photoId,
    'photoName': photoName,
    'before': before,
  };

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    // Idempotent by photo id, not by slot. A driver files as many shots as the
    // job needs, so "there is already a before photo" is no longer a reason to
    // drop one — but replaying the same mutation must not file it twice.
    if (job.photos.any((p) => p.id == photoId)) return null;

    final bytes = photoBytes[photoId];
    // The pixels have gone missing — the device was wiped, or the write was
    // interrupted. Filing a photo record with nothing behind it would let a
    // job close on evidence that does not exist.
    if (bytes == null) return null;

    final photo = JobPhoto(id: photoId, name: photoName, bytes: bytes);
    return before
        ? job.copyWith(photosBefore: [...job.photosBefore, photo])
        : job.copyWith(photosAfter: [...job.photosAfter, photo]);
  }
}
