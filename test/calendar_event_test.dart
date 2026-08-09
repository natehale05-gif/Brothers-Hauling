import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/event.dart';
import 'package:haul_board/models/job.dart';

/// A job with only the fields a calendar reads.
Job job(
  String id, {
  String type = 'Debris haul',
  String customer = 'Someone',
  String city = '',
  DateTime? at,
  // Real work needs something on the truck, and the editor will not save a
  // job without it — so a fixture standing in for a booked job carries one.
  List<String> equipment = const ['Dump trailer 14k'],
}) => Job(
  id: id,
  type: type,
  customer: customer,
  address: '',
  city: city,
  contact: '',
  phone: '',
  access: '',
  material: '',
  volume: '',
  weight: '',
  equipment: equipment,
  disposal: 'N/A',
  dumpFee: 0,
  window: '',
  miles: 0,
  deadhead: 0,
  billed: 0,
  scheduledFor: at,
);

void main() {
  group('reading a job as an event', () {
    test('a job with no date is not on the calendar at all', () {
      expect(CalendarEvent.of(job('HL-1')), isNull);
      expect(eventsFrom([job('HL-1'), job('HL-2')]), isEmpty);
    });

    test('a timed job runs for the assumed length', () {
      final event = CalendarEvent.of(job('HL-1', at: DateTime(2026, 8, 6, 9)))!;
      expect(event.allDay, isFalse);
      expect(event.start, DateTime(2026, 8, 6, 9));
      expect(event.end, DateTime(2026, 8, 6, 9).add(kAssumedJobLength));
    });

    test('midnight means a day was booked, not a job at midnight', () {
      // The day picker stores a day-only booking at midnight, so that is the
      // one time of day the calendar reads as "sometime on Thursday".
      final event = CalendarEvent.of(job('HL-1', at: DateTime(2026, 8, 6)))!;
      expect(event.allDay, isTrue);
      expect(event.onDay(DateTime(2026, 8, 6)), isTrue);
      expect(event.onDay(DateTime(2026, 8, 7)), isFalse);
    });

    test('a minute past midnight is a real time', () {
      final event = CalendarEvent.of(
        job('HL-1', at: DateTime(2026, 8, 6, 0, 1)),
      )!;
      expect(event.allDay, isFalse);
    });
  });

  group('which calendar a job belongs to', () {
    test('matches on the kind of work, whatever the casing', () {
      expect(
        WorkCalendar.of(job('a', type: 'Junk removal')),
        WorkCalendar.junk,
      );
      expect(
        WorkCalendar.of(job('a', type: '  BARK & SOIL ')),
        WorkCalendar.bark,
      );
    });

    test('an unknown kind goes grey rather than borrowing a colour', () {
      final unknown = WorkCalendar.of(job('a', type: 'Snow plowing'));
      expect(unknown, WorkCalendar.other);
      expect(
        WorkCalendar.values.where((c) => c.colour == unknown.colour),
        hasLength(1),
      );
    });

    test('every calendar has its own colour', () {
      final colours = {for (final c in WorkCalendar.values) c.colour};
      expect(colours, hasLength(WorkCalendar.values.length));
    });
  });

  group('a day of events', () {
    test('all-day work sorts above timed work, then by start', () {
      final events = eventsFrom([
        job('late', at: DateTime(2026, 8, 6, 14)),
        job('early', at: DateTime(2026, 8, 6, 7)),
        job('whenever', at: DateTime(2026, 8, 6)),
      ]);
      final onDay = eventsOn(events, DateTime(2026, 8, 6));
      expect(onDay.map((e) => e.id), ['whenever', 'early', 'late']);
    });

    test('only the day asked for comes back', () {
      final events = eventsFrom([
        job('today', at: DateTime(2026, 8, 6, 9)),
        job('tomorrow', at: DateTime(2026, 8, 7, 9)),
      ]);
      expect(eventsOn(events, DateTime(2026, 8, 6)).map((e) => e.id), [
        'today',
      ]);
    });

    test('a job running past midnight shows on both days', () {
      final event = CalendarEvent.of(
        job('HL-1', at: DateTime(2026, 8, 6, 23)),
      )!;
      expect(event.onDay(DateTime(2026, 8, 6)), isTrue);
      expect(event.onDay(DateTime(2026, 8, 7)), isTrue);
      // And it is drawn to the bottom of the first day rather than off it.
      expect(event.lengthMinutes(DateTime(2026, 8, 6)), 60);
      expect(event.topMinutes(DateTime(2026, 8, 7)), 0);
      expect(event.lengthMinutes(DateTime(2026, 8, 7)), 60);
    });

    test('a block is never shorter than it can be read at', () {
      final short = CalendarEvent(
        job: job('HL-1'),
        start: DateTime(2026, 8, 6, 9),
        end: DateTime(2026, 8, 6, 9, 5),
        calendar: WorkCalendar.debris,
        allDay: false,
      );
      expect(short.lengthMinutes(DateTime(2026, 8, 6)), 15);
    });

    test('the top is minutes from midnight', () {
      final event = CalendarEvent.of(
        job('HL-1', at: DateTime(2026, 8, 6, 7, 30)),
      )!;
      expect(event.topMinutes(DateTime(2026, 8, 6)), 7 * 60 + 30);
    });
  });

  group('lanes for overlapping work', () {
    List<CalendarEvent> at(List<(String, int, int)> spans) => [
      for (final (id, from, to) in spans)
        CalendarEvent(
          job: job(id),
          start: DateTime(2026, 8, 6, from),
          end: DateTime(2026, 8, 6, to),
          calendar: WorkCalendar.debris,
          allDay: false,
        ),
    ];

    test('work that never overlaps runs full width', () {
      final placed = placeEvents(
        at([('a', 7, 9), ('b', 10, 12)]),
        DateTime(2026, 8, 6),
      );
      expect(placed, hasLength(2));
      expect(placed.every((p) => p.lanes == 1), isTrue);
      expect(placed.every((p) => p.width == 1), isTrue);
    });

    test('two jobs at once split the column', () {
      final placed = placeEvents(
        at([('a', 9, 11), ('b', 9, 11)]),
        DateTime(2026, 8, 6),
      );
      expect(placed.map((p) => p.lanes), [2, 2]);
      expect(placed.map((p) => p.lane), [0, 1]);
      expect(placed.first.left, 0);
      expect(placed.last.left, 0.5);
    });

    test('a chain of overlaps is one group, sized by its worst pile-up', () {
      // a and b overlap, b and c overlap, but a and c never do — and they all
      // have to share a width or two of them would be drawn on top of.
      final placed = placeEvents(
        at([('a', 8, 10), ('b', 9, 11), ('c', 10, 12)]),
        DateTime(2026, 8, 6),
      );
      expect(placed.every((p) => p.lanes == 2), isTrue);
      // c goes back into a's lane, which is free by ten.
      expect(
        {for (final p in placed) p.event.id: p.lane},
        {'a': 0, 'b': 1, 'c': 0},
      );
    });

    test('a gap starts a new group at full width again', () {
      final placed = placeEvents(
        at([('a', 8, 10), ('b', 8, 10), ('c', 13, 15)]),
        DateTime(2026, 8, 6),
      );
      final lanes = {for (final p in placed) p.event.id: p.lanes};
      expect(lanes, {'a': 2, 'b': 2, 'c': 1});
    });

    test('work that only touches does not overlap', () {
      // Nine-to-eleven and eleven-to-one are back to back, not at once.
      final placed = placeEvents(
        at([('a', 9, 11), ('b', 11, 13)]),
        DateTime(2026, 8, 6),
      );
      expect(placed.every((p) => p.lanes == 1), isTrue);
    });

    test('all-day work is not placed on the grid', () {
      final events = eventsFrom([
        job('whenever', at: DateTime(2026, 8, 6)),
        job('nine', at: DateTime(2026, 8, 6, 9)),
      ]);
      final placed = placeEvents(events, DateTime(2026, 8, 6));
      expect(placed.map((p) => p.event.id), ['nine']);
    });

    test('lanes never overlap each other', () {
      final placed = placeEvents(
        at([('a', 8, 12), ('b', 9, 10), ('c', 9, 11), ('d', 10, 12)]),
        DateTime(2026, 8, 6),
      );
      for (final one in placed) {
        for (final two in placed) {
          if (identical(one, two) || one.lane != two.lane) continue;
          final apart =
              !one.event.start.isBefore(two.event.end) ||
              !two.event.start.isBefore(one.event.end);
          expect(
            apart,
            isTrue,
            reason:
                '${one.event.id} and ${two.event.id} share lane ${one.lane} '
                'while running at the same time',
          );
        }
      }
    });
  });

  group('a column per kind of work', () {
    final day = DateTime(2026, 8, 6);

    List<CalendarEvent> booked(List<(String, String, int, int)> spans) => [
      for (final (id, kind, from, to) in spans)
        CalendarEvent(
          job: job(id, type: kind),
          start: DateTime(2026, 8, 6, from),
          end: DateTime(2026, 8, 6, to),
          calendar: WorkCalendar.of(job(id, type: kind)),
          allDay: false,
        ),
    ];

    test('one kind takes the whole width', () {
      final placed = placeByCalendar(
        booked([('a', 'Debris haul', 7, 9), ('b', 'Debris haul', 11, 13)]),
        day,
      );
      expect(placed, hasLength(2));
      expect(placed.every((p) => p.width == 1), isTrue);
      expect(placed.every((p) => p.left == 0), isTrue);
    });

    test('two kinds split it, whatever hour they are at', () {
      // The whole point: these never overlap in time, and still get their own
      // columns.
      final placed = placeByCalendar(
        booked([('a', 'Debris haul', 7, 9), ('b', 'Junk removal', 14, 16)]),
        day,
      );
      final byId = {for (final p in placed) p.event.id: p};
      expect(byId['a']!.left, 0);
      expect(byId['a']!.width, 0.5);
      expect(byId['b']!.left, 0.5);
      expect(byId['b']!.width, 0.5);
    });

    test('every job of a kind shares that kind\'s column', () {
      final placed = placeByCalendar(
        booked([
          ('a', 'Debris haul', 7, 9),
          ('b', 'Debris haul', 10, 12),
          ('c', 'Junk removal', 8, 10),
        ]),
        day,
      );
      final byId = {for (final p in placed) p.event.id: p};
      expect(byId['a']!.left, byId['b']!.left);
      expect(byId['c']!.left, isNot(byId['a']!.left));
    });

    test('the column order follows the calendar, not who starts first', () {
      // Junk is booked first but gravel comes earlier in the calendar's order,
      // so a job moving must not shuffle the columns.
      final placed = placeByCalendar(
        booked([
          ('late', 'Bark & soil', 7, 9),
          ('early', 'Junk removal', 8, 10),
        ]),
        day,
      );
      final byId = {for (final p in placed) p.event.id: p};
      expect(byId['early']!.left, lessThan(byId['late']!.left));
    });

    test('two of the same kind at once split that column again', () {
      final placed = placeByCalendar(
        booked([
          ('a', 'Debris haul', 9, 11),
          ('b', 'Debris haul', 9, 11),
          ('c', 'Junk removal', 9, 11),
        ]),
        day,
      );
      final byId = {for (final p in placed) p.event.id: p};
      // The debris column is half the width, split in two again.
      expect(byId['a']!.width, closeTo(0.25, 0.0001));
      expect(byId['b']!.width, closeTo(0.25, 0.0001));
      // Junk keeps its whole column, because nothing collides in it.
      expect(byId['c']!.width, closeTo(0.5, 0.0001));
      expect(byId['a']!.left, isNot(byId['b']!.left));
    });

    test('nothing is ever drawn off the right edge', () {
      final placed = placeByCalendar(
        booked([
          ('a', 'Debris haul', 7, 9),
          ('b', 'Junk removal', 8, 10),
          ('c', 'Gravel delivery', 9, 11),
          ('d', 'Bark & soil', 10, 12),
          ('e', 'Equipment move', 11, 13),
        ]),
        day,
      );
      expect(placed, hasLength(5));
      for (final p in placed) {
        expect(p.left + p.width, lessThanOrEqualTo(1.0001));
        expect(p.left, greaterThanOrEqualTo(0));
      }
    });

    test('all-day work is never drawn in the hour grid', () {
      final events = eventsFrom([
        job('whenever', at: DateTime(2026, 8, 6)),
        job('nine', at: DateTime(2026, 8, 6, 9)),
      ]);
      expect(placeByCalendar(events, day).map((p) => p.event.id), ['nine']);
      expect(calendarsOn(events, day), hasLength(1));
    });

    test('a kind booked only for the day still gets its column', () {
      // The band above the grid draws it, and the two have to line up.
      final events = eventsFrom([
        job('whenever', type: 'Junk removal', at: DateTime(2026, 8, 6)),
        job('nine', type: 'Debris haul', at: DateTime(2026, 8, 6, 9)),
      ]);
      expect(calendarsOn(events, day), [
        WorkCalendar.debris,
        WorkCalendar.junk,
      ]);

      // The timed job takes the debris column — the left half — and leaves
      // the junk column empty rather than spreading across the whole day.
      final placed = placeByCalendar(events, day);
      expect(placed, hasLength(1));
      expect(placed.single.left, closeTo(0, 0.0001));
      expect(placed.single.width, closeTo(0.5, 0.0001));
    });

    test('an empty day has no columns at all', () {
      expect(placeByCalendar(const [], day), isEmpty);
      expect(calendarsOn(const [], day), isEmpty);
    });
  });

  test('what a screen reader hears instead of a rectangle', () {
    final event = CalendarEvent.of(
      job(
        'HL-1',
        type: 'Junk removal',
        customer: 'Harrison St rental',
        city: 'Corvallis',
        at: DateTime(2026, 8, 6, 9),
      ),
    )!;
    expect(
      event.spoken,
      'Junk removal for Harrison St rental in Corvallis. 9 AM – 11 AM.',
    );

    final whenever = CalendarEvent.of(job('HL-2', at: DateTime(2026, 8, 6)))!;
    expect(whenever.spoken, contains('All day'));
  });
}
