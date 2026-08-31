import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import { util } from '@kit.ArkTS';

interface RawUserScriptNativeXmlHttpRequestPayload {
  id?: string;
  url?: string;
  method?: string;
  data?: string;
  bodyKind?: string;
  headers?: Record<string, string | null | undefined>;
  timeout?: number;
  responseType?: string;
  anonymous?: boolean;
  withCredentials?: boolean;
  credentials?: string;
  redirect?: string;
}

interface UserScriptNativeXmlHttpRequestPayload {
  id: string;
  url: string;
  method: string;
  data: string;
  bodyKind: string;
  headers: Record<string, string>;
  timeout: number;
  responseType: string;
  anonymous: boolean;
  withCredentials: boolean;
  credentials: string;
  redirect: string;
}

interface UserScriptNativeXmlHttpRequestEvent {
  id: string;
  type: string;
  finalUrl: string;
  readyState: number;
  status: number;
  statusText: string;
  responseHeaders: string;
  responseText: string;
  responseBase64: string;
  responseType: string;
}

interface UserScriptNativeXmlHttpRequestError {
  code?: number;
  message?: string;
}

const DEFAULT_TIMEOUT_MS: number = 12000;
const MAX_TIMEOUT_MS: number = 120000;
const MAX_RESPONSE_BYTES: number = 20 * 1024 * 1024;

export class UserScriptNativeXmlHttpRequestService {
  private activeRequests: Record<string, http.HttpRequest | undefined> = {};
  private base64Helper: util.Base64Helper = new util.Base64Helper();
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  request(payloadJson: string, controller: webview.WebviewController): void {
    const payload = this.parsePayload(payloadJson);
    if (payload.id.length === 0) {
      return;
    }
    if (!this.isHttpUrl(payload.url)) {
      this.dispatch(controller, this.buildFailureEvent(payload, 'error', 'unsupported-url'));
      return;
    }
    const request = http.createHttp();
    this.activeRequests[payload.id] = request;
    const headers = this.buildHeaders(payload);
    const extraData = this.resolveRequestBody(payload);
    request.request(payload.url, {
      method: this.toRequestMethod(payload.method),
      customMethod: this.resolveCustomMethod(payload.method),
      extraData: extraData,
      expectDataType: this.resolveExpectedDataType(payload.responseType),
      connectTimeout: payload.timeout,
      readTimeout: payload.timeout,
      maxLimit: MAX_RESPONSE_BYTES,
      usingCache: false,
      header: headers
    }).then((response: http.HttpResponse) => {
      if (this.activeRequests[payload.id] === undefined) {
        return;
      }
      const responseText = this.resolveResponseText(response.result);
      const responseBase64 = this.resolveResponseBase64(response.result);
      this.persistResponseCookies(payload.url, response);
      const responseHeaders = this.serializeResponseHeaders(response.header, response.cookies);
      this.dispatch(controller, {
        id: payload.id,
        type: 'load',
        finalUrl: this.resolveFinalUrl(response, payload.url),
        readyState: 4,
        status: response.responseCode,
        statusText: this.resolveStatusText(response),
        responseHeaders: responseHeaders,
        responseText: responseText,
        responseBase64: responseBase64,
        responseType: payload.responseType
      });
    }).catch((error: Error) => {
      if (this.activeRequests[payload.id] === undefined) {
        return;
      }
      const message = this.describeError(error);
      const eventType = this.resolveFailureEventType(error);
      this.dispatch(controller, this.buildFailureEvent(payload, eventType, `request-failed: ${message}`));
    }).finally(() => {
      this.release(payload.id, request);
    });
  }

  abort(requestId: string): void {
    const normalizedId = requestId.trim();
    const request = this.activeRequests[normalizedId];
    if (request === undefined) {
      return;
    }
    this.release(normalizedId, request);
  }

