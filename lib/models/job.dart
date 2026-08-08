import 'dart:typed_data';

/// Where a job sits in the pipeline.
enum JobStatus {
  /// Came in from the website and has not been priced yet.
  ///
  /// Deliberately not [open]: an unpriced job on the driver board is a job
  /// somebody can volunteer for at nothing a load. Dispatch puts a number on
  /// it first, and only then does it reach the crew.
  requested,

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

/// Reads an enum back by name, falling back rather than throwing — a board
/// written by a newer build must not brick an older one.
T _enumFrom<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// One line in a job's movement log.
///
/// The moment is a real [DateTime], not the display string the prototype used.
/// Two devices' logs have to merge into one ordered history, and "9:05 AM"
/// cannot be compared across a midnight, a timezone, or a server.
class JobEvent {
  const JobEvent({required this.at, required this.label, required this.kind});

  final DateTime at;
  final String label;
  final EventKind kind;

  /// What the driver reads: "9:05 AM".
  String get time => formatClock(at);

  Map<String, Object?> toJson() => {
    'at': at.toUtc().toIso8601String(),
    'label': label,
    'kind': kind.name,
  };

  factory JobEvent.fromJson(Map<String, Object?> json) => JobEvent(
    at:
        DateTime.tryParse(json['at'] as String? ?? '')?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0),
    label: json['label'] as String? ?? '',
    kind: _enumFrom(EventKind.values, json['kind'], EventKind.flat),
  );
}

/// Twelve-hour clock, no leading zero on the hour.
String formatClock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} '
      '${d.hour < 12 ? 'AM' : 'PM'}';
}

/// A before/after shot.
///
/// The record and the pixels are separate concerns. [bytes] is the local copy —
/// the evidence that closes a job, held until a server confirms it — while
/// [remoteUrl] is where it ended up. Photos are never inlined into the board's
/// JSON; they are stored against [id] so a board stays small enough to write on
/// every change.
class JobPhoto {
  const JobPhoto({
    required this.id,
    required this.name,
    required this.bytes,
    this.remoteUrl,
  });

  final String id;
  final String name;
  final Uint8List bytes;
  final String? remoteUrl;

  /// False while the pixels still only exist on this device.
  bool get uploaded => remoteUrl != null;

  JobPhoto copyWith({Uint8List? bytes, String? remoteUrl}) => JobPhoto(
    id: id,
    name: name,
    bytes: bytes ?? this.bytes,
    remoteUrl: remoteUrl ?? this.remoteUrl,
  );

  /// Deliberately without [bytes] — see the class comment.
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (remoteUrl != null) 'remoteUrl': remoteUrl,
  };

  factory JobPhoto.fromJson(Map<String, Object?> json, Uint8List bytes) =>
      JobPhoto(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        bytes: bytes,
        remoteUrl: json['remoteUrl'] as String?,
      );
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

