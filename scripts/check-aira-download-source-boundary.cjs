#!/usr/bin/env node
'use strict';

// Exercise the real runtime at the controller/delegate boundary, including delayed callbacks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function load(filename) {
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  cache.set(filename, module.exports);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, {
    module, exports: module.exports, $r: (key) => key,
    require(id) {
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id.includes('/domain/') || id.endsWith('/BrowserModels') || id.startsWith('./DownloadV2')) {
        return load(path.resolve(path.dirname(filename), id + '.ets'));
      }
      // No constructor is invoked: the fixture supplies these transport/persistence dependencies.
      return {};
    }
  }, { filename });
  return module.exports;
}
const { DownloadRuntimeService } = load(path.join(root, 'services/download/DownloadRuntimeService.ets'));
const { BrowserDownloadConfirmOverlayCoordinator } = load(path.join(root,
  'core/browser/BrowserDownloadConfirmOverlayCoordinator.ets'));
const regular = { windowId: 'window-a', profileId: 'default', privacyMode: 'regular',
  dataScope: 'profile_persistent', sourcePageUrl: 'https://regular.example/page' };
const privateBoundary = { windowId: 'window-a', profileId: 'default', privacyMode: 'private',
  dataScope: 'session_ephemeral', sourcePageUrl: 'https://private.example/page' };

function fixture() {
  const consumed = [], errors = [], manual = [], canceled = [], delivered = [], tasks = new Map();
  const starters = new Map(), unregistered = [], confirmed = [];
  let listener;
  const runtime = Object.create(DownloadRuntimeService.prototype);
  Object.assign(runtime, {
    initialized: false, callbacks: { onError: value => errors.push(value),
      onPlatformDownloadEvent: (event, boundary) => delivered.push({ event, boundary }) },
    callbackListeners: [], activeBoundary: regular, nextDownloadSourceId: 1, downloadSourceSessionId: 'test-session',
    recentWebDownloadStarts: [], pageDownloadSources: new Map(),
    fileActionGuids: new Set(), fileAvailabilityByGuid: new Map(),
    downloadSourceBoundaries: new Map(), downloadGuidBoundaries: new Map(),
    downloadBridge: {
      setCallbacks(callbacks) { listener = callbacks.onDownloadEvent; },
      getDelegate() { return {}; },
      getDelegateForSource(sourceId) { return { sourceId }; },
      registerDownloadSource(sourceId, start) { starters.set(sourceId, start); },
      unregisterDownloadSource(sourceId) { unregistered.push(sourceId); starters.delete(sourceId); },
      cancelPendingDownload(guid) { canceled.push(guid); return true; }
    },
    downloadPolicyService: { canWriteSessionTasks: () => true, canCleanupSession: () => true,
      resolveSessionCleanupPolicy: () => ({ isPrivateSession: true,
        shouldDeleteSessionTempFilesOnWindowClose: false, shouldClearSessionRecordsOnWindowClose: false }) },
    downloadV2Service: {
      findTask: guid => tasks.get(guid), getCapturedRequest: () => undefined,
      consumePlatformEvent(event, boundary) { consumed.push({ event, boundary }); return false; },
      createManualRequest(url, boundary, fileName, host, context) {
        manual.push({ url, boundary, context }); return { guid: 'manual-' + manual.length, started: false };
      },
      async createConfirmedManualRequest(url, boundary, fileName, host, context) {
        confirmed.push({ url, boundary, context }); await runtime.batchHook?.(); return { status: 'queued' };
      }
    }
  });
  function controller(throws = false) {
    return { delegate: undefined, requests: [],
      setDownloadDelegate(delegate) { this.delegate = delegate; },
      startDownload(url) { this.requests.push(url); if (throws) throw Error('possibly accepted'); }
    };
  }
  function event(guid, sourceId, type = 'before_download', extra = {}) {
    const value = { type, snapshot: { guid, sourceId, url: 'https://files.example/same.bin',
      suggestedFileName: 'same.bin', ...extra } };
    listener(value);
    return value;
  }
  return { runtime, controller, event, consumed, errors, manual, canceled, delivered, tasks, starters, unregistered, confirmed };
}

