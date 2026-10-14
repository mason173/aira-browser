#!/usr/bin/env node
'use strict';

// Exercise the production permission coordinator, policy, identity, and system
// permission services. Only OS APIs, persistence, and UI effects are substituted.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function fixture({ rule = 'allow', approximate = true, precise = true, locationEnabled = true,
  saveFails = false, systemFails = false } = {}) {
  const modules = new Map();
  const effects = [];
  const lookups = [];
  const relatedOrigins = [];
  const writes = [];
  let systemRequests = 0;
  const manager = {
    checkAccessTokenSync(_token, permission) {
      return (permission === 'ohos.permission.APPROXIMATELY_LOCATION' ? approximate : precise) ? 0 : -1;
    },
    async requestPermissionsFromUser(_context, permissions) {
      systemRequests++;
      if (systemFails) throw new Error('synthetic OS error');
      return { permissions, authResults: permissions.map(p => manager.checkAccessTokenSync(1, p)),
        dialogShownResults: permissions.map(() => false) };
    }
  };
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative);
    const filename = path.join(root, relative);
    const module = { exports: {} };
    modules.set(relative, module.exports);
    const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
    }).outputText;
    vm.runInNewContext(code, { module, exports: module.exports, $r: value => value, require(name) {
      if (name === '@kit.AbilityKit') return { abilityAccessCtrl: {
        GrantStatus: { PERMISSION_GRANTED: 0, PERMISSION_DENIED: -1 }, createAtManager: () => manager
      } };
      if (name === '@kit.LocationKit') return { geoLocationManager: { isLocationEnabled: () => locationEnabled } };
      if (name === '@kit.ArkWeb') return { webview: {} };
      if (name === '@ohos.url') return { default: { URL: { parseURL: value => new URL(value) } } };
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (name.endsWith('/BrowserModels')) return { DEFAULT_BROWSER_PROFILE_ID: 'default' };
      if (name.endsWith('/BrowserProfileBoundaryService')) return {
        BrowserProfileBoundaryService: class { resolveSitePermissionScope() { return 'profile_persistent'; } }
      };
      if (!name.startsWith('.')) throw new Error(`Unexpected dependency: ${name}`);
      return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
    } }, { filename });
    return module.exports;
  }
  const { SitePolicyService } = load('services/web/SitePolicyService.ets');
  const sitePolicyService = new SitePolicyService({
    getSitePermissionSettings(origin) {
      lookups.push(origin);
      return { primaryOrigin: origin, location: rule, camera: 'ask', microphone: 'ask',
        sensor: 'ask', clipboard: 'ask', updatedAt: 1 };
    },
    async updateSitePermissionRule(origin, kind, value) {
      if (saveFails) throw new Error('synthetic persistence error');
      writes.push({ origin, kind, value });
      return { primaryOrigin: origin, location: value, updatedAt: 1 };
    }
  });
  const { WebPermissionCoordinator } = load('core/web/WebPermissionCoordinator.ets');
  const coordinator = new WebPermissionCoordinator({
    sitePolicyService,
    browserFaultClassifier: { classifyPermissionDenied: message => ({ userMessage: message }) },
    tabScopedEventContextCoordinator: { resolveProfileId: () => 'default', resolveDataScope: () => 'profile_persistent' },
    siteControlsRuntimeCoordinator: { addRelatedOrigin: origin => relatedOrigins.push(origin),
      applyPersistedPermissionSettings() {} },
    siteInteractionLogicService: { getDisplayOrigin: origin => origin },
    backgroundSessionSyncCoordinator: { protect() {}, release() {} },
    systemSettingsLaunchService: {},
    sink: {
      resolveAbilityContext: () => ({ applicationInfo: { accessTokenId: 1 } }),
      resolveCurrentSiteOrigin: () => 'https://map.baidu.com',
      applyEffect: effect => effects.push(effect)
    }
  });
  function request(origin) {
    const calls = [];
    coordinator.handleGeolocationPermissionRequest('tab-map', {
      origin, geolocation: { invoke: (...args) => calls.push(args) }
    });
    return calls;
  }
  return { coordinator, request, effects, lookups, relatedOrigins, writes, systemRequests: () => systemRequests };
}

const settle = () => new Promise(resolve => setImmediate(resolve));

test('allowed Baidu Map location completes with the exact ArkWeb request origin', async () => {
  const f = fixture();
  const calls = f.request('https://map.baidu.com/');
  await settle();
  assert.deepEqual(calls, [['https://map.baidu.com/', true, false]],
    'ArkWeb must receive its original origin index even when the site policy uses a canonical origin');
  assert.ok(f.lookups.every(origin => origin === 'https://map.baidu.com'));
  assert.equal(f.systemRequests(), 0, 'in-use authorization must not require another system prompt');
});

test('approximate-only location authorization is sufficient', async () => {
  const f = fixture({ precise: false });
  const calls = f.request('https://map.baidu.com');
  await settle();
  assert.deepEqual(calls, [['https://map.baidu.com', true, false]]);
  assert.equal(f.systemRequests(), 0);
});

test('site denial and disabled system location still reject the request', async () => {
  for (const options of [{ rule: 'block' }, { locationEnabled: false }, { approximate: false, precise: false }]) {
    const f = fixture(options);
    const calls = f.request('https://map.baidu.com');
    await settle();
    assert.deepEqual(calls, [['https://map.baidu.com', false, false]]);
  }
});

test('all prompted decisions preserve the callback origin and canonical persistence key', async () => {
  for (const [action, allowed, savedRule] of [
    ['allowPendingPermissionForSession', true],
    ['allowPendingPermissionDuringUse', true, 'allow'],
    ['denyPendingPermission', false, 'block'],
    ['dismissPendingPermissionPrompt', false]
  ]) {
    const f = fixture({ rule: 'ask' });
    const calls = f.request('https://map.baidu.com/');
    assert.equal(f.coordinator.hasPendingPrompt(), true);
    assert.deepEqual(calls, []);
    await f.coordinator[action]();
    await settle();
    assert.deepEqual(calls, [['https://map.baidu.com/', allowed, false]], action);
    assert.deepEqual(f.writes, savedRule ? [
      { origin: 'https://map.baidu.com', kind: 'location', value: savedRule }
    ] : []);
  }
});

test('persistence and OS errors deny with the original callback origin', async () => {
  for (const options of [
    { rule: 'ask', saveFails: true },
    { approximate: false, precise: false, systemFails: true },
    { locationEnabled: false }
  ]) {
    const f = fixture(options);
    const calls = f.request('https://map.baidu.com/');
    if (options.rule === 'ask') await f.coordinator.allowPendingPermissionDuringUse();
    await settle();
    assert.deepEqual(calls, [['https://map.baidu.com/', false, false]]);
    assert.equal(f.coordinator.hasPendingPrompt(), false);
    assert.equal(f.effects.filter(effect => effect.type === 'permission_flow_state').at(-1).active, false);
  }
});
