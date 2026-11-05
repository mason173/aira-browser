#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const { domainToASCII } = require('node:url');
const ts = require('./lib/deveco-typescript.cjs');
const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const modules = new Map();
const engines = [{ id: 'bing', searchUrlTemplate: 'https://www.bing.com/search?q={searchTerms}' }];
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
function resolve(rawInput) {
  return routing.resolve({ rawInput, selectedSearchEngineId: 'bing',
    availableSearchEngines: engines, settings: { defaultSearchEngineId: 'bing', fallbackSearch: { enabled: false } },
    boundary: {} });
}

test('a schemeless Chinese domain navigates to its ASCII hostname instead of searching', async () => {
  const result = await resolve('教父.com');
  assert.equal(result.intent, 'navigate');
  assert.equal(result.resolvedUrl, 'https://xn--wcv59z.com');
  assert.equal(result.httpFallbackUrl, 'http://xn--wcv59z.com');
  assert.equal(result.searchQuery, '');
  assert.equal(new NavigationController().resolveAddressInput('教父.com', engines[0]), result.resolvedUrl);
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
    ['[::1]:8080/a', 'http://[::1]:8080/a'], ['example.com/a?x=1#b', 'https://example.com/a?x=1#b'],
    ['aira://settings', 'aira://settings'], ['file:///data/中文.html', 'file:///data/中文.html']]) {
    assert.equal((await resolve(input)).resolvedUrl, expected, input);
  }
});

test('conversion failure never creates a URL with an empty host and normalization converts only once', () => {
  try {
    for (const normalize of [utils.normalizeUrl, utils.resolveSchemelessHttpFallbackUrl]) {
      let calls = 0;
      convertHostname = hostname => {
        if (++calls > 1) throw new Error('2100002: network service unavailable');
        return domainToASCII(hostname);
      };
      assert.equal(normalize('教父.com'), (normalize === utils.normalizeUrl ? 'https://' : 'http://') + 'xn--wcv59z.com');
      assert.equal(calls, 1);
    }
    for (const fail of [() => { throw new Error('2100002: network service unavailable'); }, () => '', () => 'bad..host']) {
      convertHostname = fail;
      assert.equal(utils.looksLikeUrl('教父.com'), false);
      assert.equal(utils.extractFirstUrlFromText('教父abc.com/path'), '');
      assert.equal(utils.normalizeUrl('教父.com'), 'https://www.baidu.com/s?wd=' + encodeURIComponent('教父.com'));
      assert.equal(utils.resolveSchemelessHttpFallbackUrl('教父.com'), '');
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
    assert.equal(utils.normalizeAddressInputText(input), 'https://example.com/path');
  }
  for (const input of ['打开：example.com/path', '（example.com/path）']) {
    assert.equal(utils.extractFirstUrlFromText(input), 'example.com/path');
    assert.equal(utils.normalizeAddressInputText(input), 'example.com/path');
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
