import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';
import {
  BrowserDataBoundaryInput,
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import { WebCookieHeaderService } from '../web/WebCookieHeaderService';

const CSP_PROXY_TIMEOUT_MS: number = 15000;
const CSP_PROXY_MAX_BYTES: number = 20 * 1024 * 1024;
const CSP_FALLBACK_TTL_MS: number = 30000;
const MAX_REDIRECT_DATA_URL_BYTES: number = 512 * 1024;

export interface AdBlockCspRequestIdentity {
  tabId: string;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  url: string;
}

export interface AdBlockCspResponseInput extends AdBlockCspRequestIdentity {
  requestHeaders: Array<Header>;
  directives: string[];
}

export class AdBlockResponseFactoryService {
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private cookieHeaderService: WebCookieHeaderService = new WebCookieHeaderService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private cspFallbackUntilByRequestKey: Map<string, number> = new Map<string, number>();

  buildEmptyResponse(url: string): WebResourceResponse {
    return this.buildResponse('', this.inferMimeType(url), 204, 'No Content', 'blocked');
  }

  buildUrlTransformRedirectResponse(url: string): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseHeader([
      { headerKey: 'Location', headerValue: url },
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'X-Aira-AdBlock', headerValue: 'url-transform' }
    ]);
    response.setResponseData('');
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType('text/plain');
    response.setResponseCode(302);
    response.setReasonMessage('Found');
    return response;
  }

  buildRustRedirectResponse(dataUrl: string): WebResourceResponse {
    const normalized = dataUrl.trim();
    if (normalized.length <= 0 || normalized.length > MAX_REDIRECT_DATA_URL_BYTES ||
      !normalized.toLowerCase().startsWith('data:')) {
      throw new Error('Invalid Rust redirect data URL.');
    }
    const separatorIndex = normalized.indexOf(',');
    if (separatorIndex <= 'data:'.length) {
      throw new Error('Missing Rust redirect data separator.');
    }
    const metadata = normalized.substring('data:'.length, separatorIndex);
    const metadataParts = metadata.split(';');
    const mimeType = (metadataParts.shift() ?? '').trim().toLowerCase();
    if (!this.isSafeRedirectMimeType(mimeType) || metadataParts.length !== 1 ||
      metadataParts[0].trim().toLowerCase() !== 'base64') {
      throw new Error('Unsupported Rust redirect data metadata.');
    }
    const payload = normalized.substring(separatorIndex + 1);
    const bytes = this.base64Helper.decodeSync(payload);
    const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    const response = new WebResourceResponse();
    response.setResponseHeader([
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'X-Aira-AdBlock', headerValue: 'rust-redirect' }
    ]);
    response.setResponseData(data);
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType(mimeType);
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    return response;
  }

  buildCspResponse(input: AdBlockCspResponseInput): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseData('');
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType('text/html');
    response.setResponseCode(200);
    response.setReasonMessage('OK');
    response.setResponseIsReady(false);
    this.fulfillCspResponse(response, input);
    return response;
  }

  consumeCspNativeFallback(input: AdBlockCspRequestIdentity): boolean {
    const now = Date.now();
    this.clearExpiredCspFallbacks(now);
    const key = this.buildCspFallbackKey(input);
    const until = this.cspFallbackUntilByRequestKey.get(key) ?? 0;
    this.cspFallbackUntilByRequestKey.delete(key);
    return until >= now;
  }

  private async fulfillCspResponse(
    target: WebResourceResponse,
    input: AdBlockCspResponseInput
  ): Promise<void> {
    const request = http.createHttp();
    try {
      const boundary: BrowserDataBoundaryInput = {
        profileId: input.profileId,
        privacyMode: input.privacyMode,
        dataScope: input.dataScope
      };
      const incognito = this.profileBoundaryService.resolveWebIncognitoMode(boundary);
      const headers = this.buildReplayRequestHeaders(input.url, input.requestHeaders, incognito);
      const response = await request.request(input.url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: CSP_PROXY_TIMEOUT_MS,
        readTimeout: CSP_PROXY_TIMEOUT_MS,
        maxLimit: CSP_PROXY_MAX_BYTES,
        usingCache: true,
        header: headers
      });
      this.persistResponseCookies(input.url, response, incognito);
      const contentType = this.resolveHeaderValue(response.header, 'content-type');
      const charset = this.resolveCharset(contentType);
      const data = response.result instanceof ArrayBuffer ? response.result : String(response.result ?? '');
      target.setResponseData(data);
      target.setResponseHeader(this.buildCspResponseHeaders(response.header, input.directives));
      target.setResponseEncoding(charset);
      target.setResponseMimeType(this.resolveMimeType(contentType, input.url));
      target.setResponseCode(Number(response.responseCode));
      target.setReasonMessage(this.resolveReasonMessage(Number(response.responseCode)));
    } catch (_error) {
      const now = Date.now();
      this.clearExpiredCspFallbacks(now);
      this.cspFallbackUntilByRequestKey.set(this.buildCspFallbackKey(input), now + CSP_FALLBACK_TTL_MS);
      target.setResponseData('');
      target.setResponseHeader([
        { headerKey: 'Location', headerValue: input.url },
        { headerKey: 'Cache-Control', headerValue: 'no-store' },
        { headerKey: 'X-Aira-AdBlock', headerValue: 'csp-native-fallback' }
      ]);
      target.setResponseEncoding('utf-8');
      target.setResponseMimeType('text/html');
      target.setResponseCode(302);
      target.setReasonMessage('Found');
    } finally {
      target.setResponseIsReady(true);
      request.destroy();
    }
  }

  private buildResponse(
    data: string,
    mimeType: string,
    code: number,
    reason: string,
    action: string
  ): WebResourceResponse {
    const response = new WebResourceResponse();
    response.setResponseHeader([
      { headerKey: 'Cache-Control', headerValue: 'no-store' },
      { headerKey: 'X-Aira-AdBlock', headerValue: action }
    ]);
    response.setResponseData(data);
    response.setResponseEncoding('utf-8');
    response.setResponseMimeType(mimeType);
    response.setResponseCode(code);
    response.setReasonMessage(reason);
    return response;
  }

  private buildReplayRequestHeaders(
    url: string,
    source: Array<Header>,
    incognito: boolean
  ): Record<string, string> {
    const headers: Record<string, string> = {};
    source.forEach((item: Header) => {
      const name = String(item.headerKey ?? '').trim();
      const value = String(item.headerValue ?? '').trim();
      const lower = name.toLowerCase();
      if (name.length <= 0 || value.length <= 0 || lower === 'host' || lower === 'content-length' ||
        lower === 'connection' || lower === 'accept-encoding') {
        return;
      }
      headers[name] = value;
    });
    this.cookieHeaderService.putCookieHeaderIfAbsent(headers, url, incognito);
    return headers;
  }

  private buildCspResponseHeaders(
    rawHeaders: Object,
    directives: string[]
  ): Array<Header> {
    const result: Array<Header> = [];
    const headers = rawHeaders as Record<string, Object | string | number | boolean | undefined>;
    Object.keys(headers).forEach((name: string) => {
      const lower = name.trim().toLowerCase();
      if (lower.length <= 0 || lower === 'set-cookie' || lower === 'content-length' ||
        lower === 'content-encoding' || lower === 'transfer-encoding' || lower === 'connection') {
        return;
      }
      const value = headers[name];
      if (Array.isArray(value)) {
        value.forEach((item: Object) => {
          result.push({ headerKey: name, headerValue: String(item) });
        });
      } else if (value !== undefined && value !== null) {
        result.push({ headerKey: name, headerValue: String(value) });
      }
    });
    directives.forEach((directive: string) => {
      if (directive.trim().length > 0) {
        result.push({ headerKey: 'Content-Security-Policy', headerValue: directive.trim() });
      }
    });
    result.push({ headerKey: 'X-Aira-AdBlock', headerValue: 'csp' });
    return result;
  }

  private persistResponseCookies(url: string, response: http.HttpResponse, incognito: boolean): void {
    const cookies = String(response.cookies ?? '').trim();
    if (cookies.length <= 0) {
      return;
    }
    cookies.split(/\r?\n/).forEach((line: string) => {
      const cookie = line.trim();
      if (cookie.length <= 0) {
        return;
      }
      try { webview.WebCookieManager.configCookieSync(url, cookie, incognito, true); } catch (_error) {}
    });
    if (!incognito) {
      try { webview.WebCookieManager.saveCookieSync(); } catch (_error) {}
    }
  }

  private buildCspFallbackKey(input: AdBlockCspRequestIdentity): string {
    return [
      input.tabId.trim(),
      input.profileId,
      input.privacyMode,
      input.dataScope,
      input.url.trim()
    ].join('\u0001');
  }

  private clearExpiredCspFallbacks(now: number): void {
    this.cspFallbackUntilByRequestKey.forEach((until: number, key: string) => {
      if (until < now) {
        this.cspFallbackUntilByRequestKey.delete(key);
      }
    });
  }

  private resolveHeaderValue(rawHeaders: Object, name: string): string {
    const target = name.trim().toLowerCase();
    const headers = rawHeaders as Record<string, Object | string | number | boolean | undefined>;
    const key = Object.keys(headers).find((item: string) => item.trim().toLowerCase() === target);
    if (key === undefined) {
      return '';
    }
    const value = headers[key];
    if (Array.isArray(value)) {
      return value.length > 0 ? String(value[0]) : '';
    }
    return value === undefined || value === null ? '' : String(value);
  }

  private resolveMimeType(contentType: string, url: string): string {
    const separator = contentType.indexOf(';');
    const mime = (separator >= 0 ? contentType.substring(0, separator) : contentType).trim();
    return mime.length > 0 ? mime : this.inferMimeType(url);
  }

  private resolveCharset(contentType: string): string {
    const match = contentType.match(/charset\s*=\s*["']?([^;"'\s]+)/iu);
    return match?.[1]?.trim() || 'utf-8';
  }

  private resolveReasonMessage(code: number): string {
    if (code === 200) { return 'OK'; }
    if (code === 204) { return 'No Content'; }
    if (code === 301) { return 'Moved Permanently'; }
    if (code === 302) { return 'Found'; }
    if (code === 304) { return 'Not Modified'; }
    if (code === 307) { return 'Temporary Redirect'; }
    if (code === 308) { return 'Permanent Redirect'; }
    if (code === 404) { return 'Not Found'; }
    return code >= 200 && code < 400 ? 'OK' : 'Error';
  }

  private isSafeRedirectMimeType(value: string): boolean {
    return value === 'text/css' || value === 'image/gif' || value === 'text/html' ||
      value === 'application/javascript' || value === 'application/json' || value === 'audio/mp3' ||
      value === 'video/mp4' || value === 'image/png' || value === 'text/plain' || value === 'text/xml' ||
      value === 'application/octet-stream';
  }

  private inferMimeType(url: string): string {
    const normalizedUrl = url.toLowerCase();
    if (normalizedUrl.endsWith('.js') || normalizedUrl.includes('.js?')) {
      return 'application/javascript';
    }
    if (normalizedUrl.endsWith('.css') || normalizedUrl.includes('.css?')) {
      return 'text/css';
    }
    if (normalizedUrl.endsWith('.svg') || normalizedUrl.includes('.svg?')) {
      return 'image/svg+xml';
    }
    if (normalizedUrl.endsWith('.json') || normalizedUrl.includes('.json?')) {
      return 'application/json';
    }
    if (normalizedUrl.endsWith('.html') || normalizedUrl.includes('.html?')) {
      return 'text/html';
    }
    if (normalizedUrl.endsWith('.png') || normalizedUrl.endsWith('.jpg') || normalizedUrl.endsWith('.jpeg') ||
      normalizedUrl.endsWith('.gif') || normalizedUrl.endsWith('.webp') || normalizedUrl.includes('.png?') ||
      normalizedUrl.includes('.jpg?') || normalizedUrl.includes('.jpeg?') || normalizedUrl.includes('.gif?') ||
      normalizedUrl.includes('.webp?')) {
      return 'image/png';
    }
    return 'text/plain';
  }
}
