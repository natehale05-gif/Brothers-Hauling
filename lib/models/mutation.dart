import 'dart:typed_data';

import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/role.dart';

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

    // Creating a job has no job to point at yet, so it is read before the
    // jobId guard.
    if (json['kind'] == 'job.create') {
      if (json['job'] case final Map raw) {
        return CreateJob(
          id: id,
          actorId: actorId,
          at: at,
          job: Job.fromJson(raw.cast<String, Object?>()),
        );
      }
      return null;
    }

    if (json['kind'] == 'job.delete') {
      final target = json['jobId'] as String?;
      if (target == null) return null;
      return DeleteJob(id: id, actorId: actorId, at: at, jobId: target);
    }

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

    if (json['kind'] == 'crew.role') {
      final crewId = json['crewId'] as String?;
      final named = Role.values.where((r) => r.name == json['role']);
      // An unrecognised level is dropped rather than defaulted. Defaulting
      // down would silently demote on a typo; defaulting up is worse.
      if (crewId == null || named.isEmpty) return null;
      return SetCrewRole(
        id: id,
        actorId: actorId,
        at: at,
        crewId: crewId,
        role: named.first,
      );
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
      'publish' => PublishJob(id: id, jobId: jobId, actorId: actorId, at: at),
      'edit' => EditJob(
        id: id,
        jobId: jobId,
        actorId: actorId,
        at: at,
        fields: switch (json['fields']) {
          final Map raw => raw.cast<String, Object?>(),
          _ => const {},
        },
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

/// A change to which jobs exist, rather than to one of them.
sealed class BoardMutation extends Mutation {
  const BoardMutation({
    required super.id,
    required super.actorId,
    required super.at,
  });

  /// Returns the new board, or null when the change no longer applies.
  List<Job>? apply(List<Job> jobs);
}

/// A job appears — today, always because someone booked it on the website.
///
/// The whole job travels in the mutation for the same reason the whole member
/// does when someone is hired: it does not exist anywhere else yet, so this
/// record *is* the job, and it has to replay against a server that has never
/// heard of it.
class CreateJob extends BoardMutation {
  const CreateJob({
    required super.id,
    required super.actorId,
    required super.at,
    required this.job,
  });

  final Job job;

  @override
  String get kind => 'job.create';

  @override
  Map<String, Object?> get payload => {'job': job.toJson()};

  @override
  List<Job>? apply(List<Job> jobs) {
    // Idempotent on both keys. The id catches a replay; the booking id catches
    // the same website booking arriving down a second poll, or after a
    // relaunch mid-sync, having been given a fresh job id on the way in.
    final booking = job.bookingId;
    final already = jobs.any(
      (j) => j.id == job.id || (booking != null && j.bookingId == booking),
    );
    if (already) return null;
    return [job, ...jobs];
  }
}

/// A job taken off the board for good.
///
/// A whole-board mutation rather than a field on a job, because after it
/// replays there is no job left to carry a flag. Idempotent by absence: a
/// replay against a board that no longer holds the job is a no-op, which is
/// what lets the same delete arrive twice from two devices.
class DeleteJob extends BoardMutation {
  const DeleteJob({
    required super.id,
    required super.actorId,
    required super.at,
    required this.jobId,
  });

  final String jobId;

  @override
  String get kind => 'job.delete';

  @override
  Map<String, Object?> get payload => {'jobId': jobId};

  @override
  List<Job>? apply(List<Job> jobs) {
    if (!jobs.any((j) => j.id == jobId)) return null;
    return [
      for (final job in jobs)
        if (job.id != jobId) job,
    ];
  }
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

/// Somebody moves up or down.
///
/// Carries the id and the new level rather than the whole member, for the same
/// reason [EditJob] carries fields rather than a whole job: a promotion queued
/// offline must not, on replay, undo a name or unit corrected in the meantime.
/// It moves the role and touches nothing else.
class SetCrewRole extends CrewMutation {
  const SetCrewRole({
    required super.id,
    required super.actorId,
    required super.at,
    required this.crewId,
    required this.role,
  });

  final String crewId;
  final Role role;

  @override
  String get kind => 'crew.role';

  @override
  Map<String, Object?> get payload => {'crewId': crewId, 'role': role.name};

  @override
  List<CrewMember>? apply(List<CrewMember> crew) {
    final at = crew.indexWhere((c) => c.id == crewId);
    // Nobody by that id — or it has already landed, in which case replaying it
    // would drag a later decision back to this one.
    if (at < 0 || crew[at].role == role) return null;
    return [
      for (final c in crew)
        if (c.id == crewId) c.withRole(role) else c,
    ];
  }
}

/// Dispatch corrects the details of a job.
///
/// Carries only the fields that changed, not the whole job. Sending the whole
/// thing would mean an edit made offline quietly reverting whatever a driver
/// did to the same job in the meantime — the stage they reached, the photos
/// they filed — the moment it replayed. A field-level change can only clobber
/// the field it names.
class EditJob extends JobMutation {
  const EditJob({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
    required this.fields,
  });

  final Map<String, Object?> fields;

  /// What dispatch is allowed to correct.
  ///
  /// Everything the *driver* owns is missing on purpose: status, stage, the
  /// assignee, the photos and the movement log are the record of what happened
  /// in the field, and an edit form is not the place to rewrite it.
  static const editable = {
    'type',
    'customer',
    'address',
    'city',
    'contact',
    'phone',
    'access',
    'material',
    'volume',
    'weight',
    'equipment',
    'disposal',
    'dumpFee',
    'window',
    'miles',
    'deadhead',
    'billed',
    'hazards',
    'scheduledFor',
    'minutes',
    'alertMinutes',
  };

  @override
  String get kind => 'edit';

  @override
  Map<String, Object?> get payload => {'fields': fields};

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    final before = job.toJson();
    // Filtered here as well as at the call site: the queue survives an app
    // upgrade, so a mutation written by a build with a different idea of what
    // is editable still cannot reach past this list.
    final changes = {
      for (final entry in fields.entries)
        if (editable.contains(entry.key) &&
            !_same(before[entry.key], entry.value))
          entry.key: entry.value,
    };
    // Nothing left to do — already applied, or a replay.
    if (changes.isEmpty) return null;

    // The photos are re-attached from the job in hand rather than from
    // [photoBytes], because an edit says nothing about them and must not drop
    // them on the floor.
    final updated = Job.fromJson(
      {...before, ...changes},
      photoBytes: {for (final p in job.photos) p.id: p.bytes},
    );

    return updated.copyWith(
      events: [
        ...updated.events,
        JobEvent(
          at: at,
          label: changes.length == 1
              ? 'Dispatch updated ${_label(changes.keys.first)}'
              : 'Dispatch updated ${changes.length} details',
          kind: EventKind.flat,
        ),
      ],
    );
  }

  /// Lists compare by value; everything else is a scalar out of JSON.
  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => a[i] == b[i]).every((x) => x);
    }
    return a == b;
  }

  static String _label(String field) => switch (field) {
    'dumpFee' => 'the disposal fee',
    'deadhead' => 'the deadhead miles',
    'billed' => 'what it bills at',
    'window' => 'the time window',
    'scheduledFor' => 'the day it happens',
    'minutes' => 'how long it runs',
    'alertMinutes' => 'the reminder',
    'access' => 'the access notes',
    'hazards' => 'the hazards',
    _ => 'the $field',
  };
}

/// Dispatch puts a priced booking in front of the crew.
class PublishJob extends JobMutation {
  const PublishJob({
    required super.id,
    required super.jobId,
    required super.actorId,
    required super.at,
  });

  @override
  String get kind => 'publish';

  @override
  Job? apply(Job job, {Map<String, Uint8List> photoBytes = const {}}) {
    if (job.status != JobStatus.requested) return null;
    // The same guard as the caller's, because the queue outlives the screen
    // that enforced it — a publish sitting in an outbox must not put an
    // unpriced job in front of a driver when it finally replays.
    if (job.billed <= 0) return null;

    return job.copyWith(
      status: JobStatus.open,
      events: [
        ...job.events,
        JobEvent(
          at: at,
          label: 'Priced and put on the board',
          kind: EventKind.flat,
        ),
      ],
    );
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
      // The clock starts here, stamped with when the driver actually did it
      // rather than when this reaches a server.
      startedAt: at,
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
      startedAt: at,
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
      finishedAt: closing ? at : job.finishedAt,
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
