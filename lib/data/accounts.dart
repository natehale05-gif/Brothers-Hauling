import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../models/role.dart';

/// How many times the password is stretched.
///
/// High enough that guessing at a stolen file is slow, low enough that a phone
/// signs in without a visible pause. This is the number to raise, never lower —
/// a stored account remembers the count it was written with, so raising it only
/// affects passwords set from then on.
const int kPasswordRounds = 120000;

const int _saltBytes = 16;
const int _keyBytes = 32;

/// PBKDF2-HMAC-SHA256.
///
/// Written out rather than pulled in because it is the one piece of this that
/// must be exactly right: a password is only ever stored as the output of this,
/// so the owner holding the file cannot read anybody's password out of it.
Uint8List _pbkdf2({
  required List<int> password,
  required List<int> salt,
  required int rounds,
  required int length,
}) {
  final hmac = Hmac(sha256, password);
  final out = BytesBuilder();

  for (var block = 1; out.length < length; block++) {
    // The block index goes on the end of the salt, big-endian, per the spec.
    final first = hmac.convert([
      ...salt,
      (block >> 24) & 0xFF,
      (block >> 16) & 0xFF,
      (block >> 8) & 0xFF,
      block & 0xFF,
    ]).bytes;

    final accumulated = Uint8List.fromList(first);
    var previous = first;
    for (var i = 1; i < rounds; i++) {
      previous = hmac.convert(previous).bytes;
      for (var j = 0; j < accumulated.length; j++) {
        accumulated[j] ^= previous[j];
      }
    }
    out.add(accumulated);
  }

  return Uint8List.fromList(out.takeBytes().sublist(0, length));
}

/// Compares two digests without leaking, through timing, how much of one
/// matched. Byte-by-byte with an early return would tell an attacker exactly
/// how far a guess got.
bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

String _b64(List<int> bytes) => base64Url.encode(bytes);

/// Cryptographically random bytes. [Random.secure] throws rather than quietly
/// falling back to a predictable source, which is the behaviour we want.
Uint8List randomBytes(int count) {
  final rng = Random.secure();
  return Uint8List.fromList([for (var i = 0; i < count; i++) rng.nextInt(256)]);
}

/// A password, as it is safe to write down.
///
/// The owner's laptop holds this file. Holding it must not mean being able to
/// read what anybody typed — including the owner, who very often is the person
/// with a reason to try.
class PasswordHash {
  const PasswordHash({
    required this.salt,
    required this.hash,
    required this.rounds,
  });

  /// Unique per account, so two people who pick the same password do not get
  /// the same stored value — and so one cracked password is one password.
  final String salt;
  final String hash;
  final int rounds;

  factory PasswordHash.of(String password, {int rounds = kPasswordRounds}) {
    final salt = randomBytes(_saltBytes);
    return PasswordHash(
      salt: _b64(salt),
      rounds: rounds,
      hash: _b64(
        _pbkdf2(
          password: utf8.encode(password),
          salt: salt,
          rounds: rounds,
          length: _keyBytes,
        ),
      ),
    );
  }

  bool matches(String password) {
    final computed = _pbkdf2(
      password: utf8.encode(password),
      salt: base64Url.decode(salt),
      // The stored count, not the current one: an account written under an
      // older setting must still be able to sign in.
      rounds: rounds,
      length: _keyBytes,
    );
    return _constantTimeEquals(computed, base64Url.decode(hash));
  }

  Map<String, Object?> toJson() => {
    'salt': salt,
    'hash': hash,
    'rounds': rounds,
  };

  static PasswordHash? fromJson(Map<String, Object?> json) {
    final salt = json['salt'] as String?;
    final hash = json['hash'] as String?;
    final rounds = (json['rounds'] as num?)?.toInt();
    if (salt == null || hash == null || rounds == null || rounds < 1) {
      return null;
    }
    return PasswordHash(salt: salt, hash: hash, rounds: rounds);
  }
}

/// Somebody who can sign in, and what they may do once they have.
///
/// Separate from [CrewMember] on purpose. A person on the roster is a fact
/// about the company; an account is a way into the data. Deleting one should
/// not silently do the other, and the roster is something the whole crew can
/// see while this never leaves the owner's device.
class Account {
  const Account({
    required this.username,
    required this.crewId,
    required this.role,
    required this.password,
  });

  /// What they type to sign in. Compared case-insensitively and trimmed, so
  /// "Kara" and "kara " are the same person at the login box.
  final String username;

  /// The roster entry this account is. Ties a login to the hours and the jobs
  /// that already exist for that person.
  final String crewId;

  final Role role;
  final PasswordHash password;

  static String normalise(String username) => username.trim().toLowerCase();

  String get key => normalise(username);

