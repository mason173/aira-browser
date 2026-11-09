'use strict';
// Replay the compiler-emitted host. No device or screen interaction.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const project = path.resolve(__dirname, '../AiraBrowser');
const relative = 'entry/src/main/ets/app/components/membership/AiraProScreen';
const source = path.join(project, relative + '.ets');
const emitted = path.join(project, 'entry/build/default/cache/default/default@CompileArkTS/esmodule/debug', relative + '.ts');
assert(fs.statSync(emitted).mtimeMs >= fs.statSync(source).mtimeMs, 'Rebuild the current Aira host first');
const components = [];
class ViewPU {
  finalizeConstruction() {}
  observeComponentCreation2(callback) { callback(1, true); }
  ifElseBranchUpdateFunction(_index, callback) { callback(); }
  static create(component) { components.push(component); if (component.name === 'SettingsHdsScaffold' && component.params.showTitleBar === false) component.params.content(); }
}
const stub = name => class { constructor(_parent, params) { this.name = name; this.params = params; } };
let official = true;
const product = { KitappMembershipPage: stub('KitappMembershipPage'), createKitappAppOffer: () => ({}), KITAPP_CONTACT_EMAIL: 'fixture@example.com' };
const noOp = new Proxy({}, { get: () => () => {} });
const enums = new Proxy({}, { get: (_target, key) => key });
const output = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(emitted, 'utf8'), { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText, {
  exports: output, ViewPU, $r: name => name, getContext: () => ({}),
  require(name) {
    if (name.includes('kitapp-membership')) return product;
    if (name.includes('HuaweiIapProductCatalog')) return { AIRA_SUITE_LIFETIME_PLAN_ID: 'suite_lifetime' };
    if (name.includes('AiraDistributionCapabilityOwner')) return { AIRA_DISTRIBUTION_CAPABILITY_OWNER: { isOfficial: () => official, isCommunity: () => !official } };
    if (name.includes('DesktopDialogSheetChrome')) return { applyDesktopDialogSheetChrome: options => options };
    if (name.includes('kit.ArkUI') || name.includes('arkui.StateManagement')) return { ComponentActive() {}, ComponentInactive() {} };
    return new Proxy({}, { get: (_target, key) => stub(key) });
  },
  Column: noOp, Row: noOp, Stack: noOp, If: noOp, __Common__: noOp,
  SafeAreaType: enums, SafeAreaEdge: enums, SheetType: enums, SheetSize: enums,
  Alignment: enums, FlexAlign: enums
});
const screen = Object.create(output.AiraProScreen.prototype);
const values = {
  presentationMode: 'page', pageLayoutMode: 'phone', membershipMounted: true,
  membershipActive: true, membershipPaymentBusy: false, activeSheetVisible: false, suiteOwned: false,
  activeSheetKind: 'none', membershipOffer: { name: 'Aira Pro', price: '¥68.8' },
  membershipActions: [{ key: 'plan:monthly', enabled: true }],
  state: { title: 'Fixture', proActionsEnabled: true, showManageSubscription: true, plans: [{ id: 'monthly', action: 'purchase' }] },
  theme: {}, contentScroller: {}, storedFloatingSurfaceColor: 'surface'
};
for (const [key, value] of Object.entries(values)) Object.defineProperty(screen, key, { value, writable: true });
const calls = [];
screen.openProPurchase = plan => calls.push('purchase:' + plan);
screen.restorePurchase = () => calls.push('restore');
screen.restorePurchaseForPlan = plan => calls.push('restore:' + plan);
screen.openSubscriptionManagement = () => calls.push('manage');
screen.openSharedLegalDocument = id => calls.push(id);
screen.navigationCoordinator = { back() { calls.push('back'); } };
screen.buildPageSurface();
let page = components.find(item => item.name === 'KitappMembershipPage');
assert(page, 'Official phone page uses the public product directly');
const safeFrame = components.find(item => item.name === 'SettingsHdsScaffold');
assert(safeFrame && safeFrame.params.showTitleBar === false && safeFrame.params.useTopSafeInset === true, 'Official membership lost Aira fullscreen top-safe-inset owner; navigation title can start in status bar');
assert.equal(safeFrame.params.contentKind, 'unframed');
assert.equal(page.params.asDestination, true, 'Nested membership must inherit the measured top safe area, without root top-layout expansion');
assert.equal(page.params.suitePurchaseEnabled, true, 'Aira suite checkout must use native IAP rather than the Kitapp store fallback');
assert.equal(page.params.app, values.membershipOffer);assert.equal(page.params.suiteOwned,false);
page.params.onPurchase(); page.params.onOpenSuite(); page.params.onRestore(false); page.params.onRestore(true);
page.params.onAppAction('plan:monthly'); page.params.onAppAction('manage_subscription');
assert.deepEqual(calls, ['purchase:one_time', 'purchase:suite_lifetime', 'restore', 'restore:suite_lifetime', 'purchase:monthly', 'manage']);
for (const [key, value] of [['membershipPaymentBusy', true], ['membershipActive', false], ['membershipMounted', false]]) {
  const previous = screen[key]; screen[key] = value;
  page.params.onAppAction('plan:monthly'); screen[key] = previous;
}
page.params.onAppAction('plan:unknown'); assert.equal(calls.length, 6);
components.length = 0; screen.suiteOwned=true; screen.activeSheetVisible = true; screen.buildSharedMembership();
page = components.find(item => item.name === 'KitappMembershipPage'); assert.equal(page.params.active, false);assert.equal(page.params.suiteOwned,true,'Server-owned suite state updates the retained shared product');
components.length = 0; official = false; screen.buildPageSurface();
assert(!components.some(item => item.name === 'KitappMembershipPage'), 'Community never renders the paid product');
assert(components.some(item => item.name === 'SettingsHdsScaffold'));
console.log('PASS SDK Aira host: one Official shell, current offer, lifetime/subscription/management/store/recovery callbacks, busy/hidden/disposed guards, covered-sheet pause and Community separation. No device UI.');

