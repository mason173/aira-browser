import { ShortcutRecord } from '../../common/models/BrowserModels';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeUrl } from '../../common/utils/UrlUtils';
import { HomeShortcutIconState } from '../../features/newtab/HomeShortcutTypes';
import {
  SiteIconDomainUpdate,
  SiteIconUpdateCenter
} from '../siteicons/SiteIconUpdateCenter';
import {
  HomeShortcutIconAssociationUpdate,
  HomeShortcutIconAssociationUpdateCenter
} from './HomeShortcutIconAssociationUpdateCenter';
import {
  ResolvedShortcutIcon,
  ResolvedShortcutIconEntry,
  ShortcutIconResolverService
} from './ShortcutIconResolverService';

export interface HomeShortcutIconHydrationSnapshot {
  icons: HomeShortcutIconState[];
}

export interface HomeShortcutIconHydrationCallbacks {
  applySnapshot: (snapshot: HomeShortcutIconHydrationSnapshot) => void;
  persistResolvedIcon: (shortcutId: string, sourceUrl: string, iconPath: string) => void;
}

export type HomeShortcutIconHydrationPublicationMode = 'progressive' | 'settled';

interface HomeShortcutIconUpdateToken {
  shortcutId: string;
  token: number;
}

const HOME_SHORTCUT_ICON_REMOTE_MAX_CONCURRENCY: number = 2;
const FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN: number = 0x0000;
const FAVICON_COLDSTART_DIAGNOSTIC_TAG: string = 'HomeShortcutFaviconDiag';

export class HomeShortcutIconHydrationCoordinator {
  private readonly shortcutIconResolver: ShortcutIconResolverService;
  private icons: HomeShortcutIconState[] = [];
  private resolveGeneration: number = 0;
  private lastResolveSignature: string = '';
  private activeShortcuts: ShortcutRecord[] = [];
  private activeCallbacks: HomeShortcutIconHydrationCallbacks | undefined = undefined;
  private unsubscribeSiteIconUpdates: (() => void) | undefined = undefined;
  private unsubscribeShortcutAssociationUpdates: (() => void) | undefined = undefined;
  private iconUpdateGeneration: number = 0;
  private latestIconUpdateTokens: HomeShortcutIconUpdateToken[] = [];

  constructor(shortcutIconResolver: ShortcutIconResolverService) {
    this.shortcutIconResolver = shortcutIconResolver;
  }

