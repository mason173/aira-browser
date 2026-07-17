import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import type { LeafTabPendingBookmarkConflict, LeafTabSyncRemoteKind } from '@/features/sync/app/LeafTabSyncContracts';
import {
  refreshAiraDesktopConnectionProfileMembership,
  resolveAiraDesktopProCapability,
} from '@/features/desktop-connection/desktopConnectionProfile';
import {
  isAiraDesktopCredentialRejection,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  recordAiraDesktopConnectionFailure,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  writeAiraCloudSyncEnabled,
} from '@/features/sync/bookmarks/airaCloudPreferences';
import {
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import { WEBDAV_STORAGE_KEYS } from '@/utils/webdavConfig';
import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import type {
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { LeafTabSyncAiraCloudError } from '@/sync/leaftab/airaCloudStore';
import {
  clearPendingBookmarkConflict,
  createBookmarkSyncBrowserLocalAdapter,
  createBookmarkSyncRuntime,
  persistPendingBookmarkConflict,
  type BookmarkSyncConflictChoice,
  type BookmarkSyncDataOverview,
  type BookmarkSyncRuntimeProvider,
} from './BookmarkSyncModule';

export interface BookmarkSyncPopupWebdavConfig {
  url: string;
  username?: string;
  password?: string;
  requestPermission: boolean;
}

export interface BookmarkSyncPopupRuntimeConfig {
  deviceId: string;
  rootPath: string;
  cloudUid: string;
  cloudDeviceCredential: string;
  cloudSyncEnabled: boolean;
  webdavSyncEnabled: boolean;
  webdavConfig: BookmarkSyncPopupWebdavConfig | null;
  pendingConflict: LeafTabPendingBookmarkConflict | null;
}

export type BookmarkSyncPopupBlockedReason =
  | 'webdav-config-required'
  | 'cloud-login-required'
  | 'cloud-temporarily-unavailable'
  | 'cloud-pro-required'
  | 'source-disabled'
  | 'bookmarks-permission-required'
  | 'pending-conflict';

export interface BookmarkSyncPopupActionCallbacks {
  onRunStarted?: () => void;
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
}

type BookmarkSyncPopupOperation =
  | { type: 'sync-now' }
  | { type: 'select-source' }
  | { type: 'resolve-conflict'; choice: BookmarkSyncConflictChoice };

export type BookmarkSyncPopupRunOutcome =
  | {
      type: 'completed';
      result: LeafTabSyncEngineResult;
      overview: BookmarkSyncDataOverview;
    }
  | {
      type: 'conflict';
      result: LeafTabSyncEngineResult;
      pendingConflict: LeafTabPendingBookmarkConflict;
    }
  | {
      type: 'blocked';
      reason: BookmarkSyncPopupBlockedReason;
      message: string;
    }
  | {
      type: 'failed';
      error: unknown;
      message: string;
    };

export interface BookmarkSyncPopupOverviewResult {
  sourceIdentity: string;
  baselineOverview: BookmarkSyncDataOverview | null;
  overview: BookmarkSyncDataOverview | null;
}

const persistSelectedSyncSource = async (source: LeafTabSyncRemoteKind) => {
  await writeExtensionStorageRecord({
    [LEAFTAB_SELECTED_SYNC_SOURCE_KEY]: source,
  });
  localStorage.setItem(LEAFTAB_SELECTED_SYNC_SOURCE_KEY, source);
  window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
};

const readBaselineSnapshot = async (storageKey: string): Promise<LeafTabSyncSnapshot | null> => {
  try {
    const baselineStore = new LeafTabSyncExtensionStorageBaselineStore(storageKey);
    const baseline = await baselineStore.load();
    return normalizeLeafTabSyncSnapshot(baseline?.snapshot || null);
  } catch {
    return null;
  }
};

const createOverviewFromSummary = (summary: {
  bookmarkFolders: number;
  bookmarkItems: number;
  tombstones: number;
}): BookmarkSyncDataOverview => ({
  local: summary,
  remote: summary,
});

const createOverviewFromSnapshot = (snapshot: LeafTabSyncSnapshot): BookmarkSyncDataOverview => (
  createOverviewFromSummary({
    bookmarkFolders: Object.keys(snapshot.bookmarkFolders || {}).length,
    bookmarkItems: Object.keys(snapshot.bookmarkItems || {}).length,
    tombstones: Object.keys(snapshot.tombstones || {}).length,
  })
);

export class BookmarkSyncPopupRuntime {
  private readonly config: BookmarkSyncPopupRuntimeConfig;

  constructor(config: BookmarkSyncPopupRuntimeConfig) {
    this.config = config;
  }

  syncNow(
    remoteKind: LeafTabSyncRemoteKind,
    callbacks: BookmarkSyncPopupActionCallbacks = {},
  ): Promise<BookmarkSyncPopupRunOutcome> {
    return this.execute(remoteKind, { type: 'sync-now' }, callbacks);
  }

  selectSource(
    remoteKind: LeafTabSyncRemoteKind,
    callbacks: BookmarkSyncPopupActionCallbacks = {},
  ): Promise<BookmarkSyncPopupRunOutcome> {
    return this.execute(remoteKind, { type: 'select-source' }, callbacks);
  }

  resolveConflict(
    remoteKind: LeafTabSyncRemoteKind,
    choice: BookmarkSyncConflictChoice,
    callbacks: BookmarkSyncPopupActionCallbacks = {},
  ): Promise<BookmarkSyncPopupRunOutcome> {
    return this.execute(remoteKind, { type: 'resolve-conflict', choice }, callbacks);
  }

  private async execute(
    remoteKind: LeafTabSyncRemoteKind,
    operation: BookmarkSyncPopupOperation,
    callbacks: BookmarkSyncPopupActionCallbacks,
  ): Promise<BookmarkSyncPopupRunOutcome> {
    const blocked = await this.checkEligibility(remoteKind, operation);
    if (blocked) {
      return blocked;
    }
    const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
    if (!granted) {
      return {
        type: 'blocked',
        reason: 'bookmarks-permission-required',
        message: '未授予书签权限，无法同步书签',
      };
    }

    callbacks.onRunStarted?.();
    try {
      const runtime = this.createRuntime(remoteKind);
      const runOptions = { onProgress: callbacks.onProgress };
      const result = operation.type === 'sync-now'
        ? await runtime.module.sync(runOptions)
        : operation.type === 'select-source'
          ? await runtime.module.syncAndSelectSource(runOptions)
          : await runtime.module.syncAndSelectSource({
              ...runOptions,
              conflictChoice: operation.choice,
            });
      if (result.kind === 'conflict') {
        const pendingConflict = await persistPendingBookmarkConflict(remoteKind, result);
        return { type: 'conflict', result, pendingConflict };
      }

      if (!this.config.pendingConflict || this.config.pendingConflict.provider === remoteKind) {
        await clearPendingBookmarkConflict();
      }
      await this.markSuccess(remoteKind);
      if (operation.type !== 'sync-now') {
        await this.setSourceEnabled(remoteKind, true);
      }
      return {
        type: 'completed',
        result,
        overview: createOverviewFromSummary(result.snapshotSummary),
      };
    } catch (error) {
      await this.markError(remoteKind, error);
      if (remoteKind === 'aira-cloud') {
        await this.recordCloudCredentialFailure(error);
      }
      return {
        type: 'failed',
        error,
        message: String((error as Error)?.message || error || '同步失败'),
      };
    }
  }

  async readOverview(
    remoteKind: LeafTabSyncRemoteKind,
    includeRemote: boolean,
  ): Promise<BookmarkSyncPopupOverviewResult> {
    const runtime = this.createRuntime(remoteKind);
    const overviewPromise = runtime.module.readSummary({ includeRemote })
      .then((overview) => ({ overview }))
      .catch((error: unknown) => ({ error }));
    const baselineSnapshot = remoteKind === 'aira-cloud'
      ? await readBaselineSnapshot(runtime.baselineStorageKey)
      : null;
    const overviewResult = await overviewPromise;
    if ('error' in overviewResult) {
      if (remoteKind === 'aira-cloud') {
        await this.recordCloudCredentialFailure(overviewResult.error);
      }
      return {
        sourceIdentity: runtime.sourceIdentity,
        baselineOverview: baselineSnapshot ? createOverviewFromSnapshot(baselineSnapshot) : null,
        overview: null,
      };
    }
    return {
      sourceIdentity: runtime.sourceIdentity,
      baselineOverview: baselineSnapshot ? createOverviewFromSnapshot(baselineSnapshot) : null,
      overview: overviewResult.overview,
    };
  }

  private async checkEligibility(
    remoteKind: LeafTabSyncRemoteKind,
    operation: BookmarkSyncPopupOperation,
  ): Promise<Extract<BookmarkSyncPopupRunOutcome, { type: 'blocked' }> | null> {
    if (operation.type !== 'sync-now' && this.config.pendingConflict &&
      this.config.pendingConflict.provider !== remoteKind) {
      return {
        type: 'blocked',
        reason: 'pending-conflict',
        message: '请先处理当前书签同步冲突，再更改同步方式',
      };
    }
    if (remoteKind === 'webdav') {
      if (!this.config.webdavConfig?.url) {
        return {
          type: 'blocked',
          reason: 'webdav-config-required',
          message: '请先配置 WebDAV',
        };
      }
      if (operation.type === 'sync-now' && !this.config.webdavSyncEnabled) {
        return {
          type: 'blocked',
          reason: 'source-disabled',
          message: '请先开启 WebDAV 书签同步',
        };
      }
      return null;
    }
    if (!this.config.cloudUid || !this.config.cloudDeviceCredential) {
      return {
        type: 'blocked',
        reason: 'cloud-login-required',
        message: '请先连接 Aira 桌面设备',
      };
    }
    if (operation.type === 'sync-now' && !this.config.cloudSyncEnabled) {
      return {
        type: 'blocked',
        reason: 'source-disabled',
        message: '请先为当前 Aira 账号开启云书签同步',
      };
    }
    let capability;
    try {
      const latestProfile = await refreshAiraDesktopConnectionProfileMembership({ force: true });
      capability = resolveAiraDesktopProCapability(latestProfile);
    } catch {
      capability = 'temporarily-unavailable';
    }
    if (capability === 'login-required') {
      return {
        type: 'blocked',
        reason: 'cloud-login-required',
        message: 'Aira 桌面设备需要重新连接',
      };
    }
    if (capability === 'temporarily-unavailable') {
      return {
        type: 'blocked',
        reason: 'cloud-temporarily-unavailable',
        message: 'Aira 服务暂时不可用，请稍后再试',
      };
    }
    if (capability === 'pro-required') {
      return {
        type: 'blocked',
        reason: 'cloud-pro-required',
        message: 'Aira 云同步需要 Aira Pro',
      };
    }
    return null;
  }

  private createRuntime(remoteKind: LeafTabSyncRemoteKind, webdavRequestTimeoutMs?: number) {
    const provider: BookmarkSyncRuntimeProvider = remoteKind === 'aira-cloud'
      ? {
          remoteKind: 'aira-cloud',
          uid: this.config.cloudUid,
          deviceCredential: this.config.cloudDeviceCredential,
        }
      : {
          remoteKind: 'webdav',
          url: this.config.webdavConfig?.url || '',
          username: this.config.webdavConfig?.username,
          password: this.config.webdavConfig?.password,
          requestPermission: this.config.webdavConfig?.requestPermission,
          requestTimeoutMs: webdavRequestTimeoutMs,
        };
    return createBookmarkSyncRuntime({
      provider,
      rootPath: this.config.rootPath,
      deviceId: this.config.deviceId,
      local: createBookmarkSyncBrowserLocalAdapter({
        deviceId: this.config.deviceId,
        requestPermission: true,
        invalidRootOrderMessage: '同步书签快照缺少根目录排序，已停止写入本地以避免清空书签',
      }),
      persistSelectedSource: persistSelectedSyncSource,
    });
  }

  private async markSuccess(remoteKind: LeafTabSyncRemoteKind): Promise<void> {
    const nowIso = new Date().toISOString();
    if (remoteKind === 'aira-cloud') {
      await Promise.all([
        writeExtensionStorageRecord({ [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso }),
        removeExtensionStorageKeys([AIRA_CLOUD_LAST_ERROR_AT_KEY, AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]),
      ]);
      localStorage.setItem(AIRA_CLOUD_LAST_SYNC_AT_KEY, nowIso);
      localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_AT_KEY);
      localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY);
    } else {
      await Promise.all([
        writeExtensionStorageRecord({ [WEBDAV_LAST_SYNC_AT_KEY]: nowIso }),
        removeExtensionStorageKeys([WEBDAV_LAST_ERROR_AT_KEY, WEBDAV_LAST_ERROR_MESSAGE_KEY]),
      ]);
      localStorage.setItem(WEBDAV_LAST_SYNC_AT_KEY, nowIso);
      localStorage.removeItem(WEBDAV_LAST_ERROR_AT_KEY);
      localStorage.removeItem(WEBDAV_LAST_ERROR_MESSAGE_KEY);
    }
    this.emitStatusChanged();
  }

  private async markError(remoteKind: LeafTabSyncRemoteKind, error: unknown): Promise<void> {
    const nowIso = new Date().toISOString();
    const message = String((error as Error)?.message || 'unknown');
    const errorAtKey = remoteKind === 'aira-cloud' ? AIRA_CLOUD_LAST_ERROR_AT_KEY : WEBDAV_LAST_ERROR_AT_KEY;
    const errorMessageKey = remoteKind === 'aira-cloud'
      ? AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY
      : WEBDAV_LAST_ERROR_MESSAGE_KEY;
    await writeExtensionStorageRecord({
      [errorAtKey]: nowIso,
      [errorMessageKey]: message,
    });
    localStorage.setItem(errorAtKey, nowIso);
    localStorage.setItem(errorMessageKey, message);
    this.emitStatusChanged();
  }

  private async setSourceEnabled(remoteKind: LeafTabSyncRemoteKind, enabled: boolean): Promise<void> {
    if (remoteKind === 'aira-cloud') {
      await writeAiraCloudSyncEnabled(this.config.cloudUid, enabled);
    } else {
      await writeExtensionStorageRecord({
        [WEBDAV_STORAGE_KEYS.syncEnabled]: String(enabled),
      });
      localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(enabled));
    }
    this.emitStatusChanged();
  }

  private async recordCloudCredentialFailure(error: unknown): Promise<void> {
    if (error instanceof LeafTabSyncAiraCloudError && isAiraDesktopCredentialRejection(error)) {
      await recordAiraDesktopConnectionFailure(error).catch(() => null);
    }
  }

  private emitStatusChanged(): void {
    window.dispatchEvent(new Event('webdav-config-changed'));
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
  }
}
