import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_SYNC_ENABLED_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_BOOKMARK_AUTO_SYNC_ENABLED_KEY,
  LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  readAiraDesktopLoginProfileFromExtensionStorage,
} from '@/popup/desktopLogin';
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
import { LeafTabSyncAiraCloudStore } from '@/sync/leaftab/airaCloudStore';
import {
  clearPendingLeafTabLocalBookmarkChangesInExtensionStorage,
  markLeafTabLocalBookmarkChangedInExtensionStorage,
  readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage,
} from '@/sync/leaftab/localChangeTracker';
import {
  appendLeafTabLocalBookmarkOperationEvent,
  buildLeafTabPendingLocalOperationsFromOutbox,
  clearLeafTabLocalBookmarkOperationOutbox,
} from '@/sync/leaftab/localOperationOutbox';
import {
  LeafTabSyncEngine,
  type LeafTabSyncEngineResult,
  type LeafTabSyncInitialChoice,
} from '@/sync/leaftab/engine';
import type { LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import {
  buildLeafTabSyncSnapshot,
  createLeafTabSyncBuildState,
  normalizeLeafTabLiveBookmarkSnapshot,
} from '@/sync/leaftab/snapshot';
import {
  createLeafTabDualSecondarySyncPlan,
  resolveLeafTabSyncRoute,
  type LeafTabSyncRemoteKind,
} from '@/sync/leaftab/syncRouteStateMachine';
import { LeafTabSyncWebdavStore } from '@/sync/leaftab/webdavStore';
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
const LOCAL_SYNC_ALARM_NAME = 'aira.leaftab.auto-sync.local-change';
const REMOTE_PROBE_ALARM_NAME = 'aira.leaftab.auto-sync.remote-probe';
const AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES = 1;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_STARTUP_DELAY_MINUTES = 1;
const AUTO_SYNC_REMOTE_PROBE_ACTIVE_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_BACKGROUND_INTERVAL_MINUTES = 3;
const AUTO_SYNC_REMOTE_PROBE_IDLE_DETECTION_SECONDS = 90;
const AUTO_SYNC_APPLY_SUPPRESS_MS = 20_000;
const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = 'aira/v1/bookmarks';
const LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX = 'leaftab_sync_v1_analysis';
const BACKGROUND_KEEPALIVE_INTERVAL_MS = 20_000;
const WEBDAV_BACKUP_REQUEST_TIMEOUT_MS = 3_000;
const WEBDAV_BACKUP_TOTAL_TIMEOUT_MS = 8_000;

let activeAutoSyncPromise: Promise<boolean> | null = null;
let bookmarkApplySuppressedUntil = 0;

type BackgroundSyncConfig = {
  deviceId: string;
  cloudUid: string;
  cloudEnabled: boolean;
  webdavEnabled: boolean;
  bookmarkAutoSyncEnabled: boolean;
  bookmarkAutoSyncEntitled: boolean;
  primaryRemoteKind: LeafTabSyncRemoteKind | null;
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

function createBaselineStorageKeyForRemote(remoteKind: LeafTabSyncRemoteKind, rootPath: string, uid?: string) {
  const suffix = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  if (remoteKind === 'aira-cloud') {
    const safeUid = (uid || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_v1_baseline:aira_cloud:${safeUid}:${suffix}`;
  }
  return `leaftab_sync_v1_baseline:${suffix}`;
}

function createStorageHash(source: string): string {
  let hash = 0;
  for (let index = 0; index < source.length; index += 1) {
    hash = ((hash << 5) - hash + source.charCodeAt(index)) | 0;
  }
  return Math.abs(hash).toString(36);
}

function createAnalysisCacheKey(
  remoteKind: LeafTabSyncRemoteKind,
  rootPath: string,
  identity: string,
): string {
  const rootSegment = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  return `${LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX}:${remoteKind}:${rootSegment}:${createStorageHash(identity || 'default')}`;
}

async function writeAnalysisCacheForRemote(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
  result: LeafTabSyncEngineResult,
): Promise<void> {
  const summary = result.snapshotSummary;
  const analysis = {
    hasBaseline: true,
    localSummary: {
      bookmarkFolders: summary.bookmarkFolders,
      bookmarkItems: summary.bookmarkItems,
      tombstones: summary.tombstones,
    },
    remoteSummary: {
      bookmarkFolders: summary.bookmarkFolders,
      bookmarkItems: summary.bookmarkItems,
      tombstones: summary.tombstones,
    },
    requiresInitialChoice: false,
    suggestedInitialChoice: null,
    remoteCommitId: result.remoteCommitId,
  };
  const updatedAt = getNowIso();
  const cacheKey = createAnalysisCacheKey(
    remoteKind,
    config.rootPath,
    remoteKind === 'aira-cloud' ? config.cloudUid : (config.webdavConfig?.url || ''),
  );
  await writeExtensionStorageRecord({
    [cacheKey]: JSON.stringify({
      version: 1,
      updatedAt,
      analysis,
    }),
  });
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
      LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY,
      LEAFTAB_BOOKMARK_AUTO_SYNC_ENABLED_KEY,
      WEBDAV_STORAGE_KEYS.syncEnabled,
    ]),
  ]);
  const rootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const cloudUid = loginProfile?.uid?.trim() || '';
  const cloudEnabled = String(sharedRecord[AIRA_CLOUD_SYNC_ENABLED_KEY] ?? 'false') === 'true';
  const webdavEnabled = String(sharedRecord[WEBDAV_STORAGE_KEYS.syncEnabled] ?? 'false') === 'true';
  const bookmarkAutoSyncEnabled = String(sharedRecord[LEAFTAB_BOOKMARK_AUTO_SYNC_ENABLED_KEY] ?? 'true') !== 'false';
  const bookmarkAutoSyncEntitled = String(loginProfile?.membershipPlan || '').trim() === 'pro';
  const primaryRemoteKind = sharedRecord[LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY] === 'webdav'
    ? 'webdav'
    : (sharedRecord[LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY] === 'aira-cloud' ? 'aira-cloud' : null);

  return {
    deviceId,
    cloudUid,
    cloudEnabled,
    webdavEnabled,
    bookmarkAutoSyncEnabled,
    bookmarkAutoSyncEntitled,
    primaryRemoteKind,
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
  return config.bookmarkAutoSyncEnabled && config.bookmarkAutoSyncEntitled;
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

async function createEngineForRemote(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
  pendingLocalChanges: boolean,
  options?: {
    webdavRequestTimeoutMs?: number;
  },
) {
  const rootPath = config.rootPath;
  const baselineStorageKey = remoteKind === 'aira-cloud'
    ? config.cloudBaselineStorageKey
    : config.webdavBaselineStorageKey;
  const remoteStore = remoteKind === 'aira-cloud'
    ? new LeafTabSyncAiraCloudStore(config.cloudUid)
    : new LeafTabSyncWebdavStore({
        url: config.webdavConfig?.url || '',
        username: config.webdavConfig?.username,
        password: config.webdavConfig?.password,
        rootPath,
        requestPermission: false,
        requestTimeoutMs: options?.webdavRequestTimeoutMs,
      });

  return new LeafTabSyncEngine({
    deviceId: config.deviceId,
    remoteStore,
    baselineStore: new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey),
    buildLocalSnapshot: () => buildLocalSnapshot(baselineStorageKey, config.deviceId),
    applyLocalSnapshot,
    hasPendingLocalChanges: () => pendingLocalChanges,
    clearPendingLocalChanges: () => {
      void clearPendingLeafTabLocalBookmarkChangesInExtensionStorage();
    },
    buildPendingLocalOperations: (baseSnapshot) => buildLeafTabPendingLocalOperationsFromOutbox({
      baseSnapshot,
      deviceId: config.deviceId,
    }),
    clearPendingLocalOperations: () => clearLeafTabLocalBookmarkOperationOutbox(),
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
    rootPath,
  });
}

async function runSingleRemoteSync(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
  options?: {
    mode?: LeafTabSyncInitialChoice | 'auto';
    localSnapshotOverride?: LeafTabSyncSnapshot;
    webdavRequestTimeoutMs?: number;
  },
): Promise<LeafTabSyncEngineResult> {
  const pendingLocalChanges = (await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage()) > 0;
  const engine = await createEngineForRemote(config, remoteKind, pendingLocalChanges, {
    webdavRequestTimeoutMs: options?.webdavRequestTimeoutMs,
  });
  return engine.sync(options?.mode || 'auto', {
    localSnapshotOverride: options?.localSnapshotOverride,
    onProgress: (progress) => {
      void updateBackgroundDebugState({
        lastReason: `${remoteKind}:${progress.stage}:${progress.message}`,
      });
    },
  });
}

async function withTimeout<T>(task: Promise<T>, timeoutMs: number, message: string): Promise<T> {
  let timeoutId: ReturnType<typeof globalThis.setTimeout> | null = null;
  try {
    return await Promise.race([
      task,
      new Promise<T>((_resolve, reject) => {
        timeoutId = globalThis.setTimeout(() => {
          reject(new Error(message));
        }, timeoutMs);
      }),
    ]);
  } finally {
    if (timeoutId !== null) {
      globalThis.clearTimeout(timeoutId);
    }
  }
}

async function markSyncSuccess(remoteKind: LeafTabSyncRemoteKind): Promise<void> {
  const nowIso = getNowIso();
  if (remoteKind === 'aira-cloud') {
    await writeExtensionStorageRecord({
      [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso,
      [LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY]: nowIso,
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
    [LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY]: nowIso,
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

async function readBaselineCommitId(
  baselineStorageKey: string,
): Promise<string | null | undefined> {
  const baseline = await new LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey).load();
  if (!baseline) return undefined;
  return typeof baseline.commitId === 'string' && baseline.commitId.length > 0
    ? baseline.commitId
    : null;
}

async function probeRemoteChangesForKind(
  config: BackgroundSyncConfig,
  remoteKind: LeafTabSyncRemoteKind,
): Promise<{
  hasChanges: boolean;
  provider: LeafTabSyncRemoteKind;
  baselineCommitId: string | null;
  remoteCommitId: string | null;
}> {
  const baselineCommitId = await readBaselineCommitId(
    remoteKind === 'aira-cloud' ? config.cloudBaselineStorageKey : config.webdavBaselineStorageKey,
  );
  const store = remoteKind === 'aira-cloud'
    ? new LeafTabSyncAiraCloudStore(config.cloudUid)
    : new LeafTabSyncWebdavStore({
        url: config.webdavConfig?.url || '',
        username: config.webdavConfig?.username,
        password: config.webdavConfig?.password,
        rootPath: config.rootPath,
        requestPermission: false,
      });
  const remoteHead = store.readHead ? await store.readHead() : null;
  const remoteCommitId = remoteHead?.commitId ?? null;
  const hasChanges = remoteCommitId === null
    ? Boolean(baselineCommitId)
    : (baselineCommitId === undefined || baselineCommitId === null || baselineCommitId.length <= 0
      ? true
      : remoteCommitId !== baselineCommitId);
  return {
    hasChanges,
    provider: remoteKind,
    baselineCommitId: baselineCommitId ?? null,
    remoteCommitId,
  };
}

async function runBackgroundAutoSync(trigger?: BackgroundSyncTrigger): Promise<boolean> {
  if (activeAutoSyncPromise) {
    return activeAutoSyncPromise;
  }
  activeAutoSyncPromise = (async () => {
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      await updateBackgroundDebugState({
        lastSyncStartedAt: getNowIso(),
        lastSyncFinishedAt: getNowIso(),
        lastResult: 'skipped',
        lastReason: config.bookmarkAutoSyncEnabled ? 'pro_required' : 'auto_sync_disabled',
      });
      return false;
    }
    const keepAlive = startBackgroundKeepAlive();
    const route = resolveLeafTabSyncRoute({
      cloudEnabled: config.cloudEnabled,
      cloudAvailable: Boolean(config.cloudUid),
      webdavEnabled: config.webdavEnabled,
      webdavAvailable: Boolean(config.webdavConfig?.url),
      preferredPrimaryRemoteKind: config.primaryRemoteKind ?? undefined,
      triggerProvider: trigger?.provider,
    });
    const [cloudBaselineCommitId, webdavBaselineCommitId] = await Promise.all([
      config.cloudEnabled && config.cloudUid
        ? readBaselineCommitId(config.cloudBaselineStorageKey).catch(() => null)
        : Promise.resolve(null),
      config.webdavEnabled && config.webdavConfig?.url
        ? readBaselineCommitId(config.webdavBaselineStorageKey).catch(() => null)
        : Promise.resolve(null),
    ]);
    const routeLabel = route.kind === 'single'
      ? `single:${route.remoteKind}`
      : route.kind === 'dual'
        ? `dual:${route.primaryRemoteKind}->${route.secondaryRemoteKind}`
        : `none:${route.reason}`;
    await updateBackgroundDebugState({
      lastSyncStartedAt: getNowIso(),
      lastSyncFinishedAt: '',
      lastTriggerProvider: trigger?.provider || '',
      lastRoute: routeLabel,
      lastResult: route.kind === 'none' ? 'skipped' : 'running',
      lastReason: route.kind === 'none' ? route.reason : '',
      lastError: '',
      cloudBaselineCommitId: cloudBaselineCommitId || '',
      webdavBaselineCommitId: webdavBaselineCommitId || '',
    });
    if (route.kind === 'none') {
      return false;
    }

    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRunning]: 'true',
    });

    try {
      if (route.kind === 'single') {
        await updateBackgroundDebugState({
          lastReason: `syncing:${route.remoteKind}`,
        });
        const result = await runSingleRemoteSync(config, route.remoteKind);
        if (result.kind === 'conflict') {
          await updateBackgroundDebugState({
            lastSyncFinishedAt: getNowIso(),
            lastResult: 'conflict',
            lastReason: route.remoteKind,
            cloudRemoteCommitId: route.remoteKind === 'aira-cloud' ? (result.remoteCommitId || '') : undefined,
            webdavRemoteCommitId: route.remoteKind === 'webdav' ? (result.remoteCommitId || '') : undefined,
          });
          return false;
        }
        await writeAnalysisCacheForRemote(config, route.remoteKind, result);
        await markSyncSuccess(route.remoteKind);
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'success',
          lastReason: route.remoteKind,
          lastError: '',
          cloudRemoteCommitId: route.remoteKind === 'aira-cloud' ? (result.remoteCommitId || '') : undefined,
          webdavRemoteCommitId: route.remoteKind === 'webdav' ? (result.remoteCommitId || '') : undefined,
          pendingLocalChangedAt: '',
        });
        await removeExtensionStorageKeys([
          LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
          WEBDAV_STORAGE_KEYS.nextSyncAt,
        ]);
        return true;
      }

      await updateBackgroundDebugState({
        lastReason: `syncing-primary:${route.primaryRemoteKind}`,
      });
      const primaryResult = await runSingleRemoteSync(config, route.primaryRemoteKind, {
        localSnapshotOverride: undefined,
      });
      if (primaryResult.kind === 'conflict') {
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'conflict',
          lastReason: `${route.primaryRemoteKind}:primary`,
        });
        return false;
      }
      await writeAnalysisCacheForRemote(config, route.primaryRemoteKind, primaryResult);
      await markSyncSuccess(route.primaryRemoteKind);

      const secondaryPlan = createLeafTabDualSecondarySyncPlan(route, primaryResult);
      await updateBackgroundDebugState({
        lastReason: `syncing-secondary:${route.secondaryRemoteKind}`,
      });
      let secondaryResult: LeafTabSyncEngineResult | null = null;
      let secondaryError: unknown = null;
      try {
        const secondaryTask = runSingleRemoteSync(config, route.secondaryRemoteKind, {
          localSnapshotOverride: secondaryPlan.snapshot,
          mode: secondaryPlan.mode,
          webdavRequestTimeoutMs: route.secondaryRemoteKind === 'webdav'
            ? WEBDAV_BACKUP_REQUEST_TIMEOUT_MS
            : undefined,
        });
        secondaryResult = route.secondaryRemoteKind === 'webdav'
          ? await withTimeout(
              secondaryTask,
              WEBDAV_BACKUP_TOTAL_TIMEOUT_MS,
              'WebDAV 备份连接超时，已跳过本次备份，不影响主同步。',
            )
          : await secondaryTask;
      } catch (error) {
        secondaryError = error;
      }
      if (secondaryError !== null) {
        await markSyncError(route.secondaryRemoteKind, secondaryError);
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'success',
          lastReason: `${route.primaryRemoteKind}+${route.secondaryRemoteKind}:backup-failed`,
          lastError: String((secondaryError as Error)?.message || secondaryError || 'unknown'),
          cloudRemoteCommitId: route.primaryRemoteKind === 'aira-cloud'
            ? (primaryResult.remoteCommitId || '')
            : '',
          webdavRemoteCommitId: route.primaryRemoteKind === 'webdav'
            ? (primaryResult.remoteCommitId || '')
            : '',
          pendingLocalChangedAt: '',
        });
        await removeExtensionStorageKeys([
          LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
          WEBDAV_STORAGE_KEYS.nextSyncAt,
        ]);
        return true;
      }
      if (secondaryResult === null) {
        return true;
      }
      if (secondaryResult.kind === 'conflict') {
        await markSyncError(route.secondaryRemoteKind, new Error('备份源需要处理冲突'));
        await updateBackgroundDebugState({
          lastSyncFinishedAt: getNowIso(),
          lastResult: 'success',
          lastReason: `${route.primaryRemoteKind}+${route.secondaryRemoteKind}:backup-conflict`,
          cloudRemoteCommitId: route.primaryRemoteKind === 'aira-cloud'
            ? (primaryResult.remoteCommitId || '')
            : (secondaryResult.remoteCommitId || ''),
          webdavRemoteCommitId: route.primaryRemoteKind === 'webdav'
            ? (primaryResult.remoteCommitId || '')
            : (secondaryResult.remoteCommitId || ''),
          pendingLocalChangedAt: '',
        });
        await removeExtensionStorageKeys([
          LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
          WEBDAV_STORAGE_KEYS.nextSyncAt,
        ]);
        return true;
      }
      await writeAnalysisCacheForRemote(config, route.secondaryRemoteKind, secondaryResult);
      await markSyncSuccess(route.secondaryRemoteKind);
      await updateBackgroundDebugState({
        lastSyncFinishedAt: getNowIso(),
        lastResult: 'success',
        lastReason: `${route.primaryRemoteKind}+${route.secondaryRemoteKind}`,
        lastError: '',
        cloudRemoteCommitId: route.primaryRemoteKind === 'aira-cloud'
          ? (primaryResult.remoteCommitId || '')
          : (secondaryResult.remoteCommitId || ''),
        webdavRemoteCommitId: route.primaryRemoteKind === 'webdav'
          ? (primaryResult.remoteCommitId || '')
          : (secondaryResult.remoteCommitId || ''),
        pendingLocalChangedAt: '',
      });
      await removeExtensionStorageKeys([
        LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
        WEBDAV_STORAGE_KEYS.nextSyncAt,
      ]);
      return true;
    } catch (error) {
      if (route.kind === 'single') {
        await markSyncError(route.remoteKind, error);
      } else {
        await markSyncError(route.primaryRemoteKind, error);
      }
      await updateBackgroundDebugState({
        lastSyncFinishedAt: getNowIso(),
        lastResult: 'error',
        lastError: String((error as Error)?.message || error || 'unknown'),
      });
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
  const scheduledAt = new Date(Date.now() + AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES * 60_000).toISOString();
  await updateBackgroundDebugState({
    lastLocalAlarmScheduledAt: scheduledAt,
  });
  await writeExtensionStorageRecord({
    [WEBDAV_STORAGE_KEYS.nextSyncAt]: scheduledAt,
  });
  alarms.create(LOCAL_SYNC_ALARM_NAME, {
    delayInMinutes: AUTO_SYNC_BOOKMARK_CHANGE_DELAY_MINUTES,
  });
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
  const hasAnySync = (config.cloudEnabled && Boolean(config.cloudUid))
    || (config.webdavEnabled && Boolean(config.webdavConfig?.url));
  if (!hasAnySync) {
    await clearBackgroundAlarms();
    return;
  }
  await scheduleRemoteProbeAlarm(await resolveRemoteProbeDelayMinutes(isStartup));
}

async function handleRemoteProbeAlarm(): Promise<void> {
  try {
    const config = await readBackgroundSyncConfig();
    if (!canRunBackgroundAutoSync(config)) {
      return;
    }
    const route = resolveLeafTabSyncRoute({
      cloudEnabled: config.cloudEnabled,
      cloudAvailable: Boolean(config.cloudUid),
      webdavEnabled: config.webdavEnabled,
      webdavAvailable: Boolean(config.webdavConfig?.url),
      preferredPrimaryRemoteKind: config.primaryRemoteKind ?? undefined,
    });
    if (route.kind === 'none') {
      return;
    }
    await writeExtensionStorageRecord({
      [LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt]: getNowIso(),
    });
    await updateBackgroundDebugState({
      lastRemoteProbeAt: getNowIso(),
    });
    const probeKinds: LeafTabSyncRemoteKind[] = route.kind === 'dual'
      ? [route.primaryRemoteKind]
      : [route.remoteKind];
    for (const remoteKind of probeKinds) {
      const probe = await probeRemoteChangesForKind(config, remoteKind).catch(() => null);
      if (probe) {
        await updateBackgroundDebugState({
          cloudBaselineCommitId: remoteKind === 'aira-cloud' ? (probe.baselineCommitId || '') : undefined,
          cloudRemoteCommitId: remoteKind === 'aira-cloud' ? (probe.remoteCommitId || '') : undefined,
          webdavBaselineCommitId: remoteKind === 'webdav' ? (probe.baselineCommitId || '') : undefined,
          webdavRemoteCommitId: remoteKind === 'webdav' ? (probe.remoteCommitId || '') : undefined,
          lastTriggerProvider: probe.provider,
        });
      }
      if (probe?.hasChanges) {
        await runBackgroundAutoSync({ provider: remoteKind });
        return;
      }
    }
  } finally {
    await reconcileBackgroundSchedules();
  }
}

async function handleLocalChangeAlarm(): Promise<void> {
  const pendingLocalChangedAt = await readPendingLeafTabLocalBookmarkChangedAtFromExtensionStorage();
  await updateBackgroundDebugState({
    lastLocalAlarmFiredAt: getNowIso(),
    pendingLocalChangedAt: pendingLocalChangedAt > 0 ? String(pendingLocalChangedAt) : '',
  });
  if (pendingLocalChangedAt <= 0) {
    await removeExtensionStorageKeys([
      LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
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
  await runBackgroundAutoSync();
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
  });
  runtime?.onInstalled?.addListener?.(() => {
    void updateBackgroundDebugState({
      lastWakeAt: getNowIso(),
    });
    void reconcileBackgroundSchedules(true);
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
      LEAFTAB_BOOKMARK_AUTO_SYNC_ENABLED_KEY,
      WEBDAV_STORAGE_KEYS.syncEnabled,
      WEBDAV_STORAGE_KEYS.url,
      WEBDAV_STORAGE_KEYS.username,
      WEBDAV_STORAGE_KEYS.password,
      WEBDAV_STORAGE_KEYS.syncBySchedule,
      WEBDAV_STORAGE_KEYS.syncIntervalMinutes,
      'aira_desktop_login_profile_v1',
    ];
    if (Object.keys(changes).some((key) => relevantKeys.includes(key))) {
      void reconcileBackgroundSchedules();
    }
  });
}

function bindWebdavProxyMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || message.type !== WEBDAV_PROXY_MESSAGE_TYPE) return;

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

bindWebdavProxyMessageListener();
bindBookmarkListeners();
bindAlarmListeners();
bindLifecycleListeners();
void updateBackgroundDebugState({
  lastWakeAt: getNowIso(),
  lastResult: 'idle',
});
void reconcileBackgroundSchedules();
