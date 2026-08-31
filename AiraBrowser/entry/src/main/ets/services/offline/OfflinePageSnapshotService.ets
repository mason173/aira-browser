import { webview } from '@kit.ArkWeb';
import {
  OfflinePageFailureReason,
  OfflinePageSnapshotMetadata,
  OfflinePageSnapshotResult
} from '../../common/models/OfflinePageModels';

interface OfflinePageSnapshotMetadataPayload {
  pageUrl?: string;
  title?: string;
  siteName?: string;
  host?: string;
  description?: string;
  htmlLength?: number;
  visibleTextLength?: number;
  imageElementCount?: number;
  mediaElementCount?: number;
  formElementCount?: number;
  resourceUrls?: string[];
  imageUrls?: string[];
  inlinedImageUrls?: string[];
  faviconUrls?: string[];
}

interface OfflinePageSnapshotOptions {
  maxHtmlChars?: number;
  chunkChars?: number;
}

const OFFLINE_SNAPSHOT_CACHE_KEY = '__airaOfflineSnapshotHtml';
const DEFAULT_MAX_HTML_CHARS: number = 5 * 1024 * 1024;
const DEFAULT_CHUNK_CHARS: number = 192 * 1024;
const MAX_RESOURCE_URLS: number = 160;
const MAX_IMAGE_URLS: number = 64;
const MAX_INLINED_IMAGE_URLS: number = 16;
const MAX_FAVICON_URLS: number = 16;

export class OfflinePageSnapshotService {
  async capture(
    controller: webview.WebviewController | undefined,
    options: OfflinePageSnapshotOptions = {}
  ): Promise<OfflinePageSnapshotResult> {
    if (controller === undefined) {
      return this.buildFailure('controller_unavailable');
    }
    const maxHtmlChars = Math.max(1, Math.floor(options.maxHtmlChars ?? DEFAULT_MAX_HTML_CHARS));
    const chunkChars = Math.max(32 * 1024, Math.floor(options.chunkChars ?? DEFAULT_CHUNK_CHARS));
    try {
      const metadata = await this.prepareSnapshot(controller);
      if (metadata.htmlLength <= 0) {
        await this.clearSnapshotCache(controller);
        return this.buildFailure('snapshot_failed', metadata);
      }
      if (metadata.htmlLength > maxHtmlChars) {
        await this.clearSnapshotCache(controller);
        return this.buildFailure('content_too_large', metadata);
      }
      const html = await this.readHtmlChunks(controller, metadata.htmlLength, chunkChars);
      await this.clearSnapshotCache(controller);
      if (html.length <= 0) {
        return this.buildFailure('snapshot_failed', metadata);
      }
      return {
        ok: true,
        reason: '',
        metadata: metadata,
        html: html
      };
    } catch (_error) {
      try {
        await this.clearSnapshotCache(controller);
      } catch (_clearError) {
      }
      return this.buildFailure('snapshot_failed');
    }
  }

  private async prepareSnapshot(controller: webview.WebviewController): Promise<OfflinePageSnapshotMetadata> {
    const rawResult = await controller.runJavaScript(this.buildPrepareScript());
    return this.parseMetadata(rawResult);
  }

  private async readHtmlChunks(
    controller: webview.WebviewController,
    htmlLength: number,
    chunkChars: number
  ): Promise<string> {
    const parts: string[] = [];
    for (let start = 0; start < htmlLength; start += chunkChars) {
      const end = Math.min(htmlLength, start + chunkChars);
      const rawChunk = await controller.runJavaScript(this.buildReadChunkScript(start, end));
      parts.push(this.normalizeRawString(rawChunk));
    }
    return parts.join('');
  }

  private async clearSnapshotCache(controller: webview.WebviewController): Promise<void> {
    await controller.runJavaScript(`try { window.${OFFLINE_SNAPSHOT_CACHE_KEY} = ''; } catch (error) {}`);
  }

