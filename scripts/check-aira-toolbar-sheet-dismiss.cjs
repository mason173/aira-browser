const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const ts = require('./lib/deveco-typescript.cjs');
const sourcePath = path.resolve(__dirname,
  '../AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets');
const source = fs.readFileSync(sourcePath, 'utf8');

// Execute the real Sheet adapter methods without the ArkUI builders. This checks the application's
// callback/binding contract; rendering, native animation and gesture arbitration still need a device.
function method(name) {
  const start = source.indexOf(`  private ${name}(`);
  const end = source.indexOf('\n  }', start);
  assert.ok(start >= 0 && end > start, `Missing Sheet adapter method: ${name}`);
  return source.slice(start, end + 4);
}

const moduleUnderTest = { exports: {} };
// The Sheet state machine pulls in its presentation helpers, so extract those real bodies too. Only the
// leaves that need ArkUI measurement or a view model are stubbed on the host below.
const methods = ['buildToolbarSystemSheetOptions', 'openToolbarSystemSheet',
  'handleToolbarSystemSheetDisappear', 'resetToolbarAddSheet', 'closeToolbarAddSheet',
  'exitToolbarSystemSheetEditing', 'syncToolbarSheetDisplayedActions',
  'lockToolbarSystemSheetPresentation', 'clearToolbarSystemSheetPresentationLock',
  'resetQuickActionReorderState', 'resolveToolbarSystemSheetContentWidth'].map(method).join('\n');
vm.runInNewContext(ts.transpileModule(
  `class SheetAdapter {\n${methods}\n}\nmodule.exports = SheetAdapter;`, {
    compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
  }).outputText, {
  module: moduleUnderTest,
  SheetType: { BOTTOM: 'bottom' },
  ScrollSizeMode: { CONTINUOUS: 'continuous' },
  BlurStyle: { NONE: 'none' },
  RenderStrategy: { OFFSCREEN: 0 },
  DismissReason: { PRESS_BACK: 0, TOUCH_OUTSIDE: 1, SLIDE_DOWN: 2 },
  Curve: { EaseIn: 0 },
  hilog: { info() {} },
  ROUTE_ACTION_DIAGNOSTIC_LOG_DOMAIN: 0,
  ROUTE_ACTION_DIAGNOSTIC_LOG_TAG: 'test',
  ROUTE_ACTION_DIAGNOSTIC_PREFIX: 'test'
}, { filename: sourcePath });

function createHost() {
  const adapter = new moduleUnderTest.exports();
  const events = [];
  let previewHeight = 240;
  Object.assign(adapter, {
    toolbarSystemSheetVisible: false,
    toolbarSystemSheetDetentSelection: 0,
    toolbarSystemSheetInstanceToken: 7,
    responsiveState: { aspectBreakpoint: 'narrow' },
    storedPageBackgroundColor: '#FFFFFF',
    hasQuickActionSlotsAvailable: () => true,
    resolveToolbarRenderSnapshot: () => ({ layoutState: {} }),
    resolveToolbarSystemSheetPreviewHeight: () => previewHeight,
    resolveToolbarSystemSheetFullHeight: () => 480,
    // Presentation-measurement and action-sync leaves: platform/ViewModel-backed, and irrelevant to the
    // dismissal-vs-resubmission contract this check guards.
    resolveFloatingQuickActionLayoutWidth: () => 320,
    resolveToolbarSystemSheetHostWidth: () => 320,
    toolbarSystemSheetResponsiveViewModel: { buildState: () => ({ surfaceMaxWidth: 320 }) },
    resolveToolbarSheetVisibleActions: () => [],
    resolveToolbarParkedActions: () => [],
    replaceObservedActions: () => {},
    resolveToolbarSystemSheetPresentedLayoutState: () => ({}),
    resolveToolbarSystemSheetPresentedLayoutKey: () => 'locked',
    measureToolbarSystemSheetPreviewHeight: () => 240,
    measureToolbarSystemSheetFullHeight: () => 480,
    clearQuickActionDragClickGuard: () => {},
    onToolbarSystemSheetOpened: (token) => events.push(`opened:${token}`),
    onToolbarSystemSheetDismissed: (token) => events.push(`dismissed:${token}`),
    onAction: (id) => events.push(`action:${id}`)
  });
  adapter.openToolbarSystemSheet();
  return {
    adapter,
    events,
    // A scrolling page can publish a new bottom-panel layout while native dismissal is in flight.
    redraw() {
      previewHeight += 1;
      return { show: adapter.toolbarSystemSheetVisible, options: adapter.buildToolbarSystemSheetOptions() };
    }
  };
}

for (const reason of ['TOUCH_OUTSIDE', 'BACK_PRESSED', 'SLIDE_DOWN']) {
  test(`${reason}: scrolling during dismissal must not resubmit an open Sheet`, () => {
    const host = createHost();
    const options = host.adapter.buildToolbarSystemSheetOptions();
    let nativeDismissals = 0;
    let springbacks = 0;
    const dismiss = () => { nativeDismissals += 1; };
    // ArkUI defaults to a springback for a drag when an interactive-dismiss handler is installed.
    if (reason === 'SLIDE_DOWN' && options.onWillDismiss) {
      if (options.onWillSpringBackWhenDismiss) {
        options.onWillSpringBackWhenDismiss({ springBack: () => { springbacks += 1; } });
      } else {
        springbacks += 1;
      }
    }
    if (options.onWillDismiss) {
      options.onWillDismiss({ reason, dismiss });
    } else {
      dismiss();
    }
    // Do not simulate the end-of-animation $$ update yet: this is the reported race window.
    for (let frame = 0; frame < 5; frame += 1) {
      assert.equal(host.redraw().show, false,
        'a page-scroll redraw resubmitted show=true before native dismissal finished');
    }
    assert.equal(nativeDismissals, 1, 'interactive dismissal must continue through ArkUI');
    assert.equal(springbacks, 0, 'drag dismissal must not introduce a bounce back to the open detent');
    assert.deepEqual(host.events, ['opened:7'], 'owner cleanup must wait for native disappearance');
    options.onDisappear();
    assert.deepEqual(host.events, ['opened:7', 'dismissed:7']);
    assert.equal(host.adapter.openToolbarSystemSheet(), true);
    assert.equal(host.redraw().show, true, 'a subsequent deliberate open must still work');
  });
}

test('a deferred toolbar action still runs only after the native Sheet disappears', () => {
  const host = createHost();
  host.adapter.pendingToolbarSystemSheetAction = { id: 'translate' };
  host.adapter.toolbarActionTapStartedAt = Date.now();
  host.adapter.toolbarSystemSheetVisible = false;
  const options = host.redraw().options;
  assert.deepEqual(host.events, ['opened:7']);
  options.onDisappear();
  assert.deepEqual(host.events, ['opened:7', 'dismissed:7', 'action:translate']);
  options.onDisappear();
  assert.equal(host.events.filter((event) => event === 'action:translate').length, 1);
});
