import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import { LeafTabSyncAiraCloudStore } from '@/sync/leaftab/airaCloudStore';
import {
  captureLeafTabBookmarkTreeDraft,
  replaceLeafTabBookmarkTree,
} from '@/sync/leaftab/bookmarks';
import {
  createLeafTabSyncBaselineStorageKey,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  readAllExtensionStorageRecords,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  LeafTabSyncEngine,
  type LeafTabSyncDataSummary,
  type LeafTabSyncEngineProgress,
  type LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import type { LeafTabSyncConflictResolution } from '@/sync/leaftab/merge';
import type { LeafTabSyncRemoteStore } from '@/sync/leaftab/remoteStore';
import {
  LEAFTAB_SYNC_SCHEMA_VERSION,
  normalizeLeafTabSyncSnapshot,
  type LeafTabSyncSnapshot,
} from '@/sync/leaftab/schema';
import {
  buildLeafTabSyncSnapshot,
  countLeafTabLiveBookmarkEntities,
  createLeafTabSyncBuildState,
  normalizeLeafTabLiveBookmarkSnapshot,
} from '@/sync/leaftab/snapshot';
import type {
  LeafTabPendingBookmarkConflict,
  LeafTabSyncRemoteKind,
} from '@/sync/leaftab/source';
import {
  LeafTabSyncWebdavStore,
  type LeafTabSyncWebdavStoreConfig,
} from '@/sync/leaftab/webdavStore';

export type BookmarkSyncSource = LeafTabSyncRemoteKind;
export type BookmarkSyncConflictChoice = 'computer' | 'current-source';

export type BookmarkSyncPendingConflict = LeafTabPendingBookmarkConflict;

export type BookmarkSyncDataOverview = {
  local: LeafTabSyncDataSummary | null;
  remote: LeafTabSyncDataSummary | null;
};

const normalizePendingConflict = (value: unknown): BookmarkSyncPendingConflict | null => {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as Partial<BookmarkSyncPendingConflict>;
  if (candidate.provider !== 'aira-cloud' && candidate.provider !== 'webdav') return null;
  return {
    provider: candidate.provider,
    detectedAt: String(candidate.detectedAt || ''),
    remoteCommitId: String(candidate.remoteCommitId || ''),
    summary: String(candidate.summary || '检测到书签同步冲突'),
  };
};

const setConflictBadge = async (pending: boolean) => {
  const action = globalThis.chrome?.action;
  if (!action?.setBadgeText) return;
  await action.setBadgeText({ text: pending ? '!' : '' });
  if (pending && action.setBadgeBackgroundColor) {
    await action.setBadgeBackgroundColor({ color: '#d97706' });
  }
};

export const readPendingBookmarkConflict = async (): Promise<BookmarkSyncPendingConflict | null> => {
  const record = await readAllExtensionStorageRecords();
  return normalizePendingConflict(record[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]);
};

export const persistPendingBookmarkConflict = async (
  provider: BookmarkSyncSource,
  result: LeafTabSyncEngineResult,
): Promise<BookmarkSyncPendingConflict> => {
  const pending: BookmarkSyncPendingConflict = {
    provider,
    detectedAt: new Date().toISOString(),
    remoteCommitId: result.remoteCommitId || '',
    summary: result.summaryText || '检测到书签同步冲突',
  };
  await writeExtensionStorageRecord({
    [LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]: pending,
  });
  await setConflictBadge(true);
  return pending;
};

export const clearPendingBookmarkConflict = async (): Promise<void> => {
  await removeExtensionStorageKeys([LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]);
  await setConflictBadge(false);
};

export type BookmarkSyncRuntimeProvider =
  | {
      remoteKind: 'aira-cloud';
      uid: string;
      deviceCredential: string;
    }
  | {
      remoteKind: 'webdav';
      url: string;
      username?: string;
      password?: string;
      requestPermission?: boolean;
      requestTimeoutMs?: number;
    };

const createBookmarkSyncSourceIdentity = (
  provider: BookmarkSyncRuntimeProvider,
  rootPath: string,
): string => {
  const normalizedRootPath = String(rootPath || '').trim().replace(/^\/+/, '').replace(/\/+$/, '');
  if (provider.remoteKind === 'aira-cloud') {
    return `aira-cloud:${String(provider.uid || '').trim()}:${normalizedRootPath}`;
  }
  return [
    'webdav',
    String(provider.url || '').trim().replace(/\/+$/, ''),
    String(provider.username || '').trim(),
    normalizedRootPath,
  ].join(':');
};

export interface BookmarkSyncLocalAdapter {
  buildSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applySnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  readPendingChanges?: () => Promise<number>;
  clearPendingChanges?: (expectedChangedAt: number) => Promise<void> | void;
}

interface BookmarkSyncModuleConfig {
  provider: BookmarkSyncRuntimeProvider;
  deviceId: string;
  rootPath: string;
  baselineStorageKey: string;
  local: BookmarkSyncLocalAdapter;
  persistSelectedSource?: (source: BookmarkSyncSource) => Promise<void> | void;
}

export interface BookmarkSyncRuntimeLocalAdapter {
  buildSnapshot: (baselineStorageKey: string) => Promise<LeafTabSyncSnapshot>;
  applySnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  readPendingChanges?: () => Promise<number>;
  clearPendingChanges?: (expectedChangedAt: number) => Promise<void> | void;
}

export interface BookmarkSyncBrowserLocalAdapterConfig {
  deviceId: string;
  requestPermission: boolean;
  invalidRootOrderMessage: string;
  readPendingChanges?: () => Promise<number>;
  clearPendingChanges?: (expectedChangedAt: number) => Promise<void> | void;
}

export interface BookmarkSyncRuntimeConfig {
  provider: BookmarkSyncRuntimeProvider;
  deviceId: string;
  rootPath: string;
  local: BookmarkSyncRuntimeLocalAdapter;
  persistSelectedSource?: (source: BookmarkSyncSource) => Promise<void> | void;
}

export interface BookmarkSyncRuntime {
  module: BookmarkSyncModule;
  baselineStorageKey: string;
  sourceIdentity: string;
}

export interface BookmarkSyncRunOptions {
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  conflictChoice?: BookmarkSyncConflictChoice;
}

export const createBookmarkSyncBrowserLocalAdapter = (
  config: BookmarkSyncBrowserLocalAdapterConfig,
): BookmarkSyncRuntimeLocalAdapter => ({
  async buildSnapshot(baselineStorageKey: string): Promise<LeafTabSyncSnapshot> {
    const bookmarkTree = await captureLeafTabBookmarkTreeDraft({
      requestPermission: config.requestPermission,
      throwOnPermissionDenied: true,
    });
    const baseline = await new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey).load();
    const previousSnapshot = normalizeLeafTabSyncSnapshot(baseline?.snapshot || null);
    const generatedAt = new Date().toISOString();
    const state = createLeafTabSyncBuildState({
      previousSnapshot,
      bookmarkTree,
      deviceId: config.deviceId,
      generatedAt,
    });
    return buildLeafTabSyncSnapshot({
      bookmarkTree,
      deviceId: config.deviceId,
      generatedAt,
      state,
    });
  },
  async applySnapshot(snapshot: LeafTabSyncSnapshot): Promise<void> {
    const liveSnapshot = normalizeLeafTabLiveBookmarkSnapshot(snapshot);
    const hasRemoteBookmarks = Object.keys(liveSnapshot.bookmarkFolders).length > 0
      || Object.keys(liveSnapshot.bookmarkItems).length > 0;
    const hasRootOrder = Object.values(liveSnapshot.bookmarkOrders).some((order) => (
      order.parentId === 'browser_root_toolbar'
      || order.parentId === 'browser_root_other'
      || order.parentId === null
    ));
    if (hasRemoteBookmarks && !hasRootOrder) {
      throw new Error(config.invalidRootOrderMessage);
    }
    const applied = await replaceLeafTabBookmarkTree({
        folderLookup: Object.fromEntries(
          Object.values(liveSnapshot.bookmarkFolders).map((folder) => [folder.id, {
            title: folder.title,
            parentId: folder.parentId,
          }]),
        ),
        itemLookup: Object.fromEntries(
          Object.values(liveSnapshot.bookmarkItems).map((item) => [item.id, {
            title: item.title,
            parentId: item.parentId,
            url: item.url,
          }]),
        ),
        orderIdsByParent: Object.fromEntries(
          Object.entries(liveSnapshot.bookmarkOrders).map(([key, order]) => [key, order.ids.slice()]),
        ),
        tombstoneIds: Object.keys(snapshot.tombstones || {}),
        requestPermission: false,
    });
    if (!applied) {
      throw new Error('未授予书签权限，无法写入本地书签');
    }
  },
  readPendingChanges: config.readPendingChanges,
  clearPendingChanges: config.clearPendingChanges,
});

