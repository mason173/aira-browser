import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import { LeafTabSyncAiraCloudStore } from '@/sync/leaftab/airaCloudStore';
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
import {
  probeLeafTabBookmarkSyncChanges,
  type LeafTabBookmarkSyncChangeProbeResult,
} from '@/sync/leaftab/changeProbe';
import type { LeafTabSyncRemoteStore } from '@/sync/leaftab/remoteStore';
import { LEAFTAB_SYNC_SCHEMA_VERSION, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { countLeafTabLiveBookmarkEntities } from '@/sync/leaftab/snapshot';
import {
  buildLeafTabPendingLocalOperationsFromOutbox,
  clearLeafTabLocalBookmarkOperationOutbox,
  hasPendingLeafTabLocalBookmarkOperationOutbox,
} from '@/sync/leaftab/localOperationOutbox';
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

export type BookmarkSyncSourceConfig =
  | {
      source: 'aira-cloud';
      uid: string;
      deviceCredential: string;
    }
  | {
      source: 'webdav';
      webdav: LeafTabSyncWebdavStoreConfig;
    };

export const createBookmarkSyncSourceIdentity = (
  sourceConfig: BookmarkSyncSourceConfig,
  rootPath: string,
): string => {
  const normalizedRootPath = String(rootPath || '').trim();
  if (sourceConfig.source === 'aira-cloud') {
    return `aira-cloud:${String(sourceConfig.uid || '').trim()}:${normalizedRootPath}`;
  }
  return [
    'webdav',
    String(sourceConfig.webdav.url || '').trim(),
    String(sourceConfig.webdav.username || '').trim(),
    String(sourceConfig.webdav.rootPath || normalizedRootPath).trim(),
  ].join(':');
};

export interface BookmarkSyncLocalAdapter {
  buildSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applySnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  hasPendingChanges?: () => boolean;
  clearPendingChanges?: () => void;
}

export interface BookmarkSyncModuleConfig {
  sourceConfig: BookmarkSyncSourceConfig;
  deviceId: string;
  rootPath: string;
  baselineStorageKey: string;
  local: BookmarkSyncLocalAdapter;
  persistSelectedSource?: (source: BookmarkSyncSource) => Promise<void> | void;
}

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

export interface BookmarkSyncRuntimeLocalAdapter {
  buildSnapshot: (baselineStorageKey: string) => Promise<LeafTabSyncSnapshot>;
  applySnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  hasPendingChanges?: () => boolean;
  clearPendingChanges?: () => void;
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
  localSnapshotOverride?: LeafTabSyncSnapshot;
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  conflictChoice?: BookmarkSyncConflictChoice;
}

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

export const resolveBookmarkSyncBaselineStorageKey = (
  remoteKind: BookmarkSyncSource,
  rootPath: string,
  cloudUid: string = '',
): string => createLeafTabSyncBaselineStorageKey(remoteKind, rootPath, cloudUid);

export const createBookmarkSyncRuntime = (config: BookmarkSyncRuntimeConfig): BookmarkSyncRuntime => {
  const sourceConfig: BookmarkSyncSourceConfig = config.provider.remoteKind === 'aira-cloud'
    ? {
        source: 'aira-cloud',
        uid: config.provider.uid,
        deviceCredential: config.provider.deviceCredential,
      }
    : {
        source: 'webdav',
        webdav: {
          url: config.provider.url,
          username: config.provider.username,
          password: config.provider.password,
          rootPath: config.rootPath,
          requestPermission: config.provider.requestPermission,
          requestTimeoutMs: config.provider.requestTimeoutMs,
        },
      };
  const baselineStorageKey = resolveBookmarkSyncBaselineStorageKey(
    config.provider.remoteKind,
    config.rootPath,
    config.provider.remoteKind === 'aira-cloud' ? config.provider.uid : '',
  );
  const module = new BookmarkSyncModule({
    sourceConfig,
    deviceId: config.deviceId,
    rootPath: config.rootPath,
    baselineStorageKey,
    local: {
      buildSnapshot: () => config.local.buildSnapshot(baselineStorageKey),
      applySnapshot: config.local.applySnapshot,
      hasPendingChanges: config.local.hasPendingChanges,
      clearPendingChanges: config.local.clearPendingChanges,
    },
    persistSelectedSource: config.persistSelectedSource,
  });
  return {
    module,
    baselineStorageKey,
    sourceIdentity: createBookmarkSyncSourceIdentity(sourceConfig, config.rootPath),
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
    await this.config.persistSelectedSource(this.config.sourceConfig.source);
    return result;
  }

  sync(options: BookmarkSyncRunOptions): Promise<LeafTabSyncEngineResult> {
    const engine = this.createEngine();
    return engine.sync({
      localSnapshotOverride: options.localSnapshotOverride,
      onProgress: options.onProgress,
    });
  }

  probeChanges(): Promise<LeafTabBookmarkSyncChangeProbeResult> {
    return probeLeafTabBookmarkSyncChanges({
      provider: this.config.sourceConfig.source,
      baselineStorageKey: this.config.baselineStorageKey,
      createRemoteStore: () => this.createRemoteStore(),
      hasPendingLocalChanges: this.config.local.hasPendingChanges || (() => false),
      hasPendingLocalOperationOutbox: hasPendingLeafTabLocalBookmarkOperationOutbox,
      readLocalSummary: async () => {
        const snapshot = await this.config.local.buildSnapshot();
        return {
          bookmarkFolders: Object.keys(snapshot.bookmarkFolders).length,
          bookmarkItems: Object.keys(snapshot.bookmarkItems).length,
        };
      },
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
      localSnapshotOverride: options.localSnapshotOverride,
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
      clearPendingLocalChanges: local.clearPendingChanges,
      buildPendingLocalOperations: (baseSnapshot: LeafTabSyncSnapshot) => (
        buildLeafTabPendingLocalOperationsFromOutbox({
          baseSnapshot,
          deviceId: this.config.deviceId,
        })
      ),
      clearPendingLocalOperations: clearLeafTabLocalBookmarkOperationOutbox,
      createEmptySnapshot: () => createEmptyBookmarkSyncSnapshot(this.config.deviceId),
      rootPath: this.config.rootPath,
    });
  }

  private async readRemoteSummary(): Promise<LeafTabSyncDataSummary> {
    const remoteStore = this.createRemoteStore();
    if (remoteStore.readHead) {
      const remoteHead = await remoteStore.readHead();
      const headSummary = remoteHead.summary || remoteHead.commit?.summary;
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
    const sourceConfig = this.config.sourceConfig;
    return sourceConfig.source === 'aira-cloud'
      ? new LeafTabSyncAiraCloudStore(sourceConfig.uid, sourceConfig.deviceCredential)
      : new LeafTabSyncWebdavStore(sourceConfig.webdav);
  }
}
