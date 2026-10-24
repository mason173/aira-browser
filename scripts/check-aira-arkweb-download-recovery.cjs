#!/usr/bin/env node
'use strict';
// Production ETS methods, with the documented ArkWeb serialize/deserialize boundary modeled below.
// This checks application ownership and state transitions; real renderer/network recovery still needs device QA.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const log = { info() {}, warn() {}, error() {} };
const states = { PENDING: 0, IN_PROGRESS: 1, PAUSED: 2, COMPLETED: 3, CANCELED: 4, INTERRUPTED: 5 };

function environment({ recoverable = true, admission = true, synchronousFinish = false, finishWithoutProgress = false, rejectResume = false } = {}) {
  let curlStarts = 0;
  let nativeResumes = 0;
  let pausedItemResumes = 0;
  let delegate;
  const starts = [];
  class Item {
    constructor(method = 'GET', url = 'https://example.test/once', state = states.PENDING) {
      this.method = method; this.url = url; this.state = state; this.guid = 'guid'; this.received = 200;
    }
    getGuid() { return this.guid; }
    getUrl() { return this.url; }
    getSuggestedFileName() { return 'file.bin'; }
    getMethod() { return this.method; }
    getMimeType() { return 'application/octet-stream'; }
    getTotalBytes() { return 1000; }
    getReceivedBytes() { return this.received; }
    getCurrentSpeed() { return 0; }
    getState() { return this.state; }
    getLastErrorCode() { return this.state === states.INTERRUPTED ? 30 : 0; }
    start(target) { starts.push(target); this.state = states.IN_PROGRESS; }
    pause() { this.state = states.PAUSED; }
    resume() { pausedItemResumes++; if (this.state !== states.PAUSED) throw Error('not paused'); this.state = states.IN_PROGRESS; }
    cancel() { this.state = states.CANCELED; }
    serialize() {
      if (!recoverable) throw Error('renderer context unavailable');
      return new Uint8Array(Buffer.from(JSON.stringify({ method: this.method, url: this.url, guid: this.guid, received: this.received })));
    }
    static deserialize(bytes) {
      const data = JSON.parse(Buffer.from(bytes).toString());
      const item = new Item(data.method, data.url, states.INTERRUPTED);
      item.guid = data.guid; item.received = data.received; item.deserialized = true;
      return item;
    }
  }
  const webview = {
    WebDownloadItem: Item, WebDownloadState: states,
    WebDownloadDelegate: class {
      onBeforeDownload(fn) { this.before = fn; } onDownloadUpdated(fn) { this.updated = fn; }
      onDownloadFinish(fn) { this.finished = fn; } onDownloadFailed(fn) { this.failed = fn; }
    },
    WebDownloadManager: {
      setDownloadDelegate(next) { delegate = next; },
      resumeDownload(item) {
        assert.ok(item.deserialized, 'resumeDownload requires a deserialized task, never the original failed object');
        if (rejectResume) throw Error('renderer no longer owns this download');
        nativeResumes++;
        item.state = states.IN_PROGRESS;
        if (!finishWithoutProgress) delegate.updated(item);
        if (synchronousFinish) { item.state = states.COMPLETED; delegate.finished(item); }
      }
    }
  };
  class Curl {
    setCallbacks(callbacks) { this.callbacks = callbacks; }
    hasActiveDownload() { return false; }
    getActiveDownloadSnapshot() {}
    getActiveDownloadSnapshots() { return []; }
    async retryDownload() { return false; }
    async reconnectDownload() { throw Error('ArkWeb recovery must not reach libcurl'); }
    async startDirectDownload(snapshot) {
      curlStarts++; const started = { ...snapshot, state: 'IN_PROGRESS' };
      this.callbacks?.onDownloadEvent?.({ type: 'updated', snapshot: started });
      return started;
    }
  }
  const cache = new Map();
  function evaluate(source, filename, extra = {}) {
    const module = { exports: {} };
    vm.runInNewContext(ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, {
      module, exports: module.exports, $r: value => value, Uint8Array, ...extra,
      require(id) {
        if (id === '@kit.ArkWeb') return { webview };
        if (id === '@kit.ArkTS') return { util: { Base64Helper: class {
          encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); }
          decodeSync(value) { return new Uint8Array(Buffer.from(value, 'base64')); }
        } } };
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: log };
        if (id.endsWith('/LibcurlDownloadAdapter')) return { LibcurlDownloadAdapter: Curl };
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        return load(path.resolve(path.dirname(filename), id + '.ets'));
      }
    }, { filename });
    return module.exports;
  }
  function load(filename) {
    if (!cache.has(filename)) cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
    return cache.get(filename);
  }
  const bridgeFile = path.join(sourceRoot, 'platform/download/ArkWebDownloadBridge.ets');
  const { ArkWebDownloadBridge } = load(bridgeFile);
  const { transitionDownloadV2Status } = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2StateMachine.ets'));
  const types = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2Types.ets'));
  const taskModel = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2TaskEntity.ets'));
  const serviceFile = path.join(sourceRoot, 'services/downloadv2/DownloadV2Service.ets');
  const ast = ts.createSourceFile(serviceFile, fs.readFileSync(serviceFile, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'DownloadV2Service');
  const names = ['resumeTask', 'markTaskResumeUnavailable', 'retryTask', 'startPreparedTaskFromRequest', 'startDirectRequest', 'buildCapturedRequestFromTask',
    'markStartedSnapshotAccepted', 'mergePersistenceSnapshot', 'failPreparedTaskStart', 'buildArkWebContextUnavailableFailure',
    'resolveInitialDownloadDriver', 'isHlsCapturedRequest', 'buildPlatformSnapshotFromTask',
    'shouldReconnectPersistedTask', 'reconnectPersistedActiveTasks', 'markTaskRestoreUnavailable', 'buildTaskLostFailure',
    'syncTaskFromPlatformEvent', 'resolveEngineEvent', 'resolveResumeCapability',
    'isPendingState', 'isRunningState', 'isPausedState', 'isPausingState', 'isCompletedState', 'isCanceledState', 'isFailureState'];
  const methods = names.map(name => {
    const method = owner.members.find(member => member.name?.text === name);
    assert.ok(method, `Production method missing: ${name}`);
    return method.getText(ast);
  });
  const { Service } = evaluate('export class Service { ' + methods.join('\n') + ' }', serviceFile, {
    ...types, ...taskModel, hilog: log, resolveAppResourceText: value => value,
    DOWNLOAD_V2_SERVICE_DOMAIN: 0, DOWNLOAD_V2_SERVICE_TAG: 'test', MAX_RECONNECT_TARGET_DIAGNOSTICS: 2,
    bucketRuntimeDiagnosticDuration: () => 'fast'
  });
  function serviceFor(bridge, task) {
    const service = new Service();
    const transitions = [];
    const apply = patch => {
      if (!patch) return task;
      for (const [key, value] of Object.entries(patch)) {
        if (value !== undefined) task[key] = value && typeof value === 'object' ? { ...task[key], ...value } : value;
      }
      return task;
    };
    service.engine = {
      findTask: () => task, listTasks: () => [task], synchronizeTask: (_guid, patch) => apply(patch),
      dispatch: (_guid, event, patch) => {
        const transition = transitionDownloadV2Status(task.status, event);
        if (!transition.valid) return task;
        transitions.push(`${task.status}:${event}:${transition.nextStatus}`);
        return apply({ ...patch, status: transition.nextStatus });
      }
    };
    service.platformAdapter = bridge;
    service.repository = { flushPersistence: async () => {} };
    service.resolveTaskHlsSegmentConcurrency = () => 4;
    service.resolveHlsSegmentConcurrency = () => 4;
    service.persistPageDownloadIdentity = () => {};
    service.persistQueuedAdmissionReason = () => {};
    service.rememberExpectedStatus = () => {};
    service.clearExpectedStatusIfReached = () => {};
    service.shouldSuppressStaleControlEcho = () => false;
    service.mergeRequestContext = current => current;
    service.buildFailureFromPlatformEvent = (_event, failure) => failure;
    service.flushSideEffectsForPlatformEvent = async () => {};
    service.scheduleNextQueuedDownloads = async () => {};
    service.fileNameService = { resolveFileName: () => 'file.bin' };
    service.downloadTriggerDiagnosticsService = { recordStartResult() {} };
    service.downloadQueuePolicyService = { resolveStartAdmission: () => ({ canStartNow: admission, reason: 'waiting_wifi' }) };
    service.downloadNetworkPolicyService = { resolveStartAdmission: () => ({}) };
    service.callbacks = {};
    service.expectedStatusByGuid = {}; service.expectedStatusDeadlineByGuid = {};
    bridge.setCallbacks({ onDownloadEvent: event => service.syncTaskFromPlatformEvent(event) });
    return { service, transitions };
  }
  return { Item, ArkWebDownloadBridge, serviceFor,
    get curlStarts() { return curlStarts; }, get nativeResumes() { return nativeResumes; }, get pausedItemResumes() { return pausedItemResumes; }, starts };
}

