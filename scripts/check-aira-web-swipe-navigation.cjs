#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
const TouchType = { Down: 0, Up: 1, Move: 2, Cancel: 3 };
let now = 1000;
const haptics = [];
let hapticFailure = '';
const scheduledTimers = new Map();
let nextTimerId = 0;
function advanceTime(ms) {
  const end = now + ms;
  while (true) {
    const next = [...scheduledTimers].filter(([, timer]) => timer.at <= end)
      .sort((a, b) => a[1].at - b[1].at)[0];
    if (!next) break;
    now = next[1].at;
    scheduledTimers.delete(next[0]);
    next[1].callback();
  }
  now = end;
}
const Clock = class extends Date { static now() { return now; } };
function load(relative) {
  const filename = path.resolve(root, relative);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, experimentalDecorators: true }
  }).outputText, {
    exports, TouchType, Date: Clock, Observed: value => value, $r: value => value,
    setTimeout(callback, delay) { const id = ++nextTimerId; scheduledTimers.set(id, { callback, at: now + delay }); return id; },
    clearTimeout(id) { scheduledTimers.delete(id); },
    require(id) {
      if (id === '@ohos.vibrator') return { default: { startVibration(effect, attribute) {
        haptics.push({ effect, attribute });
        if (hapticFailure === 'throw') throw new Error('motor unavailable');
        return hapticFailure === 'reject' ? Promise.reject(new Error('motor unavailable')) : Promise.resolve();
      } } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (id === '@ohos.url') return { default: { URL } };
      if (id.startsWith('@kit.') || id.endsWith('/AppRuntimeContext')) return {};
      return load(path.resolve(path.dirname(filename), id + '.ets'));
    }
  }, { filename });
  return exports;
}
const { WebSwipeNavigationScriptService, WEB_SWIPE_NAVIGATION_BRIDGE } =
  load('services/web/WebSwipeNavigationScriptService.ets');
