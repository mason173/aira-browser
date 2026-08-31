import {
  BrowserSearchInvocationEndReason,
  BrowserSearchInvocationReceipt,
  BrowserSearchInvocationSessionCoordinator,
  BrowserSearchInvocationSnapshot,
  BrowserSearchInvocationSource,
  BrowserSearchInvocationSurfaceAdapter
} from '../../core/search/BrowserSearchInvocationSessionCoordinator';
import { SettingsSearchInvocationAdapter } from '../router/SettingsSearchInvocationAdapter';

export interface BrowserSearchInvocationTrigger {
  open: () => BrowserSearchInvocationReceipt;
}

export interface BrowserSearchInvocationAuthorityGate {
  isAuthorized: () => boolean;
}

export class BrowserSearchInvocationAuthorityGateAdapter implements BrowserSearchInvocationAuthorityGate {
  private resolver: () => boolean;

  constructor(resolver: () => boolean) {
    this.resolver = resolver;
  }

  isAuthorized(): boolean {
    return this.resolver();
  }
}

class BrowserSearchAlwaysAuthorizedGate implements BrowserSearchInvocationAuthorityGate {
  isAuthorized(): boolean {
    return true;
  }
}

class BrowserSearchInvocationTriggerAdapter implements BrowserSearchInvocationTrigger {
  private coordinator: BrowserSearchInvocationSessionCoordinator;
  private source: BrowserSearchInvocationSource;
  private authorityGate: BrowserSearchInvocationAuthorityGate;

  constructor(
    coordinator: BrowserSearchInvocationSessionCoordinator,
    source: BrowserSearchInvocationSource,
    authorityGate: BrowserSearchInvocationAuthorityGate = new BrowserSearchAlwaysAuthorizedGate()
  ) {
    this.coordinator = coordinator;
    this.source = source;
    this.authorityGate = authorityGate;
  }

  open(): BrowserSearchInvocationReceipt {
    return this.coordinator.open(this.source, this.authorityGate.isAuthorized());
  }
}

export class BrowserSearchInvocationTriggers {
  readonly desktopCard: BrowserSearchInvocationTrigger;
  readonly appShortcut: BrowserSearchInvocationTrigger;
  readonly keyboard: BrowserSearchInvocationTrigger;
  readonly browserChrome: BrowserSearchInvocationTrigger;

  constructor(coordinator: BrowserSearchInvocationSessionCoordinator) {
    this.desktopCard = new BrowserSearchInvocationTriggerAdapter(coordinator, 'desktop_card');
    this.appShortcut = new BrowserSearchInvocationTriggerAdapter(coordinator, 'app_shortcut');
    this.keyboard = new BrowserSearchInvocationTriggerAdapter(coordinator, 'keyboard');
    this.browserChrome = new BrowserSearchInvocationTriggerAdapter(coordinator, 'browser_chrome');
  }
}

export class BrowserSearchInvocationSurfaceConnection {
  private defaultAdapter: BrowserSearchInvocationSurfaceAdapter;
  private pendingAdapter?: BrowserSearchInvocationSurfaceAdapter;
  private connectedAdapter?: BrowserSearchInvocationSurfaceAdapter;
  private disconnectRuntime: () => boolean = (): boolean => false;
  private connectedWindowId: string = '';
  private connectionVersion: number = 0;
  private pendingWindowId: string = '';

  constructor(adapter: BrowserSearchInvocationSurfaceAdapter) {
    this.defaultAdapter = adapter;
  }

  connect(
    windowId: string,
    ready: boolean,
    adapter: BrowserSearchInvocationSurfaceAdapter = this.defaultAdapter
  ): void {
    const normalizedWindowId = windowId.trim();
    const surfaceStillRegistered = normalizedWindowId.length > 0 &&
      BrowserSearchInvocationRuntime.isSurfaceAdapterRegistered(normalizedWindowId, adapter);
    if (!ready || normalizedWindowId.length <= 0) {
      this.disconnect();
      return;
    }
    if (normalizedWindowId === this.connectedWindowId && this.connectedAdapter === adapter &&
      surfaceStillRegistered) {
      this.cancelPendingConnection();
      return;
    }
    if (normalizedWindowId === this.pendingWindowId && this.pendingAdapter === adapter) {
      return;
    }
    const version = this.connectionVersion + 1;
    this.connectionVersion = version;
    this.pendingWindowId = normalizedWindowId;
    this.pendingAdapter = adapter;
    setTimeout((): void => {
      if (this.connectionVersion === version) {
        this.pendingWindowId = '';
        this.pendingAdapter = undefined;
      }
      this.commitConnection(version, normalizedWindowId, adapter);
    }, 0);
  }

  connectForShell(
    windowId: string,
    ready: boolean,
    largeScreenActive: boolean,
    phoneAdapter: BrowserSearchInvocationSurfaceAdapter,
    largeScreenAdapter: BrowserSearchInvocationSurfaceAdapter
  ): void {
    this.connect(windowId, ready, largeScreenActive ? largeScreenAdapter : phoneAdapter);
  }

  disconnect(): void {
    this.connectionVersion += 1;
    this.pendingWindowId = '';
    this.pendingAdapter = undefined;
    this.disconnectRuntime();
    this.disconnectRuntime = (): boolean => false;
    this.connectedWindowId = '';
    this.connectedAdapter = undefined;
  }

