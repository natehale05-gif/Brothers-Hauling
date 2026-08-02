{{flutter_js}}
{{flutter_build_config}}

// By default a release web build fetches CanvasKit from
// https://www.gstatic.com/flutter-canvaskit/…, so the app doesn't start at all
// on a network that can't reach it — a locked-down office, a captive portal, a
// cab with patchy signal. `flutter build web` already writes a copy of
// CanvasKit into the output directory, so point at that instead and the deploy
// is genuinely self-contained. `canvaskit/` is relative to <base href>, which
// makes this work both at the domain root and under /<repo>/ on GitHub Pages.
//
// No serviceWorkerSettings, deliberately. The default bootstrap registers
// Flutter's service worker, which caches the app shell — and on GitHub Pages
// that is the classic reason a visitor keeps seeing yesterday's build after a
// deploy. Flutter's service worker is also deprecated and slated for removal.
// Leaving it unregistered means every visit gets the deployed build, with
// ordinary HTTP caching still doing its job. `--pwa-strategy=none` at build
// time stops the unused worker being emitted at all.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
