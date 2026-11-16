const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const vm = require('node:vm');
const ts = require('./lib/deveco-typescript.cjs');

const etsRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');

function load(relative, dependencies = {}, extension = '.ets') {
  const filename = path.join(etsRoot, relative + extension);
  const { outputText } = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  });
  const exports = {};
  vm.runInNewContext(outputText, {
    exports, $r: value => value,
    require: name => dependencies[name] ?? {}
  }, { filename });
  return exports;
}

const settle = () => new Promise(resolve => setImmediate(resolve));

test('toolbar sharing has one entry and migrates old Copy Link placements', () => {
  const text = load('core/browser/BrowserBottomPanelText');
  const { BrowserBottomPanelActionCatalog: Catalog } = load('core/browser/BrowserBottomPanelActionCatalog', {
    './BrowserBottomPanelText': text
  });
  assert.deepEqual(Array.from(Catalog.customizableActionIds()).filter(id => id === 'copyLink' || id === 'share'),
    ['share']);
  assert.equal(text.bottomPanelActionTitle('share'), 'app.string.bottom_panel_action_share');

  const { PreferencesRepository } = load('data/preferences/PreferencesRepository');
  const preferences = Object.create(PreferencesRepository.prototype);
  const normalized = preferences.normalizeToolbarLayoutSettings({
    primaryActionIds: ['bookmark', 'copyLink', 'print', 'share'],
    secondaryActionIds: ['home', 'share'],
    leadingSlotActionId: 'copyLink',
    tabsSlotSwipeUpActionId: 'copyLink',
    splitWebMenuLongPressActionId: 'copyLink'
  });
  assert.deepEqual(Array.from(normalized.primaryActionIds.slice(0, 3)), ['bookmark', 'share', 'print']);
  assert.equal(normalized.primaryActionIds.filter(id => id === 'share').length, 1);
  assert.deepEqual(Array.from(normalized.secondaryActionIds), ['home']);
  assert.equal(normalized.leadingSlotActionId, 'share');
  assert.equal(normalized.tabsSlotSwipeUpActionId, 'share');
  assert.equal(normalized.splitWebMenuLongPressActionId, 'share');
});

test('the merged toolbar action opens page sharing while the address editor still copies', async () => {
  const { BrowserRootBottomPanelFixedActionApplication: Application } = load(
    'core/browser/BrowserRootBottomPanelActionApplication', {
      './BrowserBottomPanelActionPresentationCoordinator': {
        BrowserBottomPanelActionPresentationCoordinator: class {
          resolveTarget(facts) { return { url: facts.currentUrl }; }
        }
      }
    });
  const url = 'https://example.org/page?source=toolbar#section';
  const context = {};
  const commands = [];
  const app = new Application({
    pageShareCoordinator: { open: (...args) => commands.push(['open', ...args]) },
    clipboardService: { async copyText({ value }) { commands.push(['copy', value]); return { message: '' }; } }
  }, {
    readFacts: () => ({ context, currentUrl: url, currentTitle: 'Example', tabs: [] }),
    resolveCurrentPageActionUrl: () => url,
    showToast() {}
  });
  app.apply({ lane: 'web', actionId: 'share' }, false);
  app.apply({ lane: 'header', actionId: 'copyAddress' }, false);
  await settle();
  assert.deepEqual(commands, [['open', context, 'Example', url], ['copy', url]]);
});

