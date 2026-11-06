#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const ts = require('./lib/deveco-typescript.cjs');
const { JSDOM } = require('jsdom');
const sourceRoot = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const inertModule = new Proxy({}, { get: () => class {} });
const cache = new Map();
const baseline = process.argv.includes('--baseline');

function load(relativePath) {
  const filename = path.join(sourceRoot, relativePath);
  if (cache.has(filename)) return cache.get(filename);
  const exports = {};
  cache.set(filename, exports);
  let source = fs.readFileSync(filename, 'utf8');
  if (baseline && !filename.endsWith('WebLinkTextScriptService.ets')) {
    source = execFileSync('git', ['show', 'HEAD:' + path.relative(path.resolve(__dirname, '..'), filename)],
      { cwd: path.resolve(__dirname, '..'), encoding: 'utf8' });
  }
  const compiled = ts.transpileModule(source, {
    compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS }
  }).outputText;
  vm.runInNewContext(compiled, {
    exports, console, px2vp: value => value / 3, vp2px: value => value * 3, $r: value => value,
    require(name) {
      if (name.endsWith('/AppResourceText')) return { resolveAppResourceText: value => value };
      if (name.endsWith('/BrowserWindowRuntime')) return {
        BrowserWindowRuntime: { resolveActiveShellPresentationSurface: () => 'compact' }
      };
      if (name === '@kit.ArkWeb') return { webview: { WebHitTestType: { HttpAnchor: 1, Img: 2, HttpAnchorImg: 3 } } };
      if (/WebContextMenuOverlayCoordinator|BrowserDesktopMenuPresentationTokens|WebLinkText(ScriptService|SelectionCoordinator|SelectionScriptService)/.test(name)) {
        return load(path.relative(sourceRoot, path.resolve(path.dirname(filename), name + '.ets')));
      }
      return inertModule;
    }
  }, { filename });
  return exports;
}

const { WebContextMenuOverlayCoordinator } = load('core/web/WebContextMenuOverlayCoordinator.ets');
const coordinator = new WebContextMenuOverlayCoordinator();
const { WebLinkContextMenuCoordinator } = load('core/web/WebLinkContextMenuCoordinator.ets');
const { WebLinkContextMenuFixedActionApplication } = load('core/web/WebLinkContextMenuActionApplication.ets');
const { WebLinkTextScriptService } = load('services/web/WebLinkTextScriptService.ets');
const { BrowserWebEventHostCoordinator } = load('core/browser/BrowserWebEventHostCoordinator.ets');
const { buildGenerationBoundHostedWebNodeCallbacks } = load('core/browser/BrowserHostedWebNodeGenerationCallbacks.ets');
const textService = new WebLinkTextScriptService();
const linkUrl = 'https://example.test/article';
const facts = { activeTabId: 'source', showPageErrorSurface: false, tabTitle: 'Entire page title', currentTitle: '',
  pageUrl: 'https://page.example.test/', privacyMode: 'normal', dataScope: 'persistent',
  viewport: { rootWidthVp: 390, rootHeightVp: 844, hostedWebLayerMeasured: true,
    hostedWebLayerLeftVp: 0, hostedWebLayerTopVp: 48, hostedWebLayerWidthVp: 390,
    hostedWebLayerHeightVp: 760, webViewportTopInsetVp: 48, webViewportBottomInsetVp: 156 } };

function fixture(read = () => Promise.resolve(JSON.stringify('Pressed link text')),
  extraItems = []) {
  const copied = [];
  const shared = [], searched = [], toasts = [];
  const actionFacts = { context: { id: 'test-ability' }, activeTabId: 'source',
    homeShortcutScenarioId: '', selectedSearchEngineId: 'bing' };
  const published = [];
  const scripts = [];
  let closed = 0;
  const application = new WebLinkContextMenuFixedActionApplication({
    clipboardService: { copyText: request => { copied.push(request.value); return Promise.resolve({ message: 'Copied' }); } },
    addressSubmissionCoordinator: { submitSelectedText: (...args) => searched.push(args) },
    webPageShareService: { sharePlainText: (context, title, text) => {
      shared.push({ context, title, text }); return Promise.resolve();
    }, shareWebPage() { assert.fail('selected text must not be shared as a link'); } }
  }, { readFacts: () => actionFacts, publishHelper() {}, showToast: value => toasts.push(value), publishError() {} });
  const menu = new WebLinkContextMenuCoordinator({
    userScriptRuntimeCoordinator: { buildContextMenuCommands: () => extraItems },
    webLoadRuntimeCoordinator: {}, appUrlOpenCoordinator: {}
  }, { publishPresentation: value => published.push(value) }, () => application);
  menu.privateWindowPolicyService = { resolveTarget: () => 'tab' };
  const event = { result: { closeContextMenu: () => { closed += 1; } }, param: {
    getLinkUrl: () => linkUrl, getSourceUrl: () => '', getUnfilteredLinkUrl: () => '',
    getMediaType: () => 0, x: () => 120, y: () => 1500
  } };
  const controller = { getLastHitTest: () => ({ type: 1, extra: linkUrl }),
    getCustomUserAgent: () => '', getUserAgent: () => 'UA', runJavaScript: script => { scripts.push(script); return read(script); } };
  return { menu, copied, shared, searched, actionFacts, application, toasts,
    event, controller, published, scripts, get closed() { return closed; },
    show: () => menu.show('source', event, controller, facts),
    get presentation() { return published.at(-1); },
    select(action) {
      const item = this.presentation.state.items.find(item => item.action === action);
      assert.ok(item, action + ' is missing');
      menu.handleOverlayAction({ type: 'select', item }, facts);
    }
  };
}

