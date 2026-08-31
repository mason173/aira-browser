import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserTabPreviewCaptureService,
  BrowserTabPreviewWebViewportSize,
  buildBrowserTabPreviewComponentSnapshotId,
  buildBrowserTabPreviewVisibleSnapshotId,
  buildBrowserTabPreviewVisibleSurfaceSnapshotId,
  buildBrowserTabWebComponentSnapshotId
} from '../../services/web/BrowserTabPreviewCaptureService';
import {
  BrowserTabPreviewCachedImageInfo,
  BrowserTabPreviewPersistedImageStats,
  BrowserTabPreviewCacheRestorePathIndex,
  DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID,
  BrowserTabPreviewCacheStore
} from '../../services/web/BrowserTabPreviewCacheStore';
import {
  BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
  BROWSER_TAB_PREVIEW_PIXEL_WIDTH
} from './BrowserTabPreviewMetrics';
import {
  BrowserTabPreviewCaptureSource,
  BrowserTabPreviewSourceRect,
  BrowserTabPreviewTransitionSource
} from '../../services/web/BrowserTabPreviewTypes';
import {
  BrowserTabPreviewTransitionImageKind,
  sharedBrowserTabPreviewMetrics
} from './BrowserTabPreviewMetricsService';
import { BrowserTabPreviewDebugExportSnapshot } from '../../services/web/BrowserTabPreviewDebugExportService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';

const MIN_PASSIVE_PREVIEW_CAPTURE_INTERVAL_MS: number = 1100;
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TabPreviewCoordinator';
export const BROWSER_TAB_PREVIEW_FAILURE_NO_CAPTURE_REQUEST: string = 'capture-request-unavailable';
export const BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE: string = 'preview-cache-missing';

export interface BrowserTabPreviewState {
  tabId: string;
  sharedSnapshotImageUri?: string;
  sharedSnapshotImageWidth?: number;
  sharedSnapshotImageHeight?: number;
  sharedSnapshotPixelMap?: image.PixelMap;
  transitionReady?: boolean;
  transitionCapturedAt?: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
  lockedForTransition?: boolean;
  favicon?: image.PixelMap;
  faviconRevision?: number;
  capturedAt: number;
  failureReason?: string;
  captureSource?: string;
}

export interface BrowserTabPreviewCaptureRequest {
  tab: BrowserTabState;
  controller: webview.WebviewController;
  uiContext?: UIContext;
  componentSnapshotId?: string;
  webComponentSnapshotId?: string;
  componentSnapshotOnly?: boolean;
  captureVisibleTabSurface?: boolean;
  hasLiveController?: boolean;
  hasRenderableSurface?: boolean;
  allowWindowSnapshot?: boolean;
  allowSurfaceSnapshot?: boolean;
  preferVisibleSnapshot?: boolean;
  requireSharedSnapshot?: boolean;
  visibleSnapshotTopCropPx?: number;
  allowWhileLocked?: boolean;
  force?: boolean;
}

export interface BrowserTabPreviewCaptureRequestBuildInput {
  tab?: BrowserTabState;
  controller?: webview.WebviewController;
  uiContext?: UIContext;
  activeTabId: string;
  showTabsSheet: boolean;
  showHomePage: boolean;
  suspendHostedWebSurface: boolean;
  force?: boolean;
  requireSharedSnapshot?: boolean;
  hostedControllerAttached: boolean;
  activeControllerAttached: boolean;
  backgroundHot: boolean;
  shouldCaptureNativeErrorSurface: boolean;
  hasLiveController: boolean;
  componentSnapshotOnly?: boolean;
  // Capture the visible shell surface (web page PLUS top chrome: omnibox/tab
  // strip) instead of the bare web component. Used by leave-captures so their
  // thumbnails match what the open-overview capture produces.
  captureVisibleTabSurface?: boolean;
}

export interface BrowserTabPreviewSurfaceHost {
  isHostedControllerAttached: (tabId: string) => boolean;
  isBackgroundHot: (tabId: string) => boolean;
  // Real web viewport (vp) as measured by the shell; feeds webPageSnapshot so
  // the engine never re-lays pages out at the phone-probe size on large screen.
  resolveWebViewportSnapshotSize: () => BrowserTabPreviewWebViewportSize;
}

export interface BrowserTabPreviewCaptureShellInput {
  tab?: BrowserTabState;
  tabId: string;
  uiContext?: UIContext;
  activeTabId: string;
  showTabsSheet: boolean;
  showHomePage: boolean;
  suspendHostedWebSurface: boolean;
  activeControllerAttached: boolean;
  activeErrorSurfaceVisible: boolean;
  requireSharedSnapshot?: boolean;
  force?: boolean;
  componentSnapshotOnly?: boolean;
  captureVisibleTabSurface?: boolean;
}

interface BrowserTabPreviewCacheEntry extends BrowserTabPreviewState {
  signature: string;
  lastKnownGoodSignature: string;
  lockedForTransition: boolean;
}

interface BrowserTabSnapshotReadiness {
  ready: boolean;
  reason: string;
}

interface BrowserTabPreviewImageSize {
  width: number;
  height: number;
}

interface BrowserTabPreviewBackgroundPersistContext {
  runId: number;
  signature: string;
  capturedAt: number;
  imageWidth: number;
  imageHeight: number;
  transitionSource?: BrowserTabPreviewTransitionSource;
}

export interface BrowserTabPreviewHydrateOptions {
  batchSize?: number;
  batchDelayMs?: number;
  notifyBatchChanged?: () => void;
}

export class BrowserTabPreviewCoordinator {
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly surfaceHost: BrowserTabPreviewSurfaceHost;
  private captureService: BrowserTabPreviewCaptureService = new BrowserTabPreviewCaptureService();
  private cacheStore: BrowserTabPreviewCacheStore = new BrowserTabPreviewCacheStore();
  private previewEntries: Record<string, BrowserTabPreviewCacheEntry | undefined> = {};
  private activeCaptureTasks: Record<string, Promise<boolean> | undefined> = {};
  private activeCaptureRunIds: Record<string, number | undefined> = {};
  private nextCaptureRunId: number = 0;
  private transitionLockedTabIds: Record<string, boolean | undefined> = {};
  private tabPrivacyBoundaries: Record<string, boolean | undefined> = {};
  private activeCaptureTimeout: number = -1;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private cacheScopeId: string = DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;

  constructor(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    surfaceHost: BrowserTabPreviewSurfaceHost
  ) {
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.surfaceHost = surfaceHost;
  }

  setCacheScopeId(scopeId: string): void {
    const normalizedScopeId = scopeId.trim();
    this.cacheScopeId = normalizedScopeId.length > 0 ? normalizedScopeId : DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;
    this.cacheStore.setScopeId(this.cacheScopeId);
    this.captureService.setCacheScopeId(this.cacheScopeId);
  }

  listPreviewStates(tabs: BrowserTabState[]): BrowserTabPreviewState[] {
    return tabs
      .map((tab: BrowserTabState) => this.getPreviewState(tab.id))
      .filter((item?: BrowserTabPreviewState) => item !== undefined) as BrowserTabPreviewState[];
  }

  getPreviewState(tabId: string): BrowserTabPreviewState | undefined {
    const entry = this.previewEntries[tabId];
    if (entry === undefined) {
      return undefined;
    }
    return this.buildPreviewState(entry, this.isTransitionSnapshotReady(entry));
  }

