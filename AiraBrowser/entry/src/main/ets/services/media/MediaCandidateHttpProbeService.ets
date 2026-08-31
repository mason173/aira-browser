import { http } from '@kit.NetworkKit';
import { WebCookieHeaderService } from '../web/WebCookieHeaderService';

const DEFAULT_PROBE_TIMEOUT_MS: number = 5000;
const DEFAULT_RANGE_START: number = 0;
const DEFAULT_RANGE_END: number = 511;
const DEFAULT_MAX_LIMIT_BYTES: number = 64 * 1024;

export interface MediaHttpProbeInput {
  url: string;
  referer?: string;
  userAgent?: string;
  originUrl?: string;
  requestHeaders?: Record<string, string>;
  rangeStart?: number;
  rangeEnd?: number;
  useRange?: boolean;
  timeoutMs?: number;
  accept?: string;
}

export interface MediaHttpProbeResult {
  ok: boolean;
  url: string;
  finalUrl: string;
  statusCode: number;
  headers: Record<string, string>;
  contentType: string;
  contentLength: number;
  bytes: ArrayBuffer;
  text: string;
  textPrefix: string;
  errorMessage: string;
}

export class MediaCandidateHttpProbeService {
  private cookieHeaderService: WebCookieHeaderService;

  constructor(cookieHeaderService: WebCookieHeaderService = new WebCookieHeaderService()) {
    this.cookieHeaderService = cookieHeaderService;
  }

