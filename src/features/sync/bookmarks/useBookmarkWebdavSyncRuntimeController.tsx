import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from '@/components/ui/sonner';
import type {
  LeafTabSyncActions,
  LeafTabSyncFacade,
  LeafTabSyncState,
  LeafTabSyncWebdavActionOptions,
} from '@/features/sync/app/LeafTabSyncContracts';
import { useLeafTabSyncEngine } from '@/hooks/useLeafTabSyncEngine';
import { useLeafTabWebdavAutoSync } from '@/hooks/useLeafTabWebdavAutoSync';
import { readLeafTabBookmarkSyncScope } from '@/sync/leaftab/bookmarkScope';
import type { LeafTabSyncInitialChoice } from '@/sync/leaftab/engine';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  hasWebdavUrlConfiguredFromStorage,
  isWebdavSyncEnabledFromStorage,
  readWebdavConfigFromStorage,
  WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';

const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX;
const WEBDAV_SYNC_ENGINE_READY_TIMEOUT_MS = 6000;
const WEBDAV_SYNC_ENGINE_READY_POLL_MS = 80;

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
  const [localVersion, setLocalVersion] = useState(0);
  const [webdavSyncRunActive, setWebdavSyncRunActive] = useState(false);
  const leafTabSyncDeviceId = useMemo(() => getOrCreateLeafTabSyncDeviceId(), []);
  const leafTabBookmarkSyncScope = useMemo(() => readLeafTabBookmarkSyncScope(), []);
  const leafTabSyncRootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const leafTabSyncBaselineStorageKey = useMemo(
    () => createLeafTabSyncBaselineStorageKey(leafTabSyncRootPath),
    [leafTabSyncRootPath],
  );

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
      requestPermission: false,
    });
    if (!applied) {
      throw new Error('未授予书签权限，无法写入本地书签');
    }
  }, [leafTabBookmarkSyncScope]);

  const {
    analysis: leafTabSyncAnalysis,
    hasConfig: leafTabSyncHasConfig,
    lastResult: leafTabSyncLastResult,
    refreshAnalysis: refreshLeafTabSyncAnalysis,
    runSync: runLeafTabSync,
    syncState: leafTabSyncState,
    isReady: leafTabSyncReady,
  } = useLeafTabSyncEngine({
    deviceId: leafTabSyncDeviceId,
    webdav: webdavConfig,
    buildLocalSnapshot: buildWebdavBookmarkSnapshot,
    applyLocalSnapshot: applyWebdavBookmarkSnapshot,
    createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(leafTabSyncDeviceId),
    baselineStorageKey: leafTabSyncBaselineStorageKey,
  });

  const leafTabSyncEngineReadyRef = useRef(false);
  useEffect(() => {
    leafTabSyncEngineReadyRef.current = Boolean(leafTabSyncReady && leafTabSyncHasConfig);
  }, [leafTabSyncHasConfig, leafTabSyncReady]);

  const waitForLeafTabSyncEngineReady = useCallback(async () => {
    if (leafTabSyncEngineReadyRef.current) return true;
    const deadline = Date.now() + WEBDAV_SYNC_ENGINE_READY_TIMEOUT_MS;
    while (Date.now() < deadline) {
      await new Promise<void>((resolve) => {
        window.setTimeout(resolve, WEBDAV_SYNC_ENGINE_READY_POLL_MS);
      });
      if (leafTabSyncEngineReadyRef.current) return true;
    }
    return leafTabSyncEngineReadyRef.current;
  }, []);

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

  useEffect(() => {
    if (!params.leafTabSyncDialogOpen) return;
    if (hasWebdavUrlConfiguredFromStorage() && leafTabSyncHasConfig && leafTabSyncReady) {
      void refreshLeafTabSyncAnalysis({ force: true }).catch(() => null);
    }
  }, [
    leafTabSyncHasConfig,
    leafTabSyncReady,
    params.leafTabSyncDialogOpen,
    refreshLeafTabSyncAnalysis,
    localVersion,
  ]);

  const handleLeafTabSync = useCallback(async (options?: LeafTabSyncWebdavActionOptions) => {
    if (!hasWebdavUrlConfiguredFromStorage()) {
      if (options?.allowConfigPrompt !== false) {
        params.setSyncConfigBackTarget('settings');
        params.setWebdavEnableAfterConfigSave(true);
        params.setWebdavShowConnectionFields(true);
        params.setWebdavDialogOpen(true);
      }
      return null;
    }

    setWebdavSyncRunActive(true);
    try {
      if (!(await waitForLeafTabSyncEngineReady())) {
        throw new Error('LeafTab sync engine is not ready');
      }

      if (options?.requestBookmarkPermission !== false) {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
      }

      const result = await runLeafTabSync(options?.mode || 'auto', {
        onProgress: options?.onProgress,
      });
      if (result) {
        markWebdavSyncSuccess();
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
    leafTabSyncAnalysis,
    markWebdavSyncError,
    markWebdavSyncSuccess,
    params,
    refreshLeafTabSyncAnalysis,
    runLeafTabSync,
    setWebdavSyncEnabledInStorage,
    waitForLeafTabSyncEngineReady,
  ]);

  const runWebdavRepair = useCallback(async (mode: LeafTabSyncInitialChoice) => {
    params.setLeafTabSyncDialogOpen(false);
    if (!hasWebdavUrlConfiguredFromStorage()) {
      params.setSyncConfigBackTarget('sync-center');
      params.setWebdavEnableAfterConfigSave(true);
      params.setWebdavShowConnectionFields(true);
      params.setWebdavDialogOpen(true);
      return false;
    }
    const result = await handleLeafTabSync({
      mode,
      allowConfigPrompt: false,
      requestBookmarkPermission: true,
      silentSuccess: true,
    });
    if (result) {
      toast.success(mode === 'pull-remote' ? '已用 WebDAV 数据覆盖本地' : '已用本地数据覆盖 WebDAV');
      return true;
    }
    return false;
  }, [handleLeafTabSync, params]);

  const handleOpenWebdavConfig = useCallback((options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => {
    const shouldEnableAfterSave = options?.enableAfterSave ?? !hasWebdavUrlConfiguredFromStorage();
    const shouldShowConnectionFields = options?.showConnectionFields ?? shouldEnableAfterSave;
    params.setSyncConfigBackTarget('settings');
    params.setWebdavEnableAfterConfigSave(Boolean(shouldEnableAfterSave));
    params.setWebdavShowConnectionFields(Boolean(shouldShowConnectionFields));
    params.setWebdavDialogOpen(true);
    return true;
  }, [params]);

  const handleOpenWebdavConfigFromSyncCenter = useCallback((options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => {
    params.setSyncConfigBackTarget('sync-center');
    params.setLeafTabSyncDialogOpen(false);
    params.setWebdavEnableAfterConfigSave(Boolean(options?.enableAfterSave ?? !hasWebdavUrlConfiguredFromStorage()));
    params.setWebdavShowConnectionFields(Boolean(options?.showConnectionFields ?? !hasWebdavUrlConfiguredFromStorage()));
    params.setWebdavDialogOpen(true);
  }, [params]);

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
    isDragging: params.isDragging,
    syncing: leafTabSyncState.status === 'syncing' || webdavSyncRunActive,
    onSync: handleLeafTabAutoSync,
  });

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
    leafTabSyncHasConfig,
    leafTabSyncReady,
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
    leafTabSyncAnalysis,
    leafTabSyncHasConfig,
    leafTabSyncLastResult,
    leafTabSyncReady,
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
    handleLeafTabSyncDialogOpenChange: params.setLeafTabSyncDialogOpen,
    handleLeafTabAutoSync,
    handleWebdavSyncNowFromCenter: async () => {
      const result = await handleLeafTabSync({
        requestBookmarkPermission: true,
        silentSuccess: true,
      });
      return Boolean(result);
    },
    handleWebdavRepairFromCenter: runWebdavRepair,
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
    params.setLeafTabSyncDialogOpen,
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
