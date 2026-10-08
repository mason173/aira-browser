#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const coreRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets/core/browser');

function transpile(filename) {
  const result = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS },
    fileName: filename,
    reportDiagnostics: true
  });
  const errors = (result.diagnostics || []).filter((diagnostic) => diagnostic.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, filename);
  return result.outputText;
}

function load(filename, dependencies) {
  const module = { exports: {} };
  vm.runInNewContext(transpile(filename), {
    module,
    exports: module.exports,
    require(id) {
      assert.ok(Object.hasOwn(dependencies, id), `Unexpected runtime dependency: ${id}`);
      return dependencies[id];
    }
  }, { filename });
  return module.exports;
}

const actionModule = load(path.join(coreRoot, 'BrowserTabPreviewActionCoordinator.ets'), {});
const {
  shouldCaptureTabPreviewOnLifecycleExit,
  visibleTabPreviewMustBeReplaced,
  BrowserTabPreviewActionCoordinator
} = actionModule;

for (const reason of ['new_tab', 'background_tab', 'background_prompt', 'window_open', 'tab_switch']) {
  assert.equal(visibleTabPreviewMustBeReplaced(reason), true, `${reason} must store a new screenshot before leaving`);
}
assert.equal(visibleTabPreviewMustBeReplaced('tabs_overview'), false,
  'the tab-manager button stays on the fast snapshot path and must not wait for the file write');
assert.equal(visibleTabPreviewMustBeReplaced('passive'), false, 'an unnamed refresh must not claim a forced replace');

assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: false,
  source: 'ability-background'
}), true, 'a visible web tab still needs a lifecycle capture');
assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: false,
  tabsOverviewVisible: true,
  source: 'ability-background'
}), false, 'tabs overview must keep the scrolled card image');
assert.equal(shouldCaptureTabPreviewOnLifecycleExit({
  activeTabId: 'tab-1',
  showHomePage: true,
  source: 'page-disappear'
}), false);

const events = [];
const requests = [];
const coordinator = new BrowserTabPreviewActionCoordinator();
coordinator.captureLifecycleExit({
  buildRequest: (tabId) => {
    requests.push(tabId);
    return undefined;
  },
  previewCoordinator: {},
  notifyChanged: () => {
    assert.fail('skipping the overview recapture must not refresh the card');
  },
  recordRuntimeEvent: (event, details, tabId) => {
    events.push({ event, details, tabId });
  }
}, {
  activeTabId: 'tab-1',
  showHomePage: false,
  tabsOverviewVisible: true,
  source: 'ability-background'
});
assert.deepEqual(requests, [], 'lifecycle exit must not start webPageSnapshot while the overview is open');
assert.equal(events.length, 1);
assert.equal(events[0].event, 'tab_preview_lifecycle_capture_skipped');
assert.match(events[0].details, /tabs-overview-visible/);

const storeModule = load(path.join(coreRoot, 'BrowserTabPreviewImageLeaseStore.ets'), {});
const previewModule = load(path.join(coreRoot, 'BrowserTabPreviewCoordinator.ets'), {
  './BrowserTabPreviewImageLeaseStore': storeModule,
  '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } },
  '@kit.ArkUI': {},
  '@kit.ArkWeb': {},
  '@kit.ImageKit': {},
  '../tabs/TabManager': {},
  '../../services/web/BrowserTabPreviewCaptureService': {
    BrowserTabPreviewCaptureService: class {},
    buildBrowserTabPreviewComponentSnapshotId: (tabId) => `component-${tabId}`,
    buildBrowserTabPreviewVisibleSnapshotId: (tabId) => `visible-${tabId}`,
    buildBrowserTabPreviewVisibleSurfaceSnapshotId: (tabId) => `surface-${tabId}`,
    buildBrowserTabWebComponentSnapshotId: (tabId) => `web-${tabId}`
  },
  '../../services/web/BrowserTabPreviewCacheStore': {
    BrowserTabPreviewCacheStore: class {
      async savePreviewImageWithStats() {
        return { uri: 'file://scrolled', bytes: 8 };
      }
    },
    DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID: 'default'
  },
  './BrowserTabPreviewMetrics': {
    BROWSER_TAB_PREVIEW_PIXEL_WIDTH: 400,
    BROWSER_TAB_PREVIEW_PIXEL_HEIGHT: 800
  },
  './BrowserTabPreviewMetricsService': { sharedBrowserTabPreviewMetrics: { recordTransitionImage() {} } },
  '../../services/web/BrowserTabPreviewTypes': {},
  '../../services/web/BrowserTabPreviewDebugExportService': {},
  './BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class {} },
  '../../services/web/BrowserRuntimeLifecyclePort': {}
});