async function flush() { for (let i = 0; i < 40; i += 1) await Promise.resolve(); }

function pageFixture(text = 'Pressed link text', shadow = false, inFrame = false, options = {}) {
  const dom = new JSDOM('<!doctype html><body><a href="' + linkUrl + '"><span>' + text +
    '</span></a><p>Following paragraph text</p></body>', { runScripts: 'outside-only', pretendToBeVisual: true });
  const window = dom.window;
  let doc = window.document;
  let anchor = doc.querySelector('a');
  let iframe;
  let frameHeight = 80;
  if (inFrame) {
    iframe = doc.createElement('iframe'); doc.body.appendChild(iframe);
    doc = iframe.contentDocument; doc.body.innerHTML = anchor.outerHTML;
    anchor.remove(); anchor = doc.querySelector('a');
    iframe.getBoundingClientRect = () => ({ left: 10, top: 200, right: 210, bottom: 200 + frameHeight, width: 200, height: frameHeight });
    Object.defineProperty(doc.defaultView, 'innerWidth', { value: 200 });
    Object.defineProperty(doc.defaultView, 'innerHeight', { get: () => frameHeight });
  }
  const ownerView = doc.defaultView;
  if (options.cardWhitespace) anchor.innerHTML = '\n  <span>' + text + '</span>\n  ';
  let scrollY = 0;
  const textTop = inFrame ? 20 : 100;
  let textRoot = doc.body;
  let shadowHost;
  if (shadow) {
    shadowHost = doc.createElement('div'); doc.body.appendChild(shadowHost);
    textRoot = shadowHost.attachShadow({ mode: 'open' }); textRoot.appendChild(anchor);
    const selected = { range: null, get rangeCount() { return this.range ? 1 : 0; },
      get isCollapsed() { return !this.range || this.range.collapsed; },
      removeAllRanges() { this.range = null; }, addRange(range) { this.range = range; },
      getRangeAt() { return this.range; }, toString() { return this.range ? this.range.toString() : ''; } };
    // jsdom does not expose shadow-root selections; use real DOM Ranges with a Selection adapter.
    window.getSelection = () => selected;
    textRoot.elementFromPoint = () => anchor.firstChild;
  }
  const rect = (x, y, width, height) => ({ x, y, left: x, top: y, right: x + width, bottom: y + height, width, height });
  const textNodes = () => {
    const result = [], walker = doc.createTreeWalker(textRoot, 4);
    let node;
    while ((node = walker.nextNode())) result.push(node);
    return result;
  };
  const indexAt = (node, offset) => {
    const range = doc.createRange(); range.setStart(textRoot, 0); range.setEnd(node, offset);
    return (options.zeroWidthControls ? range.toString().replace(/\u200B/g, '') : range.toString()).length;
  };
  ownerView.HTMLElement.prototype.getClientRects = () => [rect(20, textTop - scrollY, 200, 20)];
  ownerView.Range.prototype.getClientRects = function () {
    if (this.collapsed && options.tallCollapsedCaret) return [rect(20, textTop - scrollY - 10, 200, 80)];
    const start = indexAt(this.startContainer, this.startOffset), end = indexAt(this.endContainer, this.endOffset);
    const result = [];
    let cursor = start;
    do {
      const finish = this.collapsed ? cursor : Math.min(end, (Math.floor(cursor / 20) + 1) * 20);
      result.push(rect(20 + cursor % 20 * 10, textTop - scrollY + Math.floor(cursor / 20) * 20, (finish - cursor) * 10, 20));
      cursor = finish;
    } while (cursor < end);
    return result;
  };
  ownerView.Range.prototype.getBoundingClientRect = function () {
    const rects = this.getClientRects();
    const left = Math.min(...rects.map(x => x.left)), top = Math.min(...rects.map(x => x.top));
    return rect(left, top, Math.max(...rects.map(x => x.right)) - left, Math.max(...rects.map(x => x.bottom)) - top);
  };
  doc.elementFromPoint = () => shadow ? shadowHost : anchor.firstChild;
  if (inFrame) window.document.elementFromPoint = () => iframe;
  doc.caretRangeFromPoint = (x, y) => {
    let index = Math.max(0, Math.floor((y - textTop + scrollY) / 20) * 20 + Math.round((x - 20) / 10));
    for (const node of textNodes()) {
      if (index <= node.data.length) {
        const range = doc.createRange(); range.setStart(node, index); range.collapse(true); return range;
      }
      index -= node.data.length;
    }
    return null;
  };
  if (shadow) doc.caretPositionFromPoint = (x, y, options) => {
    assert.ok(options.shadowRoots.includes(textRoot), 'shadow root must participate in caret hit testing');
    const range = doc.caretRangeFromPoint(x, y);
    return range ? { offsetNode: range.startContainer, offset: range.startOffset } : null;
  };
  Object.defineProperty(window, 'innerWidth', { value: 390 });
  const f = fixture(script => Promise.resolve(JSON.stringify(window.eval(script))));
  let latestFacts = facts;
  let generation = 1;
  const callbacks = buildGenerationBoundHostedWebNodeCallbacks('source', 1,
    new BrowserWebEventHostCoordinator().buildCallbacks({
      onLinkTextSelectionChanged: (tabId, json) => f.menu.handleTextSelectionSignal(tabId, json, latestFacts)
    }), (tabId, value) => tabId === 'source' && value === generation);
  window.__airaUserScriptNativeBridge = { linkTextSelectionChanged: json => callbacks.onLinkTextSelectionChanged?.('source', json) };
  return { ...f, dom, window, ownerView, anchor, menuFixture: f, setScrollY: value => { scrollY = value; },
    setFrameHeight: value => { frameHeight = value; }, setFacts: value => { latestFacts = value; },
    callbacks, replaceGeneration: () => { generation += 1; } };
}