(async () => {
  // Run the actual emitted purchase/restore methods against a deferred coordinator.
  let release; let starts = 0; let restores = 0;
  screen.membershipMounted = true; screen.membershipActive = true; screen.membershipPaymentBusy = false;
  screen.getHuaweiUid = () => 'fixture-account';
  screen.buildAiraProDataBoundaryInput = () => ({ dataScope: 'profile_persistent', privacyMode: 'regular' });
  screen.purchaseFlowHost = {};
  screen.purchaseCoordinator = {
    startPurchaseFlow(_context, plan) { assert.equal(plan, 'one_time'); starts++; return new Promise(resolve => { release = resolve; }); },
    restorePurchaseFlow() { restores++; return new Promise(resolve => { release = resolve; }); }
  };
  const purchase = output.AiraProScreen.prototype.openProPurchase;
  const restore = output.AiraProScreen.prototype.restorePurchaseForPlan;
  purchase.call(screen, 'one_time'); restore.call(screen, 'one_time'); purchase.call(screen, 'one_time');
  assert.equal(starts, 1); assert.equal(restores, 0); assert.equal(screen.membershipPaymentBusy, true);
  release(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(screen.membershipPaymentBusy, false);
  restore.call(screen, 'one_time'); purchase.call(screen, 'one_time'); assert.equal(starts, 1); assert.equal(restores, 1);
  release(); await new Promise(resolve => setImmediate(resolve));
  screen.membershipMounted = false;
  purchase.call(screen, 'one_time'); restore.call(screen, 'one_time'); assert.equal(starts, 1); assert.equal(restores, 1);
  console.log('PASS SDK host payment flight: checkout and restore block each other through completion, reset after success and reject disposed callbacks.');
})().catch(error => { console.error(error); process.exitCode = 1; });
