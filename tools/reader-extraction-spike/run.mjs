import { execFile } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { build } from 'esbuild';
import { chromium } from 'playwright-core';
import { deterministicCorpus, liveCorpus } from './corpus.mjs';

const TOOL_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(TOOL_DIR, '../..');
const SERVICE_RELATIVE_PATH = 'AiraBrowser/entry/src/main/ets/services/web/ReaderExtractionService.ets';
const SERVICE_PATH = path.join(
  REPO_ROOT,
  SERVICE_RELATIVE_PATH
);
const BASELINE_COMMIT = 'cc1ea9244b041d761e525411dcb64deb1cd2163c';
const DEFAULT_CHROME_PATH = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const OUTPUT_DIR = path.join(REPO_ROOT, '.tmp/reader-extraction-spike');
const args = new Set(process.argv.slice(2));
const runFixtures = !args.has('--live-only');
const runLive = !args.has('--fixtures-only');
const caseArg = process.argv.slice(2).find((value) => value.startsWith('--case='));
const selectedCaseId = caseArg ? caseArg.slice('--case='.length).trim() : '';
const execFileAsync = promisify(execFile);

const normalizeText = (value) => String(value ?? '').replace(/\s+/g, ' ').trim();
const normalizeComparable = (value) => normalizeText(value).toLocaleLowerCase();

const median = (values) => {
  const sorted = values.filter(Number.isFinite).sort((left, right) => left - right);
  if (sorted.length === 0) {
    return 0;
  }
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle];
};

const round = (value, digits = 1) => {
  const scale = 10 ** digits;
  return Math.round(value * scale) / scale;
};

const markerHits = (text, markers) => {
  const normalized = normalizeComparable(text);
  return markers.filter((marker) => normalized.includes(normalizeComparable(marker)));
};

const ngrams = (text, size = 3) => {
  const normalized = normalizeComparable(text).replace(/\s+/g, '');
  const result = new Set();
  for (let index = 0; index <= normalized.length - size; index += 1) {
    result.add(normalized.slice(index, index + size));
  }
  return result;
};

const jaccard = (leftText, rightText) => {
  const left = ngrams(leftText);
  const right = ngrams(rightText);
  if (left.size === 0 && right.size === 0) {
    return 1;
  }
  let intersection = 0;
  left.forEach((item) => {
    if (right.has(item)) {
      intersection += 1;
    }
  });
  return (left.size + right.size - intersection) > 0 ? intersection / (left.size + right.size - intersection) : 0;
};

const instantiateService = async (buildOptions) => {
  const bundled = await build({
    ...buildOptions,
    bundle: true,
    format: 'esm',
    platform: 'node',
    write: false,
    loader: { '.ets': 'ts' },
    resolveExtensions: ['.ets', '.ts', '.js', '.json'],
    external: ['@kit.ArkWeb'],
    logLevel: 'silent'
  });
  const source = bundled.outputFiles[0].text;
  const dataUrl = `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`;
  const module = await import(dataUrl);
  return new module.ReaderExtractionService();
};

const buildProductionService = async () => instantiateService({
  entryPoints: [SERVICE_PATH]
});

const buildBaselineService = async () => {
  const { stdout } = await execFileAsync(
    'git',
    ['show', `${BASELINE_COMMIT}:${SERVICE_RELATIVE_PATH}`],
    { cwd: REPO_ROOT, encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 }
  );
  return instantiateService({
    stdin: {
      contents: stdout,
      resolveDir: path.dirname(SERVICE_PATH),
      sourcefile: `ReaderExtractionService-${BASELINE_COMMIT.slice(0, 8)}.ets`,
      loader: 'ts'
    }
  });
};

const buildReadabilityBrowserBundle = async () => {
  const bundled = await build({
    stdin: {
      contents: `import { Readability } from '@mozilla/readability';\n` +
        `globalThis.__airaSpikeReadability = Readability;`,
      resolveDir: TOOL_DIR,
      sourcefile: 'readability-spike-entry.js',
      loader: 'js'
    },
    bundle: true,
    format: 'iife',
    platform: 'browser',
    minify: true,
    write: false,
    logLevel: 'silent'
  });
  return bundled.outputFiles[0].text;
};

