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

/// "Thursday, 6 August" — the day view's title.
String longDay(DateTime at) => '${weekdayName(at)}, ${at.day} ${monthName(at)}';

/// "6 Aug 2026", for anywhere the year matters.
String shortDate(DateTime at) => '${at.day} ${monthShort(at)} ${at.year}';

/// A span written the way a calendar shows it: "9 AM – 11:30 AM".
String timeRange(DateTime from, DateTime to) =>
    '${clockLabel(from)} – ${clockLabel(to)}';
