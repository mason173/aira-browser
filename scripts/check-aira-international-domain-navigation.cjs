#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { domainToASCII, domainToUnicode } = require('node:url');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const modules = new Map();
const engines = [
  { id: 'bing', searchUrlTemplate: 'https://www.bing.com/search?q={searchTerms}' },
  { id: 'baidu', searchUrlTemplate: 'https://www.baidu.com/s?wd={searchTerms}' }
];
let convertHostname = domainToASCII;

function load(relative) {
  const filename = path.join(root, relative);
  if (modules.has(filename)) return modules.get(filename);
  const exports = {};
  modules.set(filename, exports);
  const code = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(code, { exports, $r: value => value, require(name) {
    if (name === '@kit.NetworkKit') return { connection: {
      getDnsAscii: hostname => convertHostname(hostname), ConversionProcess: { USE_STD3_ASCII_RULES: 2 }
    } };
    if (name.endsWith('/BrowserModels')) return { DEFAULT_SEARCH_ENGINE_ID: 'bing', SEARCH_ENGINE_OPTIONS: engines };
    if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
    if (name.endsWith('/SearchEngineAvailabilityProbeService')) return { SearchEngineAvailabilityProbeService: class {} };
    assert.ok(name.startsWith('.'), 'Unexpected platform import: ' + name);
    return load(path.relative(root, path.resolve(path.dirname(filename), name + '.ets')));
  } }, { filename });
  return exports;
}

const utils = load('common/utils/UrlUtils.ets');
const { SearchEngineRoutingService } = load('services/search/SearchEngineRoutingService.ets');
const { NavigationController } = load('core/navigation/NavigationController.ets');
const routing = new SearchEngineRoutingService({});
function resolve(rawInput, selectedSearchEngineId = 'bing') {
  return routing.resolve({ rawInput, selectedSearchEngineId,
    availableSearchEngines: engines, settings: { defaultSearchEngineId: selectedSearchEngineId, fallbackSearch: { enabled: false } },
    boundary: {} });
}

test('Chinese version-number queries use the selected search engine instead of navigating to a Punycode host', async () => {
  // Synthetic input reproduces the reported shape without retaining a user's search text.
  for (const query of ['示例应用11.5.5.1下载', '示例应用5.5下载', '示例应用11.5.5.1',
    '2026.11.11新闻', '价格3.5元', '示例应用.安装教程', 'App11.5.5.1', '1.2.3',
    domainToASCII('示例应用11.5.5.1下载')]) {
    assert.equal(utils.resolveAddressInput(query).submittedText, query);
    assert.equal(utils.extractFirstUrlFromText(query), '', query);
    assert.equal(utils.looksLikeUrl(query), false, query);
    assert.equal(utils.resolveAddressInput(query).httpFallbackUrl, '', query);
    for (const engine of engines) {
      const result = await resolve(query, engine.id);
      assert.equal(result.intent, 'search', `${engine.id}: ${result.resolvedUrl}`);
      assert.equal(result.submittedText, query);
      assert.equal(result.searchQuery, query);
      assert.equal(result.resolvedUrl, engine.searchUrlTemplate.replace('{searchTerms}', encodeURIComponent(query)));
      assert.equal(result.httpFallbackUrl, '');
      assert.equal(new NavigationController().resolveAddressInput(query, engine), result.resolvedUrl);
    }
  }
});

test('explicit URLs still navigate even when their host suffix is not recognized', async () => {
  for (const query of ['示例应用11.5.5.1下载', '示例应用.安装教程']) {
    for (const scheme of ['http://', 'https://']) {
      const input = scheme + query + '/路径?q=中文#片段';
      const result = await resolve(input);
      assert.equal(result.intent, 'navigate');
      assert.equal(result.resolvedUrl, scheme + domainToASCII(query) + '/路径?q=中文#片段');
      assert.equal(result.httpFallbackUrl, '');
    }
  }
});

