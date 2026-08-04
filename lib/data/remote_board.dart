import 'dart:convert';
import 'dart:io';

import '../models/crew_member.dart';
import '../models/job.dart';
import '../models/mutation.dart';
import 'accounts.dart';
import 'outbox.dart';
import 'sync_server.dart';

/// What a crew device has to say about the machine it syncs to.
class DispatchAddress {
  const DispatchAddress({required this.host, this.port = kHaulPort});

  final String host;
  final int port;

  Uri path(String path) => Uri.parse('http://$host:$port$path');

  /// Parses what somebody actually types: "192.168.1.14", with or without a
  /// port, with or without a scheme, with or without a stray trailing slash.
  static DispatchAddress? parse(String text) {
    var trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains('://')) trimmed = 'http://$trimmed';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return null;
    return DispatchAddress(
      host: uri.host,
      port: uri.hasPort ? uri.port : kHaulPort,
    );
  }

  @override
  String toString() => port == kHaulPort ? host : '$host:$port';

  Map<String, Object?> toJson() => {'host': host, 'port': port};

  static DispatchAddress? fromJson(Map<String, Object?> json) {
    final host = json['host'] as String?;
    if (host == null || host.isEmpty) return null;
    return DispatchAddress(
      host: host,
      port: (json['port'] as num?)?.toInt() ?? kHaulPort,
    );
  }
}

/// What came back from asking the owner's machine for the board.
class RemoteBoard {
  const RemoteBoard({required this.jobs, required this.crew});

  final List<Job> jobs;
  final List<CrewMember> crew;
}

/// The reason a sign-in did not work, in words somebody can act on.
class SignInFailure implements Exception {
  const SignInFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A crew device's end of the link to the owner's machine.
///
/// Deliberately thin. The offline story is already handled by the outbox — this
/// only has to be honest about whether a change landed, because that is what
/// the outbox keys its retries off.
class DispatchClient {
  DispatchClient({
    required this.address,
    this.session,
    HttpClient? http,
    Duration timeout = const Duration(seconds: 8),
  }) : _timeout = timeout,
       _http = http ?? (HttpClient()..connectionTimeout = timeout);

  final DispatchAddress address;
  final HttpClient _http;
  final Duration _timeout;

  /// Null until somebody signs in on this device.
  Session? session;

  void close() => _http.close(force: true);

  /// Trades a password for a token.
  ///
  /// The password is used here and never kept: from this point the device holds
  /// only the token, so a lost phone is a revoked session rather than a leaked
  /// password.
  Future<Session> signIn(String username, String password) async {
    final (status, body) = await _send(
      'POST',
      '/login',
      body: {'username': username, 'password': password},
    );

    if (status == null) {
      throw const SignInFailure(
        'Could not reach dispatch. Check you are on the yard network and that '
        'the laptop is awake.',
      );
    }
    if (status != HttpStatus.ok) {
      throw SignInFailure(
        body?['error'] as String? ?? 'That did not work. Try again.',
      );
    }

    final signed = Session.fromJson(body ?? const {});
    if (signed == null) {
      throw const SignInFailure('Dispatch sent back something unreadable.');
    }
    return session = signed;
  }

  /// The whole board as the owner's machine currently has it, or null when it
  /// could not be reached — which is not an error, just a device out of range.
  Future<RemoteBoard?> fetchBoard() async {
    final (status, body) = await _send('GET', '/board');
    if (status != HttpStatus.ok || body == null) return null;

    final jobs = body['jobs'];
    final crew = body['crew'];
    if (jobs is! List || crew is! List) return null;

    return RemoteBoard(
      jobs: [
        for (final raw in jobs.whereType<Map>())
          Job.fromJson(raw.cast<String, Object?>()),
      ],
      crew: [
        for (final raw in crew.whereType<Map>())
          CrewMember.fromJson(raw.cast<String, Object?>()),
      ],
    );
  }

  /// The [SendMutation] the outbox drives.
  ///
  /// The three outcomes are the whole contract, and getting them wrong is how
  /// work goes missing: unreachable is a retry, a refusal is a rejection, and
  /// anything else is worth another go later.
  Future<SendOutcome> send(Mutation mutation) async {
    final (status, _) = await _send(
      'POST',
      '/mutations',
      body: mutation.toJson(),
    );

    if (status == null) return SendOutcome.retry;
    if (status == HttpStatus.ok) return SendOutcome.accepted;

    // 400 and 403 will fail identically forever: an unreadable change stays
    // unreadable, and a change filed under somebody else stays that way.
    // Keeping them queued would block everything behind them.
    if (status == HttpStatus.badRequest || status == HttpStatus.forbidden) {
      return SendOutcome.rejected;
    }

    // 401 included: the token may have been revoked, or the server may have
    // restarted. Signing in again is the fix, and the change should wait for
    // it rather than be thrown away.
    return SendOutcome.retry;
  }

  /// Returns (status, body). A null status means the machine was not reachable
  /// at all, which is a different thing from it saying no.
  Future<(int?, Map<String, Object?>?)> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      final request = await _http
          .openUrl(method, address.path(path))
          .timeout(_timeout);

      final token = session?.token;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(_timeout);
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.isEmpty ? null : jsonDecode(text);
      return (
        response.statusCode,
        decoded is Map ? decoded.cast<String, Object?>() : null,
      );
    } catch (_) {
      // Out of range, laptop asleep, wrong address, DNS, a tunnel through
      // Blodgett. All the same answer to the caller: not right now.
      return (null, null);
    }
  }
}
