import 'accounts.dart';
import 'board_repository.dart';

export 'server_control_stub.dart'
    if (dart.library.io) 'server_control_io.dart'
    show buildServerControl;

/// Turning this device into the one the crew syncs to.
///
/// An interface rather than the server itself because the app also builds for
/// the web, where there is no such thing as listening on a port. The web build
/// gets [UnsupportedServerControl] and says so out loud, rather than shipping
/// a button that cannot work.
abstract class ServerControl {
  /// Whether this platform can serve at all.
  bool get supported;

  bool get running;

  /// Addresses a driver could type in. Empty until [start] has run.
  List<String> get addresses;

  int get port;

  Future<void> start();
  Future<void> stop();
}

/// The web build's answer: no.
class UnsupportedServerControl implements ServerControl {
  const UnsupportedServerControl();

  @override
  bool get supported => false;

  @override
  bool get running => false;

  @override
  List<String> get addresses => const [];

  @override
  int get port => 0;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

/// Signature both implementations provide.
typedef ServerControlBuilder =
    ServerControl Function({
      required BoardRepository board,
      required AccountBook accounts,
      int port,
    });
