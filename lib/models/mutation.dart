import 'dart:typed_data';

import '../models/crew_member.dart';
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
  const Mutation({required this.id, required this.actorId, required this.at});

  /// Device-minted, and the server's idempotency key. A retry after a reply
  /// that never arrived must not advance a job twice.
  final String id;

  /// Who did it. Not "the signed-in user at upload time" — the driver may have
  /// handed the phone over by then.
  final String actorId;

  /// When the driver did it, not when it synced.
  final DateTime at;

  String get kind;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
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
    if (id == null || actorId == null || at == null) return null;

    // Crew changes are about the company, not a job, so they are read before
    // the jobId guard rather than being given a fake one.
    if (json['kind'] == 'crew.add') {
      if (json['member'] case final Map raw) {
        return AddCrewMember(
          id: id,
          actorId: actorId,
          at: at,
          member: CrewMember.fromJson(raw.cast<String, Object?>()),
        );
      }
      return null;
    }

    if (jobId == null) return null;

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

/// A change to one job.
///
/// Split out from [Mutation] because not everything worth recording is about a
/// job — hiring someone is a change to the company. Giving crew changes a
/// pretend job id to fit one shape would have put a lie in the outbox, and the
/// outbox is the thing a server later replays.
sealed class JobMutation extends Mutation {
  const JobMutation({
    required super.id,
    required this.jobId,
    required super.actorId,
    required super.at,
  });

  final String jobId;

  /// Applies this change to [job], returning the new job.
  ///
  /// Returns null when the mutation cannot apply — already applied, or the job
  /// moved on underneath it. The caller drops it rather than forcing it.
  ///
  /// [photoBytes] supplies pixels by photo id for the mutations that need
  /// them, so applying stays a pure function of its inputs.
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}});

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'jobId': jobId};
}

/// A change to who works here.
sealed class CrewMutation extends Mutation {
  const CrewMutation({
    required super.id,
    required super.actorId,
    required super.at,
  });

  /// Returns the new roster, or null when the change no longer applies.
  List<CrewMember>? apply(List<CrewMember> crew);
}

/// Someone is hired.
///
/// The whole member travels in the mutation rather than an id, because the
/// person does not exist anywhere else yet — this record *is* the hiring, and
/// it has to be replayable against a server that has never heard of them.
class AddCrewMember extends CrewMutation {
  const AddCrewMember({
    required super.id,
    required super.actorId,
    required super.at,
    required this.member,
  });

  final CrewMember member;

  @override
  String get kind => 'crew.add';

  @override
  Map<String, Object?> get payload => {'member': member.toJson()};

  @override
  List<CrewMember>? apply(List<CrewMember> crew) {
    // Idempotent: a replay must not hire the same person twice.
    if (crew.any((c) => c.id == member.id)) return null;
    return [...crew, member];
  }
}

/// A driver takes an unclaimed job off the board.
class ClaimJob extends JobMutation {
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
class AcceptJob extends JobMutation {
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
class AssignJob extends JobMutation {
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
class AdvanceStage extends JobMutation {
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
class AttachPhoto extends JobMutation {
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
