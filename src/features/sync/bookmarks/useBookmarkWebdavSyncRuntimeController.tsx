import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from '@/components/ui/sonner';
import type {
  LeafTabInitialSyncChoiceRequest,
  LeafTabSyncActions,
  LeafTabSyncFacade,
  LeafTabSyncProgressState,
  LeafTabSyncRemoteKind,
  LeafTabSyncState,
  LeafTabSyncWebdavActionOptions,
} from '@/features/sync/app/LeafTabSyncContracts';
import { useLeafTabWebdavAutoSync } from '@/hooks/useLeafTabWebdavAutoSync';
import { readLeafTabBookmarkSyncScope } from '@/sync/leaftab/bookmarkScope';
import type {
  LeafTabSyncAnalysis,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
  LeafTabSyncInitialChoice,
} from '@/sync/leaftab/engine';
import type { LeafTabSyncRemoteStore } from '@/sync/leaftab/remoteStore';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { importLeafTabSyncRuntime } from '@/lazy/sync';
import { useSyncState } from '@/sync/useSyncState';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  hasWebdavUrlConfiguredFromStorage,
  isWebdavSyncEnabledFromStorage,
  readWebdavConfigFromStorage,
  WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';
import { readAiraDesktopLoginProfile } from '@/popup/desktopLogin';

const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX;
const AIRA_CLOUD_SYNC_ENABLED_KEY = 'aira_cloud_bookmark_sync_enabled';
const AIRA_CLOUD_LAST_SYNC_AT_KEY = 'aira_cloud_last_sync_at';
const AIRA_CLOUD_LAST_ERROR_AT_KEY = 'aira_cloud_last_error_at';
const AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY = 'aira_cloud_last_error_message';

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

