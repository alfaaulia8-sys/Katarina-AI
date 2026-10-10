'use strict';
/* Local-only Chrome Android + Playwright connectivity probe.
 * NO navigation, clicks, screenshots, forms, bid submissions, or credentials.
 * Outputs only status booleans and tab counts; never URLs/titles/cookies.
 */
const timeoutMs = 10000;
async function main() {
  const report = {
    protocol: 'adb-forwarded-local-cdp',
    cdp_available: false,
    playwright_installed: false,
    playwright_connected: false,
    open_tabs: null,
    detail: 'not_connected'
  };
  try {
    const r = await fetch('http://127.0.0.1:9222/json/version', {
      signal: AbortSignal.timeout(3500)
    });
    if (!r.ok) throw new Error('CDP_HTTP_' + r.status);
    const v = await r.json();
    report.cdp_available = Boolean(v.Browser || v.webSocketDebuggerUrl);
  } catch (_) {
    report.detail = 'adb_forward_or_chrome_not_ready';
    console.log(JSON.stringify(report));
    process.exitCode = 2;
    return;
  }

  let chromium;
  try {
    chromium = require('playwright-core').chromium;
    report.playwright_installed = true;
  } catch (_) {
    report.detail = 'run_npm_install_in_agent_android_browser';
    console.log(JSON.stringify(report));
    process.exitCode = 3;
    return;
  }

  let browser;
  try {
    browser = await chromium.connectOverCDP('http://127.0.0.1:9222', {timeout:timeoutMs});
    const pages = browser.contexts().flatMap(c => c.pages());
    report.playwright_connected = true;
    report.open_tabs = pages.length;
    report.detail = 'ready_read_only_probe';
  } catch (_) {
    report.detail = 'cdp_connected_but_playwright_android_not_supported_on_this_device';
    process.exitCode = 4;
  } finally {
    // Disconnect local automation; do NOT close Chrome on the user's phone.
    if (browser) await browser.close().catch(() => {});
  }
  console.log(JSON.stringify(report));
}
main().catch(() => {
  console.log(JSON.stringify({
    cdp_available:false,playwright_connected:false,
    detail:'unexpected_local_probe_error'
  }));
  process.exitCode=1;
});