const { BrowserWebSwipeNavigationCoordinator } = load('core/browser/BrowserWebSwipeNavigationCoordinator.ets');
const scriptService = new WebSwipeNavigationScriptService();
function surface() {
  const listeners = new Map();
  return {
    addEventListener(name, fn, options) {
      if (!listeners.has(name)) listeners.set(name, []);
      listeners.get(name).push({ fn, capture: !!options?.capture });
    },
    removeEventListener(name, fn, capture) {
      listeners.set(name, (listeners.get(name) || []).filter(item => item.fn !== fn || item.capture !== !!capture));
    },
    dispatch(name, event, stopped = false) {
      const entries = listeners.get(name) || [];
      for (const item of entries.filter(item => item.capture)) item.fn(event);
      if (!stopped) for (const item of entries.filter(item => !item.capture)) item.fn(event);
    },
    async dispatchTrusted(name, event, stopped = false) {
      const entries = listeners.get(name) || [];
      for (const item of entries.filter(item => item.capture)) { item.fn(event); await Promise.resolve(); }
      if (!stopped) {
        for (const item of entries.filter(item => !item.capture)) { item.fn(event); await Promise.resolve(); }
      }
    },
    count(name) { return (listeners.get(name) || []).length; }
  };
}
function element(tagName = 'DIV', patch = {}) {
  return { nodeType: 1, tagName, scrollWidth: 200, clientWidth: 200,
    getAttribute() { return ''; }, style: { values: {}, setProperty(name, value) { this.values[name] = value; }, getPropertyValue(name) { return this.values[name]; } }, setAttribute() {},
    remove() { this.removed = true; }, ...patch };
}
function page(options = {}) {
  const calls = [];
  const children = [];
  const timers = new Map();
  const frames = new Map();
  let timerId = 0;
  const document = Object.assign(surface(), { hidden: false,
    documentElement: element('HTML', { appendChild(node) { children.push(node); } }),
    body: element('BODY'), createElement: tag => element(tag) });
  const window = Object.assign(surface(), {
    requestAnimationFrame(callback) { frames.set(++timerId, callback); return timerId; },
    cancelAnimationFrame(id) { frames.delete(id); },
    setTimeout(callback) { timers.set(++timerId, callback); return timerId; },
    clearTimeout(id) { timers.delete(id); }, innerWidth: 400, innerHeight: 800, scrollX: 0, scrollY: 0,
    visualViewport: { scale: 1, height: 800, offsetTop: 0 }, getSelection: () => '',
    getComputedStyle: node => ({ touchAction: 'auto', overflowX: 'visible', ...node.computedStyle }),
    [WEB_SWIPE_NAVIGATION_BRIDGE]: { getCapabilities: () => options.capabilities ?? 7,
      navigate: (...args) => calls.push(args) } });
  window.top = options.iframe ? {} : window;
  const location = { href: 'https://example.test/page', protocol: options.protocol || 'https:' };
  const context = vm.createContext({ window, document, location, Date: Clock });
  const target = options.target || element();
  const touch = (x, y = 100) => ({ identifier: 4, clientX: x, clientY: y });
  const fire = (name, x = 200, y = 100, patch = {}, stopped = false, trustedDispatch = false) => {
    const ended = name === 'touchend' || name === 'touchcancel';
    return window[trustedDispatch ? 'dispatchTrusted' : 'dispatch'](name, { isTrusted: true, defaultPrevented: false,
      touches: ended ? [] : [touch(x, y)], changedTouches: [touch(x, y)], target,
      composedPath: () => [target, ...(options.ancestors || []), document.body, document.documentElement, document, window],
      ...patch }, stopped);
  };
  const install = () => vm.runInContext(scriptService.buildRuntimeScript(true), context);
  install();
  return { window, document, location, context, calls, children, fire, install,
    fireTrusted: (name, x, y, patch, stopped) => fire(name, x, y, patch, stopped, true),
    flushFrames() { for (const [id, callback] of frames) { frames.delete(id); callback(); } },
    flushTimers() { for (const [id, callback] of timers) { timers.delete(id); callback(); } },
    swipe(dx, dy = 0) { fire('touchstart'); fire('touchmove', 200 + dx, 100 + dy); fire('touchend', 200 + dx, 100 + dy); } };
}