function taskFor(method, url, snapshot = {}) {
  return { guid: 'guid', suggestedFileName: 'file.bin', status: 'failed', privacyMode: 'private',
    request: { method, url }, progress: { totalBytes: 1000, receivedBytes: 200, speedBytesPerSecond: 0 },
    runtime: { platformTaskId: snapshot.platformTaskId, platformTaskToken: snapshot.platformTaskToken, resumeCapability: 'retry_only' },
    persistence: { tempFilePath: '/sandbox/file.bin', downloadDriver: 'arkweb' },
    timing: { createdAt: 1, failedAt: 2 }, failure: { code: 'network', retriable: true } };
}

(async () => {
  const failures = [];
  async function test(name, body) {
    try { await body(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.stack}`); }
  }
  for (const [method, url] of [['POST', 'https://example.test/export'], ['GET', 'blob:https://example.test/document'],
    ['GET', 'data:text/plain,hello'], ['GET', 'https://example.test/once?token=used']]) {
    for (const cold of [false, true]) await test(`${method} ${url.split(':')[0]} recovery ${cold ? 'after restart' : 'in process'}`, async () => {
      const env = environment();
      let bridge = new env.ArkWebDownloadBridge();
      const item = new env.Item(method, url);
      bridge.handleDownloadEvent('before_download', item);
      assert.equal(await bridge.startDownload('guid', '/sandbox/file.bin'), true);
      assert.equal(env.curlStarts, 0);
      item.state = states.INTERRUPTED;
      let failedSnapshot;
      bridge.setCallbacks({ onDownloadEvent: event => { failedSnapshot = event.snapshot; } });
      bridge.handleDownloadEvent('failed', item);
      assert.ok(failedSnapshot.platformTaskToken?.startsWith('arkweb-v1:'), 'failed task must carry its serialized context');
      if (cold) bridge = new env.ArkWebDownloadBridge();
      const task = taskFor(method, url, failedSnapshot);
      const { service, transitions } = env.serviceFor(bridge, task);
      assert.equal(await service.retryTask('guid'), true);
      assert.equal(env.nativeResumes, 1);
      assert.equal(env.curlStarts, 0);
      assert.equal(task.status, 'running');
      assert.ok(transitions[0] === 'failed:retry:queued');
      assert.equal(transitions.filter(value => value.endsWith(':queued')).length, 1);
      assert.equal(task.progress.receivedBytes, 200);
    });
  }
  await test('cold active download reconnects without network, with serialized owner intact', async () => {
    const env = environment(); const oldBridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(); oldBridge.handleDownloadEvent('before_download', item);
    await oldBridge.startDownload('guid', '/sandbox/file.bin');
    const task = taskFor('GET', item.url, oldBridge.getActiveDownloadSnapshot('guid'));
    task.status = 'running';
    const bridge = new env.ArkWebDownloadBridge(); const { service } = env.serviceFor(bridge, task);
    await service.reconnectPersistedActiveTasks();
    assert.equal(task.status, 'paused'); assert.equal(env.nativeResumes, 0); assert.equal(env.curlStarts, 0);
    assert.equal(await service.resumeTask(task.guid), true);
    assert.equal(env.nativeResumes, 1); assert.equal(task.status, 'running');
    assert.equal(env.pausedItemResumes, 0, 'cold restore must use manager directly, never paused-item resume');
  });
  for (const token of [undefined, 'arkweb-v1:broken']) await test(`missing/corrupt context fails without GET replay (${token ?? 'missing'})`, async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://example.test/once', { platformTaskId: 'arkweb:guid', platformTaskToken: token });
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), false);
    assert.equal(task.status, 'failed'); assert.equal(env.curlStarts, 0);
    assert.equal(task.failure.code, 'context_lost'); assert.equal(task.failure.retriable, false);
    assert.match(task.failure.message, /download_browser_context_unavailable/);
  });
  await test('Wi-Fi admission queues retry without starting either transport', async () => {
    const env = environment({ admission: false }); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://example.test/once'); const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), true); assert.equal(task.status, 'queued');
    assert.equal(env.nativeResumes, 0); assert.equal(env.curlStarts, 0);
  });
  await test('old ArkWeb records without platform IDs become explicit failures on startup', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('POST', 'https://example.test/export'); task.status = 'running';
    const { service } = env.serviceFor(bridge, task); await service.reconnectPersistedActiveTasks();
    assert.equal(task.status, 'failed'); assert.equal(task.failure.retriable, false); assert.equal(env.curlStarts, 0);
  });
  for (const finishWithoutProgress of [false, true]) await test(`synchronous completion stays completed (skip progress=${finishWithoutProgress})`, async () => {
    const env = environment({ synchronousFinish: true, finishWithoutProgress });
    const bridge = new env.ArkWebDownloadBridge(); const item = new env.Item();
    bridge.handleDownloadEvent('before_download', item); await bridge.startDownload('guid', '/sandbox/file.bin');
    item.state = states.INTERRUPTED;
    const snapshot = bridge.readSnapshot(item); bridge.handleDownloadEvent('failed', item);
    const task = taskFor('GET', item.url, snapshot); const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), true); assert.equal(task.status, 'completed');
    assert.equal(env.nativeResumes, 1); assert.equal(env.curlStarts, 0);
  });
  for (const options of [{ recoverable: false }, { rejectResume: true }]) await test(`unrecoverable renderer fails safely ${JSON.stringify(options)}`, async () => {
    const env = environment(options); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('POST', 'https://example.test/export');
    bridge.handleDownloadEvent('before_download', item); await bridge.startDownload('guid', '/sandbox/file.bin');
    item.state = states.INTERRUPTED; const task = taskFor('POST', item.url, bridge.readSnapshot(item));
    bridge.handleDownloadEvent('failed', item);
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), false); assert.equal(task.status, 'failed');
    assert.equal(task.failure.retriable, false); assert.equal(env.curlStarts, 0);
  });
  await test('a serialized token from a different GUID is rejected', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('GET', 'https://example.test/other', states.INTERRUPTED); item.guid = 'other';
    const task = taskFor('GET', 'https://example.test/once', bridge.readSnapshot(item));
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), false); assert.equal(env.nativeResumes, 0); assert.equal(env.curlStarts, 0);
  });
  await test('libcurl retry also transitions before synchronous progress and starts only once', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://example.test/file'); task.persistence.downloadDriver = 'libcurl';
    const { service, transitions } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask('guid'), true); assert.equal(task.status, 'running');
    assert.equal(env.curlStarts, 1); assert.equal(env.nativeResumes, 0);
    assert.equal(transitions.filter(value => value.endsWith(':queued')).length, 1);
  });
  await test('manual transfer preserves privacy mode at transport boundary', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://example.test/file'); task.persistence.downloadDriver = 'libcurl';
    const { service } = env.serviceFor(bridge, task);
    let snapshot; bridge.startDirectDownload = async value => { snapshot = value; return { ...value, state: 'RUNNING' }; };
    await service.startDirectRequest(service.buildCapturedRequestFromTask(task), '/sandbox/file.bin', task);
    assert.equal(snapshot.privacyMode, 'private'); assert.equal(snapshot.downloadDriver, 'libcurl');
  });
  if (failures.length) { console.error(`${failures.length} ArkWeb recovery contract failures`); process.exitCode = 1; }
})();
