#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const folderA = 'file://docs/storage/Users/currentUser/Download/First';
const folderB = 'file://docs/storage/Users/currentUser/Documents/Second';
const toPath = value => value.startsWith('file://') ? decodeURIComponent(new URL(value).pathname) : value;
const log = { info() {}, warn() {}, error() {} };
const boundary = { windowId: 'w', profileId: 'default', privacyMode: 'regular', dataScope: 'persistent' };

function environment() {
  const state = { files: new Map(), handles: new Map(), persisted: new Set([folderA, folderB]), live: new Set(),
    activated: [], opened: [], releases: [], pickerCalls: 0, nextPick: folderB, shortWrites: false,
    hasContext: true, saveResult: [folderB + '/chosen.bin'], saveOptions: [], denySave: false, denySelected: false,
    failPersist: false, copies: [] };
  let nextFd = 0;
  const denied = () => { throw { code: 13900012, message: 'Permission denied' }; };
  const access = uri => {
    if (!uri.startsWith('file://docs/')) return;
    if (![...state.live].some(grant => uri === grant || uri.startsWith(grant + '/'))) denied();
  };
  const platform = {
    fileShare: {
      OperationMode: { READ_MODE: 1, WRITE_MODE: 2 },
      async activatePermission(policies) {
        for (const policy of policies) {
          state.activated.push(policy);
          if (!state.persisted.has(policy.uri)) denied();
          state.live.add(policy.uri);
        }
      },
      async persistPermission(policies) { for (const policy of policies) {
        if (state.failPersist || !state.live.has(policy.uri)) denied();
        state.persisted.add(policy.uri);
      } },
      async revokePermission(policies) { for (const policy of policies) {
        state.releases.push(policy.uri); state.persisted.delete(policy.uri); state.live.delete(policy.uri);
      } }
    },
    picker: {
      DocumentSelectOptions: class {}, DocumentSelectMode: { FOLDER: 1 },
      DocumentSaveOptions: class {}, DocumentPickerMode: { DEFAULT: 0, DOWNLOAD: 1 },
      DocumentViewPicker: class {
        async select() {
          state.pickerCalls++;
          if (state.nextPick === undefined) return [];
          state.live.add(state.nextPick); return [state.nextPick];
        }
        async save(options) {
          state.saveOptions.push(options);
          if (state.denySave) denied();
          for (const uri of state.saveResult) if (uri) {
            if (!state.denySelected) state.live.add(uri);
            state.files.set(toPath(uri), { bytes: Buffer.alloc(0) });
          }
          return state.saveResult;
        }
      }
    },
    fileUri: { FileUri: class { constructor(uri) { this.path = toPath(uri); } },
      getUriFromPath: value => `file://org.aira.browser${value}` },
    fileIo: {
      OpenMode: { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512 },
      async access(value) { return state.files.has(toPath(value)); },
      async mkdir(value) { state.files.set(toPath(value), { directory: true, bytes: Buffer.alloc(0) }); },
      async open(uri, mode) {
        access(uri); state.opened.push({ uri, mode });
        const filename = toPath(uri);
        let entry = state.files.get(filename);
        if (!entry && (mode & 64)) {
          entry = { bytes: Buffer.alloc(0) }; state.files.set(filename, entry);
        }
        if (!entry) throw { code: 13900002, message: 'Missing file' };
        if (mode & 512) entry.bytes = Buffer.alloc(0);
        const fd = ++nextFd; state.handles.set(fd, { entry, filename, offset: 0 }); return { fd };
      },
      async stat(value) {
        const entry = typeof value === 'number' ? state.handles.get(value)?.entry : state.files.get(toPath(value));
        if (!entry) throw { code: 13900002 };
        return { size: entry.bytes.length, isFile: () => !entry.directory, isDirectory: () => !!entry.directory };
      },
      async read(fd, output, options) {
        const bytes = state.handles.get(fd).entry.bytes.subarray(options.offset, options.offset + options.length);
        new Uint8Array(output).set(bytes); return bytes.length;
      },
      async write(fd, payload) {
        const handle = state.handles.get(fd);
        const bytes = Buffer.from(payload);
        const written = state.shortWrites && !handle.filename.includes('.aira-write-probe') ? Math.min(3, bytes.length) : bytes.length;
        const next = Buffer.alloc(Math.max(handle.entry.bytes.length, handle.offset + written));
        handle.entry.bytes.copy(next); bytes.copy(next, handle.offset, 0, written);
        handle.offset += written; handle.entry.bytes = next; return written;
      },
      async close(file) { state.handles.delete(typeof file === 'number' ? file : file.fd); },
      async unlink(value) { state.files.delete(toPath(value)); },
      async copy(source, target) {
        access(source); access(target); state.copies.push({ source, target });
        state.files.set(toPath(target), { bytes: Buffer.from(state.files.get(toPath(source)).bytes) });
      }
    }
  };
  const cache = new Map();
  function load(relative) {
    const filename = path.resolve(root, relative);
    if (cache.has(filename)) return cache.get(filename);
    const exports = {}; cache.set(filename, exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(code, { exports, $r: value => value, canIUse: () => true, require(id) {
      if (id === '@kit.CoreFileKit') return platform;
      if (id === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: log };
      if (id === '@kit.FileManagerServiceKit') return {};
      if (id === '@ohos.url') return {};
      if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {
        hasUIAbilityContext: () => state.hasContext, getUIAbilityContext: () => ({}),
        getApplicationContext: () => ({ cacheDir: '/sandbox/cache', filesDir: '/sandbox/files' })
      } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id.endsWith('/DownloadPolicyService')) return { DownloadPolicyService: class {} };
      assert.ok(id.startsWith('.'), `Unexpected platform dependency ${id}`);
      return load(path.resolve(path.dirname(filename), `${id}.ets`));
    } }, { filename });
    return exports;
  }
  const { DownloadFileResolutionService } = load('services/download/DownloadFileResolutionService.ets');
  const { DownloadTargetResolutionService } = load('services/download/DownloadTargetResolutionService.ets');
  const { DownloadLocationDirectoryService } = load('services/download/DownloadLocationDirectoryService.ets');
  const policy = { current: { isPrivateSession: false, reason: 'default_location', settings: {
    defaultLocation: 'custom', customLocationUri: folderA, customLocationLabel: 'Download/First'
  } }, resolveSavePolicy() { return this.current; } };
  const files = new DownloadFileResolutionService();
  return { state, files, policy, targets: new DownloadTargetResolutionService(files, policy),
    authorization: new DownloadLocationDirectoryService(),
    put: (location, bytes) => state.files.set(toPath(location), { bytes: Buffer.from(bytes) }),
    get: location => state.files.get(toPath(location))?.bytes.toString(),
    revoke: uri => { state.live.delete(uri); state.persisted.delete(uri); } };
}

