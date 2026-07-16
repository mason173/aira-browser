import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from '@/components/ui/sonner';
import type {
  LeafTabPendingBookmarkConflict,
  LeafTabSyncActions,
  LeafTabSyncFacade,
  LeafTabSyncProgressState,
  LeafTabSyncRemoteKind,
  LeafTabSyncState,
} from '@/features/sync/app/LeafTabSyncContracts';
import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  createLeafTabSyncBaselineStorageKey,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE,
  LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import type { LeafTabBookmarkTreeDraft } from '@/sync/leaftab/bookmarks';
import type {
  LeafTabSyncDataSummary,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { parseLeafTabSyncRemoteKind } from '@/sync/leaftab/source';
import { LeafTabSyncExtensionStorageBaselineStore } from '@/sync/leaftab/baseline';
import { useSyncState } from '@/sync/useSyncState';
import {
  readAllExtensionStorageRecords,
  readExtensionStorageRecord,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  markLeafTabBookmarkSyncApplyFinished,
  markLeafTabBookmarkSyncApplyStarted,
} from '@/sync/leaftab/localChangeTracker';
import {
  BookmarkSyncModule,
  clearPendingBookmarkConflict,
  createBookmarkSyncSourceIdentity,
  persistPendingBookmarkConflict,
  readPendingBookmarkConflict,
  type BookmarkSyncConflictChoice,
  type BookmarkSyncDataOverview,
  type BookmarkSyncSourceConfig,
} from './BookmarkSyncModule';
import {
  hasWebdavUrlConfiguredFromStorage,
  isWebdavSyncEnabledFromStorage,
  readWebdavConfigFromStorage,
  seedWebdavCredentialsToExtensionStorage,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';
import {
  refreshAiraDesktopConnectionProfileMembership,
  resolveAiraDesktopProCapability,
  type AiraDesktopConnectionProfile,
} from '@/features/desktop-connection/desktopConnectionProfile';
import { resolveAiraDesktopSyncStatus } from './desktopSyncEligibility';
import {
  isAiraCloudSyncPreferenceStorageKey,
  readAiraCloudSyncEnabledFromLocalStorage,
  writeAiraCloudSyncEnabled,
} from './airaCloudPreferences';
import { LeafTabSyncAiraCloudError } from '@/sync/leaftab/airaCloudStore';
import {
  isAiraDesktopCredentialRejection,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import { recordAiraDesktopConnectionFailure } from '@/features/desktop-connection/desktopConnectionRuntime';

type LeafTabSyncActionOptions = {
  silentSuccess?: boolean;
  requestBookmarkPermission?: boolean;
  showProgressIndicator?: boolean;
  progressTaskId?: string | null;
  onProgress?: (progress: LeafTabSyncEngineProgress) => void;
  enableAfterSuccess?: boolean;
  allowConfigPrompt?: boolean;
  remoteKind?: LeafTabSyncRemoteKind;
  localSnapshotOverride?: LeafTabSyncSnapshot;
  webdavRequestTimeoutMs?: number;
};

const formatLiteSyncTimestamp = (value: string | null | undefined) => {
  if (!value) return '';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return '';
  return parsed.toLocaleString('zh-CN', {
    hour12: false,
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const cacheLeafTabSyncDeviceId = (deviceId: string): void => {
  try {
    localStorage.setItem(LEAFTAB_SYNC_DEVICE_ID_KEY, deviceId);
  } catch {
    // Popup localStorage is only a UI cache; extension storage is authoritative.
  }
};

const resolveLeafTabSyncDeviceId = async (): Promise<string> => {
  const record = await readExtensionStorageRecord([LEAFTAB_SYNC_DEVICE_ID_KEY]);
  const stored = String(record[LEAFTAB_SYNC_DEVICE_ID_KEY] || '').trim();
  if (stored) {
    cacheLeafTabSyncDeviceId(stored);
    return stored;
  }
  const response = await chrome.runtime.sendMessage({
    type: LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE,
  }) as { success?: boolean; deviceId?: unknown; error?: unknown } | undefined;
  const deviceId = String(response?.deviceId || '').trim();
  if (response?.success !== true || !deviceId) {
    throw new Error(String(response?.error || '同步设备标识初始化失败'));
  }
  cacheLeafTabSyncDeviceId(deviceId);
  return deviceId;
};

const readLeafTabSyncBaselineSnapshot = async (storageKey: string): Promise<LeafTabSyncSnapshot | null> => {
  try {
    const baselineStore = new LeafTabSyncExtensionStorageBaselineStore(storageKey);
    const baseline = await baselineStore.load();
    return normalizeLeafTabSyncSnapshot(baseline?.snapshot || null);
  } catch {
    return null;
  }
};

const formatLeafTabSyncErrorMessage = (error: unknown, remoteKind: LeafTabSyncRemoteKind = 'webdav') => {
  const providerName = remoteKind === 'aira-cloud' ? 'Aira 云同步' : 'WebDAV';
  if (error && typeof error === 'object') {
    const status = Number((error as { status?: unknown }).status);
    const operation = String((error as { operation?: unknown }).operation || '');
    const relativePath = String((error as { relativePath?: unknown }).relativePath || '');
    if (Number.isInteger(status) && status > 0 && operation) {
      return relativePath
        ? `${providerName} ${operation} failed (${status}): ${relativePath}`
        : `${providerName} ${operation} failed (${status})`;
    }
  }
  return String((error as Error)?.message || `${providerName}失败`);
};

const recordAiraCloudCredentialFailure = async (error: unknown): Promise<void> => {
  if (error instanceof LeafTabSyncAiraCloudError && isAiraDesktopCredentialRejection(error)) {
    await recordAiraDesktopConnectionFailure(error).catch(() => null);
  }
};

const runtimeSummaryFromSnapshot = (snapshot: LeafTabSyncSnapshot) => ({
  bookmarkFolders: Object.keys(snapshot.bookmarkFolders || {}).length,
  bookmarkItems: Object.keys(snapshot.bookmarkItems || {}).length,
  tombstones: Object.keys(snapshot.tombstones || {}).length,
});

const createBookmarkDataOverviewFromSummary = (
  summary: LeafTabSyncDataSummary,
): BookmarkSyncDataOverview => ({
  local: summary,
  remote: summary,
});

const SHARED_EXTENSION_STORAGE_KEYS: string[] = [
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError,
  WEBDAV_STORAGE_KEYS.profileName,
  WEBDAV_STORAGE_KEYS.url,
  WEBDAV_STORAGE_KEYS.username,
  WEBDAV_STORAGE_KEYS.password,
  WEBDAV_STORAGE_KEYS.syncEnabled,
];

const isSharedSyncStorageKey = (key: string) => (
  SHARED_EXTENSION_STORAGE_KEYS.includes(key)
  || isAiraCloudSyncPreferenceStorageKey(key)
  || key === LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY
);

const refreshSyncUiCacheFromExtensionStorage = async () => {
  const record = await readAllExtensionStorageRecords();
  const storageKeys = Array.from(new Set([
    ...SHARED_EXTENSION_STORAGE_KEYS,
    ...Object.keys(record).filter(isAiraCloudSyncPreferenceStorageKey),
  ]));
  storageKeys.forEach((key) => {
    const value = record[key];
    if (value === undefined || value === null || value === '') {
      localStorage.removeItem(key);
      return;
    }
    localStorage.setItem(key, String(value));
  });
};

const createIdleProgressState = (): LeafTabSyncProgressState => ({
  open: false,
  inProgress: false,
  title: '',
  detail: '',
  progress: 0,
  remoteKind: null,
  latestProgress: null,
});

const readSelectedSyncSourceFromStorage = (): LeafTabSyncRemoteKind | null => {
  return parseLeafTabSyncRemoteKind(localStorage.getItem(LEAFTAB_SELECTED_SYNC_SOURCE_KEY));
};

const persistSelectedSyncSource = async (source: LeafTabSyncRemoteKind) => {
  await writeExtensionStorageRecord({
    [LEAFTAB_SELECTED_SYNC_SOURCE_KEY]: source,
  });
  localStorage.setItem(LEAFTAB_SELECTED_SYNC_SOURCE_KEY, source);
  window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
};

const resolveRemoteProgressName = (remoteKind: LeafTabSyncRemoteKind) => (
  remoteKind === 'aira-cloud' ? '云端' : 'WebDAV'
);

const resolveProgressDetail = (
  remoteKind: LeafTabSyncRemoteKind,
  message?: string,
) => {
  if (message) return message.replace('远端', remoteKind === 'webdav' ? 'WebDAV' : '云端');
  return `正在读取本机和${resolveRemoteProgressName(remoteKind)}书签`;
};

type RunWebdavBookmarkSyncOnceParams = {
  webdavConfig: NonNullable<ReturnType<typeof readWebdavConfigFromStorage>> & {
    rootPath: string;
    requestPermission: boolean;
  };
  deviceId: string;
  baselineStorageKey: string;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  options?: LeafTabRuntimeSyncOptions;
};

type RunAiraCloudBookmarkSyncOnceParams = {
  uid: string;
  deviceCredential: string;
  rootPath: string;
  deviceId: string;
  baselineStorageKey: string;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  options?: LeafTabRuntimeSyncOptions;
};

type LeafTabRuntimeSyncOptions = LeafTabSyncActionOptions & {
  selectSourceAfterSuccess?: boolean;
  conflictChoice?: BookmarkSyncConflictChoice;
  progressAlreadyOpen?: boolean;
};

type CreateBookmarkSyncModuleParams = {
  sourceConfig: BookmarkSyncSourceConfig;
  rootPath: string;
  deviceId: string;
  baselineStorageKey: string;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
};

const createBookmarkSyncModule = ({
  sourceConfig,
  rootPath,
  deviceId,
  baselineStorageKey,
  buildLocalSnapshot,
  applyLocalSnapshot,
}: CreateBookmarkSyncModuleParams) => new BookmarkSyncModule({
    sourceConfig,
    deviceId,
    rootPath,
    baselineStorageKey,
    local: {
      buildSnapshot: buildLocalSnapshot,
      applySnapshot: applyLocalSnapshot,
    },
    persistSelectedSource: persistSelectedSyncSource,
  });

const runBookmarkSyncWithModule = async (
  params: CreateBookmarkSyncModuleParams & { options?: LeafTabRuntimeSyncOptions },
) => {
  const module = createBookmarkSyncModule(params);
  const { options } = params;
  const runOptions = {
    localSnapshotOverride: options?.localSnapshotOverride,
    onProgress: options?.onProgress,
    conflictChoice: options?.conflictChoice,
  };
  if (options?.selectSourceAfterSuccess) {
    return module.syncAndSelectSource(runOptions);
  }
  if (options?.conflictChoice) {
    return module.resolveConflict(options.conflictChoice, runOptions);
  }
  return module.sync(runOptions);
};

const runWebdavBookmarkSyncOnce = async (params: RunWebdavBookmarkSyncOnceParams) => {
  return runBookmarkSyncWithModule({
    ...params,
    sourceConfig: {
      source: 'webdav',
      webdav: {
        url: params.webdavConfig.url,
        username: params.webdavConfig.username,
        password: params.webdavConfig.password,
        rootPath: params.webdavConfig.rootPath,
        requestPermission: params.webdavConfig.requestPermission,
        requestTimeoutMs: params.options?.webdavRequestTimeoutMs,
      },
    },
    rootPath: params.webdavConfig.rootPath,
  });
};

const runAiraCloudBookmarkSyncOnce = async (params: RunAiraCloudBookmarkSyncOnceParams) => {
  return runBookmarkSyncWithModule({
    ...params,
    sourceConfig: {
      source: 'aira-cloud',
      uid: params.uid,
      deviceCredential: params.deviceCredential,
    },
  });
};

export type BookmarkSyncRuntimeControllerParams = {
  openWebdavConfig: () => void;
  desktopConnectionProfile: AiraDesktopConnectionProfile | null;
};

export function useBookmarkSyncRuntimeController(
  params: BookmarkSyncRuntimeControllerParams,
): LeafTabSyncFacade {
  const { desktopConnectionProfile, openWebdavConfig } = params;
  const [localVersion, setLocalVersion] = useState(0);
  const [webdavSyncRunActive, setWebdavSyncRunActive] = useState(false);
  const [leafTabSyncLastResult, setLeafTabSyncLastResult] = useState<LeafTabSyncEngineResult | null>(null);
  const [leafTabBookmarkDataOverview, setLeafTabBookmarkDataOverview] =
    useState<BookmarkSyncDataOverview | null>(null);
  const [leafTabSummaryLoading, setLeafTabSummaryLoading] = useState(false);
  const leafTabSummaryRefreshRequestRef = useRef(0);
  const leafTabSummarySourceKeyRef = useRef('');
  const [leafTabSyncProgress, setLeafTabSyncProgress] = useState<LeafTabSyncProgressState>(() => createIdleProgressState());
  const [leafTabPendingBookmarkConflict, setLeafTabPendingBookmarkConflict] =
    useState<LeafTabPendingBookmarkConflict | null>(null);
  const [leafTabSyncDeviceId, setLeafTabSyncDeviceId] = useState('');
  const [syncStorageReady, setSyncStorageReady] = useState(false);
  const leafTabSyncRootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const leafTabSyncBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKey('webdav', leafTabSyncRootPath),
    [leafTabSyncRootPath],
  );
  const cloudUid = desktopConnectionProfile?.uid || '';
  const cloudDeviceCredential = desktopConnectionProfile?.deviceCredential || '';
  const cloudSyncEnabled = useMemo(() => {
    void localVersion;
    return readAiraCloudSyncEnabledFromLocalStorage(cloudUid);
  }, [cloudUid, localVersion]);
  const selectedSyncSource = useMemo(() => {
    void localVersion;
    return readSelectedSyncSourceFromStorage();
  }, [localVersion]);
  const cloudSyncEffectivelyEnabled = cloudSyncEnabled;
  const leafTabCloudSyncStatus = resolveAiraDesktopSyncStatus(desktopConnectionProfile, cloudSyncEffectivelyEnabled);
  const leafTabCloudBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKey('aira-cloud', leafTabSyncRootPath, cloudUid),
    [cloudUid, leafTabSyncRootPath],
  );
  const {
    syncState: leafTabSyncState,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
  } = useSyncState();

  const webdavConfig = useMemo(() => {
    void localVersion;
    const config = readWebdavConfigFromStorage({ allowDisabled: true });
    if (!config?.url) return null;
    return {
      ...config,
      rootPath: leafTabSyncRootPath,
      requestPermission: false,
    };
  }, [leafTabSyncRootPath, localVersion]);
  const captureBookmarkTreeDraft = useCallback(async (): Promise<LeafTabBookmarkTreeDraft> => {
    const snapshotRuntime = await import('@/sync/leaftab/snapshotRuntime');
    return snapshotRuntime.captureLeafTabBookmarkTreeDraft({
      requestPermission: true,
      throwOnPermissionDenied: true,
    });
  }, []);

  const buildBookmarkSnapshotFromTree = useCallback(async (
    baselineStorageKey: string,
    bookmarkTree: LeafTabBookmarkTreeDraft,
  ) => {
    const snapshotRuntime = await import('@/sync/leaftab/snapshotRuntime');
    const baselineSnapshot = await readLeafTabSyncBaselineSnapshot(baselineStorageKey);
    const generatedAt = new Date().toISOString();
    const state = snapshotRuntime.createLeafTabSyncBuildState({
      previousSnapshot: baselineSnapshot,
      bookmarkTree,
      deviceId: leafTabSyncDeviceId,
      generatedAt,
    });

    return snapshotRuntime.buildLeafTabSyncSnapshot({
      bookmarkTree,
      deviceId: leafTabSyncDeviceId,
      generatedAt,
      state,
    });
  }, [leafTabSyncDeviceId]);

  const buildBookmarkSnapshotForBaseline = useCallback(async (baselineStorageKey: string) => {
    const bookmarkTree = await captureBookmarkTreeDraft();
    return buildBookmarkSnapshotFromTree(baselineStorageKey, bookmarkTree);
  }, [buildBookmarkSnapshotFromTree, captureBookmarkTreeDraft]);

  const applyBookmarkSnapshot = useCallback(async (snapshot: LeafTabSyncSnapshot) => {
    const snapshotRuntime = await import('@/sync/leaftab/snapshotRuntime');
    const liveSnapshot = snapshotRuntime.normalizeLeafTabLiveBookmarkSnapshot(snapshot);
    const hasRemoteBookmarks = Object.keys(liveSnapshot.bookmarkFolders).length > 0
      || Object.keys(liveSnapshot.bookmarkItems).length > 0;
    const hasRootOrder = Object.values(liveSnapshot.bookmarkOrders).some((order) => {
      return order.parentId === 'browser_root_toolbar'
        || order.parentId === 'browser_root_other'
        || order.parentId === null;
    });
    if (hasRemoteBookmarks && !hasRootOrder) {
      throw new Error('同步书签快照缺少根目录排序，已停止写入本地以避免清空书签');
    }
    await markLeafTabBookmarkSyncApplyStarted();
    try {
      const applied = await snapshotRuntime.replaceLeafTabBookmarkTree({
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
      await markLeafTabBookmarkSyncApplyFinished();
    }
  }, []);

  const runLeafTabSyncOnce = useCallback(async (
    options?: LeafTabRuntimeSyncOptions,
  ) => {
    if (!webdavConfig?.url) {
      throw new Error('WebDAV is not configured');
    }
    markSyncStart();
    try {
      const result = await runWebdavBookmarkSyncOnce({
        webdavConfig,
        deviceId: leafTabSyncDeviceId,
        baselineStorageKey: leafTabSyncBaselineStorageKey,
        buildLocalSnapshot: () => options?.localSnapshotOverride
          ? Promise.resolve(options.localSnapshotOverride)
          : buildBookmarkSnapshotForBaseline(leafTabSyncBaselineStorageKey),
        applyLocalSnapshot: applyBookmarkSnapshot,
        options,
      });
      setLeafTabSyncLastResult(result);
      if (result.kind === 'conflict') {
        markSyncConflict();
      } else {
        markSyncSuccess();
      }
      return result;
    } catch (error) {
      markSyncError(String((error as Error)?.message || error || 'Sync failed'));
      throw error;
    }
  }, [
    applyBookmarkSnapshot,
    buildBookmarkSnapshotForBaseline,
    cloudUid,
    leafTabSyncBaselineStorageKey,
    leafTabSyncDeviceId,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
    webdavConfig,
  ]);

  const runCloudSyncOnce = useCallback(async (
    options?: LeafTabRuntimeSyncOptions,
  ) => {
    if (!cloudUid) {
      throw new Error('请先连接 Aira 桌面设备。');
    }
    markSyncStart();
    try {
      const result = await runAiraCloudBookmarkSyncOnce({
        uid: cloudUid,
        deviceCredential: cloudDeviceCredential,
        rootPath: leafTabSyncRootPath,
        deviceId: leafTabSyncDeviceId,
        baselineStorageKey: leafTabCloudBaselineStorageKey,
        buildLocalSnapshot: () => options?.localSnapshotOverride
          ? Promise.resolve(options.localSnapshotOverride)
          : buildBookmarkSnapshotForBaseline(leafTabCloudBaselineStorageKey),
        applyLocalSnapshot: applyBookmarkSnapshot,
        options,
      });
      setLeafTabSyncLastResult(result);
      if (result.kind === 'conflict') {
        markSyncConflict();
      } else {
        markSyncSuccess();
      }
      return result;
    } catch (error) {
      markSyncError(String((error as Error)?.message || error || 'Sync failed'));
      throw error;
    }
  }, [
    applyBookmarkSnapshot,
    buildBookmarkSnapshotForBaseline,
    cloudUid,
    cloudDeviceCredential,
    leafTabCloudBaselineStorageKey,
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
  ]);

  const emitWebdavSyncStatusChanged = useCallback(() => {
    window.dispatchEvent(new Event('webdav-config-changed'));
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
    setLocalVersion((value) => value + 1);
  }, []);

  const markWebdavSyncSuccess = useCallback(async (): Promise<void> => {
    const nowIso = new Date().toISOString();
    await Promise.all([
      writeExtensionStorageRecord({
        [WEBDAV_LAST_SYNC_AT_KEY]: nowIso,
      }),
      removeExtensionStorageKeys([
        WEBDAV_LAST_ERROR_AT_KEY,
        WEBDAV_LAST_ERROR_MESSAGE_KEY,
      ]),
    ]);
    localStorage.setItem(WEBDAV_LAST_SYNC_AT_KEY, nowIso);
    localStorage.removeItem(WEBDAV_LAST_ERROR_AT_KEY);
    localStorage.removeItem(WEBDAV_LAST_ERROR_MESSAGE_KEY);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markWebdavSyncError = useCallback(async (error: unknown): Promise<void> => {
    console.error('[LeafTab][WebDAV sync]', error);
    const nowIso = new Date().toISOString();
    const message = String((error as Error)?.message || 'unknown');
    await writeExtensionStorageRecord({
      [WEBDAV_LAST_ERROR_AT_KEY]: nowIso,
      [WEBDAV_LAST_ERROR_MESSAGE_KEY]: message,
    });
    localStorage.setItem(WEBDAV_LAST_ERROR_AT_KEY, nowIso);
    localStorage.setItem(WEBDAV_LAST_ERROR_MESSAGE_KEY, message);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncSuccess = useCallback(async (): Promise<void> => {
    const nowIso = new Date().toISOString();
    await Promise.all([
      writeExtensionStorageRecord({
        [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso,
      }),
      removeExtensionStorageKeys([
        AIRA_CLOUD_LAST_ERROR_AT_KEY,
        AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
      ]),
    ]);
    localStorage.setItem(AIRA_CLOUD_LAST_SYNC_AT_KEY, nowIso);
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_AT_KEY);
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncError = useCallback(async (error: unknown): Promise<void> => {
    console.error('[LeafTab][Aira cloud sync]', error);
    const nowIso = new Date().toISOString();
    const message = String((error as Error)?.message || 'unknown');
    await writeExtensionStorageRecord({
      [AIRA_CLOUD_LAST_ERROR_AT_KEY]: nowIso,
      [AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]: message,
    });
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_AT_KEY, nowIso);
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY, message);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setWebdavSyncEnabledInStorage = useCallback(async (enabled: boolean): Promise<void> => {
    await writeExtensionStorageRecord({
      [WEBDAV_STORAGE_KEYS.syncEnabled]: String(enabled),
    });
    if (!enabled) {
      await removeExtensionStorageKeys([WEBDAV_STORAGE_KEYS.nextSyncAt]);
    }
    localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(enabled));
    if (!enabled) {
      localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
    }
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setCloudSyncEnabledInStorage = useCallback(async (enabled: boolean): Promise<void> => {
    await writeAiraCloudSyncEnabled(cloudUid, enabled);
    emitWebdavSyncStatusChanged();
  }, [cloudUid, emitWebdavSyncStatusChanged]);

  const beginSyncProgress = useCallback((
    remoteKind: LeafTabSyncRemoteKind,
    detail?: string,
  ) => {
    setLeafTabSyncProgress({
      open: true,
      inProgress: true,
      title: '正在同步书签',
      detail: resolveProgressDetail(remoteKind, detail),
      progress: 8,
      remoteKind,
      latestProgress: null,
    });
  }, []);

  const updateSyncProgress = useCallback((
    remoteKind: LeafTabSyncRemoteKind,
    progress: LeafTabSyncEngineProgress,
    mappedProgress?: number,
  ) => {
    setLeafTabSyncProgress(() => ({
      open: true,
      inProgress: true,
      title: '正在同步书签',
      detail: resolveProgressDetail(remoteKind, progress.message),
      progress: Math.max(0, Math.min(100, Math.round(mappedProgress ?? progress.progress))),
      remoteKind,
      latestProgress: progress,
    }));
  }, []);

  const finishSyncProgress = useCallback((detail: string) => {
    setLeafTabSyncProgress((current) => ({
      ...current,
      open: true,
      inProgress: false,
      title: '同步完成',
      detail: detail || '书签已同步完成',
      progress: 100,
    }));
  }, []);

  const conflictSyncProgress = useCallback((
    detail: string,
    remoteKind: LeafTabSyncRemoteKind = 'webdav',
  ) => {
    setLeafTabSyncProgress((current) => ({
      ...current,
      open: true,
      inProgress: false,
      title: '需要处理同步冲突',
      detail: detail || '检测到同步冲突，请选择保留哪一端的数据。',
      progress: 100,
      remoteKind,
    }));
  }, []);

  const failSyncProgress = useCallback((error: unknown, remoteKind: LeafTabSyncRemoteKind = 'webdav') => {
    setLeafTabSyncProgress((current) => ({
      ...current,
      open: true,
      inProgress: false,
      title: '同步失败',
      detail: formatLeafTabSyncErrorMessage(error, remoteKind),
      progress: Math.max(current.progress, 100),
      remoteKind,
    }));
  }, []);

  const handleDismissSyncProgress = useCallback(() => {
    setLeafTabSyncProgress((current) => (
      current.inProgress ? current : createIdleProgressState()
    ));
  }, []);

  useEffect(() => {
    let cancelled = false;
    const refreshSharedState = async () => {
      await refreshSyncUiCacheFromExtensionStorage();
      const pending = await readPendingBookmarkConflict();
      if (cancelled) {
        return;
      }
      setLeafTabPendingBookmarkConflict(pending);
      if (pending) {
        setLeafTabSyncProgress((current) => current.inProgress ? current : {
          open: true,
          inProgress: false,
          title: '需要处理同步冲突',
          detail: pending.summary,
          progress: 100,
          remoteKind: pending.provider,
          latestProgress: null,
        });
      }
      setLocalVersion((value) => value + 1);
    };

    void (async () => {
      await seedWebdavCredentialsToExtensionStorage();
      const deviceId = await resolveLeafTabSyncDeviceId();
      await refreshSharedState();
      if (!cancelled) {
        setLeafTabSyncDeviceId(deviceId);
        setSyncStorageReady(true);
      }
    })().catch((error) => {
      if (!cancelled) {
        console.error('[LeafTab][Sync storage initialization]', error);
      }
    });

    const refreshLocalState = () => setLocalVersion((value) => value + 1);
    const handleExtensionStorageChanged = (changes: Record<string, chrome.storage.StorageChange>, areaName: string) => {
      if (areaName !== 'local') {
        return;
      }
      const changedKeys = Object.keys(changes);
      if (!changedKeys.some(isSharedSyncStorageKey)) {
        return;
      }
      void refreshSharedState();
    };
    window.addEventListener('webdav-config-changed', refreshLocalState);
    window.addEventListener('webdav-sync-status-changed', refreshLocalState);
    chrome.storage?.onChanged?.addListener?.(handleExtensionStorageChanged);
    return () => {
      cancelled = true;
      window.removeEventListener('webdav-config-changed', refreshLocalState);
      window.removeEventListener('webdav-sync-status-changed', refreshLocalState);
      chrome.storage?.onChanged?.removeListener?.(handleExtensionStorageChanged);
    };
  }, [cloudUid]);

  const refreshBookmarkDataOverview = useCallback(async () => {
    const requestId = leafTabSummaryRefreshRequestRef.current + 1;
    leafTabSummaryRefreshRequestRef.current = requestId;
    if (!syncStorageReady || !leafTabSyncDeviceId || !selectedSyncSource) {
      leafTabSummarySourceKeyRef.current = '';
      setLeafTabBookmarkDataOverview(null);
      setLeafTabSummaryLoading(false);
      return;
    }

    const baselineStorageKey = selectedSyncSource === 'aira-cloud'
      ? leafTabCloudBaselineStorageKey
      : leafTabSyncBaselineStorageKey;
    const sourceConfig: BookmarkSyncSourceConfig = selectedSyncSource === 'aira-cloud'
      ? {
          source: 'aira-cloud',
          uid: cloudUid,
          deviceCredential: cloudDeviceCredential,
        }
      : {
          source: 'webdav',
          webdav: {
            url: webdavConfig?.url || '',
            username: webdavConfig?.username,
            password: webdavConfig?.password,
            rootPath: leafTabSyncRootPath,
            requestPermission: false,
          },
        };
    const summarySourceIdentity = createBookmarkSyncSourceIdentity(sourceConfig, leafTabSyncRootPath);
    if (leafTabSummarySourceKeyRef.current !== summarySourceIdentity) {
      leafTabSummarySourceKeyRef.current = summarySourceIdentity;
      setLeafTabBookmarkDataOverview(null);
    }

    setLeafTabSummaryLoading(true);
    try {
      const module = createBookmarkSyncModule({
        sourceConfig,
        rootPath: leafTabSyncRootPath,
        deviceId: leafTabSyncDeviceId,
        baselineStorageKey,
        buildLocalSnapshot: () => buildBookmarkSnapshotForBaseline(baselineStorageKey),
        applyLocalSnapshot: applyBookmarkSnapshot,
      });
      const overviewPromise = module.readSummary({
        includeRemote: selectedSyncSource === 'aira-cloud'
          ? leafTabCloudSyncStatus !== 'login-required' && leafTabCloudSyncStatus !== 'pro-required'
          : Boolean(webdavConfig?.url),
      });
      const baselineSnapshot = selectedSyncSource === 'aira-cloud'
        ? await readLeafTabSyncBaselineSnapshot(baselineStorageKey)
        : null;
      if (leafTabSummaryRefreshRequestRef.current !== requestId) {
        return;
      }
      if (baselineSnapshot) {
        const baselineOverview = createBookmarkDataOverviewFromSummary(
          runtimeSummaryFromSnapshot(baselineSnapshot),
        );
        setLeafTabBookmarkDataOverview((current) => current || baselineOverview);
      }
      const overview = await overviewPromise;
      if (leafTabSummaryRefreshRequestRef.current !== requestId) {
        return;
      }
      setLeafTabBookmarkDataOverview((current) => ({
        local: overview.local || current?.local || null,
        remote: overview.remote || current?.remote || null,
      }));
    } catch (error) {
      if (selectedSyncSource === 'aira-cloud') {
        await recordAiraCloudCredentialFailure(error);
      }
    } finally {
      if (leafTabSummaryRefreshRequestRef.current === requestId) {
        setLeafTabSummaryLoading(false);
      }
    }
  }, [
    applyBookmarkSnapshot,
    buildBookmarkSnapshotForBaseline,
    cloudDeviceCredential,
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabCloudSyncStatus,
    leafTabSyncBaselineStorageKey,
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
    selectedSyncSource,
    syncStorageReady,
    webdavConfig?.password,
    webdavConfig?.url,
    webdavConfig?.username,
  ]);

  useEffect(() => {
    void refreshBookmarkDataOverview();
  }, [refreshBookmarkDataOverview]);

  const handleLeafTabSync = useCallback(async (options?: LeafTabRuntimeSyncOptions) => {
    const remoteKind = options?.remoteKind || 'webdav';
    const isCloud = remoteKind === 'aira-cloud';
    if (!syncStorageReady || !leafTabSyncDeviceId) {
      if (options?.silentSuccess !== true) {
        toast.error('同步状态正在初始化，请稍后再试');
      }
      return null;
    }
    if (!isCloud && !webdavConfig?.url) {
      if (options?.allowConfigPrompt !== false) {
        openWebdavConfig();
      }
      return null;
    }
    if (isCloud && (!cloudUid || !cloudDeviceCredential)) {
      toast.error('请先连接 Aira 桌面设备');
      return null;
    }
    if (isCloud) {
      let latestProfile;
      try {
        latestProfile = await refreshAiraDesktopConnectionProfileMembership({ force: true });
      } catch {
        if (options?.silentSuccess !== true) {
          toast.error('Aira 服务暂时不可用，请稍后再试');
        }
        return null;
      }
      const capability = resolveAiraDesktopProCapability(latestProfile);
      if (capability === 'login-required') {
        if (options?.silentSuccess !== true) {
          toast.error('Aira 桌面设备需要重新连接');
        }
        return null;
      }
      if (capability === 'temporarily-unavailable') {
        if (options?.silentSuccess !== true) {
          toast.error('Aira 服务暂时不可用，请稍后再试');
        }
        return null;
      }
      if (capability === 'pro-required') {
        if (options?.silentSuccess !== true) {
          toast.error('Aira 云同步需要 Aira Pro');
        }
        return null;
      }
    }

    const shouldShowDialogProgress = options?.showProgressIndicator === true && !options.progressTaskId;
    setWebdavSyncRunActive(true);
    const mergedOptions: LeafTabRuntimeSyncOptions = {
      ...options,
      onProgress: (progress) => {
        options?.onProgress?.(progress);
        if (shouldShowDialogProgress) {
          updateSyncProgress(remoteKind, progress);
        }
      },
    };
    if (shouldShowDialogProgress && !options?.progressAlreadyOpen) {
      beginSyncProgress(remoteKind);
    }
    try {
      if (options?.requestBookmarkPermission !== false) {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
      }

      const result = isCloud
        ? await runCloudSyncOnce(mergedOptions)
        : await runLeafTabSyncOnce(mergedOptions);
      if (result) {
        if (result.kind === 'conflict') {
          const pending = await persistPendingBookmarkConflict(remoteKind, result);
          setLeafTabPendingBookmarkConflict(pending);
          if (shouldShowDialogProgress) {
            conflictSyncProgress(result.summaryText || '检测到同步冲突，请选择保留哪一端的数据。', remoteKind);
          }
          if (!options?.silentSuccess) {
            toast.error(result.summaryText || '检测到同步冲突，请先处理');
          }
          return result;
        }
        if (!leafTabPendingBookmarkConflict || leafTabPendingBookmarkConflict.provider === remoteKind) {
          await clearPendingBookmarkConflict();
          setLeafTabPendingBookmarkConflict(null);
        }
        setLeafTabBookmarkDataOverview(createBookmarkDataOverviewFromSummary(result.snapshotSummary));
        if (isCloud) {
          await markCloudSyncSuccess();
        } else {
          await markWebdavSyncSuccess();
        }
        if (options?.enableAfterSuccess) {
          if (isCloud) {
            await setCloudSyncEnabledInStorage(true);
          } else {
            await setWebdavSyncEnabledInStorage(true);
          }
        }
        if (!options?.silentSuccess) {
          toast.success(result.summaryText || '同步完成');
        }
        if (shouldShowDialogProgress) {
          finishSyncProgress(result.summaryText || '书签已同步完成');
        }
        return result;
      }
      return null;
    } catch (error) {
      if (isCloud) {
        await markCloudSyncError(error);
        await recordAiraCloudCredentialFailure(error);
      } else {
        await markWebdavSyncError(error);
      }
      if (shouldShowDialogProgress) {
        failSyncProgress(error, remoteKind);
      }
      if (!options?.silentSuccess) {
        toast.error(formatLeafTabSyncErrorMessage(error, remoteKind));
      }
      return null;
    } finally {
      setWebdavSyncRunActive(false);
    }
  }, [
    markWebdavSyncError,
    markCloudSyncError,
    markCloudSyncSuccess,
    markWebdavSyncSuccess,
    runCloudSyncOnce,
    runLeafTabSyncOnce,
    beginSyncProgress,
    updateSyncProgress,
    finishSyncProgress,
    conflictSyncProgress,
    failSyncProgress,
    leafTabSyncDeviceId,
    setCloudSyncEnabledInStorage,
    setWebdavSyncEnabledInStorage,
    openWebdavConfig,
    cloudDeviceCredential,
    cloudUid,
    leafTabPendingBookmarkConflict,
    syncStorageReady,
    webdavConfig?.url,
  ]);

  const handleActiveSyncNowFromCenter = useCallback(async () => {
    const webdavEnabledNow = isWebdavSyncEnabledFromStorage();
    const selectedSource = selectedSyncSource;

    if (!selectedSource) {
      return false;
    }
    if (selectedSource === 'aira-cloud') {
      if (!cloudSyncEnabled) {
        toast.error('请先为当前 Aira 账号开启云书签同步');
        return false;
      }
    }
    if (selectedSource === 'webdav' && (!webdavEnabledNow || !webdavConfig?.url)) {
      openWebdavConfig();
      return false;
    }

    return Boolean(await handleLeafTabSync({
      remoteKind: selectedSource,
      requestBookmarkPermission: true,
      silentSuccess: true,
      showProgressIndicator: true,
    }));
  }, [
    cloudSyncEnabled,
    handleLeafTabSync,
    openWebdavConfig,
    selectedSyncSource,
    webdavConfig?.url,
  ]);

  const leafTabWebdavConfigured = hasWebdavUrlConfiguredFromStorage();

  const leafTabWebdavProfileLabel = useMemo(() => {
    const config = readWebdavConfigFromStorage({ allowDisabled: true });
    if (!config?.url) return '';
    try {
      return new URL(config.url).host;
    } catch {
      return config.url;
    }
  }, [localVersion]);

  const state = useMemo<LeafTabSyncState>(() => ({
    topNavSyncStatus: leafTabPendingBookmarkConflict || leafTabSyncState.status === 'conflict'
      ? 'conflict'
      : leafTabSyncState.status === 'error'
      ? 'error'
      : (leafTabSyncState.status === 'syncing' || webdavSyncRunActive ? 'syncing' : 'idle'),
    leafTabSyncProgress,
    leafTabPendingBookmarkConflict,
    leafTabSyncHasConfig: Boolean(webdavConfig?.url),
    leafTabSyncLastResult,
    leafTabLocalSummary: leafTabBookmarkDataOverview?.local || null,
    leafTabRemoteSummary: leafTabBookmarkDataOverview?.remote || null,
    leafTabSummaryLoading,
    leafTabWebdavConfigured,
    leafTabWebdavProfileLabel,
    leafTabWebdavLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(WEBDAV_LAST_SYNC_AT_KEY)),
    leafTabCloudLoggedIn: leafTabCloudSyncStatus !== 'login-required',
    leafTabCloudSyncEnabled: cloudSyncEffectivelyEnabled,
    leafTabCloudSyncStatus,
    leafTabCloudLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(AIRA_CLOUD_LAST_SYNC_AT_KEY)),
    leafTabSelectedSyncSource: selectedSyncSource,
    leafTabAutoSyncLastProbeLabel: formatLiteSyncTimestamp(
      localStorage.getItem(LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt),
    ),
    leafTabAutoSyncNextProbeLabel: formatLiteSyncTimestamp(
      localStorage.getItem(LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt),
    ),
    leafTabAutoSyncError: localStorage.getItem(LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError) || '',
  }), [
    leafTabSyncLastResult,
    leafTabBookmarkDataOverview,
    leafTabSummaryLoading,
    leafTabPendingBookmarkConflict,
    leafTabSyncProgress,
    leafTabSyncState,
    webdavSyncRunActive,
    leafTabWebdavConfigured,
    leafTabWebdavProfileLabel,
    cloudSyncEffectivelyEnabled,
    leafTabCloudSyncStatus,
    cloudUid,
    selectedSyncSource,
    webdavConfig,
    localVersion,
  ]);

  const actions = useMemo<LeafTabSyncActions>(() => ({
    handleSelectSyncSource: async (remoteKind) => {
      if (leafTabPendingBookmarkConflict && leafTabPendingBookmarkConflict.provider !== remoteKind) {
        toast.error('请先处理当前书签同步冲突，再更改同步方式');
        return false;
      }
      const canStartProgress = remoteKind === 'webdav' && Boolean(webdavConfig?.url);
      if (canStartProgress) {
        beginSyncProgress(remoteKind);
      }
      const result = await handleLeafTabSync({
        remoteKind,
        selectSourceAfterSuccess: true,
        enableAfterSuccess: true,
        allowConfigPrompt: true,
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
        progressAlreadyOpen: canStartProgress,
      });
      if (!result || result.kind === 'conflict') {
        return false;
      }
      toast.success(remoteKind === 'aira-cloud'
        ? '已选择 Aira 云同步'
        : '已选择 WebDAV 同步');
      return true;
    },
    handleActiveSyncNowFromCenter,
    handleDismissSyncProgress,
    handleResolveBookmarkConflict: async (choice) => {
      const remoteKind = leafTabPendingBookmarkConflict?.provider
        || leafTabSyncProgress.remoteKind
        || selectedSyncSource;
      if (!remoteKind) {
        toast.error('没有可处理的书签同步冲突');
        return false;
      }
      const result = await handleLeafTabSync({
        remoteKind,
        conflictChoice: choice,
        selectSourceAfterSuccess: true,
        enableAfterSuccess: true,
        allowConfigPrompt: false,
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      });
      if (!result || result.kind === 'conflict') {
        return false;
      }
      toast.success(choice === 'computer'
        ? '已保留电脑书签并完成同步'
        : '已使用当前同步来源并完成同步');
      return true;
    },
  }), [
    handleActiveSyncNowFromCenter,
    handleDismissSyncProgress,
    handleLeafTabSync,
    leafTabPendingBookmarkConflict,
    leafTabSyncProgress.remoteKind,
    selectedSyncSource,
    webdavConfig?.url,
  ]);

  return {
    state,
    actions,
  };
}
