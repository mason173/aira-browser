#!/usr/bin/env node
'use strict';
// Production bridge, controlled ArkWeb callback timing. No network/device execution.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/platform/download/ArkWebDownloadBridge.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
const states = { PENDING: 0, IN_PROGRESS: 1, PAUSED: 2, COMPLETED: 3, CANCELED: 4, INTERRUPTED: 5 };
function environment() {
  const state = { events: [], controllerCalls: [], starts: [], curlCalls: [], managerResumes: [], timers: new Map() };
  let managerDelegate, inBefore = false, nextTimer = 0;
  class Delegate {
    onBeforeDownload(fn) { this.before = fn; } onDownloadUpdated(fn) { this.updated = fn; }
    onDownloadFinish(fn) { this.finished = fn; } onDownloadFailed(fn) { this.failed = fn; }
  }
  class Item {
    constructor(guid, url, options = {}) {
      Object.assign(this, { guid, url, originalUrl: options.originalUrl ?? url, method: options.method ?? 'GET',
        name: 'server-name.bin', state: states.PENDING, cancels: 0, received: 0, finishImmediately: false }, options);
    }
    getGuid() { return this.guid; } getUrl() { return this.url; } getOriginalUrl() { return this.originalUrl; }
    getMethod() { return this.method; } getSuggestedFileName() { return this.name; }
    getMimeType() { return 'application/octet-stream'; } getReferrerUrl() { return 'https://page.test'; }
    getTotalBytes() { return 100; } getReceivedBytes() { return this.received; }
    getCurrentSpeed() { return 0; } getState() { return this.state; } getLastErrorCode() { return 0; }
    start(target) {
      assert.ok(inBefore, 'A new controller request receives its target only within before_download');
      if (this.throwStart) throw Error('invalid path');
      state.starts.push({ nativeGuid: this.guid, target }); this.state = states.IN_PROGRESS;
      this.delegate?.updated(this);
      if (this.finishImmediately) { this.state = states.COMPLETED; this.delegate?.finished(this); }
    }
    pause() { this.state = states.PAUSED; this.delegate?.updated(this); }
    resume() { assert.equal(this.state, states.PAUSED); this.state = states.IN_PROGRESS; this.delegate?.updated(this); }
    cancel() { this.cancels++; this.state = states.CANCELED; this.delegate?.failed(this); }
    serialize() {
      return new Uint8Array(Buffer.from(JSON.stringify({ guid: this.guid, url: this.url,
        originalUrl: this.originalUrl, method: this.method, received: this.received })));
    }
    static deserialize(bytes) { const record = JSON.parse(Buffer.from(bytes).toString());
      return new Item(record.guid, record.url, { ...record, state: states.INTERRUPTED }); }
  }
  function deliver(delegate, item) {
    item.delegate = delegate; inBefore = true;
    try { delegate.before(item); } finally { inBefore = false; }
  }
  const webview = { WebDownloadDelegate: Delegate, WebDownloadItem: Item, WebDownloadState: states,
    WebDownloadManager: {
      setDownloadDelegate(delegate) { managerDelegate = delegate; },
      resumeDownload(item) { state.managerResumes.push(item); item.state = states.PENDING; deliver(managerDelegate, item); }
    } };
  class Curl {
    setCallbacks() {} hasActiveDownload() { return false; } getActiveDownloadSnapshot() {}
    getActiveDownloadSnapshots() { return []; }
    async startDirectDownload(snapshot) { state.curlCalls.push(snapshot); return { ...snapshot, state: 'IN_PROGRESS' }; }
    async pauseDownload() { return false; } async resumeDownload() { return false; }
    async retryDownload() { return false; } async cancelDownload() { return false; }
    cancelPendingDownload() { return false; } async reconnectDownload() { return undefined; }
  }
  const module = { exports: {} };
  vm.runInNewContext(compiled, { module, exports: module.exports, Uint8Array, $r: key => key,
    setTimeout(fn) { const id = ++nextTimer; state.timers.set(id, fn); return id; },
    clearTimeout(id) { state.timers.delete(id); },
    require(id) {
      if (id === '@kit.ArkWeb') return { webview };
      if (id === '@kit.ArkTS') return { util: { Base64Helper: class {
        encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); }
        decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); }
      } } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {} } };
      if (id.endsWith('/LibcurlDownloadAdapter')) return { LibcurlDownloadAdapter: Curl };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      throw Error('Unexpected dependency ' + id);
    }
  }, { filename });
  const bridge = new module.exports.ArkWebDownloadBridge();
  bridge.setCallbacks({ onDownloadEvent: event => state.events.push(event) });
  const before = (source, item) => deliver(bridge.getDelegateForSource(source), item);
  const register = (source, starter) => bridge.registerDownloadSource(source, url => {
    state.controllerCalls.push({ source, url }); starter?.(url);
  });
  const snapshot = (guid = 'app-a', url = 'https://files.test/a', sourceId = 'source-a') => ({
    guid, sourceId, url, originalUrl: url, suggestedFileName: 'chosen-name.bin', fileNameLocked: true, totalBytes: 0,
    receivedBytes: 0, currentSpeed: 0, state: 'PENDING', lastErrorCode: 0, method: 'GET', downloadDriver: 'arkweb'
  });
  return { state, bridge, Item, before, register, snapshot, expire() {
    const callbacks = [...state.timers.values()]; state.timers.clear(); callbacks.forEach(callback => callback());
  } };
}
let failures = 0;
async function test(name, run) {
  try { await run(); console.log('PASS ' + name); }
  catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.stack); }
}
(async () => {
  for (const synchronous of [false, true]) await test('manual GET keeps app GUID and filename without curl (synchronous=' + synchronous + ')', async () => {
    const e = environment(), item = new e.Item('native-a', 'https://files.test/a');
    e.register('source-a', synchronous ? () => e.before('source-a', item) : undefined);
    const started = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/chosen-name.bin');
    if (!synchronous) {
      assert.equal(e.bridge.hasActiveDownload('app-a'), true);
      assert.equal(e.bridge.getActiveDownloadSnapshot('app-a').state, 'PENDING');
      e.before('source-a', item);
    }
    const result = await started;
    assert.equal(result.guid, 'app-a'); assert.equal(result.platformTaskId, 'arkweb:native-a');
    assert.equal(result.suggestedFileName, 'chosen-name.bin'); assert.equal(result.state, 'IN_PROGRESS');
    assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.curlCalls.length, 0);
    assert.equal(e.state.starts[0].target, '/sandbox/chosen-name.bin');
    assert.ok(e.state.events.every(event => event.snapshot.guid === 'app-a' && event.type !== 'before_download'));
    item.received = 75; e.bridge.getDelegateForSource('replacement-source').updated(item);
    assert.equal(e.state.events.at(-1).snapshot.guid, 'app-a');
    assert.equal(e.state.events.at(-1).snapshot.sourceId, 'source-a', 'Known native GUID keeps its original source');
  });
  await test('redirects match original URL and never bind another source or another original request', async () => {
    const e = environment(); e.register('source-a');
    const started = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    e.before('source-b', new e.Item('native-other-source', 'https://files.test/a'));
    e.before('source-a', new e.Item('native-other-url', 'https://files.test/a', { originalUrl: 'https://files.test/other' }));
    assert.equal(e.state.starts.length, 0);
    assert.equal(e.state.events.filter(event => event.type === 'before_download').length, 2);
    e.before('source-a', new e.Item('native-a', 'https://cdn.test/redirected', { originalUrl: 'https://files.test/a' }));
    const result = await started; assert.equal(result.guid, 'app-a'); assert.equal(result.url, 'https://cdn.test/redirected');
    assert.equal(result.originalUrl, 'https://files.test/a');
  });
  await test('an unlocked URL-derived name yields to the server filename while an explicitly chosen name stays locked', async () => {
    const e = environment(); e.register('source-a');
    const started = e.bridge.startDirectDownload({ ...e.snapshot(), fileNameLocked: false }, '/sandbox/initial');
    e.before('source-a', new e.Item('native-a', 'https://files.test/a', { name: 'Content-Disposition.pdf' }));
    const result = await started;
    assert.equal(result.suggestedFileName, 'Content-Disposition.pdf'); assert.equal(result.fileNameLocked, false);
    assert.equal(e.state.events.at(-1).snapshot.suggestedFileName, 'Content-Disposition.pdf');
  });
  await test('each source starts requests serially while distinct sources remain independent', async () => {
    const e = environment(); e.register('source-a'); e.register('source-b');
    const a = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    const b = e.bridge.startDirectDownload(e.snapshot('app-b', 'https://files.test/b'), '/sandbox/b');
    const c = e.bridge.startDirectDownload(e.snapshot('app-c', 'https://files.test/c', 'source-b'), '/sandbox/c');
    assert.equal(e.state.controllerCalls.length, 2);
    e.before('source-a', new e.Item('native-a', 'https://files.test/a')); await a;
    assert.equal(e.state.controllerCalls.length, 3);
    e.before('source-a', new e.Item('native-b', 'https://files.test/b'));
    e.before('source-b', new e.Item('native-c', 'https://files.test/c'));
    assert.equal((await b).guid, 'app-b'); assert.equal((await c).guid, 'app-c');
  });
  await test('pausing a queued request prevents its GET and resumes only on an explicit start', async () => {
    const e = environment(); e.register('source-a');
    const a = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    const requestB = e.snapshot('app-b', 'https://files.test/b');
    const b = e.bridge.startDirectDownload(requestB, '/sandbox/b');
    assert.equal(await e.bridge.pauseDownload('app-b'), true); assert.equal((await b).state, 'PAUSED');
    e.before('source-a', new e.Item('native-a', 'https://files.test/a')); await a;
    assert.equal(e.state.controllerCalls.length, 1);
    const resumed = e.bridge.startDirectDownload(requestB, '/sandbox/b');
    assert.equal(e.state.controllerCalls.length, 2);
    e.before('source-a', new e.Item('native-b', 'https://files.test/b'));
    assert.equal((await resumed).guid, 'app-b');
  });
  await test('pausing an issued start holds its late original item without writing or replaying a GET', async () => {
    const e = environment(); e.register('source-a');
    const started = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    assert.equal(await e.bridge.pauseDownload('app-a'), true); assert.equal((await started).state, 'PAUSED');
    const item = new e.Item('native-a', 'https://files.test/a'); e.before('source-a', item);
    assert.equal(item.cancels, 1); assert.equal(e.state.starts.length, 0);
    const held = e.bridge.getActiveDownloadSnapshot('app-a');
    assert.equal(held.transportHeld, true); assert.equal(held.platformTaskId, 'arkweb:native-a');
    assert.equal((await e.bridge.startDirectDownload(held, '/sandbox/a')).guid, 'app-a');
    assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.managerResumes.length, 1);
    assert.equal(e.state.starts.length, 1); assert.equal(e.state.curlCalls.length, 0);
  });
  for (const direct of [false, true]) await test('quick pause then resume waits for the original before callback (direct=' + direct + ')', async () => {
    const e = environment(); e.register('source-a');
    const initial = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    await e.bridge.pauseDownload('app-a'); assert.equal((await initial).state, 'PAUSED');
    let settled = false;
    const resume = direct ? e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a') : e.bridge.resumeDownload('app-a');
    resume.then(() => { settled = true; }); await Promise.resolve();
    assert.equal(settled, false); assert.equal(e.state.controllerCalls.length, 1);
    e.before('source-a', new e.Item('native-a', 'https://files.test/a'));
    const result = await resume; assert.equal(direct ? result.state : result, direct ? 'IN_PROGRESS' : true);
    assert.equal(e.state.starts.length, 1); assert.equal(e.state.starts[0].target, '/sandbox/a');
    assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.curlCalls.length, 0);
    assert.equal(e.bridge.getActiveDownloadSnapshot('app-a').guid, 'app-a');
  });
  for (const stop of ['pause', 'cancel', 'timeout', 'unregister']) await test('resuming an issued request still converges on ' + stop, async () => {
    const e = environment(); e.register('source-a');
    const initial = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    await e.bridge.pauseDownload('app-a'); await initial;
    const resumed = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    if (stop === 'pause') await e.bridge.pauseDownload('app-a');
    if (stop === 'cancel') await e.bridge.cancelDownload('app-a');
    if (stop === 'timeout') e.expire();
    if (stop === 'unregister') e.bridge.unregisterDownloadSource('source-a');
    const result = await resumed;
    assert.equal(result?.state, stop === 'timeout' ? undefined : stop === 'pause' ? 'PAUSED' : 'CANCELED');
    const late = new e.Item('native-a', 'https://files.test/a'); e.before('source-a', late);
    assert.equal(late.cancels, 1); assert.equal(e.state.starts.length, 0);
    assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.curlCalls.length, 0);
  });
  for (const reason of ['cancel', 'timeout', 'throw']) await test(reason + ' never replays a GET and cancels exact late callbacks', async () => {
    const e = environment(); e.register('source-a', reason === 'throw' ? () => { throw Error('possibly accepted'); } : undefined);
    const started = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    if (reason === 'cancel') assert.equal(await e.bridge.cancelDownload('app-a'), true);
    if (reason === 'timeout') e.expire();
    const result = await started;
    assert.equal(result?.state, reason === 'cancel' ? 'CANCELED' : undefined);
    assert.equal(await e.bridge.startDirectDownload(e.snapshot('app-b'), '/sandbox/b'), undefined,
      'A retired source+URL cannot be confused with a second request');
    const item = new e.Item('native-late', 'https://files.test/a'); e.before('source-a', item);
    assert.equal(item.cancels, 1); assert.equal(e.state.starts.length, 0);
    assert.equal(e.state.events.filter(event => event.type === 'before_download').length, 0);
    assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.curlCalls.length, 0);
  });
  await test('unregister closes pending/queued sources and cancels late before callbacks', async () => {
    const e = environment(); e.register('source-a');
    const a = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    const b = e.bridge.startDirectDownload(e.snapshot('app-b', 'https://files.test/b'), '/sandbox/b');
    e.bridge.unregisterDownloadSource('source-a');
    assert.equal((await a).state, 'CANCELED'); assert.equal((await b).state, 'CANCELED');
    const late = new e.Item('native-late', 'https://files.test/a'); e.before('source-a', late);
    assert.equal(late.cancels, 1); assert.equal(e.state.controllerCalls.length, 1); assert.equal(e.state.starts.length, 0);
    assert.equal(await e.bridge.startDirectDownload(e.snapshot('app-c'), '/sandbox/c'), undefined);
  });
  await test('unregister also closes a paused queue entry that has never issued its request', async () => {
    const e = environment(); e.register('source-a');
    const a = e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    const b = e.bridge.startDirectDownload(e.snapshot('app-b', 'https://files.test/b'), '/sandbox/b');
    await e.bridge.pauseDownload('app-b'); assert.equal((await b).state, 'PAUSED');
    e.bridge.unregisterDownloadSource('source-a'); await a;
    assert.equal(e.bridge.hasActiveDownload('app-b'), false);
    assert.ok(e.state.events.some(event => event.type === 'canceled' && event.snapshot.guid === 'app-b'));
    assert.equal(e.state.controllerCalls.length, 1);
  });
  await test('synchronous completion during before callback returns completed under the stable app GUID', async () => {
    const e = environment(); const item = new e.Item('native-a', 'https://files.test/a', { finishImmediately: true });
    e.register('source-a', () => e.before('source-a', item));
    const result = await e.bridge.startDirectDownload(e.snapshot(), '/sandbox/a');
    assert.equal(result.guid, 'app-a'); assert.equal(result.state, 'COMPLETED');
    assert.ok(e.state.events.some(event => event.type === 'finished' && event.snapshot.guid === 'app-a'));
    assert.equal(e.bridge.hasActiveDownload('app-a'), false);
  });
  await test('cold restore validates native GUID against persisted platform ID before restoring the app alias', async () => {
    const e = environment(), item = new e.Item('native-a', 'https://files.test/a');
    const token = 'arkweb-v1:' + Buffer.from(item.serialize()).toString('base64');
    assert.equal(await e.bridge.reconnectDownload('app-a', 'arkweb:wrong-native', token), undefined);
    assert.equal(e.state.managerResumes.length, 0);
    const attached = await e.bridge.reconnectDownload('app-a', 'arkweb:native-a', token);
    assert.equal(attached.guid, 'app-a'); assert.equal(attached.state, 'PAUSED'); assert.equal(attached.platformTaskId, 'arkweb:native-a');
    const started = await e.bridge.startDirectDownload({ ...e.snapshot(), platformTaskId: attached.platformTaskId,
      platformTaskToken: token }, '/sandbox/a');
    assert.equal(started.guid, 'app-a'); assert.equal(started.suggestedFileName, 'chosen-name.bin');
    assert.equal(e.state.managerResumes.length, 1); assert.equal(e.state.controllerCalls.length, 0);
    assert.ok(e.state.events.every(event => event.snapshot.guid === 'app-a'));
  });
  await test('POST, renderer URLs and missing sources cannot become fresh GET requests', async () => {
    const e = environment(); e.register('source-a');
    for (const request of [{ ...e.snapshot(), method: 'POST' }, { ...e.snapshot(), url: 'blob:https://page.test/id', originalUrl: undefined },
      { ...e.snapshot(), sourceId: undefined }, { ...e.snapshot(), method: undefined }]) {
      assert.equal(await e.bridge.startDirectDownload(request, '/sandbox/a'), undefined);
    }
    assert.equal(e.state.controllerCalls.length, 0); assert.equal(e.state.curlCalls.length, 0);
  });
  await test('ordinary page start stays ArkWeb; only explicit native and HLS work reaches curl', async () => {
    const e = environment(), item = new e.Item('native-page', 'https://files.test/page');
    e.before('source-a', item);
    // Existing page downloads already own their before callback; model user-confirmed start.
    item.start = target => { e.state.starts.push({ nativeGuid: item.guid, target }); item.state = states.IN_PROGRESS; };
    assert.equal(await e.bridge.startDownload('native-page', '/sandbox/page'), true);
    assert.equal(e.state.curlCalls.length, 0);
    assert.ok(await e.bridge.startDirectDownload({ ...e.snapshot('native-custom'), downloadDriver: 'libcurl' }, '/sandbox/custom'));
    assert.ok(await e.bridge.startDirectDownload({ ...e.snapshot('hls', 'https://files.test/movie.m3u8'), downloadDriver: 'libcurl' }, '/sandbox/movie'));
    assert.equal(e.state.curlCalls.length, 2);
  });
  await test('the bridge honors explicit ArkWeb routing and does not infer native HLS from an incidental URL substring', async () => {
    const e = environment(); const url = 'https://files.test/archive.zip?note=.m3u8-is-not-a-manifest';
    e.register('source-a', () => e.before('source-a', new e.Item('native-a', url)));
    const result = await e.bridge.startDirectDownload(e.snapshot('app-a', url), '/sandbox/archive.zip');
    assert.equal(result.downloadDriver, 'arkweb'); assert.equal(e.state.curlCalls.length, 0);
    assert.equal(e.state.controllerCalls.length, 1);
  });
  process.exitCode = failures ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
