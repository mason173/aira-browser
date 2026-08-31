import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import urlUtils from '@ohos.url';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { ReaderModeArticle, ReaderModeArticleDiagnostics, ReaderModeBlock } from '../../features/reader/ReaderModeModels';
import { AIRA_COMPAT_MOBILE_USER_AGENT } from './BrowserUserAgentService';

const READER_IMAGE_CACHE_DIR_NAME: string = 'reader-mode-images';
const READER_IMAGE_REQUEST_TIMEOUT_MS: number = 7000;
const READER_IMAGE_MAX_BYTES: number = 6 * 1024 * 1024;
const READER_IMAGE_MAX_CACHE_COUNT: number = 18;

export interface ReaderCachedImageResult {
  sourceUrl: string;
  cachedUrl: string;
}

interface ReaderImageCacheAttempt {
  sourceUrl: string;
  cachedUrl: string;
  reason: string;
}

interface ReaderImageSourceCandidate {
  url: string;
}

export class ReaderImageCacheService {
  async cacheArticleImages(article: ReaderModeArticle): Promise<ReaderModeArticle> {
    const attempts: ReaderImageCacheAttempt[] = [];
    let cachedCount = 0;
    for (let index = 0; index < article.blocks.length; index += 1) {
      const block = article.blocks[index];
      if (block.type !== 'image' || cachedCount >= READER_IMAGE_MAX_CACHE_COUNT) {
        continue;
      }
      const candidates = this.collectSourceCandidates(block);
      if (candidates.length <= 0) {
        attempts.push({
          sourceUrl: block.originalUrl ?? block.url ?? '',
          cachedUrl: '',
          reason: 'unsupported_url'
        });
        continue;
      }
      const successfulAttempt = await this.resolveCachedCandidate(candidates, article.url);
      if (successfulAttempt.cachedUrl.length <= 0) {
        attempts.push({
          sourceUrl: candidates[0].url,
          cachedUrl: '',
          reason: 'fetch_failed'
        });
        continue;
      }
      attempts.push(successfulAttempt);
      cachedCount += 1;
    }
    return this.applyCachedImages(article, attempts);
  }

  applyCachedImages(article: ReaderModeArticle, cachedResults: ReaderCachedImageResult[]): ReaderModeArticle {
    const attempts: ReaderImageCacheAttempt[] = [];
    cachedResults.forEach((item: ReaderCachedImageResult) => {
      const attempt: ReaderImageCacheAttempt = {
        sourceUrl: item.sourceUrl,
        cachedUrl: item.cachedUrl,
        reason: ''
      };
      attempts.push(attempt);
    });
    return this.applyCachedImageAttempts(article, attempts);
  }

  private applyCachedImageAttempts(article: ReaderModeArticle, attempts: ReaderImageCacheAttempt[]): ReaderModeArticle {
    if (attempts.length <= 0) {
      return article;
    }
    let cachedCount = 0;
    let failedCount = 0;
    attempts.forEach((item: ReaderImageCacheAttempt) => {
      if (item.cachedUrl.length > 0) {
        cachedCount += 1;
      } else {
        failedCount += 1;
      }
    });
    return {
      title: article.title,
      byline: article.byline,
      siteName: article.siteName,
      publishedAt: article.publishedAt,
      url: article.url,
      excerpt: article.excerpt,
      diagnostics: this.buildCacheDiagnostics(article, cachedCount, failedCount),
      blocks: article.blocks.map((block: ReaderModeBlock) => {
        if (block.type !== 'image') {
          return block;
        }
        const cached = this.findAttemptForBlock(block, attempts);
        if (cached === undefined) {
          return block;
        }
        if (cached.cachedUrl.length <= 0) {
          return {
            id: block.id,
            type: block.type,
            text: block.text,
            url: block.url,
            originalUrl: block.originalUrl ?? block.url ?? '',
            fallbackUrls: block.fallbackUrls,
            alt: block.alt,
            caption: block.caption,
            level: block.level,
            width: block.width,
            height: block.height,
            renderedWidth: block.renderedWidth,
            renderedHeight: block.renderedHeight,
            qualityScore: block.qualityScore,
            hiddenReason: cached.reason,
            imageFailurePolicy: block.imageFailurePolicy,
            sourceTagName: block.sourceTagName,
            sourceClassName: block.sourceClassName,
            sourceId: block.sourceId,
            sourceRole: block.sourceRole
          };
        }
        return {
          id: block.id,
          type: block.type,
          text: block.text,
          url: cached.cachedUrl,
          originalUrl: block.originalUrl ?? block.url ?? '',
          fallbackUrls: this.buildCachedFallbackUrls(block, cached.sourceUrl),
          alt: block.alt,
          caption: block.caption,
          level: block.level,
          width: block.width,
          height: block.height,
          renderedWidth: block.renderedWidth,
          renderedHeight: block.renderedHeight,
          qualityScore: block.qualityScore,
          hiddenReason: block.hiddenReason,
          imageFailurePolicy: block.imageFailurePolicy,
          sourceTagName: block.sourceTagName,
          sourceClassName: block.sourceClassName,
          sourceId: block.sourceId,
          sourceRole: block.sourceRole
        };
      })
    };
  }

