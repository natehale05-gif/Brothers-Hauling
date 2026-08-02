import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Directions and phone calls, handed off to whatever the platform prefers.
abstract class LinkService {
  Future<bool> openDirections(String destination);
  Future<bool> call(String phone);
}

class UrlLauncherLinkService implements LinkService {
  const UrlLauncherLinkService();

  /// Build the maps URL the running platform will actually honour.
  ///
  ///  * iOS / macOS  → Apple Maps universal link
  ///  * Android      → `geo:` intent, which fires the driver's chosen default
  ///  * everything else → Google Maps on the web
  @visibleForTesting
  static Uri directionsUri(String destination, TargetPlatform platform) {
    final q = Uri.encodeComponent(destination);
    return switch (platform) {
      TargetPlatform.iOS || TargetPlatform.macOS => Uri.parse(
        'https://maps.apple.com/?daddr=$q&dirflg=d',
      ),
      TargetPlatform.android => Uri.parse('geo:0,0?q=$q'),
      _ => Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$q'),
    };
  }

  /// Web browsers ignore `geo:` and won't hand off to a native Maps app, so the
  /// browser always gets the https URL regardless of the OS underneath it.
  static TargetPlatform get _platform =>
      kIsWeb ? TargetPlatform.fuchsia : defaultTargetPlatform;

  @override
  Future<bool> openDirections(String destination) {
    return launchUrl(
      directionsUri(destination, _platform),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Future<bool> call(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    return launchUrl(Uri.parse('tel:$digits'));
  }
}

/// Records what would have been opened. Keeps tests off the platform channels.
class RecordingLinkService implements LinkService {
  final List<String> directions = [];
  final List<String> calls = [];

  @override
  Future<bool> openDirections(String destination) async {
    directions.add(destination);
    return true;
  }

  @override
  Future<bool> call(String phone) async {
    calls.add(phone);
    return true;
  }
}