  buildCaptureRequestFromShellState(
    input: BrowserTabPreviewCaptureShellInput
  ): BrowserTabPreviewCaptureRequest | undefined {
    const tabId = input.tabId;
    const shouldCaptureNativeErrorSurface = tabId === input.activeTabId &&
      input.activeErrorSurfaceVisible &&
      !input.showTabsSheet;
    return this.buildCaptureRequest({
      tab: input.tab,
      controller: this.runtimeLifecyclePort.resolveController(tabId),
      uiContext: input.uiContext,
      activeTabId: input.activeTabId,
      showTabsSheet: input.showTabsSheet,
      showHomePage: input.showHomePage,
      suspendHostedWebSurface: input.suspendHostedWebSurface,
      hostedControllerAttached: this.surfaceHost.isHostedControllerAttached(tabId),
      activeControllerAttached: input.activeControllerAttached,
      backgroundHot: this.surfaceHost.isBackgroundHot(tabId),
      shouldCaptureNativeErrorSurface: shouldCaptureNativeErrorSurface,
      hasLiveController: this.runtimeLifecyclePort.hasLiveRuntimeController(tabId),
      requireSharedSnapshot: input.requireSharedSnapshot,
      force: input.force,
      componentSnapshotOnly: input.componentSnapshotOnly,
      captureVisibleTabSurface: input.captureVisibleTabSurface
    });
  }

  buildCaptureRequest(input: BrowserTabPreviewCaptureRequestBuildInput): BrowserTabPreviewCaptureRequest | undefined {
    const tab = input.tab;
    if (tab === undefined || tab.isHome || input.controller === undefined) {
      return undefined;
    }
    const isActiveTab = tab.id === input.activeTabId;
    const backgroundHotPreviewTab = input.backgroundHot && input.hostedControllerAttached;
    const hasRenderableSurface = input.shouldCaptureNativeErrorSurface || (isActiveTab &&
      (input.hostedControllerAttached || input.activeControllerAttached)) ||
      backgroundHotPreviewTab;
    const shouldUseVisibleCaptureFallbacks = isActiveTab && !input.showTabsSheet;
    const force = input.force === true;
    return {
      tab: tab,
      controller: input.controller,
      uiContext: input.uiContext,
      componentSnapshotId: this.resolveCaptureComponentSnapshotId(tab.id, input),
      webComponentSnapshotId: buildBrowserTabWebComponentSnapshotId(tab.id),
      componentSnapshotOnly: input.componentSnapshotOnly === true,
      captureVisibleTabSurface: input.captureVisibleTabSurface === true,
      hasLiveController: input.hasLiveController,
      hasRenderableSurface: hasRenderableSurface,
      allowWindowSnapshot: shouldUseVisibleCaptureFallbacks,
      allowSurfaceSnapshot: shouldUseVisibleCaptureFallbacks,
      preferVisibleSnapshot: input.shouldCaptureNativeErrorSurface || (force && shouldUseVisibleCaptureFallbacks),
      requireSharedSnapshot: input.requireSharedSnapshot === true,
      visibleSnapshotTopCropPx: 0,
      allowWhileLocked: force && isActiveTab,
      force: force
    };
  }

  private resolveCaptureComponentSnapshotId(
    tabId: string,
    input: BrowserTabPreviewCaptureRequestBuildInput
  ): string {
    if (input.shouldCaptureNativeErrorSurface) {
      return buildBrowserTabPreviewVisibleSnapshotId(tabId);
    }
    // Leave-captures ask for the visible shell surface (page + top chrome) so
    // the thumbnail matches the open-overview capture. Only valid while this
    // tab is still the active, visible one — that node id is bound to the
    // active tab; otherwise fall back to the bare page component.
    if (input.captureVisibleTabSurface === true && tabId === input.activeTabId &&
      !input.showHomePage && !input.showTabsSheet) {
      return buildBrowserTabPreviewVisibleSurfaceSnapshotId(tabId);
    }
    return buildBrowserTabPreviewComponentSnapshotId(tabId);
  }

  getTransitionSnapshotState(tabId: string): BrowserTabPreviewState | undefined {
    const entry = this.previewEntries[tabId];
    if (entry === undefined || !this.isTransitionSnapshotReady(entry)) {
      return undefined;
    }
    return this.buildPreviewState(entry, true);
  }

  getSharedSnapshotState(tabId: string): BrowserTabPreviewState | undefined {
    const entry = this.previewEntries[tabId];
    if (entry === undefined || !this.hasPreview(entry)) {
      return undefined;
    }
    return this.buildPreviewState(entry, this.isTransitionSnapshotReady(entry));
  }

  private buildPreviewState(entry: BrowserTabPreviewCacheEntry, transitionReady: boolean): BrowserTabPreviewState {
    return {
      tabId: entry.tabId,
      sharedSnapshotImageUri: entry.sharedSnapshotImageUri,
      sharedSnapshotImageWidth: entry.sharedSnapshotImageWidth,
      sharedSnapshotImageHeight: entry.sharedSnapshotImageHeight,
      sharedSnapshotPixelMap: entry.sharedSnapshotPixelMap,
      favicon: entry.favicon,
      faviconRevision: entry.faviconRevision,
      capturedAt: entry.capturedAt,
      failureReason: entry.failureReason,
      captureSource: entry.captureSource,
      transitionReady: transitionReady,
      transitionCapturedAt: entry.transitionCapturedAt,
      transitionSource: entry.transitionSource,
      lockedForTransition: entry.lockedForTransition
    };
  }

