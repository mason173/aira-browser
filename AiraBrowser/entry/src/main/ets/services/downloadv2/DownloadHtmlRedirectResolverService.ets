import { http } from '@kit.NetworkKit';
import urlUtils from '@ohos.url';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadV2CapturedRequest } from '../../features/downloadv2/DownloadV2CaptureTypes';
import { DownloadFileNameService } from '../download/DownloadFileNameService';

const DOWNLOAD_HTML_REDIRECT_DOMAIN = 0x0000;
const DOWNLOAD_HTML_REDIRECT_TAG = 'DownloadHtmlRedirect';
const HTML_REDIRECT_TIMEOUT_MS = 8000;
const HTML_REDIRECT_MAX_BYTES = 128 * 1024;

export interface DownloadHtmlRedirectResolution {
  resolved: boolean;
  request: DownloadV2CapturedRequest;
}

interface DownloadHtmlRedirectProbeResult {
  statusCode: number;
  headers: Record<string, string>;
  body: string;
}

interface DownloadHtmlRedirectHeadResult {
  statusCode: number;
  headers: Record<string, string>;
  totalBytes: number;
  fileName: string;
  mimeType: string;
}

export class DownloadHtmlRedirectResolverService {
  private fileNameService: DownloadFileNameService = new DownloadFileNameService();

  async resolve(request: DownloadV2CapturedRequest): Promise<DownloadHtmlRedirectResolution> {
    if (!this.shouldProbe(request)) {
      return {
        resolved: false,
        request: request
      };
    }
    try {
      const probe = await this.fetchCandidateHtml(request);
      if (!this.isLikelyHtmlRedirect(probe)) {
        return {
          resolved: false,
          request: request
        };
      }
      const redirectUrl = this.extractRedirectUrl(probe.body, request.url);
      if (redirectUrl.length <= 0 || redirectUrl === request.url) {
        return {
          resolved: false,
          request: request
        };
      }
      const head = await this.fetchHead(redirectUrl, request);
      if (!this.isLikelyDownloadTarget(head, redirectUrl)) {
        return {
          resolved: false,
          request: request
        };
      }
      const resolvedRequest = this.buildResolvedRequest(request, redirectUrl, head);
      hilog.info(
        DOWNLOAD_HTML_REDIRECT_DOMAIN,
        DOWNLOAD_HTML_REDIRECT_TAG,
        'resolved html redirect guid=%{public}s source=%{public}s target=%{public}s file=%{public}s total=%{public}d',
        request.guid,
        request.url,
        redirectUrl,
        resolvedRequest.suggestedFileName,
        resolvedRequest.totalBytes
      );
      return {
        resolved: true,
        request: resolvedRequest
      };
    } catch (error) {
      hilog.warn(
        DOWNLOAD_HTML_REDIRECT_DOMAIN,
        DOWNLOAD_HTML_REDIRECT_TAG,
        'resolve failed guid=%{public}s url=%{public}s error=%{public}s',
        request.guid,
        request.url,
        JSON.stringify(error)
      );
      return {
        resolved: false,
        request: request
      };
    }
  }

  extractRedirectUrl(html: string, baseUrl: string): string {
    const candidates: string[] = [
      this.extractLocationReplaceUrl(html),
      this.extractLocationHrefUrl(html),
      this.extractMetaRefreshUrl(html)
    ];
    for (let index = 0; index < candidates.length; index += 1) {
      const resolved = this.resolveUrl(candidates[index], baseUrl);
      if (this.isHttpUrl(resolved)) {
        return resolved;
      }
    }
    return '';
  }

  resolveFileNameFromContentDisposition(value: string): string {
    return this.fileNameService.resolveFileNameFromContentDisposition(value);
  }

  private shouldProbe(request: DownloadV2CapturedRequest): boolean {
    if (!this.isHttpUrl(request.url)) {
      return false;
    }
    const method = request.method.trim().toUpperCase();
    if (method.length > 0 && method !== 'GET') {
      return false;
    }
    if (request.totalBytes > HTML_REDIRECT_MAX_BYTES) {
      return false;
    }
    const mimeType = request.mimeType?.trim().toLowerCase() ?? '';
    return mimeType.length <= 0 || mimeType.includes('text/html') || mimeType.includes('application/xhtml');
  }

