import { webview } from '@kit.ArkWeb';

export class WebCookieHeaderService {
  putCookieHeaderIfAbsent(headers: Record<string, string>, url: string, incognito: boolean = false): boolean {
    if (this.hasHeader(headers, 'Cookie')) {
      return false;
    }
    const cookie = this.resolveCookieHeader(url, incognito);
    if (cookie.length <= 0) {
      return false;
    }
    headers['Cookie'] = cookie;
    return true;
  }

  hasCookieHeaderOrResolvable(
    headers: Record<string, string> | undefined,
    url: string,
    incognito: boolean = false
  ): boolean {
    if (this.hasHeader(headers, 'Cookie')) {
      return true;
    }
    return this.resolveCookieHeader(url, incognito).length > 0;
  }

  resolveCookieHeader(url: string, incognito: boolean = false): string {
    const normalizedUrl = url.trim();
    if (!this.isHttpUrl(normalizedUrl)) {
      return '';
    }
    try {
      return webview.WebCookieManager.fetchCookieSync(normalizedUrl, incognito).trim();
    } catch (_error) {
      return '';
    }
  }

  private hasHeader(headers: Record<string, string> | undefined, name: string): boolean {
    if (headers === undefined) {
      return false;
    }
    const target = name.trim().toLowerCase();
    const keys = Object.keys(headers);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].trim().toLowerCase() === target && (headers[keys[i]]?.trim() ?? '').length > 0) {
        return true;
      }
    }
    return false;
  }

  private isHttpUrl(url: string): boolean {
    const lower = url.trim().toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}
