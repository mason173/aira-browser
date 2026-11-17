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

function environment({ recoverable = true, admission = true, synchronousFinish = false, finishWithoutProgress = false,
  rejectResume = false, realSideEffects = false, requireRestoreTarget = false } = {}) {
  let curlStarts = 0;
  let nativeResumes = 0;
  let pausedItemResumes = 0;
  let delegate;
  const starts = [];
  const networkListeners = {};
  class Item {
    constructor(method = 'GET', url = 'https://example.test/once', state = states.PENDING) {
      this.method = method; this.url = url; this.state = state; this.guid = 'guid'; this.received = 200;
    }
    getGuid() { return this.guid; }
    getUrl() { return this.url; }
    getSuggestedFileName() { return 'file.bin'; }
    getMethod() { return this.method; }
    getMimeType() { return 'application/octet-stream'; }
    getTotalBytes() { return this.totalBytes ?? 1000; }
    getReceivedBytes() { return this.received; }
    getCurrentSpeed() { return 0; }
    getState() { return this.state; }
    getLastErrorCode() { return this.state === states.INTERRUPTED ? (this.errorCode ?? 30) : 0; }
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
        assert.ok(item.deserialized || item.state === states.CANCELED,
          'resumeDownload requires a serialized task or the documented canceled original');
        if (rejectResume) throw Error('renderer no longer owns this download');
        nativeResumes++;
        if (requireRestoreTarget) {
          item.state = states.PENDING; delegate.before(item);
          assert.equal(item.state, states.IN_PROGRESS, 'restored before_download must bind the persisted target');
        }
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
    cancelPendingDownload() { return false; }
    async retryDownload() { return false; }
    async resumeDownload() { return false; }
    async reconnectDownload() { throw Error('ArkWeb recovery must not reach libcurl'); }
    async startDirectDownload(snapshot) {
      curlStarts++;
      this.lastRequest = snapshot;
      const started = { ...snapshot, state: 'IN_PROGRESS', downloadDriver: 'libcurl',
        platformTaskId: '42', platformTaskToken: 'libcurl:guid' };
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
      module, exports: module.exports, $r: value => value, Uint8Array, setTimeout, clearTimeout, ...extra,
      require(id) {
        if (id === '@kit.NetworkKit') return { connection: {
          NetBearType: { BEARER_WIFI: 1, BEARER_ETHERNET: 2, BEARER_CELLULAR: 3 },
          hasDefaultNetSync: () => true, getDefaultNetSync: () => ({ netId: 1 }),
          getNetCapabilitiesSync: () => ({ bearerTypes: [1] }),
          createNetConnection: () => ({ on: (name, callback) => { networkListeners[name] = callback; },
            register() {}, unregister() {} })
        } };
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
  const mapper = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2FailureMapper.ets'));
  const taskModel = load(path.join(sourceRoot, 'domain/downloadv2/DownloadV2TaskEntity.ets'));
  const serviceFile = path.join(sourceRoot, 'services/downloadv2/DownloadV2Service.ets');
  const ast = ts.createSourceFile(serviceFile, fs.readFileSync(serviceFile, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'DownloadV2Service');
  const names = ['resumeTask', 'markTaskResumeUnavailable', 'retryTask', 'startPreparedTaskFromRequest', 'startDirectRequest', 'buildCapturedRequestFromTask',
    'markStartedSnapshotAccepted', 'mergePersistenceSnapshot', 'failPreparedTaskStart', 'buildArkWebContextUnavailableFailure',
    'resolveInitialDownloadDriver', 'isHlsCapturedRequest', 'buildPlatformSnapshotFromTask',
    'shouldReconnectPersistedTask', 'reconnectPersistedActiveTasks', 'markTaskRestoreUnavailable', 'buildTaskLostFailure',
    'syncTaskFromPlatformEvent', 'flushSideEffectsForPlatformEvent', 'buildFailureFromPlatformEvent',
    'resolveFailureMessage', 'exportCompletedTaskToSystemDownloads', 'finalizeCompletedTask',
    'findFinalizingTask', 'failFileFinalization', 'failExportWithRetainedSource', 'isFinalizationSourceValid', 'commitAvailableFile', 'ensureTaskDestination', 'notifyTaskChanged', 'resolveTaskChangeKind', 'pauseTask', 'holdQueuedPlatformTask', 'persistQueuedAdmissionReason',
    'resolveQueuedRestartReason', 'resolveAdmissionPauseReason', 'applyNetworkPolicyChange',
    'pauseTaskForNetworkPolicy', 'pauseTransportForTask', 'restorePersistedTaskIntent', 'consumePlatformEvent',
    'shouldIgnoreDuplicatePlatformBeforeDownload', 'mergeHeldRequestMetadata', 'createTaskFromCapturedRequest',
    'resolveEngineEvent', 'resolveResumeCapability',
    'isPendingState', 'isRunningState', 'isPausedState', 'isPausingState', 'isCompletedState', 'isCanceledState', 'isFailureState'];
  const methods = names.map(name => {
    const method = owner.members.find(member => member.name?.text === name);
    assert.ok(method, `Production method missing: ${name}`);
    return method.getText(ast);
  });
  const { Service } = evaluate('export class Service { ' + methods.join('\n') + ' }', serviceFile, {
    ...types, ...taskModel, ...mapper, hilog: log, resolveAppResourceText: value => value,
    DOWNLOAD_V2_SERVICE_DOMAIN: 0, DOWNLOAD_V2_SERVICE_TAG: 'test', MAX_RECONNECT_TARGET_DIAGNOSTICS: 2,
    bucketRuntimeDiagnosticDuration: () => 'fast'
  });
  function serviceFor(bridge, task) {
    const service = new Service();
    const transitions = [];
    const apply = patch => {
      if (!patch) return task;
      Object.assign(task, taskModel.patchDownloadV2TaskEntity(task, patch));
      return task;
    };
    service.engine = {
      findTask: () => task, listTasks: () => [task], synchronizeTask: (_guid, patch) => apply(patch),
      dispatch: (_guid, event, patch) => {
        const transition = transitionDownloadV2Status(task.status, event);
        if (!transition.valid) return undefined;
        transitions.push(`${task.status}:${event}:${transition.nextStatus}`);
        return apply({ ...patch, status: transition.nextStatus });
      }
    };
    service.platformAdapter = bridge;
    let flushes = 0;
    service.repository = { flushPersistence: async () => { flushes++; } };
    service.resolveTaskHlsSegmentConcurrency = () => 4;
    service.resolveHlsSegmentConcurrency = () => 4;
    service.persistPageDownloadIdentity = () => {};
    service.applyRememberedPageDownloadIdentity = () => {};
    service.initialize = async () => {};
    service.startInitializationOnDemand = () => {};
    service.rememberExpectedStatus = () => {};
    service.clearExpectedStatusIfReached = () => {};
    service.shouldSuppressStaleControlEcho = () => false;
    service.mergeRequestContext = current => current;
    if (!realSideEffects) {
      service.flushSideEffectsForPlatformEvent = async () => {};
    }
    service.completedPersistenceGuids = {}; service.completionCommitGuids = {}; service.previousStatusByGuid = {};
    // Transport tests use an immediate verified-file owner; file I/O barriers are exercised separately.
    service.finalizeCompletedTask = async guid => {
      service.engine.dispatch(guid, 'finish', { persistence: { ...task.persistence, completionState: 'available' } });
    };
    service.cleanupLocalTempFile = async () => true;
    service.scheduleNextQueuedDownloads = async () => {};
    service.fileNameService = { resolveFileName: () => 'file.bin' };
    service.downloadTargetResolutionService = { resolveDestinationSnapshot: () => ({ kind: 'system_downloads' }),
      validateDestination: async () => true };
    service.fileResolutionService = { inspectReadableFile: async () => ({ size: task.progress.totalBytes }) };
    service.downloadTriggerDiagnosticsService = { recordStartResult() {}, recordPlatformEvent() {},
      recordCapturedRequest() {}, recordDriverSelection() {} };
    service.downloadQueuePolicyService = { resolveStartAdmission: () => ({ canStartNow: admission, reason: 'waiting_wifi' }) };
    service.downloadNetworkPolicyService = { resolveStartAdmission: () => ({ canStartNow: admission,
      reason: admission ? 'start_now' : 'waiting_wifi' }) };
    const errors = [];
    service.callbacks = { onError: message => errors.push(message) };
    service.expectedStatusByGuid = {}; service.expectedStatusDeadlineByGuid = {};
    bridge.setCallbacks({ onDownloadEvent: event => service.syncTaskFromPlatformEvent(event) });
    return { service, transitions, errors, get flushes() { return flushes; } };
  }
  const { DownloadQueuePolicyService } = load(path.join(sourceRoot, 'services/download/DownloadQueuePolicyService.ets'));
  const { DownloadNetworkPolicyService } = load(path.join(sourceRoot, 'services/download/DownloadNetworkPolicyService.ets'));
  return { Item, ArkWebDownloadBridge, serviceFor, DownloadQueuePolicyService, DownloadNetworkPolicyService,
    networkListeners, taskModel, Service,
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
  await test('ordinary manual and page requests select ArkWeb; only explicit native capabilities select curl', async () => {
    const env = environment(); const service = new env.Service();
    const base = { guid: 'manual-intent', method: 'GET', url: 'https://files.test/file.mp4',
      suggestedFileName: 'kept.mp4', sourceId: 'session:page', boundary: {}, createdAt: 1 };
    for (const extra of [{}, { sourceId: undefined }, { headers: { Cookie: 'page-cookie', Referer: 'https://page.test/' } },
      { url: 'https://files.test/file.zip?note=.m3u8-is-not-a-manifest' }]) {
      assert.equal(service.resolveInitialDownloadDriver({ ...base, ...extra }), 'arkweb');
    }
    for (const extra of [{ nativeReason: 'custom_headers' }, { nativeReason: 'hls' },
      { url: 'https://files.test/media.m3u8?key=fixture' }, { mimeType: 'application/vnd.apple.mpegurl' }]) {
      assert.equal(service.resolveInitialDownloadDriver({ ...base, ...extra }), 'libcurl');
    }
    for (const extra of [{ method: 'POST' }, { url: 'blob:https://page.test/generated' }, { url: 'data:text/plain,hello' },
      { platformSnapshot: { guid: 'owned' } }]) {
      assert.equal(service.resolveInitialDownloadDriver({ ...base, nativeReason: 'custom_headers', ...extra }), 'arkweb');
    }
  });
  await test('manual controller identity reaches the platform and survives callback context merges', async () => {
    const env = environment(); const task = taskFor('GET', 'https://files.test/file.mp4');
    task.request.sourceId = 'instance:source'; task.request.nativeReason = undefined;
    const bridge = new env.ArkWebDownloadBridge(); const { service } = env.serviceFor(bridge, task);
    let started;
    bridge.startDirectDownload = async snapshot => { started = snapshot; return { ...snapshot, state: 'IN_PROGRESS' }; };
    const request = service.buildCapturedRequestFromTask(task);
    assert.equal(request.sourceId, 'instance:source');
    assert.equal(service.buildPlatformSnapshotFromTask(task).sourceId, 'instance:source');
    await service.startDirectRequest(request, '/sandbox/file.bin', task);
    assert.equal(started.sourceId, 'instance:source');
    assert.equal(started.downloadDriver, 'arkweb');
  });
  await test('admitted manual task keeps app GUID through ArkWeb start, interruption and cold resume without curl', async () => {
    const env = environment({ requireRestoreTarget: true });
    let bridge = new env.ArkWebDownloadBridge();
    const delegate = bridge.getDelegateForSource('session:page');
    let item, controllerStarts = 0;
    bridge.registerDownloadSource('session:page', url => {
      controllerStarts++;
      item = new env.Item('GET', url); item.guid = 'native-manual-guid';
      delegate.before(item);
    });
    const task = taskFor('GET', 'https://files.test/one-use-download');
    task.request.sourceId = 'session:page'; task.status = 'queued'; task.timing.failedAt = undefined;
    task.resolvedFileName = 'user-chosen.zip';
    task.request.fileNameLocked = true;
    let { service } = env.serviceFor(bridge, task);
    service.fileNameService.resolveFileName = input => input.suggestedFileName;
    const eventGuids = [];
    bridge.setCallbacks({ onDownloadEvent(event) {
      assert.notEqual(event.type, 'before_download', 'a confirmed manual task must not create another prompt');
      eventGuids.push(event.snapshot.guid); service.syncTaskFromPlatformEvent(event);
    } });
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'manual_confirm'), true);
    assert.equal(task.status, 'running'); assert.equal(controllerStarts, 1);
    assert.equal(task.runtime.platformTaskId, 'arkweb:native-manual-guid');
    assert.equal(task.resolvedFileName, 'user-chosen.zip');
    assert.ok(eventGuids.length > 0 && eventGuids.every(guid => guid === task.guid));
    item.state = states.INTERRUPTED; item.errorCode = 20; delegate.failed(item);
    assert.equal(task.status, 'paused'); assert.equal(task.runtime.pauseReason, 'network');
    assert.ok(task.runtime.platformTaskToken);
    bridge = new env.ArkWebDownloadBridge();
    service = env.serviceFor(bridge, task).service;
    assert.equal(await service.resumeTask(task.guid), true);
    assert.equal(task.status, 'running'); assert.equal(task.runtime.platformTaskId, 'arkweb:native-manual-guid');
    assert.equal(env.nativeResumes, 1); assert.equal(controllerStarts, 1); assert.equal(env.curlStarts, 0);
  });
  await test('pause then resume before the first ArkWeb callback waits for that same request without failure', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const delegate = bridge.getDelegateForSource('session:page');
    let starts = 0;
    bridge.registerDownloadSource('session:page', () => { starts++; });
    const task = taskFor('GET', 'https://files.test/slow-response');
    task.request.sourceId = 'session:page'; task.status = 'queued'; task.timing.failedAt = undefined;
    const { service } = env.serviceFor(bridge, task);
    const starting = service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'confirm');
    for (let i = 0; i < 30 && starts === 0; i++) await Promise.resolve();
    assert.equal(starts, 1); assert.equal(task.status, 'running');
    assert.equal(await service.pauseTask(task.guid), true);
    await starting;
    assert.equal(task.status, 'paused'); assert.equal(task.runtime.pauseReason, 'user');
    const resuming = service.resumeTask(task.guid);
    for (let i = 0; i < 30; i++) await Promise.resolve();
    assert.equal(starts, 1); assert.notEqual(task.status, 'failed');
    const item = new env.Item('GET', task.request.url); item.guid = 'late-native-guid';
    delegate.before(item);
    assert.equal(await resuming, true);
    assert.equal(task.status, 'running'); assert.equal(task.runtime.platformTaskId, 'arkweb:late-native-guid');
    assert.equal(starts, 1); assert.equal(env.curlStarts, 0);
  });
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
  await test('cold active download preserves queued intent while waiting for Wi-Fi', async () => {
    const env = environment({ admission: false }); const oldBridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(); oldBridge.handleDownloadEvent('before_download', item);
    await oldBridge.startDownload('guid', '/sandbox/file.bin');
    const task = taskFor('GET', item.url, oldBridge.getActiveDownloadSnapshot('guid'));
    task.status = 'running';
    const bridge = new env.ArkWebDownloadBridge(); const { service } = env.serviceFor(bridge, task);
    await service.reconnectPersistedActiveTasks();
    assert.equal(task.status, 'queued'); assert.equal(task.runtime.pauseReason, 'wifi_policy');
    assert.equal(env.nativeResumes, 0); assert.equal(env.curlStarts, 0);
    service.downloadQueuePolicyService.resolveStartAdmission = () => ({ canStartNow: true });
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'network_changed'), true);
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
  await test('a serialized token inconsistent with its persisted native GUID is rejected', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('GET', 'https://example.test/other', states.INTERRUPTED); item.guid = 'other';
    const task = taskFor('GET', 'https://example.test/once', bridge.readSnapshot(item));
    task.runtime.platformTaskId = 'arkweb:expected-native-guid';
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
  async function startNetworkScenario(options = {}, method = 'GET', url = 'https://cdn.example/app.apk') {
    const env = environment({ realSideEffects: true, ...options });
    const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(method, url); item.totalBytes = 15631640; item.received = 0;
    bridge.handleDownloadEvent('before_download', item);
    const task = taskFor(method, url, bridge.readSnapshot(item));
    task.status = 'queued'; task.failure = { code: 'none', message: '', retriable: false };
    task.progress = { totalBytes: item.totalBytes, receivedBytes: 0, speedBytesPerSecond: 0 };
    const serviceState = env.serviceFor(bridge, task);
    await serviceState.service.startPreparedTaskFromRequest(
      serviceState.service.buildCapturedRequestFromTask(task), task, 'create_task');
    return { env, bridge, item, task, ...serviceState };
  }
  async function interrupt(scenario, code = 20, received = 12574720) {
    scenario.item.received = received; scenario.item.errorCode = code; scenario.item.state = states.INTERRUPTED;
    scenario.bridge.handleDownloadEvent('failed', scenario.item);
    for (let tick = 0; tick < 3; tick++) await new Promise(resolve => setImmediate(resolve));
  }
  for (const [method, url, code, received] of [
    ['GET', 'https://cdn.example/app.apk', 20, 12574720],
    ['POST', 'https://cdn.example/export', 21, 12574720],
    ['GET', 'blob:https://page.example/id', 22, 12574720],
    ['GET', 'data:application/octet-stream,123', 20, 0]
  ]) await test(`ArkWeb ${code} preserves ${method} ${url.split(':')[0]} as network pause`, async () => {
    const scenario = await startNetworkScenario({}, method, url);
    await interrupt(scenario, code, received);
    assert.equal(scenario.task.status, 'paused'); assert.equal(scenario.task.runtime.pauseReason, 'network');
    assert.equal(scenario.task.progress.receivedBytes, received);
    assert.equal(scenario.task.persistence.tempFilePath, '/sandbox/file.bin');
    assert.equal(scenario.task.persistence.downloadDriver, 'arkweb');
    assert.equal(scenario.env.curlStarts, 0); assert.equal(scenario.env.nativeResumes, 0);
    assert.equal(scenario.errors.length, 0);
    assert.match(scenario.task.failure.message, /download_failure_network/);
    await scenario.service.applyNetworkPolicyChange('network_changed');
    assert.equal(scenario.task.status, 'running'); assert.equal(scenario.task.runtime.pauseReason, 'none');
    assert.equal(scenario.env.nativeResumes, 1); assert.equal(scenario.env.curlStarts, 0);
  });
  await test('server 36 is a retriable failure rather than cancel or network pause', async () => {
    const scenario = await startNetworkScenario(); await interrupt(scenario, 36);
    assert.equal(scenario.task.status, 'failed'); assert.equal(scenario.task.failure.code, 'server');
    assert.equal(scenario.task.failure.retriable, true); assert.equal(scenario.errors.length, 1);
    assert.equal(scenario.env.curlStarts, 0);
  });
  await test('manual pause is never resumed by network or cellular policy changes', async () => {
    const scenario = await startNetworkScenario();
    assert.equal(await scenario.service.pauseTask('guid'), true);
    assert.equal(scenario.task.runtime.pauseReason, 'user');
    await scenario.service.applyNetworkPolicyChange('network_changed');
    await scenario.service.applyNetworkPolicyChange('cellular_download_policy_changed');
    assert.equal(scenario.task.status, 'paused'); assert.equal(scenario.env.nativeResumes, 0);
    assert.equal(scenario.env.pausedItemResumes, 0);
  });
  await test('a user can take ownership of an existing network pause', async () => {
    const scenario = await startNetworkScenario(); await interrupt(scenario);
    assert.equal(await scenario.service.pauseTask('guid'), true);
    assert.equal(scenario.task.runtime.pauseReason, 'user');
    await scenario.service.applyNetworkPolicyChange('network_changed');
    assert.equal(scenario.task.status, 'paused'); assert.equal(scenario.env.nativeResumes, 0);
  });
  await test('Wi-Fi policy pauses a live transfer and resumes it when permitted', async () => {
    const scenario = await startNetworkScenario();
    scenario.service.downloadNetworkPolicyService.resolveStartAdmission = () => ({ canStartNow: false, reason: 'waiting_wifi' });
    await scenario.service.applyNetworkPolicyChange('network_changed');
    assert.equal(scenario.task.status, 'paused'); assert.equal(scenario.task.runtime.pauseReason, 'wifi_policy');
    scenario.service.downloadNetworkPolicyService.resolveStartAdmission = () => ({ canStartNow: true, reason: 'start_now' });
    await scenario.service.applyNetworkPolicyChange('network_changed');
    assert.equal(scenario.task.status, 'running'); assert.equal(scenario.env.pausedItemResumes, 1);
  });
  await test('permission and storage failures retain actionable messages and user retry', async () => {
    for (const [code, message] of [[2, 'permission'], [3, 'storage']]) {
      const scenario = await startNetworkScenario(); await interrupt(scenario, code);
      assert.equal(scenario.task.status, 'failed'); assert.equal(scenario.task.failure.retriable, true);
      assert.match(scenario.task.failure.message, new RegExp('download_failure_' + message));
    }
  });
  await test('all non-retriable failures reject a retry before touching either transport', async () => {
    for (const driver of ['arkweb', 'libcurl']) {
      const env = environment(); const bridge = new env.ArkWebDownloadBridge();
      const task = taskFor('GET', 'https://files.example/file');
      task.persistence.downloadDriver = driver; task.failure = { code: 'unknown', retriable: false };
      const { service } = env.serviceFor(bridge, task);
      assert.equal(await service.retryTask('guid'), false); assert.equal(task.status, 'failed');
      assert.equal(env.curlStarts, 0); assert.equal(env.nativeResumes, 0);
    }
  });
  await test('progress is coalesced, while a network pause flushes persistence immediately', async () => {
    const env = environment({ realSideEffects: true }); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file', { platformTaskToken: 'arkweb-v1:saved' }); task.status = 'running';
    const state = env.serviceFor(bridge, task);
    state.service.syncTaskFromPlatformEvent({ type: 'updated', snapshot: {
      ...state.service.buildPlatformSnapshotFromTask(task), state: 'IN_PROGRESS', receivedBytes: 300
    } });
    assert.equal(state.flushes, 0);
    state.service.syncTaskFromPlatformEvent({ type: 'failed', snapshot: {
      ...state.service.buildPlatformSnapshotFromTask(task), state: 'FAILED', lastErrorCode: 20
    } });
    assert.equal(task.status, 'paused'); assert.equal(state.flushes, 1);
  });
  await test('before_download is held before capture without losing enriched HLS/session metadata', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge(); const item = new env.Item();
    bridge.handleDownloadEvent('before_download', item);
    const { service } = env.serviceFor(bridge, taskFor('GET', item.url));
    service.engine.findTask = () => undefined;
    let captured;
    service.shouldRequireConfirmation = () => true;
    service.requestCapture = { removeManualPendingRequestsForUrl: () => 0, getPendingRequest: () => undefined,
      capturePlatformRequest(snapshot, boundary) {
        assert.equal(item.state, states.CANCELED, 'transport must stop before creating the prompt');
        captured = { ...snapshot, platformSnapshot: snapshot, boundary }; return captured;
      } };
    const snapshot = { ...bridge.readSnapshot(item), sourceId: 'source-A', mimeType: 'application/vnd.apple.mpegurl',
      userAgent: 'Page-UA', contentDisposition: 'attachment; filename=playlist', privacyMode: 'private',
      headers: { Authorization: 'test-context' }, referer: 'https://page.example/export' };
    const boundary = { windowId: 'one', profileId: 'default', privacyMode: 'private', dataScope: 'private' };
    assert.equal(service.consumePlatformEvent({ type: 'before_download', snapshot }, boundary), true);
    assert.equal(captured.platformSnapshot.state, 'PAUSED'); assert.equal(captured.platformSnapshot.transportHeld, true);
    assert.ok(captured.platformSnapshot.platformTaskToken?.startsWith('arkweb-v1:'));
    for (const key of ['sourceId', 'mimeType', 'userAgent', 'contentDisposition', 'privacyMode', 'headers', 'referer']) {
      assert.deepEqual(captured.platformSnapshot[key], snapshot[key]);
    }
    assert.equal(service.isHlsCapturedRequest(captured), true);
  });
  await test('hold rejection reports failure without making an unowned pending prompt', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const { service, errors } = env.serviceFor(bridge, taskFor('GET', 'https://files.example/once'));
    service.engine.findTask = () => undefined; service.shouldRequireConfirmation = () => true;
    let captured = false;
    service.requestCapture = { removeManualPendingRequestsForUrl: () => 0, getPendingRequest: () => undefined,
      capturePlatformRequest() { captured = true; } };
    assert.equal(service.consumePlatformEvent({ type: 'before_download', snapshot: {
      guid: 'missing', url: 'https://files.example/once' } }, {}), true);
    assert.equal(captured, false); assert.equal(errors.length, 1);
  });
  await test('callbacks belonging to an unconfirmed request are consumed as pending updates', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const { service } = env.serviceFor(bridge, taskFor('GET', 'https://files.example/once'));
    service.engine.findTask = () => undefined;
    let incoming; service.requestCapture = { updatePendingPlatformSnapshot: snapshot => { incoming = snapshot; return true; } };
    const snapshot = { guid: 'pending', state: 'FAILED' };
    assert.equal(service.consumePlatformEvent({ type: 'failed', snapshot }, {}), true); assert.equal(incoming, snapshot);
  });
  await test('cold manual pause stays paused and explicit resume binds the saved target', async () => {
    const env = environment({ requireRestoreTarget: true }); const oldBridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('POST', 'https://files.example/export');
    oldBridge.handleDownloadEvent('before_download', item); await oldBridge.startDownload('guid', '/sandbox/file.bin');
    item.state = states.PAUSED;
    const task = taskFor('POST', item.url, oldBridge.readSnapshot(item));
    task.status = 'paused'; task.runtime.pauseReason = 'user';
    const bridge = new env.ArkWebDownloadBridge(); const { service } = env.serviceFor(bridge, task);
    await service.reconnectPersistedActiveTasks();
    assert.equal(task.status, 'paused'); assert.equal(task.runtime.pauseReason, 'user');
    assert.equal(env.nativeResumes, 0);
    assert.equal(await service.resumeTask('guid'), true);
    assert.equal(task.status, 'running'); assert.equal(env.nativeResumes, 1);
    assert.equal(env.starts.at(-1), '/sandbox/file.bin'); assert.equal(env.curlStarts, 0);
  });
  await test('cold network pause resumes its same ArkWeb task with the target path', async () => {
    const env = environment({ requireRestoreTarget: true }); const oldBridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(); oldBridge.handleDownloadEvent('before_download', item);
    item.state = states.INTERRUPTED; item.errorCode = 20;
    const task = taskFor('GET', item.url, oldBridge.readSnapshot(item));
    task.status = 'paused'; task.runtime.pauseReason = 'network';
    const bridge = new env.ArkWebDownloadBridge(); const { service } = env.serviceFor(bridge, task);
    await service.reconnectPersistedActiveTasks();
    assert.equal(task.status, 'running'); assert.equal(env.nativeResumes, 1);
    assert.equal(env.starts.at(-1), '/sandbox/file.bin'); assert.equal(env.curlStarts, 0);
  });
  await test('network policy holds a pending ArkWeb transport then restores with target on admission', async () => {
    const env = environment({ requireRestoreTarget: true }); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(); bridge.handleDownloadEvent('before_download', item);
    item.pause = () => { throw Error('17100019: pending cannot pause'); };
    const task = taskFor('GET', item.url, bridge.readSnapshot(item)); task.status = 'running';
    const { service } = env.serviceFor(bridge, task);
    service.downloadNetworkPolicyService.resolveStartAdmission = () => ({ canStartNow: false, reason: 'offline_network' });
    await service.applyNetworkPolicyChange('network_changed');
    assert.equal(task.status, 'paused'); assert.equal(task.runtime.pauseReason, 'network');
    assert.equal(item.state, states.CANCELED); assert.equal(task.persistence.resumeMode, 'none');
    service.downloadNetworkPolicyService.resolveStartAdmission = () => ({ canStartNow: true, reason: 'start_now' });
    await service.applyNetworkPolicyChange('network_changed');
    assert.equal(task.status, 'running'); assert.equal(env.starts.at(-1), '/sandbox/file.bin');
  });
  await test('manual pause records user intent before asynchronous adapter callbacks', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'running';
    const { service } = env.serviceFor(bridge, task);
    let release; const gate = new Promise(resolve => { release = resolve; });
    bridge.pauseDownload = async () => { assert.equal(task.runtime.pauseReason, 'user'); await gate; return false; };
    const pending = service.pauseTask('guid'); assert.equal(task.runtime.pauseReason, 'user');
    release(); assert.equal(await pending, false); assert.equal(task.runtime.pauseReason, 'none');
    assert.equal(service.expectedStatusByGuid.guid, undefined);
  });
  await test('network failure without a restorable context fails explicitly without replay', async () => {
    const scenario = await startNetworkScenario({ recoverable: false }); await interrupt(scenario);
    assert.equal(scenario.task.status, 'failed'); assert.equal(scenario.task.failure.code, 'context_lost');
    assert.equal(scenario.task.failure.retriable, false); assert.equal(scenario.env.curlStarts, 0);
  });
  for (const admission of [false, true]) await test(`creation returns current state and preserves held context (admission=${admission})`, async () => {
    const env = environment({ admission, requireRestoreTarget: true, synchronousFinish: admission });
    const bridge = new env.ArkWebDownloadBridge(); const item = new env.Item('POST', 'https://files.example/export');
    bridge.handleDownloadEvent('before_download', item);
    const held = bridge.holdDownload('guid');
    const task = taskFor('POST', item.url, held); const { service } = env.serviceFor(bridge, task);
    const request = service.buildCapturedRequestFromTask(task); request.platformSnapshot = held;
    service.downloadPolicyService = { canWriteSessionTasks: () => true };
    service.downloadTargetResolutionService = { ...service.downloadTargetResolutionService, resolveTargetPlan: async () => ({ fileName: 'file.bin',
      tempFilePath: '/sandbox/file.bin', partialFilePath: '/sandbox/file.bin', initialDisplayPath: 'Downloads/file.bin' }) };
    service.notifyQueuedAdmission = () => {};
    service.engine.createTask = input => {
      Object.assign(task, env.taskModel.createDownloadV2TaskEntity({ ...input, ...input.boundary,
        status: input.requiresConfirmation ? 'awaiting_confirmation' : 'queued' }));
      return structuredClone(task);
    };
    // The production repository returns snapshots, not mutable references to future states.
    const synchronize = service.engine.synchronizeTask, dispatch = service.engine.dispatch;
    service.engine.synchronizeTask = (...args) => structuredClone(synchronize(...args));
    service.engine.dispatch = (...args) => structuredClone(dispatch(...args));
    service.engine.findTask = () => structuredClone(task);
    const result = await service.createTaskFromCapturedRequest(request, true);
    assert.equal(result.status, admission ? 'completed' : 'queued');
    assert.equal(result.status, task.status);
    if (!admission) {
      assert.equal(task.runtime.platformTaskId, held.platformTaskId);
      assert.equal(task.runtime.platformTaskToken, held.platformTaskToken);
      assert.equal(task.runtime.pauseReason, 'wifi_policy');
      assert.equal(env.nativeResumes, 0); assert.equal(item.state, states.CANCELED);
      const restoredBridge = new env.ArkWebDownloadBridge(); const restored = env.serviceFor(restoredBridge, task).service;
      restored.downloadQueuePolicyService.resolveStartAdmission = () => ({ canStartNow: true });
      assert.equal(await restored.startPreparedTaskFromRequest(restored.buildCapturedRequestFromTask(task), task, 'network_changed'), true);
      assert.equal(task.status, 'running'); assert.equal(env.nativeResumes, 1);
      assert.equal(env.starts.at(-1), '/sandbox/file.bin');
    }
    assert.equal(env.curlStarts, 0);
  });
  await test('admission refusal holds an unstarted browser request before leaving it queued', async () => {
    const env = environment({ admission: false }); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item(); bridge.handleDownloadEvent('before_download', item);
    const task = taskFor('GET', item.url, bridge.readSnapshot(item)); task.status = 'queued';
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'create_task'), false);
    assert.equal(task.status, 'queued'); assert.equal(item.state, states.CANCELED);
    assert.ok(task.runtime.platformTaskToken?.startsWith('arkweb-v1:')); assert.equal(env.nativeResumes, 0);
  });
  await test('late running echoes cannot revoke a manual pause after control grace', async () => {
    const scenario = await startNetworkScenario(); await scenario.service.pauseTask('guid');
    scenario.service.expectedStatusByGuid.guid = undefined;
    scenario.item.state = states.IN_PROGRESS;
    scenario.bridge.handleDownloadEvent('updated', scenario.item);
    assert.equal(scenario.task.status, 'paused'); assert.equal(scenario.task.runtime.pauseReason, 'user');
    assert.equal(scenario.item.state, states.PAUSED);
  });
  for (const manual of [true, false]) await test(`exported conflict name reaches task presentation and toast (manual=${manual})`, async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'completed';
    const { service } = env.serviceFor(bridge, task);
    const infos = []; service.callbacks.onInfo = message => infos.push(message);
    service.persistFinishedDownload = async () => ({ isExported: true, status: 'saved',
      finalFileUri: 'file://downloads/file(1).bin', finalDisplayPath: 'Downloads/file(1).bin', finalFileName: 'file(1).bin' });
    service.buildSavedLocationMessage = (_kind, fileName) => fileName;
    service.recordDownloadActivityOnce = () => {};
    service.downloadTargetResolutionService = { ...service.downloadTargetResolutionService, resolveCompletionTargetPolicy: () => ({ shouldPromptForExport: true }) };
    if (manual) assert.equal(await service.exportCompletedTaskToSystemDownloads('guid'), true);
    else {
      task.status = 'running'; task.persistence.completionState = 'finalizing';
      await env.Service.prototype.finalizeCompletedTask.call(service, 'guid', 'file.bin', false);
    }
    assert.equal(task.resolvedFileName, 'file(1).bin'); assert.equal(infos.at(-1), 'file(1).bin');
    assert.equal(task.persistence.finalDisplayPath, 'Downloads/file(1).bin');
  });
  await test('capability changes notify the network policy consumer', async () => {
    const env = environment(); const policy = new env.DownloadNetworkPolicyService();
    const snapshots = []; policy.startMonitoring(snapshot => snapshots.push(snapshot));
    assert.equal(typeof env.networkListeners.netCapabilitiesChange, 'function');
    env.networkListeners.netCapabilitiesChange({});
    assert.equal(snapshots.at(-1).kind, 'wifi'); assert.equal(snapshots.at(-1).available, true);
  });
  await test('revoked task destination blocks the unified start path without losing browser ownership', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge(); const item = new env.Item('POST', 'https://files.example/export');
    bridge.handleDownloadEvent('before_download', item); const snapshot = bridge.holdDownload('guid');
    const task = taskFor('POST', item.url, snapshot); task.status = 'queued';
    task.persistence.destination = { kind: 'directory', uri: 'file://folder/original' };
    const { service } = env.serviceFor(bridge, task);
    service.downloadTargetResolutionService.validateDestination = async destination => {
      assert.equal(destination.uri, 'file://folder/original'); return false;
    };
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'create_task'), false);
    assert.equal(task.status, 'failed'); assert.equal(task.failure.code, 'permission'); assert.equal(task.failure.retriable, true);
    assert.equal(task.runtime.platformTaskToken, snapshot.platformTaskToken);
    assert.equal(env.nativeResumes, 0); assert.equal(env.curlStarts, 0);
  });
  await test('a queued task can receive a real paused snapshot before running progress', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('GET', 'https://files.example/file', states.PAUSED);
    bridge.handleDownloadEvent('updated', item);
    const task = taskFor('GET', item.url, bridge.readSnapshot(item)); task.status = 'queued';
    const { service, transitions } = env.serviceFor(bridge, task);
    assert.equal(service.syncTaskFromPlatformEvent({ type: 'updated', snapshot: bridge.readSnapshot(item) }), true);
    assert.equal(task.status, 'paused');
    assert.deepEqual(transitions, ['queued:start:running', 'running:pause:paused']);
  });
  await test('two queue drains cannot start the same task while the adapter is awaiting readiness', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'queued';
    task.persistence.downloadDriver = 'libcurl'; task.timing.failedAt = undefined;
    const { service } = env.serviceFor(bridge, task);
    let release, starts = 0; const gate = new Promise(resolve => { release = resolve; });
    bridge.startDirectDownload = async snapshot => { starts++; await gate; return { ...snapshot, state: 'RUNNING' }; };
    const request = service.buildCapturedRequestFromTask(task);
    const first = service.startPreparedTaskFromRequest(request, task, 'create_task');
    const second = service.startPreparedTaskFromRequest(request, task, 'network_changed');
    release(); await Promise.all([first, second]);
    assert.equal(starts, 1, 'Starting a task must reserve its queue slot before awaiting the adapter');
  });
  await test('continuing a paused task obeys network admission without losing the resume intent', async () => {
    const env = environment({ admission: false }); const bridge = new env.ArkWebDownloadBridge();
    const item = new env.Item('GET', 'https://example.test/file', states.PAUSED);
    bridge.handleDownloadEvent('updated', item);
    const task = taskFor('GET', item.url, bridge.readSnapshot(item)); task.status = 'paused';
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.resumeTask('guid'), true);
    assert.equal(env.pausedItemResumes, 0, 'Waiting for Wi-Fi must apply to resume too');
    assert.equal(task.status, 'queued');
    bridge.handleDownloadEvent('updated', item);
    assert.equal(task.status, 'queued', 'A paused platform echo must not cancel the queued resume');
    service.downloadQueuePolicyService.resolveStartAdmission = () => ({ canStartNow: true });
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(task), task, 'network_changed'), true);
    assert.equal(env.pausedItemResumes, 1); assert.equal(env.curlStarts, 0); assert.equal(task.status, 'running');
  });
  await test('an immediate completion during paused-task resume is retained', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'paused';
    const { service } = env.serviceFor(bridge, task);
    bridge.getActiveDownloadSnapshot = () => ({ ...service.buildPlatformSnapshotFromTask(task), state: 'PAUSED' });
    bridge.resumeDownload = async () => {
      service.syncTaskFromPlatformEvent({ type: 'finished', snapshot: {
        ...service.buildPlatformSnapshotFromTask(task), state: 'COMPLETED', receivedBytes: 1000
      } }); return true;
    };
    assert.equal(await service.resumeTask('guid'), true);
    assert.equal(task.status, 'completed');
  });
  await test('a final completion callback can settle a paused task', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'paused';
    const { service } = env.serviceFor(bridge, task);
    service.syncTaskFromPlatformEvent({ type: 'finished', snapshot: {
      ...service.buildPlatformSnapshotFromTask(task), state: 'COMPLETED', receivedBytes: 1000
    } });
    assert.equal(task.status, 'completed');
  });
  await test('native progress follows a safe full restart instead of retaining an old percentage', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file'); task.status = 'running';
    task.persistence.downloadDriver = 'libcurl';
    const { service } = env.serviceFor(bridge, task);
    service.syncTaskFromPlatformEvent({ type: 'updated', snapshot: {
      ...service.buildPlatformSnapshotFromTask(task), state: 'RUNNING', receivedBytes: 0, totalBytes: 0
    } });
    assert.equal(task.progress.receivedBytes, 0); assert.equal(task.progress.totalBytes, 0);
  });
  await test('a queued resume whose native handle was lost can rebuild after restart', async () => {
    const env = environment(); const bridge = new env.ArkWebDownloadBridge();
    const task = taskFor('GET', 'https://files.example/file');
    task.persistence.downloadDriver = 'libcurl'; task.persistence.resumeMode = 'queued_live_resume';
    task.runtime.platformTaskId = 'old-native-handle'; task.failure.code = 'context_lost';
    const { service } = env.serviceFor(bridge, task);
    assert.equal(await service.retryTask(task.guid), true);
    assert.equal(env.curlStarts, 1); assert.equal(task.status, 'running');
  });
  await test('a task awaiting its adapter occupies the real concurrency limit', async () => {
    const env = environment(), bridge = new env.ArkWebDownloadBridge();
    const first = taskFor('GET', 'https://files.example/one'), second = taskFor('GET', 'https://files.example/two');
    second.guid = 'two';
    for (const task of [first, second]) {
      task.status = 'queued'; task.persistence.downloadDriver = 'libcurl'; task.timing.failedAt = undefined;
    }
    const { service } = env.serviceFor(bridge, first), tasks = [first, second];
    service.engine.findTask = guid => tasks.find(task => task.guid === guid);
    service.engine.listTasks = () => tasks;
    service.downloadQueuePolicyService = new env.DownloadQueuePolicyService({ maxConcurrentDownloads: 1 });
    service.downloadNetworkPolicyService.resolveStartAdmission = () => ({ canStartNow: true, reason: 'start_now' });
    let release, starts = 0; const gate = new Promise(resolve => { release = resolve; });
    bridge.startDirectDownload = async snapshot => { starts++; await gate; return { ...snapshot, state: 'RUNNING' }; };
    const pending = service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(first), first, 'create_task');
    for (let tick = 0; tick < 3; tick++) await new Promise(resolve => setImmediate(resolve));
    assert.equal(await service.startPreparedTaskFromRequest(service.buildCapturedRequestFromTask(second), second, 'create_task'), false);
    assert.equal(second.status, 'queued'); assert.equal(starts, 1);
    release(); await pending;
  });
  if (failures.length) { console.error(`${failures.length} ArkWeb recovery contract failures`); process.exitCode = 1; }
})();
