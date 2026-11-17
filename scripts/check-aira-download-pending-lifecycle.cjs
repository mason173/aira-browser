#!/usr/bin/env node
'use strict';

// Execute the real capture, engine, state machine and repository with platform-only shims.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const plain = value => JSON.parse(JSON.stringify(value));

function environment() {
  let now = 100;
  const cache = new Map(), logs = [], prompts = [];
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename);
    const module = { exports: {} };
    cache.set(filename, module.exports);
    const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(output, {
      module, exports: module.exports, $r: value => value,
      Date: class extends Date { static now() { return now; } },
      require(id) {
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: {
          info: (...args) => logs.push(args), warn: (...args) => logs.push(args), error: (...args) => logs.push(args)
        } };
        if (id === '@ohos.url') return { URL: { parseURL: value => new URL(value) } };
        if (id === '@kit.ArkData') return { preferences: {} };
        if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {} };
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        assert.ok(id.startsWith('.'), `Unmodeled platform dependency: ${id}`);
        return load(path.resolve(path.dirname(filename), `${id}.ets`));
      }
    }, { filename });
    return module.exports;
  }
  const { DownloadV2RequestCapture } = load(path.join(sourceRoot, 'features/downloadv2/DownloadV2RequestCapture.ets'));
  const { DownloadV2Engine } = load(path.join(sourceRoot, 'core/downloadv2/DownloadV2Engine.ets'));
  const capture = new DownloadV2RequestCapture();
  capture.setCallbacks({ onPromptChanged: prompt => prompts.push(prompt) });
  const boundary = { windowId: 'window-a', profileId: 'profile-main', privacyMode: 'regular',
    dataScope: 'profile_persistent', sourcePageUrl: 'https://page.example.test/source' };
  function snapshot(guid = 'platform-a', extra = {}) {
    return {
      guid, sourceId: 'source-a', transportHeld: true, url: 'https://files.example.test/private-file.zip?signature=synthetic',
      originalUrl: 'https://files.example.test/original', suggestedFileName: 'sensitive-archive.zip',
      totalBytes: 1000, progressFraction: 0.1, estimatedTotalBytes: 1000, receivedBytes: 100, currentSpeed: 25,
      state: 'paused', lastErrorCode: 0, errorMessage: 'synthetic detail', mimeType: 'application/zip', method: 'GET',
      userAgent: 'synthetic-agent', referer: 'https://page.example.test/source',
      contentDisposition: 'attachment; filename="sensitive-archive.zip"', headers: { Cookie: 'synthetic-cookie' },
      hlsSegmentConcurrency: 3, platformTaskId: 'arkweb:platform-a', platformTaskToken: 'synthetic-token',
      downloadDriver: 'arkweb', privacyMode: 'regular', ...extra
    };
  }
  return { capture, DownloadV2Engine, logs, prompts, boundary, snapshot, advance: () => { now += 100; } };
}

