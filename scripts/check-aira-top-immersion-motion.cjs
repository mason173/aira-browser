const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');

const root = path.resolve(__dirname, '..');
const sourceRoot = path.join(root, 'AiraBrowser/entry/src/main/ets');
const cache = new Map();
let clockNow = 10000;
class Clock extends Date { static now() { return clockNow; } }
function load(relativePath) {
  const filename = path.join(sourceRoot, relativePath);
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date: Clock,
    setTimeout: () => 1, clearTimeout() {},
    require(specifier) {
      if (specifier === '@kit.PerformanceAnalysisKit') return { hilog: { warn() {} } };
      if (specifier === '@kit.ArkWeb') return { webview: {} };
      if (specifier === './BrowserContinuationCoordinator') {
        return { sharedBrowserContinuationCoordinator: { updateActiveTabScroll() {} } };
      }
      if (specifier === '../../common/debug/AiraScrollOscProbe') {
        return { AiraScrollOscProbe: { markSignal() {}, markSource() {} } };
      }
      assert.ok(specifier.startsWith('.'), `Unexpected dependency: ${specifier}`);
      return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), `${specifier}.ets`)));
    }
  }, { filename });
  cache.set(filename, module.exports);
  return module.exports;
}

const { BrowserWebTopImmersionSessionCoordinator } =
  load('core/browser/BrowserWebTopImmersionSessionCoordinator.ets');
const { BrowserTopImmersionScrollCoordinator } = load('core/browser/BrowserTopImmersionScrollCoordinator.ets');
const { BrowserBottomChromeScrollCoordinator } = load('core/browser/BrowserBottomChromeScrollCoordinator.ets');
const { BrowserWebScrollInteractionCoordinator } = load('core/browser/BrowserWebScrollInteractionCoordinator.ets');
const { BrowserWebViewportCoordinator } = load('core/browser/BrowserWebViewportCoordinator.ets');

function fixture() {
  const facts = {
    activeTabId: 'tab-1', browserShellVisible: true, webPageVisible: true,
    homePageVisible: false, tabsSheetVisible: false, scrollTopImmersionEnabled: true,
    alwaysTopImmersionEnabled: false, fullScreenModeEnabled: false,
    webAppTopSafeAreaHidden: false, assistantVideoTakeoverActive: false,
    scrollOffsetY: 0, addressFocused: false, bottomPanelInteractive: false, statusBarVisible: true
  };
  const updates = [];
  const coordinator = new BrowserWebTopImmersionSessionCoordinator({
    resolveFacts: () => facts,
    host: {
      resolveVisibleTopInsetPx: () => 40,
      applyPresentation(visible, inset, source, durationMs = 0) {
        updates.push({ visible, inset, source, durationMs });
        facts.statusBarVisible = visible;
      },
      applyWindowVisibility: async () => true,
      scheduleSafeInsetSettle() {}
    }
  }, new BrowserTopImmersionScrollCoordinator({
    hideDeltaPx: 24, revealDeltaPx: 32, visibilitySwitchCooldownMs: 0
  }));
  const scroll = y => {
    facts.scrollOffsetY = y;
    coordinator.handleScroll(facts.activeTabId, y);
  };
  const hide = () => { scroll(0); scroll(40); };
  return { facts, updates, coordinator, scroll, hide };
}

const normal = fixture();
normal.hide();
normal.scroll(0);
assert.deepEqual(normal.updates.map(update => update.inset), [0, 40]);
for (const update of normal.updates) {
  assert.ok(update.durationMs > 0 && update.durationMs <= 240,
    `Scroll ${update.visible ? 'reveal' : 'hide'} must animate instead of snapping; duration=${update.durationMs}`);
}