  async hydratePersistedPreviews(
    tabs: BrowserTabState[],
    options?: BrowserTabPreviewHydrateOptions
  ): Promise<boolean> {
    let changed = false;
    const batchSize = Math.max(0, Math.floor(options?.batchSize ?? 0));
    const batchDelayMs = Math.max(0, Math.floor(options?.batchDelayMs ?? 0));
    const hydratableTabs = this.collectHydratableTabs(tabs);
    if (hydratableTabs.length <= 0) {
      return false;
    }
    const resolvedBatchSize = batchSize > 0 ? batchSize : Math.max(1, hydratableTabs.length);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'persisted preview hydrate plan tabs=%{public}d batch=%{public}d delayMs=%{public}d',
      hydratableTabs.length, resolvedBatchSize, batchDelayMs);
    const restorePathIndex = await this.cacheStore.buildSharedSnapshotRestorePathIndex(
      this.collectHydratableTabIds(hydratableTabs)
    );
    for (let startIndex = 0; startIndex < hydratableTabs.length; startIndex += resolvedBatchSize) {
      const endIndex = Math.min(hydratableTabs.length, startIndex + resolvedBatchSize);
      const batchTabs = hydratableTabs.slice(startIndex, endIndex);
      const batchChanged = await this.hydratePersistedPreviewBatch(batchTabs, restorePathIndex);
      if (batchChanged) {
        changed = true;
        options?.notifyBatchChanged?.();
      }
      if (endIndex < hydratableTabs.length) {
        await this.waitForHydrateBatchDelay(batchDelayMs);
      }
    }
    const stats = await this.cacheStore.captureCacheDirectoryStats();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'persisted preview hydrate done tabs=%{public}d changed=%{public}s sharedFiles=%{public}d sharedBytes=%{public}d',
      hydratableTabs.length, `${changed}`, stats.sharedFiles, stats.sharedBytes);
    return changed;
  }

  private async hydratePersistedPreviewBatch(
    tabs: BrowserTabState[],
    restorePathIndex: BrowserTabPreviewCacheRestorePathIndex
  ): Promise<boolean> {
    let changed = false;
    const restoreIndex = await this.cacheStore.readSharedSnapshotRestoreIndex(restorePathIndex,
      this.collectHydratableTabIds(tabs));
    for (let index = 0; index < tabs.length; index += 1) {
      const tab = tabs[index];
      if (this.hydratePersistedPreviewForTab(tab, restoreIndex.infosByTabId[tab.id])) {
        changed = true;
      }
    }
    return changed;
  }

  private hydratePersistedPreviewForTab(
    tab: BrowserTabState,
    sharedSnapshotImageInfo?: BrowserTabPreviewCachedImageInfo
  ): boolean {
    this.tabPrivacyBoundaries[tab.id] = this.isSessionEphemeralTab(tab);
    const existing = this.previewEntries[tab.id];
    const transitionImageUri = sharedSnapshotImageInfo?.uri ?? '';
    if (this.hasPreview(existing)) {
      return this.reconcilePersistedPreview(tab, existing as BrowserTabPreviewCacheEntry, sharedSnapshotImageInfo);
    }
    if (transitionImageUri.length <= 0) {
      if (existing === undefined) {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'persisted preview hydrate miss tab=%{public}s reason=%{public}s',
          tab.id, BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE);
        this.updateFailure(tab.id, BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE);
        return true;
      }
      return false;
    }
    const signature = this.buildSignature(tab);
    const restoredTransitionSource = this.resolveRestoredTransitionSource(sharedSnapshotImageInfo);
    this.previewEntries[tab.id] = {
      tabId: tab.id,
      sharedSnapshotImageUri: transitionImageUri,
      sharedSnapshotImageWidth: sharedSnapshotImageInfo?.width ?? existing?.sharedSnapshotImageWidth ??
        BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
      sharedSnapshotImageHeight: sharedSnapshotImageInfo?.height ?? existing?.sharedSnapshotImageHeight ??
        BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
      sharedSnapshotPixelMap: existing?.sharedSnapshotPixelMap,
      transitionReady: restoredTransitionSource !== undefined,
      transitionCapturedAt: existing?.transitionCapturedAt ?? Date.now(),
      transitionSource: restoredTransitionSource,
      lockedForTransition: this.isTransitionLocked(tab.id),
      favicon: existing?.favicon,
      faviconRevision: existing?.faviconRevision,
      capturedAt: existing?.capturedAt ?? Date.now(),
      signature: '',
      lastKnownGoodSignature: signature,
      failureReason: existing?.failureReason ?? '',
      captureSource: existing?.captureSource ?? 'persisted'
    };
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'persisted preview hydrated tab=%{public}s uri=%{public}s source=%{public}s',
      tab.id, transitionImageUri,
      this.previewEntries[tab.id]?.transitionSource?.captureSource ?? 'untyped');
    return true;
  }

  private collectHydratableTabs(tabs: BrowserTabState[]): BrowserTabState[] {
    const hydratableTabs: BrowserTabState[] = [];
    tabs.forEach((tab: BrowserTabState) => {
      if (tab.id.trim().length > 0 && !tab.isHome) {
        hydratableTabs.push(tab);
      }
    });
    return hydratableTabs;
  }

  private collectHydratableTabIds(tabs: BrowserTabState[]): string[] {
    const tabIds: string[] = [];
    tabs.forEach((tab: BrowserTabState) => {
      if (tab.id.trim().length > 0 && !tab.isHome) {
        tabIds.push(tab.id);
      }
    });
    return tabIds;
  }

  private async waitForHydrateBatchDelay(delayMs: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }

  private reconcilePersistedPreview(
    tab: BrowserTabState,
    existing: BrowserTabPreviewCacheEntry,
    sharedSnapshotImageInfo?: BrowserTabPreviewCachedImageInfo
  ): boolean {
    const existingUri = existing.sharedSnapshotImageUri?.trim() ?? '';
    const restoredUri = sharedSnapshotImageInfo?.uri ?? '';
    if (existingUri.length <= 0) {
      return false;
    }
    if (restoredUri.length > 0) {
      const restoredTransitionSource = this.resolveRestoredTransitionSource(sharedSnapshotImageInfo);
      const restoredMatchesExisting = restoredUri === existingUri &&
        sharedSnapshotImageInfo?.width === existing.sharedSnapshotImageWidth &&
        sharedSnapshotImageInfo?.height === existing.sharedSnapshotImageHeight &&
        this.areTransitionSourcesEqual(restoredTransitionSource, existing.transitionSource);
      if (restoredMatchesExisting) {
        return false;
      }
      // The restore path index may predate a capture completed during hydration. Once the
      // in-memory asset is transition-ready, keep its image and semantics as one generation.
      if (this.isTransitionSnapshotReady(existing)) {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          '[THUMB-DIAG] preview-restore-ignored tab=%{public}s currentSource=%{public}s restoredSource=%{public}s reason=%{public}s',
          tab.id,
          `${existing.transitionSource?.captureSource ?? 'untyped'}`,
          `${restoredTransitionSource?.captureSource ?? 'untyped'}`,
          'live-transition-authoritative');
        return false;
      }
      hilog.info(LOG_DOMAIN, LOG_TAG,
        '[THUMB-DIAG] preview-restored tab=%{public}s size=%{public}s source=%{public}s',
        tab.id,
        `${sharedSnapshotImageInfo?.width ?? existing.sharedSnapshotImageWidth}x${sharedSnapshotImageInfo?.height ?? existing.sharedSnapshotImageHeight}`,
        `${restoredTransitionSource?.captureSource ?? 'untyped'}`);
      this.previewEntries[tab.id] = this.copyEntry(existing, {
        sharedSnapshotImageUri: restoredUri,
        sharedSnapshotImageWidth: sharedSnapshotImageInfo?.width ?? existing.sharedSnapshotImageWidth,
        sharedSnapshotImageHeight: sharedSnapshotImageInfo?.height ?? existing.sharedSnapshotImageHeight,
        transitionReady: restoredTransitionSource !== undefined,
        transitionCapturedAt: existing.transitionCapturedAt ?? Date.now(),
        transitionSource: restoredTransitionSource,
        lastKnownGoodSignature: this.buildSignature(tab),
        failureReason: ''
      });
      return true;
    }
    if (existing.sharedSnapshotPixelMap !== undefined) {
      return false;
    }
    if (existingUri.length > 0) {
      if (existing.failureReason === BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE) {
        return false;
      }
      this.previewEntries[tab.id] = this.copyEntry(existing, {
        transitionReady: this.isTransitionSnapshotReady(existing),
        failureReason: BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE
      });
      return true;
    }
    if (existing.failureReason === BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE &&
      existing.sharedSnapshotImageWidth === BROWSER_TAB_PREVIEW_PIXEL_WIDTH &&
      existing.sharedSnapshotImageHeight === BROWSER_TAB_PREVIEW_PIXEL_HEIGHT &&
      existing.transitionReady === false) {
      return false;
    }
    this.previewEntries[tab.id] = this.copyEntry(existing, {
      sharedSnapshotImageUri: '',
      sharedSnapshotImageWidth: BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
      sharedSnapshotImageHeight: BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
      transitionReady: false,
      failureReason: BROWSER_TAB_PREVIEW_FAILURE_NO_PERSISTED_IMAGE
    });
    return true;
  }

  async capturePreview(request: BrowserTabPreviewCaptureRequest): Promise<boolean> {
    this.tabPrivacyBoundaries[request.tab.id] = this.isSessionEphemeralTab(request.tab);
    if (request.force !== true) {
      const activeCaptureResult = await this.waitForActiveCapture(request.tab.id);
      if (activeCaptureResult !== undefined) {
        return activeCaptureResult;
      }
    }
    const blockedReason = this.resolveCaptureReadiness(request).reason;
    if (blockedReason.length > 0) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'capture skipped tab=%{public}s reason=%{public}s home=%{public}s private=%{public}s live=%{public}s surface=%{public}s',
        request.tab.id,
        blockedReason,
        `${request.tab.isHome}`,
        `${this.isSessionEphemeralTab(request.tab)}`,
        `${request.hasLiveController === true}`,
        `${request.hasRenderableSurface === true}`);
      this.updateFailure(request.tab.id, blockedReason);
      return false;
    }

    const existing = this.previewEntries[request.tab.id];
    const signature = this.buildSignature(request.tab);
    const now = Date.now();
    if (!request.force && this.hasPreview(existing) && existing?.signature === signature &&
      now - existing.capturedAt < MIN_PASSIVE_PREVIEW_CAPTURE_INTERVAL_MS) {
      return false;
    }

    const runId = this.createCaptureRunId(request.tab.id);
    const captureTask = this.captureAndStorePreview(request, existing, signature, runId);
    this.activeCaptureTasks[request.tab.id] = captureTask;
    try {
      return await captureTask;
    } finally {
      if (this.activeCaptureTasks[request.tab.id] === captureTask) {
        this.activeCaptureTasks[request.tab.id] = undefined;
      }
    }
  }

  async persistImmediateSharedSnapshot(
    tab: BrowserTabState,
    pixelMap: image.PixelMap,
    transitionSource: BrowserTabPreviewTransitionSource
  ): Promise<boolean> {
    if (tab.id.trim().length === 0 || tab.isHome) {
      return false;
    }
    this.tabPrivacyBoundaries[tab.id] = this.isSessionEphemeralTab(tab);
    const existing = this.previewEntries[tab.id];
    const normalizedTransitionSource = this.normalizeTransitionSource(transitionSource);
    if (normalizedTransitionSource === undefined) {
      this.updateFailure(tab.id, 'shared-transition-source-invalid');
      return false;
    }
    const source = normalizedTransitionSource.captureSource;
    const result = await this.cacheStore.savePreviewImageWithStats(
      pixelMap,
      `${tab.id}-shared`,
      normalizedTransitionSource
    );
    const sharedUri = result.uri?.trim() ?? '';
    if (sharedUri.length <= 0) {
      this.updateFailure(tab.id, `${source}-shared-persist-failed`);
      return false;
    }
    const now = Date.now();
    const imageSize = this.resolvePixelMapSize(pixelMap);
    this.previewEntries[tab.id] = {
      tabId: tab.id,
      sharedSnapshotImageUri: sharedUri,
      sharedSnapshotImageWidth: imageSize.width,
      sharedSnapshotImageHeight: imageSize.height,
      sharedSnapshotPixelMap: undefined,
      transitionReady: true,
      transitionCapturedAt: now,
      transitionSource: normalizedTransitionSource,
      lockedForTransition: this.isTransitionLocked(tab.id),
      favicon: existing?.favicon,
      faviconRevision: existing?.faviconRevision,
      capturedAt: now,
      signature: this.buildSignature(tab),
      lastKnownGoodSignature: this.buildSignature(tab),
      failureReason: '',
      captureSource: source
    };
    this.captureCacheDirectoryStatsInBackground();
    return true;
  }

  async seedSharedSnapshotFromTab(
    sourceTab: BrowserTabState | undefined,
    targetTab: BrowserTabState | undefined,
    source: BrowserTabPreviewCaptureSource
  ): Promise<boolean> {
    if (sourceTab === undefined || targetTab === undefined ||
      sourceTab.id.trim().length === 0 || targetTab.id.trim().length === 0 ||
      sourceTab.id === targetTab.id || sourceTab.isHome || targetTab.isHome) {
      return false;
    }
    if (sourceTab.profileId !== targetTab.profileId ||
      sourceTab.privacyMode !== targetTab.privacyMode ||
      sourceTab.dataScope !== targetTab.dataScope ||
      this.isSessionEphemeralTab(sourceTab) || this.isSessionEphemeralTab(targetTab)) {
      return false;
    }
    const sourceEntry = this.previewEntries[sourceTab.id];
    const sourceTransition = this.normalizeTransitionSource(sourceEntry?.transitionSource);
    if (!this.hasPreview(sourceEntry) || sourceTransition === undefined) {
      return false;
    }
    if (sourceEntry?.sharedSnapshotPixelMap !== undefined) {
      return await this.persistImmediateSharedSnapshot(
        targetTab,
        sourceEntry.sharedSnapshotPixelMap,
        sourceTransition
      );
    }
    const sourceUri = sourceEntry?.sharedSnapshotImageUri?.trim() ?? '';
    if (sourceUri.length <= 0) {
      return false;
    }
    const duplicatedImageInfo = await this.cacheStore.duplicateSharedSnapshotImage(
      sourceTab.id,
      targetTab.id,
      sourceTransition
    );
    if (duplicatedImageInfo === undefined) {
      return false;
    }
    const existing = this.previewEntries[targetTab.id];
    if (existing?.sharedSnapshotPixelMap !== undefined) {
      void this.releaseCachedPixelMap(existing.sharedSnapshotPixelMap, targetTab.id,
        existing.captureSource ?? 'seed-replaced-memory');
    }
    const now = Date.now();
    const signature = this.buildSignature(targetTab);
    this.tabPrivacyBoundaries[targetTab.id] = this.isSessionEphemeralTab(targetTab);
    this.previewEntries[targetTab.id] = {
      tabId: targetTab.id,
      sharedSnapshotImageUri: duplicatedImageInfo.uri,
      sharedSnapshotImageWidth: duplicatedImageInfo.width,
      sharedSnapshotImageHeight: duplicatedImageInfo.height,
      sharedSnapshotPixelMap: undefined,
      transitionReady: true,
      transitionCapturedAt: now,
      transitionSource: duplicatedImageInfo.transitionSource,
      lockedForTransition: this.isTransitionLocked(targetTab.id),
      favicon: existing?.favicon,
      faviconRevision: existing?.faviconRevision,
      capturedAt: now,
      signature: signature,
      lastKnownGoodSignature: signature,
      failureReason: '',
      captureSource: source
    };
    return true;
  }

  hasSharedSnapshot(tabId: string): boolean {
    const state = this.getTransitionSnapshotState(tabId);
    return state !== undefined;
  }

  hasFreshSharedSnapshot(tabId: string): boolean {
    const entry = this.previewEntries[tabId];
    return this.isTransitionSnapshotReady(entry);
  }

  hasFreshDistinctSharedSnapshot(tabId: string): boolean {
    const entry = this.previewEntries[tabId];
    return this.hasDistinctSharedSnapshot(tabId) &&
      this.isTransitionSnapshotReady(entry);
  }

  hasUsableSharedSnapshot(tabId: string): boolean {
    return this.isTransitionSnapshotReady(this.previewEntries[tabId]);
  }

  hasDistinctSharedSnapshot(tabId: string): boolean {
    const state = this.getTransitionSnapshotState(tabId);
    if (state === undefined) {
      return false;
    }
    const sharedUri = state.sharedSnapshotImageUri?.trim() ?? '';
    return sharedUri.length > 0;
  }

  getDebugSnapshotExportCandidate(tabId: string): BrowserTabPreviewDebugExportSnapshot | undefined {
    const state = this.getTransitionSnapshotState(tabId);
    if (state === undefined) {
      return undefined;
    }
    const sharedImageUri = state.sharedSnapshotImageUri?.trim() ?? '';
    if (sharedImageUri.length > 0) {
      return {
        tabId: tabId,
        uri: sharedImageUri,
        kind: 'shared',
        width: Math.max(1, Math.floor(state.sharedSnapshotImageWidth ?? BROWSER_TAB_PREVIEW_PIXEL_WIDTH)),
        height: Math.max(1, Math.floor(state.sharedSnapshotImageHeight ?? BROWSER_TAB_PREVIEW_PIXEL_HEIGHT)),
        capturedAt: state.transitionCapturedAt ?? state.capturedAt,
        source: state.transitionSource?.captureSource ?? state.captureSource ?? ''
      };
    }
    return undefined;
  }

  isCapturing(tabId: string): boolean {
    return this.activeCaptureTasks[tabId] !== undefined;
  }

  lockTransitionSnapshot(tabId: string): void {
    if (tabId.trim().length <= 0) {
      return;
    }
    this.transitionLockedTabIds[tabId] = true;
    const current = this.previewEntries[tabId];
    if (current === undefined) {
      return;
    }
    this.previewEntries[tabId] = this.copyEntry(current, {
      lockedForTransition: true
    });
  }

  unlockTransitionSnapshot(tabId: string): void {
    if (tabId.trim().length <= 0) {
      return;
    }
    this.transitionLockedTabIds[tabId] = undefined;
    const current = this.previewEntries[tabId];
    if (current === undefined) {
      return;
    }
    this.previewEntries[tabId] = this.copyEntry(current, {
      lockedForTransition: false
    });
  }

  scheduleActiveCapture(
    delayMs: number,
    requestProvider: () => BrowserTabPreviewCaptureRequest | undefined,
    onUpdated: () => void
  ): void {
    this.cancelScheduledCapture();
    if (delayMs <= 0) {
      void this.runScheduledCapture(requestProvider, onUpdated);
      return;
    }

    this.activeCaptureTimeout = setTimeout(() => {
      this.activeCaptureTimeout = -1;
      void this.runScheduledCapture(requestProvider, onUpdated);
    }, delayMs);
  }

  cancelScheduledCapture(): void {
    if (this.activeCaptureTimeout >= 0) {
      clearTimeout(this.activeCaptureTimeout);
      this.activeCaptureTimeout = -1;
    }
  }

  updateFavicon(tabId: string, favicon: image.PixelMap): boolean {
    if (tabId.trim().length === 0) {
      return false;
    }
    const current = this.previewEntries[tabId];
    if (current === undefined) {
      return false;
    }
    this.previewEntries[tabId] = {
      tabId: tabId,
      sharedSnapshotImageUri: current?.sharedSnapshotImageUri,
      sharedSnapshotImageWidth: current?.sharedSnapshotImageWidth,
      sharedSnapshotImageHeight: current?.sharedSnapshotImageHeight,
      sharedSnapshotPixelMap: current?.sharedSnapshotPixelMap,
      transitionReady: this.isTransitionSnapshotReady(current),
      transitionCapturedAt: current?.transitionCapturedAt,
      transitionSource: current?.transitionSource,
      lockedForTransition: this.isTransitionLocked(tabId),
      favicon: favicon,
      faviconRevision: Math.max(1, Math.floor(current.faviconRevision ?? 0) + 1),
      capturedAt: current?.capturedAt ?? 0,
      signature: current?.signature ?? '',
      lastKnownGoodSignature: current?.lastKnownGoodSignature ?? '',
      failureReason: current?.failureReason,
      captureSource: current?.captureSource
    };
    return true;
  }

  async removeTab(tabId: string): Promise<boolean> {
    this.transitionLockedTabIds[tabId] = undefined;
    this.tabPrivacyBoundaries[tabId] = undefined;
    this.activeCaptureRunIds[tabId] = undefined;
    const removedPersisted = await this.cacheStore.removePreviewImage(tabId);
    const current = this.previewEntries[tabId];
    if (current === undefined) {
      return removedPersisted;
    }
    if (current.sharedSnapshotPixelMap !== undefined) {
      await this.releaseCachedPixelMap(current.sharedSnapshotPixelMap, tabId, current.captureSource ?? 'memory');
    }
    this.previewEntries[tabId] = undefined;
    return true;
  }

  async removeSessionEphemeralPreviews(tabIds: string[]): Promise<boolean> {
    let changed = false;
    for (let index = 0; index < tabIds.length; index += 1) {
      const tabId = tabIds[index].trim();
      if (tabId.length <= 0) {
        continue;
      }
      this.tabPrivacyBoundaries[tabId] = true;
      if (await this.removePrivatePreviewCache(tabId)) {
        changed = true;
      }
    }
    return changed;
  }

  async clearAll(): Promise<boolean> {
    this.transitionLockedTabIds = {};
    this.tabPrivacyBoundaries = {};
    this.activeCaptureRunIds = {};
    const removedPersisted = await this.cacheStore.clearAllPreviewImages();
    const changed = Object.keys(this.previewEntries).length > 0;
    Object.keys(this.previewEntries).forEach((tabId: string) => {
      const current = this.previewEntries[tabId];
      if (current?.sharedSnapshotPixelMap !== undefined) {
        void this.releaseCachedPixelMap(current.sharedSnapshotPixelMap, tabId, current.captureSource ?? 'memory');
      }
    });
    this.previewEntries = {};
    return changed || removedPersisted;
  }

  syncTabs(tabs: BrowserTabState[]): boolean {
    const activeIds: Record<string, boolean> = {};
    let changed = false;
    tabs.forEach((tab: BrowserTabState) => {
      activeIds[tab.id] = true;
      this.tabPrivacyBoundaries[tab.id] = this.isSessionEphemeralTab(tab);
    });
    const removedEntryIds = Object.keys(this.previewEntries).filter((tabId: string) => activeIds[tabId] !== true);
    const homeTabIds = tabs
      .filter((tab: BrowserTabState) => tab.isHome)
      .map((tab: BrowserTabState) => tab.id);
    const nextEntries: Record<string, BrowserTabPreviewCacheEntry | undefined> = {};
    Object.keys(this.previewEntries).forEach((tabId: string) => {
      if (activeIds[tabId] === true) {
        if (homeTabIds.includes(tabId)) {
          changed = true;
          const current = this.previewEntries[tabId];
          if (current?.sharedSnapshotPixelMap !== undefined) {
            void this.releaseCachedPixelMap(current.sharedSnapshotPixelMap, tabId, current.captureSource ?? 'memory');
          }
          void this.cacheStore.removePreviewImage(tabId);
          return;
        }
        nextEntries[tabId] = this.previewEntries[tabId];
      } else {
        const current = this.previewEntries[tabId];
        if (current?.sharedSnapshotPixelMap !== undefined) {
          void this.releaseCachedPixelMap(current.sharedSnapshotPixelMap, tabId, current.captureSource ?? 'memory');
        }
      }
    });
    this.previewEntries = nextEntries;
    const activeTabIds: Record<string, boolean> = {};
    tabs.forEach((tab: BrowserTabState) => {
      activeTabIds[tab.id] = true;
    });
    Object.keys(this.transitionLockedTabIds).forEach((tabId: string) => {
      if (activeTabIds[tabId] !== true) {
        this.transitionLockedTabIds[tabId] = undefined;
      }
    });
    Object.keys(this.tabPrivacyBoundaries).forEach((tabId: string) => {
      if (activeTabIds[tabId] !== true) {
        this.tabPrivacyBoundaries[tabId] = undefined;
      }
    });
    Object.keys(this.activeCaptureRunIds).forEach((tabId: string) => {
      if (activeTabIds[tabId] !== true) {
        this.activeCaptureRunIds[tabId] = undefined;
      }
    });
    return changed || removedEntryIds.length > 0;
  }

  private async waitForActiveCapture(tabId: string): Promise<boolean | undefined> {
    const activeCaptureTask = this.activeCaptureTasks[tabId];
    if (activeCaptureTask === undefined) {
      return undefined;
    }
    return await activeCaptureTask;
  }

  private createCaptureRunId(tabId: string): number {
    this.nextCaptureRunId += 1;
    const runId = this.nextCaptureRunId;
    this.activeCaptureRunIds[tabId] = runId;
    return runId;
  }

  private isCurrentCaptureRun(tabId: string, runId: number): boolean {
    return this.activeCaptureRunIds[tabId] === runId;
  }

  // Invalidate a tab's in-flight capture so a slow snapshot that finishes
  // AFTER the surface changed (e.g. the "+" flow already swapped to home)
  // cannot store a stale/wrong-surface image for that tab.
  invalidateActiveCaptureRun(tabId: string): void {
    if (this.activeCaptureRunIds[tabId] !== undefined) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[THUMB-DIAG] capture-invalidated tab=%{public}s', tabId);
      this.activeCaptureRunIds[tabId] = undefined;
    }
  }

  adoptExternalTransitionSnapshot(
    tab: BrowserTabState,
    pixelMap: image.PixelMap,
    transitionSource: BrowserTabPreviewTransitionSource
  ): void {
    const normalizedTransitionSource = this.normalizeTransitionSource(transitionSource);
    if (normalizedTransitionSource === undefined) {
      this.updateFailure(tab.id, 'external-transition-source-invalid');
      void this.releaseCachedPixelMap(pixelMap, tab.id, 'external-transition-source-invalid');
      return;
    }
    const existing = this.previewEntries[tab.id];
    if (existing?.sharedSnapshotPixelMap !== undefined && existing.sharedSnapshotPixelMap !== pixelMap) {
      void this.releaseCachedPixelMap(existing.sharedSnapshotPixelMap, tab.id,
        existing.captureSource ?? 'replaced-memory');
    }
    const runId = this.createCaptureRunId(tab.id);
    const now = Date.now();
    const signature = this.buildSignature(tab);
    const imageSize = this.resolvePixelMapSize(pixelMap);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[THUMB-DIAG] preview-adopted tab=%{public}s source=%{public}s scope=%{public}s pm=%{public}s',
      tab.id, normalizedTransitionSource.captureSource, normalizedTransitionSource.captureScope,
      `${imageSize.width}x${imageSize.height}`);
    this.previewEntries[tab.id] = {
      tabId: tab.id,
      sharedSnapshotImageUri: '',
      sharedSnapshotImageWidth: imageSize.width,
      sharedSnapshotImageHeight: imageSize.height,
      sharedSnapshotPixelMap: pixelMap,
      transitionReady: true,
      transitionCapturedAt: now,
      transitionSource: normalizedTransitionSource,
      lockedForTransition: this.isTransitionLocked(tab.id),
      favicon: existing?.favicon,
      faviconRevision: existing?.faviconRevision,
      capturedAt: now,
      signature: signature,
      lastKnownGoodSignature: signature,
      failureReason: '',
      captureSource: normalizedTransitionSource.captureSource
    };
    if (!this.isSessionEphemeralTab(tab)) {
      this.persistStoredSnapshotInBackground(tab, pixelMap, normalizedTransitionSource.captureSource, {
        runId: runId,
        signature: signature,
        capturedAt: now,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
        transitionSource: normalizedTransitionSource
      });
    }
    this.captureCacheDirectoryStatsInBackground();
  }

  private async runScheduledCapture(
    requestProvider: () => BrowserTabPreviewCaptureRequest | undefined,
    onUpdated: () => void
  ): Promise<void> {
    const request = requestProvider();
    if (request === undefined) {
      return;
    }
    const readiness = this.resolveCaptureReadiness(request);
    if (!readiness.ready) {
      this.recordDeferredCapture(request.tab.id, readiness.reason);
      return;
    }
    if (await this.capturePreview(request)) {
      onUpdated();
    }
  }

  recordFailure(tabId: string, reason: string): void {
    this.updateFailure(tabId, reason);
  }

  recordMissingCaptureRequest(tabId: string): void {
    this.updateFailure(tabId, BROWSER_TAB_PREVIEW_FAILURE_NO_CAPTURE_REQUEST);
  }

  private hasPreview(entry?: BrowserTabPreviewCacheEntry | BrowserTabPreviewState): boolean {
    return (entry?.sharedSnapshotImageUri?.trim().length ?? 0) > 0 || entry?.sharedSnapshotPixelMap !== undefined;
  }

  private async captureAndStorePreview(
    request: BrowserTabPreviewCaptureRequest,
    existing: BrowserTabPreviewCacheEntry | undefined,
    signature: string,
    runId: number
  ): Promise<boolean> {
    const diagViewport = this.surfaceHost.resolveWebViewportSnapshotSize();
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[THUMB-DIAG] capture-start tab=%{public}s url=%{public}s compOnly=%{public}s preferVisible=%{public}s force=%{public}s hostViewport=%{public}s',
      request.tab.id,
      request.tab.url.slice(0, 64),
      `${request.componentSnapshotOnly === true}`,
      `${request.preferVisibleSnapshot === true}`,
      `${request.force === true}`,
      `${diagViewport.width}x${diagViewport.height}`);
    const captureResult = await this.captureService.captureWebPage(request.controller, request.tab.id, {
      uiContext: request.uiContext,
      componentSnapshotId: request.componentSnapshotId,
      webComponentSnapshotId: request.webComponentSnapshotId,
      componentSnapshotOnly: request.componentSnapshotOnly,
      captureVisibleTabSurface: request.captureVisibleTabSurface,
      allowWindowSnapshot: request.allowWindowSnapshot,
      allowSurfaceSnapshot: request.allowSurfaceSnapshot,
      preferVisibleSnapshot: request.preferVisibleSnapshot,
      requireSharedSnapshot: request.requireSharedSnapshot,
      persistSharedSnapshot: request.componentSnapshotOnly === true ? false : true,
      cacheScopeId: this.cacheScopeId,
      visibleSnapshotTopCropPx: request.visibleSnapshotTopCropPx,
      preferredWebViewportSnapshotSize: this.surfaceHost.resolveWebViewportSnapshotSize()
    });
    if (captureResult.snapshot === undefined) {
      if (!this.isCurrentCaptureRun(request.tab.id, runId)) {
        hilog.info(LOG_DOMAIN, LOG_TAG, 'capture failure dropped tab=%{public}s stale-run=true', request.tab.id);
        return false;
      }
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'capture failed tab=%{public}s reason=%{public}s',
        request.tab.id, captureResult.failureReason);
      this.updateFailure(request.tab.id, captureResult.failureReason);
      return false;
    }
    if (!this.isCurrentCaptureRun(request.tab.id, runId)) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture result dropped tab=%{public}s stale-run=true', request.tab.id);
      await this.releaseCachedPixelMap(captureResult.snapshot, request.tab.id, captureResult.source);
      return false;
    }
    if (this.isTransitionLocked(request.tab.id) && request.allowWhileLocked !== true) {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'capture result dropped tab=%{public}s locked=true', request.tab.id);
      await this.releaseCachedPixelMap(captureResult.snapshot, request.tab.id, captureResult.source);
      return false;
    }
    const now = Date.now();
    const freshSharedUri = captureResult.sharedSnapshotImageUri?.trim() ?? '';
    const transitionSource = this.normalizeTransitionSource(captureResult.transitionSource);
    const isTransitionCapture = transitionSource !== undefined;
    if (request.requireSharedSnapshot === true && !isTransitionCapture && !this.isTransitionSnapshotReady(existing)) {
      const failureReason = `${captureResult.source}-not-transition-source`;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'transition preview rejected tab=%{public}s source=%{public}s',
        request.tab.id, captureResult.source);
      await this.releaseCachedPixelMap(captureResult.snapshot, request.tab.id, captureResult.source);
      this.updateFailure(request.tab.id, failureReason);
      return false;
    }
    if (existing?.sharedSnapshotPixelMap !== undefined) {
      void this.releaseCachedPixelMap(existing.sharedSnapshotPixelMap, request.tab.id,
        existing.captureSource ?? 'replaced-memory');
    }
    const imageSize = this.resolvePixelMapSize(captureResult.snapshot);
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[THUMB-DIAG] preview-stored tab=%{public}s source=%{public}s pm=%{public}s stored=%{public}s uri=%{public}s',
      request.tab.id,
      captureResult.source,
      `${imageSize.width}x${imageSize.height}`,
      `${captureResult.sharedSnapshotWidth ?? imageSize.width}x${captureResult.sharedSnapshotHeight ?? imageSize.height}`,
      `${freshSharedUri.length > 0}`);
    this.previewEntries[request.tab.id] = {
      tabId: request.tab.id,
      sharedSnapshotImageUri: freshSharedUri,
      sharedSnapshotImageWidth: captureResult.sharedSnapshotWidth ?? imageSize.width,
      sharedSnapshotImageHeight: captureResult.sharedSnapshotHeight ?? imageSize.height,
      sharedSnapshotPixelMap: captureResult.snapshot,
      transitionReady: isTransitionCapture || this.isTransitionSnapshotReady(existing),
      transitionCapturedAt: isTransitionCapture ? now : existing?.transitionCapturedAt,
      transitionSource: transitionSource ?? existing?.transitionSource,
      lockedForTransition: this.isTransitionLocked(request.tab.id),
      favicon: existing?.favicon,
      faviconRevision: existing?.faviconRevision,
      capturedAt: now,
      signature: signature,
      lastKnownGoodSignature: signature,
      failureReason: '',
      captureSource: captureResult.source
    };
    if (freshSharedUri.length <= 0 && !this.isSessionEphemeralTab(request.tab)) {
      this.persistStoredSnapshotInBackground(request.tab, captureResult.snapshot, captureResult.source, {
        runId: runId,
        signature: signature,
        capturedAt: now,
        imageWidth: captureResult.sharedSnapshotWidth ?? imageSize.width,
        imageHeight: captureResult.sharedSnapshotHeight ?? imageSize.height,
        transitionSource: transitionSource ?? existing?.transitionSource
      });
    }
    this.captureCacheDirectoryStatsInBackground();
    return true;
  }

  private persistStoredSnapshotInBackground(
    tab: BrowserTabState,
    pixelMap: image.PixelMap,
    source: BrowserTabPreviewCaptureSource,
    context: BrowserTabPreviewBackgroundPersistContext
  ): void {
    const transitionSource = this.normalizeTransitionSource(context.transitionSource);
    if (transitionSource === undefined) {
      return;
    }
    void this.cacheStore.savePreviewImageWithStats(pixelMap, `${tab.id}-shared`, transitionSource)
      .then((result) => {
        const sharedUri = result.uri?.trim() ?? '';
        if (sharedUri.length <= 0) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'background shared persist empty tab=%{public}s source=%{public}s',
            tab.id, source);
          return;
        }
        this.applyBackgroundPersistedSharedSnapshot(tab, source, result, context);
      })
      .catch((error: Error) => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'background shared persist failed tab=%{public}s source=%{public}s error=%{public}s',
          tab.id, source, JSON.stringify(error));
      });
  }

  private applyBackgroundPersistedSharedSnapshot(
    tab: BrowserTabState,
    source: BrowserTabPreviewCaptureSource,
    result: BrowserTabPreviewPersistedImageStats,
    context: BrowserTabPreviewBackgroundPersistContext
  ): void {
    const sharedUri = result.uri?.trim() ?? '';
    if (sharedUri.length <= 0) {
      return;
    }
    if (!this.isCurrentCaptureRun(tab.id, context.runId)) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'background shared persist dropped tab=%{public}s source=%{public}s reason=%{public}s',
        tab.id, source, 'stale-run');
      return;
    }
    const current = this.previewEntries[tab.id];
    if (current === undefined) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'background shared persist dropped tab=%{public}s source=%{public}s reason=%{public}s',
        tab.id, source, 'missing-entry');
      return;
    }
    const currentUri = current.sharedSnapshotImageUri?.trim() ?? '';
    if (currentUri.length > 0 && current.capturedAt >= context.capturedAt) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'background shared persist dropped tab=%{public}s source=%{public}s reason=%{public}s',
        tab.id, source, 'uri-already-current');
      return;
    }
    if (current.capturedAt > context.capturedAt) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'background shared persist dropped tab=%{public}s source=%{public}s reason=%{public}s',
        tab.id, source, 'newer-entry');
      return;
    }
    if (current.signature !== context.signature && current.lastKnownGoodSignature !== context.signature) {
      hilog.info(LOG_DOMAIN, LOG_TAG,
        'background shared persist dropped tab=%{public}s source=%{public}s reason=%{public}s',
        tab.id, source, 'signature-changed');
      return;
    }
    this.previewEntries[tab.id] = this.copyEntry(current, {
      sharedSnapshotImageUri: sharedUri,
      sharedSnapshotImageWidth: context.imageWidth,
      sharedSnapshotImageHeight: context.imageHeight,
      transitionReady: context.transitionSource !== undefined || this.isTransitionSnapshotReady(current),
      transitionCapturedAt: context.transitionSource !== undefined ? context.capturedAt : current.transitionCapturedAt,
      transitionSource: context.transitionSource ?? current.transitionSource,
      failureReason: '',
      captureSource: source
    });
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'background shared persist applied tab=%{public}s source=%{public}s uri=%{public}s bytes=%{public}d',
      tab.id, source, sharedUri, result.bytes);
  }

  recordTransitionImageUse(tabId: string, phase: string): void {
    const state = this.getPreviewState(tabId);
    const kind = this.resolveTransitionImageKind(state);
    sharedBrowserTabPreviewMetrics.recordTransitionImage({
      tabId: tabId,
      phase: phase,
      kind: kind,
      transitionReady: state?.transitionReady === true,
      source: state?.transitionSource?.captureSource ?? state?.captureSource ?? ''
    });
  }

  private isTransitionSnapshotReady(entry?: BrowserTabPreviewCacheEntry | BrowserTabPreviewState): boolean {
    if (entry === undefined) {
      return false;
    }
    if (this.normalizeTransitionSource(entry.transitionSource) === undefined) {
      return false;
    }
    const hasTransitionImage = (entry.sharedSnapshotImageUri?.trim().length ?? 0) > 0 ||
      entry.sharedSnapshotPixelMap !== undefined;
    if (!hasTransitionImage) {
      return false;
    }
    if (entry.transitionReady === false) {
      return false;
    }
    return true;
  }

  private resolveTransitionImageKind(state?: BrowserTabPreviewState): BrowserTabPreviewTransitionImageKind {
    if (state === undefined || state.transitionReady !== true) {
      return 'none';
    }
    const sharedUri = state.sharedSnapshotImageUri?.trim() ?? '';
    if (sharedUri.length > 0 || state.sharedSnapshotPixelMap !== undefined) {
      return 'shared';
    }
    return 'none';
  }

  private resolvePixelMapSize(pixelMap: image.PixelMap): BrowserTabPreviewImageSize {
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      return {
        width: Math.max(1, Math.floor(imageInfo.size.width)),
        height: Math.max(1, Math.floor(imageInfo.size.height))
      };
    } catch (_error) {
      return {
        width: BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
        height: BROWSER_TAB_PREVIEW_PIXEL_HEIGHT
      };
    }
  }

  private resolveRestoredTransitionSource(
    sharedSnapshotImageInfo?: BrowserTabPreviewCachedImageInfo
  ): BrowserTabPreviewTransitionSource | undefined {
    return this.normalizeTransitionSource(sharedSnapshotImageInfo?.transitionSource);
  }

  private normalizeTransitionSource(
    transitionSource?: BrowserTabPreviewTransitionSource
  ): BrowserTabPreviewTransitionSource | undefined {
    if (transitionSource === undefined || transitionSource.captureSource === 'none' ||
      (transitionSource.captureScope !== 'web-content' && transitionSource.captureScope !== 'full-surface') ||
      (transitionSource.transitionFrame !== 'captured-surface' &&
        transitionSource.transitionFrame !== 'current-web')) {
      return undefined;
    }
    return {
      captureSource: transitionSource.captureSource,
      captureScope: transitionSource.captureScope,
      transitionFrame: transitionSource.transitionFrame,
      sourceRect: this.normalizeSourceRect(transitionSource.sourceRect)
    };
  }

  private normalizeSourceRect(
    sourceRect?: BrowserTabPreviewSourceRect
  ): BrowserTabPreviewSourceRect | undefined {
    if (sourceRect === undefined) {
      return undefined;
    }
    const width = Math.max(1, Math.round(sourceRect.width));
    const height = Math.max(1, Math.round(sourceRect.height));
    if (width <= 1 || height <= 1) {
      return undefined;
    }
    return {
      left: Math.round(sourceRect.left),
      top: Math.round(sourceRect.top),
      width: width,
      height: height
    };
  }

  private areSourceRectsEqual(
    left?: BrowserTabPreviewSourceRect,
    right?: BrowserTabPreviewSourceRect
  ): boolean {
    const normalizedLeft = this.normalizeSourceRect(left);
    const normalizedRight = this.normalizeSourceRect(right);
    if (normalizedLeft === undefined || normalizedRight === undefined) {
      return normalizedLeft === undefined && normalizedRight === undefined;
    }
    return normalizedLeft.left === normalizedRight.left &&
      normalizedLeft.top === normalizedRight.top &&
      normalizedLeft.width === normalizedRight.width &&
      normalizedLeft.height === normalizedRight.height;
  }

  private areTransitionSourcesEqual(
    left?: BrowserTabPreviewTransitionSource,
    right?: BrowserTabPreviewTransitionSource
  ): boolean {
    const normalizedLeft = this.normalizeTransitionSource(left);
    const normalizedRight = this.normalizeTransitionSource(right);
    if (normalizedLeft === undefined || normalizedRight === undefined) {
      return normalizedLeft === undefined && normalizedRight === undefined;
    }
    return normalizedLeft.captureSource === normalizedRight.captureSource &&
      normalizedLeft.captureScope === normalizedRight.captureScope &&
      normalizedLeft.transitionFrame === normalizedRight.transitionFrame &&
      this.areSourceRectsEqual(normalizedLeft.sourceRect, normalizedRight.sourceRect);
  }

  private async releaseCachedPixelMap(
    pixelMap: image.PixelMap,
    tabId: string,
    source: string
  ): Promise<void> {
    try {
      await pixelMap.release();
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'release cached snapshot failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
    }
  }

  private async removePrivatePreviewCache(tabId: string): Promise<boolean> {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return false;
    }
    this.transitionLockedTabIds[normalizedTabId] = undefined;
    const current = this.previewEntries[normalizedTabId];
    if (current?.sharedSnapshotPixelMap !== undefined) {
      await this.releaseCachedPixelMap(current.sharedSnapshotPixelMap, normalizedTabId, current.captureSource ?? 'private-memory');
    }
    this.previewEntries[normalizedTabId] = undefined;
    const removedPersisted = await this.cacheStore.removePreviewImage(normalizedTabId);
    return current !== undefined || removedPersisted;
  }

  private isSessionEphemeralTab(tab: BrowserTabState): boolean {
    return this.profileBoundaryService.isSessionEphemeral({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    });
  }

  private updateFailure(tabId: string, reason: string): void {
    if (tabId.trim().length === 0) {
      return;
    }
    const current = this.previewEntries[tabId];
    if (current === undefined) {
      return;
    }
    this.previewEntries[tabId] = {
      tabId: tabId,
      sharedSnapshotImageUri: current?.sharedSnapshotImageUri,
      sharedSnapshotImageWidth: current?.sharedSnapshotImageWidth,
      sharedSnapshotImageHeight: current?.sharedSnapshotImageHeight,
      sharedSnapshotPixelMap: current?.sharedSnapshotPixelMap,
      transitionReady: this.isTransitionSnapshotReady(current),
      transitionCapturedAt: current?.transitionCapturedAt,
      transitionSource: current?.transitionSource,
      lockedForTransition: this.isTransitionLocked(tabId),
      favicon: current?.favicon,
      faviconRevision: current?.faviconRevision,
      capturedAt: current?.capturedAt ?? Date.now(),
      signature: current?.signature ?? '',
      lastKnownGoodSignature: current?.lastKnownGoodSignature ?? '',
      failureReason: reason,
      captureSource: current?.captureSource
    };
  }

  private captureCacheDirectoryStatsInBackground(): void {
    setTimeout(() => {
      void this.cacheStore.captureCacheDirectoryStats();
    }, 0);
  }

  private resolveCaptureReadiness(request: BrowserTabPreviewCaptureRequest): BrowserTabSnapshotReadiness {
    if (request.tab.id.trim().length === 0) {
      return { ready: false, reason: 'empty-tab' };
    }
    if (request.tab.isHome) {
      return { ready: false, reason: 'home-tab' };
    }
    if (request.controller === undefined) {
      return { ready: false, reason: 'missing-controller' };
    }
    if (this.isTransitionLocked(request.tab.id) && request.allowWhileLocked !== true) {
      return { ready: false, reason: 'transition-locked' };
    }
    if (request.hasRenderableSurface === true) {
      return { ready: true, reason: '' };
    }
    if (request.hasLiveController === true && request.preferVisibleSnapshot !== true) {
      return { ready: true, reason: '' };
    }
    return { ready: false, reason: 'web-not-attached' };
  }

  private recordDeferredCapture(tabId: string, reason: string): void {
    hilog.info(LOG_DOMAIN, LOG_TAG, 'capture deferred tab=%{public}s reason=%{public}s', tabId, reason);
    this.updateFailure(tabId, reason);
  }

  private isTransitionLocked(tabId: string): boolean {
    return this.transitionLockedTabIds[tabId] === true;
  }

  private copyEntry(
    current: BrowserTabPreviewCacheEntry,
    patch: Partial<BrowserTabPreviewCacheEntry>
  ): BrowserTabPreviewCacheEntry {
    return {
      tabId: patch.tabId ?? current.tabId,
      sharedSnapshotImageUri: patch.sharedSnapshotImageUri ?? current.sharedSnapshotImageUri,
      sharedSnapshotImageWidth: patch.sharedSnapshotImageWidth ?? current.sharedSnapshotImageWidth,
      sharedSnapshotImageHeight: patch.sharedSnapshotImageHeight ?? current.sharedSnapshotImageHeight,
      sharedSnapshotPixelMap: patch.sharedSnapshotPixelMap ?? current.sharedSnapshotPixelMap,
      transitionReady: patch.transitionReady ?? current.transitionReady,
      transitionCapturedAt: patch.transitionCapturedAt ?? current.transitionCapturedAt,
      transitionSource: patch.transitionSource ?? current.transitionSource,
      lockedForTransition: patch.lockedForTransition ?? current.lockedForTransition,
      favicon: patch.favicon ?? current.favicon,
      faviconRevision: patch.faviconRevision ?? current.faviconRevision,
      capturedAt: patch.capturedAt ?? current.capturedAt,
      signature: patch.signature ?? current.signature,
      lastKnownGoodSignature: patch.lastKnownGoodSignature ?? current.lastKnownGoodSignature,
      failureReason: patch.failureReason ?? current.failureReason,
      captureSource: patch.captureSource ?? current.captureSource
    };
  }

  private buildSignature(tab: BrowserTabState): string {
    return [
      tab.url,
      tab.title,
      `${tab.lastLoadedAt}`,
      tab.runtimeState,
      tab.lastError
    ].join('|');
  }
}
