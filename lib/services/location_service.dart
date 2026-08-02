import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GpsState {
  /// Waiting on the first fix or on the permission prompt.
  asking,

  /// Real positions coming in.
  live,

  /// Permission denied, no hardware, no answer, or a platform without a
  /// location provider. The app keeps working against a fixed yard position.
  simulated,

  /// Sharing is stopped.
  off,
}

@immutable
class GpsFix {
  const GpsFix({required this.state, this.latitude, this.longitude, this.at});

  final GpsState state;
  final double? latitude;
  final double? longitude;
  final DateTime? at;

  bool get hasCoords => latitude != null && longitude != null;
}

/// The yard in Corvallis. Stands in whenever a real fix isn't available, so the
/// board still shows a position rather than an indefinite spinner.
const double kYardLat = 44.5646;
const double kYardLng = -123.262;

/// How long to wait on a permission prompt or a first fix before falling back.
/// Nobody watches a "getting a fix…" line for longer than this and believes it.
const Duration kFixTimeout = Duration(seconds: 12);

/// Contract the UI codes against, so tests can supply positions directly
/// instead of waiting on platform GPS.
abstract class LocationService {
  /// Emits while, and only while, the caller keeps listening. Cancelling the
  /// subscription stops the platform listener — that is the whole privacy
  /// promise the app makes to drivers: closing the app stops the reporting.
  Stream<GpsFix> watch();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService({this.fixTimeout = kFixTimeout});

  final Duration fixTimeout;

  static GpsFix _simulated() => GpsFix(
    state: GpsState.simulated,
    latitude: kYardLat,
    longitude: kYardLng,
    at: DateTime.now(),
  );

  @override
  Stream<GpsFix> watch() {
    // A StreamController rather than an async* body so the fallback timer and
    // the position stream can both feed the same sink.
    late final StreamController<GpsFix> controller;
    StreamSubscription<Position>? sub;
    Timer? fallback;
    var gotFix = false;

    void fallBackToSimulated() {
      if (gotFix || controller.isClosed) return;
      controller.add(_simulated());
    }

    Future<void> start() async {
      // Everything here can fail: no permission, no hardware, an insecure
      // origin in a browser, a Linux box with no location provider, a
      // permission prompt nobody ever answers. Every one of them lands on the
      // simulated position instead of a dead screen.
      try {
        if (!await Geolocator.isLocationServiceEnabled()) {
          fallBackToSimulated();
          return;
        }

        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          fallBackToSimulated();
          return;
        }

        if (controller.isClosed) return;

        sub =
            Geolocator.getPositionStream(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
              ),
            ).listen(
              (p) {
                gotFix = true;
                fallback?.cancel();
                if (controller.isClosed) return;
                controller.add(
                  GpsFix(
                    state: GpsState.live,
                    latitude: p.latitude,
                    longitude: p.longitude,
                    at: DateTime.now(),
                  ),
                );
              },
              onError: (_) => fallBackToSimulated(),
              cancelOnError: false,
            );
      } catch (_) {
        fallBackToSimulated();
      }
    }

    controller = StreamController<GpsFix>(
      onListen: () {
        controller.add(const GpsFix(state: GpsState.asking));
        // Show *something* even if the prompt is never answered. A real fix
        // arriving later still replaces it.
        fallback = Timer(fixTimeout, fallBackToSimulated);
        start();
      },
      onCancel: () async {
        fallback?.cancel();
        await sub?.cancel();
      },
    );

    return controller.stream;
  }
}

/// Fixed position, no platform calls. Used by tests and by any build that wants
/// the board without asking a driver for permission.
class SimulatedLocationService implements LocationService {
  const SimulatedLocationService();

  @override
  Stream<GpsFix> watch() async* {
    yield const GpsFix(state: GpsState.asking);
    yield GeolocatorLocationService._simulated();
  }
}
