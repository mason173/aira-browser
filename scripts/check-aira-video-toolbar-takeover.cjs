// Exercise the production toolbar/launch coordinator with controlled Web and window results.
// ArkWeb rendering and native overlay stacking still require device validation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const protocol = load('services/video/WebVideoRuntimeProtocol.ets').WEB_VIDEO_ACTION_TOOLBAR_PROTOCOL;
function load(relative) {
  const filename = path.join(root, relative);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date, Map, setTimeout,
    AppStorage: { get: () => 'light' }, $r: key => key,
    require(specifier) {
      if (specifier === '@kit.ArkWeb') return { webview: { MediaType: { VIDEO: 1 }, SourceType: { URL: 1 } } };
      if (specifier.endsWith('/WebVideoPresentationService')) return { WebVideoPresentationService: class {} };
      if (specifier.endsWith('/VideoAssistantModels')) return load('features/videoAssistant/VideoAssistantModels.ets');
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (specifier.endsWith('/MediaCastRequestContextPolicy')) return { MediaCastRequestContextPolicy: class { assess() { return { requestHeaderCount: 0, requiresWebRequestContext: false, reason: 'none' }; } } };
      if (specifier.endsWith('/VideoCompatibilityProfileCatalog')) {
        return { sharedVideoCompatibilityProfileCatalog: { getCurrentResolution: () => undefined } };
      }
      if (specifier.endsWith('/WebVideoRuntimeProtocol')) return load('services/video/WebVideoRuntimeProtocol.ets');
      if (specifier.endsWith('/BrowserVideoActionToolbarLayout')) return load('core/browser/media/BrowserVideoActionToolbarLayout.ets');
      if (specifier.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      if (specifier.endsWith('/BrowserThemeStorageKeys')) return { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY: 'theme' };
      if (specifier.endsWith('/VideoAssistantCastSessionService')) return { VideoAssistantCastSessionService: class {} };
      throw new Error(`Unexpected runtime dependency: ${specifier}`);
    }
  }, { filename });
  return module.exports;
}
const { BrowserArkWebMediaTakeoverCoordinator } = load('core/browser/media/BrowserArkWebMediaTakeoverCoordinator.ets');
function fixture({ fullscreen = true, presentationOk = true, windowOk = true, probeOk = true, transport = 'document_direct',
  invalidateAt = '', throwWindow = false, switchTabAtProbe = false, navigateAtProbe = false } = {}) {
  const calls = [];
  let current = true;
  let active = true;
  let activeTabId = 'tab';
  let routeEpoch = 'r1';
  let castHandler;
  let castItem;
  const session = {
    sessionId: 'session', playbackTargetId: 'target', targetKey: 'dom:video', playbackState: 'playing',
    webLiveReachability: 'reachable', webLiveReachabilityExpiresAt: Date.now() + 20000,
    currentTimeSeconds: 12, durationSeconds: 120,
    playbackTargetBinding: { transport, runtimeId: 'video', frameRuntimeId: transport === 'frame_proxy' ? 'frame' : '',
      elementId: 'video-main' },
    geometry: { visible: true, videoWidth: 1280, videoHeight: 720 }
  };
  const snapshot = {
    outcome: 'active', activeSessionId: session.sessionId,
    getSessions: () => [session], getScope: () => ({ tabId: activeTabId, generationId: 'g1', routeEpochId: routeEpoch })
  };
  const commandResult = (ok, reason) => ({
    ok, reason, userVisibleMessage: ok ? '' : 'takeover failed',
    currentTime: 12, duration: 120, paused: session.playbackState !== 'playing', ended: false, seeking: false,
    readyState: 4, networkState: 1, errorCode: 0, playbackRate: 1, fullscreenActive: fullscreen
  });
  const coordinator = new BrowserArkWebMediaTakeoverCoordinator({
    resolveController: () => ({}), isActiveWebTab: id => active && id === activeTabId
  }, {
    probeLiveTarget: async () => {
      if (invalidateAt === 'probe') current = false;
      if (switchTabAtProbe) active = false;
      if (navigateAtProbe) {
        current = false;
        coordinator.beginNavigation('tab');
      }
      return commandResult(probeOk, 'probe_result');
    },
    executeLiveCommand: async (_controller, _target, command) => {
      calls.push(command.action);
      if (command.action === 'toggle') session.playbackState = session.playbackState === 'playing' ? 'paused' : 'playing';
      if (command.action === 'pause') session.playbackState = 'paused';
      if (command.action === 'play') session.playbackState = 'playing';
      if (command.action === 'enter_live_presentation' && invalidateAt === 'presentation') current = false;
      return commandResult(command.action !== 'enter_live_presentation' || presentationOk, command.action);
    }
  }, {
    requestCast: async (item, handler) => {
      calls.push('native_cast'); castHandler = handler; castItem = item;
      return { opened: true, message: '' };
    },
    release: async () => calls.push('release_cast')
  });
  const observe = tabId => coordinator.observe({ tabId, pageUrl: 'https://example.com', pageTitle: 'Video', suppressDiagnostics: true,
    mediaInfo: { mediaType: 1, mediaSrcList: [{ type: 1, source: 'https://example.com/video.mp4', format: 'mp4' }],
      headers: [], posterUrl: '', muted: false } });
  observe('tab');
  coordinator.bindRuntimeEvidencePublisher({
    capture: () => ({ isCurrent: () => current, commit: () => true }),
    resolveSnapshot: () => snapshot,
    resolveCastMedia: () => ({ reason: 'ready', mediaUri: 'https://example.com/video.mp4', mediaFormat: 'mp4', requestHeaderCount: 0 })
  });
  const enterWindow = async route => {
    calls.push(route);
    if (invalidateAt === 'window') current = false;
    if (throwWindow) throw new Error('window refused');
    return windowOk;
  };
  const host = {
    showToast: () => {}, invalidatePresentation: () => {},
    prepareWebVideoFullscreen: async () => calls.push('prepare'),
    cancelWebVideoFullscreenPreparation: () => calls.push('cancel_prepare'),
    enterWebVideoFullscreen: () => enterWindow('web_fullscreen'),
    enterWebLiveFullscreen: () => enterWindow('assistant_fullscreen'),
    exitWebLiveFullscreen: () => calls.push('exit_fullscreen'),
    onStarted: () => calls.push('started')
  };
  const launch = () => coordinator.launchFromWebActionToolbar('tab', JSON.stringify({
    protocol, action: 'fullscreen', runtimeId: 'video', frameRuntimeId: session.playbackTargetBinding.frameRuntimeId
  }), true, host);
  const state = () => coordinator.buildNativeActionToolbarState(activeTabId, true,
    { left: 0, top: 0, width: 390, height: 700 }, 72);
  const nativeAction = (action, identity = state().identity, enabled = true) =>
    coordinator.handleNativeActionToolbarAction(activeTabId, identity, action, enabled, host, host);
  return { coordinator, calls, launch, state, nativeAction, session, snapshot, host,
    activateTab: id => { activeTabId = id; observe(id); },
    advanceRoute: () => { routeEpoch = 'r2'; },
    getCast: () => ({ item: castItem, handler: castHandler }) };

}
async function main() {
  for (const transport of ['document_direct', 'frame_proxy']) {
    for (const fullscreen of [true, false]) {
      const f = fixture({ transport, fullscreen });
      assert.equal(await f.launch(), true);
      assert.ok(f.calls.includes('enter_live_presentation'),
        'Web fullscreen alone must not report takeover success or skip the Aira presentation');
      const windowRoute = fullscreen ? 'web_fullscreen' : 'assistant_fullscreen';
      assert.ok(f.calls.indexOf('enter_live_presentation') < f.calls.indexOf(windowRoute));
      assert.ok(f.calls.indexOf(windowRoute) < f.calls.indexOf('started'));
      assert.equal(f.coordinator.getAssistantPlayerState().active, true);
    }
  }
  for (const options of [{ presentationOk: false }, { windowOk: false }, { throwWindow: true },
    { invalidateAt: 'presentation' }, { invalidateAt: 'window' }, { probeOk: false },
    { invalidateAt: 'probe' }]) {
    const f = fixture(options);
    assert.equal(await f.launch(), false, JSON.stringify(options));
    assert.equal(f.calls.includes('started'), false);
    assert.ok(f.calls.includes('restore_presentation'), 'failed toolbar launch must restore the toolbar');
    assert.ok(f.calls.includes('exit_fullscreen'), 'failed takeover must unwind the existing Web fullscreen');
    assert.ok(f.calls.includes('cancel_prepare'));
    assert.equal(f.coordinator.getAssistantPlayerState().active, false);
  }
  const retry = fixture({ presentationOk: false });
  assert.equal(await retry.launch(), false);
  assert.equal(await retry.launch(), false);
  assert.equal(retry.calls.filter(call => call === 'enter_live_presentation').length, 2,
    'another toolbar click must retry presentation rather than accepting the site fullscreen');
  assert.equal(retry.calls.includes('started'), false);
  for (const options of [{ switchTabAtProbe: true }, { navigateAtProbe: true }]) {
    const f = fixture(options);
    assert.equal(await f.launch(), false);
    assert.equal(f.calls.includes('exit_fullscreen'), false, 'old failure must not exit another tab/document fullscreen');
    if (options.navigateAtProbe) {
      assert.equal(f.calls.includes('restore_presentation'), false, 'navigation revoked the old presentation lease');
    }
  }
  for (const transport of ['document_direct', 'frame_proxy']) {
    const f = fixture({ transport });
    assert.equal(f.state().visible, true);
    const launch = f.nativeAction('fullscreen');
    assert.equal(f.state().busy, true);
    assert.equal(await f.nativeAction('fullscreen'), false, 'double tap must not start another takeover');
    assert.equal(await launch, true);
    assert.ok(f.calls.includes('enter_live_presentation'));
    assert.ok(f.calls.includes('assistant_fullscreen'));
    assert.equal(f.calls.includes('web_fullscreen'), false, 'native button must bypass site fullscreen');
    assert.equal(f.calls.includes('prepare'), false);
    assert.equal(f.state().visible, false, 'floating entry hides while Aira controls are active');
    const pip = fixture({ transport });
    assert.equal(await pip.nativeAction('picture_in_picture'), true);
    assert.deepEqual(pip.calls, ['picture_in_picture'], 'PiP must not first enter Aira/site fullscreen');
    const cast = fixture({ transport });
    assert.equal(await cast.nativeAction('cast'), true);
    assert.deepEqual(cast.calls, ['native_cast']);
    assert.equal(cast.getCast().item.mediaUri, 'https://example.com/video.mp4');
    assert.equal(await cast.getCast().handler.pause(), true);
    assert.equal(cast.session.playbackState, 'paused');
    assert.equal(await cast.getCast().handler.resume(), true);
    assert.equal(cast.session.playbackState, 'playing');
    cast.coordinator.beginNavigation('tab');
    assert.ok(cast.calls.includes('release_cast'), 'page casting must release its borrowed session on navigation');
  }
  const transferredCast = fixture();
  assert.equal(await transferredCast.nativeAction('cast'), true);
  const oldCastHandler = transferredCast.getCast().handler;
  transferredCast.activateTab('tab-b');
  assert.equal(await transferredCast.nativeAction('fullscreen'), true);
  transferredCast.coordinator.handleAssistantPlayerAction({ type: 'cast' }, transferredCast.host);
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(transferredCast.calls.filter(call => call === 'native_cast').length, 2);
  transferredCast.coordinator.beginNavigation('tab');
  transferredCast.coordinator.clearTab('tab');
  assert.equal(transferredCast.calls.includes('release_cast'), false,
    'cleanup of the previous page cast must not release the current fullscreen cast');
  transferredCast.activateTab('tab');
  assert.equal(oldCastHandler.isCurrent(), false, 'transferring cast ownership must revoke old callbacks');
  assert.equal(await oldCastHandler.pause(), false, 'old cast callbacks must not control the old video');
  transferredCast.activateTab('tab-b');
  transferredCast.coordinator.beginNavigation('tab-b');
  assert.equal(transferredCast.calls.filter(call => call === 'release_cast').length, 1,
    'current owner cleanup releases exactly once even when fullscreen also closes');
  const expired = fixture();
  expired.session.webLiveReachabilityExpiresAt = 0;
  assert.equal(expired.state().visible, false);
  assert.equal(await expired.nativeAction('fullscreen'), false);
  assert.equal(expired.calls.length, 0);
  const ambiguous = fixture();
  ambiguous.snapshot.outcome = 'ambiguous';
  assert.equal(ambiguous.state().visible, false);
  assert.equal(await ambiguous.nativeAction('cast'), false);
  const routed = fixture();
  const oldIdentity = routed.state().identity;
  routed.advanceRoute();
  assert.equal(await routed.nativeAction('fullscreen', oldIdentity), false, 'old visible button cannot act on a new route');
  assert.equal(await routed.nativeAction('fullscreen', routed.state().identity, false), false);
  assert.equal(routed.calls.length, 0);
  const failure = fixture({ presentationOk: false });
  assert.equal(await failure.nativeAction('fullscreen'), false);
  assert.equal(failure.state().busy, false);
  assert.ok(failure.calls.includes('restore_presentation'));
  assert.equal(failure.calls.includes('web_fullscreen'), false);
  console.log('Video toolbar takeover passed (legacy rollback, native full/PiP/cast, duplicate taps, expiry, navigation).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
