import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import {
  BrowserTabPreviewCoordinator,
  BrowserTabPreviewState
} from '../BrowserTabPreviewCoordinator';
import {
  BrowserTabsOverviewEntrySnapshotBeginInput,
  BrowserTabsOverviewEntrySnapshotSessionCoordinator,
  BrowserTabsOverviewEntrySnapshotSessionState
} from '../BrowserTabsOverviewEntrySnapshotSessionCoordinator';
import { BrowserTabsOverlayRect } from '../BrowserTabsOverlayViewModel';
import { BrowserTabState } from '../../tabs/TabManager';
import {
  BrowserTabPreviewSourceRect,
  BrowserTabPreviewTransitionSource
} from '../../../services/web/BrowserTabPreviewTypes';
import { BrowserWebLayerGeometrySnapshot } from '../BrowserWebLayerGeometryCache';
import { BrowserTabsOverviewThumbnailCoordinator } from './BrowserTabsOverviewThumbnailCoordinator';

export interface BrowserTabsOverviewSnapshotPipelineState {
  session: BrowserTabsOverviewEntrySnapshotSessionState;
  measuredEntryFrame?: BrowserTabsOverlayRect;
}

interface BrowserTabsOverviewSnapshotPipelineBeginInput {
  tabId: string;
  pixelMap: image.PixelMap;
  fallbackWidth: number;
  fallbackHeight: number;
  transitionSource: BrowserTabPreviewTransitionSource;
}

interface BrowserTabsOverviewSnapshotPipelineBeginResult {
  state: BrowserTabsOverviewSnapshotPipelineState;
  pixelMapToRelease?: image.PixelMap;
  width: number;
  height: number;
  capturedAt: number;
}

interface BrowserTabsOverviewSnapshotPersistLease {
  id: number;
  pixelMap: image.PixelMap;
  releaseRequested: boolean;
}

export interface BrowserTabsOverviewSnapshotPipelineDependencies {
  previewCoordinator: BrowserTabPreviewCoordinator;
  readState: () => BrowserTabsOverviewSnapshotPipelineState;
  updateState: (state: BrowserTabsOverviewSnapshotPipelineState) => void;
  releasePixelMap: (pixelMap: image.PixelMap) => void;
  notifyChanged: () => void;
  onCapturedEntryReady: (tabId: string, generation: number) => void;
  recordFailure: (eventType: string, error: Error, tabId: string) => void;
}

export interface BrowserTabsOverviewSnapshotPipelineEntryCaptureInput {
  tab: BrowserTabState;
  generation: number;
  uiContext: UIContext;
  componentSnapshotId: string;
  componentSnapshotScale: number;
  fallbackWidth: number;
  fallbackHeight: number;
  transitionSource: BrowserTabPreviewTransitionSource;
  shouldKeepPixelMap: () => boolean;
}

export interface BrowserTabsOverviewSnapshotPipelineExternalCaptureInput {
  tab: BrowserTabState;
  uiContext: UIContext;
  componentSnapshotId: string;
  componentSnapshotScale: number;
  transitionSource: BrowserTabPreviewTransitionSource;
  shouldKeepPixelMap: () => boolean;
}

export interface BrowserTabsOverviewSnapshotWebRectInput {
  showHomePage: boolean;
  rootViewportWidth: number;
  rootViewportHeight: number;
  visualTopInset: number;
  bottomInset: number;
  hostedWebLayerMeasured: boolean;
  hostedWebLayerLeft: number;
  hostedWebLayerTop: number;
  hostedWebLayerWidth: number;
  hostedWebLayerHeight: number;
  reusableGeometry?: BrowserWebLayerGeometrySnapshot;
}

export interface BrowserTabsOverviewEntryMorphSourceInput {
  tabId: string;
  fallbackWebRect: BrowserTabsOverlayRect;
  showHomePage: boolean;
  capturedAt: number;
}

export interface BrowserTabsOverviewExitMorphSourceInput {
  tabId: string;
  fallbackWebRect: BrowserTabsOverlayRect;
  showHomePage: boolean;
  capturedAt: number;
}

export interface BrowserTabsOverviewSnapshotMorphSource {
  previewState?: BrowserTabPreviewState;
  sourceRect: BrowserTabsOverlayRect;
  sourceImageTopInset: number;
}

