import {
  ReaderModeArticle,
  ReaderModeArticleDiagnostics,
  ReaderModeBlock,
  ReaderModeBlockType
} from '../../features/reader/ReaderModeModels';
import { ReaderArticlePostProcessor } from '../../features/reader/ReaderArticlePostProcessor';
import { ReaderImageQualityService } from '../../features/reader/ReaderImageQualityService';

export interface OfflineReaderExtractionInput {
  html: string;
  title: string;
  siteName: string;
  url: string;
}

interface OfflineReaderCandidate {
  html: string;
  strategy: string;
  score: number;
  textLength: number;
  blockCount: number;
}

const OFFLINE_READER_MAX_BLOCKS: number = 220;
const OFFLINE_READER_MIN_TEXT_LENGTH: number = 24;

export class OfflineReaderExtractionService {
  private postProcessor: ReaderArticlePostProcessor = new ReaderArticlePostProcessor();
  private imageQualityService: ReaderImageQualityService = new ReaderImageQualityService();

  extract(input: OfflineReaderExtractionInput): ReaderModeArticle {
    const source = this.removeDangerousBlocks(input.html);
    const body = this.extractBody(source);
    const candidate = this.selectCandidate(body);
    const rawBlocks = this.extractBlocks(candidate.html, input.url).slice(0, OFFLINE_READER_MAX_BLOCKS);
    const article = this.buildArticle(input, rawBlocks, this.buildDiagnostics(candidate, rawBlocks.length));
    return this.imageQualityService.filterArticleImages(this.postProcessor.process(article));
  }

  private buildArticle(
    input: OfflineReaderExtractionInput,
    blocks: ReaderModeBlock[],
    diagnostics: ReaderModeArticleDiagnostics
  ): ReaderModeArticle {
    return {
      title: this.resolveTitle(input.html, input.title),
      byline: '',
      siteName: this.resolveSiteName(input.html, input.siteName),
      publishedAt: this.resolveMetaContent(input.html, [
        'article:published_time',
        'pubdate',
        'publishdate',
        'date',
        'datePublished'
      ]),
      url: input.url,
      excerpt: this.resolveMetaContent(input.html, ['description', 'og:description']),
      diagnostics: diagnostics,
      blocks: blocks
    };
  }

  private buildDiagnostics(candidate: OfflineReaderCandidate, rawBlockCount: number): ReaderModeArticleDiagnostics {
    return {
      adapterId: 'offline-html',
      sourceTagName: '',
      sourceClassName: '',
      sourceTextLength: candidate.textLength,
      sourceScore: candidate.score,
      candidateCount: 1,
      extractionStrategy: candidate.strategy,
      rawBlockCount: rawBlockCount
    };
  }

