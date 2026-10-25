#!/usr/bin/env node
'use strict';
// Real, trusted Chromium touch input: dispatchEvent() and synchronous VM mocks do not
// reproduce the microtask checkpoints between capture and bubble event listeners.
// Runs only against an isolated local fixture/profile, without reading or capturing a user tab.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const vm = require('node:vm');
const { spawn } = require('node:child_process');
const { setTimeout: delay } = require('node:timers/promises');
const ts = require('./lib/deveco-typescript.cjs');
const candidates = [process.env.CHROME_BIN, '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'];
const chrome = candidates.find(value => value && fs.existsSync(value));
assert.ok(chrome, 'Set CHROME_BIN to a local Chromium executable');
const exportsObject = {};
const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/services/web/WebSwipeNavigationScriptService.ets');
vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, { exports: exportsObject });
const scriptService = new exportsObject.WebSwipeNavigationScriptService();
const installScript = scriptService.buildRuntimeScript(true);
const bridgeName = exportsObject.WEB_SWIPE_NAVIGATION_BRIDGE;
const fixture = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<style>html,body {margin:0} main {height:2000px;padding:20px}</style><main id="target">Swipe fixture</main>
<script>
window.requests=[];
window.readyPrompts=[];
window.${bridgeName}={getCapabilities:()=>7,ready:(direction,url)=>{
  window.readyPrompts.push({direction,url});
},navigate:(direction,url)=>{
  window.requests.push({direction,url}); history.go(direction==='back'?-1:1);
}};
history.replaceState({},'', '/a');history.pushState({},'', '/b');
</script><script>${installScript}</script>`;
async function main() {
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'aira-swipe-browser-'));
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }); res.end(fixture);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const browser = spawn(chrome, ['--headless=new', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--disable-component-update', '--disable-sync', '--remote-debugging-pipe',
    `--user-data-dir=${profile}`], { stdio: ['ignore', 'ignore', 'ignore', 'pipe', 'pipe'] });
  let nextId = 1;
  let buffered = '';
  const pending = new Map();
  browser.stdio[4].on('data', chunk => {
    buffered += chunk.toString();
    let index;
    while ((index = buffered.indexOf('\0')) >= 0) {
      const message = JSON.parse(buffered.slice(0, index)); buffered = buffered.slice(index + 1);
      const request = pending.get(message.id);
      if (request) {
        pending.delete(message.id); clearTimeout(request.timeout);
        if (message.error) request.reject(new Error(JSON.stringify(message.error)));
        else request.resolve(message.result);
      }
    }
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = nextId++;
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error(`CDP timeout: ${method}`)); }, 15000);
    pending.set(id, { resolve, reject, timeout });
    browser.stdio[3].write(JSON.stringify({ id, method, params, sessionId }) + '\0');
  });
  try {
    const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
    const call = (method, params) => send(method, params, sessionId);
    const evaluate = async expression => {
      const result = await call('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
      if (result.exceptionDetails) throw new Error(JSON.stringify(result.exceptionDetails));
      return result.result.value;
    };
    await call('Page.enable');
    await call('Emulation.setDeviceMetricsOverride', { width: 400, height: 800, deviceScaleFactor: 1, mobile: true });
    await call('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
    await call('Page.navigate', { url: origin });
    for (let attempt = 0; attempt < 50; attempt++) {
      if (await evaluate('!!window.__airaSwipeNavigation')) break;
      await delay(20);
    }
    assert.equal(await evaluate('!!window.__airaSwipeNavigation'), true, 'fixture runtime installed');
    const touch = (type, x, y) => call('Input.dispatchTouchEvent', { type,
      touchPoints: type === 'touchEnd' || type === 'touchCancel' ? [] : [{ x, y, id: 1 }] });
    async function swipe(startX, endX, startY = 320, endY = 320) {
      const promptsBefore = await evaluate('window.readyPrompts.length');
      await touch('touchStart', startX, startY);
      for (let step = 1; step <= 5; step++) {
        await touch('touchMove', startX + (endX - startX) * step / 5, startY + (endY - startY) * step / 5);
      }
      const hint = await evaluate(`!!document.querySelector('[data-aira-swipe-indicator]')`);
      const ready = await evaluate(`document.querySelector('[data-aira-swipe-indicator]')?.getAttribute('data-aira-swipe-state')==='ready'`);
      const promptsAtRelease = await evaluate('window.readyPrompts.length');
      assert.equal(promptsAtRelease, promptsBefore + (ready ? 1 : 0), 'ready prompt precedes release');
      await touch('touchEnd');
      await delay(80);
      assert.equal(await evaluate('window.readyPrompts.length'), promptsAtRelease, 'release has no haptic');
      return hint;
    }
    const shown = await swipe(120, 260);
    const right = await evaluate('({requests:window.requests,path:location.pathname})');
    console.log('Right swipe:', JSON.stringify({ hintShown: shown, ...right }));
    assert.equal(right.requests.length, 1, 'a real touchend must reach navigation after the arrow is shown');
    assert.equal(right.path, '/a', 'right swipe traverses back');
    await swipe(280, 140);
    assert.equal(await evaluate('location.pathname'), '/b', 'left swipe traverses forward');
    assert.equal(await evaluate('window.requests.length'), 2);
    async function holdAt(distance, shouldCommit) {
      const before = await evaluate('window.requests.length');
      const promptsBefore = await evaluate('window.readyPrompts.length');
      await touch('touchStart', 120, 320);
      await touch('touchMove', 120 + distance, 320);
      await delay(1600);
      // Stationary touch updates must not time out a gesture that the user is still holding.
      await touch('touchMove', 120 + distance, 320);
      const feedback = await evaluate(`(()=>{const e=document.querySelector('[data-aira-swipe-indicator]');return e?{state:e.getAttribute('data-aira-swipe-state'),opacity:Number(getComputedStyle(e).opacity)}:null})()`);
      assert.ok(feedback && feedback.opacity > 0.5, 'indicator remains visible while holding');
      assert.equal(feedback.state, shouldCommit ? 'ready' : 'tracking');
      assert.equal(await evaluate('window.requests.length'), before, 'holding never navigates');
      assert.equal(await evaluate('window.readyPrompts.length'), promptsBefore + (shouldCommit ? 1 : 0), 'hold prompts once at the threshold');
      await touch('touchEnd'); await delay(230);
      assert.equal(await evaluate('window.requests.length'), before + (shouldCommit ? 1 : 0));
      assert.equal(await evaluate('window.readyPrompts.length'), promptsBefore + (shouldCommit ? 1 : 0), 'no second prompt on release');
      assert.equal(await evaluate("document.querySelector('[data-aira-swipe-indicator]')===null"), true, 'exit animation removes its node');
    }
    await holdAt(40, false);
    await holdAt(140, true);
    await swipe(280, 140);
    // A cancelled retreat uses the final distance rather than remembering a crossed threshold.
    const beforeRetreat = await evaluate('window.requests.length');
    await touch('touchStart', 120, 320); await touch('touchMove', 260, 320); await delay(100);
    await touch('touchMove', 140, 320); await delay(100);
    assert.equal(await evaluate("document.querySelector('[data-aira-swipe-indicator]').getAttribute('data-aira-swipe-state')"), 'tracking');
    await touch('touchEnd'); await delay(230);
    assert.equal(await evaluate('window.requests.length'), beforeRetreat);
    for (const markup of [
      '<a href="/clicked" style="display:block;height:800px">Ordinary link</a>',
      '<img alt="Ordinary image" src="data:image/svg+xml,%3Csvg xmlns=%22http://www.w3.org/2000/svg%22 width=%22400%22 height=%22800%22/%3E" style="width:360px;height:800px">',
      '<div style="touch-action:pan-y;height:800px">Vertical scroll container</div>'
    ]) {
      await evaluate(`document.getElementById('target').innerHTML=${JSON.stringify(markup)}`);
      const before = await evaluate('window.requests.length');
      await swipe(120, 260, 320, 332);
      assert.equal(await evaluate('location.pathname'), '/a', 'controls allow a slightly angled back swipe');
      await swipe(280, 140, 320, 308);
      assert.equal(await evaluate('location.pathname'), '/b');
      assert.equal(await evaluate('window.requests.length'), before + 2);
    }
    await evaluate("document.getElementById('target').innerHTML='Swipe fixture'");
    // Match a news list -> article -> Back -> scroll list -> Forward sequence.
    await swipe(120, 260);
    assert.equal(await evaluate('location.pathname'), '/a');
    const count = await evaluate('window.requests.length');
    await swipe(200, 205, 450, 220);
    assert.equal(await evaluate('window.requests.length'), count, 'vertical scrolling is not navigation');
    await delay(500);
    const afterScroll = await call('Page.getNavigationHistory');
    assert.ok(afterScroll.currentIndex < afterScroll.entries.length - 1, 'scrolling preserves forward history');
    await swipe(280, 140, 420, 420);
    assert.equal(await evaluate('location.pathname'), '/b', 'forward still works after scrolling the restored list');
    await evaluate(scriptService.buildRuntimeScript(false));
    await swipe(120, 260);
    assert.equal(await evaluate('window.requests.length'), count + 1, 'disabled runtime stays inactive');
    console.log('Trusted browser touch: threshold prompt before release, hold, retreat, back-scroll-forward, controls and disable passed.');
  } finally {
    const exited = new Promise(resolve => browser.exitCode !== null ? resolve() : browser.once('exit', resolve));
    if (browser.exitCode === null) {
      try { await send('Browser.close'); } catch (_) {}
      await Promise.race([exited, delay(3000)]);
      if (browser.exitCode === null) browser.kill('SIGTERM');
    }
    await exited;
    for (const request of pending.values()) clearTimeout(request.timeout);
    await new Promise(resolve => server.close(resolve));
    await fs.promises.rm(profile, { recursive: true, force: true, maxRetries: 20, retryDelay: 100 });
  }
}
main().catch(error => { console.error(error.message); process.exitCode = 1; });
