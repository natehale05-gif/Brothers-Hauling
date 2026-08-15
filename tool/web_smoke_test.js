/*
 * Browser smoke test for the built web app.
 *
 * `flutter test` proves the widgets behave; it says nothing about whether the
 * compiled bundle actually boots in a browser, under the base href GitHub Pages
 * serves it from, without reaching for a third-party CDN. That is what this
 * checks — against build/web, exactly what gets deployed.
 *
 *   flutter build web --release --base-href "/brothers-hauling/"
 *   node tool/web_smoke_test.js
 *
 * Requires playwright and a Chromium build:
 *   npm i playwright && npx playwright install --with-deps chromium
 *
 * Set CHROMIUM_PATH to use a browser that is already on the machine.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const BUILD_DIR = path.resolve(__dirname, '..', 'build', 'web');

// Must match the --base-href the bundle was built with. GitHub Pages serves a
// project site under the repository name, case included.
const BASE_PATH = process.env.BASE_PATH || '/Brothers-Hauling/';
const PORT = Number(process.env.PORT || 8099);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.json': 'application/json',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.symbols': 'text/plain',
};

/** Serves build/web under BASE_PATH, the way GitHub Pages serves a project site. */
function serve() {
  const server = http.createServer((req, res) => {
    let rel = decodeURIComponent(req.url.split('?')[0]);
    if (!rel.startsWith(BASE_PATH)) {
      res.writeHead(404).end('not found');
      return;
    }
    rel = rel.slice(BASE_PATH.length) || 'index.html';
    if (rel.endsWith('/')) rel += 'index.html';

    const file = path.join(BUILD_DIR, rel);
    // Never serve outside the build directory.
    if (!file.startsWith(BUILD_DIR)) {
      res.writeHead(403).end('forbidden');
      return;
    }
    fs.readFile(file, (err, body) => {
      if (err) {
        res.writeHead(404).end('not found');
        return;
      }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file)] || 'application/octet-stream',
      });
      res.end(body);
    });
  });
  return new Promise((resolve) => server.listen(PORT, () => resolve(server)));
}

/** Boots the app and turns on the semantics tree, as assistive tech would. */
async function boot(browser, viewport) {
  // An explicit locale is load-bearing, not cosmetic. Playwright's headless
  // shell inherits the container's POSIX locale and reports
  // navigator.language as "en-US@posix"; Flutter's engine hands that straight
  // to Intl.Locale, which rejects it, and the app dies before its first frame.
  // No real browser reports a tag like that.
  const page = await browser.newPage({ viewport, locale: 'en-US' });
  // Stands in for the user saying yes to the notification prompt. Headless
  // Chromium refuses by default, which would make the reminder check assert
  // the browser's answer rather than the app's behaviour.
  await page
    .context()
    .grantPermissions(['notifications'])
    .catch(() => {});
  const errors = [];
  page.on('pageerror', (e) => errors.push('page error: ' + e.message));
  page.on('requestfailed', (r) => {
    const url = r.url();
    // Flutter's engine always probes Google Fonts for its Roboto/Noto glyph
    // fallbacks. The app bundles every font it actually renders with, so a
    // failure there changes nothing — see README.
    if (url.includes('fonts.gstatic.com')) return;
    errors.push('request failed: ' + url);
  });

  await page.goto(`http://127.0.0.1:${PORT}${BASE_PATH}`, {
    waitUntil: 'load',
    timeout: 60000,
  });
  // The boot splash removes itself on Flutter's first painted frame.
  try {
    await page.waitForFunction(() => !document.getElementById('boot'), {
      timeout: 60000,
    });
  } catch (e) {
    // The splash is still up, so Flutter never painted. Whatever the page
    // logged is far more useful than a bare timeout.
    console.error('\nThe app never painted its first frame. Page errors:');
    console.error(errors.length ? errors.join('\n') : '  (none captured)');
    throw e;
  }
  await page.waitForTimeout(1500);

  await page.evaluate(() => {
    const ph = document.querySelector('flt-semantics-placeholder');
    if (!ph) return;
    ph.click();
    ph.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
    ph.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
  });
  await page.waitForTimeout(1200);
  return { page, errors };
}

