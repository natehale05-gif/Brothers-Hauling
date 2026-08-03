import 'dart:math' as math;
// Tristate lives in dart:ui; flutter/semantics.dart imports it without
// re-exporting it.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/theme/haul_theme.dart';

import 'helpers.dart';

/// WCAG relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color fg, Color bg) {
  final a = _luminance(fg);
  final b = _luminance(bg);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Flattens a translucent chip wash over the surface it sits on, so the
/// contrast figure is what a driver actually sees rather than what the token
/// says in isolation.
Color _over(Color top, Color bottom) {
  final a = top.a;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

void main() {
  group('colour contrast clears WCAG AA', () {
    // 4.5:1 is the AA threshold for body text. Everything in this app that
    // carries meaning as text has to clear it — a board read through a dusty
    // windscreen has no margin for a low-contrast grey.
    const pairs = <String, (Color, Color)>{
      'body text on asphalt': (HaulColors.white, HaulColors.asphalt),
      'body text on surface': (HaulColors.white, HaulColors.surface),
      'body text on raised': (HaulColors.white, HaulColors.raised),
      'secondary text on asphalt': (HaulColors.grey, HaulColors.asphalt),
      'secondary text on surface': (HaulColors.grey, HaulColors.surface),
      'secondary text on raised': (HaulColors.grey, HaulColors.raised),
      'brand accent on surface': (HaulColors.brand, HaulColors.surface),
      'brand accent on raised': (HaulColors.brand, HaulColors.raised),
      'brand accent on asphalt': (HaulColors.brand, HaulColors.asphalt),
      'stage label on surface': (HaulColors.go, HaulColors.surface),
      'hazard text on surface': (HaulColors.alert, HaulColors.surface),
      'role accent on surface': (HaulColors.violet, HaulColors.surface),
      'asphalt on the brand orange (the hero tile)': (
        HaulColors.asphalt,
        HaulColors.brand,
      ),
      'asphalt on go (the done badge)': (HaulColors.asphalt, HaulColors.go),
    };

    pairs.forEach((name, colors) {
      test(name, () {
        final ratio = _contrast(colors.$1, colors.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name is only ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });

    // Pills are tinted washes over a card, so the effective background is the
    // blend, not the token.
    const washes = <String, (Color, Color, Color)>{
      'go pill': (HaulColors.go, HaulColors.goWash, HaulColors.surface),
      'alert pill': (
        HaulColors.alert,
        HaulColors.alertWash,
        HaulColors.surface,
      ),
      'violet pill': (
        HaulColors.violet,
        HaulColors.violetWash,
        HaulColors.surface,
      ),
      'hi-vis pill': (
        HaulColors.brand,
        HaulColors.brandWash,
        HaulColors.surface,
      ),
    };

    washes.forEach((name, colors) {
      test('$name over its card', () {
        final ratio = _contrast(colors.$1, _over(colors.$2, colors.$3));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '$name is only ${ratio.toStringAsFixed(2)}:1',
        );
      });
    });
  });

  group("Flutter's own accessibility guidelines", () {
    // These four cover the mechanical half of accessibility: everything you can
    // tap is big enough to hit and says what it does, and text is legible.
    Future<void> checkAll(WidgetTester tester) async {
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    }

    testWidgets('the role gate', (tester) async {
      await pumpApp(tester);
      await checkAll(tester);
    });

    testWidgets("the driver's board", (tester) async {
      await pumpApp(tester, role: Role.employee);
      await checkAll(tester);
    });

    testWidgets("the driver's own jobs", (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      harness.state.setTab(HaulTab.mine);
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('a job card', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('the dispatch job list', (tester) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.setTab(HaulTab.jobs);
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('the crew roster', (tester) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.setTab(HaulTab.crew);
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('live tracking', (tester) async {
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.tracking);
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('the owner overview', (tester) async {
      await pumpApp(tester, role: Role.admin);
      await checkAll(tester);
    });

    testWidgets('the closed-job screen', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      for (var i = 0; i < 4; i++) {
        await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      }
      await harness.state.addPhoto(
        jobIn(harness.state, 'HL-4471'),
        before: true,
      );
      await harness.state.addPhoto(
        jobIn(harness.state, 'HL-4471'),
        before: false,
      );
      await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await checkAll(tester);
    });

    testWidgets('the tablet layout with a job card open', (tester) async {
      final harness = await pumpApp(
        tester,
        role: Role.admin,
        size: const Size(1194, 834),
      );
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await checkAll(tester);
    });
  });

  group('screen reader labels', () {
    testWidgets('icon-only controls are all named', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.manager);

      // Every icon button in the chrome carries a tooltip, which is also its
      // accessible name.
      expect(find.byTooltip('See what the crew sees'), findsOneWidget);
      expect(
        find.byTooltip('Sign out and change access level'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('money is read as a sentence, not a bare number', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      expect(find.bySemanticsLabel('Your cut, 168 dollars'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a manager hears both figures on one node', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.manager);

      expect(
        find.bySemanticsLabel(
          'Bills at 395 dollars, driver payout 168 dollars',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the stage rail announces position, not just colour', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpApp(tester, role: Role.employee);
      await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Stage 3 of 5, Loading')),
        findsWidgets,
      );
      handle.dispose();
    });

    testWidgets('the route strip states progress in words', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpApp(tester, role: Role.admin);
      harness.state.setTab(HaulTab.tracking);
      await settle(tester);

      expect(
        find.bySemanticsLabel(RegExp(r'Route from Yard to Monmouth, \d+ per')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the week chart is readable without seeing the bars', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.admin);

      expect(
        find.bySemanticsLabel(RegExp(r'Billed, last 7 days\. Monday: 520')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the location strip is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      final node = tester.getSemantics(
        find.bySemanticsLabel(RegExp('Sharing location with dispatch')),
      );
      expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('tabs report their position in the set', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.admin);

      expect(find.bySemanticsLabel('Overview tab, 1 of 4'), findsOneWidget);
      expect(find.bySemanticsLabel('Crew tab, 4 of 4'), findsOneWidget);

      final selected = tester.getSemantics(
        find.bySemanticsLabel('Overview tab, 1 of 4'),
      );
      // isSelected is a tristate: unset, true, or false.
      expect(
        selected.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue,
      );
      handle.dispose();
    });

    testWidgets('the hold control explains both ways to fire it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Hold to volunteer').first,
      );
      expect(node.hint, contains('Press and hold'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('a blocked hold control says why it is blocked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      // The label is the reason, so it isn't a dead control with no
      // explanation.
      expect(find.bySemanticsLabel('Wrong rig for this load'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('photo slots say what they are for', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpApp(tester, role: Role.employee);
      await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      await scrollTo(tester, find.text('BEFORE / AFTER PHOTOS'));

      expect(find.bySemanticsLabel('Add the before photo'), findsOneWidget);
      expect(find.bySemanticsLabel('Add the after photo'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('hazards are announced as hazards', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await pumpApp(tester, role: Role.employee);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);

      expect(
        find.bySemanticsLabel('Hazard: Exposed nails in the pile'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('section titles are semantic headers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      final node = tester.getSemantics(find.text('UP FOR GRABS'));
      expect(node.getSemanticsData().flagsCollection.isHeader, isTrue);
      handle.dispose();
    });
  });

  group('keyboard', () {
    testWidgets('Escape closes an open job card', (tester) async {
      final harness = await pumpApp(tester, role: Role.manager);
      harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      expect(harness.state.openJob, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);

      expect(harness.state.openJob, isNull);
    });

    testWidgets('Escape dismisses the closed-job screen', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);
      await harness.state.claim(jobIn(harness.state, 'HL-4471'));
      for (var i = 0; i < 4; i++) {
        await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      }
      await harness.state.addPhoto(
        jobIn(harness.state, 'HL-4471'),
        before: true,
      );
      await harness.state.addPhoto(
        jobIn(harness.state, 'HL-4471'),
        before: false,
      );
      await harness.state.advance(jobIn(harness.state, 'HL-4471'));
      await settle(tester);
      expect(find.text('LOAD CLOSED'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);

      expect(find.text('LOAD CLOSED'), findsNothing);
    });

    testWidgets('holding Enter on a focused hold control commits', (
      tester,
    ) async {
      final harness = await pumpApp(tester, role: Role.employee);
      final hold = holdButtonFor('HL-4471');
      await reveal(tester, hold);

      // Focus the control the way a keyboard user would arrive at it. The
      // GestureDetector sits inside the HoldButton's own Focus, so Focus.of
      // from there resolves to that node rather than an ancestor.
      final inner = tester.element(
        find.descendant(of: hold, matching: find.byType(GestureDetector)).first,
      );
      Focus.of(inner).requestFocus();
      await settle(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await settle(tester);

      expect(jobIn(harness.state, 'HL-4471').assignedTo, isNotNull);
    });
  });

  group('reduced motion', () {
    testWidgets('the live ping stops animating', (tester) async {
      final harness = await pumpApp(
        tester,
        role: Role.admin,
        disableAnimations: true,
      );
      harness.state.setTab(HaulTab.tracking);
      await settle(tester);

      // With the pulse stopped there is nothing left scheduled, so the tree
      // can settle — which it cannot do while the pulse is running.
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