const articleTextFromAira = (article) => (article?.blocks ?? [])
  .map((block) => [block.text, block.caption, block.alt].filter(Boolean).join(' '))
  .join('\n');

const runAira = async (page, script) => {
  const startedAt = performance.now();
  try {
    const raw = await page.evaluate(script);
    const durationMs = performance.now() - startedAt;
    const rawText = String(raw ?? '{}');
    const article = JSON.parse(rawText);
    const blocks = Array.isArray(article.blocks) ? article.blocks : [];
    const text = articleTextFromAira(article);
    return {
      success: blocks.length > 0 && normalizeText(text).length > 0,
      durationMs: round(durationMs),
      title: normalizeText(article.title),
      byline: normalizeText(article.byline),
      publishedAt: normalizeText(article.publishedAt),
      siteName: normalizeText(article.siteName),
      text,
      textLength: normalizeText(text).length,
      blockCount: blocks.length,
      blocks,
      rawResultLength: rawText.length,
      blockTypes: blocks.map((block) => String(block.type ?? '')),
      imageCount: blocks.filter((block) => block.type === 'image').length,
      imageWithUrlCount: blocks.filter((block) => block.type === 'image' && normalizeText(block.url).length > 0).length,
      captionCount: blocks.filter((block) => block.type === 'image' && normalizeText(block.caption).length > 0).length,
      strategy: normalizeText(article.diagnostics?.extractionStrategy),
      adapterId: normalizeText(article.diagnostics?.adapterId),
      error: ''
    };
  } catch (error) {
    return {
      success: false,
      durationMs: round(performance.now() - startedAt),
      title: '',
      byline: '',
      publishedAt: '',
      siteName: '',
      text: '',
      textLength: 0,
      blockCount: 0,
      blocks: [],
      rawResultLength: 0,
      blockTypes: [],
      imageCount: 0,
      imageWithUrlCount: 0,
      captionCount: 0,
      strategy: '',
      adapterId: '',
      error: error instanceof Error ? error.message : String(error)
    };
  }
};

const runReadability = async (page) => {
  try {
    return await page.evaluate(() => {
      const startedAt = performance.now();
      try {
        const Constructor = globalThis.__airaSpikeReadability;
        if (typeof Constructor !== 'function') {
          throw new Error('Readability constructor is unavailable');
        }
        const clonedDocument = document.cloneNode(true);
        const removableSelectors = [
          'script', 'style', 'iframe', 'form', 'button', 'input', 'textarea', 'select',
          'nav', 'footer', 'aside', 'header',
          '[role="navigation"]', '[role="complementary"]', '[role="banner"]',
          '[role="contentinfo"]', '[role="search"]',
          '.ad', '.ads', '.advertisement', '.comment', '.comments', '.related', '.recommend', '.recommended',
          '.promo', '.popup', '.modal', '.share', '.toolbar', '.tool-bar', '.sidebar', '.login', '.reward',
          '.sponsor'
        ];
        removableSelectors.forEach((selector) => {
          Array.from(clonedDocument.querySelectorAll(selector)).forEach((node) => node.remove());
        });
        const article = new Constructor(clonedDocument, { charThreshold: 80 }).parse();
        const durationMs = performance.now() - startedAt;
        if (!article) {
          return {
            success: false,
            durationMs,
            title: '',
            byline: '',
            publishedAt: '',
            siteName: '',
            text: '',
            textLength: 0,
            blockCount: 0,
            blocks: [],
            blockTypes: [],
            imageCount: 0,
            imageWithUrlCount: 0,
            captionCount: 0,
            error: 'Readability returned null'
          };
        }
        const root = document.createElement('div');
        root.innerHTML = article.content || '';
        const blockNodes = Array.from(root.querySelectorAll(
          'h1,h2,h3,h4,h5,h6,p,blockquote,pre,li,figure,figcaption,table,img,math'
        ));
        const images = Array.from(root.querySelectorAll('img'));
        return {
          success: String(article.textContent || '').trim().length > 0,
          durationMs,
          title: String(article.title || '').replace(/\s+/g, ' ').trim(),
          byline: String(article.byline || '').replace(/\s+/g, ' ').trim(),
          publishedAt: String(article.publishedTime || '').replace(/\s+/g, ' ').trim(),
          siteName: String(article.siteName || '').replace(/\s+/g, ' ').trim(),
          text: String(article.textContent || '').replace(/\s+/g, ' ').trim(),
          textLength: String(article.textContent || '').replace(/\s+/g, ' ').trim().length,
          blockCount: blockNodes.length,
          blocks: blockNodes.map((node) => ({
            type: String(node.tagName || '').toLowerCase(),
            text: String(node.getAttribute('alt') || node.textContent || '').replace(/\s+/g, ' ').trim()
          })),
          blockTypes: blockNodes.map((node) => String(node.tagName || '').toLowerCase()),
          imageCount: images.length,
          imageWithUrlCount: images.filter((node) => String(node.getAttribute('src') || '').trim().length > 0).length,
          captionCount: root.querySelectorAll('figcaption').length,
          error: ''
        };
      } catch (error) {
        return {
          success: false,
          durationMs: performance.now() - startedAt,
          title: '',
          byline: '',
          publishedAt: '',
          siteName: '',
          text: '',
          textLength: 0,
          blockCount: 0,
          blocks: [],
          blockTypes: [],
          imageCount: 0,
          imageWithUrlCount: 0,
          captionCount: 0,
          error: error instanceof Error ? error.message : String(error)
        };
      }
    });
  } catch (error) {
    return {
      success: false,
      durationMs: 0,
      title: '',
      byline: '',
      publishedAt: '',
      siteName: '',
      text: '',
      textLength: 0,
      blockCount: 0,
      blocks: [],
      blockTypes: [],
      imageCount: 0,
      imageWithUrlCount: 0,
      captionCount: 0,
      error: error instanceof Error ? error.message : String(error)
    };
  }
};

