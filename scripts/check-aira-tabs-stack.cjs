const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

function load(relative, requireDependency) {
  const filename = path.resolve(__dirname, '..', relative);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((compiled.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length,
    0, `Transpile errors in ${filename}`);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    module, exports: module.exports, require: requireDependency
  }, { filename });
  return module.exports;
}
const exportsUnderTest = load(
  'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy.ets',
  name => { throw new Error(`Pure policy must not import ${name}`); });
const policy = new exportsUnderTest.BrowserTabsOverviewStackLayoutPolicy();
const close = (actual, expected, tolerance = 1e-9) =>
  assert.ok(Math.abs(actual - expected) <= tolerance, `${actual} != ${expected}`);
// Every card reports the same shape; only `offsetY` is not a golden column, because the resting
// deck is a single baseline (it is asserted to stay 0 below).
const metricFields = ['offsetX', 'offsetY', 'scale', 'opacity', 'titleOpacity', 'shadeOpacity', 'zIndex'];
const fields = ['offsetX', 'scale', 'opacity', 'titleOpacity', 'shadeOpacity', 'zIndex'];

test('the Hyperion suite executes against the actual transpiled ETS source', () => {
  let cases = 0;
  const suite = load('AiraBrowser/entry/src/test/BrowserTabsOverviewStackLayoutPolicy.test.ets', name => {
    if (name === '@ohos/hypium') return {
      describe: (_name, body) => body(),
      it: (name, _flags, body) => {
        try { body(); cases++; } catch (error) { throw new Error(name, { cause: error }); }
      },
      expect: value => ({
        assertTrue: () => assert.equal(value, true),
        assertFalse: () => assert.equal(value, false)
      })
    };
    assert.equal(name, '../main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy');
    return exportsUnderTest;
  });
  suite.default();
  assert.equal(cases, 15);
});

