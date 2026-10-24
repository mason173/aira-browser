// Exercise the production document-start provider and its generated page script. This verifies
// early stylesheet availability; first-paint timing in ArkWeb still needs device validation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function load(relative, dependencies = {}) {
  const filename = path.join(root, relative + '.ets');
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }, fileName: filename
  }).outputText;
  const module = { exports: {} };
  vm.runInNewContext(code, {
    module, exports: module.exports,
    require(name) {
      if (name in dependencies) return dependencies[name];
      throw new Error('Unexpected dependency: ' + name);
    }
  }, { filename });
  return module.exports;
}

const runtimeModule = load('services/adblock/AdBlockCosmeticRuntimeScriptService');
const adapterModule = load('services/adblock/AdBlockRustCosmeticResourceAdapterService');

function fixture(options = {}) {
  const queries = [];
  const resources = {
    hideSelectorsJson: JSON.stringify(['.banner-ad', '#sponsor']),
    proceduralActionsJson: '[]', injectedScript: 'window.scriptletInstalled = true;', ...options.resources
  };
  const settings = { preferences: { enabled: options.enabled !== false }, updatedAt: 1, lastRuleUpdateAt: 1 };
  const generation = {
    resolveNativeCosmeticResources(url) {
      queries.push(url);
      return options.unavailable ? undefined : resources;
    },
    getRuntimeRefreshGeneration: () => 1
  };
  const module = load('core/adblock/AdBlockDocumentStartCoordinator', {
    '@ohos.url': { default: { URL: { parseURL: value => new URL(value) } } },
    '../../services/adblock/AdBlockCosmeticRuntimeScriptService': runtimeModule,
    '../../services/adblock/AdBlockRustCosmeticResourceAdapterService': adapterModule,
    '../../services/adblock/AdBlockCosmeticDiscoveryRuntimeScriptService': {
      AdBlockCosmeticDiscoveryRuntimeScriptService: class {
        buildDocumentStartScriptItem() { return { script: '', scriptRules: ['*'] }; }
      }
    },
    '../../services/adblock/AdBlockPingRuntimeScriptService': {
      AdBlockPingRuntimeScriptService: class {
        buildDocumentStartScriptItem() { return { script: '', scriptRules: ['*'] }; }
      }
    },
    '../../services/adblock/AdBlockInteractionGuardRuntimeScriptService': {
      AdBlockInteractionGuardRuntimeScriptService: class {
        buildDocumentStartScriptItem() { return { script: '', scriptRules: ['*'] }; }
      }
    },
    '../../services/adblock/AdBlockPolicyService': {
      AdBlockPolicyService: class { isHostAllowlisted() { return options.allowlisted === true; } }
    },
    './AdBlockRuntimeGenerationCoordinator': { AdBlockRuntimeGenerationCoordinator: {
      forRepository: () => generation
    } }
  });
  const provider = new module.AdBlockDocumentStartCoordinator({ getSettings: () => settings });
  const tab = { url: 'https://example.com/article', pendingUrl: '', profileId: 'default', ...options.tab };
  return { provider, tab, queries };
}

function documentAtStart(url) {
  const nodes = new Map();
  const root = { appendChild(node) { nodes.set(node.id, node); node.parentNode = root; } };
  const document = {
    head: null, documentElement: root,
    getElementById: id => nodes.get(id),
    createElement: () => ({ id: '', textContent: '', setAttribute() {} })
  };
  const context = { document, location: new URL(url), URL, window: {} };
  return { context, style: () => nodes.get('aira-adblock-cosmetic-style') };
}

function runStart(fixture, pageUrl = fixture.tab.pendingUrl || fixture.tab.url) {
  const page = documentAtStart(pageUrl);
  const scripts = fixture.provider.buildForTab(fixture.tab);
  for (const item of scripts) vm.runInNewContext(item.script, page.context);
  return { ...page, scripts };
}

test('domain CSS is present before page-end and before head/body exists', () => {
  const page = runStart(fixture());
  assert.ok(page.style(), 'matching ads currently stay visible until the page-end injection');
  assert.match(page.style().textContent, /\.banner-ad\{display:none!important/);
  assert.match(page.style().textContent, /#sponsor\{display:none!important/);
  assert.equal(page.context.window.scriptletInstalled, true);
  const cssScript = page.scripts.find(item => item.script.includes('airaAdBlockDocumentStartCss'));
  assert.deepEqual(Array.from(cssScript.scriptRules), ['https://example.com']);
});

test('disabled, allowlisted and unready pages receive no early hiding stylesheet', () => {
  for (const options of [{ enabled: false }, { allowlisted: true }, { unavailable: true },
    { resources: { hideSelectorsJson: '[]' } }]) {
    assert.equal(runStart(fixture(options)).style(), undefined);
  }
});

test('a pending navigation selects its own rules and cannot hide a different document', () => {
  const f = fixture({ tab: { pendingUrl: 'https://next.example/article?q=one' } });
  assert.ok(runStart(f).style());
  assert.equal(f.queries[0], f.tab.pendingUrl);
  for (const url of ['https://example.com/article', 'https://next.example/other',
    'https://next.example/article?q=two']) {
    assert.equal(runStart(f, url).style(), undefined);
    assert.equal(runStart(f, url).context.window.scriptletInstalled, undefined);
  }
  assert.ok(runStart(f, f.tab.pendingUrl + '#section').style());
});

test('early CSS does not install the procedural observer or reset an existing runtime', () => {
  const f = fixture({ resources: { proceduralActionsJson: JSON.stringify([
    JSON.stringify({ selector: [{ type: 'css-selector', arg: '.deferred' }], action: { type: 'remove' } })
  ]) } });
  const page = documentAtStart(f.tab.url);
  const runtime = { marker: 'preserved' };
  page.context.window.__airaAdBlockCosmeticRuntime = runtime;
  for (const item of f.provider.buildForTab(f.tab)) vm.runInNewContext(item.script, page.context);
  assert.ok(page.style());
  assert.equal(page.context.window.__airaAdBlockCosmeticRuntime, runtime);
  assert.doesNotMatch(page.style().textContent, /deferred/);
});

test('late completion from the previous URL cannot replace or clear the new page runtime', () => {
  const service = new runtimeModule.AdBlockCosmeticRuntimeScriptService();
  const page = documentAtStart('https://example.com/new');
  const runtime = { marker: 'preserved' };
  page.context.window.__airaAdBlockCosmeticRuntime = runtime;
  for (const script of [service.buildInjectionScript([], ['.old-ad'], 'https://example.com/old'),
    service.buildInjectionScript([{ selector: '.old-ad', action: 'remove', value: '', procedural: true }], [],
      'https://example.com/old'), service.buildClearScript('https://example.com/old')]) {
    vm.runInNewContext(script, page.context);
    assert.equal(page.style(), undefined);
    assert.equal(page.context.window.__airaAdBlockCosmeticRuntime, runtime);
  }
});

test('a failed scriptlet remains eligible for the native page-end fallback', () => {
  const service = new runtimeModule.AdBlockCosmeticRuntimeScriptService();
  const page = documentAtStart('https://example.com/article');
  assert.throws(() => vm.runInNewContext(service.buildInjectedScriptExecutionScript('throw new Error("failed")'), page.context));
  assert.notEqual(page.context.window.__airaAdBlockRustScriptletsInstalled, true);
  vm.runInNewContext(service.buildInjectedScriptExecutionScript('window.ok = true'), page.context);
  assert.equal(page.context.window.__airaAdBlockRustScriptletsInstalled, true);
});