const failures = [];
function check(name, body) {
  try { body(); console.log(`PASS ${name}`); }
  catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.stack}`); }
}

check('capture copies every platform field and source page through get, replace and confirm', () => {
  const f = environment(); const snapshot = f.snapshot();
  const captured = f.capture.capturePlatformRequest(snapshot, f.boundary);
  assert.deepEqual(plain(captured.platformSnapshot), snapshot);
  const read = f.capture.getPendingRequest(snapshot.guid);
  assert.deepEqual(plain(read.platformSnapshot), snapshot);
  assert.deepEqual(plain(read.boundary), f.boundary);
  f.capture.replacePendingRequest(read);
  const confirmed = f.capture.confirmRequest(snapshot.guid);
  assert.deepEqual(plain(confirmed.platformSnapshot), snapshot);
  assert.deepEqual(plain(confirmed.boundary), f.boundary);
  assert.equal(confirmed.sourcePageUrl, f.boundary.sourcePageUrl);
});

check('captured input and returned objects cannot mutate the pending request', () => {
  const f = environment(); const snapshot = f.snapshot(); const boundary = { ...f.boundary };
  const captured = f.capture.capturePlatformRequest(snapshot, boundary);
  snapshot.headers.Cookie = 'changed input'; boundary.sourcePageUrl = 'https://other.example.test';
  captured.platformSnapshot.headers.Cookie = 'changed output'; captured.boundary.privacyMode = 'private';
  const read = f.capture.getPendingRequest(snapshot.guid);
  assert.equal(read.platformSnapshot.headers.Cookie, 'synthetic-cookie');
  assert.equal(read.boundary.sourcePageUrl, f.boundary.sourcePageUrl);
  assert.equal(read.boundary.privacyMode, 'regular');
  read.headers.Cookie = 'changed read';
  assert.equal(f.capture.cancelRequest(snapshot.guid).headers.Cookie, 'synthetic-cookie');
});

check('updates before confirmation keep the same pending request, source, prompt and latest progress', () => {
  const f = environment(); const initial = f.capture.capturePlatformRequest(f.snapshot(), f.boundary);
  f.capture.createManualRequest('https://other.example.test/file.bin', f.boundary, 'other.bin', undefined, false);
  const promptCount = f.prompts.length; f.advance();
  const updated = f.snapshot('platform-a', { sourceId: 'other-source', privacyMode: 'private',
    totalBytes: 2000, receivedBytes: 350, progressFraction: 0.175, estimatedTotalBytes: 2000,
    currentSpeed: 0, state: 'failed', lastErrorCode: 6, errorMessage: 'new error',
    platformTaskToken: undefined, transportHeld: undefined, headers: undefined, userAgent: undefined });
  assert.equal(f.capture.updatePendingPlatformSnapshot(updated), true);
  const read = f.capture.getPendingRequest(initial.guid);
  assert.equal(read.createdAt, initial.createdAt);
  assert.deepEqual(plain(read.boundary), f.boundary);
  assert.equal(read.platformSnapshot.sourceId, 'source-a');
  assert.equal(read.platformSnapshot.privacyMode, 'regular');
  assert.equal(read.platformSnapshot.transportHeld, true);
  assert.equal(read.platformSnapshot.platformTaskToken, 'synthetic-token');
  assert.equal(read.platformSnapshot.receivedBytes, 350);
  assert.equal(read.platformSnapshot.state, 'failed');
  assert.equal(read.platformSnapshot.lastErrorCode, 6);
  assert.equal(read.platformSnapshot.errorMessage, 'new error');
  assert.equal(read.platformSnapshot.headers.Cookie, 'synthetic-cookie');
  assert.equal(read.userAgent, 'synthetic-agent');
  assert.equal(read.totalBytes, 2000);
  assert.equal(f.capture.getPendingPrompt().guid, initial.guid);
  assert.equal(f.capture.getPendingPrompt().totalBytes, 2000);
  assert.equal(f.prompts.length, promptCount, 'progress must not reopen or dismiss a prompt');
  const confirmed = f.capture.confirmRequest(initial.guid);
  assert.equal(confirmed.platformSnapshot.receivedBytes, 350);
  assert.equal(confirmed.platformSnapshot.platformTaskToken, 'synthetic-token');
  assert.equal(f.capture.updatePendingPlatformSnapshot(updated), false, 'a consumed pending request stays consumed');
});

check('missing pending updates never create requests; empty tokens keep the latest recoverable token', () => {
  const f = environment();
  assert.equal(f.capture.updatePendingPlatformSnapshot(f.snapshot()), false);
  const manual = f.capture.createManualRequest(f.snapshot().url, f.boundary, 'manual.zip');
  assert.equal(f.capture.updatePendingPlatformSnapshot(f.snapshot(manual.guid)), false);
  assert.equal(f.capture.getPendingRequest(manual.guid).platformSnapshot, undefined);
  f.capture.capturePlatformRequest(f.snapshot(), f.boundary, false);
  assert.equal(f.capture.updatePendingPlatformSnapshot(f.snapshot('platform-a', { platformTaskToken: 'new-token' })), true);
  assert.equal(f.capture.updatePendingPlatformSnapshot(f.snapshot('platform-a', { platformTaskToken: '' })), true);
  assert.equal(f.capture.getPendingRequest('platform-a').platformSnapshot.platformTaskToken, 'new-token');
});

check('manual replacement only removes matching URL in the supplied window, profile, privacy and page', () => {
  const f = environment(); const url = f.snapshot().url;
  const target = f.capture.createManualRequest(`${url}#anchor`, f.boundary, 'target.zip', undefined, false);
  const variations = [
    { windowId: 'window-b' }, { profileId: 'other-profile' }, { privacyMode: 'private' },
    { dataScope: 'session_ephemeral' }, { sourcePageUrl: 'https://other.example.test/page' }
  ].map(extra => f.capture.createManualRequest(url, { ...f.boundary, ...extra }, 'keep.zip', undefined, false));
  f.capture.capturePlatformRequest(f.snapshot(), f.boundary, false);
  assert.equal(f.capture.removeManualPendingRequestsForUrl(url, f.boundary), 1);
  assert.equal(f.capture.getPendingRequest(target.guid), undefined);
  for (const request of variations) assert.ok(f.capture.getPendingRequest(request.guid));
  assert.ok(f.capture.getPendingRequest('platform-a'));
  assert.equal(f.capture.removeManualPendingRequestsForUrl(url), variations.length, 'legacy unconstrained calls remain compatible');
  assert.equal(variations[0].boundary.sourcePageUrl, f.boundary.sourcePageUrl);
  assert.equal(variations[0].sourcePageUrl, f.boundary.sourcePageUrl);
});

