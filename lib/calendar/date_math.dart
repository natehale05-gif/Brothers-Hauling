/// Dates, the way a calendar grid needs them.
///
/// Everything here is local-time and midnight-anchored. A calendar draws days,
/// not instants, and the single most common bug in one of these is a cell that
/// disagrees with its neighbour about where a day ends.
library;

/// Midnight on the same day.
DateTime dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

/// The first of the month [at] falls in.
DateTime monthOf(DateTime at) => DateTime(at.year, at.month);

/// The 1st of January in [at]'s year.
DateTime yearOf(DateTime at) => DateTime(at.year);

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// Whole days between two dates, ignoring the time on either.
int daysBetween(DateTime from, DateTime to) =>
    dayOf(to).difference(dayOf(from)).inDays;

/// Days in [at]'s month.
///
/// Day zero of the next month is the last day of this one, which is also how
/// February gets its leap years right without a rule about them.
int daysInMonth(DateTime at) => DateTime(at.year, at.month + 1, 0).day;

/// Months moved without rolling the day into the wrong one.
///
/// [DateTime] would happily turn 31 January plus a month into 3 March. A
/// calendar paging from January must land on February.
DateTime addMonths(DateTime at, int months) {
  final target = DateTime(at.year, at.month + months);
  final day = at.day <= daysInMonth(target) ? at.day : daysInMonth(target);
  return DateTime(target.year, target.month, day, at.hour, at.minute);
}

/// Which weekday a week starts on, as [DateTime]'s 1–7.
///
/// Sunday in the United States, and a setting rather than a constant because
/// the rest of the world does not agree.
const int kWeekStartsOn = DateTime.sunday;

/// The start of the week [at] falls in.
DateTime weekStart(DateTime at, {int startsOn = kWeekStartsOn}) {
  final day = dayOf(at);
  // Monday is 1 and Sunday is 7, so the arithmetic has to wrap.
  final shift = (day.weekday - startsOn + 7) % 7;
  return day.subtract(Duration(days: shift));
}

/// Every day drawn in a month grid, including the greyed-out days either side.
///
/// Always whole weeks, so the grid is rectangular. Six rows rather than five or
/// six: a month view that changes height as you page through the year is the
/// thing people notice first and never stop noticing.
List<DateTime> monthGrid(DateTime at, {int startsOn = kWeekStartsOn}) {
  final first = weekStart(monthOf(at), startsOn: startsOn);
  return [for (var i = 0; i < 42; i++) first.add(Duration(days: i))];
}

/// The seven days of the week [at] falls in.
List<DateTime> weekDays(DateTime at, {int startsOn = kWeekStartsOn}) {
  final first = weekStart(at, startsOn: startsOn);
  return [for (var i = 0; i < 7; i++) first.add(Duration(days: i))];
}

const List<String> kMonthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> kMonthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> kWeekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const List<String> kWeekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// The single letters down the top of a month grid, in week order.
///
/// Sunday reads "S" and so does Saturday, which is what the real thing does —
/// position carries the difference, and the header row is labelled for a
/// screen reader in full.
List<String> weekdayInitials({int startsOn = kWeekStartsOn}) => [
  for (var i = 0; i < 7; i++)
    kWeekdayShort[(startsOn - 1 + i) % 7].substring(0, 1),
];

String monthName(DateTime at) => kMonthNames[at.month - 1];
String monthShort(DateTime at) => kMonthShort[at.month - 1];
String weekdayName(DateTime at) => kWeekdayNames[at.weekday - 1];
String weekdayShort(DateTime at) => kWeekdayShort[at.weekday - 1];

/// "9 AM", "12 PM", "3:30 PM" — the clock as a calendar writes it.
String clockLabel(DateTime at, {bool includeMinutes = true}) {
  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final suffix = at.hour < 12 ? 'AM' : 'PM';
  if (!includeMinutes || at.minute == 0) return '$hour $suffix';
  return '$hour:${at.minute.toString().padLeft(2, '0')} $suffix';
}

/// The hour labels down the side of a day or week view.
String hourLabel(int hour) {
  if (hour == 0) return '12 AM';
  if (hour == 12) return 'noon';
  return hour < 12 ? '$hour AM' : '${hour - 12} PM';
}

/// How often a booking comes back around.
enum Repeat {
  never('Never'),
  daily('Every day'),
  weekly('Every week'),
  fortnightly('Every 2 weeks'),
  monthly('Every month'),
  yearly('Every year');

  const Repeat(this.label);

  final String label;
}

/// Every moment a repeating booking lands on, [from] included.
///
/// Bounded twice on purpose — a count and an end date — because an unbounded
/// repeat in a system that writes a real job per occurrence is a system that
/// fills a disk. Monthly walks by calendar months rather than by 30 days, so
/// the 31st of a short month clamps instead of sliding into the next one.
List<DateTime> repeatDates(
  DateTime from,
  Repeat rule, {
  int count = 1,
  DateTime? until,
}) {
  if (rule == Repeat.never || count <= 1) return [from];

  final out = <DateTime>[];
  for (var i = 0; i < count; i++) {
    final at = switch (rule) {
      Repeat.never => from,
      Repeat.daily => from.add(Duration(days: i)),
      Repeat.weekly => from.add(Duration(days: 7 * i)),
      Repeat.fortnightly => from.add(Duration(days: 14 * i)),
      Repeat.monthly => addMonths(from, i),
      Repeat.yearly => addMonths(from, 12 * i),
    };
    if (until != null && dayOf(at).isAfter(dayOf(until))) break;
    out.add(at);
  }
  return out;
}

/// A sensible hour to open a new booking on [day] at.
///
/// The next round hour when the day is today and the yard is still working,
/// eight in the morning otherwise — a job booked for next Tuesday wants to
/// start in Tuesday's working day, not at whatever o'clock it is now.
DateTime startOfWorking(DateTime day, DateTime now, {int opensAt = 8}) {
  if (sameDay(day, now) && now.hour >= opensAt && now.hour < 17) {
    return DateTime(day.year, day.month, day.day, now.hour + 1);
  }
  return DateTime(day.year, day.month, day.day, opensAt);
}

/// "Thursday, 6 August" — the day view's title.
String longDay(DateTime at) => '${weekdayName(at)}, ${at.day} ${monthName(at)}';

/// "Sat 15 Aug" — the same day, for a bar with five buttons beside it.
///
/// The nav bar has to fit a title, arrows, Today and the calendars button on a
/// phone. "Saturday, 15 August" does not, and a day view whose title is
/// ellipsised into "Saturday, 15 …" has lost the one thing it was there to
/// say.
String shortDay(DateTime at) =>
    '${weekdayName(at).substring(0, 3)} ${at.day} ${monthShort(at)}';

/// "6 Aug 2026", for anywhere the year matters.
String shortDate(DateTime at) => '${at.day} ${monthShort(at)} ${at.year}';

/// A span written the way a calendar shows it: "9 AM – 11:30 AM".
String timeRange(DateTime from, DateTime to) =>
    '${clockLabel(from)} – ${clockLabel(to)}';