/**
 * Signs in, because the board is behind a login now.
 *
 * A fresh device makes itself sample logins and prints the password on the
 * screen, so this is what anybody opening the demo does — one tap on the level
 * they want, then Sign in.
 */
async function signIn(page, level = 'Admin') {
  await page.getByRole('button', { name: `Use the ${level} sample login` })
    .first()
    .click({ timeout: 15000 });
  await page.waitForTimeout(500);
  await page.getByRole('button', { name: 'Sign in', exact: false })
    .first()
    .click({ timeout: 15000 });
  await page.waitForTimeout(1800);
}

/**
 * Flattens Flutter's semantics into `role:name` strings.
 *
 * Read straight off the semantics DOM rather than through
 * `page.accessibility.snapshot()`. That API is deprecated, and on a narrow
 * viewport it collapses the whole scrolling body into a single node — so a
 * board full of announced job cards came back as one unreadable blob and every
 * assertion against it failed while the app itself was perfectly fine. These
 * are the same nodes a screen reader walks, and the locator pierces the shadow
 * root the engine puts them in.
 */
async function axNames(page) {
  return page.locator('flt-semantics').evaluateAll((nodes) =>
    nodes
      .map((node) => {
        // A label belongs to the leaf that carries it. Taking textContent from
        // a node that still has semantic children would glue a whole subtree
        // into one string.
        if (node.querySelector('flt-semantics')) return null;
        // The engine writes the label as text, not as aria-label, and wraps
        // lines — "Overview\nTab 1 of 4" is one label, not two.
        const label = (node.textContent || '').replace(/\s+/g, ' ').trim();
        if (!label) return null;
        const role = node.getAttribute('role') === 'button' ? 'button' : 'text';
        return `${role}:${label}`;
      })
      .filter(Boolean),
  );
}

/**
 * True when any semantics node's announced text matches [re].
 *
 * Unlike [axNames] this does not restrict itself to leaves: Flutter merges a
 * whole job card into one node, so a phrase like the reason a control is
 * blocked lives inside a parent's text rather than on a node of its own.
 * Containment is the right question for those.
 */
async function axContains(page, re) {
  const texts = await page.locator('flt-semantics').evaluateAll((nodes) =>
    nodes.map((node) =>
      (node.getAttribute('aria-label') || node.textContent || '')
        .replace(/\s+/g, ' ')
        .trim(),
    ),
  );
  return texts.some((t) => re.test(t));
}

/**
 * Picks a choice off one of the job form's menus.
 *
 * Every one of those rows is shut until it is asked — the row says what is
 * chosen, the menu offers the rest — so opening it is part of the flow.
 */
async function pickFrom(page, row, choice) {
  await page.getByRole('button', { name: row }).first().click({
    timeout: 15000,
  });
  await page.waitForTimeout(900);
  // By role, not by text: the app paints to a canvas, so the only text a
  // browser can see is what the semantics tree publishes — and a menu's rows
  // come through as menuitems carrying an aria-label rather than as buttons
  // with text in them.
  await page.getByRole('menuitem', { name: choice, exact: true }).last().click({
    timeout: 15000,
  });
  await page.waitForTimeout(1200);
}

async function press(page, name) {
  await page.getByRole('button', { name, exact: false }).first().click({
    timeout: 15000,
  });
  await page.waitForTimeout(1400);
}

