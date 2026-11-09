// Native toolbar geometry, drag lifetime and renderer cutover. No screen capture.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
function loadLayout(relative) {
  const file = path.resolve(root, relative);
  const moduleObject = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: file
  }).outputText, { module: moduleObject, exports: moduleObject.exports,
    require: name => loadLayout(path.resolve(path.dirname(file), name + '.ets')) });
  return moduleObject.exports;
}
const { buildVideoActionToolbarState: project, BrowserVideoActionToolbarPositionModel: Drag,
  resolveVideoActionToolbarBottomInset: bottomInset } = loadLayout('core/browser/media/BrowserVideoActionToolbarLayout.ets');
const { resolveWebToolbarClearanceVp: clearance } = loadLayout('core/browser/BrowserWebToolbarClearancePolicy.ets');
const bounds = { left: 20, top: 30, width: 390, height: 700 };
const session = { playbackTargetBinding: { transport: 'document_direct' }, geometry: {
  x: 100, y: 200, width: 600, height: 400, viewportWidth: 780, viewportHeight: 1400
} };
const state = project(session, 'g1:r1:video', true, false, bounds, 72);
assert.equal(state.visible, true);
assert.equal(state.x, 222, 'anchor must translate Web CSS pixels into host vp');
assert.equal(state.y, 350);
assert.equal(state.maxY, 602, 'buttons must stay above native bottom chrome');
const floating = clearance({ overlayActive: true, viewportReserved: false, bottomLiftVp: 28 });
const unreserved = bottomInset(bounds, 730, 24, floating);
assert.equal(unreserved, 121, 'floating capsule height and cockpit lift both occupy the Web layer');
const shortened = { ...bounds, height: bounds.height - 72 };
assert.equal(bottomInset(shortened, 730, 24, floating), 49,
  'subtract the overlap already reserved by the Web safe-area setting');
assert.equal(project(session, 'floating', true, false, bounds, unreserved).maxY,
  project(session, 'safe-area', true, false, shortened, bottomInset(shortened, 730, 24, floating)).maxY);
assert.equal(bottomInset({ ...bounds, height: 600 }, 730, 24,
  clearance({ overlayActive: false, viewportReserved: false, bottomLiftVp: 0 })), 0,
  'split and desktop Web bounds must not reserve native chrome a second time');
assert.equal(project(session, 'g1:r1:video', false, false, bounds).visible, false);
assert.equal(project(undefined, '', true, false, bounds).visible, false);
assert.equal(project(session, 'video', true, false, { ...bounds, width: 100 }).visible, false);
assert.equal(project(session, 'video', true, false, { ...bounds, width: NaN }).visible, false);
assert.equal(project(session, 'video', true, false, bounds, 690).visible, false);
const iframe = project({ ...session, playbackTargetBinding: { transport: 'frame_proxy' } },
  'frame', true, true, bounds);
assert.equal(iframe.x, iframe.maxX);
assert.notEqual(iframe.y, state.y, 'child-frame coordinates must not masquerade as root geometry');
assert.equal(iframe.busy, true);
const drag = new Drag();
drag.begin(state);
drag.move(state, 10000, -10000);
assert.equal(drag.resolve(state).x, state.maxX);
assert.equal(drag.resolve(state).y, state.minY);
drag.end();
const movedPage = { ...state, x: state.minX, y: state.maxY };
assert.equal(drag.resolve(movedPage).x, state.maxX, 'page scrolling must not reset a user drag');
const resized = project(session, state.identity, true, false, { ...bounds, width: 240 }, 72);
assert.equal(drag.resolve(resized).x, resized.maxX);
const nextTarget = { ...state, identity: 'g2:r1:video', x: 80, y: 90 };
assert.equal(drag.resolve(nextTarget).x, 80, 'a new document must reset the drag position');
assert.equal(drag.resolve(nextTarget).y, 90);
drag.move(nextTarget, 90, 90);
assert.equal(drag.resolve(nextTarget).x, 80, 'late pan updates must not move a new target');
const service = fs.readFileSync(path.join(root, 'services/video/WebVideoPresentationService.ets'), 'utf8');
const observation = fs.readFileSync(path.join(root,
  'core/browser/media/BrowserMediaRuntimeObservationApplicationCoordinator.ets'), 'utf8');
