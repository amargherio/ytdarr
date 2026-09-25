import { createRequire } from 'node:module';
import { access, readdir, readFile } from 'node:fs/promises';
import { constants } from 'node:fs';
import { resolve, relative, sep } from 'node:path';
import { spawn } from 'node:child_process';
import { chromium } from 'playwright';

const require = createRequire(import.meta.url);
const axeSource = await readFile(require.resolve('axe-core/axe.min.js'), 'utf8');
const siteRoot = resolve(import.meta.dirname, '..');
const distRoot = resolve(siteRoot, 'dist');
const basePath = '/ytdarr/';
const origin = 'http://127.0.0.1:4322';
const siteUrl = new URL(basePath, origin).href;
const axeTags = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa'];
const browserErrors = [];
let activePreview;

function fail(message) {
  throw new Error(message);
}

function wait(milliseconds) {
  return new Promise((resolveWait) => setTimeout(resolveWait, milliseconds));
}

async function exists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function walkHtml(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = await Promise.all(entries.map(async (entry) => {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) return walkHtml(path);
    return entry.isFile() && entry.name.endsWith('.html') ? [path] : [];
  }));
  return paths.flat();
}

function routeFromOutput(path) {
  const output = relative(distRoot, path).split(sep).join('/');
  if (output === '404.html') return null;
  if (output.endsWith('/index.html')) return `${basePath}${output.slice(0, -'index.html'.length)}`;
  if (output === 'index.html') return basePath;
  return `${basePath}${output}`;
}

async function builtRoutes() {
  if (!await exists(distRoot)) fail(`Expected production output under ${distRoot}; run npm run build first.`);
  const routes = (await walkHtml(distRoot)).map(routeFromOutput).filter(Boolean);
  if (!routes.includes(basePath)) fail('The built site is missing the /ytdarr/ landing page.');
  return [...new Set(routes)].sort();
}

function startPreview() {
  const child = spawn(process.execPath, ['node_modules/astro/bin/astro.mjs', 'preview', '--ignore-lock', '--host', '127.0.0.1', '--port', '4322'], {
    cwd: siteRoot,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let output = '';
  child.stdout.on('data', (chunk) => { output += chunk; });
  child.stderr.on('data', (chunk) => { output += chunk; });
  return { child, output: () => output };
}

function assertPreviewAlive() {
  if (activePreview?.child.exitCode !== null) {
    fail(`The audit's Astro preview exited unexpectedly:\n${activePreview.output()}`);
  }
}

async function waitForPreview(preview) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    if (preview.child.exitCode !== null) fail(`Astro preview exited before becoming ready:\n${preview.output()}`);
    try {
      const response = await fetch(siteUrl);
      if (response.ok) {
        await wait(100);
        if (preview.child.exitCode === null) return;
      }
    } catch {
      // The server has not bound its loopback listener yet.
    }
    await wait(200);
  }
  fail(`Timed out waiting for this audit's Astro preview at ${siteUrl}:\n${preview.output()}`);
}

async function stopPreview(preview) {
  if (preview.child.exitCode !== null) return;
  preview.child.kill('SIGTERM');
  await Promise.race([
    new Promise((resolveExit) => preview.child.once('exit', resolveExit)),
    wait(5_000),
  ]);
  if (preview.child.exitCode === null) preview.child.kill('SIGKILL');
}

function isLocal(url) {
  return url.origin === origin;
}

function insideBase(url) {
  return url.pathname === basePath.slice(0, -1) || url.pathname.startsWith(basePath);
}

function browserIssue(kind, message, url = '') {
  browserErrors.push(`${kind}: ${message}${url ? ` (${url})` : ''}`);
}