const getOrCreateLeafTabSyncDeviceId = () => {
  try {
    const existing = localStorage.getItem('leaftab_sync_v1_device_id');
    if (existing) return existing;
    const created = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `dev_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    localStorage.setItem('leaftab_sync_v1_device_id', created);
    return created;
  } catch {
    return `dev_${Date.now()}_${Math.random().toString(16).slice(2)}`;
  }
};

const resolveLeafTabSyncRootPath = () => LEAFTAB_SYNC_DEFAULT_ROOT_PATH;

const createLeafTabSyncBaselineStorageKey = (rootPath: string) => {
  const suffix = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  return `leaftab_sync_v1_baseline:${suffix}`;
};

const createLeafTabSyncBaselineStorageKeyForRemote = (remoteKind: LeafTabSyncRemoteKind, rootPath: string, uid?: string) => {
  const suffix = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  if (remoteKind === 'aira-cloud') {
    const safeUid = (uid || 'unknown').replace(/[^a-zA-Z0-9_-]+/g, '_');
    return `leaftab_sync_v1_baseline:aira_cloud:${safeUid}:${suffix}`;
  }
  return createLeafTabSyncBaselineStorageKey(rootPath);
};

const createEmptyLiteLeafTabSyncSnapshot = (deviceId: string): LeafTabSyncSnapshot => ({
  meta: {
    version: 2,
    deviceId,
    generatedAt: '1970-01-01T00:00:00.000Z',
  },
  bookmarkFolders: {},
  bookmarkItems: {},
  bookmarkOrders: {
    __root__: {
      type: 'bookmark-order',
      parentId: null,
      ids: [],
      updatedAt: '1970-01-01T00:00:00.000Z',
      updatedBy: deviceId,
      revision: 1,
    },
  },
  tombstones: {},
});

const readLeafTabSyncBaselineSnapshot = (storageKey: string): LeafTabSyncSnapshot | null => {
  try {
    const raw = localStorage.getItem(storageKey);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { snapshot?: LeafTabSyncSnapshot };
    return normalizeLeafTabSyncSnapshot(parsed?.snapshot || null);
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

const runtimeSummaryFromSnapshot = (snapshot: LeafTabSyncSnapshot): LeafTabSyncAnalysis['localSummary'] => ({
  bookmarkFolders: Object.keys(snapshot.bookmarkFolders || {}).length,
  bookmarkItems: Object.keys(snapshot.bookmarkItems || {}).length,
  tombstones: Object.keys(snapshot.tombstones || {}).length,
});

const createAnalysisFromSyncedSnapshot = (
  result: LeafTabSyncEngineResult,
): LeafTabSyncAnalysis => {
  const nextSummary = runtimeSummaryFromSnapshot(result.snapshot);
  return {
    hasBaseline: true,
    localSummary: nextSummary,
    remoteSummary: nextSummary,
    requiresInitialChoice: false,
    suggestedInitialChoice: null,
    remoteCommitId: result.remoteCommitId,
  };
};

const createIdleProgressState = (): LeafTabSyncProgressState => ({
  open: false,
  inProgress: false,
  title: '',
  detail: '',
  progress: 0,
  latestProgress: null,
});

const resolveRemoteProgressName = (remoteKind: LeafTabSyncRemoteKind) => (
  remoteKind === 'aira-cloud' ? '云端' : 'WebDAV'
);

const resolveProgressDetail = (
  remoteKind: LeafTabSyncRemoteKind | 'dual',
  message?: string,
) => {
  if (message) return message.replace('远端', remoteKind === 'webdav' ? 'WebDAV' : '云端');
  if (remoteKind === 'dual') return '正在同步云端和 WebDAV 书签';
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
  mode: LeafTabSyncInitialChoice | 'auto';
  options?: LeafTabSyncWebdavActionOptions;
};

type RunAiraCloudBookmarkSyncOnceParams = {
  uid: string;
  rootPath: string;
  deviceId: string;
  baselineStorageKey: string;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  mode: LeafTabSyncInitialChoice | 'auto';
  options?: LeafTabSyncWebdavActionOptions;
};

const runBookmarkSyncWithRemoteStore = async ({
  remoteStore,
  rootPath,
  deviceId,
  baselineStorageKey,
  buildLocalSnapshot,
  applyLocalSnapshot,
  mode,
  options,
}: {
  remoteStore: LeafTabSyncRemoteStore;
  rootPath: string;
  deviceId: string;
  baselineStorageKey: string;
  buildLocalSnapshot: () => Promise<LeafTabSyncSnapshot>;
  applyLocalSnapshot: (snapshot: LeafTabSyncSnapshot) => Promise<void>;
  mode: LeafTabSyncInitialChoice | 'auto';
  options?: LeafTabSyncWebdavActionOptions;
}) => {
  const runtime = await importLeafTabSyncRuntime();
  const baselineStore = new runtime.LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey);
  const engine = new runtime.LeafTabSyncEngine({
    deviceId,
    remoteStore,
    baselineStore,
    buildLocalSnapshot,
    applyLocalSnapshot,
    createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(deviceId),
    rootPath,
  });

  return engine.sync(mode, {
    onProgress: options?.onProgress,
  });
};

const runWebdavBookmarkSyncOnce = async (params: RunWebdavBookmarkSyncOnceParams) => {
  const runtime = await importLeafTabSyncRuntime();
  const webdavStore = new runtime.LeafTabSyncWebdavStore({
    url: params.webdavConfig.url,
    username: params.webdavConfig.username,
    password: params.webdavConfig.password,
    rootPath: params.webdavConfig.rootPath,
    requestPermission: params.webdavConfig.requestPermission,
  });
  return runBookmarkSyncWithRemoteStore({
    ...params,
    remoteStore: webdavStore,
    rootPath: params.webdavConfig.rootPath,
  });
};

const runAiraCloudBookmarkSyncOnce = async (params: RunAiraCloudBookmarkSyncOnceParams) => {
  const runtime = await importLeafTabSyncRuntime();
  const cloudStore = new runtime.LeafTabSyncAiraCloudStore(params.uid);
  return runBookmarkSyncWithRemoteStore({
    ...params,
    remoteStore: cloudStore,
    rootPath: params.rootPath,
  });
};

export type LeafTabSyncLiteRuntimeControllerParams = {
  setWebdavDialogOpen: (open: boolean) => void;
  setLeafTabSyncDialogOpen: (open: boolean) => void;
  leafTabSyncDialogOpen: boolean;
  setWebdavEnableAfterConfigSave: (open: boolean) => void;
  setWebdavShowConnectionFields: (open: boolean) => void;
  setSyncConfigBackTarget: (target: 'settings' | 'sync-center') => void;
  isDragging: boolean;
};

export function useLeafTabSyncRuntimeController(
  params: LeafTabSyncLiteRuntimeControllerParams,
): LeafTabSyncFacade {
  const {
    setWebdavDialogOpen,
    setLeafTabSyncDialogOpen,
    leafTabSyncDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
    setSyncConfigBackTarget,
    isDragging,
  } = params;
  const [localVersion, setLocalVersion] = useState(0);
  const [webdavSyncRunActive, setWebdavSyncRunActive] = useState(false);
  const [leafTabSyncLastResult, setLeafTabSyncLastResult] = useState<LeafTabSyncEngineResult | null>(null);
  const [leafTabSyncAnalysis, setLeafTabSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabSyncAnalysisRemoteKind, setLeafTabSyncAnalysisRemoteKind] = useState<LeafTabSyncRemoteKind | null>(null);
  const [leafTabWebdavSyncAnalysis, setLeafTabWebdavSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabCloudSyncAnalysis, setLeafTabCloudSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabSyncProgress, setLeafTabSyncProgress] = useState<LeafTabSyncProgressState>(() => createIdleProgressState());
  const [leafTabInitialSyncChoiceRequest, setLeafTabInitialSyncChoiceRequest] =
    useState<LeafTabInitialSyncChoiceRequest | null>(null);
  const initialSyncChoiceResolverRef = useRef<((choice: LeafTabSyncInitialChoice | null) => void) | null>(null);
  const leafTabSyncDeviceId = useMemo(() => getOrCreateLeafTabSyncDeviceId(), []);
  const leafTabBookmarkSyncScope = useMemo(() => readLeafTabBookmarkSyncScope(), []);
  const leafTabSyncRootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const leafTabSyncBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKey(leafTabSyncRootPath),
    [leafTabSyncRootPath],
  );
  const desktopLoginProfile = useMemo(() => {
    void localVersion;
    return readAiraDesktopLoginProfile();
  }, [localVersion]);
  const cloudUid = desktopLoginProfile?.uid || '';
  const cloudSyncEnabled = useMemo(() => {
    void localVersion;
    return (localStorage.getItem(AIRA_CLOUD_SYNC_ENABLED_KEY) ?? 'false') === 'true';
  }, [localVersion]);
  const leafTabCloudBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKeyForRemote('aira-cloud', leafTabSyncRootPath, cloudUid),
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
      requestPermission: true,
    };
  }, [leafTabSyncRootPath, localVersion]);

  const buildWebdavBookmarkSnapshot = useCallback(async () => {
    const snapshotRuntime = await import('@/sync/leaftab/snapshotRuntime');
    const baselineSnapshot = readLeafTabSyncBaselineSnapshot(leafTabSyncBaselineStorageKey);
    const bookmarkTree = await snapshotRuntime.captureLeafTabBookmarkTreeDraft({
      scope: leafTabBookmarkSyncScope,
      requestPermission: true,
      throwOnPermissionDenied: true,
    });
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
  }, [leafTabBookmarkSyncScope, leafTabSyncBaselineStorageKey, leafTabSyncDeviceId]);

  const applyWebdavBookmarkSnapshot = useCallback(async (snapshot: LeafTabSyncSnapshot) => {
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
      throw new Error('WebDAV 书签快照缺少根目录排序，已停止写入本地以避免清空书签');
    }
    const applied = await snapshotRuntime.replaceLeafTabBookmarkTree({
      scope: leafTabBookmarkSyncScope,
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
  }, [leafTabBookmarkSyncScope]);

  const runLeafTabSyncOnce = useCallback(async (
    mode: LeafTabSyncInitialChoice | 'auto',
    options?: LeafTabSyncWebdavActionOptions,
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
        buildLocalSnapshot: buildWebdavBookmarkSnapshot,
        applyLocalSnapshot: applyWebdavBookmarkSnapshot,
        mode,
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
    applyWebdavBookmarkSnapshot,
    buildWebdavBookmarkSnapshot,
    leafTabSyncBaselineStorageKey,
    leafTabSyncDeviceId,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
    webdavConfig,
  ]);

  const runCloudSyncOnce = useCallback(async (
    mode: LeafTabSyncInitialChoice | 'auto',
    options?: LeafTabSyncWebdavActionOptions,
  ) => {
    if (!cloudUid) {
      throw new Error('请先扫码登录 Aira 账号。');
    }
    markSyncStart();
    try {
      const result = await runAiraCloudBookmarkSyncOnce({
        uid: cloudUid,
        rootPath: leafTabSyncRootPath,
        deviceId: leafTabSyncDeviceId,
        baselineStorageKey: leafTabCloudBaselineStorageKey,
        buildLocalSnapshot: buildWebdavBookmarkSnapshot,
        applyLocalSnapshot: applyWebdavBookmarkSnapshot,
        mode,
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
    applyWebdavBookmarkSnapshot,
    buildWebdavBookmarkSnapshot,
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
  ]);

  const refreshLeafTabSyncAnalysis = useCallback(async () => {
    if (!webdavConfig?.url) {
      setLeafTabWebdavSyncAnalysis(null);
      if (leafTabSyncAnalysisRemoteKind === 'webdav') {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      return null;
    }

    const runtime = await importLeafTabSyncRuntime();
    const baselineStore = new runtime.LeafTabSyncExtensionStorageBaselineStore(leafTabSyncBaselineStorageKey);
    const webdavStore = new runtime.LeafTabSyncWebdavStore({
      url: webdavConfig.url,
      username: webdavConfig.username,
      password: webdavConfig.password,
      rootPath: webdavConfig.rootPath,
      requestPermission: webdavConfig.requestPermission,
    });
    const engine = new runtime.LeafTabSyncEngine({
      deviceId: leafTabSyncDeviceId,
      remoteStore: webdavStore,
      baselineStore,
      buildLocalSnapshot: buildWebdavBookmarkSnapshot,
      applyLocalSnapshot: applyWebdavBookmarkSnapshot,
      createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(leafTabSyncDeviceId),
      rootPath: webdavConfig.rootPath,
    });

    const analysis = await engine.analyze();
    setLeafTabSyncAnalysisRemoteKind('webdav');
    setLeafTabSyncAnalysis(analysis);
    setLeafTabWebdavSyncAnalysis(analysis);
    return analysis;
  }, [
    applyWebdavBookmarkSnapshot,
    buildWebdavBookmarkSnapshot,
    leafTabSyncBaselineStorageKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabSyncDeviceId,
    webdavConfig,
  ]);

  const refreshCloudSyncAnalysis = useCallback(async () => {
    if (!cloudUid) {
      setLeafTabCloudSyncAnalysis(null);
      if (leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      return null;
    }

    const runtime = await importLeafTabSyncRuntime();
    const baselineStore = new runtime.LeafTabSyncExtensionStorageBaselineStore(leafTabCloudBaselineStorageKey);
    const cloudStore = new runtime.LeafTabSyncAiraCloudStore(cloudUid);
    const engine = new runtime.LeafTabSyncEngine({
      deviceId: leafTabSyncDeviceId,
      remoteStore: cloudStore,
      baselineStore,
      buildLocalSnapshot: buildWebdavBookmarkSnapshot,
      applyLocalSnapshot: applyWebdavBookmarkSnapshot,
      createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(leafTabSyncDeviceId),
      rootPath: leafTabSyncRootPath,
    });

    const analysis = await engine.analyze();
    setLeafTabSyncAnalysisRemoteKind('aira-cloud');
    setLeafTabSyncAnalysis(analysis);
    setLeafTabCloudSyncAnalysis(analysis);
    return analysis;
  }, [
    applyWebdavBookmarkSnapshot,
    buildWebdavBookmarkSnapshot,
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
  ]);

  const emitWebdavSyncStatusChanged = useCallback(() => {
    window.dispatchEvent(new Event('webdav-config-changed'));
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
    setLocalVersion((value) => value + 1);
  }, []);

  const requestInitialSyncChoice = useCallback((analysis: LeafTabSyncAnalysis) => {
    initialSyncChoiceResolverRef.current?.(null);
    setLeafTabInitialSyncChoiceRequest({
      localSummary: analysis.localSummary,
      remoteSummary: analysis.remoteSummary,
    });
    return new Promise<LeafTabSyncInitialChoice | null>((resolve) => {
      initialSyncChoiceResolverRef.current = resolve;
    });
  }, []);

  const resolveLeafTabInitialSyncChoice = useCallback((choice: LeafTabSyncInitialChoice | null) => {
    const resolver = initialSyncChoiceResolverRef.current;
    initialSyncChoiceResolverRef.current = null;
    setLeafTabInitialSyncChoiceRequest(null);
    resolver?.(choice);
  }, []);

  const markWebdavSyncSuccess = useCallback(() => {
    localStorage.setItem('webdav_last_sync_at', new Date().toISOString());
    localStorage.removeItem('webdav_last_error_at');
    localStorage.removeItem('webdav_last_error_message');
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markWebdavSyncError = useCallback((error: unknown) => {
    console.error('[LeafTab][WebDAV sync]', error);
    localStorage.setItem('webdav_last_error_at', new Date().toISOString());
    localStorage.setItem('webdav_last_error_message', String((error as Error)?.message || 'unknown'));
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncSuccess = useCallback(() => {
    localStorage.setItem(AIRA_CLOUD_LAST_SYNC_AT_KEY, new Date().toISOString());
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_AT_KEY);
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncError = useCallback((error: unknown) => {
    console.error('[LeafTab][Aira cloud sync]', error);
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_AT_KEY, new Date().toISOString());
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY, String((error as Error)?.message || 'unknown'));
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setWebdavSyncEnabledInStorage = useCallback((enabled: boolean) => {
    localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(enabled));
    if (!enabled) {
      localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
    }
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setCloudSyncEnabledInStorage = useCallback((enabled: boolean) => {
    localStorage.setItem(AIRA_CLOUD_SYNC_ENABLED_KEY, String(enabled));
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const beginSyncProgress = useCallback((
    remoteKind: LeafTabSyncRemoteKind | 'dual',
    detail?: string,
  ) => {
    setLeafTabSyncProgress({
      open: true,
      inProgress: true,
      title: '正在同步书签',
      detail: resolveProgressDetail(remoteKind, detail),
      progress: 8,
      latestProgress: null,
    });
  }, []);

  const updateSyncProgress = useCallback((
    remoteKind: LeafTabSyncRemoteKind | 'dual',
    progress: LeafTabSyncEngineProgress,
    mappedProgress?: number,
  ) => {
    setLeafTabSyncProgress(() => ({
      open: true,
      inProgress: true,
      title: '正在同步书签',
      detail: resolveProgressDetail(remoteKind, progress.message),
      progress: Math.max(0, Math.min(100, Math.round(mappedProgress ?? progress.progress))),
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

  const failSyncProgress = useCallback((error: unknown, remoteKind: LeafTabSyncRemoteKind = 'webdav') => {
    setLeafTabSyncProgress((current) => ({
      ...current,
      open: true,
      inProgress: false,
      title: '同步失败',
      detail: formatLeafTabSyncErrorMessage(error, remoteKind),
      progress: Math.max(current.progress, 100),
    }));
  }, []);

  const handleDismissSyncProgress = useCallback(() => {
    setLeafTabSyncProgress((current) => (
      current.inProgress ? current : createIdleProgressState()
    ));
  }, []);

  useEffect(() => {
    const refreshLocalState = () => setLocalVersion((value) => value + 1);
    window.addEventListener('webdav-config-changed', refreshLocalState);
    window.addEventListener('webdav-sync-status-changed', refreshLocalState);
    return () => {
      window.removeEventListener('webdav-config-changed', refreshLocalState);
      window.removeEventListener('webdav-sync-status-changed', refreshLocalState);
    };
  }, []);

  const handleLeafTabSync = useCallback(async (options?: LeafTabSyncWebdavActionOptions) => {
    const remoteKind = options?.remoteKind || 'webdav';
    const isCloud = remoteKind === 'aira-cloud';
    if (!isCloud && !webdavConfig?.url) {
      if (options?.allowConfigPrompt !== false) {
        setSyncConfigBackTarget('settings');
        setWebdavEnableAfterConfigSave(true);
        setWebdavShowConnectionFields(true);
        setWebdavDialogOpen(true);
      }
      return null;
    }
    if (isCloud && !cloudUid) {
      toast.error('请先扫码登录 Aira 账号');
      return null;
    }

    setWebdavSyncRunActive(true);
    const shouldShowDialogProgress = options?.showProgressIndicator === true && !options.progressTaskId;
    const mergedOptions: LeafTabSyncWebdavActionOptions = {
      ...options,
      onProgress: (progress) => {
        options?.onProgress?.(progress);
        if (shouldShowDialogProgress) {
          updateSyncProgress(remoteKind, progress);
        }
      },
    };
    if (shouldShowDialogProgress) {
      beginSyncProgress(remoteKind);
    }
    try {
      if (options?.requestBookmarkPermission !== false) {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
      }

      let runMode: LeafTabSyncInitialChoice | 'auto' = options?.mode || 'auto';
      if (runMode === 'auto') {
        const analysis = isCloud
          ? await refreshCloudSyncAnalysis()
          : await refreshLeafTabSyncAnalysis();
        if (analysis?.requiresInitialChoice) {
          if (options?.silentSuccess && options?.allowConfigPrompt === false) {
            return null;
          }
          const choice = await requestInitialSyncChoice(analysis);
          if (choice === null) {
            return null;
          }
          runMode = choice;
        }
      }

      const result = isCloud
        ? await runCloudSyncOnce(runMode, mergedOptions)
        : await runLeafTabSyncOnce(runMode, mergedOptions);
      if (result) {
        setLeafTabSyncAnalysisRemoteKind(remoteKind);
        const syncedAnalysis = createAnalysisFromSyncedSnapshot(result);
        if (isCloud) {
          markCloudSyncSuccess();
          setLeafTabCloudSyncAnalysis(syncedAnalysis);
        } else {
          markWebdavSyncSuccess();
          setLeafTabWebdavSyncAnalysis(syncedAnalysis);
        }
        setLeafTabSyncAnalysis(syncedAnalysis);
        if (options?.enableAfterSuccess) {
          if (isCloud) {
            setCloudSyncEnabledInStorage(true);
          } else {
            setWebdavSyncEnabledInStorage(true);
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
        markCloudSyncError(error);
      } else {
        markWebdavSyncError(error);
      }
      if (shouldShowDialogProgress) {
        failSyncProgress(error, remoteKind);
      }
      toast.error(formatLeafTabSyncErrorMessage(error, remoteKind));
      return null;
    } finally {
      setWebdavSyncRunActive(false);
    }
  }, [
    markWebdavSyncError,
    markCloudSyncError,
    markCloudSyncSuccess,
    markWebdavSyncSuccess,
    refreshCloudSyncAnalysis,
    refreshLeafTabSyncAnalysis,
    requestInitialSyncChoice,
    runCloudSyncOnce,
    runLeafTabSyncOnce,
    beginSyncProgress,
    updateSyncProgress,
    finishSyncProgress,
    failSyncProgress,
    setCloudSyncEnabledInStorage,
    setWebdavSyncEnabledInStorage,
    setSyncConfigBackTarget,
    setWebdavDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
    cloudUid,
    webdavConfig?.url,
  ]);

  const handleOpenWebdavConfig = useCallback((options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => {
    const shouldEnableAfterSave = options?.enableAfterSave ?? !hasWebdavUrlConfiguredFromStorage();
    const shouldShowConnectionFields = options?.showConnectionFields ?? shouldEnableAfterSave;
    setSyncConfigBackTarget('settings');
    setWebdavEnableAfterConfigSave(Boolean(shouldEnableAfterSave));
    setWebdavShowConnectionFields(Boolean(shouldShowConnectionFields));
    setWebdavDialogOpen(true);
    return true;
  }, [
    setSyncConfigBackTarget,
    setWebdavDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
  ]);

  const handleOpenWebdavConfigFromSyncCenter = useCallback((options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => {
    setSyncConfigBackTarget('sync-center');
    setLeafTabSyncDialogOpen(false);
    setWebdavEnableAfterConfigSave(Boolean(options?.enableAfterSave ?? !hasWebdavUrlConfiguredFromStorage()));
    setWebdavShowConnectionFields(Boolean(options?.showConnectionFields ?? !hasWebdavUrlConfiguredFromStorage()));
    setWebdavDialogOpen(true);
  }, [
    setLeafTabSyncDialogOpen,
    setSyncConfigBackTarget,
    setWebdavDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
  ]);

  const handleLeafTabAutoSync = useCallback(async () => {
    const result = await handleLeafTabSync({
      silentSuccess: true,
      allowConfigPrompt: false,
      requestBookmarkPermission: true,
    });
    return Boolean(result);
  }, [handleLeafTabSync]);

  const handleActiveSyncNowFromCenter = useCallback(async () => {
    const webdavEnabledNow = isWebdavSyncEnabledFromStorage();
    const cloudEnabledNow = (localStorage.getItem(AIRA_CLOUD_SYNC_ENABLED_KEY) ?? 'false') === 'true';
    if (cloudEnabledNow && cloudUid && webdavEnabledNow && webdavConfig?.url) {
      setWebdavSyncRunActive(true);
      beginSyncProgress('dual', '正在同步云端和 WebDAV 书签');
      try {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
        const cloudResult = await handleLeafTabSync({
          remoteKind: 'aira-cloud',
          requestBookmarkPermission: false,
          silentSuccess: true,
          showProgressIndicator: false,
          onProgress: (progress) => updateSyncProgress('aira-cloud', progress, Math.min(50, progress.progress * 0.5)),
        });
        if (!cloudResult) {
          finishSyncProgress('同步未完成，请稍后重试');
          return false;
        }
        updateSyncProgress('dual', {
          stage: 'reading-state',
          progress: 52,
          message: '正在同步 WebDAV 书签',
        }, 52);
        const webdavResult = await handleLeafTabSync({
          requestBookmarkPermission: false,
          silentSuccess: true,
          showProgressIndicator: false,
          onProgress: (progress) => updateSyncProgress('webdav', progress, 50 + (progress.progress * 0.5)),
        });
        if (!webdavResult) {
          finishSyncProgress('同步未完成，请稍后重试');
          return false;
        }
        finishSyncProgress(webdavResult.summaryText || cloudResult.summaryText || '云端和 WebDAV 已同步完成');
        toast.success('书签同步完成');
        return true;
      } catch (error) {
        markCloudSyncError(error);
        markWebdavSyncError(error);
        failSyncProgress(error);
        toast.error(formatLeafTabSyncErrorMessage(error));
        return false;
      } finally {
        setWebdavSyncRunActive(false);
      }
    }

    if (cloudEnabledNow && cloudUid) {
      return Boolean(await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      }));
    }

    if (webdavEnabledNow) {
      return Boolean(await handleLeafTabSync({
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      }));
    }

    if (cloudUid) {
      return Boolean(await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      }));
    }

    if (webdavConfig?.url) {
      return Boolean(await handleLeafTabSync({
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      }));
    }

    handleOpenWebdavConfigFromSyncCenter({ enableAfterSave: true, showConnectionFields: true });
    return false;
  }, [
    beginSyncProgress,
    cloudUid,
    failSyncProgress,
    finishSyncProgress,
    handleLeafTabSync,
    handleOpenWebdavConfigFromSyncCenter,
    markCloudSyncError,
    markWebdavSyncError,
    updateSyncProgress,
    webdavConfig?.url,
  ]);

  useLeafTabWebdavAutoSync({
    conflictModalOpen: false,
    isDragging,
    syncing: leafTabSyncState.status === 'syncing' || webdavSyncRunActive,
    onSync: handleLeafTabAutoSync,
  });

  useEffect(() => {
    if (!leafTabSyncDialogOpen || !webdavConfig?.url) {
      if (!webdavConfig?.url) {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      return;
    }

    let disposed = false;
    void refreshLeafTabSyncAnalysis()
      .then((analysis) => {
        if (disposed || !analysis) return;
        setLeafTabSyncAnalysis(analysis);
      })
      .catch((error) => {
        if (disposed) return;
        console.error('[LeafTab][WebDAV sync analysis]', error);
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      });

    return () => {
      disposed = true;
    };
  }, [leafTabSyncDialogOpen, refreshLeafTabSyncAnalysis, webdavConfig?.url]);

  useEffect(() => {
    if (!leafTabSyncDialogOpen || !cloudUid || !cloudSyncEnabled) {
      if (!cloudUid && leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      return;
    }

    let disposed = false;
    void refreshCloudSyncAnalysis()
      .then((analysis) => {
        if (disposed || !analysis) return;
        setLeafTabCloudSyncAnalysis(analysis);
      })
      .catch((error) => {
        if (disposed) return;
        console.error('[LeafTab][Aira cloud sync analysis]', error);
      });

    return () => {
      disposed = true;
    };
  }, [
    cloudSyncEnabled,
    cloudUid,
    leafTabSyncAnalysisRemoteKind,
    leafTabSyncDialogOpen,
    refreshCloudSyncAnalysis,
  ]);

  const leafTabWebdavConfigured = hasWebdavUrlConfiguredFromStorage();
  const leafTabWebdavEnabled = isWebdavSyncEnabledFromStorage();
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
    leafTabSyncState,
    topNavSyncStatus: leafTabSyncState.status === 'error'
      ? 'error'
      : (leafTabSyncState.status === 'syncing' || webdavSyncRunActive ? 'syncing' : 'idle'),
    leafTabSyncAnalysis,
    leafTabSyncAnalysisRemoteKind,
    leafTabWebdavSyncAnalysis,
    leafTabCloudSyncAnalysis,
    leafTabSyncProgress,
    leafTabInitialSyncChoiceRequest,
    leafTabSyncHasConfig: Boolean(webdavConfig?.url),
    leafTabSyncReady: true,
    leafTabSyncLastResult,
    leafTabSyncWebdavConfig: webdavConfig,
    webdavSyncBookmarksEnabled: true,
    leafTabWebdavConfigured,
    leafTabWebdavEnabled,
    leafTabWebdavProfileLabel,
    leafTabWebdavLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem('webdav_last_sync_at')),
    leafTabWebdavNextSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(WEBDAV_STORAGE_KEYS.nextSyncAt)),
    leafTabBookmarkSyncScopeLabel: '书签栏 / 其他书签',
    leafTabCloudLoggedIn: Boolean(cloudUid),
    leafTabCloudSyncEnabled: cloudSyncEnabled,
    leafTabCloudLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(AIRA_CLOUD_LAST_SYNC_AT_KEY)),
    leafTabCloudUserId: cloudUid,
  }), [
    leafTabSyncLastResult,
    leafTabInitialSyncChoiceRequest,
    leafTabSyncAnalysis,
    leafTabSyncAnalysisRemoteKind,
    leafTabWebdavSyncAnalysis,
    leafTabCloudSyncAnalysis,
    leafTabSyncProgress,
    leafTabSyncState,
    webdavSyncRunActive,
    leafTabWebdavConfigured,
    leafTabWebdavEnabled,
    leafTabWebdavProfileLabel,
    cloudSyncEnabled,
    cloudUid,
    webdavConfig,
    localVersion,
  ]);

  const actions = useMemo<LeafTabSyncActions>(() => ({
    handleLeafTabSync,
    handleEnableWebdavSync: async () => {
      await handleLeafTabSync({
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      });
    },
    handleDisableWebdavSync: async () => {
      setWebdavSyncEnabledInStorage(false);
      if (leafTabSyncAnalysisRemoteKind === 'webdav') {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      setLeafTabWebdavSyncAnalysis(null);
      toast.success('WebDAV 同步已关闭');
    },
    handleOpenWebdavConfig,
    handleOpenWebdavConfigFromSyncCenter,
    handleLeafTabSyncDialogOpenChange: setLeafTabSyncDialogOpen,
    handleLeafTabAutoSync,
    handleActiveSyncNowFromCenter,
    handleDismissSyncProgress,
    handleWebdavSyncNowFromCenter: async () => {
      const result = await handleLeafTabSync({
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      });
      return Boolean(result);
    },
    handleWebdavRefreshAnalysis: async () => {
      try {
        const analysis = await refreshLeafTabSyncAnalysis();
        if (analysis) {
          toast.success('WebDAV 数据检查完成');
        }
        return analysis;
      } catch (error) {
        toast.error(formatLeafTabSyncErrorMessage(error, 'webdav'));
        return null;
      }
    },
    handleWebdavOverwriteFromCenter: async (mode) => {
      const result = await handleLeafTabSync({
        mode,
        allowConfigPrompt: false,
        requestBookmarkPermission: true,
        silentSuccess: true,
      });
      if (result) {
        toast.success(mode === 'pull-remote' ? '已用 WebDAV 覆盖本地' : '已用本地覆盖 WebDAV');
      }
      return Boolean(result);
    },
    handleCloudSyncNowFromCenter: async () => {
      const result = await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      });
      return Boolean(result);
    },
    handleEnableCloudSync: async () => {
      const result = await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      });
      return Boolean(result);
    },
    handleDisableCloudSync: async () => {
      setCloudSyncEnabledInStorage(false);
      if (leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
        setLeafTabSyncAnalysis(null);
        setLeafTabSyncAnalysisRemoteKind(null);
      }
      setLeafTabCloudSyncAnalysis(null);
      toast.success('Aira 云同步已关闭');
    },
    handleCloudRefreshAnalysis: async () => {
      try {
        const analysis = await refreshCloudSyncAnalysis();
        if (analysis) {
          toast.success('Aira 云端数据检查完成');
        }
        return analysis;
      } catch (error) {
        toast.error(formatLeafTabSyncErrorMessage(error, 'aira-cloud'));
        return null;
      }
    },
    handleCloudOverwriteFromCenter: async (mode) => {
      const result = await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        mode,
        allowConfigPrompt: false,
        requestBookmarkPermission: true,
        silentSuccess: true,
      });
      if (result) {
        toast.success(mode === 'pull-remote' ? '已用 Aira 云端覆盖本机' : '已用本机覆盖 Aira 云端');
      }
      return Boolean(result);
    },
    resolveWebdavConflict: async () => {
      await handleLeafTabSync({
        requestBookmarkPermission: true,
      });
    },
    resolveLeafTabInitialSyncChoice,
  }), [
    handleLeafTabAutoSync,
    handleActiveSyncNowFromCenter,
    handleDismissSyncProgress,
    handleLeafTabSync,
    handleOpenWebdavConfig,
    handleOpenWebdavConfigFromSyncCenter,
    leafTabSyncAnalysisRemoteKind,
    refreshCloudSyncAnalysis,
    refreshLeafTabSyncAnalysis,
    resolveLeafTabInitialSyncChoice,
    setLeafTabSyncDialogOpen,
    setCloudSyncEnabledInStorage,
    setWebdavSyncEnabledInStorage,
  ]);

  const meta = useMemo(() => ({
    resolveLeafTabSyncRootPath,
  }), []);

  return {
    state,
    actions,
    meta,
  };
}

export type LeafTabSyncRuntimeController = LeafTabSyncFacade;