export interface BookmarkSyncReadSummaryOptions {
  includeRemote?: boolean;
}

const createEmptyBookmarkSyncSnapshot = (deviceId: string): LeafTabSyncSnapshot => ({
  meta: {
    version: LEAFTAB_SYNC_SCHEMA_VERSION,
    deviceId,
    generatedAt: new Date(0).toISOString(),
  },
  bookmarkFolders: {},
  bookmarkItems: {},
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: [],
      updatedAt: new Date(0).toISOString(),
      updatedBy: deviceId,
      revision: 1,
    },
  },
  tombstones: {},
});

export const createBookmarkSyncRuntime = (config: BookmarkSyncRuntimeConfig): BookmarkSyncRuntime => {
  const baselineStorageKey = createLeafTabSyncBaselineStorageKey(
    config.provider,
    config.rootPath,
  );
  const module = new BookmarkSyncModule({
    provider: config.provider,
    deviceId: config.deviceId,
    rootPath: config.rootPath,
    baselineStorageKey,
    local: {
      buildSnapshot: () => config.local.buildSnapshot(baselineStorageKey),
      applySnapshot: config.local.applySnapshot,
      readPendingChanges: config.local.readPendingChanges,
      clearPendingChanges: config.local.clearPendingChanges,
    },
    persistSelectedSource: config.persistSelectedSource,
  });
  return {
    module,
    baselineStorageKey,
    sourceIdentity: createBookmarkSyncSourceIdentity(config.provider, config.rootPath),
  };
};

