#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');
const ts = require('./lib/deveco-typescript.cjs');

const root = path.resolve(__dirname, '../AiraBrowser/entry/src/main/ets');
const cache = new Map();
function evaluate(source, filename, requireModule = () => { throw new Error('Unexpected dependency'); }) {
  const result = ts.transpileModule(source, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename, reportDiagnostics: true
  });
  assert.equal((result.diagnostics || []).filter(d => d.category === ts.DiagnosticCategory.Error).length, 0);
  const module = { exports: {} };
  vm.runInNewContext(result.outputText, { module, exports: module.exports, require: requireModule }, { filename });
  return module.exports;
}
function load(relative) {
  if (cache.has(relative)) return cache.get(relative);
  const filename = path.join(root, relative);
  const exports = evaluate(fs.readFileSync(filename, 'utf8'), filename, name => {
    assert.ok(name.startsWith('.'), `Unexpected dependency: ${name}`);
    return load(path.relative(root, path.resolve(path.dirname(filename), `${name}.ets`)));
  });
  cache.set(relative, exports);
  return exports;
}

const { ReadingDocumentPaginator } = load('features/reading/ReadingDocumentPaginator.ets');
const surfacePath = path.join(root, 'app/components/reading/ReadingSurface.ets');
const surfaceSource = fs.readFileSync(surfacePath, 'utf8');
// Execute the real Surface height calculation and pagination entry point without
// mounting ArkUI. Only native text measurement and scheduling are substituted.
const methods = ['repaginate', 'resolvePageChromeHeight'].map(name => {
  const match = surfaceSource.match(new RegExp(`  private ${name}\\([\\s\\S]*?\\n  }`));
  assert.ok(match, `Missing ReadingSurface method: ${name}`);
  return match[0];
}).join('\n');
const constants = surfaceSource.match(/^const READING_SURFACE_\w+: [^\n]+;$/gm).join('\n');
const { SurfaceHarness, chrome } = evaluate(`${constants}
export class SurfaceHarness { ${methods} }
export const chrome = {
  header: READING_SURFACE_PAGE_HEADER_HEIGHT,
  footer: READING_SURFACE_PAGE_FOOTER_HEIGHT,
  padding: READING_SURFACE_PAGE_VERTICAL_PADDING
};`, surfacePath);

function documentOf(blocks) {
  return { id: 'synthetic-reading', title: 'Pagination fixture', subtitle: '', blocks };
}
function paragraph(id, lines) {
  return { id, type: 'paragraph', text: '文'.repeat(lines * 10) };
}
function measureLines(lineHeight) {
  return (block, start, end) => {
    const lines = Math.ceil((end - start) / 10);
    return { height: lines * lineHeight, estimatedLineCount: lines };
  };
}
function usedHeight(page, document, metrics, measure) {
  return page.fragments.reduce((height, fragment, index) => height + (index ? metrics.blockSpacing : 0) +
    measure(document.blocks[fragment.blockIndex], fragment.startCharacterOffset,
      fragment.endCharacterOffset, metrics).height, 0);
}
function paginateSurface(document, fontSize = 20, fontScale = 1, lineHeight = 'normal') {
  const surface = new SurfaceHarness();
  const measure = measureLines(fontSize * fontScale * (lineHeight === 'loose' ? 1.9 : 1.65));
  Object.assign(surface, {
    mode: 'horizontal', document, contentWidthVp: 360, contentHeightVp: 800,
    appearance: { fontSize, lineHeight }, systemFontSizeScale: fontScale,
    options: { pageHeaderVisible: true, pageNumberVisible: true, contentTopInset: 20, contentBottomInset: 0 },
    paginationGeneration: 0, paginationRevision: 0,
    paginator: new ReadingDocumentPaginator(),
    documentFlow: { resolveInitialPaginationBlockCount: () => document.blocks.length },
    cancelDeferredPagination() {}, resolveAvailableContentWidth: () => 320,
    resolveSpreadIndexForLeafPage: index => index,
    paginateDocument(doc, metrics) {
      this.metrics = metrics;
      return this.paginator.paginate(doc, metrics, measure).pages;
    },
    handleLayoutFailure() { throw new Error('Unexpected pagination failure'); }
  });
  surface.repaginate({ documentId: document.id, blockId: document.blocks[0].id, characterOffset: 0 });
  return { surface, measure };
}