// Inputs: index, raw scroll position, count, card width. Outputs follow `fields`.
//
// Offsets, fades, shades and z-order are fixed values independently evaluated by transliterating
// AppSwitcherOverlay.kt (commit 8298945). The scale column is Aira's own depth curve instead: the
// focused card and everything in front of it are the standard size, and each level *behind* it is
// `0.96x` smaller, floored at the third level. Those numbers come from that formula, not this policy.
const goldens = [
  [[2, 2, 6, 250], [0, 1, 1, 1, 0, 2]],
  [[1, 2, 6, 250], [-55, .96, 1, 0, .25, 1]],
  [[0, 2, 6, 250], [-70.4, .9216, 1, 0, .5, 0]],
  [[3, 2, 6, 250], [212.5, 1, 1, 1, 0, 3]],
  [[0, 2.5, 6, 250], [-73.21986676296929, .9029798987795907, .5, 0, .5, 0]],
  [[2, 2.5, 6, 250], [-35.96768830317987, .9797958971132712, 1, .5, .125, 2]],
  [[3, 2.5, 6, 250], [92.4959973502132, 1, 1, 1, 0, 3]],
  [[4, 2.5, 6, 250], [345.67537706926646, 1, 1, .5, 0, 4]],
  [[5, 2.5, 6, 250], [638.0973555526352, 1, 1, 0, 0, 5]],
  [[0, -.5, 6, 250], [54.64285714285714, 1, 1, 1, 0, 0]],
  [[1, -.5, 6, 250], [293.2310267857143, 1, 1, 1, 0, 1]],
  [[2, -.5, 6, 250], [574.9481745001135, 1, 1, 0, 0, 2]],
  [[5, 5.5, 6, 250], [-49.33035714285714, .9839285714285715, 1, 1, 0, 5]],
  [[4, 5.5, 6, 250], [-79.66517857142858, .9245714285714286, 1, 0, .25, 4]],
  [[3, 5.5, 6, 250], [-86.84345238095237, .8821028571428572, 1, 0, .5, 3]]
];
test('independent goldens cover depth, parallax, fades and differential overscroll', () => {
  for (const [input, expected] of goldens) {
    const actual = policy.resolveCard(...input);
    assert.deepEqual(Object.keys(actual).sort(), [...metricFields].sort());
    assert.equal(actual.offsetY, 0);
    fields.forEach((field, i) => close(actual[field], expected[i]));
  }
});
test('title tent, shade and left fade have exact boundaries', () => {
  for (const [relative, title, shade, opacity] of [
    [-3, 0, .5, 0], [-2.75, 0, .5, .25], [-2, 0, .5, 1],
    [-.75, .25, .1875, 1], [-.25, .75, .0625, 1],
    [0, 1, 0, 1], [.75, 1, 0, 1], [1.25, .75, 0, 1], [2, 0, 0, 1]
  ]) {
    const m = policy.resolveCard(4, 4 - relative, 10, 250);
    [m.titleOpacity, m.shadeOpacity, m.opacity]
      .forEach((value, i) => close(value, [title, shade, opacity][i]));
  }
  // The title fades through opacity alone: the deck must not expose a blur channel at all.
  for (let relative = -3; relative <= 3; relative += 0.25) {
    const metrics = policy.resolveCard(4, 4 - relative, 10, 250);
    assert.deepEqual(Object.keys(metrics).sort(), [...metricFields].sort());
    assert.equal(metrics.offsetY, 0);
    assert.ok(metrics.titleOpacity >= 0 && metrics.titleOpacity <= 1);
  }
});
test('release projects the velocity and only discards it after an overscroll', () => {
  for (const [position, velocity, target, speed] of [
    [2, -600, 3, 4], [2, 600, 1, -4], [2.5, 0, 3, 0],
    [-.5, -1800, 3, 0], [5.5, 1800, 3, 0], [0, 600, 0, -4], [5, -600, 5, 4],
    [5.5, -1800, 5, 0], [-.5, 1800, 0, 0]
  ]) {
    const result = policy.release(position, velocity, 250, 6);
    assert.deepEqual(Object.keys(result).sort(), ['target', 'velocity']);
    assert.equal(result.target, target);
    close(result.velocity, speed);
  }
});
test('drag friction matches the reference at both edges, including a single card', () => {
  for (const [position, delta, expected] of [
    [2, -150, 2.7], [2, 150, 1.3], [0, 150, -.42], [0, -150, .7],
    [-2, 150, -2.21], [-2, -150, -1.3], [7, -150, 7.21], [7, 150, 6.3],
    [.1, 150, -.6], [5, 150, 4.3], [5, -150, 5.42]
  ]) close(policy.advanceDrag(position, delta, 250, 6), expected);
  close(policy.advanceDrag(0, -150, 250, 1), .42);
  close(policy.advanceDrag(0, 150, 250, 1), -.42);
});
test('spring independent golden with initial velocity and fixed stiffness 80', () => {
  // 50-digit decimal evaluation of the analytic critically damped solution, not a replica.
  const sample = policy.sampleSpring(0, 0, 3, .12);
  close(sample.position, .12307468943367433);
  close(sample.velocity, -.07519107558619749);
  assert.equal(sample.finished, false);
  close(policy.sampleSpring(1, 0, 0, .1).position, .7745208708001288);
  for (const [start, target] of [[0, 5], [5, 0], [-.5, 0], [5.5, 5]]) {
    let previous = Math.abs(start - target);
    for (let frame = 0; frame <= 240; frame++) {
      const sample = policy.sampleSpring(start, target, 0, frame / 60);
      const distance = Math.abs(sample.position - target);
      assert.ok(distance <= previous + 1e-12);
      assert.ok(sample.position >= Math.min(start, target) && sample.position <= Math.max(start, target));
      previous = distance;
    }
    const end = policy.sampleSpring(start, target, 0, 4);
    assert.equal(end.finished, true);
    assert.equal(end.position, target);
    assert.equal(end.velocity, 0);
  }
  assert.equal(policy.sampleSpring(1, 0, 0, -.1).position, 1);
  // The reference rest condition requires both displacement and velocity under the threshold.
  const crawling = policy.sampleSpring(.1, 0, 0, .92);
  assert.ok(Math.abs(crawling.position) < .0005 && Math.abs(crawling.velocity) >= .0005);
  assert.equal(crawling.finished, false);
});
test('cancel uses the softer StiffnessLow spring, not the release stiffness', () => {
  const cancelled = policy.sampleSpring(3, 2, 0, .12, 200);
  close(cancelled.position, 2.4941602779191264);
  close(cancelled.velocity, -4.39733007451937);
  close(policy.sampleSpring(3, 2, 0, .12).position, 2.70881196649359);
  assert.ok(cancelled.position < policy.sampleSpring(3, 2, 0, .12).position);
});
test('the visible window covers the viewport and never exceeds the deck', () => {
  for (const position of [-1, 0, 2.5, 5, 19, 25]) {
    const range = policy.resolveVisibleRange(position, 20, 390, 250);
    assert.ok(range.first >= 0 && range.first <= range.last && range.last <= 19);
    const clamped = Math.min(Math.max(position, 0), 19);
    assert.ok(range.first <= Math.floor(clamped) && range.last >= Math.ceil(clamped));
  }
  // A wider viewport can only widen the trailing window, never narrow it.
  let previous = 0;
  for (const viewport of [200, 390, 800, 1400]) {
    const last = policy.resolveVisibleRange(0, 60, viewport, 250).last;
    assert.ok(last >= previous);
    previous = last;
  }
});
test('the anchored card survives insertions, removals and its own deletion', () => {
  const previous = ['a', 'b', 'c', 'd'];
  assert.equal(policy.reconcilePosition(2, previous, previous), 2);
  assert.equal(policy.reconcilePosition(2, previous, ['z', 'a', 'b', 'c', 'd']), 3);
  assert.equal(policy.reconcilePosition(2, previous, ['a', 'c', 'd']), 1);
  assert.equal(policy.reconcilePosition(2, previous, ['a', 'b', 'd']), 2);
  assert.equal(policy.reconcilePosition(3, previous, ['a', 'b', 'c']), 2);
  close(policy.reconcilePosition(2.4, previous, ['a', 'c', 'd']), 1.4);
  assert.equal(policy.reconcilePosition(2, previous, []), 0);
});
test('empty counts, invalid indices and nonfinite inputs yield defined finite results', () => {
  // The reference never fades the trailing side; right-side cards leave the sheet by position.
  for (const count of [0, -1, NaN, Infinity, -Infinity]) {
    assert.equal(policy.clamp(4, count), 0);
    assert.equal(policy.resolveMaxIndex(count), 0);
    assert.equal(policy.advanceDrag(4, -150, 250, count), 0);
    const release = policy.release(4, -600, 250, count);
    assert.equal(release.target, 0);
    assert.equal(release.velocity, 0);
  }
  assert.equal(policy.resolveCard(0, 0, 0, 250).opacity, 0);
  assert.equal(policy.resolveCard(0, 0, 1, 250).opacity, 1);
  for (const bad of [NaN, Infinity, -Infinity]) {
    for (const value of Object.values(policy.resolveCard(bad, bad, bad, bad)))
      assert.ok(Number.isFinite(value));
    assert.equal(policy.resolveCard(bad, 2, 6, 250).opacity, 0);
    const spring = policy.sampleSpring(bad, bad, bad, bad);
    assert.equal(spring.finished, true);
    assert.equal(spring.position, 0);
    assert.equal(spring.velocity, 0);
  }
  // A non-positive or non-finite width must not divide the drag or the release.
  for (const width of [0, -1, NaN, Infinity]) {
    close(policy.advanceDrag(2, -150, width, 6), 2);
    const release = policy.release(2.2, -600, width, 6);
    assert.equal(release.target, 2);
    assert.equal(release.velocity, 0);
  }
});

test('motion owns one scalar position and rejects stale frames after a retarget', () => {
  const motionExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackMotion.ets',
    name => {
      assert.equal(name, './BrowserTabsOverviewStackLayoutPolicy');
      return exportsUnderTest;
    });
  const motion = new motionExports.BrowserTabsOverviewStackMotion();
  const frames = [];
  const schedule = callback => frames.push(callback);
  assert.equal(motion.seed(3, 6), 3);
  // A drag is delta-based, so the same cumulative offset applied twice must not double-count.
  motion.begin();
  motion.drag(40, 250, 6);
  close(motion.drag(80, 250, 6), motion.getPosition());
  let published = [];
  motion.release(0, 250, 6, schedule, position => published.push(position));
  assert.equal(published.length, 0);
  assert.equal(frames.length, 1);
  // Frames advance the displayed position monotonically towards the projected card.
  let previous = motion.getPosition();
  for (let i = 0; i < 400 && frames.length > 0; i++) {
    const frame = frames.shift();
    frame(i * 16000000);
    if (published.length > 0) {
      assert.ok(published[published.length - 1] >= previous - 1e-9);
      previous = published[published.length - 1];
    }
  }
  assert.equal(motion.getPosition(), Math.round(motion.getPosition()));
  // A retarget invalidates every in-flight frame from the previous animation.
  motion.release(0, 250, 6, schedule, () => {});
  const stale = frames.shift();
  motion.stop();
  const before = motion.getPosition();
  stale(999 * 16000000);
  assert.equal(motion.getPosition(), before);
});