export class BrowserTabsOverviewSnapshotPipelineCoordinator {
  private readonly dependencies: BrowserTabsOverviewSnapshotPipelineDependencies;
  private sessionCoordinator: BrowserTabsOverviewEntrySnapshotSessionCoordinator =
    new BrowserTabsOverviewEntrySnapshotSessionCoordinator();
  private thumbnailCoordinator: BrowserTabsOverviewThumbnailCoordinator = new BrowserTabsOverviewThumbnailCoordinator();
  private persistLeases: BrowserTabsOverviewSnapshotPersistLease[] = [];
  private persistLeaseId: number = 0;

  private static readonly ENTRY_SNAPSHOT_PERSIST_WAIT_MS: number = 120;

  constructor(dependencies: BrowserTabsOverviewSnapshotPipelineDependencies) {
    this.dependencies = dependencies;
  }

  buildIdleState(): BrowserTabsOverviewSnapshotPipelineState {
    return {
      session: this.sessionCoordinator.buildIdleState()
    };
  }

  mergePreviewStatesWithEntrySession(
    state: BrowserTabsOverviewSnapshotPipelineState,
    persistedStates: BrowserTabPreviewState[],
    capturedAt: number
  ): BrowserTabPreviewState[] {
    return this.sessionCoordinator.mergePreviewStatesWithEntrySession(state.session, persistedStates, capturedAt);
  }

  buildGalleryPreviewStates(
    state: BrowserTabsOverviewSnapshotPipelineState,
    persistedStates: BrowserTabPreviewState[],
    tabs: BrowserTabState[],
    capturedAt: number
  ): BrowserTabPreviewState[] {
    const mergedStates = this.mergePreviewStatesWithEntrySession(state, persistedStates, capturedAt);
    // Mirror the freshest persisted previews into the thumbnail store so the card's
    // snapshotThumbnail asset and the shared-snapshot transition resolve the same
    // capture. The store's capturedAt guard rejects any stale write.
    this.thumbnailCoordinator.reconcileFromPreviewStates(mergedStates);
    return this.thumbnailCoordinator.buildGalleryPreviewStates(mergedStates, tabs);
  }

  buildTransitionPreviewState(
    state: BrowserTabsOverviewSnapshotPipelineState,
    tabId: string,
    persistedState: BrowserTabPreviewState | undefined,
    capturedAt: number
  ): BrowserTabPreviewState | undefined {
    if (!this.hasEntryPixelMap(state, tabId)) {
      return this.thumbnailCoordinator.mergeThumbnailAssetIntoTransitionPreviewState(tabId, persistedState);
    }
    return this.thumbnailCoordinator.mergeThumbnailAssetIntoTransitionPreviewState(
      tabId,
      this.sessionCoordinator.buildPreviewState(state.session, persistedState, capturedAt)
    );
  }

  hasEntryPixelMap(state: BrowserTabsOverviewSnapshotPipelineState, tabId: string): boolean {
    return state.session.tabId === tabId && state.session.pixelMap !== undefined;
  }

  /**
   * Owner-facing state accessors keep the Snapshot Pipeline's mutable capture state
   * behind its existing dependency boundary. Tabs Overview owns the transition
   * narrative; the page only supplies the pipeline's platform callbacks.
   */
  hasEntryPixelMapForTab(tabId: string): boolean {
    return this.hasEntryPixelMap(this.dependencies.readState(), tabId);
  }

  buildTransitionPreviewStateForTab(
    tabId: string,
    capturedAt: number
  ): BrowserTabPreviewState | undefined {
    const state = this.dependencies.readState();
    return this.buildTransitionPreviewState(
      state,
      tabId,
      this.dependencies.previewCoordinator.getTransitionSnapshotState(tabId),
      capturedAt
    );
  }

  rememberMeasuredEntryFrameForOwner(rect: BrowserTabsOverlayRect): void {
    const nextState = this.rememberMeasuredEntryFrame(this.dependencies.readState(), rect);
    this.dependencies.updateState(nextState);
  }

  resetMeasuredEntryFrameForOwner(): void {
    const nextState = this.resetMeasuredEntryFrame(this.dependencies.readState());
    this.dependencies.updateState(nextState);
  }

  getMeasuredEntryFrameForOwner(): BrowserTabsOverlayRect | undefined {
    return this.getMeasuredEntryFrame(this.dependencies.readState());
  }

  isEntryFrameMeasuredForOwner(): boolean {
    return this.isEntryFrameMeasured(this.dependencies.readState());
  }

