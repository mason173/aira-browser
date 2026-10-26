// Execute production UA policy with in-memory preferences and a fake ArkWeb boundary.
// No page scripts are injected and no device or network access is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const nativeUA = 'Fixture-Native-ArkWeb';
const logKit = { hilog: { info() {}, warn() {}, error() {} } };

function load(relative, dependencies = {}) {
  const filename = path.join(root, relative + '.ets');
  const module = { exports: {} };
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, $r: key => key,
    require(name) {
      if (name in dependencies) return dependencies[name];
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  return module.exports;
}

const site = load('services/web/SiteIdentityService', {
  '@ohos.url': { default: { URL: { parseURL: value => new URL(value) } } }
});
const resources = { resolveAppResourceText: value => value };
const ua = load('services/web/BrowserUserAgentService', {
  './SiteIdentityService': site, '../../core/resources/AppResourceText': resources
});
const decisions = load('services/web/BrowserBrowsingIdentityDecisionService');
const { BrowserUserAgentHostPolicyCatalog } = load('services/web/BrowserUserAgentHostPolicyCatalog', {
  './BrowserUserAgentService': ua,
  './GeneratedGoogleSearchCompatibilityHosts': load('services/web/GeneratedGoogleSearchCompatibilityHosts')
});
const { BrowserBrowsingIdentityPolicyCoordinator } = load('core/browser/BrowserBrowsingIdentityPolicyCoordinator', {
  '@kit.ArkWeb': {}, '@kit.PerformanceAnalysisKit': logKit,
  '../../services/web/BrowserUserAgentService': ua,
  '../../services/web/BrowserBrowsingIdentityDecisionService': decisions,
  '../../services/web/BrowserUserAgentHostPolicyService': {}
});
const { BrowserUserAgentSettingsViewModel } = load('core/settings/BrowserUserAgentSettingsViewModel', {
  '../../services/web/BrowserUserAgentService': ua, '../resources/AppResourceText': resources
});
const navigation = load('services/web/BrowserWebNavigationGuardService');
const { BrowserUserAgentRuntimeService } = load('services/web/BrowserUserAgentRuntimeService', {
  '@kit.PerformanceAnalysisKit': logKit,
  './BrowserBrowsingIdentityDecisionService': decisions,
  './BrowserWebNavigationGuardService': navigation
});
const service = new ua.BrowserUserAgentService();
const presetSettings = id => service.buildPresetSettings(id, ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS);

function fixture(family = 'desktop', settings = ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS) {
  const state = { settings, entries: new Map() };
  const catalog = new BrowserUserAgentHostPolicyCatalog();
  const coordinator = new BrowserBrowsingIdentityPolicyCoordinator(
    { getSettings: () => state.settings },
    { findEntry: (target, profile) => state.entries.get(profile + '|' + target.canonicalOrigin) },
    service, new decisions.BrowserBrowsingIdentityDecisionService(), {
      resolveApplicationFamily: () => family,
      resolveMandatoryCompatibility(host, requestedFamily) {
        const match = catalog.resolveMandatoryCompatibility(family, host, requestedFamily);
        return match === undefined ? undefined : {
          ...match, identityId: 'host_profile:' + match.profileId,
          mode: match.profileId === 'aira_desktop_compat' ? 'desktop' : 'mobile'
        };
      }
    }
  );
  return {
    state, coordinator,
    saveSite(url, identityId, profile = 'default') {
      const target = service.resolveSiteSettingTarget(url);
      state.entries.set(profile + '|' + target.canonicalOrigin, {
        profileId: profile, target, overrides: { userAgentIdentityId: identityId }, revision: 1, updatedAt: 1
      });
    },
    resolve(url = 'https://next.bgm.tv/demo/login', extra = {}) {
      return coordinator.resolve({
        tabId: 'tab', currentUrl: url, profileId: 'default', privateBrowsing: false,
        systemDefaultUserAgent: nativeUA, ...extra
      });
    }
  };
}

test('phone keeps its compatible default; tablet and PC use untouched native ArkWeb', () => {
  for (const family of ['mobile', 'tablet', 'desktop']) {
    const result = fixture(family).resolve();
    const isPhone = family === 'mobile';
    const expectedUA = isPhone ? ua.AIRA_COMPAT_MOBILE_USER_AGENT : nativeUA;
    assert.equal(result.winningSource, 'applicable_default');
    assert.equal(result.userAgent, expectedUA);
    assert.equal(result.source, isPhone ? 'app_default' : 'system_default');
    assert.equal(result.identityId, isPhone ? ua.AIRA_DEFAULT_BROWSER_IDENTITY_ID : ua.AIRA_DESKTOP_DEFAULT_BROWSER_IDENTITY_ID);
    assert.equal(result.profile.uaStringMode, isPhone ? 'known_preset' : 'system_untouched');
    assert.equal(result.profile.clientHintsMode, isPhone ? 'known_metadata' : 'system');
    if (!isPhone) assert.equal(result.profile.metadata, undefined);
    assert.equal(service.resolveApplicationDefault(nativeUA, family).userAgent, expectedUA);
  }
  assert.equal(service.resolveApplicationFamilyForShell('phone'), 'mobile');
  assert.equal(service.resolveApplicationFamilyForShell('large_screen'), 'desktop');
  assert.equal(service.resolveApplicationFamilyForDevice('tablet'), 'tablet');
  assert.equal(service.resolveApplicationFamilyForDevice('2in1'), 'desktop');
});

test('PC native default never fabricates a browser identity when the platform UA is unavailable', () => {
  const result = fixture('desktop').resolve(undefined, { systemDefaultUserAgent: '' });
  assert.equal(result.profile.uaStringMode, 'system_untouched');
  assert.equal(result.userAgent, '');
  assert.equal(result.profile.metadata, undefined);
});

for (const preset of ua.BROWSER_USER_AGENT_PRESETS.filter(item => item.id !== ua.APPLICATION_DEFAULT_USER_AGENT_PRESET_ID)) {
  test('global and site choices honor the concrete preset: ' + preset.id, () => {
    for (const family of ['mobile', 'tablet', 'desktop']) {
      const global = fixture(family, presetSettings(preset.id)).resolve();
      const f = fixture(family);
      f.saveSite('https://next.bgm.tv', preset.id);
      const exact = f.resolve();
      assert.equal(global.winningSource, 'global');
      assert.equal(exact.winningSource, 'exact_origin');
      for (const result of [global, exact]) {
        assert.equal(result.identityId, preset.id);
        assert.equal(result.userAgent, preset.userAgent || nativeUA);
        assert.equal(result.profile.uaStringMode, preset.id === 'arkweb_original' ? 'system_untouched' : 'known_preset');
      }
    }
  });
}

test('temporary tab choice, exact Origin, global and default keep their precedence and lifetimes', () => {
  const f = fixture('desktop', presetSettings('desktop_edge_windows'));
  const url = 'https://site.example:8443/page';
  f.saveSite(url, 'desktop_firefox_windows');
  f.coordinator.setCurrentTabIdentity('tab', 'mobile_safari_iphone');
  assert.equal(f.resolve(url).identityId, 'mobile_safari_iphone');
  assert.equal(f.resolve(url).targetOrigin, '');
  assert.equal(f.resolve(url, { tabId: 'other' }).identityId, 'desktop_firefox_windows');
  assert.equal(f.resolve(url, { tabId: 'other' }).targetOrigin, 'https://site.example:8443');
  f.coordinator.releaseTab('tab');
  assert.equal(f.resolve(url).winningSource, 'exact_origin');
  for (const other of ['https://site.example/page', 'http://site.example:8443/page', 'https://sub.site.example:8443/page']) {
    assert.equal(f.resolve(other).identityId, 'desktop_edge_windows');
  }
  assert.equal(f.resolve(url, { profileId: 'other' }).winningSource, 'global');
  assert.equal(f.resolve(url, { privateBrowsing: true }).winningSource, 'global');
  f.coordinator.setCurrentTabIdentity('tab', 'mobile_chrome_android');
  f.coordinator.setCurrentTabIdentity('tab', 'follow_global');
  assert.equal(f.resolve(url).winningSource, 'exact_origin');
  f.state.settings = ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS;
  assert.equal(f.resolve('https://unconfigured.example').winningSource, 'applicable_default');
});

test('package-owned Google and YouTube compatibility still wins and follows requested page shape', () => {
  for (const host of ['www.google.com', 'www.youtube.com']) {
    for (const family of ['mobile', 'tablet', 'desktop']) {
      const defaultDecision = fixture(family).resolve('https://' + host + '/');
      assert.equal(defaultDecision.winningSource, 'mandatory_host');
      assert.equal(defaultDecision.userAgent, family === 'mobile' ? ua.AIRA_COMPAT_MOBILE_USER_AGENT : ua.AIRA_COMPAT_DESKTOP_USER_AGENT);
      const f = fixture(family, presetSettings('desktop_safari_mac'));
      const url = 'https://' + host + '/';
      f.saveSite(url, 'desktop_firefox_windows');
      assert.equal(f.resolve(url).winningSource, 'mandatory_host');
      assert.equal(f.resolve(url).userAgent, ua.AIRA_COMPAT_DESKTOP_USER_AGENT);
      f.coordinator.setCurrentTabIdentity('tab', 'mobile_safari_iphone');
      assert.equal(f.resolve(url).userAgent, ua.AIRA_COMPAT_MOBILE_USER_AGENT);
      f.coordinator.releaseTab('tab');
      assert.equal(f.resolve(url).userAgent, ua.AIRA_COMPAT_DESKTOP_USER_AGENT);
    }
  }
  const phone = fixture('mobile');
  assert.equal(phone.resolve('https://wx.10086.cn/').userAgent, ua.AIRA_COMPAT_HARMONY_MOBILE_USER_AGENT);
  assert.equal(phone.resolve('https://next.bgm.tv/').winningSource, 'applicable_default');
});

test('explicit Aira mobile compatibility remains available on a PC with a native default', () => {
  const f = fixture('desktop');
  f.saveSite('https://next.bgm.tv', ua.AIRA_DEFAULT_BROWSER_IDENTITY_ID);
  assert.equal(f.resolve().winningSource, 'exact_origin');
  assert.equal(f.resolve().userAgent, ua.AIRA_COMPAT_MOBILE_USER_AGENT);
  f.coordinator.setCurrentTabIdentity('tab', ua.AIRA_DEFAULT_BROWSER_IDENTITY_ID);
  assert.equal(f.resolve('https://other.example').winningSource, 'current_tab');
  assert.equal(f.resolve('https://other.example').userAgent, ua.AIRA_COMPAT_MOBILE_USER_AGENT);
});

test('custom global and site identities, missing references and legacy desktop fallback remain usable', () => {
  const record = { id: 'custom_fixture', name: 'My UA', userAgent: 'MyBrowser/1.0', createdAt: 1, updatedAt: 1 };
  const settings = service.buildSettingsForCustomRecord(record, ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS);
  const f = fixture('desktop', settings);
  assert.equal(f.resolve().userAgent, record.userAgent);
  assert.equal(f.resolve().profile.uaStringMode, 'custom');
  f.saveSite('https://next.bgm.tv', record.id);
  assert.equal(f.resolve().winningSource, 'exact_origin');
  assert.equal(f.resolve().userAgent, record.userAgent);
  f.state.settings = presetSettings('desktop_edge_windows');
  assert.equal(f.resolve().winningSource, 'global');
  assert.equal(f.resolve().identityId, 'desktop_edge_windows');
  const legacy = { ...ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS, defaultMode: 'desktop' };
  assert.equal(fixture('mobile', legacy).resolve().identityId, 'desktop_chrome_windows');
});

test('PC settings expose native identity and retain every desktop choice without mutating phone options', () => {
  const model = new BrowserUserAgentSettingsViewModel();
  const state = model.buildState(presetSettings('desktop_edge_windows'));
  const phoneIds = Array.from(state.mobileOptions, item => item.id);
  assert.deepEqual(Array.from(model.resolveDesktopPresentationOptions(state), item => item.id), [
    'system_default', 'arkweb_original', 'desktop_chrome_windows', 'desktop_edge_windows',
    'desktop_safari_mac', 'desktop_firefox_windows'
  ]);
  assert.deepEqual(Array.from(state.mobileOptions, item => item.id), phoneIds);
  assert.equal(state.summary, 'app.string.web_ua_preset_edge_windows');
  assert.equal(state.mobileOptions.find(item => item.id === 'arkweb_original').subtitle, 'app.string.web_ua_preset_arkweb_original_desc');
});

test('automatic and native choices are neutral identities while old saved selection values round-trip', () => {
  const model = new BrowserUserAgentSettingsViewModel();
  for (const [id, kind] of [['system_default', 'application_default'], ['arkweb_original', 'native']]) {
    const preset = service.findPreset(id);
    assert.equal(preset.kind, kind);
    assert.equal(preset.presentationMode, 'default');
    const saved = presetSettings(id);
    const restored = service.normalizeSettings(JSON.parse(JSON.stringify(saved)));
    assert.equal(restored.selectedPresetId, id);
    assert.equal(restored.defaultMode, 'mobile');
    const state = model.buildState(restored);
    const pc = model.resolveDesktopPresentationOptions(state).find(item => item.id === id);
    assert.equal(pc.kind, kind);
    assert.equal(pc.presentationMode, 'default');
    assert.equal(pc.selectionMode, restored.defaultMode);
    assert.ok(state.mobileOptions.some(item => item.id === id));
  }
  for (const preset of service.getPresets().filter(item => item.kind === 'preset')) {
    const saved = presetSettings(preset.id);
    const options = model.buildState(saved);
    const selected = options.mobileOptions.concat(options.desktopOptions).find(item => item.id === preset.id);
    assert.equal(selected.selectionMode, saved.defaultMode);
    assert.equal(selected.presentationMode, preset.presentationMode);
  }
});

test('scoped identity builders do not replace an unavailable choice with a global or device default', () => {
  const settings = presetSettings('desktop_edge_windows');
  for (const scope of ['exact_origin', 'current_tab']) {
    for (const identityId of ['missing', 'follow_global', '']) {
      assert.equal(service.resolveIdentityUserAgent({
        identityId, settings, systemDefaultUserAgent: nativeUA, applicationFamily: 'desktop', scope,
        pageUrl: 'https://next.bgm.tv/demo/login', targetOrigin: 'https://next.bgm.tv'
      }), undefined);
    }
  }
  const f = fixture('desktop', settings);
  f.saveSite('https://next.bgm.tv', 'desktop_firefox_windows');
  f.coordinator.setCurrentTabIdentity('tab', 'missing');
  const decision = f.resolve();
  assert.equal(decision.winningSource, 'exact_origin');
  assert.equal(decision.identityId, 'desktop_firefox_windows');
  assert.equal(decision.explanation.find(item => item.source === 'current_tab').status, 'unavailable');
});

test('legacy custom strings, deleted custom references and desktop selections keep their fallback behavior', () => {
  const legacyCustom = {
    ...ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS, defaultMode: 'custom', customUserAgent: 'LegacyBrowser/1.0'
  };
  const normalized = service.normalizeSettings(JSON.parse(JSON.stringify(legacyCustom)));
  assert.equal(fixture('desktop', normalized).resolve().userAgent, 'LegacyBrowser/1.0');
  assert.equal(normalized.selectedCustomUserAgentId, '');
  const missingCustom = { ...normalized, selectedCustomUserAgentId: 'deleted', customUserAgent: '' };
  assert.equal(fixture('desktop', missingCustom).resolve().userAgent, ua.AIRA_COMPAT_MOBILE_USER_AGENT);
  const oldDesktopSwitch = { ...ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS, defaultMode: 'desktop' };
  assert.equal(fixture('mobile', oldDesktopSwitch).resolve().identityId, 'desktop_chrome_windows');
  assert.equal(ua.APPLICATION_DEFAULT_USER_AGENT_PRESET_ID, 'system_default');
});

test('native identity stays untouched; redirects and history do not overwrite the active controller', () => {
  const calls = [];
  const controller = {};
  let historyIndex = 0;
  const runtime = new BrowserUserAgentRuntimeService({}, {
    resolveController: () => controller,
    applyCustomUserAgent: (_controller, value) => calls.push(value),
    readHistorySnapshot: () => ({ currentIndex: historyIndex, size: historyIndex + 1 }),
    applyClientHints() {}, releaseController() {}
  }, new navigation.BrowserWebNavigationGuardService());
  const f = fixture('desktop', presetSettings('arkweb_original'));
  assert.equal(runtime.prepareNavigation({}, 'tab', 'https://site.example/', f.resolve()).applicationStatus, 'native_untouched');
  assert.equal(calls.length, 0);
  f.state.settings = presetSettings('desktop_edge_windows');
  const first = f.resolve();
  runtime.prepareNavigation({}, 'tab', 'https://site.example/first', first);
  f.state.settings = presetSettings('desktop_firefox_windows');
  runtime.prepareWebMainFrameNavigation({}, 'tab', 'https://site.example/redirect', f.resolve());
  assert.deepEqual(calls, [first.userAgent]);
  runtime.commitNavigation('tab', controller, 'https://site.example/first');
  historyIndex = 1;
  runtime.prepareNavigation({}, 'tab', 'https://site.example/second', f.resolve());
  runtime.commitNavigation('tab', controller, 'https://site.example/second');
  const beforeHistory = calls.length;
  runtime.prepareHistoryNavigation({}, 'tab', 'https://site.example/first', 0, 'back', f.resolve());
  assert.equal(calls.length, beforeHistory);
  f.state.settings = presetSettings('arkweb_original');
  assert.equal(runtime.requiresControllerTransition('tab', f.resolve()), true);
  assert.equal(runtime.prepareNavigation({}, 'tab', 'https://site.example/native', f.resolve()).applicationStatus, 'identity_transition_required');
  assert.equal(calls.length, beforeHistory);
});

test('first page -> child page -> back -> forward preserves UA without reapplying it', () => {
  for (const preset of ['system_default', 'desktop_edge_windows', 'arkweb_original']) {
    const calls = [];
    const controller = {};
    let historyIndex = 0;
    const guard = new navigation.BrowserWebNavigationGuardService();
    const runtime = new BrowserUserAgentRuntimeService({}, {
      resolveController: () => controller,
      applyCustomUserAgent: (_controller, value) => calls.push(value),
      readHistorySnapshot: () => ({ currentIndex: historyIndex, size: 2 }),
      applyClientHints() {}, releaseController() { assert.fail('history must keep the controller'); }
    }, guard);
    const f = fixture('desktop', presetSettings(preset));
    const url = 'https://next.bgm.tv/demo/login';
    const initial = f.resolve(url);
    runtime.prepareNavigation({}, 'tab', url, initial);
    runtime.commitNavigation('tab', controller, url);
    const initialCalls = calls.length;
    assert.equal(initialCalls, preset === 'desktop_edge_windows' ? 1 : 0);
    historyIndex = 1;
    runtime.prepareWebMainFrameNavigation({}, 'tab', url + '/child', f.resolve(url + '/child'), true);
    runtime.commitNavigation('tab', controller, url + '/child');
    assert.equal(calls.length, initialCalls);
    // A new global preference must not mutate a restored history entry mid-navigation.
    f.state.settings = presetSettings('desktop_firefox_windows');
    historyIndex = 0;
    const back = runtime.prepareHistoryNavigation({}, 'tab', url, 0, 'back', f.resolve(url));
    assert.equal(back.allowed, true);
    runtime.commitNavigation('tab', controller, url);
    historyIndex = 1;
    const forward = runtime.prepareHistoryNavigation({}, 'tab', url + '/child', 1, 'forward', f.resolve());
    assert.equal(forward.allowed, true);
    assert.equal(calls.length, initialCalls);
    assert.equal(runtime.hasEffectiveIdentityChange('tab', initial), false);
  }
});

test('returning from explicit desktop UA to the PC default requires a fresh native controller', () => {
  const calls = [];
  let controller = {};
  const runtime = new BrowserUserAgentRuntimeService({}, {
    resolveController: () => controller,
    applyCustomUserAgent: (_controller, value) => calls.push(value),
    readHistorySnapshot: () => ({ currentIndex: 0, size: 1 }),
    applyClientHints() {}, releaseController() {}
  }, new navigation.BrowserWebNavigationGuardService());
  const f = fixture('desktop', presetSettings('desktop_chrome_windows'));
  const url = 'https://next.bgm.tv/demo/login';
  assert.equal(runtime.prepareNavigation({}, 'tab', url, f.resolve()).applicationStatus, 'custom_applied');
  f.state.settings = ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS;
  assert.equal(runtime.requiresControllerTransition('tab', f.resolve()), true);
  assert.equal(runtime.prepareNavigation({}, 'tab', url, f.resolve()).applicationStatus, 'identity_transition_required');
  assert.deepEqual(calls, [ua.AIRA_COMPAT_DESKTOP_USER_AGENT]);
  controller = {};
  assert.equal(runtime.prepareNavigation({}, 'tab', url, f.resolve()).applicationStatus, 'native_untouched');
  assert.equal(runtime.requiresControllerTransition('tab', f.resolve()), false);
  f.state.settings = presetSettings('arkweb_original');
  assert.equal(runtime.prepareNavigation({}, 'tab', url, f.resolve()).applicationStatus, 'unchanged');
  f.state.settings = ua.DEFAULT_BROWSER_USER_AGENT_SETTINGS;
  assert.equal(runtime.prepareNavigation({}, 'tab', url, f.resolve()).applicationStatus, 'unchanged');
  assert.deepEqual(calls, [ua.AIRA_COMPAT_DESKTOP_USER_AGENT]);
});

test('native PC default preserves saved login redirect affinity without leaking it into explicit unrelated navigation', () => {
  const f = fixture('desktop');
  const savedOrigin = 'https://site.example';
  const loginOrigin = 'https://login.example';
  f.saveSite(savedOrigin, 'desktop_edge_windows');
  const runtime = new BrowserUserAgentRuntimeService({}, {}, new navigation.BrowserWebNavigationGuardService());
  const context = currentOrigin => ({
    tabId: 'tab', profileId: 'default', currentOrigin, observedOrigins: [savedOrigin, loginOrigin]
  });
  const resolveTarget = origin => f.resolve(origin);
  const savedDecision = f.resolve(savedOrigin);
  runtime.resolveForContext(context(savedOrigin), savedDecision, true, resolveTarget);
  assert.equal(runtime.resolveForContext(context(loginOrigin), f.resolve(loginOrigin), true, resolveTarget).identityId, savedDecision.identityId);
  assert.equal(runtime.resolveForContext({ ...context(loginOrigin), profileId: 'other' }, f.resolve(loginOrigin), true, resolveTarget).winningSource, 'applicable_default');
  runtime.resolveForContext(context(savedOrigin), savedDecision, true, resolveTarget);
  runtime.clearAffinityForExplicitNavigation('tab', 'https://unrelated.example');
  assert.equal(runtime.resolveForContext(context(loginOrigin), f.resolve(loginOrigin), true, resolveTarget).winningSource, 'applicable_default');
  runtime.resolveForContext(context(savedOrigin), savedDecision, true, resolveTarget);
  f.state.entries.clear();
  assert.equal(runtime.resolveForContext(context(loginOrigin), f.resolve(loginOrigin), true, resolveTarget).winningSource, 'applicable_default');
});

test('UA changes requested inside an ArkWeb navigation callback remain deferred', () => {
  const calls = [];
  const guard = new navigation.BrowserWebNavigationGuardService();
  const runtime = new BrowserUserAgentRuntimeService({}, {
    resolveController: () => controller,
    applyCustomUserAgent: (_controller, value) => calls.push(value),
    readHistorySnapshot: () => ({ currentIndex: 0, size: 1 }),
    applyClientHints() {}, releaseController() {}
  }, guard);
  const controller = {};
  const f = fixture('desktop', presetSettings('desktop_edge_windows'));
  runtime.prepareNavigation({}, 'tab', 'https://site.example/', f.resolve());
  f.state.settings = presetSettings('desktop_firefox_windows');
  const scope = guard.openTabNavigationScope('tab');
  const result = runtime.prepareNavigation({}, 'tab', 'https://site.example/child', f.resolve());
  assert.equal(result.applicationStatus, 'identity_transition_required');
  assert.equal(calls.length, 1);
  scope.close();
  assert.equal(runtime.prepareNavigation({}, 'tab', 'https://site.example/child', f.resolve()).applicationStatus, 'custom_applied');
  assert.equal(calls.length, 2);
});