async function main() {
let failures = 0;
async function check(name, run) {
  try { await run(); console.log('PASS ' + name); }
  catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.stack); }
}

await check('a background private download keeps its tab boundary and identity after a tab switch', () => {
  const f = fixture(), a = f.controller(), b = f.controller();
  f.runtime.registerPageDownloadSource('private-tab', a, privateBoundary);
  f.runtime.registerPageDownloadSource('regular-tab', b, regular);
  f.runtime.recordWebDownloadStart('private-tab', 'https://files.example/same.bin', 'Private-UA', 'private-name', 'application/private', 1);
  f.runtime.recordWebDownloadStart('regular-tab', 'https://files.example/same.bin', 'Regular-UA', 'regular-name', 'application/regular', 2);
  f.runtime.setActiveBoundary('default', 'regular', 'profile_persistent', 'other-window', 'https://other.example');
  const privateEvent = f.event('private-guid', a.delegate.sourceId);
  const regularEvent = f.event('regular-guid', b.delegate.sourceId);
  assert.equal(f.consumed[0].boundary.privacyMode, 'private');
  assert.equal(f.consumed[0].boundary.windowId, 'window-a');
  assert.equal(f.consumed[0].boundary.sourcePageUrl, privateBoundary.sourcePageUrl);
  assert.equal(privateEvent.snapshot.userAgent, 'Private-UA');
  assert.equal(privateEvent.snapshot.contentDisposition, 'private-name');
  assert.equal(regularEvent.snapshot.userAgent, 'Regular-UA');
  assert.equal(f.delivered[0].boundary.privacyMode, 'private');
  assert.equal(f.errors.length, 0, 'An unhandled service callback must not invent a failure toast');
});

await check('controller replacement cannot move old callbacks into a new privacy boundary', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  const oldSource = a.delegate.sourceId;
  f.runtime.registerPageDownloadSource('tab', a, regular);
  assert.notEqual(a.delegate.sourceId, oldSource);
  f.event('old-guid', oldSource);
  f.event('new-guid', a.delegate.sourceId);
  assert.equal(f.consumed[0].boundary.privacyMode, 'private');
  assert.equal(f.consumed[1].boundary.privacyMode, 'regular');
});

await check('restored task callbacks resolve by guid before a current source or active page', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, regular);
  f.tasks.set('restored', { ...privateBoundary, request: { sourcePageUrl: privateBoundary.sourcePageUrl } });
  f.event('restored', a.delegate.sourceId, 'updated');
  f.event('restored', undefined, 'finished');
  assert.equal(f.consumed.length, 2);
  assert.ok(f.consumed.every(entry => entry.boundary.privacyMode === 'private'));
});

await check('unknown and expired sources do not use the active boundary or generic error toast', () => {
  const f = fixture(); f.runtime.initialize();
  f.event('unknown-progress', undefined, 'failed');
  f.event('unknown-before', 'closed-private-source');
  assert.equal(f.consumed.length, 0);
  assert.equal(f.errors.length, 0);
  assert.deepEqual(f.canceled, ['unknown-before']);
});

await check('ordinary requests retain confirmation and stable GUID, starting only through the registered source', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  const result = f.runtime.requestPageDownload('tab', { url: 'https://files.example/file',
    userAgent: 'Page-UA', referer: privateBoundary.sourcePageUrl });
  assert.equal(result.started, false); assert.equal(result.guid, 'manual-1');
  assert.equal(a.requests.length, 0); assert.equal(f.manual.length, 1);
  assert.equal(f.manual[0].context.sourceId, a.delegate.sourceId);
  assert.equal(f.manual[0].context.nativeReason, undefined);
  f.starters.get(a.delegate.sourceId)('https://files.example/file');
  assert.deepEqual(a.requests, ['https://files.example/file']);
});