function settingsController(relative, embedded, { fail = false, retained = false } = {}) {
  const source = fs.readFileSync(path.join(root, relative), 'utf8').replace(/\bstruct\b/g, 'class');
  const ast = ts.createSourceFile('settings.ts', source, ts.ScriptTarget.Latest, true);
  const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.members.some(member => member.name?.text === 'chooseCustomDownloadLocation'));
  assert.ok(owner, 'Settings folder owner missing');
  const methodNames = ['chooseCustomDownloadLocation', 'resetToSystemDownloadLocation', embedded ? 'updateDownloadSettings' : 'saveDownloadSettings'];
  const methods = methodNames.map(name => {
    const method = owner.members.find(member => member.name?.text === name);
    assert.ok(method, `Missing production method ${name}`); return method.getText(ast);
  }).join('\n');
  let current = { defaultLocation: 'custom', customLocationUri: folderA, customLocationLabel: 'First' };
  let releaseSave;
  const pendingSave = new Promise(resolve => { releaseSave = resolve; });
  const releases = [];
  const update = async settings => {
    await pendingSave;
    if (fail) throw new Error('preferences unavailable');
    current = settings; return { downloads: settings };
  };
  const exports = {};
  vm.runInNewContext(ts.transpileModule(`export class Settings { ${methods} }`, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText, { exports, $r: value => value, resolveAppResourceText: value => value,
    localizeSettingsCopy: value => value, readDownloadSettings: () => current, hilog: log,
    DOWNLOAD_SETTINGS_DOMAIN: 0, DOWNLOAD_SETTINGS_TAG: 'test',
    sharedDownloadPolicyService: { updateSettings: (_boundary, settings) => update(settings) },
    sharedPreferencesRepository: { getPreferences: () => ({ downloads: current }), updateDownloadSettings: update },
    sharedDownloadRuntimeService: { hasDownloadDestinationReference: () => retained },
    DownloadLocationDirectoryService: class {
      isFolderSelectionSupported() { return true; }
      async selectDirectory() { return { status: 'selected', selection: { uri: folderB, label: 'Second' }, isPersisted: true }; }
      async verifyDirectoryWritable() { return true; }
      async releaseDirectory(uri) { releases.push(uri); }
    }
  });
  const service = new exports.Settings();
  Object.assign(service, { settingsBoundary: boundary, showToast() {}, stringifyError: error => error.message,
    getPickerContext: () => ({}), getUIContext: () => ({ getHostContext: () => ({}) }),
    applyDownloadSettingsState() {}, handleSettingsChanged() {},
    downloadSettingsViewModel: { buildState: value => value, buildSettingsPatch: (value, patch) => ({ ...value, ...patch }) },
    downloadViewModel: { buildSettingsPatch: (value, patch) => ({ ...value, ...patch }) } });
  return { service, releases, releaseSave, current: () => current };
}

