import { http } from '@kit.NetworkKit';
import urlUtils from '@ohos.url';
import {
  NovelBookOverview,
  NovelCatalogEntry,
  NovelCatalogResult
} from '../../features/novel/NovelReaderModels';
import { ComicBookSourceRule } from '../../features/novel/NovelSiteRules';

interface ZaimanComicAuthorRaw {
  authorName?: string;
}

interface ZaimanComicChapterRaw {
  chapter_id?: string | number;
  chapter_title?: string;
  chapter_name?: string;
  title?: string;
}

interface ZaimanComicChapterGroupRaw {
  data?: ZaimanComicChapterRaw[];
}

interface ZaimanComicInfoRaw {
  id?: string | number;
  comicPy?: string;
  title?: string;
  cover?: string;
  description?: string;
  types?: string;
  readerGroup?: string;
  lastUpdateChapterName?: string;
  authorInfo?: ZaimanComicAuthorRaw;
  chapterList?: ZaimanComicChapterGroupRaw[];
}

interface ZaimanComicDetailDataRaw {
  comicInfo?: ZaimanComicInfoRaw;
}

interface ZaimanComicDetailResponseRaw {
  errno?: number;
  data?: ZaimanComicDetailDataRaw;
}

interface ZaimanComicTagRaw {
  tag_name?: string;
}

interface ZaimanMobileComicInfoRaw {
  id?: string | number;
  comic_py?: string;
  title?: string;
  cover?: string;
  description?: string;
  last_update_chapter_name?: string;
  authors?: ZaimanComicTagRaw[];
  types?: ZaimanComicTagRaw[];
  status?: ZaimanComicTagRaw[];
  chapters?: ZaimanComicChapterGroupRaw[];
}

interface ZaimanMobileComicDetailDataRaw {
  data?: ZaimanMobileComicInfoRaw;
}

interface ZaimanMobileComicDetailResponseRaw {
  errno?: number;
  data?: ZaimanMobileComicDetailDataRaw;
}

interface ZaimanNormalizedComicInfo {
  comicId: string;
  comicPy: string;
  title: string;
  author: string;
  category: string;
  latest: string;
  cover: string;
  synopsis: string;
  chapterGroups: ZaimanComicChapterGroupRaw[];
}

interface ComicBookPageIdentity {
  pageUrl: string;
  origin: string;
  host: string;
  comicPy: string;
  comicId: string;
}

interface ComicBookAcquisitionResult {
  title: string;
  author: string;
  category: string;
  latest: string;
  cover: string;
  synopsis: string;
  host: string;
  detailUrl: string;
  entries: NovelCatalogEntry[];
  total: number;
  complete: boolean;
}

interface ComicBookAcquisitionCache {
  pageUrl: string;
  storedAt: number;
  result: ComicBookAcquisitionResult;
}

const COMIC_BOOK_CONNECT_TIMEOUT_MS: number = 8000;
const COMIC_BOOK_READ_TIMEOUT_MS: number = 12000;
const COMIC_BOOK_MAX_BYTES: number = 4 * 1024 * 1024;
const COMIC_BOOK_MAX_CATALOG_ENTRIES: number = 8000;
const COMIC_BOOK_CACHE_TTL_MS: number = 15 * 1000;

/**
 * `NovelExtractionService` 的本地漫画书籍子引擎。
 * 站点只能选择编译进 App 的已审阅算法，不能提供 endpoint、header 或字段路径。
 */
export class ComicBookOverviewAcquisitionEngine {
  private cache?: ComicBookAcquisitionCache;

  supportsBookPage(pageUrl: string, source: ComicBookSourceRule): boolean {
    return source.kind === 'zaiman_detail_json_api' && this.resolveZaimanPageIdentity(pageUrl) !== undefined;
  }

  async acquireOverview(
    pageUrl: string,
    source: ComicBookSourceRule,
    initialEntryLimit: number
  ): Promise<NovelBookOverview | undefined> {
    const result: ComicBookAcquisitionResult | undefined = await this.acquire(pageUrl, source);
    if (result === undefined) {
      return undefined;
    }
    const limit: number = Math.max(1, Math.min(COMIC_BOOK_MAX_CATALOG_ENTRIES, Math.floor(initialEntryLimit)));
    return {
      contentKind: 'comic',
      title: result.title,
      author: result.author,
      category: result.category,
      latest: result.latest,
      cover: result.cover,
      synopsis: result.synopsis,
      host: result.host,
      catalogUrl: result.detailUrl,
      startChapterUrl: result.entries.length > 0 ? result.entries[0].url : '',
      catalogSourceComplete: result.complete,
      catalogTotal: result.total,
      initialEntries: result.entries.slice(0, limit)
    };
  }