// Exercise the actual order: bottom chrome restores first, then top immersion
// resolves fresh shell facts from that same user scroll event. The panel detent
// stays `low` while scrolling, so the engaged fact stays false and the reveal must
// come from the restore event itself, not from a resting panel.
for (const behavior of ['compact', 'hidden']) {
  const item = fixture();
  let bottomPresentation = 'resting';
  item.facts.bottomPanelInteractive = false;
  const interaction = new BrowserWebScrollInteractionCoordinator({
    bottomChromeScrollCoordinator: new BrowserBottomChromeScrollCoordinator({
      applyPresentationDeltaPx: 28, restorePresentationDeltaPx: 24, transitionCooldownMs: 0
    }),
    topImmersionSessionCoordinator: item.coordinator,
    recentActionManager: { recordClick() {} },
    scrollPerformanceCoordinator: {
      createState: () => ({}), activateForMove: state => state
    },
    smoothModeService: {}, runtimeLifecyclePort: {}
  }, {
    resolveFacts: () => ({
      activeTabId: item.facts.activeTabId, webPageVisible: true, addressFocused: false,
      currentDetent: 'low', currentPresentation: bottomPresentation, tabsSheetVisible: false,
      webAppImmersiveMode: false, fullScreenModeEnabled: false,
      smoothModeRuntimeEnabled: false, experimentSettings: {}
    }),
    applyBottomChromeDecision(decision) {
      bottomPresentation = decision.presentation;
    }
  });
  interaction.applyBottomToolbarScrollBehavior(behavior, item.facts.activeTabId);
  interaction.handleTouch(item.facts.activeTabId, 'down');
  interaction.handleTouch(item.facts.activeTabId, 'move');
  for (const y of [0, 40, 16]) {
    item.facts.scrollOffsetY = y;
    interaction.handleScroll(item.facts.activeTabId, y);
  }
  assert.equal(bottomPresentation, 'resting');
  assert.deepEqual(item.updates.map(update => update.inset), [0, 40]);
  assert.ok(item.updates.at(-1).durationMs > 0,
    `Top inset must animate when ${behavior} bottom chrome restores during the same scroll event`);
}

// "Always show" keeps the bottom toolbar at `resting` for the whole scroll, so the
// resting state must not be read as an engaged panel. Top immersion has to work on
// its own or the status bar stays pinned and the top never immerses.
{
  const item = fixture();
  const interaction = new BrowserWebScrollInteractionCoordinator({
    bottomChromeScrollCoordinator: new BrowserBottomChromeScrollCoordinator({
      applyPresentationDeltaPx: 28, restorePresentationDeltaPx: 24, transitionCooldownMs: 0
    }),
    topImmersionSessionCoordinator: item.coordinator,
    recentActionManager: { recordClick() {} },
    scrollPerformanceCoordinator: {
      createState: () => ({}), activateForMove: state => state
    },
    smoothModeService: {}, runtimeLifecyclePort: {}
  }, {
    resolveFacts: () => ({
      activeTabId: item.facts.activeTabId, webPageVisible: true, addressFocused: false,
      currentDetent: 'low', currentPresentation: 'resting', tabsSheetVisible: false,
      webAppImmersiveMode: false, fullScreenModeEnabled: false,
      smoothModeRuntimeEnabled: false, experimentSettings: {}
    }),
    applyBottomChromeDecision() {}
  });
  interaction.applyBottomToolbarScrollBehavior('fixed', item.facts.activeTabId);
  interaction.handleTouch(item.facts.activeTabId, 'down');
  interaction.handleTouch(item.facts.activeTabId, 'move');
  for (const y of [0, 40, 90, 200]) {
    clockNow += 400;
    item.facts.scrollOffsetY = y;
    interaction.handleScroll(item.facts.activeTabId, y);
  }
  assert.deepEqual(item.updates.map(update => update.visible), [false],
    'always-show toolbar must still allow the top to immerse on a downward scroll');
  assert.equal(item.updates.at(-1).durationMs, 180, 'the immersion must animate');
  clockNow += 400;
  item.facts.scrollOffsetY = 40;
  interaction.handleScroll(item.facts.activeTabId, 40);
  assert.deepEqual(item.updates.map(update => update.visible), [false, true],
    'an upward scroll must reveal the top again');
}