  private buildPrepareScript(): string {
    return `
(() => {
  try {
    const trim = (value) => String(value || '').trim();
    const unique = (values, limit) => {
      const seen = {};
      const result = [];
      for (const value of values) {
        const item = trim(value);
        if (item.length === 0 || seen[item]) {
          continue;
        }
        seen[item] = true;
        result.push(item);
        if (result.length >= limit) {
          break;
        }
      }
      return result;
    };
    const absolutize = (value) => {
      try {
        return new URL(trim(value), window.location.href).href;
      } catch (error) {
        return '';
      }
    };
    const readMeta = (selector) => {
      const node = document.querySelector(selector);
      return node ? trim(node.getAttribute('content') || '') : '';
    };
    const readSrcSet = (value) => {
      return trim(value).split(',').map((part) => trim(part).split(/\\s+/)[0]).filter((part) => part.length > 0);
    };
    const visibleTextLength = trim(document.body ? document.body.innerText || '' : '').length;
    const imageElementCount = document.querySelectorAll('img, picture, svg').length;
    const mediaElementCount = document.querySelectorAll('video, audio, canvas').length;
    const formElementCount = document.querySelectorAll('input, textarea, select, button').length;
    const clone = document.documentElement ? document.documentElement.cloneNode(true) : document.createElement('html');
    const imageCandidates = [];
    const sourceImages = Array.from(document.querySelectorAll('img[src], img[data-src], source[srcset], img[srcset]'));
    sourceImages.forEach((node) => {
      const tag = String(node.tagName || '').toLowerCase();
      if (tag === 'source' || node.hasAttribute('srcset')) {
        readSrcSet(node.getAttribute('srcset') || '').forEach((url) => imageCandidates.push(absolutize(url)));
      }
      imageCandidates.push(absolutize(node.getAttribute('src') || node.getAttribute('data-src') || ''));
    });
    const ogImage = readMeta('meta[property="og:image"], meta[name="og:image"]');
    if (ogImage.length > 0) {
      imageCandidates.unshift(absolutize(ogImage));
    }
    const faviconCandidates = Array.from(document.querySelectorAll('link[rel~="icon"], link[rel="shortcut icon"], link[rel="apple-touch-icon"]'))
      .map((node) => absolutize(node.getAttribute('href') || ''));
    const resourceCandidates = [];
    try {
      performance.getEntriesByType('resource').forEach((entry) => {
        resourceCandidates.push(absolutize(entry.name || ''));
      });
    } catch (error) {
    }
    Array.from(document.querySelectorAll('link[rel="stylesheet"][href], script[src]')).forEach((node) => {
      resourceCandidates.push(absolutize(node.getAttribute('href') || node.getAttribute('src') || ''));
    });
    const clonedImages = Array.from(clone.querySelectorAll ? clone.querySelectorAll('img') : []);
    const inlinedImageUrls = [];
    let inlineBudget = 1200 * 1024;
    for (let index = 0; index < sourceImages.length && inlinedImageUrls.length < ${MAX_INLINED_IMAGE_URLS}; index += 1) {
      const sourceNode = sourceImages[index];
      const clonedNode = clonedImages[index];
      if (!sourceNode || !clonedNode || String(sourceNode.tagName || '').toLowerCase() !== 'img') {
        continue;
      }
      const sourceUrl = absolutize(sourceNode.getAttribute('currentSrc') || sourceNode.getAttribute('src') || sourceNode.getAttribute('data-src') || '');
      if (sourceUrl.length === 0 || sourceUrl.startsWith('data:') || sourceUrl.startsWith('blob:')) {
        continue;
      }
      if (!sourceNode.complete || sourceNode.naturalWidth <= 0 || sourceNode.naturalHeight <= 0) {
        continue;
      }
      try {
        const maxSide = 1280;
        const scale = Math.min(1, maxSide / Math.max(sourceNode.naturalWidth, sourceNode.naturalHeight));
        const width = Math.max(1, Math.round(sourceNode.naturalWidth * scale));
        const height = Math.max(1, Math.round(sourceNode.naturalHeight * scale));
        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;
        const ctx = canvas.getContext('2d');
        if (!ctx) {
          continue;
        }
        ctx.drawImage(sourceNode, 0, 0, width, height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.82);
        if (dataUrl.length <= 32 || dataUrl.length > inlineBudget) {
          continue;
        }
        inlineBudget -= dataUrl.length;
        clonedNode.setAttribute('data-aira-offline-original-src', sourceUrl);
        clonedNode.setAttribute('src', dataUrl);
        clonedNode.removeAttribute('srcset');
        clonedNode.removeAttribute('sizes');
        inlinedImageUrls.push(sourceUrl);
      } catch (error) {
      }
    }
    const html = '<!DOCTYPE html>\\n' + (clone ? clone.outerHTML : '');
    window.${OFFLINE_SNAPSHOT_CACHE_KEY} = html;
    const url = trim(window.location.href || '');
    let host = '';
    try {
      host = new URL(url).host;
    } catch (error) {
    }
    const siteName = readMeta('meta[property="og:site_name"], meta[name="application-name"]') || host;
    return JSON.stringify({
      pageUrl: url,
      title: trim(document.title || readMeta('meta[property="og:title"]')),
      siteName: siteName,
      host: host,
      description: readMeta('meta[name="description"], meta[property="og:description"]'),
      htmlLength: html.length,
      visibleTextLength: visibleTextLength,
      imageElementCount: imageElementCount,
      mediaElementCount: mediaElementCount,
      formElementCount: formElementCount,
      resourceUrls: unique(resourceCandidates, ${MAX_RESOURCE_URLS}),
      imageUrls: unique(imageCandidates, ${MAX_IMAGE_URLS}),
      inlinedImageUrls: unique(inlinedImageUrls, ${MAX_INLINED_IMAGE_URLS}),
      faviconUrls: unique(faviconCandidates, ${MAX_FAVICON_URLS})
    });
  } catch (error) {
    window.${OFFLINE_SNAPSHOT_CACHE_KEY} = '';
    return '';
  }
})()
`;
  }

