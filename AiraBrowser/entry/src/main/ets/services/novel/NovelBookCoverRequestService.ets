import { http } from '@kit.NetworkKit';
import urlUtils from '@ohos.url';
import { NovelSiteRule } from '../../features/novel/NovelSiteRules';
import { NovelRuleCatalog, sharedNovelRuleCatalog } from './NovelRuleCatalog';

const COVER_REQUEST_TIMEOUT_MS: number = 8000;
const COVER_MAX_BYTES: number = 8 * 1024 * 1024;

export class NovelBookCoverRequestService {
  private ruleCatalog: NovelRuleCatalog;

  constructor(ruleCatalog: NovelRuleCatalog = sharedNovelRuleCatalog) {
    this.ruleCatalog = ruleCatalog;
  }

  async downloadCandidate(url: string, refererUrl: string): Promise<ArrayBuffer> {
    const normalizedUrl: string = url.trim();
    if (!this.isRemoteImageUrl(normalizedUrl)) {
      throw new Error('novel-cover-url');
    }
    const request = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Accept': 'image/avif,image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.4',
        'User-Agent': 'Mozilla/5.0 (Mobile; HarmonyOS) AppleWebKit/537.36 Safari/537.36 AiraBrowser/1.0'
      };
      const safeReferer: string = this.resolveSafeReferer(refererUrl);
      if (safeReferer.length > 0) {
        headers['Referer'] = safeReferer;
      }
      const response = await request.request(normalizedUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: COVER_REQUEST_TIMEOUT_MS,
        readTimeout: COVER_REQUEST_TIMEOUT_MS,
        usingCache: false,
        maxLimit: COVER_MAX_BYTES,
        header: headers
      });
      if (response.responseCode < 200 || response.responseCode >= 300 ||
        !(response.result instanceof ArrayBuffer)) {
        throw new Error(`novel-cover-http-${response.responseCode}`);
      }
      if (response.result.byteLength <= 0 || response.result.byteLength > COVER_MAX_BYTES) {
        throw new Error(`novel-cover-size-${response.result.byteLength}`);
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  private isRemoteImageUrl(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  resolveCoverCandidates(coverUrl: string, refererUrl: string): string[] {
    const normalizedCoverUrl: string = coverUrl.trim();
    if (!this.isRemoteImageUrl(normalizedCoverUrl)) {
      return [];
    }
    const candidates: string[] = [normalizedCoverUrl];
    try {
      const cover = urlUtils.URL.parseURL(normalizedCoverUrl);
      const referer = urlUtils.URL.parseURL(refererUrl.trim());
      const coverHost: string = cover.hostname.toLowerCase();
      const refererHost: string = referer.hostname.toLowerCase();
      if (coverHost === refererHost || !this.shareConfiguredSiteFamily(normalizedCoverUrl, refererUrl)) {
        return candidates;
      }
      const refererProtocol: string = referer.protocol.toLowerCase();
      if (refererProtocol !== 'http:' && refererProtocol !== 'https:') {
        return candidates;
      }
      const port: string = referer.port.length > 0 ? `:${referer.port}` : '';
      const samePathCandidate: string =
        `${refererProtocol}//${referer.hostname}${port}${cover.pathname}${cover.search}${cover.hash}`;
      if (samePathCandidate !== normalizedCoverUrl) {
        candidates.push(samePathCandidate);
      }
    } catch (_error) {
      return candidates;
    }
    return candidates;
  }

  private shareConfiguredSiteFamily(firstUrl: string, secondUrl: string): boolean {
    const firstRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(firstUrl);
    const secondRule: NovelSiteRule | undefined = this.ruleCatalog.resolveRule(secondUrl);
    return firstRule !== undefined && secondRule !== undefined && firstRule.id === secondRule.id;
  }

  private resolveSafeReferer(value: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(value.trim());
      const protocol: string = parsed.protocol.toLowerCase();
      if (protocol !== 'http:' && protocol !== 'https:') {
        return '';
      }
      const port: string = parsed.port.length > 0 ? `:${parsed.port}` : '';
      return `${protocol}//${parsed.hostname}${port}/`;
    } catch (_error) {
      return '';
    }
  }
}

export const sharedNovelBookCoverRequestService: NovelBookCoverRequestService =
  new NovelBookCoverRequestService();
