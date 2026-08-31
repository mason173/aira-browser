import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import {
  NovelCatalogEntry,
  NovelCatalogPageCursor,
  NovelCatalogPageResult
} from '../../features/novel/NovelReaderModels';
import { NovelCatalogPageSourceRule } from '../../features/novel/NovelSiteRules';

interface NovelNumberedCatalogEntryRaw {
  title?: string;
  pic?: string;
}

interface NovelNumberedCatalogPageRaw {
  total?: string | number;
  pageSize?: string | number;
  totalPage?: string | number;
  list?: NovelNumberedCatalogEntryRaw[];
}

const NOVEL_CATALOG_PAGE_CONNECT_TIMEOUT_MS: number = 8000;
const NOVEL_CATALOG_PAGE_READ_TIMEOUT_MS: number = 10000;
const NOVEL_CATALOG_PAGE_MAX_BYTES: number = 512 * 1024;
const NOVEL_CATALOG_PAGE_MAX_TOKEN_LENGTH: number = 160;
const NOVEL_CATALOG_PAGE_MAX_ENTRIES: number = 100;

/**
 * NovelExtractionService 的本地分页子引擎。它只执行编译进 App 的同源 JSON recipe，
 * 不接受云端 endpoint、请求头、Cookie 或脚本。
 */
export class NovelCatalogPageAcquisitionEngine {
  async resolveInitialCursor(
    controller: webview.WebviewController,
    pageUrl: string,
    ruleId: string,
    rule: NovelCatalogPageSourceRule
  ): Promise<NovelCatalogPageCursor | undefined> {
    if (rule.kind !== 'numbered_json_list' || this.extractOrigin(pageUrl).length === 0) {
      return undefined;
    }
    const script: string = `
(function(){
  try {
    var expected = new URL(${JSON.stringify(pageUrl)});
    if (expected.origin !== location.origin || expected.pathname !== location.pathname){ return ''; }
    var element = document.querySelector(${JSON.stringify(rule.tokenSelector)});
    if (!element){ return ''; }
    return String(element.getAttribute(${JSON.stringify(rule.tokenAttribute)}) || '').trim();
  } catch (e){ return ''; }
})();`;
    const raw: string = await controller.runJavaScript(script);
    const token: string = this.normalizeScriptString(raw).substring(0, NOVEL_CATALOG_PAGE_MAX_TOKEN_LENGTH);
    if (token.length === 0) {
      return undefined;
    }
    const initialPage: number = Math.max(0, Math.floor(rule.initialPage));
    return {
      ruleId: ruleId,
      bookToken: token,
      initialPage: initialPage,
      nextPage: initialPage,
      pageSize: Math.max(1, Math.floor(rule.pageSize)),
      totalHint: 0,
      totalPages: 0
    };
  }

  async acquire(
    catalogUrl: string,
    cursor: NovelCatalogPageCursor,
    ruleId: string,
    rule: NovelCatalogPageSourceRule
  ): Promise<NovelCatalogPageResult | undefined> {
    if (rule.kind !== 'numbered_json_list' || cursor.ruleId !== ruleId ||
      cursor.bookToken.length === 0 || cursor.bookToken.length > NOVEL_CATALOG_PAGE_MAX_TOKEN_LENGTH ||
      cursor.initialPage < 0 || cursor.nextPage < cursor.initialPage) {
      return undefined;
    }
    const requestUrl: string = this.buildRequestUrl(catalogUrl, cursor, rule);
    if (requestUrl.length === 0) {
      return undefined;
    }
    const payload: string = await this.fetchJson(requestUrl, catalogUrl);
    if (payload.length === 0) {
      return undefined;
    }
    let parsed: NovelNumberedCatalogPageRaw;
    try {
      parsed = JSON.parse(payload) as NovelNumberedCatalogPageRaw;
    } catch (_error) {
      return undefined;
    }
    const rawEntries: NovelNumberedCatalogEntryRaw[] = Array.isArray(parsed.list) ? parsed.list : [];
    if (rawEntries.length > NOVEL_CATALOG_PAGE_MAX_ENTRIES) {
      return undefined;
    }
    const entries: NovelCatalogEntry[] = [];
    const firstOrdinal: number = Math.max(0, cursor.nextPage - cursor.initialPage) * cursor.pageSize;
    for (let index: number = 0; index < rawEntries.length; index += 1) {
      const title: string = String(rawEntries[index].title ?? '').trim();
      const url: string = this.resolveSameOriginUrl(String(rawEntries[index].pic ?? ''), catalogUrl);
      if (title.length > 0 && url.length > 0) {
        entries.push({ ordinal: firstOrdinal + index, title: title, url: url });
      }
    }
    if (entries.length === 0) {
      return undefined;
    }
    const pageSize: number = this.positiveInteger(parsed.pageSize, cursor.pageSize);
    const totalHint: number = this.positiveInteger(parsed.total, cursor.totalHint);
    const totalPages: number = this.positiveInteger(parsed.totalPage, cursor.totalPages);
    const nextPage: number = cursor.nextPage + 1;
    const hasMore: boolean = totalPages > 0
      ? nextPage < cursor.initialPage + totalPages
      : entries.length >= pageSize;
    return {
      entries: entries,
      hasMore: hasMore,
      cursor: {
        ruleId: cursor.ruleId,
        bookToken: cursor.bookToken,
        initialPage: cursor.initialPage,
        nextPage: nextPage,
        pageSize: pageSize,
        totalHint: Math.max(totalHint, cursor.totalHint),
        totalPages: Math.max(totalPages, cursor.totalPages)
      }
    };
  }

