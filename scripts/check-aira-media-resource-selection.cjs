#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const inert = new Proxy({}, { get: () => class {} });

function load(file, modules = {}, globals = {}) {
  const exports = {};
  const filename = path.join(root, file);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(compiled, {
    exports, console, $r: (key, ...args) => `${key}:${args.join(',')}`,
    require(name) {
      for (const [suffix, value] of Object.entries(modules)) if (name.endsWith(suffix)) return value;
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {} } };
      return inert;
    }, ...globals
  }, { filename });
  return exports;
}

const selection = load('features/mediaDiscovery/MediaResourceSelection.ets');
const { DownloadV2RequestCapture } = load('features/downloadv2/DownloadV2RequestCapture.ets', {
  '/DownloadFileNameService': { DownloadFileNameService: class { resolveFileName(input) { return input.suggestedFileName || 'image.png'; } } },
  '/DownloadV2UrlUtils': { inferDownloadSourceHost: () => 'cdn.example.test' }
}, { Date: class extends Date { static now() { return 123456; } } });
const { DownloadV2Service } = load('services/downloadv2/DownloadV2Service.ets');
const { DownloadRuntimeService } = load('services/download/DownloadRuntimeService.ets');
const { BrowserMediaResourceSessionCoordinator } = load('core/browser/BrowserMediaResourceSessionCoordinator.ets', {
  '/MediaResourceSelection': selection
});
const item = (id, family = 'image', actions = ['download', 'copy']) => ({
  id, tabId: 'source-tab', family, kind: family, status: 'downloadable', actions,
  url: `https://cdn.example.test/${id}.png`, displayName: `${id}.png`
});
const boundary = () => ({ windowId: 'source-window', profileId: 'main',
  privacyMode: 'private', dataScope: 'session_ephemeral', sourcePageUrl: 'https://page.example.test/gallery' });

test('selection excludes videos, segments, stale and unavailable IDs, and honors each action', () => {
  const candidates = [item('image'), item('copy-only', 'file', ['copy']), item('audio', 'audio'),
    item('video', 'video'), item('segment', 'segment'), item('unavailable', 'file', [])];
  const ids = ['image', 'image', 'copy-only', 'audio', 'video', 'segment', 'unavailable', 'gone'];
  assert.equal(selection.reconcileMediaResourceSelection(ids, candidates).join(','), 'image,copy-only,audio');
  assert.equal(selection.selectedMediaResourcesForAction(ids, candidates, 'download').map(x => x.id).join(','), 'image,audio');
  assert.equal(selection.selectedMediaResourcesForAction(ids, candidates, 'copy').length, 3);
  assert.equal(selection.reconcileMediaResourceSelection(['image'], []).length, 0, 'removed images leave selection');
  assert.equal(selection.belongsToMediaResourceTab(item('audio-manifest', 'manifest'), 'video'), true);
  assert.equal(selection.belongsToMediaResourceTab({ ...item('audio-manifest', 'manifest'),
    acquisition: { primaryTrack: { role: 'audio' } } }, 'other'), true);
});

test('rapid captures have unique IDs and silent batch confirmation preserves another pending prompt', async () => {
  const capture = new DownloadV2RequestCapture();
  const changes = [];
  capture.setCallbacks({ onPromptChanged: prompt => changes.push(prompt) });
  const pending = capture.createManualRequest('https://cdn.example.test/pending', boundary());
  const first = capture.createManualRequest('https://cdn.example.test/a.png', boundary(), 'a.png', undefined, false);
  const second = capture.createManualRequest('https://cdn.example.test/b.png', boundary(), 'b.png', undefined, false);
  assert.equal(new Set([pending.guid, first.guid, second.guid]).size, 3);
  capture.confirmRequest(first.guid, false);
  capture.confirmRequest(second.guid, false);
  assert.equal(capture.getPendingPrompt().guid, pending.guid);
  assert.equal(changes.length, 1);

  const service = Object.create(DownloadV2Service.prototype);
  service.requestCapture = capture;
  service.downloadTriggerDiagnosticsService = { recordCapturedRequest() {} };
  const created = [];
  service.createTaskFromCapturedRequest = async (request, confirmed) => {
    created.push({ request, confirmed });
    return { guid: request.guid, status: 'queued' };
  };
  const headers = { Referer: 'https://frame.example.test/', Cookie: 'fixture' };
  const task = await service.createConfirmedManualRequest('https://cdn.example.test/c.png', boundary(), 'c.png',
    'cdn.example.test', { headers, userAgent: 'captured-UA', referer: headers.Referer, mimeType: 'image/png' });
  assert.equal(task.status, 'queued');
  assert.equal(created[0].confirmed, true);
  assert.equal(created[0].request.headers.Cookie, 'fixture');
  assert.equal(created[0].request.userAgent, 'captured-UA');
  assert.equal(capture.getPendingPrompt().guid, pending.guid);
  assert.equal(changes.length, 1, 'no per-image prompt events');
});

