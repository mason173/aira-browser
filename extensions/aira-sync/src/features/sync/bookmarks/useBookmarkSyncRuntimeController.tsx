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
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PENDING_BOOKMARK_CONFLICT_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE,
  LEAFTAB_SYNC_DEFAULT_ROOT_PATH,
  PERSONAL_SERVER_LAST_ERROR_AT_KEY,
  PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY,
  PERSONAL_SERVER_LAST_SYNC_AT_KEY,
  WEBDAV_LAST_ERROR_AT_KEY,
  WEBDAV_LAST_ERROR_MESSAGE_KEY,
  WEBDAV_LAST_SYNC_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  PERSONAL_SERVER_CONNECTION_STORAGE_KEY,
  readPersonalServerConnection,
  type PersonalServerConnection,
} from '@/features/personal-server/PersonalServerConnection';
import type {
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import { parseLeafTabSyncRemoteKind } from '@/sync/leaftab/source';
import { useSyncState } from '@/sync/useSyncState';
import {
  readAllExtensionStorageRecords,
  readExtensionStorageRecord,
} from '@/platform/extensionStorage';
import {
  type BookmarkSyncDataOverview,
} from './BookmarkSyncModule';
import {
  BookmarkSyncPopupRuntime,
  type BookmarkSyncPopupActionCallbacks,
  type BookmarkSyncPopupRunOutcome,
} from './BookmarkSyncPopupRuntime';
import {
  hasWebdavUrlConfiguredFromStorage,
  readWebdavConfigFromStorage,
  seedWebdavCredentialsToExtensionStorage,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';
import {
  type AiraDesktopConnectionProfile,
} from '@/features/desktop-connection/desktopConnectionProfile';
import { resolveAiraDesktopSyncStatus } from './desktopSyncEligibility';
import {
  isAiraCloudSyncPreferenceStorageKey,
  readAiraCloudSyncEnabledFromLocalStorage,
} from './airaCloudPreferences';

type BookmarkSyncPresentationOptions = {
  allowConfigPrompt?: boolean;
  showAllBlockedReasons?: boolean;
};

type BookmarkSyncPopupAction = (
  callbacks: BookmarkSyncPopupActionCallbacks,
) => Promise<BookmarkSyncPopupRunOutcome>;

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

const formatLeafTabSyncErrorMessage = (error: unknown, remoteKind: LeafTabSyncRemoteKind = 'webdav') => {
  const providerName = remoteKind === 'aira-cloud'
    ? 'Aira 云同步'
    : remoteKind === 'personal-server' ? 'Personal Server' : 'WebDAV';
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

const SHARED_EXTENSION_STORAGE_KEYS: string[] = [
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  PERSONAL_SERVER_LAST_SYNC_AT_KEY,
  PERSONAL_SERVER_LAST_ERROR_AT_KEY,
  PERSONAL_SERVER_LAST_ERROR_MESSAGE_KEY,
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
  PERSONAL_SERVER_CONNECTION_STORAGE_KEY,
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
    if (key === PERSONAL_SERVER_CONNECTION_STORAGE_KEY) return;
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

const resolveRemoteProgressName = (remoteKind: LeafTabSyncRemoteKind) => (
  remoteKind === 'aira-cloud' ? '云端' : remoteKind === 'personal-server' ? '个人服务器' : 'WebDAV'
);

const resolveProgressDetail = (
  remoteKind: LeafTabSyncRemoteKind,
  message?: string,
) => {
  if (message) return message.replace('远端', resolveRemoteProgressName(remoteKind));
  return `正在读取本机和${resolveRemoteProgressName(remoteKind)}书签`;
};

export type BookmarkSyncRuntimeControllerParams = {
  openWebdavConfig: () => void;
  openPersonalServerConfig: () => void;
  desktopConnectionProfile: AiraDesktopConnectionProfile | null;
};

export function useBookmarkSyncRuntimeController(
  params: BookmarkSyncRuntimeControllerParams,
): LeafTabSyncFacade {
  const { desktopConnectionProfile, openPersonalServerConfig, openWebdavConfig } = params;
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
  const [personalServerConnection, setPersonalServerConnection] =
    useState<PersonalServerConnection | null>(null);
  const leafTabSyncRootPath = LEAFTAB_SYNC_DEFAULT_ROOT_PATH;
  const cloudUid = desktopConnectionProfile?.uid || '';
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
  const bookmarkSyncRuntime = useMemo(() => new BookmarkSyncPopupRuntime({
    deviceId: leafTabSyncDeviceId,
    rootPath: leafTabSyncRootPath,
  }), [
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
  ]);

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
      const [pending, connection] = await Promise.all([
        bookmarkSyncRuntime.readPendingConflict(),
        readPersonalServerConnection(),
      ]);
      if (cancelled) {
        return;
      }
      setLeafTabPendingBookmarkConflict(pending);
      setPersonalServerConnection(connection);
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
  }, [bookmarkSyncRuntime, cloudUid]);

  const refreshBookmarkDataOverview = useCallback(async () => {
    const requestId = leafTabSummaryRefreshRequestRef.current + 1;
    leafTabSummaryRefreshRequestRef.current = requestId;
    if (!syncStorageReady || !leafTabSyncDeviceId || !selectedSyncSource) {
      leafTabSummarySourceKeyRef.current = '';
      setLeafTabBookmarkDataOverview(null);
      setLeafTabSummaryLoading(false);
      return;
    }

    setLeafTabSummaryLoading(true);
    const summaryResult = await bookmarkSyncRuntime.readOverview(
      selectedSyncSource,
      selectedSyncSource === 'aira-cloud'
        ? leafTabCloudSyncStatus !== 'login-required' && leafTabCloudSyncStatus !== 'pro-required'
        : selectedSyncSource === 'personal-server'
          ? Boolean(personalServerConnection?.capabilities.bookmarks)
          : Boolean(webdavConfig?.url),
    );
    if (leafTabSummaryRefreshRequestRef.current !== requestId) {
      return;
    }
    if (leafTabSummarySourceKeyRef.current !== summaryResult.sourceIdentity) {
      leafTabSummarySourceKeyRef.current = summaryResult.sourceIdentity;
      setLeafTabBookmarkDataOverview(null);
    }
    if (summaryResult.baselineOverview) {
      setLeafTabBookmarkDataOverview((current) => current || summaryResult.baselineOverview);
    }
    if (summaryResult.overview) {
      setLeafTabBookmarkDataOverview((current) => ({
        local: summaryResult.overview?.local || current?.local || null,
        remote: summaryResult.overview?.remote || current?.remote || null,
      }));
    }
    if (leafTabSummaryRefreshRequestRef.current === requestId) {
      setLeafTabSummaryLoading(false);
    }
  }, [
    bookmarkSyncRuntime,
    leafTabCloudSyncStatus,
    leafTabSyncDeviceId,
    selectedSyncSource,
    syncStorageReady,
    personalServerConnection,
    webdavConfig?.url,
  ]);

  useEffect(() => {
    void refreshBookmarkDataOverview();
  }, [refreshBookmarkDataOverview]);

  const runBookmarkSyncAction = useCallback(async (
    remoteKind: LeafTabSyncRemoteKind,
    action: BookmarkSyncPopupAction,
    options: BookmarkSyncPresentationOptions = {},
  ): Promise<LeafTabSyncEngineResult | null> => {
    if (!syncStorageReady || !leafTabSyncDeviceId) {
      return null;
    }

    let runStarted = false;
    const outcome = await action({
      onRunStarted: () => {
        runStarted = true;
        setWebdavSyncRunActive(true);
        markSyncStart();
        beginSyncProgress(remoteKind);
      },
      onProgress: (progress) => {
        updateSyncProgress(remoteKind, progress);
      },
    });

    try {
      if (outcome.type === 'blocked') {
        const shouldOpenConfig = remoteKind === 'webdav' &&
          (outcome.reason === 'webdav-config-required' || outcome.reason === 'source-disabled') &&
          options.allowConfigPrompt !== false;
        if (shouldOpenConfig) {
          openWebdavConfig();
        }
        const shouldOpenPersonalServerConfig = remoteKind === 'personal-server'
          && outcome.reason === 'personal-server-config-required'
          && options.allowConfigPrompt !== false;
        if (shouldOpenPersonalServerConfig) {
          openPersonalServerConfig();
        }
        const shouldShowBlocked = !shouldOpenConfig && !shouldOpenPersonalServerConfig
          && (options.showAllBlockedReasons === true
          || outcome.reason === 'pending-conflict'
          || outcome.reason === 'cloud-login-required'
          || outcome.reason === 'client-update-required'
          || outcome.reason === 'bookmarks-permission-required');
        if (shouldShowBlocked) {
          toast.error(outcome.message);
        }
        if (runStarted && outcome.reason === 'client-update-required') {
          markSyncError(outcome.message);
          failSyncProgress(new Error(outcome.message), remoteKind);
        }
        return null;
      }
      if (outcome.type === 'conflict') {
        markSyncConflict();
        setLeafTabSyncLastResult(outcome.result);
        setLeafTabPendingBookmarkConflict(outcome.pendingConflict);
        conflictSyncProgress(
          outcome.result.summaryText || '检测到同步冲突，请选择保留哪一端的数据。',
          remoteKind,
        );
        return outcome.result;
      }
      if (outcome.type === 'failed') {
        markSyncError(outcome.message);
        failSyncProgress(outcome.error, remoteKind);
        return null;
      }

      markSyncSuccess();
      setLeafTabSyncLastResult(outcome.result);
      setLeafTabPendingBookmarkConflict(null);
      setLeafTabBookmarkDataOverview(outcome.overview);
      finishSyncProgress(outcome.result.summaryText || '书签已同步完成');
      return outcome.result;
    } finally {
      if (runStarted) {
        setWebdavSyncRunActive(false);
      }
    }
  }, [
    beginSyncProgress,
    conflictSyncProgress,
    failSyncProgress,
    finishSyncProgress,
    leafTabSyncDeviceId,
    markSyncConflict,
    markSyncError,
    markSyncStart,
    markSyncSuccess,
    openWebdavConfig,
    openPersonalServerConfig,
    syncStorageReady,
    updateSyncProgress,
  ]);

  const handleActiveSyncNowFromCenter = useCallback(async () => {
    const selectedSource = selectedSyncSource;

    if (!selectedSource) {
      return false;
    }

    return Boolean(await runBookmarkSyncAction(
      selectedSource,
      (callbacks) => bookmarkSyncRuntime.syncNow(selectedSource, callbacks),
      { showAllBlockedReasons: true },
    ));
  }, [
    bookmarkSyncRuntime,
    runBookmarkSyncAction,
    selectedSyncSource,
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
    leafTabSyncHasConfig: Boolean(webdavConfig?.url || personalServerConnection || cloudUid),
    leafTabSyncLastResult,
    leafTabLocalSummary: leafTabBookmarkDataOverview?.local || null,
    leafTabRemoteSummary: leafTabBookmarkDataOverview?.remote || null,
    leafTabSummaryLoading,
    leafTabWebdavConfigured,
    leafTabWebdavProfileLabel,
    leafTabWebdavLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(WEBDAV_LAST_SYNC_AT_KEY)),
    leafTabPersonalServerConfigured: personalServerConnection !== null,
    leafTabPersonalServerProfileLabel: personalServerConnection
      ? `${personalServerConnection.baseUrl} · ${personalServerConnection.instanceId.slice(-8)}`
      : '',
    leafTabPersonalServerLastSyncLabel: formatLiteSyncTimestamp(
      localStorage.getItem(PERSONAL_SERVER_LAST_SYNC_AT_KEY),
    ),
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
    personalServerConnection,
    localVersion,
  ]);

  const actions = useMemo<LeafTabSyncActions>(() => ({
    handleSelectSyncSource: async (remoteKind) => {
      const result = await runBookmarkSyncAction(
        remoteKind,
        (callbacks) => bookmarkSyncRuntime.selectSource(remoteKind, callbacks),
        { allowConfigPrompt: true },
      );
      if (!result || result.kind === 'conflict') {
        return false;
      }
      toast.success(remoteKind === 'aira-cloud'
        ? '已选择 Aira 云同步'
        : remoteKind === 'personal-server'
          ? '已选择 Personal Server 同步'
          : '已选择 WebDAV 同步');
      return true;
    },
    handleSaveAndSelectWebdav: async (candidate) => {
      const result = await runBookmarkSyncAction(
        'webdav',
        (callbacks) => bookmarkSyncRuntime.selectWebdavSource({
          ...candidate,
          syncEnabled: false,
        }, callbacks),
        { allowConfigPrompt: false, showAllBlockedReasons: true },
      );
      if (!result || result.kind === 'conflict') {
        return false;
      }
      toast.success('已选择 WebDAV 同步');
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
      const result = await runBookmarkSyncAction(
        remoteKind,
        (callbacks) => bookmarkSyncRuntime.resolveConflict(remoteKind, choice, callbacks),
        { allowConfigPrompt: false },
      );
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
    bookmarkSyncRuntime,
    leafTabPendingBookmarkConflict,
    leafTabSyncProgress.remoteKind,
    selectedSyncSource,
    runBookmarkSyncAction,
  ]);

  return {
    state,
    actions,
  };
}
