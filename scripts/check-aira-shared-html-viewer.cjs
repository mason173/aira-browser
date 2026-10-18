#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const ts = require('./lib/deveco-typescript.cjs');
const repo = path.resolve(__dirname, '..');
const root = path.join(repo, 'AiraBrowser/entry/src/main/ets');
const baseline = process.argv.includes('--baseline');
const modules = new Map();
const responseState = new WeakMap();
let sharedRecords = [];
let fileFailure = false;
let fileSize = 707;
const openedUris = [];

// Native WebResourceResponse exposes methods, not the plain fields consumed by
// WebBridge::ConvertJSValueToWebResponse in arkts_native_web_bridge.cpp.
class Response {
  constructor() {
    responseState.set(this, { mimeType: '', code: 0, headers: [], ready: true });
    this.completed = new Promise(resolve => { this.complete = resolve; });
  }
  setResponseData(value) { responseState.get(this).data = value; }
  setResponseEncoding(value) { responseState.get(this).encoding = value; }
  setResponseMimeType(value) { responseState.get(this).mimeType = value; }
  setResponseHeader(value) { responseState.get(this).headers = value; }
  setResponseCode(value) { responseState.get(this).code = value; }
  setReasonMessage(value) { responseState.get(this).reason = value; }
  setResponseIsReady(value) {
    responseState.get(this).ready = value;
    if (value) this.complete();
  }
}

const platform = {
  '@kit.CoreFileKit': { fileIo: {
    OpenMode: { READ_ONLY: 0 },
    async stat() {
      if (fileFailure) throw { code: 13900012 };
      return { size: fileSize, isDirectory: () => false };
    },
    async open(uri) { openedUris.push(uri); return { fd: 42 }; },
    async close() {}
  } },
  '@kit.ArkTS': { util: {} },
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, error() {} } },
  '@kit.ShareKit': { systemShare: { getSharedData: async () => ({ getRecords: () => sharedRecords }) } },
  '@ohos.url': { default: { URL: { parseURL: value => new URL(value) } } },
  '@ohos.deviceInfo': { default: { sdkApiVersion: 23 } }
};

function readSource(filename) {
  if (baseline && ['HostedWebNode.ets', 'WebDefaultContextMenuModifier.ets'].includes(path.basename(filename))) {
    return execFileSync('git', ['show', `HEAD:${path.relative(repo, filename)}`], { cwd: repo, encoding: 'utf8' });
  }
  return fs.readFileSync(filename, 'utf8');
}

function evaluate(source, filename, globals = {}) {
  const result = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal(result.diagnostics.length, 0, filename);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, URL, WebResourceResponse: Response, $r: value => value, ...globals,
    require(id) {
      if (platform[id]) return platform[id];
      if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (id.endsWith('/MarkdownDocumentViewerService')) return { MarkdownDocumentViewerService: class {
        isMarkdownSourceUrl() { return false; }
        isMarkdownViewerUrl() { return false; }
        parseViewerUrl() { return undefined; }
      } };
      assert.ok(id.startsWith('.'), `Unexpected runtime dependency: ${id}`);
      return load(path.resolve(path.dirname(filename), `${id}.ets`));
    }
  }, { filename });
  return module.exports;
}

function load(filename) {
  if (!modules.has(filename)) modules.set(filename, evaluate(readSource(filename), filename));
  return modules.get(filename);
}

const { DocumentViewerService } = load(path.join(root, 'services/viewer/DocumentViewerService.ets'));
const { SharedBrowserUrlIngressService } = load(path.join(root, 'services/share/SharedBrowserUrlIngressService.ets'));
const { BrowserWebAttributeModifier } = load(path.join(root, 'core/web/WebDefaultContextMenuModifier.ets'));
const { documentViewerHtmlFileTransport } = load(path.join(root, 'services/viewer/DocumentViewerHtmlFileTransport.ets'));
const viewer = new DocumentViewerService();
const ingress = new SharedBrowserUrlIngressService();
const { BrowserAddressDisplayCoordinator } = load(path.join(root,
  'core/browser/BrowserAddressDisplayCoordinator.ets'));
const toolbarPolicy = load(path.join(root, 'core/browser/BrowserToolbarChromeStylePolicy.ets'));
const { BrowserWebViewportCoordinator } = load(path.join(root,
  'core/browser/BrowserWebViewportCoordinator.ets'));