function attachBrowserDiagnostics(page, { allowPagefindFailure = false, allowed404Path = null } = {}) {
  page.on('pageerror', (error) => browserIssue('page error', error.message));
  page.on('console', (message) => {
    if (message.type() !== 'error') return;
    const location = message.location().url;
    const text = message.text();
    const allowedPagefind = allowPagefindFailure && (
      location.includes('/pagefind/pagefind.js') || text.includes('/pagefind/pagefind.js')
    );
    const allowed404 = allowed404Path !== null && location &&
      new URL(location, origin).pathname === allowed404Path &&
      text === 'Failed to load resource: the server responded with a status of 404 (Not Found)';
    if (!allowedPagefind && !allowed404) browserIssue('console error', text, location);
  });
  page.on('response', (response) => {
    if (!isLocal(new URL(response.url())) || response.status() < 400) return;
    const pathname = new URL(response.url()).pathname;
    const allowedPagefindFailure = allowPagefindFailure && response.url().includes('/pagefind/pagefind.js') && response.status() === 404;
    const allowedExpected404 = allowed404Path === pathname && response.status() === 404;
    if (!allowedPagefindFailure && !allowedExpected404) {
      browserIssue('HTTP failure', `${response.status()} ${response.statusText()}`, response.url());
    }
  });
}

function checkBrowserDiagnostics(context) {
  if (!browserErrors.length) return;
  const messages = browserErrors.splice(0);
  fail(`${context} produced browser failures:\n${messages.join('\n')}`);
}

async function goto(page, pathname, { expectedStatus = 200 } = {}) {
  assertPreviewAlive();
  const response = await page.goto(new URL(pathname, origin).href, { waitUntil: 'networkidle', timeout: 30_000 });
  assertPreviewAlive();
  if (!response) fail(`No HTTP response while opening ${pathname}.`);
  if (expectedStatus === 200 && !response.ok()) fail(`${pathname} returned HTTP ${response.status()}.`);
  if (expectedStatus !== 200 && response.status() !== expectedStatus) fail(`${pathname} returned HTTP ${response.status()}, expected ${expectedStatus}.`);
}

async function pageReferences(page) {
  return page.evaluate(() => {
    const refs = [];
    const add = (kind, value) => { if (value) refs.push({ kind, value }); };
    document.querySelectorAll('a[href], area[href], link[href]').forEach((element) => add(element.tagName.toLowerCase(), element.getAttribute('href')));
    document.querySelectorAll('script[src], img[src], source[src], video[src], audio[src], iframe[src], embed[src], object[data]').forEach((element) => {
      add(element.tagName.toLowerCase(), element.getAttribute('src') ?? element.getAttribute('data'));
    });
    document.querySelectorAll('[srcset]').forEach((element) => {
      for (const candidate of element.getAttribute('srcset').split(',')) add('srcset', candidate.trim().split(/\s+/, 1)[0]);
    });
    const canonical = document.querySelector('link[rel="canonical"]')?.getAttribute('href') ?? null;
    const icon = [...document.querySelectorAll('link[rel]')].some((element) => element.rel.split(/\s+/).includes('icon'));
    return { refs, canonical, icon };
  });
}

async function checkCanonical(page, route) {
  const canonical = await page.evaluate(() => document.querySelector('link[rel="canonical"]')?.href ?? null);
  if (!canonical) fail(`${route} is missing a canonical URL.`);
  const url = new URL(canonical);
  if (url.origin !== 'https://amargherio.github.io' || !insideBase(url)) {
    fail(`${route} has a canonical URL outside the GitHub Pages project base: ${canonical}`);
  }
}