test('a numeric DNS suffix remains a query even when the platform successfully encodes it', async () => {
  try {
    // NetworkKit converts DNS names; Node's WHATWG helper additionally rejects
    // numeric final labels as invalid IPv4. Suppress that unrelated URL heuristic.
    convertHostname = hostname => domainToASCII(hostname + '.invalid').replace(/\.invalid$/, '');
    const query = '示例应用11.5.5.1';
    assert.ok(convertHostname(query).endsWith('.5.5.1'));
    for (const engine of engines) {
      assert.equal((await resolve(query, engine.id)).resolvedUrl,
        engine.searchUrlTemplate.replace('{searchTerms}', encodeURIComponent(query)));
      assert.equal(utils.resolveAddressInput(query).httpFallbackUrl, '');
    }
  } finally {
    convertHostname = domainToASCII;
  }
});

test('a schemeless Chinese domain navigates to its ASCII hostname instead of searching', async () => {
  const result = await resolve('教父.com');
  assert.equal(result.intent, 'navigate');
  assert.equal(result.resolvedUrl, 'https://xn--wcv59z.com');
  assert.equal(result.httpFallbackUrl, 'http://xn--wcv59z.com');
  assert.equal(result.searchQuery, '');
  assert.equal(new NavigationController().resolveAddressInput('教父.com', engines[0]), result.resolvedUrl);
});

test('one submission keeps a single successful host conversion through navigation and HTTP fallback', async () => {
  try {
    for (const entry of ['routing', 'navigation']) {
      let calls = 0;
      convertHostname = hostname => {
        if (++calls > 1) throw new Error('2100002: network service unavailable');
        return domainToASCII(hostname);
      };
      const input = '示例.com/路径?q=中文';
      const expected = 'https://' + domainToASCII('示例.com') + '/路径?q=中文';
      if (entry === 'routing') {
        const result = await resolve(input);
        assert.equal(result.intent, 'navigate');
        assert.equal(result.resolvedUrl, expected);
        assert.equal(result.httpFallbackUrl, expected.replace('https:', 'http:'));
      } else {
        assert.equal(new NavigationController().resolveAddressInput(input, engines[0]), expected);
      }
      assert.equal(calls, 1, entry);
    }
  } finally {
    convertHostname = domainToASCII;
  }
});

test('URL-only normalization never silently chooses a search engine', () => {
  assert.equal(utils.normalizeUrl('示例应用11.5.5.1下载'), '');
  assert.equal(utils.normalizeUrl('ordinary search terms'), '');
});

test('the shared interpretation distinguishes empty, search and navigation without choosing an engine', () => {
  for (const [input, intent, text, url, fallback] of [
    ['  ', 'empty', '', '', ''],
    ['  示例应用11.5.5.1下载  ', 'search', '示例应用11.5.5.1下载', '', ''],
    ['打开：https://example.com/path。', 'navigate', 'https://example.com/path', 'https://example.com/path', ''],
    ['example.com/path', 'navigate', 'example.com/path', 'https://example.com/path', 'http://example.com/path'],
    ['localhost:8080/a', 'navigate', 'localhost:8080/a', 'http://localhost:8080/a', ''],
    ['aira://settings', 'navigate', 'aira://settings', 'aira://settings', '']
  ]) {
    const result = utils.resolveAddressInput(input);
    assert.equal(result.intent, intent, input);
    assert.equal(result.submittedText, text, input);
    assert.equal(result.navigationUrl, url, input);
    assert.equal(result.httpFallbackUrl, fallback, input);
  }
});