for (const source of ['history-navigation', 'tabs-overview-entry', 'navigation-start']) {
  const item = fixture();
  item.hide();
  item.coordinator.requestVisible(source);
  assert.equal(item.updates.at(-1).durationMs, 0, `${source} must settle immediately`);
}
for (const field of ['addressFocused', 'bottomPanelInteractive', 'tabsSheetVisible']) {
  const item = fixture();
  item.hide();
  item.facts[field] = true;
  item.scroll(0);
  assert.equal(item.updates.at(-1).durationMs, 0, `${field} is not a scroll reveal`);
}

// The engaged-panel rule is shared: an expanded panel keeps the status bar visible,
// while the resting toolbar of a normal scroll does not count as engagement.
{
  const { isBottomPanelEngagedForTopImmersion } = load('core/browser/BrowserTopImmersionScrollCoordinator.ets');
  assert.equal(isBottomPanelEngagedForTopImmersion('middle'), true, 'an expanded panel is engaged');
  assert.equal(isBottomPanelEngagedForTopImmersion('low'), false, 'a resting toolbar is not engaged');
  assert.equal(isBottomPanelEngagedForTopImmersion('peek'), false, 'a collapsed toolbar is not engaged');
}
const disabled = fixture();
disabled.hide();
disabled.facts.scrollTopImmersionEnabled = false;
disabled.coordinator.syncPolicy('settings');
assert.equal(disabled.updates.at(-1).durationMs, 0);

const forced = fixture();
forced.facts.fullScreenModeEnabled = true;
forced.coordinator.requestFullscreenHidden();
assert.equal(forced.updates.at(-1).durationMs, 0, 'Fullscreen must settle immediately');

const refresh = fixture();
refresh.coordinator.refreshVisibleInset('quick-search');
assert.equal(refresh.updates.at(-1).durationMs, 0, 'Chrome content changes must settle immediately');

const blur = fixture();
const geometry = { systemTopInsetVp: 48, cutoutTopInsetVp: 32 };
const resolveBlur = () => blur.coordinator.resolveScrollHiddenTopBlurHeightVp(geometry, 16);
assert.equal(resolveBlur(), 0, 'Visible top chrome must not blur Web content');
blur.hide();
assert.equal(resolveBlur(), 72, 'Blur height must be 1.5 times the visible cutout + gap, without quick-search height');
for (const field of ['fullScreenModeEnabled', 'webAppTopSafeAreaHidden',
  'assistantVideoTakeoverActive', 'homePageVisible', 'tabsSheetVisible']) {
  blur.facts[field] = true;
  assert.equal(resolveBlur(), 0, `${field} must not enable scroll blur`);
  blur.facts[field] = false;
}
blur.facts.scrollTopImmersionEnabled = false;
blur.facts.alwaysTopImmersionEnabled = true;
blur.facts.statusBarVisible = true;
assert.equal(resolveBlur(), 0, 'Always-on immersion must not blur before the top has collapsed');
blur.facts.statusBarVisible = false;
assert.equal(resolveBlur(), 72, 'Always-on immersion blurs once the top has collapsed');
blur.facts.alwaysTopImmersionEnabled = false;
blur.facts.scrollTopImmersionEnabled = true;
blur.facts.scrollTopImmersionEnabled = false;
assert.equal(resolveBlur(), 0);
blur.facts.scrollTopImmersionEnabled = true;
const viewportInput = {
  hostHeightPx: 800, visualTopInsetPx: 0, fullViewport: false,
  largeScreenShellActive: false, nativeVideoTakeoverActive: false,
  scrollHiddenTopBlurHeightPx: resolveBlur()
};
const blurred = BrowserWebViewportCoordinator.resolvePresentation(viewportInput);
assert.equal(blurred.contentTopPx, 0, 'Blur must not restore occupied top space');
assert.equal(blurred.contentHeightPx, 800, 'Blur must not resize the Web viewport');
const stops = BrowserWebViewportCoordinator.resolveTopBlurFractionStops(blurred);
assert.equal(stops[0][0], 1);
assert.equal(stops[0][1], 0, 'Full blur begins on the safe-strip edge, with no gap');
assert.equal(stops[2][0], 0);
assert.equal(stops[2][1] * blurred.contentHeightPx, 72, 'Blur must end at 1.5 times the safe-area height');
for (let i = 1; i < stops.length; i++) assert.ok(stops[i][1] > stops[i - 1][1]);
const clear = BrowserWebViewportCoordinator.resolvePresentation({ ...viewportInput, scrollHiddenTopBlurHeightPx: 0 });
assert.equal(BrowserWebViewportCoordinator.resolvePresentationUpdate({ current: blurred, next: clear }), clear,
  'Blur-only changes must be published even when viewport geometry stays unchanged');