  Account withPassword(String password) => Account(
    username: username,
    crewId: crewId,
    role: role,
    password: PasswordHash.of(password),
  );

  Map<String, Object?> toJson() => {
    'username': username,
    'crewId': crewId,
    'role': role.name,
    'password': password.toJson(),
  };

  static Account? fromJson(Map<String, Object?> json) {
    final username = json['username'] as String?;
    final crewId = json['crewId'] as String?;
    final password = json['password'];
    final named = Role.values.where((r) => r.name == json['role']);
    if (username == null ||
        crewId == null ||
        named.isEmpty ||
        password is! Map) {
      return null;
    }
    final hash = PasswordHash.fromJson(password.cast<String, Object?>());
    if (hash == null) return null;
    return Account(
      username: username,
      crewId: crewId,
      role: named.first,
      password: hash,
    );
  }
}

/// A signed-in device.
///
/// The token is what the device sends from then on, so the password is typed
/// once and never stored anywhere. Revoking somebody is deleting their tokens,
/// which does not require knowing their password either.
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.crewId,
    required this.role,
  });

  final String token;
  final String username;
  final String crewId;
  final Role role;

  Map<String, Object?> toJson() => {
    'token': token,
    'username': username,
    'crewId': crewId,
    'role': role.name,
  };

  static Session? fromJson(Map<String, Object?> json) {
    final token = json['token'] as String?;
    final username = json['username'] as String?;
    final crewId = json['crewId'] as String?;
    final named = Role.values.where((r) => r.name == json['role']);
    if (token == null || username == null || crewId == null || named.isEmpty) {
      return null;
    }
    return Session(
      token: token,
      username: username,
      crewId: crewId,
      role: named.first,
    );
  }
}

/// Every account on this device, and the sessions handed out from it.
///
/// Lives only where the data lives — the owner's machine. A crew device holds
/// its own token and nothing about anybody else.
class AccountBook {
  AccountBook({Map<String, Account>? accounts}) : _accounts = {...?accounts};

  final Map<String, Account> _accounts;
  final Map<String, Session> _sessions = {};

  Iterable<Account> get accounts => _accounts.values;

  bool get isEmpty => _accounts.isEmpty;

  bool has(String username) =>
      _accounts.containsKey(Account.normalise(username));

  /// Replaces every account with [incoming], in place.
  ///
  /// In place because the server and the screen that edits accounts have to be
  /// looking at the same book — handing one of them a fresh object is how an
  /// owner adds somebody, sees it confirmed, and watches them fail to connect
  /// until the app is restarted.
  ///
  /// Sessions go with them: the roster this vouched for no longer exists.
  void adopt(Iterable<Account> incoming) {
    _accounts
      ..clear()
      ..addEntries(incoming.map((a) => MapEntry(a.key, a)));
    _sessions.clear();
  }

  /// Adds or replaces an account. Returns false when the name is taken by
  /// somebody else, rather than quietly overwriting a colleague's login.
  bool put(Account account) {
    final existing = _accounts[account.key];
    if (existing != null && existing.crewId != account.crewId) return false;
    _accounts[account.key] = account;
    return true;
  }

  void remove(String username) {
    final key = Account.normalise(username);
    _accounts.remove(key);
    // Their device stops working at the next request rather than at the next
    // restart, which is the whole point of removing somebody.
    _sessions.removeWhere((_, s) => Account.normalise(s.username) == key);
  }

  /// Checks a password and hands back a session, or null.
  ///
  /// Deliberately says nothing about which half was wrong: "no such user" tells
  /// somebody probing the login box which names are real.
  Session? signIn(String username, String password) {
    final account = _accounts[Account.normalise(username)];
    if (account == null || !account.password.matches(password)) return null;

    final session = Session(
      token: _b64(randomBytes(24)),
      username: account.username,
      crewId: account.crewId,
      role: account.role,
    );
    _sessions[session.token] = session;
    return session;
  }

  Session? sessionFor(String? token) => token == null ? null : _sessions[token];

  void signOut(String token) => _sessions.remove(token);

  /// Only the hashes go to disk. There is nothing here to leak but work.
  String encode() =>
      jsonEncode([for (final account in _accounts.values) account.toJson()]);

  static AccountBook decode(String? text) {
    if (text == null || text.isEmpty) return AccountBook();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return AccountBook();
      final out = <String, Account>{};
      for (final raw in decoded.whereType<Map>()) {
        final account = Account.fromJson(raw.cast<String, Object?>());
        if (account != null) out[account.key] = account;
      }
      return AccountBook(accounts: out);
    } catch (_) {
      // A corrupt file must not lock everybody out permanently, but it also
      // must not be treated as "no accounts, let anyone in" by a caller that
      // forgets to check. Empty is safe: the server refuses every request.
      return AccountBook();
    }
  }
}
