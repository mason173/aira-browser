import {
  LEAFTAB_SYNC_DEVICE_ID_KEY,
  LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE,
} from '@/features/sync/app/leafTabSyncStorageKeys';
import {
  isAiraDesktopConnectionProfilePro,
  readAiraDesktopConnectionProfile,
  refreshAiraDesktopConnectionProfileMembership,
  resolveAiraDesktopProCapability,
  shouldRefreshAiraDesktopConnectionMembership,
  type AiraDesktopProCapabilityStatus,
} from '@/features/desktop-connection/desktopConnectionProfile';
import {
  PHONE_PAGE_PUSH_MESSAGE_TYPE,
  type PhonePagePushMessage,
} from '@/features/phone-page-push/pagePushMessages';
import {
  isPhonePagePushPreferenceStorageKey,
  readPhonePagePushEnabledFromExtensionStorage,
} from '@/features/phone-page-push/pagePushPreferences';
import {
  AIRA_DESKTOP_CONNECTION_STORAGE_KEY,
  postAiraDesktopJson,
  recordAiraDesktopConnectionFailure,
} from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  createBookmarkBackgroundSyncRuntime,
} from '@/features/sync/bookmarks/BookmarkBackgroundSyncRuntime';
import {
  readExtensionStorageRecord,
} from '@/platform/extensionStorage';

const WEBDAV_PROXY_MESSAGE_TYPE = 'LEAFTAB_WEBDAV_PROXY';
const PHONE_PAGE_PUSH_POLL_ALARM_NAME = 'aira.phone-page-push.poll';
const BACKGROUND_KEEPALIVE_INTERVAL_MS = 20_000;
const PHONE_PAGE_PUSH_FALLBACK_TITLE = 'Aira';
const PHONE_PAGE_PUSH_POLL_INTERVAL_MS = 500;
const PHONE_PAGE_PUSH_LONG_POLL_WAIT_MS = 20_000;
const PHONE_PAGE_PUSH_ERROR_RETRY_MS = 5_000;
const PHONE_PAGE_PUSH_ALARM_FALLBACK_MS = 30_000;
const PHONE_PAGE_PUSH_SOURCE = 'airatab_desktop_extension';

let activePhonePagePushPollPromise: Promise<boolean> | null = null;
let phonePagePushPollTimer: ReturnType<typeof globalThis.setTimeout> | null = null;
let phonePagePushEnabled = true;

async function refreshDesktopMembershipForProFeature(): Promise<AiraDesktopProCapabilityStatus> {
  try {
    const profile = await readAiraDesktopConnectionProfile();
    const currentCapability = resolveAiraDesktopProCapability(profile);
    if (currentCapability === 'login-required') return currentCapability;
    const latestProfile = await refreshAiraDesktopConnectionProfileMembership({ force: true });
    return resolveAiraDesktopProCapability(latestProfile);
  } catch {
    return 'temporarily-unavailable';
  }
}

type PhonePagePushUrlPayload = {
  url?: unknown;
  originalUrl?: unknown;
  desktopUrl?: unknown;
};

