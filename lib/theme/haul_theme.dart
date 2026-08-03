import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// The Brothers Hauling palette, taken from the app icon.
///
/// Three colours are sampled straight out of `assets/branding/app_icon_source.png`
/// rather than approximated — the near-black field, the neutral grey of
/// "BROTHERS", and the safety orange of "HAULING". The app and the launcher
/// icon are then provably the same brand, not two colour schemes that resemble
/// each other.
///
/// Dark by design: these screens get read in a cab in daylight and in a yard at
/// 5 AM. Every foreground/background pairing used for text clears WCAG AA
/// (4.5:1); `test/accessibility_test.dart` asserts it rather than trusting it.
abstract final class HaulColors {
  /// The icon's field colour. Neutral, not the blue-black of the prototype.
  static const asphalt = Color(0xFF111112);

  static const surface = Color(0xFF1A1A1C);
  static const raised = Color(0xFF242427);
  static const line = Color(0xFF34343A);

  /// The grey of "BROTHERS" in the icon. 6.9:1 on [surface].
  static const grey = Color(0xFFA4A3A5);

  static const white = Color(0xFFF2F2F3);

  /// The safety orange of "HAULING" in the icon, used untinted — it clears AA
  /// on every surface in the app (5.8:1 on [asphalt]), so the brand colour and
  /// the accessible colour are the same colour.
  static const brand = Color(0xFFF9570D);

  static const go = Color(0xFF2FCB74);

  /// Pushed to a clear pink-red. The prototype's alert was itself an
  /// orange-red, which is unreadable as "different" now that the brand accent
  /// is orange.
  static const alert = Color(0xFFFF4D6D);

  static const violet = Color(0xFFA99CFF);

  /// Tinted chip backgrounds. The alpha is deliberately low: the darker the
  /// blend stays, the more headroom the coloured label has on top of it.
  static const goWash = Color(0x1E2FCB74);
  static const alertWash = Color(0x1EFF4D6D);
  static const violetWash = Color(0x1EA99CFF);
  static const brandWash = Color(0x1EF9570D);
}

/// Font families registered in pubspec.yaml. Bundled, not fetched — the app has
/// to render the same on a tablet with no signal as it does on GitHub Pages.
abstract final class HaulFonts {
  static const body = 'Archivo';

  /// Headlines and numbers that need to shout.
  static const black = 'ArchivoBlack';

  /// Job IDs, phone numbers, clock times — anything that should line up.
  static const mono = 'DMMono';
}

abstract final class HaulText {
  static const display = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 34,
    height: 1.0,
    letterSpacing: -0.3,
    color: HaulColors.white,
  );

  static const heading = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 16,
    height: 1.1,
    color: HaulColors.white,
  );

  static const sectionTitle = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 15,
    height: 1.15,
    color: HaulColors.white,
  );

  static const blockTitle = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 12,
    letterSpacing: 1.4,
    color: HaulColors.grey,
  );

  static const eyebrow = TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.6,
    color: HaulColors.grey,
  );

  static const body = TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 14,
    height: 1.45,
    color: HaulColors.white,
  );

  static const bodyStrong = TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.35,
    color: HaulColors.white,
  );

  static const secondary = TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 13,
    height: 1.35,
    color: HaulColors.grey,
  );

  static const small = TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 12,
    height: 1.35,
    color: HaulColors.grey,
  );

  static const money = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 20,
    height: 1.1,
    color: HaulColors.brand,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const mono = TextStyle(
    fontFamily: HaulFonts.mono,
    fontSize: 12,
    height: 1.3,
    color: HaulColors.grey,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const action = TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 13,
    letterSpacing: 1.2,
    color: HaulColors.white,
  );

  static const pill = TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.0,
    height: 1.2,
    color: HaulColors.grey,
  );
}

abstract final class HaulSpace {
  /// Corner radius on cards and blocks.
  static const double radius = 14;
  static const double radiusSm = 10;

  /// Minimum hit target on every platform. Material wants 48, iOS wants 44 —
  /// 48 satisfies both, and gloves need it anyway.
  static const double tap = 48;

  /// Content stops widening past this so lines stay readable on a 27" monitor.
  static const double maxContentWidth = 720;

  /// Above this the app switches from bottom tabs to a rail + detail pane.
  static const double wideBreakpoint = 900;
}

ThemeData buildHaulTheme() {
  const scheme = ColorScheme.dark(
    primary: HaulColors.brand,
    onPrimary: HaulColors.asphalt,
    secondary: HaulColors.go,
    onSecondary: HaulColors.asphalt,
    error: HaulColors.alert,
    onError: HaulColors.asphalt,
    surface: HaulColors.surface,
    onSurface: HaulColors.white,
    outline: HaulColors.line,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: HaulColors.asphalt,
    fontFamily: HaulFonts.body,
    splashFactory: InkSparkle.splashFactory,
    // A single, unmissable focus ring in the accent colour — this is how the
    // whole app is navigable from a keyboard on macOS, Windows, Linux and web.
    focusColor: HaulColors.brand.withValues(alpha: 0.30),
    textTheme: const TextTheme(
      displayLarge: HaulText.display,
      titleLarge: HaulText.heading,
      titleMedium: HaulText.sectionTitle,
      bodyLarge: HaulText.body,
      bodyMedium: HaulText.secondary,
      labelLarge: HaulText.action,
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: HaulColors.raised,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(
        fontFamily: HaulFonts.body,
        fontSize: 12,
        color: HaulColors.white,
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: HaulColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    // Every platform gets the same board. Only the chrome around it changes.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
