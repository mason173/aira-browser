#!/usr/bin/env node
'use strict';

// Run the production ETS owners with only the platform/persistence boundary replaced.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const folder = 'file://docs/storage/Users/currentUser/Download/Chosen';
const original = folder + '/original.tar.gz';
const boundary = { windowId: 'window-a', profileId: 'profile-main', privacyMode: 'regular',
  dataScope: 'profile_persistent', sourcePageUrl: 'https://example.org/page' };

function environment() {
  const state = { files: new Map(), handles: new Map(), denied: new Set(), events: [], shares: [],
    links: [], failLink: false, failRename: false, failAccess: false, failDelete: '', deleteThenFail: false, badCopy: false,
    validDestination: true, metadataResults: [], requests: [], errors: [], infos: [], changed: 0,
    persistedGrants: new Set(), activatedGrants: [] };
  let nextFd = 0;
  const missing = () => { throw { code: 13900002 }; };
  const platform = {
    fileIo: {
      OpenMode: { READ_ONLY: 0 },
      async open(location, mode) {
        state.events.push(['open', location, mode]);
        if (state.denied.has(location)) throw { code: 13900012 };
        const entry = state.files.get(location); if (!entry) missing();
        const fd = ++nextFd; state.handles.set(fd, entry); return { fd };
      },
      async stat(fd) { const entry = state.handles.get(fd);
        return { isFile: () => !entry.directory, size: entry.bytes.length }; },
      async close(file) { state.handles.delete(file.fd); },
      async access(location) { if (state.failAccess) throw { code: 13900012 }; return state.files.has(location); },
      async rename(source, target) {
        state.events.push(['rename', source, target]);
        if (state.failRename) throw { code: 13900012 };
        if (!state.files.has(source)) missing();
        assert.ok(!state.files.has(target), 'A rename must never overwrite an existing file');
        state.files.set(target, state.files.get(source)); state.files.delete(source);
      }
    },
    fileUri: { FileUri: class { constructor(uri) { this.uri = uri; }
      getFullDirectoryUri() { return this.uri.substring(0, this.uri.lastIndexOf('/')); } },
      getUriFromPath: filename => 'file://app' + filename }
  };
  const files = {
    async inspectReadableFile(uri) { const entry = state.files.get(uri);
      return entry && !entry.directory && !state.denied.has(uri) ? { size: entry.bytes.length } : undefined; },
    async validateDestination() { return state.validDestination; },
    async persistToDestination(source, name, destination) {
      state.events.push(['copy', source]);
      let candidate = name, index = 0;
      while (state.files.has(destination.uri + '/' + candidate)) candidate = (++index) + '-' + name;
      const target = destination.uri + '/' + candidate;
      state.files.set(target, { bytes: state.badCopy ? Buffer.from('x') : Buffer.from(state.files.get(source).bytes) });
      return { status: 'exported', isExported: true, finalFileUri: target, finalFileName: candidate,
        finalDisplayPath: 'Download/Chosen/' + candidate };
    },
    async movePublicDocumentToTrash(uri) {
      state.events.push(['trash', uri]);
      if (state.failDelete === uri) {
        if (state.deleteThenFail) state.files.delete(uri);
        throw { code: 13900012 };
      }
      const existed = state.files.delete(uri); return existed ? 'deleted' : 'missing';
    }
  };
  const cache = new Map();
  function load(relative) {
    const filename = path.resolve(root, relative);
    if (cache.has(filename)) return cache.get(filename);
    const exports = {}; cache.set(filename, exports);
    vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText, { exports, $r: value => value, require(id) {
      if (id === '@kit.CoreFileKit') return platform;
      if (id === '@kit.ArkData') return { uniformTypeDescriptor: {
        UniformDataType: { FILE_URI: 'general.file-uri' }, getUniformDataTypeByMIMEType: () => 'general.file' } };
      if (id === '@kit.ShareKit') return { systemShare: {
        SelectionMode: { SINGLE: 0 }, SharePreviewMode: { DEFAULT: 0 },
        SharedData: class { constructor(record) { this.record = record; } },
        ShareController: class { constructor(data) { this.data = data; }
          async show() { state.shares.push(this.data.record); } } } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {
        getApplicationContext: () => ({ filesDir: '/sandbox/files', cacheDir: '/sandbox/cache' }),
        getUIAbilityContext: () => ({ async openLink(uri, options) {
          state.links.push({ uri, options }); if (state.failLink) throw Error('No file manager');
        } }) } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id.endsWith('/DownloadFileResolutionService')) return { DownloadFileResolutionService: class {} };
      if (id.endsWith('/DownloadLocationDirectoryService')) return { DownloadLocationDirectoryService: class {
        async activateDirectory(uri) { state.activatedGrants.push(uri);
          if (state.persistedGrants.has(uri)) for (const location of state.denied) {
            if (location.startsWith(uri + '/')) state.denied.delete(location);
          } }
        async activateReadableFile(uri) { state.activatedGrants.push(uri);
          if (state.persistedGrants.has(uri)) state.denied.delete(uri); }
      } };
      if (id.includes('/domain/') || id.endsWith('/BrowserModels') ||
        /\/Download(FileAction|FileName|Followup)Service$/.test(id)) {
        return load(path.resolve(path.dirname(filename), id + '.ets'));
      }
      return {};
    } }, { filename });
    return exports;
  }
  const { DownloadFileActionService } = load('services/download/DownloadFileActionService.ets');
  const { DownloadRuntimeService } = load('services/download/DownloadRuntimeService.ets');
  const { DownloadFollowupService } = load('services/download/DownloadFollowupService.ets');
  const actions = new DownloadFileActionService(files);
  const followup = new DownloadFollowupService(files);
  const tasks = new Map();
  const runtime = Object.create(DownloadRuntimeService.prototype);
  Object.assign(runtime, { fileActionService: actions, fileActionGuids: new Set(), fileAvailabilityByGuid: new Map(),
    downloadFollowupService: followup, pageDownloadSources: new Map(), repositoryHydrated: false,
    initialize() {}, getPendingDownloadPrompt() {}, emitPendingDownloadPromptChange() {},
    emitTaskListChange() { state.changed++; }, emitError: value => state.errors.push(value),
    emitInfo: value => state.infos.push(value), downloadPolicyService: {
      canReadSessionTasks: () => true, canWriteSessionTasks: () => true, canExportFile: () => true,
      resolveSavePolicy: () => ({ reason: 'default_location' })
    }, downloadV2Service: {
      findTask: guid => tasks.get(guid), listTasks: () => [...tasks.values()], initialize: async () => {},
      async updateCompletedFileAfterRename(guid, expected, result) {
        state.events.push(['metadata', expected, result.finalFileUri || result.tempFilePath]);
        const current = tasks.get(guid);
        if ((current.persistence.finalFileUri || current.persistence.tempFilePath) !== expected) return 'restored';
        const resultState = state.metadataResults.length ? state.metadataResults.shift() : 'committed';
        if (resultState !== 'committed') return resultState;
        tasks.set(guid, { ...current, suggestedFileName: result.fileName, resolvedFileName: result.fileName,
          persistence: { ...current.persistence, ...Object.fromEntries(Object.entries(result)
            .filter(([key, value]) => key !== 'fileName' && value !== undefined)) } });
        return 'committed';
      },
      async createConfirmedManualRequest(url, requestBoundary, name, host, context) {
        state.requests.push({ url, boundary: requestBoundary, name, host, context });
        return { guid: 'new-guid', status: 'queued' };
      }
    } });
  const task = (persistence = {}) => ({
    ...boundary, guid: 'download-a', status: 'completed', suggestedFileName: 'original.tar.gz',
    resolvedFileName: 'original.tar.gz', request: { method: 'GET', url: 'https://files.example.org/original.tar.gz',
      originalUrl: 'https://files.example.org/original.tar.gz', sourcePageUrl: boundary.sourcePageUrl, sourceHost: 'files.example.org' },
    persistence: { finalFileUri: original, completionState: 'available', destination: { kind: 'directory', uri: folder },
      finalDisplayPath: 'Download/Chosen/original.tar.gz', ...persistence },
    runtime: {}, failure: { retriable: false }
  });
  const put = (uri, content = 'original payload') => state.files.set(uri, { bytes: Buffer.from(content) });
  return { state, actions, followup, runtime, task, tasks, put, files };
}