test('horizontal touch navigates right/back and left/forward exactly once; short swipes do nothing', () => {
  const p = page();
  p.swipe(110); p.swipe(-110); p.swipe(40);
  assert.deepEqual(p.calls.map(call => call[0]), ['back', 'forward']);
  p.flushTimers();
  assert.ok(p.children.every(child => child.removed));
  p.fire('touchend', 310);
  assert.equal(p.calls.length, 2);
});
test('history capabilities, nested frames and non-web documents suppress navigation', () => {
  for (const capabilities of [0, 1]) { const p = page({ capabilities }); p.swipe(110); p.swipe(-110); assert.equal(p.calls.length, 0); }
  const back = page({ capabilities: 3 }); back.swipe(-110); back.swipe(110);
  assert.deepEqual(back.calls.map(call => call[0]), ['back']);
  const forward = page({ capabilities: 5 }); forward.swipe(110); forward.swipe(-110);
  assert.deepEqual(forward.calls.map(call => call[0]), ['forward']);
  for (const options of [{ iframe: true }, { protocol: 'file:' }]) {
    const p = page(options); p.swipe(110); assert.equal(p.window.count('touchstart'), 0); assert.equal(p.calls.length, 0);
  }
});
test('vertical, diagonal, reversed, pinched, cancelled and synthetic gestures do not navigate', () => {
  for (const change of [
    p => p.fire('touchmove', 205, 120),
    p => p.fire('touchmove', 220, 118),
    p => { p.fire('touchmove', 250); p.fire('touchmove', 160); p.fire('touchend', 160); },
    p => { p.window.visualViewport.scale = 2; },
    p => p.fire('touchmove', 220, 100, { touches: [{}, {}] }),
    p => p.fire('touchcancel'),
    p => p.fire('touchmove', 310, 100, { isTrusted: false }),
    p => p.fire('touchmove', 310, 100, { defaultPrevented: true })
  ]) {
    const p = page(); p.fire('touchstart'); change(p); p.fire('touchend', 310);
    assert.equal(p.calls.length, 0);
  }
});
test('inputs, media, carousels, shadow roots and horizontal scrollers retain their own gestures', () => {
  const targets = ['INPUT', 'TEXTAREA', 'BUTTON', 'SELECT', 'CANVAS', 'VIDEO', 'AUDIO', 'IFRAME']
    .map(tag => element(tag)).concat([
      element('DIV', { isContentEditable: true }), element('DIV', { draggable: true, getAttribute: name => name === 'draggable' ? 'true' : '' }),
      element('DIV', { className: 'swiper-slide' }), element('DIV', { shadowRoot: {} }),
      element('DIV', { getAttribute: () => 'slider' }),
      element('DIV', { computedStyle: { touchAction: 'none' } }),
      element('DIV', { scrollWidth: 400, computedStyle: { overflowX: 'auto' } }),
      element('DIV', { scrollWidth: 400, computedStyle: { overflowX: 'hidden' } })
    ]);
  for (const target of targets) {
    const p = page({ ancestors: [target] }); p.swipe(110); assert.equal(p.calls.length, 0);
  }
});
test('document scroll, selection, fullscreen, visibility and changed URL cancel pending navigation', () => {
  for (const change of [p => { p.window.scrollY = 4; }, p => { p.window.scrollX = 4; },
    p => { p.window.getSelection = () => 'selected'; }, p => { p.document.fullscreenElement = {}; },
    p => { p.document.hidden = true; }, p => { p.location.href += '#other'; }]) {
    const p = page(); p.fire('touchstart'); change(p); p.fire('touchend', 310); assert.equal(p.calls.length, 0);
  }
});
test('runtime is idempotent, can be disabled immediately and resets across BFCache restoration', async () => {
  const p = page(); p.install(); assert.equal(p.window.count('touchstart'), 1);
  p.fire('touchstart'); p.fire('touchmove', 310);
  p.window.dispatch('pagehide', {}); p.window.dispatch('pageshow', {}); p.fire('touchend', 310);
  assert.equal(p.calls.length, 0);
  p.swipe(110); assert.equal(p.calls.length, 1);
  p.fire('touchstart'); p.fire('touchmove', 310);
  vm.runInContext(scriptService.buildRuntimeScript(false), p.context);
  p.fire('touchend', 310); assert.equal(p.calls.length, 1);
  assert.equal(p.window.count('touchstart'), 0); assert.equal(p.window.__airaSwipeNavigation, undefined);
  p.install(); p.swipe(-110); assert.equal(p.calls.length, 2);
  await Promise.resolve();
});
test('page stopping touch-end propagation cannot leave a stuck direction hint', async () => {
  const p = page(); p.fire('touchstart'); p.fire('touchmove', 310);
  p.fire('touchend', 310, 100, {}, true);
  await Promise.resolve();
  p.flushTimers();
  assert.ok(p.children.every(child => child.removed)); assert.equal(p.calls.length, 0);
});
function nativeRuntime() {
  const calls = [];
  let enabled = true;
  let active = 'tab';
  let panel = 'low';
  const controller = { url: 'https://example.test/page', getUrl() { return this.url; }, accessStep: () => true,
    deleteJavaScriptRegister() {}, registerJavaScriptProxy(bridge) { this.bridge = bridge; },
    runJavaScript(script) { this.script = script; return Promise.resolve(''); } };
  let currentController = controller;
  const coordinator = new BrowserWebSwipeNavigationCoordinator({ isEnabled: () => enabled,
    isEligible: tabId => tabId === active, resolvePanelDetent: () => panel, resolveController: () => currentController,
    navigate: direction => calls.push(direction) });
  coordinator.handleControllerAttached('tab');
  return { coordinator, controller, calls, down() { coordinator.handleTouch('tab', { type: TouchType.Down, touches: [{}] }); },
    request(direction = 'back') { controller.bridge.navigate(direction, 'https://example.test/page'); },
    setPanel(value) { panel = value; },
    disable() { enabled = false; }, switchTab() { active = 'other'; }, replaceController() { currentController = {}; } };
}
test('native bridge needs a current physical touch and consumes it exactly once in either touch-end order', () => {
  const n = nativeRuntime(); n.request(); assert.equal(n.calls.length, 0);
  n.down(); n.request(); n.request(); assert.deepEqual(n.calls, ['back']);
  n.down(); n.coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] });
  n.request('forward'); assert.deepEqual(n.calls, ['back', 'forward']);
});
test('native bridge rejects disabled, stale tab, controller, URL, expired, cancelled or multi-touch requests', () => {
  for (const invalidate of [n => n.disable(), n => n.switchTab(), n => n.replaceController(),
    n => { n.controller.url += '#changed'; }, n => n.coordinator.reset(),
    n => n.coordinator.handleTouch('tab', { type: TouchType.Cancel, touches: [] }),
    n => n.coordinator.handleTouch('tab', { type: TouchType.Down, touches: [{}, {}] }),
    n => { n.coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] }); now += 351; },
    n => { n.controller.accessStep = () => false; }
  ]) { const n = nativeRuntime(); n.down(); invalidate(n); n.request(); assert.equal(n.calls.length, 0); }
});
test('settings hot refresh disposes installed runtime and invalidates in-flight touches', () => {
  const n = nativeRuntime(); n.down(); n.disable(); n.coordinator.sync(['tab']); n.request();
  assert.equal(n.calls.length, 0); assert.match(n.controller.script, /dispose/);
  assert.equal(n.controller.bridge.getCapabilities(), 0);
});
test('preference defaults and stored migration stay opt-in; toggling unrelated settings preserves it', () => {
  const { PreferencesRepository, DEFAULT_BROWSER_EXPERIMENT_SETTINGS } = load('data/preferences/PreferencesRepository.ets');
  const { ArkPreferencesStorageAdapter } = load('data/preferences/ArkPreferencesStorageAdapter.ets');
  const { SettingsDetailActionResolver } = load('core/settings/SettingsDetailActionResolver.ets');
  assert.equal(DEFAULT_BROWSER_EXPERIMENT_SETTINGS.swipeNavigationEnabled, false);
  const repository = new PreferencesRepository();
  const adapter = new ArkPreferencesStorageAdapter();
  for (const value of [undefined, false, 'true', 1, true]) {
    const settings = { ...DEFAULT_BROWSER_EXPERIMENT_SETTINGS, swipeNavigationEnabled: value };
    assert.equal(repository.normalizeExperimentSettings(settings).swipeNavigationEnabled, value === true);
    assert.equal(adapter.parseExperimentSettings(JSON.stringify(settings)).swipeNavigationEnabled, value === true);
  }
  const resolver = new SettingsDetailActionResolver();
  const enabled = resolver.buildExperimentSettingsForAction('toggle_swipe_navigation', true, DEFAULT_BROWSER_EXPERIMENT_SETTINGS);
  assert.equal(enabled.swipeNavigationEnabled, true);
  const unrelated = resolver.buildExperimentSettingsForAction('toggle_pull_refresh', false, enabled);
  assert.equal(unrelated.swipeNavigationEnabled, true);
});

