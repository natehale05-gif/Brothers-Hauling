import 'accounts.dart';
import 'board_repository.dart';
import 'server_control.dart';
import 'sync_server.dart';

ServerControl buildServerControl({
  required BoardRepository board,
  required AccountBook accounts,
  int port = kHaulPort,
}) => _IoServerControl(
  server: HaulServer(board: board, accounts: accounts, port: port),
);

class _IoServerControl implements ServerControl {
  _IoServerControl({required this.server});

  final HaulServer server;
  List<String> _addresses = const [];

  @override
  bool get supported => true;

  @override
  bool get running => server.running;

  @override
  List<String> get addresses => _addresses;

  @override
  int get port => server.boundPort ?? server.port;

  @override
  Future<void> start() async {
    await server.start();
    // Read after binding: an interface that came up with the Wi-Fi is not
    // there when the app launches on a machine still joining the network.
    _addresses = await localAddresses();
  }

  @override
  Future<void> stop() async {
    await server.stop();
    _addresses = const [];
  }
}