const fieldMatches = (actual, expected) => !expected || normalizeComparable(actual).includes(normalizeComparable(expected));

const typedMarkerMatches = (blocks, expectedBlocks) => expectedBlocks.map((expected) => ({
  type: expected.type,
  marker: expected.marker,
  passed: (blocks ?? []).some((block) =>
    String(block.type ?? '').toLowerCase() === String(expected.type ?? '').toLowerCase() &&
    normalizeComparable([block.text, block.caption, block.alt].filter(Boolean).join(' '))
      .includes(normalizeComparable(expected.marker))
  )
}));

const compactEngineResult = (
  result,
  required = [],
  forbidden = [],
  expectedMetadata = {},
  expectedBlocks = []
) => ({
  success: result.success,
  durationMs: round(result.durationMs),
  textLength: result.textLength,
  blockCount: result.blockCount,
  rawResultLength: result.rawResultLength ?? 0,
  blockTypes: [...new Set(result.blockTypes)],
  typedMarkerMatches: typedMarkerMatches(result.blocks, expectedBlocks),
  imageCount: result.imageCount ?? 0,
  imageWithUrlCount: result.imageWithUrlCount ?? 0,
  captionCount: result.captionCount ?? 0,
  metadataPresent: {
    title: normalizeText(result.title).length > 0,
    byline: normalizeText(result.byline).length > 0,
    publishedAt: normalizeText(result.publishedAt).length > 0,
    siteName: normalizeText(result.siteName).length > 0
  },
  metadataMatches: {
    title: fieldMatches(result.title, expectedMetadata.title),
    byline: fieldMatches(result.byline, expectedMetadata.byline),
    publishedAt: fieldMatches(result.publishedAt, expectedMetadata.publishedAt),
    siteName: fieldMatches(result.siteName, expectedMetadata.siteName)
  },
  requiredHits: markerHits(result.text, required),
  forbiddenHits: markerHits(result.text, forbidden),
  strategy: result.strategy ?? '',
  adapterId: result.adapterId ?? '',
  error: result.error
});

const createPage = async (context, readabilityBundle) => {
  const page = await context.newPage();
  await page.route('**/*', async (route) => {
    const type = route.request().resourceType();
    if (type === 'image' || type === 'media' || type === 'font') {
      await route.abort();
      return;
    }
    await route.continue();
  });
  await page.addInitScript({ content: readabilityBundle });
  return page;
};

