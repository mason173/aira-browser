import {
  BrowserLaunchPayload,
  BrowserLaunchShortcutContext
} from '../../app/runtime/BrowserWindowRuntime';
import { DesktopWebEntryRecord } from '../../data/webapps/WebAppInstallModels';
import {
  WebAppInstallRepository,
  sharedWebAppInstallRepository
} from '../../data/webapps/WebAppInstallRepository';
import {
  DesktopWebEntryLaunchPlan,
  DesktopWebEntryLaunchService
} from '../../services/webapps/DesktopWebEntryLaunchService';
import { BrowserTabState } from '../tabs/TabManager';

export interface WebAppActiveContext {
  shortcutId: string;
  windowId: string;
  launchUrl: string;
  origin: string;
  scope: string;
  manifestUrl: string;
  themeColor: string;
  title: string;
  iconPath: string;
  createdAt: number;
  startedAt: number;
}

export class WebAppSessionSnapshot {
  windowId: string;
  activeContext: WebAppActiveContext | undefined;
  defaultFullscreen: boolean;

  constructor(
    windowId: string,
    activeContext: WebAppActiveContext | undefined,
    defaultFullscreen: boolean
  ) {
    this.windowId = windowId;
    this.activeContext = activeContext;
    this.defaultFullscreen = defaultFullscreen;
  }
}

export class WebAppSessionLaunchPreparation {
  accepted: boolean;
  snapshot: WebAppSessionSnapshot;
  plan: DesktopWebEntryLaunchPlan;

  constructor(
    accepted: boolean,
    snapshot: WebAppSessionSnapshot,
    plan: DesktopWebEntryLaunchPlan
  ) {
    this.accepted = accepted;
    this.snapshot = snapshot;
    this.plan = plan;
  }
}

export interface WebAppImmersiveModeInput {
  showHomePage: boolean;
  showTabsSheet: boolean;
}

export interface WebAppImmersiveVisualStateInput extends WebAppImmersiveModeInput {
  webPageVisible: boolean;
  fullScreenModeEnabled: boolean;
  globalImmersionEnabled: boolean;
}

export interface WebAppImmersiveVisualState {
  immersive: boolean;
  hideTopSafeArea: boolean;
  hideBottomChrome: boolean;
  restoreTopSafeArea: boolean;
}

const DEFAULT_WEB_APP_WINDOW_ID: string = 'window-main';

export class WebAppSessionCoordinator {
  private readonly installRepository: WebAppInstallRepository;
  private readonly launchService: DesktopWebEntryLaunchService;
  private snapshotsByWindowId: Record<string, WebAppSessionSnapshot | undefined> = {};
  private requestGenerationByWindowId: Record<string, number | undefined> = {};

  constructor(
    installRepository: WebAppInstallRepository = sharedWebAppInstallRepository,
    launchService: DesktopWebEntryLaunchService = new DesktopWebEntryLaunchService()
  ) {
    this.installRepository = installRepository;
    this.launchService = launchService;
  }

  async prepareLaunch(
    payload: BrowserLaunchPayload,
    windowId: string,
    tabs: BrowserTabState[],
    activeTabId: string
  ): Promise<WebAppSessionLaunchPreparation> {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const generation = this.advanceRequestGeneration(normalizedWindowId);
    const shortcut = payload.shortcut;
    let record: DesktopWebEntryRecord | undefined = undefined;
    if (shortcut !== undefined) {
      try {
        record = await this.installRepository.findByShortcutId(shortcut.shortcutId);
      } catch (_error) {
      }
    }
    const plan = this.launchService.buildPlan(payload, record, tabs, activeTabId);
    if (shortcut === undefined || !this.isCurrentRequest(normalizedWindowId, generation)) {
      return new WebAppSessionLaunchPreparation(false, this.snapshot(normalizedWindowId), plan);
    }
    const context = this.buildActiveContext(payload, shortcut, normalizedWindowId, record);
    const snapshot = this.commitSnapshot(
      normalizedWindowId,
      context,
      record?.settings.defaultFullscreen === true
    );
    return new WebAppSessionLaunchPreparation(true, snapshot, plan);
  }

  snapshot(windowId: string): WebAppSessionSnapshot {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    return this.snapshotsByWindowId[normalizedWindowId] ??
      new WebAppSessionSnapshot(normalizedWindowId, undefined, false);
  }

