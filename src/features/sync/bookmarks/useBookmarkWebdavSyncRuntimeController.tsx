import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from '@/components/ui/sonner';
import type {
  LeafTabInitialSyncChoiceRequest,
  LeafTabPrimarySyncSwitchStrategy,
  LeafTabRemoteAutoSyncDiagnostic,
  LeafTabRemoteAutoSyncProbeResult,
  LeafTabSyncActions,
  LeafTabSyncFacade,
  LeafTabSyncProgressState,
  LeafTabSyncRemoteKind,
  LeafTabSyncState,
  LeafTabSyncWebdavActionOptions,
} from '@/features/sync/app/LeafTabSyncContracts';
import {
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_SYNC_ENABLED_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS,
  LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY,
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import { readLeafTabBookmarkSyncScope } from '@/sync/leaftab/bookmarkScope';
import type { LeafTabBookmarkTreeDraft } from '@/sync/leaftab/bookmarks';
import type {
  LeafTabSyncAnalysis,
  LeafTabSyncDataSummary,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
  LeafTabSyncInitialChoice,
} from '@/sync/leaftab/engine';
import type { LeafTabSyncRemoteStore } from '@/sync/leaftab/remoteStore';
import { normalizeLeafTabSyncSnapshot, type LeafTabSyncSnapshot } from '@/sync/leaftab/schema';
import { importLeafTabSyncRuntime } from '@/lazy/sync';
import { useSyncState } from '@/sync/useSyncState';
import { getBookmarksApi } from '@/platform/runtime';
import {
  readAllExtensionStorageRecords,
  removeExtensionStorageKeys,
  writeExtensionStorageRecord,
} from '@/platform/extensionStorage';
import { ensureExtensionPermission } from '@/utils/extensionPermissions';
import {
  clearPendingLeafTabLocalBookmarkChanges,
  hasPendingLeafTabLocalBookmarkChanges,
  LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY,
  markLeafTabBookmarkSyncApplyFinished,
  markLeafTabBookmarkSyncApplyStarted,
} from '@/sync/leaftab/localChangeTracker';
import {
  createLeafTabDualSecondarySyncPlan,
  resolveLeafTabSyncRoute,
  shouldBuildLeafTabPrimaryLocalSnapshot,
  type LeafTabSyncRoute,
} from '@/sync/leaftab/syncRouteStateMachine';
import {
  clearWebdavBackupFailureCooldown,
  readWebdavBackupCooldownResult,
  recordWebdavBackupFailureCooldown,
  WEBDAV_BACKUP_REQUEST_TIMEOUT_MS,
  WEBDAV_BACKUP_TOTAL_TIMEOUT_MS,
  withWebdavBackupTimeout,
} from '@/sync/leaftab/webdavBackupPolicy';
import {
  hasWebdavUrlConfiguredFromStorage,
  isWebdavSyncEnabledFromStorage,
  readWebdavConfigFromStorage,
  syncWebdavStorageStateToExtensionStorage,
  WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';
import {
  readAiraDesktopLoginProfile,
  syncAiraDesktopLoginProfileToExtensionStorage,
} from '@/popup/desktopLogin';

const LEAFTAB_SYNC_DEFAULT_ROOT_PATH = WEBDAV_BOOKMARK_SYNC_ROOT_SUFFIX;
const LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX = 'leaftab_sync_v1_analysis';
const LEAFTAB_SYNC_SUMMARY_CACHE_PREFIX = 'leaftab_sync_v1_summary';
const LEAFTAB_AUTO_SYNC_MESSAGE_TYPE = 'LEAFTAB_AUTO_SYNC_NOW';

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
    const existing = localStorage.getItem(LEAFTAB_SYNC_DEVICE_ID_KEY);
    if (existing) return existing;
    const created = typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `dev_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    localStorage.setItem(LEAFTAB_SYNC_DEVICE_ID_KEY, created);
    void writeExtensionStorageRecord({
      [LEAFTAB_SYNC_DEVICE_ID_KEY]: created,
    });
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

const createStorageHash = (source: string) => {
  let hash = 0;
  for (let index = 0; index < source.length; index += 1) {
    hash = ((hash << 5) - hash + source.charCodeAt(index)) | 0;
  }
  return Math.abs(hash).toString(36);
};

const createLeafTabSyncAnalysisCacheKey = (
  remoteKind: LeafTabSyncRemoteKind,
  rootPath: string,
  identity: string,
) => {
  const rootSegment = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  return `${LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX}:${remoteKind}:${rootSegment}:${createStorageHash(identity || 'default')}`;
};

const createLeafTabSyncSummaryCacheKey = (
  kind: LeafTabSyncRemoteKind | 'local',
  rootPath: string,
  identity: string,
) => {
  const rootSegment = (rootPath || LEAFTAB_SYNC_DEFAULT_ROOT_PATH).replace(/[^a-zA-Z0-9_-]+/g, '_');
  return `${LEAFTAB_SYNC_SUMMARY_CACHE_PREFIX}:${kind}:${rootSegment}:${createStorageHash(identity || 'default')}`;
};

const createWebdavCacheIdentity = (
  config: (NonNullable<ReturnType<typeof readWebdavConfigFromStorage>> & { rootPath: string }) | null,
) => {
  if (!config?.url) return '';
  return [
    config.url,
    config.username,
    config.rootPath,
  ].join('|');
};

const isLeafTabSyncDataSummary = (value: unknown): value is LeafTabSyncDataSummary => {
  if (!value || typeof value !== 'object') return false;
  const summary = value as Partial<LeafTabSyncDataSummary>;
  return Number.isFinite(summary.bookmarkFolders)
    && Number.isFinite(summary.bookmarkItems)
    && Number.isFinite(summary.tombstones);
};

const normalizeCachedLeafTabSyncAnalysis = (value: unknown): LeafTabSyncAnalysis | null => {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as Partial<LeafTabSyncAnalysis>;
  if (!isLeafTabSyncDataSummary(candidate.localSummary) || !isLeafTabSyncDataSummary(candidate.remoteSummary)) {
    return null;
  }

  const suggestedInitialChoice = candidate.suggestedInitialChoice === 'push-local'
    || candidate.suggestedInitialChoice === 'pull-remote'
    || candidate.suggestedInitialChoice === 'merge'
    ? candidate.suggestedInitialChoice
    : null;

  return {
    hasBaseline: Boolean(candidate.hasBaseline),
    localSummary: candidate.localSummary,
    remoteSummary: candidate.remoteSummary,
    requiresInitialChoice: Boolean(candidate.requiresInitialChoice),
    suggestedInitialChoice,
    remoteCommitId: typeof candidate.remoteCommitId === 'string' ? candidate.remoteCommitId : null,
  };
};

const formatLeafTabSyncCacheTimestamp = (value: string | null | undefined) => {
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

const readLeafTabSyncAnalysisCache = (cacheKey: string) => {
  try {
    const parsed = JSON.parse(localStorage.getItem(cacheKey) || 'null') as {
      analysis?: unknown;
      updatedAt?: unknown;
    } | null;
    return {
      analysis: normalizeCachedLeafTabSyncAnalysis(parsed?.analysis),
      updatedAt: typeof parsed?.updatedAt === 'string' ? parsed.updatedAt : null,
    };
  } catch {
    return {
      analysis: null,
      updatedAt: null,
    };
  }
};

const writeLeafTabSyncAnalysisCache = (cacheKey: string, analysis: LeafTabSyncAnalysis) => {
  const updatedAt = new Date().toISOString();
  try {
    localStorage.setItem(cacheKey, JSON.stringify({
      version: 1,
      updatedAt,
      analysis,
    }));
  } catch {
    // The sync result is still valid even if local summary caching is unavailable.
  }
  return updatedAt;
};

const readLeafTabSyncSummaryCache = (cacheKey: string): LeafTabSyncDataSummary | null => {
  try {
    const parsed = JSON.parse(localStorage.getItem(cacheKey) || 'null') as {
      summary?: unknown;
    } | null;
    return isLeafTabSyncDataSummary(parsed?.summary) ? parsed.summary : null;
  } catch {
    return null;
  }
};

const writeLeafTabSyncSummaryCache = (
  cacheKey: string,
  summary: LeafTabSyncDataSummary,
): string => {
  const updatedAt = new Date().toISOString();
  try {
    localStorage.setItem(cacheKey, JSON.stringify({
      version: 1,
      updatedAt,
      summary,
    }));
  } catch {}
  void writeExtensionStorageRecord({
    [cacheKey]: JSON.stringify({
      version: 1,
      updatedAt,
      summary,
    }),
  });
  return updatedAt;
};

const requestBackgroundLeafTabAutoSync = (provider: LeafTabSyncRemoteKind) => {
  try {
    chrome.runtime?.sendMessage?.({
      type: LEAFTAB_AUTO_SYNC_MESSAGE_TYPE,
      provider,
    }, () => undefined);
  } catch {}
};

const createLeafTabSyncAnalysisWithLocalSummary = (
  analysis: LeafTabSyncAnalysis,
  localSummary: LeafTabSyncAnalysis['localSummary'],
): LeafTabSyncAnalysis => ({
  ...analysis,
  localSummary,
});

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

const readLeafTabSyncBaselineSnapshot = async (storageKey: string): Promise<LeafTabSyncSnapshot | null> => {
  try {
    const runtime = await importLeafTabSyncRuntime();
    const baselineStore = new runtime.LeafTabSyncExtensionStorageBaselineStore(storageKey);
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

const runtimeSummaryFromSnapshot = (snapshot: LeafTabSyncSnapshot): LeafTabSyncDataSummary => ({
  bookmarkFolders: Object.keys(snapshot.bookmarkFolders || {}).length,
  bookmarkItems: Object.keys(snapshot.bookmarkItems || {}).length,
  tombstones: Object.keys(snapshot.tombstones || {}).length,
});

const createAnalysisFromSyncedSnapshot = (
  result: LeafTabSyncEngineResult,
): LeafTabSyncAnalysis => {
  const nextSummary = result.snapshotSummary;
  return {
    hasBaseline: true,
    localSummary: nextSummary,
    remoteSummary: nextSummary,
    requiresInitialChoice: false,
    suggestedInitialChoice: null,
    remoteCommitId: result.remoteCommitId,
  };
};

const SHARED_EXTENSION_STORAGE_KEYS: string[] = [
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY,
  LEAFTAB_LOCAL_BOOKMARK_CHANGED_AT_KEY,
  LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.pendingLocalChangedAt,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.lastRemoteProbeAt,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.nextRemoteProbeAt,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRunning,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncLastError,
  LEAFTAB_BACKGROUND_STORAGE_KEYS.autoSyncRetryProvider,
  AIRA_CLOUD_SYNC_ENABLED_KEY,
  AIRA_CLOUD_LAST_SYNC_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_AT_KEY,
  AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
  'webdav_last_sync_at',
  'webdav_last_error_at',
  'webdav_last_error_message',
  ...Object.values(WEBDAV_STORAGE_KEYS),
];

const isSharedSyncStorageKey = (key: string) => (
  SHARED_EXTENSION_STORAGE_KEYS.includes(key)
  || key.startsWith(LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX)
  || key.startsWith(LEAFTAB_SYNC_SUMMARY_CACHE_PREFIX)
);

const syncSharedExtensionStorageToLocalStorage = async () => {
  const record = await readAllExtensionStorageRecords();
  SHARED_EXTENSION_STORAGE_KEYS.forEach((key) => {
    const value = record[key];
    if (value === undefined || value === null || value === '') {
      localStorage.removeItem(key);
      return;
    }
    localStorage.setItem(key, String(value));
  });
  for (let index = localStorage.length - 1; index >= 0; index -= 1) {
    const key = localStorage.key(index);
    if (!key || (!key.startsWith(LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX) && !key.startsWith(LEAFTAB_SYNC_SUMMARY_CACHE_PREFIX))) {
      continue;
    }
    if (!(key in record)) {
      localStorage.removeItem(key);
    }
  }
  Object.entries(record).forEach(([key, value]) => {
    if (!key.startsWith(LEAFTAB_SYNC_ANALYSIS_CACHE_PREFIX) && !key.startsWith(LEAFTAB_SYNC_SUMMARY_CACHE_PREFIX)) {
      return;
    }
    if (value === undefined || value === null || value === '') {
      localStorage.removeItem(key);
      return;
    }
    localStorage.setItem(key, String(value));
  });
};

const createAnalysisFromBaselineSnapshot = (snapshot: LeafTabSyncSnapshot): LeafTabSyncAnalysis => {
  const summary = runtimeSummaryFromSnapshot(snapshot);
  return {
    hasBaseline: true,
    localSummary: summary,
    remoteSummary: summary,
    requiresInitialChoice: false,
    suggestedInitialChoice: null,
    remoteCommitId: null,
  };
};

const createInitialChoiceAnalysisFromConflict = (
  result: LeafTabSyncEngineResult,
): LeafTabSyncAnalysis => (
  result.initialChoiceAnalysis || {
    hasBaseline: false,
    localSummary: result.snapshotSummary,
    remoteSummary: result.snapshotSummary,
    requiresInitialChoice: true,
    suggestedInitialChoice: 'merge',
    remoteCommitId: result.remoteCommitId,
  }
);

const createIdleProgressState = (): LeafTabSyncProgressState => ({
  open: false,
  inProgress: false,
  title: '',
  detail: '',
  progress: 0,
  latestProgress: null,
});

const readPreferredPrimaryRemoteKindFromStorage = (): LeafTabSyncRemoteKind | null => {
  const raw = localStorage.getItem(LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY);
  if (raw === 'aira-cloud' || raw === 'webdav') {
    return raw;
  }
  return null;
};

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

const resolveDualProgressMessage = (remoteKind: LeafTabSyncRemoteKind) => (
  remoteKind === 'aira-cloud' ? '正在同步云端书签' : '正在同步 WebDAV 书签'
);

const resolvePrimarySwitchMode = (
  strategy: LeafTabPrimarySyncSwitchStrategy,
): LeafTabSyncInitialChoice => {
  if (strategy === 'upload-local') return 'push-local';
  if (strategy === 'use-remote') return 'pull-remote';
  return 'merge';
};

const isDualLeafTabSyncRoute = (
  route: LeafTabSyncRoute,
): route is Extract<LeafTabSyncRoute, { kind: 'dual' }> => route.kind === 'dual';

const createWebdavBackupTargetFromConfig = (
  config: (NonNullable<ReturnType<typeof readWebdavConfigFromStorage>> & { rootPath: string }) | null,
) => {
  if (!config?.url) return null;
  return {
    url: config.url,
    username: config.username,
    rootPath: config.rootPath,
  };
};

const createLeafTabRemoteAutoSyncDiagnostic = (
  probe: LeafTabRemoteAutoSyncProbeResult,
  overrides?: Partial<LeafTabRemoteAutoSyncDiagnostic>,
): LeafTabRemoteAutoSyncDiagnostic => ({
  lastCheckedAt: new Date().toISOString(),
  lastProvider: probe.provider || '',
  lastBaselineCommitId: probe.baselineCommitId || '',
  lastRemoteCommitId: probe.remoteCommitId || '',
  lastRemoteFolders: Number(probe.remoteFolders || 0),
  lastRemoteItems: Number(probe.remoteItems || 0),
  lastRemoteTombstones: Number(probe.remoteTombstones || 0),
  lastHadChanges: Boolean(probe.hasChanges),
  lastSyncAttempted: false,
  lastSyncSucceeded: null,
  lastError: probe.error || '',
  ...overrides,
});

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
    hasPendingLocalChanges: hasPendingLeafTabLocalBookmarkChanges,
    clearPendingLocalChanges: clearPendingLeafTabLocalBookmarkChanges,
    createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(deviceId),
    rootPath,
  });

  return engine.sync(mode, {
    localSnapshotOverride: options?.localSnapshotOverride,
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
    requestTimeoutMs: params.options?.webdavRequestTimeoutMs,
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
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
    setSyncConfigBackTarget,
  } = params;
  const [localVersion, setLocalVersion] = useState(0);
  const [webdavSyncRunActive, setWebdavSyncRunActive] = useState(false);
  const [leafTabSyncLastResult, setLeafTabSyncLastResult] = useState<LeafTabSyncEngineResult | null>(null);
  const [leafTabSyncAnalysis, setLeafTabSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabSyncAnalysisRemoteKind, setLeafTabSyncAnalysisRemoteKind] = useState<LeafTabSyncRemoteKind | null>(null);
  const [leafTabLocalBookmarkSummary, setLeafTabLocalBookmarkSummary] = useState<LeafTabSyncDataSummary | null>(null);
  const [leafTabWebdavRemoteSummary, setLeafTabWebdavRemoteSummary] = useState<LeafTabSyncDataSummary | null>(null);
  const [leafTabCloudRemoteSummary, setLeafTabCloudRemoteSummary] = useState<LeafTabSyncDataSummary | null>(null);
  const [leafTabWebdavSyncAnalysis, setLeafTabWebdavSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabCloudSyncAnalysis, setLeafTabCloudSyncAnalysis] = useState<LeafTabSyncAnalysis | null>(null);
  const [leafTabWebdavAnalysisCheckedAt, setLeafTabWebdavAnalysisCheckedAt] = useState<string | null>(null);
  const [leafTabCloudAnalysisCheckedAt, setLeafTabCloudAnalysisCheckedAt] = useState<string | null>(null);
  const [leafTabRemoteAutoSyncDiagnostic, setLeafTabRemoteAutoSyncDiagnostic] =
    useState<LeafTabRemoteAutoSyncDiagnostic | null>(null);
  const [leafTabSyncProgress, setLeafTabSyncProgress] = useState<LeafTabSyncProgressState>(() => createIdleProgressState());
  const [leafTabInitialSyncChoiceRequest, setLeafTabInitialSyncChoiceRequest] =
    useState<LeafTabInitialSyncChoiceRequest | null>(null);
  const initialSyncChoiceResolverRef = useRef<((choice: LeafTabSyncInitialChoice | null) => void) | null>(null);
  const initialLocalSummaryHydratedRef = useRef(false);
  const remoteSummaryHydratedKeyRef = useRef('');
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
  const preferredPrimaryRemoteKind = useMemo(() => {
    void localVersion;
    return readPreferredPrimaryRemoteKindFromStorage();
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
  const leafTabWebdavCacheIdentity = useMemo(
    () => createWebdavCacheIdentity(webdavConfig),
    [webdavConfig?.rootPath, webdavConfig?.url, webdavConfig?.username],
  );
  const leafTabWebdavAnalysisCacheKey = useMemo(
    () => createLeafTabSyncAnalysisCacheKey('webdav', leafTabSyncRootPath, leafTabWebdavCacheIdentity),
    [leafTabSyncRootPath, leafTabWebdavCacheIdentity],
  );
  const leafTabCloudAnalysisCacheKey = useMemo(
    () => createLeafTabSyncAnalysisCacheKey('aira-cloud', leafTabSyncRootPath, cloudUid),
    [cloudUid, leafTabSyncRootPath],
  );
  const leafTabLocalSummaryCacheKey = useMemo(
    () => createLeafTabSyncSummaryCacheKey('local', leafTabSyncRootPath, leafTabSyncDeviceId),
    [leafTabSyncDeviceId, leafTabSyncRootPath],
  );
  const leafTabWebdavSummaryCacheKey = useMemo(
    () => createLeafTabSyncSummaryCacheKey('webdav', leafTabSyncRootPath, leafTabWebdavCacheIdentity),
    [leafTabSyncRootPath, leafTabWebdavCacheIdentity],
  );
  const leafTabCloudSummaryCacheKey = useMemo(
    () => createLeafTabSyncSummaryCacheKey('aira-cloud', leafTabSyncRootPath, cloudUid),
    [cloudUid, leafTabSyncRootPath],
  );

  const captureBookmarkTreeDraft = useCallback(async (): Promise<LeafTabBookmarkTreeDraft> => {
    const snapshotRuntime = await import('@/sync/leaftab/snapshotRuntime');
    return snapshotRuntime.captureLeafTabBookmarkTreeDraft({
      scope: leafTabBookmarkSyncScope,
      requestPermission: true,
      throwOnPermissionDenied: true,
    });
  }, [leafTabBookmarkSyncScope]);

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

  const captureLocalBookmarkSummary = useCallback(async (): Promise<LeafTabSyncAnalysis['localSummary'] | null> => {
    try {
      const bookmarkTree = await captureBookmarkTreeDraft();
      return {
        bookmarkFolders: bookmarkTree.folders.length,
        bookmarkItems: bookmarkTree.items.length,
        tombstones: 0,
      };
    } catch {
      return null;
    }
  }, [captureBookmarkTreeDraft]);

  const readLocalSummaryCheckedAt = useCallback(() => {
    try {
      return localStorage.getItem(LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY);
    } catch {
      return null;
    }
  }, []);

  const markLocalSummaryCheckedAt = useCallback(() => {
    const next = new Date().toISOString();
    try {
      localStorage.setItem(LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY, next);
    } catch {
      // Ignore storage availability issues; local summary still renders.
    }
    void writeExtensionStorageRecord({
      [LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY]: next,
    });
    return next;
  }, []);

  const readCachedOrBaselineAnalysis = useCallback(async (
    cacheKey: string,
    baselineStorageKey: string,
  ) => {
    const cached = readLeafTabSyncAnalysisCache(cacheKey);
    if (cached.analysis) return cached;

    const baselineSnapshot = await readLeafTabSyncBaselineSnapshot(baselineStorageKey);
    if (!baselineSnapshot) {
      return {
        analysis: null,
        updatedAt: null,
      };
    }
    const analysis = createAnalysisFromBaselineSnapshot(baselineSnapshot);
    return {
      analysis,
      updatedAt: writeLeafTabSyncAnalysisCache(cacheKey, analysis),
    };
  }, []);

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
    markLeafTabBookmarkSyncApplyStarted();
    try {
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
    } finally {
      markLeafTabBookmarkSyncApplyFinished();
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
        buildLocalSnapshot: () => options?.localSnapshotOverride
          ? Promise.resolve(options.localSnapshotOverride)
          : buildBookmarkSnapshotForBaseline(leafTabSyncBaselineStorageKey),
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
    buildBookmarkSnapshotForBaseline,
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
        buildLocalSnapshot: () => options?.localSnapshotOverride
          ? Promise.resolve(options.localSnapshotOverride)
          : buildBookmarkSnapshotForBaseline(leafTabCloudBaselineStorageKey),
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
    buildBookmarkSnapshotForBaseline,
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
      buildLocalSnapshot: () => buildBookmarkSnapshotForBaseline(leafTabSyncBaselineStorageKey),
      applyLocalSnapshot: applyWebdavBookmarkSnapshot,
      hasPendingLocalChanges: hasPendingLeafTabLocalBookmarkChanges,
      clearPendingLocalChanges: clearPendingLeafTabLocalBookmarkChanges,
      createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(leafTabSyncDeviceId),
      rootPath: webdavConfig.rootPath,
    });

    const analysis = await engine.analyze();
    setLeafTabSyncAnalysisRemoteKind('webdav');
    setLeafTabSyncAnalysis(analysis);
    setLeafTabWebdavSyncAnalysis(analysis);
    setLeafTabLocalBookmarkSummary(analysis.localSummary);
    setLeafTabWebdavRemoteSummary(analysis.remoteSummary);
    writeLeafTabSyncSummaryCache(leafTabLocalSummaryCacheKey, analysis.localSummary);
    writeLeafTabSyncSummaryCache(leafTabWebdavSummaryCacheKey, analysis.remoteSummary);
    setLeafTabWebdavAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabWebdavAnalysisCacheKey, analysis));
    return analysis;
  }, [
    applyWebdavBookmarkSnapshot,
    buildBookmarkSnapshotForBaseline,
    leafTabLocalSummaryCacheKey,
    leafTabSyncBaselineStorageKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabSyncDeviceId,
    leafTabWebdavAnalysisCacheKey,
    leafTabWebdavSummaryCacheKey,
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
      buildLocalSnapshot: () => buildBookmarkSnapshotForBaseline(leafTabCloudBaselineStorageKey),
      applyLocalSnapshot: applyWebdavBookmarkSnapshot,
      hasPendingLocalChanges: hasPendingLeafTabLocalBookmarkChanges,
      clearPendingLocalChanges: clearPendingLeafTabLocalBookmarkChanges,
      createEmptySnapshot: () => createEmptyLiteLeafTabSyncSnapshot(leafTabSyncDeviceId),
      rootPath: leafTabSyncRootPath,
    });

    const analysis = await engine.analyze();
    setLeafTabSyncAnalysisRemoteKind('aira-cloud');
    setLeafTabSyncAnalysis(analysis);
    setLeafTabCloudSyncAnalysis(analysis);
    setLeafTabLocalBookmarkSummary(analysis.localSummary);
    setLeafTabCloudRemoteSummary(analysis.remoteSummary);
    writeLeafTabSyncSummaryCache(leafTabLocalSummaryCacheKey, analysis.localSummary);
    writeLeafTabSyncSummaryCache(leafTabCloudSummaryCacheKey, analysis.remoteSummary);
    setLeafTabCloudAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabCloudAnalysisCacheKey, analysis));
    return analysis;
  }, [
    applyWebdavBookmarkSnapshot,
    buildBookmarkSnapshotForBaseline,
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabCloudAnalysisCacheKey,
    leafTabCloudSummaryCacheKey,
    leafTabLocalSummaryCacheKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabSyncDeviceId,
    leafTabSyncRootPath,
  ]);

  const updateLeafTabRemoteAutoSyncDiagnostic = useCallback((
    probe: LeafTabRemoteAutoSyncProbeResult,
    overrides?: Partial<LeafTabRemoteAutoSyncDiagnostic>,
  ) => {
    setLeafTabRemoteAutoSyncDiagnostic((current) => createLeafTabRemoteAutoSyncDiagnostic(probe, {
      lastSyncAttempted: current?.lastSyncAttempted ?? false,
      lastSyncSucceeded: current?.lastSyncSucceeded ?? null,
      ...overrides,
    }));
  }, []);

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
      localCheckedAt: readLocalSummaryCheckedAt(),
      remoteCheckedAt: leafTabSyncAnalysisRemoteKind === 'aira-cloud'
        ? leafTabCloudAnalysisCheckedAt
        : leafTabWebdavAnalysisCheckedAt,
    });
    return new Promise<LeafTabSyncInitialChoice | null>((resolve) => {
      initialSyncChoiceResolverRef.current = resolve;
    });
  }, [
    leafTabCloudAnalysisCheckedAt,
    leafTabSyncAnalysisRemoteKind,
    leafTabWebdavAnalysisCheckedAt,
    readLocalSummaryCheckedAt,
  ]);

  const resolveLeafTabInitialSyncChoice = useCallback((choice: LeafTabSyncInitialChoice | null) => {
    const resolver = initialSyncChoiceResolverRef.current;
    initialSyncChoiceResolverRef.current = null;
    setLeafTabInitialSyncChoiceRequest(null);
    resolver?.(choice);
  }, []);

  const markWebdavSyncSuccess = useCallback(() => {
    const nowIso = new Date().toISOString();
    localStorage.setItem('webdav_last_sync_at', nowIso);
    localStorage.removeItem('webdav_last_error_at');
    localStorage.removeItem('webdav_last_error_message');
    void writeExtensionStorageRecord({
      webdav_last_sync_at: nowIso,
    });
    void removeExtensionStorageKeys([
      'webdav_last_error_at',
      'webdav_last_error_message',
    ]);
    const target = createWebdavBackupTargetFromConfig(webdavConfig);
    if (target) {
      void clearWebdavBackupFailureCooldown(target);
    }
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged, webdavConfig]);

  const markWebdavSyncError = useCallback((error: unknown) => {
    console.error('[LeafTab][WebDAV sync]', error);
    const nowIso = new Date().toISOString();
    const message = String((error as Error)?.message || 'unknown');
    localStorage.setItem('webdav_last_error_at', nowIso);
    localStorage.setItem('webdav_last_error_message', message);
    void writeExtensionStorageRecord({
      webdav_last_error_at: nowIso,
      webdav_last_error_message: message,
    });
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncSuccess = useCallback(() => {
    const nowIso = new Date().toISOString();
    localStorage.setItem(AIRA_CLOUD_LAST_SYNC_AT_KEY, nowIso);
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_AT_KEY);
    localStorage.removeItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY);
    void writeExtensionStorageRecord({
      [AIRA_CLOUD_LAST_SYNC_AT_KEY]: nowIso,
    });
    void removeExtensionStorageKeys([
      AIRA_CLOUD_LAST_ERROR_AT_KEY,
      AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY,
    ]);
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const markCloudSyncError = useCallback((error: unknown) => {
    console.error('[LeafTab][Aira cloud sync]', error);
    const nowIso = new Date().toISOString();
    const message = String((error as Error)?.message || 'unknown');
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_AT_KEY, nowIso);
    localStorage.setItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY, message);
    void writeExtensionStorageRecord({
      [AIRA_CLOUD_LAST_ERROR_AT_KEY]: nowIso,
      [AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]: message,
    });
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setWebdavSyncEnabledInStorage = useCallback((enabled: boolean) => {
    localStorage.setItem(WEBDAV_STORAGE_KEYS.syncEnabled, String(enabled));
    if (!enabled) {
      localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
    }
    void writeExtensionStorageRecord({
      [WEBDAV_STORAGE_KEYS.syncEnabled]: String(enabled),
    });
    if (!enabled) {
      void removeExtensionStorageKeys([WEBDAV_STORAGE_KEYS.nextSyncAt]);
    }
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setCloudSyncEnabledInStorage = useCallback((enabled: boolean) => {
    localStorage.setItem(AIRA_CLOUD_SYNC_ENABLED_KEY, String(enabled));
    void writeExtensionStorageRecord({
      [AIRA_CLOUD_SYNC_ENABLED_KEY]: String(enabled),
    });
    emitWebdavSyncStatusChanged();
  }, [emitWebdavSyncStatusChanged]);

  const setPrimaryRemoteKindInStorage = useCallback((remoteKind: LeafTabSyncRemoteKind | null) => {
    if (remoteKind === null) {
      localStorage.removeItem(LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY);
      void removeExtensionStorageKeys([LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY]);
    } else {
      localStorage.setItem(LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY, remoteKind);
      void writeExtensionStorageRecord({
        [LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY]: remoteKind,
      });
    }
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

  const updateCachedLocalSummaries = useCallback(async () => {
    const localSummary = await captureLocalBookmarkSummary();
    if (!localSummary) return;
    markLocalSummaryCheckedAt();
    setLeafTabLocalBookmarkSummary(localSummary);
    writeLeafTabSyncSummaryCache(leafTabLocalSummaryCacheKey, localSummary);

    setLeafTabWebdavSyncAnalysis((current) => {
      if (!current) return current;
      const next = createLeafTabSyncAnalysisWithLocalSummary(current, localSummary);
      setLeafTabWebdavAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabWebdavAnalysisCacheKey, next));
      return next;
    });
    setLeafTabCloudSyncAnalysis((current) => {
      if (!current) return current;
      const next = createLeafTabSyncAnalysisWithLocalSummary(current, localSummary);
      setLeafTabCloudAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabCloudAnalysisCacheKey, next));
      return next;
    });
    setLeafTabSyncAnalysis((current) => {
      if (!current) return current;
      const next = createLeafTabSyncAnalysisWithLocalSummary(current, localSummary);
      const cacheKey = leafTabSyncAnalysisRemoteKind === 'aira-cloud'
        ? leafTabCloudAnalysisCacheKey
        : leafTabWebdavAnalysisCacheKey;
      const updatedAt = writeLeafTabSyncAnalysisCache(cacheKey, next);
      if (leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
        setLeafTabCloudAnalysisCheckedAt(updatedAt);
      } else {
        setLeafTabWebdavAnalysisCheckedAt(updatedAt);
      }
      return next;
    });
  }, [
    captureLocalBookmarkSummary,
    leafTabCloudAnalysisCacheKey,
    leafTabLocalSummaryCacheKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabWebdavAnalysisCacheKey,
    markLocalSummaryCheckedAt,
  ]);

  const handleDismissSyncProgress = useCallback(() => {
    setLeafTabSyncProgress((current) => (
      current.inProgress ? current : createIdleProgressState()
    ));
  }, []);

  const refreshCachedRemoteSummariesFromHead = useCallback(async () => {
    const runtime = await importLeafTabSyncRuntime();
    const tasks: Promise<void>[] = [];
    if (webdavConfig?.url) {
      tasks.push((async () => {
        const webdavStore = new runtime.LeafTabSyncWebdavStore({
          url: webdavConfig.url,
          username: webdavConfig.username,
          password: webdavConfig.password,
          rootPath: webdavConfig.rootPath,
          requestPermission: false,
          requestTimeoutMs: WEBDAV_BACKUP_REQUEST_TIMEOUT_MS,
        });
        const remoteHead = await webdavStore.readHead();
        const headSummary = remoteHead.summary || remoteHead.commit?.summary;
        const summary = remoteHead.commitId === null
          ? { bookmarkFolders: 0, bookmarkItems: 0, tombstones: 0 }
          : headSummary;
        if (!summary) return;
        setLeafTabWebdavRemoteSummary(summary);
        writeLeafTabSyncSummaryCache(leafTabWebdavSummaryCacheKey, summary);
      })().catch(() => undefined));
    }
    if (cloudUid) {
      tasks.push((async () => {
        const cloudStore = new runtime.LeafTabSyncAiraCloudStore(cloudUid);
        const remoteHead = await cloudStore.readHead();
        const headSummary = remoteHead.summary || remoteHead.commit?.summary;
        const summary = remoteHead.commitId === null
          ? { bookmarkFolders: 0, bookmarkItems: 0, tombstones: 0 }
          : headSummary;
        if (!summary) return;
        setLeafTabCloudRemoteSummary(summary);
        writeLeafTabSyncSummaryCache(leafTabCloudSummaryCacheKey, summary);
        const baseline = await new runtime.LeafTabSyncExtensionStorageBaselineStore(leafTabCloudBaselineStorageKey).load();
        const cloudIsPrimary = preferredPrimaryRemoteKind !== 'webdav';
        if (cloudIsPrimary &&
          remoteHead.commitId &&
          baseline?.commitId &&
          remoteHead.commitId !== baseline.commitId) {
          requestBackgroundLeafTabAutoSync('aira-cloud');
        }
      })().catch(() => undefined));
    }
    await Promise.all(tasks);
  }, [
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabCloudSummaryCacheKey,
    leafTabWebdavSummaryCacheKey,
    preferredPrimaryRemoteKind,
    webdavConfig,
  ]);

  useEffect(() => {
    let cancelled = false;

    void (async () => {
      const cachedWebdav = webdavConfig?.url
        ? await readCachedOrBaselineAnalysis(leafTabWebdavAnalysisCacheKey, leafTabSyncBaselineStorageKey)
        : { analysis: null, updatedAt: null };
      const cachedCloud = cloudUid
        ? await readCachedOrBaselineAnalysis(leafTabCloudAnalysisCacheKey, leafTabCloudBaselineStorageKey)
        : { analysis: null, updatedAt: null };
      const cachedLocalSummary = readLeafTabSyncSummaryCache(leafTabLocalSummaryCacheKey);
      const cachedWebdavSummary = webdavConfig?.url
        ? readLeafTabSyncSummaryCache(leafTabWebdavSummaryCacheKey)
        : null;
      const cachedCloudSummary = cloudUid
        ? readLeafTabSyncSummaryCache(leafTabCloudSummaryCacheKey)
        : null;
      if (cancelled) return;

      setLeafTabLocalBookmarkSummary(cachedLocalSummary);
      setLeafTabWebdavRemoteSummary(cachedWebdavSummary || cachedWebdav.analysis?.remoteSummary || null);
      setLeafTabCloudRemoteSummary(cachedCloudSummary || cachedCloud.analysis?.remoteSummary || null);
      setLeafTabWebdavSyncAnalysis(cachedWebdav.analysis);
      setLeafTabCloudSyncAnalysis(cachedCloud.analysis);
      setLeafTabWebdavAnalysisCheckedAt(cachedWebdav.updatedAt);
      setLeafTabCloudAnalysisCheckedAt(cachedCloud.updatedAt);
      if (leafTabSyncAnalysisRemoteKind === 'webdav') {
        setLeafTabSyncAnalysis(cachedWebdav.analysis);
      } else if (leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
        setLeafTabSyncAnalysis(cachedCloud.analysis);
      } else if (cachedWebdav.analysis) {
        setLeafTabSyncAnalysisRemoteKind('webdav');
        setLeafTabSyncAnalysis(cachedWebdav.analysis);
      } else if (cachedCloud.analysis) {
        setLeafTabSyncAnalysisRemoteKind('aira-cloud');
        setLeafTabSyncAnalysis(cachedCloud.analysis);
      }

      if (!initialLocalSummaryHydratedRef.current) {
        initialLocalSummaryHydratedRef.current = true;
        void updateCachedLocalSummaries();
      }
      const remoteSummaryHydrationKey = `${leafTabWebdavCacheIdentity}|${cloudUid}`;
      if (remoteSummaryHydratedKeyRef.current !== remoteSummaryHydrationKey) {
        remoteSummaryHydratedKeyRef.current = remoteSummaryHydrationKey;
        void refreshCachedRemoteSummariesFromHead();
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [
    cloudUid,
    leafTabCloudBaselineStorageKey,
    leafTabCloudAnalysisCacheKey,
    leafTabCloudSummaryCacheKey,
    leafTabLocalSummaryCacheKey,
    leafTabWebdavCacheIdentity,
    leafTabWebdavSummaryCacheKey,
    localVersion,
    leafTabSyncBaselineStorageKey,
    leafTabSyncAnalysisRemoteKind,
    leafTabWebdavAnalysisCacheKey,
    refreshCachedRemoteSummariesFromHead,
    readCachedOrBaselineAnalysis,
    updateCachedLocalSummaries,
    webdavConfig?.url,
  ]);

  useEffect(() => {
    const api = getBookmarksApi();
    if (!api) return undefined;

    let refreshTimer: number | undefined;
    const scheduleRefresh = () => {
      if (refreshTimer) {
        window.clearTimeout(refreshTimer);
      }
      refreshTimer = window.setTimeout(() => {
        refreshTimer = undefined;
        void updateCachedLocalSummaries();
      }, 250);
    };

    api.onCreated?.addListener?.(scheduleRefresh);
    api.onRemoved?.addListener?.(scheduleRefresh);
    api.onChanged?.addListener?.(scheduleRefresh);
    api.onMoved?.addListener?.(scheduleRefresh);
    api.onChildrenReordered?.addListener?.(scheduleRefresh);
    api.onImportEnded?.addListener?.(scheduleRefresh);

    return () => {
      if (refreshTimer) {
        window.clearTimeout(refreshTimer);
      }
      api.onCreated?.removeListener?.(scheduleRefresh);
      api.onRemoved?.removeListener?.(scheduleRefresh);
      api.onChanged?.removeListener?.(scheduleRefresh);
      api.onMoved?.removeListener?.(scheduleRefresh);
      api.onChildrenReordered?.removeListener?.(scheduleRefresh);
      api.onImportEnded?.removeListener?.(scheduleRefresh);
    };
  }, [updateCachedLocalSummaries]);

  useEffect(() => {
    void syncWebdavStorageStateToExtensionStorage();
    void syncAiraDesktopLoginProfileToExtensionStorage();
    void writeExtensionStorageRecord({
      [LEAFTAB_SYNC_DEVICE_ID_KEY]: localStorage.getItem(LEAFTAB_SYNC_DEVICE_ID_KEY) || leafTabSyncDeviceId,
      [LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY]: localStorage.getItem(LEAFTAB_PRIMARY_SYNC_REMOTE_KIND_KEY) || '',
      [AIRA_CLOUD_SYNC_ENABLED_KEY]: localStorage.getItem(AIRA_CLOUD_SYNC_ENABLED_KEY) || 'false',
      [AIRA_CLOUD_LAST_SYNC_AT_KEY]: localStorage.getItem(AIRA_CLOUD_LAST_SYNC_AT_KEY) || '',
      [AIRA_CLOUD_LAST_ERROR_AT_KEY]: localStorage.getItem(AIRA_CLOUD_LAST_ERROR_AT_KEY) || '',
      [AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY]: localStorage.getItem(AIRA_CLOUD_LAST_ERROR_MESSAGE_KEY) || '',
      webdav_last_sync_at: localStorage.getItem('webdav_last_sync_at') || '',
      webdav_last_error_at: localStorage.getItem('webdav_last_error_at') || '',
      webdav_last_error_message: localStorage.getItem('webdav_last_error_message') || '',
      [LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY]: localStorage.getItem(LEAFTAB_SYNC_LOCAL_SUMMARY_AT_KEY) || '',
    });
    void syncSharedExtensionStorageToLocalStorage().then(() => {
      setLocalVersion((value) => value + 1);
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
      void syncSharedExtensionStorageToLocalStorage().then(() => {
        refreshLocalState();
      });
    };
    window.addEventListener('webdav-config-changed', refreshLocalState);
    window.addEventListener('webdav-sync-status-changed', refreshLocalState);
    chrome.storage?.onChanged?.addListener?.(handleExtensionStorageChanged);
    return () => {
      window.removeEventListener('webdav-config-changed', refreshLocalState);
      window.removeEventListener('webdav-sync-status-changed', refreshLocalState);
      chrome.storage?.onChanged?.removeListener?.(handleExtensionStorageChanged);
    };
  }, [leafTabSyncDeviceId]);

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

      const runMode: LeafTabSyncInitialChoice | 'auto' = options?.mode || 'auto';

      let result = isCloud
        ? await runCloudSyncOnce(runMode, mergedOptions)
        : await runLeafTabSyncOnce(runMode, mergedOptions);
      if (result?.kind === 'conflict' && runMode === 'auto' && result.initialChoiceAnalysis?.requiresInitialChoice) {
        if (options?.silentSuccess && options?.allowConfigPrompt === false) {
          return null;
        }
        const choice = await requestInitialSyncChoice(createInitialChoiceAnalysisFromConflict(result));
        if (choice === null) {
          return null;
        }
        result = isCloud
          ? await runCloudSyncOnce(choice, mergedOptions)
          : await runLeafTabSyncOnce(choice, mergedOptions);
      }
      if (result) {
        if (result.kind === 'conflict') {
          if (!options?.silentSuccess) {
            toast.error(result.summaryText || '检测到同步冲突，请先处理');
          }
          return result;
        }
        setLeafTabSyncAnalysisRemoteKind(remoteKind);
        const syncedAnalysis = createAnalysisFromSyncedSnapshot(result);
        setLeafTabLocalBookmarkSummary(syncedAnalysis.localSummary);
        writeLeafTabSyncSummaryCache(leafTabLocalSummaryCacheKey, syncedAnalysis.localSummary);
        if (isCloud) {
          markCloudSyncSuccess();
          setLeafTabCloudSyncAnalysis(syncedAnalysis);
          setLeafTabCloudRemoteSummary(syncedAnalysis.remoteSummary);
          writeLeafTabSyncSummaryCache(leafTabCloudSummaryCacheKey, syncedAnalysis.remoteSummary);
          setLeafTabCloudAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabCloudAnalysisCacheKey, syncedAnalysis));
        } else {
          markWebdavSyncSuccess();
          setLeafTabWebdavSyncAnalysis(syncedAnalysis);
          setLeafTabWebdavRemoteSummary(syncedAnalysis.remoteSummary);
          writeLeafTabSyncSummaryCache(leafTabWebdavSummaryCacheKey, syncedAnalysis.remoteSummary);
          setLeafTabWebdavAnalysisCheckedAt(writeLeafTabSyncAnalysisCache(leafTabWebdavAnalysisCacheKey, syncedAnalysis));
        }
        updateLeafTabRemoteAutoSyncDiagnostic({
          hasChanges: false,
          provider: remoteKind,
          baselineCommitId: result.remoteCommitId || null,
          remoteCommitId: result.remoteCommitId || null,
          remoteFolders: syncedAnalysis.remoteSummary.bookmarkFolders,
          remoteItems: syncedAnalysis.remoteSummary.bookmarkItems,
          remoteTombstones: syncedAnalysis.remoteSummary.tombstones,
        }, {
          lastSyncAttempted: options?.silentSuccess === true,
          lastSyncSucceeded: options?.silentSuccess === true ? true : null,
          lastError: '',
        });
        markLocalSummaryCheckedAt();
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
      updateLeafTabRemoteAutoSyncDiagnostic({
        hasChanges: false,
        provider: remoteKind,
        error: formatLeafTabSyncErrorMessage(error, remoteKind),
      }, {
        lastSyncAttempted: options?.silentSuccess === true,
        lastSyncSucceeded: options?.silentSuccess === true ? false : null,
        lastError: formatLeafTabSyncErrorMessage(error, remoteKind),
      });
      if (isCloud) {
        markCloudSyncError(error);
      } else {
        markWebdavSyncError(error);
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
    requestInitialSyncChoice,
    runCloudSyncOnce,
    runLeafTabSyncOnce,
    beginSyncProgress,
    updateSyncProgress,
    finishSyncProgress,
    failSyncProgress,
    leafTabCloudAnalysisCacheKey,
    leafTabCloudSummaryCacheKey,
    leafTabLocalSummaryCacheKey,
    leafTabWebdavAnalysisCacheKey,
    leafTabWebdavSummaryCacheKey,
    updateLeafTabRemoteAutoSyncDiagnostic,
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

  const buildSnapshotForRemoteKind = useCallback(async (
    remoteKind: LeafTabSyncRemoteKind,
    bookmarkTree: LeafTabBookmarkTreeDraft,
  ) => buildBookmarkSnapshotFromTree(
    remoteKind === 'aira-cloud' ? leafTabCloudBaselineStorageKey : leafTabSyncBaselineStorageKey,
    bookmarkTree,
  ), [
    buildBookmarkSnapshotFromTree,
    leafTabCloudBaselineStorageKey,
    leafTabSyncBaselineStorageKey,
  ]);

  const handleActiveSyncNowFromCenter = useCallback(async (options?: {
    auto?: boolean;
    trigger?: LeafTabRemoteAutoSyncProbeResult;
  }) => {
    const isAuto = options?.auto === true;
    const triggerProvider = options?.trigger?.hasChanges ? options.trigger.provider : undefined;
    const webdavEnabledNow = isWebdavSyncEnabledFromStorage();
    const cloudEnabledNow = (localStorage.getItem(AIRA_CLOUD_SYNC_ENABLED_KEY) ?? 'false') === 'true';
    const route = resolveLeafTabSyncRoute({
      cloudEnabled: cloudEnabledNow,
      cloudAvailable: Boolean(cloudUid),
      webdavEnabled: webdavEnabledNow,
      webdavAvailable: Boolean(webdavConfig?.url),
      preferredPrimaryRemoteKind: preferredPrimaryRemoteKind ?? undefined,
      triggerProvider,
    });

    if (isDualLeafTabSyncRoute(route)) {
      setWebdavSyncRunActive(true);
      if (!isAuto) {
        beginSyncProgress('dual', '正在同步云端和 WebDAV 书签');
      }
      try {
        const granted = await ensureExtensionPermission('bookmarks', { requestIfNeeded: true }).catch(() => false);
        if (!granted) {
          throw new Error('未授予书签权限，无法同步书签');
        }
        const hasPendingLocalChanges = hasPendingLeafTabLocalBookmarkChanges();
        const bookmarkTree = shouldBuildLeafTabPrimaryLocalSnapshot(hasPendingLocalChanges)
          ? await captureBookmarkTreeDraft()
          : null;
        const primarySnapshot = bookmarkTree
          ? await buildSnapshotForRemoteKind(route.primaryRemoteKind, bookmarkTree)
          : null;
        const primaryResult = await handleLeafTabSync({
          remoteKind: route.primaryRemoteKind,
          localSnapshotOverride: primarySnapshot || undefined,
          allowConfigPrompt: isAuto ? false : undefined,
          requestBookmarkPermission: false,
          silentSuccess: true,
          showProgressIndicator: false,
          onProgress: isAuto
            ? undefined
            : (progress) => updateSyncProgress(
              route.primaryRemoteKind,
              progress,
              Math.min(50, progress.progress * 0.5),
            ),
        });
        if (!primaryResult) {
          if (!isAuto) {
            finishSyncProgress(`${resolveRemoteProgressName(route.primaryRemoteKind)}同步未完成，请稍后重试`);
          }
          return false;
        }

        const secondaryPlan = createLeafTabDualSecondarySyncPlan(route, primaryResult);
        if (!isAuto) {
          updateSyncProgress('dual', {
            stage: 'reading-state',
            progress: 52,
            message: resolveDualProgressMessage(route.secondaryRemoteKind),
          }, 52);
        }
        const secondaryWebdavTarget = route.secondaryRemoteKind === 'webdav'
          ? createWebdavBackupTargetFromConfig(webdavConfig)
          : null;
        const secondaryCooldownReason = secondaryWebdavTarget
          ? await readWebdavBackupCooldownResult(secondaryWebdavTarget)
          : null;
        if (secondaryCooldownReason) {
          updateLeafTabRemoteAutoSyncDiagnostic({
            hasChanges: false,
            provider: route.secondaryRemoteKind,
            error: secondaryCooldownReason,
          }, {
            lastSyncAttempted: isAuto,
            lastSyncSucceeded: isAuto ? true : null,
            lastError: secondaryCooldownReason,
          });
          if (!isAuto) {
            finishSyncProgress(`${primaryResult.summaryText || '主同步已完成'}；${secondaryCooldownReason}`);
          }
          return true;
        }
        let secondaryResult: LeafTabSyncEngineResult | null = null;
        try {
          const secondaryTask = handleLeafTabSync({
            remoteKind: route.secondaryRemoteKind,
            localSnapshotOverride: secondaryPlan.snapshot,
            mode: secondaryPlan.mode,
            allowConfigPrompt: isAuto ? false : undefined,
            requestBookmarkPermission: false,
            silentSuccess: true,
            showProgressIndicator: false,
            webdavRequestTimeoutMs: route.secondaryRemoteKind === 'webdav'
              ? WEBDAV_BACKUP_REQUEST_TIMEOUT_MS
              : undefined,
            onProgress: isAuto
              ? undefined
              : (progress) => updateSyncProgress(
                route.secondaryRemoteKind,
                progress,
                50 + (progress.progress * 0.5),
              ),
          });
          secondaryResult = route.secondaryRemoteKind === 'webdav'
            ? await withWebdavBackupTimeout(
              secondaryTask,
              WEBDAV_BACKUP_TOTAL_TIMEOUT_MS,
              'WebDAV 备份连接超时，已跳过本次备份，不影响主同步。',
            )
            : await secondaryTask;
        } catch (error) {
          secondaryResult = null;
          if (route.secondaryRemoteKind === 'aira-cloud') {
            markCloudSyncError(error);
          } else {
            markWebdavSyncError(error);
          }
          if (secondaryWebdavTarget) {
            await recordWebdavBackupFailureCooldown(secondaryWebdavTarget, error);
          }
          if (!isAuto) {
            finishSyncProgress(`${primaryResult.summaryText || '主同步已完成'}；${resolveRemoteProgressName(route.secondaryRemoteKind)}备份失败，可稍后重试`);
            toast.error(`${resolveRemoteProgressName(route.secondaryRemoteKind)}备份失败，主同步已完成`);
          }
          return true;
        }
        if (!secondaryResult) {
          if (route.secondaryRemoteKind === 'aira-cloud') {
            markCloudSyncError(new Error('备份未完成'));
          } else {
            markWebdavSyncError(new Error('备份未完成'));
          }
          if (secondaryWebdavTarget) {
            await recordWebdavBackupFailureCooldown(secondaryWebdavTarget, new Error('备份未完成'));
          }
          if (!isAuto) {
            finishSyncProgress(`${primaryResult.summaryText || '主同步已完成'}；${resolveRemoteProgressName(route.secondaryRemoteKind)}备份未完成，可稍后重试`);
          }
          return true;
        }
        if (secondaryResult.kind === 'conflict') {
          if (route.secondaryRemoteKind === 'aira-cloud') {
            markCloudSyncError(new Error('备份源需要处理冲突'));
          } else {
            markWebdavSyncError(new Error('备份源需要处理冲突'));
          }
          if (secondaryWebdavTarget) {
            await recordWebdavBackupFailureCooldown(secondaryWebdavTarget, new Error('备份源需要处理冲突'));
          }
          if (!isAuto) {
            finishSyncProgress(`${primaryResult.summaryText || '主同步已完成'}；${resolveRemoteProgressName(route.secondaryRemoteKind)}备份需要处理冲突`);
            toast.error(`${resolveRemoteProgressName(route.secondaryRemoteKind)}备份需要处理冲突，主同步已完成`);
          }
          return true;
        }
        if (secondaryWebdavTarget) {
          await clearWebdavBackupFailureCooldown(secondaryWebdavTarget);
        }
        if (!isAuto) {
          finishSyncProgress(secondaryResult.summaryText || primaryResult.summaryText || '云端和 WebDAV 已同步完成');
          toast.success('书签同步完成');
        }
        return true;
      } catch (error) {
        markCloudSyncError(error);
        markWebdavSyncError(error);
        if (!isAuto) {
          failSyncProgress(error);
          toast.error(formatLeafTabSyncErrorMessage(error));
        }
        return false;
      } finally {
        setWebdavSyncRunActive(false);
      }
    }

    if (route.kind === 'single') {
      return Boolean(await handleLeafTabSync({
        remoteKind: route.remoteKind,
        allowConfigPrompt: isAuto ? false : undefined,
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: !isAuto,
      }));
    }

    if (isAuto) {
      return false;
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
    buildSnapshotForRemoteKind,
    captureBookmarkTreeDraft,
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

  const handleLeafTabAutoSync = useCallback(async (trigger?: LeafTabRemoteAutoSyncProbeResult) => {
    return handleActiveSyncNowFromCenter({ auto: true, trigger });
  }, [handleActiveSyncNowFromCenter]);

  const leafTabWebdavConfigured = hasWebdavUrlConfiguredFromStorage();
  const leafTabWebdavEnabled = isWebdavSyncEnabledFromStorage();

  useEffect(() => {
    if (webdavConfig?.url) return;
    if (leafTabSyncAnalysisRemoteKind === 'webdav') {
      setLeafTabSyncAnalysis(null);
      setLeafTabSyncAnalysisRemoteKind(null);
    }
    setLeafTabWebdavSyncAnalysis(null);
    setLeafTabWebdavRemoteSummary(null);
    setLeafTabWebdavAnalysisCheckedAt(null);
  }, [leafTabSyncAnalysisRemoteKind, webdavConfig?.url]);

  useEffect(() => {
    if (cloudUid) return;
    if (leafTabSyncAnalysisRemoteKind === 'aira-cloud') {
      setLeafTabSyncAnalysis(null);
      setLeafTabSyncAnalysisRemoteKind(null);
    }
    setLeafTabCloudSyncAnalysis(null);
    setLeafTabCloudRemoteSummary(null);
    setLeafTabCloudAnalysisCheckedAt(null);
  }, [cloudUid, leafTabSyncAnalysisRemoteKind]);

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
    leafTabLocalBookmarkSummary,
    leafTabWebdavRemoteSummary,
    leafTabCloudRemoteSummary,
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
    leafTabWebdavAnalysisCheckedAt: formatLeafTabSyncCacheTimestamp(leafTabWebdavAnalysisCheckedAt),
    leafTabWebdavNextSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(WEBDAV_STORAGE_KEYS.nextSyncAt)),
    leafTabBookmarkSyncScopeLabel: '书签栏 / 其他书签',
    leafTabLocalSummaryCheckedAt: formatLeafTabSyncCacheTimestamp(readLocalSummaryCheckedAt()),
    leafTabCloudLoggedIn: Boolean(cloudUid),
    leafTabCloudSyncEnabled: cloudSyncEnabled,
    leafTabCloudLastSyncLabel: formatLiteSyncTimestamp(localStorage.getItem(AIRA_CLOUD_LAST_SYNC_AT_KEY)),
    leafTabCloudAnalysisCheckedAt: formatLeafTabSyncCacheTimestamp(leafTabCloudAnalysisCheckedAt),
    leafTabCloudUserId: cloudUid,
    leafTabPrimaryRemoteKind: preferredPrimaryRemoteKind,
    leafTabRemoteAutoSyncDiagnostic,
  }), [
    leafTabSyncLastResult,
    leafTabInitialSyncChoiceRequest,
    leafTabSyncAnalysis,
    leafTabSyncAnalysisRemoteKind,
    leafTabLocalBookmarkSummary,
    leafTabWebdavRemoteSummary,
    leafTabCloudRemoteSummary,
    leafTabWebdavSyncAnalysis,
    leafTabCloudSyncAnalysis,
    leafTabWebdavAnalysisCheckedAt,
    leafTabCloudAnalysisCheckedAt,
    leafTabSyncProgress,
    leafTabSyncState,
    webdavSyncRunActive,
    leafTabWebdavConfigured,
    leafTabWebdavEnabled,
    leafTabWebdavProfileLabel,
    cloudSyncEnabled,
    cloudUid,
    preferredPrimaryRemoteKind,
    leafTabRemoteAutoSyncDiagnostic,
    webdavConfig,
    localVersion,
    readLocalSummaryCheckedAt,
  ]);

  const actions = useMemo<LeafTabSyncActions>(() => ({
    handleLeafTabSync,
    handleEnableWebdavSync: async () => {
      const result = await handleLeafTabSync({
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      });
      if (result && !cloudSyncEnabled) {
        setPrimaryRemoteKindInStorage('webdav');
      }
    },
    handleDisableWebdavSync: async () => {
      setWebdavSyncEnabledInStorage(false);
      if (preferredPrimaryRemoteKind === 'webdav') {
        setPrimaryRemoteKindInStorage(cloudSyncEnabled ? 'aira-cloud' : null);
      }
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
    handleEnableCloudSync: async (options?: { confirmedPrimarySwitch?: boolean }) => {
      const webdavEnabledNow = isWebdavSyncEnabledFromStorage();
      if (webdavEnabledNow && !cloudSyncEnabled && options?.confirmedPrimarySwitch !== true) {
        toast.error('开启云同步前请确认主同步源切换');
        return false;
      }
      const result = await handleLeafTabSync({
        remoteKind: 'aira-cloud',
        enableAfterSuccess: true,
        requestBookmarkPermission: true,
        showProgressIndicator: true,
      });
      if (result) {
        setPrimaryRemoteKindInStorage('aira-cloud');
      }
      return Boolean(result);
    },
    handleDisableCloudSync: async () => {
      setCloudSyncEnabledInStorage(false);
      if (preferredPrimaryRemoteKind === 'aira-cloud') {
        setPrimaryRemoteKindInStorage(leafTabWebdavEnabled ? 'webdav' : null);
      }
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
    handleSetPrimaryRemoteKind: async (remoteKind, strategy) => {
      if (remoteKind === 'aira-cloud' && (!cloudSyncEnabled || !cloudUid)) {
        toast.error('请先启用 Aira 云同步');
        return false;
      }
      if (remoteKind === 'webdav' && (!leafTabWebdavEnabled || !webdavConfig?.url)) {
        toast.error('请先启用 WebDAV 同步');
        return false;
      }
      const result = await handleLeafTabSync({
        remoteKind,
        mode: resolvePrimarySwitchMode(strategy),
        allowConfigPrompt: false,
        requestBookmarkPermission: true,
        silentSuccess: true,
        showProgressIndicator: true,
      });
      if (!result || result.kind === 'conflict') {
        toast.error('主同步源切换未完成，请先处理同步冲突或稍后重试');
        return false;
      }
      setPrimaryRemoteKindInStorage(remoteKind);
      toast.success(remoteKind === 'aira-cloud' ? '已切换为云同步主同步源' : '已切换为 WebDAV 主同步源');
      return true;
    },
    resolveWebdavConflict: async () => {
      await handleLeafTabSync({
        requestBookmarkPermission: true,
      });
    },
    resolveLeafTabInitialSyncChoice,
  }), [
    cloudSyncEnabled,
    cloudUid,
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
    preferredPrimaryRemoteKind,
    setLeafTabSyncDialogOpen,
    setCloudSyncEnabledInStorage,
    setPrimaryRemoteKindInStorage,
    setWebdavSyncEnabledInStorage,
    leafTabWebdavEnabled,
    webdavConfig?.url,
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