test('document recognition dispatches through native history and tolerates a late bridge attachment', () => {
  const n = nativeRuntime();
  const p = page();
  delete p.window[WEB_SWIPE_NAVIGATION_BRIDGE];
  p.swipe(110); assert.equal(n.calls.length, 0);
  p.window[WEB_SWIPE_NAVIGATION_BRIDGE] = n.controller.bridge;
  n.down(); p.swipe(110);
  n.down(); p.swipe(-110);
  assert.deepEqual(n.calls, ['back', 'forward']);
});
test('a background document lifecycle does not cancel the active tab touch', () => {
  const n = nativeRuntime(); n.down();
  n.coordinator.reset('background'); n.coordinator.sync(['background']); n.request();
  assert.deepEqual(n.calls, ['back']);
});

test('trusted touch-end microtask checkpoint does not clear navigation before bubble listeners', async () => {
  const p = page();
  await p.fireTrusted('touchstart'); await p.fireTrusted('touchmove', 310);
  await p.fireTrusted('touchend', 310);
  assert.deepEqual(p.calls.map(call => call[0]), ['back']);
  p.flushTimers(); assert.equal(p.calls.length, 1);
});
test('a stopped end event cleans up on the next task without cancelling the next gesture', async () => {
  const p = page();
  await p.fireTrusted('touchstart'); await p.fireTrusted('touchmove', 310);
  await p.fireTrusted('touchend', 310, 100, {}, true);
  assert.equal(p.calls.length, 0);
  p.flushTimers(); assert.ok(p.children.every(child => child.removed));
  await p.fireTrusted('touchstart'); await p.fireTrusted('touchmove', 90);
  await p.fireTrusted('touchend', 90); p.flushTimers();
  assert.deepEqual(p.calls.map(call => call[0]), ['forward']);
});
test('ordinary links, images and vertical touch-action containers allow horizontal navigation', () => {
  for (const target of [element('A', { draggable: true }), element('IMG', { draggable: true }),
    element('DIV', { computedStyle: { touchAction: 'pan-y' } }),
    element('DIV', { computedStyle: { touchAction: 'pan-y pinch-zoom' } })]) {
    const p = page({ target }); p.swipe(110);
    assert.equal(p.calls.length, 1);
  }
});
test('an initially fitted desktop page is allowed, but a zoomed page retains panning', () => {
  const p = page();
  p.document.documentElement.clientWidth = 980;
  p.document.documentElement.scrollWidth = 980;
  p.window.visualViewport = { width: 980, scale: 400 / 980 };
  p.swipe(110); assert.equal(p.calls.length, 1);
  p.window.visualViewport = { width: 490, scale: 800 / 980 };
  p.swipe(110); assert.equal(p.calls.length, 1);
});

