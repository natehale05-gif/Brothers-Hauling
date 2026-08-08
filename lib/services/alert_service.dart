import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/job.dart';

/// A reminder waiting to fire.
@immutable
class Alert {
  const Alert({
    required this.jobId,
    required this.at,
    required this.title,
    required this.body,
  });

  final String jobId;
  final DateTime at;
  final String title;
  final String body;

  /// A stable integer per job, because the platforms key notifications by int.
  ///
  /// A hash rather than a counter so the same job cancels and re-schedules to
  /// the same slot across a relaunch — a counter would leave the old reminder
  /// behind every time the app restarted.
  int get id => jobId.hashCode & 0x7fffffff;

  @override
  bool operator ==(Object other) =>
      other is Alert &&
      other.jobId == jobId &&
      other.at == at &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(jobId, at, title, body);

  @override
  String toString() => 'Alert($jobId at $at)';
}

/// What a job's reminder says when it arrives.
///
/// Written here rather than in the UI because a notification is read on a lock
/// screen with no app around it: it has to carry the customer, the time and
/// where to go without anything else on screen to explain it.
Alert? alertFor(Job job) {
  final at = job.alertAt;
  if (at == null) return null;

  final starts = job.scheduledFor!;
  final allDay = starts.hour == 0 && starts.minute == 0;
  final when = allDay ? 'today' : 'at ${formatClock(starts)}';
  final where = job.city.isEmpty ? job.address : job.city;

  return Alert(
    jobId: job.id,
    at: at,
    title: '${job.type} for ${job.customer}',
    body: where.isEmpty ? '${job.id}, $when' : '$where, $when',
  );
}