  private removeDangerousBlocks(html: string): string {
    return html
      .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
      .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '')
      .replace(/<noscript\b[^>]*>[\s\S]*?<\/noscript>/gi, '')
      .replace(/<svg\b[^>]*>[\s\S]*?<\/svg>/gi, '');
  }

  private extractBody(html: string): string {
    const match = /<body\b[^>]*>([\s\S]*?)<\/body>/i.exec(html);
    return match !== null ? match[1] : html;
  }

  private selectCandidate(body: string): OfflineReaderCandidate {
    const candidates: OfflineReaderCandidate[] = [];
    this.collectTagCandidates(body, 'article', candidates);
    this.collectTagCandidates(body, 'main', candidates);
    this.collectClassCandidates(body, candidates);
    candidates.push(this.buildCandidate(body, 'body'));
    candidates.sort((left: OfflineReaderCandidate, right: OfflineReaderCandidate) => right.score - left.score);
    return candidates.length > 0 ? candidates[0] : this.buildCandidate(body, 'body');
  }

  private collectTagCandidates(body: string, tagName: string, candidates: OfflineReaderCandidate[]): void {
    const pattern = new RegExp(`<${tagName}\\b[^>]*>([\\s\\S]*?)<\\/${tagName}>`, 'gi');
    let match = pattern.exec(body);
    while (match !== null) {
      candidates.push(this.buildCandidate(match[1], tagName));
      match = pattern.exec(body);
    }
  }

  private collectClassCandidates(body: string, candidates: OfflineReaderCandidate[]): void {
    const pattern = /<([a-z0-9]+)\b[^>]*(class|id)=["'][^"']*(article|content|post|entry|main|正文)[^"']*["'][^>]*>([\s\S]*?)<\/\1>/gi;
    let match = pattern.exec(body);
    while (match !== null) {
      candidates.push(this.buildCandidate(match[4], `.${match[3]}`));
      match = pattern.exec(body);
    }
  }

  private buildCandidate(html: string, strategy: string): OfflineReaderCandidate {
    const text = this.normalizeText(this.stripTags(html));
    const blockCount = this.countReadableBlocks(html);
    const linkText = this.normalizeText(this.stripTags(this.collectTagHtml(html, 'a'))).length;
    const score = text.length + (blockCount * 120) - Math.floor(linkText * 1.2);
    return {
      html: html,
      strategy: strategy,
      score: score,
      textLength: text.length,
      blockCount: blockCount
    };
  }

  private collectTagHtml(html: string, tagName: string): string {
    const pattern = new RegExp(`<${tagName}\\b[^>]*>[\\s\\S]*?<\\/${tagName}>`, 'gi');
    const values: string[] = [];
    let match = pattern.exec(html);
    while (match !== null) {
      values.push(match[0]);
      match = pattern.exec(html);
    }
    return values.join('\n');
  }

  private countReadableBlocks(html: string): number {
    const pattern = /<(p|h[1-6]|blockquote|li|pre)\b[^>]*>([\s\S]*?)<\/\1>/gi;
    let count = 0;
    let match = pattern.exec(html);
    while (match !== null) {
      if (this.normalizeText(this.stripTags(match[2])).length >= OFFLINE_READER_MIN_TEXT_LENGTH) {
        count += 1;
      }
      match = pattern.exec(html);
    }
    return count;
  }

  private extractBlocks(html: string, baseUrl: string): ReaderModeBlock[] {
    const blocks: ReaderModeBlock[] = [];
    const pattern = /<(h[1-6]|p|blockquote|li|pre)\b([^>]*)>([\s\S]*?)<\/\1>|<img\b([^>]*)>/gi;
    let match = pattern.exec(html);
    while (match !== null && blocks.length < OFFLINE_READER_MAX_BLOCKS) {
      if (match[1] !== undefined) {
        const tagName = match[1].toLowerCase();
        const text = this.normalizeText(this.stripTags(match[3]));
        if (text.length > 0) {
          blocks.push(this.buildTextBlock(tagName, text, blocks.length));
        }
      } else if (match[4] !== undefined) {
        const src = this.readAttribute(match[4], 'src');
        if (src.length > 0) {
          blocks.push(this.buildImageBlock(match[4], src, baseUrl, blocks.length));
        }
      }
      match = pattern.exec(html);
    }
    if (blocks.length <= 0) {
      return this.extractFallbackParagraphs(html);
    }
    return blocks;
  }

  private buildTextBlock(tagName: string, text: string, index: number): ReaderModeBlock {
    return {
      id: `offline-reader-${index}`,
      type: this.resolveBlockType(tagName),
      text: text,
      level: this.resolveHeadingLevel(tagName)
    };
  }

  private buildImageBlock(attrs: string, src: string, baseUrl: string, index: number): ReaderModeBlock {
    return {
      id: `offline-reader-${index}`,
      type: 'image',
      text: '',
      url: this.resolveUrl(src, baseUrl),
      originalUrl: src,
      alt: this.normalizeText(this.readAttribute(attrs, 'alt')),
      caption: ''
    };
  }

  private extractFallbackParagraphs(html: string): ReaderModeBlock[] {
    const text = this.normalizeText(this.stripTags(html));
    if (text.length <= 0) {
      return [];
    }
    const blocks: ReaderModeBlock[] = [];
    let offset = 0;
    while (offset < text.length && blocks.length < OFFLINE_READER_MAX_BLOCKS) {
      const chunk = text.substring(offset, Math.min(text.length, offset + 420)).trim();
      if (chunk.length > 0) {
        blocks.push({
          id: `offline-reader-${blocks.length}`,
          type: 'paragraph',
          text: chunk
        });
      }
      offset += 420;
    }
    return blocks;
  }

  private resolveBlockType(tagName: string): ReaderModeBlockType {
    if (tagName.startsWith('h')) {
      return 'heading';
    }
    if (tagName === 'blockquote') {
      return 'quote';
    }
    if (tagName === 'li') {
      return 'list_item';
    }
    if (tagName === 'pre') {
      return 'code';
    }
    return 'paragraph';
  }

  private resolveHeadingLevel(tagName: string): number | undefined {
    if (!tagName.startsWith('h')) {
      return undefined;
    }
    const level = Number(tagName.substring(1));
    return isNaN(level) ? undefined : level;
  }

  private resolveTitle(html: string, fallback: string): string {
    const candidates: string[] = [
      fallback,
      this.resolveMetaContent(html, ['og:title', 'twitter:title']),
      this.extractTitleTag(html)
    ];
    return this.firstNonEmpty(candidates);
  }

  private resolveSiteName(html: string, fallback: string): string {
    return this.firstNonEmpty([fallback, this.resolveMetaContent(html, ['og:site_name', 'application-name'])]);
  }

  private extractTitleTag(html: string): string {
    const match = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html);
    return match !== null ? this.normalizeText(this.decodeEntities(match[1])) : '';
  }

  private resolveMetaContent(html: string, names: string[]): string {
    for (let index = 0; index < names.length; index += 1) {
      const name = names[index];
      const pattern = new RegExp(`<meta\\b[^>]*(name|property)=["']${this.escapeRegExp(name)}["'][^>]*>`, 'i');
      const match = pattern.exec(html);
      if (match !== null) {
        const content = this.readAttribute(match[0], 'content');
        if (content.length > 0) {
          return this.normalizeText(content);
        }
      }
    }
    return '';
  }

  private firstNonEmpty(values: string[]): string {
    for (let index = 0; index < values.length; index += 1) {
      const value = this.normalizeText(values[index]);
      if (value.length > 0) {
        return value;
      }
    }
    return '';
  }

  private stripTags(html: string): string {
    return this.decodeEntities(html
      .replace(/<br\b[^>]*>/gi, '\n')
      .replace(/<\/(p|div|section|article|main|li|blockquote|h[1-6]|pre)>/gi, '\n')
      .replace(/<[^>]+>/g, ' '));
  }

  private normalizeText(value: string): string {
    return this.decodeEntities(value).replace(/\s+/g, ' ').trim();
  }

  private readAttribute(attrs: string, name: string): string {
    const pattern = new RegExp(`${this.escapeRegExp(name)}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s>]+))`, 'i');
    const match = pattern.exec(attrs);
    if (match === null) {
      return '';
    }
    return this.decodeEntities(match[2] ?? match[3] ?? match[4] ?? '').trim();
  }

  private resolveUrl(url: string, baseUrl: string): string {
    const normalized = url.trim();
    if (normalized.length <= 0 || /^[a-z][a-z0-9+.-]*:/i.test(normalized)) {
      return normalized;
    }
    if (normalized.startsWith('//')) {
      return `https:${normalized}`;
    }
    const origin = this.resolveOrigin(baseUrl);
    if (normalized.startsWith('/')) {
      return origin.length > 0 ? `${origin}${normalized}` : normalized;
    }
    const baseDir = baseUrl.includes('/') ? baseUrl.substring(0, baseUrl.lastIndexOf('/') + 1) : '';
    return baseDir.length > 0 ? `${baseDir}${normalized}` : normalized;
  }

  private resolveOrigin(url: string): string {
    const match = /^(https?:\/\/[^/]+)/i.exec(url.trim());
    return match !== null ? match[1] : '';
  }

  private decodeEntities(value: string): string {
    return value
      .replace(/&nbsp;/gi, ' ')
      .replace(/&amp;/gi, '&')
      .replace(/&lt;/gi, '<')
      .replace(/&gt;/gi, '>')
      .replace(/&quot;/gi, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/gi, "'")
      .replace(/&mdash;/gi, '-')
      .replace(/&ndash;/gi, '-')
      .replace(/&hellip;/gi, '...')
      .replace(/&#x([0-9a-f]+);/gi, (_match: string, hex: string): string => String.fromCharCode(parseInt(hex, 16)))
      .replace(/&#([0-9]+);/g, (_match: string, code: string): string => String.fromCharCode(parseInt(code, 10)));
  }

  private escapeRegExp(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