test('holding before and after the threshold keeps the indicator and only release navigates', async () => {
  for (const distance of [40, 120]) {
    const p = page(); await p.fireTrusted('touchstart'); await p.fireTrusted('touchmove', 200 + distance);
    p.flushFrames(); const hint = p.children[p.children.length - 1];
    now += 120000;
    await p.fireTrusted('touchmove', 200 + distance); // stationary touch jitter after a long hold
    p.flushTimers();
    assert.equal(hint.removed, undefined); assert.equal(p.calls.length, 0);
    await p.fireTrusted('touchend', 200 + distance);
    assert.equal(p.calls.length, distance >= 88 ? 1 : 0);
    assert.equal(hint.removed, undefined, 'release animates instead of abruptly removing the circle');
    p.flushTimers(); assert.equal(hint.removed, true);
  }
});
test('dragging back below threshold keeps feedback until release and cancels navigation', () => {
  const p = page(); p.fire('touchstart'); p.fire('touchmove', 340); p.flushFrames();
  const hint = p.children[p.children.length - 1];
  p.fire('touchmove', 220); assert.equal(hint.removed, undefined);
  p.fire('touchmove', 200); assert.equal(hint.removed, undefined);
  p.fire('touchend', 200); p.flushTimers(); assert.equal(p.calls.length, 0);
  assert.equal(hint.removed, true);
});
test('holding native contact does not expire; idempotent runtime sync preserves that contact', () => {
  const n = nativeRuntime(); n.down(); now += 120000;
  n.coordinator.sync(['tab']); n.request(); assert.deepEqual(n.calls, ['back']);
  const released = nativeRuntime(); released.down(); now += 120000;
  released.coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] });
  released.request('forward'); assert.deepEqual(released.calls, ['forward']);
});
test('toolbar tucked away after reading does not block ArkWeb forward; an expanded panel still does', () => {
  const n = nativeRuntime();
  n.controller.accessBackward = () => false; n.controller.accessForward = () => true;
  n.controller.accessStep = () => { throw new Error('documented directional query should be used'); };
  n.setPanel('peek'); assert.equal(n.controller.bridge.getCapabilities(), 5);
  n.down(); n.request('forward'); assert.deepEqual(n.calls, ['forward']);
  n.setPanel('middle'); assert.equal(n.controller.bridge.getCapabilities(), 0);
  n.down(); n.request('forward'); assert.deepEqual(n.calls, ['forward']);
});

