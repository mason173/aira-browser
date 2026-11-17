#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const imageUrl = 'https://images.example.test/image.png';
const imageBytes = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3, 4]).buffer;

function environment() {
  const requests = [], cookies = [], copied = [], cache = new Map();
  const state = { cookieFailure: false, destroyed: 0 };
  const kits = {
    '@kit.ArkData': {}, '@kit.CoreFileKit': {}, '@kit.MediaLibraryKit': {}, '@kit.ShareKit': {},
    '@kit.BasicServicesKit': { pasteboard: { MIMETYPE_PIXELMAP: 'image', createData: (type, map) => map,
      getSystemPasteboard: () => ({ setData: async value => copied.push(value) }) } },
    '@kit.ImageKit': { image: { createImageSource: bytes => ({
      createPixelMap: async () => ({ bytes, release: async () => {} }), release: async () => {}
    }) } },
    '@kit.ArkWeb': { webview: { WebCookieManager: { fetchCookieSync(url, incognito) {
      cookies.push({ url, incognito }); if (state.cookieFailure) throw Error('unavailable');
      return incognito ? 'private=synthetic' : 'regular=synthetic';
    } } } },
    '@kit.PerformanceAnalysisKit': { hilog: { info() {}, warn() {} } },
    '@kit.NetworkKit': { http: { RequestMethod: { GET: 'GET' }, HttpDataType: { ARRAY_BUFFER: 'buffer' },
      createHttp: () => ({ request: async (url, options) => {
        requests.push({ url, options }); return { responseCode: 200, result: imageBytes };
      }, destroy: () => { state.destroyed++; } }) } }
  };
  function evaluate(source, filename) {
    const module = { exports: {} };
    const output = ts.transpileModule(source, {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    vm.runInNewContext(output, { module, exports: module.exports, ArrayBuffer, Uint8Array,
      $r: value => value, resolveAppResourceText: value => value,
      require(id) {
        if (kits[id]) return kits[id];
        if (id.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
        if (id.endsWith('/AppRuntimeContext')) return { AppRuntimeContext: {} };
        assert.ok(id.startsWith('.'), `Unexpected dependency ${id}`);
        return load(path.resolve(path.dirname(filename), `${id}.ets`));
      }
    }, { filename });
    return module.exports;
  }
  function load(filename) {
    if (!cache.has(filename)) cache.set(filename, evaluate(fs.readFileSync(filename, 'utf8'), filename));
    return cache.get(filename);
  }
  const { WebImageContextActionService } = load(path.join(sourceRoot, 'services/web/WebImageContextActionService.ets'));
  // Keep the production methods intact; layout and UI hosts are unrelated to request identity.
  const filename = path.join(sourceRoot, 'core/web/WebLinkContextMenuCoordinator.ets');
  const ast = ts.createSourceFile(filename, fs.readFileSync(filename, 'utf8'), ts.ScriptTarget.Latest, true);
  const owner = ast.statements.find(node => ts.isClassDeclaration(node) && node.name?.text === 'WebLinkContextMenuCoordinator');
  const names = ['buildImageState', 'executeImageAction', 'isPrivateBoundary', 'isWebLinkUrl', 'safeNumber',
    'safeString', 'resolveDownloadUserAgent'];
  const methods = names.map(name => { const method = owner.members.find(node => node.name?.text === name);
    assert.ok(method, `Production method missing: ${name}`); return method.getText(ast); });
  const { ImageMenu } = evaluate(`export class ImageMenu { ${methods.join('\n')} }`, filename);
  return { service: new WebImageContextActionService(), menu: new ImageMenu(), requests, cookies, copied, state };
}

(async () => {
  for (const isPrivate of [false, true]) {
    const f = environment();
    assert.equal((await f.service.copyImage({ imageUrl, pageUrl: 'https://page.example.test/origin',
      userAgent: 'Actual page UA', isPrivate })).ok, true);
    assert.deepEqual(f.cookies, [{ url: imageUrl, incognito: isPrivate }]);
    const options = f.requests[0].options;
    assert.equal(options.header.Cookie, isPrivate ? 'private=synthetic' : 'regular=synthetic');
    assert.equal(options.header['User-Agent'], 'Actual page UA');
    assert.equal(options.header.Referer, 'https://page.example.test/origin');
    assert.equal(options.usingCache, !isPrivate);
    assert.equal(f.state.destroyed, 1);
    assert.deepEqual(new Uint8Array(f.copied[0].bytes), new Uint8Array(imageBytes));
    console.log(`PASS ${isPrivate ? 'private' : 'regular'} image copy uses source UA, referrer and matching cookie store`);
  }
  {
    const f = environment(); f.state.cookieFailure = true;
    assert.equal((await f.service.copyImage({ imageUrl, isPrivate: true })).ok, true);
    assert.deepEqual(f.cookies, [{ url: imageUrl, incognito: true }]);
    assert.equal(f.requests[0].options.header.Cookie, undefined);
    assert.equal(f.requests[0].options.header['User-Agent'], undefined);
    console.log('PASS unavailable private cookies never fall back to the regular cookie store or fake UA');
  }
  {
    const f = environment(); const encoded = Buffer.from(imageBytes).toString('base64');
    assert.equal((await f.service.copyImage({ imageUrl: `data:image/png;base64,${encoded}`, isPrivate: true })).ok, true);
    assert.equal((await f.service.copyImage({ imageUrl: 'blob:https://page.example.test/id', isPrivate: true })).ok, false);
    assert.equal(f.requests.length, 0); assert.equal(f.cookies.length, 0);
    console.log('PASS data images preserve bytes and renderer-owned blob URLs never enter native HTTP');
  }
  {
    const f = environment(), inputs = [];
    f.menu.resolveImageUrl = () => imageUrl; f.menu.isWebImageContext = () => true;
    f.menu.imageActionService = {
      saveToGallery: async input => { inputs.push(input); return { ok: true, message: 'saved' }; },
      copyImage: async input => { inputs.push(input); return { ok: true, message: 'copied' }; },
      shareImage: async input => { inputs.push(input); return { ok: true, message: 'shared' }; }
    };
    const sourceUa = f.menu.resolveDownloadUserAgent({ getCustomUserAgent: () => 'Source custom UA', getUserAgent: () => 'default UA' });
    for (const boundary of [{ privacyMode: 'private', dataScope: 'session_ephemeral' },
      { privacyMode: 'regular', dataScope: 'session_ephemeral' }]) {
      const captured = f.menu.buildImageState({ tabId: 'source-tab', pageTitle: 'Page',
        pageUrl: 'https://source.example.test/page', userAgent: sourceUa, ...boundary,
        event: { param: { x: () => 1, y: () => 2 } } });
      for (const action of ['save_image', 'copy_image', 'share_image']) await f.menu.executeImageAction(action, captured,
        { activeTabId: 'other-tab', pageUrl: 'https://other.example.test', privacyMode: 'regular', dataScope: 'profile_persistent' });
    }
    assert.equal(inputs.length, 6);
    for (const input of inputs) {
      assert.equal(input.tabId, 'source-tab'); assert.equal(input.pageUrl, 'https://source.example.test/page');
      assert.equal(input.userAgent, 'Source custom UA'); assert.equal(input.isPrivate, true);
    }
    console.log('PASS save, copy and share keep captured tab/page/UA/privacy after active-page facts change');
  }
  console.log('Web image context checks passed (5 scenarios).');
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
