import 'crew_member.dart';
import 'job.dart';

/// One stretch of paid work: a driver, a job, and the clock either side of it.
///
/// Derived from the job rather than stored beside it. A separate timesheet is a
/// second record of the same thing, and two records of the same thing disagree
/// — usually the week somebody forgets to press stop. Here the hours *are* the
/// job's own start and finish stamps, so a shift worked in a dead zone is
/// already on the timesheet by the time the phone finds signal.
class TimeEntry {
  const TimeEntry({
    required this.crewId,
    required this.job,
    required this.startedAt,
    this.finishedAt,
  });

  final String crewId;
  final Job job;
  final DateTime startedAt;

  /// Null while the driver is still on it.
  final DateTime? finishedAt;

  bool get running => finishedAt == null;

  /// How long this ran, up to [now] if it is still going.
  Duration workedBy(DateTime now) {
    final span = (finishedAt ?? now).difference(startedAt);
    return span.isNegative ? Duration.zero : span;
  }

  /// The day the work is counted against — the day it started.
  ///
  /// A job that runs past midnight belongs to the shift it began in, which is
  /// how anyone reading a timesheet expects to find it.
  DateTime get day => DateTime(startedAt.year, startedAt.month, startedAt.day);

  /// Every entry these jobs represent, newest first.
  static List<TimeEntry> from(Iterable<Job> jobs) {
    final out = <TimeEntry>[
      for (final job in jobs)
        if (job.startedAt case final started?)
          if (job.assignedTo case final crew?)
            TimeEntry(
              crewId: crew,
              job: job,
              startedAt: started,
              finishedAt: job.finishedAt,
            ),
    ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }
}

/// What one person is owed, and for what.
class Timesheet {
  const Timesheet({
    required this.member,
    required this.entries,
    required this.now,
  });

  final CrewMember member;
  final List<TimeEntry> entries;
  final DateTime now;

  Duration get worked =>
      entries.fold(Duration.zero, (total, e) => total + e.workedBy(now));

  bool get onTheClock => entries.any((e) => e.running);

  /// Whole minutes, so a rounding rule exists in one place rather than in
  /// every widget that shows a figure.
  int get minutes => worked.inMinutes;

  /// What the hours come to at this person's rate, in whole dollars.
  ///
  /// Null when nobody has set a rate. Showing 0 would read as "worked for
  /// nothing" rather than "nobody has said what they earn".
  int? get pay => member.hourlyRate <= 0
      ? null
      : (member.hourlyRate * minutes / 60).round();
}

/// "6h 20m", or "20m" — never "6.33 hours", which nobody writes on a timesheet.
String formatWorked(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

/// The same span in words, for a screen reader.
String describeWorked(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final parts = [
    if (hours > 0) '$hours ${hours == 1 ? 'hour' : 'hours'}',
    if (minutes > 0) '$minutes ${minutes == 1 ? 'minute' : 'minutes'}',
  ];
  return parts.isEmpty ? 'no time yet' : parts.join(' ');
}