  private buildCacheDiagnostics(
    article: ReaderModeArticle,
    cachedCount: number,
    failedCount: number
  ): ReaderModeArticleDiagnostics | undefined {
    const diagnostics = article.diagnostics;
    if (diagnostics === undefined) {
      return diagnostics;
    }
    const previous = diagnostics.postProcessSummary ?? '';
    const next = `cache:${cachedCount},failed:${failedCount}`;
    return {
      adapterId: diagnostics.adapterId,
      sourceTagName: diagnostics.sourceTagName,
      sourceClassName: diagnostics.sourceClassName,
      sourceTextLength: diagnostics.sourceTextLength,
      sourceScore: diagnostics.sourceScore,
      candidateCount: diagnostics.candidateCount,
      extractionStrategy: diagnostics.extractionStrategy,
      rawBlockCount: diagnostics.rawBlockCount,
      retainedBlockCount: diagnostics.retainedBlockCount,
      rawImageCount: diagnostics.rawImageCount,
      retainedImageCount: diagnostics.retainedImageCount,
      hiddenImageCount: diagnostics.hiddenImageCount,
      postProcessSummary: previous.length > 0 ? `${previous};${next}` : next
    };
  }

  shouldCacheImageUrl(url: string): boolean {
    try {
      const parsed = urlUtils.URL.parseURL(url.trim());
      const protocol = parsed.protocol.toLowerCase();
      return protocol === 'http:' || protocol === 'https:';
    } catch (_error) {
      return false;
    }
  }

  private findAttemptForBlock(
    block: ReaderModeBlock,
    attempts: ReaderImageCacheAttempt[]
  ): ReaderImageCacheAttempt | undefined {
    const candidates = this.collectSourceCandidates(block);
    for (let index = 0; index < candidates.length; index += 1) {
      const sourceUrl = candidates[index].url;
      const attempt = attempts.find((item: ReaderImageCacheAttempt) => item.sourceUrl === sourceUrl);
      if (attempt !== undefined) {
        return attempt;
      }
    }
    return undefined;
  }

  private collectSourceCandidates(block: ReaderModeBlock): ReaderImageSourceCandidate[] {
    const urls: string[] = [];
    const candidates: ReaderImageSourceCandidate[] = [];
    this.addUniqueUrl(urls, block.originalUrl ?? '');
    this.addUniqueUrl(urls, block.url ?? '');
    (block.fallbackUrls ?? []).forEach((url: string) => {
      this.addUniqueUrl(urls, url);
    });
    urls.forEach((url: string) => {
      if (!this.shouldCacheImageUrl(url)) {
        return;
      }
      const candidate: ReaderImageSourceCandidate = {
        url: url
      };
      candidates.push(candidate);
    });
    return candidates;
  }

  private addUniqueUrl(urls: string[], url: string): void {
    const normalized = url.trim();
    if (normalized.length <= 0 || urls.indexOf(normalized) >= 0) {
      return;
    }
    urls.push(normalized);
  }

  private async resolveCachedCandidate(
    candidates: ReaderImageSourceCandidate[],
    pageUrl: string
  ): Promise<ReaderImageCacheAttempt> {
    for (let index = 0; index < candidates.length; index += 1) {
      const sourceUrl = candidates[index].url;
      const cachedUrl = await this.resolveCachedImage(sourceUrl, pageUrl);
      if (cachedUrl.length > 0) {
        return {
          sourceUrl: sourceUrl,
          cachedUrl: cachedUrl,
          reason: ''
        };
      }
    }
    return {
      sourceUrl: candidates.length > 0 ? candidates[0].url : '',
      cachedUrl: '',
      reason: 'fetch_failed'
    };
  }

  private buildCachedFallbackUrls(block: ReaderModeBlock, cachedSourceUrl: string): string[] {
    const urls: string[] = [];
    this.addUniqueUrl(urls, block.url ?? '');
    this.addUniqueUrl(urls, block.originalUrl ?? '');
    (block.fallbackUrls ?? []).forEach((url: string) => {
      this.addUniqueUrl(urls, url);
    });
    return urls.filter((url: string) => url !== cachedSourceUrl).slice(0, 6);
  }

