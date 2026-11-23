#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ts = require('./lib/deveco-typescript.cjs');

const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const folderUri = 'file://docs/storage/Users/currentUser/Download/MyFiles';
const OperationMode = { READ_MODE: 1, WRITE_MODE: 2, CREATE_MODE: 4 };
const log = { info() {}, warn() {}, error() {} };

// Platform model follows Huawei's fileShare contract: CREATE_MODE is temporary
// only. Persisting/activating a directory uses READ_MODE | WRITE_MODE; a restart
// clears picker grants but keeps successfully persisted grants.
// https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-fileshare
function environment({ existingGrant = false, overlapProbeStats = false, failProbeWrite = false,
  uriCreateUnsupported = false, selectedFolderUri = folderUri, denyUriCopy = false,
  zeroByteCopy = false } = {}) {
  const files = new Map();
  const handles = new Map();
  const policies = [];
  const persisted = new Set(existingGrant ? [selectedFolderUri] : []);
  let temporary = false;
  let active = false;
  let nextFd = 1;
  let statCount = 0;
  let releaseDelayedStat;
  const firstProbeDeleted = new Promise(resolve => { releaseDelayedStat = resolve; });
  const deny = () => { throw { code: 13900012, message: 'Permission denied' }; };
  const requireAccess = () => { if (!temporary && !active) deny(); };
  const checkMode = policy => {
    policies.push(policy.operationMode);
    if ((policy.operationMode & ~3) !== 0) {
      throw { code: 13900001, message: 'Operation not permitted', data: [
        { uri: policy.uri, code: 2, message: 'INVALID_MODE: only read/write can be persisted' }
      ] };
    }
  };
  const coreFileKit = {
    fileShare: {
      OperationMode,
      async persistPermission(items) {
        for (const item of items) { checkMode(item); if (!temporary) deny(); persisted.add(item.uri); }
      },
      async activatePermission(items) {
        for (const item of items) {
          checkMode(item);
          if (!persisted.has(item.uri)) throw { code: 13900001, message: 'Operation not permitted', data: [
            { uri: item.uri, code: 4, message: 'PERMISSION_NOT_PERSISTED' }
          ] };
          active = true;
        }
      },
      async revokePermission(items) { for (const item of items) { checkMode(item); persisted.delete(item.uri); } }
    },
    picker: {
      DocumentSelectOptions: class {},
      DocumentSelectMode: { FOLDER: 1 },
      DocumentViewPicker: class {
        async select() { temporary = true; return [selectedFolderUri]; }
      }
    },
    fileUri: {
      FileUri: class { constructor(uri) { this.path = uri.replace('file://docs', ''); } },
      getUriFromPath: value => `file://com.aira.browser${value}`
    },
    fileIo: {
      OpenMode: { CREATE: 1, READ_WRITE: 2, TRUNC: 4 },
      async access(uri) { return files.has(uri); },
      async mkdir(uri) { files.set(uri, { size: 0 }); },
      async open(uri) {
        if (uri.startsWith('file://docs/')) {
          requireAccess();
          if (uriCreateUnsupported) throw { code: 13900002, message: 'No such file or directory' };
        }
        const entry = { size: 0 };
        files.set(uri, entry);
        const file = { fd: nextFd++ };
        handles.set(file.fd, entry);
        return file;
      },
      async write(fd, payload) {
        if (failProbeWrite) throw { code: 13900028, message: 'No space left on device' };
        handles.get(fd).size = payload.length;
        return payload.length;
      },
      async close(file) { handles.delete(file.fd); },
      async copy(source, target) {
        requireAccess();
        if (denyUriCopy) deny();
        const sourcePath = source.replace('file://com.aira.browser', '');
        const entry = files.get(sourcePath);
        assert.ok(entry, 'Copy probe source must exist');
        files.set(target, { size: zeroByteCopy ? 0 : entry.size });
      },
      async stat(uri) {
        if (uri === selectedFolderUri) return { size: 0, isDirectory: () => true };
        if (overlapProbeStats && ++statCount === 2) await firstProbeDeleted;
        const entry = files.get(uri);
        if (!entry) throw { code: 13900002, message: 'No such file' };
        return { size: entry.size };
      },
      async unlink(uri) { files.delete(uri); releaseDelayedStat(); }
    }
  };
  const cache = new Map();
  function evaluate(source, filename, globals = {}) {
    const module = { exports: {} };
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    });
    vm.runInNewContext(output.outputText, {
      module, exports: module.exports, canIUse: () => true, $r: key => key, ...globals,
      require(id) {
        if (id === '@kit.CoreFileKit') return coreFileKit;
        if (id === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID } };
        if (id === '@kit.PerformanceAnalysisKit') return { hilog: log };
        if (id === '@kit.FileManagerServiceKit') return {};
        if (id === '@ohos.url') return {};
        if (id.endsWith('/AppRuntimeContext')) return {
          AppRuntimeContext: { getApplicationContext: () => ({ cacheDir: '/sandbox/cache' }) }
        };
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        assert.ok(id.startsWith('.'), `Unexpected platform dependency ${id}`);
        return load(path.resolve(path.dirname(filename), `${id}.ets`));
      }
    }, { filename });
    return module.exports;
  }
  function load(filename) {
    if (!cache.has(filename)) cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
    return cache.get(filename);
  }
  const directory = load(path.join(sourceRoot, 'services/download/DownloadLocationDirectoryService.ets'));
  const { DownloadFileResolutionService } = load(path.join(sourceRoot, 'services/download/DownloadFileResolutionService.ets'));
  const service = new DownloadFileResolutionService();
  const copyOriginal = service.copyLocalPathWithoutOverwrite.bind(service);
  service.copyLocalPathWithoutOverwrite = async (_source, target) => { requireAccess(); return target; };
  let fallbackCount = 0;
  service.persistToSystemDownloads = async () => {
    fallbackCount++;
    return { status: 'exported', isExported: true, finalFileUri: 'file://docs/default/result.png',
      finalDisplayPath: 'Download/com.aira.browser/result.png' };
  };
  const completionFile = path.join(sourceRoot, 'services/downloadv2/DownloadV2Service.ets');
  const ast = ts.createSourceFile(completionFile, fs.readFileSync(completionFile, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'DownloadV2Service');
  const completionMethod = owner.members.find(node => node.name?.text === 'persistFinishedDownload');
  assert.ok(completionMethod, 'Production completion path missing');
  const { Completion } = evaluate(`export class Completion { ${completionMethod.getText(ast)} }`, completionFile,
    { resolveCustomDownloadDirectory: directory.resolveCustomDownloadDirectory });
  const completion = new Completion();
  completion.fileResolutionService = service;
  completion.downloadPolicyService = { resolveSavePolicy: () => ({ isPrivateSession: false, settings: {
    defaultLocation: 'custom', customLocationUri: selectedFolderUri, customLocationLabel: 'MyFiles'
  } }) };
  return {
    directory: new directory.DownloadLocationDirectoryService(),
    fileResolution: service,
    fileIo: coreFileKit.fileIo,
    copyOriginal,
    complete: name => completion.persistFinishedDownload('/sandbox/result.png', name, {}),
    restart() { temporary = false; active = false; },
    revoke() { temporary = false; active = false; persisted.clear(); },
    get fallbackCount() { return fallbackCount; },
    policies, files, handles
  };
}

