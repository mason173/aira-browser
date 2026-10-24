// Replay the production interception and navigation methods with Rust decisions at the engine
// boundary and a recorded WebResourceResponse. This catches synthetic download responses without
// opening a browser or device; actual ArkWeb download UI still needs device validation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const resources = JSON.parse(fs.readFileSync(path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/resources/brave-resources-v0.13.2.json'), 'utf8'));

function redirect(name) {
  const resource = resources.find(item => item.name === name);
  assert.ok(resource, 'missing pinned Rust resource: ' + name);
  return `data:${resource.kind.mime};base64,${resource.content}`;
}

class Response {
  setResponseHeader(value) { this.headers = value; }
  setResponseData(value) { this.data = value; }
  setResponseEncoding(value) { this.encoding = value; }
  setResponseMimeType(value) { this.mime = value; }
  setResponseCode(value) { this.code = value; }
  setReasonMessage(value) { this.reason = value; }
  setResponseIsReady(value) { this.ready = value; }
}

function load(relative, dependencies = {}, allowUnusedImports = false) {
  const filename = path.join(root, relative + '.ets');
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, WebResourceResponse: Response,
    require(name) {
      if (name in dependencies) return dependencies[name];
      // The coordinator constructor is not run: only its production request paths are exercised.
      if (allowUnusedImports) return {};
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  return module.exports;
}

const policy = load('services/adblock/AdBlockBlockedResourcePolicy');
const { AdBlockResponseFactoryService } = load('services/adblock/AdBlockResponseFactoryService', {
  '@kit.NetworkKit': { http: {} },
  '@kit.ArkWeb': { webview: {} },
  '@kit.ArkTS': { util: { Base64Helper: class {
    decodeSync(value) {
      // Native decode errors and the empty resource must not release a blocked request.
      if (!value || !/^[A-Za-z0-9+/]*={0,2}$/.test(value)) throw new Error('Invalid base64');
      return new Uint8Array(Buffer.from(value, 'base64'));
    }
  } } },
  '../../core/browser/BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class {} },
  '../web/WebCookieHeaderService': { WebCookieHeaderService: class {} },
  './AdBlockBlockedResourcePolicy': policy
});
const { AdBlockRequestClassifierService } = load('services/adblock/AdBlockRequestClassifierService');
const { BrowserAdBlockCoordinator } = load('core/browser/BrowserAdBlockCoordinator', {}, true);

function fixture(options = {}) {
  const evaluations = [];
  const recorded = [];
  const coordinator = Object.create(BrowserAdBlockCoordinator.prototype);
  coordinator.requestClassifier = new AdBlockRequestClassifierService();
  coordinator.responseFactory = new AdBlockResponseFactoryService();
  coordinator.pingRequestSignalService = { consume: () => false };
  coordinator.statsCoordinator = { recordNetworkBlocked: event => recorded.push(event) };
  coordinator.resolveSnapshot = () => ({ version: 1, settings: { preferences: { enabled: options.enabled !== false } } });
  coordinator.resolveEffectivePagePolicy = () => ({ allowlisted: options.allowlisted === true, enabledForPage: true });
  coordinator.runtimeGeneration = { evaluateNetworkRequest(input) {
    evaluations.push(input);
    return { network: {
      shouldBlock: input.enabled && options.blocked !== false,
      redirectDataUrl: options.redirect ?? redirect('noop.html'), rewrittenUrl: ''
    }, response: { cspDirectives: [] } };
  } };
  coordinator.urlTransformRedirectGuards = new Map();
  coordinator.buildUrlTransformRedirectGuardKey = () => 'fixture';
  const headers = options.headers ?? [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'iframe' }];
  const context = {
    tabId: 'tab', pageUrl: 'https://page.example/article', profileId: 'default',
    privacyMode: 'regular', dataScope: 'persistent', capabilitySupported: true,
    controllerAttached: true, strengthenForSmoothScroll: false,
    request: {
      getRequestUrl: () => options.url ?? 'https://ads.example/slot',
      getRequestMethod: () => options.method ?? 'GET',
      isMainFrame: () => options.mainFrame === true,
      isRedirect: () => false,
      getRequestHeader() { if (options.headerFailure) throw new Error('No metadata'); return headers; }
    }
  };
  return { coordinator, context, evaluations, recorded };
}

