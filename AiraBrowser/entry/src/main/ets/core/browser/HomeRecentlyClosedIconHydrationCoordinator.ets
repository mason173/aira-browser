import { image } from '@kit.ImageKit';
import { SiteIconUriCacheEntry } from '../../common/models/SiteIconModels';
import { HomeRecentlyClosedPreparedIconService } from '../../services/siteicons/HomeRecentlyClosedPreparedIconService';
import { SiteIconPixelMapCacheService } from '../../services/siteicons/SiteIconPixelMapCacheService';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { BrowserRecentlyClosedTabRecord } from './BrowserRecentlyClosedTabsService';

export interface HomeRecentlyClosedIconState {
  id: string;
  path: string;
  pixelMap?: image.PixelMap;
}

export interface HomeRecentlyClosedIconHydrationSnapshot {
  icons: HomeRecentlyClosedIconState[];
}

export interface HomeRecentlyClosedIconHydrationCallbacks {
  applySnapshot: (snapshot: HomeRecentlyClosedIconHydrationSnapshot) => void;
  persistResolvedIcon: (recordId: string, iconPath: string) => void;
}

interface RecentlyClosedIconPrepareCandidate {
  recordId: string;
  sourcePath: string;
  shouldPersist: boolean;
}

export class HomeRecentlyClosedIconHydrationCoordinator {
  private readonly siteIconService: SiteIconService;
  private readonly pixelMapCacheService: SiteIconPixelMapCacheService;
  private readonly preparedIconService: HomeRecentlyClosedPreparedIconService;
  private icons: HomeRecentlyClosedIconState[] = [];
  private resolveGeneration: number = 0;
  private lastResolveSignature: string = '';

  constructor(
    siteIconService: SiteIconService = new SiteIconService(),
    pixelMapCacheService: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService(),
    preparedIconService?: HomeRecentlyClosedPreparedIconService
  ) {
    this.siteIconService = siteIconService;
    this.pixelMapCacheService = pixelMapCacheService;
    this.preparedIconService = preparedIconService ?? new HomeRecentlyClosedPreparedIconService(pixelMapCacheService);
  }

  clear(callbacks: HomeRecentlyClosedIconHydrationCallbacks): void {
    this.nextResolveToken();
    this.icons = [];
    this.lastResolveSignature = '';
    callbacks.applySnapshot(this.buildSnapshot());
  }

  resolveFor(
    records: BrowserRecentlyClosedTabRecord[],
    callbacks: HomeRecentlyClosedIconHydrationCallbacks
  ): void {
    if (records.length === 0) {
      this.clear(callbacks);
      return;
    }

    const resolveSignature = this.buildResolveSignature(records);
    if (resolveSignature === this.lastResolveSignature) {
      return;
    }
    this.lastResolveSignature = resolveSignature;

    const token = this.nextResolveToken();
    const activeRecordIds = records.map((record: BrowserRecentlyClosedTabRecord) => record.id);
    const activeIconStates: HomeRecentlyClosedIconState[] = [];
    const pendingRecords: BrowserRecentlyClosedTabRecord[] = [];
    records.forEach((record: BrowserRecentlyClosedTabRecord) => {
      const memoryUri = this.siteIconService.peekUri(this.resolveRecordUrl(record));
      if (memoryUri.length > 0) {
        activeIconStates.push(this.createIconState(record.id, memoryUri));
        return;
      }
      const existingIcon = this.icons.find((item: HomeRecentlyClosedIconState) => item.id === record.id);
      if (existingIcon !== undefined) {
        activeIconStates.push(existingIcon);
      } else {
        const storedIconUri = this.resolveStoredRecordIconUri(record);
        if (storedIconUri.length > 0) {
          activeIconStates.push(this.createIconState(record.id, storedIconUri));
        }
      }
      pendingRecords.push(record);
    });

    this.icons = this.mergeIconStates(activeIconStates, activeRecordIds);
    callbacks.applySnapshot(this.buildSnapshot());
    this.resolveCachedRecordIcons(token, pendingRecords, callbacks);
  }

  private resolveCachedRecordIcons(
    token: number,
    records: BrowserRecentlyClosedTabRecord[],
    callbacks: HomeRecentlyClosedIconHydrationCallbacks
  ): void {
    if (records.length <= 0) {
      return;
    }
    const urls = records.map((record: BrowserRecentlyClosedTabRecord) => this.resolveRecordUrl(record));
    this.siteIconService.resolveCachedUris(urls)
      .then((cachedIcons: SiteIconUriCacheEntry[]) => {
        if (!this.isCurrentToken(token)) {
          return;
        }
        const candidates: RecentlyClosedIconPrepareCandidate[] = [];
        records.forEach((record: BrowserRecentlyClosedTabRecord) => {
          const uri = this.findCachedIconUri(this.resolveRecordUrl(record), cachedIcons);
          if (uri.length <= 0) {
            return;
          }
          candidates.push({
            recordId: record.id,
            sourcePath: uri,
            shouldPersist: this.resolveStoredRecordIconUri(record).length === 0
          });
        });
        this.prepareAndApplyResolvedIcons(token, candidates, callbacks);
      })
      .catch((_error: Error) => {
      });
  }