let failures = 0;
async function check(name, action) {
  try { await action(); console.log('PASS ' + name); }
  catch (error) { failures += 1; console.error('FAIL ' + name + ': ' + error.message); }
}

async function main() {
  await check('long menu stays above the toolbar and below the top browser chrome', () => {
    const request = {
      point: { rawWebXPx: 120, rawWebYPx: 1500 },
      geometry: { rootWidthVp: 390, rootHeightVp: 844, webLeftVp: 0, webTopVp: 48,
        webWidthVp: 390, webHeightVp: 640 },
      itemCount: 30, dividerCount: 29, presentation: 'touch'
    };
    for (const layout of [coordinator.buildInitialLayout(request),
      coordinator.buildMeasuredLayout(request, { menuWidthVp: 248, menuHeightVp: 1800 })]) {
      assert.ok(layout.menuTopVp >= 56, 'menu crosses the top browser chrome');
      assert.ok(layout.menuTopVp + layout.menuHeightVp <= 680, 'menu crosses the bottom toolbar');
      assert.ok(layout.maxHeightVp <= 624, 'scroll limit ignores the visible Web viewport');
    }
  });

  await check('portrait, landscape, split windows and desktop retain every row in a bounded scroll surface', () => {
    for (const [width, height, top, bottom] of [[390, 844, 48, 156], [844, 390, 24, 64],
      [320, 360, 36, 80], [1280, 800, 72, 0]]) {
      for (const presentation of ['touch', 'desktop']) {
        for (const y of [0, (height - top) / 2, height - top]) {
          const request = { point: { rawWebXPx: width * 3, rawWebYPx: y * 3 },
            geometry: { rootWidthVp: width, rootHeightVp: height, webLeftVp: 0, webTopVp: top,
              webWidthVp: width, webHeightVp: height - top,
              availableTopVp: top, availableBottomVp: height - bottom },
            itemCount: 40, dividerCount: 5, presentation };
          const initial = coordinator.buildInitialLayout(request);
          const measured = coordinator.buildMeasuredLayout(request,
            { menuWidthVp: initial.menuWidthVp, menuHeightVp: initial.menuHeightVp });
          assert.equal(measured.menuTopVp, initial.menuTopVp, 'measurement makes the menu jump');
          assert.equal(measured.menuHeightVp, initial.menuHeightVp, 'measurement changes its height');
          assert.ok(initial.menuTopVp >= top + 8);
          assert.ok(initial.menuTopVp + initial.menuHeightVp <= height - bottom - 8);
          assert.ok(initial.menuLeftVp >= 8);
          assert.ok(initial.menuLeftVp + initial.menuWidthVp <= width - 8);
          assert.ok(initial.menuHeightVp < 40 * 44, 'long content must scroll');
        }
      }
    }
  });

  await check('pressed anchor text is copied separately from its URL and the page title', async () => {
    const f = fixture();
    assert.equal(f.show(), true);
    await Promise.resolve();
    f.select('copy_link_text');
    assert.deepEqual(f.copied, ['Pressed link text']);
    assert.equal(f.presentation.state.visible, false);
    assert.equal(f.closed, 1);
    f.show();
    f.select('copy_link');
    assert.deepEqual(f.copied, ['Pressed link text', linkUrl]);
    assert.equal(f.closed, 2);
  });

  await check('selection creates its range in the original Web document', async () => {
    const page = pageFixture();
    const f = page.menuFixture;
    f.show();
    await Promise.resolve();
    f.select('select_link_text');
    assert.equal(f.presentation.state.visible, true);
    assert.equal(f.presentation.state.selectingText, true);
    await flush();
    assert.equal(page.window.getSelection().toString(), 'Pressed link text');
    assert.ok(f.presentation.state.selection, 'native handles are missing');
    assert.equal(f.closed, 1);
    assert.ok(f.scripts.some(script => script.includes('__airaLinkTextSelection')), 'selection never reaches the original Web document');
    assert.equal(f.closed, 1, 'native context menu closes only once');
    f.menu.dismiss();
    page.window.close();
  });

  await check('card-formatting whitespace and block-sized collapsed carets never determine handle height', async () => {
    const page = pageFixture('Pressed link text', false, false, { cardWhitespace: true, tallCollapsedCaret: true });
    const f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    assert.equal(f.presentation.state.selection.start.heightVp, 20, 'start handle uses the whole card height');
    assert.equal(f.presentation.state.selection.end.heightVp, 20, 'end handle uses the whole card height');
    assert.equal(page.window.getSelection().toString(), 'Pressed link text');
    f.menu.dismiss(); page.window.close();
  });

  await check('dragging through a rendered space keeps the handles and selection alive', async () => {
    const page = pageFixture('a b'), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    f.menu.handleOverlayAction({ type: 'selection_drag_start', handle: 'end' }, facts);
    f.menu.handleOverlayAction({ type: 'selection_drag_end', handle: 'end', offsetXVp: -10 }, facts);
    await flush();
    f.menu.handleOverlayAction({ type: 'selection_drag_start', handle: 'start' }, facts);
    f.menu.handleOverlayAction({ type: 'selection_drag_end', handle: 'start', offsetXVp: 10 }, facts);
    await flush();
    assert.equal(f.presentation.state.visible, true);
    assert.equal(page.window.getSelection().toString(), ' ');
    assert.equal(f.presentation.state.selection.start.heightVp, 20);
    f.menu.dismiss(); page.window.close();
  });

  await check('a zero-width character at the edge uses the next visible glyph in the same text node', async () => {
    const page = pageFixture('word\u200B', false, false, { zeroWidthControls: true }), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    assert.equal(f.presentation.state.visible, true);
    assert.equal(f.presentation.state.selection.start.heightVp, 20);
    assert.equal(f.presentation.state.selection.end.heightVp, 20);
    assert.equal(f.presentation.state.selection.end.xVp, 60);
    f.menu.dismiss(); page.window.close();
  });

  await check('scroll updates use the current native Web bounds after browser chrome moves', async () => {
    const page = pageFixture(), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    const before = f.presentation.state.selection.start.yVp;
    page.setFacts({ ...facts, viewport: { ...facts.viewport, hostedWebLayerTopVp: 72, webViewportTopInsetVp: 72 } });
    page.window.dispatchEvent(new page.window.Event('scroll'));
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(f.presentation.state.selection.start.yVp, before + 24, 'handles remain at the old Web origin');
    f.menu.dismiss(); page.window.close();
  });

  await check('page scroll moves both selection handles and toolbar through the real tab callback chain', async () => {
    const page = pageFixture(), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    const before = f.presentation.state.selection;
    for (const scrollY of [10, 20, 0]) {
      page.setScrollY(scrollY);
      page.window.dispatchEvent(new page.window.Event('scroll'));
      await new Promise(resolve => setTimeout(resolve, 25));
      const after = f.presentation.state.selection;
      assert.equal(after.start.yVp, before.start.yVp - scrollY, 'start handle stays at its old screen location');
      assert.equal(after.end.yVp, before.end.yVp - scrollY, 'end handle stays at its old screen location');
      assert.equal(after.toolbarTopVp, before.toolbarTopVp - scrollY, 'selection toolbar stays at its old screen location');
    }
    f.menu.dismiss(); page.window.close();
  });

  await check('tapping page whitespace dismisses native selection controls through the real tab callback chain', async () => {
    const page = pageFixture(), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    page.window.document.body.dispatchEvent(new page.window.MouseEvent('pointerdown',
      { bubbles: true, clientX: 350, clientY: 500 }));
    page.window.document.body.dispatchEvent(new page.window.MouseEvent('pointerup',
      { bubbles: true, clientX: 350, clientY: 500 }));
    await flush();
    assert.equal(f.presentation.state.visible, false, 'native handles and menu remain visible after the DOM selection closes');
    assert.equal(page.window.getSelection().rangeCount, 0);
    assert.equal(page.window.__airaLinkTextSelection, undefined);
    page.window.close();
  });

  await check('selection notifications from another tab or an obsolete Web generation cannot dismiss the active controls', async () => {
    const page = pageFixture(), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    const inactive = JSON.stringify({ sessionId: page.window.__airaLinkTextSelection.id, active: false, revision: 1000 });
    page.callbacks.onLinkTextSelectionChanged('another', inactive);
    assert.equal(f.presentation.state.visible, true);
    page.replaceGeneration();
    page.callbacks.onLinkTextSelectionChanged('source', inactive);
    assert.equal(f.presentation.state.visible, true, 'a replaced Web generation dismissed the native controls');
    assert.equal(page.window.getSelection().toString(), 'Pressed link text');
    f.menu.dismiss(); page.window.close();
  });

  await check('native handle geometry uses reactive component props instead of frozen builder arguments', () => {
    const overlay = fs.readFileSync(path.join(sourceRoot, 'app/components/browser/WebLinkTextSelectionOverlay.ets'), 'utf8');
    assert.doesNotMatch(overlay, /@Builder\s+private buildHandle\(point:/,
      'value parameters in a multi-argument Builder do not refresh their UI');
    assert.match(overlay, /@Prop xVp: number/);
    assert.match(overlay, /@Prop yVp: number/);
    assert.match(overlay, /@Prop heightVp: number/);
  });

  await check('dragging in-page handles copies the selected part and cleans the original document', async () => {
    const page = pageFixture();
    const f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    for (const type of ['selection_drag_start', 'selection_drag_update', 'selection_drag_end']) {
      f.menu.handleOverlayAction({ type, handle: 'start', offsetXVp: type.endsWith('start') ? 0 : 80, offsetYVp: 0 }, facts);
    }
    await flush();
    assert.equal(page.window.getSelection().toString(), 'link text');
    f.menu.handleOverlayAction({ type: 'copy_selection' }, facts);
    await flush();
    assert.deepEqual(f.copied, ['link text']);
    assert.equal(f.presentation.state.visible, false);
    assert.equal(page.window.getSelection().rangeCount, 0);
    assert.equal(page.window.__airaLinkTextSelection, undefined);
    assert.equal(page.anchor.style.getPropertyValue('user-select'), '');
    page.window.close();
  });

  await check('share and search use the current selected portion and dismiss the in-page controls', async () => {
    for (const type of ['share_selection', 'search_selection']) {
      const page = pageFixture(), f = page.menuFixture;
      f.show(); await flush(); f.select('select_link_text'); await flush();
      f.menu.handleOverlayAction({ type: 'selection_drag_start', handle: 'start' }, facts);
      f.menu.handleOverlayAction({ type: 'selection_drag_end', handle: 'start', offsetXVp: 80 }, facts);
      await flush();
      f.actionFacts.selectedSearchEngineId = 'custom_docs';
      f.menu.handleOverlayAction({ type }, facts); await flush();
      if (type === 'share_selection') {
        assert.deepEqual(f.shared, [{ context: f.actionFacts.context, title: 'Entire page title', text: 'link text' }]);
        assert.equal(f.searched.length, 0);
      } else {
        assert.deepEqual(f.searched, [['source', 'link text', 'custom_docs']]);
        assert.equal(f.shared.length, 0);
      }
      assert.equal(f.presentation.state.visible, false);
      assert.equal(page.window.getSelection().rangeCount, 0);
      page.window.close();
    }
  });

  await check('the floating menu exposes copy, select all, share and browser search with no Done button', () => {
    const source = fs.readFileSync(path.join(sourceRoot, 'app/components/browser/WebLinkTextSelectionOverlay.ets'), 'utf8');
    const actions = [...source.matchAll(/\.onClick\(\(\) => this\.onAction\(\{ type: '([^']+)'/g)].map(match => match[1]);
    assert.deepEqual(actions, ['copy_selection', 'select_all_text', 'share_selection', 'search_selection']);
    assert.doesNotMatch(source, /app\.string\.ui_done/);
    const f = fixture();
    f.actionFacts.activeTabId = 'another';
    f.application.applyEffects([{ type: 'share_text', tabId: 'source', text: 'stale selection' },
      { type: 'search_text', tabId: 'source', text: 'stale selection' }]);
    assert.equal(f.shared.length, 0); assert.equal(f.searched.length, 0);
  });

  await check('select-all restores the pressed link and reverse drags keep an ordered range', async () => {
    const page = pageFixture();
    const f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    f.menu.handleOverlayAction({ type: 'selection_drag_start', handle: 'start' }, facts);
    f.menu.handleOverlayAction({ type: 'selection_drag_end', handle: 'start', offsetXVp: 190 }, facts);
    await flush();
    assert.equal(page.window.getSelection().toString(), 'Fo');
    f.menu.handleOverlayAction({ type: 'select_all_text' }, facts);
    await flush();
    assert.equal(page.window.getSelection().toString(), 'Pressed link text');
    f.menu.dismiss(); page.window.close();
  });

  await check('shadow-root link handles update the original range and copy partial text', async () => {
    const page = pageFixture('Pressed link text', true), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    f.menu.handleOverlayAction({ type: 'selection_drag_start', handle: 'start' }, facts);
    f.menu.handleOverlayAction({ type: 'selection_drag_update', handle: 'start', offsetXVp: 80 }, facts);
    f.menu.handleOverlayAction({ type: 'selection_drag_end', handle: 'start' }, facts);
    await flush();
    assert.equal(page.window.getSelection().toString(), 'link text', 'cancel/end retains the last drag position');
    f.menu.handleOverlayAction({ type: 'copy_selection' }, facts); await flush();
    assert.deepEqual(f.copied, ['link text']);
    page.window.close();
  });

  await check('selection controls stop touches before the Web while the empty overlay stays transparent', () => {
    const overlay = fs.readFileSync(path.join(sourceRoot, 'app/components/browser/WebLinkTextSelectionOverlay.ets'), 'utf8');
    assert.match(overlay, /toolbarLeftVp[\s\S]*?hitTestBehavior\(HitTestMode\.BLOCK_HIERARCHY\)/);
    assert.match(overlay, /this\.xVp - 22[\s\S]*?hitTestBehavior\(HitTestMode\.BLOCK_HIERARCHY\)/);
    assert.match(overlay, /hitTestBehavior\(HitTestMode\.Transparent\)/);
    assert.doesNotMatch(overlay, /hitTestBehavior\(HitTestMode\.Block\)/);
    const { BrowserWebEventHostCoordinator } = load('core/browser/BrowserWebEventHostCoordinator.ets');
    const received = [];
    new BrowserWebEventHostCoordinator().buildCallbacks({
      onLinkTextSelectionChanged: (tabId, payload) => received.push([tabId, payload])
    }).onLinkTextSelectionChanged('source', '{"active":true}');
    assert.deepEqual(received, [['source', '{"active":true}']]);
  });

  await check('iframe selections hide clipped controls and dismiss on taps in the parent document', async () => {
    const page = pageFixture('Pressed link text', false, true), f = page.menuFixture;
    f.show(); await flush(); f.select('select_link_text'); await flush();
    assert.equal(page.ownerView.getSelection().toString(), 'Pressed link text');
    assert.equal(f.presentation.state.selection.toolbarVisible, true);
    page.setFrameHeight(10);
    page.ownerView.dispatchEvent(new page.ownerView.Event('resize'));
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(f.presentation.state.selection.toolbarVisible, false, 'iframe resize invalidates the clip');
    page.setFrameHeight(80);
    page.ownerView.dispatchEvent(new page.ownerView.Event('resize'));
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(f.presentation.state.selection.toolbarVisible, true);
    page.setScrollY(100);
    page.ownerView.dispatchEvent(new page.ownerView.Event('scroll'));
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.equal(f.presentation.state.selection.toolbarVisible, false, 'off-frame text has no floating toolbar');
    assert.equal(f.presentation.state.selection.start.visible, false);
    assert.equal(f.presentation.state.selection.end.visible, false);
    page.window.document.dispatchEvent(new page.window.MouseEvent('pointerdown', { clientX: 300, clientY: 400 }));
    page.window.document.dispatchEvent(new page.window.MouseEvent('pointerup', { clientX: 300, clientY: 400 }));
    await flush();
    assert.equal(f.presentation.state.visible, false);
    assert.equal(page.ownerView.getSelection().rangeCount, 0);
    page.window.close();
  });

  await check('overflow-clipped link text does not leave handles on unrelated content', async () => {
    const page = pageFixture(), f = page.menuFixture;
    const container = page.window.document.createElement('div');
    container.style.overflow = 'hidden';
    container.getBoundingClientRect = () => ({ left: 0, top: 90, right: 100, bottom: 140, width: 100, height: 50 });
    Object.defineProperty(container, 'clientWidth', { value: 100 });
    Object.defineProperty(container, 'clientHeight', { value: 50 });
    page.anchor.parentElement.appendChild(container); container.appendChild(page.anchor);
    f.show(); await flush(); f.select('select_link_text'); await flush();
    assert.equal(f.presentation.state.selection.start.visible, true);
    assert.equal(f.presentation.state.selection.end.visible, false);
    f.menu.dismiss(); page.window.close();
  });

  await check('overflow on a visible inline link does not invent an empty clipping box', async () => {
    const page = pageFixture(), f = page.menuFixture;
    page.anchor.style.display = 'inline'; page.anchor.style.overflow = 'hidden';
    f.show(); await flush(); f.select('select_link_text'); await flush();
    assert.equal(f.presentation.state.selection.toolbarVisible, true);
    assert.equal(f.presentation.state.selection.start.visible, true);
    assert.equal(f.presentation.state.selection.end.visible, true);
    f.menu.dismiss(); page.window.close();
  });

  await check('menus and in-page selections close on tab change, including delayed text results', async () => {
    let resolveText;
    const f = fixture(() => new Promise(resolve => { resolveText = resolve; }));
    f.show();
    f.menu.handleActiveTabChanged('another');
    assert.equal(f.presentation.state.visible, false);
    resolveText('"Old tab text"'); await flush();
    assert.equal(f.presentation.state.visible, false);
    assert.equal(f.menu.show('source', f.event, f.controller, { ...facts, activeTabId: 'another' }), false);
    const page = pageFixture(), selected = page.menuFixture;
    selected.show(); await flush(); selected.select('select_link_text'); await flush();
    selected.menu.handleActiveTabChanged('another'); await flush();
    assert.equal(selected.presentation.state.visible, false);
    assert.equal(page.window.getSelection().rangeCount, 0);
    assert.equal(page.window.__airaLinkTextSelection, undefined);
    page.window.close();
    const shell = fs.readFileSync(path.join(sourceRoot, 'app/pages/BrowserShellPage.ets'), 'utf8');
    assert.match(shell, /@Watch\('reconcileShellTabPresentation'\) activeTabId/);
    assert.match(shell, /reconcileShellTabPresentation\(\): void \{\s*this\.webContextMenuCoordinator\?\.handleActiveTabChanged\(this\.activeTabId\)/);
  });

  await check('an open menu follows window resize and expands again when space returns', async () => {
    const f = fixture();
    f.show();
    await Promise.resolve();
    const portraitHeight = f.presentation.layout.menuHeightVp;
    const compactFacts = { ...facts, viewport: { ...facts.viewport, rootHeightVp: 360,
      hostedWebLayerHeightVp: 312, webViewportBottomInsetVp: 80 } };
    f.menu.handleOverlayAction({ type: 'viewport_changed' }, compactFacts);
    assert.ok(f.presentation.layout.menuTopVp + f.presentation.layout.menuHeightVp <= 272);
    assert.ok(f.presentation.layout.menuHeightVp < portraitHeight);
    f.menu.handleOverlayAction({ type: 'viewport_changed' }, facts);
    assert.equal(f.presentation.layout.menuHeightVp, portraitHeight);
  });

  await check('common tab and text actions precede saving, private browsing and userscript commands', async () => {
    const f = fixture(undefined, [{ scriptId: 's', commandId: 'c', title: 'Script command' }]);
    f.show();
    await Promise.resolve();
    const actions = Array.from(f.presentation.state.items, item => item.action);
    assert.deepEqual(actions.slice(0, 2), ['open_new_tab', 'open_background_tab']);
    assert.ok(actions.indexOf('copy_link_text') < actions.indexOf('add_bookmark'));
    assert.ok(actions.indexOf('select_link_text') < actions.indexOf('open_private_tab'));
    assert.equal(actions.at(-1), 'run_userscript');
    assert.ok(f.presentation.layout.menuTopVp + f.presentation.layout.menuHeightVp <= 680);
  });

  await check('empty or unavailable link text keeps URL actions and omits text actions', async () => {
    for (const read of [() => Promise.resolve('""'), () => Promise.reject(new Error('Detached Web'))]) {
      const f = fixture(read);
      f.show();
      await Promise.resolve();
      assert.equal(f.presentation.state.items.some(item => item.action === 'copy_link_text'), false);
      f.select('copy_link');
      assert.deepEqual(f.copied, [linkUrl]);
    }
  });

  await check('late JavaScript results cannot reopen a dismissed menu or overwrite another long press', async () => {
    const resolvers = [];
    const f = fixture(() => new Promise(resolve => resolvers.push(resolve)));
    f.show();
    f.menu.dismiss();
    resolvers[0]('"Old text"');
    await Promise.resolve();
    assert.equal(f.presentation.state.visible, false);
    f.show();
    f.show();
    resolvers[1]('"Stale text"');
    await Promise.resolve();
    assert.equal(f.presentation.state.linkText, undefined);
    resolvers[2]('"Current text"');
    await Promise.resolve();
    assert.equal(f.presentation.state.linkText, 'Current text');
  });

  await check('link text arriving after resize uses the current window bounds', async () => {
    let resolveText;
    const f = fixture(() => new Promise(resolve => { resolveText = resolve; }));
    f.show();
    const compactFacts = { ...facts, viewport: { ...facts.viewport, rootHeightVp: 360,
      hostedWebLayerHeightVp: 312, webViewportBottomInsetVp: 80 } };
    f.menu.handleOverlayAction({ type: 'viewport_changed' }, compactFacts);
    resolveText('"Late text"');
    await Promise.resolve();
    assert.equal(f.presentation.state.linkText, 'Late text');
    assert.ok(f.presentation.layout.menuTopVp + f.presentation.layout.menuHeightVp <= 272);
  });

  await check('script reads nested link text at the press point, including same-origin frames and shadow DOM', () => {
    const anchor = { tagName: 'A', href: linkUrl, innerText: ' Visible link text ', textContent: 'Other text' };
    const inline = { tagName: 'SPAN', parentElement: anchor };
    const points = [];
    const document = { elementFromPoint: (x, y) => { points.push([x, y]); return inline; } };
    const script = textService.buildReadScript(linkUrl, 120, 1500, 1170);
    const run = doc => vm.runInNewContext(script, { document: doc, window: { innerWidth: 390 } });
    assert.equal(run(document), 'Visible link text');
    assert.ok(Math.abs(points[0][0] - 40) < 0.001);
    assert.ok(Math.abs(points[0][1] - 500) < 0.001);
    vm.runInNewContext(script, { document, window: { innerWidth: 390,
      visualViewport: { width: 195, offsetLeft: 80, offsetTop: 120 } } });
    assert.ok(Math.abs(points.at(-1)[0] - 100) < 0.001, 'pinch zoom must include the visual viewport X offset');
    assert.ok(Math.abs(points.at(-1)[1] - 370) < 0.001, 'pinch zoom must include the visual viewport Y offset');
    const frame = { tagName: 'IFRAME', contentDocument: document,
      clientLeft: 1, clientTop: 1, getBoundingClientRect: () => ({ left: 10, top: 20 }) };
    assert.equal(run({ elementFromPoint: () => frame }), 'Visible link text');
    assert.equal(run({ elementFromPoint: () => ({ shadowRoot: { elementFromPoint: () => inline } }) }), 'Visible link text');
    assert.equal(run({ elementFromPoint: () => ({ ...anchor, href: 'https://example.test/another' }) }), '');
    assert.equal(run({ elementFromPoint: () => ({ ...frame, contentDocument: null }) }), '');
    assert.equal(textService.parseText(JSON.stringify('Line one\nLine two')), 'Line one\nLine two');
  });

  await check('image menus retain image actions without attempting to extract link text', () => {
    let reads = 0;
    const f = fixture(() => { reads += 1; return Promise.resolve('"text"'); });
    f.event.param.getSourceUrl = () => 'https://example.test/image.png';
    f.event.param.getMediaType = () => 1;
    f.controller.getLastHitTest = () => ({ type: 2, extra: 'https://example.test/image.png' });
    f.show();
    assert.equal(f.presentation.state.kind, 'image');
    assert.deepEqual(Array.from(f.presentation.state.items, item => item.action), ['save_image', 'copy_image', 'share_image']);
    assert.equal(reads, 0);
  });
  if (failures > 0) process.exitCode = 1;
}
main().catch(error => { console.error(error); process.exitCode = 1; });