async function crawlRoutes(browser, routes) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  attachBrowserDiagnostics(page);
  const resources = new Map();
  const fragments = new Map();
  let foundIcon = false;

  for (const route of routes) {
    await goto(page, route);
    await checkCanonical(page, route);
    const { refs, icon } = await pageReferences(page);
    foundIcon ||= icon;
    for (const reference of refs) {
      if (/^(?:data|mailto|tel|javascript):/i.test(reference.value)) continue;
      const url = new URL(reference.value, page.url());
      if (!isLocal(url)) continue;
      if (!insideBase(url)) fail(`${route} references a local URL outside /ytdarr/: ${reference.value}`);
      if (url.hash) {
        const key = `${url.origin}${url.pathname}${url.search}#${url.hash.slice(1)}`;
        fragments.set(key, url);
      }
      resources.set(new URL(`${url.pathname}${url.search}`, origin).href, route);
    }
    checkBrowserDiagnostics(`Crawling ${route}`);
  }

  if (!foundIcon) fail('No page exposes a favicon link.');
  for (const [url, sourceRoute] of resources) {
    assertPreviewAlive();
    const response = await page.request.get(url, { timeout: 30_000 });
    assertPreviewAlive();
    if (!response.ok()) fail(`Broken local resource ${url} linked from ${sourceRoute}: HTTP ${response.status()}.`);
  }

  for (const [key, url] of fragments) {
    await goto(page, `${url.pathname}${url.search}`);
    const fragment = decodeURIComponent(url.hash.slice(1));
    const exists = await page.evaluate((id) => document.getElementById(id) !== null, fragment);
    if (!exists) fail(`Broken local fragment ${key}.`);
    checkBrowserDiagnostics(`Checking fragment ${key}`);
  }

  await context.close();
}

async function runAxe(page, label) {
  await page.addScriptTag({ content: axeSource });
  const result = await page.evaluate(async (tags) => axe.run(document, { runOnly: { type: 'tag', values: tags } }), axeTags);
  if (!result.violations.length) return;
  const details = result.violations.map((violation) => {
    const targets = violation.nodes.map((node) => node.target.join(' ')).join(', ');
    return `${violation.id}: ${violation.help} [${targets}]`;
  }).join('\n');
  fail(`axe WCAG violation(s) on ${label}:\n${details}`);
}

async function openDisclosuresAndAudit(page, label) {
  const count = await page.locator('details > summary').count();
  for (let index = 0; index < count; index += 1) {
    const summary = page.locator('details > summary').nth(index);
    if (!await summary.isVisible()) continue;
    const wasOpen = await summary.evaluate((element) => element.parentElement.open);
    if (!wasOpen) {
      await summary.click();
      const opened = await summary.evaluate((element) => element.parentElement.open);
      if (!opened) fail(`Disclosure ${index + 1} did not open on ${label}.`);
    }
    await runAxe(page, `${label}, disclosure ${index + 1} open`);
    if (!wasOpen) await summary.click();
  }
}

async function auditRoutes(browser, routes) {
  const viewports = [
    { label: 'desktop', viewport: { width: 1440, height: 1000 } },
    { label: 'mobile', viewport: { width: 390, height: 844 } },
  ];
  for (const theme of ['light', 'dark']) {
    for (const { label: viewportLabel, viewport } of viewports) {
      const context = await browser.newContext({ viewport, colorScheme: theme });
      await context.addInitScript((activeTheme) => {
        localStorage.setItem('starlight-theme', activeTheme);
      }, theme);
      const page = await context.newPage();
      attachBrowserDiagnostics(page);
      for (const route of routes) {
        await goto(page, route);
        await page.evaluate((activeTheme) => {
          document.documentElement.dataset.theme = activeTheme;
          document.documentElement.style.colorScheme = activeTheme;
        }, theme);
        await runAxe(page, `${route} (${theme}, ${viewportLabel})`);
        if (viewportLabel === 'mobile') {
          const hasPageOverflow = await page.evaluate(() => document.documentElement.scrollWidth > document.documentElement.clientWidth);
          if (hasPageOverflow) fail(`${route} has page-level horizontal overflow at the mobile viewport.`);
        }
        if (route === basePath || route.includes('/docs/')) await openDisclosuresAndAudit(page, `${route} (${theme}, ${viewportLabel})`);
        checkBrowserDiagnostics(`Auditing ${route} (${theme}, ${viewportLabel})`);
      }
      await context.close();
    }
  }
}

async function waitForText(locator, pattern, description) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (pattern.test(await locator.textContent() ?? '')) return;
    await wait(100);
  }
  fail(`Timed out waiting for ${description}.`);
}

