# Brothers Hauling

The job pipeline for Brothers Hauling — three access levels, one board.
A Flutter rebuild of the `haulboardv3` React prototype, running from the same
codebase on **iPhone, iPad, Android, macOS, Windows, Linux and the web**.

**Try it:** https://natehale05-gif.github.io/Brothers-Hauling/ — no install, no
sign-up. Pick any of the three access levels to see what that role sees.

---

## What it does

Three roles, one job pipeline:

| Role | Sees |
| --- | --- |
| **Admin** | Everything — money, live crew tracking, every job, and hiring at any level |
| **Manager** | Job pay, who's staffed where, hiring drivers, plus the full employee view |
| **Employee** | The board, job details, and before / after photos |

A driver takes a load off the board by **pressing and holding** a card — an
accidental tap must not sign someone up for a job. From there the job walks
through six stages (accepted → driving → loading → in transit → at disposal →
closed), writing a movement log dispatch can read live. **A job cannot close
without at least one before and one after photo.**

The moment a driver reaches the site the card asks for the before shot, at the
top of the card rather than down beside the photo strips — by the time anyone
scrolls that far the first load is already on the truck, and the "before" it was
meant to capture no longer exists. Each slot takes as many shots as the job
needs: the pile, the access, and the thing the customer will later swear was
already broken.

Managers and admins can push a job at a specific driver, but the driver still
has to accept it. Anyone above employee can flip into the employee view to see
exactly what their crew sees, money hidden and all.

### Hiring

Admins take on anyone; managers staff their own crew but cannot mint another
manager, and nobody but an owner can make an owner. That rule lives in the state,
not in the form — the form only offers what you may hand out, but submitting
something else is refused anyway, because otherwise "add crew" is a privilege
escalation with a friendly form on top of it. Anyone in the employee view gets
what their crew gets: no hiring at all.

A new hire starts off shift with the app closed, so nobody appears on the
tracking board before they have installed the thing.

### Hiring us from the website

A booking made on the website turns into a job on the dispatch board.

`BookingRequest` is the wire contract, and it is deliberately small: a customer
knows what they want moved and where from, and knows none of the things the app
needs to run the job. Mileage, equipment and money are left blank rather than
guessed — a made-up figure looks exactly like a real one on the board.

So a booking lands as **requested**, not open. Dispatch fills in the details and
puts a price on it, and only then does it reach the crew; an unpriced job on the
driver board is a job somebody can volunteer for at nothing a load. That rule is
enforced in the mutation as well as the screen, because the queue outlives the
screen.

Every booking carries the website's own id, and the job keeps it. The same
booking arriving down a second poll, or after a relaunch mid-sync, is the same
job rather than a second one.