test('an interruption settles the deck onto a card instead of freezing it', () => {
  const motionExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackMotion.ets',
    name => { assert.equal(name, './BrowserTabsOverviewStackLayoutPolicy'); return exportsUnderTest; });
  const motion = new motionExports.BrowserTabsOverviewStackMotion();
  const frames = [];
  const schedule = callback => frames.push(callback);
  motion.seed(2, 6);
  motion.begin();
  motion.drag(90, 250, 6);
  const fractional = motion.getPosition();
  assert.notEqual(fractional, Math.round(fractional));
  // A non-gesture interruption must finish the movement, not just stop it.
  motion.settleToNearest(6, schedule, () => {});
  let frame = 0;
  while (frames.length > 0 && frame < 600) frames.shift()(frame++ * 16000000);
  assert.equal(motion.getPosition(), Math.round(fractional));
  // Already on a card: the abort is a no-op rather than an endless frame chain.
  motion.seed(3, 6);
  const quiet = [];
  motion.settleToNearest(6, callback => quiet.push(callback), () => {});
  assert.equal(quiet.length, 0);
  assert.equal(motion.getPosition(), 3);
  // Cancelling a drag uses the cancel spring and still lands on a card.
  motion.begin();
  motion.drag(-60, 250, 6);
  const cancelFrames = [];
  motion.cancel(6, callback => cancelFrames.push(callback), () => {});
  let tick = 0;
  while (cancelFrames.length > 0 && tick < 600) cancelFrames.shift()(tick++ * 16000000);
  assert.equal(motion.getPosition(), Math.round(motion.getPosition()));
});

test('a dismissed card leaves at the speed the finger had', () => {
  const swipeExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewSwipeDismissPolicy.ets',
    name => { throw new Error(`Pure policy must not import ${name}`); });
  const swipe = new swipeExports.BrowserTabsOverviewSwipeDismissPolicy();
  const min = swipeExports.BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MIN_DURATION_MS;
  const max = swipeExports.BROWSER_TABS_OVERVIEW_SWIPE_FLYOUT_MAX_DURATION_MS;
  // travel / speed: 800vp at 4000vp/s is 200ms, and a quarter of that speed takes four times as long.
  close(swipe.resolveFlyoutDurationMs(800, 4000), 200);
  assert.equal(swipe.resolveFlyoutDurationMs(800, 1000), max);
  // The bounds only clamp the extremes: a violent flick and a release with no speed at all.
  assert.equal(swipe.resolveFlyoutDurationMs(800, 20000), min);
  assert.equal(swipe.resolveFlyoutDurationMs(800, 0), max);
  assert.equal(swipe.resolveFlyoutDurationMs(0, 4000), min);
  // Faster is never slower.
  let previous = Infinity;
  for (const speed of [200, 500, 1000, 2000, 4000, 8000]) {
    const duration = swipe.resolveFlyoutDurationMs(800, speed);
    assert.ok(duration <= previous, `${speed}vp/s took ${duration}ms, longer than ${previous}ms`);
    previous = duration;
  }
  // The sign of the release velocity is the gesture's direction, not its speed.
  assert.equal(swipe.resolveFlyoutDurationMs(800, -4000), swipe.resolveFlyoutDurationMs(800, 4000));
  // Invalid input cannot produce a duration outside the bounds.
  for (const [travel, speed] of [[NaN, NaN], [Infinity, 100], [-100, -100], [800, Infinity]]) {
    const duration = swipe.resolveFlyoutDurationMs(travel, speed);
    assert.ok(duration >= min && duration <= max, `${duration} out of bounds`);
  }
});

test('a removal moves only the cards beyond it, and only towards the focus', () => {
  // A card's place in the deck is its slot against the deck scalar, so what a removal changes is the
  // slot. `reconcilePosition` resolves the scalar the shorter list focuses while keeping the focused
  // tab, and the slots are the new list's own order, so the movement of each card is the difference
  // between its relative position before and after.
  const shift = (previousIds, removedId, position) => {
    const nextIds = previousIds.filter(id => id !== removedId);
    const nextPosition = policy.reconcilePosition(position, previousIds, nextIds);
    const moved = {};
    nextIds.forEach((id, index) => {
      const delta = (index - nextPosition) - (previousIds.indexOf(id) - position);
      if (Math.abs(delta) > 1e-9) moved[id] = delta;
    });
    return { nextPosition, moved };
  };
  const tabs = ['a', 'b', 'c', 'd', 'e'];
  // The focused card (index 2) closes: its successor takes the focus and the cards beyond it follow.
  // The cards before the focus keep their place, which is what makes the gap close from one side.
  assert.deepEqual(shift(tabs, 'c', 2), { nextPosition: 2, moved: { d: -1, e: -1 } });
  // The last card closes while it holds the focus: the predecessor takes the focus and every card
  // before it moves one slot towards it.
  assert.deepEqual(shift(tabs, 'e', 4), { nextPosition: 3, moved: { a: 1, b: 1, c: 1, d: 1 } });
  // A card before the focus closes: only the cards beyond it close the gap, and the focus is kept.
  assert.deepEqual(shift(tabs, 'b', 3), { nextPosition: 2, moved: { a: 1 } });
  // A card after the focus closes: same rule on the other side.
  assert.deepEqual(shift(tabs, 'd', 1), { nextPosition: 1, moved: { e: -1 } });
  // The outermost card behind the focus leaves no slot behind: the deck scalar moves with the slots
  // and no card changes its relative position, so there is nothing to animate.
  assert.deepEqual(shift(tabs, 'a', 3), { nextPosition: 2, moved: {} });
  assert.deepEqual(shift(tabs, 'e', 3), { nextPosition: 3, moved: {} });
  // The outermost card in front of the focus is a real removal: everything comes forward one slot.
  assert.deepEqual(shift(tabs, 'a', 0),
    { nextPosition: 0, moved: { b: -1, c: -1, d: -1, e: -1 } });
  // Closing the only card empties the deck instead of leaving a position pointing past the end.
  assert.deepEqual(shift(['a'], 'a', 0), { nextPosition: 0, moved: {} });
  // Closing a card that is not in the list changes nothing.
  assert.deepEqual(shift(tabs, 'zz', 2), { nextPosition: 2, moved: {} });
});