type PhonePagePushTaskPayload = PhonePagePushUrlPayload & {
  taskId?: unknown;
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

function getStorageApi() {
  return globalThis.chrome?.storage;
}

function getIdleApi() {
  return globalThis.chrome?.idle;
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

function normalizePhonePagePushMessage(message: unknown): PhonePagePushMessage | null {
  if (!message || typeof message !== 'object') return null;
  const candidate = message as Partial<PhonePagePushMessage>;
  if (candidate.type !== PHONE_PAGE_PUSH_MESSAGE_TYPE) return null;
  const payload = (candidate.payload || {}) as {
    url?: unknown;
    originalUrl?: unknown;
    desktopUrl?: unknown;
    title?: unknown;
  };
  const originalUrl = normalizePhonePagePushUrl(payload.originalUrl) || normalizePhonePagePushUrl(payload.url);
  const desktopUrl = normalizePhonePagePushUrl(payload.desktopUrl);
  const url = desktopUrl || normalizePhonePagePushUrl(payload.url) || originalUrl;
  if (!url) return null;
  return {
    type: PHONE_PAGE_PUSH_MESSAGE_TYPE,
    payload: {
      url,
      originalUrl: originalUrl || undefined,
      desktopUrl: desktopUrl || undefined,
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

function resolvePhonePagePushOpenUrl(payload: PhonePagePushUrlPayload | null | undefined): string {
  return normalizePhonePagePushUrl(payload?.desktopUrl)
    || normalizePhonePagePushUrl(payload?.url)
    || normalizePhonePagePushUrl(payload?.originalUrl);
}

function resolvePhonePagePushOriginalUrl(payload: PhonePagePushUrlPayload | null | undefined): string {
  return normalizePhonePagePushUrl(payload?.originalUrl) || normalizePhonePagePushUrl(payload?.url);
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

async function openPhonePagePushPayload(payload: PhonePagePushUrlPayload, title: string): Promise<boolean> {
  const preferredUrl = resolvePhonePagePushOpenUrl(payload);
  if (!preferredUrl) {
    return false;
  }
  if (await openPhonePagePushTab(preferredUrl, title)) {
    return true;
  }
  const originalUrl = resolvePhonePagePushOriginalUrl(payload);
  if (!originalUrl || originalUrl === preferredUrl) {
    return false;
  }
  return openPhonePagePushTab(originalUrl, title);
}

async function resolvePhonePagePushPollProfile() {
  phonePagePushEnabled = await readPhonePagePushEnabledFromExtensionStorage();
  if (!phonePagePushEnabled) {
    return null;
  }

  const profile = await readAiraDesktopConnectionProfile();
  if (!profile?.uid || !profile.deviceCredential) {
    return null;
  }

  const isCachedPro = isAiraDesktopConnectionProfilePro(profile);
  if (!isCachedPro || shouldRefreshAiraDesktopConnectionMembership(profile)) {
    try {
      const latestProfile = await refreshAiraDesktopConnectionProfileMembership({
        force: !isCachedPro,
      });
      if (!isAiraDesktopConnectionProfilePro(latestProfile)) {
        return null;
      }
      return latestProfile;
    } catch (error) {
      if (!isCachedPro) return null;
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
  deviceId: string;
  deviceName: string;
  taskId: string;
  leaseToken: string;
  status: 'opened' | 'failed';
  error?: string;
}): Promise<void> {
  const response = await postAiraDesktopJson<PhonePagePushAckResponse>('/phone-page-push/ack', {
    desktopPushToken: params.desktopPushToken,
    deviceId: params.deviceId,
    deviceName: params.deviceName,
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
    if (!profile?.deviceCredential) {
      clearPhonePagePushPollTimer();
      await clearPhonePagePushPollAlarm();
      return false;
    }

    let nextDelayMs = PHONE_PAGE_PUSH_POLL_INTERVAL_MS;
    let continuePolling = true;
    const keepAlive = startBackgroundKeepAlive();
    try {
      const response = await postAiraDesktopJson<PhonePagePushPollResponse>('/phone-page-push/poll', {
        desktopPushToken: profile.deviceCredential,
        deviceId: profile.deviceId,
        deviceName: profile.deviceName,
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
      const url = resolvePhonePagePushOpenUrl(task);
      const title = normalizePhonePagePushTitle(task?.title) || PHONE_PAGE_PUSH_FALLBACK_TITLE;
      if (!taskId || !leaseToken || !url) {
        return false;
      }

      nextDelayMs = 0;
      const opened = await openPhonePagePushPayload(task || {}, title);
      try {
        await ackPhonePagePushTask({
          desktopPushToken: profile.deviceCredential,
          deviceId: profile.deviceId,
          deviceName: profile.deviceName,
          taskId,
          leaseToken,
          status: opened ? 'opened' : 'failed',
          error: opened ? '' : 'tabs.create unavailable or failed',
        });
      } catch (error) {
        const snapshot = await recordAiraDesktopConnectionFailure(error).catch(() => null);
        if (snapshot?.status === 'reauth-required') {
          continuePolling = false;
        }
        console.warn('[Aira][PhonePush] ack failed', error);
      }
      return opened;
    } catch (error) {
      nextDelayMs = PHONE_PAGE_PUSH_ERROR_RETRY_MS;
      const snapshot = await recordAiraDesktopConnectionFailure(error).catch(() => null);
      if (snapshot?.status === 'reauth-required') {
        continuePolling = false;
      }
      console.warn('[Aira][PhonePush] poll failed', error);
      return false;
    } finally {
      keepAlive.stop();
      if (continuePolling) {
        schedulePhonePagePushPollTimer(nextDelayMs);
        await schedulePhonePagePushPollAlarm(PHONE_PAGE_PUSH_ALARM_FALLBACK_MS);
      } else {
        clearPhonePagePushPollTimer();
        await clearPhonePagePushPollAlarm();
      }
    }
  })();

  try {
    return await activePhonePagePushPollPromise;
  } finally {
    activePhonePagePushPollPromise = null;
  }
}

const bookmarkBackgroundSyncRuntime = createBookmarkBackgroundSyncRuntime({
  startKeepAlive: startBackgroundKeepAlive,
});

function bindAlarmListeners(): void {
  const alarms = getAlarmsApi();
  if (!alarms?.onAlarm) {
    return;
  }
  alarms.onAlarm.addListener((alarm) => {
    if (bookmarkBackgroundSyncRuntime.handleAlarm(alarm.name)) {
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
    bookmarkBackgroundSyncRuntime.notifyStartup();
    void reconcilePhonePagePushSchedule(true);
    void pollPhonePagePushOnce();
  });
  runtime?.onInstalled?.addListener?.(() => {
    bookmarkBackgroundSyncRuntime.notifyStartup();
    void reconcilePhonePagePushSchedule(true);
    void pollPhonePagePushOnce();
  });
  getIdleApi()?.onStateChanged?.addListener?.((_state) => {
    bookmarkBackgroundSyncRuntime.notifyIdleStateChanged();
  });
  getStorageApi()?.onChanged?.addListener?.((changes, areaName) => {
    bookmarkBackgroundSyncRuntime.notifyStorageChanged(changes, areaName);
    if (areaName !== 'local') {
      return;
    }
    const changedKeys = Object.keys(changes);
    const phonePagePushPreferenceChanged = changedKeys.some(isPhonePagePushPreferenceStorageKey);
    const phonePagePushRelevantChanged = phonePagePushPreferenceChanged
      || changedKeys.includes(AIRA_DESKTOP_CONNECTION_STORAGE_KEY);
    if (phonePagePushRelevantChanged) {
      void reconcilePhonePagePushSchedule();
      void pollPhonePagePushOnce();
      if (phonePagePushPreferenceChanged) {
        void readPhonePagePushEnabledFromExtensionStorage().then((enabled) => {
          phonePagePushEnabled = enabled;
        });
      }
    }
  });
}

function bindWebdavProxyMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message) return;
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
          headers: Object.fromEntries(response.headers.entries()),
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

function bindLeafTabSyncDeviceIdMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    if (message?.type !== LEAFTAB_SYNC_DEVICE_ID_REQUEST_TYPE) return;
    void bookmarkBackgroundSyncRuntime.getOrCreateDeviceId()
      .then((deviceId) => {
        sendResponse({ success: true, deviceId });
      })
      .catch((error) => {
        sendResponse({
          success: false,
          error: String(error instanceof Error ? error.message : error),
        });
      });
    return true;
  });
}

function bindPhonePagePushMessageListener(): void {
  getRuntime()?.onMessage.addListener((message, _sender, sendResponse) => {
    const normalized = normalizePhonePagePushMessage(message);
    if (!normalized) return;
    void (async () => {
      phonePagePushEnabled = await readPhonePagePushEnabledFromExtensionStorage();
      if (!phonePagePushEnabled) {
        sendResponse({
          success: false,
          error: 'Phone page push is disabled',
        });
        return;
      }
      const capability = await refreshDesktopMembershipForProFeature();
      if (capability !== 'ready') {
        sendResponse({
          success: false,
          error: capability === 'login-required'
            ? 'Aira desktop reconnection is required'
            : capability === 'pro-required'
              ? 'Aira Pro is required'
              : 'Aira service is temporarily unavailable',
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

      const opened = await openPhonePagePushPayload(payload, payload.title || PHONE_PAGE_PUSH_FALLBACK_TITLE);
      sendResponse({
        success: opened,
        error: opened ? undefined : 'Unable to open pushed page',
      });
    })();
    return true;
  });
}

bindWebdavProxyMessageListener();
bindLeafTabSyncDeviceIdMessageListener();
bindPhonePagePushMessageListener();
bindAlarmListeners();
bindLifecycleListeners();
bookmarkBackgroundSyncRuntime.initialize();
void readPhonePagePushEnabledFromExtensionStorage()
  .then((enabled) => {
    phonePagePushEnabled = enabled;
  })
  .catch(() => undefined);
void reconcilePhonePagePushSchedule(true);
void pollPhonePagePushOnce();