  async acquireCatalog(
    pageUrl: string,
    source: ComicBookSourceRule,
    maximumEntries: number
  ): Promise<NovelCatalogResult | undefined> {
    const result: ComicBookAcquisitionResult | undefined = await this.acquire(pageUrl, source);
    if (result === undefined) {
      return undefined;
    }
    const limit: number = Math.max(1, Math.min(COMIC_BOOK_MAX_CATALOG_ENTRIES, Math.floor(maximumEntries)));
    const entries: NovelCatalogEntry[] = result.entries.slice(0, limit);
    return {
      bookTitle: result.title,
      author: result.author,
      coverUrl: result.cover,
      complete: result.complete && result.total === entries.length,
      entries: entries
    };
  }

  private async acquire(
    pageUrl: string,
    source: ComicBookSourceRule
  ): Promise<ComicBookAcquisitionResult | undefined> {
    if (source.kind !== 'zaiman_detail_json_api') {
      return undefined;
    }
    const identity: ComicBookPageIdentity | undefined = this.resolveZaimanPageIdentity(pageUrl);
    if (identity === undefined) {
      return undefined;
    }
    const cached: ComicBookAcquisitionCache | undefined = this.cache;
    if (cached !== undefined && cached.pageUrl === identity.pageUrl &&
      Date.now() - cached.storedAt <= COMIC_BOOK_CACHE_TTL_MS) {
      return cached.result;
    }
    const payload: string = await this.fetchZaimanDetail(identity);
    const result: ComicBookAcquisitionResult | undefined = this.parseZaimanDetail(payload, identity);
    if (result !== undefined) {
      this.cache = { pageUrl: identity.pageUrl, storedAt: Date.now(), result: result };
    }
    return result;
  }