test('the four styles are offered 卡片平铺 first, and every normaliser names all four', () => {
  const read = relative => fs.readFileSync(path.resolve(__dirname, '..', relative), 'utf8');
  const coordinator = read('AiraBrowser/entry/src/main/ets/core/settings/TabOverviewLayoutSettingsCoordinator.ets');
  const options = coordinator.slice(coordinator.indexOf('buildOptions('),
    coordinator.indexOf('private normalizeStyle('));
  assert.ok(options.indexOf("style: 'grid'") >= 0 &&
    options.indexOf("style: 'grid'") < options.indexOf("style: 'horizontal_cards'") &&
    options.indexOf("style: 'horizontal_cards'") < options.indexOf("style: 'stack'") &&
    options.indexOf("style: 'stack'") < options.indexOf("style: 'list'"),
  '卡片平铺 must lead, then 横向大卡片, then 堆叠式, then 列表式');
  // Every normaliser has to name all four styles. Naming only the non-default ones would quietly
  // turn a stored style back into the default the moment the default changed.
  assert.match(coordinator,
    /return style === 'horizontal_cards' \|\| style === 'stack' \|\| style === 'list' \? style : 'grid';/);
  const preferences = read('AiraBrowser/entry/src/main/ets/data/preferences/PreferencesRepository.ets');
  assert.match(preferences, /tabsOverviewLayoutStyle: 'grid',/);
  assert.match(preferences,
    /return value === 'grid' \|\| value === 'horizontal_cards' \|\| value === 'stack' \|\| value === 'list' \?/);
  const layoutViewModel = read('AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewLayoutViewModel.ets');
  assert.match(layoutViewModel,
    /return style === 'horizontal_cards' \|\| style === 'stack' \|\| style === 'list' \? style : 'grid';/);
  assert.match(layoutViewModel, /layoutStyle: 'list'/);
  const snapshot = read('AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncSnapshotService.ets');
  assert.match(snapshot,
    /value === 'grid' \|\| value === 'horizontal_cards' \|\| value === 'stack' \|\| value === 'list' \?/);
  const sheet = read('AiraBrowser/entry/src/main/ets/app/components/settings/TabOverviewLayoutChoiceSheet.ets');
  assert.match(sheet, /optionsInRange\(0, 2\)/);
  assert.match(sheet, /optionsInRange\(2, 4\)/);
  assert.match(sheet, /TAB_OVERVIEW_LAYOUT_FOOTER_CLEARANCE/);
  assert.doesNotMatch(sheet, /Grid\(\)/);
  assert.match(sheet, /tab_overview_list_light/);
  const intro = read('AiraBrowser/entry/src/main/ets/app/pages/FeatureIntroAppearancePage.ets');
  assert.match(intro, /TabOverviewLayoutOptionGrid/);
  assert.match(intro, /feature-intro-tab-overview-style/);
  const introViewModel = read('AiraBrowser/entry/src/main/ets/core/onboarding/FeatureIntroAppearanceViewModel.ets');
  assert.match(introViewModel, /style: 'list'/);
  assert.match(introViewModel,
    /value === 'horizontal_cards' \|\| value === 'stack' \|\| value === 'list'/);
  const overlay = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets');
  assert.match(overlay, /private buildListLayer\(\)/);
  assert.match(overlay, /BrowserTabOverviewListRow/);
  const listLayer = overlay.slice(overlay.indexOf('private buildListLayer'),
    overlay.indexOf('private resolveCardSnapshotImageUri'));
  assert.match(listLayer, /resolveListItems\(\)/);
  assert.match(overlay, /lastActiveAt/);
  assert.match(listLayer, /contentStartOffset\(this\.resolveContentTopPadding\(\)\)/);
  assert.match(listLayer, /clipContent\(ContentClipMode\.BOUNDARY\)/);
  assert.match(listLayer, /FLOATING_TABS_TOP_BLUR_STOPS/);
  assert.match(listLayer, /contentOpacity: this\.resolveListRowContentOpacity\(item\.tab\.id\)/);
  assert.match(listLayer, /frameScale: this\.resolveListRowFrameScale\(item\.tab\.id\)/);
  assert.match(overlay, /getListEntryDissolveCurve\(\)/);
  assert.match(overlay, /listEntrySnapshotSuppressed/);
  assert.doesNotMatch(listLayer, /top: this\.resolveContentTopPadding\(\)/);
  assert.match(overlay, /listEntrySnapshotOpacity = 0/);
  const session = read('AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewSessionCoordinator.ets');
  assert.match(session, /this\.styleEntryPolicy\.resolve\(facts\.tabOverviewLayoutStyle\)/);
  assert.doesNotMatch(session, /tabOverviewLayoutStyle === 'list'/);
  assert.match(overlay, /!this\.isMorphCoveredTab\(tabId\)/);
  const listRow = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabOverviewListRow.ets');
  assert.match(listRow, /\.opacity\(this\.contentOpacity\)/);
  assert.match(listRow, /\.opacity\(this\.frameOpacity\)/);
  assert.match(listRow, /\.opacity\(this\.rowOpacity\)/);
});