test('gesture history commands reach ArkWeb backward/forward and do not replace history with loadUrl', () => {
  const hapticCount = haptics.length;
  const { BrowserWebComponentController } = load('core/web/BrowserWebComponentController.ets');
  const { BrowserWebHistoryCommandRuntimeCoordinator } = load('core/browser/BrowserWebHistoryCommandRuntimeCoordinator.ets');
  const entries = ['https://news.test/list', 'https://news.test/article'];
  let index = 1;
  const issued = [];
  const controller = {
    accessBackward: () => index > 0, accessForward: () => index < entries.length - 1,
    backward() { index--; issued.push('backward'); }, forward() { index++; issued.push('forward'); },
    getUrl: () => entries[index],
    loadUrl() { assert.fail('history navigation must not reload a URL'); },
    clearHistory() { assert.fail('reading must not clear history'); },
    deleteJavaScriptRegister() {}, registerJavaScriptProxy(bridge) { this.bridge = bridge; }
  };
  const component = new BrowserWebComponentController('tab');
  const componentHost = { resolveWebController: () => controller, isWebControllerAttached: () => true,
    recordRuntimeEvent() {} };
  const result = action => {
    assert.equal(component[action](componentHost).reason, 'issued');
    return { status: 'native_issued' };
  };
  const commands = new BrowserWebHistoryCommandRuntimeCoordinator({ webTabsController: {
    goActivePageBackward: () => result('backward'), goActivePageForward: () => result('forward')
  } }, { resolveActiveTabId: () => 'tab' });
  let panel = 'low';
  const coordinator = new BrowserWebSwipeNavigationCoordinator({ isEnabled: () => true,
    isEligible: () => true, resolvePanelDetent: () => panel, resolveController: () => controller,
    navigate: direction => commands.handleSwipeNavigate(direction) });
  coordinator.handleControllerAttached('tab');
  const release = direction => {
    coordinator.handleTouch('tab', { type: TouchType.Down, touches: [{}] });
    const before = haptics.length;
    const indexBefore = index;
    controller.bridge.ready(direction, controller.getUrl());
    controller.bridge.ready(direction, controller.getUrl());
    assert.equal(haptics.length, before + 1, 'threshold prompts release once while still holding');
    assert.equal(index, indexBefore, 'the ready prompt must not navigate');
    coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] });
    controller.bridge.navigate(direction, controller.getUrl());
    assert.equal(haptics.length, before + 1, 'release must not vibrate again');
  };
  release('back'); assert.equal(index, 0);
  // Reading/scrolling can tuck away chrome; it does not add or erase a history entry.
  panel = 'peek'; now += 10000;
  assert.equal(controller.bridge.getCapabilities(), 5);
  release('forward'); assert.equal(index, 1);
  assert.deepEqual(issued, ['backward', 'forward']);
  assert.equal(entries.length, 2);
  assert.equal(haptics.length, hapticCount + 2, 'one ready haptic per gesture');
});

test('history command dispatch never vibrates, including successful swipe releases and toolbar commands', () => {
  const { BrowserWebHistoryCommandRuntimeCoordinator } = load('core/browser/BrowserWebHistoryCommandRuntimeCoordinator.ets');
  let status = 'native_issued';
  const commands = new BrowserWebHistoryCommandRuntimeCoordinator({ webTabsController: {
    goActivePageBackward: () => ({ status }), goActivePageForward: () => ({ status })
  }, quickSearchSwitchingCoordinator: { handleNavigationCancelled() {} } }, { resolveActiveTabId: () => 'tab' });
  const before = haptics.length;
  for (status of ['unavailable', 'failed', 'loading_cancelled', 'transient_consumed']) {
    commands.handleSwipeNavigate('back'); commands.handleSwipeNavigate('forward');
  }
  assert.equal(haptics.length, before);
  status = 'native_issued';
  commands.handleToolbarNavigateBack(); commands.handleToolbarNavigateForward();
  assert.equal(haptics.length, before);
  commands.handleSwipeNavigate('back'); commands.handleSwipeNavigate('forward');
  assert.equal(haptics.length, before);
});

