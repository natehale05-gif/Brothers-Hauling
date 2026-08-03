import 'package:flutter/material.dart';

import 'data/board_repository.dart';
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

  runApp(
    BrothersHaulingApp(
      state: AppState(
        board: board,
        storageIsDurable: durable,
        location: const GeolocatorLocationService(),
        photos: ImagePickerPhotoService(),
      ),
    ),
  );
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
      child: MaterialApp(
        title: 'Brothers Hauling',
        debugShowCheckedModeBanner: false,
        theme: buildHaulTheme(),
        darkTheme: buildHaulTheme(),
        // The board is dark by design — it gets read in a cab. Opting out of a
        // light theme keeps it consistent rather than half-legible under a
        // system light setting.
        themeMode: ThemeMode.dark,
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
    );
  }
}
