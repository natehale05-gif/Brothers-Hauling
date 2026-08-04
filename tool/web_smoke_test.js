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
    // ---- phone, signed in as a driver -----------------------------------
    {
      const { page, errors } = await boot(browser, { width: 430, height: 900 });
      await press(page, 'Sign in as Employee');
      const n = await axNames(page);

      check('the hold control is reachable', n.some((x) => /Hold to volunteer/.test(x)));
      check(
        'a blocked control says why',
        n.some((x) => /Wrong rig for this load/.test(x)),
      );
      check(
        'the payout reads as a phrase, not a bare number',
        n.some((x) => /Your cut, \d+ dollars/.test(x)),
        n.find((x) => /Your cut/.test(x)),
      );
      check(
        'tabs announce their position',
        n.filter((x) => /^button:.*tab,? \d of \d$/i.test(x)).length === 2,
      );
      check(
        'the driver never sees a billed figure',
        !n.some((x) => /Bills at/.test(x)),
      );

      // ---- the bottom tabs stay on the bottom edge ----------------------
      // A phone browser's toolbar makes the page taller than the screen. Left
      // to itself the engine sizes the app from that taller box and the tab
      // bar is drawn below the visible edge, behind the toolbar — reachable
      // only by fighting the page. #app plus a ResizeObserver is what stops
      // that; see the note in web/index.html. Widget tests cannot see any of
      // this, because it is the host page getting it wrong, not the widgets.
      const tabBottom = async () => {
        const box = await page
          .getByRole('button', { name: /tab, 1 of/i })
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

      const resting = await tabBottom();
      check(
        'the bottom tabs sit on the bottom edge',
        resting !== null && Math.abs(resting - (await appBottom())) <= 1,
        `tabs end at ${resting}, app ends at ${await appBottom()}`,
      );
      check(
        'the page itself never scrolls',
        await page.evaluate(
          () => document.documentElement.scrollHeight <= window.innerHeight + 1,
        ),
      );

      // Slide a browser toolbar in: the visible area shrinks, and the tabs
      // have to come with it rather than sail off the bottom.
      await setAppHeight('calc(100dvh - 96px)');
      await page.waitForTimeout(1200);
      const shrunk = await tabBottom();
      check(
        'the tabs follow when browser chrome takes space',
        shrunk !== null &&
          shrunk < resting &&
          Math.abs(shrunk - (await appBottom())) <= 1,
        `tabs end at ${shrunk}, app ends at ${await appBottom()}`,
      );

      await setAppHeight('');
      await page.waitForTimeout(1200);
      check('and go back when it slides away', (await tabBottom()) === resting);

      // Location must resolve one way or the other; a permanent "getting a
      // fix…" is a dead strip.
      await page.waitForTimeout(14000);
      const loc =
        (await axNames(page)).find((x) =>
          /^text:Sharing location with dispatch\./.test(x),
        ) || '';
      check(
        'the location strip resolves to a position',
        loc.length > 0 && !/Getting a fix/.test(loc),
        loc.slice(0, 130),
      );
      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- tablet/desktop, signed in as the owner --------------------------
    {
      const { page, errors } = await boot(browser, { width: 1194, height: 834 });
      await press(page, 'Sign in as Admin');
      let n = await axNames(page);

      check(
        'the week chart is described in words',
        n.some((x) => /Billed, last 7 days\. Monday: \d+ dollars/.test(x)),
      );
      check(
        'the route strip states progress in words',
        n.some((x) => /Route from .* percent complete/.test(x)),
        (n.find((x) => /Route from/.test(x)) || '').slice(0, 110),
      );
      check(
        'the wide layout offers every destination',
        n.filter((x) => /^button:.*tab,? \d of 5$/i.test(x)).length === 5,
      );
      check(
        'the day view is one of them',
        n.some((x) => /^button:.*Day tab,? \d of 5$/i.test(x)),
      );

      await press(page, 'Tracking tab');
      n = await axNames(page);
      check(
        'a driver with the app closed still shows a last ping',
        n.some((x) => /Last ping/.test(x)),
        n.find((x) => /Last ping/.test(x)),
      );

      await press(page, 'Jobs tab');
      await press(page, 'Details and staffing for HL-4471');
      n = await axNames(page);
      check(
        'hazards are announced as hazards',
        n.some((x) => /Hazard: /.test(x)),
      );
      check(
        'dispatch does see the billed figure',
        n.some((x) => /Bills at \d+ dollars/.test(x)),
      );
      check('no page errors', errors.length === 0, errors.join('; '));
      await page.close();
    }

    // ---- a booking made on the website reaches the board -----------------
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
      await press(app, 'Sign in as Admin');
      await press(app, 'Jobs tab');

      const n = await axNames(app);
      check(
        'a job booked on the website turns up on the dispatch board',
        n.some((x) => /Fairbanks Excavating/.test(x)),
        n.find((x) => /Fairbanks/.test(x)),
      );
      check(
        'and it is held back until somebody prices it',
        n.some((x) => /not priced yet/i.test(x)),
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
      check('one booking is still one job after a reload', fromWeb === 1,
        `${fromWeb} job(s) carrying a bookingId`);
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