  private prepareAndApplyResolvedIcons(
    token: number,
    candidates: RecentlyClosedIconPrepareCandidate[],
    callbacks: HomeRecentlyClosedIconHydrationCallbacks
  ): void {
    if (!this.isCurrentToken(token) || candidates.length === 0) {
      return;
    }
    const prepareTasks: Promise<HomeRecentlyClosedIconState | undefined>[] = [];
    candidates.forEach((candidate: RecentlyClosedIconPrepareCandidate) => {
      prepareTasks.push(this.prepareResolvedIconState(token, candidate));
    });
    Promise.all(prepareTasks)
      .then((preparedStates: (HomeRecentlyClosedIconState | undefined)[]) => {
        if (!this.isCurrentToken(token)) {
          return;
        }
        const resolvedStates: HomeRecentlyClosedIconState[] = [];
        preparedStates.forEach((state: HomeRecentlyClosedIconState | undefined, index: number) => {
          const candidate = candidates[index];
          resolvedStates.push(state ?? this.createIconState(candidate.recordId, candidate.sourcePath));
        });
        const activeRecordIds = this.icons.map((item: HomeRecentlyClosedIconState) => item.id);
        this.icons = this.mergeIconStates(resolvedStates, activeRecordIds);
        callbacks.applySnapshot(this.buildSnapshot());
        candidates.forEach((candidate: RecentlyClosedIconPrepareCandidate, index: number) => {
          if (!candidate.shouldPersist || !this.isCurrentToken(token)) {
            return;
          }
          callbacks.persistResolvedIcon(candidate.recordId, resolvedStates[index].path);
        });
      })
      .catch((_error: Error) => {
      });
  }

  private async prepareResolvedIconState(
    token: number,
    candidate: RecentlyClosedIconPrepareCandidate
  ): Promise<HomeRecentlyClosedIconState | undefined> {
    if (!this.isCurrentToken(token) || this.preparedIconService.isPreparedIconUri(candidate.sourcePath)) {
      return undefined;
    }
    const preparedIcon = await this.preparedIconService.prepareIconUri(candidate.sourcePath);
    if (!this.isCurrentToken(token) || preparedIcon === undefined || preparedIcon.uri.length === 0) {
      return undefined;
    }
    return {
      id: candidate.recordId,
      path: preparedIcon.uri,
      pixelMap: preparedIcon.pixelMap ?? this.pixelMapCacheService.getCachedPixelMap(preparedIcon.uri)
    };
  }

  private mergeIconStates(
    activeIconStates: HomeRecentlyClosedIconState[],
    activeRecordIds: string[]
  ): HomeRecentlyClosedIconState[] {
    const nextStates = this.icons.filter((item: HomeRecentlyClosedIconState) => {
      return activeRecordIds.indexOf(item.id) >= 0;
    });
    activeIconStates.forEach((state: HomeRecentlyClosedIconState) => {
      const existingIndex = nextStates.findIndex((item: HomeRecentlyClosedIconState) => item.id === state.id);
      if (existingIndex >= 0) {
        nextStates[existingIndex] = state;
      } else {
        nextStates.push(state);
      }
    });
    return nextStates;
  }

  private createIconState(recordId: string, path: string): HomeRecentlyClosedIconState {
    return {
      id: recordId,
      path: path,
      pixelMap: this.pixelMapCacheService.getCachedPixelMap(path)
    };
  }

  private buildSnapshot(): HomeRecentlyClosedIconHydrationSnapshot {
    return {
      icons: this.icons.slice()
    };
  }

  private resolveStoredRecordIconUri(record: BrowserRecentlyClosedTabRecord): string {
    return (record.siteIconUri ?? '').trim();
  }

  private resolveRecordUrl(record: BrowserRecentlyClosedTabRecord): string {
    if (record.tab.url.trim().length > 0) {
      return record.tab.url.trim();
    }
    if (record.tab.lastGoodUrl.trim().length > 0) {
      return record.tab.lastGoodUrl.trim();
    }
    return record.tab.pendingUrl.trim();
  }

  private findCachedIconUri(url: string, cachedIcons: SiteIconUriCacheEntry[]): string {
    const normalizedUrl = url.trim();
    const entry = cachedIcons.find((item: SiteIconUriCacheEntry) => item.url === normalizedUrl);
    return entry?.uri ?? '';
  }

  private nextResolveToken(): number {
    this.resolveGeneration += 1;
    return this.resolveGeneration;
  }

  private isCurrentToken(token: number): boolean {
    return token === this.resolveGeneration;
  }

  private buildResolveSignature(records: BrowserRecentlyClosedTabRecord[]): string {
    const parts: string[] = [];
    records.forEach((record: BrowserRecentlyClosedTabRecord) => {
      parts.push(`${record.id}|${this.resolveStoredRecordIconUri(record)}|${this.resolveRecordUrl(record)}`);
    });
    return parts.join('\n');
  }
}
