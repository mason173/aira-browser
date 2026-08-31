import {
  NovelCatalogCacheRecord,
  NovelCatalogEntry
} from '../../features/novel/NovelReaderModels';

const COMPLETE_CATALOG_REFRESH_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
const PARTIAL_CATALOG_REFRESH_INTERVAL_MS: number = 15 * 60 * 1000;

/** 决定目录快照何时后台刷新；数据读取和网络抓取不属于这个纯策略。 */
export class NovelCatalogCachePolicyService {
  shouldRefresh(
    record: NovelCatalogCacheRecord | undefined,
    sourceLatest: string,
    now: number = Date.now()
  ): boolean {
    if (record === undefined || record.entries.length === 0 || record.cachedAt <= 0) {
      return true;
    }
    const normalizedLatest: string = sourceLatest.trim();
    if (normalizedLatest.length > 0 && normalizedLatest !== record.sourceLatest.trim()) {
      return true;
    }
    const refreshInterval: number = record.complete
      ? COMPLETE_CATALOG_REFRESH_INTERVAL_MS
      : PARTIAL_CATALOG_REFRESH_INTERVAL_MS;
    return now - record.cachedAt >= refreshInterval;
  }

  /** 同一本书的部分结果只扩充，不允许短响应删掉已知章节标题。 */
  mergeMonotonic(current: NovelCatalogEntry[], incoming: NovelCatalogEntry[]): NovelCatalogEntry[] {
    const merged: NovelCatalogEntry[] = current.map((entry: NovelCatalogEntry): NovelCatalogEntry => ({
      ordinal: entry.ordinal,
      title: entry.title,
      url: entry.url
    }));
    const replaceOrAppend = (entry: NovelCatalogEntry): void => {
      const url: string = entry.url.trim();
      const title: string = entry.title.trim();
      const ordinal: number = Math.floor(entry.ordinal);
      if (url.length === 0 || title.length === 0 || !Number.isFinite(ordinal) || ordinal < 0) {
        return;
      }
      for (let index: number = merged.length - 1; index >= 0; index -= 1) {
        if (merged[index].url === url || merged[index].ordinal === ordinal) {
          merged.splice(index, 1);
        }
      }
      merged.push({ ordinal: ordinal, title: title, url: url });
    };
    for (let index: number = 0; index < incoming.length; index += 1) {
      replaceOrAppend(incoming[index]);
    }
    merged.sort((left: NovelCatalogEntry, right: NovelCatalogEntry): number =>
      left.ordinal === right.ordinal ? left.url.localeCompare(right.url) : left.ordinal - right.ordinal);
    return merged;
  }
}