export class BookmarkSyncModule {
  private readonly config: BookmarkSyncModuleConfig;

  constructor(config: BookmarkSyncModuleConfig) {
    this.config = config;
  }

  async syncAndSelectSource(options: BookmarkSyncRunOptions): Promise<LeafTabSyncEngineResult> {
    if (!this.config.persistSelectedSource) {
      throw new Error('当前调用方没有提供同步方式选择 adapter。');
    }

    const result = options.conflictChoice
      ? await this.resolveConflict(options.conflictChoice, options)
      : await this.sync(options);
    if (result.kind === 'conflict') {
      return result;
    }
    await this.config.persistSelectedSource(this.config.provider.remoteKind);
    return result;
  }

  sync(options: BookmarkSyncRunOptions): Promise<LeafTabSyncEngineResult> {
    const engine = this.createEngine();
    return engine.sync({
      onProgress: options.onProgress,
    });
  }

  async readSummary(options: BookmarkSyncReadSummaryOptions = {}): Promise<BookmarkSyncDataOverview> {
    const remoteSummaryPromise: Promise<LeafTabSyncDataSummary | null> = options.includeRemote === false
      ? Promise.resolve(null)
      : this.readRemoteSummary();
    const [localResult, remoteResult] = await Promise.allSettled([
      this.config.local.buildSnapshot().then((snapshot) => countLeafTabLiveBookmarkEntities(snapshot)),
      remoteSummaryPromise,
    ]);
    return {
      local: localResult.status === 'fulfilled' ? localResult.value : null,
      remote: remoteResult.status === 'fulfilled' ? remoteResult.value : null,
    };
  }

  resolveConflict(
    choice: BookmarkSyncConflictChoice,
    options: BookmarkSyncRunOptions,
  ): Promise<LeafTabSyncEngineResult> {
    const conflictResolution: LeafTabSyncConflictResolution = choice === 'computer'
      ? 'prefer-local'
      : 'prefer-remote';
    const engine = this.createEngine();
    return engine.sync({
      onProgress: options.onProgress,
      conflictResolution,
    });
  }

  private createEngine(): LeafTabSyncEngine {
    const local = this.config.local;
    return new LeafTabSyncEngine({
      deviceId: this.config.deviceId,
      remoteStore: this.createRemoteStore(),
      baselineStore: new LeafTabSyncExtensionStorageBaselineStore(this.config.baselineStorageKey),
      buildLocalSnapshot: local.buildSnapshot,
      applyLocalSnapshot: local.applySnapshot,
      readPendingLocalChanges: local.readPendingChanges,
      clearPendingLocalChanges: local.clearPendingChanges,
      createEmptySnapshot: () => createEmptyBookmarkSyncSnapshot(this.config.deviceId),
    });
  }

  private async readRemoteSummary(): Promise<LeafTabSyncDataSummary> {
    const remoteStore = this.createRemoteStore();
    if (remoteStore.readHead) {
      const remoteHead = await remoteStore.readHead();
      const headSummary = remoteHead.summary;
      if (headSummary) {
        return {
          bookmarkFolders: Number(headSummary.bookmarkFolders || 0),
          bookmarkItems: Number(headSummary.bookmarkItems || 0),
          tombstones: Number(headSummary.tombstones || 0),
        };
      }
      if (!remoteHead.commitId) {
        return countLeafTabLiveBookmarkEntities(null);
      }
    }
    const remoteState = await remoteStore.readState();
    return countLeafTabLiveBookmarkEntities(remoteState.snapshot);
  }

  private createRemoteStore(): LeafTabSyncRemoteStore {
    const provider = this.config.provider;
    return provider.remoteKind === 'aira-cloud'
      ? new LeafTabSyncAiraCloudStore(provider.uid, provider.deviceCredential)
      : new LeafTabSyncWebdavStore({
          url: provider.url,
          username: provider.username,
          password: provider.password,
          rootPath: this.config.rootPath,
          requestPermission: provider.requestPermission,
          requestTimeoutMs: provider.requestTimeoutMs,
        } satisfies LeafTabSyncWebdavStoreConfig);
  }
}