test('custom templates, exact engine selection and configured fallback still own search routing', async () => {
  const custom = { id: 'custom_docs', searchUrlTemplate: 'https://docs.example/find/%s?lang=zh' };
  const query = '示例应用11.5.5.1下载';
  let allowed = true, reachability = 'unreachable', probes = 0;
  const service = new SearchEngineRoutingService({
    resolveCachedAvailability() { probes += 1; return { reachability }; }
  }, async () => allowed);
  const input = { rawInput: query, selectedSearchEngineId: 'bing', availableSearchEngines: [...engines, custom],
    settings: { defaultSearchEngineId: 'bing', fallbackSearch: {
      enabled: true, fallbackSearchEngineId: 'baidu', noticeEnabled: false
    } }, boundary: { privacyMode: 'regular' } };
  for (const selectedSearchEngineId of ['bing', 'baidu', custom.id]) {
    const result = await service.resolve({ ...input, selectedSearchEngineId, routingMode: 'exact' });
    const engine = input.availableSearchEngines.find(item => item.id === selectedSearchEngineId);
    const expected = engine.searchUrlTemplate.replace('%s', '{searchTerms}')
      .replace('{searchTerms}', encodeURIComponent(query));
    assert.equal(result.resolvedUrl, expected);
    assert.equal(result.searchEngineId, selectedSearchEngineId);
    assert.equal(new NavigationController().resolveAddressInput(query, selectedSearchEngineId,
      input.availableSearchEngines), expected);
  }
  assert.equal(probes, 0, 'exact engine selection must not probe or fall back');
  assert.equal((await service.resolve({ ...input, routingMode: 'exact', selectedSearchEngineId: 'missing' })).intent, 'empty');
  const fallback = await service.resolve(input);
  assert.equal(fallback.searchEngineId, 'baidu');
  assert.equal(fallback.primarySearchEngineId, 'bing');
  assert.equal(fallback.fallbackApplied, true);
  allowed = false;
  assert.equal((await service.resolve(input)).searchEngineId, 'bing');
  assert.equal(probes, 1, 'ineligible search never probes');
  allowed = true;
  reachability = 'reachable';
  assert.equal((await service.resolve(input)).searchEngineId, 'bing');
  assert.equal(service.consumeLoadFailureFallback({ primarySearchEngineId: 'bing', query }), true);
  assert.equal(service.consumeLoadFailureFallback({ primarySearchEngineId: 'bing', query }), false);
  const beforeNavigation = probes;
  assert.equal((await service.resolve({ ...input, rawInput: 'example.com' })).intent, 'navigate');
  assert.equal((await service.resolve({ ...input, rawInput: ' ' })).intent, 'empty');
  assert.equal(probes, beforeNavigation, 'URLs and empty input never probe search engines');
});

test('failed host conversion keeps the original query and the selected engine', async () => {
  try {
    for (const engine of engines) {
      let calls = 0;
      convertHostname = () => { calls += 1; throw new Error('network service unavailable'); };
      const query = '示例.com';
      const result = await resolve(query, engine.id);
      assert.equal(result.intent, 'search');
      assert.equal(result.searchQuery, query);
      assert.equal(result.resolvedUrl, engine.searchUrlTemplate.replace('{searchTerms}', encodeURIComponent(query)));
      assert.equal(result.httpFallbackUrl, '');
      assert.equal(calls, 1, 'failed input must not be reinterpreted later in the same submission');
    }
  } finally {
    convertHostname = domainToASCII;
  }
});

test('external app search retains its query and native/web fallback routes', () => {
  const { ExternalAppSearchService } = load('services/search/ExternalAppSearchService.ets');
  const service = new ExternalAppSearchService();
  const query = '示例应用11.5.5.1下载';
  const action = service.buildAction('bilibili', query);
  assert.equal(action.query, query);
  assert.ok(action.nativeUrl.includes(encodeURIComponent(query)));
  assert.ok(action.fallbackUrl.includes(encodeURIComponent(query)));
  assert.equal(service.buildAction('bilibili', 'https://example.com'), undefined);
  assert.equal(service.buildAction('bilibili', ''), undefined);
});

test('URL-only settings reject search text and preserve valid international addresses', () => {
  const { CustomHomepageUrlService } = load('services/customhome/CustomHomepageUrlService.ets');
  const { SearchEngineTemplateService } = load('services/search/SearchEngineTemplateService.ets');
  const home = new CustomHomepageUrlService();
  const templates = new SearchEngineTemplateService();
  assert.equal(home.validateRemoteHomepageUrl('示例应用11.5.5.1下载').valid, false);
  assert.equal(home.validateRemoteHomepageUrl('示例.com').normalizedUrl, 'https://' + domainToASCII('示例.com'));
  assert.equal(templates.validateTemplate('搜索 {searchTerms}').valid, false);
  assert.equal(templates.validateTemplate('https://example.com/search?q=%s').valid, true);
});

