import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'primitives.dart';

/// Switches the board between dark, light, and whatever the device says.
///
/// One control, three states, because "follow my device" is a real answer and
/// has to stay reachable after someone has overridden it — a plain light/dark
/// switch is a one-way door out of that.
///
/// The label always says the state it is *in* before the state it moves to. A
/// screen reader user needs to know which one is on far more than they need to
/// know what the button does next, and an icon alone tells them neither.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  static IconData iconFor(ThemeMode mode) => switch (mode) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  static String labelFor(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Appearance follows your device. Switch to light.',
    ThemeMode.light => 'Appearance is light. Switch to dark.',
    ThemeMode.dark =>
      'Appearance is dark. Switch back to following your '
          'device.',
  };

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final mode = state.themeMode;

    return HaulIconButton(
      icon: iconFor(mode),
      tooltip: labelFor(mode),
      onPressed: state.cycleThemeMode,
    );
  }
}