  dispatchFailure(
    controller: webview.WebviewController,
    requestId: string,
    url: string,
    responseType: string,
    statusText: string
  ): void {
    const payload: UserScriptNativeXmlHttpRequestPayload = {
      id: requestId.trim(),
      url: url.trim(),
      method: 'GET',
      data: '',
      bodyKind: 'none',
      headers: this.emptyHeaders(),
      timeout: DEFAULT_TIMEOUT_MS,
      responseType: responseType.trim(),
      anonymous: false,
      withCredentials: false,
      credentials: '',
      redirect: ''
    };
    this.dispatch(controller, this.buildFailureEvent(payload, 'error', statusText));
  }

  private parsePayload(payloadJson: string): UserScriptNativeXmlHttpRequestPayload {
    try {
      const raw = JSON.parse(payloadJson) as RawUserScriptNativeXmlHttpRequestPayload;
      const timeout = this.normalizeTimeout(raw.timeout);
      return {
        id: String(raw.id ?? '').trim(),
        url: String(raw.url ?? '').trim(),
        method: this.normalizeMethod(raw.method),
        data: raw.data === undefined || raw.data === null ? '' : String(raw.data),
        bodyKind: this.normalizeBodyKind(raw.bodyKind),
        headers: this.normalizeHeaders(raw.headers),
        timeout: timeout,
        responseType: String(raw.responseType ?? '').trim(),
        anonymous: raw.anonymous === true,
        withCredentials: raw.withCredentials === true,
        credentials: String(raw.credentials ?? '').trim().toLowerCase(),
        redirect: String(raw.redirect ?? '').trim().toLowerCase()
      };
    } catch (_error) {
      return {
        id: '',
        url: '',
        method: 'GET',
        data: '',
        bodyKind: 'none',
        headers: this.emptyHeaders(),
        timeout: DEFAULT_TIMEOUT_MS,
        responseType: '',
        anonymous: false,
        withCredentials: false,
        credentials: '',
        redirect: ''
      };
    }
  }

  private normalizeMethod(value: string | undefined): string {
    const method = String(value ?? 'GET').trim().toUpperCase();
    return method.length > 0 ? method : 'GET';
  }

  private normalizeTimeout(value: number | undefined): number {
    if (typeof value !== 'number' || value <= 0) {
      return DEFAULT_TIMEOUT_MS;
    }
    return Math.min(Math.max(Math.floor(value), 1000), MAX_TIMEOUT_MS);
  }

  private normalizeBodyKind(value: string | undefined): string {
    const normalized = String(value ?? '').trim().toLowerCase();
    if (normalized === 'base64' || normalized === 'text' || normalized === 'json') {
      return normalized;
    }
    return 'none';
  }

  private normalizeHeaders(
    headers: Record<string, string | null | undefined> | undefined
  ): Record<string, string> {
    const normalized = this.emptyHeaders();
    if (headers === undefined) {
      return normalized;
    }
    Object.keys(headers).forEach((name: string) => {
      const key = name.trim();
      const value = headers[name];
      if (key.length === 0 || value === null || value === undefined) {
        return;
      }
      const headerValue = String(value).trim();
      if (headerValue.length === 0) {
        return;
      }
      normalized[key] = headerValue;
    });
    return normalized;
  }

  private buildHeaders(payload: UserScriptNativeXmlHttpRequestPayload): Record<string, string> {
    const normalized = this.emptyHeaders();
    const headers = payload.headers;
    if (headers === undefined) {
      return normalized;
    }
    Object.keys(headers).forEach((name: string) => {
      const value = headers[name] ?? '';
      if (name.trim().length > 0 && value.trim().length > 0) {
        normalized[name.trim()] = value.trim();
      }
    });
    const cookie = this.resolveCookieHeader(payload);
    if (cookie.length > 0 && !this.hasHeader(normalized, 'Cookie')) {
      normalized['Cookie'] = cookie;
    }
    return normalized;
  }

  private resolveCookieHeader(payload: UserScriptNativeXmlHttpRequestPayload): string {
    if (payload.anonymous || payload.credentials === 'omit') {
      return '';
    }
    const normalizedUrl = payload.url.trim();
    if (normalizedUrl.length <= 0) {
      return '';
    }
    try {
      return webview.WebCookieManager.fetchCookieSync(normalizedUrl, false).trim();
    } catch (_error) {
      return '';
    }
  }