test('URL-only shortcuts and tab reuse never turn malformed stored URLs into searches', () => {
  const { HomeShortcutOpenPolicyService } = load('services/shortcuts/HomeShortcutOpenPolicyService.ets');
  const { TabReusePolicyService } = load('services/tabs/TabReusePolicyService.ets');
  const policy = new HomeShortcutOpenPolicyService();
  const shortcut = { id: 'shortcut', title: 'Example', kind: 'web', url: 'example.com' };
  assert.equal(policy.buildOpenPlan(shortcut, 'tab', 'new_tab').url, 'https://example.com');
  assert.throws(() => policy.buildOpenPlan({ ...shortcut, url: '示例应用11.5.5.1下载' }, 'tab', 'new_tab'));
  assert.equal(new TabReusePolicyService().findReusableTab([], {
    targetUrl: '示例应用11.5.5.1下载', activeTabId: 'tab', launchContext: {}
  }).reason, 'none');
});

test('delegated international suffixes navigate in both Unicode and Punycode form', async () => {
  const { INTERNATIONAL_DOMAIN_SUFFIXES } = load('common/utils/InternationalDomainSuffixes.ets');
  assert.ok(INTERNATIONAL_DOMAIN_SUFFIXES.has(domainToASCII('中国')));
  assert.ok(INTERNATIONAL_DOMAIN_SUFFIXES.has(domainToASCII('公司')));
  assert.ok(INTERNATIONAL_DOMAIN_SUFFIXES.has(domainToASCII('рф')));
  assert.ok(!INTERNATIONAL_DOMAIN_SUFFIXES.has(domainToASCII('1下载')));
  for (const suffix of INTERNATIONAL_DOMAIN_SUFFIXES) {
    for (const hostname of ['example.' + suffix, '示例.' + domainToUnicode(suffix)]) {
      const result = await resolve(hostname + '/path?q=1#section');
      assert.equal(result.intent, 'navigate', hostname);
      assert.equal(result.resolvedUrl, 'https://' + domainToASCII(hostname) + '/path?q=1#section');
    }
  }
});