function pixelMap() {
  return { release: () => Promise.resolve() };
}

const tab = {
  id: 'tab-1',
  url: 'https://example.com/article',
  title: 'Article',
  isHome: false,
  profileId: 'default',
  privacyMode: 'regular',
  dataScope: 'profile_persistent'
};
const previewCoordinator = new previewModule.BrowserTabPreviewCoordinator({}, {
  isHostedControllerAttached: () => true,
  isBackgroundHot: () => false,
  resolveWebViewportSnapshotSize: () => ({ width: 400, height: 800 })
});
previewCoordinator.profileBoundaryService.isSessionEphemeral = () => false;
previewCoordinator.captureCacheDirectoryStatsInBackground = () => {};

const coveredRequest = previewCoordinator.buildCaptureRequest({
  tab,
  controller: {},
  activeTabId: tab.id,
  showTabsSheet: true,
  showHomePage: false,
  suspendHostedWebSurface: false,
  hostedControllerAttached: true,
  activeControllerAttached: true,
  backgroundHot: false,
  shouldCaptureNativeErrorSurface: false,
  hasLiveController: true,
  force: true,
  requireSharedSnapshot: true
});
assert.equal(coveredRequest.keepExistingSnapshot, true);
assert.equal(coveredRequest.allowWhileLocked, false);
assert.equal(coveredRequest.preferVisibleSnapshot, false);

const visibleRequest = previewCoordinator.buildCaptureRequest({
  tab,
  controller: {},
  activeTabId: tab.id,
  showTabsSheet: false,
  showHomePage: false,
  suspendHostedWebSurface: false,
  hostedControllerAttached: true,
  activeControllerAttached: true,
  backgroundHot: false,
  shouldCaptureNativeErrorSurface: false,
  hasLiveController: true,
  force: true
});
assert.equal(visibleRequest.keepExistingSnapshot, false);
assert.equal(visibleRequest.preferVisibleSnapshot, true);
assert.equal(visibleRequest.componentSnapshotOnly, true, 'a visible tab copies the painted component');
assert.equal(visibleRequest.captureVisibleTabSurface, true);

const hiddenRequest = previewCoordinator.buildCaptureRequest({
  tab,
  controller: {},
  activeTabId: 'other-tab',
  showTabsSheet: false,
  showHomePage: false,
  suspendHostedWebSurface: false,
  hostedControllerAttached: true,
  activeControllerAttached: false,
  backgroundHot: true,
  shouldCaptureNativeErrorSurface: false,
  hasLiveController: true,
  force: true
});
assert.equal(hiddenRequest.hasRenderableSurface, false, 'an off-screen tab is not recaptured');
assert.equal(hiddenRequest.componentSnapshotOnly, false);

