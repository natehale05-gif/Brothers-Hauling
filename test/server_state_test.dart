import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/accounts.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/server_control.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

/// Stands in for a real socket. What is under test here is who is allowed to
/// turn it on and what gets written down — not that dart:io can bind a port,
/// which sync_server_test drives for real.
class FakeServerControl implements ServerControl {
  FakeServerControl({this.supported = true});

  @override
  final bool supported;

  bool _running = false;
  int starts = 0;
  Object? failWith;

  @override
  bool get running => _running;

  @override
  List<String> get addresses => _running ? const ['192.168.1.14'] : const [];

  @override
  int get port => 8477;

  @override
  Future<void> start() async {
    if (failWith != null) throw failWith!;
    starts++;
    _running = true;
  }

  @override
  Future<void> stop() async => _running = false;
}

void main() {
  ({AppState state, AccountBook book, FakeServerControl server, Store store})
  boot({Store? store, Role role = Role.admin, bool supported = true}) {
    final shared = store ?? MemoryStore();
    final book = AccountBook();
    final server = FakeServerControl(supported: supported);
    final state = AppState(
      board: LocalBoardRepository(store: shared),
      store: shared,
      accounts: book,
      server: server,
      location: const SimulatedLocationService(),
      photos: FakePhotoService(),
      autoAdvance: false,
      toastDuration: null,
    );
    addTearDown(state.dispose);
    state.enter(role);
    return (state: state, book: book, server: server, store: shared);
  }

  group('who may run the server', () {
    test('an owner may', () {
      expect(boot().state.canManageServer, isTrue);
    });

    test('a driver may not', () {
      // The data is on the owner's machine. Handing out the keys to it is not
      // a scheduling decision.
      expect(boot(role: Role.driver).state.canManageServer, isFalse);
    });

    test('nor may the shared crew login', () {
      expect(boot(role: Role.employee).state.canManageServer, isFalse);
    });

    test('nor an owner standing in the crew view', () {
      final harness = boot();
      harness.state.toggleEmployeeView();
      expect(harness.state.canManageServer, isFalse);
    });

    test('a browser says so rather than offering a dead button', () {
      final harness = boot(supported: false);
      expect(harness.state.canServe, isFalse);
    });
  });

  group('handing out a login', () {
    test('an owner can give somebody one', () async {
      final harness = boot();
      final member = harness.state.crew.first;

      final ok = await harness.state.setLogin(
        member: member,
        username: 'kara',
        password: 'flatbed12',
      );

      expect(ok, isTrue);
      expect(harness.state.hasLogin(member.id), isTrue);
      expect(harness.book.signIn('kara', 'flatbed12'), isNotNull);
    });

    test('the password is never written down as itself', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      final written = await harness.store.readString('accounts.v1');
      // The owner's laptop holds this file. Holding it must not be reading it.
      expect(written, isNotNull);
      expect(written, isNot(contains('flatbed12')));
    });

    test('the server and the screen share one book', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      // Two copies is how somebody gets added, sees it confirmed, and still
      // cannot connect until the app is restarted.
      expect(harness.book.has('kara'), isTrue);
    });

    test('a driver cannot hand out logins', () async {
      final harness = boot(role: Role.employee);
      final ok = await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'sneaky',
        password: 'letmein1',
      );

      expect(ok, isFalse);
      expect(harness.book.isEmpty, isTrue);
    });

    test('a blank password is refused', () async {
      final harness = boot();
      final ok = await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: '',
      );
      expect(ok, isFalse);
    });

    test('a name somebody else already uses is refused', () async {
      final harness = boot();
      final crew = harness.state.crew;
      await harness.state.setLogin(
        member: crew[0],
        username: 'kara',
        password: 'flatbed12',
      );

      final ok = await harness.state.setLogin(
        member: crew[1],
        username: 'KARA',
        password: 'mine-now',
      );

      expect(ok, isFalse);
      expect(harness.book.signIn('kara', 'flatbed12'), isNotNull);
    });

    test('taking it away stops them signing in', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      expect(await harness.state.removeLogin('kara'), isTrue);
      expect(harness.book.signIn('kara', 'flatbed12'), isNull);
    });

    test('logins survive a relaunch', () async {
      final store = MemoryStore();
      final first = boot(store: store);
      await first.state.setLogin(
        member: first.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      final second = boot(store: store);
      await second.state.restore();

      expect(second.book.signIn('kara', 'flatbed12'), isNotNull);
    });
  });

  group('turning it on', () {
    test('it refuses to serve with nobody able to connect', () async {
      final harness = boot();
      final ok = await harness.state.setServing(true);

      // A server that refuses everybody looks exactly like a broken network
      // to the crew standing in the yard.
      expect(ok, isFalse);
      expect(harness.state.serving, isFalse);
    });

    test('with one login it starts, and says where to find it', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      expect(await harness.state.setServing(true), isTrue);
      expect(harness.state.serving, isTrue);
      expect(harness.state.serverAddresses, ['192.168.1.14']);
      expect(harness.state.serverPort, 8477);
    });

    test('turning it on twice starts one server', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );

      await harness.state.setServing(true);
      await harness.state.setServing(true);

      expect(harness.server.starts, 1);
    });

    test('stopping it stops it', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );
      await harness.state.setServing(true);

      expect(await harness.state.setServing(false), isTrue);
      expect(harness.state.serving, isFalse);
      expect(harness.state.serverAddresses, isEmpty);
    });

    test('a port already taken is reported, not swallowed', () async {
      final harness = boot();
      await harness.state.setLogin(
        member: harness.state.crew.first,
        username: 'kara',
        password: 'flatbed12',
      );
      harness.server.failWith = Exception('address already in use');

      final ok = await harness.state.setServing(true);

      // Otherwise the toggle springs back and nobody knows why.
      expect(ok, isFalse);
      expect(harness.state.serving, isFalse);
      expect(harness.state.toast, contains('Could not start'));
    });

    test('a driver cannot start it', () async {
      final harness = boot(role: Role.employee);
      expect(await harness.state.setServing(true), isFalse);
      expect(harness.state.serving, isFalse);
    });
  });
}
