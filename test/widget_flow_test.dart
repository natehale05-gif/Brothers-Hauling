import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/main.dart';
import 'package:haul_board/models/job.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/screens/home_shell.dart';
import 'package:haul_board/screens/job_detail.dart';
import 'package:haul_board/services/link_service.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/theme/haul_theme.dart';

import 'helpers.dart';

void main() {
  group('role gate', () {
    testWidgets('offers all three access levels', (tester) async {
      await pumpApp(tester);

      expect(find.text('Pick an access level to sign in.'), findsOneWidget);
      for (final role in Role.values) {
        expect(find.text(role.label.toUpperCase()), findsOneWidget);
      }
    });

    testWidgets('picking a role signs in and shows the board', (tester) async {
      final harness = await pumpApp(tester);

      await tester.tap(find.text('EMPLOYEE'));
      await settle(tester);

      expect(harness.state.role, Role.employee);
      expect(find.text('UP FOR GRABS'), findsOneWidget);
      // The privacy promise is on screen, not buried in a settings page.
      expect(find.text('Sharing location with dispatch'), findsOneWidget);
    });
  });

  group('employee board', () {
    testWidgets('open jobs are listed and the wrong rig is called out', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.employee);

      expect(find.text('DEBRIS HAUL'), findsWidgets);
      // HL-4488 needs a Lowboy; Nate is not checked out on one.
      expect(find.text('Lowboy 25t — not your rig'), findsOneWidget);
    });

    testWidgets('the hold button is blocked for equipment I cannot run', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.employee);

      expect(find.text('WRONG RIG FOR THIS LOAD'), findsOneWidget);
      expect(find.text('HOLD TO VOLUNTEER'), findsWidgets);
    });

    testWidgets('holding a card volunteers me for the load', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);

      await holdToCommit(tester, holdButtonFor('HL-4471'));

      expect(jobIn(harness.state, 'HL-4471').assignedTo, isNotNull);
      expect(harness.state.tab, HaulTab.mine);
      expect(find.textContaining('HL-4471 is yours'), findsOneWidget);
      // The hold committed, so releasing must not also raise the prompt.
      expect(find.text('Take HL-4471?'), findsNothing);
    });

    testWidgets('letting go early does not claim the job', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);

      await tapAndRelease(tester, holdButtonFor('HL-4471'));

      // A tap that isn't held asks for confirmation rather than committing.
      expect(jobIn(harness.state, 'HL-4471').status, JobStatus.open);
      expect(find.text('Take HL-4471?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(jobIn(harness.state, 'HL-4471').status, JobStatus.open);
    });

    testWidgets('confirming in the dialog claims the job', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);

      await tapVisible(tester, holdButtonFor('HL-4471'));
      await tester.tap(find.text('Yes, take it'));
      await settle(tester);

      expect(jobIn(harness.state, 'HL-4471').status, JobStatus.active);
    });
  });

  group('job card', () {
    testWidgets('shows access notes, hazards and the load', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      harness.state.accept(jobIn(harness.state, 'HL-4491'));
      await settle(tester);

      await tapTab(tester, HaulTab.mine);
      await tapVisible(tester, find.text('OPEN JOB CARD').first);

      expect(find.text('ACCESS NOTES'), findsOneWidget);
      expect(find.textContaining('key in lockbox 0913'), findsOneWidget);
      expect(
        find.textContaining('Fridge must go to appliance bay'),
        findsOneWidget,
      );

      await scrollTo(tester, find.text('THE LOAD'));
      expect(
        find.text('Garage cleanout — furniture, boxes, one fridge'),
        findsOneWidget,
      );
    });

    testWidgets('an employee sees their cut, never the billed figure', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.employee);

      expect(find.text('\$168'), findsOneWidget); // HL-4471 payout
      expect(find.text('\$395'), findsNothing); // HL-4471 billed
    });

    testWidgets('a manager sees billed and payout together', (tester) async {
      await pumpApp(tester, role: Role.manager);

      expect(find.text('\$395'), findsOneWidget);
      expect(find.text('billed · pays \$168'), findsOneWidget);
    });

    testWidgets('the employee-view toggle hides money from a manager', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.manager);
      expect(find.text('\$395'), findsOneWidget);

      await tester.tap(find.byTooltip('See what the crew sees'));
      await settle(tester);

      expect(harness.state.canSeeMoney, isFalse);
      expect(find.text('\$395'), findsNothing);
      expect(find.text('\$168'), findsOneWidget);
    });
  });

  group('closing a job', () {
    testWidgets('photos gate the close, then the payoff screen shows', (
      tester,
    ) async {
      final photos = FakePhotoService();
      final harness = await pumpApp(
        tester,
        role: Role.employee,
        photos: photos,
      );

      // Take a job and drive it to the last stage.
      harness.state.claim(jobIn(harness.state, 'HL-4471'));
      for (var i = 0; i < 4; i++) {
        harness.state.advance(jobIn(harness.state, 'HL-4471'));
      }
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      expect(find.text('PHOTOS NEEDED TO CLOSE'), findsOneWidget);

      await scrollTo(tester, find.text('BEFORE / AFTER PHOTOS'));
      await tapVisible(tester, find.text('BEFORE'));
      await tapVisible(tester, find.text('AFTER'));

      expect(find.text('CLOSE IT OUT'), findsOneWidget);
      await tapVisible(tester, find.text('CLOSE IT OUT'));

      expect(find.text('LOAD CLOSED'), findsOneWidget);
      expect(find.text('+\$168'), findsOneWidget);

      await tester.tap(find.text('BACK TO THE BOARD'));
      await settle(tester);
      expect(find.text('LOAD CLOSED'), findsNothing);
    });
  });

  group('dispatch', () {
    testWidgets('admin overview totals only closed work', (tester) async {
      await pumpApp(tester, role: Role.admin);

      expect(find.text('\$470'), findsOneWidget); // billed today
      expect(find.text('\$177'), findsOneWidget); // margin
      expect(find.text('\$293'), findsOneWidget); // payout + disposal
    });

    testWidgets('tracking separates who is reporting from who is not', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.tracking);
      await settle(tester);

      expect(find.text('LIVE CREW'), findsOneWidget);
      expect(find.text('NOT TRACKING'), findsOneWidget);
      // K. Whitlow closed the app — dispatch still gets a last known ping.
      expect(find.textContaining('Hwy 20 near Philomath'), findsOneWidget);
    });

    testWidgets('a manager can push an unclaimed job to a driver', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.manager);

      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      await scrollTo(tester, find.text('MONEY & STAFFING'));
      expect(find.text('MONEY & STAFFING'), findsOneWidget);
      expect(find.text('PUSH TO A DRIVER'), findsOneWidget);

      await tapVisible(tester, find.text('D. Alvarez'));

      expect(jobIn(harness.state, 'HL-4471').assignedTo, 'c2');
      expect(find.textContaining('still have to accept'), findsOneWidget);
    });

    testWidgets('an employee never sees the money block', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4491'));
      await settle(tester);

      // Scroll the whole card — the block would be here if it existed.
      await scrollTo(tester, find.text('BEFORE / AFTER PHOTOS'));
      expect(find.text('MONEY & STAFFING'), findsNothing);
      expect(find.text('PUSH TO A DRIVER'), findsNothing);
    });
  });

  group('directions', () {
    testWidgets('routes to the site, then to disposal once loaded', (
      tester,
    ) async {
      final links = RecordingLinkService();
      final harness = await pumpApp(tester, role: Role.employee, links: links);

      harness.state.claim(jobIn(harness.state, 'HL-4471'));
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      await tapVisible(tester, find.text('DIRECTIONS'));
      expect(links.directions.single, contains('3820 NW Sunset Ridge Dr'));

      // Roll out, arrive, load up — now the rig is headed for the landfill.
      for (var i = 0; i < 3; i++) {
        harness.state.advance(jobIn(harness.state, 'HL-4471'));
      }
      await settle(tester);

      expect(find.text('TO DISPOSAL'), findsOneWidget);
      await tapVisible(tester, find.text('TO DISPOSAL'));
      expect(links.directions.last, 'Coffin Butte Landfill, Oregon');
    });

    testWidgets('calling strips the number down to diallable digits', (
      tester,
    ) async {
      final links = RecordingLinkService();
      final harness = await pumpApp(tester, role: Role.employee, links: links);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4491'));
      await settle(tester);

      await tapVisible(tester, find.text('CALL'));
      expect(links.calls.single, '541-555-0173');
    });

    test('each platform gets the maps URL it can actually honour', () {
      Uri uri(TargetPlatform p) =>
          UrlLauncherLinkService.directionsUri('Coffin Butte, OR', p);

      expect(uri(TargetPlatform.iOS).host, 'maps.apple.com');
      expect(uri(TargetPlatform.macOS).host, 'maps.apple.com');
      expect(uri(TargetPlatform.android).scheme, 'geo');
      expect(uri(TargetPlatform.windows).host, 'www.google.com');
      expect(uri(TargetPlatform.linux).host, 'www.google.com');
      // Destinations with spaces and commas survive the round trip.
      expect(
        uri(TargetPlatform.windows).queryParameters['destination'],
        'Coffin Butte, OR',
      );
    });
  });

  group('layout adapts to the window', () {
    testWidgets('a phone-width window uses bottom tabs', (tester) async {
      await pumpApp(tester, role: Role.admin, size: const Size(420, 900));

      expect(find.byType(HaulBottomTabs), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('a tablet or desktop window uses a rail', (tester) async {
      await pumpApp(tester, role: Role.admin, size: const Size(1280, 900));

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(HaulBottomTabs), findsNothing);
    });

    testWidgets('wide windows keep the list beside the job card', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        role: Role.manager,
        size: const Size(1280, 900),
      );

      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      // Both panes are on screen at once — no back button needed.
      expect(find.byType(JobDetail), findsOneWidget);
      expect(find.text('RUNNING NOW'), findsOneWidget);
      expect(find.byTooltip('Back to the list'), findsNothing);
      expect(find.byTooltip('Close job card'), findsOneWidget);
    });

    testWidgets('narrow windows swap the list out for the job card', (
      tester,
    ) async {
      final harness = await pumpApp(
        tester,
        role: Role.manager,
        size: const Size(420, 900),
      );

      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      expect(find.byType(JobDetail), findsOneWidget);
      expect(find.text('RUNNING NOW'), findsNothing);
      expect(find.byTooltip('Back to the list'), findsOneWidget);
    });
  });

  group('platform chrome', () {
    for (final platform in TargetPlatform.values) {
      testWidgets('builds on $platform without overflowing', (tester) async {
        // Reset inside the body: the framework checks for leaked debug flags
        // before tear-downs run.
        debugDefaultTargetPlatformOverride = platform;
        try {
          await pumpApp(tester, role: Role.admin);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  });

  group('text scaling', () {
    testWidgets('the board still lays out at the largest supported size', (
      tester,
    ) async {
      await pumpApp(
        tester,
        role: Role.employee,
        textScale: 2.0, // clamped to 1.6 by the app
      );

      expect(tester.takeException(), isNull);
      expect(find.text('UP FOR GRABS'), findsOneWidget);
    });

    testWidgets('the job card holds together at large text', (tester) async {
      final harness = await pumpApp(
        tester,
        role: Role.employee,
        textScale: 2.0,
      );
      harness.state.openJobCard(jobIn(harness.state, 'HL-4491'));
      await settle(tester);

      await scrollTo(tester, find.text('THE LOAD'));
      expect(tester.takeException(), isNull);
      expect(find.text('THE LOAD'), findsOneWidget);
    });
  });

  group('reduced motion', () {
    testWidgets('the hold control switches to a confirm prompt', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.employee, disableAnimations: true);

      // No sustained gesture required — one tap asks, and asking is enough.
      await tapVisible(tester, holdButtonFor('HL-4471'));

      expect(find.text('Take HL-4471?'), findsOneWidget);
    });
  });

  group('location', () {
    testWidgets('falls back to a simulated fix rather than failing', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.employee);

      expect(
        find.textContaining('showing a simulated position'),
        findsOneWidget,
      );
      expect(
        find.text('Stops when you close the app'.toUpperCase()),
        findsOneWidget,
      );
    });

    testWidgets('dispatch views do not show the driver location strip', (
      tester,
    ) async {
      await pumpApp(tester, role: Role.admin);
      expect(find.text('Sharing location with dispatch'), findsNothing);
    });
  });

  testWidgets('the app boots from main() with real services wired up', (
    tester,
  ) async {
    // Guards the production wiring — the default services must at least
    // construct and render the gate without touching a platform channel.
    await tester.pumpWidget(BrothersHaulingApp(links: RecordingLinkService()));
    await tester.pump();

    expect(find.text('Pick an access level to sign in.'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('the theme keeps its identity across both slots', () {
    final theme = buildHaulTheme();
    expect(theme.scaffoldBackgroundColor, HaulColors.asphalt);
    expect(theme.colorScheme.primary, HaulColors.brand);
    expect(theme.textTheme.bodyLarge?.fontFamily, HaulFonts.body);
  });

  test('the simulated location service reports the yard', () async {
    final fixes = await const SimulatedLocationService().watch().toList();
    expect(fixes.first.state, GpsState.asking);
    expect(fixes.last.state, GpsState.simulated);
    expect(fixes.last.latitude, kYardLat);
  });
}