const shellSource = readSource(path.join(root, 'app/pages/BrowserShellPage.ets'));
function shellMethod(name) {
  const match = shellSource.match(new RegExp(`  private ${name}\\([^]*?\\n  }`));
  assert.ok(match, `Missing shell method: ${name}`);
  return match[0];
}
const { HtmlBrowserShell } = evaluate(`export class HtmlBrowserShell {
  ${shellMethod('buildCurrentDocumentViewerChromeContext')}
  ${shellMethod('shouldUseSplitToolbarChrome')}
}`, 'HtmlBrowserShell.ts', { isSplitToolbarChromeActive: toolbarPolicy.isSplitToolbarChromeActive });

function checkHtmlBrowserChrome(url) {
  for (const style of ['split', 'dock', 'floating']) {
    const shell = Object.assign(new HtmlBrowserShell(), {
      toolbarChromeStyle: style, activeTabId: 'shared-html', currentUrl: url,
      pendingWebUrl: '', currentTitle: 'Shared report', documentViewerService: viewer,
      tabManager: { getTab: () => ({ url, pendingUrl: '', lastGoodUrl: '' }) },
      isLargeScreenShellFamilyActive: () => false,
      shouldHideRootBottomChromeForImmersion: () => false,
      readerModeSessionSnapshot: { state: { visible: false } }, novelReaderSnapshot: { visible: false }
    });
    const splitChromeMounted = shell.shouldUseSplitToolbarChrome();
    const floatingChromeSuppressed = toolbarPolicy.shouldSuppressLegacyFloatingToolbar(style, false);
    assert.ok(splitChromeMounted || !floatingChromeSuppressed,
      `External HTML must mount the selected ${style} toolbar: both toolbar families were hidden`);
    assert.equal(splitChromeMounted, style !== 'floating', 'HTML must honor the selected toolbar family');
    const context = shell.buildCurrentDocumentViewerChromeContext();
    assert.equal(context.policy.active, false, 'HTML must use browser presentation instead of preview actions');
    const viewportInput = { hostHeightPx: 844, visualTopInsetPx: 100, visualBottomInsetPx: 80,
      largeScreenShellActive: false, nativeVideoTakeoverActive: false };
    assert.deepEqual(BrowserWebViewportCoordinator.resolvePresentation({
      ...viewportInput, fullViewport: context.policy.fullViewport
    }), BrowserWebViewportCoordinator.resolvePresentation({ ...viewportInput, fullViewport: false }),
    `${style}: HTML must reserve toolbar space instead of covering it with a full-height viewport`);
  }
  const visibleUrl = documentViewerHtmlFileTransport.resolveVisibleUrl(url) || url;
  assert.equal(viewer.resolveChromePolicy(visibleUrl).active, true,
    'local-file identity for loading, file metadata and persistence must remain intact');
}

const hostedSource = readSource(path.join(root, 'core/web/HostedWebNode.ets'));
const direct = /\.onInterceptRequest\((\(event: OnInterceptRequestEvent\) => \{[\s\S]*?\n      \})\)/.exec(hostedSource);
const modifier = /\.attributeModifier\(new BrowserWebAttributeModifier\((\{[\s\S]*?\n      \})\)\)/.exec(hostedSource);
assert.ok(direct || modifier, 'Missing production interception binding');
const factorySource = direct
  ? `export function bind(config) { return ${direct[1]}; }`
  : `export function bind(config) {
      let callback;
      new BrowserWebAttributeModifier(${modifier[1]}).applyNormalAttribute({
        onInterceptRequest(value) { callback = value; }
      });
      return callback;
    }`;
const { bind } = evaluate(factorySource, 'HostedWebBinding.ts', {
  BrowserWebAttributeModifier, documentViewerHtmlFileTransport
});

function nativeResponse(value) {
  if (value === null || direct) return value;
  // Model the modifier bridge's public-field conversion, which does not unwrap
  // the native response or retain the asynchronous response object. The direct
  // JSWeb::OnInterceptRequest binding unwraps and retains that native object.
  const response = new Response();
  response.setResponseCode(value.statusCode ?? 0);
  response.setResponseMimeType(value.mimeType ?? '');
  response.setResponseData(value.fd ?? value.body);
  response.setResponseIsReady(value.isReady ?? true);
  return response;
}

