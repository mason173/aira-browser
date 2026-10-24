#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const filename = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/platform/download/LibcurlDownloadAdapter.ets');
const cookieReads = [];
const nativeRequests = [];
const moduleObject = { exports: {} };
const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
});
vm.runInNewContext(output.outputText, {
  module: moduleObject, exports: moduleObject.exports, setInterval: () => 1, clearInterval() {},
  require(id) {
    if (id === '@kit.ArkWeb') return { webview: { WebCookieManager: {
      fetchCookieSync(url, incognito) {
        cookieReads.push({ url, incognito });
        return incognito ? 'session=private' : 'session=regular';
      }
    } } };
    if (id === '@kit.DeviceCertificateKit') return { certificateManager: {
      CertType: { CA_CERT_SYSTEM: 0 }, getCertificateStorePath: () => '/test-ca'
    } };
    if (id === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
    throw new Error(`Unexpected dependency ${id}`);
  }
}, { filename });

async function run() {
  const adapter = new moduleObject.exports.LibcurlDownloadAdapter();
  adapter.nativeModule = {
    hlsPolicySummary: () => 'test', startTask: () => true, releaseTask() {},
    getSnapshot: () => ({ state: 'failed', receivedBytes: 100, totalBytes: 200,
      speedBytesPerSecond: 0, errorCode: 18, errorMessage: 'Interrupted', diagnosticMessage: '',
      failurePhase: 'http_download', fileExtension: '' }),
    createTask(url, target, headers, hls) {
      nativeRequests.push({ url, target, headers: Array.from(headers), hls });
      return nativeRequests.length;
    }
  };
  const snapshot = (guid, extra = {}) => ({ guid, url: 'https://media.example/video',
    suggestedFileName: 'video.mp4', totalBytes: 0, receivedBytes: 0, currentSpeed: 0,
    state: 'PENDING', lastErrorCode: 0, method: 'GET', ...extra });
  const failures = [];
  async function scenario(name, body) {
    cookieReads.length = 0;
    nativeRequests.length = 0;
    try { await body(); console.log(`PASS ${name}`); }
    catch (error) { failures.push(name); console.error(`FAIL ${name}: ${error.message}`); }
  }
  await scenario('private downloads and their retries use only the private cookie store', async () => {
    const started = await adapter.startDirectDownload(snapshot('private', { privacyMode: 'private' }), '/tmp/test.bin');
    assert.ok(started);
    assert.equal(cookieReads[0].incognito, true);
    assert.ok(nativeRequests[0].headers.includes('Cookie: session=private'));
    const failed = await adapter.reconnectDownload('private', started.platformTaskId);
    assert.equal(failed.state, 'FAILED');
    assert.equal(await adapter.retryDownload('private', '/tmp/test.bin'), true);
    assert.equal(cookieReads[1].incognito, true);
    assert.ok(nativeRequests[1].headers.includes('Cookie: session=private'));
  });
  await scenario('ordinary downloads keep the regular cookie store', async () => {
    await adapter.startDirectDownload(snapshot('regular', { privacyMode: 'regular' }), '/tmp/test.bin');
    assert.equal(cookieReads[0].incognito, false);
    assert.ok(nativeRequests[0].headers.includes('Cookie: session=regular'));
  });
  await scenario('captured credentials and page identity survive without cached range conditions', async () => {
    await adapter.startDirectDownload(snapshot('captured', { userAgent: 'Page-UA', referer: 'https://page.example/watch',
      headers: { cookie: 'ticket=observed', Origin: 'https://page.example', Authorization: 'Bearer test',
        Range: 'bytes=100-', 'If-Range': 'old-etag', 'If-None-Match': 'cached-etag',
        'If-Modified-Since': 'Thu, 01 Jan 2026 00:00:00 GMT', 'Accept-Encoding': 'gzip' }
    }), '/tmp/test.bin');
    const headers = nativeRequests[0].headers;
    assert.equal(cookieReads.length, 0);
    for (const expected of ['cookie: ticket=observed', 'Origin: https://page.example', 'Authorization: Bearer test',
      'User-Agent: Page-UA', 'Referer: https://page.example/watch']) assert.ok(headers.includes(expected), expected);
    assert.equal(headers.some(header => /^(range|if-range|if-none-match|if-modified-since|accept-encoding):/i.test(header)), false);
  });
  await scenario('HLS progress never treats manifest length as the total video length', async () => {
    const started = await adapter.startDirectDownload(snapshot('hls-progress', {
      url: 'https://media.example/index.m3u8', mimeType: 'application/vnd.apple.mpegurl', totalBytes: 777
    }), '/tmp/hls-progress.ts');
    assert.equal(started.totalBytes, 0);
    adapter.nativeModule.getSnapshot = () => ({ state: 'running', receivedBytes: 2048, totalBytes: 0,
      speedBytesPerSecond: 100, errorCode: 0, errorMessage: '', diagnosticMessage: '', failurePhase: '', fileExtension: '.ts' });
    const progress = await adapter.reconnectDownload('hls-progress', started.platformTaskId);
    assert.equal(progress.totalBytes, 0); assert.equal(progress.receivedBytes, 2048);
  });
  if (failures.length) throw new Error(`${failures.length} download context scenarios failed`);
}
run().catch(error => { console.error(error.message); process.exitCode = 1; });
