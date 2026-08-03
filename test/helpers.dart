import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/main.dart';
import 'package:haul_board/screens/home_shell.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/link_service.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/widgets/hold_button.dart';
import 'package:haul_board/widgets/job_card.dart';

/// What a pumped app hands back so a test can drive it from either end.
class Harness {
  Harness({required this.state, required this.links, required this.photos});

  final AppState state;
  final RecordingLinkService links;
  final FakePhotoService photos;
}

Job jobIn(AppState state, String id) =>
    state.jobs.firstWhere((j) => j.id == id);

/// Pumps enough frames for transitions and dialogs to finish.
///
/// [WidgetTester.pumpAndSettle] can't be used here: the "we're hearing from
/// this driver" pulse is a deliberately endless animation, so settling never
/// completes while a live crew member is on screen.
Future<void> settle(WidgetTester tester, {int frames = 8}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Boots the app with every platform service faked out, at a chosen window
/// size and accessibility setting.
///
/// The default 420x900 is a phone; pass a wider [size] for the tablet and
/// desktop layouts.
Future<Harness> pumpApp(
  WidgetTester tester, {
  Role? role,
  Size size = const Size(420, 900),
  double textScale = 1.0,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  RecordingLinkService? links,
  FakePhotoService? photos,
  List<Job>? jobs,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final resolvedLinks = links ?? RecordingLinkService();
  final resolvedPhotos = photos ?? FakePhotoService();
  final state = AppState(
    jobs: jobs,
    location: const SimulatedLocationService(),
    photos: resolvedPhotos,
    // No background timers: a ticker or a toast still pending when the test
    // ends is a failure, and a rig that moves mid-assertion is a flake.
    autoAdvance: false,
    toastDuration: null,
    now: () => DateTime(2026, 8, 2, 9, 5),
  );
  addTearDown(state.dispose);

  if (role != null) state.enter(role);

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: BrothersHaulingApp(state: state, links: resolvedLinks),
    ),
  );
  await settle(tester);

  return Harness(state: state, links: resolvedLinks, photos: resolvedPhotos);
}

/// Scrolls a lazily-built list until [target] exists and is on screen.
///
/// The job card is a [ListView], so blocks below the fold aren't in the tree at
/// all until they scroll into range — [reveal] can't find what isn't built.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await settle(tester);
}

/// Scrolls [target] into the viewport before interacting with it.
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await settle(tester);
}

/// Presses and holds [target] long enough to commit.
///
/// The pumps are deliberately separate: the tap recognizer only reports the
/// press-down once its disambiguation deadline passes, and the fill's
/// [AnimationController] doesn't start counting until the frame after that.
/// One long pump would leave the hold barely begun.
Future<void> holdToCommit(
  WidgetTester tester,
  Finder target, {
  Duration hold = const Duration(milliseconds: 1000),
}) async {
  await reveal(tester, target);
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 150)); // press registers
  await tester.pump(const Duration(milliseconds: 16)); // fill starts counting
  await tester.pump(hold);
  await tester.pump(const Duration(milliseconds: 16));
  await gesture.up();
  await settle(tester);
}

/// Presses [target] and lets go immediately — the "I tapped instead of held"
/// case, which should ask rather than commit.
Future<void> tapAndRelease(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  final gesture = await tester.startGesture(tester.getCenter(target));
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pump(const Duration(milliseconds: 120));
  await gesture.up();
  await settle(tester);
}

/// Taps [target] after scrolling it into view.
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await reveal(tester, target);
  await tester.tap(target);
  await settle(tester);
}

/// Switches tabs through the bottom bar, the way a driver would.
Future<void> tapTab(WidgetTester tester, HaulTab tab) async {
  await tester.tap(
    find.descendant(
      of: find.byType(HaulBottomTabs),
      matching: find.text(tab.label.toUpperCase()),
    ),
  );
  await settle(tester);
}

/// The hold control on the card showing [jobId].
Finder holdButtonFor(String jobId) => find
    .descendant(
      of: find.ancestor(of: find.text(jobId), matching: find.byType(JobCard)),
      matching: find.byType(HoldButton),
    )
    .first;