  resolveEntryMorphSourceForOwner(
    input: BrowserTabsOverviewEntryMorphSourceInput
  ): BrowserTabsOverviewSnapshotMorphSource {
    const state = this.dependencies.readState();
    const previewState = this.buildTransitionPreviewState(
      state,
      input.tabId,
      this.dependencies.previewCoordinator.getTransitionSnapshotState(input.tabId),
      input.capturedAt
    );
    const sourceRect = this.resolveEntrySnapshotSourceRect(
      state,
      input.tabId,
      input.fallbackWebRect
    );
    const fallbackTopInset = this.resolveFallbackSourceImageTopInset(input.showHomePage, sourceRect);
    return {
      previewState: previewState,
      sourceRect: sourceRect,
      sourceImageTopInset: this.resolveSourceImageTopInset(previewState?.transitionSource, fallbackTopInset)
    };
  }

  resolveExitMorphSourceForOwner(
    input: BrowserTabsOverviewExitMorphSourceInput
  ): BrowserTabsOverviewSnapshotMorphSource {
    const state = this.dependencies.readState();
    const previewState = this.buildTransitionPreviewState(
      state,
      input.tabId,
      this.dependencies.previewCoordinator.getTransitionSnapshotState(input.tabId),
      input.capturedAt
    );
    const sourceRect = this.resolveTransitionSourceRect(input.fallbackWebRect, previewState?.transitionSource);
    const fallbackTopInset = this.resolveFallbackSourceImageTopInset(input.showHomePage, sourceRect);
    return {
      previewState: previewState,
      sourceRect: sourceRect,
      sourceImageTopInset: this.resolveSourceImageTopInset(previewState?.transitionSource, fallbackTopInset)
    };
  }

  private beginEntrySnapshot(
    state: BrowserTabsOverviewSnapshotPipelineState,
    input: BrowserTabsOverviewSnapshotPipelineBeginInput
  ): BrowserTabsOverviewSnapshotPipelineBeginResult {
    const size = this.resolvePixelMapSize(input.pixelMap, input.fallbackWidth, input.fallbackHeight);
    const beginInput: BrowserTabsOverviewEntrySnapshotBeginInput = {
      tabId: input.tabId,
      pixelMap: input.pixelMap,
      width: size.width,
      height: size.height,
      transitionSource: input.transitionSource
    };
    const result = this.sessionCoordinator.beginSession(state.session, beginInput);
    return {
      state: this.withSession(state, result.state),
      pixelMapToRelease: result.pixelMapToRelease,
      width: size.width,
      height: size.height,
      capturedAt: result.state.capturedAt
    };
  }

  private resolveEntrySnapshotSourceRect(
    state: BrowserTabsOverviewSnapshotPipelineState,
    tabId: string,
    fallbackWebRect: BrowserTabsOverlayRect
  ): BrowserTabsOverlayRect {
    const entryTransitionSource = state.session.transitionSource;
    const entrySourceRect = entryTransitionSource?.sourceRect;
    if (state.session.tabId === tabId && entryTransitionSource !== undefined) {
      if (entryTransitionSource.transitionFrame === 'current-web') {
        return fallbackWebRect;
      }
      if (entrySourceRect !== undefined) {
        return this.buildOverlayRect(entrySourceRect);
      }
    }
    if (!this.hasEntryPixelMap(state, tabId)) {
      return fallbackWebRect;
    }
    return fallbackWebRect;
  }

  rememberMeasuredEntryFrame(
    state: BrowserTabsOverviewSnapshotPipelineState,
    rect: BrowserTabsOverlayRect
  ): BrowserTabsOverviewSnapshotPipelineState {
    return {
      session: state.session,
      measuredEntryFrame: this.roundRect(rect)
    };
  }

  resetMeasuredEntryFrame(
    state: BrowserTabsOverviewSnapshotPipelineState
  ): BrowserTabsOverviewSnapshotPipelineState {
    if (state.measuredEntryFrame === undefined) {
      return state;
    }
    return {
      session: state.session
    };
  }

  getMeasuredEntryFrame(state: BrowserTabsOverviewSnapshotPipelineState): BrowserTabsOverlayRect | undefined {
    return state.measuredEntryFrame;
  }

  isEntryFrameMeasured(state: BrowserTabsOverviewSnapshotPipelineState): boolean {
    return state.measuredEntryFrame !== undefined;
  }