await check('only HLS and irreproducible custom headers select the native transfer', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  for (const input of [
    { headers: { Authorization: 'test' } },
    { url: 'https://files.example/index.m3u8?token=test' },
    { mimeType: 'application/vnd.apple.mpegurl' },
    { headersSource: 'page', headers: { Cookie: 'captured', Referer: privateBoundary.sourcePageUrl,
      'User-Agent': 'Page-UA', Origin: 'https://private.example', 'Sec-Fetch-Dest': 'video' } },
    { headersSource: 'page', headers: { Authorization: 'token' } },
    { headersSource: 'page', headers: { 'X-Signature': 'token' } },
    { headersSource: 'page', headers: { 'Sec-Custom-Token': 'token' } },
    { headersSource: 'page', headers: { Origin: 'https://frame.example' } },
    { headersSource: 'explicit', headers: { Referer: privateBoundary.sourcePageUrl } },
    { headers: {} }
  ]) f.runtime.requestPageDownload('tab', { url: 'https://files.example/file', ...input });
  assert.deepEqual(f.manual.map(entry => entry.context.nativeReason),
    ['custom_headers', 'hls', 'hls', undefined, 'custom_headers', 'custom_headers', 'custom_headers',
      'custom_headers', 'custom_headers', undefined]);
  assert.equal(f.manual[3].context.headers.Cookie, 'captured');
  assert.equal(a.requests.length, 0);
});

await check('expired explicit sources and missing controllers fail without borrowing active cookies or native replay', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('active', a, regular);
  f.runtime.registerPageDownloadSource('missing-controller', undefined, privateBoundary);
  assert.equal(f.runtime.requestPageDownload('missing-controller', { url: 'https://files.example/file' }), undefined);
  assert.equal(f.runtime.requestPageDownload('expired', { url: 'https://files.example/file' }), undefined);
  assert.equal(f.runtime.requestManualDownload({ url: 'https://files.example/file', sourceTabId: 'expired',
    headers: { Authorization: 'token' } }), undefined);
  assert.equal(f.manual.length, 0); assert.equal(a.requests.length, 0); assert.equal(f.errors.length, 3);
});

await check('unscoped manual requests resolve only one live source inside the initiating boundary', () => {
  const f = fixture(), a = f.controller(), b = f.controller();
  f.runtime.registerPageDownloadSource('private', a, privateBoundary);
  f.runtime.registerPageDownloadSource('regular', b, regular);
  assert.equal(f.runtime.requestManualDownload({ url: 'https://files.example/file' }).guid, 'manual-1');
  assert.equal(f.manual[0].context.sourceId, b.delegate.sourceId);
  f.runtime.setActiveBoundary('default', 'regular', 'profile_persistent', 'another-window', regular.sourcePageUrl);
  assert.equal(f.runtime.requestManualDownload({ url: 'https://files.example/file' }), undefined);
  assert.equal(f.manual.length, 1);
});

await check('popup and userscript-shaped manual requests keep their explicit source boundary and stable task ID', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('opener', a, privateBoundary);
  f.runtime.requestManualDownload({ url: 'https://files.example/popup' }, 'opener');
  const script = f.runtime.requestManualDownload({ url: 'https://files.example/script', sourceTabId: 'opener', headersSource: 'explicit' });
  assert.equal(script.guid, 'manual-2');
  for (const entry of f.manual) {
    assert.equal(entry.boundary.privacyMode, 'private'); assert.equal(entry.context.sourceId, a.delegate.sourceId);
    assert.equal(entry.context.nativeReason, undefined);
  }
});

await check('delegate installation failure never creates an ordinary task with a substitute source', () => {
  const f = fixture(), a = f.controller();
  a.setDownloadDelegate = () => { throw Error('not attached'); };
  f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  assert.equal(f.runtime.requestPageDownload('tab', { url: 'https://files.example/file' }), undefined);
  assert.equal(f.manual.length, 0); assert.equal(f.starters.size, 0);
});

await check('navigation unregisters old starters but retains old callback identity; tab release removes the live starter', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, regular); const oldId = a.delegate.sourceId;
  f.runtime.registerPageDownloadSource('tab', a, { ...regular, sourcePageUrl: 'https://regular.example/next' });
  assert.notEqual(a.delegate.sourceId, oldId); assert.equal(f.starters.has(oldId), false);
  f.event('old-guid', oldId); assert.equal(f.consumed[0].boundary.sourcePageUrl, regular.sourcePageUrl);
  assert.ok(a.delegate.sourceId.startsWith('test-session:'));
  f.runtime.retainPageDownloadSources('window-a', []);
  assert.equal(f.starters.size, 0); assert.equal(f.runtime.pageDownloadSources.size, 0);
});