test('batch queues keep the initiating privacy boundary, continue after errors and report partial failure', async () => {
  const runtime = Object.create(DownloadRuntimeService.prototype);
  runtime.activeBoundary = boundary();
  runtime.downloadPolicyService = { canWriteSessionTasks: () => true };
  const calls = [];
  let release;
  runtime.downloadV2Service = { async createConfirmedManualRequest(url, scope, name, host, context) {
    calls.push({ url, scope, name, host, context });
    if (calls.length === 1) await new Promise(resolve => { release = resolve; });
    if (url.endsWith('b.png')) throw new Error('fixture');
    return { status: url.endsWith('c.png') ? 'failed' : 'queued' };
  } };
  const inputs = ['a', 'b', 'c', 'd'].map(id => ({ url: `https://cdn.example.test/${id}.png`,
    suggestedFileName: `${id}.png`, headers: { Cookie: 'fixture' }, userAgent: 'gallery-UA',
    referer: 'https://page.example.test/gallery', mimeType: 'image/png' }));
  const resultPromise = runtime.requestConfirmedManualDownloads(inputs);
  runtime.activeBoundary.windowId = 'another-window';
  runtime.activeBoundary.privacyMode = 'regular';
  release();
  const result = await resultPromise;
  assert.equal(result.queued, 2);
  assert.equal(result.failed, 2);
  assert.equal(calls.length, 4);
  for (const call of calls) {
    assert.equal(call.scope.windowId, 'source-window');
    assert.equal(call.scope.privacyMode, 'private');
    assert.equal(call.scope.dataScope, 'session_ephemeral');
    assert.equal(call.context.headers.Cookie, 'fixture');
    assert.equal(call.context.userAgent, 'gallery-UA');
  }
  runtime.downloadPolicyService.canWriteSessionTasks = () => false;
  assert.equal((await runtime.requestConfirmedManualDownloads(inputs)).failed, 4);
  assert.equal(calls.length, 4, 'read-only boundaries create no tasks');
});

function sessionFixture(candidates) {
  const session = Object.create(BrowserMediaResourceSessionCoordinator.prototype);
  session.snapshot = { resourceListItems: candidates };
  session.batchDownloadInFlight = false;
  session.applyDiscoverySurfaceState = () => {};
  const resolutions = [];
  session.mediaDiscoveryCoordinator = { resolveMediaResourceAction(input, id, action) {
    resolutions.push({ input, id, action });
    const candidate = candidates.find(x => x.id === id);
    return action === 'copy' ? { copyUrl: candidate.url } : {
      downloadRequest: { url: candidate.url, suggestedFileName: candidate.displayName,
        headers: { Cookie: 'fixture', Referer: 'https://page.example.test/gallery' } }
    };
  } };
  const toasts = [];
  session.mediaDiscoveryHost = { resolveActiveTabId: () => 'source-tab', buildRuntimeContext: () => ({}),
    showToast: value => toasts.push(value) };
  const copies = [];
  session.shell = { copyText: (...args) => copies.push(args) };
  let closed = 0;
  session.closeResources = () => { closed++; };
  return { session, resolutions, toasts, copies, get closed() { return closed; } };
}

test('batch actions resolve captured context once, deduplicate URLs, reject stale tabs and block repeated taps', async () => {
  const first = item('first');
  const duplicate = { ...item('duplicate'), url: first.url };
  const otherTab = { ...item('other-tab'), tabId: 'another-tab' };
  const f = sessionFixture([first, duplicate, item('second'), item('video', 'video'), otherTab]);
  let release;
  const queued = [];
  f.session.downloadService = { async requestConfirmedManualDownloads(requests) {
    queued.push(requests);
    await new Promise(resolve => { release = resolve; });
    return { queued: requests.length, failed: 0 };
  } };
  const ids = ['first', 'duplicate', 'first', 'second', 'video', 'other-tab', 'gone'];
  const running = f.session.handleResourceBatchAction(ids, 'download');
  await f.session.handleResourceBatchAction(ids, 'download');
  assert.equal(queued.length, 1);
  assert.equal(queued[0].length, 2);
  assert.equal(queued[0][0].headers.Cookie, 'fixture');
  assert.equal(f.closed, 1);
  assert.equal(f.resolutions.some(x => x.id === 'video' || x.id === 'other-tab'), false);
  release();
  await running;
  assert.equal(f.session.batchDownloadInFlight, false);
  assert.ok(f.toasts.at(-1).includes('batch_added:2'));
  await f.session.handleResourceBatchAction(ids, 'copy');
  assert.equal(f.copies[0][0], `${first.url}\nhttps://cdn.example.test/second.png`);
  assert.equal(f.closed, 1, 'copy keeps the selection surface open');
  await f.session.handleResourceBatchAction(['gone'], 'download');
  assert.ok(f.toasts.at(-1).includes('batch_unavailable'));
});