/// Every reminder a board is owed, ignoring any already in the past.
///
/// [now] is passed in rather than read so a test drives the clock. Work that
/// is finished, or whose reminder has already gone by, is left out: a phone
/// buzzing about a job closed yesterday is how somebody turns alerts off.
List<Alert> alertsFor(Iterable<Job> jobs, DateTime now) {
  final out = <Alert>[];
  for (final job in jobs) {
    if (job.status == JobStatus.done) continue;
    final alert = alertFor(job);
    if (alert == null || !alert.at.isAfter(now)) continue;
    out.add(alert);
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Reminders on the device, behind an interface so the app never branches on
/// which platform it is running on.
abstract class AlertService {
  /// Asks for permission if the platform needs it. False when refused, which
  /// is a thing the app says out loud rather than silently dropping alerts.
  Future<bool> ensureAllowed();

  /// Replaces everything scheduled with exactly [alerts].
  ///
  /// Replace rather than add: the board is the truth, and reconciling against
  /// whatever the OS is holding is the only way a job that moved, or was
  /// deleted, stops buzzing at its old time.
  Future<void> sync(List<Alert> alerts);

  /// What is currently scheduled, for the settings screen and for tests.
  List<Alert> get scheduled;

  /// True when the device hands the reminder to the operating system, so it
  /// arrives whether or not the app is running. False on a browser, which can
  /// only raise one while the page is open — worth saying out loud rather than
  /// letting somebody close a tab expecting to be told about a nine o'clock.
  bool get firesWhenClosed => true;

  /// Stops anything this service is holding. A no-op for most of them.
  void dispose() {}
}

/// Does nothing, and says so.
///
/// Used in tests and anywhere the real one cannot start — the app keeps every
/// alert on the job either way, so turning this on later loses nothing.
class SilentAlertService extends AlertService {
  final List<Alert> _scheduled = [];

  @override
  List<Alert> get scheduled => List.unmodifiable(_scheduled);

  @override
  Future<bool> ensureAllowed() async => false;

  @override
  Future<void> sync(List<Alert> alerts) async {
    _scheduled
      ..clear()
      ..addAll(alerts);
  }
}

/// Loads the zone database and points `tz.local` at this device's zone.
///
/// Both halves matter. Without the database nothing can be scheduled at all;
/// without the second line `tz.local` is a late field nobody ever set, and the
/// first reminder to be scheduled throws rather than firing — which is exactly
/// how alerts came to be silently unavailable the first time this was wired
/// up. The zone is matched on the offset the device is actually running at,
/// which avoids a second plugin whose only job would be to name it.
void _useDeviceZone([DateTime? at]) {
  tzdata.initializeTimeZones();

  final now = at ?? DateTime.now();
  final offset = now.timeZoneOffset;
  for (final location in tz.timeZoneDatabase.locations.values) {
    if (tz.TZDateTime.from(now, location).timeZoneOffset == offset) {
      tz.setLocalLocation(location);
      return;
    }
  }
  // Nothing matched, which should not happen — but a reminder an hour out is
  // better than an exception where a reminder was meant to be.
  tz.setLocalLocation(tz.UTC);
}

/// The real thing, on every platform the plugin supports.
class LocalAlertService extends AlertService {
  LocalAlertService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final List<Alert> _scheduled = [];

  bool _started = false;
  bool _allowed = false;

  /// Set once the platform has told us it cannot schedule ahead.
  bool _scheduleAhead = true;
  Timer? _next;

  @override
  bool get firesWhenClosed => _scheduleAhead;

  @override
  void dispose() {
    _next?.cancel();
    _next = null;
  }

  @override
  List<Alert> get scheduled => List.unmodifiable(_scheduled);

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'jobs',
      'Job reminders',
      channelDescription: 'A heads-up before a job starts.',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
    web: WebNotificationDetails(),
  );

  Future<void> _start() async {
    if (_started) return;
    _started = true;

    _useDeviceZone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'Brothers Hauling',
          appUserModelId: 'BrothersHauling.HaulBoard',
          // Stable and arbitrary: Windows keys a toast's history off this, so
          // it has to be the same string on every launch.
          guid: 'b7f1c0e2-4a6d-4f3b-9b21-2f0d5a7c8e14',
        ),
        web: WebInitializationSettings(),
      ),
    );
  }

  @override
  Future<bool> ensureAllowed() async {
    try {
      await _start();
      // Each platform asks in its own way, and several do not ask at all.
      // Any of them coming back true is enough; none of them existing means
      // the platform does not gate it, which is also fine.
      final android = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      final ios = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      final macos = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      final web = kIsWeb
          ? await _plugin
                .resolvePlatformSpecificImplementation<
                  WebFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission()
          : null;

      _allowed = web ?? android ?? ios ?? macos ?? true;
      return _allowed;
    } catch (error, stack) {
      // A platform channel that is not there must not take the app down with
      // it. Alerts are a convenience; the board is the job.
      debugPrint('Alerts unavailable: $error');
      debugPrintStack(stackTrace: stack);
      _allowed = false;
      return false;
    }
  }

  @override
  Future<void> sync(List<Alert> alerts) async {
    // Nothing to do, and nothing was ever scheduled — do not wake the plugin
    // just to tell it so.
    if (alerts.isEmpty && _scheduled.isEmpty) return;
    if (!_allowed && !await ensureAllowed()) return;

    _scheduled
      ..clear()
      ..addAll(alerts);

    if (_scheduleAhead) {
      try {
        await _plugin.cancelAll();
        for (final alert in alerts) {
          await _plugin.zonedSchedule(
            id: alert.id,
            title: alert.title,
            body: alert.body,
            scheduledDate: tz.TZDateTime.from(alert.at, tz.local),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        }
        return;
      } on UnsupportedError {
        // A browser cannot hand a future notification to anything that
        // outlives the page. Fall through to raising them from here instead,
        // and stop trying — the answer will not change.
        _scheduleAhead = false;
      } catch (error, stack) {
        debugPrint('Could not schedule alerts: $error');
        debugPrintStack(stackTrace: stack);
        return;
      }
    }

    _armNext();
  }

  /// Waits for the soonest reminder and raises it from inside the app.
  ///
  /// One timer rather than one per alert: only the next one matters, and a
  /// board with a hundred jobs on it should not be holding a hundred timers.
  void _armNext() {
    _next?.cancel();
    _next = null;
    if (_scheduled.isEmpty) return;

    final soonest = _scheduled.first;
    final wait = soonest.at.difference(DateTime.now());
    _next = Timer(wait.isNegative ? Duration.zero : wait, () async {
      _scheduled.remove(soonest);
      try {
        await _plugin.show(
          id: soonest.id,
          title: soonest.title,
          body: soonest.body,
          notificationDetails: _details,
        );
      } catch (error) {
        debugPrint('Could not raise a reminder: $error');
      }
      _armNext();
    });
  }
}
