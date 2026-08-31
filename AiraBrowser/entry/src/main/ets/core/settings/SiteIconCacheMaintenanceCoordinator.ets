import {
  BookmarkNode,
  HistoryVisit,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { OfflinePageRecord } from '../../common/models/OfflinePageModels';
import {
  BookmarkRepository,
  HistoryRepository,
  ShortcutRepository
} from '../../data/repositories/BrowserRepositories';
import { OfflinePageRepository } from '../../data/offline/OfflinePageRepository';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import {
  SiteIconCachePruneResult,
  SiteIconResult
} from '../../common/models/SiteIconModels';

export interface SiteIconCacheRefreshResult {
  message: string;
}

interface SiteIconRefreshTarget {
  url: string;
}

export class SiteIconCacheMaintenanceCoordinator {
  private bookmarkRepository: BookmarkRepository;
  private historyRepository: HistoryRepository;
  private shortcutRepository: ShortcutRepository;
  private offlinePageRepository: OfflinePageRepository;
  private siteIconService: SiteIconService;

  constructor(
    bookmarkRepository: BookmarkRepository,
    historyRepository: HistoryRepository,
    shortcutRepository: ShortcutRepository,
    offlinePageRepository: OfflinePageRepository,
    siteIconService: SiteIconService = new SiteIconService()
  ) {
    this.bookmarkRepository = bookmarkRepository;
    this.historyRepository = historyRepository;
    this.shortcutRepository = shortcutRepository;
    this.offlinePageRepository = offlinePageRepository;
    this.siteIconService = siteIconService;
  }

  async refreshKnownSiteIcons(): Promise<SiteIconCacheRefreshResult> {
    const targets = await this.collectTargets();
    let refreshedCount = 0;
    let failedCount = 0;
    let skippedCount = 0;

    for (let index = 0; index < targets.length; index += 1) {
      const target = targets[index];
      const result: SiteIconResult | undefined = await this.siteIconService.refresh(target.url, {
        networkPolicy: 'remoteAllowed'
      });
      if (result === undefined) {
        failedCount += 1;
      } else if (result.cacheState === 'network') {
        refreshedCount += 1;
      } else {
        skippedCount += 1;
      }
    }

    const pruneResult = await this.siteIconService.prune();
    return this.buildResult(targets.length, refreshedCount, failedCount, skippedCount, pruneResult);
  }

  private async collectTargets(): Promise<SiteIconRefreshTarget[]> {
    const urls: string[] = [];
    this.bookmarkRepository.listNodes().forEach((node: BookmarkNode) => {
      if (node.type === 'bookmark') {
        this.appendUrl(urls, node.url ?? '');
      }
    });
    this.historyRepository.listVisits().forEach((visit: HistoryVisit) => {
      this.appendUrl(urls, visit.url);
    });
    this.shortcutRepository.listAll().forEach((shortcut: ShortcutRecord) => {
      this.appendShortcutUrls(urls, shortcut);
    });
    const offlinePages = await this.offlinePageRepository.list();
    offlinePages.forEach((page: OfflinePageRecord) => {
      this.appendUrl(urls, page.originalUrl);
      this.appendUrl(urls, page.normalizedUrl);
    });
    return urls.map((url: string): SiteIconRefreshTarget => {
      return { url: url };
    });
  }

  private appendShortcutUrls(urls: string[], shortcut: ShortcutRecord): void {
    this.appendUrl(urls, shortcut.url);
  }

  private appendUrl(urls: string[], url: string): void {
    const normalized = this.normalizeUrl(url);
    if (normalized.length === 0 || urls.indexOf(normalized) >= 0) {
      return;
    }
    urls.push(normalized);
  }

  private normalizeUrl(url: string): string {
    const normalized = url.trim();
    if (normalized.length === 0) {
      return '';
    }
    if (!/^https?:\/\//i.test(normalized)) {
      return '';
    }
    return normalized;
  }

  private buildResult(
    targetCount: number,
    refreshedCount: number,
    failedCount: number,
    skippedCount: number,
    pruneResult: SiteIconCachePruneResult
  ): SiteIconCacheRefreshResult {
    let message = '没有需要刷新的网站图标。';
    if (targetCount > 0 && refreshedCount > 0 && failedCount === 0 && skippedCount === 0) {
      message = `已刷新 ${refreshedCount} 个网站图标。`;
    } else if (targetCount > 0 && refreshedCount === 0 && failedCount === 0 && skippedCount > 0) {
      message = `已检查 ${skippedCount} 个网站图标，当前缓存已经是更高清版本。`;
    } else if (refreshedCount > 0) {
      const skippedText = skippedCount > 0 ? `，${skippedCount} 个已保留更高清缓存` : '';
      const failedText = failedCount > 0 ? `，${failedCount} 个暂时无法获取` : '';
      message = `已刷新 ${refreshedCount} 个网站图标${skippedText}${failedText}。`;
    } else if (failedCount > 0) {
      message = '网站图标暂时无法刷新，请稍后再试。';
    }
    if (pruneResult.removedFiles > 0) {
      message = `${message} 已清理 ${pruneResult.removedFiles} 个旧图标缓存。`;
    }
    return {
      message: message
    };
  }
}
