import { useCallback, useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { toast } from '@/components/ui/sonner';
import type { LeafTabRemoteAutoSyncProbeResult } from '@/features/sync/app/LeafTabSyncContracts';
import { getBookmarksApi } from '@/platform/runtime';
import { getAlignedJitteredNextAt, resolveInitialAlignedJitteredTargetAt } from '@/sync/schedule';
import { markLeafTabLocalBookmarkChanged } from '@/sync/leaftab/localChangeTracker';
import {
  normalizeLeafTabAutoSyncAttemptResult,
  reduceLeafTabAutoSyncRetry,
} from '@/sync/leaftab/autoSyncStateMachine';
import {
  readWebdavConfigFromStorage,
  readWebdavStorageStateFromStorage,
  WEBDAV_DEFAULT_SYNC_INTERVAL_MINUTES,
  WEBDAV_STORAGE_KEYS,
} from '@/utils/webdavConfig';

const AUTO_SYNC_BOOKMARK_CHANGE_DEBOUNCE_MS = 7 * 1000;
const AUTO_SYNC_REMOTE_PROBE_STARTUP_DELAY_MS = 3 * 1000;
const AUTO_SYNC_BUSY_RETRY_DELAY_MS = 30 * 1000;
const AUTO_SYNC_FAILURE_RETRY_BASE_DELAY_MS = 60 * 1000;
const AUTO_SYNC_FAILURE_RETRY_MAX_DELAY_MS = 10 * 60 * 1000;
const AUTO_SYNC_REMOTE_PROBE_INTERVAL_MS = 60 * 1000;
const AUTO_SYNC_REMOTE_PROBE_MIN_INTERVAL_MS = 60 * 1000;
const AUTO_SYNC_LEASE_KEY = 'webdav_auto_sync_lease_v1';
const AUTO_SYNC_LEASE_TTL_MS = 3 * 60 * 1000;
const AUTO_SYNC_LEASE_RENEW_MS = 30 * 1000;

type AutoSyncLease = {
  ownerId: string;
  expiresAt: number;
};

function createAutoSyncOwnerId() {
  try {
    if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
      return crypto.randomUUID();
    }
  } catch {}
  return `webdav_auto_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function readAutoSyncLease(): AutoSyncLease | null {
  try {
    const raw = localStorage.getItem(AUTO_SYNC_LEASE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<AutoSyncLease>;
    if (!parsed.ownerId || typeof parsed.expiresAt !== 'number') return null;
    return {
      ownerId: parsed.ownerId,
      expiresAt: parsed.expiresAt,
    };
  } catch {
    return null;
  }
}

function writeAutoSyncLease(ownerId: string, nowMs = Date.now()) {
  try {
    localStorage.setItem(AUTO_SYNC_LEASE_KEY, JSON.stringify({
      ownerId,
      expiresAt: nowMs + AUTO_SYNC_LEASE_TTL_MS,
    } satisfies AutoSyncLease));
    const confirmed = readAutoSyncLease();
    return confirmed?.ownerId === ownerId;
  } catch {
    return true;
  }
}

function tryAcquireAutoSyncLease(ownerId: string, nowMs = Date.now()) {
  const current = readAutoSyncLease();
  if (current && current.ownerId !== ownerId && current.expiresAt > nowMs) {
    return false;
  }
  return writeAutoSyncLease(ownerId, nowMs);
}

function releaseAutoSyncLease(ownerId: string) {
  try {
    const current = readAutoSyncLease();
    if (current?.ownerId === ownerId) {
      localStorage.removeItem(AUTO_SYNC_LEASE_KEY);
    }
  } catch {}
}

function getFailureRetryDelay(failureCount: number) {
  const normalizedFailureCount = Math.max(1, Math.min(8, Math.floor(failureCount)));
  return Math.min(
    AUTO_SYNC_FAILURE_RETRY_MAX_DELAY_MS,
    AUTO_SYNC_FAILURE_RETRY_BASE_DELAY_MS * (2 ** (normalizedFailureCount - 1)),
  );
}

type UseLeafTabWebdavAutoSyncParams = {
  conflictModalOpen: boolean;
  isDragging: boolean;
  syncing: boolean;
  onSync: (trigger?: LeafTabRemoteAutoSyncProbeResult) => Promise<boolean>;
  onRemoteProbe?: () => Promise<LeafTabRemoteAutoSyncProbeResult>;
  autoSyncEnabled?: boolean;
  scheduleSyncEnabled?: boolean;
};

export function useLeafTabWebdavAutoSync({
  conflictModalOpen,
  isDragging,
  syncing,
  onSync,
  onRemoteProbe,
  autoSyncEnabled,
  scheduleSyncEnabled,
}: UseLeafTabWebdavAutoSyncParams) {
  const { t } = useTranslation();
  const timerRef = useRef<number | null>(null);
  const bookmarkChangeTimerRef = useRef<number | null>(null);
  const leaseRenewTimerRef = useRef<number | null>(null);
  const inFlightRef = useRef(false);
  const remoteProbeRunningRef = useRef(false);
  const lastRemoteProbeAtRef = useRef(0);
  const ownerIdRef = useRef(createAutoSyncOwnerId());
  const failureCountRef = useRef(0);
  const latestFlagsRef = useRef({
    conflictModalOpen,
    isDragging,
    syncing,
  });
  const latestOnSyncRef = useRef(onSync);
  const latestOnRemoteProbeRef = useRef(onRemoteProbe);
  const latestTRef = useRef(t);
  const [configVersion, setConfigVersion] = useState(0);

  useEffect(() => {
    latestFlagsRef.current = {
      conflictModalOpen,
      isDragging,
      syncing,
    };
  }, [conflictModalOpen, isDragging, syncing]);

  useEffect(() => {
    latestOnSyncRef.current = onSync;
  }, [onSync]);

  useEffect(() => {
    latestOnRemoteProbeRef.current = onRemoteProbe;
  }, [onRemoteProbe]);

  useEffect(() => {
    latestTRef.current = t;
  }, [t]);

  const emitStatusChanged = useCallback(() => {
    window.dispatchEvent(new CustomEvent('webdav-sync-status-changed'));
  }, []);

  const isAutoSyncEnabled = useCallback(() => {
    if (typeof autoSyncEnabled === 'boolean') return autoSyncEnabled;
    return Boolean(readWebdavConfigFromStorage()?.syncOptions?.enabled);
  }, [autoSyncEnabled]);

  const isScheduledSyncEnabled = useCallback(() => {
    if (!isAutoSyncEnabled()) return false;
    if (typeof scheduleSyncEnabled === 'boolean') return scheduleSyncEnabled;
    return Boolean(readWebdavConfigFromStorage()?.syncOptions?.syncBySchedule);
  }, [isAutoSyncEnabled, scheduleSyncEnabled]);

  const clearLeaseRenewTimer = useCallback(() => {
    if (leaseRenewTimerRef.current !== null) {
      window.clearInterval(leaseRenewTimerRef.current);
      leaseRenewTimerRef.current = null;
    }
  }, []);

  const startLeaseRenewal = useCallback(() => {
    clearLeaseRenewTimer();
    leaseRenewTimerRef.current = window.setInterval(() => {
      writeAutoSyncLease(ownerIdRef.current);
    }, AUTO_SYNC_LEASE_RENEW_MS);
  }, [clearLeaseRenewTimer]);

  const getIntervalMinutes = useCallback(() => {
    const config = readWebdavConfigFromStorage();
    const raw = Number(config?.syncOptions?.syncIntervalMinutes ?? WEBDAV_DEFAULT_SYNC_INTERVAL_MINUTES);
    return Math.max(1, Number.isFinite(raw) ? raw : WEBDAV_DEFAULT_SYNC_INTERVAL_MINUTES);
  }, []);

  const getAutoSyncSuccessText = useCallback(() => {
    return latestTRef.current('popup.dashboard.autoSyncSuccess', {
      defaultValue: '书签已自动同步',
    });
  }, []);

  const performAutoSync = useCallback(async (trigger?: LeafTabRemoteAutoSyncProbeResult) => {
    if (!isAutoSyncEnabled()) return null;
    const latestFlags = latestFlagsRef.current;
    const now = Date.now();
    if (
      inFlightRef.current
      || latestFlags.syncing
      || latestFlags.conflictModalOpen
      || latestFlags.isDragging
      || document.hidden
      || !navigator.onLine
    ) {
      return null;
    }

    if (!tryAcquireAutoSyncLease(ownerIdRef.current, now)) {
      return null;
    }

    inFlightRef.current = true;
    startLeaseRenewal();
    try {
      const ok = await latestOnSyncRef.current(trigger);
      if (ok && readWebdavStorageStateFromStorage().autoSyncToastEnabled) {
        toast.success(getAutoSyncSuccessText());
      }
      return ok;
    } catch (error) {
      console.error('[LeafTab][auto sync]', error);
      return false;
    } finally {
      inFlightRef.current = false;
      clearLeaseRenewTimer();
      releaseAutoSyncLease(ownerIdRef.current);
    }
  }, [clearLeaseRenewTimer, getAutoSyncSuccessText, isAutoSyncEnabled, startLeaseRenewal]);

  const probeRemoteChangesAndSync = useCallback(async () => {
    if (!isAutoSyncEnabled() || remoteProbeRunningRef.current || inFlightRef.current) return;
    const latestFlags = latestFlagsRef.current;
    if (
      latestFlags.syncing ||
      latestFlags.conflictModalOpen ||
      latestFlags.isDragging ||
      document.hidden ||
      !navigator.onLine
    ) {
      return;
    }
    const now = Date.now();
    if (now - lastRemoteProbeAtRef.current < AUTO_SYNC_REMOTE_PROBE_MIN_INTERVAL_MS) {
      return;
    }
    const probe = latestOnRemoteProbeRef.current;
    if (!probe) return;

    remoteProbeRunningRef.current = true;
    lastRemoteProbeAtRef.current = now;
    try {
      const result = await probe();
      if (result.hasChanges) {
        await performAutoSync(result);
      }
    } catch (error) {
      console.error('[LeafTab][remote auto sync probe]', error);
    } finally {
      remoteProbeRunningRef.current = false;
    }
  }, [isAutoSyncEnabled, performAutoSync]);

  useEffect(() => {
    const handleConfigChanged = () => {
      setConfigVersion((value) => value + 1);
    };
    window.addEventListener('webdav-config-changed', handleConfigChanged);
    window.addEventListener('online', handleConfigChanged);
    document.addEventListener('visibilitychange', handleConfigChanged);
    return () => {
      window.removeEventListener('webdav-config-changed', handleConfigChanged);
      window.removeEventListener('online', handleConfigChanged);
      document.removeEventListener('visibilitychange', handleConfigChanged);
    };
  }, []);

  useEffect(() => {
    let disposed = false;
    if (!isScheduledSyncEnabled()) {
      if (timerRef.current) window.clearTimeout(timerRef.current);
      timerRef.current = null;
      localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
      emitStatusChanged();
      return;
    }

    if (typeof document !== 'undefined' && document.hidden) {
      if (timerRef.current) window.clearTimeout(timerRef.current);
      timerRef.current = null;
      clearLeaseRenewTimer();
      releaseAutoSyncLease(ownerIdRef.current);
      return () => {
        disposed = true;
      };
    }

    const scheduleNext = (targetMs: number, options?: { publishStatus?: boolean }) => {
      if (disposed) return;
      if (timerRef.current) {
        window.clearTimeout(timerRef.current);
      }
      const nextMs = Math.max(Date.now() + 200, targetMs);
      if (options?.publishStatus !== false) {
        localStorage.setItem(WEBDAV_STORAGE_KEYS.nextSyncAt, new Date(nextMs).toISOString());
        emitStatusChanged();
      }
      const delay = Math.min(nextMs - Date.now(), 2_147_483_647);
      timerRef.current = window.setTimeout(async () => {
        if (disposed) return;
        if (!isScheduledSyncEnabled()) {
          if (timerRef.current) window.clearTimeout(timerRef.current);
          timerRef.current = null;
          localStorage.removeItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
          emitStatusChanged();
          return;
        }

        const now = Date.now();
        const retryAfterBusyAt = now + AUTO_SYNC_BUSY_RETRY_DELAY_MS;
        const attemptResult = normalizeLeafTabAutoSyncAttemptResult(await performAutoSync());
        const decision = reduceLeafTabAutoSyncRetry(attemptResult, failureCountRef.current);
        const retryAfterFailureAt = now + getFailureRetryDelay(decision.nextFailureCount);
        if (disposed) return;
        failureCountRef.current = decision.nextFailureCount;
        if (decision.kind === 'retry-busy') {
          scheduleNext(retryAfterBusyAt, { publishStatus: false });
          return;
        }
        if (decision.kind === 'idle') {
          scheduleNext(getAlignedJitteredNextAt(getIntervalMinutes()));
          return;
        }

        scheduleNext(retryAfterFailureAt);
      }, delay);
    };

    const persistedNextAtIso = localStorage.getItem(WEBDAV_STORAGE_KEYS.nextSyncAt);
    const persistedNextAtMs = persistedNextAtIso ? new Date(persistedNextAtIso).getTime() : Number.NaN;
    const initialTarget = resolveInitialAlignedJitteredTargetAt({
      intervalMinutes: getIntervalMinutes(),
      persistedNextAtIso: Number.isFinite(persistedNextAtMs) && persistedNextAtMs > Date.now()
        ? persistedNextAtIso
        : null,
    });

    scheduleNext(initialTarget);

    return () => {
      disposed = true;
      if (timerRef.current) window.clearTimeout(timerRef.current);
      timerRef.current = null;
      clearLeaseRenewTimer();
      releaseAutoSyncLease(ownerIdRef.current);
    };
  }, [
    clearLeaseRenewTimer,
    configVersion,
    emitStatusChanged,
    getIntervalMinutes,
    isScheduledSyncEnabled,
    performAutoSync,
  ]);

  useEffect(() => {
    const api = getBookmarksApi();
    if (!api || !isAutoSyncEnabled()) return undefined;
    let disposed = false;

    const clearBookmarkChangeTimer = () => {
      if (bookmarkChangeTimerRef.current !== null) {
        window.clearTimeout(bookmarkChangeTimerRef.current);
        bookmarkChangeTimerRef.current = null;
      }
    };

    const scheduleBookmarkChangeAutoSync = (delayMs = AUTO_SYNC_BOOKMARK_CHANGE_DEBOUNCE_MS) => {
      if (disposed || !isAutoSyncEnabled() || inFlightRef.current || latestFlagsRef.current.syncing) return;
      clearBookmarkChangeTimer();
      bookmarkChangeTimerRef.current = window.setTimeout(async () => {
        bookmarkChangeTimerRef.current = null;
        if (disposed || !isAutoSyncEnabled()) return;
        const attemptResult = normalizeLeafTabAutoSyncAttemptResult(await performAutoSync());
        const decision = reduceLeafTabAutoSyncRetry(attemptResult, failureCountRef.current);
        if (disposed) return;
        failureCountRef.current = decision.nextFailureCount;
        if (decision.kind === 'retry-busy') {
          scheduleBookmarkChangeAutoSync(AUTO_SYNC_BUSY_RETRY_DELAY_MS);
          return;
        }
        if (decision.kind === 'idle') {
          return;
        }
        scheduleBookmarkChangeAutoSync(getFailureRetryDelay(decision.nextFailureCount));
      }, delayMs);
    };

    const handleBookmarkChanged = () => {
      if (!markLeafTabLocalBookmarkChanged()) return;
      scheduleBookmarkChangeAutoSync();
    };

    api.onCreated?.addListener?.(handleBookmarkChanged);
    api.onRemoved?.addListener?.(handleBookmarkChanged);
    api.onChanged?.addListener?.(handleBookmarkChanged);
    api.onMoved?.addListener?.(handleBookmarkChanged);
    api.onChildrenReordered?.addListener?.(handleBookmarkChanged);
    api.onImportEnded?.addListener?.(handleBookmarkChanged);

    return () => {
      disposed = true;
      clearBookmarkChangeTimer();
      api.onCreated?.removeListener?.(handleBookmarkChanged);
      api.onRemoved?.removeListener?.(handleBookmarkChanged);
      api.onChanged?.removeListener?.(handleBookmarkChanged);
      api.onMoved?.removeListener?.(handleBookmarkChanged);
      api.onChildrenReordered?.removeListener?.(handleBookmarkChanged);
      api.onImportEnded?.removeListener?.(handleBookmarkChanged);
    };
  }, [configVersion, isAutoSyncEnabled, performAutoSync]);

  useEffect(() => {
    if (!isAutoSyncEnabled() || !latestOnRemoteProbeRef.current) return undefined;
    let disposed = false;
    const timer = window.setTimeout(() => {
      if (!disposed) {
        void probeRemoteChangesAndSync();
      }
    }, AUTO_SYNC_REMOTE_PROBE_STARTUP_DELAY_MS);
    let interval: number | null = null;

    const clearRemoteProbeInterval = () => {
      if (interval !== null) {
        window.clearInterval(interval);
        interval = null;
      }
    };

    const ensureRemoteProbeInterval = () => {
      clearRemoteProbeInterval();
      if (document.hidden) return;
      interval = window.setInterval(() => {
        if (!disposed && !document.hidden) {
          void probeRemoteChangesAndSync();
        }
      }, AUTO_SYNC_REMOTE_PROBE_INTERVAL_MS);
    };

    const handleVisibilityChanged = () => {
      if (!document.hidden) {
        ensureRemoteProbeInterval();
        void probeRemoteChangesAndSync();
      } else {
        clearRemoteProbeInterval();
      }
    };

    ensureRemoteProbeInterval();
    window.addEventListener('online', probeRemoteChangesAndSync);
    document.addEventListener('visibilitychange', handleVisibilityChanged);
    return () => {
      disposed = true;
      window.clearTimeout(timer);
      clearRemoteProbeInterval();
      window.removeEventListener('online', probeRemoteChangesAndSync);
      document.removeEventListener('visibilitychange', handleVisibilityChanged);
    };
  }, [configVersion, isAutoSyncEnabled, probeRemoteChangesAndSync]);
}
