# Haul Board

The job pipeline for Brothers Hauling — three access levels, one board.
A Flutter rebuild of the `haulboardv3` React prototype, running from the same
codebase on **iPhone, iPad, Android, macOS, Windows, Linux and the web**.

**Try it:** https://natehale05-gif.github.io/brothers-hauling/ — no install, no
sign-up. Pick any of the three access levels to see what that role sees.

---

## What it does

Three roles, one job pipeline:

| Role | Sees |
| --- | --- |
| **Admin** | Everything — money, live crew tracking, every job |
| **Manager** | Job pay, who's staffed where, plus the full employee view |
| **Employee** | The board, job details, and before / after photos |

A driver takes a load off the board by **pressing and holding** a card — an
accidental tap must not sign someone up for a job. From there the job walks
through six stages (accepted → driving → loading → in transit → at disposal →
closed), writing a movement log dispatch can read live. **A job cannot close
without a before and an after photo.**

Managers and admins can push a job at a specific driver, but the driver still
has to accept it. Anyone above employee can flip into the employee view to see
exactly what their crew sees, money hidden and all.

### Location, stated plainly

Position is shared with dispatch **only while the app is open**. There is no
background location permission on any platform, and the driver's screen says so
in a strip that never scrolls away. When the app closes, dispatch keeps the last
known ping so nobody simply vanishes off the board.

If location is denied, unavailable, or the permission prompt goes unanswered for
12 seconds, the app falls back to a simulated yard position and says so, rather
than sitting on a spinner forever.

---

## Running it

Needs Flutter **3.44.8** (pinned in `pubspec.yaml`).

```bash
flutter pub get

flutter run                      # whatever device is attached
flutter run -d chrome            # web
flutter run -d macos             # macOS       (also: windows, linux)
flutter run -d ipad              # any booted simulator
```

Building:

```bash
flutter build apk --release           # Android
flutter build ios --release           # iOS / iPadOS
flutter build macos --release         # macOS
flutter build windows --release       # Windows
flutter build linux --release         # Linux
flutter build web --release           # web
```

`.github/workflows/build.yml` builds all six on every push to `main`, so the
cross-platform claim is checked rather than asserted.

---

## Testing

```bash
flutter analyze
flutter test
```

**220 tests**, in four files:

| File | Covers |
| --- | --- |
| `test/app_state_test.dart` | The pipeline itself — claiming, accepting, stage transitions, the photo gate, movement/ETA maths, rig matching, money roll-ups |
| `test/widget_flow_test.dart` | End-to-end journeys per role, the hold gesture, money visibility, directions and dialling, layout switching, every `TargetPlatform` |
| `test/layout_test.dart` | Every tab and every job card across six device sizes at normal and 1.6× text — 122 combinations, each asserting nothing overflows |
| `test/accessibility_test.dart` | Contrast maths, Flutter's four accessibility guidelines on every screen, screen reader labels, keyboard control, reduced motion |

### Browser smoke test

Widget tests say nothing about whether the compiled bundle actually boots in a
browser at the base href GitHub Pages serves it from. `tool/web_smoke_test.js`
drives the real artifact through Chromium — signing in, reading the accessibility
tree the way a screen reader would, and failing on any console error:

```bash
flutter build web --release --base-href "/brothers-hauling/"
npm install --no-save playwright && npx playwright install --with-deps chromium
node tool/web_smoke_test.js
```

It runs in `.github/workflows/pages.yml` before anything is published, so a
bundle that doesn't boot never reaches the site.

---

## Accessibility

Not a pass at the end — it shaped the widgets.

- **Hold-to-commit has three paths.** Press and hold; hold Enter or Space on a
  focused control; or, when a screen reader or reduced-motion setting is
  detected, a single activation opens a confirmation dialog instead. Nobody has
  to sustain a gesture to take a job.
- **Nothing means anything by colour alone.** The stage rail announces
  "Stage 3 of 5, Loading". The route strip announces "Route from Yard to
  Monmouth, 42 percent complete, 11 min out". The week chart announces every
  day's figure. A dimmed job card also carries a chip reading "Lowboy 25t — not
  your rig".
- **Every colour pairing clears WCAG AA (4.5:1)**, including translucent chips
  measured against the blend they actually sit on — asserted in
  `accessibility_test.dart`, which is why the alert and violet tokens are a
  shade brighter than the prototype's.
- **Money reads as a phrase**, not an orphaned number: "Your cut, 168 dollars".
- **Toasts are announced** to screen readers and are transparent to pointers, so
  a confirmation can never eat a tap meant for the button underneath it.
- **48pt minimum hit targets** everywhere — Material's 48 and iOS's 44 at once,
  and enough for gloves.
- **Text scales to 1.6×** without a single overflow, verified across six device
  sizes.
- **Reduced motion is respected**: the live-ping pulse stops, the rig snaps
  instead of gliding, and the hold control switches to the dialog.
- **Full keyboard control** with a hi-vis focus ring; Escape closes a job card or
  the closed-job screen.
- Disabled controls **say why** they're disabled instead of greying out silently.

---

## How it's put together

```
lib/
  main.dart              app shell, theme wiring, text-scale clamp
  models/                Job, CrewMember, Role — plain data, no Flutter imports
  data/seed_data.dart    today's board
  state/app_state.dart   one ChangeNotifier; AppScope exposes it
  services/              everything platform-specific, behind an interface
  theme/haul_theme.dart  the palette and type scale, as tokens
  widgets/               the reusable pieces (hold button, route strip, …)
  screens/               role gate, adaptive shell, job card, the tabs
```

Two decisions worth knowing:

**Platform code lives behind three interfaces** — `LocationService`,
`LinkService`, `PhotoService`. The UI never branches on platform; a target
missing a capability (no camera on a desktop, no location provider on Linux)
falls through inside the service, and tests inject stand-ins instead of mocking
platform channels.

**One layout, two shapes.** Under 900pt the app uses bottom tabs and the job
card takes over the screen. Above it, a navigation rail with the job card in a
permanent side pane — so an iPad or a desktop window isn't a stretched phone.
Same widgets either way; only the chrome differs.

State is a single `ChangeNotifier` reached through an `InheritedNotifier`. No
state-management package: the app has one screen's worth of state, and every
dependency is a dependency that can break a Windows or Linux build.

### Dependencies

`geolocator`, `url_launcher`, `image_picker` — all three ship implementations
for all six targets. Fonts (Archivo, Archivo Black, DM Mono) are **bundled**
rather than fetched, so the app renders identically offline; the prototype
pulled them from Google Fonts on every load.

The web build **self-hosts CanvasKit** (`web/flutter_bootstrap.js`). By default
Flutter fetches it from `gstatic.com` at runtime, which means the app doesn't
start at all on a network that can't reach it.

One third-party request remains: the Flutter engine probes `fonts.gstatic.com`
for its own Roboto/Noto glyph fallbacks. Every font the app renders with is
bundled, so blocking it changes nothing visible — the smoke test runs with that
request failing.

---

## Deploying

Pushes to `main` build, test, smoke-test and publish to GitHub Pages via
`.github/workflows/pages.yml`. It needs **Settings → Pages → Source: GitHub
Actions** enabled once. `--base-href` is derived from the repository name, so a
rename doesn't break the asset paths.

---

The seed data is fictional — placeholder customers, `555` phone numbers, and a
crew of four.
