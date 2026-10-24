// Run the production discovery script against a deterministic DOM/ArkWeb bridge boundary.
// No browser, screen capture or additional package is needed for these timing and queue contracts.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/services/adblock/AdBlockCosmeticDiscoveryRuntimeScriptService.ets');
const mod = { exports: {} };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
}).outputText, { module: mod, exports: mod.exports }, { filename });
const service = new mod.exports.AdBlockCosmeticDiscoveryRuntimeScriptService();
const item = service.buildDocumentStartScriptItem();

class Element {
  constructor(tag = 'div', classes = [], id = '') {
    this.nodeType = 1;
    this.tagName = tag.toUpperCase();
    this.classes = classes;
    this.id = id;
    this.children = [];
    this.parentNode = null;
    this.textContent = '';
  }
  get classList() { return { length: this.classes.length, item: i => this.classes[i] }; }
  get isConnected() { return this.tagName === 'HTML' || !!this.parentNode?.isConnected; }
  setAttribute(name, value) { if (name === 'id') this.id = value; }
  getAttribute(name) { return name === 'id' ? this.id : name === 'class' ? this.classes.join(' ') : null; }
  appendChild(node) {
    if (node.parentNode) node.parentNode.removeChild(node);
    node.parentNode = this;
    this.children.push(node);
    return node;
  }
  removeChild(node) { this.children.splice(this.children.indexOf(node), 1); node.parentNode = null; }
}

function fixture(options = {}) {
  const html = new Element('html');
  const timers = new Map();
  const listeners = new Map();
  const observers = [];
  const calls = [];
  let now = 100;
  let nextTimer = 0;
  let visited = 0;
  function descendants(root) { return root.children.flatMap(child => [child, ...descendants(child)]); }
  const document = {
    documentElement: html, head: null,
    createElement: tag => new Element(tag),
    getElementById: id => [html, ...descendants(html)].find(node => node.id === id) ?? null,
    createTreeWalker(root) {
      let current = root;
      return { nextNode() {
        const nodes = [root, ...descendants(root)];
        current = nodes[nodes.indexOf(current) + 1] ?? null;
        if (current) visited += 1;
        return current;
      } };
    }
  };
  const context = {
    document, location: new URL(options.url ?? 'https://destination.example/article'), URL,
    Date: { now: () => now }, NodeFilter: { SHOW_ELEMENT: 1 },
    setTimeout(callback, delay = 0) { const id = ++nextTimer; timers.set(id, { callback, due: now + delay }); return id; },
    clearTimeout(id) { timers.delete(id); },
    addEventListener(name, callback) {
      if (!listeners.has(name)) listeners.set(name, new Set());
      listeners.get(name).add(callback);
    },
    removeEventListener(name, callback) { listeners.get(name)?.delete(callback); },
    MutationObserver: class {
      constructor(callback) { this.callback = callback; this.active = false; observers.push(this); }
      observe(_root, config) { this.active = true; this.config = config; }
      disconnect() { this.active = false; }
    }
  };
  context.window = context;
  context.top = options.subframe ? {} : context;
  const bridge = { adBlockCosmeticQuery(payload) {
    const request = JSON.parse(payload);
    calls.push(request);
    if (options.respond) return JSON.stringify(options.respond(request, calls.length, context));
    return JSON.stringify({
      ready: true, enabled: true, pageUrl: context.location.href,
      cssSelectors: request.classes.concat(request.ids).map(token => '.hide-' + token),
      injectedScript: ''
    });
  } };
  if (!options.missingBridge) context.__airaUserScriptNativeBridge = bridge;
  const sandbox = vm.createContext(context);
  function boot() { vm.runInContext(item.script, sandbox); }
  function fire(records) { for (const observer of observers.filter(value => value.active)) observer.callback(records); }
  function mutate(node, kind = 'childList') {
    fire([kind === 'attributes' ? { type: kind, target: node, attributeName: 'class' } :
      { type: kind, target: node.parentNode ?? html, addedNodes: [node], removedNodes: [] }]);
  }
  function next() {
    const [id, timer] = [...timers].sort((a, b) => a[1].due - b[1].due)[0] ?? [];
    if (!timer) return false;
    timers.delete(id);
    now = Math.max(now, timer.due);
    timer.callback();
    return true;
  }
  function drain() { let count = 0; while (next()) assert.ok(++count < 1000, 'timer loop must be finite'); }
  function event(name, persisted = true) {
    for (const callback of [...(listeners.get(name) ?? [])]) callback({ type: name, persisted });
  }
  return {
    context, html, bridge, calls, timers, observers, boot, mutate, fire, next, drain, event,
    style: () => document.getElementById('aira-adblock-discovered-style'),
    active: () => observers.filter(value => value.active).length,
    visited: () => visited,
    advance: () => { now += 20; }
  };
}