  private resolveRequestBody(payload: UserScriptNativeXmlHttpRequestPayload): string | ArrayBuffer | undefined {
    if (payload.data.length <= 0 || payload.bodyKind === 'none') {
      return undefined;
    }
    if (payload.bodyKind === 'base64') {
      try {
        const bytes = this.base64Helper.decodeSync(payload.data);
        return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      } catch (_error) {
        return new ArrayBuffer(0);
      }
    }
    return payload.data;
  }

  private emptyHeaders(): Record<string, string> {
    return JSON.parse('{}') as Record<string, string>;
  }

  private toRequestMethod(method: string): http.RequestMethod {
    if (method === 'POST') {
      return http.RequestMethod.POST;
    }
    if (method === 'PUT') {
      return http.RequestMethod.PUT;
    }
    if (method === 'DELETE') {
      return http.RequestMethod.DELETE;
    }
    if (method === 'HEAD') {
      return http.RequestMethod.HEAD;
    }
    if (method === 'OPTIONS') {
      return http.RequestMethod.OPTIONS;
    }
    if (method === 'TRACE') {
      return http.RequestMethod.TRACE;
    }
    if (method === 'CONNECT') {
      return http.RequestMethod.CONNECT;
    }
    return http.RequestMethod.GET;
  }

  private resolveCustomMethod(method: string): string | undefined {
    const normalized = method.trim().toUpperCase();
    if (normalized === 'GET' || normalized === 'POST' || normalized === 'PUT' || normalized === 'DELETE' ||
      normalized === 'HEAD' || normalized === 'OPTIONS' || normalized === 'TRACE' || normalized === 'CONNECT') {
      return undefined;
    }
    return normalized.length > 0 ? normalized : undefined;
  }

  private resolveExpectedDataType(responseType: string): http.HttpDataType {
    const normalized = responseType.trim().toLowerCase();
    if (normalized === 'arraybuffer' || normalized === 'blob' || normalized === 'base64') {
      return http.HttpDataType.ARRAY_BUFFER;
    }
    return http.HttpDataType.STRING;
  }

