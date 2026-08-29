import { AIRA_DESKTOP_CONNECTION_STORAGE_KEY } from '@/features/desktop-connection/desktopConnectionRuntime';
import {
  clearDesktopTabSnapshot,
  publishCurrentDesktopTabs,
} from './deviceTabsClient';
import {
  isCrossDeviceTabsPreferenceStorageKey,
  readCrossDeviceTabsEnabledFromExtensionStorage,
} from './deviceTabsPreferences';

const DEVICE_TABS_HEARTBEAT_ALARM = 'aira.cross-device-tabs.heartbeat';
const PUBLISH_DEBOUNCE_MS = 750;

export class DeviceTabsBackgroundRuntime {
  private publishTimer: ReturnType<typeof globalThis.setTimeout> | null = null;
  private publishPromise: Promise<boolean> | null = null;

  initialize(): void {
    this.bindBrowserTabSignals();
    void this.reconcile(true);
  }

  handleAlarm(name: string): boolean {
    if (name !== DEVICE_TABS_HEARTBEAT_ALARM) return false;
    void this.publishNow();
    return true;
  }

  notifyStartup(): void {
    void this.reconcile(true);
  }

  notifyStorageChanged(changes: Record<string, chrome.storage.StorageChange>, areaName: string): void {
    if (areaName !== 'local') return;
    const keys = Object.keys(changes);
    if (!keys.includes(AIRA_DESKTOP_CONNECTION_STORAGE_KEY)
      && !keys.some(isCrossDeviceTabsPreferenceStorageKey)) {
      return;
    }
    void this.reconcile(false);
  }

  schedulePublish(): void {
    if (this.publishTimer !== null) {
      globalThis.clearTimeout(this.publishTimer);
    }
    this.publishTimer = globalThis.setTimeout(() => {
      this.publishTimer = null;
      void this.publishNow();
    }, PUBLISH_DEBOUNCE_MS);
  }

  async publishNow(): Promise<boolean> {
    if (this.publishPromise) return this.publishPromise;
    this.publishPromise = this.publishIfEnabled();
    try {
      return await this.publishPromise;
    } finally {
      this.publishPromise = null;
    }
  }

  private async publishIfEnabled(): Promise<boolean> {
    if (!(await readCrossDeviceTabsEnabledFromExtensionStorage())) {
      return false;
    }
    try {
      return await publishCurrentDesktopTabs();
    } catch (error) {
      console.warn('[Aira][DeviceTabs] publish failed', error);
      return false;
    }
  }

  private async reconcile(isStartup: boolean): Promise<void> {
    const enabled = await readCrossDeviceTabsEnabledFromExtensionStorage().catch(() => false);
    if (!enabled) {
      this.cancelPendingPublish();
      await this.clearHeartbeatAlarm();
      if (!isStartup) {
        await clearDesktopTabSnapshot().catch((error) => {
          console.warn('[Aira][DeviceTabs] clear failed', error);
        });
      }
      return;
    }
    this.scheduleHeartbeatAlarm();
    this.schedulePublish();
  }

  private bindBrowserTabSignals(): void {
    const tabs = globalThis.chrome?.tabs;
    tabs?.onCreated?.addListener(() => this.schedulePublish());
    tabs?.onUpdated?.addListener(() => this.schedulePublish());
    tabs?.onRemoved?.addListener(() => this.schedulePublish());
    tabs?.onActivated?.addListener(() => this.schedulePublish());
    tabs?.onMoved?.addListener(() => this.schedulePublish());
    tabs?.onAttached?.addListener(() => this.schedulePublish());
    tabs?.onDetached?.addListener(() => this.schedulePublish());
    tabs?.onReplaced?.addListener(() => this.schedulePublish());
    globalThis.chrome?.windows?.onFocusChanged?.addListener(() => this.schedulePublish());
  }

  private scheduleHeartbeatAlarm(): void {
    globalThis.chrome?.alarms?.create?.(DEVICE_TABS_HEARTBEAT_ALARM, {
      delayInMinutes: 1,
      periodInMinutes: 1,
    });
  }

  private async clearHeartbeatAlarm(): Promise<void> {
    await globalThis.chrome?.alarms?.clear?.(DEVICE_TABS_HEARTBEAT_ALARM);
  }

  private cancelPendingPublish(): void {
    if (this.publishTimer !== null) {
      globalThis.clearTimeout(this.publishTimer);
      this.publishTimer = null;
    }
  }
}
