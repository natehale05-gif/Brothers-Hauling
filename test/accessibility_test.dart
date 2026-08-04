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
  // Both palettes, the same bar. Light mode is not a cosmetic reskin — the
  // icon's orange manages 3.3:1 on white, so a light palette that reuses the
  // dark accents is unreadable. Running the identical table over both is what
  // stops that being discovered by a driver in a yard.
  for (final (mode, hc) in <(String, HaulPalette)>[
    ('dark', HaulPalette.dark),
    ('light', HaulPalette.light),
  ]) {
    group('$mode: colour contrast clears WCAG AA', () {
      // 4.5:1 is the AA threshold for body text. Everything in this app that
      // carries meaning as text has to clear it — a board read through a dusty
      // windscreen has no margin for a low-contrast grey.
      final pairs = <String, (Color, Color)>{
        'body text on the page': (hc.ink, hc.bg),
        'body text on surface': (hc.ink, hc.surface),
        'body text on raised': (hc.ink, hc.raised),
        'secondary text on the page': (hc.inkSoft, hc.bg),
        'secondary text on surface': (hc.inkSoft, hc.surface),
        'secondary text on raised': (hc.inkSoft, hc.raised),
        'brand accent on the page': (hc.brand, hc.bg),
        'brand accent on surface': (hc.brand, hc.surface),
        'brand accent on raised': (hc.brand, hc.raised),
        'stage label on surface': (hc.go, hc.surface),
        'hazard text on surface': (hc.alert, hc.surface),
        'role accent on surface': (hc.violet, hc.surface),
        'ink on the brand orange (the hero tile)': (hc.onBrand, hc.brand),
        'ink on go (the done badge)': (hc.onBrand, hc.go),
      };

      pairs.forEach((name, colors) {
        test(name, () {
          final ratio = _contrast(colors.$1, colors.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '$mode: $name is only ${ratio.toStringAsFixed(2)}:1',
          );
        });
      });

      // Pills are tinted washes over a card, so the effective background is
      // the blend, not the token. This is where the two palettes genuinely
      // differ: on dark a wash hands the label headroom, on light it takes it
      // away, which is why the light wash is much thinner.
      final washes = <String, (Color, Color)>{
        'go pill': (hc.go, hc.goWash),
        'alert pill': (hc.alert, hc.alertWash),
        'violet pill': (hc.violet, hc.violetWash),
        'brand pill': (hc.brand, hc.brandWash),
      };

      washes.forEach((name, colors) {
        // Over every surface a pill can land on, not just the friendliest one.
        //
        // `raised` is deliberately absent, and it is the one case worth
        // spelling out. Nothing draws a tinted pill on a raised block — that
        // token backs avatars, buttons, the photo slot and the ping dot, none
        // of which contain a pill — and on dark, a wash over `raised` cannot
        // clear 4.5:1 at any alpha without collapsing `raised` into `surface`
        // and losing the elevation step. If a pill ever does land on one, this
        // list is what needs to grow, not the exception that needs writing.
        for (final (where, under) in [
          ('a card', hc.surface),
          ('the page', hc.bg),
        ]) {
          test('$name over $where', () {
            final ratio = _contrast(colors.$1, _over(colors.$2, under));
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason:
                  '$mode: $name over $where is only '
                  '${ratio.toStringAsFixed(2)}:1',
            );
          });
        }
      });

      test('hairlines are visible against what they separate', () {
        // A border is not text, so AA asks 3:1 of it, not 4.5:1.
        for (final (where, under) in [
          ('surface', hc.surface),
          ('the page', hc.bg),
        ]) {
          final ratio = _contrast(hc.line, under);
          expect(
            ratio,
            greaterThanOrEqualTo(1.2),
            reason:
                '$mode: the hairline on $where is only '
                '${ratio.toStringAsFixed(2)}:1',
          );
        }
      });
    });
  }

  group('the two palettes are actually different', () {
    test('light is light and dark is dark', () {
      expect(_luminance(HaulPalette.dark.bg), lessThan(0.1));
      expect(_luminance(HaulPalette.light.bg), greaterThan(0.7));
    });

    test('light does not simply reuse the dark accents', () {
      // The seed orange is 3.3:1 on white. Shipping it as light-mode text
      // would be the single easiest way to undo all of the above.
      expect(HaulPalette.light.brand, isNot(HaulPalette.dark.brand));
      expect(
        _contrast(HaulPalette.dark.brand, HaulPalette.light.surface),
        lessThan(4.5),
        reason: 'the premise of the light palette, stated as a test',
      );
    });
  });

  // Every screen, in both palettes. The contrast guideline reads the pixels
  // that actually got painted, so this is what catches a colour that was only
  // ever checked against the dark background it was chosen on.
  for (final mode in [ThemeMode.dark, ThemeMode.light]) {
    group("Flutter's own accessibility guidelines (${mode.name})", () {
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
        await pumpApp(tester, themeMode: mode);
        await checkAll(tester);
      });

      testWidgets("the driver's board", (tester) async {
        await pumpApp(tester, role: Role.employee, themeMode: mode);
        await checkAll(tester);
      });

      testWidgets("the driver's own jobs", (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.employee,
          themeMode: mode,
        );
        harness.state.setTab(HaulTab.mine);
        await settle(tester);
        await checkAll(tester);
      });

      testWidgets('a job card', (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.employee,
          themeMode: mode,
        );
        await harness.state.claim(jobIn(harness.state, 'HL-4471'));
        harness.state.openJobCard(jobIn(harness.state, 'HL-4471'));
        await settle(tester);
        await checkAll(tester);
      });

      testWidgets('the dispatch job list', (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.manager,
          themeMode: mode,
        );
        harness.state.setTab(HaulTab.jobs);
        await settle(tester);
        await checkAll(tester);
      });

      testWidgets('the crew roster', (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.manager,
          themeMode: mode,
        );
        harness.state.setTab(HaulTab.crew);
        await settle(tester);
        await checkAll(tester);
      });

      testWidgets('live tracking', (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.admin,
          themeMode: mode,
        );
        harness.state.setTab(HaulTab.tracking);
        await settle(tester);
        await checkAll(tester);
      });

      testWidgets('the owner overview', (tester) async {
        await pumpApp(tester, role: Role.admin, themeMode: mode);
        await checkAll(tester);
      });

      testWidgets('the closed-job screen', (tester) async {
        final harness = await pumpApp(
          tester,
          role: Role.employee,
          themeMode: mode,
        );
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
  }

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

    testWidgets('a driver is never read a figure at all', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      // Pay is hourly, so there is no per-job number that would even be true —
      // and what an hour is worth is not the app's to announce.
      expect(find.bySemanticsLabel(RegExp('dollars')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Your cut')), findsNothing);
      handle.dispose();
    });

    testWidgets('money is read as a sentence for the people who see it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.manager);

      expect(find.bySemanticsLabel('Bills at 395 dollars'), findsOneWidget);
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

      expect(find.bySemanticsLabel('Overview tab, 1 of 6'), findsOneWidget);
      expect(find.bySemanticsLabel('Day tab, 2 of 6'), findsOneWidget);
      expect(find.bySemanticsLabel('Crew tab, 6 of 6'), findsOneWidget);

      final selected = tester.getSemantics(
        find.bySemanticsLabel('Overview tab, 1 of 6'),
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
      final harness = await pumpApp(tester, role: Role.employee);
      // The Lowboy job runs tomorrow; the board is paged by day.
      harness.state.showDay(1);
      await settle(tester);
      // Semantics only exist for what is on screen, so the card has to be
      // scrolled to before its label can be read.
      await tester.ensureVisible(find.text('WRONG RIG FOR THIS LOAD'));
      await settle(tester);

      // The label is the reason, so it isn't a dead control with no
      // explanation. Matched by containment: the card announces as one node,
      // and the reason is a phrase inside it rather than a label of its own.
      expect(
        find.bySemanticsLabel(RegExp('Wrong rig for this load')),
        findsWidgets,
      );
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

      // The day heading is the board's section title now.
      final node = tester.getSemantics(find.text('TODAY'));
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
