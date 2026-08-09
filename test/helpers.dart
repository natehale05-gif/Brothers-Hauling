import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/calendar/calendar_state.dart';
import 'package:haul_board/calendar/event_editor.dart';
import 'package:haul_board/data/intake.dart';
import 'package:haul_board/main.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/link_service.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/alert_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';

/// What a pumped app hands back so a test can drive it from either end.
class Harness {
  Harness({
    required this.state,
    required this.calendar,
    required this.links,
    required this.photos,
  });

  final AppState state;
  final CalendarState calendar;
  final RecordingLinkService links;
  final FakePhotoService photos;
}

Job jobIn(AppState state, String id) =>
    state.jobs.firstWhere((j) => j.id == id);

/// A fixed "now", so "today" means the same thing on every run.
///
/// A calendar is the one kind of app where a test that reads the wall clock is
/// guaranteed to fail on some particular Tuesday.
final DateTime kTestNow = DateTime(2026, 8, 6, 9, 30);

/// Pumps enough frames for transitions and sheets to finish.
///
/// [WidgetTester.pumpAndSettle] cannot be used while anything is animating
/// forever — and it also never settles against the calendar's own minute
/// ticker unless that is switched off.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Chooses a rig in the open job editor.
///
/// The form will not save without one, so every test that books through it has
/// to do this — which is the point of the rule. Taps the chip when the board
/// already knows the rig, and types it in when it does not.
Future<void> pickRig(
  WidgetTester tester, [
  String rig = 'Dump trailer 14k',
]) async {
  final chip = find.bySemanticsLabel(rig);
  if (chip.evaluate().isNotEmpty) {
    await tester.ensureVisible(chip.first);
    await settle(tester);
    await tester.tap(chip.first);
  } else {
    await tester.ensureVisible(find.byKey(kRigField));
    await settle(tester);
    await tester.enterText(find.byKey(kRigField), rig);
    await tester.tap(find.bySemanticsLabel('Add this rig'));
  }
  await settle(tester);
}

/// Boots the calendar with every platform service faked out.
///
/// The clock is pinned and the minute ticker switched off, so a test drives
/// time rather than waiting on it.
Future<Harness> pumpApp(
  WidgetTester tester, {

  /// Who is looking. Defaults to an owner, because the calendar is behind a
  /// sign-in now and a test that pumped nobody would only ever see the login
  /// box. Pass a role to check what somebody else is shown.
  Role role = Role.admin,
  Size size = const Size(420, 900),
  double textScale = 1.0,
  CalView view = CalView.month,
  DateTime? now,
  RecordingLinkService? links,
  FakePhotoService? photos,
  List<Job>? jobs,
  ThemeMode themeMode = ThemeMode.light,
  IntakeSource? intake,
  AlertService? alerts,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final clock = now ?? kTestNow;
  final recordedLinks = links ?? RecordingLinkService();
  final fakePhotos = photos ?? FakePhotoService();

  final state = AppState(
    jobs: jobs,
    location: const SimulatedLocationService(),
    photos: fakePhotos,
    autoAdvance: false,
    toastDuration: null,
    intake: intake,
    alerts: alerts,
    now: () => clock,
  );
  addTearDown(state.dispose);
  state.setThemeMode(themeMode);
  state.enter(role);

  final calendar = CalendarState(
    now: () => clock,
    view: view,
    // No ticker: a periodic timer never lets the tester settle.
    tick: Duration.zero,
  );
  addTearDown(calendar.dispose);

  await tester.pumpWidget(
    MediaQuery(
      // Built from the view rather than from nothing. A bare MediaQueryData
      // reports a zero-sized screen, and MaterialApp honours the one it finds
      // above it — which silently collapses anything sized against the window,
      // the job sheet included.
      data: MediaQueryData.fromView(
        tester.view,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: BrothersHaulingApp(
        // A fresh key every pump. Without one, pumping the app a second time
        // in the same test reuses the first State — which holds its own
        // AppState — and the state this call just built is silently ignored.
        key: UniqueKey(),
        state: state,
        calendar: calendar,
        links: recordedLinks,
      ),
    ),
  );
  await settle(tester);

  return Harness(
    state: state,
    calendar: calendar,
    links: recordedLinks,
    photos: fakePhotos,
  );
}