async function run() {
  let failures = 0;
  async function check(name, action) {
    try { await action(); console.log('PASS ' + name); }
    catch (error) { failures++; console.error('FAIL ' + name + ': ' + error.stack); }
  }
  await check('a task freezes its selected directory while global settings change', async () => {
    const env = environment();
    const plan = await env.targets.resolveTargetPlan({ boundary, suggestedFileName: 'report.bin' });
    assert.equal(plan.destination.uri, folderA);
    env.policy.current.settings.customLocationUri = folderB;
    env.policy.current.settings.customLocationLabel = 'Documents/Second';
    assert.equal(env.targets.resolveDestinationSnapshot(boundary).uri, folderB);
    assert.equal(plan.destination.uri, folderA);
    env.put(plan.tempFilePath, 'contents');
    const result = await env.files.persistToDestination(plan.tempFilePath, plan.fileName, plan.destination);
    assert.equal(result.finalFileUri, folderA + '/report.bin');
    assert.equal(result.destination.kind, 'directory'); assert.equal(result.destination.uri, folderA);
    assert.equal(env.get(result.finalFileUri), 'contents');
    assert.equal(env.get(folderB + '/report.bin'), undefined);
  });
  await check('restart activates the recorded directory; revoked permission blocks export without a fallback', async () => {
    const env = environment(); const destination = env.targets.resolveDestinationSnapshot(boundary);
    assert.equal(await env.targets.validateDestination(destination), true);
    assert.equal(env.state.activated[0].uri, folderA);
    env.revoke(folderA);
    assert.equal(await env.targets.validateDestination(destination), false);
    env.put('/sandbox/source', 'keep source');
    env.files.persistToSystemDownloads = async () => { throw new Error('A chosen destination must not fall back'); };
    const result = await env.files.persistToDestination('/sandbox/source', 'retry.bin', destination);
    assert.equal(result.isExported, false); assert.equal(result.status, 'failed');
    assert.equal(env.get('/sandbox/source'), 'keep source');
    assert.equal(env.state.pickerCalls, 0);
    assert.equal(env.get(folderA + '/retry.bin'), undefined);
  });
  await check('directory export accepts an already authorized source URI without converting or bypassing it', async () => {
    const env = environment(); const source = folderA + '/original.bin';
    env.put(source, 'original source'); env.state.live.add(folderA);
    const destination = { kind: 'directory', uri: folderB, label: 'Documents/Second' };
    const result = await env.files.persistToDestination(source, 'renamed.bin', destination);
    assert.equal(result.isExported, true); assert.equal(env.get(result.finalFileUri), 'original source');
    assert.ok(env.state.opened.some(open => open.uri === source && open.mode === 0));
    assert.ok(env.state.copies.some(copy => copy.source === source));
    env.revoke(folderA);
    const denied = await env.files.persistToDestination(source, 'denied.bin', destination);
    assert.equal(denied.isExported, false); assert.equal(env.get(folderB + '/denied.bin'), undefined);
    assert.equal(env.get(source), 'original source'); assert.equal(env.state.handles.size, 0);
  });
  await check('canceling re-selection preserves the old target; a new selection returns a verified separate snapshot', async () => {
    const env = environment(); const original = env.targets.resolveDestinationSnapshot(boundary);
    env.state.nextPick = undefined;
    assert.equal(await env.targets.selectDestination('report.bin'), undefined);
    assert.equal(original.uri, folderA);
    env.state.nextPick = folderB;
    const selected = await env.targets.selectDestination('report.bin');
    assert.equal(selected.kind, 'directory'); assert.equal(selected.uri, folderB);
    assert.equal(await env.targets.validateDestination(selected), true);
    assert.equal(original.uri, folderA);
    assert.equal(env.state.handles.size, 0);
  });
  await check('file grants use the complete URI and never truncate while validating; export handles short writes', async () => {
    const env = environment(); const uri = folderB + '/selected.bin';
    env.state.persisted.clear(); env.state.persisted.add(uri);
    env.put(uri, 'original longer content'); env.put('/sandbox/source', 'abcdefghij');
    const destination = { kind: 'file', uri, label: 'Documents/Second/selected.bin' };
    assert.equal(await env.files.validateDestination(destination), true);
    assert.equal(env.state.activated[0].uri, uri); assert.equal(env.state.activated[0].operationMode, 2);
    assert.equal(env.state.opened[0].mode, 1); assert.equal(env.get(uri), 'original longer content');
    env.state.shortWrites = true;
    const result = await env.files.persistToDestination('/sandbox/source', 'ignored.bin', destination);
    assert.equal(result.isExported, true); assert.equal(result.finalFileUri, uri);
    assert.equal(result.destination.kind, 'file'); assert.equal(result.destination.uri, uri);
    assert.equal(result.finalFileName, 'selected.bin'); assert.equal(env.get(uri), 'abcdefghij');
    assert.equal(env.state.handles.size, 0);
    env.revoke(uri);
    assert.equal(await env.files.validateDestination(destination), false);
    const failed = await env.files.persistToDestination('/sandbox/source', 'ignored.bin', destination);
    assert.equal(failed.isExported, false); assert.equal(env.get(uri), 'abcdefghij');
  });
  await check('reading a restored selected file activates READ permission on the full URI independently of write access', async () => {
    const env = environment(); const uri = folderB + '/selected.bin';
    env.state.persisted.clear(); env.state.persisted.add(uri);
    env.put(uri, 'readable contents');
    const readable = await env.authorization.activateReadableFile(uri);
    assert.equal(readable.usable, true);
    assert.equal(env.state.activated[0].uri, uri);
    assert.equal(env.state.activated[0].operationMode, 1, 'Reading must request READ_MODE, not WRITE_MODE');
    assert.equal((await env.files.inspectReadableFile(uri)).size, 17);
    env.revoke(uri);
    assert.equal((await env.authorization.activateReadableFile(uri)).usable, false);
    assert.equal(await env.files.inspectReadableFile(uri), undefined);
    assert.equal(env.state.handles.size, 0);
  });
  await check('private targets keep their original temp or prompt policy when preferences change', async () => {
    const env = environment();
    env.policy.current.isPrivateSession = true; env.policy.current.reason = 'private_session_temp_only';
    const snapshot = env.targets.resolveDestinationSnapshot(boundary);
    assert.equal(snapshot.kind, 'session_temp');
    env.policy.current.reason = 'private_prompt_for_location';
    assert.equal(env.targets.resolveDestinationSnapshot(boundary).kind, 'prompt');
    assert.equal(env.targets.resolveCompletionTargetPolicy(boundary, 'private.bin', snapshot).shouldPromptForExport, false);
    assert.equal(env.targets.resolveCompletionTargetPolicy(boundary, 'private.bin', { kind: 'prompt' }).shouldPromptForExport, true);
    assert.equal(env.state.pickerCalls, 0);
  });
  await check('prompt opens the normal save picker and writes exactly its returned full file URI', async () => {
    const env = environment(); env.put('/sandbox/source', 'chosen contents');
    const result = await env.files.persistToDestination('/sandbox/source', 'asked.bin', { kind: 'prompt' });
    assert.equal(env.state.saveOptions[0].pickerMode, 0);
    assert.deepEqual(Array.from(env.state.saveOptions[0].newFileNames), ['asked.bin']);
    assert.equal(result.isExported, true); assert.equal(result.finalFileUri, folderB + '/chosen.bin');
    assert.equal(result.destination.kind, 'file');
    assert.equal(result.destination.uri, result.finalFileUri, 'DEFAULT save authorizes the returned file, never its parent');
    assert.equal(result.destination.label, result.finalDisplayPath);
    assert.notEqual(result.destination.uri, folderB);
    assert.equal(env.get(result.finalFileUri), 'chosen contents');
    assert.equal(env.get(result.finalFileUri + '/asked.bin'), undefined);
    assert.ok(env.state.persisted.has(result.finalFileUri));
    assert.ok(env.state.activated.some(policy => policy.uri === result.finalFileUri && policy.operationMode === 2));
    assert.equal(env.state.handles.size, 0);
  });
  await check('prompt distinguishes actual picker cancellation from permission, context and malformed-result failures', async () => {
    for (const reason of ['cancel', 'denied', 'denied_selection', 'no_context', 'empty_uri']) {
      const env = environment(); env.put('/sandbox/source', 'keep source');
      if (reason === 'cancel') env.state.saveResult = [];
      if (reason === 'denied') env.state.denySave = true;
      if (reason === 'denied_selection') env.state.denySelected = true;
      if (reason === 'no_context') env.state.hasContext = false;
      if (reason === 'empty_uri') env.state.saveResult = [''];
      const result = await env.files.persistToDestination('/sandbox/source', 'asked.bin', { kind: 'prompt' });
      assert.equal(result.status, reason === 'cancel' ? 'user_canceled' : 'failed', reason);
      assert.equal(result.isExported, false); assert.equal(env.get('/sandbox/source'), 'keep source');
      assert.equal(env.state.handles.size, 0);
    }
  });
  await check('a selected file with a live grant remains writable even if persistent authorization is unavailable', async () => {
    const env = environment(); env.put('/sandbox/source', 'live grant contents'); env.state.failPersist = true;
    const result = await env.files.persistToDestination('/sandbox/source', 'asked.bin', { kind: 'prompt' });
    assert.equal(result.isExported, true); assert.equal(env.get(result.finalFileUri), 'live grant contents');
    assert.equal(env.state.persisted.has(result.finalFileUri), false);
    assert.equal(env.state.handles.size, 0);
  });
  await check('both settings surfaces release old grants only after a successful save with no task references', async () => {
    for (const [relative, embedded] of [
      ['app/components/browser/BrowserDownloadSettingsScreen.ets', false],
      ['app/components/settings/SettingsEmbeddedDetailPanel.ets', true]
    ]) for (const method of ['chooseCustomDownloadLocation', 'resetToSystemDownloadLocation']) {
      for (const options of [{ fail: true }, { retained: true }, {}]) {
        const env = settingsController(relative, embedded, options);
        const pending = env.service[method]();
        for (let step = 0; step < 10; step++) await Promise.resolve();
        assert.equal(env.releases.length, 0, 'An unsettled preferences write must retain the old grant');
        env.releaseSave(); await pending;
        assert.equal(env.releases.length, options.fail || options.retained ? 0 : 1);
        if (options.fail) assert.equal(env.current().customLocationUri, folderA);
      }
    }
  });
  if (failures) throw new Error(`${failures} destination contracts failed`);
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