function assertNoContent(response) {
  assert.ok(response, 'a matched ad must never fall through to the real network request');
  assert.equal(response.code, 204);
  assert.equal(response.data, '');
  assert.equal(response.ready, true);
  assert.equal(response.headers.some(header => header.headerKey.toLowerCase() === 'content-disposition'), false);
}

test('matched main/subframe navigations are denied even when Rust supplies a replacement', () => {
  for (const mainFrame of [false, true]) for (const method of ['GET', 'POST']) {
    for (const resource of ['empty', 'noop.html']) {
      const f = fixture({ mainFrame, method, redirect: redirect(resource) });
      assert.equal(f.coordinator.shouldBlockMainFrameNavigation(f.context), true);
      assert.equal(f.recorded.length, 1);
    }
  }
});

test('interception fallback answers blocked frames and unknown types with empty 204', () => {
  for (const method of ['GET', 'POST']) for (const resource of ['empty', 'noop.html', 'noop.js']) {
    for (const options of [{}, { mainFrame: true }, { headers: [] },
      { headers: [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'object' }] }]) {
      const f = fixture({ method, redirect: redirect(resource), ...options });
      assertNoContent(f.coordinator.handleInterceptRequest(f.context));
      assert.equal(f.recorded.length, 1);
    }
  }
});

test('navigate metadata overrides a script-looking URL for replacement selection', () => {
  const f = fixture({ url: 'https://ads.example/slot.js', redirect: redirect('noop.js'), headers: [
    { headerKey: 'sEc-FeTcH-mOdE', headerValue: ' Navigate ' }
  ] });
  assertNoContent(f.coordinator.handleInterceptRequest(f.context));
  assert.equal(f.evaluations[0].resourceType, 'script', 'rule matching keeps the existing classifier');
});

test('generic binary replacements and unreadable metadata never become synthetic files', () => {
  for (const options of [{ redirect: redirect('empty') },
    { redirect: 'data:application/octet-stream;base64,YQ==' }, { headerFailure: true }]) {
    const f = fixture({ url: 'https://ads.example/slot.js',
      headers: [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'script' }], ...options });
    assertNoContent(f.coordinator.handleInterceptRequest(f.context));
  }
});

test('invalid replacement metadata and native decoding failures keep the ad blocked', () => {
  for (const data of ['not-a-data-url', 'data:text/html,no-base64', 'data:application/javascript;base64,!!!']) {
    const f = fixture({ redirect: data, headers: [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'script' }] });
    assertNoContent(f.coordinator.handleInterceptRequest(f.context));
    assert.equal(f.recorded.length, 1);
  }
});

test('ordinary script, stylesheet, image and XHR replacements keep their contents', () => {
  for (const [resource, headers, url] of [
    ['noop.js', [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'script' }]],
    ['noop.js', [], 'https://ads.example/compat.js'],
    ['noop.css', [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'style' }]],
    ['1x1.gif', [{ headerKey: 'Sec-Fetch-Dest', headerValue: 'image' }]],
    ['noop.json', [{ headerKey: 'X-Requested-With', headerValue: 'XMLHttpRequest' }]]
  ]) {
    const f = fixture({ redirect: redirect(resource), headers, url });
    const response = f.coordinator.handleInterceptRequest(f.context);
    const original = resources.find(item => item.name === resource);
    assert.equal(response.code, 200);
    assert.equal(response.mime, original.kind.mime);
    assert.equal(Buffer.from(response.data).toString('base64'), original.content);
    assert.equal(f.recorded.length, 1);
  }
});

test('ordinary blocks remain 204; disabled, allowlisted and unmatched requests pass through', () => {
  const blocked = fixture({ redirect: '' });
  assertNoContent(blocked.coordinator.handleInterceptRequest(blocked.context));
  for (const options of [{ enabled: false }, { allowlisted: true }, { blocked: false }]) {
    const f = fixture(options);
    assert.equal(f.coordinator.shouldBlockMainFrameNavigation(f.context), false);
    assert.equal(f.coordinator.handleInterceptRequest(f.context), null);
    assert.equal(f.recorded.length, 0);
  }
});