test('document-start queries the actual destination immediately and installs CSS before head exists', () => {
  assert.deepEqual(Array.from(item.scriptRules), ['*']);
  const f = fixture({ respond: (_request, _count, context) => ({
    ready: true, enabled: true, pageUrl: context.location.href, cssSelectors: ['.destination-ad'],
    injectedScript: 'window.scriptletRuns = (window.scriptletRuns || 0) + 1;'
  }) });
  f.boot();
  assert.match(f.style().textContent, /\.destination-ad\{display:none!important/);
  assert.deepEqual(f.calls[0], { classes: [], ids: [], includeScriptlets: true });
  assert.equal(f.context.scriptletRuns, 1);
  assert.equal(f.context.__airaAdBlockRustScriptletsInstalled, true);
  assert.equal(f.active(), 1);
});

test('new classes and ids are queried in the first mutation pass and confirmed tokens are not repeated', () => {
  const f = fixture(); f.boot(); f.drain();
  const node = f.html.appendChild(new Element('div', ['new-ad'], 'ad-id'));
  f.mutate(node);
  assert.match(f.style().textContent, /hide-new-ad/);
  assert.match(f.style().textContent, /hide-ad-id/);
  const count = f.calls.length;
  f.advance(); f.mutate(node, 'attributes'); f.drain();
  assert.equal(f.calls.length, count);
  node.classes.push('changed-ad');
  f.advance(); f.mutate(node, 'attributes');
  assert.match(f.style().textContent, /hide-changed-ad/);
  assert.ok(f.observers[0].config.subtree);
  assert.deepEqual(Array.from(f.observers[0].config.attributeFilter), ['class', 'id']);
});

test('large inserted trees yield between bounded scans and bridge batches', () => {
  const f = fixture(); f.boot(); f.drain();
  const container = f.html.appendChild(new Element());
  for (let i = 0; i < 1400; i += 1) container.appendChild(new Element('div', ['slot' + i], 'id' + i));
  let before = f.visited();
  f.mutate(container);
  assert.ok(f.visited() - before <= 600);
  assert.ok(f.timers.size > 0);
  while (f.timers.size > 0) {
    before = f.visited(); f.next(); assert.ok(f.visited() - before <= 600);
  }
  assert.match(f.style().textContent, /hide-slot1399/);
  for (const call of f.calls) assert.ok(call.classes.length <= 128 && call.ids.length <= 128);
});

test('failed candidate batches remain pending and are retried before being marked seen', () => {
  let failed = false;
  const f = fixture({ respond: (request, _count, context) => {
    if (request.classes.includes('retry-ad') && !failed) { failed = true; return { ready: false }; }
    return { ready: true, enabled: true, pageUrl: context.location.href,
      cssSelectors: request.classes.map(token => '.hide-' + token), injectedScript: '' };
  } });
  f.boot(); f.drain();
  const node = f.html.appendChild(new Element('div', ['retry-ad']));
  f.mutate(node);
  assert.equal(f.style(), null);
  f.drain();
  assert.match(f.style().textContent, /hide-retry-ad/);
  assert.equal(f.calls.filter(call => call.classes.includes('retry-ad')).length, 2);
});

test('mutation storms collapse into a bounded root walk without losing late candidates', () => {
  const f = fixture(); f.boot(); f.drain();
  const nodes = [];
  for (let i = 0; i < 2000; i += 1) nodes.push(f.html.appendChild(new Element('div', ['storm' + i])));
  const before = f.visited();
  f.fire([{ type: 'childList', target: f.html, addedNodes: nodes, removedNodes: [] }]);
  assert.ok(f.visited() - before <= 600);
  f.drain();
  assert.match(f.style().textContent, /hide-storm1999/);
  assert.equal(f.calls.flatMap(call => call.classes).length, 2000);
});

test('missing bridges and unready engines retry finitely, and a later bootstrap refreshes', () => {
  const missing = fixture({ missingBridge: true }); missing.boot();
  missing.context.__airaUserScriptNativeBridge = missing.bridge;
  missing.drain(); assert.equal(missing.active(), 1);
  let ready = false;
  const f = fixture({ respond: (_request, _count, context) => ({
    ready, enabled: true, pageUrl: context.location.href, cssSelectors: ['.recovered'], injectedScript: ''
  }) });
  f.boot(); f.drain();
  assert.ok(f.calls.length > 1 && f.calls.length <= 10);
  assert.equal(f.timers.size, 0);
  ready = true; f.boot(); f.drain();
  assert.match(f.style().textContent, /recovered/);
  assert.equal(f.active(), 1);
});

test('stale URL replies are rejected, fragment differences are accepted, and SPA mutations reset candidates', () => {
  let stale = true;
  const f = fixture({ respond: (request, _count, context) => ({
    ready: true, enabled: true,
    pageUrl: stale ? 'https://previous.example/article' : context.location.href + '#fragment',
    cssSelectors: request.classes.length ? ['.rule-' + new URL(context.location.href).pathname.slice(1)] : [],
    injectedScript: ''
  }) });
  f.boot(); assert.equal(f.style(), null);
  stale = false; f.drain();
  const node = f.html.appendChild(new Element('div', ['same-token']));
  f.mutate(node); f.drain(); assert.match(f.style().textContent, /rule-article/);
  f.context.location = new URL('https://destination.example/next');
  f.advance(); f.mutate(node, 'attributes'); f.drain();
  assert.match(f.style().textContent, /rule-next/);
  assert.doesNotMatch(f.style().textContent, /rule-article/);
  assert.equal(f.calls.filter(call => call.classes.includes('same-token')).length, 2);
});

test('disabled policy removes its style and observer; refresh can enable it again', () => {
  let enabled = true;
  const f = fixture({ respond: (_request, _count, context) => ({
    ready: true, enabled, pageUrl: context.location.href, cssSelectors: ['.ad'], injectedScript: ''
  }) });
  f.boot(); f.drain(); enabled = false; f.boot();
  assert.equal(f.style(), null); assert.equal(f.active(), 0); assert.equal(f.timers.size, 0);
  enabled = true; f.boot(); f.drain();
  assert.ok(f.style()); assert.equal(f.active(), 1);
});

test('pagehide pauses work, BFCache pageshow refreshes, and stop releases all page work', () => {
  const f = fixture(); f.boot(); f.drain();
  const callsBeforeShow = f.calls.length;
  f.event('pageshow', false); f.drain();
  assert.equal(f.calls.length, callsBeforeShow, 'ordinary pageshow must not add another full DOM scan');
  const node = f.html.appendChild(new Element('div', ['ad']));
  f.mutate(node); f.drain();
  f.event('pagehide'); assert.equal(f.active(), 0); assert.equal(f.timers.size, 0);
  f.event('pageshow'); f.drain(); assert.equal(f.active(), 1); assert.ok(f.style());
  f.context.__airaAdBlockDiscoveryRuntime.stop();
  assert.equal(f.active(), 0); assert.equal(f.timers.size, 0); assert.equal(f.style(), null);
  f.event('pageshow'); assert.equal(f.active(), 0);
});

test('CSP eval failure does not claim scriptlet installation or prevent cosmetic CSS', () => {
  const f = fixture({ respond: (_request, _count, context) => ({
    ready: true, enabled: true, pageUrl: context.location.href, cssSelectors: ['.ad'],
    injectedScript: 'window.scriptletRuns = (window.scriptletRuns || 0) + 1;'
  }) });
  f.context.eval = () => { throw new EvalError('unsafe-eval blocked'); };
  f.boot(); assert.ok(f.style()); assert.notEqual(f.context.__airaAdBlockRustScriptletsInstalled, true);
  delete f.context.eval; f.boot();
  assert.equal(f.context.scriptletRuns, 1);
  f.boot(); assert.equal(f.context.scriptletRuns, 1);
});

test('subframes and non-HTTP documents never query the native bridge', () => {
  for (const options of [{ subframe: true }, { url: 'file:///tmp/page.html' }, { url: 'about:blank' }]) {
    const f = fixture(options); f.boot(); f.drain(); assert.equal(f.calls.length, 0); assert.equal(f.active(), 0);
  }
});

test('candidate and stylesheet budgets stay bounded while invalid long tokens are ignored', () => {
  const f = fixture({ respond: (_request, _count, context) => ({
    ready: true, enabled: true, pageUrl: context.location.href,
    cssSelectors: Array.from({ length: 5000 }, (_, i) => '.ad-' + i + '-'.repeat(100)), injectedScript: ''
  }) });
  const tokens = Array.from({ length: 8300 }, (_, i) => 'c' + i);
  tokens.unshift('x'.repeat(257));
  f.html.appendChild(new Element('div', tokens));
  f.boot(); f.drain();
  const requested = f.calls.flatMap(call => call.classes);
  assert.equal(new Set(requested).size, 8192);
  assert.equal(requested.length, 8192);
  assert.ok(requested.every(token => token.length <= 256));
  assert.ok(f.style().textContent.length <= 384 * 1024);
  assert.ok((f.style().textContent.match(/display:none/g) ?? []).length <= 4096);
});
