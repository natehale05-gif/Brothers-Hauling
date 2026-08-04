import 'accounts.dart';
import 'board_repository.dart';
import 'server_control.dart';

/// The web build cannot listen on a port, so the button is never offered.
ServerControl buildServerControl({
  required BoardRepository board,
  required AccountBook accounts,
  int port = 0,
}) => const UnsupportedServerControl();