test('international host conversion preserves subdomains, ports and the untouched path/query/fragment', async () => {
  for (const input of ['教父abc.com/路径?q=中文#章节', '新闻.例子.中国:8443/文章?q=中文#段落',
    'www.教父.com/path', '教父。com/路径', 'bücher.de/书籍',
    '教父.com/https://example.com', '教父.com/?next=https://example.com/a',
    '教父.com/a中文?q=中文#章节', '教父.com/新闻-news-中文']) {
    const hostPort = input.split(/[/?#]/)[0];
    const portIndex = hostPort.indexOf(':');
    const hostname = portIndex < 0 ? hostPort : hostPort.slice(0, portIndex);
    const port = portIndex < 0 ? '' : hostPort.slice(portIndex);
    const expected = domainToASCII(hostname) + port + input.slice(hostPort.length);
    assert.equal(utils.extractFirstUrlFromText(input), input, 'paste and paste-and-go must retain the outer IDN host');
    const result = await resolve(input);
    assert.equal(result.intent, 'navigate', input);
    assert.equal(result.submittedText, input, 'address extraction must keep the complete international host');
    assert.equal(result.resolvedUrl, 'https://' + expected, input);
    assert.equal(result.httpFallbackUrl, 'http://' + expected, input);
  }
});

test('explicit HTTP(S) hosts are converted while local hosts and other URL schemes retain their behavior', async () => {
  for (const protocol of ['http', 'https']) {
    const input = protocol + '://教父.com:8080/中文?key=中文#片段';
    assert.equal((await resolve(input)).resolvedUrl, protocol + '://xn--wcv59z.com:8080/中文?key=中文#片段');
    for (const separator of ['。', '．', '｡']) {
      const internationalInput = protocol + '://例子' + separator + '中国:8443/文章';
      assert.equal(utils.extractFirstUrlFromText(internationalInput), internationalInput);
      assert.equal((await resolve(internationalInput)).resolvedUrl,
        protocol + '://' + domainToASCII('例子.中国') + ':8443/文章');
    }
  }
  for (const [input, expected] of [['本地.local:8080/path', 'http://' + domainToASCII('本地.local') + ':8080/path'],
    ['localhost:8080/path', 'http://localhost:8080/path'], ['192.168.1.2/a', 'http://192.168.1.2/a'],
    ['[::1]:8080/a', 'http://[::1]:8080/a'], ['8.8.8.8/a', 'https://8.8.8.8/a'],
    ['www.bing.com', 'https://www.bing.com'], ['www.baidu.com', 'https://www.baidu.com'],
    ['example.com/a?x=1#b', 'https://example.com/a?x=1#b'],
    ['aira://settings', 'aira://settings'], ['file:///data/中文.html', 'file:///data/中文.html']]) {
    assert.equal((await resolve(input)).resolvedUrl, expected, input);
  }
});

test('conversion failure never creates a URL with an empty host and normalization converts only once', () => {
  try {
    for (const [normalize, scheme] of [[utils.normalizeUrl, 'https://'],
      [value => utils.resolveAddressInput(value).httpFallbackUrl, 'http://']]) {
      let calls = 0;
      convertHostname = hostname => {
        if (++calls > 1) throw new Error('2100002: network service unavailable');
        return domainToASCII(hostname);
      };
      assert.equal(normalize('教父.com'), scheme + 'xn--wcv59z.com');
      assert.equal(calls, 1);
    }
    for (const fail of [() => { throw new Error('2100002: network service unavailable'); }, () => '', () => 'bad..host']) {
      convertHostname = fail;
      assert.equal(utils.looksLikeUrl('教父.com'), false);
      assert.equal(utils.extractFirstUrlFromText('教父abc.com/path'), '');
      assert.equal(utils.normalizeUrl('教父.com'), '');
      assert.equal(utils.resolveAddressInput('教父.com').httpFallbackUrl, '');
    }
  } finally {
    convertHostname = domainToASCII;
  }
});

test('ordinary Chinese queries and malformed domain-shaped text still search', async () => {
  for (const query of ['教父', '教父电影', '教父 com', '教父.com 是什么', '教父..com', '教父.com:端口']) {
    const result = await resolve(query);
    assert.equal(result.intent, 'search', query);
    assert.equal(result.searchQuery, query);
    assert.equal(result.resolvedUrl, 'https://www.bing.com/search?q=' + encodeURIComponent(query));
  }
  assert.equal(utils.extractFirstUrlFromText('教父..abc.com/path'), '');
});

test('pasted ASCII links still shed surrounding prose and trailing punctuation', () => {
  for (const input of ['打开：https://example.com/path。', '访问 https://example.com/path 谢谢',
    'https://example.com/path']) {
    assert.equal(utils.resolveAddressInput(input).submittedText, 'https://example.com/path');
  }
  for (const input of ['打开：example.com/path', '（example.com/path）']) {
    assert.equal(utils.extractFirstUrlFromText(input), 'example.com/path');
    assert.equal(utils.resolveAddressInput(input).submittedText, 'example.com/path');
  }
});

test('complete international links retain the existing pasted path and trailing punctuation rules', async () => {
  for (const prefix of ['', 'https://']) {
    for (const suffix of [')', '。', ',', ')。']) {
      const input = prefix + '教父.com/path' + suffix;
      assert.equal(utils.extractFirstUrlFromText(input), prefix + '教父.com/path', input);
      assert.equal((await resolve(input)).resolvedUrl, 'https://xn--wcv59z.com/path', input);
    }
    const mixedPath = prefix + '教父.com/a中文?q=中文#章节';
    assert.equal(utils.extractFirstUrlFromText(mixedPath), mixedPath);
    assert.equal((await resolve(mixedPath)).resolvedUrl, 'https://xn--wcv59z.com/a中文?q=中文#章节');
    assert.equal(utils.extractFirstUrlFromText(prefix + '教父.com,'), prefix + '教父.com');
  }
});
