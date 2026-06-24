import { useCallback, useEffect, useMemo, useState } from 'react';
import { toast } from '@/components/ui/sonner';
import type {
  LeafTabSyncActions,
  LeafTabSyncFacade,
  LeafTabSyncState,
  LeafTabSyncWebdavActionOptions,
} from '@/features/sync/app/LeafTabSyncContracts';
import { useLeafTabWebdavAutoSync } from '@/hooks/useLeafTabWebdavAutoSync';
import { readLeafTabBookmarkSyncScope } from '@/sync/leaftab/bookmarkScope';
import type { LeafTabSyncAnalysis, LeafTabSyncEngineResult, LeafTabSyncInitialChoice } from '@/sync/leaftab/engine';
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

const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX;

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

const formatLeafTabSyncErrorMessage = (error: unknown) => {
  if (error && typeof error === 'object') {
    const status = Number((error as { status?: unknown }).status);
    const operation = String((error as { operation?: unknown }).operation || '');
    const relativePath = String((error as { relativePath?: unknown }).relativePath || '');
    if (Number.isInteger(status) && status > 0 && operation) {
      return relativePath
        ? `WebDAV ${operation} failed (${status}): ${relativePath}`
        : `WebDAV ${operation} failed (${status})`;
    }
  }
  return String((error as Error)?.message || 'WebDAV 同步失败');
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

const runWebdavBookmarkSyncOnce = async ({
  webdavConfig,
  deviceId,
  baselineStorageKey,
  buildLocalSnapshot,
  applyLocalSnapshot,
  mode,
  options,
}: RunWebdavBookmarkSyncOnceParams) => {
  const runtime = await importLeafTabSyncRuntime();
  const baselineStore = new runtime.LeafTabSyncExtensionStorageBaselineStore(baselineStorageKey);
  const webdavStore = new runtime.LeafTabSyncWebdavStore({
    url: webdavConfig.url,
    username: webdavConfig.username,
    password: webdavConfig.password,
    rootPath: webdavConfig.rootPath,
    requestPermission: webdavConfig.requestPermission,
  });
  const engine = new runtime.LeafTabSyncEngine({
    deviceId,
    remoteStore: webdavStore,
    baselineStore,
    buildLocalSnapshot,
    applyLocalSnapshot,
    createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(deviceId),
    rootPath: webdavConfig.rootPath,
  });

  return engine.sync(mode, {
    onProgress: options?.onProgress,
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
  const leafTabSyncDeviceId = useMemo(() => getOrCreateLeafTabSyncDeviceId(), []);
  const leafTabBookmarkSyncScope = useMemo(() => readLeafTabBookmarkSyncScope(), []);
  const leafTabSyncRootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const leafTabSyncBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKey(leafTabSyncRootPath),
    [leafTabSyncRootPath],
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

  const refreshLeafTabSyncAnalysis = useCallback(async () => {
    if (!webdavConfig?.url) {
      setLeafTabSyncAnalysis(null);
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
    setLeafTabSyncAnalysis(analysis);
    return analysis;
  }, [
    applyWebdavBookmarkSnapshot,
    buildWebdavBookmarkSnapshot,
    leafTabSyncBaselineStorageKey,
    leafTabSyncDeviceId,
    webdavConfig,
  ]);

  const emitWebdavSyncStatusChanged = useCallback(() => {
    window.dispatchEvent(new Event('webdav-config-changed'));
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
    setLocalVersion((value) => value + 1);
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

  const setWebdavSyncEnabledInStorage = useCallback((enabled: boolean) => {
    localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(enabled));
    if (!enabled) {
      localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
    }
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

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
    if (!webdavConfig?.url) {
      if (options?.allowConfigPrompt !== false) {
        setSyncConfigBackTarget('settings');
        setWebdavEnableAfterConfigSave(true);
        setWebdavShowConnectionFields(true);
        setWebdavDialogOpen(true);
      }
      return null;
    }

    setWebdavSyncRunActive(true);
    try {
      if (options?.requestBookmarkPermission !== false) {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
      }

      const result = await runLeafTabSyncOnce(options?.mode || 'auto', options);
      if (result) {
        markWebdavSyncSuccess();
        void refreshLeafTabSyncAnalysis().catch((error) => {
          console.error('[LeafTab][WebDAV sync analysis]', error);
        });
        if (options?.enableAfterSuccess) {
          setWebdavSyncEnabledInStorage(true);
        }
        if (!options?.silentSuccess) {
          toast.success(result.summaryText || '同步完成');
        }
        return result;
      }
      return null;
    } catch (error) {
      markWebdavSyncError(error);
      toast.error(formatLeafTabSyncErrorMessage(error));
      return null;
    } finally {
      setWebdavSyncRunActive(false);
    }
  }, [
    markWebdavSyncError,
    markWebdavSyncSuccess,
    refreshLeafTabSyncAnalysis,
    runLeafTabSyncOnce,
    setWebdavSyncEnabledInStorage,
    setSyncConfigBackTarget,
    setWebdavDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
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
      });

    return () => {
      disposed = true;
    };
  }, [leafTabSyncDialogOpen, refreshLeafTabSyncAnalysis, webdavConfig?.url]);

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
    topNavSyncStatus: leafTabSyncState.status === 'error' ? 'error' : leafTabSyncState.status === 'syncing' ? 'syncing' : 'idle',
    leafTabSyncAnalysis,
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
  }), [
    leafTabSyncLastResult,
    leafTabSyncAnalysis,
    leafTabSyncState,
    leafTabWebdavConfigured,
    leafTabWebdavEnabled,
    leafTabWebdavProfileLabel,
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
      toast.success('WebDAV 同步已关闭');
    },
    handleOpenWebdavConfig,
    handleOpenWebdavConfigFromSyncCenter,
    handleLeafTabSyncDialogOpenChange: setLeafTabSyncDialogOpen,
    handleLeafTabAutoSync,
    handleWebdavSyncNowFromCenter: async () => {
      const toastId = toast.info('正在同步 WebDAV 书签...', { duration: 30000 });
      const result = await handleLeafTabSync({
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      });
      if (result) {
        toast.success(result.summaryText || 'WebDAV 书签同步完成', { id: toastId });
      } else {
        toast.dismiss(toastId);
      }
      return Boolean(result);
    },
    handleWebdavRefreshAnalysis: async () => {
      try {
        const analysis = await refreshLeafTabSyncAnalysis();
        if (analysis) {
          toast.success('云端数据检查完成');
        }
        return analysis;
      } catch (error) {
        toast.error(formatLeafTabSyncErrorMessage(error));
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
    resolveWebdavConflict: async () => {
      await handleLeafTabSync({
        requestBookmarkPermission: true,
      });
    },
  }), [
    handleLeafTabAutoSync,
    handleLeafTabSync,
    handleOpenWebdavConfig,
    handleOpenWebdavConfigFromSyncCenter,
    refreshLeafTabSyncAnalysis,
    setLeafTabSyncDialogOpen,
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
