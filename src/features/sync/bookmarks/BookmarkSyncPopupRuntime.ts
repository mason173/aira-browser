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
  readAiraDesktopConnectionProfileWithinExecutionLock,
  refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock,
  resolveAiraDesktopProCapability,
  type AiraDesktopConnectionProfile,
  type AiraDesktopProCapabilityStatus,
} from '@/features/desktop-connection/desktopConnectionProfile';
import {
  isAiraDesktopCredentialRejection,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  recordAiraDesktopConnectionFailure,
  recordAiraDesktopConnectionFailureWithinExecutionLock,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  readAiraCloudSyncEnabledFromExtensionStorage,
  writeAiraCloudSyncEnabled,
} from '@/features/sync/bookmarks/airaCloudPreferences';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  readWebdavStorageStateFromExtensionStorage,
  writeWebdavStorageStateWithinExecutionLock,
  type WebdavStorageState,
} from '@/utils/webdavConfig';
import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import type {
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { LeafTabSyncAiraCloudError } from '@/sync/leaftab/airaCloudStore';
import {
  clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
  readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
} from '@/sync/leaftab/localChangeTracker';
import {
  clearPendingBookmarkConflict,
  createBookmarkSyncBrowserLocalAdapter,
  createBookmarkSyncRuntime,
  isPendingBookmarkConflictForSource,
  persistPendingBookmarkConflict,
  readPendingBookmarkConflictWithinExecutionLock,
  type BookmarkSyncConflictChoice,
  type BookmarkSyncDataOverview,
  type BookmarkSyncRuntimeProvider,
} from './BookmarkSyncModule';
import { withBookmarkSyncExecutionLock } from '@/sync/leaftab/executionLock';
import {
  parseLeafTabSyncRemoteKind,
  resolveLeafTabSyncMergeIntent,
} from '@/sync/leaftab/source';

export interface BookmarkSyncPopupRuntimeConfig {
  deviceId: string;
  rootPath: string;
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
  | { type: 'select-webdav-candidate'; candidate: WebdavStorageState }
  | { type: 'resolve-conflict'; choice: BookmarkSyncConflictChoice };

interface BookmarkSyncPopupExecutionConfig {
  selectedSource: LeafTabSyncRemoteKind | null;
  cloudUid: string;
  cloudDeviceCredential: string;
  cloudSyncEnabled: boolean;
  cloudCapability: AiraDesktopProCapabilityStatus;
  webdavState: WebdavStorageState;
  pendingConflict: LeafTabPendingBookmarkConflict | null;
}

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

const updatePopupLocalStorageCache = (operation: () => void): void => {
  try {
    operation();
  } catch {
    // Extension storage is authoritative; localStorage is only a Popup UI cache.
  }
};

const persistSelectedSyncSource = async (source: LeafTabSyncRemoteKind) => {
  await writeExtensionStorageRecord({
    [LEAFTAB_SELECTED_SYNC_SOURCE_KEY]: source,
  });
  updatePopupLocalStorageCache(() => {
    localStorage.setItem(LEAFTAB_SELECTED_SYNC_SOURCE_KEY, source);
  });
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

  selectWebdavSource(
    candidate: WebdavStorageState,
    callbacks: BookmarkSyncPopupActionCallbacks = {},
  ): Promise<BookmarkSyncPopupRunOutcome> {
    return this.execute('webdav', { type: 'select-webdav-candidate', candidate }, callbacks);
  }

  resolveConflict(
    remoteKind: LeafTabSyncRemoteKind,
    choice: BookmarkSyncConflictChoice,
    callbacks: BookmarkSyncPopupActionCallbacks = {},
  ): Promise<BookmarkSyncPopupRunOutcome> {
    return this.execute(remoteKind, { type: 'resolve-conflict', choice }, callbacks);
  }

  readPendingConflict(): Promise<LeafTabPendingBookmarkConflict | null> {
    return withBookmarkSyncExecutionLock(async () => {
      const config = await this.readExecutionConfig('webdav', undefined, false);
      return config.pendingConflict;
    });
  }

  private async execute(
    remoteKind: LeafTabSyncRemoteKind,
    operation: BookmarkSyncPopupOperation,
    callbacks: BookmarkSyncPopupActionCallbacks,
  ): Promise<BookmarkSyncPopupRunOutcome> {
    const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
    if (!granted) {
      return {
        type: 'blocked',
        reason: 'bookmarks-permission-required',
        message: '未授予书签权限，无法同步书签',
      };
    }

    let expectedCloudIdentity: { uid: string; deviceCredential: string } | undefined;
    try {
      return await withBookmarkSyncExecutionLock(async (): Promise<BookmarkSyncPopupRunOutcome> => {
        const executionConfig = await this.readExecutionConfig(
          remoteKind,
          operation.type === 'select-webdav-candidate' ? operation.candidate : undefined,
          true,
        );
        expectedCloudIdentity = {
          uid: executionConfig.cloudUid,
          deviceCredential: executionConfig.cloudDeviceCredential,
        };
        const blocked = this.checkEligibility(remoteKind, operation, executionConfig);
        if (blocked) {
          return blocked;
        }
        callbacks.onRunStarted?.();
        const runtime = this.createRuntime(remoteKind, executionConfig);
        const runOptions = {
          onProgress: callbacks.onProgress,
          mergeIntent: resolveLeafTabSyncMergeIntent(executionConfig.selectedSource, remoteKind),
        };
        const result = operation.type === 'sync-now'
          ? await runtime.module.sync(runOptions)
          : operation.type === 'select-webdav-candidate'
            ? await runtime.module.sync(runOptions)
            : operation.type === 'select-source'
            ? await runtime.module.syncAndSelectSource(runOptions)
            : await runtime.module.syncAndSelectSource({
                ...runOptions,
                conflictChoice: operation.choice,
              });
        if (result.kind === 'conflict') {
          if (operation.type === 'select-webdav-candidate') {
            await writeWebdavStorageStateWithinExecutionLock({
              ...operation.candidate,
              syncEnabled: false,
            });
          }
          const pendingConflict = await persistPendingBookmarkConflict(
            remoteKind,
            runtime.sourceIdentity,
            result,
          );
          return { type: 'conflict', result, pendingConflict };
        }

        if (operation.type === 'select-webdav-candidate') {
          await this.commitSelectedSource('webdav', executionConfig, {
            ...operation.candidate,
            syncEnabled: true,
          });
        }
        if (!executionConfig.pendingConflict || executionConfig.pendingConflict.provider === remoteKind) {
          await clearPendingBookmarkConflict();
        }
        await this.markSuccess(remoteKind);
        return {
          type: 'completed',
          result,
          overview: createOverviewFromSummary(result.snapshotSummary),
        };
      });
    } catch (error) {
      await this.markError(remoteKind, error);
      if (remoteKind === 'aira-cloud') {
        await this.recordCloudCredentialFailure(error, expectedCloudIdentity, false);
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
    return withBookmarkSyncExecutionLock(async (): Promise<BookmarkSyncPopupOverviewResult> => {
      const executionConfig = await this.readExecutionConfig(remoteKind, undefined, false);
      const runtime = this.createRuntime(remoteKind, executionConfig);
      const overviewPromise = runtime.module.readSummary({ includeRemote })
        .then((overview) => ({ overview }))
        .catch((error: unknown) => ({ error }));
      const baselineSnapshot = remoteKind === 'aira-cloud'
        ? await readBaselineSnapshot(runtime.baselineStorageKey)
        : null;
      const overviewResult = await overviewPromise;
      if ('error' in overviewResult) {
        if (remoteKind === 'aira-cloud') {
          await this.recordCloudCredentialFailure(overviewResult.error, {
            uid: executionConfig.cloudUid,
            deviceCredential: executionConfig.cloudDeviceCredential,
          }, true);
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
    });
  }

  private checkEligibility(
    remoteKind: LeafTabSyncRemoteKind,
    operation: BookmarkSyncPopupOperation,
    config: BookmarkSyncPopupExecutionConfig,
  ): Extract<BookmarkSyncPopupRunOutcome, { type: 'blocked' }> | null {
    if (operation.type !== 'sync-now' && config.pendingConflict &&
      config.pendingConflict.provider !== remoteKind) {
      return {
        type: 'blocked',
        reason: 'pending-conflict',
        message: '请先处理当前书签同步冲突，再更改同步方式',
      };
    }
    if (remoteKind === 'webdav') {
      if (!config.webdavState.url) {
        return {
          type: 'blocked',
          reason: 'webdav-config-required',
          message: '请先配置 WebDAV',
        };
      }
      if (operation.type === 'sync-now' && !config.webdavState.syncEnabled) {
        return {
          type: 'blocked',
          reason: 'source-disabled',
          message: '请先开启 WebDAV 书签同步',
        };
      }
      return null;
    }
    if (!config.cloudUid || !config.cloudDeviceCredential) {
      return {
        type: 'blocked',
        reason: 'cloud-login-required',
        message: '请先连接 Aira 桌面设备',
      };
    }
    if (operation.type === 'sync-now' && !config.cloudSyncEnabled) {
      return {
        type: 'blocked',
        reason: 'source-disabled',
        message: '请先为当前 Aira 账号开启云书签同步',
      };
    }
    if (config.cloudCapability === 'login-required') {
      return {
        type: 'blocked',
        reason: 'cloud-login-required',
        message: 'Aira 桌面设备需要重新连接',
      };
    }
    if (config.cloudCapability === 'temporarily-unavailable') {
      return {
        type: 'blocked',
        reason: 'cloud-temporarily-unavailable',
        message: 'Aira 服务暂时不可用，请稍后再试',
      };
    }
    if (config.cloudCapability === 'pro-required') {
      return {
        type: 'blocked',
        reason: 'cloud-pro-required',
        message: 'Aira 云同步需要 Aira Pro',
      };
    }
    return null;
  }

  private async readExecutionConfig(
    remoteKind: LeafTabSyncRemoteKind,
    candidateWebdav: WebdavStorageState | undefined,
    refreshCloudMembership: boolean,
  ): Promise<BookmarkSyncPopupExecutionConfig> {
    const [storedWebdav, storedPendingConflict, initialCloudProfile, selectedSourceRecord] = await Promise.all([
      readWebdavStorageStateFromExtensionStorage(),
      readPendingBookmarkConflictWithinExecutionLock(),
      readAiraDesktopConnectionProfileWithinExecutionLock(),
      readExtensionStorageRecord([LEAFTAB_SELECTED_SYNC_SOURCE_KEY]),
    ]);
    let cloudProfile: AiraDesktopConnectionProfile | null = initialCloudProfile;
    let cloudCapability: AiraDesktopProCapabilityStatus = 'login-required';
    if (remoteKind === 'aira-cloud') {
      if (cloudProfile?.uid && cloudProfile.deviceCredential && refreshCloudMembership) {
        try {
          cloudProfile = await refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock({ force: true });
        } catch {
          cloudCapability = 'temporarily-unavailable';
        }
      }
      if (cloudCapability !== 'temporarily-unavailable') {
        cloudCapability = resolveAiraDesktopProCapability(cloudProfile);
      }
    }
    const cloudUid = cloudProfile?.uid?.trim() || '';
    const cloudDeviceCredential = cloudProfile?.deviceCredential?.trim() || '';
    let pendingConflict = storedPendingConflict;
    if (pendingConflict) {
      const matchesCurrentIdentity = pendingConflict.provider === 'aira-cloud'
        ? isPendingBookmarkConflictForSource(pendingConflict, {
            remoteKind: 'aira-cloud',
            uid: cloudUid,
            deviceCredential: cloudDeviceCredential,
          }, this.config.rootPath)
        : isPendingBookmarkConflictForSource(pendingConflict, {
            remoteKind: 'webdav',
            url: storedWebdav.url,
            username: storedWebdav.username,
            password: storedWebdav.password,
            requestPermission: false,
          }, this.config.rootPath);
      if (!matchesCurrentIdentity) {
        await clearPendingBookmarkConflict();
        pendingConflict = null;
      }
    }
    const effectiveWebdav = candidateWebdav ?? storedWebdav;
    return {
      selectedSource: parseLeafTabSyncRemoteKind(
        selectedSourceRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY],
      ),
      cloudUid,
      cloudDeviceCredential,
      cloudSyncEnabled: await readAiraCloudSyncEnabledFromExtensionStorage(cloudUid),
      cloudCapability,
      webdavState: {
        profileName: effectiveWebdav.profileName.trim(),
        url: effectiveWebdav.url.trim(),
        username: effectiveWebdav.username.trim(),
        password: effectiveWebdav.password,
        syncEnabled: effectiveWebdav.syncEnabled,
      },
      pendingConflict,
    };
  }

  private createRuntime(
    remoteKind: LeafTabSyncRemoteKind,
    config: BookmarkSyncPopupExecutionConfig,
    webdavRequestTimeoutMs?: number,
  ) {
    const provider: BookmarkSyncRuntimeProvider = remoteKind === 'aira-cloud'
      ? {
          remoteKind: 'aira-cloud',
          uid: config.cloudUid,
          deviceCredential: config.cloudDeviceCredential,
        }
      : {
          remoteKind: 'webdav',
          url: config.webdavState.url,
          username: config.webdavState.username,
          password: config.webdavState.password,
          requestPermission: false,
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
        readPendingChanges: readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
        clearPendingChanges: clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
      }),
      persistSelectedSource: (source: LeafTabSyncRemoteKind): Promise<void> => {
        return this.commitSelectedSource(source, config);
      },
    });
  }

  private async markSuccess(remoteKind: LeafTabSyncRemoteKind): Promise<void> {
    const nowIso = new Date().toISOString();
    if (remoteKind === 'aira-cloud') {
      await Promise.all([
        writeExtensionStorageRecord({ [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso }),
        removeExtensionStorageKeys([AIRA_CLOUD_LAST_ERROR_AT_KEY, AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]),
      ]);
      updatePopupLocalStorageCache(() => {
        localStorage.setItem(AIRA_CLOUD_LAST_SYNC_AT_KEY, nowIso);
        localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_AT_KEY);
        localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY);
      });
    } else {
      await Promise.all([
        writeExtensionStorageRecord({ [WEBDAV_LAST_SYNC_AT_KEY]: nowIso }),
        removeExtensionStorageKeys([WEBDAV_LAST_ERROR_AT_KEY, WEBDAV_LAST_ERROR_MESSAGE_KEY]),
      ]);
      updatePopupLocalStorageCache(() => {
        localStorage.setItem(WEBDAV_LAST_SYNC_AT_KEY, nowIso);
        localStorage.removeItem(WEBDAV_LAST_ERROR_AT_KEY);
        localStorage.removeItem(WEBDAV_LAST_ERROR_MESSAGE_KEY);
      });
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
    updatePopupLocalStorageCache(() => {
      localStorage.setItem(errorAtKey, nowIso);
      localStorage.setItem(errorMessageKey, message);
    });
    this.emitStatusChanged();
  }

  private async commitSelectedSource(
    remoteKind: LeafTabSyncRemoteKind,
    config: BookmarkSyncPopupExecutionConfig,
    webdavOverride?: WebdavStorageState,
  ): Promise<void> {
    if (remoteKind === 'aira-cloud') {
      await writeAiraCloudSyncEnabled(config.cloudUid, true);
    } else {
      await writeWebdavStorageStateWithinExecutionLock({
        ...(webdavOverride ?? config.webdavState),
        syncEnabled: true,
      });
    }
    await persistSelectedSyncSource(remoteKind);
    this.emitStatusChanged();
  }

  private async recordCloudCredentialFailure(
    error: unknown,
    expectedIdentity: { uid: string; deviceCredential: string } | undefined,
    withinExecutionLock: boolean,
  ): Promise<void> {
    if (error instanceof LeafTabSyncAiraCloudError && isAiraDesktopCredentialRejection(error)) {
      if (withinExecutionLock) {
        await recordAiraDesktopConnectionFailureWithinExecutionLock(error, expectedIdentity).catch(() => null);
      } else {
        await recordAiraDesktopConnectionFailure(error, expectedIdentity).catch(() => null);
      }
    }
  }

  private emitStatusChanged(): void {
    window.dispatchEvent(new Event('webdav-config-changed'));
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
  }
}