const runFixture = async (context, item, airaScript, productionScript, readabilityBundle) => {
  const page = await createPage(context, readabilityBundle);
  await page.route(item.url, (route) => route.fulfill({
    status: 200,
    contentType: 'text/html; charset=utf-8',
    body: item.html
  }));
  try {
    await page.goto(item.url, { waitUntil: 'domcontentloaded', timeout: 15_000 });
    if (item.settleMs > 0) {
      await page.waitForTimeout(item.settleMs);
    }
    const aira = await runAira(page, airaScript);
    const readability = await runReadability(page);
    const production = await runAira(page, productionScript);
    const expectedMetadata = item.expectedMetadata ?? {};
    const expectedAiraBlocks = item.expectedAiraBlocks ?? [];
    const expectedReadabilityBlocks = item.expectedReadabilityBlocks ?? [];
    return {
      id: item.id,
      category: item.category,
      url: item.url,
      requiredCount: item.required.length,
      forbiddenCount: item.forbidden.length,
      expectedImageCount: item.expectedImageCount ?? 0,
      expectedCaptionCount: item.expectedCaptionCount ?? 0,
      expectedMetadataCount: Object.values(expectedMetadata).filter(Boolean).length,
      expectedAiraBlockCount: expectedAiraBlocks.length,
      expectedReadabilityBlockCount: expectedReadabilityBlocks.length,
      dynamic: item.dynamic === true,
      overlap: round(jaccard(aira.text, readability.text), 3),
      aira: compactEngineResult(aira, item.required, item.forbidden, expectedMetadata, expectedAiraBlocks),
      readability: compactEngineResult(
        readability,
        item.required,
        item.forbidden,
        expectedMetadata,
        expectedReadabilityBlocks
      ),
      production: compactEngineResult(
        production,
        item.required,
        item.forbidden,
        expectedMetadata,
        expectedAiraBlocks
      )
    };
  } finally {
    await page.close();
  }
};

const runLivePage = async (context, item, airaScript, productionScript, readabilityBundle) => {
  const page = await createPage(context, readabilityBundle);
  const startedAt = performance.now();
  try {
    const response = await page.goto(item.url, { waitUntil: 'domcontentloaded', timeout: 25_000 });
    const status = response?.status() ?? 0;
    if (status >= 400) {
      throw new Error(`HTTP ${status}`);
    }
    await page.waitForTimeout(1_200);
    const aira = await runAira(page, airaScript);
    const readability = await runReadability(page);
    const production = await runAira(page, productionScript);
    return {
      id: item.id,
      url: page.url(),
      loaded: true,
      status,
      loadDurationMs: round(performance.now() - startedAt),
      overlap: round(jaccard(aira.text, readability.text), 3),
      aira: compactEngineResult(aira),
      readability: compactEngineResult(readability),
      production: compactEngineResult(production),
      error: ''
    };
  } catch (error) {
    return {
      id: item.id,
      url: item.url,
      loaded: false,
      status: 0,
      loadDurationMs: round(performance.now() - startedAt),
      overlap: 0,
      aira: compactEngineResult({ success: false, durationMs: 0, title: '', byline: '', text: '', textLength: 0, blockCount: 0, blockTypes: [], error: '' }),
      readability: compactEngineResult({ success: false, durationMs: 0, title: '', byline: '', text: '', textLength: 0, blockCount: 0, blockTypes: [], error: '' }),
      production: compactEngineResult({ success: false, durationMs: 0, title: '', byline: '', text: '', textLength: 0, blockCount: 0, blockTypes: [], error: '' }),
      error: error instanceof Error ? error.message : String(error)
    };
  } finally {
    await page.close();
  }
};