  private async fetchZaimanDetail(identity: ComicBookPageIdentity): Promise<string> {
    const query: string = 'channel=pc&app_name=zmh&version=1.0.0&timestamp=' + Date.now().toString() +
      '&uid=113119197&comic_py=' + encodeURIComponent(identity.comicPy);
    const endpoint: string = identity.comicId.length > 0
      ? `${identity.origin}/api/app/v1/comic/detail/${identity.comicId}`
      : `${identity.origin}/api/v1/comic1/comic/detail?${query}`;
    const request = http.createHttp();
    try {
      const response = await request.request(endpoint, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: COMIC_BOOK_CONNECT_TIMEOUT_MS,
        readTimeout: COMIC_BOOK_READ_TIMEOUT_MS,
        usingCache: false,
        maxLimit: COMIC_BOOK_MAX_BYTES,
        header: {
          'Accept': 'application/json,text/plain,*/*',
          'Referer': identity.pageUrl,
          'Platform': 'pc'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        return '';
      }
      const payload: string = response.result;
      return payload.length > 0 && payload.length <= COMIC_BOOK_MAX_BYTES ? payload : '';
    } catch (_error) {
      return '';
    } finally {
      request.destroy();
    }
  }

  private parseZaimanDetail(
    payload: string,
    identity: ComicBookPageIdentity
  ): ComicBookAcquisitionResult | undefined {
    if (payload.length === 0) {
      return undefined;
    }
    let normalized: ZaimanNormalizedComicInfo | undefined;
    try {
      if (identity.comicId.length > 0) {
        normalized = this.normalizeZaimanMobileDetail(
          JSON.parse(payload) as ZaimanMobileComicDetailResponseRaw
        );
      } else {
        normalized = this.normalizeZaimanDesktopDetail(
          JSON.parse(payload) as ZaimanComicDetailResponseRaw
        );
      }
    } catch (_error) {
      return undefined;
    }
    if (normalized === undefined) {
      return undefined;
    }
    const identityMatches: boolean = identity.comicId.length > 0
      ? normalized.comicId === identity.comicId
      : normalized.comicPy.toLowerCase() === identity.comicPy.toLowerCase();
    if (normalized.comicId.length === 0 || normalized.title.length === 0 || !identityMatches) {
      return undefined;
    }
    const entries: NovelCatalogEntry[] = [];
    const seenUrls: Record<string, boolean> = {};
    let validTotal: number = 0;
    const groups: ZaimanComicChapterGroupRaw[] = normalized.chapterGroups;
    for (let groupIndex: number = 0; groupIndex < groups.length; groupIndex += 1) {
      const chapters: ZaimanComicChapterRaw[] = Array.isArray(groups[groupIndex].data)
        ? groups[groupIndex].data as ZaimanComicChapterRaw[]
        : [];
      // 站点接口默认最新章在前，阅读目录统一归一为从最早到最新。
      for (let chapterIndex: number = chapters.length - 1; chapterIndex >= 0; chapterIndex -= 1) {
        const chapterId: string = this.integerText(chapters[chapterIndex].chapter_id);
        const chapterTitle: string = this.text(chapters[chapterIndex].chapter_name) ||
          this.text(chapters[chapterIndex].chapter_title) ||
          this.text(chapters[chapterIndex].title);
        if (chapterId.length === 0 || chapterTitle.length === 0) {
          continue;
        }
        const chapterUrl: string = identity.comicId.length > 0
          ? `${identity.origin}/pages/comic/page?comic_id=${normalized.comicId}&chapter_id=${chapterId}`
          : `${identity.origin}/view/${normalized.comicPy}/${normalized.comicId}/${chapterId}`;
        if (seenUrls[chapterUrl] === true) {
          continue;
        }
        seenUrls[chapterUrl] = true;
        if (entries.length < COMIC_BOOK_MAX_CATALOG_ENTRIES) {
          entries.push({ ordinal: validTotal, title: chapterTitle, url: chapterUrl });
        }
        validTotal += 1;
      }
    }
    return {
      title: normalized.title,
      author: normalized.author,
      category: normalized.category,
      latest: normalized.latest ||
        (entries.length > 0 ? entries[entries.length - 1].title : ''),
      cover: normalized.cover,
      synopsis: normalized.synopsis,
      host: identity.host,
      detailUrl: identity.pageUrl,
      entries: entries,
      total: validTotal,
      complete: validTotal === entries.length
    };
  }

  private normalizeZaimanDesktopDetail(
    response: ZaimanComicDetailResponseRaw
  ): ZaimanNormalizedComicInfo | undefined {
    const info: ZaimanComicInfoRaw | undefined = response.errno === 0 ? response.data?.comicInfo : undefined;
    if (info === undefined) {
      return undefined;
    }
    const types: string = this.text(info.types);
    const readerGroup: string = this.text(info.readerGroup);
    return {
      comicId: this.integerText(info.id),
      comicPy: this.text(info.comicPy),
      title: this.text(info.title),
      author: this.text(info.authorInfo?.authorName),
      category: readerGroup.length > 0 && types.length > 0
        ? `${readerGroup} / ${types}`
        : (types || readerGroup),
      latest: this.text(info.lastUpdateChapterName),
      cover: this.httpUrl(info.cover),
      synopsis: this.text(info.description),
      chapterGroups: Array.isArray(info.chapterList) ? info.chapterList : []
    };
  }

  private normalizeZaimanMobileDetail(
    response: ZaimanMobileComicDetailResponseRaw
  ): ZaimanNormalizedComicInfo | undefined {
    const info: ZaimanMobileComicInfoRaw | undefined = response.errno === 0 ? response.data?.data : undefined;
    if (info === undefined) {
      return undefined;
    }
    const status: string = this.tagNames(info.status, ' / ');
    const types: string = this.tagNames(info.types, ' / ');
    return {
      comicId: this.integerText(info.id),
      comicPy: this.text(info.comic_py),
      title: this.text(info.title),
      author: this.tagNames(info.authors, ', '),
      category: status.length > 0 && types.length > 0 ? `${status} / ${types}` : (types || status),
      latest: this.text(info.last_update_chapter_name),
      cover: this.httpUrl(info.cover),
      synopsis: this.text(info.description),
      chapterGroups: Array.isArray(info.chapters) ? info.chapters : []
    };
  }

  private resolveZaimanPageIdentity(pageUrl: string): ComicBookPageIdentity | undefined {
    let parsed: urlUtils.URL;
    try {
      parsed = urlUtils.URL.parseURL(pageUrl.trim());
    } catch (_error) {
      return undefined;
    }
    const scheme: string = parsed.protocol.replace(':', '').toLowerCase();
    const host: string = parsed.hostname.toLowerCase();
    if ((scheme !== 'https' && scheme !== 'http') || parsed.username.length > 0) {
      return undefined;
    }
    if (host !== 'zaimanhua.com' && !host.endsWith('.zaimanhua.com')) {
      return undefined;
    }
    const path: string = parsed.pathname;
    let comicPy: string = '';
    let comicId: string = '';
    if (path.startsWith('/info/') && path.endsWith('.html')) {
      comicPy = path.substring('/info/'.length, path.length - '.html'.length);
    } else if (path.startsWith('/details/') && path.endsWith('.html')) {
      comicPy = path.substring('/details/'.length, path.length - '.html'.length);
    } else if (path === '/pages/comic/detail') {
      comicId = this.integerText(parsed.params.get('id') ?? '');
    }
    if ((comicPy.length === 0 || !/^[A-Za-z0-9_-]+$/.test(comicPy)) && comicId.length === 0) {
      return undefined;
    }
    parsed.hash = '';
    return {
      pageUrl: parsed.toString(),
      origin: parsed.origin,
      host: host,
      comicPy: comicPy,
      comicId: comicId
    };
  }

  private tagNames(values: ZaimanComicTagRaw[] | undefined, separator: string): string {
    const source: ZaimanComicTagRaw[] = Array.isArray(values) ? values : [];
    const output: string[] = [];
    for (let index: number = 0; index < source.length; index += 1) {
      const name: string = this.text(source[index].tag_name);
      if (name.length > 0 && output.indexOf(name) < 0) {
        output.push(name);
      }
    }
    return output.join(separator);
  }

  private integerText(value: string | number | undefined): string {
    const normalized: string = this.text(value);
    return /^\d+$/.test(normalized) ? normalized : '';
  }

  private httpUrl(value: string | undefined): string {
    const normalized: string = this.text(value);
    return normalized.startsWith('https://') || normalized.startsWith('http://') ? normalized : '';
  }

  private text(value: string | number | undefined): string {
    return value === undefined || value === null ? '' : String(value).trim();
  }
}