async function scenario(protectionEnabled, fileUri, utd) {
  sharedRecords = [{ utd, uri: fileUri, title: 'Shared report.html' }];
  const resolution = await ingress.resolve({ action: 'ohos.want.action.sendData' });
  assert.equal(resolution.kind, 'browser_url');
  assert.equal(viewer.parseViewerUrl(resolution.url).fileUri, fileUri);
  const transportUrl = viewer.resolveHtmlFileTransportUrl(resolution.url);
  checkHtmlBrowserChrome(resolution.url);
  checkHtmlBrowserChrome(fileUri);
  checkHtmlBrowserChrome(transportUrl);
  const address = new BrowserAddressDisplayCoordinator();
  assert.equal(address.resolveCommittedDisplay('shared-html', resolution.url), fileUri);
  assert.equal(address.resolveEditingText('shared-html', resolution.url, ''), fileUri);
  const callback = bind({
    tabId: 'shared-html', networkInterceptEnabled: protectionEnabled,
    callbacks: { onInterceptRequest: (_tabId, event) => viewer.tryBuildHtmlFileResponse(event.request) }
  });
  assert.equal(typeof callback, 'function', 'local HTML delivery must remain available with protection disabled');
  const response = nativeResponse(callback({
    request: { getRequestUrl: () => transportUrl, isMainFrame: () => true }
  }));
  assert.ok(response);
  await response.completed;
  const native = responseState.get(response);
  assert.equal(native.code, 200, 'the native bridge must retain the response status instead of producing status=0');
  assert.equal(native.mimeType, utd === 'general.xhtml' ? 'application/xhtml+xml' : 'text/html',
    'the native bridge must retain the document MIME instead of starting a download');
  assert.equal(native.data, 42, 'the native bridge must retain the streamed file descriptor');
  assert.equal(openedUris.at(-1), fileUri);
  if (!protectionEnabled) {
    assert.equal(callback({ request: { getRequestUrl: () => 'https://example.com/' } }), null,
      'ordinary requests must bypass disabled content filtering');
  }
  console.log(`PASS native HTML handoff: protection=${protectionEnabled}, ${utd}`);
}

async function main() {
  for (const extension of ['txt', 'json']) {
    const url = viewer.buildViewerUrl(`file://docs/report.${extension}`);
    const policy = viewer.resolveChromeContext([url], '').policy;
    assert.equal(policy.active, true, 'other document types retain their preview UI');
    assert.equal(policy.fullViewport, true);
  }
  const htmlUrl = viewer.buildViewerUrl('file://docs/report.html');
  const previousTextUrl = viewer.buildViewerUrl('file://docs/previous.txt');
  const transportUrl = viewer.resolveHtmlFileTransportUrl(htmlUrl);
  for (const url of [htmlUrl, transportUrl]) {
    assert.equal(viewer.resolveChromeContext([url, previousTextUrl], '').policy.active, false,
      'an HTML target must not inherit preview chrome from the previous document');
  }
  assert.equal(viewer.isDocumentViewerTabRecord({ url: htmlUrl }), true);
  const originalUri = 'file://docs/Report  v2+appendix.html?key=a&value=b#section';
  const originalViewerUrl = viewer.buildViewerUrl(originalUri, 'text/html');
  const address = new BrowserAddressDisplayCoordinator();
  assert.equal(address.resolveCommittedDisplay('shared-html', originalViewerUrl), originalUri);
  assert.equal(address.resolveEditingText('shared-html', '', originalViewerUrl), originalUri);
  let failures = 0;
  for (const protection of [true, false]) {
    for (const [uri, utd] of [
      ['file://com.example.sender/data/storage/el2/base/cache/Report%20v2.html', 'general.html'],
      ['file://docs/storage/Users/currentUser/Report.html', 'general.html'],
      ['file://com.example.sender/data/storage/el2/base/cache/Report.xhtml', 'general.xhtml']
    ]) {
      try { await scenario(protection, uri, utd); }
      catch (error) { failures++; console.error(error.message); }
    }
  }
  assert.equal(failures, 0, `${failures} native HTML handoff scenarios failed`);
  console.log('PASS floating/split/dock toolbar mounting, normal viewport reserves and editable file addresses');
  fileSize = 4 * 1024 * 1024;
  await scenario(true, 'file://docs/large.html', 'general.html');
  const request = (url) => ({ getRequestUrl: () => url, isMainFrame: () => true });
  const expired = viewer.tryBuildHtmlFileResponse(request('https://document-viewer.aira.invalid/html/expired'));
  assert.equal(responseState.get(expired).code, 404);
  fileFailure = true;
  const unreadable = viewer.tryBuildHtmlFileResponse(request(
    viewer.resolveHtmlFileTransportUrl(viewer.buildViewerUrl('file://docs/missing.html'))
  ));
  await unreadable.completed;
  assert.equal(responseState.get(unreadable).code, 500);
  assert.match(responseState.get(unreadable).data, /viewer_html_unreadable/);
  assert.equal(viewer.tryBuildHtmlFileResponse(request('https://example.com/report.html')), null);
  console.log('PASS large files, expired tickets, unreadable files and ordinary network requests');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
