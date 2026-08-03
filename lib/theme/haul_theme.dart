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
/// There are two of these. Dark is the default: these screens get read in a cab
/// at 5 AM, and a white screen at that hour is a flashbang. Light exists because
/// the same screens get read at noon in a yard with the sun behind them, where a
/// dark screen turns into a mirror.
///
/// Every foreground/background pairing used for text clears WCAG AA (4.5:1) in
/// **both** palettes; `test/accessibility_test.dart` asserts it for each rather
/// than trusting it.
@immutable
class HaulPalette extends ThemeExtension<HaulPalette> {
  const HaulPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.raised,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.brand,
    required this.onBrand,
    required this.go,
    required this.alert,
    required this.violet,
    required this.washAlpha,
  });

  final Brightness brightness;

  /// The page behind everything.
  final Color bg;

  /// Cards, the top bar, the tab bar — one step up from [bg].
  final Color surface;

  /// Chips and inset blocks sitting on a [surface].
  final Color raised;

  /// Hairlines. Not a text colour, so it is held to 3:1, not 4.5:1.
  final Color line;

  /// Primary text.
  final Color ink;

  /// Secondary text — still a text colour, so still held to 4.5:1.
  final Color inkSoft;

  /// The safety orange of "HAULING" in the icon.
  final Color brand;

  /// What reads on top of a [brand] fill.
  final Color onBrand;

  final Color go;
  final Color alert;
  final Color violet;

  /// How strongly a tinted chip stains the surface under it.
  ///
  /// Not the same in both palettes, and that asymmetry is the whole reason it
  /// is a field rather than a constant. On dark, a tint *darkens* the chip and
  /// hands the coloured label more headroom, so it can be laid on fairly
  /// thickly. On light the tint darkens the chip too — but there the label is
  /// also dark, so every extra point of alpha eats the contrast instead of
  /// feeding it. The light wash is therefore much thinner.
  final int washAlpha;

  Color get brandWash => brand.withAlpha(washAlpha);
  Color get goWash => go.withAlpha(washAlpha);
  Color get alertWash => alert.withAlpha(washAlpha);
  Color get violetWash => violet.withAlpha(washAlpha);

  bool get isDark => brightness == Brightness.dark;

  /// The palette in force. An inherited lookup, not a rebuild.
  static HaulPalette of(BuildContext context) =>
      Theme.of(context).extension<HaulPalette>() ?? dark;

  /// The default. Neutral black, because the icon's field is neutral — the
  /// prototype's blue-black is gone.
  static const dark = HaulPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF111112),
    surface: Color(0xFF1A1A1C),
    raised: Color(0xFF242427),
    line: Color(0xFF34343A),
    ink: Color(0xFFF2F2F3),
    inkSoft: Color(0xFFA4A3A5),
    // Untinted: it happens to clear AA on every dark surface (5.8:1 on bg), so
    // the brand colour and the accessible colour are the same colour.
    brand: Color(0xFFF9570D),
    onBrand: Color(0xFF111112),
    go: Color(0xFF2FCB74),
    // A clear pink-red. The prototype's alert was itself an orange-red, which
    // stops reading as "different" once the accent is orange.
    alert: Color(0xFFFF4D6D),
    violet: Color(0xFFA99CFF),
    washAlpha: 0x1E,
  );

  /// The daylight palette.
  ///
  /// The accents are deliberately *not* the dark palette's accents dropped onto
  /// a white card. The icon's orange manages 3.3:1 on white, which is not a
  /// text colour by any reading of AA. Each accent here is the same hue walked
  /// down in value until it clears 4.8:1 both on the darkest surface it can
  /// land on and on its own tinted chip. The vivid orange survives as a *fill*
  /// colour, where light ink sits on top of it instead of beside it.
  static const light = HaulPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF2F2F0),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFEDEDEA),
    line: Color(0xFFD8D8D4),
    ink: Color(0xFF141416),
    inkSoft: Color(0xFF55555A),
    brand: Color(0xFFAC3C09),
    onBrand: Color(0xFFFFFFFF),
    go: Color(0xFF1A6F40),
    alert: Color(0xFFAE344A),
    violet: Color(0xFF625A94),
    washAlpha: 0x10,
  );

  @override
  HaulPalette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? raised,
    Color? line,
    Color? ink,
    Color? inkSoft,
    Color? brand,
    Color? onBrand,
    Color? go,
    Color? alert,
    Color? violet,
    int? washAlpha,
  }) {
    return HaulPalette(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      line: line ?? this.line,
      ink: ink ?? this.ink,
      inkSoft: inkSoft ?? this.inkSoft,
      brand: brand ?? this.brand,
      onBrand: onBrand ?? this.onBrand,
      go: go ?? this.go,
      alert: alert ?? this.alert,
      violet: violet ?? this.violet,
      washAlpha: washAlpha ?? this.washAlpha,
    );
  }

  @override
  HaulPalette lerp(covariant HaulPalette? other, double t) {
    if (other == null) return this;
    return HaulPalette(
      // A half-way brightness is not a thing; snap it at the midpoint.
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      raised: Color.lerp(raised, other.raised, t)!,
      line: Color.lerp(line, other.line, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      go: Color.lerp(go, other.go, t)!,
      alert: Color.lerp(alert, other.alert, t)!,
      violet: Color.lerp(violet, other.violet, t)!,
      washAlpha: (washAlpha + (other.washAlpha - washAlpha) * t).round(),
    );
  }
}

