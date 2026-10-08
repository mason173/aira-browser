#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/browser');
function load(name, dependencies = {}) {
  const filename = path.join(root, `${name}.ets`);
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).length, 0, filename);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, {
    module, exports: module.exports, setTimeout, clearTimeout,
    require(id) {
      assert.ok(Object.hasOwn(dependencies, id), `Unexpected runtime dependency: ${id}`);
      return dependencies[id];
    }
  }, { filename });
  return module.exports;
}
const storeModule = load('BrowserTabPreviewImageLeaseStore');
const Store = storeModule.BrowserTabPreviewImageLeaseStore;
const warnings = [];
class Cache {
  async removePreviewImage() { return false; }
  async clearAllPreviewImages() { return false; }
}
const { BrowserTabPreviewCoordinator: Coordinator } = load('BrowserTabPreviewCoordinator', {
  './BrowserTabPreviewImageLeaseStore': storeModule,
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn(...args) { warnings.push(args); } } },
  '../../services/web/BrowserTabPreviewCaptureService': { BrowserTabPreviewCaptureService: class {} },
  '../../services/web/BrowserTabPreviewCacheStore': { BrowserTabPreviewCacheStore: Cache },
  './BrowserTabPreviewMetrics': { BROWSER_TAB_PREVIEW_PIXEL_WIDTH: 400, BROWSER_TAB_PREVIEW_PIXEL_HEIGHT: 800 },
  './BrowserTabPreviewMetricsService': {},
  './BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class {} }
});
function pixelMap(throws = false) {
  return { releases: 0, release() { this.releases++; if (throws) throw Error('platform failure'); return Promise.resolve(); } };
}
function entry(pixel, uri = '') {
  return { tabId: 'tab', capturedAt: 1, sharedSnapshotPixelMap: pixel, sharedSnapshotImageUri: uri,
    lockedForTransition: false, signature: '', lastKnownGoodSignature: '' };
}
function coordinator(pixel, uri = '') {
  const c = new Coordinator({}, {});
  c.previewEntries.tab = entry(pixel, uri);
  return c;
}
async function main() {
  const store = new Store();
  const p = pixelMap();
  assert.equal(store.retain(p), true);
  assert.equal(store.retain(p), true);
  await store.requestRelease(p, () => p.release());
  await store.requestRelease(p, () => { throw Error('duplicate callback'); });
  await store.releaseLease(p);
  assert.equal(p.releases, 0);
  // Retaining a still-live deferred image extends its lifetime.
  assert.equal(store.retain(p), true);
  await store.releaseLease(p);
  assert.equal(p.releases, 0);
  await store.releaseLease(p);
  await store.releaseLease(p);
  await store.requestRelease(p, () => p.release());
  assert.equal(p.releases, 1);
  assert.equal(store.retain(p), false);

  const owned = pixelMap();
  store.retain(owned);
  await store.releaseLease(owned);
  assert.equal(owned.releases, 0, 'returning a lease must not release an owned entry');
  assert.equal(store.retain(owned), true);
  await store.releaseLease(owned);
  await store.requestRelease(owned, () => owned.release());
  assert.equal(owned.releases, 1);

  // Persisting a URI over an existing in-memory image must keep a live lease valid.
  {
    const orphan = pixelMap();
    const c = coordinator(orphan, 'file://previous');
    c.profileBoundaryService.isSessionEphemeral = () => false;
    const live = c.acquireSharedSnapshot('tab');
    c.captureCacheDirectoryStatsInBackground = () => {};
    c.cacheStore.savePreviewImageWithStats =
      async () => ({ uri: 'file://persisted', bytes: 1, reused: false });
    c.surfaceHost.resolveWebViewportSnapshotSize = () => ({ width: 400, height: 800 });
    assert.equal(await c.persistImmediateSharedSnapshot(
      { id: 'tab', url: 'https://example.com', isHome: false },
      pixelMap(),
      { captureSource: 'web-page', captureScope: 'web-content', transitionFrame: 'current-web' }), true);
    assert.equal(orphan.releases, 0, 'a replaced image is only requested for release');
    assert.equal(live.state.sharedSnapshotPixelMap, orphan);
    live.release();
    live.release();
    // Only the lease held by the gesture may still be outstanding here; if the coordinator forgot to
    // request disposal, this image would never be released at all.
    assert.equal(orphan.releases, 1);
    await c.releaseCachedPixelMap(orphan, 'tab', 'duplicate');
    assert.equal(orphan.releases, 1);
  }
  for (const asynchronous of [false, true]) {
    const failing = pixelMap();
    let attempts = 0;
    await store.requestRelease(failing, () => {
      attempts++;
      assert.equal(store.retain(failing), false, 'mark released before callback');
      if (asynchronous) return Promise.reject(Error('async platform failure'));
      throw Error('sync platform failure');
    });
    await store.requestRelease(failing, () => { attempts++; });
    assert.equal(attempts, 1);
    assert.equal(store.retain(failing), false);
  }

  for (const operation of ['replace', 'remove', 'clear', 'private', 'sync', 'force']) {
    const old = pixelMap();
    const next = pixelMap();
    const c = coordinator(old, 'file://old');
    const a = c.acquireSharedSnapshot('tab');
    const b = c.acquireSharedSnapshot('tab');
    assert.notEqual(a.state, c.previewEntries.tab);
    assert.equal(a.state.sharedSnapshotPixelMap, old);
    assert.equal(a.state.transitionReady, c.getSharedSnapshotState('tab').transitionReady);
    assert.equal(c.isTransitionLocked('tab'), false);
    c.lockTransitionSnapshot('tab');
    a.release();
    a.release();
    assert.equal(c.isTransitionLocked('tab'), true, 'lease release does not unlock transition');
    c.unlockTransitionSnapshot('tab');
    if (operation === 'replace') {
      await c.releaseCachedPixelMap(old, 'tab', operation);
      c.previewEntries.tab = entry(next);
    } else if (operation === 'remove') await c.removeTab('tab');
    else if (operation === 'clear') await c.clearAll();
    else if (operation === 'private') await c.removeSessionEphemeralPreviews(['tab']);
    else if (operation === 'sync') c.syncTabs([]);
    else {
      c.profileBoundaryService.isSessionEphemeral = () => true;
      c.surfaceHost.resolveWebViewportSnapshotSize = () => ({ width: 400, height: 800 });
      c.captureService.captureWebPage = async () => ({ snapshot: next, source: 'web-page', sharedSnapshotImageUri: 'file://next' });
      c.captureCacheDirectoryStatsInBackground = () => {};
      assert.equal(await c.capturePreview({ tab: { id: 'tab', url: 'https://example.com', isHome: false },
        controller: {}, hasRenderableSurface: true, force: true }), true);
      assert.equal(c.getSharedSnapshotState('tab').sharedSnapshotPixelMap, next);
    }
    assert.equal(old.releases, 0, operation);
    assert.equal(b.state.sharedSnapshotPixelMap, old);
    assert.equal(b.state.sharedSnapshotImageUri, 'file://old');
    b.release();
    b.release();
    await c.releaseCachedPixelMap(old, 'tab', 'duplicate');
    assert.equal(old.releases, 1, operation);
    assert.equal(next.releases, 0);
  }
  const c = coordinator(undefined, 'file://only');
  const uri = c.acquireSharedSnapshot('tab');
  assert.equal(uri.state.sharedSnapshotImageUri, 'file://only');
  uri.release();
  uri.release();
  assert.equal(c.acquireSharedSnapshot('missing'), undefined);
  c.previewEntries.tab = entry(undefined);
  assert.equal(c.acquireSharedSnapshot('tab'), undefined);
  const broken = pixelMap(true);
  c.previewEntries.tab = entry(broken);
  const lease = c.acquireSharedSnapshot('tab');
  await c.releaseCachedPixelMap(broken, 'tab', 'failing');
  lease.release();
  await c.releaseCachedPixelMap(broken, 'tab', 'failing-again');
  assert.equal(broken.releases, 1);
  assert.equal(warnings.length, 1);
  assert.equal(c.acquireSharedSnapshot('tab'), undefined, 'released PixelMaps cannot be leased again');
  console.log('Tab preview image lease checks passed (real store and coordinator).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