  buildRequestHeaders(imageUrl: string, pageUrl: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/gif,image/*;q=0.8,*/*;q=0.4',
      'User-Agent': AIRA_COMPAT_MOBILE_USER_AGENT
    };
    if (pageUrl.trim().length > 0) {
      headers['Referer'] = pageUrl.trim();
    }
    const cookie = this.resolveCookieHeader(imageUrl);
    if (cookie.length > 0) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  buildCachePathForUrl(imageUrl: string): string {
    return `${this.getCacheDir()}/${this.hashString(imageUrl)}.${this.resolveImageExtension(imageUrl)}`;
  }

  toImageUri(path: string): string {
    if (path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  private async resolveCachedImage(imageUrl: string, pageUrl: string): Promise<string> {
    const path = this.buildCachePathForUrl(imageUrl);
    if (await this.isCachedImageUsable(path)) {
      return this.toImageUri(path);
    }
    const data = await this.fetchImage(imageUrl, pageUrl);
    if (data.byteLength <= 0) {
      return '';
    }
    await this.writeImage(path, data);
    return this.toImageUri(path);
  }

  private async fetchImage(imageUrl: string, pageUrl: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const response = await request.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: READER_IMAGE_REQUEST_TIMEOUT_MS,
        readTimeout: READER_IMAGE_REQUEST_TIMEOUT_MS,
        usingCache: true,
        header: this.buildRequestHeaders(imageUrl, pageUrl)
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return new ArrayBuffer(0);
      }
      if (!(response.result instanceof ArrayBuffer)) {
        return new ArrayBuffer(0);
      }
      if (response.result.byteLength <= 0 || response.result.byteLength > READER_IMAGE_MAX_BYTES) {
        return new ArrayBuffer(0);
      }
      if (!this.isLikelyImagePayload(response.result)) {
        return new ArrayBuffer(0);
      }
      return response.result;
    } catch (_error) {
      return new ArrayBuffer(0);
    } finally {
      request.destroy();
    }
  }

  private async writeImage(path: string, data: ArrayBuffer): Promise<void> {
    await this.ensureCacheDir();
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data);
    } finally {
      await fileIo.close(file);
    }
  }

  private async isCachedImageUsable(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return stat.size > 0 && stat.size <= READER_IMAGE_MAX_BYTES;
    } catch (_error) {
      return false;
    }
  }

  private async ensureCacheDir(): Promise<void> {
    const dir = this.getCacheDir();
    try {
      if (await fileIo.access(dir)) {
        return;
      }
    } catch (_error) {
    }
    try {
      await fileIo.mkdir(dir, true);
    } catch (_error) {
    }
  }

  private getCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().cacheDir}/${READER_IMAGE_CACHE_DIR_NAME}`;
  }

  private resolveCookieHeader(url: string): string {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length <= 0) {
      return '';
    }
    try {
      return webview.WebCookieManager.fetchCookieSync(normalizedUrl, false).trim();
    } catch (_error) {
      return '';
    }
  }

  private resolveImageExtension(url: string): string {
    const normalized = url.toLowerCase();
    if (normalized.indexOf('.jpg') >= 0 || normalized.indexOf('.jpeg') >= 0) {
      return 'jpg';
    }
    if (normalized.indexOf('.webp') >= 0) {
      return 'webp';
    }
    if (normalized.indexOf('.gif') >= 0) {
      return 'gif';
    }
    if (normalized.indexOf('.svg') >= 0) {
      return 'svg';
    }
    return 'png';
  }

  private hashString(value: string): string {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  private isLikelyImagePayload(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data);
    if (bytes.length < 4) {
      return false;
    }
    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return true;
    }
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return true;
    }
    if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return true;
    }
    return this.looksLikeSvgPayload(bytes);
  }

  private looksLikeSvgPayload(bytes: Uint8Array): boolean {
    const limit = Math.min(bytes.length, 256);
    let snippet = '';
    for (let index = 0; index < limit; index += 1) {
      const value = bytes[index];
      if (value === 0) {
        return false;
      }
      snippet += String.fromCharCode(value);
    }
    const normalized = snippet.trim().toLowerCase();
    if (normalized.startsWith('<!doctype html') || normalized.startsWith('<html') ||
      normalized.startsWith('{') || normalized.startsWith('[')) {
      return false;
    }
    return normalized.indexOf('<svg') >= 0;
  }
}
