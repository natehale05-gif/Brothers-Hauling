import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/accounts.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/outbox.dart';
import 'package:haul_board/data/remote_board.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/data/sync_server.dart';
import 'package:haul_board/models/mutation.dart';
import 'package:haul_board/models/role.dart';

/// Rounds are the cost of a sign-in, and these tests do a lot of them. The
/// number under test is that the *stored* count is honoured, not what it is.
const int _fastRounds = 1;

void main() {
  group('a password is stored so that holding the file is not reading it', () {
    test('the password itself is nowhere in what gets written', () {
      final hash = PasswordHash.of('gravel-truck-42', rounds: _fastRounds);
      final written = jsonEncode(hash.toJson());

      expect(written, isNot(contains('gravel-truck-42')));
    });

    test('the right password matches', () {
      final hash = PasswordHash.of('gravel-truck-42', rounds: _fastRounds);
      expect(hash.matches('gravel-truck-42'), isTrue);
    });

    test('a near miss does not', () {
      final hash = PasswordHash.of('gravel-truck-42', rounds: _fastRounds);
      expect(hash.matches('gravel-truck-4'), isFalse);
      expect(hash.matches('Gravel-truck-42'), isFalse);
      expect(hash.matches(''), isFalse);
    });

    test('two people with the same password store different things', () {
      final one = PasswordHash.of('same', rounds: _fastRounds);
      final two = PasswordHash.of('same', rounds: _fastRounds);

      // Per-account salt: one cracked password has to be one password.
      expect(one.salt, isNot(two.salt));
      expect(one.hash, isNot(two.hash));
    });

    test('an account written at an older cost still signs in', () {
      final hash = PasswordHash.of('old-account', rounds: 3);
      final back = PasswordHash.fromJson(jsonDecode(jsonEncode(hash.toJson())));

      // Raising the round count must not lock out everybody hired before it.
      expect(back!.rounds, 3);
      expect(back.matches('old-account'), isTrue);
    });

    test('a hash that cannot be read comes back as nothing', () {
      expect(PasswordHash.fromJson({'salt': 'x'}), isNull);
      expect(
        PasswordHash.fromJson({'salt': 'x', 'hash': 'y', 'rounds': 0}),
        isNull,
      );
    });
  });

  group('the account book', () {
    AccountBook bookWith(String name, String password, {Role? role}) {
      final book = AccountBook();
      book.put(
        Account(
          username: name,
          crewId: 'c2',
          role: role ?? Role.employee,
          password: PasswordHash.of(password, rounds: _fastRounds),
        ),
      );
      return book;
    }

    test('the right password hands back a session', () {
      final book = bookWith('kara', 'flatbed');
      final session = book.signIn('kara', 'flatbed');

      expect(session, isNotNull);
      expect(session!.crewId, 'c2');
      expect(session.role, Role.employee);
      expect(session.token, isNotEmpty);
    });

    test('the name is not case sensitive, because a login box never is', () {
      final book = bookWith('Kara', 'flatbed');
      expect(book.signIn('  kara ', 'flatbed'), isNotNull);
    });

    test('the password is', () {
      final book = bookWith('kara', 'flatbed');
      expect(book.signIn('kara', 'Flatbed'), isNull);
    });

    test('a name nobody has is refused like a wrong password', () {
      final book = bookWith('kara', 'flatbed');
      // Same answer either way: telling somebody a name is real tells them
      // which names are worth guessing at.
      expect(book.signIn('nobody', 'flatbed'), isNull);
    });

    test('two sign-ins are two sessions', () {
      final book = bookWith('kara', 'flatbed');
      final first = book.signIn('kara', 'flatbed')!;
      final second = book.signIn('kara', 'flatbed')!;

      // A phone and a tablet are two devices, and revoking one is not both.
      expect(first.token, isNot(second.token));
      expect(book.sessionFor(first.token), isNotNull);
      expect(book.sessionFor(second.token), isNotNull);
    });

    test('removing somebody kills the device already signed in', () {
      final book = bookWith('kara', 'flatbed');
      final session = book.signIn('kara', 'flatbed')!;

      book.remove('KARA');

      // At the next request, not at the next restart — that is the point of
      // taking somebody off.
      expect(book.sessionFor(session.token), isNull);
      expect(book.signIn('kara', 'flatbed'), isNull);
    });

    test('a name already taken by somebody else is refused', () {
      final book = bookWith('kara', 'flatbed');
      final clash = Account(
        username: 'kara',
        crewId: 'c7',
        role: Role.admin,
        password: PasswordHash.of('mine-now', rounds: _fastRounds),
      );

      expect(book.put(clash), isFalse);
      expect(book.signIn('kara', 'mine-now'), isNull);
      expect(book.signIn('kara', 'flatbed'), isNotNull);
    });

    test('the same person may change their own password', () {
      final book = bookWith('kara', 'flatbed');
      final updated = book.accounts.first.withPassword('lowboy');

      expect(book.put(updated), isTrue);
      expect(book.signIn('kara', 'lowboy'), isNotNull);
      expect(book.signIn('kara', 'flatbed'), isNull);
    });

    test('it survives being written and read', () {
      final book = bookWith('kara', 'flatbed', role: Role.admin);
      final back = AccountBook.decode(book.encode());

      expect(back.signIn('kara', 'flatbed')?.role, Role.admin);
    });

    test('a corrupt file is no accounts, not every account', () {
      // Which means the server refuses everybody rather than letting anybody
      // in. Locked out is recoverable; wide open is not.
      expect(AccountBook.decode('{not json').isEmpty, isTrue);
      expect(AccountBook.decode('[{"username":"x"}]').isEmpty, isTrue);
    });
  });

  group('an address somebody typed', () {
    test('a bare IP gets the standard port', () {
      final address = DispatchAddress.parse('192.168.1.14')!;
      expect(address.host, '192.168.1.14');
      expect(address.port, kHaulPort);
    });

    test('a port they gave is kept', () {
      expect(DispatchAddress.parse('192.168.1.14:9000')!.port, 9000);
    });

    test('a scheme and a trailing slash are forgiven', () {
      final address = DispatchAddress.parse('  http://yard-laptop:8477/  ')!;
      expect(address.host, 'yard-laptop');
      expect(address.port, 8477);
    });

    test('nothing at all is nothing', () {
      expect(DispatchAddress.parse('   '), isNull);
    });
  });

  group('a crew device talking to the yard laptop', () {
    late HaulServer server;
    late LocalBoardRepository board;
    late AccountBook accounts;
    late DispatchClient client;

    setUp(() async {
      board = LocalBoardRepository(store: MemoryStore());
      accounts = AccountBook();
      accounts.put(
        Account(
          username: 'kara',
          crewId: 'c2',
          role: Role.employee,
          password: PasswordHash.of('flatbed', rounds: _fastRounds),
        ),
      );

      // Port 0 lets the OS pick a free one, so tests never collide.
      server = HaulServer(board: board, accounts: accounts, port: 0);
      await server.start();

      client = DispatchClient(
        address: DispatchAddress(host: '127.0.0.1', port: server.boundPort!),
      );
    });

    tearDown(() async {
      client.close();
      await server.stop();
      board.dispose();
    });

    test('signing in gets a token and says who you are', () async {
      final session = await client.signIn('kara', 'flatbed');

      expect(session.token, isNotEmpty);
      expect(session.crewId, 'c2');
      expect(session.role, Role.employee);
    });

    test('a wrong password says so without saying which half', () async {
      await expectLater(
        client.signIn('kara', 'wrong'),
        throwsA(
          isA<SignInFailure>().having(
            (e) => e.message,
            'message',
            contains('do not go together'),
          ),
        ),
      );
    });

    test('the board is not readable without signing in', () async {
      expect(await client.fetchBoard(), isNull);
    });

    test('and is readable once you have', () async {
      await client.signIn('kara', 'flatbed');
      final remote = await client.fetchBoard();

      expect(remote, isNotNull);
      expect(remote!.jobs, isNotEmpty);
      expect(remote.crew, isNotEmpty);
      expect(remote.jobs.map((j) => j.id), contains('HL-4471'));
    });

    test('a change made on a phone lands on the laptop', () async {
      await client.signIn('kara', 'flatbed');

      final outcome = await client.send(
        ClaimJob(
          id: 'm1',
          jobId: 'HL-4471',
          actorId: 'c2',
          at: DateTime(2026, 8, 2, 9),
        ),
      );

      expect(outcome, SendOutcome.accepted);
      expect(board.jobs.firstWhere((j) => j.id == 'HL-4471').assignedTo, 'c2');
    });

    test('a change filed under somebody else is refused outright', () async {
      await client.signIn('kara', 'flatbed');

      final outcome = await client.send(
        ClaimJob(
          id: 'm2',
          jobId: 'HL-4471',
          // The token says c2. Trusting the body would let any signed-in
          // device file work as the owner.
          actorId: 'c1',
          at: DateTime(2026, 8, 2, 9),
        ),
      );

      expect(outcome, SendOutcome.rejected);
      expect(
        board.jobs.firstWhere((j) => j.id == 'HL-4471').assignedTo,
        isNull,
      );
    });

    test('an unsigned device cannot change anything', () async {
      final outcome = await client.send(
        ClaimJob(
          id: 'm3',
          jobId: 'HL-4471',
          actorId: 'c2',
          at: DateTime(2026, 8, 2, 9),
        ),
      );

      // Retry, not rejected: signing in again is the fix, and the work should
      // wait for it rather than be thrown away.
      expect(outcome, SendOutcome.retry);
      expect(
        board.jobs.firstWhere((j) => j.id == 'HL-4471').assignedTo,
        isNull,
      );
    });

    test('a laptop that is asleep is a retry, never a loss', () async {
      await client.signIn('kara', 'flatbed');
      await server.stop();

      final outcome = await client.send(
        ClaimJob(
          id: 'm4',
          jobId: 'HL-4471',
          actorId: 'c2',
          at: DateTime(2026, 8, 2, 9),
        ),
      );

      // The whole offline story depends on this one answer being right.
      expect(outcome, SendOutcome.retry);
    });

    test('signing out stops the token working', () async {
      final session = await client.signIn('kara', 'flatbed');
      accounts.signOut(session.token);

      expect(await client.fetchBoard(), isNull);
    });

    test('the same booking twice is still one job', () async {
      await client.signIn('kara', 'flatbed');
      final claim = ClaimJob(
        id: 'm5',
        jobId: 'HL-4471',
        actorId: 'c2',
        at: DateTime(2026, 8, 2, 9),
      );

      expect(await client.send(claim), SendOutcome.accepted);
      // A retried send must not double-apply. The mutation is idempotent and
      // the server reports honestly that nothing changed the second time.
      final second = await client.send(claim);
      expect(second, SendOutcome.accepted);
      expect(board.jobs.firstWhere((j) => j.id == 'HL-4471').assignedTo, 'c2');
    });

    test(
      'a body that is not a mutation is rejected, not queued forever',
      () async {
        // Straight at the socket: the client would never send this, but a stale
        // build on somebody's phone might.
        final session = await client.signIn('kara', 'flatbed');
        final http = HttpClient();
        addTearDown(() => http.close(force: true));

        final request = await http.postUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}/mutations'),
        );
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${session.token}',
        );
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'kind': 'nonsense'}));
        final response = await request.close();
        await response.drain<void>();

        // Rejected rather than retried: replaying it will not make it readable,
        // and keeping it queued blocks everything behind it.
        expect(response.statusCode, HttpStatus.badRequest);
      },
    );

    test('an address that is not a thing is refused', () async {
      await client.signIn('kara', 'flatbed');
      final http = HttpClient();
      addTearDown(() => http.close(force: true));

      final request = await http.getUrl(
        Uri.parse('http://127.0.0.1:${server.boundPort}/payroll'),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${client.session!.token}',
      );
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.notFound);
    });
  });
}
