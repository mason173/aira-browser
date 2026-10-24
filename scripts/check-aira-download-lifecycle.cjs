#!/usr/bin/env node
'use strict';
// Run the actual adapter with a delayed native-module boundary, as on a cold start.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const filename = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/platform/download/LibcurlDownloadAdapter.ets');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
}).outputText, {
  exports: exportsObject, setInterval: () => 1, clearInterval() {},
  require(id) {
    if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    if (id === '@kit.ArkWeb') return { webview: { WebCookieManager: { fetchCookieSync: () => '' } } };
    if (id === '@kit.DeviceCertificateKit') return { certificateManager: { CertType: { CA_CERT_SYSTEM: 0 }, getCertificateStorePath: () => '' } };
    throw Error('Unexpected dependency ' + id);
  }
}, { filename });
function fixture() {
  const requests = [], released = [], canceled = [];
  let ready;
  const gate = new Promise(resolve => { ready = resolve; });
  const native = { hlsPolicySummary: () => '', startTask: () => true,
    createTask(url, target) { requests.push({ url, target }); return requests.length; },
    releaseTask: handle => released.push(handle), cancelTask: handle => { canceled.push(handle); return true; },
    pauseTask: () => true, resumeTask: () => true
  };
  const adapter = new exportsObject.LibcurlDownloadAdapter();
  adapter.loadNativeModule = async () => { await gate; adapter.nativeModule = native; return native; };
  const snapshot = { guid: 'one', url: 'https://files.example/file', suggestedFileName: 'file.bin',
    method: 'GET', state: 'PENDING', totalBytes: 0, receivedBytes: 0, currentSpeed: 0, lastErrorCode: 0 };
  return { adapter, snapshot, requests, released, canceled, native, ready: () => ready() };
}
(async () => {
  let failures = 0;
  async function check(name, body) {
    try { await body(); console.log('PASS ' + name); }
    catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.message); }
  }
  await check('duplicate starts during native loading share one writer', async () => {
    const f = fixture();
    const first = f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    const second = f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    f.ready(); await Promise.all([first, second]);
    assert.equal(f.requests.length, 1, 'A task must never open two native writers');
  });
  await check('cancel while native module loads prevents the request', async () => {
    const f = fixture(); const pending = f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    const accepted = await f.adapter.cancelDownload('one');
    f.ready(); const started = await pending;
    assert.equal(f.requests.length, 0, 'A canceled task must not start after the module becomes ready');
    assert.equal(accepted, true); assert.equal(started, undefined);
  });
  await check('a completed start cannot be replaced by another start for the same guid', async () => {
    const f = fixture(); f.ready();
    await f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    await f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    assert.equal(f.requests.length, 1);
  });
  await check('a native import failure settles all duplicate callers and allows a later retry', async () => {
    const f = fixture();
    f.adapter.loadNativeModule = async () => { throw Error('module temporarily unavailable'); };
    const results = await Promise.all([
      f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin'),
      f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin')
    ]);
    assert.deepEqual(results, [undefined, undefined]);
    assert.equal(Object.values(f.adapter.pendingStartsByGuid).filter(Boolean).length, 0);
    f.adapter.loadNativeModule = async () => { f.adapter.nativeModule = f.native; return f.native; };
    assert.ok(await f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin'));
    assert.equal(f.requests.length, 1);
  });
  await check('cancel in the first progress callback cancels the already-created native handle', async () => {
    const f = fixture(); f.ready();
    f.adapter.setCallbacks({ onDownloadEvent: () => { void f.adapter.cancelDownload('one'); } });
    await f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    assert.deepEqual(f.canceled, [1]);
  });
  await check('pause during native loading holds the request until explicit resume', async () => {
    const f = fixture(); const pending = f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    const accepted = await f.adapter.pauseDownload('one');
    f.ready(); await pending;
    assert.equal(accepted, true); assert.equal(f.requests.length, 0);
    assert.equal(f.adapter.getActiveDownloadSnapshot('one').state, 'PAUSED');
    assert.equal(await f.adapter.resumeDownload('one'), true);
    assert.equal(f.requests.length, 1);
  });
  await check('a second pause supersedes a resume still waiting for the native module', async () => {
    const f = fixture(); const pending = f.adapter.startDirectDownload(f.snapshot, '/sandbox/file.bin');
    await f.adapter.pauseDownload('one');
    const resuming = f.adapter.resumeDownload('one');
    await f.adapter.pauseDownload('one');
    f.ready(); await pending;
    assert.equal(await resuming, false); assert.equal(f.requests.length, 0);
  });
  if (failures) process.exitCode = 1;
})();
