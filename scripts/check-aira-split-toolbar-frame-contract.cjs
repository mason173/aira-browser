/**
 * Split toolbar frame contract.
 *
 * The split chrome is a hard-edged phone frame: the web page lives between the address row and
 * the bottom row, never behind one of them. That holds only while
 *
 *   1. the reserve the web viewport takes is at least the height each row actually paints,
 *   2. the chrome rows stacked above the page (the quick search row) add their own height instead
 *      of trading it for the address row, and
 *   3. the reserve follows the rows that are on screen instead of the status bar or the keyboard.
 */
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const root = path.resolve(__dirname, '..');
const sourceRoot = path.join(root, 'AiraBrowser/entry/src/main/ets');
const cache = new Map();

function load(relativePath) {
  const filename = path.join(sourceRoot, relativePath);
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module,
    exports: module.exports,
    require(specifier) {
      if (!specifier.startsWith('.')) return {};
      return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), `${specifier}.ets`)));
    }
  }, { filename });
  cache.set(filename, module.exports);
  return module.exports;
}

const policy = load('core/browser/BrowserToolbarChromeStylePolicy.ets');
const shellSource = fs.readFileSync(path.join(sourceRoot, 'app/pages/BrowserShellPage.ets'), 'utf8');
const splitChromeSource = fs.readFileSync(
  path.join(sourceRoot, 'app/components/browser/BrowserSplitToolbarChrome.ets'), 'utf8');

const CONTENT_GAP_VP = 16;
const QUICK_SEARCH_ROW_VP = 48;
// A phone whose status bar strip is taller than the reported cutout, which is where a strip-based
// reserve falls short of the row painted over it.
const STATUS_BAR_STRIPS_VP = [0, 16, 52, 72];
const SAFE_INSETS_VP = [0, 24, 36, 48, 60];
const BOTTOM_INSETS_VP = [0, 12, 34];
const STACKED_CHROME_HEIGHTS_VP = [0, QUICK_SEARCH_ROW_VP];

function buildReserve(statusBarStripVp, statusBarVisible, stackedChromeHeightVp, addressRowPainted) {
  return policy.resolveSplitToolbarWebReserve({
    statusBarStripVp: statusBarStripVp,
    statusBarVisible: statusBarVisible,
    stackedChromeHeightVp: stackedChromeHeightVp,
    addressRowSafeInsetVp: 36,
    bottomRowSafeInsetVp: 12,
    contentGapVp: CONTENT_GAP_VP,
    addressRowPainted: addressRowPainted,
    bottomRowPainted: true
  });
}

for (const safeInsetVp of SAFE_INSETS_VP) {
  const rowHeightVp = policy.resolveSplitToolbarTopRowHeightVp(safeInsetVp);
  const reserveVp = policy.resolveSplitToolbarTopRowReserveVp(safeInsetVp, CONTENT_GAP_VP);
  assert.ok(reserveVp >= rowHeightVp,
    `The address row paints ${rowHeightVp}vp with a ${safeInsetVp}vp safe inset, but the page only ` +
    `reserves ${reserveVp}vp: the page top would sit behind the row`);
}

for (const safeInsetVp of BOTTOM_INSETS_VP) {
  const rowHeightVp = policy.resolveSplitToolbarBottomRowHeightVp(safeInsetVp);
  const reserveVp = policy.resolveSplitToolbarBottomReserveVp(safeInsetVp);
  assert.ok(reserveVp >= rowHeightVp,
    `The bottom row paints ${rowHeightVp}vp with a ${safeInsetVp}vp gesture inset, but the page only ` +
    `reserves ${reserveVp}vp: the page bottom would sit behind the row`);
}

// The row itself is the source of the reserve: the page top meets the painted row bottom.
assert.equal(
  policy.SPLIT_TOOLBAR_ADDRESS_BLOCK_VP,
  policy.SPLIT_TOOLBAR_PILL_ROW_VP + policy.SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP,
  'The address block must be the painted row, so the page top meets the address row bottom');
assert.ok(splitChromeSource.includes('SPLIT_TOOLBAR_PILL_ROW_VP') &&
  splitChromeSource.includes('SPLIT_TOOLBAR_TOP_ROW_BOTTOM_GAP_VP'),
  'The painted row height and its under-pill gap must come from the same policy constants the reserve uses');