  releaseSession(tabId?: string): void {
    const state = this.dependencies.readState();
    const result = this.sessionCoordinator.releaseSession(state.session, tabId);
    const pixelMapToRelease = this.resolvePixelMapToReleaseAfterLeaseCheck(result.pixelMapToRelease);
    const nextState: BrowserTabsOverviewSnapshotPipelineState = {
      session: result.state
    };
    this.dependencies.updateState(nextState);
    if (pixelMapToRelease !== undefined) {
      this.dependencies.releasePixelMap(pixelMapToRelease);
    }
  }

  rememberPersistedPreviewState(previewState: BrowserTabPreviewState | undefined): boolean {
    return this.thumbnailCoordinator.rememberPersistedPreviewState(previewState);
  }

  clearMissingTabs(retainedTabs: BrowserTabState[]): boolean {
    return this.thumbnailCoordinator.clearMissingTabs(retainedTabs);
  }

  clearTabThumbnail(tabId: string): boolean {
    return this.thumbnailCoordinator.clearTab(tabId);
  }

  buildWindowSourceRect(rootViewportWidth: number, rootViewportHeight: number): BrowserTabPreviewSourceRect {
    return {
      left: 0,
      top: 0,
      width: Math.max(1, rootViewportWidth),
      height: Math.max(1, rootViewportHeight)
    };
  }

  buildEntryVisibleTabSurfaceTransitionSource(
    rootViewportWidth: number,
    rootViewportHeight: number
  ): BrowserTabPreviewTransitionSource {
    return {
      captureSource: 'visible-tab-surface',
      captureScope: 'full-surface',
      transitionFrame: 'captured-surface',
      sourceRect: this.buildWindowSourceRect(rootViewportWidth, rootViewportHeight)
    };
  }

  buildCurrentWebVisibleTabSurfaceTransitionSource(): BrowserTabPreviewTransitionSource {
    return {
      captureSource: 'visible-tab-surface',
      captureScope: 'full-surface',
      transitionFrame: 'current-web'
    };
  }

  buildWebRect(input: BrowserTabsOverviewSnapshotWebRectInput): BrowserTabsOverlayRect {
    const visualTopInset = input.showHomePage ? 0 : Math.max(0, input.visualTopInset);
    const fallbackTop = visualTopInset;
    const fallbackHeight = Math.max(1, input.rootViewportHeight - fallbackTop - Math.max(0, input.bottomInset));
    const shouldUseMeasuredWebLayer = input.hostedWebLayerMeasured &&
      input.hostedWebLayerWidth > 1 && input.hostedWebLayerHeight > 1;
    if (!shouldUseMeasuredWebLayer) {
      return {
        left: 0,
        top: fallbackTop,
        width: Math.max(1, Math.round(input.rootViewportWidth)),
        height: fallbackHeight
      };
    }
    const measuredTop = input.hostedWebLayerTop > 0 ? input.hostedWebLayerTop :
      (input.reusableGeometry?.webTop ?? fallbackTop);
    const measuredLeft = input.hostedWebLayerWidth > 1 ? Math.max(0, input.hostedWebLayerLeft) :
      (input.reusableGeometry?.webLeft ?? 0);
    const measuredWidth = input.hostedWebLayerWidth > 1 ? input.hostedWebLayerWidth :
      (input.reusableGeometry?.webWidth ?? input.rootViewportWidth);
    const measuredHeight = input.hostedWebLayerHeight > 1 ? input.hostedWebLayerHeight :
      (input.reusableGeometry?.webHeight ?? fallbackHeight);
    const sourceTop = Math.max(0, Math.round(measuredTop));
    return {
      left: measuredLeft,
      top: sourceTop,
      width: Math.max(1, Math.min(measuredWidth, input.rootViewportWidth - measuredLeft)),
      height: Math.max(1, Math.min(measuredHeight, input.rootViewportHeight - sourceTop))
    };
  }

  private async waitForTask<T>(task: Promise<T>, timeoutMs: number): Promise<void> {
    const trackedTask = task
      .then(() => {})
      .catch((_error: Error) => {});
    await Promise.race([
      trackedTask,
      this.delay(timeoutMs)
    ]);
  }