  private buildReadChunkScript(start: number, end: number): string {
    return `
(() => {
  try {
    const html = String(window.${OFFLINE_SNAPSHOT_CACHE_KEY} || '');
    return html.substring(${Math.max(0, Math.floor(start))}, ${Math.max(0, Math.floor(end))});
  } catch (error) {
    return '';
  }
})()
`;
  }

  private parseMetadata(rawResult: string): OfflinePageSnapshotMetadata {
    const normalized = this.normalizeRawString(rawResult);
    if (normalized.length <= 0) {
      return this.buildEmptyMetadata();
    }
    try {
      const parsed = JSON.parse(normalized) as OfflinePageSnapshotMetadataPayload;
      return {
        pageUrl: this.readString(parsed.pageUrl),
        title: this.readString(parsed.title),
        siteName: this.readString(parsed.siteName),
        host: this.readString(parsed.host),
        description: this.readString(parsed.description),
        htmlLength: this.readNumber(parsed.htmlLength),
        visibleTextLength: this.readNumber(parsed.visibleTextLength),
        imageElementCount: this.readNumber(parsed.imageElementCount),
        mediaElementCount: this.readNumber(parsed.mediaElementCount),
        formElementCount: this.readNumber(parsed.formElementCount),
        resourceUrls: this.readStringArray(parsed.resourceUrls, MAX_RESOURCE_URLS),
        imageUrls: this.readStringArray(parsed.imageUrls, MAX_IMAGE_URLS),
        inlinedImageUrls: this.readStringArray(parsed.inlinedImageUrls, MAX_INLINED_IMAGE_URLS),
        faviconUrls: this.readStringArray(parsed.faviconUrls, MAX_FAVICON_URLS)
      };
    } catch (_error) {
      return this.buildEmptyMetadata();
    }
  }

  private normalizeRawString(rawResult: string): string {
    const trimmed = rawResult.trim();
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      try {
        return JSON.parse(trimmed) as string;
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1);
      }
    }
    return trimmed;
  }

  private buildFailure(
    reason: OfflinePageFailureReason,
    metadata: OfflinePageSnapshotMetadata = this.buildEmptyMetadata()
  ): OfflinePageSnapshotResult {
    return {
      ok: false,
      reason: reason,
      metadata: metadata,
      html: ''
    };
  }

  private buildEmptyMetadata(): OfflinePageSnapshotMetadata {
    return {
      pageUrl: '',
      title: '',
      siteName: '',
      host: '',
      description: '',
      htmlLength: 0,
      visibleTextLength: 0,
      imageElementCount: 0,
      mediaElementCount: 0,
      formElementCount: 0,
      resourceUrls: [],
      imageUrls: [],
      inlinedImageUrls: [],
      faviconUrls: []
    };
  }

  private readString(value?: string): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private readNumber(value?: number): number {
    return typeof value === 'number' && Number.isFinite(value) ? Math.max(0, Math.floor(value)) : 0;
  }

  private readStringArray(value: string[] | undefined, limit: number): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    const result: string[] = [];
    value.forEach((item: string) => {
      const normalized = this.readString(item);
      if (normalized.length > 0 && result.indexOf(normalized) < 0 && result.length < limit) {
        result.push(normalized);
      }
    });
    return result;
  }
}
