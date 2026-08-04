import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/mutation.dart';
import 'accounts.dart';
import 'board_repository.dart';

/// The port the owner's machine listens on.
///
/// Fixed rather than chosen at random so the address a driver types once keeps
/// working tomorrow. High enough not to need admin rights on any platform.
const int kHaulPort = 8477;

/// The owner's device, acting as the server for the crew.
///
/// There is no cloud in this app and this is why it still works: the board
/// lives on one machine on the yard's network, every other device syncs to it,
/// and nothing leaves the premises. The trade is the honest one — the laptop
/// has to be awake and on the same network, and crew devices work offline in
/// the meantime because the outbox was built for exactly that.
///
/// Logins stay private. The book holds PBKDF2 hashes, so the person running
/// the server cannot read anybody's password out of the file they are holding.
class HaulServer {
  HaulServer({
    required this.board,
    required this.accounts,
    this.port = kHaulPort,
  });

  final BoardRepository board;

  /// Shared with whoever edits accounts, so a login added while the server is
  /// running works immediately — see [AccountBook.adopt].
  final AccountBook accounts;

  final int port;

  HttpServer? _socket;

  bool get running => _socket != null;

  /// The port actually bound, which differs from [port] only when the caller
  /// asked for 0 — useful in a test, never in the yard.
  int? get boundPort => _socket?.port;

  /// Starts listening on every interface this machine has.
  ///
  /// [InternetAddress.anyIPv4] rather than loopback: a server only the laptop
  /// can reach is not a server. What keeps it private is the network it is on
  /// and the token every request has to carry, not the interface.
  Future<void> start() async {
    if (_socket != null) return;
    final socket = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _socket = socket;
    unawaited(_serve(socket));
  }

  Future<void> stop() async {
    final socket = _socket;
    _socket = null;
    await socket?.close(force: true);
  }

  Future<void> _serve(HttpServer socket) async {
    await for (final request in socket) {
      try {
        await _handle(request);
      } catch (_) {
        // One malformed request must not take the yard's board down with it.
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {
          // The client hung up mid-reply. Nothing to say to nobody.
        }
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.set('Cache-Control', 'no-store');

    final path = request.uri.path;

    // Unauthenticated, and the only one: it is how a device gets a token.
    if (path == '/login' && request.method == 'POST') {
      final body = await _readJson(request);
      final username = body?['username'];
      final password = body?['password'];
      if (username is! String || password is! String) {
        return _send(response, HttpStatus.badRequest, {
          'error': 'Send a username and a password.',
        });
      }

      final session = accounts.signIn(username, password);
      if (session == null) {
        // Deliberately one message for both halves. Saying "no such user"
        // tells somebody guessing which names are worth guessing at.
        return _send(response, HttpStatus.unauthorized, {
          'error': 'That name and password do not go together.',
        });
      }
      return _send(response, HttpStatus.ok, session.toJson());
    }

    final session = accounts.sessionFor(_bearer(request));
    if (session == null) {
      return _send(response, HttpStatus.unauthorized, {
        'error': 'Sign in again.',
      });
    }

    if (path == '/board' && request.method == 'GET') {
      return _send(response, HttpStatus.ok, {
        'jobs': [for (final job in board.jobs) job.toJson()],
        'crew': [for (final member in board.crew) member.toJson()],
      });
    }

    if (path == '/mutations' && request.method == 'POST') {
      final body = await _readJson(request);
      if (body == null) {
        return _send(response, HttpStatus.badRequest, {
          'error': 'Send a mutation.',
        });
      }

      final mutation = Mutation.fromJson(body);
      if (mutation == null) {
        // Rejected, not retried: replaying something unreadable will not make
        // it readable, and the client's outbox needs to be told to drop it.
        return _send(response, HttpStatus.badRequest, {
          'error': 'That change could not be read.',
        });
      }

      // The actor is whoever the token says, never whoever the body claims.
      // Otherwise any signed-in device could file a change as the owner.
      if (mutation.actorId != session.crewId) {
        return _send(response, HttpStatus.forbidden, {
          'error': 'That change is filed under somebody else.',
        });
      }

      final applied = await board.apply(mutation);
      return _send(response, HttpStatus.ok, {'applied': applied});
    }

    if (path == '/logout' && request.method == 'POST') {
      accounts.signOut(session.token);
      return _send(response, HttpStatus.ok, {'ok': true});
    }

    return _send(response, HttpStatus.notFound, {'error': 'No such thing.'});
  }

  static String? _bearer(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader);
    if (header == null || !header.startsWith('Bearer ')) return null;
    final token = header.substring(7).trim();
    return token.isEmpty ? null : token;
  }

  static Future<Map<String, Object?>?> _readJson(HttpRequest request) async {
    try {
      final text = await utf8.decoder.bind(request).join();
      if (text.isEmpty) return null;
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _send(
    HttpResponse response,
    int status,
    Map<String, Object?> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }
}

/// Every address a driver could type to reach this machine.
///
/// Loopback is left out on purpose: it works on the laptop itself and nowhere
/// else, which makes it exactly the address somebody would read out to the crew
/// and then spend an afternoon wondering about.
Future<List<String>> localAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses) address.address,
    ];
  } catch (_) {
    return const [];
  }
}
