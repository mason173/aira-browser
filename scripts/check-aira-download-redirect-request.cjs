#!/usr/bin/env node
'use strict';

// Exercise production V2 creation, state transitions and transfer dispatch.
// Default mode sends real local HTTP GETs. --control-only explicitly checks the
// application orchestration with an in-memory response; it is not a network test.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const controlOnly = process.argv.includes('--control-only');
const hits = new Map();
const log = { info() {}, warn() {}, error() {} };
const inertModule = new Proxy({}, { get: () => class {} });
const html = '<html><script>location.replace("/target.bin")</script></html>';
function payload(url) { return url.endsWith('.html') ? html : 'FILE'; }
async function request(url, options) {
  if (!controlOnly) return fetch(url, options);
  const pathname = new URL(url).pathname;
  const count = (hits.get(pathname) ?? 0) + 1;
  hits.set(pathname, count);
  return { status: count > 1 ? 403 : 200, headers: new Map(),
    text: async () => count > 1 ? 'token consumed' : payload(pathname) };
}
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
            const response = await request(url, { method: options.method, headers: options.header });
            return { responseCode: response.status, header: Object.fromEntries(response.headers), result: await response.text() };
          }, destroy() {}
        })
      } };
      // Load local service helpers and pure domain rules without replacing their behavior.
      if (id.endsWith('/DownloadV2RecordStore')) return inertModule;
      if (id.startsWith('./') || /\/(DownloadV2Types|DownloadV2TaskEntity|DownloadV2StateMachine|DownloadFileNameService|DownloadV2Engine|DownloadV2Repository|BrowserModels|DownloadTypes|RuntimeDiagnosticModels)$/.test(id)) {
        return load(path.resolve(path.dirname(filename), id + '.ets'));
      }
      return inertModule;
    }
  }, { filename });
  cache.set(filename, exports);
  return exports;
}

async function scenario(base, mimeType, attachment, privacyMode = 'regular', native = false) {
  hits.clear();
  const url = base + (mimeType ? '/once.html' : '/once.bin');
  const captured = { guid: 'test', sourceId: 'page-source', url, method: 'GET', totalBytes: 0,
    nativeReason: native ? 'custom_headers' : undefined, suggestedFileName: mimeType ? 'once.html' : 'once.bin',
    sourceHost: '127.0.0.1', createdAt: 1, mimeType, contentDisposition: attachment ? 'attachment; filename="once.html"' : undefined,
    userAgent: 'Page-UA', referer: 'https://page.example/watch',
    headers: native ? { Cookie: 'fixture=original', Authorization: 'Bearer fixture' } : { Cookie: 'fixture=original' },
    boundary: { profileId: 'default', privacyMode,
      dataScope: privacyMode === 'private' ? 'session_ephemeral' : 'profile_persistent', windowId: 'test' } };
  const { DownloadV2Engine } = load(path.join(sourceRoot, 'core/downloadv2/DownloadV2Engine.ets'));
  const { InMemoryDownloadV2Repository } = load(path.join(sourceRoot, 'data/downloadv2/DownloadV2Repository.ets'));
  const repository = new InMemoryDownloadV2Repository();
  const engine = new DownloadV2Engine(repository);
  const requests = [];
  const adapter = {
    setCallbacks() {},
    async startDirectDownload(snapshot) {
      assert.equal(hits.size, 0, 'V2 must not request any URL before starting the actual transfer');
      requests.push(snapshot);
      assert.equal(snapshot.url, captured.url, 'HTML must be saved rather than interpreted as navigation');
      assert.equal(snapshot.privacyMode, privacyMode);
      assert.equal(snapshot.mimeType, mimeType);
      assert.equal(snapshot.userAgent, 'Page-UA');
      assert.equal(snapshot.referer, 'https://page.example/watch');
      assert.equal(snapshot.sourceId, captured.sourceId);
      assert.equal(snapshot.downloadDriver, native ? 'libcurl' : 'arkweb');
      assert.equal(engine.findTask(captured.guid).status, 'running', 'Reserve a real queue slot before transfer');
      assert.equal(snapshot.headers.Cookie, 'fixture=original');
      assert.equal(snapshot.headers.Authorization, native ? 'Bearer fixture' : undefined);
      const response = await request(snapshot.url, { headers: snapshot.headers });
      assert.equal(response.status, 200);
      assert.equal(await response.text(), mimeType ? html : 'FILE');
      return { ...snapshot, state: 'IN_PROGRESS', receivedBytes: 0, currentSpeed: 0,
        platformTaskId: native ? 'libcurl:test' : 'arkweb:test' };
    }
  };
  const { DownloadV2Service } = load(path.join(sourceRoot, 'services/downloadv2/DownloadV2Service.ets'));
  const service = new DownloadV2Service(engine, { setCallbacks() {} }, repository, adapter, {}, {
    canWriteSessionTasks: () => true
  });
  service.initialize = async () => {};
  service.downloadTargetResolutionService = { resolveTargetPlan: async () => ({ fileName: captured.suggestedFileName,
    destination: { kind: privacyMode === 'private' ? 'session_temp' : 'system_downloads' },
    tempFilePath: '/sandbox/' + captured.suggestedFileName, initialDisplayPath: '', storageMode: 'sandbox', completionExportPolicy: 'none' }),
    validateDestination: async () => true };
  service.downloadQueuePolicyService = { resolveStartAdmission: () => ({ canStartNow: true }) };
  service.downloadNetworkPolicyService = { resolveStartAdmission: () => ({}) };
  service.downloadTriggerDiagnosticsService = { recordCapturedRequest() {}, recordDriverSelection() {}, recordStartResult() {} };
  service.resolveHlsSegmentConcurrency = () => 4;
  service.syncTaskFromPlatformEvent = () => true;
  service.markStartedSnapshotAccepted = () => {};
  await service.createTaskFromCapturedRequest(captured, false);
  assert.equal(engine.findTask(captured.guid).status, 'running');
  assert.equal(requests.length, 1);
  assert.equal(hits.get(new URL(url).pathname), 1);
  assert.equal(hits.get('/target.bin'), undefined);
}

(async () => {
  if (!controlOnly) await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const base = controlOnly ? 'http://fixture.invalid' : `http://127.0.0.1:${server.address().port}`;
  console.log(controlOnly ? 'Control-only: no HTTP transport coverage' : 'Real local HTTP fixture');
  const failures = [];
  try {
    for (const [name, mime, attachment, privacy, native] of [
      ['unknown MIME one-time URL', undefined, false, 'regular'],
      ['known HTML one-time URL with JS', 'text/html', false, 'regular'],
      ['explicit HTML attachment', 'text/html', true, 'regular'],
      ['private known HTML retains boundary and cookies', 'text/html', false, 'private'],
      ['explicit custom headers retain native transport and credentials', 'text/html', false, 'regular', true],
      ['private explicit headers retain boundary and credentials', 'text/html', false, 'private', true]
    ]) {
      try { await scenario(base, mime, attachment, privacy, native); console.log('PASS ' + name); }
      catch (error) { failures.push(name); console.error('FAIL ' + name + ': ' + error.stack); }
    }
  } finally {
    if (!controlOnly) {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  }
  assert.equal(failures.length, 0, failures.join(', '));
})().catch(error => { console.error(error); process.exitCode = 1; });
