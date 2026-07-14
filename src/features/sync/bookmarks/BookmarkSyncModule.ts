import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import { LeafTabSyncAiraCloudStore } from '@/sync/leaftab/airaCloudStore';
import { LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY } from '@/features/sync/app/leafTabSyncStorageKeys';
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
import type {
  LeafTabSyncOperation,
  LeafTabSyncRemoteStore,
} from '@/sync/leaftab/remoteStore';
import type { LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
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
  local: LeafTabSyncDataSummary;
  remote: LeafTabSyncDataSummary;
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
      desktopPushToken: string;
    }
  | {
      source: 'webdav';
      webdav: LeafTabSyncWebdavStoreConfig;
    };

export interface BookmarkSyncLocalAdapter {
  buildSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applySnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  hasPendingChanges?: () => boolean;
  hasPendingOperations?: () => boolean | Promise<boolean>;
  clearPendingChanges?: () => void;
  buildPendingOperations?: (baseSnapshot: LeafTabSyncSnapshot) => Promise<LeafTabSyncOperation[] | null>;
  clearPendingOperations?: () => Promise<void> | void;
  createEmptySnapshot: () => LeafTabSyncSnapshot;
}

export interface BookmarkSyncModuleConfig {
  sourceConfig: BookmarkSyncSourceConfig;
  deviceId: string;
  rootPath: string;
  baselineStorageKey: string;
  local: BookmarkSyncLocalAdapter;
  persistSelectedSource?: (source: BookmarkSyncSource) => Promise<void> | void;
}

export interface BookmarkSyncRunOptions {
  localSnapshotOverride?: LeafTabSyncSnapshot;
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  conflictChoice?: BookmarkSyncConflictChoice;
}

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
    return engine.sync('auto', {
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
      hasPendingLocalOperationOutbox: this.config.local.hasPendingOperations,
    });
  }

  async readSummary(): Promise<BookmarkSyncDataOverview> {
    const analysis = await this.createEngine().analyze();
    return {
      local: analysis.localSummary,
      remote: analysis.remoteSummary,
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
    return engine.sync('auto', {
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
      hasPendingLocalChanges: local.hasPendingChanges,
      clearPendingLocalChanges: local.clearPendingChanges,
      buildPendingLocalOperations: local.buildPendingOperations,
      clearPendingLocalOperations: local.clearPendingOperations,
      createEmptySnapshot: local.createEmptySnapshot,
      rootPath: this.config.rootPath,
    });
  }

  private createRemoteStore(): LeafTabSyncRemoteStore {
    const sourceConfig = this.config.sourceConfig;
    return sourceConfig.source === 'aira-cloud'
      ? new LeafTabSyncAiraCloudStore(sourceConfig.uid, sourceConfig.desktopPushToken)
      : new LeafTabSyncWebdavStore(sourceConfig.webdav);
  }
}
