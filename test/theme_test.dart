import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haul_board/data/board_repository.dart';
import 'package:haul_board/data/store.dart';
import 'package:haul_board/models/role.dart';
import 'package:haul_board/services/location_service.dart';
import 'package:haul_board/services/photo_service.dart';
import 'package:haul_board/state/app_state.dart';
import 'package:haul_board/theme/haul_theme.dart';
import 'package:haul_board/widgets/theme_toggle.dart';

import 'helpers.dart';

void main() {
  group('the appearance choice', () {
    test('starts by following the device rather than forcing dark', () {
      final state = AppState(
        location: const SimulatedLocationService(),
        photos: FakePhotoService(),
        autoAdvance: false,
      );
      addTearDown(state.dispose);

      // A driver who has already told their phone which way they want it has
      // said everything they intend to say about it.
      expect(state.themeMode, ThemeMode.system);
    });

    test('cycles through all three, ending back at the device', () async {
      final state = AppState(
        location: const SimulatedLocationService(),
        photos: FakePhotoService(),
        autoAdvance: false,
      );
      addTearDown(state.dispose);

      await state.cycleThemeMode();
      expect(state.themeMode, ThemeMode.light);
      await state.cycleThemeMode();
      expect(state.themeMode, ThemeMode.dark);
      await state.cycleThemeMode();
      // "Follow my device" has to be reachable again — otherwise overriding it
      // once is a one-way door.
      expect(state.themeMode, ThemeMode.system);
    });

    test('survives the app being closed', () async {
      final store = MemoryStore();

      AppState boot() {
        final state = AppState(
          board: LocalBoardRepository(store: store),
          store: store,
          location: const SimulatedLocationService(),
          photos: FakePhotoService(),
          autoAdvance: false,
        );
        addTearDown(state.dispose);
        return state;
      }

      final first = boot();
      await first.setThemeMode(ThemeMode.light);

      final second = boot();
      expect(second.themeMode, ThemeMode.system, reason: 'not read yet');
      await second.restore();
      expect(second.themeMode, ThemeMode.light);
    });

    test(
      'a phone that will not let us write still changes the screen',
      () async {
        final store = MemoryStore()..failNextWrite = true;
        final state = AppState(
          store: store,
          location: const SimulatedLocationService(),
          photos: FakePhotoService(),
          autoAdvance: false,
        );
        addTearDown(state.dispose);

        // The write is allowed to fail; the screen is not allowed to ignore you.
        await expectLater(
          state.setThemeMode(ThemeMode.light),
          throwsA(anything),
        );
        expect(state.themeMode, ThemeMode.light);
      },
    );

    test(
      'a stored value written by a newer build does not brick launch',
      () async {
        final store = MemoryStore();
        await store.writeString('theme.v1', 'solar-eclipse');
        final state = AppState(
          board: LocalBoardRepository(store: store),
          store: store,
          location: const SimulatedLocationService(),
          photos: FakePhotoService(),
          autoAdvance: false,
        );
        addTearDown(state.dispose);

        await state.restore();
        expect(state.themeMode, ThemeMode.system);
      },
    );
  });

  group('the toggle on screen', () {
    testWidgets('repaints the board when it is flipped', (tester) async {
      final harness = await pumpApp(tester, role: Role.employee);

      Color pageColour() =>
          HaulPalette.of(tester.element(find.byType(ThemeToggle).first)).bg;

      final darkPage = pageColour();
      expect(darkPage, HaulPalette.dark.bg);

      await tester.tap(find.byType(ThemeToggle).first);
      await settle(tester);

      // system -> light. If the MaterialApp were not listening to the state
      // this would still read as dark.
      expect(harness.state.themeMode, ThemeMode.system);
      expect(pageColour(), isNot(darkPage));
    });

    testWidgets('says which mode is on, not just what the button does', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, role: Role.employee);

      // Naming only the action ("switch to light") leaves a screen reader user
      // unable to find out which one they are currently in.
      expect(
        find.bySemanticsLabel(RegExp('Appearance is dark')),
        findsOneWidget,
      );

      await tester.tap(find.byType(ThemeToggle).first);
      await settle(tester);
      expect(
        find.bySemanticsLabel(RegExp('Appearance follows your device')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('is reachable before signing in', (tester) async {
      await pumpApp(tester);

      // Someone squinting at a white screen in a yard should not have to pick
      // a role first to be able to turn it down.
      expect(find.text('Pick an access level to sign in.'), findsOneWidget);
      expect(find.byType(ThemeToggle), findsOneWidget);
    });
  });

  group('both palettes reach the screen', () {
    for (final (name, mode, expected) in <(String, ThemeMode, HaulPalette)>[
      ('dark', ThemeMode.dark, HaulPalette.dark),
      ('light', ThemeMode.light, HaulPalette.light),
    ]) {
      testWidgets('$name paints its own palette', (tester) async {
        await pumpApp(tester, role: Role.employee, themeMode: mode);

        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, expected.bg);
      });
    }

    testWidgets('the app offers a light theme at all', (tester) async {
      await pumpApp(tester, role: Role.employee);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

      // Both slots are real themes. Before light mode both were the dark one.
      expect(app.theme?.brightness, Brightness.light);
      expect(app.darkTheme?.brightness, Brightness.dark);
      expect(app.theme?.extension<HaulPalette>(), HaulPalette.light);
      expect(app.darkTheme?.extension<HaulPalette>(), HaulPalette.dark);
    });
  });
}