for (const statusBarStripVp of STATUS_BAR_STRIPS_VP) {
  for (const statusBarVisible of [true, false]) {
    for (const stackedChromeHeightVp of STACKED_CHROME_HEIGHTS_VP) {
      for (const safeInsetVp of SAFE_INSETS_VP) {
        const reserve = policy.resolveSplitToolbarWebReserve({
          statusBarStripVp: statusBarStripVp,
          statusBarVisible: statusBarVisible,
          stackedChromeHeightVp: stackedChromeHeightVp,
          addressRowSafeInsetVp: safeInsetVp,
          bottomRowSafeInsetVp: 12,
          contentGapVp: CONTENT_GAP_VP,
          addressRowPainted: true,
          bottomRowPainted: true
        });
        // The page and every stacked chrome row sit below the painted address row.
        assert.ok(reserve.topVp - stackedChromeHeightVp >=
        policy.resolveSplitToolbarTopRowHeightVp(safeInsetVp),
        `A painted address row (safe ${safeInsetVp}vp, strip ${statusBarStripVp}vp, status bar visible=` +
        `${statusBarVisible}, stacked ${stackedChromeHeightVp}vp) must keep its whole height below the ` +
        `stacked chrome, got ${reserve.topVp - stackedChromeHeightVp}vp`);
        assert.ok(reserve.bottomVp >= policy.resolveSplitToolbarBottomRowHeightVp(12),
          'A painted bottom row must keep its whole height reserved');
      }
      // The stacked chrome row keeps its own height: it must never be traded for the address row.
      const withoutStacked = buildReserve(statusBarStripVp, statusBarVisible, 0, true);
      const withStacked = buildReserve(statusBarStripVp, statusBarVisible, QUICK_SEARCH_ROW_VP, true);
      assert.equal(withStacked.topVp - withoutStacked.topVp, QUICK_SEARCH_ROW_VP,
        `The quick search row must add its ${QUICK_SEARCH_ROW_VP}vp to the reserve (strip ${statusBarStripVp}vp, ` +
        `status bar visible=${statusBarVisible}), instead of replacing the address row clearance`);
    }
  }
}

// Rows that left the frame release their edge, including the whole page behind a hidden status bar.
assert.equal(buildReserve(52, false, 0, false).topVp, 0,
  'A page whose address row and status bar both left keeps the full top');
assert.equal(buildReserve(36, true, 0, false).topVp, 36 + CONTENT_GAP_VP,
  'A page whose address row left still clears the visible status bar strip and the floating gap');
assert.equal(buildReserve(52, false, QUICK_SEARCH_ROW_VP, false).topVp, QUICK_SEARCH_ROW_VP,
  'A visible quick search row keeps its height even when nothing else is above the page');

// A painted split row is an opaque row: the page clears that row and nothing else. Re-adding the
// floating strip gap on top of it is what leaves the wide empty band under the address row.
for (const statusBarStripVp of STATUS_BAR_STRIPS_VP) {
  for (const safeInsetVp of SAFE_INSETS_VP) {
    for (const statusBarVisible of [true, false]) {
      const reserve = policy.resolveSplitToolbarWebReserve({
        statusBarStripVp: statusBarStripVp,
        statusBarVisible: statusBarVisible,
        stackedChromeHeightVp: 0,
        addressRowSafeInsetVp: safeInsetVp,
        bottomRowSafeInsetVp: 12,
        contentGapVp: CONTENT_GAP_VP,
        addressRowPainted: true,
        bottomRowPainted: true
      });
      const expectedTopVp = Math.max(statusBarVisible ? statusBarStripVp : 0, safeInsetVp) +
        policy.SPLIT_TOOLBAR_ADDRESS_BLOCK_VP;
      assert.equal(reserve.topVp, expectedTopVp,
        `A painted address row (strip ${statusBarStripVp}vp, safe ${safeInsetVp}vp, status bar ` +
        `visible=${statusBarVisible}) must clear the row itself and not the floating content gap, ` +
        `expected ${expectedTopVp}vp, got ${reserve.topVp}vp`);
      const emptyBandVp = reserve.topVp - policy.resolveSplitToolbarTopRowHeightVp(safeInsetVp);
      const stripOverflowVp = Math.max(0, (statusBarVisible ? statusBarStripVp : 0) - safeInsetVp);
      assert.equal(emptyBandVp, stripOverflowVp,
        `The page top must meet the painted address row (strip ${statusBarStripVp}vp, safe ` +
        `${safeInsetVp}vp, status bar visible=${statusBarVisible}), got an extra ` +
        `${emptyBandVp - stripOverflowVp}vp`);
    }
  }
}

// The shell must resolve both edges through that policy, and must not fall back to a strip-based
// or keyboard-cancelled reserve while a row is still painted.
assert.ok(shellSource.includes('resolveSplitToolbarWebReserve('),
  'The shell web viewport must take its split reserves from the split frame policy');
assert.ok(shellSource.includes('stackedChromeHeightVp: this.quickSearchSwitchingPresentation.occupiedHeightPx'),
  'The quick search row must enter the reserve as stacked chrome height');
assert.ok(!shellSource.includes('visibleTopInsetPx + SPLIT_TOOLBAR_ADDRESS_BLOCK_VP'),
  'The address block must not be added to the status bar strip alone: that reserve can be shorter than the row');
assert.ok(!shellSource.includes('SPLIT_TOOLBAR_BOTTOM_BAR_VP + this.homeBottomSafeInsetVp'),
  'The bottom reserve must not be rebuilt inline next to the policy that owns the row height');
assert.ok(shellSource.includes("this.reconcileSplitToolbarViewportReserve('quick-search-row')"),
  'A quick search row that appears or leaves must move the split frame with it');

console.log('split toolbar frame contract: ok');