const buildGates = (fixtures, livePages) => {
  const generic = fixtures.filter((item) => item.category === 'generic');
  const readabilityRequired = generic.reduce((sum, item) => sum + item.readability.requiredHits.length, 0);
  const productionRequired = generic.reduce((sum, item) => sum + item.production.requiredHits.length, 0);
  const requiredTotal = generic.reduce((sum, item) => sum + item.requiredCount, 0);
  const readabilityNoise = generic.reduce((sum, item) => sum + item.readability.forbiddenHits.length, 0);
  const productionNoise = generic.reduce((sum, item) => sum + item.production.forbiddenHits.length, 0);
  const airaNoise = generic.reduce((sum, item) => sum + item.aira.forbiddenHits.length, 0);
  const adapters = fixtures.filter((item) => item.category === 'adapter');
  const loadedLive = livePages.filter((item) => item.loaded);
  const readabilityTimes = [...generic, ...loadedLive].map((item) => item.readability.durationMs);
  const productionTimes = [...fixtures, ...loadedLive].map((item) => item.production.durationMs);
  const medianReadabilityMs = round(median(readabilityTimes));
  const medianProductionMs = round(median(productionTimes));
  const metadataFixtures = fixtures.filter((item) => item.expectedMetadataCount > 0);
  const metadataPassed = metadataFixtures.length > 0 && metadataFixtures.every((item) =>
    Object.values(item.aira.metadataMatches).every(Boolean) &&
    Object.values(item.readability.metadataMatches).every(Boolean) &&
    Object.values(item.production.metadataMatches).every(Boolean)
  );
  const structureFixtures = fixtures.filter((item) => item.expectedImageCount > 0 || item.expectedCaptionCount > 0);
  const structurePassed = structureFixtures.length > 0 && structureFixtures.every((item) =>
    item.readability.imageWithUrlCount >= item.expectedImageCount &&
    item.production.imageWithUrlCount >= item.expectedImageCount &&
    item.readability.captionCount >= item.expectedCaptionCount &&
    item.production.captionCount >= item.expectedCaptionCount
  );
  const dynamicFixtures = generic.filter((item) => item.dynamic);
  const dynamicPassed = dynamicFixtures.length > 0 && dynamicFixtures.every((item) =>
    item.readability.requiredHits.length === item.requiredCount &&
    item.production.requiredHits.length === item.requiredCount
  );
  const typedFixtures = fixtures.filter((item) =>
    item.expectedAiraBlockCount > 0 || item.expectedReadabilityBlockCount > 0);
  const typedStructurePassed = typedFixtures.length > 0 && typedFixtures.every((item) =>
    item.production.typedMarkerMatches.every((match) => match.passed) &&
    item.readability.typedMarkerMatches.every((match) => match.passed)
  );
  return {
    deterministicRecall: {
      passed: !runFixtures ||
        (generic.length > 0 && readabilityRequired === requiredTotal && productionRequired === requiredTotal),
      actual: runFixtures ?
        `Readability ${readabilityRequired}/${requiredTotal}; production ${productionRequired}/${requiredTotal}` :
        'not run',
      required: runFixtures ? 'all generic fixture markers in engine and integration' : 'not applicable'
    },
    contamination: {
      passed: !runFixtures ||
        (generic.length > 0 && readabilityNoise <= airaNoise && productionNoise <= airaNoise),
      actual: runFixtures ?
        `Readability ${readabilityNoise}; production ${productionNoise}; legacy Aira ${airaNoise}` :
        'not run',
      required: runFixtures ? 'engine and production no worse than legacy Aira' : 'not applicable'
    },
    adapterPrecedence: {
      passed: !runFixtures || (adapters.length > 0 && adapters.every((item) =>
        item.production.adapterId === item.aira.adapterId &&
        !item.production.strategy.includes('mozilla_readability'))),
      actual: runFixtures ? `${adapters.filter((item) =>
        item.production.adapterId === item.aira.adapterId &&
        !item.production.strategy.includes('mozilla_readability')).length}/${adapters.length}` : 'not run',
      required: runFixtures ? 'all labelled adapters bypass Readability' : 'not applicable'
    },
    liveReliability: {
      passed: !runLive || (loadedLive.length >= 3 && loadedLive.every((item) =>
        item.readability.success && item.production.success)),
      actual: runLive ? `Readability ${loadedLive.filter((item) => item.readability.success).length}/${loadedLive.length}; ` +
        `production ${loadedLive.filter((item) => item.production.success).length}/${loadedLive.length}` : 'not run',
      required: runLive ? 'engine and production on all loaded pages, at least 3 loaded' : 'not applicable'
    },
    runtime: {
      passed: readabilityTimes.length > 0 && productionTimes.length > 0 &&
        medianReadabilityMs < 100 && medianProductionMs < 100,
      actual: `Readability ${medianReadabilityMs} ms; production ${medianProductionMs} ms median`,
      required: '< 100 ms engine and production local Chrome median'
    },
    metadata: {
      passed: !runFixtures || metadataPassed,
      actual: runFixtures ? `${metadataFixtures.filter((item) =>
        Object.values(item.aira.metadataMatches).every(Boolean) &&
        Object.values(item.readability.metadataMatches).every(Boolean) &&
        Object.values(item.production.metadataMatches).every(Boolean)).length}/${metadataFixtures.length}` : 'not run',
      required: runFixtures ? 'title/byline/date/site retained by baseline, engine, and integration' : 'not applicable'
    },
    imageAndCaption: {
      passed: !runFixtures || structurePassed,
      actual: runFixtures ? `${structureFixtures.filter((item) =>
        item.readability.imageWithUrlCount >= item.expectedImageCount &&
        item.production.imageWithUrlCount >= item.expectedImageCount &&
        item.readability.captionCount >= item.expectedCaptionCount &&
        item.production.captionCount >= item.expectedCaptionCount).length}/${structureFixtures.length}` : 'not run',
      required: runFixtures ? 'engine and production retain labelled image URLs and captions' : 'not applicable'
    },
    dynamicDom: {
      passed: !runFixtures || dynamicPassed,
      actual: runFixtures ? `${dynamicFixtures.filter((item) =>
        item.readability.requiredHits.length === item.requiredCount &&
        item.production.requiredHits.length === item.requiredCount).length}/${dynamicFixtures.length}` : 'not run',
      required: runFixtures ? 'engine and production retain post-DOMContentLoaded content' : 'not applicable'
    },
    typedStructure: {
      passed: !runFixtures || typedStructurePassed,
      actual: runFixtures ? `${typedFixtures.filter((item) =>
        item.production.typedMarkerMatches.every((match) => match.passed) &&
        item.readability.typedMarkerMatches.every((match) => match.passed)).length}/${typedFixtures.length}` : 'not run',
      required: runFixtures ? 'engine DOM and Aira typed blocks retain labelled structures' : 'not applicable'
    },
    transportReliability: {
      passed: (!runFixtures || (fixtures.length > 0 && fixtures.every((item) =>
        item.aira.success && item.readability.success && item.production.success))) &&
        (!runLive || (loadedLive.length > 0 && loadedLive.every((item) =>
          item.readability.success && item.production.success))),
      actual: (runFixtures ?
        `${fixtures.filter((item) =>
          item.aira.success && item.readability.success && item.production.success).length}/${fixtures.length} fixtures` :
        'fixtures not run') + '; ' +
        (runLive ? `${loadedLive.filter((item) => item.production.success).length}/${loadedLive.length} live` : 'live not run'),
      required: 'baseline, engine, and production injection/JSON transport succeeds'
    }
  };
};