check('capture diagnostics exclude URL, file name, request headers and resume tokens', () => {
  const f = environment(); const snapshot = f.snapshot();
  f.capture.capturePlatformRequest(snapshot, f.boundary);
  f.capture.createManualRequest(snapshot.url, f.boundary, snapshot.suggestedFileName);
  f.capture.removeManualPendingRequestsForUrl(snapshot.url, f.boundary);
  f.capture.confirmRequest(snapshot.guid);
  const logs = JSON.stringify(f.logs);
  for (const value of [snapshot.url, snapshot.suggestedFileName, snapshot.headers.Cookie,
    snapshot.platformTaskToken, f.boundary.sourcePageUrl]) assert.equal(logs.includes(value), false, value);
});

check('invalid engine dispatch reports failure and never applies patches or emits task updates', () => {
  const f = environment(); const engine = new f.DownloadV2Engine(); let changes = 0;
  engine.setObserver({ onTaskChanged: () => { changes++; } });
  engine.createTask({ guid: 'task', suggestedFileName: 'file.zip', request: { url: 'https://example.test/file', method: 'GET' },
    boundary: f.boundary, requiresConfirmation: true });
  for (const [status, event] of [['awaiting_confirmation', 'start'], ['queued', 'pause'], ['queued', 'finish'],
    ['completed', 'retry'], ['removed', 'start']]) {
    engine.synchronizeTask('task', { status });
    const before = plain(engine.findTask('task')); const previousChanges = changes; f.advance();
    assert.equal(engine.dispatch('task', event, { progress: { receivedBytes: 999 }, resolvedFileName: 'wrong.zip' }), undefined);
    assert.deepEqual(plain(engine.findTask('task')), before);
    assert.equal(changes, previousChanges);
  }
  assert.equal(engine.dispatch('missing', 'start'), undefined);
});

check('valid engine confirmation and transfer lifecycle still commits state and metadata', () => {
  const f = environment(); const engine = new f.DownloadV2Engine();
  engine.createTask({ guid: 'task', suggestedFileName: 'file.zip', request: { url: 'https://example.test/file', method: 'GET' },
    boundary: f.boundary, requiresConfirmation: true });
  for (const [event, status] of [['confirm', 'queued'], ['start', 'running'], ['pause', 'paused'],
    ['resume', 'running'], ['finish', 'completed']]) {
    const task = engine.dispatch('task', event, { progress: { receivedBytes: 42 } });
    assert.equal(task.status, status); assert.equal(task.progress.receivedBytes, 42);
  }
  assert.equal(engine.findTask('task').timing.completedAt, 100);
});

if (failures.length) process.exitCode = 1;
else console.log('Download pending lifecycle checks passed (8 scenarios).');
