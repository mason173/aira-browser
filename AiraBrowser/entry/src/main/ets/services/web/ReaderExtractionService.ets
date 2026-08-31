import { webview } from '@kit.ArkWeb';
import {
  ReaderModeArticle,
  ReaderModeArticleDiagnostics,
  ReaderModeBlock,
  ReaderModeBlockType,
  ReaderModeProbeCandidate,
  ReaderModeProbeResult
} from '../../features/reader/ReaderModeModels';
import { ReaderSiteAdapterRegistry } from '../../features/reader/ReaderSiteAdapterRegistry';
import {
  MOZILLA_READABILITY_RUNTIME_SOURCE,
  MOZILLA_READABILITY_VERSION
} from '../../features/reader/ReaderReadabilityRuntimeSource';

interface ReaderExtractionRawBlock {
  type: string;
  text?: string;
  url?: string;
  fallbackUrls?: string[];
  alt?: string;
  caption?: string;
  level?: number;
  width?: number;
  height?: number;
  renderedWidth?: number;
  renderedHeight?: number;
  sourceTagName?: string;
  sourceClassName?: string;
  sourceId?: string;
  sourceRole?: string;
}

interface ReaderExtractionRawArticle {
  title?: string;
  byline?: string;
  siteName?: string;
  publishedAt?: string;
  url?: string;
  excerpt?: string;
  diagnostics?: ReaderExtractionRawDiagnostics;
  blocks?: ReaderExtractionRawBlock[];
}

interface ReaderExtractionRawSession {
  title?: string;
  byline?: string;
  siteName?: string;
  publishedAt?: string;
  url?: string;
  excerpt?: string;
  diagnostics?: ReaderExtractionRawDiagnostics;
  blockCount?: number;
}

interface ReaderExtractionRawDiagnostics {
  adapterId?: string;
  sourceTagName?: string;
  sourceClassName?: string;
  sourceTextLength?: number;
  sourceScore?: number;
  candidateCount?: number;
  extractionStrategy?: string;
  rawBlockCount?: number;
  retainedBlockCount?: number;
  rawImageCount?: number;
  retainedImageCount?: number;
  hiddenImageCount?: number;
  postProcessSummary?: string;
}

interface ReaderExtractionRawChunk {
  offset?: number;
  nextOffset?: number;
  done?: boolean;
  blocks?: ReaderExtractionRawBlock[];
}

export interface ReaderExtractionChunkSession {
  article: ReaderModeArticle;
  blockCount: number;
}

export interface ReaderExtractionChunk {
  blocks: ReaderModeBlock[];
  nextOffset: number;
  done: boolean;
}

const READER_MAX_BLOCKS: number = 220;
const READER_MAX_BLOCK_TEXT_LENGTH: number = 2400;
const READER_BLOCK_CHUNK_SIZE: number = 36;

export class ReaderExtractionService {
  private siteAdapterRegistry: ReaderSiteAdapterRegistry = new ReaderSiteAdapterRegistry();

  async probe(controller: webview.WebviewController): Promise<ReaderModeProbeResult> {
    const rawResult = await controller.runJavaScript(this.buildProbeScript());
    return this.parseProbeResult(rawResult);
  }

  async extract(controller: webview.WebviewController, preferredSelector: string = ''): Promise<ReaderModeArticle> {
    const rawResult = await controller.runJavaScript(this.buildExtractionScript(preferredSelector));
    return this.parseArticleResult(rawResult);
  }

  async extractChunked(controller: webview.WebviewController, preferredSelector: string = ''): Promise<ReaderModeArticle> {
    const rawSession = await controller.runJavaScript(this.buildChunkedExtractionPrepareScript(preferredSelector));
    const session = this.parseChunkedExtractionSession(rawSession);
    const blocks: ReaderModeBlock[] = [];
    let offset = 0;
    while (offset < session.blockCount && blocks.length < READER_MAX_BLOCKS) {
      const rawChunk = await controller.runJavaScript(
        this.buildChunkedExtractionChunkScript(offset, READER_BLOCK_CHUNK_SIZE)
      );
      const chunk = this.parseChunkedExtractionChunk(rawChunk);
      blocks.push(...chunk.blocks);
      if (chunk.done || chunk.nextOffset <= offset) {
        break;
      }
      offset = chunk.nextOffset;
    }
    return {
      title: session.article.title,
      byline: session.article.byline,
      siteName: session.article.siteName,
      publishedAt: session.article.publishedAt,
      url: session.article.url,
      excerpt: session.article.excerpt,
      diagnostics: session.article.diagnostics,
      blocks: blocks.slice(0, READER_MAX_BLOCKS)
    };
  }