await check('batch captures all source IDs, boundaries and headers before asynchronous creation', async () => {
  const f = fixture(), a = f.controller(); f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  const oldId = a.delegate.sourceId;
  f.runtime.batchHook = async () => {
    f.runtime.setActiveBoundary('default', 'regular', 'profile_persistent', 'other-window', 'https://other.example');
    f.runtime.registerPageDownloadSource('tab', a, regular);
  };
  const result = await f.runtime.requestConfirmedManualDownloads([
    { url: 'https://files.example/1', sourceTabId: 'tab' },
    { url: 'https://files.example/2', sourceTabId: 'tab' }
  ]);
  assert.equal(result.queued, 2); assert.equal(result.failed, 0);
  for (const entry of f.confirmed) {
    assert.equal(entry.context.sourceId, oldId); assert.equal(entry.boundary.privacyMode, 'private');
  }
  assert.equal(f.starters.has(oldId), false, 'admission must fail closed if the frozen source was replaced');
});

await check('private session cleanup expires its controller sources and pending callback boundary', () => {
  const f = fixture(), a = f.controller();
  f.runtime.registerPageDownloadSource('tab', a, privateBoundary);
  const source = a.delegate.sourceId;
  f.event('private-guid', source);
  f.runtime.clearPrivateDownloadSessionForWindow('window-a');
  f.event('private-late', source);
  f.event('private-guid', source, 'updated');
  assert.equal(f.consumed.length, 1);
  assert.deepEqual(f.canceled, ['private-late']);
  assert.equal(f.runtime.pageDownloadSources.size, 0);
});

await check('all download drivers honor a non-retriable failure in available actions', () => {
  const f = fixture();
  for (const driver of ['arkweb', 'libcurl', 'hls_native']) {
    const task = { status: 'failed', persistence: { downloadDriver: driver },
      runtime: { resumeCapability: 'retry_only' }, failure: { code: 'server_forbidden', retriable: false } };
    const actions = f.runtime.listAllowedActionsForTask(task);
    assert.equal(actions.includes('retry'), false, driver);
    assert.equal(actions.includes('resume'), false, driver);
    task.failure.retriable = true;
    assert.equal(f.runtime.listAllowedActionsForTask(task).includes('retry'), true, driver);
  }
});

await check('the fixed confirmation owner preserves the page task GUID and original manual confirmation', () => {
  const owner = Object.create(BrowserDownloadConfirmOverlayCoordinator.prototype);
  const requests = [], presentations = [], prompt = { guid: 'stable-page-task' };
  owner.downloadService = { requestPageDownload(tabId, input) {
    requests.push({ tabId, input }); return { guid: prompt.guid, started: false, prompt };
  } };
  owner.present = value => presentations.push(value);
  const input = { url: 'https://files.example/file', userAgent: 'Page-UA' };
  owner.requestPageAndPresent('originating-tab', input);
  assert.equal(requests.length, 1); assert.equal(requests[0].tabId, 'originating-tab');
  assert.equal(requests[0].input, input); assert.equal(presentations[0], prompt);
  owner.downloadService.requestPageDownload = () => undefined;
  owner.requestPageAndPresent('expired-tab', input);
  assert.equal(presentations.length, 1, 'An unavailable source must not clear an unrelated confirmation');
});

await check('the fixed confirmation owner keeps explicit manual requests and their opener source', () => {
  const owner = Object.create(BrowserDownloadConfirmOverlayCoordinator.prototype);
  const requests = [], presentations = [];
  const prompt = { guid: 'manual-guid' };
  owner.downloadService = { requestManualDownload(input, tabId) {
    requests.push({ input, tabId }); return { guid: 'manual-guid', started: false, prompt };
  } };
  owner.present = value => presentations.push(value);
  assert.equal(owner.requestAndPresent({ url: ' https://files.example/file ' }, 'opener-tab'), 'manual-guid');
  assert.equal(requests[0].tabId, 'opener-tab');
  assert.equal(requests[0].input.url, 'https://files.example/file');
  assert.equal(presentations[0], prompt);
});

if (failures) process.exitCode = 1;
}
main().catch(error => { console.error(error); process.exitCode = 1; });