  private commitConnection(
    version: number,
    windowId: string,
    adapter: BrowserSearchInvocationSurfaceAdapter
  ): void {
    if (this.connectionVersion !== version) {
      return;
    }
    const surfaceStillRegistered = BrowserSearchInvocationRuntime.isSurfaceAdapterRegistered(windowId, adapter);
    if (windowId === this.connectedWindowId && this.connectedAdapter === adapter && surfaceStillRegistered) {
      return;
    }
    this.disconnectRuntime();
    this.disconnectRuntime = (): boolean => false;
    this.connectedWindowId = '';
    this.connectedAdapter = undefined;
    this.disconnectRuntime = BrowserSearchInvocationRuntime.registerSurfaceAdapter(
      windowId,
      adapter
    );
    this.connectedWindowId = windowId;
    this.connectedAdapter = adapter;
  }

  private cancelPendingConnection(): void {
    if (this.pendingWindowId.length <= 0) {
      return;
    }
    this.connectionVersion += 1;
    this.pendingWindowId = '';
    this.pendingAdapter = undefined;
  }
}

class BrowserSearchInvocationWindowRuntime {
  readonly coordinator: BrowserSearchInvocationSessionCoordinator;
  readonly triggers: BrowserSearchInvocationTriggers;
  readonly settingsAdapter: SettingsSearchInvocationAdapter;

  constructor() {
    this.coordinator = new BrowserSearchInvocationSessionCoordinator();
    this.triggers = new BrowserSearchInvocationTriggers(this.coordinator);
    this.settingsAdapter = new SettingsSearchInvocationAdapter();
    this.coordinator.registerSettingsAdapter(this.settingsAdapter);
  }
}

export class BrowserSearchInvocationRuntime {
  private static windows: Record<string, BrowserSearchInvocationWindowRuntime> = {};

  static triggers(windowId: string): BrowserSearchInvocationTriggers {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).triggers;
  }

  static bindThirdPartyHomeTrigger(
    windowId: string,
    authorityGate: BrowserSearchInvocationAuthorityGate
  ): BrowserSearchInvocationTrigger {
    return new BrowserSearchInvocationTriggerAdapter(
      BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator,
      'third_party_home',
      authorityGate
    );
  }

  static activateSettingsNavigation(windowId: string): void {
    const runtime = BrowserSearchInvocationRuntime.resolveWindow(windowId);
    runtime.coordinator.clearSurfaceAdapter();
    runtime.settingsAdapter.activate();
  }

  static isSurfaceAdapterRegistered(
    windowId: string,
    adapter: BrowserSearchInvocationSurfaceAdapter
  ): boolean {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.isSurfaceAdapterRegistered(adapter);
  }

  static registerSurfaceAdapter(
    windowId: string,
    adapter: BrowserSearchInvocationSurfaceAdapter
  ): () => boolean {
    const coordinator = BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator;
    coordinator.registerSurfaceAdapter(adapter);
    return (): boolean => {
      coordinator.unregisterSurfaceAdapter(adapter);
      return true;
    };
  }

  static notifyForeground(windowId: string): void {
    const coordinator = BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator;
    coordinator.notifyForeground();
  }

  static notifyBackground(windowId: string): void {
    const coordinator = BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator;
    coordinator.notifyBackground();
  }

  static updateDraft(windowId: string, authorityId: string, draft: string): boolean {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.updateDraft(authorityId, draft);
  }

  static updateCurrentDraft(windowId: string, draft: string): boolean {
    const coordinator = BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator;
    return coordinator.updateDraft(coordinator.currentAuthorityId(), draft);
  }

  static reconcileActiveContext(windowId: string, activeContextId: string): boolean {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.reconcileActiveContext(activeContextId);
  }

  static end(
    windowId: string,
    authorityId: string,
    reason: BrowserSearchInvocationEndReason
  ): boolean {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.end(authorityId, reason);
  }

  static endCurrent(windowId: string, reason: BrowserSearchInvocationEndReason): boolean {
    const coordinator = BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator;
    return coordinator.end(coordinator.currentAuthorityId(), reason);
  }

  static currentAuthorityId(windowId: string): string {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.currentAuthorityId();
  }

  static snapshot(windowId: string): BrowserSearchInvocationSnapshot {
    return BrowserSearchInvocationRuntime.resolveWindow(windowId).coordinator.snapshot();
  }

  static clearWindow(windowId: string): void {
    const normalizedWindowId = BrowserSearchInvocationRuntime.normalizeWindowId(windowId);
    BrowserSearchInvocationRuntime.windows[normalizedWindowId]?.settingsAdapter.dispose();
    BrowserSearchInvocationRuntime.windows = BrowserSearchInvocationRuntime.filterWindows(normalizedWindowId);
  }

  private static resolveWindow(windowId: string): BrowserSearchInvocationWindowRuntime {
    const normalizedWindowId = BrowserSearchInvocationRuntime.normalizeWindowId(windowId);
    let runtime = BrowserSearchInvocationRuntime.windows[normalizedWindowId];
    if (runtime === undefined) {
      runtime = new BrowserSearchInvocationWindowRuntime();
      BrowserSearchInvocationRuntime.windows[normalizedWindowId] = runtime;
    }
    return runtime;
  }

  private static normalizeWindowId(windowId: string): string {
    const normalized = windowId.trim();
    return normalized.length > 0 ? normalized : 'window-main';
  }

  private static filterWindows(excludedWindowId: string): Record<string, BrowserSearchInvocationWindowRuntime> {
    const next: Record<string, BrowserSearchInvocationWindowRuntime> = {};
    const windowIds = Object.keys(BrowserSearchInvocationRuntime.windows);
    for (let index = 0; index < windowIds.length; index += 1) {
      const windowId = windowIds[index];
      if (windowId !== excludedWindowId) {
        next[windowId] = BrowserSearchInvocationRuntime.windows[windowId];
      }
    }
    return next;
  }
}
