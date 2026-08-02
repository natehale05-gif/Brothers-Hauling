{{flutter_js}}
{{flutter_build_config}}

// By default a release web build fetches CanvasKit from
// https://www.gstatic.com/flutter-canvaskit/…, so the app doesn't start at all
// on a network that can't reach it — a locked-down office, a captive portal, a
// cab with patchy signal. `flutter build web` already writes a copy of
// CanvasKit into the output directory, so point at that instead and the deploy
// is genuinely self-contained. `canvaskit/` is relative to <base href>, which
// makes this work both at the domain root and under /<repo>/ on GitHub Pages.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