test('motor errors do not consume the gesture, repeat the prompt or prevent release navigation', async () => {
  try {
    for (hapticFailure of ['throw', 'reject']) {
      const n = nativeRuntime(); n.down();
      const before = haptics.length;
      assert.doesNotThrow(() => n.controller.bridge.ready('back', n.controller.getUrl()));
      n.controller.bridge.ready('back', n.controller.getUrl());
      assert.equal(haptics.length, before + 1);
      n.request(); assert.deepEqual(n.calls, ['back']);
      await Promise.resolve();
    }
  } finally { hapticFailure = ''; }
});

test('both directions vibrate on reaching the threshold before release, once even through hold and retreat', async () => {
  for (const sign of [1, -1]) {
    const n = nativeRuntime(); const p = page();
    p.window[WEB_SWIPE_NAVIGATION_BRIDGE] = n.controller.bridge;
    const before = haptics.length;
    n.down(); await p.fireTrusted('touchstart');
    await p.fireTrusted('touchmove', 200 + sign * 87);
    assert.equal(haptics.length, before); assert.equal(n.calls.length, 0);
    await p.fireTrusted('touchmove', 200 + sign * 88);
    assert.equal(haptics.length, before + 1); assert.equal(n.calls.length, 0);
    for (const distance of [120, 88, 87, 90, 40, 120]) {
      now += 1000; await p.fireTrusted('touchmove', 200 + sign * distance);
      assert.equal(haptics.length, before + 1); assert.equal(n.calls.length, 0);
    }
    n.coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] });
    await p.fireTrusted('touchend', 200 + sign * 120);
    assert.equal(haptics.length, before + 1);
    assert.deepEqual(n.calls, [sign === 1 ? 'back' : 'forward']);
    assert.equal(haptics[before].attribute.usage, 'touch');
    assert.equal(haptics[before].effect.duration, 18);
  }
});

test('retreat after the prompt can still cancel; the next gesture gets a new ready prompt', () => {
  const n = nativeRuntime(); const p = page(); p.window[WEB_SWIPE_NAVIGATION_BRIDGE] = n.controller.bridge;
  const before = haptics.length;
  n.down(); p.fire('touchstart'); p.fire('touchmove', 310);
  assert.equal(haptics.length, before + 1);
  p.fire('touchmove', 240); p.fire('touchend', 240);
  assert.equal(n.calls.length, 0); assert.equal(haptics.length, before + 1);
  n.down(); p.swipe(-110);
  assert.equal(haptics.length, before + 2); assert.deepEqual(n.calls, ['forward']);
});

test('a final touchend distance never produces a late ready prompt', () => {
  const n = nativeRuntime(); const p = page(); p.window[WEB_SWIPE_NAVIGATION_BRIDGE] = n.controller.bridge;
  const before = haptics.length;
  n.down(); p.fire('touchstart'); p.fire('touchmove', 240); p.fire('touchend', 310);
  assert.equal(haptics.length, before); assert.deepEqual(n.calls, ['back']);
});

test('native ready feedback rejects missing/released touches and stale or ineligible documents', () => {
  const before = haptics.length;
  const untouched = nativeRuntime(); untouched.controller.bridge.ready('back', untouched.controller.getUrl());
  for (const invalidate of [n => n.disable(), n => n.switchTab(), n => n.replaceController(),
    n => { n.controller.url += '#changed'; }, n => n.coordinator.reset(), n => n.setPanel('middle'),
    n => n.coordinator.handleTouch('tab', { type: TouchType.Cancel, touches: [] }),
    n => n.coordinator.handleTouch('tab', { type: TouchType.Up, touches: [] }),
    n => n.coordinator.handleTouch('tab', { type: TouchType.Move, touches: [{}, {}] }),
    n => { n.controller.accessStep = () => false; }
  ]) {
    const n = nativeRuntime(); n.down(); invalidate(n);
    n.controller.bridge.ready('back', 'https://example.test/page');
  }
  assert.equal(haptics.length, before);
});