let failures = 0;
async function check(name, run) {
  try { await run(); console.log('PASS ' + name); }
  catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.stack); }
}

(async () => {
  await check('file management opens Huawei directory deeplink; sharing is a separate action', async () => {
    const f = environment(); f.put(original);
    const task = { suggestedFileName: 'original.tar.gz', finalFileUri: original };
    assert.equal((await f.followup.openLocation(task)).success, true);
    assert.equal(f.state.links[0].uri, 'filemanager://openDirectory');
    assert.equal(f.state.links[0].options.parameters.fileUri, original);
    assert.equal(f.state.shares.length, 0);
    assert.equal((await f.followup.shareFile(task)).success, true);
    assert.equal(f.state.shares[0].uri, original);
    f.state.failLink = true;
    assert.equal((await f.followup.openLocation(task)).success, false);
    assert.equal(f.state.shares.length, 1, 'A file-manager failure must not launch Share');
  });
  await check('readability distinguishes missing, zero-byte files, directories, and revoked access', async () => {
    const f = environment(); f.put(original, '');
    assert.equal(await f.actions.inspect(original), 'available');
    f.state.denied.add(original); assert.equal(await f.actions.inspect(original), 'unavailable');
    assert.equal(await f.actions.inspect(folder + '/missing'), 'missing');
    f.state.files.set(folder, { bytes: Buffer.alloc(0), directory: true });
    assert.equal(await f.actions.inspect(folder), 'unavailable');
    assert.equal(f.state.handles.size, 0);
    assert.ok(f.state.events.filter(event => event[0] === 'open').every(event => event[2] === 0));
  });
  await check('restored tasks reactivate only their recorded provider grant before opening or renaming', async () => {
    const f = environment(); f.put(original); f.state.denied.add(original); f.state.persistedGrants.add(folder);
    assert.equal(await f.actions.inspectTask(f.task()), 'available');
    assert.deepEqual(f.state.activatedGrants, [folder]);
    f.state.denied.add(original); f.state.persistedGrants.clear(); f.state.activatedGrants.length = 0;
    assert.equal(await f.actions.inspectTask(f.task({ destination: { kind: 'file', uri: original } })), 'unavailable');
    assert.deepEqual(f.state.activatedGrants, [original], 'A file grant never becomes a parent grant');
    f.state.persistedGrants.add(original);
    assert.equal(await f.actions.inspectTask(f.task({ destination: { kind: 'file', uri: original } })), 'available');
  });
  await check('sandbox rename preserves compound extension and existing conflicts; metadata failure restores original', async () => {
    const f = environment(), source = '/sandbox/cache/original.tar.gz';
    f.put(source); f.put('/sandbox/cache/renamed.tar.gz', 'untouched');
    const task = f.task({ finalFileUri: undefined, tempFilePath: source, destination: { kind: 'session_temp' } });
    f.tasks.set(task.guid, task);
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), true);
    const next = f.tasks.get(task.guid);
    assert.equal(next.resolvedFileName, 'renamed (1).tar.gz');
    assert.equal(f.state.files.get('/sandbox/cache/renamed.tar.gz').bytes.toString(), 'untouched');
    assert.ok(f.state.files.has(next.persistence.tempFilePath));
    f.state.metadataResults.push('restored');
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'again', boundary), false);
    assert.ok(f.state.files.has(next.persistence.tempFilePath));
    assert.ok(!f.state.files.has('/sandbox/cache/again.tar.gz'));
  });
  await check('sandbox path checks and failed access never claim an external URI or leak a reserved filename', async () => {
    const f = environment(), source = '/sandbox/cache/original.tar.gz';
    f.put(source); const task = f.task({ finalFileUri: undefined, tempFilePath: source });
    f.state.failAccess = true; assert.equal((await f.actions.prepareRename(task, 'renamed')).failure, 'failed');
    f.state.failAccess = false; const result = await f.actions.prepareRename(task, 'renamed');
    assert.equal(result.plan.fileName, 'renamed.tar.gz');
    await f.actions.rollbackRename(result.plan); f.actions.releaseRename(result.plan);
    f.put('/storage/public/original.tar.gz');
    assert.equal((await f.actions.prepareRename(f.task({ finalFileUri: undefined,
      tempFilePath: '/storage/public/original.tar.gz' }), 'renamed')).failure, 'unsupported');
    assert.equal((await f.actions.prepareRename(task, '../escape')).failure, 'invalid_name');
  });
  await check('authorized-directory rename verifies copy, flushes metadata, then recycles the original', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    f.put(folder + '/renamed.tar.gz', 'existing');
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), true);
    const next = f.tasks.get(task.guid);
    assert.equal(next.resolvedFileName, '1-renamed.tar.gz', 'Record uses actual conflict-resolved file name');
    assert.ok(!f.state.files.has(original));
    assert.equal(f.state.files.get(next.persistence.finalFileUri).bytes.toString(), 'original payload');
    assert.equal(f.state.files.get(folder + '/renamed.tar.gz').bytes.toString(), 'existing');
    const order = f.state.events.map(event => event[0]);
    assert.ok(order.indexOf('copy') < order.indexOf('metadata'));
    assert.ok(order.indexOf('metadata') < order.indexOf('trash'));
  });
  await check('single-file grants, mismatched directories, and failed copy verification keep the original', async () => {
    const f = environment(); f.put(original);
    for (const destination of [{ kind: 'file', uri: original }, { kind: 'system_downloads' },
      { kind: 'directory', uri: folder + '/Different' }]) {
      assert.equal((await f.actions.prepareRename(f.task({ destination }), 'renamed')).failure, 'unsupported');
    }
    assert.equal(f.state.events.filter(event => event[0] === 'copy').length, 0);
    f.state.badCopy = true;
    assert.equal((await f.actions.prepareRename(f.task(), 'renamed')).failure, 'failed');
    assert.ok(f.state.files.has(original)); assert.ok(!f.state.files.has(folder + '/renamed.tar.gz'));
  });
  await check('metadata failure removes only the new copy; delete-old failure rolls metadata back first', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    f.state.metadataResults.push('restored');
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), false);
    assert.ok(f.state.files.has(original)); assert.ok(!f.state.files.has(folder + '/renamed.tar.gz'));
    assert.equal(f.tasks.get(task.guid).persistence.finalFileUri, original);
    f.state.failDelete = original; f.state.events.length = 0;
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), false);
    assert.ok(f.state.files.has(original)); assert.ok(!f.state.files.has(folder + '/renamed.tar.gz'));
    assert.equal(f.tasks.get(task.guid).persistence.finalFileUri, original);
    const mutations = f.state.events.filter(event => ['metadata', 'trash'].includes(event[0]));
    assert.deepEqual(mutations.map(event => event[0]), ['metadata', 'trash', 'metadata', 'trash']);
  });
  await check('failed metadata rollback preserves both files and reports failure', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    f.state.failDelete = original; f.state.metadataResults.push('committed', 'restored');
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), false);
    assert.ok(f.state.files.has(original)); assert.ok(f.state.files.has(folder + '/renamed.tar.gz'));
    assert.equal(f.tasks.get(task.guid).persistence.finalFileUri, folder + '/renamed.tar.gz');
    assert.ok(f.state.errors.at(-1).endsWith('download_rename_cleanup_failed'));
  });
  await check('uncertain persistence preserves both possible targets without recycling the original', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    f.state.metadataResults.push('uncertain');
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), false);
    assert.ok(f.state.files.has(original)); assert.ok(f.state.files.has(folder + '/renamed.tar.gz'));
    assert.equal(f.state.events.filter(event => event[0] === 'trash').length, 0);
    assert.ok(f.state.errors.at(-1).endsWith('download_rename_cleanup_failed'));
  });
  await check('a provider that recycles the source before rejecting never causes the verified new file to be deleted', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    f.state.failDelete = original; f.state.deleteThenFail = true;
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary), false);
    assert.ok(!f.state.files.has(original)); assert.ok(f.state.files.has(folder + '/renamed.tar.gz'));
    assert.equal(f.tasks.get(task.guid).persistence.finalFileUri, folder + '/renamed.tar.gz');
    assert.equal(f.state.events.filter(event => event[0] === 'trash').length, 1);
  });
  await check('missing-file replay is explicit, safe GET only, in the original privacy boundary with a new identity', async () => {
    const f = environment(); const task = f.task(); f.tasks.set(task.guid, task);
    assert.equal(await f.runtime.inspectTaskFileForBoundary(task.guid, boundary), 'missing');
    assert.equal(f.state.requests.length, 0);
    assert.ok(!f.runtime.resolveAllowedActionsForV2Task(task).includes('rename'));
    assert.ok(!f.runtime.resolveAllowedActionsForV2Task(task).includes('share_file'));
    assert.equal(await f.runtime.redownloadMissingTaskForBoundary(task.guid, boundary), false,
      'A missing controller cannot fall through to a fresh native GET');
    assert.equal(f.state.requests.length, 0);
    f.runtime.pageDownloadSources.set('tab-a', { sourceId: 'source-a', controller: {}, boundary: boundary });
    assert.equal(await f.runtime.redownloadMissingTaskForBoundary(task.guid, { ...boundary, privacyMode: 'private',
      dataScope: 'session_ephemeral' }), false);
    assert.equal(await f.runtime.redownloadMissingTaskForBoundary(task.guid, boundary), true);
    assert.equal(f.state.requests.length, 1);
    assert.equal(f.state.requests[0].boundary.privacyMode, 'regular');
    assert.equal(f.state.requests[0].context.sourceId, 'source-a');
    assert.equal(f.tasks.get(task.guid), task, 'Completed history is not reset or reused');
    f.put(original); f.state.denied.add(original);
    assert.equal(await f.runtime.redownloadMissingTaskForBoundary(task.guid, boundary), false);
    assert.equal(f.state.requests.length, 1, 'A revoked grant is not a missing file');
    for (const request of [{ ...task.request, method: 'POST' }, { ...task.request, originalUrl: 'blob:https://example.org/id' },
      { ...task.request, originalUrl: 'https://example.org/file?X-Amz-Signature=old' },
      { ...task.request, headers: { Cookie: 'session=old' } },
      { ...task.request, headers: { Authorization: 'old' } }]) {
      assert.equal(f.actions.canRedownload({ ...task, request }), false);
    }
  });
  await check('rename locks other file actions and does not cross profile or privacy boundaries', async () => {
    const f = environment(); f.put(original); const task = f.task(); f.tasks.set(task.guid, task);
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', { ...boundary, privacyMode: 'private',
      dataScope: 'session_ephemeral' }), false);
    let release; const blocked = new Promise(resolve => { release = resolve; });
    const copy = f.files.persistToDestination;
    f.files.persistToDestination = async (...args) => { await blocked; return copy(...args); };
    const running = f.runtime.renameTaskForBoundary(task.guid, 'renamed', boundary);
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'second', boundary), false);
    assert.equal(await f.runtime.shareFileForBoundary(task.guid, boundary), false);
    release(); assert.equal(await running, true);
    assert.equal(f.runtime.fileActionGuids.size, 0);
  });
  await check('two missing-file confirmation callbacks cannot start duplicate downloads', async () => {
    const f = environment(); const task = f.task(); f.tasks.set(task.guid, task);
    f.runtime.pageDownloadSources.set('tab-a', { sourceId: 'source-a', controller: {}, boundary: boundary });
    const attempts = await Promise.all([f.runtime.redownloadMissingTaskForBoundary(task.guid, boundary),
      f.runtime.redownloadMissingTaskForBoundary(task.guid, boundary)]);
    assert.deepEqual(attempts, [true, false]);
    assert.equal(f.state.requests.length, 1); assert.equal(f.runtime.fileActionGuids.size, 0);
  });
  await check('destination grants remain referenced until repository hydration actually completes', async () => {
    const f = environment(); let release;
    f.runtime.downloadV2Service.initialize = () => new Promise(resolve => { release = resolve; });
    assert.equal(f.runtime.hasDownloadDestinationReference(''), false);
    assert.equal(f.runtime.hasDownloadDestinationReference(folder), true);
    const hydrate = f.runtime.initializeRepository();
    assert.equal(f.runtime.hasDownloadDestinationReference(folder), true);
    release(); await hydrate;
    assert.equal(f.runtime.hasDownloadDestinationReference(folder), false);
    const task = f.task(); f.tasks.set(task.guid, task);
    assert.equal(f.runtime.hasDownloadDestinationReference(folder), true);
  });
  await check('file action errors reach only the initiating callback, including unsupported and denied private files', async () => {
    const f = environment(); f.put(original);
    const privateBoundary = { ...boundary, privacyMode: 'private', dataScope: 'session_ephemeral' };
    const task = { ...f.task({ destination: { kind: 'file', uri: original } }), ...privateBoundary };
    f.tasks.set(task.guid, task); const localErrors = [];
    const onFailure = message => localErrors.push(message);
    assert.equal(await f.runtime.renameTaskForBoundary(task.guid, 'renamed', privateBoundary, onFailure), false);
    assert.ok(localErrors.at(-1).endsWith('download_rename_unsupported'));
    f.state.denied.add(original);
    assert.equal(await f.runtime.shareFileForBoundary(task.guid, privateBoundary, onFailure), false);
    assert.ok(localErrors.at(-1).endsWith('download_share_failed'));
    f.state.failLink = true;
    assert.equal(await f.runtime.openLocationForBoundary(task.guid, privateBoundary, onFailure), false);
    assert.ok(localErrors.at(-1).endsWith('download_location_failed'));
    f.runtime.downloadFollowupService.openFile = async () => ({ success: false, userMessage: 'open failure' });
    assert.equal(await f.runtime.openFileForBoundary(task.guid, privateBoundary, onFailure), false);
    assert.equal(localErrors.at(-1), 'open failure');
    assert.equal(localErrors.length, 4); assert.equal(f.state.errors.length, 0);
  });
  process.exitCode = failures ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