  async probeBytes(input: MediaHttpProbeInput): Promise<MediaHttpProbeResult> {
    const request = http.createHttp();
    const url = input.url.trim();
    try {
      const headers = this.buildHeaders(input);
      const rangeStart = Math.max(0, Math.floor(input.rangeStart ?? DEFAULT_RANGE_START));
      const rangeEnd = Math.max(rangeStart, Math.floor(input.rangeEnd ?? DEFAULT_RANGE_END));
      if (input.useRange !== false) {
        headers['Range'] = 'bytes=' + rangeStart.toString() + '-' + rangeEnd.toString();
      }
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: this.resolveTimeout(input.timeoutMs),
        readTimeout: this.resolveTimeout(input.timeoutMs),
        usingCache: true,
        maxLimit: DEFAULT_MAX_LIMIT_BYTES,
        header: headers
      });
      const bytes = response.result instanceof ArrayBuffer ? response.result : new ArrayBuffer(0);
      const normalizedHeaders = this.normalizeHeaders(response.header);
      return this.buildResult(url, response.responseCode, normalizedHeaders, bytes, '', '');
    } catch (error) {
      return this.fail(url, this.stringifyError(error as Error));
    } finally {
      request.destroy();
    }
  }

  async fetchText(input: MediaHttpProbeInput, maxBytes: number): Promise<MediaHttpProbeResult> {
    const request = http.createHttp();
    const url = input.url.trim();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: this.resolveTimeout(input.timeoutMs),
        readTimeout: this.resolveTimeout(input.timeoutMs),
        usingCache: true,
        maxLimit: Math.max(1024, Math.floor(maxBytes)),
        header: this.buildHeaders(input)
      });
      const text = typeof response.result === 'string' ? response.result : '';
      const normalizedHeaders = this.normalizeHeaders(response.header);
      return this.buildResult(url, response.responseCode, normalizedHeaders, new ArrayBuffer(0), text, '');
    } catch (error) {
      return this.fail(url, this.stringifyError(error as Error));
    } finally {
      request.destroy();
    }
  }

  private buildHeaders(input: MediaHttpProbeInput): Record<string, string> {
    const headers: Record<string, string> = {};
    const sourceHeaders = input.requestHeaders ?? {};
    const keys = Object.keys(sourceHeaders);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      const value = sourceHeaders[keys[i]]?.trim() ?? '';
      if (key.length > 0 && value.length > 0 && key.toLowerCase() !== 'set-cookie') {
        headers[key] = value;
      }
    }
    headers['Accept'] = input.accept ?? 'video/*,audio/*,application/vnd.apple.mpegurl,application/x-mpegURL,' +
      'application/dash+xml,*/*;q=0.8';
    if (!this.hasHeader(headers, 'User-Agent')) {
      headers['User-Agent'] = input.userAgent?.trim() || 'AiraBrowser/1.0';
    }
    if (!this.hasHeader(headers, 'Referer') && input.referer !== undefined && input.referer.trim().length > 0) {
      headers['Referer'] = input.referer.trim();
    }
    if (!this.hasHeader(headers, 'Origin') && input.originUrl !== undefined && input.originUrl.trim().length > 0 &&
      !this.sameOrigin(input.url, input.originUrl)) {
      headers['Origin'] = input.originUrl.trim();
    }
    this.putIfAbsent(headers, 'Sec-Fetch-Dest', 'video');
    this.putIfAbsent(headers, 'Sec-Fetch-Mode', 'no-cors');
    this.putIfAbsent(headers, 'Sec-Fetch-Site', this.resolveFetchSite(input.url, input.referer ?? input.originUrl));
    this.cookieHeaderService.putCookieHeaderIfAbsent(headers, input.url);
    return headers;
  }

  private putIfAbsent(headers: Record<string, string>, name: string, value: string): void {
    if (!this.hasHeader(headers, name) && value.trim().length > 0) {
      headers[name] = value.trim();
    }
  }

  private resolveFetchSite(url: string, pageUrl: string | undefined): string {
    const page = pageUrl?.trim() ?? '';
    if (page.length <= 0 || !this.isHttpUrl(page)) {
      return 'same-origin';
    }
    if (this.sameOrigin(url, page)) {
      return 'same-origin';
    }
    if (this.sameSite(url, page)) {
      return 'same-site';
    }
    return 'cross-site';
  }

  private sameOrigin(left: string, right: string): boolean {
    const leftOrigin = this.extractOrigin(left);
    const rightOrigin = this.extractOrigin(right);
    return leftOrigin.length > 0 && leftOrigin === rightOrigin;
  }

  private sameSite(left: string, right: string): boolean {
    const leftHost = this.extractHost(left);
    const rightHost = this.extractHost(right);
    if (leftHost.length <= 0 || rightHost.length <= 0) {
      return false;
    }
    return this.registrableHost(leftHost) === this.registrableHost(rightHost);
  }

  private registrableHost(host: string): string {
    const parts = host.toLowerCase().split('.').filter((part: string): boolean => part.length > 0);
    if (parts.length <= 2) {
      return parts.join('.');
    }
    return parts.slice(parts.length - 2).join('.');
  }

  private extractOrigin(url: string): string {
    const match = /^https?:\/\/[^/?#]+/i.exec(url.trim());
    return match !== null ? match[0].toLowerCase() : '';
  }

  private extractHost(url: string): string {
    const match = /^https?:\/\/([^/?#]+)/i.exec(url.trim());
    return match !== null ? match[1].toLowerCase() : '';
  }

  private buildResult(
    url: string,
    statusCode: number,
    headers: Record<string, string>,
    bytes: ArrayBuffer,
    text: string,
    errorMessage: string
  ): MediaHttpProbeResult {
    const contentType = this.headerValue(headers, 'content-type');
    const contentLength = this.resolveContentLength(headers);
    const textPrefix = text.length > 0 ? text.substring(0, Math.min(text.length, 512)) : this.arrayBufferPrefix(bytes);
    return {
      ok: statusCode >= 200 && statusCode < 300,
      url: url,
      finalUrl: url,
      statusCode: statusCode,
      headers: headers,
      contentType: contentType,
      contentLength: contentLength,
      bytes: bytes,
      text: text,
      textPrefix: textPrefix,
      errorMessage: errorMessage
    };
  }

  private fail(url: string, errorMessage: string): MediaHttpProbeResult {
    return {
      ok: false,
      url: url,
      finalUrl: url,
      statusCode: 0,
      headers: {},
      contentType: '',
      contentLength: 0,
      bytes: new ArrayBuffer(0),
      text: '',
      textPrefix: '',
      errorMessage: errorMessage
    };
  }

  private normalizeHeaders(rawHeaders: Object | undefined): Record<string, string> {
    const headers: Record<string, string> = {};
    if (rawHeaders === undefined || rawHeaders === null) {
      return headers;
    }
    const source = rawHeaders as Record<string, Object>;
    const keys = Object.keys(source);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i].trim();
      if (key.length <= 0) {
        continue;
      }
      const value = source[keys[i]];
      if (value !== undefined && value !== null) {
        headers[key] = String(value);
      }
    }
    return headers;
  }

  private headerValue(headers: Record<string, string>, name: string): string {
    const target = name.trim().toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].trim().toLowerCase() === target) {
        return headers[keys[i]].trim();
      }
    }
    return '';
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    return this.headerValue(headers, name).length > 0;
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  private parseContentLength(value: string): number {
    const parsed = Math.floor(Number(value.trim()));
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  private resolveContentLength(headers: Record<string, string>): number {
    const contentRange = this.headerValue(headers, 'content-range');
    const rangeMatch = /^bytes\s+\d+-\d+\/(\d+|\*)$/i.exec(contentRange.trim());
    if (rangeMatch !== null && rangeMatch[1] !== '*') {
      const rangeTotal = this.parseContentLength(rangeMatch[1]);
      if (rangeTotal > 0) {
        return rangeTotal;
      }
    }
    return this.parseContentLength(this.headerValue(headers, 'content-length'));
  }

  private resolveTimeout(value: number | undefined): number {
    const timeout = Math.floor(value ?? DEFAULT_PROBE_TIMEOUT_MS);
    return timeout > 0 ? timeout : DEFAULT_PROBE_TIMEOUT_MS;
  }

  private arrayBufferPrefix(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    const limit = Math.min(bytes.length, 512);
    let result = '';
    for (let i = 0; i < limit; i++) {
      result += String.fromCharCode(bytes[i]);
    }
    return result;
  }

  private stringifyError(error: Error): string {
    const message = error.message?.trim() ?? '';
    return message.length > 0 ? message : 'request_failed';
  }
}