const markdownReport = (report) => {
  const gateRows = Object.entries(report.gates).map(([name, gate]) =>
    `| ${name} | ${gate.passed ? 'pass' : 'fail'} | ${gate.actual} | ${gate.required} |`
  ).join('\n');
  const fixtureRows = report.fixtures.map((item) =>
    `| ${item.id} | ${item.category} | ${item.aira.requiredHits.length}/${item.requiredCount} | ` +
    `${item.readability.requiredHits.length}/${item.requiredCount} | ${item.production.requiredHits.length}/${item.requiredCount} | ` +
    `${item.aira.forbiddenHits.length} | ${item.production.forbiddenHits.length} | ${item.aira.durationMs} | ` +
    `${round(item.readability.durationMs)} | ${item.production.durationMs} | ${item.production.strategy || '-'} |`
  ).join('\n');
  const liveRows = report.livePages.map((item) =>
    `| ${item.id} | ${item.loaded ? item.status : 'load failed'} | ${item.aira.success ? 'yes' : 'no'} | ` +
    `${item.readability.success ? 'yes' : 'no'} | ${item.production.success ? 'yes' : 'no'} | ` +
    `${item.aira.textLength} | ${item.readability.textLength} | ${item.production.textLength} | ` +
    `${item.aira.durationMs} | ${round(item.readability.durationMs)} | ${item.production.durationMs} |`
  ).join('\n');
  return `# Reader Extraction Spike Result\n\n` +
    `Generated: ${report.generatedAt}\n\n` +
    `Chrome: ${report.environment.chromeVersion}\n\n` +
    `Legacy Aira script: ${report.environment.airaScriptBytes} bytes; production hybrid script: ` +
    `${report.environment.productionScriptBytes} bytes; Readability browser bundle: ` +
    `${report.environment.readabilityBundleBytes} bytes.\n\n` +
    `## Gates\n\n| Gate | Result | Actual | Requirement |\n|------|--------|--------|-------------|\n${gateRows}\n\n` +
    `## Deterministic Fixtures\n\n` +
    `| Fixture | Category | Legacy recall | Engine recall | Production recall | Legacy noise | Production noise | Legacy ms | Engine ms | Production ms | Production strategy |\n` +
    `|---------|----------|---------------|---------------|-------------------|--------------|------------------|-----------|-----------|---------------|---------------------|\n` +
    `${fixtureRows || '| not run | - | - | - | - | - | - | - | - | - | - |'}\n\n` +
    `## Public Live Pages\n\n` +
    `| Page | HTTP | Legacy success | Engine success | Production success | Legacy chars | Engine chars | Production chars | Legacy ms | Engine ms | Production ms |\n` +
    `|------|------|----------------|----------------|--------------------|--------------|--------------|------------------|-----------|-----------|---------------|\n` +
    `${liveRows || '| not run | - | - | - | - | - | - | - | - | - | - |'}\n\n` +
    `No screenshots or other visual captures were created. Live-page rows contain metrics only, not extracted article text.\n`;
};

