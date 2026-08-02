import 'dart:typed_data';

/// Where a job sits in the pipeline.
enum JobStatus {
  /// On the board, nobody has taken it.
  open,

  /// Pushed to a driver by dispatch — still needs their yes.
  assigned,

  /// Accepted and running.
  active,

  /// Closed out.
  done,
}

enum EventKind { flat, depart, arrive }

/// One line in a job's movement log.
class JobEvent {
  const JobEvent({required this.time, required this.label, required this.kind});

  final String time;
  final String label;
  final EventKind kind;
}

/// A before/after shot. Bytes are held in memory so the same code path works on
/// web (where there is no readable file path) as on the five native platforms.
class JobPhoto {
  const JobPhoto({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// The six stages a driver walks through, in order.
const List<String> kStages = [
  'Accepted',
  'Driving to site',
  'Loading',
  'In transit',
  'At disposal',
  'Closed',
];

/// The button label that moves a job out of the stage at the same index.
const List<String> kStageActions = [
  'Roll out',
  "I'm on site",
  'Loaded up',
  'At the dump',
  'Close it out',
];

/// Stage → what dispatch sees. [moving] drives the route animation and ETA.
class Phase {
  const Phase(this.key, this.label, {required this.moving});

  final String key;
  final String label;
  final bool moving;
}

const List<Phase> kPhases = [
  Phase('staged', 'Staged', moving: false),
  Phase('to_site', 'On the way', moving: true),
  Phase('on_site', 'On site', moving: false),
  Phase('to_dump', 'Hauling', moving: true),
  Phase('at_dump', 'At disposal', moving: false),
  Phase('closed', 'Closed', moving: false),
];

/// Rough fleet average, used for every ETA in the app.
const double kAvgMph = 34;

class Job {
  const Job({
    required this.id,
    required this.type,
    required this.customer,
    required this.address,
    required this.city,
    required this.contact,
    required this.phone,
    required this.access,
    required this.material,
    required this.volume,
    required this.weight,
    required this.equipment,
    required this.disposal,
    required this.dumpFee,
    required this.window,
    required this.miles,
    required this.deadhead,
    required this.payout,
    required this.billed,
    this.hazards = const [],
    this.status = JobStatus.open,
    this.assignedTo,
    this.stage = 0,
    this.photoBefore,
    this.photoAfter,
    this.events = const [],
    this.progress = 0,
  });

  final String id;
  final String type;
  final String customer;
  final String address;
  final String city;
  final String contact;
  final String phone;

  /// Gate codes, which drive to use, where not to back down. Read this first.
  final String access;

  final String material;
  final String volume;
  final String weight;
  final String equipment;

  /// Landfill or transfer station, or an "N/A — …" string for deliveries that
  /// never leave the customer's property.
  final String disposal;

  final int dumpFee;
  final String window;

  /// Loaded miles for the haul leg.
  final int miles;

  /// Empty miles from the yard to the site.
  final int deadhead;

  final int payout;
  final int billed;
  final List<String> hazards;
  final JobStatus status;
  final String? assignedTo;

  /// Index into [kStages].
  final int stage;

  final JobPhoto? photoBefore;
  final JobPhoto? photoAfter;
  final List<JobEvent> events;

  /// 0..1 along the current leg.
  final double progress;

  Phase get phase => kPhases[stage];

  bool get hasDisposalStop => !disposal.startsWith('N/A');

  /// Both shots are required before a job can close.
  bool get photosComplete => photoBefore != null && photoAfter != null;

  int get margin => billed - payout - dumpFee;

  /// Miles on the leg the driver is currently running.
  int get legMiles => stage == 1 ? deadhead : miles;

  /// Minutes left on the current leg. Never reports zero — "1 min out" reads
  /// better on a board than "0 min out".
  int etaMinutes() =>
      ((legMiles * (1 - progress) / kAvgMph) * 60).round().clamp(1, 1 << 30);

  /// Where this driver is actually headed right now: the site until they are
  /// loaded, the disposal site after.
  ({String label, String query}) get legTarget {
    final haulingOut = stage >= 3 && hasDisposalStop;
    return haulingOut
        ? (label: disposal, query: '$disposal, Oregon')
        : (label: 'the site', query: '$address, $city, OR');
  }

  /// The log line for arriving at [newStage].
  JobEvent transitionEvent(int newStage, String time) {
    return switch (newStage) {
      1 => JobEvent(
        time: time,
        label: 'Left the yard — on the way to $city',
        kind: EventKind.depart,
      ),
      2 => JobEvent(
        time: time,
        label: 'Arrived on site',
        kind: EventKind.arrive,
      ),
      3 => JobEvent(
        time: time,
        label: 'Left the site — hauling to $disposal',
        kind: EventKind.depart,
      ),
      4 => JobEvent(
        time: time,
        label: 'Arrived at $disposal',
        kind: EventKind.arrive,
      ),
      5 => JobEvent(time: time, label: 'Job closed', kind: EventKind.flat),
      _ => JobEvent(
        time: time,
        label: 'Accepted the job',
        kind: EventKind.flat,
      ),
    };
  }

  Job copyWith({
    JobStatus? status,
    String? assignedTo,
    bool clearAssignee = false,
    int? stage,
    JobPhoto? photoBefore,
    JobPhoto? photoAfter,
    List<JobEvent>? events,
    double? progress,
  }) {
    return Job(
      id: id,
      type: type,
      customer: customer,
      address: address,
      city: city,
      contact: contact,
      phone: phone,
      access: access,
      material: material,
      volume: volume,
      weight: weight,
      equipment: equipment,
      disposal: disposal,
      dumpFee: dumpFee,
      window: window,
      miles: miles,
      deadhead: deadhead,
      payout: payout,
      billed: billed,
      hazards: hazards,
      status: status ?? this.status,
      assignedTo: clearAssignee ? null : (assignedTo ?? this.assignedTo),
      stage: stage ?? this.stage,
      photoBefore: photoBefore ?? this.photoBefore,
      photoAfter: photoAfter ?? this.photoAfter,
      events: events ?? this.events,
      progress: progress ?? this.progress,
    );
  }
}
