#!/usr/bin/env node
'use strict';
// Execute production engine/entity/service methods with controlled file/persistence boundaries.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const log = { info() {}, warn() {}, error() {} };
const cache = new Map();
function evaluate(source, filename, extras = {}) {
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText, { module, exports: module.exports, ...extras,
    require(id) {
      if (id.endsWith('/DownloadV2Repository')) return {};
      return load(path.resolve(path.dirname(filename), `${id}.ets`));
    }
  }, { filename });
  return module.exports;
}
function load(filename) {
  if (!cache.has(filename)) cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
  return cache.get(filename);
}
const types = load(path.join(root, 'domain/downloadv2/DownloadV2Types.ets'));
const model = load(path.join(root, 'domain/downloadv2/DownloadV2TaskEntity.ets'));
const mapper = load(path.join(root, 'domain/downloadv2/DownloadV2FailureMapper.ets'));
const { DownloadV2Engine } = load(path.join(root, 'core/downloadv2/DownloadV2Engine.ets'));
const serviceFile = path.join(root, 'services/downloadv2/DownloadV2Service.ets');
const ast = ts.createSourceFile(serviceFile, fs.readFileSync(serviceFile, 'utf8'), ts.ScriptTarget.Latest, true);
const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'DownloadV2Service');
const body = owner.members.filter(node => !ts.isConstructorDeclaration(node)).map(node => node.getText(ast)).join('\n');
const { Service } = evaluate(`export class Service { ${body} }`, serviceFile, {
  ...types, ...model, ...mapper, hilog: log, $r: key => key, resolveAppResourceText: value => value,
  DOWNLOAD_V2_SERVICE_DOMAIN: 0, DOWNLOAD_V2_SERVICE_TAG: 'test', MAX_RECONNECT_TARGET_DIAGNOSTICS: 2,
  bucketRuntimeDiagnosticDuration: () => 'fast', DownloadV2Service: { CONTROL_SYNC_GRACE_MS: 2200 }
});
function environment(options = {}) {
  let task = model.createDownloadV2TaskEntity({
    guid: 'guid', profileId: 'default', privacyMode: options.private ? 'private' : 'regular', dataScope: 'persistent',
    status: options.status ?? 'running', suggestedFileName: 'file.bin',
    request: { method: 'GET', url: options.hls ? 'https://media.test/movie.m3u8' : 'https://files.test/file' },
    progress: { receivedBytes: options.bytes ?? 1000, totalBytes: options.bytes ?? 1000 },
    persistence: { tempFilePath: '/app/file.bin', partialFilePath: '/app/file.bin',
      downloadDriver: options.hls ? 'libcurl' : 'arkweb', completionState: options.completionState,
      destination: options.destination ?? { kind: options.local ? 'session_temp' : 'system_downloads' } },
    runtime: { platformTaskId: 'arkweb:guid', platformTaskToken: 'arkweb-v1:token' }
  });
  const notifications = [], changes = [], errors = [], infos = [], inspected = [];
  let flushes = 0, copies = 0, cleaned = 0, networkStarts = 0;
  const state = { notifications, changes, errors, infos, inspected,
    files: new Map([['/app/file.bin', options.sourceSize ?? (options.bytes ?? 1000)], ['/docs/file(1).bin', options.targetSize ?? (options.bytes ?? 1000)]]),
    get task() { return task; }, get flushes() { return flushes; }, get copies() { return copies; },
    get cleaned() { return cleaned; }, get networkStarts() { return networkStarts; },
    remove() { task = undefined; }, options };
  const repository = {
    initialize: async () => {}, findOne: () => task && structuredClone(task), list: () => task ? [structuredClone(task)] : [],
    patch(_lookup, patch) { if (!task) return; task = model.patchDownloadV2TaskEntity(task, patch); return structuredClone(task); },
    upsert(value) { task = structuredClone(value); return structuredClone(task); },
    remove() { task = undefined; return true; },
    async flushPersistence() { flushes++; if (options.flushHook) await options.flushHook(flushes, state); }
  };
  const engine = new DownloadV2Engine(repository);
  const service = new Service(); service.engine = engine; service.repository = repository;
  service.callbacks = { onTaskChanged: value => changes.push(value.status), onError: value => errors.push(value), onInfo: value => infos.push(value) };
  service.systemNotificationService = { handleTaskChanged(value, previousStatus) { if (value.privacyMode !== 'private' && value.status !== previousStatus) notifications.push(value.status); } };
  engine.setObserver(service.buildEngineObserver());
  service.fileNameService = { resolveFileName: () => 'file.bin' };
  service.fileResolutionService = {
    async inspectReadableFile(location) { inspected.push(location); if (options.inspectHook) await options.inspectHook(location, state);
      const size = state.files.get(location); return size === undefined ? undefined : { size }; },
    async persistToDestination(_source, _name, destination) { copies++; state.lastDestination = destination;
      if (options.copyHook) await options.copyHook(state);
      return options.copyResult ?? { status: 'exported', isExported: true, finalFileUri: '/docs/file(1).bin',
        finalFileName: 'file(1).bin', finalDisplayPath: 'Downloads/file(1).bin' }; }
  };
  service.downloadTargetResolutionService = {
    resolveDestinationSnapshot: () => ({ kind: 'system_downloads' }),
    resolveCompletionTargetPolicy: () => ({ shouldPromptForExport: !options.local, tempDisplayPath: 'Local/file.bin' }),
    validateDestination: async () => options.authorized !== false,
    selectDestination: async () => options.selection
  };
  service.platformAdapter = { hasActiveDownload: () => false,
    reconnectDownload: async () => { networkStarts++; throw Error('File finalization must not reconnect transport'); } };
  service.cleanupLocalTempFile = async () => { cleaned++; return true; };
  service.recordDownloadActivityOnce = () => {};
  service.scheduleNextQueuedDownloads = async () => {};
  service.applyNetworkPolicyChange = async () => {};
  service.shouldSuppressStaleControlEcho = () => false;
  service.resolveTaskHlsSegmentConcurrency = () => 4;
  state.service = service; state.engine = engine;
  state.finish = () => service.syncTaskFromPlatformEvent({ type: 'finished', snapshot: {
    ...service.buildPlatformSnapshotFromTask(task), state: 'COMPLETED', lastErrorCode: 0
  } });
  return state;
}
async function settled(state) {
  for (let i = 0; i < 60; i++) {
    if (!state.service.completedPersistenceGuids.guid) return;
    await new Promise(resolve => setImmediate(resolve));
  }
  throw Error('File finalization did not settle');
}
function gate() { let release; const promise = new Promise(resolve => { release = resolve; }); return { promise, release }; }
(async () => {
  const failures = [];
  async function test(name, run) { try { await run(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.stack}`); } }
  await test('network completion stays saving until validated export and durable completion', async () => {
    const copy = gate(); const state = environment({ copyHook: () => copy.promise });
    state.finish(); await new Promise(resolve => setImmediate(resolve));
    assert.equal(state.task.status, 'running'); assert.equal(state.task.persistence.completionState, 'finalizing');
    assert.equal(state.notifications.includes('completed'), false); assert.equal(state.changes.includes('completed'), false);
    assert.equal(state.cleaned, 0); state.finish(); assert.equal(state.copies, 1);
    copy.release(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.task.persistence.completionState, 'available');
    assert.equal(state.task.resolvedFileName, 'file(1).bin'); assert.equal(state.task.persistence.finalFileUri, '/docs/file(1).bin');
    assert.equal(state.notifications.filter(value => value === 'completed').length, 1); assert.equal(state.cleaned, 1);
  });
  for (const point of [1, 2, 3]) await test(`persistence failure at barrier ${point} never completes or removes source`, async () => {
    const state = environment({ flushHook: async count => { if (count === point) throw Error('storage unavailable'); } });
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'failed'); assert.equal(state.task.persistence.completionState, 'export_failed');
    assert.equal(state.notifications.includes('completed'), false); assert.equal(state.changes.includes('completed'), false);
    assert.equal(state.cleaned, 0); assert.equal(state.task.persistence.tempFilePath, '/app/file.bin');
  });
  for (const sourceSize of [undefined, 0, 500]) await test(`missing or incomplete HTTP source cannot complete (${sourceSize})`, async () => {
    const state = environment({ sourceSize }); if (sourceSize === undefined) state.files.delete('/app/file.bin');
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'failed'); assert.equal(state.copies, 0); assert.equal(state.cleaned, 0);
    assert.match(state.task.failure.message, /file_verification_failed/);
    assert.equal(state.task.failure.retriable, false);
    state.service.downloadTargetResolutionService.selectDestination = async () => { throw Error('unrecoverable source must not open a picker'); };
    assert.equal(await state.service.chooseTaskLocation('guid'), false);
    assert.equal(await state.service.retryTask('guid'), false);
  });
  for (const targetSize of [undefined, 0, 900]) await test(`unreadable or mismatched destination cannot complete (${targetSize})`, async () => {
    const state = environment({ targetSize }); if (targetSize === undefined) state.files.delete('/docs/file(1).bin');
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'failed'); assert.equal(state.cleaned, 0); assert.equal(state.notifications.includes('completed'), false);
    assert.equal(state.task.failure.retriable, true, 'an intact source permits a deliberate export retry');
  });
  await test('explicit export cancellation completes only with the retained source verified', async () => {
    const state = environment({ copyResult: { status: 'user_canceled', isExported: false, finalDisplayPath: 'Local/file.bin' } });
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.cleaned, 0);
    assert.equal(state.inspected.filter(value => value === '/app/file.bin').length, 2);
  });
  await test('private local completion keeps the file and does not publish system notification', async () => {
    const state = environment({ private: true, local: true }); state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.copies, 0); assert.equal(state.cleaned, 0);
    assert.equal(state.notifications.length, 0);
  });
  await test('real empty local files complete when transport expected zero bytes', async () => {
    const state = environment({ local: true, bytes: 0 }); state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed');
  });
  await test('HLS validates final output and copy sizes rather than segment transfer totals', async () => {
    const state = environment({ hls: true, sourceSize: 700, targetSize: 700 }); state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.task.persistence.writtenBytes, 700);
  });
  await test('export retry keeps the original received file and never replays network', async () => {
    const options = { copyResult: { status: 'failed', isExported: false, finalDisplayPath: 'Local/file.bin' } };
    const state = environment(options); state.finish(); await settled(state);
    assert.equal(state.task.status, 'failed'); options.copyResult = undefined;
    assert.equal(await state.service.retryTask('guid'), true);
    assert.equal(state.task.status, 'completed'); assert.equal(state.copies, 2); assert.equal(state.networkStarts, 0);
  });
  await test('restart resumes file finalization without ArkWeb or libcurl restoration', async () => {
    const state = environment({ completionState: 'finalizing' }); await state.service.reconnectPersistedActiveTasks();
    assert.equal(state.task.status, 'completed'); assert.equal(state.networkStarts, 0);
  });
  for (const stage of ['inspect', 'copy']) await test(`removal during ${stage} cannot resurrect or clean a task`, async () => {
    const pause = gate(); const state = environment(stage === 'copy' ? { copyHook: () => pause.promise } : { inspectHook: () => pause.promise });
    state.finish(); await new Promise(resolve => setImmediate(resolve)); state.remove(); pause.release(); await settled(state);
    assert.equal(state.task, undefined); assert.equal(state.notifications.includes('completed'), false); assert.equal(state.cleaned, 0);
  });
  await test('failed fixed-directory authorization retains destination and original source', async () => {
    const state = environment({ authorized: false, destination: { kind: 'directory', uri: 'file://folder/A' } });
    state.finish(); await settled(state);
    assert.equal(state.task.failure.code, 'permission'); assert.equal(state.task.persistence.destination.uri, 'file://folder/A');
    assert.equal(state.copies, 0); assert.equal(state.cleaned, 0);
  });
  await test('choosing a replacement destination retries only file export and cancellation is inert', async () => {
    const options = { authorized: false, selection: undefined };
    const state = environment(options); state.finish(); await settled(state);
    const before = JSON.stringify(state.task.persistence);
    assert.equal(await state.service.chooseTaskLocation('guid'), false); assert.equal(JSON.stringify(state.task.persistence), before);
    options.authorized = true; options.selection = { kind: 'directory', uri: 'file://folder/B', label: 'B' };
    assert.equal(await state.service.chooseTaskLocation('guid'), true);
    assert.equal(state.lastDestination.uri, 'file://folder/B'); assert.equal(state.networkStarts, 0);
  });
  await test('a real prompt export freezes the actual selected file URI', async () => {
    const state = environment({ destination: { kind: 'prompt' } }); state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.task.persistence.destination.kind, 'file');
    assert.equal(state.task.persistence.destination.uri, '/docs/file(1).bin');
  });
  await test('save policy changes do not redirect an already captured destination', async () => {
    const state = environment({ destination: { kind: 'directory', uri: 'file://folder/original' } });
    state.service.downloadTargetResolutionService.resolveDestinationSnapshot = () => { throw Error('must not reread settings'); };
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'completed'); assert.equal(state.lastDestination.uri, 'file://folder/original');
  });
  for (const rejectPersistence of [false, true]) await test(`completed rename metadata preserves outcome and rolls back failed persistence (${rejectPersistence})`, async () => {
    const state = environment({ status: 'completed', completionState: 'available', local: true,
      flushHook: async count => { if (rejectPersistence && count === 1) throw Error('disk unavailable'); } });
    state.engine.synchronizeTask('guid', { persistence: { ...state.task.persistence, finalFilePath: '/app/file.bin' } });
    const changed = await state.service.updateCompletedFileAfterRename('guid', '/app/file.bin', {
      fileName: 'renamed.bin', tempFilePath: '/app/renamed.bin', finalDisplayPath: 'Local/renamed.bin'
    });
    assert.equal(changed, rejectPersistence ? 'restored' : 'committed');
    assert.equal(state.task.persistence.tempFilePath, rejectPersistence ? '/app/file.bin' : '/app/renamed.bin');
    assert.equal(state.task.persistence.partialFilePath, state.task.persistence.tempFilePath);
    assert.equal(state.task.persistence.finalFilePath, state.task.persistence.tempFilePath);
    assert.equal(state.task.persistence.completionState, 'available'); assert.equal(state.task.persistence.destination.kind, 'session_temp');
    assert.equal(await state.service.updateCompletedFileAfterRename('guid', '/wrong/file', { fileName: 'wrong.bin' }), 'restored');
  });
  await test('double persistence failure marks rename metadata uncertain so both possible file targets survive', async () => {
    const state = environment({ status: 'completed', completionState: 'available', local: true,
      flushHook: async () => { throw Error('disk unavailable'); } });
    assert.equal(await state.service.updateCompletedFileAfterRename('guid', '/app/file.bin', {
      fileName: 'renamed.bin', tempFilePath: '/app/renamed.bin'
    }), 'uncertain');
    assert.equal(state.task.persistence.tempFilePath, '/app/file.bin');
  });
  for (const sourcePresent of [false, true]) await test(`invalid persisted target retries only if a valid source survives (${sourcePresent})`, async () => {
    const state = environment({ completionState: 'finalizing' });
    state.engine.synchronizeTask('guid', { persistence: { ...state.task.persistence,
      finalFileUri: '/docs/missing.bin', writtenBytes: 1000 } });
    if (!sourcePresent) state.files.delete('/app/file.bin');
    await state.service.reconnectPersistedActiveTasks();
    assert.equal(state.task.status, 'failed'); assert.equal(state.task.failure.retriable, sourcePresent);
    if (sourcePresent) {
      assert.equal(state.task.persistence.finalFileUri, undefined, 'retry must not revalidate the same unusable destination forever');
      assert.equal(await state.service.retryTask('guid'), true); assert.equal(state.copies, 1);
    } else {
      assert.equal(await state.service.chooseTaskLocation('guid'), false);
      assert.equal(await state.service.retryTask('guid'), false);
    }
  });
  await test('a source removed while export fails does not advertise a repairable export', async () => {
    const state = environment({ copyHook: value => { value.files.delete('/app/file.bin'); },
      copyResult: { status: 'failed', isExported: false, finalDisplayPath: 'Local/file.bin' } });
    state.finish(); await settled(state);
    assert.equal(state.task.status, 'failed'); assert.equal(state.task.failure.retriable, false);
    assert.match(state.task.failure.message, /file_verification_failed/);
  });
  for (const requested of ['system_downloads', 'prompt']) for (const manual of [false, true]) for (const kind of ['directory', 'file']) {
    await test(`export retains the actual provider grant (${requested} -> ${kind}, manual=${manual})`, async () => {
      const destination = { kind, uri: kind === 'directory' ? 'file://docs/Download/Aira' : '/docs/file(1).bin', label: 'actual grant' };
      const state = environment({ status: manual ? 'completed' : 'running', completionState: manual ? 'available' : undefined,
        destination: { kind: requested }, copyResult: { status: 'exported', isExported: true,
          finalFileUri: '/docs/file(1).bin', finalFileName: 'file(1).bin', finalDisplayPath: 'Downloads/file(1).bin', destination } });
      if (manual) assert.equal(await state.service.exportCompletedTaskToSystemDownloads('guid'), true);
      else { state.finish(); await settled(state); }
      assert.equal(state.task.status, 'completed');
      assert.equal(state.task.persistence.destination.kind, kind); assert.equal(state.task.persistence.destination.uri, destination.uri);
    });
  }
  if (failures.length) process.exitCode = 1;
})();
