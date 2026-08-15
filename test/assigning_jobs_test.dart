import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/views/timed_grid.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';

import 'calendar_event_test.dart' show job;
import 'helpers.dart';

/// The two rigs the day-view tests lay columns out with. Alphabetical, because
/// that is the order the calendar rules its columns in.
const String kDump = 'Dump trailer 14k';
const String kFlatbed = 'Flatbed 20ft';

/// An open job on the pinned day, priced so it has reached the board.
Job openJob(String id, {String rig = kDump, int at = 9}) => job(
  id,
  equipment: [rig],
  at: DateTime(2026, 8, 6, at),
).copyWith(status: JobStatus.open);

/// Booked for the pinned day with no time on it — the all-day band.
Job allDayJob(String id, {String rig = kDump}) => job(
  id,
  equipment: [rig],
  at: DateTime(2026, 8, 6),
).copyWith(status: JobStatus.open);

/// Opens the one job on the board.
Future<void> openIt(WidgetTester tester, [String rig = kDump]) async {
  await tester.tap(find.text(rig).first);
  await settle(tester);
}

void main() {
  group('who decides', () {
    testWidgets('an owner is offered the driver row', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      expect(app.state.canAssign, isTrue);
      await openIt(tester);
      expect(
        find.bySemanticsLabel(RegExp('^Who is on this job, ')),
        findsOneWidget,
      );
    });

    for (final role in [Role.driver, Role.employee]) {
      testWidgets('a ${role.label} is not', (tester) async {
        final app = await pumpApp(
          tester,
          role: role,
          view: CalView.day,
          jobs: [openJob('HL-1')],
        );

        expect(app.state.canAssign, isFalse);
        await openIt(tester);
        expect(
          find.bySemanticsLabel(RegExp('^Who is on this job, ')),
          findsNothing,
        );
      });
    }

    testWidgets('and the rule holds even when the row is bypassed', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.employee,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      expect(await app.state.assign(jobIn(app.state, 'HL-1'), 'c2'), isFalse);
      expect(jobIn(app.state, 'HL-1').assignedTo, isNull);
    });
  });

  group('putting somebody on a job', () {
    testWidgets('the job is theirs from that moment — there is no yes', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      expect(await app.state.assign(jobIn(app.state, 'HL-1'), 'c2'), isTrue);

      final after = jobIn(app.state, 'HL-1');
      expect(after.status, JobStatus.active);
      expect(after.assignedTo, 'c2');
      expect(after.stage, 0);
    });

    testWidgets('but the clock does not start until they set off', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      await app.state.assign(jobIn(app.state, 'HL-1'), app.state.meId);
      expect(
        jobIn(app.state, 'HL-1').startedAt,
        isNull,
        reason: 'work booked days ahead must not bill the wait',
      );

      await app.state.advance(jobIn(app.state, 'HL-1'));
      expect(jobIn(app.state, 'HL-1').startedAt, isNotNull);
    });

    testWidgets('the first step is the only one that sets the clock', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      await app.state.assign(jobIn(app.state, 'HL-1'), app.state.meId);
      await app.state.advance(jobIn(app.state, 'HL-1'));
      final started = jobIn(app.state, 'HL-1').startedAt;

      await app.state.advance(jobIn(app.state, 'HL-1'));
      expect(jobIn(app.state, 'HL-1').startedAt, started);
    });

    testWidgets('nobody goes out on a job with no price', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1').copyWith(status: JobStatus.requested)],
      );

      expect(await app.state.assign(jobIn(app.state, 'HL-1'), 'c2'), isFalse);
      expect(jobIn(app.state, 'HL-1').assignedTo, isNull);

      await openIt(tester);
      expect(find.textContaining('until it has one'), findsOneWidget);
    });

    testWidgets('taking it back puts it on the board again', (tester) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [openJob('HL-1')],
      );

      await app.state.assign(jobIn(app.state, 'HL-1'), 'c2');
      expect(await app.state.assign(jobIn(app.state, 'HL-1'), ''), isTrue);

      final after = jobIn(app.state, 'HL-1');
      expect(after.status, JobStatus.open);
      expect(after.assignedTo, isNull);
    });

    testWidgets('a closed job cannot be moved to somebody else', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        role: Role.admin,
        view: CalView.day,
        jobs: [
          openJob(
            'HL-1',
          ).copyWith(status: JobStatus.done, assignedTo: 'c3', stage: 5),
        ],
      );

      expect(await app.state.assign(jobIn(app.state, 'HL-1'), 'c2'), isFalse);
      expect(
        jobIn(app.state, 'HL-1').assignedTo,
        'c3',
        reason: 'whose hours those were is not up for revision',
      );
    });
  });

  group('who a job can be put on', () {
    testWidgets('the owner and the drivers, never the shared login', (
      tester,
    ) async {
      final app = await pumpApp(tester, role: Role.admin);

      final offered = app.state.assignable.map((c) => c.id).toList();
      expect(offered, contains('c1'), reason: 'the owner drives too');
      expect(offered, contains('c2'));
      expect(
        app.state.assignable.every((c) => c.role.takesJobs),
        isTrue,
        reason: 'a job on the shared login is a job on nobody',
      );
    });
  });

  group('the day view, laid out by rig', () {
    testWidgets('names its columns when there is more than one', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          openJob('HL-1', rig: kDump, at: 7),
          openJob('HL-2', rig: kFlatbed, at: 14),
        ],
      );

      expect(find.byType(CalendarColumnHeader), findsOneWidget);
      // Once on the block, once over its column.
      expect(find.text(kDump), findsNWidgets(2));
      expect(find.text(kFlatbed), findsNWidgets(2));
    });

    testWidgets('does not bother when everything is one rig', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [openJob('HL-1', at: 7), openJob('HL-2', at: 14)],
      );

      expect(find.byType(CalendarColumnHeader), findsNothing);
      // Two blocks, and no header repeating what the colour already says.
      expect(find.text(kDump), findsNWidgets(2));
    });

    testWidgets('two rigs at different hours sit side by side', (tester) async {
      await pumpApp(
        tester,
        view: CalView.day,
        jobs: [
          openJob('HL-1', rig: kDump, at: 7),
          openJob('HL-2', rig: kFlatbed, at: 14),
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
          allDayJob('HL-1', rig: kFlatbed),
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
          // The dump trailer sorts first, so the timed job holds the left
          // column and the all-day flatbed job belongs over the right.
          openJob('HL-1', rig: kDump, at: 9),
          allDayJob('HL-2', rig: kFlatbed),
        ],
      );

      final chip = tester.getRect(find.byType(AllDayChip));
      final block = tester.getRect(find.byType(EventBlock));
      expect(
        chip.left,
        greaterThan(block.right),
        reason: 'the flatbed column is to the right of the dump one',
      );
    });

    testWidgets('two on the same rig share one column', (tester) async {
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
          allDayJob('HL-1', rig: kFlatbed),
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

    testWidgets('a week view still packs by collision, not by rig', (
      tester,
    ) async {
      await pumpApp(
        tester,
        view: CalView.week,
        jobs: [
          openJob('HL-1', rig: kDump, at: 7),
          openJob('HL-2', rig: kFlatbed, at: 14),
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