  private async fetchCandidateHtml(request: DownloadV2CapturedRequest): Promise<DownloadHtmlRedirectProbeResult> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(request.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: HTML_REDIRECT_TIMEOUT_MS,
        readTimeout: HTML_REDIRECT_TIMEOUT_MS,
        usingCache: false,
        header: this.buildProbeHeaders(request)
      });
      const body = typeof response.result === 'string' ? response.result : '';
      return {
        statusCode: response.responseCode,
        headers: this.normalizeHeaders(response.header),
        body: body.length > HTML_REDIRECT_MAX_BYTES ? '' : body
      };
    } finally {
      httpRequest.destroy();
    }
  }

  private async fetchHead(url: string, sourceRequest: DownloadV2CapturedRequest): Promise<DownloadHtmlRedirectHeadResult> {
    const httpRequest = http.createHttp();
    let resolved = false;
    let headers: Record<string, string> = {};
    const headersPromise = new Promise<DownloadHtmlRedirectHeadResult>((resolve, reject) => {
      const finish = (statusCode: number, rawHeaders: Record<string, string>): void => {
        if (resolved) {
          return;
        }
        resolved = true;
        headers = rawHeaders;
        const contentRange = this.getHeader(headers, 'content-range');
        resolve({
          statusCode: statusCode > 0 ? statusCode : this.inferStatusFromHeaders(headers),
          headers: headers,
          totalBytes: this.resolveTotalBytes(headers, contentRange),
          fileName: this.resolveFileName(headers, url),
          mimeType: this.getHeader(headers, 'content-type') ?? ''
        });
        try {
          httpRequest.destroy();
        } catch (_error) {
        }
      };
      httpRequest.on('headersReceive', (rawHeaders: Object) => {
        const nextHeaders = this.normalizeHeaders(rawHeaders);
        finish(this.resolveStatusCode(nextHeaders), nextHeaders);
      });
      httpRequest.on('dataReceive', () => {
        if (resolved) {
          return;
        }
        finish(this.inferStatusFromHeaders(headers), headers);
      });
      httpRequest.requestInStream(url, {
        method: http.RequestMethod.GET,
        connectTimeout: HTML_REDIRECT_TIMEOUT_MS,
        readTimeout: HTML_REDIRECT_TIMEOUT_MS,
        usingCache: false,
        header: this.buildRangeProbeHeaders(sourceRequest)
      }, (error: Error | undefined, code: number) => {
        if (resolved) {
          return;
        }
        if (error !== undefined && error !== null) {
          reject(error);
          return;
        }
        finish(code, headers);
      });
    });
    try {
      return await headersPromise;
    } finally {
      httpRequest.off('headersReceive');
      httpRequest.off('dataReceive');
      httpRequest.destroy();
    }
  }

  private isLikelyHtmlRedirect(probe: DownloadHtmlRedirectProbeResult): boolean {
    if (probe.statusCode < 200 || probe.statusCode >= 300 || probe.body.length <= 0) {
      return false;
    }
    const contentType = this.getHeader(probe.headers, 'content-type')?.toLowerCase() ?? '';
    if (contentType.length > 0 && !contentType.includes('text/html') && !contentType.includes('application/xhtml')) {
      return false;
    }
    return /location\s*\.\s*replace\s*\(/i.test(probe.body) ||
      /location\s*\.\s*href\s*=/i.test(probe.body) ||
      /http-equiv\s*=\s*['"]?refresh/i.test(probe.body);
  }

  private isLikelyDownloadTarget(head: DownloadHtmlRedirectHeadResult, url: string): boolean {
    if (head.statusCode !== 206) {
      return false;
    }
    if (head.totalBytes <= HTML_REDIRECT_MAX_BYTES) {
      return false;
    }
    const contentType = head.mimeType.toLowerCase();
    if (contentType.includes('text/html') || contentType.includes('application/xhtml')) {
      return false;
    }
    const disposition = this.getHeader(head.headers, 'content-disposition') ?? '';
    return disposition.length > 0 || this.resolveFileNameFromUrl(url).length > 0;
  }

  private buildResolvedRequest(
    request: DownloadV2CapturedRequest,
    url: string,
    head: DownloadHtmlRedirectHeadResult
  ): DownloadV2CapturedRequest {
    return {
      guid: request.guid,
      url: url,
      originalUrl: request.originalUrl,
      suggestedFileName: this.fileNameService.resolveFileName({
        suggestedFileName: head.fileName.length > 0 ? head.fileName : request.suggestedFileName,
        url: url,
        mimeType: head.mimeType.length > 0 ? head.mimeType : request.mimeType,
        contentDisposition: this.getHeader(head.headers, 'content-disposition') ?? request.contentDisposition
      }),
      sourceHost: this.resolveHost(url) || request.sourceHost,
      totalBytes: head.totalBytes > 0 ? head.totalBytes : request.totalBytes,
      mimeType: head.mimeType.length > 0 ? head.mimeType : request.mimeType,
      method: 'GET',
      userAgent: request.userAgent,
      referer: request.referer ?? request.url,
      contentDisposition: this.getHeader(head.headers, 'content-disposition') ?? request.contentDisposition,
      headers: this.stripContentHeaders(request.headers),
      sourcePageUrl: request.sourcePageUrl,
      boundary: request.boundary,
      platformSnapshot: undefined,
      createdAt: request.createdAt
    };
  }

  private buildProbeHeaders(request: DownloadV2CapturedRequest): Record<string, string> {
    const headers = this.stripContentHeaders(request.headers);
    if (!this.hasHeader(headers, 'Accept')) {
      headers['Accept'] = 'text/html,application/xhtml+xml,*/*;q=0.8';
    }
    if ((request.userAgent?.trim().length ?? 0) > 0 && !this.hasHeader(headers, 'User-Agent')) {
      headers['User-Agent'] = request.userAgent?.trim() ?? '';
    }
    if ((request.referer?.trim().length ?? 0) > 0 && !this.hasHeader(headers, 'Referer')) {
      headers['Referer'] = request.referer?.trim() ?? '';
    }
    return headers;
  }

  private buildRangeProbeHeaders(request: DownloadV2CapturedRequest): Record<string, string> {
    const headers = this.stripContentHeaders(request.headers);
    if (!this.hasHeader(headers, 'Accept')) {
      headers['Accept'] = '*/*';
    }
    if ((request.userAgent?.trim().length ?? 0) > 0 && !this.hasHeader(headers, 'User-Agent')) {
      headers['User-Agent'] = request.userAgent?.trim() ?? '';
    }
    if (!this.hasHeader(headers, 'Referer')) {
      headers['Referer'] = request.url;
    }
    headers['Range'] = 'bytes=0-0';
    return headers;
  }

  private stripContentHeaders(headers?: Record<string, string>): Record<string, string> {
    const nextHeaders: Record<string, string> = {};
    if (headers === undefined) {
      return nextHeaders;
    }
    Object.keys(headers).forEach((key: string) => {
      const normalizedKey = key.trim();
      const lowerKey = normalizedKey.toLowerCase();
      const value = headers[key]?.trim() ?? '';
      if (normalizedKey.length <= 0 || value.length <= 0) {
        return;
      }
      if (lowerKey === 'range' || lowerKey === 'if-range' || lowerKey === 'content-length') {
        return;
      }
      nextHeaders[normalizedKey] = value;
    });
    return nextHeaders;
  }

  private extractLocationReplaceUrl(html: string): string {
    const match = /location\s*\.\s*replace\s*\(\s*(['"])(.*?)\1\s*\)/i.exec(html);
    return match === null ? '' : this.decodeHtmlEntities(match[2]);
  }

  private extractLocationHrefUrl(html: string): string {
    const match = /location\s*\.\s*href\s*=\s*(['"])(.*?)\1/i.exec(html);
    return match === null ? '' : this.decodeHtmlEntities(match[2]);
  }

  private extractMetaRefreshUrl(html: string): string {
    const match = /http-equiv\s*=\s*['"]?refresh['"]?[^>]*content\s*=\s*(['"])(.*?)\1/i.exec(html);
    if (match === null) {
      return '';
    }
    const urlMatch = /url\s*=\s*(.+)$/i.exec(match[2]);
    return urlMatch === null ? '' : this.decodeHtmlEntities(urlMatch[1].trim());
  }

  private resolveUrl(candidate: string, baseUrl: string): string {
    const normalized = candidate.trim();
    if (normalized.length <= 0) {
      return '';
    }
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(normalized)) {
      return normalized;
    }
    if (normalized.startsWith('//')) {
      return `https:${normalized}`;
    }
    try {
      const parsedBase = urlUtils.URL.parseURL(baseUrl);
      const origin = `${parsedBase.protocol}//${parsedBase.hostname}${parsedBase.port.length > 0 ? `:${parsedBase.port}` : ''}`;
      if (normalized.startsWith('/')) {
        return `${origin}${normalized}`;
      }
      const path = parsedBase.pathname;
      const basePath = path.endsWith('/') ? path : path.substring(0, path.lastIndexOf('/') + 1);
      return this.normalizePathUrl(`${origin}${basePath}${normalized}`);
    } catch (_error) {
      return '';
    }
  }

  private resolveFileName(headers: Record<string, string>, url: string): string {
    const dispositionFileName = this.resolveFileNameFromContentDisposition(
      this.getHeader(headers, 'content-disposition') ?? ''
    );
    if (dispositionFileName.length > 0) {
      return dispositionFileName;
    }
    return this.fileNameService.resolveFileName({
      url: url,
      mimeType: this.getHeader(headers, 'content-type'),
      contentDisposition: this.getHeader(headers, 'content-disposition')
    });
  }

  private resolveFileNameFromUrl(url: string): string {
    return this.fileNameService.resolveFileNameFromUrl(url);
  }

  private resolveHost(url: string): string {
    try {
      return urlUtils.URL.parseURL(url).hostname;
    } catch (_error) {
      return '';
    }
  }

  private resolveTotalBytes(headers: Record<string, string>, contentRange?: string): number {
    const rangeTotal = this.resolveTotalBytesFromContentRange(contentRange ?? '');
    if (rangeTotal > 0) {
      return rangeTotal;
    }
    const contentLength = Number(this.getHeader(headers, 'content-length') ?? '');
    return Number.isFinite(contentLength) && contentLength > 0 ? Math.floor(contentLength) : 0;
  }

  private resolveTotalBytesFromContentRange(value: string): number {
    const match = /^bytes\s+\d+-\d+\/(\d+|\*)$/i.exec(value.trim());
    if (match === null || match[1] === '*') {
      return 0;
    }
    const total = Number(match[1]);
    return Number.isFinite(total) && total > 0 ? Math.floor(total) : 0;
  }

  private resolveStatusCode(headers: Record<string, string>): number {
    const statusLine = headers[':status'] ?? headers['status'] ?? headers['Status'] ?? '';
    const inlineStatus = Number(statusLine);
    if (Number.isFinite(inlineStatus) && inlineStatus > 0) {
      return Math.floor(inlineStatus);
    }
    const match = /\b(\d{3})\b/.exec(statusLine);
    if (match !== null) {
      return Number(match[1]);
    }
    return 0;
  }

  private inferStatusFromHeaders(headers: Record<string, string>): number {
    const explicitStatus = this.resolveStatusCode(headers);
    if (explicitStatus > 0) {
      return explicitStatus;
    }
    return (this.getHeader(headers, 'content-range') ?? '').length > 0 ? 206 : 200;
  }

  private normalizeHeaders(rawHeaders: Object): Record<string, string> {
    const normalized: Record<string, string> = {};
    const record = rawHeaders as Record<string, Object | string | number | boolean | Array<string> | undefined>;
    Object.keys(record).forEach((key: string) => {
      const value = record[key];
      if (value === undefined || value === null) {
        return;
      }
      if (Array.isArray(value)) {
        normalized[key] = value.join(', ');
        return;
      }
      normalized[key] = String(value);
    });
    return normalized;
  }

  private getHeader(headers: Record<string, string>, name: string): string | undefined {
    const target = name.trim().toLowerCase();
    const keys = Object.keys(headers);
    for (let index = 0; index < keys.length; index += 1) {
      if (keys[index].trim().toLowerCase() === target) {
        const value = headers[keys[index]];
        return value.trim().length > 0 ? value : undefined;
      }
    }
    return undefined;
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    const target = name.trim().toLowerCase();
    return Object.keys(headers).some((key: string) => key.trim().toLowerCase() === target);
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private decodeHtmlEntities(value: string): string {
    return value
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim();
  }

  private normalizePathUrl(rawUrl: string): string {
    const parts = rawUrl.split('/');
    const normalizedParts: string[] = [];
    parts.forEach((part: string) => {
      if (part === '..') {
        normalizedParts.pop();
        return;
      }
      if (part === '.') {
        return;
      }
      normalizedParts.push(part);
    });
    return normalizedParts.join('/');
  }
}