function loadingProgress() {
  const { BrowserLoadingProgressCoordinator } = load('core/browser/BrowserLoadingProgressCoordinator.ets');
  const { BrowserWebLoadingProgressBarPresentationViewModel } = load('core/browser/BrowserWebLoadingProgressBarPresentationViewModel.ets');
  const coordinator = new BrowserLoadingProgressCoordinator();
  const presentation = new BrowserWebLoadingProgressBarPresentationViewModel();
  let state = coordinator.createState();
  const applied = [];
  const host = { getLoadingProgressState: () => state,
    applyLoadingProgressState(value) { state = value; applied.push(value); } };
  return { coordinator, host, applied, state: () => state,
    visible: () => presentation.buildState({ loadingProgressState: state, showHomePage: false, showTabsSheet: false }).visible,
    begin: () => coordinator.beginLoadAndSchedule(true, host, now, 120) };
}

test('fast history restoration completes without a progress flash, including repeated completion events', () => {
  const p = loadingProgress(); p.begin();
  assert.equal(p.visible(), false);
  advanceTime(50); p.coordinator.applyRealProgressAndSchedule(80, p.host);
  assert.equal(p.visible(), false);
  advanceTime(30); p.coordinator.finishLoadAndSchedule(p.host);
  p.coordinator.applyRealProgressAndSchedule(100, p.host);
  advanceTime(200);
  p.coordinator.applyRealProgressAndSchedule(100, p.host);
  advanceTime(200);
  assert.ok(p.applied.every(state => !state.visualVisible));
  assert.equal(p.state().visualState, 'idle');
});

test('a real slow load reveals progress even at the estimate cap and completes normally', () => {
  const p = loadingProgress(); p.begin();
  p.coordinator.applyRealProgressAndSchedule(95, p.host);
  advanceTime(100); assert.equal(p.visible(), false);
  advanceTime(50); assert.equal(p.visible(), true);
  assert.ok(p.state().displayProgress >= 95);
  p.coordinator.finishLoadAndSchedule(p.host);
  assert.equal(p.visible(), true); assert.equal(p.state().displayProgress, 100);
  advanceTime(100); assert.equal(p.visible(), false);
});

test('explicit navigation and manual refresh keep their immediate progress feedback', () => {
  const p = loadingProgress(); p.coordinator.beginNavigationIntentAndSchedule(p.host);
  assert.equal(p.visible(), true);
  p.begin(); assert.equal(p.visible(), true);
  p.coordinator.resetForNonWebSurfaceAndSchedule(p.host);
});

test('tab changes, superseding navigation and errors cannot reveal an old deferred progress bar', () => {
  const p = loadingProgress(); p.begin(); advanceTime(50);
  p.coordinator.resetForNonWebSurfaceAndSchedule(p.host);
  advanceTime(300); assert.equal(p.visible(), false);
  p.begin(); advanceTime(50); p.begin();
  advanceTime(100); assert.equal(p.visible(), false);
  advanceTime(50); assert.equal(p.visible(), true);
  p.coordinator.resetForNonWebSurfaceAndSchedule(p.host);
  p.begin(); p.coordinator.applyErrorAndSchedule(p.host);
  assert.equal(p.visible(), true); assert.equal(p.state().visualState, 'error');
  advanceTime(200); assert.equal(p.visible(), false);
});

test('a completion without any load start does not create a progress bar', () => {
  const p = loadingProgress(); p.coordinator.finishLoadAndSchedule(p.host);
  assert.equal(p.visible(), false);
  advanceTime(200); assert.equal(p.visible(), false);
});
