import 'package:flutter/material.dart';

import 'data/accounts.dart';
import 'data/board_repository.dart';
import 'data/intake.dart';
import 'data/server_control.dart';
import 'data/store.dart';
import 'screens/home_shell.dart';
import 'services/link_service.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';
import 'state/app_state.dart';
import 'theme/haul_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Device storage, or the best available substitute.
  //
  // A platform channel that never answers must not hold the app on a splash
  // screen forever — a driver with a shift to run needs the board far more
  // than they need yesterday's copy of it. If this falls through, the app
  // still works; it just cannot remember anything, and says so.
  Store store;
  var durable = true;
  try {
    store = await PrefsStore.open().timeout(const Duration(seconds: 5));
  } catch (error, stack) {
    debugPrint('Device storage unavailable, running in memory: $error');
    debugPrintStack(stackTrace: stack);
    store = MemoryStore();
    durable = false;
  }

  // The board is read off the device before the first frame, so a driver
  // relaunching mid-shift never sees a stale or empty board flash past.
  final board = LocalBoardRepository(store: store);
  await board.load();

  // Photos from jobs long since closed are the one thing here that grows
  // without bound. Sweeping at startup keeps a phone that has run a year of
  // shifts from filling up.
  unawaited(board.sweepOrphanedPhotos());

  // The accounts this device would serve with, read before the server exists
  // so the same book is the one the owner edits and the one that checks
  // passwords. Only hashes are on disk; nothing here can be read back into a
  // password, including by the person whose laptop it is.
  // One book, shared: the server checks passwords against exactly what the
  // owner's screen edits. Two copies is how somebody gets added, sees it
  // confirmed, and still cannot connect until the app restarts.
  final accounts = AccountBook.decode(await store.readString('accounts.v1'));

  final state = AppState(
    board: board,
    store: store,
    // Lets the owner's machine be the one the crew syncs to. Unsupported on
    // the web, which cannot listen on a port — see ServerControl.
    server: buildServerControl(board: board, accounts: accounts),
    accounts: accounts,
    // Bookings made on the website. On the hosted demo `hire.html` is served
    // from the same origin, so a booking made there lands in the storage this
    // reads — a real round trip rather than a mocked one. Pointing at a live
    // backend is a HttpIntakeSource here and nothing else in the app.
    intake: StoreIntakeSource(store: store),
    storageIsDurable: durable,
    location: const GeolocatorLocationService(),
    photos: ImagePickerPhotoService(),
  );

  // The board is already loaded above, so this is the appearance choice and
  // anything booked while the app was closed. Both are cheap reads, and both
  // want to be settled before the first frame: a board that flashes dark then
  // turns light is worse than one that waits a frame.
  await state.restore();

  runApp(BrothersHaulingApp(state: state));
}

/// Brothers Hauling — one job pipeline, three access levels.
///
/// Runs unchanged on iPhone, iPad, Android, macOS, Windows, Linux and the web.
/// Everything platform-specific sits behind a service in `lib/services/`, so
/// tests — and any platform missing a capability — swap in a stand-in rather
/// than branching the UI.
class BrothersHaulingApp extends StatefulWidget {
  const BrothersHaulingApp({
    super.key,
    this.state,
    this.links = const UrlLauncherLinkService(),
  });

  /// Injected by tests. Production builds get the real services.
  final AppState? state;
  final LinkService links;

  @override
  State<BrothersHaulingApp> createState() => _BrothersHaulingAppState();
}

class _BrothersHaulingAppState extends State<BrothersHaulingApp> {
  late final AppState _state =
      widget.state ??
      AppState(
        location: const GeolocatorLocationService(),
        photos: ImagePickerPhotoService(),
      );

  /// Only dispose what this widget created.
  late final bool _ownsState = widget.state == null;

  @override
  void dispose() {
    if (_ownsState) _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      // The MaterialApp is the scope's child, so it does not rebuild when the
      // state changes — and the theme choice lives on the state. Listening
      // here is what makes flipping to light take effect immediately.
      child: ListenableBuilder(
        listenable: _state,
        builder: (context, _) => MaterialApp(
          title: 'Brothers Hauling',
          debugShowCheckedModeBanner: false,
          // Two full palettes, not one with a switch in it. Dark is what a cab
          // at 5 AM needs; light is what a yard at noon needs, where a dark
          // screen is a mirror. Both clear WCAG AA on every pairing.
          theme: buildHaulTheme(HaulPalette.light),
          darkTheme: buildHaulTheme(HaulPalette.dark),
          themeMode: _state.themeMode,
          builder: (context, child) {
            // Honour the OS text size, but stop runaway scaling — desktop lets
            // users push it far past anything the layout can absorb.
            final scaler = MediaQuery.textScalerOf(
              context,
            ).clamp(minScaleFactor: 1.0, maxScaleFactor: 1.6);
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: child!,
            );
          },
          home: HomeShell(links: widget.links),
        ),
      ),
    );
  }
}
