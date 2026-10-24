const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
let sequence = 0;

function load(relative) {
  const filename = path.join(root, relative + '.ets');
  if (cache.has(filename)) return cache.get(filename);
  const module = { exports: {} };
  cache.set(filename, module.exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  vm.runInNewContext(code, {
    module, exports: module.exports, Date, $r: name => name,
    require(name) {
      if (name === '@kit.AbilityKit') return { bundleManager: {} };
      if (name === '@kit.ArkTS') return { util: {
        generateRandomUUID: () => `00000000-0000-4000-8000-${String(++sequence).padStart(12, '0')}`
      } };
      if (name.endsWith('AppResourceText')) return { resolveAppResourceText: name => name };
      if (name.endsWith('SiteIdentityService')) return { SiteIdentityService: class {} };
      if (name.endsWith('BrowserModels')) return {
        DEFAULT_BROWSER_PROFILE_ID: 'profile-main',
        normalizeBrowserProfileId: value => value || 'profile-main',
        normalizeBrowserSessionPrivacyMode: value => value || 'regular',
        normalizeBrowserDataScope: (value, mode) => value || (mode === 'private' ? 'session_ephemeral' : 'profile_persistent')
      };
      if (name.endsWith('QqWebLoginCallbackService')) return load('services/web/QqWebLoginCallbackService');
      if (relative === 'app/runtime/BrowserWindowRuntime') {
        if (name.endsWith('DocumentViewerService')) return { DocumentViewerService: class {} };
        if (name.endsWith('WebAppInstallModels')) return { DESKTOP_WEB_SHORTCUT_WANT_KEYS: { source: 'shortcut.source' } };
        if (name.endsWith('BrowserContinuationCoordinator')) return {
          sharedBrowserContinuationCoordinator: { copyPayload: () => undefined }
        };
        return {};
      }
      if (relative === 'core/browser/BrowserWindowLaunchApplication') return {};
      const resolved = path.relative(root, path.resolve(path.dirname(filename), name)).replaceAll('\\', '/');
      return load(resolved);
    }
  }, { filename });
  return module.exports;
}

const jump = 'https://ssl.ptlogin2.qq.com/jump?u1=https%3A%2F%2Fconnect.qq.com&pt_aid=716027609&daid=383';
// Observed in Tencent's actual ptlogin script with Aira's default Android/Chrome UA.
const launch = `wtloginmqq://ptlogin/qlogin?p=${encodeURIComponent(jump)}&schemacallback=googlechrome%3A%2F%2F`;
const context = {
  windowId: 'window-main', tabId: 'login-tab', sourcePageUrl: 'https://graph.qq.com/oauth2.0/authorize',
  profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent'
};

function service() {
  return load('services/web/QqWebLoginCallbackService').sharedQqWebLoginCallbackService;
}

function callbackFor(prepared, target = jump + '&clientkey=fixture%2Bticket&clientuin=fixture') {
  return new URL(prepared.launchUrl).searchParams.get('schemacallback') + encodeURIComponent(target);
}

test('the production webpage launcher gives QQ an Aira callback instead of Chrome', async () => {
  const { ExternalNavigationPolicyService } = load('services/web/ExternalNavigationPolicyService');
  const calls = [];
  const result = await new ExternalNavigationPolicyService().openExternalLink({
    async startAbility(want) { calls.push(want); }
  }, launch, context);
  assert.equal(result.success, true);
  const sent = new URL(calls[0].uri);
  assert.match(sent.searchParams.get('schemacallback'), /^airabrowser:\/\/qq-login\//);
  assert.equal(sent.searchParams.get('p'), jump, 'keep the website authorization request intact');
  assert.equal(sent.searchParams.get('encode_jump_url'), '1');
  assert.equal(sent.searchParams.get('replace_https'), '0');
  assert.ok(!result.diagnosticSummary.includes('ptlogin2.qq.com/jump'), 'authorization URLs stay out of diagnostics');
});

test('encoded and raw QQ returns retain query escaping and can be claimed only once', () => {
  const target = jump + '&clientkey=fixture%2Bticket';
  for (const format of ['encoded', 'raw', 'replaced-scheme']) {
    const prepared = service().prepareLaunch(launch, context);
    const prefix = new URL(prepared.launchUrl).searchParams.get('schemacallback');
    const callback = prefix + (format === 'encoded' ? encodeURIComponent(target)
      : format === 'replaced-scheme' ? target.substring('https://'.length) : target);
    assert.equal(service().peekReturn(callback).targetUrl, target);
    assert.equal(service().peekReturn(callback).tabId, context.tabId);
    assert.equal(service().consumeReturn(callback).targetUrl, target);
    assert.equal(service().consumeReturn(callback), undefined);
  }
});

test('concurrent tabs keep separate return tickets while a new attempt replaces only its own tab', () => {
  const earlier = service().prepareLaunch(launch, context);
  const other = service().prepareLaunch(launch, { ...context, tabId: 'second-login-tab' });
  const latest = service().prepareLaunch(launch, context);
  assert.equal(service().peekReturn(callbackFor(earlier)), undefined);
  assert.equal(service().consumeReturn(callbackFor(other)).tabId, 'second-login-tab');
  assert.equal(service().consumeReturn(callbackFor(latest)).tabId, context.tabId);
});

test('spoofed, malformed, replayed and expired callback URLs cannot become page navigation', () => {
  const prepared = service().prepareLaunch(launch, context);
  const prefix = new URL(prepared.launchUrl).searchParams.get('schemacallback');
  for (const target of [
    'javascript:alert(1)', 'https://evil.example/jump?u1=https%3A%2F%2Fconnect.qq.com',
    'https://ssl.ptlogin2.qq.com@evil.example/jump?u1=https%3A%2F%2Fconnect.qq.com',
    'https://ssl.ptlogin2.qq.com/jump?u1=https%3A%2F%2Fevil.example',
    jump + '&u1=https%3A%2F%2Fevil.example', jump + '#fragment', '%not-encoded'
  ]) assert.equal(service().peekReturn(prefix + encodeURIComponent(target)), undefined, target);
  assert.equal(service().peekReturn(callbackFor(prepared).replace('qq-login/', 'elsewhere/')), undefined);
  assert.ok(service().consumeReturn(callbackFor(prepared)), 'invalid probes must not burn a valid request');
  const timed = service().prepareLaunch(launch, context, 100);
  assert.equal(service().peekReturn(callbackFor(timed), 100 + 11 * 60 * 1000), undefined);
  const { QqWebLoginCallbackService } = load('services/web/QqWebLoginCallbackService');
  assert.equal(new QqWebLoginCallbackService().consumeReturn(callbackFor(prepared)), undefined,
    'a restarted process must not redeem a return without its pending login');
});

test('other external protocols, QR-only flows and malformed requests remain unchanged', async () => {
  const { ExternalNavigationPolicyService } = load('services/web/ExternalNavigationPolicyService');
  for (const uri of [
    'alipays://platformapi/startapp?appId=fixture', 'wtloginmqq://ptlogin/qlogin?qrcode=fixture',
    'wtloginmqq://other/qlogin?p=' + encodeURIComponent(jump),
    'wtloginmqq://ptlogin/qlogin?p=broken', launch + '&p=' + encodeURIComponent(jump)
  ]) {
    let actual;
    await new ExternalNavigationPolicyService().openExternalLink({ async startAbility(want) { actual = want.uri; } }, uri, context);
    assert.equal(actual, uri);
  }
  assert.equal(service().prepareLaunch(launch, undefined), undefined);
});

test('a failed native launch cancels the return ticket', async () => {
  const { ExternalNavigationPolicyService } = load('services/web/ExternalNavigationPolicyService');
  let sent;
  const result = await new ExternalNavigationPolicyService().openExternalLink({
    async startAbility(want) { sent = want.uri; throw { code: 16000019, message: 'No matching ability' }; },
    async openLink() { throw { code: 16000019, message: 'No matching ability' }; }
  }, launch, context);
  assert.equal(result.success, false);
  assert.equal(service().peekReturn(callbackFor({ launchUrl: sent })), undefined);
});

test('Ability ingress routes QQ returns to their original window and private profile', () => {
  const runtime = load('app/runtime/BrowserWindowRuntime');
  const privateContext = { ...context, windowId: 'private-window:fixture', profileId: 'private-profile',
    privacyMode: 'private', dataScope: 'session_ephemeral' };
  const prepared = service().prepareLaunch(launch, privateContext);
  const payload = runtime.resolveBrowserLaunchPayloadFromWant({ uri: callbackFor(prepared) }, 'onNewWant');
  assert.equal(payload.source, 'qq_web_login_callback');
  assert.equal(payload.profileId, privateContext.profileId);
  assert.equal(payload.privacyMode, 'private');
  assert.equal(payload.dataScope, 'session_ephemeral');
  assert.equal(runtime.resolveBrowserLaunchWindowId(payload), privateContext.windowId);
});

async function returnScenario(change) {
  const { BrowserWindowFixedLaunchApplication } = load('core/browser/BrowserWindowLaunchApplication');
  const privateContext = { ...context, windowId: 'private-window:fixture', profileId: 'private-profile',
    privacyMode: 'private', dataScope: 'session_ephemeral' };
  const prepared = service().prepareLaunch(launch, privateContext);
  const callback = callbackFor(prepared);
  const facts = { currentWindowId: privateContext.windowId, activeTabId: 'other-tab', showHomePage: false,
    tabs: [{ id: context.tabId, url: context.sourcePageUrl, pendingUrl: '', ...privateContext }] };
  const opened = [], toasts = [];
  const app = new BrowserWindowFixedLaunchApplication({
    tabSwitchCoordinator: { async switchToTab(id, canApply) {
      if (change === 'unlock-cancelled') return;
      if (change === 'changed-while-switching') facts.tabs[0].url = 'https://unrelated.example/';
      if (canApply()) facts.activeTabId = id;
    } },
    appUrlOpenCoordinator: { open: request => opened.push(request) }
  }, { readFacts: () => facts, showToast: text => toasts.push(text) });
  if (change === 'closed') facts.tabs = [];
  if (change === 'changed-page') facts.tabs[0].url = 'https://unrelated.example/';
  if (change === 'changed-profile') facts.tabs[0].profileId = 'profile-other';
  if (change === 'wrong-window') facts.currentWindowId = 'window-main';
  app.apply({ uri: callback });
  await new Promise(resolve => setImmediate(resolve));
  return { opened, toasts, callback, app };
}

test('a QQ return continues the original tab, preserving the private browsing boundary', async () => {
  const scenario = await returnScenario();
  assert.equal(scenario.opened.length, 1);
  assert.equal(scenario.opened[0].intent, 'current_tab');
  assert.equal(scenario.opened[0].url, jump + '&clientkey=fixture%2Bticket&clientuin=fixture');
  assert.equal(scenario.opened[0].profileId, 'private-profile');
  assert.equal(scenario.opened[0].privacyMode, 'private');
  assert.equal(scenario.opened[0].dataScope, 'session_ephemeral');
  scenario.app.apply({ uri: scenario.callback });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(scenario.opened.length, 1, 'a repeated Want must not navigate twice');
});

test('closing, navigating, changing profile or cancelling private unlock never overwrites another tab', async () => {
  for (const change of ['closed', 'changed-page', 'changed-profile', 'wrong-window',
    'unlock-cancelled', 'changed-while-switching']) {
    assert.equal((await returnScenario(change)).opened.length, 0, change);
  }
});

test('the installed Ability declares Aira QQ callbacks and warm ingress uses their window', () => {
  const manifest = JSON.parse(fs.readFileSync(path.resolve(root, '../module.json5'), 'utf8'));
  const skill = manifest.module.abilities.find(ability => ability.name === 'EntryAbility').skills.find(skill =>
    skill.uris?.some(uri => uri.scheme === 'airabrowser' && uri.host === 'qq-login'));
  assert.ok(skill.actions.includes('ohos.want.action.viewData'));
  assert.ok(skill.entities.includes('entity.system.browsable'));
  const ability = fs.readFileSync(path.join(root, 'app/abilities/EntryAbility.ets'), 'utf8');
  assert.match(ability, /launchPayload.source === QQ_WEB_LOGIN_CALLBACK_SOURCE/);
});