const main = async () => {
  const [baselineService, service] = await Promise.all([
    buildBaselineService(),
    buildProductionService()
  ]);
  const airaScript = baselineService.buildExtractionScript('');
  const productionScript = service.buildExtractionScript('');
  const readabilityBundle = await buildReadabilityBrowserBundle();
  const executablePath = process.env.AIRA_SPIKE_CHROME_PATH || DEFAULT_CHROME_PATH;
  const browser = await chromium.launch({ executablePath, headless: true });
  try {
    const context = await browser.newContext({
      locale: 'zh-CN',
      viewport: { width: 1280, height: 900 },
      serviceWorkers: 'block'
    });
    const fixtures = [];
    if (runFixtures) {
      for (const item of deterministicCorpus) {
        if (selectedCaseId && item.id !== selectedCaseId) {
          continue;
        }
        fixtures.push(await runFixture(context, item, airaScript, productionScript, readabilityBundle));
      }
    }
    const livePages = [];
    if (runLive) {
      for (const item of liveCorpus) {
        if (selectedCaseId && item.id !== selectedCaseId) {
          continue;
        }
        livePages.push(await runLivePage(context, item, airaScript, productionScript, readabilityBundle));
      }
    }
    const chromeVersion = await browser.version();
    const report = {
      generatedAt: new Date().toISOString(),
      environment: {
        nodeVersion: process.version,
        chromeVersion,
        baselineCommit: BASELINE_COMMIT,
        airaScriptBytes: Buffer.byteLength(airaScript),
        productionScriptBytes: Buffer.byteLength(productionScript),
        readabilityVersion: '0.6.0',
        readabilityBundleBytes: Buffer.byteLength(readabilityBundle)
      },
      gates: buildGates(fixtures, livePages),
      fixtures,
      livePages
    };
    await mkdir(OUTPUT_DIR, { recursive: true });
    await writeFile(path.join(OUTPUT_DIR, 'result.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8');
    await writeFile(path.join(OUTPUT_DIR, 'result.md'), markdownReport(report), 'utf8');
    console.log(markdownReport(report));
    const allPassed = Object.values(report.gates).every((gate) => gate.passed);
    process.exitCode = allPassed ? 0 : 2;
  } finally {
    await browser.close();
  }
};

await main();