test('paged text uses the available body height instead of leaving an extra empty line', () => {
  const document = documentOf([paragraph('long', 100)]);
  for (const [fontSize, scale, spacing] of [[20, 1, 'normal'], [26, 1.3, 'loose']]) {
    const { surface, measure } = paginateSurface(document, fontSize, scale, spacing);
    const bodyHeight = surface.contentHeightVp - chrome.header - chrome.footer - 20 - chrome.padding * 2;
    const used = usedHeight(surface.pages[0], document, surface.metrics, measure);
    const oneLine = measure(document.blocks[0], 0, 10).height;
    assert.ok(used <= bodyHeight, 'text must not overlap the footer');
    assert.ok(bodyHeight - used < oneLine + 2,
      `unused body height ${bodyHeight - used} leaves a full extra line (${oneLine})`);
  }
});

test('a four-line paragraph can fill two remaining lines without leaving a one-line tail', () => {
  const document = documentOf([paragraph('intro', 2), paragraph('body', 4)]);
  const metrics = { contentWidth: 320, contentHeight: 100, blockSpacing: 10 };
  const result = new ReadingDocumentPaginator().paginate(document, metrics, measureLines(20));
  assert.equal(result.pages[0].fragments.length, 2, 'two available lines must not be left empty');
  assert.equal(result.pages[0].fragments[1].endCharacterOffset, 20);
  assert.equal(result.pages[1].fragments[0].startCharacterOffset, 20);
});

test('short paragraphs and one-line tails retain their reading protection', () => {
  const metrics = { contentWidth: 320, contentHeight: 100, blockSpacing: 10 };
  const measure = measureLines(20);
  for (const [introLines, bodyLines, expectedEnd] of [[2, 3, 0], [3, 4, 0], [1, 4, 20], [2, 5, 20]]) {
    const document = documentOf([paragraph('intro', introLines), paragraph('body', bodyLines)]);
    const result = new ReadingDocumentPaginator().paginate(document, metrics, measure);
    const body = result.pages[0].fragments.find(fragment => fragment.blockId === 'body');
    assert.equal(body?.endCharacterOffset || 0, expectedEnd);
    for (const page of result.pages) {
      assert.ok(usedHeight(page, document, metrics, measure) <= metrics.contentHeight);
    }
  }
});

test('reflow preserves every character and the anchor without overflowing the page', () => {
  const document = documentOf([paragraph('intro', 2), paragraph('short', 4),
    { id: 'long', type: 'paragraph', text: '春天的故事“从这里开始”，读到下一页也要连贯。🌿'.repeat(40) }]);
  const paginator = new ReadingDocumentPaginator();
  const measure = measureLines(20);
  for (const height of [90, 100, 160, 300]) {
    const metrics = { contentWidth: 320, contentHeight: height, blockSpacing: 10 };
    const { pages } = paginator.paginateCached(document, metrics, 'fixture', measure);
    for (const page of pages) {
      assert.ok(usedHeight(page, document, metrics, measure) <= height);
    }
    for (const block of document.blocks) {
      let offset = 0;
      for (const fragment of pages.flatMap(page => page.fragments).filter(fragment => fragment.blockId === block.id)) {
        assert.equal(fragment.startCharacterOffset, offset, 'no gap or repeated text at a page boundary');
        offset = fragment.endCharacterOffset;
        const nextCodeUnit = block.text.charCodeAt(offset);
        assert.ok(!(nextCodeUnit >= 0xDC00 && nextCodeUnit <= 0xDFFF), 'do not split an emoji');
      }
      assert.equal(offset, block.text.length);
      for (const characterOffset of [0, 17, block.text.length - 1]) {
        const page = pages[paginator.findPageForAnchor(pages, { blockId: block.id, characterOffset })];
        assert.ok(page.fragments.some(fragment => fragment.blockId === block.id &&
          fragment.startCharacterOffset <= characterOffset && fragment.endCharacterOffset > characterOffset));
      }
    }
  }
});

test('headings stay with following text and images remain atomic', () => {
  const document = documentOf([paragraph('intro', 3),
    { id: 'heading', type: 'heading', text: '章节标题' }, paragraph('body', 4),
    { id: 'image', type: 'image', text: '' }]);
  const metrics = { contentWidth: 320, contentHeight: 100, blockSpacing: 10 };
  const measure = (block, start, end) => block.type === 'image'
    ? { height: 80, estimatedLineCount: 0 } : measureLines(20)(block, start, end);
  const { pages } = new ReadingDocumentPaginator().paginate(document, metrics, measure);
  const headingPage = pages.find(page => page.fragments.some(fragment => fragment.blockId === 'heading'));
  assert.ok(headingPage.fragments.some(fragment => fragment.blockId === 'body'));
  const images = pages.flatMap(page => page.fragments).filter(fragment => fragment.blockId === 'image');
  assert.equal(images.length, 1);
  assert.equal(images[0].atomic, true);
  for (const page of pages) assert.ok(usedHeight(page, document, metrics, measure) <= metrics.contentHeight);
});
