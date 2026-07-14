import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_SYNC_ENABLED_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  isAiraDesktopProfilePro,
  readAiraDesktopLoginProfileFromExtensionStorage,
  refreshAiraDesktopMembershipProfile,
  shouldRefreshAiraDesktopMembershipProfile,
} from '@/popup/desktopLogin';
import {
  PHONE_PAGE_PUSH_MESSAGE_TYPE,
  type PhonePagePushMessage,
} from '@/features/phone-page-push/pagePushMessages';
import {
  readPhonePagePushEnabledFromExtensionStorage,
} from '@/features/phone-page-push/pagePushPreferences';
import {
  LeafTabSyncExtensionStorageBaselineStore,
} from '@/sync/leaftab/baseline';
import {
  getDefaultLeafTabBookmarkSyncScope,
} from '@/sync/leaftab/bookmarkScope';
import {
  captureLeafTabBookmarkTreeDraft,
  replaceLeafTabBookmarkTree,
} from '@/sync/leaftab/bookmarks';
import {
  LeafTabSyncAiraCloudError,
} from '@/sync/leaftab/airaCloudStore';
import {
  clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
  markLeafTabLocalBookmarkChangedInExtensionStorage,
  readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
} from '@/sync/leaftab/localChangeTracker';
import {
  appendLeafTabLocalBookmarkOperationEvent,
  buildLeafTabPendingLocalOperationsFromOutbox,
  clearLeafTabLocalBookmarkOperationOutbox,
  hasPendingLeafTabLocalBookmarkOperationOutbox,
} from '@/sync/leaftab/localOperationOutbox';
import {
  type LeafTabBookmarkSyncChangeProbeResult,
} from '@/sync/leaftab/changeProbe';
import {
  type LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import {
  BookmarkSyncModule,
  clearPendingBookmarkConflict,
  persistPendingBookmarkConflict,
  type BookmarkSyncSource as LeafTabSyncRemoteKind,
} from '@/features/sync/bookmarks/BookmarkSyncModule';
import {
  canRunLeafTabSelectedAutoSync,
  resolveLeafTabSelectedSyncSource,
} from '@/sync/leaftab/source';
import type { LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import {
  buildLeafTabSyncSnapshot,
  createLeafTabSyncBuildState,
  normalizeLeafTabLiveBookmarkSnapshot,
} from '@/sync/leaftab/snapshot';
import {
  LeafTabSyncWebdavError,
  LeafTabSyncWebdavTopologyError,
} from '@/sync/leaftab/webdavStore';
import {
  readWebdavConfigFromExtensionStorage,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';
import {
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';

const WEBDAV_PROXY_MESSAGE_TYPE = 'LEAFTAB_WEBDAV_PROXY';
const AUTO_SYNC_MESSAGE_TYPE = 'LEAFTAB_AUTO_SYNC_NOW';
const AIRA_API_BASE_URL = 'https://api.aira.cool';
const LOCAL_SYNC_ALARM_NAME = 'aira.leaftab.auto-sync.local-change';
const REMOTE_PROBE_ALARM_NAME = 'aira.leaftab.auto-sync.remote-probe';
const PHONE_PAGE_PUSH_POLL_ALARM_NAME = 'aira.phone-page-push.poll';
const AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES = 1;
const AUTO_SYNC_RETRY_DELAY_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES = 1;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_BACKGROUND_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_IDLE_DETECTION_SECONDS = 90;
const AUTO_SYNC_APPLY_SUPPRESS_MS = 20_000;
const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = 'aira/v1/bookmarks';
const BACKGROUND_KEEPALIVE_INTERVAL_MS = 20_000;
const PHONE_PAGE_PUSH_FALLBACK_TITLE = 'Aira';
const PHONE_PAGE_PUSH_POLL_INTERVAL_MS = 500;
const PHONE_PAGE_PUSH_LONG_POLL_WAIT_MS = 20_000;
const PHONE_PAGE_PUSH_ERROR_RETRY_MS = 5_000;
const PHONE_PAGE_PUSH_REQUEST_TIMEOUT_MS = 25_000;
const PHONE_PAGE_PUSH_ALARM_FALLBACK_MS = 30_000;
const PHONE_PAGE_PUSH_SOURCE = 'airatab_desktop_extension';

let activeAutoSyncPromise: Promise<boolean> | null = null;
let activePhonePagePushPollPromise: Promise<boolean> | null = null;
let phonePagePushPollTimer: ReturnType<typeof globalThis.setTimeout> | null = null;
let bookmarkApplySuppressedUntil = 0;
let phonePagePushEnabled = true;

async function disableDesktopProFeatureSettings(): Promise<void> {
  phonePagePushEnabled = false;
  await writeExtensionStorageRecord({
    [AIRA_CLOUD_SYNC_ENABLED_KEY]: 'false',
    aira_phone_page_push_enabled_v1: 'false',
  });
}

async function refreshDesktopMembershipForProFeature(): Promise<boolean> {
  const profile = await readAiraDesktopLoginProfileFromExtensionStorage();
  if (!profile?.uid) {
    return false;
  }
  const latestProfile = await refreshAiraDesktopMembershipProfile(profile, { force: true });
  const entitled = isAiraDesktopProfilePro(latestProfile);
  if (!entitled) {
    await disableDesktopProFeatureSettings();
  }
  return entitled;
}

type BackgroundSyncConfig = {
  deviceId: string;
  cloudUid: string;
  cloudDesktopPushToken: string;
  cloudEntitled: boolean;
  selectedSource: LeafTabSyncRemoteKind | null;
  hasPendingConflict: boolean;
  webdavConfig: (Awaited<ReturnType<typeof readWebdavConfigFromExtensionStorage>> & {
    rootPath: string;
    requestPermission: boolean;
  }) | null;
  rootPath: string;
  webdavBaselineStorageKey: string;
  cloudBaselineStorageKey: string;
};

type BackgroundSyncTrigger = {
  provider?: LeafTabSyncRemoteKind;
  hasRemoteChanges?: boolean;
};

type PhonePagePushTaskPayload = {
  taskId?: unknown;
  url?: unknown;
  title?: unknown;
};

type PhonePagePushPollResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
  task?: PhonePagePushTaskPayload | null;
  leaseToken?: string;
  nextPollAfterMs?: number;
};

type PhonePagePushAckResponse = {
  ok?: boolean;
  code?: string;
  message?: string;
};

function getRuntime() {
  return globalThis.chrome?.runtime;
}

function getAlarmsApi() {
  return globalThis.chrome?.alarms;
}

function getBookmarksApi() {
  return globalThis.chrome?.bookmarks;
}

function getStorageApi() {
  return globalThis.chrome?.storage;
}

function getIdleApi() {
  return globalThis.chrome?.idle;
}

function getNowIso() {
  return new Date().toISOString();
}

function startBackgroundKeepAlive(): { stop: () => void } {
  let timerId: ReturnType<typeof globalThis.setTimeout> | null = null;
  let stopped = false;

  const tick = () => {
    if (stopped) {
      return;
    }
    void readExtensionStorageRecord([LEAFTAB_SYNC_DEVICE_ID_KEY]).catch(() => undefined);
    timerId = globalThis.setTimeout(tick, BACKGROUND_KEEPALIVE_INTERVAL_MS);
  };

  tick();

  return {
    stop: () => {
      stopped = true;
      if (timerId !== null) {
        globalThis.clearTimeout(timerId);
        timerId = null;
      }
    },
  };
}

async function updateBackgroundDebugState(_patch: Record<string, unknown>): Promise<void> {
  // Background debug storage is intentionally disabled; keep call sites easy to restore if needed.
}

function normalizePhonePagePushMessage(message: unknown): PhonePagePushMessage | null {
  if (!message || typeof message !== 'object') return null;
  const candidate = message as Partial<PhonePagePushMessage>;
  if (candidate.type !== PHONE_PAGE_PUSH_MESSAGE_TYPE) return null;
  const payload = (candidate.payload || {}) as { url?: unknown; title?: unknown };
  const url = normalizePhonePagePushUrl(payload.url);
  if (!url) return null;
  return {
    type: PHONE_PAGE_PUSH_MESSAGE_TYPE,
    payload: {
      url,
      title: typeof payload.title === 'string' ? payload.title.trim() : '',
    },
  };
}

function normalizePhonePagePushUrl(value: unknown): string {
  const raw = typeof value === 'string' ? value.trim() : '';
  if (!raw) return '';
  try {
    const parsed = new URL(raw);
    if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
      return '';
    }
    return parsed.toString();
  } catch {
    return '';
  }
}

function normalizePhonePagePushTitle(value: unknown): string {
  return typeof value === 'string' ? value.trim().slice(0, 240) : '';
}

function normalizePhonePagePushDelayMs(value: unknown, fallbackMs: number): number {
  const delayMs = Number(value || 0);
  if (!Number.isFinite(delayMs) || delayMs <= 0) {
    return fallbackMs;
  }
  return Math.min(PHONE_PAGE_PUSH_ALARM_FALLBACK_MS, Math.max(250, delayMs));
}

async function openPhonePagePushTab(url: string, title: string): Promise<boolean> {
  const tabs = globalThis.chrome?.tabs;
  if (!tabs?.create) {
    console.warn('[Aira][PhonePush] tabs.create unavailable');
    return false;
  }
  try {
    await tabs.create({
      url,
      active: true,
    });
    return true;
  } catch (error) {
    console.error('[Aira][PhonePush] open tab failed', title || url, error);
    return false;
  }
}

async function postPhonePagePushJson<T>(path: string, body: unknown): Promise<T> {
  const controller = new AbortController();
  const timeout = globalThis.setTimeout(() => controller.abort(), PHONE_PAGE_PUSH_REQUEST_TIMEOUT_MS);
  try {
    const response = await fetch(`${AIRA_API_BASE_URL}${path}`, {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    const text = await response.text();
    const parsed = text ? JSON.parse(text) as T : {} as T;
    if (!response.ok) {
      const error = parsed as { message?: string };
      throw new Error(error.message || `Aira API request failed (${response.status}).`);
    }
    return parsed;
  } finally {
    globalThis.clearTimeout(timeout);
  }
}

async function resolvePhonePagePushPollProfile() {
  phonePagePushEnabled = await readPhonePagePushEnabledFromExtensionStorage();
  if (!phonePagePushEnabled) {
    return null;
  }

  const profile = await readAiraDesktopLoginProfileFromExtensionStorage();
  if (!profile?.uid || !profile.desktopPushToken) {
    return null;
  }

  const isCachedPro = isAiraDesktopProfilePro(profile);
  if (!isCachedPro || shouldRefreshAiraDesktopMembershipProfile(profile)) {
    try {
      const latestProfile = await refreshAiraDesktopMembershipProfile(profile, {
        force: !isCachedPro,
      });
      if (!isAiraDesktopProfilePro(latestProfile)) {
        await disableDesktopProFeatureSettings();
        return null;
      }
      return latestProfile;
    } catch (error) {
      if (!isCachedPro) {
        await disableDesktopProFeatureSettings();
        return null;
      }
      console.warn('[Aira][PhonePush] membership refresh failed; using cached active Pro state', error);
    }
  }

  return profile;
}

async function schedulePhonePagePushPollAlarm(delayMs: number = PHONE_PAGE_PUSH_ALARM_FALLBACK_MS): Promise<void> {
  const alarms = getAlarmsApi();
  if (!alarms?.create) {
    return;
  }
  const safeDelayMs = Math.max(6_000, delayMs);
  alarms.create(PHONE_PAGE_PUSH_POLL_ALARM_NAME, {
    delayInMinutes: safeDelayMs / 60_000,
  });
}

async function clearPhonePagePushPollAlarm(): Promise<void> {
  const alarms = getAlarmsApi();
  if (alarms?.clear) {
    await alarms.clear(PHONE_PAGE_PUSH_POLL_ALARM_NAME);
  }
}

function schedulePhonePagePushPollTimer(delayMs: number = PHONE_PAGE_PUSH_POLL_INTERVAL_MS): void {
  if (phonePagePushPollTimer !== null) {
    globalThis.clearTimeout(phonePagePushPollTimer);
    phonePagePushPollTimer = null;
  }
  phonePagePushPollTimer = globalThis.setTimeout(() => {
    phonePagePushPollTimer = null;
    void pollPhonePagePushOnce({ waitMs: PHONE_PAGE_PUSH_LONG_POLL_WAIT_MS });
  }, Math.max(0, delayMs));
}

function clearPhonePagePushPollTimer(): void {
  if (phonePagePushPollTimer !== null) {
    globalThis.clearTimeout(phonePagePushPollTimer);
    phonePagePushPollTimer = null;
  }
}

async function reconcilePhonePagePushSchedule(isStartup: boolean = false): Promise<void> {
  const profile = await resolvePhonePagePushPollProfile();
  if (!profile) {
    clearPhonePagePushPollTimer();
    await clearPhonePagePushPollAlarm();
    return;
  }
  schedulePhonePagePushPollTimer(isStartup ? 0 : PHONE_PAGE_PUSH_POLL_INTERVAL_MS);
  await schedulePhonePagePushPollAlarm(PHONE_PAGE_PUSH_ALARM_FALLBACK_MS);
}

async function ackPhonePagePushTask(params: {
  desktopPushToken: string;
  taskId: string;
  leaseToken: string;
  status: 'opened' | 'failed';
  error?: string;
}): Promise<void> {
  const response = await postPhonePagePushJson<PhonePagePushAckResponse>('/phone-page-push/ack', {
    desktopPushToken: params.desktopPushToken,
    taskId: params.taskId,
    leaseToken: params.leaseToken,
    status: params.status,
    error: params.error || '',
    source: PHONE_PAGE_PUSH_SOURCE,
  });
  if (!response.ok) {
    throw new Error(response.message || 'Phone page push acknowledgement failed.');
  }
}

async function pollPhonePagePushOnce(options: { waitMs?: number } = {}): Promise<boolean> {
  if (activePhonePagePushPollPromise) {
    return activePhonePagePushPollPromise;
  }

  activePhonePagePushPollPromise = (async () => {
    const profile = await resolvePhonePagePushPollProfile();
    if (!profile?.desktopPushToken) {
      clearPhonePagePushPollTimer();
      await clearPhonePagePushPollAlarm();
      return false;
    }

    let nextDelayMs = PHONE_PAGE_PUSH_POLL_INTERVAL_MS;
    const keepAlive = startBackgroundKeepAlive();
    try {
      const response = await postPhonePagePushJson<PhonePagePushPollResponse>('/phone-page-push/poll', {
        desktopPushToken: profile.desktopPushToken,
        source: PHONE_PAGE_PUSH_SOURCE,
        waitMs: Math.max(0, Math.min(PHONE_PAGE_PUSH_LONG_POLL_WAIT_MS, Number(options.waitMs || 0))),
      });
      if (!response.ok) {
        throw new Error(response.message || 'Phone page push polling failed.');
      }
      nextDelayMs = normalizePhonePagePushDelayMs(response.nextPollAfterMs, PHONE_PAGE_PUSH_POLL_INTERVAL_MS);
      const task = response.task || null;
      const taskId = typeof task?.taskId === 'string' ? task.taskId.trim() : '';
      const leaseToken = typeof response.leaseToken === 'string' ? response.leaseToken.trim() : '';
      const url = normalizePhonePagePushUrl(task?.url);
      const title = normalizePhonePagePushTitle(task?.title) || PHONE_PAGE_PUSH_FALLBACK_TITLE;
      if (!taskId || !leaseToken || !url) {
        return false;
      }

      nextDelayMs = 0;
      const opened = await openPhonePagePushTab(url, title);
      await ackPhonePagePushTask({
        desktopPushToken: profile.desktopPushToken,
        taskId,
        leaseToken,
        status: opened ? 'opened' : 'failed',
        error: opened ? '' : 'tabs.create unavailable or failed',
      }).catch((error) => {
        console.warn('[Aira][PhonePush] ack failed', error);
      });
      return opened;
    } catch (error) {
      nextDelayMs = PHONE_PAGE_PUSH_ERROR_RETRY_MS;
      console.warn('[Aira][PhonePush] poll failed', error);
      return false;
    } finally {
      keepAlive.stop();
      schedulePhonePagePushPollTimer(nextDelayMs);
      await schedulePhonePagePushPollAlarm(PHONE_PAGE_PUSH_ALARM_FALLBACK_MS);
    }
  })();

  try {
    return await activePhonePagePushPollPromise;
  } finally {
    activePhonePagePushPollPromise = null;
  }
}

function createBaselineStorageKeyForRemote(remoteKind: LeafTabSyncRemoteKind, rootPath: string, uid?: string) {
  const suffix = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  if (remoteKind === 'aira-cloud') {
    const safeUid = (uid || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_v1_baseline:aira_cloud:${safeUid}:${suffix}`;
  }
  return `leaftab_sync_v1_baseline:${suffix}`;
}

async function getOrCreateDeviceId(): Promise<string> {
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
}

async function readBackgroundSyncConfig(): Promise<BackgroundSyncConfig> {
  const [deviceId, loginProfile, webdavConfig, sharedRecord] = await Promise.all([
    getOrCreateDeviceId(),
    readAiraDesktopLoginProfileFromExtensionStorage(),
    readWebdavConfigFromExtensionStorage({ allowDisabled: true }),
    readExtensionStorageRecord([
      AIRA_CLOUD_SYNC_ENABLED_KEY,
      LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
      LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
      WEBDAV_STORAGE_KEYS.syncEnabled,
    ]),
  ]);
  const rootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const cloudUid = loginProfile?.uid?.trim() || '';
  const cloudDesktopPushToken = loginProfile?.desktopPushToken?.trim() || '';
  const cloudEntitled = isAiraDesktopProfilePro(loginProfile);
  const selectedSourceResolution = resolveLeafTabSelectedSyncSource({
    selectedSource: sharedRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY],
    airaCloudEnabled: sharedRecord[AIRA_CLOUD_SYNC_ENABLED_KEY],
    webdavEnabled: sharedRecord[WEBDAV_STORAGE_KEYS.syncEnabled],
  });
  const selectedSource = selectedSourceResolution.source;
  if (selectedSourceResolution.needsMigration && selectedSource) {
    await writeExtensionStorageRecord({
      [LEAFTAB_SELECTED_SYNC_SOURCE_KEY]: selectedSource,
    });
  }
  const hasPendingConflict = Boolean(sharedRecord[LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY]);

  return {
    deviceId,
    cloudUid,
    cloudDesktopPushToken,
    cloudEntitled,
    selectedSource,
    hasPendingConflict,
    webdavConfig: webdavConfig?.url
      ? {
          ...webdavConfig,
          rootPath,
          requestPermission: false,
        }
      : null,
    rootPath,
    webdavBaselineStorageKey: createBaselineStorageKeyForRemote('webdav', rootPath),
    cloudBaselineStorageKey: createBaselineStorageKeyForRemote('aira-cloud', rootPath, cloudUid),
  };
}

function canRunBackgroundAutoSync(config: BackgroundSyncConfig): boolean {
  if (config.hasPendingConflict) {
    return false;
  }
  return canRunLeafTabSelectedAutoSync({
    selectedSource: config.selectedSource,
    cloudUid: config.cloudUid,
    cloudDesktopPushToken: config.cloudDesktopPushToken,
    cloudEntitled: config.cloudEntitled,
    webdavUrl: config.webdavConfig?.url || '',
  });
}

async function buildLocalSnapshot(
  baselineStorageKey: string,
  deviceId: string,
): Promise<LeafTabSyncSnapshot> {
  const scope = getDefaultLeafTabBookmarkSyncScope();
  const bookmarkTree = await captureLeafTabBookmarkTreeDraft({
    scope,
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
      scope: getDefaultLeafTabBookmarkSyncScope(),
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

async function createBookmarkSyncModuleForBackground(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
  pendingLocalChanges: boolean,
  options?: {
    webdavRequestTimeoutMs?: number;
  },
): Promise<BookmarkSyncModule> {
  const rootPath = config.rootPath;
  const baselineStorageKey = remoteKind === 'aira-cloud'
    ? config.cloudBaselineStorageKey
    : config.webdavBaselineStorageKey;
  return new BookmarkSyncModule({
    sourceConfig: remoteKind === 'aira-cloud'
      ? {
          source: 'aira-cloud',
          uid: config.cloudUid,
          desktopPushToken: config.cloudDesktopPushToken,
        }
      : {
          source: 'webdav',
          webdav: {
            url: config.webdavConfig?.url || '',
            username: config.webdavConfig?.username,
            password: config.webdavConfig?.password,
            rootPath,
            requestPermission: false,
            requestTimeoutMs: options?.webdavRequestTimeoutMs,
          },
        },
    deviceId: config.deviceId,
    rootPath,
    baselineStorageKey,
    local: {
      buildSnapshot: () => buildLocalSnapshot(baselineStorageKey, config.deviceId),
      applySnapshot: applyLocalSnapshot,
      hasPendingChanges: () => pendingLocalChanges,
      hasPendingOperations: hasPendingLeafTabLocalBookmarkOperationOutbox,
      clearPendingChanges: () => {
        void clearPendingLeafTabLocalBookmarkChangesInExtensionStorage();
      },
      buildPendingOperations: (baseSnapshot) => buildLeafTabPendingLocalOperationsFromOutbox({
        baseSnapshot,
        deviceId: config.deviceId,
      }),
      clearPendingOperations: () => clearLeafTabLocalBookmarkOperationOutbox(),
      createEmptySnapshot: () => ({
        meta: {
          version: 2,
          deviceId: config.deviceId,
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
            updatedBy: config.deviceId,
            revision: 1,
          },
        },
        tombstones: {},
      }),
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
  const module = await createBookmarkSyncModuleForBackground(config, remoteKind, pendingLocalChanges, {
    webdavRequestTimeoutMs: options?.webdavRequestTimeoutMs,
  });
  return module.sync({
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
    webdav_last_sync_at: nowIso,
    [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: '',
  });
  await removeExtensionStorageKeys([
    'webdav_last_error_at',
    'webdav_last_error_message',
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
    webdav_last_error_at: nowIso,
    webdav_last_error_message: message,
    [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError]: message,
  });
}

async function probeSyncPreflightForKind(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
): Promise<LeafTabBookmarkSyncChangeProbeResult> {
  const pendingLocalChanges = (await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage()) > 0;
  const module = await createBookmarkSyncModuleForBackground(config, remoteKind, pendingLocalChanges);
  return module.probeChanges();
}
async function skipBackgroundSyncAsUnchanged(
  provider: LeafTabSyncRemoteKind,
  probe: LeafTabBookmarkSyncChangeProbeResult,
): Promise<void> {
  await updateBackgroundDebugState({
    lastSyncFinishedAt: getNowIso(),
    lastResult: 'skipped',
    lastReason: `${provider}:unchanged`,
    lastError: '',
    lastTriggerProvider: provider,
    cloudRemoteCommitId: provider === 'aira-cloud' ? (probe.remoteCommitId || '') : undefined,
    webdavRemoteCommitId: provider === 'webdav' ? (probe.remoteCommitId || '') : undefined,
    pendingLocalChangedAt: '',
  });
  await removeExtensionStorageKeys([
    LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
    LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
    WEBDAV_STORAGE_KEYS.nextSyncAt,
  ]);
}

function isActionRequiredSyncError(error: unknown): boolean {
  if (error instanceof LeafTabSyncWebdavTopologyError) return true;
  if (error instanceof LeafTabSyncWebdavError) {
    return error.status === 401 || error.status === 403;
  }
  if (error instanceof LeafTabSyncAiraCloudError) {
    return [
      'invalid_desktop_push_token',
      'desktop_session_expired',
      'pro_required',
      'extension_sync_requires_aira_primary',
      'invalid_sync_topology',
    ].includes(error.code);
  }
  const message = String((error as Error)?.message || error || '');
  return /请先|重新扫码|权限|认证|凭据|不是 App 当前的主同步|尚未由 Aira App 初始化/i.test(message);
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
      const entitled = await refreshDesktopMembershipForProFeature().catch(() => false);
      if (!entitled) {
        const error = new LeafTabSyncAiraCloudError(
          'Aira 云同步需要有效的 Pro 权限，请恢复权限后重试。',
          'pro_required',
        );
        await markSyncError(remoteKind, error);
        await updateBackgroundDebugState({
          lastSyncStartedAt: getNowIso(),
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'action-required',
          lastReason: 'pro_required',
          lastError: error.message,
        });
        return false;
      }
    }

    const baselineStorageKey = remoteKind === 'aira-cloud'
      ? config.cloudBaselineStorageKey
      : config.webdavBaselineStorageKey;
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

    const keepAlive = startBackgroundKeepAlive();
    try {
      if (!(trigger?.hasRemoteChanges === true && trigger.provider === remoteKind)) {
        const preflight = await probeSyncPreflightForKind(config, remoteKind);
        await updateBackgroundDebugState({
          cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (preflight.remoteCommitId || '') : undefined,
          webdavRemoteCommitId: remoteKind === 'webdav' ? (preflight.remoteCommitId || '') : undefined,
        });
        if (preflight.canSkipSync) {
          await skipBackgroundSyncAsUnchanged(remoteKind, preflight);
          return false;
        }
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
    const probe = await probeSyncPreflightForKind(config, remoteKind).catch(() => null);
    if (probe) {
      await updateBackgroundDebugState({
        cloudBaselineCommitId: remoteKind === 'aira-cloud' ? (probe.baselineCommitId || '') : undefined,
        cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (probe.remoteCommitId || '') : undefined,
        webdavBaselineCommitId: remoteKind === 'webdav' ? (probe.baselineCommitId || '') : undefined,
        webdavRemoteCommitId: remoteKind === 'webdav' ? (probe.remoteCommitId || '') : undefined,
        lastTriggerProvider: probe.provider,
      });
    }
    if (probe?.hasRemoteChanges) {
      await runBackgroundAutoSync({ provider: remoteKind, hasRemoteChanges: true });
      return;
    }
  } finally {
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

function bindAlarmListeners(): void {
  const alarms = getAlarmsApi();
  if (!alarms?.onAlarm) {
    return;
  }
  alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === LOCAL_SYNC_ALARM_NAME) {
      void handleLocalChangeAlarm();
      return;
    }
    if (alarm.name === REMOTE_PROBE_ALARM_NAME) {
      void handleRemoteProbeAlarm();
      return;
    }
    if (alarm.name === PHONE_PAGE_PUSH_POLL_ALARM_NAME) {
      void pollPhonePagePushOnce();
    }
  });
}

function bindLifecycleListeners(): void {
  const runtime = getRuntime();
  runtime?.onStartup?.addListener?.(() => {
    void updateBackgroundDebugState({
      lastWakeAt: getNowIso(),
    });
    void reconcileBackgroundSchedules(true);
    void reconcilePhonePagePushSchedule(true);
    void pollPhonePagePushOnce();
  });
  runtime?.onInstalled?.addListener?.(() => {
    void updateBackgroundDebugState({
      lastWakeAt: getNowIso(),
    });
    void reconcileBackgroundSchedules(true);
    void reconcilePhonePagePushSchedule(true);
    void pollPhonePagePushOnce();
  });
  getIdleApi()?.onStateChanged?.addListener?.((_state) => {
    void reconcileBackgroundSchedules();
  });
  getStorageApi()?.onChanged?.addListener?.((changes, areaName) => {
    if (areaName !== 'local') {
      return;
    }
    const relevantKeys = [
      AIRA_CLOUD_SYNC_ENABLED_KEY,
      LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
      LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
      WEBDAV_STORAGE_KEYS.syncEnabled,
      WEBDAV_STORAGE_KEYS.url,
      WEBDAV_STORAGE_KEYS.username,
      WEBDAV_STORAGE_KEYS.password,
      'aira_desktop_login_profile_v1',
      'aira_phone_page_push_enabled_v1',
    ];
    if (Object.keys(changes).some((key) => relevantKeys.includes(key))) {
      void reconcileBackgroundSchedules();
      void reconcilePhonePagePushSchedule();
      void pollPhonePagePushOnce();
      if (Object.prototype.hasOwnProperty.call(changes, 'aira_phone_page_push_enabled_v1')) {
        const nextValue = changes.aira_phone_page_push_enabled_v1?.newValue;
        phonePagePushEnabled = nextValue === undefined ? true : String(nextValue) !== 'false';
      }
    }
  });
}

function bindWebdavProxyMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message) return;
    if (message.type === AUTO_SYNC_MESSAGE_TYPE) {
      const provider = message.provider === 'webdav' || message.provider === 'aira-cloud'
        ? message.provider
        : undefined;
      void runBackgroundAutoSync({ provider }).then((ok) => {
        sendResponse({ success: ok });
      }).catch((error) => {
        sendResponse({
          success: false,
          error: String((error as Error)?.message || error || 'unknown'),
        });
      });
      return true;
    }
    if (message.type !== WEBDAV_PROXY_MESSAGE_TYPE) return;

    const payload = message.payload || {};
    const method = String(payload.method || 'GET').toUpperCase();
    const url = typeof payload.url === 'string' ? payload.url : '';
    const rawHeaders = payload.headers && typeof payload.headers === 'object' ? payload.headers : {};
    const body = typeof payload.body === 'string' ? payload.body : undefined;
    const timeoutMs = Number.isFinite(Number(payload.timeoutMs))
      ? Math.max(1_000, Number(payload.timeoutMs))
      : 15_000;

    if (!url) {
      sendResponse({ success: false, error: 'Invalid WebDAV URL' });
      return;
    }

    const headers: Record<string, string> = {};
    Object.entries(rawHeaders).forEach(([key, value]) => {
      if (typeof value === 'string') headers[key] = value;
    });

    (async () => {
      const controller = new AbortController();
      const timeout = globalThis.setTimeout(() => {
        controller.abort();
      }, timeoutMs);
      try {
        const response = await fetch(url, {
          method,
          headers,
          body,
          signal: controller.signal,
        });
        const responseText = await response.text();
        sendResponse({
          success: true,
          status: response.status,
          ok: response.ok,
          bodyText: responseText,
        });
      } catch (error) {
        console.error('[Aira][WebDAV proxy]', method, url, error);
        sendResponse({
          success: false,
          error: String(error instanceof Error ? error.message : error),
        });
      } finally {
        globalThis.clearTimeout(timeout);
      }
    })();

    return true;
  });
}

function bindPhonePagePushMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    const normalized = normalizePhonePagePushMessage(message);
    if (!normalized) return;
    void (async () => {
      if (!phonePagePushEnabled) {
        sendResponse({
          success: false,
          error: 'Phone page push is disabled',
        });
        return;
      }
      const entitled = await refreshDesktopMembershipForProFeature().catch(() => false);
      if (!entitled) {
        sendResponse({
          success: false,
          error: 'Aira Pro is required',
        });
        return;
      }

      const payload = normalized.payload;
      if (!payload?.url) {
        sendResponse({
          success: false,
          error: 'Invalid phone page push URL',
        });
        return;
      }

      const opened = await openPhonePagePushTab(payload.url, payload.title || PHONE_PAGE_PUSH_FALLBACK_TITLE);
      sendResponse({
        success: opened,
        error: opened ? undefined : 'Unable to open pushed page',
      });
    })();
    return true;
  });
}

bindWebdavProxyMessageListener();
bindPhonePagePushMessageListener();
bindBookmarkListeners();
bindAlarmListeners();
bindLifecycleListeners();
void readPhonePagePushEnabledFromExtensionStorage()
  .then((enabled) => {
    phonePagePushEnabled = enabled;
  })
  .catch(() => undefined);
void reconcilePhonePagePushSchedule(true);
void pollPhonePagePushOnce();
void updateBackgroundDebugState({
  lastWakeAt: getNowIso(),
  lastResult: 'idle',
});
void reconcileBackgroundSchedules();
