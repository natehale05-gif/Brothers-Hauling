# Brothers Hauling

The job calendar for Brothers Hauling, built the way Apple Calendar is, running
from one codebase on **iPhone, iPad, Android, macOS, Windows, Linux and the
web**.

**Try it:** https://natehale05-gif.github.io/Brothers-Hauling/ — no install, no
sign-up. Five views over the same days, and every job opens onto its details.

---

## What it does

Five views over one set of days, and a job opens onto a sheet over whatever you
were looking at rather than a screen you have to come back from.

| View | Shows |
| --- | --- |
| **Day** | An hour grid, the week along the top, and a red line across now — only ever on today |
| **Week** | Seven columns; work booked at the same hour sits side by side rather than on top of itself |
| **Month** | Dots under the day numbers on a phone, with the chosen day listed below; give it a window and the jobs are written into the cells |
| **Year** | Twelve small months, the current one named in red |
| **List** | Forward from today, grouped under day headings |

The arrows step by whatever is on screen — a month view pages by months and a
day view by days, because "next" has to mean what you are looking at. On a
desktop the **left and right keys** do the same, **T** returns to today, and
**Escape** closes an open job. "Today" is one tap away whenever you have left it.

Work is grouped into **calendars** by the kind of job — debris, junk, gravel,
bark, equipment — each with its own colour, and any of them can be switched off
without touching the jobs themselves.

### Booking, changing and moving work

| | |
| --- | --- |
| **Add** | The + in the bar, or tap the hour you want in the day or week view |
| **Edit** | Edit on a job's sheet — the same form it was booked on |
| **Delete** | From the editor, with a confirmation |
| **Move** | Long-press a block and drag it, snapped to the quarter hour |
| **Stretch** | Take its bottom edge and pull to change how long it runs |
| **Search** | Over every field; a result jumps to the day it is on |
| **Go to** | Tap the title to jump somewhere too far off to page to |
| **Repeat** | Daily, weekly, fortnightly, monthly or yearly, a set number of times |
| **Alert** | At the time, or fifteen minutes to a day before it starts |

Long-press before a block moves, deliberately: a calendar you can knock a job
off by brushing it while scrolling is worse than one you cannot drag at all.

A **repeat writes a real job per occurrence** rather than one job claiming to
happen six times. Each haul has its own driver, its own hours and its own
photos, and a virtual occurrence has nowhere to put any of them. The cost is
that a repeat cannot later be edited as a series, so the Repeat row is offered
when booking and not when correcting rather than pretending otherwise.

**Deleting is refused for work that has been started.** The movement log, the
hours and the photos are the record of what happened in the field, and an edit
form is not the place to erase it.

Every one of these goes through the same mutations and the same outbox as the
rest of the board, so a job booked in a dead zone is on the board before the
phone finds signal.

### Reminders

An alert lives **on the job**, not on the device that set it, so dispatch
saying "give them half an hour's warning" reaches the driver who is going to
do the work. Each device schedules its own from whatever the board says and
re-reconciles every time the board moves — which is what makes a job somebody
else dragged to the afternoon stop buzzing at its old time. Reminders already
gone by are never scheduled, and a closed job never buzzes at all.

The web is the odd one out. A browser cannot hand a future notification to
anything that outlives the page, so there the app raises them itself while the
page is open. The Calendars sheet says which of the two is happening rather
than letting somebody close a tab expecting to be told about a nine o'clock.

### What a job needs, and who may take it

A job states **what rig it needs**. It does not assign one to a person and it
does not stop anybody from answering. The crew know their own equipment better
than a form does.

### Work with no date

A booking made on the website arrives with no day on it, and a calendar has
nowhere to draw that. Rather than lose it, the list view carries a **Not
scheduled yet** section at the top — a job quietly filed under today is a job
that gets missed tomorrow, and one omitted from the grid entirely is worse.

### Signing in

The board is behind a login, because what the app shows depends entirely on
who is looking.

| | Sees |
| --- | --- |
| **Admin** | Everything, and is the only one who books, corrects or deletes a job |
| **Manager** | The board and what a job bills at, but cannot rewrite one |
| **Employee** | The board and the job details. No money anywhere, ever |

A session survives a relaunch, and is dropped if the account was removed or
demoted while the app was closed — the level you had on the way out is not
yours to keep. An owner hands out logins from **Logins**: tied to somebody
already on the roster, so their jobs and hours are theirs the moment they sign
in.

Passwords are PBKDF2-HMAC-SHA256 with a per-account salt, compared in constant
time. Only the hash is ever written; the owner runs the server and still
cannot read what anybody typed.

