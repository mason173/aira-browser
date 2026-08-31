export const TELEGRAM_WEB_NO_SERVICE_WORKER_PARAM: string = 'noServiceWorker';

interface ParsedTelegramUrl {
  scheme: string;
  host: string;
  path: string;
  query: string;
  hash: string;
}

export class TelegramWebCompatibilityService {
  resolveLoadUrl(url: string): string {
    const parsed = this.parseTelegramWebUrl(url);
    if (parsed === undefined) {
      return url;
    }
    const query = this.upsertQueryParam(parsed.query, TELEGRAM_WEB_NO_SERVICE_WORKER_PARAM, '1');
    return this.buildUrl(parsed, query);
  }

  resolveVisibleUrl(url: string): string {
    return url;
  }

  shouldRewriteMainFrameNavigation(url: string): boolean {
    return this.resolveLoadUrl(url) !== url.trim();
  }

  private parseTelegramWebUrl(url: string): ParsedTelegramUrl | undefined {
    const trimmed = url.trim();
    const match = /^(https?):\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?(#.*)?$/i.exec(trimmed);
    if (match === null) {
      return undefined;
    }
    const host = (match[2] ?? '').toLowerCase();
    if (!this.isTelegramWebHost(host)) {
      return undefined;
    }
    return {
      scheme: (match[1] ?? 'https').toLowerCase(),
      host: match[2] ?? '',
      path: this.resolveTelegramWebRuntimePath((match[3] ?? '').length > 0 ? (match[3] ?? '') : '/'),
      query: match[4] ?? '',
      hash: match[5] ?? ''
    };
  }

  private isTelegramWebHost(host: string): boolean {
    return host === 'web.telegram.org';
  }

  private resolveTelegramWebRuntimePath(path: string): string {
    if (path === '/k' || path === '/k/' || path.startsWith('/k/')) {
      return path;
    }
    return '/k/';
  }

  private buildUrl(parsed: ParsedTelegramUrl, query: string): string {
    const queryPart = query.length > 0 ? `?${query}` : '';
    return `${parsed.scheme}://${parsed.host}${parsed.path}${queryPart}${parsed.hash}`;
  }

  private upsertQueryParam(query: string, key: string, value: string): string {
    const parts = this.queryParts(query);
    let replaced = false;
    const result: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (this.queryPartKey(part).toLowerCase() === key.toLowerCase()) {
        if (!replaced) {
          result.push(`${key}=${value}`);
          replaced = true;
        }
      } else {
        result.push(part);
      }
    }
    if (!replaced) {
      result.push(`${key}=${value}`);
    }
    return result.join('&');
  }

  private queryParts(query: string): string[] {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      return [];
    }
    const rawParts = trimmed.split('&');
    const result: string[] = [];
    for (let i = 0; i < rawParts.length; i++) {
      if (rawParts[i].length > 0) {
        result.push(rawParts[i]);
      }
    }
    return result;
  }

  private queryPartKey(part: string): string {
    const equalsIndex = part.indexOf('=');
    return equalsIndex >= 0 ? part.substring(0, equalsIndex) : part;
  }
}