async function main() {
  let captureCalls = 0;
  previewCoordinator.captureService.captureWebPage = async () => {
    captureCalls += 1;
    return { snapshot: pixelMap(), source: 'web', sharedSnapshotImageUri: 'file://top' };
  };
  previewCoordinator.previewEntries[tab.id] = {
    tabId: tab.id,
    sharedSnapshotImageUri: 'file://scrolled',
    sharedSnapshotImageWidth: 400,
    sharedSnapshotImageHeight: 800,
    capturedAt: 50,
    transitionReady: true,
    transitionSource: {
      captureSource: 'visible-tab-surface',
      captureScope: 'full-surface',
      transitionFrame: 'captured-surface'
    },
    captureSource: 'visible-tab-surface',
    signature: '',
    lastKnownGoodSignature: ''
  };
  assert.equal(await previewCoordinator.capturePreview(coveredRequest), false);
  assert.equal(captureCalls, 0, 'a covered tab must not call webPageSnapshot');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).sharedSnapshotImageUri, 'file://scrolled');

  let releaseCapture;
  const captureStarted = new Promise((resolve) => {
    previewCoordinator.captureService.captureWebPage = () => new Promise((resolveCapture) => {
      releaseCapture = () => resolveCapture({
        snapshot: pixelMap(),
        source: 'web',
        sharedSnapshotImageUri: 'file://top',
        transitionSource: {
          captureSource: 'web',
          captureScope: 'web-content',
          transitionFrame: 'current-web'
        }
      });
      resolve();
    });
  });
  const inFlight = previewCoordinator.capturePreview({
    ...visibleRequest,
    keepExistingSnapshot: false
  });
  await captureStarted;
  assert.equal(await previewCoordinator.persistImmediateSharedSnapshot(tab, pixelMap(), {
    captureSource: 'visible-tab-surface',
    captureScope: 'full-surface',
    transitionFrame: 'captured-surface'
  }), true);
  releaseCapture();
  assert.equal(await inFlight, false, 'a snapshot that started before the overview image must be dropped');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).sharedSnapshotImageUri, 'file://scrolled');
  assert.equal(previewCoordinator.getSharedSnapshotState(tab.id).captureSource, 'visible-tab-surface');

  const overlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets'), 'utf8');
  const morphOverlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsSharedSnapshotOverlay.ets'), 'utf8');
  assert.match(overlay, /snapshotImageUri: this\.resolveCardSnapshotImageUri\(item\)/);
  assert.match(overlay, /hasImage \? 'image' : 'none'/);
  assert.match(overlay, /resolveCardSnapshotPixelMap\(_item: BrowserTabsFloatingItem\): image\.PixelMap \| undefined/);
  assert.doesNotMatch(overlay, /BrowserTabSnapshotPixelMapCache/);
  assert.match(morphOverlay, /if \(this\.resolveRenderableImageUri\(\)\.length > 0\) \{\s*this\.buildUriImage\(\)/);
  assert.match(morphOverlay, /resolveCachedMorphPixelMap\(\) !== undefined\) \{\s*this\.buildPixelMapImage\(\)/);
  assert.match(morphOverlay, /@Prop imagePixelMap: image\.PixelMap \| undefined = undefined;/);
  assert.match(morphOverlay, /height\(this\.imageClipHeight\(\)\)/);
  assert.match(morphOverlay, /imageFrame\.width/);
  assert.match(morphOverlay, /objectFit\(ImageFit\.Fill\)/);
  assert.doesNotMatch(morphOverlay, /objectFit\(ImageFit\.Cover\)/);
  assert.doesNotMatch(morphOverlay, /ENTRY_SNAPSHOT_PERSIST_WAIT/);
  const pipeline = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator.ets'), 'utf8');
  assert.match(pipeline, /void this\.persistEntrySnapshotForGallery\(/);
  assert.doesNotMatch(pipeline, /await this\.persistEntrySnapshotForGallery|ENTRY_SNAPSHOT_PERSIST_WAIT_MS|waitForTask/);
  const background = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/BrowserBackgroundTabPreviewRuntimeCoordinator.ets'), 'utf8');
  const schedule = background.slice(background.indexOf('scheduleCandidate('),
    background.indexOf('startIfNeeded('));
  const implementation = background.slice(background.indexOf('export class BrowserBackgroundTabPreviewRuntimeCoordinator'));
  assert.match(schedule, /enqueueCandidate/, 'background open must load the hidden page');
  assert.doesNotMatch(implementation, /capturePreview/, 'a hidden background page must not be snapshotted');
  const shell = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets'), 'utf8');
  assert.match(shell, /persistImmediateSharedSnapshot\(/, 'a visible leave must write a new card file before returning');
  assert.match(shell, /captureOutgoingTabVisibleSurfacePreview[\s\S]{0,180}replaceVisibleTabCardImage/,
    'opening a new tab must replace the visible card image');
  console.log('Tab preview lifecycle snapshot checks passed.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
