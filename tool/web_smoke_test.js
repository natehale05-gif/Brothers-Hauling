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

// Must match the --base-href the bundle was built with.
const BASE_PATH = process.env.BASE_PATH || '/brothers-hauling/';
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
  const page = await browser.newPage({ viewport });
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
  await page.waitForFunction(() => !document.getElementById('boot'), {
    timeout: 60000,
  });
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

/** Flattens the accessibility tree into `role:name` strings. */
async function axNames(page) {
  const snapshot = await page.accessibility.snapshot();
  const names = [];
  (function walk(node) {
    if (!node) return;
    if (node.name) names.push(`${node.role}:${node.name}`);
    (node.children || []).forEach(walk);
  })(snapshot);
  return names;
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
        'the wide layout offers all four destinations',
        n.filter((x) => /^button:.*tab,? \d of 4$/i.test(x)).length === 4,
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
