#!/usr/bin/env node
'use strict';

// Exercise production V2 task creation and transfer dispatch. Only storage, policy,
// and the platform transport are modeled; the transport sends real local HTTP GETs.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const hits = new Map();
const log = { info() {}, warn() {}, error() {} };
const inertModule = new Proxy({}, { get: () => class {} });
const html = '<html><script>location.replace("/target.bin")</script></html>';
const server = http.createServer((request, response) => {
  const count = (hits.get(request.url) ?? 0) + 1;
  hits.set(request.url, count);
  if (count > 1) { response.writeHead(403); response.end('token consumed'); return; }
  response.writeHead(200, { 'Content-Type': request.url.endsWith('.html') ? 'text/html' : 'application/octet-stream',
    'Set-Cookie': 'landing=only-this-response; Path=/' });
  response.end(request.url.endsWith('.html') ? html : 'FILE');
});
const cache = new Map();
function load(filename) {
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
  }).outputText;
  vm.runInNewContext(compiled, {
    exports, $r: value => value,
    require(id) {
      if (id === '@kit.PerformanceAnalysisKit') return { hilog: log };
      if (id === '@ohos.url') return { default: { URL: { parseURL: (url, base) => new URL(url, base) } } };
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id === '@kit.NetworkKit') return { http: {
        RequestMethod: { GET: 'GET' }, HttpDataType: { STRING: 0 }, createHttp: () => ({
          async request(url, options) {
            const response = await fetch(url, { method: options.method, headers: options.header });
            return { responseCode: response.status, header: Object.fromEntries(response.headers), result: await response.text() };
          }, destroy() {}
        })
      } };
      // Load local service helpers and pure domain rules without replacing their behavior.
      if (id.startsWith('./') || /\/(DownloadV2Types|DownloadV2TaskEntity|DownloadV2StateMachine|DownloadFileNameService)$/.test(id)) {
        return load(path.resolve(path.dirname(filename), id + '.ets'));
      }
      return inertModule;
    }
  }, { filename });
  cache.set(filename, exports);
  return exports;
}

async function scenario(base, mimeType, attachment, privacyMode = 'regular') {
  hits.clear();
  const url = base + (mimeType ? '/once.html' : '/once.bin');
  const captured = { guid: 'test', url, method: 'GET', totalBytes: 0, suggestedFileName: mimeType ? 'once.html' : 'once.bin',
    sourceHost: '127.0.0.1', createdAt: 1, mimeType, contentDisposition: attachment ? 'attachment; filename="once.html"' : undefined,
    userAgent: 'Page-UA', referer: 'https://page.example/watch', headers: { Cookie: 'fixture=original', Authorization: 'Bearer fixture' },
    boundary: { profileId: 'default', privacyMode, dataScope: privacyMode === 'private' ? 'memory' : 'persistent', windowId: 'test' } };
  let task;
  const merge = patch => {
    for (const [key, value] of Object.entries(patch)) {
      if (value !== undefined) task[key] = value && typeof value === 'object' ? { ...task[key], ...value } : value;
    }
    return task;
  };
  const engine = {
    createTask(input) {
      task = { ...input, ...input.boundary, status: 'queued', persistence: {}, runtime: {}, timing: { createdAt: 1 }, failure: {} };
      return task;
    },
    synchronizeTask: (_guid, patch) => merge(patch), findTask: () => task, listTasks: () => [task],
    dispatch: () => task
  };
  const requests = [];
  const adapter = {
    setCallbacks() {},
    async startDirectDownload(snapshot) {
      assert.equal(hits.size, 0, 'V2 must not request any URL before starting the actual transfer');
      requests.push(snapshot);
      assert.equal(snapshot.url, captured.url, 'HTML must be saved rather than interpreted as navigation');
      assert.equal(snapshot.privacyMode, privacyMode);
      assert.equal(snapshot.mimeType, mimeType);
      assert.equal(snapshot.headers.Cookie, 'fixture=original');
      assert.equal(snapshot.headers.Authorization, 'Bearer fixture');
      const response = await fetch(snapshot.url, { headers: snapshot.headers });
      assert.equal(response.status, 200);
      assert.equal(await response.text(), mimeType ? html : 'FILE');
      return { ...snapshot, state: 'IN_PROGRESS', receivedBytes: 0, currentSpeed: 0, platformTaskId: 'libcurl:test' };
    }
  };
  const { DownloadV2Service } = load(path.join(sourceRoot, 'services/downloadv2/DownloadV2Service.ets'));
  const service = new DownloadV2Service(engine, { setCallbacks() {} }, { flushPersistence: async () => {} }, adapter, {}, {
    canWriteSessionTasks: () => true
  });
  service.initialize = async () => {};
  service.downloadTargetResolutionService = { resolveTargetPlan: async () => ({ fileName: captured.suggestedFileName,
    tempFilePath: '/sandbox/' + captured.suggestedFileName, initialDisplayPath: '', storageMode: 'sandbox', completionExportPolicy: 'none' }) };
  service.downloadQueuePolicyService = { resolveStartAdmission: () => ({ canStartNow: true }) };
  service.downloadNetworkPolicyService = { resolveStartAdmission: () => ({}) };
  service.downloadTriggerDiagnosticsService = { recordCapturedRequest() {}, recordDriverSelection() {}, recordStartResult() {} };
  service.resolveHlsSegmentConcurrency = () => 4;
  service.syncTaskFromPlatformEvent = () => true;
  service.markStartedSnapshotAccepted = () => {};
  await service.createTaskFromCapturedRequest(captured, false);
  assert.equal(requests.length, 1);
  assert.equal(hits.get(new URL(url).pathname), 1);
  assert.equal(hits.get('/target.bin'), undefined);
}

(async () => {
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  const failures = [];
  try {
    for (const [name, mime, attachment, privacy] of [
      ['unknown MIME one-time URL', undefined, false, 'regular'],
      ['known HTML one-time URL with JS', 'text/html', false, 'regular'],
      ['explicit HTML attachment', 'text/html', true, 'regular'],
      ['private known HTML retains boundary and credentials', 'text/html', false, 'private']
    ]) {
      try { await scenario(base, mime, attachment, privacy); console.log('PASS ' + name); }
      catch (error) { failures.push(name); console.error('FAIL ' + name + ': ' + error.stack); }
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  assert.equal(failures.length, 0, failures.join(', '));
})().catch(error => { console.error(error); process.exitCode = 1; });