  async captureEntryPixelMapBeforeOpen(
    input: BrowserTabsOverviewSnapshotPipelineEntryCaptureInput
  ): Promise<boolean> {
    const tabId = input.tab.id;
    if (tabId.trim().length <= 0 || !input.shouldKeepPixelMap()) {
      return false;
    }
    try {
      const pixelMap = await input.uiContext.getComponentSnapshot().get(input.componentSnapshotId, {
        scale: input.componentSnapshotScale,
        waitUntilRenderFinished: false
      });
      if (!input.shouldKeepPixelMap()) {
        this.dependencies.releasePixelMap(pixelMap);
        return false;
      }
      await this.handleCapturedEntryPixelMap(input, pixelMap, input.transitionSource);
      return this.hasEntryPixelMap(this.dependencies.readState(), tabId);
    } catch (error) {
      this.dependencies.recordFailure('tabs_entry_snapshot_capture_failed', error as Error, tabId);
      return false;
    }
  }

  async captureAndAdoptExternalTransitionSnapshot(
    input: BrowserTabsOverviewSnapshotPipelineExternalCaptureInput
  ): Promise<boolean> {
    const tabId = input.tab.id;
    if (tabId.trim().length <= 0 || input.tab.isHome || !input.shouldKeepPixelMap()) {
      return false;
    }
    try {
      const pixelMap = await input.uiContext.getComponentSnapshot().get(input.componentSnapshotId, {
        scale: input.componentSnapshotScale,
        waitUntilRenderFinished: false
      });
      if (!input.shouldKeepPixelMap()) {
        this.dependencies.releasePixelMap(pixelMap);
        return false;
      }
      this.dependencies.previewCoordinator.adoptExternalTransitionSnapshot(
        input.tab,
        pixelMap,
        input.transitionSource
      );
      this.dependencies.notifyChanged();
      return this.dependencies.previewCoordinator.getTransitionSnapshotState(tabId) !== undefined;
    } catch (error) {
      this.dependencies.recordFailure('tabs_external_snapshot_capture_failed', error as Error, tabId);
      return false;
    }
  }

  private resolveTransitionSourceRect(
    componentRect: BrowserTabsOverlayRect,
    transitionSource?: BrowserTabPreviewTransitionSource
  ): BrowserTabsOverlayRect {
    const rememberedRect = transitionSource?.sourceRect;
    if (transitionSource?.transitionFrame !== 'captured-surface') {
      return componentRect;
    }
    if (rememberedRect !== undefined && rememberedRect.width > 0 && rememberedRect.height > 0) {
      return this.buildOverlayRect(rememberedRect);
    }
    return componentRect;
  }

  private resolveFallbackSourceImageTopInset(showHomePage: boolean, sourceRect: BrowserTabsOverlayRect): number {
    if (showHomePage) {
      return 0;
    }
    return Math.max(0, Math.round(sourceRect.top));
  }

  private resolveSourceImageTopInset(
    transitionSource: BrowserTabPreviewTransitionSource | undefined,
    componentTopInset: number
  ): number {
    const topInset = Math.max(0, Math.round(componentTopInset));
    if (topInset <= 0 || transitionSource?.captureScope !== 'full-surface') {
      return 0;
    }
    return -topInset;
  }

  private installEntrySnapshot(input: BrowserTabsOverviewSnapshotPipelineBeginInput): void {
    const beginResult = this.beginEntrySnapshot(this.dependencies.readState(), {
      tabId: input.tabId,
      pixelMap: input.pixelMap,
      fallbackWidth: input.fallbackWidth,
      fallbackHeight: input.fallbackHeight,
      transitionSource: input.transitionSource
    });
    this.dependencies.updateState(beginResult.state);
    this.releaseExternalPixelMapCandidate(beginResult.pixelMapToRelease);
    this.dependencies.notifyChanged();
  }

  private async handleCapturedEntryPixelMap(
    input: BrowserTabsOverviewSnapshotPipelineEntryCaptureInput,
    pixelMap: image.PixelMap,
    transitionSource: BrowserTabPreviewTransitionSource
  ): Promise<void> {
    const tabId = input.tab.id;
    if (!input.shouldKeepPixelMap()) {
      this.dependencies.releasePixelMap(pixelMap);
      return;
    }
    this.installEntrySnapshot({
      tabId: tabId,
      pixelMap: pixelMap,
      fallbackWidth: input.fallbackWidth,
      fallbackHeight: input.fallbackHeight,
      transitionSource: transitionSource
    });
    const persistTask = this.persistEntrySnapshotForGalleryBeforeEntry(
      input,
      pixelMap,
      transitionSource
    );
    await this.waitForTask(
      persistTask,
      BrowserTabsOverviewSnapshotPipelineCoordinator.ENTRY_SNAPSHOT_PERSIST_WAIT_MS
    );
    this.dependencies.onCapturedEntryReady(tabId, input.generation);
  }