  private resolveResponseText(result: Object | string | ArrayBuffer | undefined): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      try {
        return this.textDecoder.decodeToString(new Uint8Array(result));
      } catch (_error) {
        return '';
      }
    }
    return '';
  }

  private resolveResponseBase64(result: Object | string | ArrayBuffer | undefined): string {
    if (result instanceof ArrayBuffer) {
      return this.base64Helper.encodeToStringSync(new Uint8Array(result));
    }
    return '';
  }

  private resolveFinalUrl(response: http.HttpResponse, fallbackUrl: string): string {
    const responseRecord = response as Object as Record<string, Object | string | undefined>;
    const candidates: string[] = [
      String(responseRecord['finalUrl'] ?? ''),
      String(responseRecord['responseUrl'] ?? ''),
      String(responseRecord['requestUrl'] ?? ''),
      fallbackUrl
    ];
    const match = candidates.find((candidate: string) => candidate.trim().length > 0);
    return match?.trim() ?? fallbackUrl;
  }

  private serializeResponseHeaders(rawHeaders: Object | undefined, cookies: string | undefined): string {
    if (rawHeaders === undefined || rawHeaders === null) {
      return this.serializeCookieHeaders(cookies);
    }
    const record = rawHeaders as Record<string, Object | string | number | boolean | undefined>;
    const lines: string[] = [];
    Object.keys(record).forEach((name: string) => {
      const value = record[name];
      if (name.trim().length === 0 || value === undefined || value === null) {
        return;
      }
      if (Array.isArray(value)) {
        value.forEach((item: Object) => {
          lines.push(`${name}: ${String(item)}`);
        });
        return;
      }
      lines.push(`${name}: ${String(value)}`);
    });
    this.appendCookieHeaderLines(lines, cookies);
    return lines.join('\r\n');
  }

  private serializeCookieHeaders(cookies: string | undefined): string {
    const lines: string[] = [];
    this.appendCookieHeaderLines(lines, cookies);
    return lines.join('\r\n');
  }

  private appendCookieHeaderLines(lines: string[], cookies: string | undefined): void {
    const normalizedCookies = String(cookies ?? '').trim();
    if (normalizedCookies.length <= 0) {
      return;
    }
    normalizedCookies.split(/\r?\n/).forEach((line: string) => {
      const cookie = line.trim();
      if (cookie.length > 0) {
        lines.push(`Set-Cookie: ${cookie}`);
      }
    });
  }

  private persistResponseCookies(url: string, response: http.HttpResponse): void {
    const cookies = String(response.cookies ?? '').trim();
    if (cookies.length <= 0) {
      return;
    }
    cookies.split(/\r?\n/).forEach((line: string) => {
      const cookie = line.trim();
      if (cookie.length <= 0) {
        return;
      }
      try {
        webview.WebCookieManager.configCookieSync(url, cookie, false, true);
      } catch (_error) {
      }
    });
    try {
      webview.WebCookieManager.saveCookieSync();
    } catch (_error) {
    }
  }

  private hasHeader(headers: Record<string, string>, name: string): boolean {
    const target = name.trim().toLowerCase();
    return Object.keys(headers).some((key: string) => key.trim().toLowerCase() === target);
  }

  private isHttpUrl(url: string): boolean {
    const normalized = url.trim().toLowerCase();
    return normalized.startsWith('http://') || normalized.startsWith('https://');
  }

  private buildFailureEvent(
    payload: UserScriptNativeXmlHttpRequestPayload,
    type: string,
    statusText: string
  ): UserScriptNativeXmlHttpRequestEvent {
    return {
      id: String(payload.id ?? '').trim(),
      type: type,
      finalUrl: String(payload.url ?? '').trim(),
      readyState: 4,
      status: 0,
      statusText: statusText,
      responseHeaders: '',
      responseText: '',
      responseBase64: '',
      responseType: String(payload.responseType ?? '').trim()
    };
  }

  private resolveStatusText(response: http.HttpResponse): string {
    const responseRecord = response as Object as Record<string, Object | string | number | undefined>;
    const candidates: string[] = [
      String(responseRecord['statusText'] ?? ''),
      String(responseRecord['statusMessage'] ?? ''),
      String(responseRecord['responseMessage'] ?? '')
    ];
    const match = candidates.find((candidate: string) => candidate.trim().length > 0);
    return match?.trim() ?? String(response.responseCode);
  }

  private describeError(error: Error | undefined): string {
    if (error === undefined || error === null) {
      return 'unknown';
    }
    const message = String(error.message ?? '').trim();
    if (message.length > 0) {
      return message;
    }
    return String(error);
  }

  private resolveFailureEventType(error: Error | undefined): string {
    const requestError = error as UserScriptNativeXmlHttpRequestError | undefined;
    return requestError?.code === 2300028 ? 'timeout' : 'error';
  }

  private dispatch(controller: webview.WebviewController, event: UserScriptNativeXmlHttpRequestEvent): void {
    const eventLiteral = JSON.stringify(event);
    this.runJavaScriptSafely(controller, `
;(function airaDispatchNativeUserScriptRequest() {
  try {
    if (typeof window.__airaUserScriptNativeRequestDispatch === 'function') {
      window.__airaUserScriptNativeRequestDispatch(${eventLiteral});
    }
  } catch (error) {
    console.error('[AiraUserScript][native-xhr-dispatch] ' + (error && (error.stack || error.message || String(error))));
  }
})();
`);
  }

  private runJavaScriptSafely(controller: webview.WebviewController, script: string): void {
    try {
      controller.runJavaScript(script).catch((_error: Error): void => {
        // The Web component may detach while an HTTP request is completing.
      });
    } catch (_error) {
      // ArkWeb can reject synchronously before the controller is associated.
    }
  }

  private release(id: string, request: http.HttpRequest): void {
    this.activeRequests[id] = undefined;
    try {
      request.destroy();
    } catch (_error) {
    }
  }
}
