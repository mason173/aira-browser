import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  PERSONAL_SERVER_LAST_ERROR_AT_KEY,
  PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY,
  PERSONAL_SERVER_LAST_SYNC_AT_KEY,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  PERSONAL_SERVER_CONNECTION_STORAGE_KEY,
  PersonalServerRemoteError,
  readPersonalServerConnection,
  type PersonalServerConnection,
} from '@/features/personal-server/PersonalServerConnection';
import {
  readAiraDesktopConnectionProfileWithinExecutionLock,
  refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock,
  resolveAiraDesktopProCapability,
  type AiraDesktopProCapabilityStatus,
} from '@/features/desktop-connection/desktopConnectionProfile';
import {
  isAiraDesktopCredentialRejection,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
  recordAiraDesktopConnectionFailureWithinExecutionLock,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  isAiraCloudSyncPreferenceStorageKey,
  readAiraCloudSyncEnabledFromExtensionStorage,
} from '@/features/sync/bookmarks/airaCloudPreferences';
import {
  clearPendingBookmarkConflict,
  createBookmarkSyncBrowserLocalAdapter,
  createBookmarkSyncRuntime,
  isPendingBookmarkConflictForSource,
  persistPendingBookmarkConflict,
  readPendingBookmarkConflictWithinExecutionLock,
  type BookmarkSyncSource as LeafTabSyncRemoteKind,
} from '@/features/sync/bookmarks/BookmarkSyncModule';
import { withBookmarkSyncExecutionLock } from '@/sync/leaftab/executionLock';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { LeafTabSyncAiraCloudError } from '@/sync/leaftab/airaCloudStore';
import {
  clearAiraCloudClientUpdateBlock,
  persistAiraCloudClientUpdateBlock,
  readAiraCloudClientUpdateBlock,
} from './airaCloudClientUpdateBlock';
import {
  clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
  markLeafTabLocalBookmarkChangedInExtensionStorage,
  readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
} from '@/sync/leaftab/localChangeTracker';
import type { LeafTabSyncEngineResult } from '@/sync/leaftab/engine';
import {
  canRunLeafTabSelectedAutoSync,
  parseLeafTabSyncRemoteKind,
} from '@/sync/leaftab/source';
import { LeafTabSyncWebdavError } from '@/sync/leaftab/webdavStore';
import {
  readWebdavStorageStateFromExtensionStorage,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';

const LOCAL_SYNC_ALARM_NAME = 'aira.leaftab.g2.auto-sync.local-change';
const PERIODIC_SYNC_ALARM_NAME = 'aira.leaftab.g2.auto-sync.periodic';
const AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES = 1;
const AUTO_SYNC_RETRY_DELAY_MINUTES = 3;
const AUTO_SYNC_PERIODIC_STARTUP_DELAY_MINUTES = 1;
const AUTO_SYNC_AIRA_CLOUD_INTERVAL_MINUTES = 3;
const AUTO_SYNC_WEBDAV_INTERVAL_MINUTES = 15;

type BackgroundSyncConfig = {
  deviceId: string;
  cloudUid: string;
  cloudDeviceCredential: string;
  cloudSyncEnabled: boolean;
  cloudClientUpdateBlocked: boolean;
  webdavSyncEnabled: boolean;
  personalServerConnection: PersonalServerConnection | null;
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
    const profile = await readAiraDesktopConnectionProfileWithinExecutionLock();
    const currentCapability = resolveAiraDesktopProCapability(profile);
    if (currentCapability === 'login-required') return currentCapability;
    const latestProfile = await refreshAiraDesktopConnectionProfileMembershipWithinExecutionLock();
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

function getNowIso() {
  return new Date().toISOString();
}

export function createBookmarkBackgroundSyncRuntime(
  runtimeConfig: BookmarkBackgroundSyncRuntimeConfig,
): BookmarkBackgroundSyncRuntime {
  let activeAutoSyncPromise: Promise<boolean> | null = null;
  let activeDeviceIdPromise: Promise<string> | null = null;

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

  async function readBackgroundSyncConfigWithinExecutionLock(): Promise<BackgroundSyncConfig> {
    const [deviceId, loginProfile, webdavState, personalServerConnection] = await Promise.all([
      getOrCreateDeviceId(),
      readAiraDesktopConnectionProfileWithinExecutionLock(),
      readWebdavStorageStateFromExtensionStorage(),
      readPersonalServerConnection(),
    ]);
    const rootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
    const cloudUid = loginProfile?.uid?.trim() || '';
    const cloudDeviceCredential = loginProfile?.deviceCredential?.trim() || '';
    const cloudSyncEnabled = await readAiraCloudSyncEnabledFromExtensionStorage(cloudUid);
    const [sharedRecord, pendingConflict, cloudClientUpdateBlock] = await Promise.all([
      readExtensionStorageRecord([LEAFTAB_SELECTED_SYNC_SOURCE_KEY]),
      readPendingBookmarkConflictWithinExecutionLock(),
      readAiraCloudClientUpdateBlock(),
    ]);
    const selectedSource = parseLeafTabSyncRemoteKind(
      sharedRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY],
    );
    let pendingConflictMatchesCurrentIdentity = false;
    if (pendingConflict?.provider === 'aira-cloud') {
      pendingConflictMatchesCurrentIdentity = isPendingBookmarkConflictForSource(pendingConflict, {
            remoteKind: 'aira-cloud',
            uid: cloudUid,
            deviceCredential: cloudDeviceCredential,
          }, rootPath);
    } else if (pendingConflict?.provider === 'personal-server' && personalServerConnection) {
      pendingConflictMatchesCurrentIdentity = isPendingBookmarkConflictForSource(pendingConflict, {
        remoteKind: 'personal-server',
        connection: personalServerConnection,
      }, rootPath);
    } else if (pendingConflict?.provider === 'webdav') {
      pendingConflictMatchesCurrentIdentity = isPendingBookmarkConflictForSource(pendingConflict, {
            remoteKind: 'webdav',
            url: webdavState.url,
            username: webdavState.username,
            password: webdavState.password,
            requestPermission: false,
          }, rootPath);
    }
    if (pendingConflict && !pendingConflictMatchesCurrentIdentity) {
      await clearPendingBookmarkConflict();
    }

    return {
      deviceId,
      cloudUid,
      cloudDeviceCredential,
      cloudSyncEnabled,
      cloudClientUpdateBlocked: cloudClientUpdateBlock.blocked,
      webdavSyncEnabled: webdavState.syncEnabled,
      personalServerConnection,
      selectedSource,
      hasPendingConflict: pendingConflictMatchesCurrentIdentity,
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

  async function readBackgroundSyncConfig(): Promise<BackgroundSyncConfig> {
    return withBookmarkSyncExecutionLock(() => {
      return readBackgroundSyncConfigWithinExecutionLock();
    });
  }

  function canRunBackgroundAutoSync(config: BackgroundSyncConfig): boolean {
    if (config.hasPendingConflict) {
      return false;
    }
    if (config.selectedSource === 'aira-cloud' && config.cloudClientUpdateBlocked) {
      return false;
    }
    return canRunLeafTabSelectedAutoSync({
      selectedSource: config.selectedSource,
      cloudUid: config.cloudUid,
      cloudDeviceCredential: config.cloudDeviceCredential,
      airaCloudEnabled: config.cloudSyncEnabled,
      webdavUrl: config.webdavConfig?.url || '',
      webdavEnabled: config.webdavSyncEnabled,
      personalServerConfigured: Boolean(config.personalServerConnection?.capabilities.bookmarks),
    });
  }

  function createBookmarkSyncRuntimeForBackground(
    config: BackgroundSyncConfig,
    remoteKind: LeafTabSyncRemoteKind,
    options?: {
      webdavRequestTimeoutMs?: number;
    },
  ): ReturnType<typeof createBookmarkSyncRuntime> {
    const rootPath = config.rootPath;
    let provider;
    if (remoteKind === 'aira-cloud') {
      provider = {
            remoteKind: 'aira-cloud',
            uid: config.cloudUid,
            deviceCredential: config.cloudDeviceCredential,
          } as const;
    } else if (remoteKind === 'personal-server') {
      if (!config.personalServerConnection) throw new Error('请先连接 Personal Server');
      provider = {
        remoteKind: 'personal-server',
        connection: config.personalServerConnection,
      } as const;
    } else {
      provider = {
            remoteKind: 'webdav',
            url: config.webdavConfig?.url || '',
            username: config.webdavConfig?.username,
            password: config.webdavConfig?.password,
            requestPermission: false,
            requestTimeoutMs: options?.webdavRequestTimeoutMs,
          } as const;
    }
    return createBookmarkSyncRuntime({
      provider,
      deviceId: config.deviceId,
      rootPath,
      local: createBookmarkSyncBrowserLocalAdapter({
        deviceId: config.deviceId,
        requestPermission: false,
        invalidRootOrderMessage: '远端书签快照缺少根目录排序，已停止写入本地以避免清空书签',
        readPendingChanges: readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
        clearPendingChanges: clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
      }),
    });
  }

  async function runSingleRemoteSync(
    config: BackgroundSyncConfig,
    remoteKind: LeafTabSyncRemoteKind,
    options?: {
      webdavRequestTimeoutMs?: number;
    },
  ): Promise<{ result: LeafTabSyncEngineResult; sourceIdentity: string }> {
    const runtime = createBookmarkSyncRuntimeForBackground(config, remoteKind, {
      webdavRequestTimeoutMs: options?.webdavRequestTimeoutMs,
    });
    return {
      result: await runtime.module.sync({}),
      sourceIdentity: runtime.sourceIdentity,
    };
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
      await clearAiraCloudClientUpdateBlock();
      return;
    }
    if (remoteKind === 'personal-server') {
      await writeExtensionStorageRecord({
        [PERSONAL_SERVER_LAST_SYNC_AT_KEY]: nowIso,
        [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: '',
      });
      await removeExtensionStorageKeys([
        PERSONAL_SERVER_LAST_ERROR_AT_KEY,
        PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY,
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
    if (remoteKind === 'personal-server') {
      await writeExtensionStorageRecord({
        [PERSONAL_SERVER_LAST_ERROR_AT_KEY]: nowIso,
        [PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY]: message,
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

  function isActionRequiredSyncError(error: unknown): boolean {
    if (error instanceof LeafTabSyncWebdavError) {
      return error.status === 401 || error.status === 403;
    }
    if (error instanceof LeafTabSyncAiraCloudError) {
      return [
        'invalid_desktop_push_token',
        'desktop_session_expired',
        'pro_required',
        'client_update_required',
      ].includes(error.code);
    }
    if (error instanceof PersonalServerRemoteError) {
      return error.status === 401 || error.status === 403 ||
        error.code === 'personal_server_required' || error.code === 'client_update_required';
    }
    const message = String((error as Error)?.message || error || '');
    return /请先|重新扫码|权限|认证|凭据/i.test(message);
  }

  async function runBackgroundAutoSync(trigger?: BackgroundSyncTrigger): Promise<boolean> {
    if (activeAutoSyncPromise) {
      return activeAutoSyncPromise;
    }
    activeAutoSyncPromise = withBookmarkSyncExecutionLock(async () => {
      const config = await readBackgroundSyncConfigWithinExecutionLock();
      const remoteKind = config.selectedSource;
      if (!remoteKind || !canRunBackgroundAutoSync(config)) {
        return false;
      }
      if (trigger?.provider && trigger.provider !== remoteKind) {
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
            await scheduleSelectedSourceSyncRetry(remoteKind);
            return false;
          }
          const error = new LeafTabSyncAiraCloudError(
            capability === 'login-required'
              ? 'Aira 桌面设备需要重新连接。'
              : 'Aira 云同步需要有效的 Pro 权限，请恢复权限后重试。',
            capability === 'login-required' ? 'invalid_desktop_push_token' : 'pro_required',
          );
          await markSyncError(remoteKind, error);
          return false;
        }
      }

      const keepAlive = runtimeConfig.startKeepAlive();
      try {
        const syncRun = await runSingleRemoteSync(config, remoteKind);
        const result = syncRun.result;
        if (result.kind === 'conflict') {
          await persistPendingBookmarkConflict(remoteKind, syncRun.sourceIdentity, result);
          await removeExtensionStorageKeys([
            LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          ]);
          return false;
        }

        await clearPendingBookmarkConflict();
        await markSyncSuccess(remoteKind);
        const remainingPendingLocalChangedAt =
          await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage();
        await removeExtensionStorageKeys([
          LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
        ]);
        if (remainingPendingLocalChangedAt > 0) {
          await scheduleLocalChangeAlarm();
        }
        return true;
      } catch (error) {
        await markSyncError(remoteKind, error);
        if (remoteKind === 'aira-cloud' && error instanceof LeafTabSyncAiraCloudError &&
          error.code === 'client_update_required') {
          await persistAiraCloudClientUpdateBlock(error.message);
          await clearBackgroundAlarms();
        }
        if (remoteKind === 'personal-server' && error instanceof PersonalServerRemoteError &&
          error.code === 'client_update_required') {
          await removeExtensionStorageKeys([
            LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          ]);
          await clearBackgroundAlarms();
        }
        if (error instanceof LeafTabSyncAiraCloudError && isAiraDesktopCredentialRejection(error)) {
          await recordAiraDesktopConnectionFailureWithinExecutionLock(error, {
            uid: config.cloudUid,
            deviceCredential: config.cloudDeviceCredential,
          }).catch(() => null);
        }
        const actionRequired = isActionRequiredSyncError(error);
        if (!actionRequired) {
          await scheduleSelectedSourceSyncRetry(remoteKind);
        } else {
          await removeExtensionStorageKeys([
            LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
          ]);
        }
        console.error('[Aira][background auto sync]', error);
        return false;
      } finally {
        keepAlive.stop();
      }
    });

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
    alarms.create(LOCAL_SYNC_ALARM_NAME, {
      delayInMinutes: safeDelayMinutes,
    });
  }

  async function scheduleSelectedSourceSyncRetry(provider: LeafTabSyncRemoteKind): Promise<void> {
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider]: provider,
    });
    await scheduleLocalSyncAlarmAfter(AUTO_SYNC_RETRY_DELAY_MINUTES);
  }

  function resolvePeriodicSyncDelayMinutes(
    config: BackgroundSyncConfig,
    isStartup: boolean = false,
  ): number {
    if (isStartup) {
      return AUTO_SYNC_PERIODIC_STARTUP_DELAY_MINUTES;
    }
    return config.selectedSource === 'webdav'
      ? AUTO_SYNC_WEBDAV_INTERVAL_MINUTES
      : AUTO_SYNC_AIRA_CLOUD_INTERVAL_MINUTES;
  }

  async function schedulePeriodicSyncAlarm(
    config: BackgroundSyncConfig,
    delayMinutes?: number,
  ): Promise<void> {
    const alarms = getAlarmsApi();
    if (!alarms?.create) {
      return;
    }
    const resolvedDelayMinutes = delayMinutes ?? resolvePeriodicSyncDelayMinutes(config);
    const desiredScheduledTime = Date.now() + resolvedDelayMinutes * 60_000;
    const existing = alarms.get ? await alarms.get(PERIODIC_SYNC_ALARM_NAME) : undefined;
    const existingScheduledTime = Number(existing?.scheduledTime || 0);
    if (existingScheduledTime > Date.now() && existingScheduledTime <= desiredScheduledTime) {
      await writeExtensionStorageRecord({
        [LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt]: new Date(existingScheduledTime).toISOString(),
      });
      return;
    }
    const scheduledAt = new Date(desiredScheduledTime).toISOString();
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt]: scheduledAt,
    });
    alarms.create(PERIODIC_SYNC_ALARM_NAME, {
      delayInMinutes: resolvedDelayMinutes,
    });
  }

  async function ensureFallbackPeriodicAlarm(): Promise<void> {
    const alarms = getAlarmsApi();
    if (!alarms?.create) return;
    const existing = alarms.get ? await alarms.get(PERIODIC_SYNC_ALARM_NAME) : undefined;
    if (Number(existing?.scheduledTime || 0) > Date.now()) return;
    const delayMinutes = AUTO_SYNC_RETRY_DELAY_MINUTES;
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt]:
        new Date(Date.now() + delayMinutes * 60_000).toISOString(),
    }).catch(() => undefined);
    alarms.create(PERIODIC_SYNC_ALARM_NAME, { delayInMinutes: delayMinutes });
  }

  async function clearBackgroundAlarms(): Promise<void> {
    const alarms = getAlarmsApi();
    if (alarms?.clear) {
      await alarms.clear(LOCAL_SYNC_ALARM_NAME);
      await alarms.clear(PERIODIC_SYNC_ALARM_NAME);
    }
    await removeExtensionStorageKeys([
      LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt,
    ]);
  }

  async function reconcileBackgroundSchedules(isStartup: boolean = false): Promise<void> {
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config) || !config.selectedSource) {
      await clearBackgroundAlarms();
      return;
    }
    const pendingLocalChangedAt = await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage();
    if (pendingLocalChangedAt > 0) {
      await scheduleLocalChangeAlarm();
    }
    await schedulePeriodicSyncAlarm(config, resolvePeriodicSyncDelayMinutes(config, isStartup));
  }

  async function handlePeriodicSyncAlarm(): Promise<void> {
    const checkedAt = getNowIso();
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt]: checkedAt,
    });
    try {
      const config = await readBackgroundSyncConfig();
      if (!canRunBackgroundAutoSync(config) || !config.selectedSource) {
        return;
      }
      await runBackgroundAutoSync({ provider: config.selectedSource });
    } finally {
      try {
        await reconcileBackgroundSchedules();
      } catch (error) {
        console.error('[Aira][periodic sync schedule recovery]', error);
        await ensureFallbackPeriodicAlarm();
      }
    }
  }

  async function handleLocalChangeAlarm(): Promise<void> {
    const [pendingLocalChangedAt, retryRecord] = await Promise.all([
      readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage(),
      readExtensionStorageRecord([LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider]),
    ]);
    const retryProviderValue = retryRecord[LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider];
    const retryProvider: LeafTabSyncRemoteKind | undefined =
      retryProviderValue === 'aira-cloud' || retryProviderValue === 'personal-server' || retryProviderValue === 'webdav'
        ? retryProviderValue
        : undefined;
    if (pendingLocalChangedAt <= 0 && !retryProvider) {
      await removeExtensionStorageKeys([
        LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
      ]);
      return;
    }
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      return;
    }
    await runBackgroundAutoSync({ provider: retryProvider });
  }

  async function handleBookmarkMutation(): Promise<void> {
    const now = Date.now();
    const markedPending = await markLeafTabLocalBookmarkChangedInExtensionStorage(now);
    if (!markedPending) {
      return;
    }
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      return;
    }
    await scheduleLocalChangeAlarm();
  }

  function handleBookmarkMutationEvent(): void {
    void handleBookmarkMutation();
  }

  function bindBookmarkListeners(): void {
    const bookmarks = getBookmarksApi();
    if (!bookmarks) {
      return;
    }
    bookmarks.onCreated?.addListener?.(handleBookmarkMutationEvent);
    bookmarks.onRemoved?.addListener?.(handleBookmarkMutationEvent);
    bookmarks.onChanged?.addListener?.(handleBookmarkMutationEvent);
    bookmarks.onMoved?.addListener?.(handleBookmarkMutationEvent);
    bookmarks.onChildrenReordered?.addListener?.(handleBookmarkMutationEvent);
    bookmarks.onImportEnded?.addListener?.(handleBookmarkMutationEvent);
  }

  return {
    getOrCreateDeviceId,
    initialize(): void {
      bindBookmarkListeners();
      void reconcileBackgroundSchedules().catch(async (error) => {
        console.error('[Aira][background schedule initialize]', error);
        await ensureFallbackPeriodicAlarm();
      });
    },
    handleAlarm(alarmName: string): boolean {
      if (alarmName === LOCAL_SYNC_ALARM_NAME) {
        void handleLocalChangeAlarm().catch(async (error) => {
          console.error('[Aira][local sync alarm]', error);
          await scheduleLocalSyncAlarmAfter(AUTO_SYNC_RETRY_DELAY_MINUTES);
        });
        return true;
      }
      if (alarmName === PERIODIC_SYNC_ALARM_NAME) {
        void handlePeriodicSyncAlarm().catch(async (error) => {
          console.error('[Aira][periodic sync alarm]', error);
          await ensureFallbackPeriodicAlarm();
        });
        return true;
      }
      return false;
    },
    notifyStartup(): void {
      void reconcileBackgroundSchedules(true).catch(async (error) => {
        console.error('[Aira][background startup schedule]', error);
        await ensureFallbackPeriodicAlarm();
      });
    },
    notifyIdleStateChanged(): void {
      void reconcileBackgroundSchedules().catch(async (error) => {
        console.error('[Aira][background idle schedule]', error);
        await ensureFallbackPeriodicAlarm();
      });
    },
    notifyStorageChanged(changes: Record<string, unknown>, areaName: string): void {
      if (areaName !== 'local') {
        return;
      }
      const relevantKeys = [
        LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
        LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
        LEAFTAB_BACKGROUND_STORAGE_KEYS.airaCloudClientUpdateRequired,
        WEBDAV_STORAGE_KEYS.syncEnabled,
        WEBDAV_STORAGE_KEYS.url,
        WEBDAV_STORAGE_KEYS.username,
        WEBDAV_STORAGE_KEYS.password,
        AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
        PERSONAL_SERVER_CONNECTION_STORAGE_KEY,
      ];
      const changedKeys = Object.keys(changes);
      const relevantChanged = changedKeys.some((key) => (
        relevantKeys.includes(key) || isAiraCloudSyncPreferenceStorageKey(key)
      ));
      if (relevantChanged) {
        void reconcileBackgroundSchedules().catch(async (error) => {
          console.error('[Aira][background storage schedule]', error);
          await ensureFallbackPeriodicAlarm();
        });
      }
    },
  };
}