  private async persistEntrySnapshotForGalleryBeforeEntry(
    input: BrowserTabsOverviewSnapshotPipelineEntryCaptureInput,
    pixelMap: image.PixelMap,
    transitionSource: BrowserTabPreviewTransitionSource
  ): Promise<void> {
    const lease = this.createPersistLease(pixelMap);
    try {
      const persisted = await this.dependencies.previewCoordinator.persistImmediateSharedSnapshot(
        input.tab,
        pixelMap,
        transitionSource
      );
      const previewState = this.dependencies.previewCoordinator.getPreviewState(input.tab.id);
      if (persisted && this.rememberPersistedPreviewState(previewState)) {
        this.dependencies.notifyChanged();
      }
    } catch (error) {
      this.dependencies.recordFailure('tabs_entry_snapshot_persist_failed', error as Error, input.tab.id);
    } finally {
      this.finishPersistLease(lease);
    }
  }

  private releaseExternalPixelMapCandidate(pixelMap?: image.PixelMap): void {
    if (pixelMap !== undefined) {
      this.releasePixelMapWithLeaseCheck(pixelMap);
    }
  }

  private createPersistLease(pixelMap: image.PixelMap): BrowserTabsOverviewSnapshotPersistLease {
    this.persistLeaseId += 1;
    const lease: BrowserTabsOverviewSnapshotPersistLease = {
      id: this.persistLeaseId,
      pixelMap: pixelMap,
      releaseRequested: false
    };
    this.persistLeases = this.persistLeases.concat([lease]);
    return lease;
  }

  private finishPersistLease(lease: BrowserTabsOverviewSnapshotPersistLease): void {
    this.persistLeases = this.persistLeases.filter((item: BrowserTabsOverviewSnapshotPersistLease) => {
      return item.id !== lease.id;
    });
    if (lease.releaseRequested) {
      this.dependencies.releasePixelMap(lease.pixelMap);
    }
  }

  private requestReleasePersistLeasedPixelMap(pixelMap: image.PixelMap): boolean {
    let requested = false;
    this.persistLeases.forEach((lease: BrowserTabsOverviewSnapshotPersistLease) => {
      if (lease.pixelMap === pixelMap) {
        lease.releaseRequested = true;
        requested = true;
      }
    });
    return requested;
  }

  private releasePixelMapWithLeaseCheck(pixelMap: image.PixelMap): void {
    if (this.requestReleasePersistLeasedPixelMap(pixelMap)) {
      return;
    }
    this.dependencies.releasePixelMap(pixelMap);
  }

  private resolvePixelMapToReleaseAfterLeaseCheck(pixelMap?: image.PixelMap): image.PixelMap | undefined {
    if (pixelMap === undefined) {
      return undefined;
    }
    if (this.requestReleasePersistLeasedPixelMap(pixelMap)) {
      return undefined;
    }
    return pixelMap;
  }

  private withSession(
    state: BrowserTabsOverviewSnapshotPipelineState,
    session: BrowserTabsOverviewEntrySnapshotSessionState
  ): BrowserTabsOverviewSnapshotPipelineState {
    return {
      session: session,
      measuredEntryFrame: state.measuredEntryFrame
    };
  }

  private resolvePixelMapSize(
    pixelMap: image.PixelMap,
    fallbackWidth: number,
    fallbackHeight: number
  ): BrowserTabsOverlayRect {
    let width = Math.max(1, Math.round(fallbackWidth));
    let height = Math.max(1, Math.round(fallbackHeight));
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      width = Math.max(1, Math.floor(imageInfo.size.width));
      height = Math.max(1, Math.floor(imageInfo.size.height));
    } catch (_error) {
    }
    return {
      left: 0,
      top: 0,
      width: width,
      height: height
    };
  }

  private roundRect(rect: BrowserTabsOverlayRect): BrowserTabsOverlayRect {
    return {
      left: Math.round(rect.left),
      top: Math.round(rect.top),
      width: Math.max(1, Math.round(rect.width)),
      height: Math.max(1, Math.round(rect.height))
    };
  }

  private buildOverlayRect(rect: BrowserTabPreviewSourceRect): BrowserTabsOverlayRect {
    return {
      left: Math.round(rect.left),
      top: Math.round(rect.top),
      width: Math.max(1, Math.round(rect.width)),
      height: Math.max(1, Math.round(rect.height))
    };
  }

  private delay(timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, Math.max(0, Math.floor(timeoutMs)));
    });
  }
}