test('the middle bar\'s swipe-up is a second trigger for the same open, not a second animation', () => {
  const read = relative => fs.readFileSync(path.resolve(__dirname, '..', relative), 'utf8');
  const gestureExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewEntryGesturePolicy.ets',
    name => { throw new Error(`Pure policy must not import ${name}`); });
  const gesture = new gestureExports.BrowserTabsOverviewEntryGesturePolicy();
  // Only the claim is still used: one small upward travel per gesture, and only on the way up.
  assert.equal(gesture.shouldClaim(4, false), false);
  assert.equal(gesture.shouldClaim(-8, false), true);
  assert.equal(gesture.shouldClaim(40, true), true);
  const panel = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets');
  const page = read('AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets');
  // The panel latches the trigger once and reports it through a plain callback.
  assert.match(panel, /onOpenTabsOverview: \(\) => void = \(\) => \{\};/);
  assert.match(panel, /private shouldOpenTabsOverviewFromMiddleBar\(offsetY: number\): boolean \{/);
  assert.match(panel, /this\.entryGesturePolicy\.shouldClaim\(offsetY, false\)/);
  assert.match(panel, /if \(frame\.phase === 'update' && this\.shouldOpenTabsOverviewFromMiddleBar\(frame\.offsetY\)\) \{\s*this\.beginMiddleBarTabsOverviewGesture\(\);/);
  // One decision, asked by every consumer. The release intercept and the toolbar Sheet gate both have
  // to consult it, which is what stops the panel from expanding after the overview was already asked
  // for — the flash of the toolbar panel that then tore itself down.
  assert.match(panel, /private resolveMiddleBarSwipeUpTarget\(\s*source: BrowserBottomChromeGestureSource,\s*offsetY: number\s*\): 'tabs_overview' \| 'toolbar' \{/);
  assert.match(panel, /private beginMiddleBarTabsOverviewGesture\(\): void \{\s*if \(this\.tabsOverviewMiddleBarGestureTriggered\) \{\s*return;\s*\}/);
  const intercept = panel.slice(panel.indexOf('onPanelGestureEndIntercept: ('),
    panel.indexOf('onPanelGestureRelease: ('));
  assert.match(intercept, /if \(this\.resolveMiddleBarSwipeUpTarget\(source, offsetY\) === 'tabs_overview'\) \{\s*this\.beginMiddleBarTabsOverviewGesture\(\);\s*return 'low';\s*\}/);
  assert.match(intercept, /if \(this\.shouldOpenToolbarSystemSheetFromGesture\(targetDetent, offsetY, source\)\) \{\s*this\.openToolbarSystemSheet\(\);/);
  const sheetGate = panel.slice(panel.indexOf('private shouldOpenToolbarSystemSheetFromGesture('),
    panel.indexOf('private isTabsOverviewPullEnabled('));
  assert.match(sheetGate, /this\.resolveMiddleBarSwipeUpTarget\(source, offsetY\) === 'toolbar' &&/);
  assert.match(sheetGate, /!this\.tabsOverviewMiddleBarGestureTriggered &&/);
  // The shell opens the overview through the same call the 标签页 button uses, and passes no finger
  // state to the overlay at all.
  assert.match(page, /private handleTabsOverviewEntryGesture\(\): void \{\s*void this\.openTabsOverview\(\);\s*\}/);
  assert.match(page, /private async openTabsOverview\(activeSection: BrowserTabsOverviewSessionSection = 'tabs'\): Promise<void> \{\s*this\.dispatchTabsOverviewSession\(\{ type: 'request_open', section: activeSection \}\);/);
  // Both triggers have to reach that one call: the button through the shell action, the gesture
  // through `handleTabsOverviewEntryGesture`.
  assert.match(page, /onOpenTabsOverview: \(\) => \{\s*this\.handleTabsOverviewEntryGesture\(\);/);
  // Nothing may be left of the finger-driven pull, on either side of the boundary.
  for (const [name, source] of [['panel', panel], ['page', page]]) {
    assert.doesNotMatch(source, /entryGestureActive|entryGestureOffset[XY]|onTabsOverviewEntryGesture/,
      `${name} must not carry finger state for the overview entry`);
  }
  const overlay = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets');
  assert.doesNotMatch(overlay, /entryGesture|EntryGesture/,
    'the overlay must not own any part of a finger-driven pull');
  // And the pull-only geometry helpers must be gone from the overlay.
  assert.doesNotMatch(overlay, /resolveEntryGesturePulledRect|resolveEntryGestureCardMetrics|buildEntryGestureSnapshot/);
});

test('the middle bar\'s swipe-up is a second trigger for the same open, not a second animation', () => {
  const read = relative => fs.readFileSync(path.resolve(__dirname, '..', relative), 'utf8');
  const gestureExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewEntryGesturePolicy.ets',
    name => { throw new Error(`Pure policy must not import ${name}`); });
  const gesture = new gestureExports.BrowserTabsOverviewEntryGesturePolicy();
  // Only the claim is still used: one small upward travel per gesture, and only on the way up.
  assert.equal(gesture.shouldClaim(4, false), false);
  assert.equal(gesture.shouldClaim(-8, false), true);
  assert.equal(gesture.shouldClaim(40, true), true);
  const panel = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets');
  const page = read('AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets');
  // The panel latches the trigger once and reports it through a plain callback.
  assert.match(panel, /onOpenTabsOverview: \(\) => void = \(\) => \{\};/);
  assert.match(panel, /private shouldOpenTabsOverviewFromMiddleBar\(offsetY: number\): boolean \{/);
  assert.match(panel, /this\.entryGesturePolicy\.shouldClaim\(offsetY, false\)/);
  assert.match(panel, /if \(frame\.phase === 'update' && this\.shouldOpenTabsOverviewFromMiddleBar\(frame\.offsetY\)\) \{\s*this\.beginMiddleBarTabsOverviewGesture\(\);/);
  // One decision, asked by every consumer. The release intercept and the toolbar Sheet gate both have
  // to consult it, which is what stops the panel from expanding after the overview was already asked
  // for — the flash of the toolbar panel that then tore itself down.
  assert.match(panel, /private resolveMiddleBarSwipeUpTarget\(\s*source: BrowserBottomChromeGestureSource,\s*offsetY: number\s*\): 'tabs_overview' \| 'toolbar' \{/);
  assert.match(panel, /private beginMiddleBarTabsOverviewGesture\(\): void \{\s*if \(this\.tabsOverviewMiddleBarGestureTriggered\) \{\s*return;\s*\}/);
  const intercept = panel.slice(panel.indexOf('onPanelGestureEndIntercept: ('),
    panel.indexOf('onPanelGestureRelease: ('));
  assert.match(intercept, /if \(this\.resolveMiddleBarSwipeUpTarget\(source, offsetY\) === 'tabs_overview'\) \{\s*this\.beginMiddleBarTabsOverviewGesture\(\);\s*return 'low';\s*\}/);
  assert.match(intercept, /if \(this\.shouldOpenToolbarSystemSheetFromGesture\(targetDetent, offsetY, source\)\) \{\s*this\.openToolbarSystemSheet\(\);/);
  const sheetGate = panel.slice(panel.indexOf('private shouldOpenToolbarSystemSheetFromGesture('),
    panel.indexOf('private isTabsOverviewPullEnabled('));
  assert.match(sheetGate, /this\.resolveMiddleBarSwipeUpTarget\(source, offsetY\) === 'toolbar' &&/);
  assert.match(sheetGate, /!this\.tabsOverviewMiddleBarGestureTriggered &&/);
  // The shell opens the overview through the same call the 标签页 button uses, and passes no finger
  // state to the overlay at all.
  assert.match(page, /private handleTabsOverviewEntryGesture\(\): void \{\s*void this\.openTabsOverview\(\);\s*\}/);
  assert.match(page, /private async openTabsOverview\(activeSection: BrowserTabsOverviewSessionSection = 'tabs'\): Promise<void> \{\s*this\.dispatchTabsOverviewSession\(\{ type: 'request_open', section: activeSection \}\);/);
  // Both triggers have to reach that one call: the button through the shell action, the gesture
  // through `handleTabsOverviewEntryGesture`.
  assert.match(page, /onOpenTabsOverview: \(\) => \{\s*this\.handleTabsOverviewEntryGesture\(\);/);
  // Nothing may be left of the finger-driven pull, on either side of the boundary.
  for (const [name, source] of [['panel', panel], ['page', page]]) {
    assert.doesNotMatch(source, /entryGestureActive|entryGestureOffset[XY]|onTabsOverviewEntryGesture/,
      `${name} must not carry finger state for the overview entry`);
  }
  const overlay = read('AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets');
  assert.doesNotMatch(overlay, /entryGesture|EntryGesture/,
    'the overlay must not own any part of a finger-driven pull');
  // And the pull-only geometry helpers must be gone from the overlay.
  assert.doesNotMatch(overlay, /resolveEntryGesturePulledRect|resolveEntryGestureCardMetrics|buildEntryGestureSnapshot/);
});

test('the overlay deck wires the policy, per-frame motion and the reference visuals', () => {
  const overlay = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabsFloatingOverlay.ets'), 'utf8');
  // The stacked deck is a Stack of translated cards, never a List; the large card strip beside it is
  // the List, so the two branches cannot collapse back into one.
  const deck = overlay.slice(overlay.indexOf('private buildStackCardsLayer'),
    overlay.indexOf('private buildBlankGridItem'));
  assert.match(deck, /Stack\(\{ alignContent: Alignment\.Center \}\)/);
  assert.match(deck, /PanGesture\(\{ direction: PanDirection\.Horizontal/);
  assert.doesNotMatch(deck, /\bList\(/);
  const strip = overlay.slice(overlay.indexOf('private buildHorizontalCardsLayer'),
    overlay.indexOf('private buildStackCardsLayer'));
  assert.match(strip, /List\(\{/);
  assert.match(strip, /listDirection\(Axis\.Horizontal\)/);
  assert.match(strip, /scrollSnapAlign\(ScrollSnapAlign\.CENTER\)/);
  assert.match(strip, /contentStartOffset\(this\.resolveHorizontalEdgeInset\(true\)\)/);
  assert.doesNotMatch(strip, /resolveDeckMetrics/);
  // Every strip card shares the viewport box. A screenshot's pixel size is a capture artifact and
  // must not become the card frame, or the page just opened sits lower than its neighbours.
  assert.match(strip, /\.width\(this\.layoutState\.cardWidth\)/);
  assert.match(overlay, /snapshotCoverEnabled: this\.isStackLayout\(\) \|\| this\.isHorizontalCardsLayout\(\)/);
  assert.doesNotMatch(overlay, /stripCardFrameByTabId|resolveHorizontalCardFrame|clearStripCardFrames/);
  const layout = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewLayoutViewModel.ets'), 'utf8');
  assert.match(layout, /resolveViewportAspectFrame\(/);
  assert.doesNotMatch(layout, /resolveHorizontalCardFrame|snapshotWidth/);
  // Selection and closing both stop the deck motion first.
  assert.match(overlay, /private selectOverviewTab\(tabId: string/);
  assert.match(overlay, /private stopDeckMotion\(\): void/);
  assert.match(overlay, /this\.deckMotion\.release\(/);
  assert.match(overlay, /postFrameCallback\(new BrowserTabsStackFrameCallback/);
  // The position is seeded once per entry, from the entry target when there is one, and seeding is
  // what latches it: a section switch reseeds through `seedDeckPosition`.
  const seedBody = overlay.slice(overlay.indexOf('private seedDeckPosition('),
    overlay.indexOf('private selectOverviewTab('));
  assert.match(seedBody, /this\.deckPositionSeeded = true/);
  // Anything that interrupts the gesture has to finish the movement.
  assert.match(overlay, /private abortDeckMotion\(\): void \{/);
  assert.match(overlay, /this\.stopDeckMotion\(\);\s*this\.settleDeckToNearestCard\(\);/);
  assert.match(overlay, /this\.abortDeckMotion\(\);/);
  // The deck item key must not include the index, or every later card is rebuilt on a removal.
  assert.doesNotMatch(overlay, /resolveCardIdentityKey\(item\)\}\|\$\{item\.index\}/);
  // The per-frame scalar must not re-run presentation construction.
  assert.match(overlay, /if \(this\.isStackLayout\(\)\) \{\s*return this\.deckItems\.length <= 0;/);
  // Shade and cover are the reference's dark overlay and card-filling screenshot.
  assert.match(overlay, /deckShadeOpacity: this\.isStackLayout\(\)/);
  assert.match(overlay, /snapshotCoverEnabled: this\.isStackLayout\(\)/);
  const card = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabOverviewCard.ets'), 'utf8');
  assert.match(card, /ImageFit\.Cover/);
  assert.match(card, /private buildDeckShadeOverlay\(\)/);
  // The title transition rides on opacity alone. Upstream's per-frame label blur is not ported, so
  // no deck path may reintroduce a title blur radius.
  const item = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserTabOverviewItem.ets'), 'utf8');
  const policySource = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy.ets'), 'utf8');
  assert.doesNotMatch(item, /identityBlurRadius|\.blur\(this\.identity/);
  assert.doesNotMatch(overlay, /identityBlurRadius|titleBlurRadius/);
  // The metrics contract carries no blur field; the header comment may still name upstream's term.
  assert.doesNotMatch(policySource, /titleBlurRadius\s*[,:=]/);
  // Card slots are doubled so the entering morph can hold a slot of its own strictly between the
  // covered card and its successor, instead of becoming one more layer above the whole deck. The
  // holder is inside the deck's own Stack, so its `zIndex` competes with the cards' and not with the
  // cards layer as a whole.
  // A dismissal must never be able to close the deck's touch handling. The gate the cards layer
  // reads is observed state — as a plain field the framework could not see it clear, so the layer
  // stayed on the `HitTestMode` it rendered while the dismissal was in flight and the deck could not
  // be panned until the whole overview was reopened. A pan also finishes a dismissal still in flight,
  // and every gesture path releases the overlay's "a card owns the touch" latch.
  assert.match(overlay, /@State private pendingDeckDismissTabId: string = '';/);
  assert.match(overlay, /private beginDeckDrag\(\): void \{\s*if \(this\.pendingDeckDismissTabId\.length > 0\) \{\s*\/\//);
  assert.match(overlay, /if \(!this\.canInteractWithDeck\(\) \|\| this\.deckSwipeTabId\.length > 0\) \{ return; \}/);
  const latchReleases = item.match(
    /if \(this\.localSwipePhase === 'dismissing'\) \{[\s\S]{0,600}?this\.onSwipeCancel\(this\.tab\.id\);/g) || [];
  assert.equal(latchReleases.length, 2, 'both gesture ends must release the deck latch while leaving');
  assert.match(deck, /this\.buildDeckEntryMorphSlot\(\)/);
  // A card's slot, geometry and layer order come from recorded state, never from the `ForEach` item:
  // a reused node keeps the item it was built with, so reading the index from it left every card on
  // its old slot after a removal and the gap never closed.
  assert.match(deck, /\.zIndex\(this\.resolveDeckCardLayerZIndex\(item\)\)/);
  assert.doesNotMatch(deck, /item\.index/);
  assert.match(deck, /\.zIndex\(this\.resolveDeckEntryMorphLayerZIndex\(\)\)/);
  assert.match(overlay, /private resolveDeckIndex\(item: BrowserTabsFloatingItem\): number \{\s*const slot = this\.deckSlotIndexById\[item\.id\];/);
  assert.match(overlay, /@State private deckSlotIndexById: Record<string, number> = \{\};/);
  assert.match(overlay, /private recordDeckSlots\(items: BrowserTabsFloatingItem\[\]\): void/);
  assert.match(overlay, /this\.recordDeckSlots\(next\);/);
  // The metrics memo follows the recorded slots, not the list order.
  assert.match(overlay, /const slot = this\.resolveDeckIndex\(item\);[\s\S]{0,400}?const key = `\$\{this\.horizontalDeckPosition\}\|\$\{this\.layoutState\.cardWidth\}\|` \+\s*`\$\{this\.deckItemsSignature\}\|\$\{this\.deckSlotSignature\}`;/);
  assert.match(overlay, /this\.stackLayoutPolicy\.resolveCard\(slot, this\.horizontalDeckPosition,/);
  // Clip stays on except during a vertical dismiss flight. Toggling it at the morph handover
  // re-rasterises every card in the same frame the current card is revealed.
  assert.match(deck, /\.clip\(this\.deckSwipeTabId\.length <= 0\)/);
  assert.match(deck, /Stack\(\) \{\s*if \(this\.shouldMountSharedSnapshotInDeck\(\)\) \{\s*this\.buildSharedSnapshotOverlay\(true\)/);
  assert.match(overlay, /private shouldMountSharedSnapshotInDeck\(\): boolean \{[\s\S]{0,400}?return this\.entrySharedSnapshotMounted &&\s*this\.entrySharedSnapshotState\.direction === 'enter' &&/);
  assert.match(overlay, /return slot < 0 \? 0 : slot \* 2 \+ 1;/);
  // The entering morph is the only overlay there is: the deck paints it from its own slot, and every
  // other layout paints it from the root.
  assert.match(overlay, /if \(this\.entrySharedSnapshotMounted && !this\.shouldMountSharedSnapshotInDeck\(\) &&\s*!this\.isStackEntryMorph\(\)\) \{\s*this\.buildSharedSnapshotOverlay\(\)/);
  // In-deck morph must not reuse the overlay-root 20/25 z-index; the slot wrapper owns stacking.
  assert.match(overlay, /snapshotLayerZIndex: inDeck \? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX/);
  // List clip fade is a separate node. Its opacity must not be chained onto the card shrink.
  const listMorph = overlay.slice(overlay.indexOf('private buildListClipSnapshotOverlay'),
    overlay.indexOf('private buildListEntrySurface'));
  const cardMorph = overlay.slice(overlay.indexOf('private buildCoveringSnapshotOverlay'),
    overlay.indexOf('private buildListClipSnapshotOverlay'));
  assert.match(listMorph, /imageBlurExtra: this\.listEntryImageBlur/);
  assert.match(listMorph, /\.opacity\(this\.resolveListEntrySnapshotOpacity\(\)\)/);
  assert.match(cardMorph, /imageBlurExtra: 0/);
  assert.doesNotMatch(cardMorph, /resolveListEntrySnapshotOpacity/);
  assert.match(cardMorph, /\.zIndex\(inDeck \? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX\)/);
  assert.match(overlay, /this\.buildSharedSnapshotOverlay\(true\)/);
  // Waiting snaps to the origin (duration 0). Settling uses the 350ms implicit fly-in. A duration of
  // 0 for the whole displacement made ArkUI snap the derived translate to rest with no motion.
  assert.match(overlay, /if \(!this\.entryDisplacementSettlingEnabled\) \{\s*return 0;/);
  assert.match(overlay, /return this\.animationViewModel\.getSharedSnapshotEnterDurationMs\(\);/);
  // SettlingEnabled dropping must not yank an in-flight displacement back to the origin.
  assert.match(overlay, /if \(this\.entryDisplacementProgress > 0 && this\.entryDisplacementProgress < 1\) \{\s*return;/);
  // In-deck morph already covers the current card; hiding that preview leaves a hole at unmount.
  // The grid and the strip paint the morph above the cards instead, and used to keep the preview
  // at opacity 0 until that overlay unmounted — the card flashed as the shrink finished. Once the
  // overlay is covering the card, the preview stays painted, including the frame the overlay drops
  // before the covered-tab id clears.
  assert.match(overlay, /coveredByMorph: this\.shouldHideCardSurfaceUnderMorph\(item\.tab\.id\)/);
  assert.match(overlay, /if \(this\.shouldMountSharedSnapshotInDeck\(\)\) \{\s*this\.entryMorphPreviewLatchedTabId = '';\s*return false;/);
  assert.match(overlay, /private isEntryMorphOverlayCovering\(tabId: string\): boolean \{[\s\S]*?state\.tabId === tabId/);
  assert.match(overlay, /this\.entryMorphPreviewLatchedTabId === tabId \|\| this\.isEntryMorphOverlayCovering\(tabId\)/);
  // The persisted URI must not be part of the card key. It arrives as the shrink finishes, and a
  // key that changed from the live PixelMap to that file destroyed the card in the handoff frame.
  assert.match(overlay, /hasImage \? 'image' : 'none'/);
  assert.doesNotMatch(overlay, /uri\.length > 0 \? uri : \(hasPixelMap \? 'pm' : 'none'\)/);
  // The predicted entry target must use the painted (scaled) deck preview, not the unscaled layout
  // slot. Landing at 1.0 and then revealing the 0.98 focused card was a visible extra shrink.
  const predicted = overlay.slice(overlay.indexOf('private buildPredictedEntryTargetPreviewRect'),
    overlay.indexOf('private syncLayoutState'));
  assert.match(predicted, /this\.resolveDeckPreviewRect\(targetTabId\)/);
  // The unscaled layout slot must not reappear in the deck's own branch. The strip branch beside it
  // sizes to its own screenshot on purpose, so the check is scoped to the deck.
  const predictedDeck = predicted.slice(predicted.indexOf('if (this.isStackLayout())'));
  assert.doesNotMatch(predictedDeck, /targetWidth = this\.layoutState\.cardWidth/);
  assert.match(overlay, /private buildDeckPreviewRect\(metrics: BrowserTabsOverviewStackCardMetrics\)/);
  const coordinator = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/BrowserTabsOverviewSessionCoordinator.ets'), 'utf8');
  // Morph unmount and the covered-card reveal land in one presentation publish.
  assert.match(coordinator, /sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState\(\),\s*sceneState: this\.sceneDriver\.buildSettledState/);
  assert.match(coordinator, /shouldDeferEntryAnimationSettle\(this\.presentationState\.sceneState\)/);
  // The grid path keeps its own scroller and must not be switched to the deck.
  const grid = overlay.slice(overlay.indexOf('private buildGridCardsLayer'),
    overlay.indexOf('private buildHorizontalCardsLayer'));
  assert.match(grid, /Grid\(this\.scroller\)/);
  assert.doesNotMatch(grid, /resolveDeckMetrics/);
  // Swipe-to-close must fly the card off-screen before unmounting it. Calling `onSwipeEnd` from
  // `endLocalSwipe` removed the ForEach node in the release frame, so the fly-out never painted.
  assert.doesNotMatch(item, /this\.dismissLocalSwipe\([^)]*\);\s*this\.onSwipeEnd/);
  assert.match(item, /private completePendingSwipeDismiss\(\): void/);
  assert.match(item, /this\.onSwipeEnd\(tabId, offset, direction\)/);
  // The flight is as quick as the flick: the duration comes from the release speed, and the node's
  // own implicit animation reads the same value so both clocks agree.
  assert.match(item, /this\.swipeFlyoutDurationMs = this\.swipeDismissPolicy\.resolveFlyoutDurationMs\(\s*Math\.abs\(flyout - swipeOffset\), releaseVelocity\);/);
  assert.match(item, /this\.dismissLocalSwipe\(direction, swipeOffset, releaseVelocity\);/);
  assert.match(item, /private dismissLocalSwipe\(direction: number, swipeOffset: number, releaseVelocity: number\): void/);
  assert.match(item, /duration: this\.swipeFlyoutDurationMs,\s*curve: TAB_OVERVIEW_ITEM_SWIPE_FLYOUT_CURVE/);
  assert.match(item, /\}, this\.swipeFlyoutDurationMs\);/);
  assert.match(item, /if \(this\.localSwipePhase === 'dismissing'\) \{\s*return this\.swipeFlyoutDurationMs;/);
  assert.match(item, /if \(this\.localSwipePhase === 'dismissing'\) \{\s*return TAB_OVERVIEW_ITEM_SWIPE_FLYOUT_CURVE;/);
  assert.doesNotMatch(item, /TAB_OVERVIEW_ITEM_SWIPE_FLYOUT_DURATION_MS/);
  // Remaining cards fill the gap while the closed card is still in the list as a ghost. One
  // animation moves the deck scalar and the recorded slots together, so only the cards the removal
  // actually shifts move, and the committed values are that animation's own end state.
  assert.match(overlay, /private beginDeckDismiss\(tabId: string\): void/);
  assert.match(overlay, /private hasDeckSlotChange\(previousIds: string\[\], nextIds: string\[\], position: number\): boolean/);
  assert.match(overlay, /if \(nextIds\.length <= 0 \|\| !this\.hasDeckSlotChange\(previousIds, nextIds, position\)\) \{\s*this\.commitPendingDeckDismiss\(\);/);
  assert.match(overlay, /animateTo\(\{\s*duration: FLOATING_TABS_REORDER_DURATION_MS,\s*curve: this\.animationViewModel\.getFloatingCardEntryCurve\(\)\s*\}, \(\) => \{\s*this\.horizontalDeckPosition = position;\s*this\.deckSlotIndexById = slots;\s*this\.deckSlotSignature = slotSignature;/);
  assert.match(overlay, /private commitPendingDeckDismiss\(\): void/);
  assert.match(overlay, /this\.scheduleDeckDismissCommit\(\);/);
  assert.match(overlay, /private scheduleDeckDismissCommit\(\): void/);
  assert.match(overlay, /this\.clearDeckDismissCommitTimer\(\);/);
  assert.match(overlay, /swipeFlyoutOffset: this\.usesUpwardCardDismiss\(\) \? this\.resolveRootHeight\(\)/);
  assert.doesNotMatch(overlay, /private playDeckSlotReorder/);
  assert.doesNotMatch(overlay, /settleTo\(/);
});

test('each tab overview style owns a closed entry profile', () => {
  const policyExports = load(
    'AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStyleEntryPolicy.ets',
    name => {
      assert.equal(name, '../BrowserTabsOverviewVisualTokens');
      return {
        BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS: 26,
        BROWSER_TABS_OVERVIEW_LIST_ROW_CORNER_RADIUS: 14
      };
    });
  const policy = new policyExports.BrowserTabsOverviewStyleEntryPolicy();
  const grid = policy.resolve('grid');
  const strip = policy.resolve('horizontal_cards');
  const stack = policy.resolve('stack');
  const list = policy.resolve('list');
  const unknown = policy.resolve('nope');
  for (const card of [grid, strip, unknown]) {
    assert.equal(card.snapshotMotion, 'scale');
    assert.equal(card.pinImageToSource, false);
    assert.equal(card.fadesCoveringSnapshot, false);
    assert.equal(card.paintsEntrySurface, false);
    assert.equal(card.cornerRadius, 26);
  }
  assert.equal(grid.morphHost, 'above_cards');
  assert.equal(strip.morphHost, 'above_cards');
  assert.equal(stack.morphHost, 'deck');
  assert.equal(stack.snapshotMotion, 'scale');
  assert.equal(stack.fadesCoveringSnapshot, false);
  assert.equal(stack.pinImageToSource, false);
  assert.equal(list.morphHost, 'above_cards');
  assert.equal(list.snapshotMotion, 'clip');
  assert.equal(list.pinImageToSource, true);
  assert.equal(list.fadesCoveringSnapshot, true);
  assert.equal(list.paintsEntrySurface, true);
  assert.equal(list.cornerRadius, 14);
  assert.equal(policy.resolve(undefined).style, 'grid');
  const source = fs.readFileSync(path.resolve(__dirname,
    '../AiraBrowser/entry/src/main/ets/core/browser/tabsOverview/BrowserTabsOverviewStyleEntryPolicy.ets'),
    'utf8');
  assert.match(source, /private gridProfile\(\)/);
  assert.match(source, /private horizontalCardsProfile\(\)/);
  assert.match(source, /private stackProfile\(\)/);
  assert.match(source, /private listProfile\(\)/);
  // List-only effects live on the list record alone. A card profile must not grow one by sharing it.
  assert.equal((source.match(/fadesCoveringSnapshot: true/g) || []).length, 1);
  assert.equal((source.match(/pinImageToSource: true/g) || []).length, 1);
  assert.equal((source.match(/paintsEntrySurface: true/g) || []).length, 1);
  assert.equal((source.match(/morphHost: 'deck'/g) || []).length, 1);
  assert.equal((source.match(/snapshotMotion: 'clip'/g) || []).length, 1);
});
