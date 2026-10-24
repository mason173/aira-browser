#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const resources = { resolveAppResourceText: value => value };
const inertModule = new Proxy({}, { get: () => class {} });

function load(relativePath) {
  const filename = path.join(sourceRoot, relativePath);
  const exports = {};
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(compiled, {
    exports,
    require(name) {
      if (name.endsWith('/AppResourceText')) return resources;
      if (name.endsWith('/MediaManifestModels')) return load('features/mediaDiscovery/MediaManifestModels.ets');
      if (name.endsWith('/BrowserWindowRuntime')) return {
        BrowserWindowRuntime: { resolveActiveShellPresentationSurface: () => 'compact' }
      };
      if (name === '@kit.ArkWeb') return { webview: { WebHitTestType: { HttpAnchor: 1, Img: 2, HttpAnchorImg: 3 } } };
      return inertModule;
    },
    $r: value => value,
    console
  }, { filename });
  return exports;
}

const { BrowserMediaDiscoveryCoordinator } = load('core/browser/media/BrowserMediaDiscoveryCoordinator.ets');
const media = Object.create(BrowserMediaDiscoveryCoordinator.prototype);
const { MediaCandidateProjector } = load('services/media/MediaCandidateProjector.ets');
const projector = Object.create(MediaCandidateProjector.prototype);
const { WebLinkContextMenuCoordinator } = load('core/web/WebLinkContextMenuCoordinator.ets');
const { WebLinkContextMenuFixedActionApplication } = load('core/web/WebLinkContextMenuActionApplication.ets');

async function main() {
  const failures = [];
  async function check(name, action) {
    try { await action(); console.log('PASS ' + name); }
    catch (error) { failures.push(name); console.error('FAIL ' + name + ': ' + error.message); }
  }

  await check('sniffed extensionless HLS keeps its format and captured request context', () => {
    const request = media.buildResourceDownloadPromptRequest({
      url: 'https://cdn.example.test/play?id=7', kind: 'hls', pageUrl: 'https://page.example.test/watch',
      sourceHost: 'cdn.example.test', displayName: 'movie.ts', mimeType: 'text/plain',
      estimatedTotalBytes: 5000, userAgent: 'fallback-UA', referer: 'https://fallback.example.test/',
      originUrl: 'https://fallback.example.test', requestHeaders: {
        'user-agent': 'captured-UA', referer: 'https://frame.example.test/player',
        origin: 'https://frame.example.test', Cookie: 'session=captured', Authorization: 'Bearer fixture'
      }
    });
    assert.equal(request.mimeType, 'application/vnd.apple.mpegurl');
    assert.equal(request.url, 'https://cdn.example.test/play?id=7');
    assert.equal(request.totalBytes, 5000);
    assert.equal(request.headers['user-agent'], 'captured-UA');
    assert.equal(request.headers.referer, 'https://frame.example.test/player');
    assert.equal(request.headers.origin, 'https://frame.example.test');
    assert.equal(request.headers.Cookie, 'session=captured');
    assert.equal(request.headers.Authorization, 'Bearer fixture');
    assert.equal(Object.keys(request.headers).length, 5);
  });

  await check('resource actions reject protected and separate streams while keeping AES-128 HLS', () => {
    const candidate = { url: 'https://cdn.example.test/play', kind: 'hls', family: 'manifest',
      actionHints: ['download', 'copy'], downloadabilityState: 'downloadable',
      playabilityState: 'candidate' };
    assert.equal(projector.isDownloadCandidate(candidate), true);
    assert.equal(projector.isDownloadCandidate({ ...candidate, playabilityState: 'protected' }), false);
    assert.equal(projector.isDownloadCandidate({ ...candidate, validation: { state: 'protected' } }), false);
    assert.equal(projector.isDownloadCandidate({ ...candidate, kind: 'dash' }), false);
    assert.equal(projector.isDownloadCandidate({ ...candidate, acquisition: { mode: 'paired_adaptive' } }), false);
    assert.equal(projector.mediaResourceActions({ ...candidate, playabilityState: 'protected' }).includes('copy'), true);
  });

  await check('long press carries the originating page and UA through menu selection into download', () => {
    const requests = [];
    const application = new WebLinkContextMenuFixedActionApplication({
      downloadConfirmOverlayCoordinator: { requestAndPresent: input => requests.push(input) }
    }, {});
    const menu = Object.create(WebLinkContextMenuCoordinator.prototype);
    menu.overlayCoordinator = { createHiddenLayout: () => ({}), buildInitialLayout: () => ({}) };
    menu.privateWindowPolicyService = { resolveTarget: () => 'tab' };
    menu.userScriptRuntimeCoordinator = { buildContextMenuCommands: () => [] };
    menu.sink = { publishPresentation() {} };
    menu.resolveActionApplication = () => application;
    menu.pendingResultClosed = true;
    menu.presentation = menu.buildHiddenPresentation();
    const facts = { activeTabId: 'source', showPageErrorSurface: false, tabTitle: 'Page', currentTitle: '',
      pageUrl: 'https://page.example.test/source', privacyMode: 'normal', dataScope: 'persistent',
      viewport: { rootWidthVp: 800, rootHeightVp: 600, hostedWebLayerMeasured: false, webViewportTopInsetVp: 0 } };
    const event = { result: { closeContextMenu() {} }, param: {
      getLinkUrl: () => 'https://cdn.example.test/file', getSourceUrl: () => '',
      getUnfilteredLinkUrl: () => '', getMediaType: () => 0, x: () => 20, y: () => 20
    } };
    const controller = { getLastHitTest: () => ({ type: 1 }),
      getCustomUserAgent: () => 'Page-specific-UA', getUserAgent: () => 'Default-UA' };
    assert.equal(menu.show('source', event, controller, facts), true);
    menu.handleOverlayAction({ type: 'select', item: { action: 'download_link' } }, {
      ...facts, activeTabId: 'another', pageUrl: 'https://another.example.test/'
    });
    assert.equal(requests.length, 1);
    assert.equal(requests[0].referer, facts.pageUrl);
    assert.equal(requests[0].userAgent, 'Page-specific-UA');
    assert.equal(menu.show('source', event, { ...controller, getCustomUserAgent: () => '' }, facts), true);
    menu.handleOverlayAction({ type: 'select', item: { action: 'download_link' } }, facts);
    assert.equal(requests[1].userAgent, 'Default-UA');
  });

  await check('AES-128 identity keys remain downloadable, DRM stays protected', async () => {
    const { MediaManifestProcessingService } = load('services/media/MediaManifestProcessingService.ets');
    const parser = new MediaManifestProcessingService({});
    const manifest = method => '#EXTM3U\n#EXT-X-TARGETDURATION:1\n' +
      '#EXT-X-KEY:METHOD=' + method + ',URI="key.bin"\n#EXTINF:1,\npart.ts\n#EXT-X-ENDLIST\n';
    const aes = await parser.parseText(manifest('AES-128'), 'https://cdn.example.test/index.m3u8', {});
    assert.equal(aes.ok, true);
    assert.equal(aes.summary.encrypted, true);
    assert.equal(aes.summary.protectedContent, false);
    const drm = await parser.parseText(manifest('SAMPLE-AES'), 'https://cdn.example.test/index.m3u8', {});
    assert.equal(drm.summary.protectedContent, true);
  });
  assert.equal(failures.length, 0, failures.join(', '));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