**Try it:** open [`hire.html`](https://natehale05-gif.github.io/Brothers-Hauling/hire.html),
book a haul, then open the board and sign in as Admin. The demo page is served
from the same origin as the app, so the booking lands in the storage the board
reads — no server, but a real round trip rather than a mocked one. Pointing at a
live backend is `HttpIntakeSource` in `main.dart` and nothing else in the app.

### Correcting a job

An owner can edit every detail of a job — customer, address, access notes,
hazards, the load, the window, the mileage and all three money figures — from
the job card. Managers and drivers cannot, and neither can an owner standing in
the employee view.

The edit carries **only the fields that changed**, not the whole job. Sending
the whole thing would mean an edit made offline quietly reverting whatever the
driver did to the same job in the meantime — the stage they reached, the photos
they filed — the moment it replayed.

Status, stage, the assignee, the photos and the movement log are missing from
the editable set on purpose: they are the record of what happened in the field,
and an edit form is not the place to rewrite it. That list is enforced in the
mutation as well as at the call site, because the queue outlives an app upgrade.
Every edit writes itself into the movement log, so dispatch changing what a job
pays is something the driver can see afterwards.

### Working with no signal

The board lives on the device, not in memory. Every change — claiming a load,
stepping a stage, filing a photo — is recorded as a **mutation**: applied
immediately so the driver sees it, written to disk before the call returns, then
queued for the server and sent when there is something to send to.

That ordering is the whole design. The first three steps cannot fail for lack of
signal, so a driver can work an entire job in Blodgett, close it, kill the app,
and lose nothing. Only the fourth step needs a radio, and it is allowed to fail
for as long as it likes.

The queue preserves order and sends strictly one at a time — "arrived on site"
before "loaded up" — backs off exponentially on failure, and gives up loudly
rather than retrying forever. Work the server refuses is never silently
dropped; it is shown to the driver with a retry.

Nothing in the UI claims a change has reached dispatch until it has. Queued work
reads "saved on this phone", not "saved".

There is still no server — the send step currently succeeds as soon as a change
is durable, which is what makes the demo above persist across a reload. Pointing
it at a real backend means implementing one function.

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

**433 tests**, in thirteen files:

| File | Covers |
| --- | --- |
| `test/app_state_test.dart` | The pipeline itself — claiming, accepting, stage transitions, the photo gate, movement/ETA maths, rig matching, money roll-ups |
| `test/widget_flow_test.dart` | End-to-end journeys per role, the hold gesture, money visibility, directions and dialling, layout switching, every `TargetPlatform` |
| `test/layout_test.dart` | Every tab and every job card across six device sizes at normal and 1.6× text — 122 combinations, each asserting nothing overflows |
| `test/accessibility_test.dart` | Contrast maths, Flutter's four accessibility guidelines on every screen, screen reader labels, keyboard control, reduced motion |
| `test/serialization_test.dart` | Everything that is persisted or sent, round-tripped through real JSON, plus what happens when the stored data is malformed |
| `test/outbox_test.dart` | The offline queue — ordering, backoff, giving up, surviving the process dying |
| `test/board_repository_test.dart` | A shift worked with no signal: applied locally, kept across relaunch, delivered in order when signal returns |
| `test/sync_ui_test.dart` | That the app never tells a driver their work landed when it has not |
| `test/theme_test.dart` | The appearance choice — that it cycles, persists, repaints, and says which mode is on |
| `test/photos_test.dart` | Many shots per slot, the on-site prompt, and that a board written by the previous build still loads |
| `test/crew_test.dart` | Who may hire whom, that the rule is enforced in the state rather than the form, and that a new hire survives a relaunch |
| `test/edit_job_test.dart` | That an owner can correct every detail, that nobody else can, and that an edit cannot rewrite what the driver did |
| `test/intake_test.dart` | The booking contract, that the same booking never lands twice, that a dead website doesn't take the board down, and that nothing reaches a driver unpriced |

### Browser smoke test

Widget tests say nothing about whether the compiled bundle actually boots in a
browser at the base href GitHub Pages serves it from. `tool/web_smoke_test.js`
drives the real artifact through Chromium — signing in, reading the accessibility
tree the way a screen reader would, and failing on any console error:

```bash
flutter build web --release --base-href "/Brothers-Hauling/"
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
- **Every colour pairing clears WCAG AA (4.5:1) in both light and dark**,
  including translucent chips measured against the blend they actually sit on.
  Flutter's four guidelines are also run over every screen in *both* palettes,
  because the contrast guideline reads the pixels that were really painted —
  which is how a hardcoded near-black scrim behind now-dark light-mode text got
  caught.
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

### Brand

The palette is not eyeballed off the logo — three colours are sampled straight
out of `assets/branding/app_icon_source.png` and used as-is:

| | | |
| --- | --- | --- |
| `#111112` | near-black | the icon's field, and the app's background |
| `#A4A3A5` | neutral grey | the grey of "BROTHERS" |
| `#F9570D` | safety orange | the orange of "HAULING", the accent everywhere |

The orange is used untinted because it happens to clear WCAG AA on every
surface in the app (5.8:1 on the background), so the brand colour and the
accessible colour are the same colour — no separate "web-safe" variant to keep
in sync.

Two knock-on changes fell out of it. The alert colour moved to a pink-red
(`#FF4D6D`); the prototype's alert was itself an orange-red, which stops
reading as "different" once the accent is orange. And the neutrals lost their
blue cast — the icon's black is neutral, so the surfaces are too.

The role gate draws the icon's lockup in type (`lib/widgets/brand_mark.dart`)
rather than shipping it as an image: crisp at any size, and nothing added to
the web payload.

### Light and dark

Dark is what a cab at 5 AM needs. Light is what a yard at noon needs, where a
dark screen is just a mirror. Both ship; the toggle sits in the top bar and on
the sign-in screen, and the choice is remembered on the device.

The default follows the phone rather than forcing either one — someone who has
already set their device has said everything they mean to say about it. The
control cycles through *follow my device → light → dark* rather than being a
two-way switch, because "follow my device" is a real answer and has to stay
reachable after you have overridden it once.

Light is **not** the dark palette on a white card. The icon's orange manages
3.3:1 on white, which is not a text colour by any reading of AA. Each accent in
the light palette is the same hue walked down in value until it clears 4.8:1
both on the darkest surface it can land on and on its own tinted chip; the vivid
orange survives as a *fill*, where light ink sits on top of it rather than
beside it. The tinted chips are also much thinner on light, because a tint
darkens the chip either way — which hands a light label headroom on dark, and
takes it away from a dark label on light.

### App icon

One source image, `assets/branding/app_icon_source.png`, drives every
platform's icon. `python3 tool/generate_icons.py` regenerates all 44 outputs —
edit the source and re-run rather than hand-editing any of them.

Each platform frames it differently, which is the reason for the script:
iOS gets a full-bleed square with no alpha channel (it rounds the corners
itself, and the App Store rejects alpha); Android gets a legacy square plus an
adaptive icon with a monochrome layer for themed icons; macOS gets the rounded
square inset in a transparent canvas the way the Dock expects; Windows gets a
multi-resolution `.ico`; Linux gets a PNG the GTK window loads at runtime.

Where something else masks the icon — Android's launcher shapes, a maskable
web icon — the script sizes the mark by **where its ink actually falls** rather
than by its bounding box. Fitting the bounding box inside the safe circle
shrinks the logo needlessly; fitting the box's corners, which are empty, is
what clips "HAULING" off the bottom under a circular mask.

### Dependencies

`geolocator`, `url_launcher`, `image_picker` — all three ship implementations
for all six targets. Fonts (Archivo, Archivo Black, DM Mono) are **bundled**
rather than fetched, so the app renders identically offline; the prototype
pulled them from Google Fonts on every load.

The web build **self-hosts CanvasKit** (`web/flutter_bootstrap.js`). By default
Flutter fetches it from `gstatic.com` at runtime, which means the app doesn't
start at all on a network that can't reach it.

It also renders into a **host element** (`#app`) rather than into the page.
Left to itself the engine sizes the app from the layout viewport, which on a
phone browser is the tall "toolbar retracted" height — so the bottom tab bar
gets drawn below the visible edge, behind the browser toolbar, and a driver has
to fight the page to reach it. No CSS on `<html>` can correct that, because
`documentElement.clientHeight` reports the tall viewport whatever the stylesheet
says. Given a host element the engine measures *that box* instead and watches it
with a `ResizeObserver`, so sizing it in `dvh` units pins the tabs to the bottom
edge and re-lays-out when the toolbar slides in or out. The smoke test asserts
it, since no widget test can see a host page getting it wrong.

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
