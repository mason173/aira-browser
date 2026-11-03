import {
  isAiraDesktopCredentialRejection,
  type AiraDesktopAuthorizedSession,
} from '@/features/desktop-connection/AiraDesktopConnectionModule';
import {
  readAiraDesktopAuthorizedSession,
  recordAiraDesktopConnectionFailure,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  readAiraDesktopConnectionProfile,
  refreshAiraDesktopConnectionProfileMembership,
  resolveAiraDesktopProCapability,
  shouldRefreshAiraDesktopConnectionMembership,
  type AiraDesktopProCapabilityStatus,
} from '@/features/desktop-connection/desktopConnectionProfile';
import { writeExtensionStorageRecord } from '@/platform/extensionStorage';
import { readExtensionStorageRecord } from '@/platform/extensionStorage';
import { HistorySyncModule } from './HistorySyncModule';
import { HISTORY_SYNC_MAX_VISITS } from './HistorySyncModels';
import { HistorySurfaceTimeline, nativeHistoryUrlForVisitId } from '@/features/history-surface/HistorySurfaceTimeline';
import { callBrowserHistoryApi } from '@/platform/browserHistoryApi';
import { AiraCloudHistoryRemoteStore } from './AiraCloudHistoryRemoteStore';
import {
  PERSONAL_SERVER_CONNECTION_STORAGE_KEY,
  personalServerAccountScope,
  readPersonalServerConnection,
} from '@/features/personal-server/PersonalServerConnection';
import {
  HISTORY_SYNC_DOMAIN_ENABLED_KEY,
  LEAFTAB_SELECTED_SYNC_SOURCE_KEY,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import { readHistorySyncDomainEnabled } from '@/features/sync/app/syncDomainPreferences';
import { parseLeafTabSyncRemoteKind } from '@/sync/leaftab/source';
import {
  HISTORY_MESSAGE_TYPE,
  HISTORY_REVISION_STORAGE_KEY,
  type HistoryCapabilityStatus,
  type HistoryRuntimeMessage,
  type HistoryRuntimeResponse,
} from './historyMessages';

const LOCAL_SYNC_ALARM_NAME = 'aira.history.local-sync';
const PERIODIC_SYNC_ALARM_NAME = 'aira.history.periodic-sync';
const LOCAL_CHANGE_DELAY_MINUTES = 0.1;
const PERIODIC_SYNC_INTERVAL_MINUTES = 3;
const RETRY_DELAY_MINUTES = 1;

export type HistoryBackgroundSyncRuntime = {
  initialize(): void;
  handleAlarm(alarmName: string): boolean;
  notifyStartup(): void;
  notifyStorageChanged(changes: Record<string, unknown>, areaName: string): void;
  handleMessage(
    message: unknown,
    sendResponse: (response: HistoryRuntimeResponse) => void,
  ): boolean;
};

export function createHistoryBackgroundSyncRuntime(config: {
  connectionStorageKey: string;
  startKeepAlive: () => { stop(): void };
}): HistoryBackgroundSyncRuntime {
  const module = new HistorySyncModule();
  const surface = new HistorySurfaceTimeline();
  let activeRun: Promise<boolean> | null = null;

  async function resolveSession(
    refreshMembership: boolean,
  ): Promise<{
    session: AiraDesktopAuthorizedSession | null;
    status: HistoryCapabilityStatus;
    remote: AiraCloudHistoryRemoteStore | null;
    hosted: boolean;
  }> {
    const [sourceRecord, personalServer] = await Promise.all([
      readExtensionStorageRecord([LEAFTAB_SELECTED_SYNC_SOURCE_KEY]),
      readPersonalServerConnection(),
    ]);
    const selectedSource = parseLeafTabSyncRemoteKind(sourceRecord[LEAFTAB_SELECTED_SYNC_SOURCE_KEY]);
    if (selectedSource === 'personal-server' && personalServer?.capabilities.history) {
      const session: AiraDesktopAuthorizedSession = {
        uid: personalServerAccountScope(personalServer),
        deviceId: personalServer.deviceId,
        deviceName: personalServer.deviceName,
        deviceCredential: personalServer.deviceToken,
      };
      return {
        session,
        status: 'ready',
        remote: new AiraCloudHistoryRemoteStore(
          session,
          `${personalServer.baseUrl}/v1/sync/history`,
          {
            authorizationToken: personalServer.deviceToken,
            includeHostedCredentials: false,
            serviceLabel: 'Personal Server History',
          },
        ),
        hosted: false,
      };
    }
    if (selectedSource !== 'aira-cloud') {
      return { session: null, status: 'login-required', remote: null, hosted: false };
    }
    let profile = await readAiraDesktopConnectionProfile();
    let status: AiraDesktopProCapabilityStatus = resolveAiraDesktopProCapability(profile);
    if (
      refreshMembership
      && status !== 'login-required'
      && (status !== 'ready' || shouldRefreshAiraDesktopConnectionMembership(profile))
    ) {
      try {
        profile = await refreshAiraDesktopConnectionProfileMembership({ force: status !== 'ready' });
        status = resolveAiraDesktopProCapability(profile);
      } catch {
        status = status === 'ready' ? 'ready' : 'temporarily-unavailable';
      }
    }
    const session = await readAiraDesktopAuthorizedSession();
    if (!session) return { session: null, status: 'login-required', remote: null, hosted: true };
    return { session, status, remote: new AiraCloudHistoryRemoteStore(session), hosted: true };
  }

  async function bumpRevision(): Promise<void> {
    await writeExtensionStorageRecord({
      [HISTORY_REVISION_STORAGE_KEY]: Date.now(),
    });
  }

  function getAlarms() {
    return globalThis.chrome?.alarms;
  }

  async function schedulePeriodic(delayMinutes = PERIODIC_SYNC_INTERVAL_MINUTES): Promise<void> {
    if (!(await readHistorySyncDomainEnabled())) return;
    const alarms = getAlarms();
    if (!alarms?.create) return;
    alarms.create(PERIODIC_SYNC_ALARM_NAME, { delayInMinutes: delayMinutes });
  }

  async function scheduleLocalChange(delayMinutes = LOCAL_CHANGE_DELAY_MINUTES): Promise<void> {
    if (!(await readHistorySyncDomainEnabled())) return;
    const alarms = getAlarms();
    if (!alarms?.create) return;
    alarms.create(LOCAL_SYNC_ALARM_NAME, { delayInMinutes: delayMinutes });
  }

  async function clearSchedules(): Promise<void> {
    const alarms = getAlarms();
    if (!alarms?.clear) return;
    await alarms.clear(LOCAL_SYNC_ALARM_NAME);
    await alarms.clear(PERIODIC_SYNC_ALARM_NAME);
  }

  async function runBackgroundSync(forceFullReconciliation = false): Promise<boolean> {
    if (activeRun) return activeRun;
    const run = (async () => {
      const syncEnabled = await readHistorySyncDomainEnabled();
      // The history override must stay current even when remote sync is paused.
      // Local capture uses the existing account ledger/outbox; only a later enabled
      // run may send those changes. Do not refresh membership over the network here
      // when the user has disabled History Sync.
      const resolved = await resolveSession(syncEnabled);
      if (!resolved.session) {
        if (resolved.status === 'login-required' || resolved.status === 'pro-required') {
          await clearSchedules();
        } else {
          await schedulePeriodic(RETRY_DELAY_MINUTES);
        }
        return false;
      }
      const keepAlive = config.startKeepAlive();
      try {
        await module.reconcileNativeHistory(resolved.session, forceFullReconciliation);
        if (!syncEnabled || !(await readHistorySyncDomainEnabled())) {
          await clearSchedules();
          await bumpRevision();
          return true;
        }
        if (resolved.status !== 'ready') {
          const message = capabilityError(resolved.status);
          await module.markSyncError(resolved.session, new Error(message));
          await bumpRevision();
          if (resolved.status === 'temporarily-unavailable') {
            await schedulePeriodic(RETRY_DELAY_MINUTES);
          } else {
            await clearSchedules();
          }
          return false;
        }
        await module.runSync(resolved.session, resolved.remote || undefined);
        await bumpRevision();
        return true;
      } catch (error) {
        await module.markSyncError(resolved.session, error).catch(() => undefined);
        if (resolved.hosted && isAiraDesktopCredentialRejection(error)) {
          await recordAiraDesktopConnectionFailure(error, {
            uid: resolved.session.uid,
            deviceCredential: resolved.session.deviceCredential,
          }).catch(() => undefined);
        } else {
          await schedulePeriodic(RETRY_DELAY_MINUTES);
        }
        await bumpRevision().catch(() => undefined);
        console.error('[Aira][History sync]', error);
        return false;
      } finally {
        keepAlive.stop();
      }
    })();
    activeRun = run;
    try {
      return await run;
    } finally {
      if (activeRun === run) activeRun = null;
    }
  }

  async function captureVisited(item: chrome.history.HistoryItem): Promise<void> {
    surface.invalidate(item.url);
    await bumpRevision();
    const resolved = await resolveSession(false);
    if (!resolved.session) return;
    const changed = await module.captureVisitedItem(resolved.session, item);
    if (changed > 0) {
      await bumpRevision();
      await scheduleLocalChange();
    }
  }

  async function captureRemoval(removed: chrome.history.RemovedResult): Promise<void> {
    surface.invalidate();
    await bumpRevision();
    const resolved = await resolveSession(false);
    if (!resolved.session) return;
    const changed = await module.recordNativeRemoval(resolved.session, removed);
    if (changed > 0 || removed.allHistory) {
      await bumpRevision();
      await scheduleLocalChange();
    }
  }

  function bindHistoryListeners(): void {
    const history = globalThis.chrome?.history;
    history?.onVisited?.addListener?.((item) => {
      void captureVisited(item).catch((error) => console.error('[Aira][History capture]', error));
    });
    history?.onVisitRemoved?.addListener?.((removed) => {
      void captureRemoval(removed).catch((error) => console.error('[Aira][History removal]', error));
    });
  }

  function bindOnlineRecovery(): void {
    globalThis.addEventListener?.('online', () => {
      void runBackgroundSync(false);
    });
  }

  async function listForCurrentAccount(message: HistoryRuntimeMessage): Promise<HistoryRuntimeResponse> {
    const resolved = await resolveSession(false);
    if (message.includeNative) {
      const synced = resolved.session
        ? await module.listTimeline(resolved.session.uid, {
          query: message.query, deviceId: message.deviceId, limit: HISTORY_SYNC_MAX_VISITS,
        })
        : emptyTimelinePage();
      const page = await surface.list(synced, resolved.session?.deviceId || '', resolved.session?.deviceName || '', message);
      return { success: true, status: typeof globalThis.chrome?.history?.search === 'function' ? 'ready' : resolved.status, page };
    }
    if (!resolved.session) {
      return { success: true, status: resolved.status, page: emptyTimelinePage() };
    }
    const page = await module.listTimeline(resolved.session.uid, {
      query: message.query,
      deviceId: message.deviceId,
      offset: message.offset,
      limit: message.limit,
    });
    return { success: true, status: resolved.status, page };
  }

  async function handleRuntimeMessage(message: HistoryRuntimeMessage): Promise<HistoryRuntimeResponse> {
    if (message.action === 'open') {
      if (message.includeNative) {
        // Native history is immediately available, even offline/unpaired. Cloud
        // refresh publishes a revision when it finishes, without blocking this view.
        void runBackgroundSync(false).catch(error => console.error('[Aira][History surface refresh]', error));
        return listForCurrentAccount(message);
      }
      const success = await runBackgroundSync(false);
      const response = await listForCurrentAccount(message);
      return {
        ...response,
        success,
        error: success
          ? undefined
          : response.page?.lastError || capabilityError(response.status),
      };
    }
    if (message.action === 'list') {
      return listForCurrentAccount(message);
    }
    if (message.action === 'sync') {
      const success = await runBackgroundSync(false);
      const response = await listForCurrentAccount(message);
      return {
        ...response,
        success,
        error: success
          ? undefined
          : response.page?.lastError || capabilityError(response.status),
      };
    }
    const resolved = await resolveSession(false);
    if (message.action === 'delete' && message.includeNative) {
      const url = nativeHistoryUrlForVisitId(String(message.visitId || ''));
      if (url) {
        // Only an explicit local row action may change the browser's native store.
        // The common browser API removes all visits to this URL; UI labels say so.
        await callBrowserHistoryApi<void>(callback => globalThis.chrome.history.deleteUrl({ url }, callback));
        surface.invalidate(url);
        if (resolved.session) await module.recordNativeRemoval(resolved.session, { allHistory: false, urls: [url] });
        await bumpRevision();
        await scheduleLocalChange();
        return listForCurrentAccount(message);
      }
    }
    if (!resolved.session) {
      return { success: false, status: resolved.status, error: 'Aira desktop connection is required.' };
    }
    if (message.action === 'delete') {
      const visitId = String(message.visitId || '').trim();
      if (!visitId) return { success: false, status: resolved.status, error: 'Missing visit ID.' };
      await module.deleteVisit(resolved.session, visitId);
    } else if (message.action === 'clear') {
      await module.clearHistory(resolved.session);
    }
    await bumpRevision();
    await scheduleLocalChange();
    return listForCurrentAccount(message);
  }

  return {
    initialize(): void {
      bindHistoryListeners();
      bindOnlineRecovery();
      void module.initialize()
        .then(() => schedulePeriodic(LOCAL_CHANGE_DELAY_MINUTES))
        .catch((error) => console.error('[Aira][History initialize]', error));
    },
    handleAlarm(alarmName: string): boolean {
      if (alarmName === LOCAL_SYNC_ALARM_NAME || alarmName === PERIODIC_SYNC_ALARM_NAME) {
        void runBackgroundSync(false)
          .finally(() => schedulePeriodic())
          .catch((error) => console.error('[Aira][History alarm]', error));
        return true;
      }
      return false;
    },
    notifyStartup(): void {
      void runBackgroundSync(true)
        .finally(() => schedulePeriodic())
        .catch((error) => console.error('[Aira][History startup]', error));
    },
    notifyStorageChanged(changes: Record<string, unknown>, areaName: string): void {
      if (areaName !== 'local') {
        return;
      }
      if (Object.prototype.hasOwnProperty.call(changes, HISTORY_SYNC_DOMAIN_ENABLED_KEY)) {
        void readHistorySyncDomainEnabled()
          .then(async (enabled) => {
            if (!enabled) {
              await clearSchedules();
              return;
            }
            await schedulePeriodic();
            await runBackgroundSync(false);
          })
          .catch((error) => console.error('[Aira][History sync switch]', error));
        return;
      }
      if (areaName !== 'local' || (
        !Object.prototype.hasOwnProperty.call(changes, config.connectionStorageKey)
        && !Object.prototype.hasOwnProperty.call(changes, PERSONAL_SERVER_CONNECTION_STORAGE_KEY)
        && !Object.prototype.hasOwnProperty.call(changes, LEAFTAB_SELECTED_SYNC_SOURCE_KEY)
      )) {
        return;
      }
      void runBackgroundSync(false)
        .finally(() => schedulePeriodic())
        .catch((error) => console.error('[Aira][History account change]', error));
    },
    handleMessage(message: unknown, sendResponse: (response: HistoryRuntimeResponse) => void): boolean {
      if (!message || typeof message !== 'object') return false;
      const request = message as Partial<HistoryRuntimeMessage>;
      if (request.type !== HISTORY_MESSAGE_TYPE) return false;
      void handleRuntimeMessage(request as HistoryRuntimeMessage)
        .then(sendResponse)
        .catch((error) => {
          sendResponse({
            success: false,
            status: 'temporarily-unavailable',
            error: String((error as Error)?.message || error),
          });
        });
      return true;
    },
  };
}

function emptyTimelinePage() {
  return {
    visits: [],
    total: 0,
    devices: [],
    lastSyncAt: 0,
    lastError: '',
  };
}

function capabilityError(status: HistoryCapabilityStatus): string {
  if (status === 'login-required') return 'Aira desktop connection is required.';
  if (status === 'pro-required') return 'Aira Pro is required for History Sync.';
  if (status === 'temporarily-unavailable') return 'History Sync is temporarily unavailable.';
  return 'History Sync failed.';
}