async function exerciseSearch(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  attachBrowserDiagnostics(page);
  const searchRoute = `${basePath}search/?q=YTDARR_YOUTUBE_API_KEY_FILE&version=unreleased`;
  await goto(page, searchRoute);
  const status = page.locator('#search-status');
  await waitForText(status, /(?:[1-9]\d* results?|No results|Search unavailable)/, 'search completion');
  const resultText = await status.textContent();
  if (!/[1-9]\d* results?/.test(resultText ?? '') || await page.locator('#search-results a').count() === 0) {
    fail(`The known configuration query did not produce an Unreleased result: ${resultText}`);
  }
  await runAxe(page, 'search result state');

  await page.locator('#search-query').fill('qzxjvpuw95374912870');
  await page.locator('#search-query').press('Enter');
  await waitForText(status, /No results in unreleased\./, 'zero-result search state');
  await runAxe(page, 'search zero-result state');
  checkBrowserDiagnostics('Exercising search results');
  await context.close();

  const blockedContext = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  await blockedContext.route('**/pagefind/pagefind.js', (route) => route.fulfill({ status: 404, contentType: 'text/plain', body: 'Pagefind blocked for audit.' }));
  const blockedPage = await blockedContext.newPage();
  attachBrowserDiagnostics(blockedPage, { allowPagefindFailure: true });
  await goto(blockedPage, searchRoute);
  const blockedStatus = blockedPage.locator('#search-status');
  await waitForText(blockedStatus, /Search unavailable for unreleased\./, 'blocked Pagefind recovery state');
  const recovery = blockedPage.locator('#search-recovery:not([hidden]) a');
  if (await recovery.count() !== 1) fail('Blocked Pagefind recovery does not expose a documentation link.');
  const href = await recovery.getAttribute('href');
  if (new URL(href, blockedPage.url()).pathname !== `${basePath}docs/unreleased/`) {
    fail(`Blocked Pagefind recovery points to the wrong documentation directory: ${href}`);
  }
  await runAxe(blockedPage, 'search Pagefind-error state');
  checkBrowserDiagnostics('Exercising intentionally blocked Pagefind');
  await blockedContext.close();
}

async function exercise404(browser) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const missingPath = `${basePath}site-audit-not-found/`;
  attachBrowserDiagnostics(page, { allowed404Path: missingPath });
  await goto(page, missingPath, { expectedStatus: 404 });
  if (await page.locator('h1').count() !== 1) fail('The custom 404 page does not expose exactly one H1.');
  await runAxe(page, '404 page');
  checkBrowserDiagnostics('Exercising the 404 page');
  await context.close();
}

async function exerciseWithoutJavaScript(browser) {
  const context = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 390, height: 844 } });
  const page = await context.newPage();
  attachBrowserDiagnostics(page);
  await goto(page, basePath);
  if (await page.locator('h1').count() !== 1) fail('The landing page is not readable without JavaScript.');
  await goto(page, `${basePath}docs/unreleased/`);
  if (await page.locator('h1').count() !== 1) fail('The documentation overview is not readable without JavaScript.');
  await goto(page, `${basePath}search/`);
  if (!/Search requires JavaScript\./.test(await page.locator('body').innerText())) {
    fail('The search page does not explain its JavaScript limitation.');
  }
  checkBrowserDiagnostics('Exercising no-JavaScript pages');
  await context.close();
}

const routes = await builtRoutes();
const preview = startPreview();
activePreview = preview;
let browser;
try {
  await waitForPreview(preview);
  browser = await chromium.launch({ headless: true });
  await crawlRoutes(browser, routes);
  await auditRoutes(browser, routes);
  await exerciseSearch(browser);
  await exercise404(browser);
  await exerciseWithoutJavaScript(browser);
  assertPreviewAlive();
  console.log(`Verified ${routes.length} production routes under ${basePath}.`);
} finally {
  await browser?.close();
  await stopPreview(preview);
}
