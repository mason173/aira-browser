import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  readAiraDesktopConnectionProfile,
  refreshAiraDesktopConnectionProfileMembership,
  resolveAiraDesktopProCapability,
  type AiraDesktopProCapabilityStatus,
} from '@/features/desktop-connection/desktopConnectionProfile';
import {
  isAiraDesktopCredentialRejection,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
  recordAiraDesktopConnectionFailure,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  isAiraCloudSyncPreferenceStorageKey,
  readAiraCloudSyncEnabledFromExtensionStorage,
} from '@/features/sync/bookmarks/airaCloudPreferences';
import {
  clearPendingBookmarkConflict,
  createBookmarkSyncRuntime,
  persistPendingBookmarkConflict,
  resolveBookmarkSyncBaselineStorageKey,
  type BookmarkSyncSource as LeafTabSyncRemoteKind,
} from '@/features/sync/bookmarks/BookmarkSyncModule';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import {
  captureLeafTabBookmarkTreeDraft,
  replaceLeafTabBookmarkTree,
} from '@/sync/leaftab/bookmarks';
import { LeafTabSyncAiraCloudError } from '@/sync/leaftab/airaCloudStore';
import {
  clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
  markLeafTabLocalBookmarkChangedInExtensionStorage,
  readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
} from '@/sync/leaftab/localChangeTracker';
import {
  appendLeafTabLocalBookmarkOperationEvent,
} from '@/sync/leaftab/localOperationOutbox';
import type { LeafTabBookmarkSyncChangeProbeResult } from '@/sync/leaftab/changeProbe';
import type { LeafTabSyncEngineResult } from '@/sync/leaftab/engine';
import {
  canRunLeafTabSelectedAutoSync,
  parseLeafTabSyncRemoteKind,
} from '@/sync/leaftab/source';
import type { LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import {
  buildLeafTabSyncSnapshot,
  createLeafTabSyncBuildState,
  normalizeLeafTabLiveBookmarkSnapshot,
} from '@/sync/leaftab/snapshot';
import { LeafTabSyncWebdavError } from '@/sync/leaftab/webdavStore';
import {
  readWebdavStorageStateFromExtensionStorage,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';

const LOCAL_SYNC_ALARM_NAME = 'aira.leaftab.g2.auto-sync.local-change';
const REMOTE_PROBE_ALARM_NAME = 'aira.leaftab.g2.auto-sync.remote-probe';
const AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES = 1;
const AUTO_SYNC_RETRY_DELAY_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES = 1;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_BACKGROUND_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_IDLE_DETECTION_SECONDS = 90;
const AUTO_SYNC_APPLY_SUPPRESS_MS = 20_000;

type BackgroundSyncConfig = {
  deviceId: string;
  cloudUid: string;
  cloudDeviceCredential: string;
  cloudSyncEnabled: boolean;
  webdavSyncEnabled: boolean;
  selectedSource: LeafTabSyncRemoteKind | null;
  hasPendingConflict: boolean;
  webdavConfig: ({
    url: string;
    username: string;
    password: string;
    rootPath: string;
    requestPermission: boolean;
  }) | null;
  rootPath: string;
};

type BackgroundSyncTrigger = {
  provider?: LeafTabSyncRemoteKind;
  preflightCompleted?: boolean;
};

export interface BookmarkBackgroundSyncRuntimeConfig {
  startKeepAlive: () => { stop: () => void };
}

export interface BookmarkBackgroundSyncRuntime {
  getOrCreateDeviceId(): Promise<string>;
  initialize(): void;
  handleAlarm(alarmName: string): boolean;
  notifyStartup(): void;
  notifyIdleStateChanged(): void;
  notifyStorageChanged(changes: Record<string, unknown>, areaName: string): void;
}

async function refreshDesktopMembershipForProFeature(): Promise<AiraDesktopProCapabilityStatus> {
  try {
    const profile = await readAiraDesktopConnectionProfile();
    const currentCapability = resolveAiraDesktopProCapability(profile);
    if (currentCapability === 'login-required') return currentCapability;
    const latestProfile = await refreshAiraDesktopConnectionProfileMembership({ force: true });
    return resolveAiraDesktopProCapability(latestProfile);
  } catch {
    return 'temporarily-unavailable';
  }
}

function getAlarmsApi() {
  return globalThis.chrome?.alarms;
}

function getBookmarksApi() {
  return globalThis.chrome?.bookmarks;
}

function getIdleApi() {
  return globalThis.chrome?.idle;
}

function getNowIso() {
  return new Date().toISOString();
}

async function updateBackgroundDebugState(_patch: Record<string, unknown>): Promise<void> {
  // Background debug storage is intentionally disabled; keep call sites easy to restore if needed.
}

export function createBookmarkBackgroundSyncRuntime(
  runtimeConfig: BookmarkBackgroundSyncRuntimeConfig,
): BookmarkBackgroundSyncRuntime {
  let activeAutoSyncPromise: Promise<boolean> | null = null;
  let activeDeviceIdPromise: Promise<string> | null = null;
  let bookmarkApplySuppressedUntil = 0;

  async function getOrCreateDeviceId(): Promise<string> {
    if (activeDeviceIdPromise) {
      return activeDeviceIdPromise;
    }
    activeDeviceIdPromise = (async () => {
      const result = await readExtensionStorageRecord([LEAFTAB_SYNC_DEVICE_ID_KEY]);
      const existing = String(result[LEAFTAB_SYNC_DEVICE_ID_KEY] || '').trim();
      if (existing) {
        return existing;
      }
      const created = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : `dev_${Date.now()}_${Math.random().toString(16).slice(2)}`;
      await writeExtensionStorageRecord({
        [LEAFTAB_SYNC_DEVICE_ID_KEY]: created,
      });
      return created;
    })();
    try {
      return await activeDeviceIdPromise;
    } finally {
      activeDeviceIdPromise = null;
    }
  }

  async function readBackgroundSyncConfig(): Promise<BackgroundSyncConfig> {
    const [deviceId, loginProfile, webdavState] = await Promise.all([
      getOrCreateDeviceId(),
      readAiraDesktopConnectionProfile(),
      readWebdavStorageStateFromExtensionStorage(),
    ]);
    const rootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
    const cloudUid = loginProfile?.uid?.trim() || '';
    const cloudDeviceCredential = loginProfile?.deviceCredential?.trim() || '';
    const cloudSyncEnabled = await readAiraCloudSyncEnabledFromExtensionStorage(cloudUid);
    const sharedRecord = await readExtensionStorageRecord([
      LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
      LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
    ]);
    const selectedSource = parseLeafTabSyncRemoteKind(
      sharedRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY],
    );
    const hasPendingConflict = Boolean(sharedRecord[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]);

    return {
      deviceId,
      cloudUid,
      cloudDeviceCredential,
      cloudSyncEnabled,
      webdavSyncEnabled: webdavState.syncEnabled,
      selectedSource,
      hasPendingConflict,
      webdavConfig: webdavState.url
        ? {
            url: webdavState.url,
            username: webdavState.username,
            password: webdavState.password,
            rootPath,
            requestPermission: false,
          }
        : null,
      rootPath,
    };
  }

  function canRunBackgroundAutoSync(config: BackgroundSyncConfig): boolean {
    if (config.hasPendingConflict) {
      return false;
    }
    return canRunLeafTabSelectedAutoSync({
      selectedSource: config.selectedSource,
      cloudUid: config.cloudUid,
      cloudDeviceCredential: config.cloudDeviceCredential,
      airaCloudEnabled: config.cloudSyncEnabled,
      webdavUrl: config.webdavConfig?.url || '',
      webdavEnabled: config.webdavSyncEnabled,
    });
  }

  async function buildLocalSnapshot(
    baselineStorageKey: string,
    deviceId: string,
  ): Promise<LeafTabSyncSnapshot> {
    const bookmarkTree = await captureLeafTabBookmarkTreeDraft({
      requestPermission: false,
      throwOnPermissionDenied: true,
    });
    const baselineStore = new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey);
    const baseline = await baselineStore.load();
    const previousSnapshot = baseline?.snapshot || null;
    const generatedAt = getNowIso();
    const state = createLeafTabSyncBuildState({
      previousSnapshot,
      bookmarkTree,
      deviceId,
      generatedAt,
    });

    return buildLeafTabSyncSnapshot({
      bookmarkTree,
      deviceId,
      generatedAt,
      state,
    });
  }

  async function applyLocalSnapshot(snapshot: LeafTabSyncSnapshot): Promise<void> {
    const liveSnapshot = normalizeLeafTabLiveBookmarkSnapshot(snapshot);
    const hasRemoteBookmarks = Object.keys(liveSnapshot.bookmarkFolders).length > 0
      || Object.keys(liveSnapshot.bookmarkItems).length > 0;
    const hasRootOrder = Object.values(liveSnapshot.bookmarkOrders).some((order) => {
      return order.parentId === 'browser_root_toolbar'
        || order.parentId === 'browser_root_other'
        || order.parentId === null;
    });
    if (hasRemoteBookmarks && !hasRootOrder) {
      throw new Error('远端书签快照缺少根目录排序，已停止写入本地以避免清空书签');
    }
    bookmarkApplySuppressedUntil = Date.now() + AUTO_SYNC_APPLY_SUPPRESS_MS;
    try {
      const applied = await replaceLeafTabBookmarkTree({
        folderLookup: Object.fromEntries(
          Object.values(liveSnapshot.bookmarkFolders).map((folder) => [
            folder.id,
            {
              title: folder.title,
              parentId: folder.parentId,
            },
          ]),
        ),
        itemLookup: Object.fromEntries(
          Object.values(liveSnapshot.bookmarkItems).map((item) => [
            item.id,
            {
              title: item.title,
              parentId: item.parentId,
              url: item.url,
            },
          ]),
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
    } finally {
      bookmarkApplySuppressedUntil = Date.now() + AUTO_SYNC_APPLY_SUPPRESS_MS;
    }
  }

  function createBookmarkSyncRuntimeForBackground(
    config: BackgroundSyncConfig,
    remoteKind: LeafTabSyncRemoteKind,
    pendingLocalChanges: boolean,
    options?: {
      webdavRequestTimeoutMs?: number;
    },
  ): ReturnType<typeof createBookmarkSyncRuntime> {
    const rootPath = config.rootPath;
    return createBookmarkSyncRuntime({
      provider: remoteKind === 'aira-cloud'
        ? {
            remoteKind: 'aira-cloud',
            uid: config.cloudUid,
            deviceCredential: config.cloudDeviceCredential,
          }
        : {
            remoteKind: 'webdav',
            url: config.webdavConfig?.url || '',
            username: config.webdavConfig?.username,
            password: config.webdavConfig?.password,
            requestPermission: false,
            requestTimeoutMs: options?.webdavRequestTimeoutMs,
          },
      deviceId: config.deviceId,
      rootPath,
      local: {
        buildSnapshot: (baselineStorageKey: string) => buildLocalSnapshot(baselineStorageKey, config.deviceId),
        applySnapshot: applyLocalSnapshot,
        hasPendingChanges: () => pendingLocalChanges,
        clearPendingChanges: () => {
          void clearPendingLeafTabLocalBookmarkChangesInExtensionStorage();
        },
      },
    });
  }

  async function runSingleRemoteSync(
    config: BackgroundSyncConfig,
    remoteKind: LeafTabSyncRemoteKind,
    options?: {
      localSnapshotOverride?: LeafTabSyncSnapshot;
      webdavRequestTimeoutMs?: number;
    },
  ): Promise<LeafTabSyncEngineResult> {
    const pendingLocalChanges = (await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage()) > 0;
    const runtime = createBookmarkSyncRuntimeForBackground(config, remoteKind, pendingLocalChanges, {
      webdavRequestTimeoutMs: options?.webdavRequestTimeoutMs,
    });
    return runtime.module.sync({
      localSnapshotOverride: options?.localSnapshotOverride,
      onProgress: (progress) => {
        void updateBackgroundDebugState({
          lastReason: `${remoteKind}:${progress.stage}:${progress.message}`,
        });
      },
    });
  }

  async function markSyncSuccess(remoteKind: LeafTabSyncRemoteKind): Promise<void> {
    const nowIso = getNowIso();
    if (remoteKind === 'aira-cloud') {
      await writeExtensionStorageRecord({
        [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso,
        [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: '',
      });
      await removeExtensionStorageKeys([
        AIRA_CLOUD_LAST_ERROR_AT_KEY,
        AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
      ]);
      return;
    }
    await writeExtensionStorageRecord({
      [WEBDAV_LAST_SYNC_AT_KEY]: nowIso,
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: '',
    });
    await removeExtensionStorageKeys([
      WEBDAV_LAST_ERROR_AT_KEY,
      WEBDAV_LAST_ERROR_MESSAGE_KEY,
    ]);
  }

  async function markSyncError(remoteKind: LeafTabSyncRemoteKind, error: unknown): Promise<void> {
    const nowIso = getNowIso();
    const message = String((error as Error)?.message || error || 'unknown');
    if (remoteKind === 'aira-cloud') {
      await writeExtensionStorageRecord({
        [AIRA_CLOUD_LAST_ERROR_AT_KEY]: nowIso,
        [AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]: message,
        [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: message,
      });
      return;
    }
    await writeExtensionStorageRecord({
      [WEBDAV_LAST_ERROR_AT_KEY]: nowIso,
      [WEBDAV_LAST_ERROR_MESSAGE_KEY]: message,
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: message,
    });
  }

  async function probeSyncPreflightForKind(
    config: BackgroundSyncConfig,
    remoteKind: LeafTabSyncRemoteKind,
  ): Promise<LeafTabBookmarkSyncChangeProbeResult> {
    const pendingLocalChanges = (await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage()) > 0;
    const runtime = createBookmarkSyncRuntimeForBackground(config, remoteKind, pendingLocalChanges);
    return runtime.module.probeChanges();
  }

  function isActionRequiredSyncError(error: unknown): boolean {
    if (error instanceof LeafTabSyncWebdavError) {
      return error.status === 401 || error.status === 403;
    }
    if (error instanceof LeafTabSyncAiraCloudError) {
      return [
        'invalid_desktop_push_token',
        'desktop_session_expired',
        'pro_required',
      ].includes(error.code);
    }
    const message = String((error as Error)?.message || error || '');
    return /请先|重新扫码|权限|认证|凭据/i.test(message);
  }

  async function runBackgroundAutoSync(trigger?: BackgroundSyncTrigger): Promise<boolean> {
    if (activeAutoSyncPromise) {
      return activeAutoSyncPromise;
    }
    activeAutoSyncPromise = (async () => {
      const config = await readBackgroundSyncConfig();
      const remoteKind = config.selectedSource;
      if (!remoteKind || !canRunBackgroundAutoSync(config)) {
        await updateBackgroundDebugState({
          lastSyncStartedAt: getNowIso(),
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'skipped',
          lastReason: config.hasPendingConflict
            ? 'pending_conflict'
            : remoteKind ? 'selected_source_unavailable' : 'no_selected_source',
        });
        return false;
      }
      if (trigger?.provider && trigger.provider !== remoteKind) {
        await updateBackgroundDebugState({
          lastSyncStartedAt: getNowIso(),
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'skipped',
          lastReason: `inactive_source:${trigger.provider}`,
        });
        return false;
      }
      if (remoteKind === 'aira-cloud') {
        const capability = await refreshDesktopMembershipForProFeature();
        if (capability !== 'ready') {
          if (capability === 'temporarily-unavailable') {
            const error = new LeafTabSyncAiraCloudError(
              'Aira 服务暂时不可用，请稍后重试。',
              'temporary_failure',
            );
            await markSyncError(remoteKind, error);
            await updateBackgroundDebugState({
              lastSyncStartedAt: getNowIso(),
              lastSyncFinishedAt: getNowIso(),
              lastResult: 'error',
              lastReason: capability,
              lastError: error.message,
            });
            await scheduleSelectedSourceSyncRetry(remoteKind, capability);
            return false;
          }
          const error = new LeafTabSyncAiraCloudError(
            capability === 'login-required'
              ? 'Aira 桌面设备需要重新连接。'
              : 'Aira 云同步需要有效的 Pro 权限，请恢复权限后重试。',
            capability === 'login-required' ? 'invalid_desktop_push_token' : 'pro_required',
          );
          await markSyncError(remoteKind, error);
          await updateBackgroundDebugState({
            lastSyncStartedAt: getNowIso(),
            lastSyncFinishedAt: getNowIso(),
            lastResult: 'action-required',
            lastReason: capability,
            lastError: error.message,
          });
          return false;
        }
      }

      const baselineStorageKey = resolveBookmarkSyncBaselineStorageKey(
        remoteKind,
        config.rootPath,
        remoteKind === 'aira-cloud' ? config.cloudUid : '',
      );
      const baseline = await new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey).load().catch(() => null);
      const baselineCommitId = baseline?.commitId || null;
      await updateBackgroundDebugState({
        lastSyncStartedAt: getNowIso(),
        lastSyncFinishedAt: '',
        lastTriggerProvider: trigger?.provider || '',
        lastRoute: `single:${remoteKind}`,
        lastResult: 'running',
        lastReason: '',
        lastError: '',
        cloudBaselineCommitId: remoteKind === 'aira-cloud' ? (baselineCommitId || '') : '',
        webdavBaselineCommitId: remoteKind === 'webdav' ? (baselineCommitId || '') : '',
      });

      const keepAlive = runtimeConfig.startKeepAlive();
      try {
        if (!(trigger?.preflightCompleted === true && trigger.provider === remoteKind)) {
          const preflight = await probeSyncPreflightForKind(config, remoteKind);
          await updateBackgroundDebugState({
            cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (preflight.remoteCommitId || '') : undefined,
            webdavRemoteCommitId: remoteKind === 'webdav' ? (preflight.remoteCommitId || '') : undefined,
          });
        }

        await writeExtensionStorageRecord({
          [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRunning]: 'true',
        });
        await updateBackgroundDebugState({
          lastReason: `syncing:${remoteKind}`,
        });
        const result = await runSingleRemoteSync(config, remoteKind);
        if (result.kind === 'conflict') {
          await persistPendingBookmarkConflict(remoteKind, result);
          await updateBackgroundDebugState({
            lastSyncFinishedAt: getNowIso(),
            lastResult: 'conflict',
            lastReason: remoteKind,
            cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (result.remoteCommitId || '') : undefined,
            webdavRemoteCommitId: remoteKind === 'webdav' ? (result.remoteCommitId || '') : undefined,
          });
          await removeExtensionStorageKeys([
            LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          ]);
          return false;
        }

        await clearPendingBookmarkConflict();
        await markSyncSuccess(remoteKind);
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'success',
          lastReason: remoteKind,
          lastError: '',
          cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (result.remoteCommitId || '') : undefined,
          webdavRemoteCommitId: remoteKind === 'webdav' ? (result.remoteCommitId || '') : undefined,
          pendingLocalChangedAt: '',
        });
        await removeExtensionStorageKeys([
          LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
          LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          WEBDAV_STORAGE_KEYS.nextSyncAt,
        ]);
        return true;
      } catch (error) {
        await markSyncError(remoteKind, error);
        if (error instanceof LeafTabSyncAiraCloudError && isAiraDesktopCredentialRejection(error)) {
          await recordAiraDesktopConnectionFailure(error).catch(() => null);
        }
        const actionRequired = isActionRequiredSyncError(error);
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: actionRequired ? 'action-required' : 'error',
          lastReason: remoteKind,
          lastError: String((error as Error)?.message || error || 'unknown'),
        });
        if (!actionRequired) {
          await scheduleSelectedSourceSyncRetry(remoteKind, 'temporary-failure');
        } else {
          await removeExtensionStorageKeys([
            LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          ]);
        }
        console.error('[Aira][background auto sync]', error);
        return false;
      } finally {
        keepAlive.stop();
        await writeExtensionStorageRecord({
          [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRunning]: 'false',
        });
      }
    })();

    try {
      return await activeAutoSyncPromise;
    } finally {
      activeAutoSyncPromise = null;
    }
  }

  async function scheduleLocalChangeAlarm(): Promise<void> {
    const alarms = getAlarmsApi();
    if (!alarms?.create) {
      return;
    }
    await scheduleLocalSyncAlarmAfter(AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES);
  }

  async function scheduleLocalSyncAlarmAfter(delayMinutes: number): Promise<void> {
    const alarms = getAlarmsApi();
    if (!alarms?.create) {
      return;
    }
    const safeDelayMinutes = Math.max(0.1, delayMinutes);
    const scheduledAt = new Date(Date.now() + safeDelayMinutes * 60_000).toISOString();
    await updateBackgroundDebugState({
      lastLocalAlarmScheduledAt: scheduledAt,
    });
    await writeExtensionStorageRecord({
      [WEBDAV_STORAGE_KEYS.nextSyncAt]: scheduledAt,
    });
    alarms.create(LOCAL_SYNC_ALARM_NAME, {
      delayInMinutes: safeDelayMinutes,
    });
  }

  async function scheduleSelectedSourceSyncRetry(provider: LeafTabSyncRemoteKind, reason: string): Promise<void> {
    await updateBackgroundDebugState({
      lastReason: `${provider}:${reason}:retry-scheduled`,
    });
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider]: provider,
    });
    await scheduleLocalSyncAlarmAfter(AUTO_SYNC_RETRY_DELAY_MINUTES);
  }

  async function resolveRemoteProbeDelayMinutes(isStartup: boolean = false): Promise<number> {
    const idle = getIdleApi();
    if (!idle?.queryState) {
      return isStartup
        ? AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES
        : AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES;
    }
    try {
      const state = await idle.queryState(AUTO_SYNC_REMOTE_PROBE_IDLE_DETECTION_SECONDS);
      if (state === 'idle' || state === 'locked') {
        return AUTO_SYNC_REMOTE_PROBE_BACKGROUND_INTERVAL_MINUTES;
      }
      return isStartup
        ? AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES
        : AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES;
    } catch {
      return isStartup
        ? AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES
        : AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES;
    }
  }

  async function scheduleRemoteProbeAlarm(delayMinutes?: number): Promise<void> {
    const alarms = getAlarmsApi();
    if (!alarms?.create) {
      return;
    }
    const resolvedDelayMinutes = delayMinutes ?? await resolveRemoteProbeDelayMinutes();
    const scheduledAt = new Date(Date.now() + resolvedDelayMinutes * 60_000).toISOString();
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt]: scheduledAt,
    });
    alarms.create(REMOTE_PROBE_ALARM_NAME, {
      delayInMinutes: resolvedDelayMinutes,
    });
  }

  async function clearBackgroundAlarms(): Promise<void> {
    const alarms = getAlarmsApi();
    if (alarms?.clear) {
      await alarms.clear(LOCAL_SYNC_ALARM_NAME);
      await alarms.clear(REMOTE_PROBE_ALARM_NAME);
    }
    await removeExtensionStorageKeys([
      LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt,
      WEBDAV_STORAGE_KEYS.nextSyncAt,
    ]);
  }

  async function reconcileBackgroundSchedules(isStartup: boolean = false): Promise<void> {
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      await clearBackgroundAlarms();
      return;
    }
    if (!config.selectedSource) {
      await clearBackgroundAlarms();
      return;
    }
    const pendingLocalChangedAt = await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage();
    if (pendingLocalChangedAt > 0) {
      await scheduleLocalChangeAlarm();
    }
    await scheduleRemoteProbeAlarm(await resolveRemoteProbeDelayMinutes(isStartup));
  }

  async function handleRemoteProbeAlarm(): Promise<void> {
    const keepAlive = runtimeConfig.startKeepAlive();
    try {
      const config = await readBackgroundSyncConfig();
      if (!canRunBackgroundAutoSync(config)) {
        return;
      }
      const remoteKind = config.selectedSource;
      if (!remoteKind) {
        return;
      }
      await writeExtensionStorageRecord({
        [LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt]: getNowIso(),
      });
      await updateBackgroundDebugState({
        lastRemoteProbeAt: getNowIso(),
      });
      let probe: LeafTabBookmarkSyncChangeProbeResult | null = null;
      try {
        probe = await probeSyncPreflightForKind(config, remoteKind);
      } catch (error) {
        await markSyncError(remoteKind, error);
        await updateBackgroundDebugState({
          lastResult: 'error',
          lastReason: `${remoteKind}:remote-probe`,
          lastError: String((error as Error)?.message || error || 'unknown'),
        });
        return;
      }
      if (probe) {
        await updateBackgroundDebugState({
          cloudBaselineCommitId: remoteKind === 'aira-cloud' ? (probe.baselineCommitId || '') : undefined,
          cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (probe.remoteCommitId || '') : undefined,
          webdavBaselineCommitId: remoteKind === 'webdav' ? (probe.baselineCommitId || '') : undefined,
          webdavRemoteCommitId: remoteKind === 'webdav' ? (probe.remoteCommitId || '') : undefined,
          lastTriggerProvider: probe.provider,
        });
      }
      if (probe?.status === 'unknown') {
        await markSyncError(remoteKind, new Error(probe.summary || '自动同步检查失败。'));
        return;
      }
      await runBackgroundAutoSync({
        provider: remoteKind,
        preflightCompleted: true,
      });
    } finally {
      keepAlive.stop();
      await reconcileBackgroundSchedules();
    }
  }

  async function handleLocalChangeAlarm(): Promise<void> {
    const [pendingLocalChangedAt, retryRecord] = await Promise.all([
      readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage(),
      readExtensionStorageRecord([LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider]),
    ]);
    const retryProviderValue = retryRecord[LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider];
    const retryProvider: LeafTabSyncRemoteKind | undefined =
      retryProviderValue === 'aira-cloud' || retryProviderValue === 'webdav'
        ? retryProviderValue
        : undefined;
    await updateBackgroundDebugState({
      lastLocalAlarmFiredAt: getNowIso(),
      pendingLocalChangedAt: pendingLocalChangedAt > 0 ? String(pendingLocalChangedAt) : '',
      lastTriggerProvider: retryProvider || '',
    });
    if (pendingLocalChangedAt <= 0 && !retryProvider) {
      await removeExtensionStorageKeys([
        LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
        LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
        WEBDAV_STORAGE_KEYS.nextSyncAt,
      ]);
      return;
    }
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      await removeExtensionStorageKeys([
        WEBDAV_STORAGE_KEYS.nextSyncAt,
      ]);
      return;
    }
    await runBackgroundAutoSync({ provider: retryProvider });
  }

  function shouldSuppressBookmarkEvent(): boolean {
    return Date.now() < bookmarkApplySuppressedUntil;
  }

  async function handleBookmarkMutation(): Promise<void> {
    if (shouldSuppressBookmarkEvent()) {
      return;
    }
    const now = Date.now();
    const nowIso = new Date(now).toISOString();
    await markLeafTabLocalBookmarkChangedInExtensionStorage(now);
    await updateBackgroundDebugState({
      lastBookmarkEventAt: nowIso,
      pendingLocalChangedAt: nowIso,
    });
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt]: nowIso,
    });
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      await removeExtensionStorageKeys([
        WEBDAV_STORAGE_KEYS.nextSyncAt,
      ]);
      return;
    }
    await scheduleLocalChangeAlarm();
  }

  function bindBookmarkListeners(): void {
    const bookmarks = getBookmarksApi();
    if (!bookmarks) {
      return;
    }
    bookmarks.onCreated?.addListener?.((id, node) => {
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'created',
        id,
        node,
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
    bookmarks.onRemoved?.addListener?.((id, removeInfo) => {
      if (!removeInfo?.node) {
        void handleBookmarkMutation();
        return;
      }
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'removed',
        id,
        parentId: removeInfo?.parentId,
        node: removeInfo?.node,
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
    bookmarks.onChanged?.addListener?.((id) => {
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'changed',
        id,
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
    bookmarks.onMoved?.addListener?.((id, moveInfo) => {
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'moved',
        id,
        parentId: moveInfo?.parentId,
        oldParentId: moveInfo?.oldParentId,
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
    bookmarks.onChildrenReordered?.addListener?.((id) => {
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'children_reordered',
        id,
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
    bookmarks.onImportEnded?.addListener?.(() => {
      void appendLeafTabLocalBookmarkOperationEvent({
        kind: 'import_ended',
        at: Date.now(),
      }).finally(() => {
        void handleBookmarkMutation();
      });
    });
  }

  return {
    getOrCreateDeviceId,
    initialize(): void {
      bindBookmarkListeners();
      void updateBackgroundDebugState({
        lastWakeAt: getNowIso(),
        lastResult: 'idle',
      });
      void reconcileBackgroundSchedules();
    },
    handleAlarm(alarmName: string): boolean {
      if (alarmName === LOCAL_SYNC_ALARM_NAME) {
        void handleLocalChangeAlarm();
        return true;
      }
      if (alarmName === REMOTE_PROBE_ALARM_NAME) {
        void handleRemoteProbeAlarm();
        return true;
      }
      return false;
    },
    notifyStartup(): void {
      void updateBackgroundDebugState({
        lastWakeAt: getNowIso(),
      });
      void reconcileBackgroundSchedules(true);
    },
    notifyIdleStateChanged(): void {
      void reconcileBackgroundSchedules();
    },
    notifyStorageChanged(changes: Record<string, unknown>, areaName: string): void {
      if (areaName !== 'local') {
        return;
      }
      const relevantKeys = [
        LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
        LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
        WEBDAV_STORAGE_KEYS.syncEnabled,
        WEBDAV_STORAGE_KEYS.url,
        WEBDAV_STORAGE_KEYS.username,
        WEBDAV_STORAGE_KEYS.password,
        AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
      ];
      const changedKeys = Object.keys(changes);
      const relevantChanged = changedKeys.some((key) => (
        relevantKeys.includes(key) || isAiraCloudSyncPreferenceStorageKey(key)
      ));
      if (relevantChanged) {
        void reconcileBackgroundSchedules();
      }
    },
  };
}
