import { webview } from '@kit.ArkWeb';

export interface BrowserWindowNewEventManagerOptions {
  timeoutMs?: number;
  schedule?: (delayMs: number, callback: () => void) => number;
  cancel?: (timerId: number) => void;
  onEventExpired?: (tabId: string, reason: string) => void;
}

interface BrowserWindowNewEventRecord {
  tabId: string;
  event: OnWindowNewEvent;
  timerId: number;
  createdAt: number;
}

const DEFAULT_WINDOW_NEW_EVENT_TIMEOUT_MS: number = 3000;

export class BrowserWindowNewEventManager {
  private readonly timeoutMs: number;
  private readonly schedule: (delayMs: number, callback: () => void) => number;
  private readonly cancel: (timerId: number) => void;
  private readonly onEventExpired?: (tabId: string, reason: string) => void;
  private recordsByTabId: Record<string, BrowserWindowNewEventRecord | undefined> = {};

  constructor(options: BrowserWindowNewEventManagerOptions = {}) {
    this.timeoutMs = Math.max(0, options.timeoutMs ?? DEFAULT_WINDOW_NEW_EVENT_TIMEOUT_MS);
    this.schedule = options.schedule ?? ((delayMs: number, callback: () => void): number => {
      return setTimeout(callback, delayMs);
    });
    this.cancel = options.cancel ?? ((timerId: number): void => {
      clearTimeout(timerId);
    });
    this.onEventExpired = options.onEventExpired;
  }

  addEvent(tabId: string, event: OnWindowNewEvent): boolean {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      this.safeSetWebController(event, undefined);
      return false;
    }
    this.rejectEvent(normalizedTabId, 'replaced');
    const timerId = this.schedule(this.timeoutMs, (): void => {
      this.expireEvent(normalizedTabId);
    });
    this.recordsByTabId[normalizedTabId] = {
      tabId: normalizedTabId,
      event: event,
      timerId: timerId,
      createdAt: Date.now()
    };
    return true;
  }

  hasEvent(tabId: string): boolean {
    return this.recordsByTabId[tabId.trim()] !== undefined;
  }

  takeEvent(tabId: string): OnWindowNewEvent | undefined {
    const normalizedTabId = tabId.trim();
    const record = this.recordsByTabId[normalizedTabId];
    if (record === undefined) {
      return undefined;
    }
    this.clearRecord(normalizedTabId, record);
    return record.event;
  }

  completeEvent(tabId: string, controller: webview.WebviewController): boolean {
    const event = this.takeEvent(tabId);
    if (event === undefined) {
      return false;
    }
    return this.safeSetWebController(event, controller);
  }

  rejectEvent(tabId: string, reason: string = 'rejected'): boolean {
    const event = this.takeEvent(tabId);
    if (event === undefined) {
      return false;
    }
    this.onEventExpired?.(tabId.trim(), reason);
    return this.safeSetWebController(event, undefined);
  }

  private expireEvent(tabId: string): void {
    const normalizedTabId = tabId.trim();
    const record = this.recordsByTabId[normalizedTabId];
    if (record === undefined) {
      return;
    }
    this.recordsByTabId[normalizedTabId] = undefined;
    this.onEventExpired?.(normalizedTabId, 'timeout');
    this.safeSetWebController(record.event, undefined);
  }

  private clearRecord(tabId: string, record: BrowserWindowNewEventRecord): void {
    this.cancel(record.timerId);
    this.recordsByTabId[tabId] = undefined;
  }

  private safeSetWebController(event: OnWindowNewEvent, controller: webview.WebviewController | undefined): boolean {
    try {
      if (controller !== undefined) {
        event.handler.setWebController(controller);
      } else {
        event.handler.setWebController(null);
      }
      return true;
    } catch (_error) {
      return false;
    }
  }
}