for (const field of ['fullViewport', 'largeScreenShellActive', 'nativeVideoTakeoverActive']) {
  assert.equal(BrowserWebViewportCoordinator.resolvePresentation({ ...viewportInput, [field]: true })
    .scrollHiddenTopBlurHeightPx, 0);
}
assert.equal(BrowserWebViewportCoordinator.resolvePresentation({ ...viewportInput, visualTopInsetPx: 48 })
  .scrollHiddenTopBlurHeightPx, 0);

const renderer = fs.readFileSync(path.join(sourceRoot,
  'app/components/browser/BrowserWebViewportSurfaceHost.ets'), 'utf8');
assert.doesNotMatch(renderer, /if\s*\(this\.presentation\.topSafeOverlayHeightPx\s*>\s*0\)/,
  'Top chrome must remain mounted while its height animates to/from zero');
assert.doesNotMatch(renderer, /\.animation\(/,
  'Do not apply unconditional animations to history-navigation geometry');
console.log('Top immersion motion passed: scroll motion and safe-area blur; navigation and forced changes stay immediate.');

// Execute the actual shell callback: bottom avoidance must retain the same scroll
// animation as normal pages. Native chrome and Web bounds share one transaction.
const shellSource = fs.readFileSync(path.join(sourceRoot, 'app/pages/BrowserShellPage.ets'), 'utf8');
const hostStart = shellSource.indexOf('private browserWebTopImmersionSessionHost:');
const callbackStart = shellSource.indexOf('applyPresentation:', hostStart) + 'applyPresentation:'.length;
const callbackEnd = shellSource.indexOf(',\n    applyWindowVisibility:', callbackStart);
assert.ok(hostStart >= 0 && callbackEnd > callbackStart);
const callbackModule = { exports: {} };
vm.runInNewContext(ts.transpileModule(
  `exports.apply = function${shellSource.slice(callbackStart, callbackEnd).trim().replace('=> {', '{')};`,
  { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }
).outputText, { exports: callbackModule.exports, Curve: { EaseOut: 'ease-out' }, BrowserWebViewportCoordinator });
for (const bottomInset of [0, 101]) {
  const geometryInput = { hostHeightPx: 844, visualTopInsetPx: 40, visualBottomInsetPx: bottomInset,
    fullViewport: false, largeScreenShellActive: false, nativeVideoTakeoverActive: false };
  let animationDuration = 0;
  const writes = [];
  const shell = {
    webViewportVisualTopInsetInitialized: true, webViewportVisualTopInset: 40, webStatusBarVisible: true,
    webViewportPresentation: BrowserWebViewportCoordinator.resolvePresentation(geometryInput),
    getUIContext: () => ({ animateTo(options, apply) {
      animationDuration = options.duration; apply(); animationDuration = 0;
    } }),
    refreshWebViewportPresentation(topInset) {
      const previous = this.webViewportPresentation;
      this.webViewportPresentation = BrowserWebViewportCoordinator.resolvePresentation({ ...geometryInput,
        visualTopInsetPx: topInset });
      writes.push({ previous, next: this.webViewportPresentation, animationDuration });
    }
  };
  callbackModule.exports.apply.call(shell, false, 0, 'web-scroll', 180);
  callbackModule.exports.apply.call(shell, true, 40, 'web-scroll', 180);
  for (const write of writes) {
    assert.equal(write.next.contentTopPx + write.next.contentHeightPx, 844 - bottomInset,
      'The final native bottom edge stays fixed');
    assert.equal(write.animationDuration, 180,
      'Bottom avoidance must preserve the existing top immersion animation');
  }
}
console.log('Combined safe areas: bottom avoidance preserves the top immersion animation.');

// Bottom avoidance creates a shorter native screen. Its top-immersion geometry
// must be identical to an ordinary viewport with that physical available height.
for (const topInset of [0, 13, 40, 88]) {
  const input = { hostHeightPx: 844, visualTopInsetPx: topInset, fullViewport: false,
    largeScreenShellActive: false, nativeVideoTakeoverActive: false };
  const reserved = BrowserWebViewportCoordinator.resolvePresentation({ ...input, visualBottomInsetPx: 101 });
  const shorter = BrowserWebViewportCoordinator.resolvePresentation({ ...input, hostHeightPx: 743 });
  assert.equal(reserved.hostHeightPx, shorter.hostHeightPx, 'shorten the native host, not only its Web child');
  for (const field of ['contentTopPx', 'contentHeightPx', 'topSafeOverlayHeightPx', 'scrollHiddenTopBlurHeightPx']) {
    assert.equal(reserved[field], shorter[field], `shorter native screen must preserve normal ${field}`);
  }
  assert.equal(reserved.reservedBottomInsetPx, 101);
  assert.equal(reserved.contentTopPx + reserved.contentHeightPx, reserved.hostHeightPx);
}
assert.doesNotMatch(renderer, /\.renderFit\(/, 'do not create another special animation path for bottom avoidance');
assert.match(renderer, /\.clip\(this\.presentation\.reservedBottomInsetPx > 0\)/,
  'the shortened native viewport must also clip content to its bottom boundary');
const phoneSurface = fs.readFileSync(path.join(sourceRoot, 'app/components/browser/BrowserPhonePrimarySurface.ets'), 'utf8');
assert.match(phoneSurface, /if \(this\.webLayerMounted\) \{\s*Stack\(\{ alignContent: Alignment\.Top \}\)/,
  'the shorter Web host must stay top-aligned, not centered inside the full-height phone slot');
console.log('Combined safe areas: bottom reservation is equivalent to a shorter native viewport.');

// Replay a root scroll-range correction after the Web viewport grows at the page end.
// Cover ordinary pages and pages whose bottom toolbar is pinned by native avoidance.
// Replay layout feedback during a held gesture and during its inertial continuation.
for (const bottomInset of [0, 101]) {
  for (const mode of ['single', 'split', 'inertia', 'mid-page', 'new-touch', 'expired', 'larger-reversal', 'continued-down']) {
    const facts = { ...fixture().facts, bottomPanelInteractive: true, bottomToolbarPinnedBySafeArea: bottomInset > 0 };
    const pageHeight = 1200;
    const geometryInput = { hostHeightPx: 844, visualTopInsetPx: 40, visualBottomInsetPx: bottomInset,
      fullViewport: false, largeScreenShellActive: false, nativeVideoTakeoverActive: false };
    const transitions = [];
    const durations = [];
    let bottomPresentation = 'resting';
    let interaction;
    const shell = {
      webViewportVisualTopInsetInitialized: true, webViewportVisualTopInset: 40, webStatusBarVisible: true,
      webViewportPresentation: BrowserWebViewportCoordinator.resolvePresentation(geometryInput),
      getUIContext: () => ({ animateTo(_options, apply) { apply(); } }),
      refreshWebViewportPresentation(topInset) {
        const previous = this.webViewportPresentation;
        this.webViewportPresentation = BrowserWebViewportCoordinator.resolvePresentation({ ...geometryInput,
          visualTopInsetPx: topInset });
        interaction.handleViewportChanged(facts.activeTabId, previous, this.webViewportPresentation);
      }
    };
    const top = new BrowserWebTopImmersionSessionCoordinator({ resolveFacts: () => facts,
      host: { resolveVisibleTopInsetPx: () => 40,
        applyPresentation(visible, inset, source, duration) {
          callbackModule.exports.apply.call(shell, visible, inset, source, duration);
          facts.statusBarVisible = visible;
          transitions.push(visible);
          durations.push(duration);
        }, applyWindowVisibility: async () => true, scheduleSafeInsetSettle() {} }
    });
    interaction = new BrowserWebScrollInteractionCoordinator({
      bottomChromeScrollCoordinator: new BrowserBottomChromeScrollCoordinator(),
      topImmersionSessionCoordinator: top, recentActionManager: { recordClick() {} },
      scrollPerformanceCoordinator: { createState: () => ({}), activateForMove: state => state, activate: state => state },
      smoothModeService: {}, runtimeLifecyclePort: {}
    }, { resolveFacts: () => ({ activeTabId: facts.activeTabId, webPageVisible: true, addressFocused: false,
        currentDetent: 'low', currentPresentation: bottomPresentation, tabsSheetVisible: false,
        bottomToolbarPinnedBySafeArea: bottomInset > 0,
        webAppImmersiveMode: false, fullScreenModeEnabled: false, smoothModeRuntimeEnabled: false,
        experimentSettings: {} }),
      applyBottomChromeDecision(decision) {
        bottomPresentation = decision.presentation;
        facts.bottomPanelInteractive = bottomPresentation === 'resting';
      }
    });
    const scroll = y => { facts.scrollOffsetY = y; interaction.handleScroll(facts.activeTabId, y); };
    interaction.handleTouch(facts.activeTabId, 'down');
    interaction.handleTouch(facts.activeTabId, 'move');
    const gestureTargetY = pageHeight - shell.webViewportPresentation.contentHeightPx - (mode === 'mid-page' ? 120 : 0);
    scroll(gestureTargetY - 47);
    clockNow += 400;
    scroll(gestureTargetY);
    const clampedY = Math.min(facts.scrollOffsetY, pageHeight - shell.webViewportPresentation.contentHeightPx);
    if (mode === 'mid-page') {
      assert.equal(clampedY, facts.scrollOffsetY, 'viewport expansion need not move a mid-page scroll position');
      clockNow += 60;
      scroll(gestureTargetY + 10);
      clockNow += 60;
      scroll(gestureTargetY + 30);
      assert.deepEqual(transitions, [false], 'continued forward scrolling does not reverse the chrome transition');
      assert.equal(interaction.getLastScrollY(), gestureTargetY + 30, 'forward scroll offsets are still consumed');
      clockNow += 400;
      scroll(gestureTargetY - 10);
      assert.deepEqual(transitions, [false, true], 'a real reversal after continued scrolling still reveals chrome');
      assert.ok(durations.every(duration => duration === 180), 'both directions retain the top animation');
      continue;
    }
    assert.ok(clampedY < facts.scrollOffsetY, 'expanding the viewport reduces the page-end scroll range');
    if (mode === 'new-touch') {
      clockNow += 400;
      interaction.handleTouch(facts.activeTabId, 'down');
      interaction.handleTouch(facts.activeTabId, 'move');
      scroll(clampedY);
      assert.deepEqual(transitions, [false, true], 'a new gesture must not inherit layout correction suppression');
    } else if (mode === 'expired') {
      clockNow += 700;
      scroll(clampedY);
      assert.deepEqual(transitions, [false, true], 'correction window must expire without a timer');
    } else if (mode === 'larger-reversal') {
      clockNow += 400;
      scroll(clampedY - 40);
      assert.deepEqual(transitions, [false, true], 'movement larger than the resize must not be swallowed');
    } else if (mode === 'continued-down') {
      clockNow += 400;
      scroll(facts.scrollOffsetY + 10);
      scroll(clampedY);
      assert.deepEqual(transitions, [false, true], 'fresh downward movement ends the correction allowance');
    } else {
      if (mode === 'inertia') interaction.handleTouch(facts.activeTabId, 'up');
      clockNow += 200;
      if (mode === 'split') {
        scroll(clampedY + 20);
        clockNow += 100;
      }
      scroll(clampedY);
      assert.deepEqual(transitions, [false],
        `bottom=${bottomInset}, ${mode}: viewport correction must not reveal chrome and reverse its geometry`);
      assert.equal(interaction.getLastScrollY(), clampedY, 'correction updates the actual scroll baseline');
      assert.equal(bottomPresentation, bottomInset > 0 ? 'resting' : 'compact',
        'layout feedback preserves the intended bottom toolbar state');
      clockNow += 400;
      if (mode === 'inertia') {
        interaction.handleTouch(facts.activeTabId, 'down');
        interaction.handleTouch(facts.activeTabId, 'move');
      }
      scroll(clampedY - 40);
      assert.deepEqual(transitions, [false, true], 'a subsequent genuine upward scroll must still restore chrome');
    }
    assert.ok(durations.every(duration => duration === 180), 'both directions retain the top animation');
  }
}
console.log('Top immersion: ordinary and bottom-reserved pages reject viewport feedback and preserve gesture/inertia behavior.');


const refreshStart = shellSource.indexOf('private refreshWebViewportPresentation(');
const refreshEnd = shellSource.indexOf('private setWebBottomAddressFocused(', refreshStart);
assert.match(shellSource.slice(refreshStart, refreshEnd),
  /browserWebScrollInteractionCoordinator\.handleViewportChanged\(\s*this\.activeTabId, previousPresentation, this\.webViewportPresentation/,
  'all published viewport changes must reach the scroll feedback owner');

// A reserved native bottom strip owns a permanently visible resting toolbar,
// while the top inset retains independent scroll immersion.
for (const behavior of ['compact', 'hidden']) {
  const item = fixture();
  let pinned = true;
  let bottomPresentation = behavior;
  let currentDetent = 'low';
  item.facts.bottomToolbarPinnedBySafeArea = true;
  item.facts.bottomPanelInteractive = true;
  const interaction = new BrowserWebScrollInteractionCoordinator({
    bottomChromeScrollCoordinator: new BrowserBottomChromeScrollCoordinator({
      applyPresentationDeltaPx: 28, restorePresentationDeltaPx: 24, transitionCooldownMs: 0
    }),
    topImmersionSessionCoordinator: item.coordinator,
    recentActionManager: { recordClick() {} },
    scrollPerformanceCoordinator: { createState: () => ({}), activateForMove: state => state },
    smoothModeService: {}, runtimeLifecyclePort: {}
  }, {
    resolveFacts: () => ({ activeTabId: item.facts.activeTabId, webPageVisible: true,
      addressFocused: false, currentDetent, currentPresentation: bottomPresentation,
      bottomToolbarPinnedBySafeArea: pinned, tabsSheetVisible: false,
      webAppImmersiveMode: false, fullScreenModeEnabled: false,
      smoothModeRuntimeEnabled: false, experimentSettings: {} }),
    applyBottomChromeDecision(decision) {
      bottomPresentation = decision.presentation;
      currentDetent = decision.detent;
      item.facts.bottomPanelInteractive = bottomPresentation === 'resting';
    }
  });
  interaction.applyBottomToolbarScrollBehavior(behavior, item.facts.activeTabId);
  const viewport = { hostHeightPx: 844, visualTopInsetPx: 40, fullViewport: false,
    largeScreenShellActive: false, nativeVideoTakeoverActive: false };
  // A detection can arrive after a toolbar has already hidden; restore on applying
  // the reservation, without requiring the user to touch or scroll again.
  bottomPresentation = behavior;
  interaction.handleViewportChanged(item.facts.activeTabId,
    BrowserWebViewportCoordinator.resolvePresentation(viewport),
    BrowserWebViewportCoordinator.resolvePresentation({ ...viewport, visualBottomInsetPx: 101 }));
  assert.equal(bottomPresentation, 'resting', 'safe-area activation immediately restores the toolbar');
  interaction.handleTouch(item.facts.activeTabId, 'down');
  interaction.handleTouch(item.facts.activeTabId, 'move');
  const scroll = y => { item.facts.scrollOffsetY = y; interaction.handleScroll(item.facts.activeTabId, y); };
  for (const y of [0, 40, 90, 140]) {
    clockNow += 400; scroll(y);
    assert.equal(bottomPresentation, 'resting', `pinned toolbar must ignore ${behavior} on downward scroll`);
  }
  assert.deepEqual(item.updates.map(x => x.visible), [false], 'pinned resting toolbar must allow top immersion');
  clockNow += 400; scroll(40);
  assert.deepEqual(item.updates.map(x => x.visible), [false, true], 'top still reveals on upward scroll');
  assert.ok(item.updates.every(x => x.durationMs === 180));
  for (const delta of [60, -40, 80]) {
    interaction.handleLocalScrollSignal(item.facts.activeTabId, JSON.stringify({
      sourceId: 'nested-feed', scrollTop: 200, deltaY: delta, timestamp: clockNow
    }));
    assert.equal(bottomPresentation, 'resting', 'nested scrollers also keep the reserved toolbar visible');
  }
  for (const field of ['addressFocused', 'tabsSheetVisible']) {
    const focused = fixture();
    focused.facts.bottomToolbarPinnedBySafeArea = true;
    focused.facts.bottomPanelInteractive = true;
    focused.hide();
    focused.facts[field] = true;
    focused.scroll(0);
    assert.equal(focused.updates.at(-1).visible, true, `${field} must still reveal top chrome`);
    assert.equal(focused.updates.at(-1).durationMs, 0);
  }
  pinned = false;
  item.facts.bottomToolbarPinnedBySafeArea = false;
  interaction.handleTouch(item.facts.activeTabId, 'down');
  interaction.handleTouch(item.facts.activeTabId, 'move');
  clockNow += 400; scroll(100); // Re-establish root coordinates after the nested source.
  clockNow += 400; scroll(160);
  assert.equal(bottomPresentation, behavior, 'releasing the reservation restores the saved user scroll preference');
}
console.log('Combined safe areas: pinned bottom toolbar and animated top immersion remain independent.');

for (const detent of ['peek', 'low', 'middle']) {
  const input = { tabId: 'pinned', bottomToolbarPinnedBySafeArea: true, scrollOffsetY: 100,
    webPageVisible: true, addressFocused: false, currentDetent: detent, currentPresentation: 'hidden',
    presentationChangeAllowed: true, showTabsSheet: false, scrollBehavior: 'hidden',
    webAppImmersiveMode: false, fullScreenModeEnabled: false };
  const bottom = new BrowserBottomChromeScrollCoordinator();
  for (const method of ['handleWebScrollMove', 'handleWebScrollSettle']) {
    const decision = bottom[method](input);
    assert.equal(decision.presentation, 'resting');
    assert.equal(decision.detent, detent === 'peek' ? 'low' : detent,
      'reservation restores the toolbar but preserves an explicitly expanded panel');
  }
  assert.equal(bottom.handleWebScrollMove({ ...input, fullScreenModeEnabled: true }).detent, 'peek',
    'fullscreen remains authoritative');
}