test('the dialog operates on the original page and ignores QR generation after dismissal', async () => {
  const { BrowserPageShareCoordinator } = load('core/browser/BrowserPageShareCoordinator');
  const events = [];
  const pendingQr = [];
  const coordinator = new BrowserPageShareCoordinator(
    { async copyText({ value }) { events.push(['copy', value]); return { ok: true, message: 'copied' }; } },
    { async shareWebPage(_context, request) { events.push(['share', request.title, request.url]); } },
    {
      generate: url => new Promise(resolve => pendingQr.push([url, resolve])),
      async saveToGallery(_context, qr) { events.push(['save', qr.source]); return true; }
    },
    {
      publishSnapshot: state => events.push(['state', state]),
      openDialog: () => events.push(['open']),
      closeDialog: () => events.push(['close']),
      showToast: () => {}
    }
  );
  const first = 'https://example.org/old';
  const current = 'https://example.org/current';
  coordinator.open({}, 'Old', first);
  coordinator.close();
  coordinator.handleDidDisappear();
  coordinator.open({}, 'Current', current);
  assert.deepEqual(pendingQr.map(([url]) => url), [first, current]);
  pendingQr[0][1]({ source: 'old image' });
  await settle();
  assert.equal(events.filter(([kind]) => kind === 'state').at(-1)[1].qrSource, '');
  pendingQr[1][1]({ source: 'current image' });
  await settle();
  coordinator.handleAction('save_qr');
  coordinator.handleAction('system_share');
  coordinator.handleAction('copy');
  await settle();
  assert.deepEqual(events.filter(([kind]) => ['save', 'share', 'copy'].includes(kind)),
    [['save', 'current image'], ['share', 'Current', current], ['copy', current]]);
});

test('QR generation works without Scan Kit, preserves UTF-8, and clears a cancelled gallery export', async () => {
  const events = [];
  const qrPng = new Uint8Array([1, 2, 3, 4]).buffer;
  const { qrcodegen } = load('services/share/vendor/QrCodeGenerator', {}, '.ts');
  const encodeBytes = qrcodegen.QrSegment.makeBytes;
  qrcodegen.QrSegment.makeBytes = bytes => {
    events.push(['encode', Buffer.from(bytes).toString('utf8')]);
    return encodeBytes(bytes);
  };
  const { WebPageQrCodeService } = load('services/share/WebPageQrCodeService', {
    './vendor/QrCodeGenerator': { qrcodegen },
    '@kit.ArkTS': { util: {
      TextEncoder: { create: () => ({ encodeInto: value => new TextEncoder().encode(value) }) },
      Base64Helper: class { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } },
      generateRandomUUID: () => 'temp'
    } },
    '@kit.ImageKit': { image: {
      PixelMapFormat: { RGBA_8888: 3 },
      AlphaType: { OPAQUE: 1 },
      async createPixelMapFromPixels(buffer, { size }) {
        const pixels = new Uint8Array(buffer);
        assert.equal(size.width, size.height);
        assert.equal(buffer.byteLength, size.width * size.height * 4);
        assert.ok(pixels.subarray(0, size.width * 4).every(value => value === 255));
        assert.ok(pixels.includes(0));
        assert.ok(pixels.every((value, index) => index % 4 !== 3 || value === 255));
        return { async release() {} };
      },
      createImagePacker: () => ({ async packToData() { return qrPng; }, async release() {} })
    } },
    '@kit.CoreFileKit': {
      fileUri: { getUriFromPath: value => 'file://' + value },
      fileIo: {
        OpenMode: { WRITE_ONLY: 1, CREATE: 2, TRUNC: 4 },
        async open(name) { events.push(['open', name]); return { fd: 5 }; },
        async write(_fd, bytes, { offset }) { events.push(['write', offset, bytes.byteLength]); return 2; },
        async close() {},
        async unlink(name) { events.push(['unlink', name]); }
      }
    },
    '@kit.MediaLibraryKit': { photoAccessHelper: {
      PhotoType: { IMAGE: 1 },
      getPhotoAccessHelper: () => ({
        async showAssetsCreationDialog(uris) { events.push(['gallery', uris[0]]); return []; }
      })
    } }
  });
  const url = 'https://example.org/' + '路径'.repeat(320) + '#section';
  const qr = await new WebPageQrCodeService().generate(url);
  assert.equal(qr.source, 'data:image/png;base64,AQIDBA==');
  assert.equal(await new WebPageQrCodeService().saveToGallery({ cacheDir: '/cache' }, qr), false);
  assert.deepEqual(events, [
    ['encode', url], ['open', '/cache/aira-qr-temp.png'], ['write', 0, 4], ['write', 2, 2],
    ['gallery', 'file:///cache/aira-qr-temp.png'], ['unlink', '/cache/aira-qr-temp.png']
  ]);
});