assert.doesNotMatch(service, /install_action_toolbar|function installActionToolbar|__aira_video_action_toolbar/,
  'native toolbar cutover must remove the DOM renderer');
assert.doesNotMatch(observation, /ensureWebActionToolbar|scheduleWebActionToolbar/);
const shell = fs.readFileSync(path.join(root, 'app/pages/BrowserShellPage.ets'), 'utf8');
assert.match(shell, /BrowserArkWebMediaTakeoverFloatingButtonHost\(\{/);
assert.match(shell, /handleNativeActionToolbarAction/);
assert.match(shell, /resolveVideoActionToolbarBottomInset\(this\.resolveEffectiveWebLayerRect\(\)/);
const component = fs.readFileSync(path.join(root,
  'app/components/browser/BrowserArkWebMediaTakeoverFloatingButton.ets'), 'utf8');
assert.match(component, /HdsImmersiveMaterialSurface\(\{/);
assert.match(component, /hostMaterialActive: isHdsMaterialAvailable\(\)/);
assert.match(component, /backgroundBlurEnabled: true/);
assert.match(component, /priorityGesture/);
// Static ArkUI hit-test contract, not a substitute for native gesture/device validation.
// Both modes below exclude descendants, leaving the host draggable but all three buttons inert.
const toolbarHost = component.slice(component.indexOf('export struct BrowserArkWebMediaTakeoverFloatingButtonHost'));
const hostHitTestModes = [...toolbarHost.matchAll(/\.hitTestBehavior\(HitTestMode\.(\w+)\)/g)].map(match => match[1]);
assert.ok(hostHitTestModes.every(mode => !['Block', 'BLOCK_DESCENDANTS'].includes(mode)),
  'the toolbar host must allow touch hit-testing to reach its child buttons');
function loadVideoModule(relative) {
  const filename = path.join(root, relative);
  const module = { exports: {} };
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText, { module, exports: module.exports, $r: key => key,
    require(name) {
      if (name === '@kit.ArkWeb') return { webview: {} };
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: key => key };
      if (name.endsWith('/WebVideoRuntimeProtocol')) return loadVideoModule('services/video/WebVideoRuntimeProtocol.ets');
      if (name.endsWith('/WebVideoFrameCommandTransport')) return {};
      throw Error(name);
    }
  });
  return module.exports;
}
const { WebVideoPresentationService } = loadVideoModule('services/video/WebVideoPresentationService.ets');
const runtimeProperty = loadVideoModule('services/video/WebVideoRuntimeProtocol.ets').WEB_VIDEO_RUNTIME_ID_PROPERTY;
const presentation = new WebVideoPresentationService();
const pageWindow = {};
const pageDocument = { defaultView: pageWindow,
  querySelectorAll: selector => selector === 'video' ? [video] : [] };
const video = { [runtimeProperty]: 'video', ownerDocument: pageDocument, controls: true,
  paused: false, ended: false, currentTime: 12, duration: 120,
  pause() { this.paused = true; }, play() { this.paused = false; return Promise.resolve(); } };
for (const action of ['pause', 'pause', 'play', 'play']) {
  const result = JSON.parse(vm.runInNewContext(presentation.buildExecuteLiveCommandScript(
    { runtimeId: 'video', elementId: '', source: '' }, { action }), { document: pageDocument, window: pageWindow }));
  assert.equal(result.ok, true, result.reason);
  assert.equal(video.paused, action === 'pause', 'cast pause/resume must be idempotent');
  assert.equal(video.controls, true, 'casting from a normal page must preserve the site controls');
}
console.log('Native video toolbar lifecycle passed (geometry, safe bounds, dragging, session changes, native-only renderer).');
