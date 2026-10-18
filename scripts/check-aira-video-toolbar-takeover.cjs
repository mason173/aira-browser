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
      if (specifier === '@kit.ArkWeb') return { webview: {} };
      if (specifier.endsWith('/WebVideoPresentationService')) return { WebVideoPresentationService: class {} };
      if (specifier.endsWith('/VideoAssistantModels')) return load('features/videoAssistant/VideoAssistantModels.ets');
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (specifier.endsWith('/MediaCastRequestContextPolicy')) return { MediaCastRequestContextPolicy: class {} };
      if (specifier.endsWith('/VideoCompatibilityProfileCatalog')) {
        return { sharedVideoCompatibilityProfileCatalog: { getCurrentResolution: () => undefined } };
      }
      if (specifier.endsWith('/WebVideoRuntimeProtocol')) return load('services/video/WebVideoRuntimeProtocol.ets');
      if (specifier.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      if (specifier.endsWith('/BrowserThemeStorageKeys')) return { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY: 'theme' };
      if (specifier.endsWith('/VideoAssistantCastSessionService')) return { VideoAssistantCastSessionService: class {} };
      throw new Error(`Unexpected runtime dependency: ${specifier}`);
    }
  }, { filename });
  return module.exports;
}
const { BrowserArkWebMediaTakeoverCoordinator } = load('core/browser/media/BrowserArkWebMediaTakeoverCoordinator.ets');
function fixture({ fullscreen = true, presentationOk = true, windowOk = true, transport = 'document_direct',
  invalidateAt = '', throwWindow = false } = {}) {
  const calls = [];
  let current = true;
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
    getSessions: () => [session], getScope: () => ({ tabId: 'tab', generationId: 'g1', routeEpochId: 'r1' })
  };
  const commandResult = (ok, reason) => ({
    ok, reason, userVisibleMessage: ok ? '' : 'takeover failed',
    currentTime: 12, duration: 120, paused: false, ended: false, seeking: false,
    readyState: 4, networkState: 1, errorCode: 0, playbackRate: 1, fullscreenActive: fullscreen
  });
  const coordinator = new BrowserArkWebMediaTakeoverCoordinator({
    resolveController: () => ({}), isActiveWebTab: id => current && id === 'tab'
  }, {
    probeLiveTarget: async () => commandResult(true, 'probe_ok'),
    executeLiveCommand: async (_controller, _target, command) => {
      calls.push(command.action);
      if (command.action === 'enter_live_presentation' && invalidateAt === 'presentation') current = false;
      return commandResult(command.action !== 'enter_live_presentation' || presentationOk, command.action);
    }
  });
  coordinator.bindRuntimeEvidencePublisher({
    capture: () => ({ isCurrent: () => current, commit: () => true }),
    resolveSnapshot: () => snapshot
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
  return { coordinator, calls, launch };
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
    { invalidateAt: 'presentation' }, { invalidateAt: 'window' }]) {
    const f = fixture(options);
    assert.equal(await f.launch(), false, JSON.stringify(options));
    assert.equal(f.calls.includes('started'), false);
    assert.ok(f.calls.includes('restore_presentation'));
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
  console.log('Video toolbar takeover contract passed (10 cases).');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