**A device nobody has set up makes itself three sample logins** — one per
level, matched to the sample roster — because a fresh install with no way in
is an app nobody can open. The password is printed on the sign-in screen
rather than hidden in the source, and both that screen and the Logins screen
keep saying which accounts are still on it until somebody replaces them.
Default credentials nobody mentions again are the hazard; these are the
opposite of quiet.

### What the calendar cannot reach yet

The rebuild replaced the dispatch UI, not the machinery underneath it. Hiring
and promotion, the hours a job clocks up, live crew tracking, before/after
photos and the movement log are all still in `lib/state` and `lib/models`,
still enforced, and still covered by tests — but the calendar has no way in to
any of them yet. They are the next things to build on top of this, not things
that were thrown away.

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

**364 tests**, in sixteen files:

| File | Covers |
| --- | --- |
| `test/date_math_test.dart` | The arithmetic under every grid — six-row months, week starts, month paging that lands on February rather than March |
| `test/calendar_event_test.dart` | Reading a job as an event, which calendar it belongs to, and the lane packing that keeps two jobs at nine o'clock from being drawn on top of each other |
| `test/calendar_state_test.dart` | What is on screen — stepping per view, focus versus selection, titles, hiding a calendar |
| `test/calendar_view_test.dart` | Every view rendered and driven: taps, the keyboard, the job sheet, undated work, and 1.6× text on a 320pt screen |
| `test/calendar_edit_test.dart` | Booking, correcting and deleting a job; the drag and stretch gestures; the recurrence maths; and search |
| `test/alerts_test.dart` | When a reminder is due, what it says, which ones a board is owed, and that the device is told again whenever a job moves |
| `test/sign_in_test.dart` | Signing in at each level, a wrong password saying nothing useful, sessions across a relaunch, revocation and demotion, and handing out a login |
| `test/app_state_test.dart` | The pipeline itself — claiming, accepting, stage transitions, the photo gate, movement/ETA maths, money roll-ups |
| `test/serialization_test.dart` | Everything that is persisted or sent, round-tripped through real JSON, plus what happens when the stored data is malformed |
| `test/outbox_test.dart` | The offline queue — ordering, backoff, giving up, surviving the process dying |
| `test/board_repository_test.dart` | A shift worked with no signal: applied locally, kept across relaunch, delivered in order when signal returns |
| `test/sync_server_test.dart` | The owner's machine as the server — private logins, hashed passwords, a real socket |
| `test/server_state_test.dart` | Who may run a server, and what the accounts book does and does not keep |
| `test/photos_test.dart` | Many shots per slot, the on-site prompt, and that a board written by the previous build still loads |
| `test/crew_test.dart` | Who may hire whom, and that the rule is enforced in the state rather than the form |
| `test/edit_job_test.dart` | That an edit carries only what changed, and cannot rewrite what the driver did |
| `test/hours_test.dart` | The clock starting and stopping with the job, and the timesheet maths |
| `test/intake_test.dart` | The booking contract, that the same booking never lands twice, and that nothing reaches a driver unpriced |

### Browser smoke test

Widget tests say nothing about whether the compiled bundle actually boots in a
browser at the base href GitHub Pages serves it from. `tool/web_smoke_test.js`
drives the real artifact through Chromium — moving through the views, reading
the accessibility tree the way a screen reader would, following a booking from
the website form into the calendar, and failing on any console error:

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

- **Nothing means anything by colour alone.** A coloured block announces
  "Junk removal for Harrison St rental in Corvallis. 9 AM – 11 AM." A day in the
  month grid announces "Thursday, 6 August, today. 3 jobs." — and when the cell
  is wide enough to list them, so does its label. A day with no work says
  "Nothing on" rather than falling silent.
- **The weekday header is read in full.** Two of the seven letters are "S";
  position carries the difference for the eye, and the header announces
  "Saturday" and "Sunday" for everyone else.
- **The view switcher states position**: "Month view, 3 of 5".
- **The all-day gutter label is hidden from screen readers**, because each chip
  in the band already announces "All day" and hearing it twice before the job
  helps nobody.
- **Every colour pairing clears WCAG AA (4.5:1) in both light and dark**, drawn
  with the real iOS system colours in both appearances.
- **44pt minimum hit targets** on every control in the bar.
- **Text scales to 1.6×** without a single overflow — every view, on a 320pt
  screen, asserted in `test/calendar_view_test.dart`.
- **Full keyboard control**: left/right step, **T** returns to today, **N**
  books a job, **⌘F** searches, **Escape** closes an open job.
