#!/usr/bin/env node
'use strict';
// Exercises the production bridge. Models ArkWeb's documented PENDING/cancel/manager boundary.
// Renderer and server behavior still require device verification.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/platform/download/ArkWebDownloadBridge.ets');
const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText;
function setup({ serialization = true, rejectResume = false, delayedBefore = false, finishImmediately = false } = {}) {
  const states = { PENDING: 0, IN_PROGRESS: 1, PAUSED: 2, COMPLETED: 3, CANCELED: 4, INTERRUPTED: 5 };
  const events = [], starts = [], resumes = [];
  let managerDelegate, inBefore = false, curlStarts = 0, deferred;
  class Delegate {
    onBeforeDownload(f) { this.before = f; } onDownloadUpdated(f) { this.updated = f; }
    onDownloadFinish(f) { this.finished = f; } onDownloadFailed(f) { this.failed = f; }
  }
  class Item {
    constructor(guid = 'task', method = 'POST', url = 'https://site.test/once') {
      Object.assign(this, { guid, method, url, state: states.PENDING, received: 12, cancels: 0 });
    }
    getGuid() { return this.guid; } getUrl() { return this.url; } getMethod() { return this.method; }
    getSuggestedFileName() { return 'report.pdf'; } getMimeType() { return 'application/pdf'; }
    getTotalBytes() { return 100; } getReceivedBytes() { return this.received; }
    getCurrentSpeed() { return 0; } getState() { return this.state; } getLastErrorCode() { return 0; }
    cancel() { this.cancels++; this.state = states.CANCELED; this.delegate?.failed(this); }
    pause() { if (this.state === states.PENDING) throw Error('17100019'); this.state = states.PAUSED; }
    resume() { throw Error('Canceled/deserialized items must use WebDownloadManager'); }
    start(target) {
      assert.ok(inBefore, 'start(path) must be called from the manager before callback');
      starts.push({ guid: this.guid, target }); this.state = states.IN_PROGRESS;
      if (finishImmediately) { this.state = states.COMPLETED; managerDelegate.finished(this); }
    }
    serialize() {
      if (!serialization) throw Error('serialization unavailable');
      return new Uint8Array(Buffer.from(JSON.stringify({ guid: this.guid, method: this.method, url: this.url, received: this.received })));
    }
    static deserialize(data) {
      const record = JSON.parse(Buffer.from(data).toString());
      const item = new Item(record.guid, record.method, record.url); item.received = record.received;
      item.state = states.INTERRUPTED; return item;
    }
  }
  const webview = {
    WebDownloadState: states, WebDownloadItem: Item, WebDownloadDelegate: Delegate,
    WebDownloadManager: {
      setDownloadDelegate(d) { managerDelegate = d; },
      resumeDownload(item) {
        if (rejectResume) throw Error('context expired');
        resumes.push(item);
        const before = () => { item.state = states.PENDING; inBefore = true;
          try { managerDelegate.before(item); } finally { inBefore = false; } };
        if (delayedBefore) deferred = before; else before();
      }
    }
  };
  class Curl {
    setCallbacks() {} hasActiveDownload() { return false; } getActiveDownloadSnapshot() {}
    getActiveDownloadSnapshots() { return []; }
    async startDirectDownload(s) { curlStarts++; return { ...s, state: 'IN_PROGRESS', downloadDriver: 'libcurl' }; }
    cancelPendingDownload() { return false; }
  }
  const module = { exports: {} };
  vm.runInNewContext(compiled, { module, exports: module.exports, Uint8Array, $r: x => x,
    require(id) {
      if (id === '@kit.ArkWeb') return { webview };
      if (id === '@kit.ArkTS') return { util: { Base64Helper: class {
        encodeToStringSync(b) { return Buffer.from(b).toString('base64'); }
        decodeSync(s) { return new Uint8Array(Buffer.from(s, 'base64')); }
      } } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {} } };
      if (id.endsWith('/LibcurlDownloadAdapter')) return { LibcurlDownloadAdapter: Curl };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: x => x };
      throw Error(`Unexpected import: ${id}`);
    }
  }, { filename });
  const bridge = new module.exports.ArkWebDownloadBridge();
  bridge.setCallbacks({ onDownloadEvent: e => events.push(e) });
  function capture(item = new Item(), source = 'tab-private:1') {
    item.delegate = bridge.getDelegateForSource(source); item.delegate.before(item); return item;
  }
  return { bridge, Item, capture, events, starts, resumes, states, runDeferred: () => deferred(),
    get curlStarts() { return curlStarts; }, manager: () => managerDelegate };
}
(async () => {
  const failures = [];
  async function test(name, body) {
    try { await body(); console.log(`PASS ${name}`); }
    catch (e) { failures.push(name); console.error(`FAIL ${name}: ${e.stack}`); }
  }
  await test('PENDING stops transport before confirmation and suppresses synchronous/late cancel echoes', () => {
    const e = setup(), item = e.capture(); const held = e.bridge.holdDownload(item.guid);
    assert.equal(item.cancels, 1); assert.equal(item.state, e.states.CANCELED);
    assert.equal(held.transportHeld, true); assert.equal(held.state, 'PAUSED');
    assert.ok(held.platformTaskToken.startsWith('arkweb-v1:'));
    item.delegate.failed(item); item.delegate.updated(item);
    assert.equal(e.events.length, 1); assert.equal(e.starts.length, 0); assert.equal(e.resumes.length, 0);
    assert.equal(e.bridge.getActiveDownloadSnapshot('task').sourceId, 'tab-private:1');
  });
  for (const [method, url] of [['POST', 'https://site.test/once'], ['GET', 'blob:https://site.test/generated'], ['GET', 'data:text/plain,test']]) {
    await test(`${method} ${url.split(':')[0]} restores original GUID with destination in before callback`, async () => {
      const e = setup(), item = e.capture(new e.Item('task', method, url));
      const held = e.bridge.holdDownload('task');
      const started = await e.bridge.startDirectDownload(held, '/sandbox/confirmed.pdf');
      assert.equal(e.resumes.length, 1); assert.equal(e.resumes[0].method, method); assert.equal(e.resumes[0].url, url);
      assert.equal(started.guid, 'task'); assert.equal(started.state, 'IN_PROGRESS');
      assert.equal(e.starts[0].target, '/sandbox/confirmed.pdf'); assert.equal(e.curlStarts, 0);
      assert.equal(e.events.filter(x => x.type === 'before_download').length, 1);
      assert.equal(e.events.at(-1).snapshot.sourceId, 'tab-private:1');
      item.state = e.states.IN_PROGRESS; item.delegate.updated(item);
      assert.equal(e.bridge.getActiveDownloadSnapshot('task').state, 'IN_PROGRESS');
      assert.equal(e.events.length, 2, 'obsolete owner callbacks are ignored');
    });
  }
  await test('non-serializable renderer task retains original canceled object in-process', async () => {
    const e = setup({ serialization: false }), item = e.capture();
    const held = e.bridge.holdDownload('task'); assert.equal(held.platformTaskToken, undefined);
    assert.equal((await e.bridge.startDirectDownload(held, '/sandbox/blob.pdf')).state, 'IN_PROGRESS');
    assert.equal(e.resumes[0], item); assert.equal(e.curlStarts, 0);
  });
  await test('manager rejection retains held request without replaying its URL', async () => {
    const e = setup({ rejectResume: true }); e.capture(); const held = e.bridge.holdDownload('task');
    assert.equal(await e.bridge.startDirectDownload(held, '/sandbox/file'), undefined);
    assert.equal(e.bridge.getActiveDownloadSnapshot('task').transportHeld, true); assert.equal(e.curlStarts, 0);
  });
  await test('asynchronous restored before callback binds destination without another prompt', async () => {
    const e = setup({ delayedBefore: true }); e.capture(); const held = e.bridge.holdDownload('task');
    const started = await e.bridge.startDirectDownload(held, '/sandbox/delayed');
    assert.equal(started.state, 'IN_PROGRESS'); assert.equal(e.starts.length, 0);
    e.runDeferred(); assert.equal(e.starts[0].target, '/sandbox/delayed');
    assert.equal(e.events.filter(x => x.type === 'before_download').length, 1);
  });
  await test('synchronous completion during manager restore cannot regress to running', async () => {
    const e = setup({ finishImmediately: true }); e.capture();
    const started = await e.bridge.startDirectDownload(e.bridge.holdDownload('task'), '/sandbox/done');
    assert.equal(started.state, 'COMPLETED'); assert.equal(e.bridge.hasActiveDownload('task'), false);
  });
  await test('cancel during asynchronous restoration prevents late before from writing a destination', async () => {
    const e = setup({ delayedBefore: true }); e.capture();
    const held = e.bridge.holdDownload('task');
    await e.bridge.startDirectDownload(held, '/sandbox/canceled');
    assert.equal(await e.bridge.cancelDownload('task'), true);
    e.runDeferred();
    assert.equal(e.starts.length, 0); assert.equal(e.bridge.hasActiveDownload('task'), false);
    assert.equal(await e.bridge.startDirectDownload(held, '/sandbox/canceled'), undefined);
  });
  await test('multiple recoveries continue to suppress every obsolete owner', async () => {
    const e = setup(), original = e.capture();
    const held = e.bridge.holdDownload('task');
    await e.bridge.startDirectDownload(held, '/sandbox/file');
    const firstRestore = e.resumes[0];
    firstRestore.state = e.states.INTERRUPTED;
    e.manager().failed(firstRestore);
    await e.bridge.retryDownload('task', '/sandbox/file', held.platformTaskId, held.platformTaskToken);
    const count = e.events.length;
    original.state = e.states.IN_PROGRESS; original.delegate.updated(original);
    firstRestore.state = e.states.IN_PROGRESS; e.manager().updated(firstRestore);
    assert.equal(e.events.length, count);
    assert.equal(e.resumes.length, 2); assert.equal(e.curlStarts, 0);
  });
  await test('canceling held prompt releases ownership and ignores delayed callback', async () => {
    const e = setup(), item = e.capture(); e.bridge.holdDownload('task');
    assert.equal(e.bridge.cancelPendingDownload('task'), true); item.delegate.failed(item);
    assert.equal(e.bridge.hasActiveDownload('task'), false); assert.equal(e.events.length, 1);
    assert.equal(e.resumes.length, 0);
  });
  await test('cold reattach performs no network operation until admitted with a target', async () => {
    const old = setup(); old.capture(); const held = old.bridge.holdDownload('task');
    const e = setup(); const snapshot = await e.bridge.reconnectDownload('task', held.platformTaskId, held.platformTaskToken);
    assert.equal(snapshot.state, 'PAUSED'); assert.equal(e.resumes.length, 0);
    await e.bridge.startDirectDownload(snapshot, '/sandbox/restart');
    assert.equal(e.starts[0].target, '/sandbox/restart'); assert.equal(e.curlStarts, 0);
  });
  if (failures.length) process.exitCode = 1;
})();
