import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/outbox.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/link_service.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/main.dart';

import 'helpers.dart';

/// A link the test can cut, the way a canyon cuts a driver's signal.
class _Link {
  SendOutcome outcome = SendOutcome.accepted;
  Future<SendOutcome> call(_) async => outcome;
}

void main() {
  late MemoryStore store;
  late _Link link;

  setUp(() {
    store = MemoryStore();
    link = _Link();
  });

  /// Boots the app over a shared store, so "relaunch" means what it says.
  Future<AppState> pumpBoard(
    WidgetTester tester, {
    Role role = Role.employee,
  }) async {
    tester.view
      ..physicalSize = const Size(430, 900)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final board = LocalBoardRepository(store: store, send: link.call);
    await board.load();

    final state = AppState(
      board: board,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
    );
    addTearDown(state.dispose);
    state.enter(role);

    await tester.pumpWidget(
      BrothersHaulingApp(state: state, links: RecordingLinkService()),
    );
    await settle(tester);
    return state;
  }

  group('the strip only appears when something is unsettled', () {
    testWidgets('nothing is shown when everything has landed', (tester) async {
      await pumpBoard(tester);

      // An always-on "all good" banner is noise the eye learns to skip, which
      // is exactly the wrong habit for the day it turns red.
      expect(find.textContaining('saved on this phone'), findsNothing);
      expect(find.text('SEND NOW'), findsNothing);
    });

    testWidgets('a change made with no signal is reported as not sent', (
      tester,
    ) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;

      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);

      expect(
        find.textContaining('1 change saved on this phone'),
        findsOneWidget,
      );
      expect(find.text('SEND NOW'), findsOneWidget);
    });

    testWidgets('it never says "saved" or "synced" for queued work', (
      tester,
    ) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;
      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);

      // The wording has to keep the driver's expectation accurate: it is on
      // the phone, not with dispatch.
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(text, contains('saved on this phone'));
      expect(text, isNot(contains('Synced')));
      expect(text, isNot(contains('Sent to dispatch')));
    });

    testWidgets('it clears once the work actually lands', (tester) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;
      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);
      expect(find.text('SEND NOW'), findsOneWidget);

      link.outcome = SendOutcome.accepted;
      await state.syncNow();
      await settle(tester);

      expect(find.text('SEND NOW'), findsNothing);
      expect(state.syncState.settled, isTrue);
    });
  });

  group('work the server refused', () {
    testWidgets('is called out as never having arrived', (tester) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.rejected;

      await state.claim(jobIn(state, 'HL-4471'));
      await state.syncNow();
      await settle(tester);

      expect(find.textContaining('dispatch never got'), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);
    });

    testWidgets('retry is one tap and clears it when it works', (tester) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.rejected;
      await state.claim(jobIn(state, 'HL-4471'));
      await state.syncNow();
      await settle(tester);

      link.outcome = SendOutcome.accepted;
      await tester.tap(find.text('RETRY'));
      await settle(tester);

      expect(find.text('RETRY'), findsNothing);
      expect(state.syncState.settled, isTrue);
    });
  });

  group('the driver can see which job is affected', () {
    testWidgets('the card carrying unsent work is marked', (tester) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;

      await state.claim(jobIn(state, 'HL-4471'));
      state.setTab(HaulTab.mine);
      await settle(tester);

      // A global count does not tell you which card to worry about.
      expect(find.text('NOT SENT YET'), findsOneWidget);
    });

    testWidgets('only the affected card is marked', (tester) async {
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;
      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);

      expect(state.unsyncedJobIds, {'HL-4471'});
      // My jobs shows exactly the one card that is owed to dispatch.
      expect(find.text('NOT SENT YET'), findsOneWidget);

      // The open board is full of jobs with nothing pending; none are marked.
      state.setTab(HaulTab.board);
      await settle(tester);
      expect(find.text('NOT SENT YET'), findsNothing);
    });
  });

  group('the board survives a relaunch', () {
    testWidgets('a claim made in a dead zone is still there next launch', (
      tester,
    ) async {
      link.outcome = SendOutcome.retry;
      final first = await pumpBoard(tester);
      await first.claim(jobIn(first, 'HL-4471'));
      await settle(tester);
      expect(jobIn(first, 'HL-4471').status, JobStatus.active);

      // The app is killed and relaunched over the same device storage.
      final second = await pumpBoard(tester);

      expect(jobIn(second, 'HL-4471').status, JobStatus.active);
      expect(jobIn(second, 'HL-4471').assignedTo, 'c1');
      expect(second.syncState.pending, 1, reason: 'still owed to dispatch');
      expect(find.textContaining('saved on this phone'), findsOneWidget);
    });

    testWidgets('a photo taken offline is still attached next launch', (
      tester,
    ) async {
      link.outcome = SendOutcome.retry;
      final first = await pumpBoard(tester);
      await first.claim(jobIn(first, 'HL-4471'));
      await first.addPhoto(jobIn(first, 'HL-4471'), before: true);
      await settle(tester);
      expect(jobIn(first, 'HL-4471').photoBefore, isNotNull);

      final second = await pumpBoard(tester);

      // The evidence that closes the job cannot evaporate with the process.
      expect(jobIn(second, 'HL-4471').photoBefore, isNotNull);
      expect(jobIn(second, 'HL-4471').photoBefore!.bytes, isNotEmpty);
    });

    testWidgets('a whole job worked offline replays intact', (tester) async {
      link.outcome = SendOutcome.retry;
      final first = await pumpBoard(tester);
      final id = 'HL-4471';

      await first.claim(jobIn(first, id));
      for (var i = 0; i < 4; i++) {
        await first.advance(jobIn(first, id));
      }
      await first.addPhoto(jobIn(first, id), before: true);
      await first.addPhoto(jobIn(first, id), before: false);
      await first.advance(jobIn(first, id));
      await settle(tester);
      expect(jobIn(first, id).status, JobStatus.done);

      final second = await pumpBoard(tester);
      final job = jobIn(second, id);

      expect(job.status, JobStatus.done);
      expect(job.stage, 5);
      expect(job.photosComplete, isTrue);
      expect(job.events.last.label, 'Job closed');
      // Eight actions, none of which reached dispatch, none of which were lost.
      expect(second.syncState.pending, 8);
    });
  });

  group('accessibility of the sync strip', () {
    testWidgets('it is a live region and names its action', (tester) async {
      final handle = tester.ensureSemantics();
      final state = await pumpBoard(tester);
      link.outcome = SendOutcome.retry;
      await state.claim(jobIn(state, 'HL-4471'));
      await settle(tester);

      expect(
        find.bySemanticsLabel(RegExp('saved on this phone')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Send the saved changes now'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
