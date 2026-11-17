#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const folder = 'file://docs/storage/Users/currentUser/Download/Aira';
const toPath = value => value.startsWith('file://') ? decodeURIComponent(new URL(value).pathname) : value;
const uriName = value => decodeURIComponent(value.slice(value.lastIndexOf('/') + 1));

// Run the production naming and export classes; only platform IO is replaced.
// File existence is checked by the decoded target path, not by a URI string or
// the temporary download directory, just as FileUri.path is used in production.
function environment(options = {}) {
  const state = { files: new Map(), copies: [], saveOptions: [], beforeCopy: async () => {} };
  const platform = {
    fileShare: { OperationMode: { READ_MODE: 1, WRITE_MODE: 2 } },
    fileUri: { FileUri: class { constructor(uri) { this.path = toPath(uri); } },
      getUriFromPath: value => `file://org.aira.browser${value}` },
    picker: {
      DocumentSaveOptions: class {}, DocumentPickerMode: { DOWNLOAD: 1 },
      DocumentViewPicker: class { async save(saveOptions) { state.saveOptions.push(saveOptions); return [options.pickerFolder]; } }
    },
    fileIo: {
      async access(value) { return state.files.has(toPath(value)); },
      async mkdir(value) {
        if (options.directFolderUnavailable && toPath(value) === toPath(folder)) throw new Error('grant unavailable');
        state.files.set(toPath(value), '');
      },
      async stat(value) {
        const contents = state.files.get(toPath(value));
        if (contents === undefined) throw new Error('not found');
        return { size: contents.length };
      },
      async copy(source, target) {
        state.copies.push({ source, target });
        await state.beforeCopy();
        assert.equal(state.files.has(toPath(target)), false, 'An existing target must never be overwritten');
        state.files.set(toPath(target), state.files.get(toPath(source)));
      }
    }
  };
  const cache = new Map();
  function load(filename) {
    if (cache.has(filename)) return cache.get(filename);
    const exports = {};
    cache.set(filename, exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(code, { exports, $r: key => key, require(id) {
      if (id === '@kit.CoreFileKit') return platform;
      if (id === '@kit.ArkTS') return { util: { generateRandomUUID: randomUUID } };
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (id === '@kit.FileManagerServiceKit') return {};
      if (id === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {} };
      assert.ok(id.startsWith('.'), `Unexpected platform dependency ${id}`);
      return load(path.resolve(path.dirname(filename), `${id}.ets`));
    } }, { filename });
    return exports;
  }
  const { DownloadFileNameService } = load(path.join(root, 'services/download/DownloadFileNameService.ets'));
  const { DownloadFilenameConflictService } = load(path.join(root, 'services/download/DownloadFilenameConflictService.ets'));
  const { DownloadFileResolutionService } = load(path.join(root, 'services/download/DownloadFileResolutionService.ets'));
  return { ...state, names: new DownloadFileNameService(), conflicts: new DownloadFilenameConflictService(),
    exports: new DownloadFileResolutionService(), newExporter: () => new DownloadFileResolutionService(),
    setBeforeCopy: hook => { state.beforeCopy = hook; } };
}

function validName(value) {
  assert.ok(value.length > 0 && value !== '.' && value !== '..');
  assert.ok(Buffer.byteLength(value, 'utf8') <= 255, `Name exceeds 255 UTF-8 bytes: ${Buffer.byteLength(value)}`);
  assert.equal(Buffer.from(value, 'utf8').toString('utf8'), value, 'A UTF-16 surrogate must not be cut in half');
  assert.doesNotMatch(value, /[\\/:*?"<>|\u0000-\u001f\u007f\u202a-\u202e\u2066-\u2069]/);
  assert.equal(value.trim(), value);
  assert.doesNotThrow(() => encodeURIComponent(value));
}

async function run() {
  const failures = [];
  async function scenario(name, body) {
    try { await body(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.stack}`); }
  }
  await scenario('255-byte ASCII boundary keeps the extension without shortening valid names', () => {
    const { names } = environment();
    const atLimit = 'a'.repeat(251) + '.pdf';
    assert.equal(names.sanitizeFileName(atLimit), atLimit);
    assert.equal(names.sanitizeFileName('a' + atLimit), atLimit);
    assert.equal(names.sanitizeFileName('a'.repeat(255)), 'a'.repeat(255));
    assert.equal(names.sanitizeFileName('report..pdf'), 'report..pdf');
    validName(atLimit);
  });
  await scenario('Chinese, emoji and Unicode extensions keep whole characters within the byte budget', () => {
    const { names } = environment();
    const fixtures = [
      ['中'.repeat(100) + '.zip', '中'.repeat(83) + '.zip'],
      ['🙂'.repeat(100) + '.mp4', '🙂'.repeat(62) + '.mp4'],
      ['中🙂'.repeat(100) + '.pdf', '中🙂'.repeat(35) + '中.pdf'],
      ['中'.repeat(100) + '.档案', '中'.repeat(82) + '.档案'],
      ['x'.repeat(300) + '.tar.gz', 'x'.repeat(248) + '.tar.gz']
    ];
    for (const [raw, expected] of fixtures) {
      const actual = names.sanitizeFileName(raw);
      assert.equal(actual, expected); validName(actual);
      assert.equal(names.sanitizeFileName(actual), actual, 'Sanitizing a resolved name must be stable');
    }
  });
  await scenario('MIME, URL and Content-Disposition resolution all apply the final extension budget', () => {
    const { names } = environment();
    const long = '中🙂'.repeat(80);
    const fromMime = names.resolveFileName({ suggestedFileName: long, mimeType: 'application/pdf' });
    assert.equal(fromMime, '中🙂'.repeat(35) + '中.pdf'); validName(fromMime);
    const fromHeader = names.resolveFileName({ suggestedFileName: 'wrong.txt', mimeType: 'text/plain',
      contentDisposition: `attachment; filename*=UTF-8''${encodeURIComponent(long + '.tar.xz')}` });
    assert.ok(fromHeader.endsWith('.tar.xz')); validName(fromHeader);
    const fromUrl = names.resolveFileName({ url: `https://fixture.invalid/get?filename=${encodeURIComponent(long + '.zip')}` });
    assert.ok(fromUrl.endsWith('.zip')); validName(fromUrl);
  });
  await scenario('empty, path-like and ill-formed Unicode names remain safe and URI encodable', () => {
    const { names, conflicts, exports } = environment();
    for (const raw of ['', '  \n\t ', '.', '..', '... ']) {
      assert.equal(names.sanitizeFileName(raw), 'download.bin');
    }
    for (const raw of ['../课程: 第一集? / 片段\u0000\u202e.mp4', '\ud800bad\udc00.pdf',
      '  spaced\t\nname.pdf... ', 'a.' + 'b'.repeat(300)]) {
      validName(names.sanitizeFileName(raw));
      validName(conflicts.buildUniquifiedFileName(raw));
      const plan = exports.buildExportResolution(raw, folder);
      validName(uriName(plan.targetUri)); validName(uriName(plan.conflictResolvedUri));
      assert.equal(plan.targetUri.slice(0, plan.targetUri.lastIndexOf('/')), folder);
    }
    assert.equal(names.sanitizeFileName('\ud800bad\udc00.pdf'), '_bad_.pdf');
    assert.equal(names.sanitizeFileName('  spaced\t\nname.pdf... '), 'spaced name.pdf');
  });
  await scenario('conflict numbering reserves bytes before ordinary and compound extensions', () => {
    const { conflicts } = environment();
    const raw = 'x'.repeat(300) + '.tar.gz';
    assert.equal(conflicts.buildUniquifiedFileName(raw, 1), 'x'.repeat(244) + ' (1).tar.gz');
    assert.equal(conflicts.buildUniquifiedFileName(raw, 999), 'x'.repeat(242) + ' (999).tar.gz');
    for (const index of [1, 9, 10, 99, 100, 999]) {
      for (const original of ['中🙂'.repeat(100) + '.mp4', 'a'.repeat(255), raw]) {
        const name = conflicts.buildUniquifiedFileName(original, index);
        validName(name); assert.ok(name.includes(` (${index})`));
      }
    }
    assert.equal(conflicts.buildUniquifiedFileName('report.pdf', 0), 'report (1).pdf');
    validName(conflicts.buildOriginalPlan(raw).fileName);
  });
  await scenario('exports skip existing files in the final directory and leave their contents intact', async () => {
    const env = environment();
    const plan = env.exports.buildExportResolution('中🙂'.repeat(100) + '.tar.gz', folder + '/');
    env.files.set('/sandbox/source', 'new contents');
    env.files.set(toPath(plan.targetUri), 'original contents');
    env.files.set(toPath(plan.conflictResolvedUri), 'first conflict contents');
    const actual = await env.exports.copyLocalPathWithoutOverwrite('/sandbox/source', plan.targetUri, plan.conflictResolvedUri);
    assert.ok(uriName(actual).endsWith(' (2).tar.gz')); validName(uriName(actual));
    assert.equal(actual.slice(0, actual.lastIndexOf('/')), folder);
    assert.equal(env.files.get(toPath(actual)), 'new contents');
    assert.equal(env.files.get(toPath(plan.targetUri)), 'original contents');
    assert.equal(env.files.get(toPath(plan.conflictResolvedUri)), 'first conflict contents');
    const otherPlan = env.exports.buildExportResolution(plan.fileName, folder + '-other');
    assert.equal(await env.exports.copyLocalPathWithoutOverwrite('/sandbox/source', otherPlan.targetUri,
      otherPlan.conflictResolvedUri), otherPlan.targetUri, 'Another final directory has an independent name namespace');
  });
  for (const usePicker of [false, true]) {
    await scenario(`${usePicker ? 'picker' : 'direct'} export returns the actual conflict name and displayed location`, async () => {
      const selectedFolder = usePicker ? folder.replace('/Aira', '/org.aira.browser') : folder;
      const env = environment({ directFolderUnavailable: usePicker, pickerFolder: selectedFolder });
      const name = '中🙂'.repeat(100) + '.zip';
      const plan = env.exports.buildExportResolution(name, selectedFolder);
      env.files.set('/sandbox/source', 'new contents');
      env.files.set(toPath(plan.targetUri), 'existing contents');
      const result = await env.exports.persistToSystemDownloads('/sandbox/source', name);
      assert.equal(result.isExported, true);
      assert.equal(result.finalFileName, uriName(result.finalFileUri));
      assert.ok(result.finalFileName.endsWith(' (1).zip')); validName(result.finalFileName);
      assert.equal(result.finalDisplayPath, `${usePicker ? 'Download/org.aira.browser' : 'Download/Aira'}/${result.finalFileName}`);
      assert.equal(result.destination.kind, 'directory');
      assert.equal(result.destination.uri, selectedFolder, 'Directory authorization must preserve the provider base URI');
      assert.equal(result.destination.label, result.destinationLabel);
      if (usePicker) assert.equal(env.saveOptions[0].pickerMode, 1, 'DOWNLOAD returns a directory grant, not a selected file grant');
      assert.equal(env.files.get(toPath(plan.targetUri)), 'existing contents');
    });
  }
  await scenario('simultaneous full-length exports reserve separate valid names before either copy finishes', async () => {
    const env = environment();
    const plan = env.exports.buildExportResolution('🙂'.repeat(100) + '.mp4', folder);
    env.files.set('/sandbox/one', 'first contents'); env.files.set('/sandbox/two', 'second contents');
    let release, started;
    const blocked = new Promise(resolve => { release = resolve; });
    const bothStarted = new Promise(resolve => { started = resolve; });
    env.setBeforeCopy(async () => { if (env.copies.length === 2) started(); await blocked; });
    const pending = Promise.all([
      env.exports.copyLocalPathWithoutOverwrite('/sandbox/one', plan.targetUri, plan.conflictResolvedUri),
      env.newExporter().copyLocalPathWithoutOverwrite('/sandbox/two', plan.targetUri, plan.conflictResolvedUri)
    ]);
    await bothStarted;
    try {
      assert.notEqual(env.copies[0].target, env.copies[1].target);
      assert.equal(env.files.size, 2, 'The reservation must work before either target exists on disk');
    } finally { release(); }
    const actual = await pending;
    assert.equal(new Set(actual).size, 2);
    for (const uri of actual) validName(uriName(uri));
    assert.deepEqual(new Set(actual.map(uri => env.files.get(toPath(uri)))), new Set(['first contents', 'second contents']));
  });
  if (failures.length) throw new Error(`${failures.length} download filename scenarios failed`);
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