async function run() {
  const failures = [];
  async function scenario(name, body) {
    try { await body(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.message}`); }
  }
  await scenario('selected folder survives restart and receives the completed download', async () => {
    const env = environment();
    const picked = await env.directory.selectDirectory({});
    const liveDownload = await env.complete('before-restart.png');
    assert.equal(liveDownload.isExported, true, 'Picker grant should allow the initial download');
    env.restart();
    const result = await env.complete('after-restart.png');
    console.log(`  persisted=${picked.isPersisted} modes=${env.policies.join(',')} fallback=${env.fallbackCount}`);
    assert.equal(result.finalFileUri, `${folderUri}/after-restart.png`,
      'Restart must not move a custom-folder download into Download/com.aira.browser');
    assert.equal(picked.isPersisted, true, 'A valid folder must receive durable read/write permission');
  });
  await scenario('previously persisted read/write grant can be activated', async () => {
    const env = environment({ existingGrant: true });
    const result = await env.complete('existing-grant.png');
    assert.equal(result.finalFileUri, `${folderUri}/existing-grant.png`);
    assert.equal(env.fallbackCount, 0);
  });
  await scenario('a Documents provider that rejects child URI open can still receive URI copies', async () => {
    const documentsUri = 'file://docs/storage/Users/currentUser/Documents';
    const env = environment({ uriCreateUnsupported: true, selectedFolderUri: documentsUri });
    await env.directory.selectDirectory({});
    const result = await env.complete('documents.png');
    assert.equal(result.finalFileUri, `${documentsUri}/documents.png`,
      'An ENOENT from open(CREATE) must not reject a directory whose URI-copy transport works');
    assert.equal(env.fallbackCount, 0);
    assert.equal(env.files.size, 0, 'Both local and destination probes must be removed');
    assert.equal(env.handles.size, 0);
  });
  for (const failure of ['permission', 'empty_copy']) {
    await scenario(`a Documents copy probe still rejects ${failure}`, async () => {
      const env = environment({ uriCreateUnsupported: true,
        denyUriCopy: failure === 'permission', zeroByteCopy: failure === 'empty_copy' });
      await env.directory.selectDirectory({});
      const result = await env.complete('failed-copy.png');
      assert.equal(env.fallbackCount, 1);
      assert.equal(result.customDirectoryBypassed, true);
      assert.equal(env.files.size, 0, 'Copy failures must leave no local or destination probe files');
      assert.equal(env.handles.size, 0);
    });
  }
  await scenario('overlapping downloads cannot delete each other\'s folder probe', async () => {
    const env = environment({ overlapProbeStats: true });
    await env.directory.selectDirectory({});
    const results = await Promise.all([env.complete('first.png'), env.complete('second.png')]);
    assert.equal(env.fallbackCount, 0, 'A valid folder must not fall back when another probe finishes');
    assert.ok(results.every(result => result.finalFileUri.startsWith(`${folderUri}/`)));
    assert.equal(env.files.size, 0, 'Probe files must be cleaned up');
  });
  await scenario('a genuinely revoked folder still falls back and reports the bypass', async () => {
    const env = environment();
    await env.directory.selectDirectory({});
    env.revoke();
    const result = await env.complete('revoked.png');
    assert.equal(env.fallbackCount, 1);
    assert.equal(result.customDirectoryBypassed, true);
    assert.equal(env.files.size, 0, 'A revoked grant must not create empty download shells');
  });
  await scenario('activation diagnostics retain the per-policy failure reason', async () => {
    const env = environment();
    const result = await env.directory.activateDirectory(folderUri);
    assert.equal(result.isPersisted, false);
    assert.match(result.diagnosticMessage, /4:PERMISSION_NOT_PERSISTED/);
  });
  await scenario('a failed probe write closes its descriptor and removes only its own file', async () => {
    const env = environment({ failProbeWrite: true });
    await env.directory.selectDirectory({});
    env.files.set(`${folderUri}/.aira-write-probe`, { size: 123 });
    assert.equal(await env.directory.verifyDirectoryWritable(folderUri), false);
    assert.equal(env.handles.size, 0, 'The descriptor must close even when write fails');
    assert.equal(env.files.size, 1);
    assert.equal(env.files.get(`${folderUri}/.aira-write-probe`).size, 123, 'Existing files must be untouched');
  });
  await scenario('deleting a download after restart also removes its resume metadata', async () => {
    const env = environment();
    const target = '/sandbox/partial.bin';
    for (const suffix of ['', '.aira-resume', '.aira-resume.tmp', '.unrelated']) {
      env.files.set(target + suffix, { size: 10 });
    }
    assert.equal(await env.fileResolution.deleteLocalPath(target), 'deleted');
    assert.deepEqual(Array.from(env.files.keys()), [target + '.unrelated']);
    env.files.set(target + '.aira-resume', { size: 10 });
    assert.equal(await env.fileResolution.deleteLocalPath(target), 'missing');
    assert.deepEqual(Array.from(env.files.keys()), [target + '.unrelated']);
  });
  await scenario('same-named tasks created in the same millisecond get independent temporary files', async () => {
    const env = environment(); env.fileResolution.getDownloadsTempDir = () => '/sandbox/incomplete';
    const plans = await Promise.all([
      env.fileResolution.resolveTemporaryTarget('same.zip', 123),
      env.fileResolution.resolveTemporaryTarget('same.zip', 123)
    ]);
    assert.notEqual(plans[0].targetPath, plans[1].targetPath);
  });
  await scenario('concurrent exports with the same filename cannot select the same destination', async () => {
    const env = environment();
    env.files.set('/sandbox/one', { size: 10 }); env.files.set('/sandbox/two', { size: 10 });
    env.fileResolution.copyLocalPathToUri = async (source, target) => {
      await Promise.resolve(); env.files.set(target, { size: 10, source });
    };
    const otherWindow = new env.fileResolution.constructor();
    otherWindow.copyLocalPathToUri = env.fileResolution.copyLocalPathToUri;
    const target = folderUri + '/same.zip', conflict = folderUri + '/same%20(1).zip';
    const destinations = await Promise.all([
      env.copyOriginal('/sandbox/one', target, conflict), otherWindow.copyLocalPathWithoutOverwrite('/sandbox/two', target, conflict)
    ]);
    assert.notEqual(destinations[0], destinations[1]);
    assert.equal(new Set(destinations.map(uri => env.files.get(uri).source)).size, 2);
  });
  await scenario('a failed export releases its destination reservation for a later retry', async () => {
    const env = environment(); env.files.set('/sandbox/one', { size: 10 });
    const target = folderUri + '/retry.zip', conflict = folderUri + '/retry%20(1).zip';
    env.fileResolution.copyLocalPathToUri = async () => { throw { code: 13900012, message: 'Permission denied' }; };
    await assert.rejects(env.copyOriginal('/sandbox/one', target, conflict));
    env.fileResolution.copyLocalPathToUri = async (_source, uri) => { env.files.set(uri, { size: 10 }); };
    assert.equal(await env.copyOriginal('/sandbox/one', target, conflict), target);
  });
  await scenario('descriptor-copy fallback handles short writes without dropping the rest of a chunk', async () => {
    const env = environment(); const source = Buffer.from('abcdefghij'), chunks = [];
    env.fileIo.read = async (_fd, output, options) => {
      const bytes = source.subarray(options.offset, options.offset + options.length);
      new Uint8Array(output).set(bytes); return bytes.length;
    };
    env.fileIo.write = async (_fd, payload) => {
      const bytes = Buffer.from(payload).subarray(0, 3); chunks.push(bytes); return bytes.length;
    };
    await env.fileResolution.rewriteFileDescriptors(1, 2);
    assert.equal(Buffer.concat(chunks).toString(), source.toString());
  });
  if (failures.length) throw new Error(`${failures.length} download directory lifecycle scenarios failed`);
}

run().catch(error => { console.error(error.message); process.exitCode = 1; });