/// The stage at which the driver is standing on the customer's ground.
///
/// The before photo has to happen here: once the first load is on the truck,
/// the state of the site before anyone touched it is gone for good, and with it
/// the answer to "that was already broken when we got there".
const int kOnSiteStage = 2;

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
    required this.billed,
    this.hazards = const [],
    this.status = JobStatus.open,
    this.assignedTo,
    this.stage = 0,
    this.photosBefore = const [],
    this.photosAfter = const [],
    this.events = const [],
    this.progress = 0,
    this.bookingId,
    this.scheduledFor,
    this.minutes,
    this.startedAt,
    this.finishedAt,
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

  final int billed;
  final List<String> hazards;
  final JobStatus status;
  final String? assignedTo;

  /// Index into [kStages].
  final int stage;

  /// Shots taken before the load is touched, in the order they were taken.
  ///
  /// A list rather than a single slot because one photo rarely covers a job —
  /// a driver needs the pile, the access, and the thing the customer will
  /// later say was already broken.
  final List<JobPhoto> photosBefore;

  /// Shots taken once the site is clear.
  final List<JobPhoto> photosAfter;
  final List<JobEvent> events;

  /// 0..1 along the current leg.
  final double progress;

  /// When the driver took this job on, and when they closed it.
  ///
  /// The clock, and the only one. Hours are not a running timer somebody has
  /// to remember to start — a timer is a thing that gets left going overnight,
  /// and it cannot survive the app being killed in a dead zone. These two
  /// stamps are written by the same mutations that move the job, so the hours
  /// are a consequence of the work rather than a second record of it.
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// How long this job has been worked, so far or in total.
  ///
  /// [now] is passed in rather than read, so a running job's figure is
  /// whatever the caller's clock says and tests are not at the mercy of one.
  Duration workedBy(DateTime now) {
    final from = startedAt;
    if (from == null) return Duration.zero;
    final to = finishedAt ?? now;
    final span = to.difference(from);
    return span.isNegative ? Duration.zero : span;
  }

  /// Still on the clock.
  bool get onTheClock => startedAt != null && finishedAt == null;

  /// The day this job is meant to happen.
  ///
  /// Null means nobody has committed to a day yet — a website booking that
  /// said "weekday mornings" has not been scheduled just because it arrived.
  /// The day view keeps those visible in their own bucket rather than
  /// inventing a date for them, because a job silently parked on today is a
  /// job that gets missed tomorrow.
  final DateTime? scheduledFor;

  /// The date part alone, for grouping. Time of day lives in [window].
  DateTime? get scheduledDay => scheduledFor == null
      ? null
      : DateTime(scheduledFor!.year, scheduledFor!.month, scheduledFor!.day);

  /// How long the job is booked for, in minutes.
  ///
  /// Null means nobody has said, and a calendar falls back to its own
  /// assumption rather than refusing to draw a block. Stored in minutes
  /// because that is the resolution anybody schedules at — a hauling job is
  /// not booked to the second, and an integer survives a JSON round trip
  /// without the rounding a Duration in microseconds invites.
  final int? minutes;

  /// The website booking this came from, if it did.
  ///
  /// Kept so the same booking arriving twice — a retried poll, a relaunch
  /// mid-sync — becomes the same job rather than a duplicate on the board.
  final String? bookingId;

  /// Waiting on dispatch to put a price on it.
  bool get needsPricing => status == JobStatus.requested;

  /// Came in from the website rather than being written by dispatch.
  bool get fromWebsite => bookingId != null;

  Phase get phase => kPhases[stage];

  bool get hasDisposalStop => !disposal.startsWith('N/A');

  /// At least one shot of each is required before a job can close.
  bool get photosComplete => photosBefore.isNotEmpty && photosAfter.isNotEmpty;

  /// The first before/after shot, for the places that show one thumbnail.
  JobPhoto? get photoBefore => photosBefore.isEmpty ? null : photosBefore.first;
  JobPhoto? get photoAfter => photosAfter.isEmpty ? null : photosAfter.first;

  /// What is left before labour. Labour costs hours × the driver's rate, and
  /// neither of those lives on a job, so this is deliberately not "profit".
  int get beforeLabour => billed - dumpFee;

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
  JobEvent transitionEvent(int newStage, DateTime at) {
    return switch (newStage) {
      1 => JobEvent(
        at: at,
        label: 'Left the yard — on the way to $city',
        kind: EventKind.depart,
      ),
      2 => JobEvent(at: at, label: 'Arrived on site', kind: EventKind.arrive),
      3 => JobEvent(
        at: at,
        label: 'Left the site — hauling to $disposal',
        kind: EventKind.depart,
      ),
      4 => JobEvent(
        at: at,
        label: 'Arrived at $disposal',
        kind: EventKind.arrive,
      ),
      5 => JobEvent(at: at, label: 'Job closed', kind: EventKind.flat),
      _ => JobEvent(at: at, label: 'Accepted the job', kind: EventKind.flat),
    };
  }

  // ---------------------------------------------------------------- wire

  /// The whole job except its photo pixels, which travel separately.
  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'customer': customer,
    'address': address,
    'city': city,
    'contact': contact,
    'phone': phone,
    'access': access,
    'material': material,
    'volume': volume,
    'weight': weight,
    'equipment': equipment,
    'disposal': disposal,
    'dumpFee': dumpFee,
    'window': window,
    'miles': miles,
    'deadhead': deadhead,
    'billed': billed,
    'hazards': hazards,
    'status': status.name,
    'assignedTo': assignedTo,
    'stage': stage,
    'photosBefore': [for (final p in photosBefore) p.toJson()],
    'photosAfter': [for (final p in photosAfter) p.toJson()],
    'events': events.map((e) => e.toJson()).toList(),
    'progress': progress,
    'bookingId': bookingId,
    'scheduledFor': scheduledFor?.toUtc().toIso8601String(),
    'minutes': minutes,
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'finishedAt': finishedAt?.toUtc().toIso8601String(),
  };

  /// [photoBytes] supplies the pixels for any photo id the job references;
  /// a photo whose bytes are missing locally is dropped rather than faked.
  factory Job.fromJson(
    Map<String, Object?> json, {
    Map<String, Uint8List> photoBytes = const {},
  }) {
    JobPhoto? photo(Object? raw) {
      if (raw is! Map) return null;
      final map = raw.cast<String, Object?>();
      final bytes = photoBytes[map['id']];
      if (bytes == null) return null;
      return JobPhoto.fromJson(map, bytes);
    }

    /// Reads the list, falling back to the single-slot key an earlier build
    /// wrote. A phone that has been running the shipped version has a board on
    /// it in the old shape, and losing a driver's before shot on upgrade would
    /// be the exact failure the outbox exists to prevent.
    List<JobPhoto> photoList(Object? list, Object? legacy) {
      if (list is List) {
        return [for (final raw in list) ?photo(raw)];
      }
      return [?photo(legacy)];
    }

    return Job(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      customer: json['customer'] as String? ?? '',
      address: json['address'] as String? ?? '',
      city: json['city'] as String? ?? '',
      contact: json['contact'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      access: json['access'] as String? ?? '',
      material: json['material'] as String? ?? '',
      volume: json['volume'] as String? ?? '',
      weight: json['weight'] as String? ?? '',
      equipment: json['equipment'] as String? ?? '',
      disposal: json['disposal'] as String? ?? '',
      dumpFee: (json['dumpFee'] as num?)?.toInt() ?? 0,
      window: json['window'] as String? ?? '',
      miles: (json['miles'] as num?)?.toInt() ?? 0,
      deadhead: (json['deadhead'] as num?)?.toInt() ?? 0,
      billed: (json['billed'] as num?)?.toInt() ?? 0,
      hazards: (json['hazards'] as List?)?.cast<String>() ?? const [],
      status: _enumFrom(JobStatus.values, json['status'], JobStatus.open),
      assignedTo: json['assignedTo'] as String?,
      stage: (json['stage'] as num?)?.toInt().clamp(0, kStages.length - 1) ?? 0,
      photosBefore: photoList(json['photosBefore'], json['photoBefore']),
      photosAfter: photoList(json['photosAfter'], json['photoAfter']),
      events:
          (json['events'] as List?)
              ?.whereType<Map>()
              .map((e) => JobEvent.fromJson(e.cast<String, Object?>()))
              .toList() ??
          const [],
      progress: (json['progress'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0,
      bookingId: json['bookingId'] as String?,
      minutes: (json['minutes'] as num?)?.toInt(),
      scheduledFor: DateTime.tryParse(
        json['scheduledFor'] as String? ?? '',
      )?.toLocal(),
      startedAt: DateTime.tryParse(
        json['startedAt'] as String? ?? '',
      )?.toLocal(),
      finishedAt: DateTime.tryParse(
        json['finishedAt'] as String? ?? '',
      )?.toLocal(),
    );
  }

  /// Every photo this job references, before shots first.
  List<JobPhoto> get photos => [...photosBefore, ...photosAfter];

  Job copyWith({
    JobStatus? status,
    String? assignedTo,
    bool clearAssignee = false,
    int? stage,
    List<JobPhoto>? photosBefore,
    List<JobPhoto>? photosAfter,
    List<JobEvent>? events,
    double? progress,
    String? bookingId,
    DateTime? scheduledFor,
    bool clearSchedule = false,
    int? minutes,
    DateTime? startedAt,
    DateTime? finishedAt,
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
      billed: billed,
      hazards: hazards,
      status: status ?? this.status,
      assignedTo: clearAssignee ? null : (assignedTo ?? this.assignedTo),
      stage: stage ?? this.stage,
      photosBefore: photosBefore ?? this.photosBefore,
      photosAfter: photosAfter ?? this.photosAfter,
      events: events ?? this.events,
      progress: progress ?? this.progress,
      bookingId: bookingId ?? this.bookingId,
      scheduledFor: clearSchedule ? null : (scheduledFor ?? this.scheduledFor),
      minutes: minutes ?? this.minutes,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}