  private async fetchJson(url: string, referer: string): Promise<string> {
    const request = http.createHttp();
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: NOVEL_CATALOG_PAGE_CONNECT_TIMEOUT_MS,
        readTimeout: NOVEL_CATALOG_PAGE_READ_TIMEOUT_MS,
        usingCache: false,
        maxLimit: NOVEL_CATALOG_PAGE_MAX_BYTES,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'Referer': referer
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return '';
      }
      const payload: string = response.result;
      return payload.length > 0 && payload.length <= NOVEL_CATALOG_PAGE_MAX_BYTES ? payload : '';
    } finally {
      request.destroy();
    }
  }

  private buildRequestUrl(
    catalogUrl: string,
    cursor: NovelCatalogPageCursor,
    rule: NovelCatalogPageSourceRule
  ): string {
    const origin: string = this.extractOrigin(catalogUrl);
    if (origin.length === 0 || !rule.endpointPath.startsWith('/')) {
      return '';
    }
    return `${origin}${rule.endpointPath}?${encodeURIComponent(rule.tokenQueryName)}=` +
      `${encodeURIComponent(cursor.bookToken)}&${encodeURIComponent(rule.pageQueryName)}=${cursor.nextPage}` +
      `&${encodeURIComponent(rule.orderQueryName)}=${encodeURIComponent(rule.orderQueryValue)}`;
  }

  private resolveSameOriginUrl(value: string, baseUrl: string): string {
    const candidate: string = value.trim();
    const origin: string = this.extractOrigin(baseUrl);
    if (candidate.length === 0 || origin.length === 0) {
      return '';
    }
    let resolved: string = '';
    if (candidate.startsWith('https://') || candidate.startsWith('http://')) {
      resolved = candidate;
    } else if (candidate.startsWith('/')) {
      resolved = origin + candidate;
    } else {
      const cleanBase: string = this.stripQueryAndFragment(baseUrl);
      const slash: number = cleanBase.lastIndexOf('/');
      resolved = slash >= 0 ? cleanBase.substring(0, slash + 1) + candidate : '';
    }
    return this.extractOrigin(resolved) === origin ? resolved : '';
  }

  private extractOrigin(url: string): string {
    const value: string = url.trim();
    const schemeIndex: number = value.indexOf('://');
    if (schemeIndex <= 0) {
      return '';
    }
    const scheme: string = value.substring(0, schemeIndex).toLowerCase();
    if (scheme !== 'https' && scheme !== 'http') {
      return '';
    }
    const authorityStart: number = schemeIndex + 3;
    const slashIndex: number = value.indexOf('/', authorityStart);
    const authority: string = slashIndex >= 0
      ? value.substring(authorityStart, slashIndex)
      : this.stripQueryAndFragment(value.substring(authorityStart));
    return authority.length > 0 ? `${scheme}://${authority.toLowerCase()}` : '';
  }

  private stripQueryAndFragment(value: string): string {
    let end: number = value.length;
    const query: number = value.indexOf('?');
    const fragment: number = value.indexOf('#');
    if (query >= 0) {
      end = query;
    }
    if (fragment >= 0 && fragment < end) {
      end = fragment;
    }
    return value.substring(0, end);
  }

  private normalizeScriptString(raw: string): string {
    const value: string = raw.trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      try {
        const parsed = JSON.parse(value) as string;
        return typeof parsed === 'string' ? parsed.trim() : '';
      } catch (_error) {
        return '';
      }
    }
    return value;
  }

  private positiveInteger(value: string | number | undefined, fallback: number): number {
    const numeric: number = typeof value === 'number' ? value : parseInt(String(value ?? ''), 10);
    return Number.isFinite(numeric) && numeric > 0 ? Math.floor(numeric) : Math.max(0, Math.floor(fallback));
  }
}