- **Every gesture has a keyboard or a form behind it.** A block can be dragged
  to a new hour, but the same move is a field in the editor — nobody has to
  land a drag to reschedule a job.
- The title is a **live region**, so paging months announces where you landed.

---

## How it's put together

```
lib/
  main.dart              app shell, theme wiring, text-scale clamp
  models/                Job, CrewMember, Role — plain data, no Flutter imports
  data/                  the store, the outbox, the repository, the sync server
  state/app_state.dart   the domain: one ChangeNotifier, AppScope exposes it
  services/              everything platform-specific, behind an interface
  calendar/
    date_math.dart       days, weeks, month grids — pure, and tested alone
    event.dart           a Job as a calendar draws it, and the lane packing
    calendar_state.dart  what is on screen; never leaves the device
    calendar_theme.dart  the iOS palette and type ramp, as tokens
    calendar_home.dart   nav bar, view switcher, calendars sheet
    event_sheet.dart     a job, opened over the calendar
    views/               day, week, month, year, list, and the hour grid
```

Two decisions worth knowing:

**Platform code lives behind three interfaces** — `LocationService`,
`LinkService`, `PhotoService`. The UI never branches on platform; a target
missing a capability (no camera on a desktop, no location provider on Linux)
falls through inside the service, and tests inject stand-ins instead of mocking
platform channels.

**One layout, sized by what fits, not by a breakpoint list.** The month view
measures its own cells: too small for anything but dots and the chosen day is
listed underneath, the way an iPhone does it; big enough to hold two lines and
the jobs are written into the cells and the list goes away, the way a Mac does
it. Same widgets either way — an iPad or a desktop window isn't a stretched
phone.

**Two states, kept apart.** `AppState` is the domain — jobs, crew, the outbox,
the server — and is the thing that syncs. `CalendarState` is which day is on
screen, which view is chosen, which calendars are hidden: facts about this
device at this moment, and nothing in it ever leaves it. Both are plain
`ChangeNotifier`s reached through an `InheritedNotifier`. No state-management
package: every dependency is a dependency that can break a Windows or Linux
build.

### Brand

The app itself is drawn in **iOS's own system colours** — systemRed for today
and the now-line, the system greys for labels and rules — because a calendar
that looks like the OS is the whole point of the exercise. The brand palette
below is what the icon, the boot splash and the booking site are built from.

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

The boot splash draws the icon's lockup in type (`web/index.html`) rather than
shipping it as an image: crisp at any size, and nothing added to the web
payload.

### Light and dark

Dark is what a cab at 5 AM needs. Light is what a yard at noon needs, where a
dark screen is just a mirror. Both ship and the choice is remembered on the
device; the default follows the phone, because someone who has already set
their device has said everything they mean to say about it.

Both palettes are the real iOS system values rather than one derived from the
other — systemRed is `#FF3B30` on light and `#FF453A` on dark for a reason, and
a calendar that dimmed the light one would stop looking like the OS it is
imitating. A job's colour is used untinted for its text and at 18% for its
fill, so the block reads at a glance even when it is too short for its own
title.

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

`geolocator`, `url_launcher`, `image_picker`, `flutter_local_notifications`
and `timezone` — all of them ship implementations for all six targets. Fonts (Archivo, Archivo Black, DM Mono) are **bundled**
rather than fetched. That matters more than it looks: name no font at all and
Flutter fetches Roboto from `gstatic.com` at boot, so the web build paints its
entire layout with no text in it until the download lands, and stays wordless
offline. Apple platforms still get the system face — SF Pro, which is what
Apple Calendar itself is set in — because there the engine can reach it.

The web build **self-hosts CanvasKit** (`web/flutter_bootstrap.js`). By default
Flutter fetches it from `gstatic.com` at runtime, which means the app doesn't
start at all on a network that can't reach it.

The Calendars sheet also carries what this device is doing: whether anything
is still waiting to be sent, and — for an owner on a platform that can listen
on a port — the switch that serves the board to the crew, with the addresses
to type in.

It also renders into a **host element** (`#app`) rather than into the page.
Left to itself the engine sizes the app from the layout viewport, which on a
phone browser is the tall "toolbar retracted" height — so the bottom tab bar
gets drawn below the visible edge, behind the browser toolbar, and a driver has
to fight the page to reach it. The view switcher sits exactly there. No CSS on `<html>` can correct that, because
`documentElement.clientHeight` reports the tall viewport whatever the stylesheet
says. Given a host element the engine measures *that box* instead and watches it
with a `ResizeObserver`, so sizing it in `dvh` units pins the switcher to the bottom
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
