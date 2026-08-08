import 'package:flutter/cupertino.dart' show NoDefaultCupertinoThemeData;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// The palette Apple Calendar draws with, in both appearances.
///
/// These are the real system colours rather than an approximation: iOS ships
/// `systemRed` at #FF3B30 in light and #FF453A in dark, and the separator is a
/// grey with alpha rather than a solid, which is why a hairline over a grouped
/// background looks different from the same hairline over white.
@immutable
class CalPalette extends ThemeExtension<CalPalette> {
  const CalPalette({
    required this.brightness,
    required this.bg,
    required this.groupedBg,
    required this.card,
    required this.separator,
    required this.hairline,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.accent,
    required this.onAccent,
    required this.fill,
  });

  final Brightness brightness;

  /// What a full-bleed view sits on — white in light, black in dark. Apple
  /// Calendar's month grid is the lighter of the two backgrounds.
  final Color bg;

  /// The recessed one, behind grouped lists and the year view.
  final Color groupedBg;

  /// A raised sheet or row.
  final Color card;

  /// The hairline between rows in a list.
  final Color separator;

  /// The fainter rule inside a grid — the hour lines and the cell borders.
  final Color hairline;

  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;

  /// systemRed. Today, the now-line, and every affordance in the app.
  final Color accent;
  final Color onAccent;

  /// The grey behind a segmented control or a search field.
  final Color fill;

  bool get isDark => brightness == Brightness.dark;

  static const light = CalPalette(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    groupedBg: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    separator: Color(0xFFC6C6C8),
    hairline: Color(0xFFE5E5EA),
    label: Color(0xFF000000),
    secondaryLabel: Color(0xFF8A8A8E),
    tertiaryLabel: Color(0xFFC7C7CC),
    accent: Color(0xFFFF3B30),
    onAccent: Color(0xFFFFFFFF),
    fill: Color(0xFFEFEFF0),
  );

  static const dark = CalPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF000000),
    groupedBg: Color(0xFF1C1C1E),
    card: Color(0xFF1C1C1E),
    separator: Color(0xFF38383A),
    hairline: Color(0xFF2C2C2E),
    label: Color(0xFFFFFFFF),
    secondaryLabel: Color(0xFF8D8D93),
    tertiaryLabel: Color(0xFF48484A),
    accent: Color(0xFFFF453A),
    onAccent: Color(0xFFFFFFFF),
    fill: Color(0xFF1C1C1E),
  );

  static CalPalette of(BuildContext context) =>
      Theme.of(context).extension<CalPalette>() ?? light;

  @override
  CalPalette copyWith({
    Brightness? brightness,
    Color? bg,
    Color? groupedBg,
    Color? card,
    Color? separator,
    Color? hairline,
    Color? label,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? accent,
    Color? onAccent,
    Color? fill,
  }) => CalPalette(
    brightness: brightness ?? this.brightness,
    bg: bg ?? this.bg,
    groupedBg: groupedBg ?? this.groupedBg,
    card: card ?? this.card,
    separator: separator ?? this.separator,
    hairline: hairline ?? this.hairline,
    label: label ?? this.label,
    secondaryLabel: secondaryLabel ?? this.secondaryLabel,
    tertiaryLabel: tertiaryLabel ?? this.tertiaryLabel,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    fill: fill ?? this.fill,
  );

  @override
  CalPalette lerp(ThemeExtension<CalPalette>? other, double t) {
    if (other is! CalPalette) return this;
    return CalPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      groupedBg: Color.lerp(groupedBg, other.groupedBg, t)!,
      card: Color.lerp(card, other.card, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      label: Color.lerp(label, other.label, t)!,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      tertiaryLabel: Color.lerp(tertiaryLabel, other.tertiaryLabel, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
    );
  }
}

/// The face the ramp is set in.
///
/// On a real iPhone or Mac the right answer is to name nothing: Flutter picks
/// up the system face, which is SF Pro — the one Apple Calendar itself is set
/// in, and the reason a screenshot of it looks like the OS rather than like an
/// app. Nowhere else is there a system face the engine can reach. Naming
/// nothing on web or Linux makes Flutter fetch Roboto over the network at
/// boot, so the app paints its whole layout with no text in it until the
/// download lands and stays wordless offline — which is exactly what the
/// GitHub Pages demo and a crew on a bad signal would get. The bundled face is
/// the honest default there.
String? calendarFace([TargetPlatform? platform]) {
  if (kIsWeb) return 'Archivo';
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => null,
    _ => 'Archivo',
  };
}

/// The type ramp, close to iOS's.
class CalText {
  const CalText(this.p);

  final CalPalette p;

  static CalText of(BuildContext context) => CalText(CalPalette.of(context));

  TextStyle _style({
    required double size,
    FontWeight? weight,
    Color? colour,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
    fontFamily: calendarFace(),
    fontSize: size,
    fontWeight: weight,
    color: colour ?? p.label,
    letterSpacing: letterSpacing,
    height: height,
  );

  /// The big month name over a month view.
  TextStyle get largeTitle =>
      _style(size: 34, weight: FontWeight.w700, letterSpacing: 0.37);

  /// A nav-bar title.
  TextStyle get navTitle => _style(size: 17, weight: FontWeight.w600);

  /// The month name inside the year view's mini grid.
  TextStyle get miniMonth => _style(size: 15, weight: FontWeight.w600);

  TextStyle get body => _style(size: 17);

  TextStyle get bodyStrong => _style(size: 17, weight: FontWeight.w600);

  TextStyle get secondary => _style(size: 15, colour: p.secondaryLabel);

  /// The number in a month cell.
  TextStyle get dayNumber =>
      _style(size: 18, weight: FontWeight.w400, height: 1.0);

  /// The single letters over the month grid.
  TextStyle get weekdayHeader => _style(
    size: 11,
    weight: FontWeight.w600,
    letterSpacing: 0.5,
    colour: p.secondaryLabel,
  );

  /// The title inside an event block, and the hour labels beside it.
  TextStyle get eventTitle => _style(size: 12, weight: FontWeight.w600);

  TextStyle get eventDetail => _style(size: 11, colour: p.secondaryLabel);

  TextStyle get hourLabel => _style(size: 11, colour: p.secondaryLabel);

  /// The three-line stack in a year view's mini month.
  TextStyle get miniDay => _style(size: 9, height: 1.25);
}

ThemeData buildCalendarTheme(CalPalette p) {
  final scheme =
      (p.isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
            primary: p.accent,
            onPrimary: p.onAccent,
            surface: p.bg,
            onSurface: p.label,
            outline: p.separator,
          );

  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    extensions: [p],
    scaffoldBackgroundColor: p.bg,
    fontFamily: calendarFace(),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerTheme: DividerThemeData(
      color: p.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
      primaryColor: p.accent,
      brightness: p.brightness,
    ),
  );
}