/// Shorthand for [HaulPalette.of].
abstract final class HaulColors {
  static HaulPalette of(BuildContext context) => HaulPalette.of(context);
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

/// The type scale, bound to a palette.
///
/// The styles carry their own colour because the split between primary and
/// secondary text is part of the scale, not something each call site should
/// have to remember.
@immutable
class HaulTypography {
  const HaulTypography(this.palette);

  final HaulPalette palette;

  static HaulTypography of(BuildContext context) =>
      HaulTypography(HaulPalette.of(context));

  TextStyle get display => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 34,
    height: 1.0,
    letterSpacing: -0.3,
    color: palette.ink,
  );

  TextStyle get heading => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 16,
    height: 1.1,
    color: palette.ink,
  );

  TextStyle get sectionTitle => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 15,
    height: 1.15,
    color: palette.ink,
  );

  TextStyle get blockTitle => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 12,
    letterSpacing: 1.4,
    color: palette.inkSoft,
  );

  TextStyle get eyebrow => TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.6,
    color: palette.inkSoft,
  );

  TextStyle get body => TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 14,
    height: 1.45,
    color: palette.ink,
  );

  TextStyle get bodyStrong => TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    height: 1.35,
    color: palette.ink,
  );

  TextStyle get secondary => TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 13,
    height: 1.35,
    color: palette.inkSoft,
  );

  TextStyle get small => TextStyle(
    fontFamily: HaulFonts.body,
    fontSize: 12,
    height: 1.35,
    color: palette.inkSoft,
  );

  TextStyle get money => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 20,
    height: 1.1,
    color: palette.brand,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  TextStyle get mono => TextStyle(
    fontFamily: HaulFonts.mono,
    fontSize: 12,
    height: 1.3,
    color: palette.inkSoft,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  TextStyle get action => TextStyle(
    fontFamily: HaulFonts.black,
    fontSize: 13,
    letterSpacing: 1.2,
    color: palette.ink,
  );

  TextStyle get pill => TextStyle(
    fontFamily: HaulFonts.body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.0,
    height: 1.2,
    color: palette.inkSoft,
  );
}

/// Shorthand for [HaulTypography.of].
abstract final class HaulText {
  static HaulTypography of(BuildContext context) => HaulTypography.of(context);
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

ThemeData buildHaulTheme(HaulPalette hc) {
  final ht = HaulTypography(hc);

  final scheme =
      (hc.isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            primary: hc.brand,
            onPrimary: hc.onBrand,
            secondary: hc.go,
            onSecondary: hc.onBrand,
            error: hc.alert,
            onError: hc.onBrand,
            surface: hc.surface,
            onSurface: hc.ink,
            outline: hc.line,
          );

  return ThemeData(
    useMaterial3: true,
    brightness: hc.brightness,
    colorScheme: scheme,
    extensions: [hc],
    scaffoldBackgroundColor: hc.bg,
    fontFamily: HaulFonts.body,
    splashFactory: InkSparkle.splashFactory,
    // A single, unmissable focus ring in the accent colour — this is how the
    // whole app is navigable from a keyboard on macOS, Windows, Linux and web.
    focusColor: hc.brand.withValues(alpha: 0.30),
    textTheme: TextTheme(
      displayLarge: ht.display,
      titleLarge: ht.heading,
      titleMedium: ht.sectionTitle,
      bodyLarge: ht.body,
      bodyMedium: ht.secondary,
      labelLarge: ht.action,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        // The one surface that inverts in light mode — a dark chip on a light
        // page, the way every platform draws a tooltip.
        color: hc.isDark ? hc.raised : hc.ink,
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      textStyle: TextStyle(
        fontFamily: HaulFonts.body,
        fontSize: 12,
        color: hc.isDark ? hc.ink : hc.surface,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: hc.surface,
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
