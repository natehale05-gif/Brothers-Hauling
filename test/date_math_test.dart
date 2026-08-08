import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/date_math.dart';

/// The arithmetic underneath every grid in the app.
///
/// Worth testing on its own because none of it is visible when it goes wrong:
/// a month that pages to the wrong place or a week that starts on Monday looks
/// like a working calendar right up until somebody misses a job.
void main() {
  group('days and months', () {
    test('dayOf strips the time', () {
      expect(dayOf(DateTime(2026, 8, 6, 23, 59)), DateTime(2026, 8, 6));
    });

    test('sameDay ignores the clock, sameMonth ignores the day', () {
      expect(
        sameDay(DateTime(2026, 8, 6, 1), DateTime(2026, 8, 6, 22)),
        isTrue,
      );
      expect(sameDay(DateTime(2026, 8, 6), DateTime(2026, 8, 7)), isFalse);
      expect(sameMonth(DateTime(2026, 8, 1), DateTime(2026, 8, 31)), isTrue);
      expect(sameMonth(DateTime(2026, 8, 31), DateTime(2026, 9, 1)), isFalse);
    });

    test('daysBetween counts days, not elapsed hours', () {
      // Half an hour apart across a midnight is still a whole day.
      expect(
        daysBetween(DateTime(2026, 8, 6, 23, 45), DateTime(2026, 8, 7, 0, 15)),
        1,
      );
      expect(daysBetween(DateTime(2026, 8, 7), DateTime(2026, 8, 6)), -1);
    });

    test('daysInMonth handles the leap year', () {
      expect(daysInMonth(DateTime(2026, 2)), 28);
      expect(daysInMonth(DateTime(2028, 2)), 29);
      expect(daysInMonth(DateTime(2026, 8)), 31);
    });
  });

  group('addMonths', () {
    test('clamps the day rather than rolling into the next month', () {
      // Plain DateTime arithmetic turns this into 3 March.
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 8, 31), 1), DateTime(2026, 9, 30));
    });

    test('crosses the year in both directions', () {
      expect(addMonths(DateTime(2026, 12, 15), 1), DateTime(2027, 1, 15));
      expect(addMonths(DateTime(2026, 1, 15), -1), DateTime(2025, 12, 15));
    });

    test('keeps the time of day', () {
      final moved = addMonths(DateTime(2026, 8, 6, 14, 30), 2);
      expect(moved, DateTime(2026, 10, 6, 14, 30));
    });
  });

  group('week and month grids', () {
    test('a week starts on Sunday', () {
      // 6 August 2026 is a Thursday.
      expect(weekStart(DateTime(2026, 8, 6)), DateTime(2026, 8, 2));
      // A Sunday is already the start of its own week.
      expect(weekStart(DateTime(2026, 8, 2)), DateTime(2026, 8, 2));
    });

    test('the week start is configurable', () {
      expect(
        weekStart(DateTime(2026, 8, 6), startsOn: DateTime.monday),
        DateTime(2026, 8, 3),
      );
    });

    test('weekDays runs seven consecutive days from the start', () {
      final days = weekDays(DateTime(2026, 8, 6));
      expect(days, hasLength(7));
      expect(days.first, DateTime(2026, 8, 2));
      expect(days.last, DateTime(2026, 8, 8));
    });

    test('a month grid is always six rows, so it never changes height', () {
      for (var month = 1; month <= 12; month++) {
        expect(monthGrid(DateTime(2026, month)), hasLength(42));
      }
      // February 2026 starts on a Sunday and has exactly 28 days — the one
      // month that fits in four rows, and still gets six.
      expect(monthGrid(DateTime(2026, 2)), hasLength(42));
    });

    test('a month grid starts on the week containing the first', () {
      final grid = monthGrid(DateTime(2026, 8));
      expect(grid.first, DateTime(2026, 7, 26));
      expect(grid[6], DateTime(2026, 8, 1));
      expect(grid.last, DateTime(2026, 9, 5));
    });

    test('every grid day is consecutive', () {
      final grid = monthGrid(DateTime(2026, 3));
      for (var i = 1; i < grid.length; i++) {
        expect(daysBetween(grid[i - 1], grid[i]), 1);
      }
    });
  });

  group('labels', () {
    test('weekday initials are in week order', () {
      expect(weekdayInitials(), ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
      expect(weekdayInitials(startsOn: DateTime.monday), [
        'M',
        'T',
        'W',
        'T',
        'F',
        'S',
        'S',
      ]);
    });

    test('the clock reads the way a calendar writes it', () {
      expect(clockLabel(DateTime(2026, 8, 6, 9)), '9 AM');
      expect(clockLabel(DateTime(2026, 8, 6, 9, 30)), '9:30 AM');
      expect(clockLabel(DateTime(2026, 8, 6, 12)), '12 PM');
      expect(clockLabel(DateTime(2026, 8, 6, 0, 15)), '12:15 AM');
      expect(clockLabel(DateTime(2026, 8, 6, 13)), '1 PM');
    });

    test('hour labels name noon and midnight', () {
      expect(hourLabel(0), '12 AM');
      expect(hourLabel(7), '7 AM');
      expect(hourLabel(12), 'noon');
      expect(hourLabel(13), '1 PM');
      expect(hourLabel(23), '11 PM');
    });

    test('dates read as people say them', () {
      expect(longDay(DateTime(2026, 8, 6)), 'Thursday, 6 August');
      expect(shortDate(DateTime(2026, 8, 6)), '6 Aug 2026');
      expect(
        timeRange(DateTime(2026, 8, 6, 9), DateTime(2026, 8, 6, 11, 30)),
        '9 AM – 11:30 AM',
      );
    });
  });
}
