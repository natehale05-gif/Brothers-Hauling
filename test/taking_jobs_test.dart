import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/views/timed_grid.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// An open job on the pinned day, priced so it has reached the crew.
Job openJob(String id, {String type = 'Debris haul', int at = 9}) => job(
  id,
  type: type,
  at: DateTime(2026, 8, 6, at),
).copyWith(status: JobStatus.open);

/// Booked for the pinned day with no time on it — the all-day band.
Job allDayJob(String id, {String type = 'Debris haul'}) => job(
  id,
  type: type,
  at: DateTime(2026, 8, 6),
).copyWith(status: JobStatus.open);

void main() {
  group('taking a job on', () {
    for (final role in Role.values) {
      testWidgets('a ${role.label} can take an open job', (tester) async {
        final app = await pumpApp(
          tester,
          role: role,
          view: CalView.day,
          jobs: [openJob('HL-1')],
        );

        expect(app.state.canTake(jobIn(app.state, 'HL-1')), isTrue);

        await tester.tap(find.text('Debris haul').first);
        await settle(tester);
        // Tapped on the control itself. The semantics label is checked
        // separately below — it merges with the line under the button, so a
        // finder for it resolves to the pair rather than to the button.
        expect(
          find.bySemanticsLabel(RegExp('^Take this job\\.')),
          findsOneWidget,
        );
        await tester.tap(find.text('Take this job'));
        await settle(tester);

        final after = jobIn(app.state, 'HL-1');
        expect(after.status, JobStatus.active);
        expect(after.assignedTo, app.state.meId);
        expect(after.startedAt, isNotNull, reason: 'the clock starts');
      });
    }

    testWidgets('an unpriced booking says why it cannot be taken', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [openJob('HL-1').copyWith(status: JobStatus.requested)],
      );

      expect(app.state.canTake(jobIn(app.state, 'HL-1')), isFalse);

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);

      expect(find.text('Take this job'), findsNothing);
      expect(find.textContaining('until it has a price'), findsOneWidget);
    });

    testWidgets('a job somebody already has offers nothing', (tester) async {
      await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [
          openJob('HL-1').copyWith(status: JobStatus.active, assignedTo: 'c9'),
        ],
      );

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);

      expect(find.text('Take this job'), findsNothing);
      expect(find.text('Accept this job'), findsNothing);
    });
  });

  group('accepting one pushed at you', () {
    testWidgets('the person it was pushed at can say yes', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      // Dispatch pushes it at whoever is signed in.
      await app.state.assign(jobIn(app.state, 'HL-1'), app.state.meId);
      await settle(tester);
      expect(jobIn(app.state, 'HL-1').status, JobStatus.assigned);
      expect(app.state.canAccept(jobIn(app.state, 'HL-1')), isTrue);

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Accept this job\\.')),
        findsOneWidget,
      );
      await tester.tap(find.text('Accept this job'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').status, JobStatus.active);
    });

    testWidgets('somebody else cannot say yes for them', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [
          openJob(
            'HL-1',
          ).copyWith(status: JobStatus.assigned, assignedTo: 'somebody-else'),
        ],
      );

      expect(app.state.canAccept(jobIn(app.state, 'HL-1')), isFalse);

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(find.text('Accept this job'), findsNothing);
    });

    testWidgets('a manager can accept work pushed at them too', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.manager,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      await app.state.assign(jobIn(app.state, 'HL-1'), app.state.meId);
      await settle(tester);

      await tester.tap(find.text('Debris haul').first);
      await settle(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Accept this job\\.')),
        findsOneWidget,
      );
      await tester.tap(find.text('Accept this job'));
      await settle(tester);

      expect(jobIn(app.state, 'HL-1').status, JobStatus.active);
      expect(jobIn(app.state, 'HL-1').assignedTo, app.state.meId);
    });
  });

  group('the day view, laid out by kind', () {
    testWidgets('names its columns when there is more than one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          openJob('HL-1', type: 'Debris haul', at: 7),
          openJob('HL-2', type: 'Junk removal', at: 14),
        ],
      );

      expect(find.byType(CalendarColumnHeader), findsOneWidget);
      // Once on the block, once over its column.
      expect(find.text('Debris haul'), findsNWidgets(2));
      expect(find.text('Junk removal'), findsNWidgets(2));
    });

    testWidgets('does not bother when everything is one kind', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          openJob('HL-1', type: 'Debris haul', at: 7),
          openJob('HL-2', type: 'Debris haul', at: 14),
        ],
      );

      expect(find.byType(CalendarColumnHeader), findsNothing);
      // Two blocks, and no header repeating what the colour already says.
      expect(find.text('Debris haul'), findsNWidgets(2));
    });

    testWidgets('two kinds at different hours sit side by side', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          openJob('HL-1', type: 'Debris haul', at: 7),
          openJob('HL-2', type: 'Junk removal', at: 14),
        ],
      );

      final blocks = find.byType(EventBlock);
      expect(blocks, findsNWidgets(2));
      final first = tester.getRect(blocks.at(0));
      final second = tester.getRect(blocks.at(1));

      // Different columns, and neither on top of the other.
      expect(first.left, isNot(closeTo(second.left, 1)));
      expect(
        first.right <= second.left + 1 || second.right <= first.left + 1,
        isTrue,
        reason: 'the columns do not overlap',
      );
    });

    testWidgets('all-day work sits in columns rather than stacking', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          allDayJob('HL-1', type: 'Junk removal'),
          allDayJob('HL-2'),
        ],
      );

      final chips = find.byType(AllDayChip);
      expect(chips, findsNWidgets(2));
      final first = tester.getRect(chips.at(0));
      final second = tester.getRect(chips.at(1));

      expect(
        first.top,
        closeTo(second.top, 1),
        reason: 'side by side, not one under the other',
      );
      expect(first.left, isNot(closeTo(second.left, 1)));
    });

    testWidgets('an all-day job lines up over its own column', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          // Debris comes first in the calendar's order, so the timed job holds
          // the left column and the all-day junk job belongs over the right.
          openJob('HL-1', type: 'Debris haul', at: 9),
          allDayJob('HL-2', type: 'Junk removal'),
        ],
      );

      final chip = tester.getRect(find.byType(AllDayChip));
      final block = tester.getRect(find.byType(EventBlock));
      expect(
        chip.left,
        greaterThan(block.right),
        reason: 'the junk column is to the right of the debris one',
      );
    });

    testWidgets('two of the same kind share one column', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [allDayJob('HL-1'), allDayJob('HL-2')],
      );

      final chips = find.byType(AllDayChip);
      expect(chips, findsNWidgets(2));
      final first = tester.getRect(chips.at(0));
      final second = tester.getRect(chips.at(1));
      expect(first.left, closeTo(second.left, 1));
      expect(first.bottom, lessThanOrEqualTo(second.top + 1));
    });

    testWidgets('a day with nothing all-day has no band', (tester) async {
      await pumpApp(tester, view: CalView.day, jobs: [openJob('HL-1', at: 9)]);

      expect(find.text('all-day'), findsNothing);
      expect(find.byType(AllDayChip), findsNothing);
    });

    testWidgets('a week view still stacks its all-day work by day', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.week,
        jobs: [
          allDayJob('HL-1', type: 'Junk removal'),
          allDayJob('HL-2'),
        ],
      );

      // A week column is a day, so two jobs on the same day stack in it.
      final chips = find.byType(AllDayChip);
      expect(chips, findsNWidgets(2));
      final first = tester.getRect(chips.at(0));
      final second = tester.getRect(chips.at(1));
      expect(first.left, closeTo(second.left, 1));
      expect(first.bottom, lessThanOrEqualTo(second.top + 1));
    });

    testWidgets('a week view still packs by collision, not by kind', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.week,
        jobs: [
          openJob('HL-1', type: 'Debris haul', at: 7),
          openJob('HL-2', type: 'Junk removal', at: 14),
        ],
      );

      // Nothing collides, so both run the full width of their day column.
      final blocks = find.byType(EventBlock);
      expect(blocks, findsNWidgets(2));
      final first = tester.getRect(blocks.at(0));
      final second = tester.getRect(blocks.at(1));
      expect(first.left, closeTo(second.left, 1));
      expect(find.byType(CalendarColumnHeader), findsNothing);
    });
  });
}
