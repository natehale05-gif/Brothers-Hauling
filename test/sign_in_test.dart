import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/accounts.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/main.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

import 'helpers.dart';

/// A state with real storage behind it, so a sign-in can be made to survive a
/// relaunch the way it does on a device.
AppState stateOn(Store store, {bool sampleLogins = true}) => AppState(
  store: store,
  location: const SimulatedLocationService(),
  photos: FakePhotoService(),
  autoAdvance: false,
  toastDuration: null,
  sampleLogins: sampleLogins,
  now: () => kTestNow,
);

void main() {
  group('a device nobody has set up', () {
    test('makes itself a way in, and says every one is a sample', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      expect(s.hasAccounts, isTrue);
      expect(s.accounts, hasLength(kSampleLogins.length));
      expect(s.sampleAccounts, hasLength(kSampleLogins.length));
      // One owner, one driver, and the login the rest of the crew share.
      expect(s.accounts.map((a) => a.role).toSet(), {
        Role.admin,
        Role.driver,
        Role.employee,
      });
      s.dispose();
    });

    test('does not, when it was told not to', () async {
      final s = stateOn(MemoryStore(), sampleLogins: false);
      await s.restore();

      expect(s.hasAccounts, isFalse);
      expect(s.accounts, isEmpty);
      s.dispose();
    });

    test('never makes them twice', () async {
      final store = MemoryStore();
      final first = stateOn(store);
      await first.restore();
      first.dispose();

      final second = stateOn(store);
      await second.restore();
      expect(second.accounts, hasLength(kSampleLogins.length));
      second.dispose();
    });
  });

  group('signing in', () {
    test('the right password lets you in at your own level', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      expect(await s.signIn('driver', kSamplePassword), isTrue);
      expect(s.role, Role.driver);
      expect(s.session!.username, 'driver');
      // The board now knows who you are, rather than assuming.
      expect(s.meId, 'c2');
      s.dispose();
    });

    test('an owner comes in as an owner', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      expect(await s.signIn('owner', kSamplePassword), isTrue);
      expect(s.role, Role.admin);
      expect(s.canEditJobs, isTrue);
      expect(s.canSeeMoney, isTrue);
      s.dispose();
    });

    test('a driver sees money but cannot rewrite a job', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      await s.signIn('driver', kSamplePassword);
      expect(s.role, Role.driver);
      // They take the payment, so they have to see what is owed.
      expect(s.canSeeMoney, isTrue);
      expect(s.canTakePayment, isTrue);
      expect(s.canEditJobs, isFalse);
      expect(s.canPriceJobs, isFalse);
      s.dispose();
    });

    test('the shared crew login sees no money at all', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      await s.signIn('crew', kSamplePassword);
      expect(s.role, Role.employee);
      expect(s.canSeeMoney, isFalse);
      expect(s.canTakePayment, isFalse);
      expect(s.canEditJobs, isFalse);
      s.dispose();
    });

    test('the wrong password does not, and says nothing useful', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      expect(await s.signIn('owner', 'guessing'), isFalse);
      expect(s.role, isNull);
      expect(s.session, isNull);
      // The same message either way, so it does not confirm which names exist.
      final wrongPassword = s.toast;
      await s.signIn('nobody-at-all', 'guessing');
      expect(s.toast, wrongPassword);
      s.dispose();
    });

    test('the name is not case sensitive', () async {
      final s = stateOn(MemoryStore());
      await s.restore();

      expect(await s.signIn('  OWNER ', kSamplePassword), isTrue);
      expect(s.role, Role.admin);
      s.dispose();
    });
  });

  group('across a relaunch', () {
    test('you are still signed in', () async {
      final store = MemoryStore();
      final first = stateOn(store);
      await first.restore();
      await first.signIn('driver', kSamplePassword);
      first.dispose();

      final second = stateOn(store);
      await second.restore();
      expect(second.role, Role.driver);
      expect(second.session!.username, 'driver');
      second.dispose();
    });

    test('signing out is remembered too', () async {
      final store = MemoryStore();
      final first = stateOn(store);
      await first.restore();
      await first.signIn('driver', kSamplePassword);
      await first.signOut();
      first.dispose();

      final second = stateOn(store);
      await second.restore();
      expect(second.role, isNull);
      second.dispose();
    });

    test('somebody whose login was removed does not come back in', () async {
      final store = MemoryStore();
      final first = stateOn(store);
      await first.restore();
      await first.signIn('driver', kSamplePassword);
      first.dispose();

      // The account book arrives from elsewhere without them in it — which is
      // what a device syncing to an owner who revoked them looks like. The
      // session on this device is untouched and still says driver.
      final without = AccountBook.decode(
        await store.readString('accounts.v1'),
      ).accounts.where((a) => a.username != 'driver');
      await store.writeString(
        'accounts.v1',
        AccountBook(accounts: {for (final a in without) a.key: a}).encode(),
      );

      final again = stateOn(store);
      await again.restore();
      expect(again.role, isNull, reason: 'the account is gone');
      expect(again.session, isNull);
      again.dispose();
    });

    test('somebody demoted while away does not keep the level', () async {
      final store = MemoryStore();
      final first = stateOn(store);
      await first.restore();
      await first.signIn('driver', kSamplePassword);
      first.dispose();

      final book = AccountBook.decode(await store.readString('accounts.v1'));
      final was = book.accounts.firstWhere((a) => a.username == 'driver');
      final demoted = Account(
        username: was.username,
        crewId: was.crewId,
        role: Role.employee,
        password: was.password,
      );
      await store.writeString(
        'accounts.v1',
        AccountBook(
          accounts: {
            for (final a in book.accounts)
              a.key: a.username == 'driver' ? demoted : a,
          },
        ).encode(),
      );

      final again = stateOn(store);
      await again.restore();
      expect(again.role, isNull, reason: 'the level they had is gone');
      again.dispose();
    });
  });

  group('handing out a login', () {
    test('an owner can, and it stops being a sample once set', () async {
      final s = stateOn(MemoryStore());
      await s.restore();
      await s.signIn('owner', kSamplePassword);

      final member = s.crew.firstWhere((c) => c.id == 'c4');
      expect(
        await s.setLogin(member: member, username: 'sood', password: 'gravel1'),
        isTrue,
      );
      expect(s.hasLogin('c4'), isTrue);
      expect(
        s.accounts.where((a) => a.username == 'sood').single.sample,
        isFalse,
      );

      // And it works.
      await s.signOut();
      expect(await s.signIn('sood', 'gravel1'), isTrue);
      s.dispose();
    });

    test('setting a real password clears the sample flag', () async {
      final s = stateOn(MemoryStore());
      await s.restore();
      await s.signIn('owner', kSamplePassword);
      expect(s.sampleAccounts, hasLength(3));

      final member = s.crew.firstWhere((c) => c.id == 'c1');
      await s.setLogin(
        member: member,
        username: 'owner',
        password: 'a real one',
      );

      expect(s.sampleAccounts.map((a) => a.username), isNot(contains('owner')));
      // The old printed password stops working.
      await s.signOut();
      expect(await s.signIn('owner', kSamplePassword), isFalse);
      expect(await s.signIn('owner', 'a real one'), isTrue);
      s.dispose();
    });

    test('a driver cannot hand one out at all', () async {
      final s = stateOn(MemoryStore());
      await s.restore();
      await s.signIn('driver', kSamplePassword);

      final member = s.crew.firstWhere((c) => c.id == 'c4');
      expect(
        await s.setLogin(member: member, username: 'sood', password: 'gravel1'),
        isFalse,
      );
      expect(s.hasLogin('c4'), isFalse);
      s.dispose();
    });

    test('two people cannot share a username', () async {
      final s = stateOn(MemoryStore());
      await s.restore();
      await s.signIn('owner', kSamplePassword);

      final member = s.crew.firstWhere((c) => c.id == 'c4');
      expect(
        await s.setLogin(member: member, username: 'DRIVER', password: 'x1234'),
        isFalse,
        reason: 'driver is taken, whatever the casing',
      );
      s.dispose();
    });
  });

  group('the sign-in screen', () {
    /// Boots the whole app with nobody signed in, which is what a real launch
    /// looks like.
    Future<AppState> pumpSignIn(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(420, 900)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final state = stateOn(MemoryStore());
      addTearDown(state.dispose);
      await state.restore();

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(tester.view),
          child: BrothersHaulingApp(key: UniqueKey(), state: state),
        ),
      );
      await settle(tester);
      return state;
    }

    testWidgets('is what you get before anything else', (tester) async {
      await pumpSignIn(tester);

      expect(find.text('Sign in to see the board.'), findsOneWidget);
      // Nothing about the board is on screen yet.
      expect(find.text('August 2026'), findsNothing);
    });

    testWidgets('offers the sample logins and says what they are', (
      tester,
    ) async {
      await pumpSignIn(tester);

      expect(find.text('Sample logins'), findsOneWidget);
      expect(find.textContaining(kSamplePassword), findsOneWidget);
      for (final (username, _, _) in kSampleLogins) {
        expect(find.text(username), findsOneWidget);
      }
    });

    testWidgets('one tap fills the box, and signing in opens the board', (
      tester,
    ) async {
      final state = await pumpSignIn(tester);

      await tester.tap(find.bySemanticsLabel('Use the Admin sample login'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Sign in'));
      await settle(tester);

      expect(state.role, Role.admin);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('Sign in to see the board.'), findsNothing);
    });

    testWidgets('a wrong password keeps you out', (tester) async {
      final state = await pumpSignIn(tester);

      await tester.enterText(find.byType(TextField).first, 'owner');
      await tester.enterText(find.byType(TextField).last, 'not it');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Sign in'));
      await settle(tester);

      expect(state.role, isNull);
      expect(find.text('Sign in to see the board.'), findsOneWidget);
    });

    testWidgets('survives a small screen at 1.6x text', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 640)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final state = stateOn(MemoryStore());
      addTearDown(state.dispose);
      await state.restore();

      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: BrothersHaulingApp(key: UniqueKey(), state: state),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
    });
  });

  group('what the device says about itself', () {
    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
    }

    testWidgets('a settled board says so', (tester) async {
      await pumpApp(tester, role: Role.admin);
      await openSheet(tester);

      expect(find.text('This device'), findsOneWidget);
      expect(find.textContaining('saved and sent'), findsOneWidget);
    });

    testWidgets('the web says it cannot be the server', (tester) async {
      // No ServerControl is wired up in a test, which is the same answer a
      // browser gives: this device cannot listen on a port.
      await pumpApp(tester, role: Role.admin);
      await openSheet(tester);
      await tester.ensureVisible(find.text('Serving the crew'));
      await settle(tester);

      expect(find.text('Serving the crew'), findsOneWidget);
      expect(find.textContaining('cannot listen on a port'), findsOneWidget);
    });

    testWidgets('a driver is not offered the server at all', (tester) async {
      await pumpApp(tester, role: Role.driver);
      await openSheet(tester);

      expect(find.text('Serving the crew'), findsNothing);
      // But still sees whether their own work is safe.
      expect(find.text('This device'), findsOneWidget);
    });
  });

  group('the way out', () {
    testWidgets('signing out puts the login box back', (tester) async {
      final app = await pumpApp(tester, role: Role.admin);

      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
      // The sheet scrolls, and the way out is at the bottom of it.
      await tester.ensureVisible(find.bySemanticsLabel('Sign out'));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Sign out'));
      await settle(tester);

      expect(app.state.role, isNull);
      expect(find.text('Sign in to see the board.'), findsOneWidget);
    });

    testWidgets('only an owner is offered the logins screen', (tester) async {
      await pumpApp(tester, role: Role.driver);
      await tester.tap(find.bySemanticsLabel('Calendars'));
      await settle(tester);
      await tester.ensureVisible(find.bySemanticsLabel('Sign out'));
      await settle(tester);

      expect(find.bySemanticsLabel('Sign out'), findsOneWidget);
      expect(find.bySemanticsLabel('Logins'), findsNothing);
    });
  });
}