  adoptPreparedFor(
    shortcuts: ShortcutRecord[],
    callbacks: HomeShortcutIconHydrationCallbacks
  ): HomeShortcutIconHydrationSnapshot {
    const startedAt = Date.now();
    this.activeShortcuts = shortcuts.slice();
    this.activeCallbacks = shortcuts.length > 0 ? callbacks : undefined;
    this.latestIconUpdateTokens = [];
    // The prepared state only contains process-local pixel maps. Let the first
    // refresh hydrate persisted URIs and discover icons that are not cached yet.
    this.lastResolveSignature = '';
    this.nextResolveToken();

    if (shortcuts.length === 0) {
      this.icons = [];
      this.disposeIconUpdates();
      return this.buildSnapshot();
    }

    this.ensureIconUpdateSubscriptions();
    const activeShortcutIds = shortcuts.map((shortcut: ShortcutRecord) => shortcut.id);
    const preparedEntries: ResolvedShortcutIconEntry[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord): void => {
      const preparedIcon = this.shortcutIconResolver.getCachedShortcutIcon(shortcut);
      if (preparedIcon?.pixelMap === undefined) {
        return;
      }
      preparedEntries.push({
        shortcutId: shortcut.id,
        icon: preparedIcon
      });
    });
    this.icons = this.mergeIconStates(
      preparedEntries.map((entry: ResolvedShortcutIconEntry): HomeShortcutIconState => {
        return this.toHomeShortcutIconState(entry.shortcutId, entry.icon);
      }),
      activeShortcutIds
    );
    preparedEntries.forEach((entry: ResolvedShortcutIconEntry): void => {
      const shortcut = shortcuts.find((item: ShortcutRecord): boolean => item.id === entry.shortcutId);
      if (shortcut !== undefined) {
        callbacks.persistResolvedIcon(entry.shortcutId, shortcut.url, entry.icon.path);
      }
    });
    hilog.info(
      FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
      FAVICON_COLDSTART_DIAGNOSTIC_TAG,
      '[DEBUG-FAVICON-COLDSTART] hydration_prepared shortcuts=%{public}d cachedPixelMaps=%{public}d durationMs=%{public}d',
      shortcuts.length,
      preparedEntries.length,
      Date.now() - startedAt
    );
    return this.buildSnapshot();
  }

  clear(callbacks: HomeShortcutIconHydrationCallbacks): void {
    this.nextResolveToken();
    this.icons = [];
    this.lastResolveSignature = '';
    this.activeShortcuts = [];
    this.activeCallbacks = undefined;
    this.latestIconUpdateTokens = [];
    this.disposeIconUpdates();
    callbacks.applySnapshot(this.buildSnapshot());
  }

  resolveFor(
    shortcuts: ShortcutRecord[],
    callbacks: HomeShortcutIconHydrationCallbacks,
    publicationMode: HomeShortcutIconHydrationPublicationMode = 'progressive'
  ): Promise<void> {
    const startedAt = Date.now();
    if (shortcuts.length === 0) {
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] hydration_empty mode=%{public}s durationMs=%{public}d',
        publicationMode,
        0
      );
      this.clear(callbacks);
      return Promise.resolve();
    }

    this.activeShortcuts = shortcuts.slice();
    this.activeCallbacks = callbacks;
    this.latestIconUpdateTokens = [];

    const resolveSignature = this.buildResolveSignature(shortcuts);
    const hasProvisionalPreparedIcons = shortcuts.some((shortcut: ShortcutRecord) => {
      return this.shortcutIconResolver.shouldRefreshPersistedShortcutIcon(shortcut);
    });
    if (resolveSignature === this.lastResolveSignature && !hasProvisionalPreparedIcons) {
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] hydration_skip shortcuts=%{public}d mode=%{public}s durationMs=%{public}d',
        shortcuts.length,
        publicationMode,
        Date.now() - startedAt
      );
      return Promise.resolve();
    }
    this.lastResolveSignature = resolveSignature;

    const token = this.nextResolveToken();
    this.ensureIconUpdateSubscriptions();
    const activeShortcutIds = shortcuts.map((shortcut: ShortcutRecord) => shortcut.id);
    const activeIconStates: HomeShortcutIconState[] = [];
    const pendingShortcuts: ShortcutRecord[] = [];
    let persistedCount = 0;
    let existingCount = 0;
    let memoryCount = 0;
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      const persistedIcon = this.shortcutIconResolver.getPersistedShortcutIcon(shortcut);
      if (persistedIcon !== undefined) {
        persistedCount += 1;
        activeIconStates.push(this.toHomeShortcutIconState(shortcut.id, persistedIcon));
        if (this.shortcutIconResolver.shouldResolveShortcutIcon(shortcut)) {
          pendingShortcuts.push(shortcut);
        }
        return;
      }
      const existingIcon = this.icons.find((item: HomeShortcutIconState) => item.id === shortcut.id);
      if (existingIcon !== undefined) {
        existingCount += 1;
        activeIconStates.push(existingIcon);
        return;
      }
      const memoryIcon = this.shortcutIconResolver.getCachedShortcutIcon(shortcut);
      if (memoryIcon !== undefined) {
        memoryCount += 1;
        activeIconStates.push(this.toHomeShortcutIconState(shortcut.id, memoryIcon));
        return;
      }
      if (this.shortcutIconResolver.shouldResolveShortcutIcon(shortcut)) {
        pendingShortcuts.push(shortcut);
      }
    });

    this.icons = this.mergeIconStates(activeIconStates, activeShortcutIds);
    if (publicationMode === 'progressive') {
      callbacks.applySnapshot(this.buildSnapshot());
    }
    hilog.info(
      FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
      FAVICON_COLDSTART_DIAGNOSTIC_TAG,
      '[DEBUG-FAVICON-COLDSTART] hydration_classified shortcuts=%{public}d persisted=%{public}d existing=%{public}d memory=%{public}d pending=%{public}d mode=%{public}s durationMs=%{public}d',
      shortcuts.length,
      persistedCount,
      existingCount,
      memoryCount,
      pendingShortcuts.length,
      publicationMode,
      Date.now() - startedAt
    );
    return this.resolvePendingIcons(token, pendingShortcuts, callbacks, publicationMode)
      .then((): void => {
        hilog.info(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] hydration_local_settled shortcuts=%{public}d pending=%{public}d durationMs=%{public}d',
          shortcuts.length,
          pendingShortcuts.length,
          Date.now() - startedAt
        );
      });
  }

  private resolvePendingIcons(
    token: number,
    pendingShortcuts: ShortcutRecord[],
    callbacks: HomeShortcutIconHydrationCallbacks,
    publicationMode: HomeShortcutIconHydrationPublicationMode
  ): Promise<void> {
    if (pendingShortcuts.length <= 0) {
      if (publicationMode === 'settled') {
        callbacks.applySnapshot(this.buildSnapshot());
      }
      return Promise.resolve();
    }
    const cacheStartedAt = Date.now();
    return this.shortcutIconResolver.resolveCachedShortcutIcons(pendingShortcuts)
      .then((cachedEntries: ResolvedShortcutIconEntry[]) => {
        if (!this.isCurrentToken(token)) {
          return;
        }
        const cachedShortcutIds: string[] = [];
        cachedEntries.forEach((entry: ResolvedShortcutIconEntry): void => {
          cachedShortcutIds.push(entry.shortcutId);
        });
        if (cachedEntries.length > 0) {
          this.applyResolvedEntries(token, cachedEntries, callbacks);
        }
        const remoteShortcuts = pendingShortcuts.filter((shortcut: ShortcutRecord): boolean => {
          return cachedShortcutIds.indexOf(shortcut.id) < 0;
        });

        if (publicationMode === 'settled' && cachedEntries.length <= 0) {
          callbacks.applySnapshot(this.buildSnapshot());
        }

        if (remoteShortcuts.length > 0) {
          // Remote discovery must not delay the first homepage render.
          void this.resolveRemoteIcons(token, remoteShortcuts, callbacks)
            .catch((_error: Error): void => {
            });
        }
        hilog.info(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] cache_phase_done requested=%{public}d cached=%{public}d remote=%{public}d durationMs=%{public}d',
          pendingShortcuts.length,
          cachedEntries.length,
          remoteShortcuts.length,
          Date.now() - cacheStartedAt
        );
      })
      .catch((_error: Error) => {
        hilog.warn(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] cache_phase_failed requested=%{public}d durationMs=%{public}d',
          pendingShortcuts.length,
          Date.now() - cacheStartedAt
        );
        if (publicationMode === 'settled' && this.isCurrentToken(token)) {
          callbacks.applySnapshot(this.buildSnapshot());
        }
      });
  }

  private resolveRemoteIcons(
    token: number,
    shortcuts: ShortcutRecord[],
    callbacks: HomeShortcutIconHydrationCallbacks
  ): Promise<void> {
    if (shortcuts.length <= 0) {
      return Promise.resolve();
    }

    const remoteStartedAt = Date.now();
    hilog.info(
      FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
      FAVICON_COLDSTART_DIAGNOSTIC_TAG,
      '[DEBUG-FAVICON-COLDSTART] remote_phase_start count=%{public}d concurrency=%{public}d',
      shortcuts.length,
      Math.min(HOME_SHORTCUT_ICON_REMOTE_MAX_CONCURRENCY, shortcuts.length)
    );
    let nextIndex: number = 0;
    const worker = async (): Promise<void> => {
      while (this.isCurrentToken(token)) {
        const index = nextIndex;
        nextIndex += 1;
        if (index >= shortcuts.length) {
          return;
        }
        const shortcut = shortcuts[index];
        const itemStartedAt = Date.now();
        let resolved = false;
        hilog.info(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] remote_item_start index=%{public}d total=%{public}d',
          index,
          shortcuts.length
        );
        try {
          const resolvedIcon = await this.shortcutIconResolver.resolveShortcutIcon(shortcut);
          if (this.isCurrentToken(token) && resolvedIcon !== undefined) {
            this.applyResolvedEntries(token, [{
              shortcutId: shortcut.id,
              icon: resolvedIcon
            }], callbacks);
            resolved = true;
          }
        } catch (_error) {
        }
        hilog.info(
          FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
          FAVICON_COLDSTART_DIAGNOSTIC_TAG,
          '[DEBUG-FAVICON-COLDSTART] remote_item_done index=%{public}d resolved=%{public}s durationMs=%{public}d',
          index,
          `${resolved}`,
          Date.now() - itemStartedAt
        );
      }
    };
    const workerCount = Math.min(HOME_SHORTCUT_ICON_REMOTE_MAX_CONCURRENCY, shortcuts.length);
    const workers: Promise<void>[] = [];
    for (let index = 0; index < workerCount; index += 1) {
      workers.push(worker());
    }
    return Promise.all(workers).then(() => {
      hilog.info(
        FAVICON_COLDSTART_DIAGNOSTIC_DOMAIN,
        FAVICON_COLDSTART_DIAGNOSTIC_TAG,
        '[DEBUG-FAVICON-COLDSTART] remote_phase_done count=%{public}d durationMs=%{public}d',
        shortcuts.length,
        Date.now() - remoteStartedAt
      );
    });
  }

  private applyResolvedEntries(
    token: number,
    entries: ResolvedShortcutIconEntry[],
    callbacks: HomeShortcutIconHydrationCallbacks
  ): void {
    if (!this.isCurrentToken(token) || entries.length === 0) {
      return;
    }
    const activeShortcutIds = this.activeShortcuts.map((shortcut: ShortcutRecord) => shortcut.id);
    const resolvedStates = entries.map((entry: ResolvedShortcutIconEntry) => {
      return this.toHomeShortcutIconState(entry.shortcutId, entry.icon);
    });
    this.icons = this.mergeIconStates(resolvedStates, activeShortcutIds);
    callbacks.applySnapshot(this.buildSnapshot());
    entries.forEach((entry: ResolvedShortcutIconEntry) => {
      const shortcut = this.activeShortcuts.find((item: ShortcutRecord): boolean => {
        return item.id === entry.shortcutId;
      });
      if (shortcut !== undefined) {
        callbacks.persistResolvedIcon(entry.shortcutId, shortcut.url, entry.icon.path);
      }
    });
  }

  private ensureIconUpdateSubscriptions(): void {
    if (this.unsubscribeSiteIconUpdates === undefined) {
      this.unsubscribeSiteIconUpdates = SiteIconUpdateCenter.subscribe((update: SiteIconDomainUpdate): void => {
        this.applySiteIconDomainUpdate(update);
      });
    }
    if (this.unsubscribeShortcutAssociationUpdates === undefined) {
      this.unsubscribeShortcutAssociationUpdates = HomeShortcutIconAssociationUpdateCenter.subscribe(
        (update: HomeShortcutIconAssociationUpdate): void => {
          this.applyShortcutAssociationUpdate(update);
        }
      );
    }
  }

  private disposeIconUpdates(): void {
    const unsubscribeSiteIconUpdates = this.unsubscribeSiteIconUpdates;
    if (unsubscribeSiteIconUpdates !== undefined) {
      unsubscribeSiteIconUpdates();
      this.unsubscribeSiteIconUpdates = undefined;
    }
    const unsubscribeShortcutAssociationUpdates = this.unsubscribeShortcutAssociationUpdates;
    if (unsubscribeShortcutAssociationUpdates !== undefined) {
      unsubscribeShortcutAssociationUpdates();
      this.unsubscribeShortcutAssociationUpdates = undefined;
    }
  }

  private applySiteIconDomainUpdate(update: SiteIconDomainUpdate): void {
    const callbacks = this.activeCallbacks;
    const domain = update.domain.trim().toLowerCase();
    const sourceIconPath = update.uri.trim();
    if (callbacks === undefined || domain.length === 0 || sourceIconPath.length === 0) {
      return;
    }
    const matchingShortcuts = this.activeShortcuts.filter((shortcut: ShortcutRecord) => {
      return this.shortcutIconResolver.shouldResolveShortcutIcon(shortcut) &&
        this.shortcutIconResolver.resolveShortcutDomain(shortcut.url) === domain;
    });
    if (matchingShortcuts.length === 0) {
      return;
    }
    this.resolveSharedIconUpdates(matchingShortcuts, sourceIconPath);
  }

  private applyShortcutAssociationUpdate(update: HomeShortcutIconAssociationUpdate): void {
    const callbacks = this.activeCallbacks;
    const shortcutId = update.shortcutId.trim();
    const sourceIconPath = update.iconUri.trim();
    const sourceUrl = normalizeUrl(update.sourceUrl).trim();
    if (callbacks === undefined || shortcutId.length === 0 || sourceIconPath.length === 0 || sourceUrl.length === 0) {
      return;
    }
    const shortcut = this.activeShortcuts.find((item: ShortcutRecord) => item.id === shortcutId);
    if (shortcut === undefined || normalizeUrl(shortcut.url).trim() !== sourceUrl ||
      !this.shortcutIconResolver.shouldResolveShortcutIcon(shortcut)) {
      return;
    }
    this.resolveSharedIconUpdates([shortcut], sourceIconPath);
  }

  private resolveSharedIconUpdates(
    shortcuts: ShortcutRecord[],
    sourceIconPath: string
  ): void {
    if (shortcuts.length === 0 || sourceIconPath.trim().length === 0) {
      return;
    }
    const resolveToken = this.resolveGeneration;
    const iconUpdateTokens = shortcuts.map((shortcut: ShortcutRecord) => {
      return this.nextIconUpdateToken(shortcut.id);
    });
    const tasks: Promise<ResolvedShortcutIconEntry | undefined>[] = shortcuts.map((shortcut: ShortcutRecord) => {
      return this.shortcutIconResolver.resolveSharedShortcutIconUpdate(shortcut, sourceIconPath)
        .then((icon: ResolvedShortcutIcon | undefined): ResolvedShortcutIconEntry | undefined => {
          if (icon === undefined) {
            return undefined;
          }
          return {
            shortcutId: shortcut.id,
            icon: icon
          };
        });
    });
    Promise.all(tasks)
      .then((resolvedEntries: (ResolvedShortcutIconEntry | undefined)[]) => {
        if (!this.isCurrentToken(resolveToken)) {
          return;
        }
        const entries: ResolvedShortcutIconEntry[] = [];
        resolvedEntries.forEach((entry: ResolvedShortcutIconEntry | undefined, index: number) => {
          const shortcut = shortcuts[index];
          if (entry !== undefined &&
            this.isCurrentIconUpdateToken(shortcut.id, iconUpdateTokens[index])) {
            entries.push(entry);
          }
        });
        const currentCallbacks = this.activeCallbacks;
        if (currentCallbacks === undefined) {
          return;
        }
        this.applyResolvedEntries(resolveToken, entries, currentCallbacks);
      })
      .catch((_error: Error) => {
      });
  }

  private nextIconUpdateToken(shortcutId: string): number {
    this.iconUpdateGeneration += 1;
    const token = this.iconUpdateGeneration;
    this.latestIconUpdateTokens = this.latestIconUpdateTokens
      .filter((entry: HomeShortcutIconUpdateToken) => entry.shortcutId !== shortcutId)
      .concat([{
        shortcutId: shortcutId,
        token: token
      }]);
    return token;
  }

  private isCurrentIconUpdateToken(shortcutId: string, token: number): boolean {
    const entry = this.latestIconUpdateTokens
      .find((item: HomeShortcutIconUpdateToken) => item.shortcutId === shortcutId);
    return entry !== undefined && entry.token === token;
  }

  private mergeIconStates(
    activeIconStates: HomeShortcutIconState[],
    activeShortcutIds: string[]
  ): HomeShortcutIconState[] {
    const nextStates = this.icons.filter((item: HomeShortcutIconState) => {
      return activeShortcutIds.indexOf(item.id) >= 0;
    });
    activeIconStates.forEach((state: HomeShortcutIconState) => {
      const existingIndex = nextStates.findIndex((item: HomeShortcutIconState) => item.id === state.id);
      if (existingIndex >= 0) {
        const existingState = nextStates[existingIndex];
        const sourceChanged = existingState.path !== state.path || existingState.pixelMap !== state.pixelMap;
        state.revision = sourceChanged ? (existingState.revision ?? 0) + 1 : (existingState.revision ?? 1);
        nextStates[existingIndex] = state;
      } else {
        state.revision = 1;
        nextStates.push(state);
      }
    });
    return nextStates;
  }

  private toHomeShortcutIconState(shortcutId: string, icon: ResolvedShortcutIcon): HomeShortcutIconState {
    return {
      id: shortcutId,
      path: icon.path,
      backgroundColor: '',
      pixelMap: icon.pixelMap,
      revision: 0
    };
  }

  private buildSnapshot(): HomeShortcutIconHydrationSnapshot {
    return {
      icons: this.icons.slice()
    };
  }

  private nextResolveToken(): number {
    this.resolveGeneration += 1;
    return this.resolveGeneration;
  }

  private isCurrentToken(token: number): boolean {
    return token === this.resolveGeneration;
  }

  private buildResolveSignature(shortcuts: ShortcutRecord[]): string {
    const parts: string[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      parts.push(`${shortcut.id}|${shortcut.url.trim()}|${(shortcut.icon ?? '').trim()}`);
    });
    return parts.join('\n');
  }
}