  async refreshSettings(windowId: string): Promise<WebAppSessionSnapshot> {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    const currentSnapshot = this.snapshot(normalizedWindowId);
    const activeContext = currentSnapshot.activeContext;
    if (activeContext === undefined) {
      return currentSnapshot;
    }
    const generation = this.advanceRequestGeneration(normalizedWindowId);
    let record: DesktopWebEntryRecord | undefined = undefined;
    try {
      record = await this.installRepository.findByShortcutId(activeContext.shortcutId);
    } catch (_error) {
      return this.snapshot(normalizedWindowId);
    }
    const latestSnapshot = this.snapshot(normalizedWindowId);
    if (!this.isCurrentRequest(normalizedWindowId, generation) ||
      latestSnapshot.activeContext?.shortcutId !== activeContext.shortcutId) {
      return latestSnapshot;
    }
    return this.commitSnapshot(
      normalizedWindowId,
      latestSnapshot.activeContext,
      record?.settings.defaultFullscreen === true
    );
  }

  getActive(windowId: string): WebAppActiveContext | undefined {
    return this.snapshot(windowId).activeContext;
  }

  isImmersive(snapshot: WebAppSessionSnapshot, input: WebAppImmersiveModeInput): boolean {
    return snapshot.activeContext !== undefined &&
      !input.showHomePage &&
      !input.showTabsSheet;
  }

  buildImmersiveVisualState(
    snapshot: WebAppSessionSnapshot,
    input: WebAppImmersiveVisualStateInput
  ): WebAppImmersiveVisualState {
    const immersive = this.isImmersive(snapshot, input) && input.webPageVisible;
    const hideTopSafeArea = immersive && snapshot.defaultFullscreen;
    return {
      immersive: immersive,
      hideTopSafeArea: hideTopSafeArea,
      hideBottomChrome: immersive,
      restoreTopSafeArea: !hideTopSafeArea && input.webPageVisible &&
        !input.fullScreenModeEnabled &&
        !input.globalImmersionEnabled
    };
  }

  clear(windowId: string): WebAppSessionSnapshot {
    const normalizedWindowId = this.normalizeWindowId(windowId);
    this.advanceRequestGeneration(normalizedWindowId);
    return this.commitSnapshot(normalizedWindowId, undefined, false);
  }

  clearAll(): void {
    this.snapshotsByWindowId = {};
    this.requestGenerationByWindowId = {};
  }

  private buildActiveContext(
    payload: BrowserLaunchPayload,
    shortcut: BrowserLaunchShortcutContext,
    windowId: string,
    record: DesktopWebEntryRecord | undefined
  ): WebAppActiveContext {
    const context: WebAppActiveContext = {
      shortcutId: shortcut.shortcutId,
      windowId: windowId,
      launchUrl: record?.launchUrl ?? payload.uri,
      origin: shortcut.origin.length > 0 ? shortcut.origin : (record?.origin ?? ''),
      scope: shortcut.scope.length > 0 ? shortcut.scope : (record?.scope ?? ''),
      manifestUrl: shortcut.manifestUrl.length > 0 ? shortcut.manifestUrl : (record?.manifestUrl ?? ''),
      themeColor: shortcut.themeColor.length > 0 ? shortcut.themeColor : (record?.themeColor ?? ''),
      title: record?.title ?? '',
      iconPath: record?.iconPath ?? '',
      createdAt: shortcut.createdAt !== 0 ? shortcut.createdAt : (record?.createdAt ?? Date.now()),
      startedAt: Date.now()
    };
    return context;
  }

  private commitSnapshot(
    windowId: string,
    activeContext: WebAppActiveContext | undefined,
    defaultFullscreen: boolean
  ): WebAppSessionSnapshot {
    const snapshot = new WebAppSessionSnapshot(windowId, activeContext, defaultFullscreen);
    this.snapshotsByWindowId[windowId] = snapshot;
    return snapshot;
  }

  private advanceRequestGeneration(windowId: string): number {
    const next = (this.requestGenerationByWindowId[windowId] ?? 0) + 1;
    this.requestGenerationByWindowId[windowId] = next;
    return next;
  }

  private isCurrentRequest(windowId: string, generation: number): boolean {
    return this.requestGenerationByWindowId[windowId] === generation;
  }

  private normalizeWindowId(windowId: string): string {
    const normalized = windowId.trim();
    return normalized.length > 0 ? normalized : DEFAULT_WEB_APP_WINDOW_ID;
  }
}

export const sharedWebAppSessionCoordinator: WebAppSessionCoordinator = new WebAppSessionCoordinator();
