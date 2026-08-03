import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'services/link_service.dart';
import 'services/location_service.dart';
import 'services/photo_service.dart';
import 'state/app_state.dart';
import 'theme/haul_theme.dart';

void main() {
  runApp(const BrothersHaulingApp());
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
