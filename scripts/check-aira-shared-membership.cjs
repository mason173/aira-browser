'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const project = path.resolve(__dirname, '../AiraBrowser');
function fixture() {
  let community = false;
  const cache = new Map();
  const strings = new Map(JSON.parse(fs.readFileSync(path.join(project, 'entry/src/main/resources/base/element/string.json'))).string.map(row => [row.name, row.value]));
  const resource = (name, ...args) => ({ name, args });
  const text = value => typeof value === 'string' ? value : (strings.get(value.name.replace('app.string.', '')) || value.name).replace(/%([0-9]+)\$[sd]/g, (_m, index) => String(value.args[Number(index) - 1]));
  const mocks = {
    'core/resources/AppResourceText': { resolveAppResourceText: text },
    'common/config/AiraDistributionCapabilityOwner': { AIRA_DISTRIBUTION_CAPABILITY_OWNER: { isCommunity: () => community, isAvailable: () => !community } },
    'core/browser/BrowserProfileBoundaryService': { BrowserProfileBoundaryService: class { buildBoundary(input) { return input; } } },
    'services/privacy/BrowserPrivacyEffectPolicyService': { BrowserPrivacyEffectPolicyService: class { decide(input) { return { outcome: input.requestingBoundary.privacyMode === 'regular' && input.requestingBoundary.dataScope === 'profile_persistent' ? 'allow' : 'deny' }; } } }
  };
  function load(file) {
    if (cache.has(file)) return cache.get(file);
    const exports = {}; cache.set(file, exports);
    const source = fs.readFileSync(file, 'utf8');
    vm.runInNewContext(ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText, {
      exports, $r: resource, Date,
      require(name) {
        if (name === 'design') return { ...load(path.join(project, 'design/src/main/ets/components/JuMembershipModels.ets')), JuSettingItem: class { constructor(key, title) { Object.assign(this, { key, title, enabled: true }); } } };
        if (name === 'kitapp-membership') return load(path.join(project, 'membership/src/main/ets/KitappMembershipData.ets'));
        const target = path.resolve(path.dirname(file), name) + '.ets';
        const relative = path.relative(path.join(project, 'entry/src/main/ets'), target).replace(/\.ets$/, '');
        return mocks[relative] || load(target);
      }
    });
    return exports;
  }
  const model = load(path.join(project, 'entry/src/main/ets/core/membership/AiraProOverviewViewModel.ets'));
  const catalog = load(path.join(project, 'entry/src/main/ets/core/membership/AiraProMembershipCatalog.ets'));
  const product = load(path.join(project, 'membership/src/main/ets/KitappMembershipData.ets'));
  const member = { userId: 'fixture', plan: 'guest', planExpiresAt: 0, subscriptionStatus: 'none', subscriptionProductId: '', accountRecognition: 'none', accessFlags: [], accountFirstSeenAt: 0, accountLastSeenAt: 0, lastSyncedAt: 0, updatedAt: 0 };
  function present(patch = {}, privacy = 'regular', price = '') {
    const state = new model.AiraProOverviewViewModel().buildState({ ...member, ...patch }, 'profile_persistent', privacy, price);
    return { state, offer: catalog.createAiraProMembershipOffer(state), actions: catalog.createAiraProMembershipActions(state) };
  }
  return { present, product, community() { community = true; } };
}
test('free users keep the live lifetime price, both subscriptions, redemption and claim', () => {
  const f = fixture(), result = f.present({}, 'regular', 'CNY 48.00');
  assert.equal(result.offer.price, '¥48');
  assert.equal(result.offer.actionEnabled, true);
  assert.equal(result.offer.features.length, 4);
  for (const key of ['plan:monthly', 'plan:yearly', 'redeem', 'claim', 'membership_terms', 'auto_renewal_terms', 'self_hosting']) assert(result.actions.some(row => row.key === key));
  const suite = f.product.fixedKitappSuite();
  assert.equal(suite.apps.length, 5); assert.equal(suite.offer.price, '¥68.8');
  assert.equal(suite.apps.find(row => row.key === 'glimmerclock').price, '¥18.00');
});
test('timed gifts can upgrade; permanent rights disable purchase and code redemption', () => {
  const f = fixture();
  assert.equal(f.present({ plan: 'pro', planExpiresAt: Date.now() + 86400000 }).offer.actionEnabled, true);
  const permanent = f.present({ plan: 'pro', planExpiresAt: 0 });
  assert.equal(permanent.offer.actionEnabled, false);
  assert(!permanent.actions.some(row => row.key.startsWith('plan:') || row.key === 'redeem' || row.key === 'claim'));
});
test('subscribers keep subscription management and the lifetime upgrade', () => {
  const f = fixture();
  for (const status of ['active', 'grace_period', 'cancelled', 'unknown']) {
    const result = f.present({ plan: 'pro', planExpiresAt: Date.now() + 86400000, subscriptionStatus: status, subscriptionProductId: 'aira_pro_monthly' });
    assert(result.actions.some(row => row.key === 'manage_subscription' && row.enabled));
    assert.equal(result.offer.actionEnabled, true);
    assert(!result.actions.some(row => row.key.startsWith('plan:')));
  }
});
test('private boundaries disable every paid/account action; Community has no paid plans', () => {
  const f = fixture(), privatePage = f.present({}, 'private');
  assert.equal(privatePage.offer.actionEnabled, false); assert(privatePage.actions.every(row => !row.enabled));
  f.community(); const community = f.present();
  assert.equal(community.state.plans.length, 0); assert.equal(community.offer.actionEnabled, false);
});