  parseProbeResult(rawResult: string): ReaderModeProbeResult {
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(rawResult)) as ReaderModeProbeResult;
      return {
        url: this.normalizeText(parsed.url),
        title: this.normalizeText(parsed.title),
        host: this.normalizeText(parsed.host),
        siteName: this.normalizeText(parsed.siteName),
        publishedAt: this.normalizeText(parsed.publishedAt),
        paragraphCount: this.normalizeNumber(parsed.paragraphCount),
        textLength: this.normalizeNumber(parsed.textLength),
        linkTextLength: this.normalizeNumber(parsed.linkTextLength),
        candidates: Array.isArray(parsed.candidates)
          ? parsed.candidates.map((candidate: ReaderModeProbeCandidate) => this.normalizeCandidate(candidate))
          : []
      };
    } catch (_error) {
      return this.buildEmptyProbe();
    }
  }

  parseArticleResult(rawResult: string): ReaderModeArticle {
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(rawResult)) as ReaderExtractionRawArticle;
      const blocks = Array.isArray(parsed.blocks)
        ? parsed.blocks.slice(0, READER_MAX_BLOCKS).map((block: ReaderExtractionRawBlock, index: number) => {
          return this.normalizeBlock(block, index);
        }).filter((block: ReaderModeBlock) => block.text.length > 0 || (block.url?.length ?? 0) > 0)
        : [];
      return {
        title: this.normalizeText(parsed.title),
        byline: this.normalizeText(parsed.byline),
        siteName: this.normalizeText(parsed.siteName),
        publishedAt: this.normalizeText(parsed.publishedAt),
        url: this.normalizeText(parsed.url),
        excerpt: this.normalizeText(parsed.excerpt),
        diagnostics: this.normalizeDiagnostics(parsed.diagnostics),
        blocks: blocks
      };
    } catch (_error) {
      return {
        title: '',
        byline: '',
        siteName: '',
        publishedAt: '',
        url: '',
        excerpt: '',
        diagnostics: this.normalizeDiagnostics(undefined),
        blocks: []
      };
    }
  }

  parseChunkedExtractionSession(rawResult: string): ReaderExtractionChunkSession {
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(rawResult)) as ReaderExtractionRawSession;
      return {
        article: {
          title: this.normalizeText(parsed.title),
          byline: this.normalizeText(parsed.byline),
          siteName: this.normalizeText(parsed.siteName),
          publishedAt: this.normalizeText(parsed.publishedAt),
          url: this.normalizeText(parsed.url),
          excerpt: this.normalizeText(parsed.excerpt),
          diagnostics: this.normalizeDiagnostics(parsed.diagnostics),
          blocks: []
        },
        blockCount: Math.min(this.normalizeNumber(parsed.blockCount), READER_MAX_BLOCKS)
      };
    } catch (_error) {
      return {
        article: {
          title: '',
          byline: '',
          siteName: '',
          publishedAt: '',
          url: '',
          excerpt: '',
          diagnostics: this.normalizeDiagnostics(undefined),
          blocks: []
        },
        blockCount: 0
      };
    }
  }

  parseChunkedExtractionChunk(rawResult: string): ReaderExtractionChunk {
    try {
      const parsed = JSON.parse(this.normalizeRawScriptResult(rawResult)) as ReaderExtractionRawChunk;
      const offset = this.normalizeNumber(parsed.offset);
      const blocks = Array.isArray(parsed.blocks)
        ? parsed.blocks.slice(0, READER_BLOCK_CHUNK_SIZE).map((block: ReaderExtractionRawBlock, index: number) => {
          return this.normalizeBlock(block, offset + index);
        }).filter((block: ReaderModeBlock) => block.text.length > 0 || (block.url?.length ?? 0) > 0)
        : [];
      return {
        blocks: blocks,
        nextOffset: Math.min(this.normalizeNumber(parsed.nextOffset), READER_MAX_BLOCKS),
        done: parsed.done === true
      };
    } catch (_error) {
      return {
        blocks: [],
        nextOffset: 0,
        done: true
      };
    }
  }

  buildProbeScript(): string {
    return `
(() => {
  try {
    const normalizeText = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
    const getMeta = (names) => {
      for (const name of names) {
        const node = document.querySelector('meta[name="' + name + '"], meta[property="' + name + '"]');
        const content = node ? normalizeText(node.getAttribute('content')) : '';
        if (content) {
          return content;
        }
      }
      return '';
    };
    ${this.buildSiteAdapterScript()}
    if (!hasRequiredSiteSources()) {
      return JSON.stringify({
        url: location.href,
        title: normalizeText(document.title),
        host: location.host,
        siteName: siteAdapter.siteName,
        publishedAt: '',
        paragraphCount: 0,
        textLength: 0,
        linkTextLength: 0,
        candidates: []
      });
    }
    const buildSelector = (node) => {
      if (!node || !node.tagName) {
        return '';
      }
      if (node.id) {
        return '#' + String(node.id).replace(/([ #;?%&,.+*~\\':"!^$\\[\\]()=>|\\/])/g, '\\\\$1');
      }
      const tag = String(node.tagName || '').toLowerCase();
      if (tag === 'article' || tag === 'main') {
        return tag;
      }
      return '';
    };
    const scoreNode = (node) => {
      const text = normalizeText(node.innerText || node.textContent || '');
      const paragraphs = collectContentBlockElements(node)
        .filter((item) => normalizeText(item.innerText || item.textContent || '').length >= 32);
      const links = Array.from(node.querySelectorAll('a'));
      const linkTextLength = links.reduce((sum, item) => sum + normalizeText(item.innerText || item.textContent || '').length, 0);
      const semanticBonus = /^(ARTICLE|MAIN)$/.test(node.tagName || '') || node.getAttribute('role') === 'main' ? 240 : 0;
      const score = text.length + paragraphs.length * 120 - linkTextLength * 1.4 + semanticBonus;
      return {
        selector: buildSelector(node),
        tagName: String(node.tagName || '').toLowerCase(),
        textLength: text.length,
        paragraphCount: paragraphs.length,
        linkTextLength: linkTextLength,
        score: Math.round(score)
      };
    };
    const compositeSource = buildCompositeSourceNode();
    const rawCandidates = collectElements(mergeUnique(siteAdapter.sourceSelectors, [
      'article', 'main', '[role="main"]', '.article', '.post', '.content', '#article', '#content'
    ]));
    if (compositeSource && rawCandidates.indexOf(compositeSource) < 0) {
      rawCandidates.unshift(compositeSource);
    }
    const candidates = rawCandidates
      .map(scoreNode)
      .filter((item) => item.textLength >= 120)
      .sort((a, b) => b.score - a.score)
      .slice(0, 8);
    const probeSource = compositeSource || document.body;
    const bodyText = normalizeText(probeSource ? (probeSource.innerText || probeSource.textContent || '') : '');
    const paragraphs = collectContentBlockElements(probeSource)
      .filter((item) => normalizeText(item.innerText || item.textContent || '').length >= 32);
    const linkTextLength = Array.from(probeSource ? probeSource.querySelectorAll('a') : [])
      .reduce((sum, item) => sum + normalizeText(item.innerText || item.textContent || '').length, 0);
    return JSON.stringify({
      url: location.href,
      title: normalizeText(document.title),
      host: location.host,
      siteName: getMeta(['og:site_name', 'application-name']),
      publishedAt: getMeta(['article:published_time', 'pubdate', 'publishdate', 'date', 'datePublished']),
      paragraphCount: paragraphs.length,
      textLength: bodyText.length,
      linkTextLength: linkTextLength,
      candidates: candidates
    });
  } catch (error) {
    return JSON.stringify({ url: location.href, title: document.title || '', host: location.host || '', siteName: '', publishedAt: '', paragraphCount: 0, textLength: 0, linkTextLength: 0, candidates: [] });
  }
})()
`;
  }

  buildExtractionScript(preferredSelector: string = ''): string {
    const selectorLiteral = JSON.stringify(preferredSelector);
    return `
(() => {
  try {
    ${MOZILLA_READABILITY_RUNTIME_SOURCE}
    const preferredSelector = ${selectorLiteral};
    const normalizeText = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
    const absoluteUrl = (value) => {
      try {
        return value ? new URL(value, location.href).href : '';
      } catch (error) {
        return '';
      }
    };
    const getMeta = (names) => {
      for (const name of names) {
        const node = document.querySelector('meta[name="' + name + '"], meta[property="' + name + '"]');
        const content = node ? normalizeText(node.getAttribute('content')) : '';
        if (content) {
          return content;
        }
      }
      return '';
    };
    ${this.buildSiteAdapterScript()}
    if (!hasRequiredSiteSources()) {
      return JSON.stringify({
        title: normalizeText(document.title),
        byline: '',
        siteName: siteAdapter.siteName || location.host,
        publishedAt: '',
        url: location.href,
        excerpt: '',
        diagnostics: {
          adapterId: siteAdapter.id,
          sourceTagName: '',
          sourceClassName: '',
          sourceTextLength: 0,
          sourceScore: 0,
          candidateCount: 0,
          extractionStrategy: 'required_source_missing',
          rawBlockCount: 0,
          retainedBlockCount: 0,
          rawImageCount: 0,
          retainedImageCount: 0,
          hiddenImageCount: 0,
          postProcessSummary: ''
        },
        blocks: []
      });
    }
    const cloneReadableNode = (source) => {
      const clone = source.cloneNode(true);
      const removableSelectors = mergeUnique([
        'script', 'style', 'iframe', 'form', 'button', 'input', 'textarea', 'select',
        'nav', 'footer', 'aside', 'header',
        '[role="navigation"]', '[role="complementary"]', '[role="banner"]', '[role="contentinfo"]', '[role="search"]',
        '.ad', '.ads', '.advertisement', '.comment', '.comments', '.related', '.recommend', '.recommended', '.promo',
        '.popup', '.modal', '.share', '.toolbar', '.tool-bar', '.sidebar', '.login', '.reward', '.sponsor'
      ], siteAdapter.removeSelectors);
      removableSelectors.forEach((selector) => {
        try {
          Array.from(clone.querySelectorAll(selector)).forEach((node) => node.remove());
        } catch (error) {
        }
      });
      return clone;
    };
    ${this.buildReadabilitySelectionScript()}
    const scoreNode = (node) => {
      const text = normalizeText(node.innerText || node.textContent || '');
      const paragraphs = Array.from(node.querySelectorAll('p')).filter((item) => normalizeText(item.innerText || item.textContent || '').length >= 32);
      const linkTextLength = Array.from(node.querySelectorAll('a')).reduce((sum, item) => sum + normalizeText(item.innerText || item.textContent || '').length, 0);
      const semanticBonus = /^(ARTICLE|MAIN)$/.test(node.tagName || '') || node.getAttribute('role') === 'main' ? 240 : 0;
      return text.length + paragraphs.length * 120 - linkTextLength * 1.4 + semanticBonus;
    };
    const selectSourceNode = () => {
      const compositeSource = buildCompositeSourceNode();
      if (compositeSource && getNodeText(compositeSource).length >= 80) {
        return buildSelectedSource(compositeSource, 'site_composite');
      }
      const siteCandidates = collectElements(siteAdapter.sourceSelectors)
        .filter((node) => getNodeText(node).length >= 80)
        .sort((a, b) => scoreNode(b) - scoreNode(a));
      if (siteCandidates.length > 0) {
        return buildSelectedSource(siteCandidates[0], 'site_adapter');
      }
      const readabilityCandidate = selectReadabilitySource();
      if (readabilityCandidate) {
        return readabilityCandidate;
      }
      if (preferredSelector) {
        try {
          const preferred = document.querySelector(preferredSelector);
          if (preferred && getNodeText(preferred).length >= 80) {
            return buildSelectedSource(preferred, 'preferred_selector');
          }
        } catch (error) {
        }
      }
      const contentScoreCandidate = selectBestScoredNode();
      if (contentScoreCandidate) {
        return contentScoreCandidate;
      }
      const candidates = collectElements(mergeUnique(siteAdapter.sourceSelectors, [
        'article', 'main', '[role="main"]', '.article', '.post', '.content', '#article', '#content'
      ])).filter((node) => getNodeText(node).length >= 80);
      if (candidates.length <= 0) {
        return buildSelectedSource(document.body, 'document_body');
      }
      return buildSelectedSource(candidates.sort((a, b) => scoreNode(b) - scoreNode(a))[0] || document.body, 'generic_selector');
    };
    const selectedSource = selectSourceNode();
    const serializationStartedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const source = cloneReadableNode(selectedSource.node);
    const blocks = [];
    const pushBlock = (block) => {
      if (blocks.length >= ${READER_MAX_BLOCKS}) {
        return;
      }
      const text = normalizeText(block.text || '');
      const url = absoluteUrl(block.url || '');
      if (!text && !url) {
        return;
      }
      blocks.push({
        type: block.type,
        text: text.slice(0, ${READER_MAX_BLOCK_TEXT_LENGTH}),
        url: url,
        fallbackUrls: (block.fallbackUrls || []).map((item) => absoluteUrl(item)).filter((item) => item.length > 0).slice(0, 6),
        alt: normalizeText(block.alt || ''),
        caption: normalizeText(block.caption || ''),
        level: block.level || 0,
        width: Math.max(0, Math.round(Number(block.width || 0))),
        height: Math.max(0, Math.round(Number(block.height || 0))),
        renderedWidth: Math.max(0, Math.round(Number(block.renderedWidth || 0))),
        renderedHeight: Math.max(0, Math.round(Number(block.renderedHeight || 0))),
        sourceTagName: normalizeText(block.sourceTagName || ''),
        sourceClassName: normalizeText(block.sourceClassName || ''),
        sourceId: normalizeText(block.sourceId || ''),
        sourceRole: normalizeText(block.sourceRole || '')
      });
    };
    const countReadableTextBlocks = () => {
      return blocks.filter((block) => {
        const type = String(block.type || '');
        return (type === 'paragraph' || type === 'quote' || type === 'list_item' || type === 'code') &&
          normalizeText(block.text || '').length >= 24;
      }).length;
    };
    const pushTextFallbackBlocks = (node, force) => {
      if (!node || (!force && blocks.length > 0)) {
        return;
      }
      const paragraphs = Array.from(node.querySelectorAll('p, .RichText p, .ztext p, span'))
        .map((item) => getNodeText(item))
        .filter((text) => text.length >= 24);
      const seen = {};
      blocks.forEach((block) => {
        const text = normalizeText(block.text || '');
        if (text) {
          seen[text] = true;
        }
      });
      paragraphs.forEach((text) => {
        if (!seen[text]) {
          seen[text] = true;
          pushBlock({ type: 'paragraph', text: text });
        }
      });
    };
    const readNode = (node) => {
      if (!node || blocks.length >= ${READER_MAX_BLOCKS}) {
        return;
      }
      if (node.nodeType !== 1) {
        return;
      }
      const tag = String(node.tagName || '').toLowerCase();
      if (matchesAnySelector(node, siteAdapter.contentBlockSelectors)) {
        const semanticType = String(node.getAttribute('data-tag') || '').toLowerCase();
        if (semanticType === 'header') {
          pushBlock({
            type: 'heading',
            text: getNodeText(node),
            level: Number(node.getAttribute('data-level') || 2)
          });
          return;
        }
        pushBlock({ type: 'paragraph', text: getNodeText(node) });
        return;
      }
      if (/^h[1-6]$/.test(tag)) {
        pushBlock({ type: 'heading', text: getNodeText(node), level: Number(tag.substring(1)) });
        return;
      }
      if (tag === 'p') {
        pushBlock({ type: 'paragraph', text: getNodeText(node) });
        return;
      }
      if (tag === 'a') {
        const linkText = getNodeText(node);
        const href = node.getAttribute('href') || '';
        if (normalizeText(linkText).length > 0 && href) {
          pushBlock({ type: 'link', text: linkText, url: href });
        }
        return;
      }
      if (tag === 'blockquote') {
        pushBlock({ type: 'quote', text: getNodeText(node) });
        return;
      }
      if (tag === 'pre' || tag === 'code') {
        pushBlock({ type: 'code', text: getNodeText(node) });
        return;
      }
      if (tag === 'li') {
        pushBlock({ type: 'list_item', text: getNodeText(node) });
        return;
      }
      if (tag === 'tr') {
        const cells = Array.from(node.querySelectorAll('th,td'))
          .map((cell) => getNodeText(cell))
          .filter((text) => text.length > 0);
        pushBlock({ type: 'paragraph', text: cells.join(' | ') || getNodeText(node) });
        return;
      }
      if (tag === 'img') {
        pushBlock(buildImageBlock(node));
        return;
      }
      if (hasStandaloneImageCandidate(node, tag)) {
        pushBlock(buildImageBlock(node));
        return;
      }
      Array.from(node.children || []).forEach(readNode);
    };
    collectReadableNodes(source).forEach(readNode);
    pushTextFallbackBlocks(source, false);
    if (countReadableTextBlocks() < 3 && getNodeText(source).length >= 120) {
      pushTextFallbackBlocks(source, true);
    }
    if (blocks.length <= 0) {
      Array.from(source.querySelectorAll('h1,h2,h3,h4,h5,h6,p,a,blockquote,pre,li,table tr,img,picture,source,figure')).forEach(readNode);
    }
    if (blocks.length <= 0 || (countReadableTextBlocks() < 3 && getNodeText(source).length >= 120)) {
      pushPlainTextFallbackBlocks(source, blocks.length > 0);
    }
    const serializationFinishedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    selectedSource.strategy += ':serialize_ms=' +
      Math.max(0, Math.round(serializationFinishedAt - serializationStartedAt));
    const metadata = buildArticleMetadata(selectedSource);
    return JSON.stringify({
      title: metadata.title,
      byline: metadata.byline,
      siteName: metadata.siteName,
      publishedAt: metadata.publishedAt,
      url: location.href,
      excerpt: metadata.excerpt,
      diagnostics: buildDiagnostics(source, selectedSource, blocks),
      blocks: blocks
    });
  } catch (error) {
    return JSON.stringify({ title: document.title || '', byline: '', siteName: location.host || '', publishedAt: '', url: location.href || '', excerpt: '', blocks: [] });
  }
})()
`;
  }

  buildChunkedExtractionPrepareScript(preferredSelector: string = ''): string {
    const selectorLiteral = JSON.stringify(preferredSelector);
    return `
(() => {
  try {
    ${MOZILLA_READABILITY_RUNTIME_SOURCE}
    const preferredSelector = ${selectorLiteral};
    const normalizeText = (value) => String(value || '').replace(/\\s+/g, ' ').trim();
    const absoluteUrl = (value) => {
      try {
        return value ? new URL(value, location.href).href : '';
      } catch (error) {
        return '';
      }
    };
    const getMeta = (names) => {
      for (const name of names) {
        const node = document.querySelector('meta[name="' + name + '"], meta[property="' + name + '"]');
        const content = node ? normalizeText(node.getAttribute('content')) : '';
        if (content) {
          return content;
        }
      }
      return '';
    };
    ${this.buildSiteAdapterScript()}
    if (!hasRequiredSiteSources()) {
      window.__airaReaderModeExtraction = undefined;
      return JSON.stringify({
        title: normalizeText(document.title),
        byline: '',
        siteName: siteAdapter.siteName || location.host,
        publishedAt: '',
        url: location.href,
        excerpt: '',
        diagnostics: {
          adapterId: siteAdapter.id,
          sourceTagName: '',
          sourceClassName: '',
          sourceTextLength: 0,
          sourceScore: 0,
          candidateCount: 0,
          extractionStrategy: 'required_source_missing',
          rawBlockCount: 0,
          retainedBlockCount: 0,
          rawImageCount: 0,
          retainedImageCount: 0,
          hiddenImageCount: 0,
          postProcessSummary: ''
        },
        blockCount: 0
      });
    }
    const cloneReadableNode = (source) => {
      const clone = source.cloneNode(true);
      const removableSelectors = mergeUnique([
        'script', 'style', 'iframe', 'form', 'button', 'input', 'textarea', 'select',
        'nav', 'footer', 'aside', 'header',
        '[role="navigation"]', '[role="complementary"]', '[role="banner"]', '[role="contentinfo"]', '[role="search"]',
        '.ad', '.ads', '.advertisement', '.comment', '.comments', '.related', '.recommend', '.recommended', '.promo',
        '.popup', '.modal', '.share', '.toolbar', '.tool-bar', '.sidebar', '.login', '.reward', '.sponsor'
      ], siteAdapter.removeSelectors);
      removableSelectors.forEach((selector) => {
        try {
          Array.from(clone.querySelectorAll(selector)).forEach((node) => node.remove());
        } catch (error) {
        }
      });
      return clone;
    };
    ${this.buildReadabilitySelectionScript()}
    const scoreNode = (node) => {
      const text = normalizeText(node.innerText || node.textContent || '');
      const paragraphs = Array.from(node.querySelectorAll('p')).filter((item) => normalizeText(item.innerText || item.textContent || '').length >= 32);
      const linkTextLength = Array.from(node.querySelectorAll('a')).reduce((sum, item) => sum + normalizeText(item.innerText || item.textContent || '').length, 0);
      const semanticBonus = /^(ARTICLE|MAIN)$/.test(node.tagName || '') || node.getAttribute('role') === 'main' ? 240 : 0;
      return text.length + paragraphs.length * 120 - linkTextLength * 1.4 + semanticBonus;
    };
    const selectSourceNode = () => {
      const compositeSource = buildCompositeSourceNode();
      if (compositeSource && getNodeText(compositeSource).length >= 80) {
        return buildSelectedSource(compositeSource, 'site_composite');
      }
      const siteCandidates = collectElements(siteAdapter.sourceSelectors)
        .filter((node) => getNodeText(node).length >= 80)
        .sort((a, b) => scoreNode(b) - scoreNode(a));
      if (siteCandidates.length > 0) {
        return buildSelectedSource(siteCandidates[0], 'site_adapter');
      }
      const readabilityCandidate = selectReadabilitySource();
      if (readabilityCandidate) {
        return readabilityCandidate;
      }
      if (preferredSelector) {
        try {
          const preferred = document.querySelector(preferredSelector);
          if (preferred && getNodeText(preferred).length >= 80) {
            return buildSelectedSource(preferred, 'preferred_selector');
          }
        } catch (error) {
        }
      }
      const contentScoreCandidate = selectBestScoredNode();
      if (contentScoreCandidate) {
        return contentScoreCandidate;
      }
      const candidates = collectElements(mergeUnique(siteAdapter.sourceSelectors, [
        'article', 'main', '[role="main"]', '.article', '.post', '.content', '#article', '#content'
      ])).filter((node) => getNodeText(node).length >= 80);
      if (candidates.length <= 0) {
        return buildSelectedSource(document.body, 'document_body');
      }
      return buildSelectedSource(candidates.sort((a, b) => scoreNode(b) - scoreNode(a))[0] || document.body, 'generic_selector');
    };
    const selectedSource = selectSourceNode();
    const serializationStartedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const source = cloneReadableNode(selectedSource.node);
    const blocks = [];
    const pushBlock = (block) => {
      if (blocks.length >= ${READER_MAX_BLOCKS}) {
        return;
      }
      const text = normalizeText(block.text || '');
      const url = absoluteUrl(block.url || '');
      if (!text && !url) {
        return;
      }
      blocks.push({
        type: block.type,
        text: text.slice(0, ${READER_MAX_BLOCK_TEXT_LENGTH}),
        url: url,
        fallbackUrls: (block.fallbackUrls || []).map((item) => absoluteUrl(item)).filter((item) => item.length > 0).slice(0, 6),
        alt: normalizeText(block.alt || ''),
        caption: normalizeText(block.caption || ''),
        level: block.level || 0,
        width: Math.max(0, Math.round(Number(block.width || 0))),
        height: Math.max(0, Math.round(Number(block.height || 0))),
        renderedWidth: Math.max(0, Math.round(Number(block.renderedWidth || 0))),
        renderedHeight: Math.max(0, Math.round(Number(block.renderedHeight || 0))),
        sourceTagName: normalizeText(block.sourceTagName || ''),
        sourceClassName: normalizeText(block.sourceClassName || ''),
        sourceId: normalizeText(block.sourceId || ''),
        sourceRole: normalizeText(block.sourceRole || '')
      });
    };
    const countReadableTextBlocks = () => {
      return blocks.filter((block) => {
        const type = String(block.type || '');
        return (type === 'paragraph' || type === 'quote' || type === 'list_item' || type === 'code') &&
          normalizeText(block.text || '').length >= 24;
      }).length;
    };
    const pushTextFallbackBlocks = (node, force) => {
      if (!node || (!force && blocks.length > 0)) {
        return;
      }
      const paragraphs = Array.from(node.querySelectorAll('p, .RichText p, .ztext p, span'))
        .map((item) => getNodeText(item))
        .filter((text) => text.length >= 24);
      const seen = {};
      blocks.forEach((block) => {
        const text = normalizeText(block.text || '');
        if (text) {
          seen[text] = true;
        }
      });
      paragraphs.forEach((text) => {
        if (!seen[text]) {
          seen[text] = true;
          pushBlock({ type: 'paragraph', text: text });
        }
      });
    };
    const readNode = (node) => {
      if (!node || blocks.length >= ${READER_MAX_BLOCKS}) {
        return;
      }
      if (node.nodeType !== 1) {
        return;
      }
      const tag = String(node.tagName || '').toLowerCase();
      if (matchesAnySelector(node, siteAdapter.contentBlockSelectors)) {
        const semanticType = String(node.getAttribute('data-tag') || '').toLowerCase();
        if (semanticType === 'header') {
          pushBlock({
            type: 'heading',
            text: getNodeText(node),
            level: Number(node.getAttribute('data-level') || 2)
          });
          return;
        }
        pushBlock({ type: 'paragraph', text: getNodeText(node) });
        return;
      }
      if (/^h[1-6]$/.test(tag)) {
        pushBlock({ type: 'heading', text: getNodeText(node), level: Number(tag.substring(1)) });
        return;
      }
      if (tag === 'p') {
        pushBlock({ type: 'paragraph', text: getNodeText(node) });
        return;
      }
      if (tag === 'a') {
        const linkText = getNodeText(node);
        const href = node.getAttribute('href') || '';
        if (normalizeText(linkText).length > 0 && href) {
          pushBlock({ type: 'link', text: linkText, url: href });
        }
        return;
      }
      if (tag === 'blockquote') {
        pushBlock({ type: 'quote', text: getNodeText(node) });
        return;
      }
      if (tag === 'pre' || tag === 'code') {
        pushBlock({ type: 'code', text: getNodeText(node) });
        return;
      }
      if (tag === 'li') {
        pushBlock({ type: 'list_item', text: getNodeText(node) });
        return;
      }
      if (tag === 'tr') {
        const cells = Array.from(node.querySelectorAll('th,td'))
          .map((cell) => getNodeText(cell))
          .filter((text) => text.length > 0);
        pushBlock({ type: 'paragraph', text: cells.join(' | ') || getNodeText(node) });
        return;
      }
      if (tag === 'img') {
        pushBlock(buildImageBlock(node));
        return;
      }
      if (hasStandaloneImageCandidate(node, tag)) {
        pushBlock(buildImageBlock(node));
        return;
      }
      Array.from(node.children || []).forEach(readNode);
    };
    collectReadableNodes(source).forEach(readNode);
    pushTextFallbackBlocks(source, false);
    if (countReadableTextBlocks() < 3 && getNodeText(source).length >= 120) {
      pushTextFallbackBlocks(source, true);
    }
    if (blocks.length <= 0) {
      Array.from(source.querySelectorAll('h1,h2,h3,h4,h5,h6,p,a,blockquote,pre,li,table tr,img,picture,source,figure')).forEach(readNode);
    }
    if (blocks.length <= 0 || (countReadableTextBlocks() < 3 && getNodeText(source).length >= 120)) {
      pushPlainTextFallbackBlocks(source, blocks.length > 0);
    }
    const serializationFinishedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
    selectedSource.strategy += ':serialize_ms=' +
      Math.max(0, Math.round(serializationFinishedAt - serializationStartedAt));
    const metadata = buildArticleMetadata(selectedSource);
    const article = {
      title: metadata.title,
      byline: metadata.byline,
      siteName: metadata.siteName,
      publishedAt: metadata.publishedAt,
      url: location.href,
      excerpt: metadata.excerpt,
      diagnostics: buildDiagnostics(source, selectedSource, blocks)
    };
    window.__airaReaderModeExtraction = {
      article: article,
      blocks: blocks
    };
    return JSON.stringify({
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      url: article.url,
      excerpt: article.excerpt,
      diagnostics: article.diagnostics,
      blockCount: blocks.length
    });
  } catch (error) {
    window.__airaReaderModeExtraction = { article: {}, blocks: [] };
    return JSON.stringify({ title: document.title || '', byline: '', siteName: location.host || '', publishedAt: '', url: location.href || '', excerpt: '', blockCount: 0 });
  }
})()
`;
  }

  buildChunkedExtractionChunkScript(offset: number, limit: number = READER_BLOCK_CHUNK_SIZE): string {
    const safeOffset = Math.max(0, Math.min(Math.round(offset), READER_MAX_BLOCKS));
    const safeLimit = Math.max(1, Math.min(Math.round(limit), READER_BLOCK_CHUNK_SIZE));
    return `
(() => {
  try {
    const state = window.__airaReaderModeExtraction;
    const offset = ${safeOffset};
    const limit = ${safeLimit};
    const blocks = state && Array.isArray(state.blocks) ? state.blocks : [];
    const nextOffset = Math.min(offset + limit, blocks.length, ${READER_MAX_BLOCKS});
    return JSON.stringify({
      offset: offset,
      nextOffset: nextOffset,
      done: nextOffset >= blocks.length || nextOffset >= ${READER_MAX_BLOCKS},
      blocks: blocks.slice(offset, nextOffset)
    });
  } catch (error) {
    return JSON.stringify({ offset: 0, nextOffset: 0, done: true, blocks: [] });
  }
})()
`;
  }

  private buildReadabilitySelectionScript(): string {
    const versionLiteral = JSON.stringify(MOZILLA_READABILITY_VERSION);
    return `
    const selectReadabilitySource = () => {
      try {
        if (typeof AiraReaderReadability === 'undefined' ||
          typeof AiraReaderReadability.Readability !== 'function') {
          return undefined;
        }
        const startedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
        const readableDocument = cloneReadableNode(document);
        const precleanedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
        const article = new AiraReaderReadability.Readability(readableDocument, {
          charThreshold: 80
        }).parse();
        const parsedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
        const content = article ? String(article.content || '') : '';
        const textContent = article ? normalizeText(article.textContent || '') : '';
        if (!article || !content || textContent.length < 80) {
          return undefined;
        }
        const container = document.createElement('article');
        container.setAttribute('data-aira-reader-engine', 'mozilla-readability');
        container.innerHTML = content;
        if (getNodeText(container).length < 80) {
          return undefined;
        }
        const selected = buildSelectedSource(
          container,
          'mozilla_readability@' + ${versionLiteral}
        );
        const selectedAt = typeof performance !== 'undefined' ? performance.now() : Date.now();
        selected.strategy += ':preclean_ms=' + Math.max(0, Math.round(precleanedAt - startedAt));
        selected.strategy += ':parse_ms=' + Math.max(0, Math.round(parsedAt - precleanedAt));
        selected.strategy += ':select_ms=' + Math.max(0, Math.round(selectedAt - parsedAt));
        selected.metadata = {
          title: normalizeText(article.title || ''),
          byline: normalizeText(article.byline || ''),
          siteName: normalizeText(article.siteName || ''),
          publishedTime: normalizeText(article.publishedTime || ''),
          excerpt: normalizeText(article.excerpt || '')
        };
        return selected;
      } catch (error) {
        return undefined;
      }
    };
`;
  }

  private buildSiteAdapterScript(): string {
    const adapterRulesLiteral = this.siteAdapterRegistry.buildScriptRulePayload();
    return `
    const siteAdapterRules = ${adapterRulesLiteral};
    const normalizeHost = (value) => String(value || '').trim().toLowerCase().replace(/^www\\./, '');
    const POSITIVE_RE = /article|body|content|entry|hentry|main|page|post|richtext|text|story|ztext|markdown|news/i;
    const NEGATIVE_RE = /ad|banner|comment|combx|contact|footer|header|menu|meta|nav|promo|related|recommend|scroll|share|shoutbox|sidebar|sponsor|tool|widget|toolbar|login|modal|popup|reward/i;
    const matchesHostSuffix = (host, suffix) => {
      const normalizedSuffix = normalizeHost(suffix);
      return host === normalizedSuffix || host.endsWith('.' + normalizedSuffix);
    };
    const mergeUnique = (first, second) => {
      const seen = {};
      const values = [];
      (first || []).concat(second || []).forEach((item) => {
        const value = String(item || '').trim();
        if (value && !seen[value]) {
          seen[value] = true;
          values.push(value);
        }
      });
      return values;
    };
    const resolveSiteAdapter = () => {
      const host = normalizeHost(location.hostname || location.host || '');
      const rule = siteAdapterRules.find((item) => {
        return (item.hostSuffixes || []).some((suffix) => matchesHostSuffix(host, suffix));
      });
      if (!rule) {
        return {
          id: '',
          sourceSelectors: [],
          compositeSourceSelectors: [],
          contentBlockSelectors: [],
          requiredSourceSelectors: [],
          removeSelectors: [],
          titleSelectors: [],
          bylineSelectors: [],
          publishedAtSelectors: [],
          imageAttributes: [],
          siteName: ''
        };
      }
      return {
        id: String(rule.id || ''),
        sourceSelectors: rule.sourceSelectors || [],
        compositeSourceSelectors: rule.compositeSourceSelectors || [],
        contentBlockSelectors: rule.contentBlockSelectors || [],
        requiredSourceSelectors: rule.requiredSourceSelectors || [],
        removeSelectors: rule.removeSelectors || [],
        titleSelectors: rule.titleSelectors || [],
        bylineSelectors: rule.bylineSelectors || [],
        publishedAtSelectors: rule.publishedAtSelectors || [],
        imageAttributes: rule.imageAttributes || [],
        siteName: String(rule.siteName || '')
      };
    };
    const collectElements = (selectors) => {
      const nodes = [];
      selectors.forEach((selector) => {
        try {
          Array.from(document.querySelectorAll(selector)).forEach((node) => {
            if (nodes.indexOf(node) < 0) {
              nodes.push(node);
            }
          });
        } catch (error) {
        }
      });
      return nodes;
    };
    const collectElementsWithin = (source, selectors) => {
      if (!source || !source.querySelectorAll) {
        return [];
      }
      const selectorList = mergeUnique(selectors, []);
      if (selectorList.length <= 0) {
        return [];
      }
      try {
        return Array.from(source.querySelectorAll(selectorList.join(',')));
      } catch (error) {
        return [];
      }
    };
    const collectOutermostElementsWithin = (source, selectors) => {
      const nodes = collectElementsWithin(source, selectors);
      return nodes.filter((node) => !nodes.some((candidate) => candidate !== node && candidate.contains(node)));
    };
    const matchesAnySelector = (node, selectors) => {
      if (!node || !node.matches) {
        return false;
      }
      return (selectors || []).some((selector) => {
        try {
          return node.matches(selector);
        } catch (error) {
          return false;
        }
      });
    };
    const hasRequiredSiteSources = () => {
      if (siteAdapter.requiredSourceSelectors.length <= 0) {
        return true;
      }
      const hasConfiguredRoot = siteAdapter.requiredSourceSelectors.some((selector) => {
        try {
          return document.querySelector(selector) !== null;
        } catch (error) {
          return false;
        }
      });
      if (hasConfiguredRoot) {
        return true;
      }
      const hasSemanticContent = collectElements(siteAdapter.contentBlockSelectors).some((node) => {
        return normalizeText(node.innerText || node.textContent || '').length >= 24;
      });
      if (hasSemanticContent) {
        return true;
      }
      const pageText = normalizeText(document.body ? (document.body.innerText || document.body.textContent || '') : '');
      const blockedText = normalizeText(document.title) + ' ' + pageText.slice(0, 600);
      const isBlockedPage = /安全验证|访问受限|请输入验证码|请完成验证|网络不给力|页面不存在|内容不存在/.test(blockedText);
      return !isBlockedPage && pageText.length >= 200;
    };
    const buildCompositeSourceNode = () => {
      let sourceNodes = collectElements(siteAdapter.compositeSourceSelectors);
      if (sourceNodes.length <= 0 && siteAdapter.contentBlockSelectors.length > 0) {
        sourceNodes = collectOutermostElementsWithin(document, siteAdapter.contentBlockSelectors);
      }
      if (sourceNodes.length <= 0) {
        return undefined;
      }
      const composite = document.createElement('div');
      composite.setAttribute('data-aira-reader-composite', siteAdapter.id);
      sourceNodes.forEach((node) => composite.appendChild(node.cloneNode(true)));
      return composite;
    };
    const collectContentBlockElements = (source) => {
      const selectors = mergeUnique(['p', 'blockquote', 'li'], siteAdapter.contentBlockSelectors);
      return siteAdapter.contentBlockSelectors.length > 0 ?
        collectOutermostElementsWithin(source, selectors) :
        collectElementsWithin(source, selectors);
    };
    const getNodeText = (node) => {
      if (!node) {
        return '';
      }
      const rawText = node.isConnected === false ? node.textContent : (node.innerText || node.textContent || '');
      return normalizeText(rawText || '');
    };
    const getClassWeight = (node) => {
      if (!node || !node.getAttribute) {
        return 0;
      }
      const value = String((node.getAttribute('class') || '') + ' ' + (node.getAttribute('id') || ''));
      let weight = 0;
      if (POSITIVE_RE.test(value)) {
        weight += 25;
      }
      if (NEGATIVE_RE.test(value)) {
        weight -= 35;
      }
      return weight;
    };
    const getLinkDensity = (node) => {
      const textLength = getNodeText(node).length;
      if (textLength <= 0) {
        return 1;
      }
      const linkTextLength = Array.from(node.querySelectorAll ? node.querySelectorAll('a') : [])
        .reduce((sum, item) => sum + getNodeText(item).length, 0);
      return linkTextLength / textLength;
    };
    const countInteractiveNodes = (node) => {
      if (!node || !node.querySelectorAll) {
        return 0;
      }
      return node.querySelectorAll('button,input,textarea,select,form,[role="button"],[role="toolbar"]').length;
    };
    const countImages = (node) => {
      if (!node || !node.querySelectorAll) {
        return 0;
      }
      return node.querySelectorAll('img,svg,picture').length;
    };
    const scoreContentNode = (node) => {
      const text = getNodeText(node);
      if (text.length < 80) {
        return 0;
      }
      const paragraphCount = collectContentBlockElements(node)
        .filter((item) => getNodeText(item).length >= 24).length;
      const semanticBonus = /^(ARTICLE|MAIN)$/.test(node.tagName || '') || node.getAttribute('role') === 'main' ? 180 : 0;
      const textScore = Math.min(1600, text.length) / 8;
      const paragraphScore = paragraphCount * 45;
      const densityPenalty = Math.round(getLinkDensity(node) * 220);
      const interactivePenalty = countInteractiveNodes(node) * 32;
      const imageCount = countImages(node);
      const imagePenalty = paragraphCount <= 2 && imageCount >= 4 ? imageCount * 24 : Math.max(0, imageCount - paragraphCount * 2) * 6;
      return textScore + paragraphScore + semanticBonus + getClassWeight(node) -
        densityPenalty - interactivePenalty - imagePenalty;
    };
    const buildSelectedSource = (node, strategy) => {
      return {
        node: node || document.body,
        strategy: strategy,
        score: Math.round(scoreContentNode(node || document.body))
      };
    };
    const selectBestScoredNode = () => {
      const paragraphNodes = collectElements(mergeUnique(
        ['p', 'pre', 'blockquote', 'li'],
        siteAdapter.contentBlockSelectors
      ))
        .filter((node) => getNodeText(node).length >= 24);
      const candidates = [];
      paragraphNodes.forEach((node) => {
        let parent = node.parentElement;
        let depth = 0;
        while (parent && depth < 3) {
          if (candidates.indexOf(parent) < 0 && getNodeText(parent).length >= 120) {
            candidates.push(parent);
          }
          parent = parent.parentElement;
          depth += 1;
        }
      });
      collectElements(['article', 'main', '[role="main"]', '.RichText', '.ztext', '.content', '.article', '.post'])
        .forEach((node) => {
          if (candidates.indexOf(node) < 0 && getNodeText(node).length >= 120) {
            candidates.push(node);
          }
        });
      if (candidates.length <= 0) {
        return undefined;
      }
      return buildSelectedSource(candidates.sort((a, b) => scoreContentNode(b) - scoreContentNode(a))[0], 'content_score');
    };
    const collectReadableNodes = (source) => {
      const selectors = siteAdapter.contentBlockSelectors.length > 0 ?
        siteAdapter.contentBlockSelectors :
        ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'a', 'blockquote', 'pre', 'li', 'table tr', 'img', 'figure'];
      const nodes = siteAdapter.contentBlockSelectors.length > 0 ?
        collectOutermostElementsWithin(source, selectors) :
        collectElementsWithin(source, selectors);
      if (nodes.length > 0) {
        return nodes;
      }
      return Array.from(source.children || []);
    };
    const findAncestor = (node, predicate) => {
      let current = node;
      let depth = 0;
      while (current && depth < 5) {
        if (predicate(current)) {
          return current;
        }
        current = current.parentElement;
        depth += 1;
      }
      return null;
    };
    const queryClosestText = (node, selector) => {
      const ancestor = findAncestor(node, (item) => item.matches && item.matches(selector));
      if (!ancestor) {
        return '';
      }
      return getNodeText(ancestor);
    };
    const queryDescendantText = (node, selector) => {
      if (!node || !node.querySelector) {
        return '';
      }
      const descendant = node.querySelector(selector);
      if (!descendant) {
        return '';
      }
      return getNodeText(descendant);
    };
    const readImageCaption = (node) => {
      const figureCaption = queryClosestText(node, 'figure figcaption, figure .caption, figure .image-caption');
      if (figureCaption) {
        return figureCaption;
      }
      const figure = findAncestor(node, (item) => item.matches && item.matches('figure'));
      const descendantCaption = queryDescendantText(figure, 'figcaption, .caption, .image-caption');
      if (descendantCaption) {
        return descendantCaption;
      }
      const parent = node.parentElement;
      if (!parent) {
        return '';
      }
      return queryDescendantText(parent, 'figcaption, .caption, .image-caption');
    };
    const isPlaceholderImageUrl = (value) => {
      const normalized = String(value || '').trim().toLowerCase();
      if (!normalized) {
        return true;
      }
      if (normalized.startsWith('data:image/svg') || normalized.startsWith('data:image/gif')) {
        return true;
      }
      return normalized === 'about:blank' || normalized.indexOf('placeholder') >= 0 ||
        normalized.indexOf('spacer') >= 0 || normalized.indexOf('transparent') >= 0 ||
        normalized.indexOf('pixel') >= 0 || normalized.indexOf('loading') >= 0 ||
        normalized.indexOf('1x1') >= 0 || normalized.indexOf('/blank.') >= 0;
    };
    const readBestSrcsetUrl = (value) => {
      const candidates = String(value || '').split(',')
        .map((item) => item.trim())
        .filter((item) => item.length > 0)
        .map((item) => {
          const parts = item.split(/\\s+/).filter((part) => part.length > 0);
          const url = parts.length > 0 ? parts[0] : '';
          const descriptor = parts.length > 1 ? parts[parts.length - 1] : '';
          let score = 1;
          if (descriptor.endsWith('w')) {
            score = Number(descriptor.substring(0, descriptor.length - 1)) || score;
          } else if (descriptor.endsWith('x')) {
            score = (Number(descriptor.substring(0, descriptor.length - 1)) || score) * 1000;
          }
          return { url: url, score: score };
        })
        .filter((item) => item.url.length > 0 && !isPlaceholderImageUrl(item.url));
      if (candidates.length <= 0) {
        return '';
      }
      candidates.sort((a, b) => b.score - a.score);
      return candidates[0].url;
    };
    const readPictureSourceUrl = (node) => {
      const picture = findAncestor(node, (item) => item.matches && item.matches('picture'));
      if (!picture || !picture.querySelectorAll) {
        return '';
      }
      const sources = Array.from(picture.querySelectorAll('source'));
      for (const source of sources) {
        const srcset = source.getAttribute('srcset') || source.getAttribute('data-srcset') || '';
        const url = readBestSrcsetUrl(srcset);
        if (url) {
          return url;
        }
      }
      return '';
    };
    const readStyleImageUrl = (node) => {
      const style = String(node.getAttribute ? (node.getAttribute('style') || '') : '');
      const match = /url\\((['"]?)(.*?)\\1\\)/i.exec(style);
      const value = match && match.length >= 3 ? normalizeText(match[2] || '') : '';
      return value && !isPlaceholderImageUrl(value) ? value : '';
    };
    const readNoscriptImageUrl = (node) => {
      const container = findAncestor(node, (item) => item.matches && item.matches('figure, picture, p, div')) || node.parentElement;
      if (!container || !container.querySelectorAll) {
        return '';
      }
      const noscripts = Array.from(container.querySelectorAll('noscript'));
      for (const noscript of noscripts) {
        const html = String(noscript.textContent || '');
        const doc = document.implementation && document.implementation.createHTMLDocument ?
          document.implementation.createHTMLDocument('reader-noscript') : null;
        if (!doc) {
          continue;
        }
        doc.body.innerHTML = html;
        const image = doc.body.querySelector('img,source');
        if (!image) {
          continue;
        }
        const url = readImageUrl(image);
        if (url) {
          return url;
        }
      }
      return '';
    };
    const collectImageUrls = (node) => {
      const urls = [];
      const addUrl = (value) => {
        const normalized = normalizeText(value || '');
        if (normalized && !isPlaceholderImageUrl(normalized) && urls.indexOf(normalized) < 0) {
          urls.push(normalized);
        }
      };
      const attributes = mergeUnique(siteAdapter.imageAttributes, [
        'data-original', 'data-actualsrc', 'data-src', 'data-lazy-src', 'data-url', 'data-backsrc',
        'data-large', 'data-full', 'data-hi-res-src', 'data-image', 'data-image-src',
        'currentSrc', 'src'
      ]);
      for (const name of attributes) {
        const value = name === 'currentSrc' ? node.currentSrc : name === 'src' ? node.src : node.getAttribute(name);
        addUrl(value);
      }
      addUrl(readBestSrcsetUrl(node.getAttribute('data-srcset') || node.getAttribute('srcset') || ''));
      addUrl(readPictureSourceUrl(node));
      addUrl(readStyleImageUrl(node));
      addUrl(readNoscriptImageUrl(node));
      return urls;
    };
    const hasStandaloneImageCandidate = (node, tag) => {
      if (!node || !node.getAttribute) {
        return false;
      }
      if (tag === 'picture' || tag === 'source') {
        return collectImageUrls(node).length > 0;
      }
      if (tag !== 'figure' && tag !== 'div' && tag !== 'span') {
        return false;
      }
      if (node.querySelector && node.querySelector('img,picture,source')) {
        return false;
      }
      const signal = String((node.getAttribute('class') || '') + ' ' + (node.getAttribute('id') || '')).toLowerCase();
      return /image|photo|figure|media|lazy|cover|thumb/.test(signal) && collectImageUrls(node).length > 0;
    };
    const buildImageBlock = (node) => {
      const parent = node.parentElement;
      const figure = findAncestor(node, (item) => item.matches && item.matches('figure'));
      const rect = node.getBoundingClientRect ? node.getBoundingClientRect() : undefined;
      const urls = collectImageUrls(node);
      const altText = node.getAttribute ? (node.getAttribute('alt') || '') : '';
      const titleText = node.getAttribute ? (node.getAttribute('title') || '') : '';
      const widthAttr = node.getAttribute ? (node.getAttribute('width') || 0) : 0;
      const heightAttr = node.getAttribute ? (node.getAttribute('height') || 0) : 0;
      return {
        type: 'image',
        text: normalizeText(altText || titleText),
        url: urls.length > 0 ? urls[0] : '',
        fallbackUrls: urls.slice(1, 7),
        alt: altText,
        caption: readImageCaption(node),
        width: node.naturalWidth || Number(widthAttr || 0) || 0,
        height: node.naturalHeight || Number(heightAttr || 0) || 0,
        renderedWidth: Math.max(node.clientWidth || 0, rect ? rect.width : 0),
        renderedHeight: Math.max(node.clientHeight || 0, rect ? rect.height : 0),
        sourceTagName: String(node.tagName || '').toLowerCase(),
        sourceClassName: String((node.getAttribute ? (node.getAttribute('class') || '') : '') + ' ' +
          (parent && parent.getAttribute ? (parent.getAttribute('class') || '') : '') + ' ' +
          (figure && figure.getAttribute ? (figure.getAttribute('class') || '') : '')).trim(),
        sourceId: String((node.getAttribute ? (node.getAttribute('id') || '') : '') + ' ' +
          (parent && parent.getAttribute ? (parent.getAttribute('id') || '') : '') + ' ' +
          (figure && figure.getAttribute ? (figure.getAttribute('id') || '') : '')).trim(),
        sourceRole: String((node.getAttribute ? (node.getAttribute('role') || '') : '') + ' ' +
          (parent && parent.getAttribute ? (parent.getAttribute('role') || '') : '') + ' ' +
          (figure && figure.getAttribute ? (figure.getAttribute('role') || '') : '')).trim()
      };
    };
    const buildDiagnostics = (source, selectedSource, articleBlocks) => {
      const imageCount = articleBlocks.filter((block) => block.type === 'image').length;
      return {
        adapterId: siteAdapter.id,
        sourceTagName: String(source.tagName || '').toLowerCase(),
        sourceClassName: String(source.getAttribute ? (source.getAttribute('class') || '') : '').slice(0, 160),
        sourceTextLength: getNodeText(source).length,
        sourceScore: selectedSource.score,
        candidateCount: collectReadableNodes(source).length,
        extractionStrategy: selectedSource.strategy + ':blocks=' + articleBlocks.length,
        rawBlockCount: articleBlocks.length,
        retainedBlockCount: articleBlocks.length,
        rawImageCount: imageCount,
        retainedImageCount: imageCount,
        hiddenImageCount: 0,
        postProcessSummary: ''
      };
    };
    const queryTextBySelectors = (selectors) => {
      for (const selector of selectors || []) {
        try {
          const node = document.querySelector(selector);
          if (!node) {
            continue;
          }
          const text = normalizeText(node.getAttribute('datetime') || node.getAttribute('content') || node.getAttribute('title') || node.innerText || node.textContent || '');
          if (text) {
            return text;
          }
        } catch (error) {
        }
      }
      return '';
    };
    const buildArticleMetadata = (selectedSource) => {
      const metadata = selectedSource && selectedSource.metadata ? selectedSource.metadata : {};
      return {
        title: normalizeText(metadata.title || '') || getMeta(['og:title', 'twitter:title']) ||
          queryTextBySelectors(siteAdapter.titleSelectors) ||
          normalizeText(document.querySelector('h1')?.innerText || '') || normalizeText(document.title),
        byline: normalizeText(metadata.byline || '') || getMeta(['author', 'article:author', 'twitter:creator']) ||
          queryTextBySelectors(siteAdapter.bylineSelectors),
        siteName: normalizeText(metadata.siteName || '') || getMeta(['og:site_name', 'application-name']) ||
          siteAdapter.siteName || location.host,
        publishedAt: normalizeText(metadata.publishedTime || '') ||
          getMeta(['article:published_time', 'pubdate', 'publishdate', 'date', 'datePublished']) ||
          queryTextBySelectors(siteAdapter.publishedAtSelectors),
        excerpt: normalizeText(metadata.excerpt || '') || getMeta(['description', 'og:description'])
      };
    };
    const pushPlainTextFallbackBlocks = (node, force) => {
      if (!node || (!force && blocks.length > 0)) {
        return;
      }
      const text = getNodeText(node);
      if (text.length < 120) {
        return;
      }
      const chunks = text
        .split(/\\n+|\\s{2,}/)
        .map((item) => normalizeText(item))
        .filter((item) => item.length >= 32)
        .slice(0, 80);
      const seen = {};
      blocks.forEach((block) => {
        const blockText = normalizeText(block.text || '');
        if (blockText) {
          seen[blockText] = true;
        }
      });
      chunks.forEach((item) => {
        if (!seen[item]) {
          seen[item] = true;
          pushBlock({ type: 'paragraph', text: item });
        }
      });
    };
    const readImageUrl = (node) => {
      const urls = collectImageUrls(node);
      return urls.length > 0 ? urls[0] : '';
    };
    const siteAdapter = resolveSiteAdapter();
`;
  }

  private normalizeCandidate(candidate: ReaderModeProbeCandidate): ReaderModeProbeCandidate {
    return {
      selector: this.normalizeText(candidate.selector),
      tagName: this.normalizeText(candidate.tagName),
      textLength: this.normalizeNumber(candidate.textLength),
      paragraphCount: this.normalizeNumber(candidate.paragraphCount),
      linkTextLength: this.normalizeNumber(candidate.linkTextLength),
      score: this.normalizeNumber(candidate.score)
    };
  }

  private normalizeBlock(block: ReaderExtractionRawBlock, index: number): ReaderModeBlock {
    return {
      id: `reader-block-${index}`,
      type: this.normalizeBlockType(block.type),
      text: this.normalizeText(block.text).slice(0, READER_MAX_BLOCK_TEXT_LENGTH),
      url: this.normalizeText(block.url),
      originalUrl: this.normalizeText(block.url),
      fallbackUrls: this.normalizeUrlList(block.fallbackUrls),
      alt: this.normalizeText(block.alt),
      caption: this.normalizeText(block.caption),
      level: this.normalizeNumber(block.level),
      width: this.normalizeNumber(block.width),
      height: this.normalizeNumber(block.height),
      renderedWidth: this.normalizeNumber(block.renderedWidth),
      renderedHeight: this.normalizeNumber(block.renderedHeight),
      sourceTagName: this.normalizeText(block.sourceTagName),
      sourceClassName: this.normalizeText(block.sourceClassName),
      sourceId: this.normalizeText(block.sourceId),
      sourceRole: this.normalizeText(block.sourceRole)
    };
  }

  private normalizeBlockType(type: string | undefined): ReaderModeBlockType {
    if (type === 'heading' || type === 'image' || type === 'link' || type === 'quote' || type === 'list_item' ||
      type === 'code') {
      return type;
    }
    return 'paragraph';
  }

  private normalizeDiagnostics(diagnostics: ReaderExtractionRawDiagnostics | undefined): ReaderModeArticleDiagnostics {
    return {
      adapterId: this.normalizeText(diagnostics?.adapterId),
      sourceTagName: this.normalizeText(diagnostics?.sourceTagName),
      sourceClassName: this.normalizeText(diagnostics?.sourceClassName),
      sourceTextLength: this.normalizeNumber(diagnostics?.sourceTextLength),
      sourceScore: this.normalizeNumber(diagnostics?.sourceScore),
      candidateCount: this.normalizeNumber(diagnostics?.candidateCount),
      extractionStrategy: this.normalizeText(diagnostics?.extractionStrategy),
      rawBlockCount: this.normalizeNumber(diagnostics?.rawBlockCount),
      retainedBlockCount: this.normalizeNumber(diagnostics?.retainedBlockCount),
      rawImageCount: this.normalizeNumber(diagnostics?.rawImageCount),
      retainedImageCount: this.normalizeNumber(diagnostics?.retainedImageCount),
      hiddenImageCount: this.normalizeNumber(diagnostics?.hiddenImageCount),
      postProcessSummary: this.normalizeText(diagnostics?.postProcessSummary)
    };
  }

  private normalizeText(value: string | undefined): string {
    return (value ?? '').trim();
  }

  private normalizeRawScriptResult(rawResult: string): string {
    const trimmed = rawResult.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        const parsed = JSON.parse(trimmed) as string;
        return typeof parsed === 'string' ? parsed.trim() : trimmed;
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private normalizeNumber(value: number | undefined): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }

  private normalizeUrlList(values: string[] | undefined): string[] {
    if (!Array.isArray(values)) {
      return [];
    }
    const seen: Record<string, boolean> = {};
    const normalized: string[] = [];
    values.forEach((value: string) => {
      const item = this.normalizeText(value);
      if (item.length <= 0 || seen[item]) {
        return;
      }
      seen[item] = true;
      normalized.push(item);
    });
    return normalized.slice(0, 6);
  }

  private buildEmptyProbe(): ReaderModeProbeResult {
    return {
      url: '',
      title: '',
      host: '',
      siteName: '',
      publishedAt: '',
      paragraphCount: 0,
      textLength: 0,
      linkTextLength: 0,
      candidates: []
    };
  }
}
