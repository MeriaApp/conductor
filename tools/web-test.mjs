#!/usr/bin/env node
// Conductor Web Test Helper — screenshot, DOM, console, click for headless browser testing
import { chromium } from 'playwright';

const [,, command, url, ...rest] = process.argv;
const usage = `Usage:
  web-test.mjs screenshot <url> [output.png]  — capture screenshot
  web-test.mjs html <url>                     — print rendered DOM
  web-test.mjs console <url>                  — capture JS console output
  web-test.mjs click <url> <selector> [output.png] — click element, optionally screenshot after`;

if (!command || !url) { console.error(usage); process.exit(1); }

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });

try {
  if (command === 'console') {
    const logs = [];
    page.on('console', msg => logs.push(`[${msg.type()}] ${msg.text()}`));
    page.on('pageerror', err => logs.push(`[error] ${err.message}`));
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15000 });
    await page.waitForTimeout(2000);
    console.log(logs.join('\n') || '(no console output)');
  } else if (command === 'html') {
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15000 });
    console.log(await page.content());
  } else if (command === 'screenshot') {
    const output = rest[0] || '/tmp/web-test-screenshot.png';
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15000 });
    await page.screenshot({ path: output, fullPage: false });
    console.log(`Screenshot saved: ${output}`);
  } else if (command === 'click') {
    const selector = rest[0];
    const output = rest[1];
    if (!selector) { console.error('click requires a CSS selector'); process.exit(1); }
    await page.goto(url, { waitUntil: 'networkidle', timeout: 15000 });
    await page.click(selector, { timeout: 5000 });
    await page.waitForTimeout(1000);
    if (output) {
      await page.screenshot({ path: output, fullPage: false });
      console.log(`Clicked "${selector}", screenshot saved: ${output}`);
    } else {
      console.log(`Clicked "${selector}"`);
    }
  } else {
    console.error(`Unknown command: ${command}\n${usage}`);
    process.exit(1);
  }
} catch (err) {
  console.error(`Error: ${err.message}`);
  process.exit(1);
} finally {
  await browser.close();
}