let failures = 0;
function check(label, ok, detail = '') {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? '  → ' + detail : ''}`);
  if (!ok) failures++;
}

(async () => {
  if (!fs.existsSync(path.join(BUILD_DIR, 'index.html'))) {
    console.error(`No build at ${BUILD_DIR}. Run "flutter build web" first.`);
    process.exit(1);
  }

  const server = await serve();
  // CHROMIUM_PATH lets a preinstalled browser be used instead of Playwright's
  // own download, which is how CI images and sandboxes usually ship one.
  const browser = await chromium.launch(
    process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {},
  );

  try {
    // ---- phone: the month view, as it opens -----------------------------
    {
      const { page, errors } = await boot(browser, { width: 430, height: 900 });

      check(
        'the board is behind a login',
        await axContains(page, /Sign in to see the board/),
      );
      check(
        'and a fresh device says how to get in',
        await axContains(page, /Sample logins/),
      );
      await signIn(page);

      const n = await axNames(page);

      check(
        'it opens on the month, with today announced',
        await axContains(page, /, today\. (\d+ jobs?|Nothing on)\./),
      );
      check(
        'the weekday header reads as days, not as letters',
        n.some((x) => /Wednesday/.test(x)) && n.some((x) => /Saturday/.test(x)),
      );
      check(
        'every view is reachable from the switcher',
        [1, 2, 3, 4, 5].every((i) =>
          n.some((x) => new RegExp(`view, ${i} of 5$`).test(x)),
        ),
        n.filter((x) => /view, \d of 5$/.test(x)).join(' / '),
      );
      check(
        'the calendars button is there',
        n.some((x) => /^button:Calendars$/.test(x)),
      );

      // ---- the day view -------------------------------------------------
      await press(page, 'Day view');
      check(
        'a job is announced with its customer and its hours',
        await axContains(
          page,
          /for .+\. \d+(:\d+)? [AP]M – \d+(:\d+)? [AP]M\./,
        ),
      );
      check(
        'no rig is assigned to anybody, and nobody is locked out of one',
        !(await axContains(page, /not your rig|Wrong rig|Assigned rig/)),
      );

      // ---- the switcher stays on the bottom edge ------------------------
      // A phone browser's toolbar makes the page taller than the screen. Left
      // to itself the engine sizes the app from that taller box and the bar is
      // drawn below the visible edge, behind the toolbar. #app plus a
      // ResizeObserver is what stops that; see the note in web/index.html.
      // Widget tests cannot see any of it — it is the host page getting it
      // wrong, not the widgets.
      const switcherBottom = async () => {
        const box = await page
          .getByRole('button', { name: /Day view, 1 of 5/ })
          .first()
          .boundingBox();
        return box ? Math.round(box.y + box.height) : null;
      };
      const appBottom = () =>
        page.evaluate(() =>
          Math.round(
            document.querySelector('#app').getBoundingClientRect().bottom,
          ),
        );
      const setAppHeight = (css) =>
        page.evaluate((h) => {
          document.querySelector('#app').style.height = h;
        }, css);

      const resting = await switcherBottom();
      check(
        'the view switcher sits on the bottom edge',
        resting !== null && (await appBottom()) - resting <= 14,
        `switcher ends at ${resting}, app ends at ${await appBottom()}`,
      );
      check(
        'the page itself never scrolls',
        await page.evaluate(
          () => document.documentElement.scrollHeight <= window.innerHeight + 1,
        ),
      );

      // Slide a browser toolbar in: the visible area shrinks, and the switcher
      // has to come with it rather than sail off the bottom.
      await setAppHeight('calc(100dvh - 96px)');
      await page.waitForTimeout(1200);
      const shrunk = await switcherBottom();
      check(
        'it follows when browser chrome takes space',
        shrunk !== null && shrunk < resting,
        `switcher ends at ${shrunk}, app ends at ${await appBottom()}`,
      );

      await setAppHeight('');
      await page.waitForTimeout(1200);
      check(
        'and goes back when it slides away',
        (await switcherBottom()) === resting,
      );

      // ---- booking a job from the calendar ------------------------------
      // The whole write path in one go: the form opens on the day showing,
      // the job goes through the outbox onto the board, and the calendar
      // draws it. Widget tests cover each step; only this proves the
      // compiled bundle does all of them in a browser.
      await press(page, 'New job');
      await page.keyboard.type('Skyline Ranch');
      await page.waitForTimeout(400);
      // The form will not book work with nothing to load it — the rig is what
      // the job is called, and the ones on offer are the ones the board has
      // already needed.
      await pickFrom(page, /^Rig needed, /, 'Dump trailer 14k');
      await press(page, 'Add');
      check(
        'a job booked in the calendar turns up on it',
        await axContains(page, /Skyline Ranch/),
      );

      await press(page, 'Search');
      await page.keyboard.type('skyline');
      await page.waitForTimeout(900);
      check(
        'and search finds it',
        await axContains(page, /Dump trailer 14k for Skyline Ranch/),
      );
      await press(page, 'Done');

      // ---- reminders ----------------------------------------------------
      // The alert itself is a field on the job and syncs with it. Whether the
      // device can actually raise one is the browser's business: a headless
      // shell has no Notification API at all, and the app says so rather than
      // pretending. So this asserts what the app owns — the alert is stored,
      // and the panel states one of the two truthful answers.
      // On a day that has not happened yet. The form opens a job at the next
      // working hour of whatever day is showing, and once the working day is
      // over that is this morning — an alert already in the past, which the
      // app is right to drop and which would fail this check for a reason
      // that has nothing to do with the app.
      await press(page, 'Next');
      await press(page, 'New job');
      await page.keyboard.type('Kings Valley pickup');
      await page.waitForTimeout(400);
      await pickFrom(page, /^Rig needed, /, 'Dump trailer 14k');
      // The alert row is below the fold of a long form, and a Flutter list
      // does not scroll for the browser's own scrollIntoView.
      await page.mouse.wheel(0, 900);
      await page.waitForTimeout(700);
      // At the time, not a day before: the form opens the job later today, so
      // a day's warning would already have gone by and nothing would be set.
      await pickFrom(page, /^Alert, /, 'At the time');
      await press(page, 'Add');

      const alerted = await page.evaluate(() => {
        const raw = window.localStorage.getItem('flutter.board.v1');
        const board = raw ? JSON.parse(JSON.parse(raw)) : [];
        return board.filter((j) => j.alertMinutes != null).length;
      });
      check(
        'an alert set in the form is stored on the job',
        alerted === 1,
        `${alerted} job(s) carrying an alert`,
      );

      await press(page, 'Calendars');
      check(
        'and the app says plainly what the device will do about it',
        (await axContains(page, /reminder(s)? set\. The next is/)) ||
          (await axContains(page, /turned reminders off/)),
      );
      await page.keyboard.press('Escape');
      await page.waitForTimeout(800);

      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- desktop: the wide month, the year, and a job --------------------
    {
      const { page, errors } = await boot(browser, { width: 1194, height: 834 });
      await signIn(page);

      check(
        'a window with room writes the work into the month cells',
        await axContains(page, /Dump trailer 14k/),
      );

      await press(page, 'Year view');
      let n = await axNames(page);
      check(
        'the year shows every month',
        ['January', 'June', 'December'].every((m) =>
          n.some((x) => new RegExp(`^button:${m}`).test(x)),
        ),
      );

      await press(page, 'List view');
      check(
        'the list is grouped under day headings',
        await axContains(page, /\w+day, \d+ \w+/),
      );
      check(
        'and it holds the work, not empty squares',
        await axContains(page, /for .+\. \d+(:\d+)? [AP]M – /),
      );

      // Open the first job in the list and read its sheet.
      await page
        .locator('flt-semantics[role="button"]')
        .filter({ hasText: /for .+\./ })
        .first()
        .click({ timeout: 15000 });
      await page.waitForTimeout(1400);
      check(
        'a job opens onto its details',
        await axContains(page, /Rig needed/),
      );
      check(
        'the rig is stated, never assigned to a person',
        !(await axContains(page, /Assigned rig|not your rig/)),
      );
      check(
        'and the sheet can be closed again',
        (await page.getByRole('button', { name: 'Close' }).count()) > 0,
      );
      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- reading a job off the calendar, and reaching the world ----------
    // Everything the yard asked for on the card itself: the notes where a
    // driver reads them before setting off, one tap from the month grid into
    // the day, a bar that names the day it is showing, and an address and a
    // number that hand off to the phone rather than being copied out by hand.
    {
      const { page, errors } = await boot(browser, { width: 390, height: 844 });
      await signIn(page);

      check(
        'the notes are on the calendar, not buried in the job',
        await axContains(page, /Gate code 4417#/),
      );

      // One tap on a day, and the day opens. Not two.
      await page
        .locator('flt-semantics[role="button"]')
        // Today's cell specifically: it is the one with work on it, and the
        // job below is opened from the day it lands on.
        .filter({ hasText: /, today\./ })
        .first()
        .click({ timeout: 15000 });
      await page.waitForTimeout(1600);
      check(
        'tapping a day in the month grid opens that day',
        (await page.getByRole('button', { name: 'Day view, 1 of 5' }).count()) >
          0,
      );
      check(
        'and the bar over it names the day, not the month',
        // The title doubles as the way to jump to a date, so it comes through
        // as that button rather than as a node of its own.
        await axContains(page, /^\w{3} \d+ \w{3}\. Go to date/),
      );

      await page
        .getByRole('button', { name: /^Dump trailer 14k for/ })
        .first()
        .click({ timeout: 15000 });
      await page.waitForTimeout(1400);
      check(
        'the address on a job is something you can tap for directions',
        await axContains(page, /^Directions to, /),
      );
      check(
        'and so is the number',
        await axContains(page, /^Call, 541-555/),
      );
      check(
        'dispatch picks who is on it — there is nothing to accept',
        (await axContains(page, /^Who is on this job, /)) &&
          !(await axContains(page, /Accept this job/)),
      );

      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- the office's day sheet, on a desk and on a phone -----------------
    // The paper run-sheet the yard has always kept: a lane per rig, what each
    // job still owes, and who is out on the day. The one screen in the app
    // whose whole job is money, so the level that opens it matters as much as
    // what it says.
    for (const [what, size] of [
      ['a desk', { width: 1194, height: 834 }],
      ['a phone', { width: 390, height: 844 }],
    ]) {
      const { page, errors } = await boot(browser, size);
      await signIn(page);
      await press(page, 'Calendars');
      await press(page, 'Day sheet');

      check(
        `${what} opens the day sheet onto the rigs of the day`,
        await axContains(page, /Dump trailer 14k/),
      );
      check(
        `${what} rules the sheet with what is still owed`,
        await axContains(page, /Still owed/),
      );
      check(
        `${what} carries a job's balance rather than its price`,
        // The gravel delivery is half paid on the demo board.
        await axContains(page, /Owes \$270/),
      );
      check(
        `${what} says how a settled job was paid`,
        await axContains(page, /Paid by Card/),
      );
      check(
        `${what} names who is out on the day`,
        await axContains(page, /Who's working/),
      );

      await press(page, 'The day after');
      check(
        `${what} walks to the next day from the sheet itself`,
        await axContains(page, /Lowboy 25t|Nothing booked/),
      );

      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // A driver has no business on it, and must not be shown the way in.
    {
      const { page, errors } = await boot(browser, { width: 390, height: 844 });
      await signIn(page, 'Employee');
      await press(page, 'Calendars');
      check(
        'a driver is not offered the day sheet at all',
        !(await axContains(page, /Day sheet/)),
      );
      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- the driver's side: work a job that has your name on it -----------
    // The one path nothing else covers end to end. The demo board has
    // HL-4491 on the owner, who drives — which is ordinary in a yard this
    // size and the reason nothing about a job narrows by level. There is no
    // accepting: a job with your name on it is yours.
    {
      const { page, errors } = await boot(browser, { width: 390, height: 844 });
      await signIn(page);
      await press(page, 'Day view, 1 of 5');

      await page
        .getByRole('button', { name: /^Flatbed 20ft for/ })
        .first()
        .click({ timeout: 15000 });
      await page.waitForTimeout(1400);
      check(
        'a job already on you opens onto the panel that runs it',
        (await axContains(page, /Up to/)) &&
          (await axContains(page, /Not started/)),
      );

      await press(page, 'Roll out');
      check(
        'and the button becomes the next step, not the one just taken',
        (await page.getByRole('button', { name: "I'm on site" }).count()) > 0,
      );

      await press(page, "I'm on site");
      check(
        'standing on site, the before photo is asked for',
        await axContains(page, /you are on site/),
      );

      // Two stages on, at the dump, with no photos filed. The close-out is
      // refused before it is pressed rather than after.
      await press(page, 'Loaded up');
      await press(page, 'At the dump');
      check(
        'and the close-out says what is missing before anybody presses it',
        await axContains(page, /Blocked: a before and an after photo/),
      );

      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- a booking made on the website reaches the calendar --------------
    // Both pages share one browser context on purpose: same origin, same
    // storage, which is the whole mechanism. Nothing below this line works if
    // hire.html writes in a shape the app cannot read — and it very nearly
    // did, because shared_preferences stores a string JSON-encoded.
    {
      const context = await browser.newContext({
        viewport: { width: 1194, height: 834 },
        locale: 'en-US',
      });

      const site = await context.newPage();
      await site.goto(`http://127.0.0.1:${PORT}${BASE_PATH}hire.html`, {
        waitUntil: 'load',
        timeout: 60000,
      });
      await site.fill('[name="customer"]', 'Fairbanks Excavating');
      await site.fill('[name="phone"]', '555-0177');
      await site.fill('[name="address"]', '9 Mill Road');
      await site.fill('[name="type"]', 'Equipment move');
      await site.fill('[name="details"]', 'Skid steer behind the shop.');
      await site.click('button[type="submit"]');
      await site.waitForTimeout(400);
      check(
        'the booking form confirms it was sent',
        await site.locator('#done').isVisible(),
      );
      await site.close();

      const app = await context.newPage();
      const appErrors = [];
      app.on('pageerror', (e) => appErrors.push(e.message));
      await app.goto(`http://127.0.0.1:${PORT}${BASE_PATH}`, {
        waitUntil: 'load',
        timeout: 60000,
      });
      await app.waitForFunction(() => !document.getElementById('boot'), {
        timeout: 60000,
      });
      await app.waitForTimeout(1500);
      await app.evaluate(() => {
        const ph = document.querySelector('flt-semantics-placeholder');
        if (!ph) return;
        ph.click();
        ph.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
        ph.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
      });
      await app.waitForTimeout(1200);
      await signIn(app);
      await press(app, 'List view');

      // A booking arrives with no date on it, so the calendar has nowhere to
      // draw it. The list's undated section is where it has to surface — a
      // grid that quietly omits it is a lost job.
      check(
        'a job booked on the website turns up in the calendar',
        await axContains(app, /Fairbanks Excavating/),
      );
      check(
        'and it is held back until somebody prices it',
        await axContains(app, /Not priced yet/i),
      );

      // The same booking must not become a second job on the next launch.
      await app.reload({ waitUntil: 'load' });
      await app.waitForFunction(() => !document.getElementById('boot'), {
        timeout: 60000,
      });
      await app.waitForTimeout(2500);
      const fromWeb = await app.evaluate(() => {
        const raw = window.localStorage.getItem('flutter.board.v1');
        const board = raw ? JSON.parse(JSON.parse(raw)) : [];
        return board.filter((j) => j.bookingId).length;
      });
      check(
        'one booking is still one job after a reload',
        fromWeb === 1,
        `${fromWeb} job(s) carrying a bookingId`,
      );
      check('no page errors', appErrors.length === 0, appErrors.join('; '));

      await context.close();
    }
  } finally {
    await browser.close();
    server.close();
  }

  console.log(
    failures === 0
      ? '\nAll browser checks passed.'
      : `\n${failures} browser check(s) failed.`,
  );
  process.exit(failures === 0 ? 0 : 1);
})();
