import { image } from '@kit.ImageKit';
import { BrowserTabPreviewState } from './BrowserTabPreviewCoordinator';
import { BrowserTabState } from '../tabs/TabManager';
import {
  BrowserTabsOverlayRect,
  BrowserTabsOverlayViewModel,
  BrowserTabsSharedSnapshotVisualState
} from './BrowserTabsOverlayViewModel';
import {
  BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
  BROWSER_TAB_PREVIEW_PIXEL_WIDTH
} from './BrowserTabPreviewMetrics';
import { BrowserTabsOverviewLayoutViewModel } from './BrowserTabsOverviewLayoutViewModel';
import { BrowserTabsOverviewSectionPolicy } from './tabsOverview/BrowserTabsOverviewSectionPolicy';

export type BrowserTabsSharedSnapshotPhase =
  'idle' |
  'enterPreparing' |
  'enterAnimating' |
  'settled' |
  'exitPreparing' |
  'exitAnimating';

export type BrowserTabsSharedSnapshotDirection = 'enter' | 'exit';

export interface BrowserTabsSharedSnapshotTransitionState {
  phase: BrowserTabsSharedSnapshotPhase;
  direction: BrowserTabsSharedSnapshotDirection;
  tabId: string;
  progress: number;
  sourceRect: BrowserTabsOverlayRect;
  targetRect: BrowserTabsOverlayRect;
  imageUri: string;
  imagePixelMap?: image.PixelMap;
  imageRevision: number;
  imageWidth: number;
  imageHeight: number;
  useFullWebSnapshot: boolean;
  sourceImageTopInset: number;
  previewCornerRadius: number;
  imageBlurRadius: number;
}

export interface BrowserTabsSharedSnapshotTransitionInput {
  tabId: string;
  sourceRect: BrowserTabsOverlayRect;
  targetRect: BrowserTabsOverlayRect;
  imageUri: string;
  imagePixelMap?: image.PixelMap;
  imageRevision?: number;
  imageWidth: number;
  imageHeight: number;
  useFullWebSnapshot: boolean;
  sourceImageTopInset?: number;
  previewCornerRadius: number;
  imageBlurRadius?: number;
}

export interface BrowserTabsSharedSnapshotWindowInput {
  rootWidth: number;
  rootHeight: number;
  webLeft?: number;
  webTop: number;
  visualWebTop?: number;
  webWidth?: number;
  webHeight?: number;
  bottomInset: number;
  sourceImageTopInset?: number;
}

export interface BrowserTabsSharedSnapshotTargetRectInput {
  tabs: BrowserTabState[];
  tabId: string;
  measuredRect?: BrowserTabsOverlayRect;
  rootWidth: number;
  rootHeight?: number;
  topSafeInset: number;
}

export interface BrowserTabsSharedSnapshotImageInput {
  imageUri: string;
  imagePixelMap?: image.PixelMap;
  imageRevision: number;
  imageWidth: number;
  imageHeight: number;
  useFullWebSnapshot: boolean;
}

export interface BrowserTabsSharedSnapshotLayerPolicy {
  snapshotZIndex: number;
  snapshotDecorationZIndex: number;
  webChromeTopZIndex: number;
  webChromeBottomZIndex: number;
}

export interface BrowserTabsSharedSnapshotEntryOverlayPresentationState {
  frame: BrowserTabsOverlayRect;
  imageFrame: BrowserTabsOverlayRect;
  cornerRadius: number;
  imageClipHeight: number;
  clipImageToFrame: boolean;
  imageBlurRadius: number;
}

export interface BrowserTabsSharedSnapshotInterruptedEntryExitInput {
  state: BrowserTabsSharedSnapshotTransitionState;
  tabsOverlayExiting: boolean;
  entryAnimationActive: boolean;
  hasEntryPixelMap: boolean;
}

const EMPTY_RECT: BrowserTabsOverlayRect = {
  left: 0,
  top: 0,
  width: 1,
  height: 1
};

const LAYER_POLICY: BrowserTabsSharedSnapshotLayerPolicy = {
  snapshotZIndex: 340,
  snapshotDecorationZIndex: 345,
  webChromeBottomZIndex: 350,
  webChromeTopZIndex: 360
};

const EXIT_SOURCE_REVEAL_PROGRESS: number = 0.995;
const TAB_OVERVIEW_HORIZONTAL_PADDING: number = 16;
const TAB_OVERVIEW_TOP_SAFE_GAP: number = 10;
const TAB_OVERVIEW_PRIVATE_NOTICE_HEIGHT: number = 64;
const TAB_OVERVIEW_PRIVATE_NOTICE_BOTTOM_GAP: number = 14;

export function buildBrowserTabsSharedSnapshotIdleState(): BrowserTabsSharedSnapshotTransitionState {
  return {
    phase: 'idle',
    direction: 'enter',
    tabId: '',
    progress: 1,
    sourceRect: EMPTY_RECT,
    targetRect: EMPTY_RECT,
    imageUri: '',
    imagePixelMap: undefined,
    imageRevision: 0,
    imageWidth: 1,
    imageHeight: 1,
    useFullWebSnapshot: false,
    sourceImageTopInset: 0,
    previewCornerRadius: 0,
    imageBlurRadius: 0
  };
}

export class BrowserTabsSharedSnapshotTransitionCoordinator {
  private viewModel: BrowserTabsOverlayViewModel = new BrowserTabsOverlayViewModel();
  private layoutViewModel: BrowserTabsOverviewLayoutViewModel = new BrowserTabsOverviewLayoutViewModel();
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();
  private previewRectsByTabId: Record<string, BrowserTabsOverlayRect | undefined> = {};

  buildIdleState(): BrowserTabsSharedSnapshotTransitionState {
    return buildBrowserTabsSharedSnapshotIdleState();
  }

  shouldRenderInterruptedEntryExit(input: BrowserTabsSharedSnapshotInterruptedEntryExitInput): boolean {
    return input.state.direction === 'exit' &&
      input.tabsOverlayExiting &&
      input.entryAnimationActive &&
      input.hasEntryPixelMap;
  }

  buildEnterState(input: BrowserTabsSharedSnapshotTransitionInput): BrowserTabsSharedSnapshotTransitionState {
    return this.buildState('enterPreparing', 'enter', 0, input);
  }

  buildExitState(input: BrowserTabsSharedSnapshotTransitionInput): BrowserTabsSharedSnapshotTransitionState {
    return this.buildState('exitPreparing', 'exit', 0, input);
  }

  rememberPreviewRect(tabId: string, left: number, top: number, width: number, height: number): void {
    this.previewRectsByTabId[tabId] = {
      left: Math.round(left),
      top: Math.round(top),
      width: Math.round(width),
      height: Math.round(height)
    };
  }

  buildEnterStateFromContext(
    tabId: string,
    previewState: BrowserTabPreviewState | undefined,
    windowInput: BrowserTabsSharedSnapshotWindowInput,
    targetInput: BrowserTabsSharedSnapshotTargetRectInput,
    previewCornerRadius: number,
    imageBlurRadius: number = 0
  ): BrowserTabsSharedSnapshotTransitionState | undefined {
    const imageInput = this.buildImageInput(previewState);
    if (imageInput === undefined) {
      return undefined;
    }
    return this.buildEnterState({
      tabId: tabId,
      sourceRect: this.buildWebRect(windowInput),
      targetRect: this.buildTargetRectWithRememberedRect(targetInput),
      imageUri: imageInput.imageUri,
      imagePixelMap: imageInput.imagePixelMap,
      imageRevision: imageInput.imageRevision,
      imageWidth: imageInput.imageWidth,
      imageHeight: imageInput.imageHeight,
      useFullWebSnapshot: imageInput.useFullWebSnapshot,
      sourceImageTopInset: this.resolveSourceImageTopInset(windowInput),
      previewCornerRadius: previewCornerRadius,
      imageBlurRadius: imageBlurRadius
    });
  }

  buildExitStateFromContext(
    tabId: string,
    previewState: BrowserTabPreviewState | undefined,
    windowInput: BrowserTabsSharedSnapshotWindowInput,
    targetInput: BrowserTabsSharedSnapshotTargetRectInput,
    previewCornerRadius: number,
    imageBlurRadius: number = 0
  ): BrowserTabsSharedSnapshotTransitionState | undefined {
    const imageInput = this.buildImageInput(previewState);
    if (imageInput === undefined) {
      return undefined;
    }
    return this.buildExitState({
      tabId: tabId,
      sourceRect: this.buildWebRect(windowInput),
      targetRect: this.buildExitTargetRect(targetInput),
      imageUri: imageInput.imageUri,
      imagePixelMap: imageInput.imagePixelMap,
      imageRevision: imageInput.imageRevision,
      imageWidth: imageInput.imageWidth,
      imageHeight: imageInput.imageHeight,
      useFullWebSnapshot: imageInput.useFullWebSnapshot,
      sourceImageTopInset: this.resolveSourceImageTopInset(windowInput),
      previewCornerRadius: previewCornerRadius,
      imageBlurRadius: imageBlurRadius
    });
  }

  buildImageInput(previewState?: BrowserTabPreviewState): BrowserTabsSharedSnapshotImageInput | undefined {
    const sharedImageUri = previewState?.sharedSnapshotImageUri?.trim() ?? '';
    if (previewState === undefined || (sharedImageUri.length <= 0 && previewState.sharedSnapshotPixelMap === undefined)) {
      return undefined;
    }
    const imageRevision = this.resolvePreviewImageRevision(previewState);
    return {
      imageUri: sharedImageUri,
      imagePixelMap: previewState.sharedSnapshotPixelMap,
      imageRevision: imageRevision,
      imageWidth: Math.max(1, Math.floor(previewState.sharedSnapshotImageWidth ?? BROWSER_TAB_PREVIEW_PIXEL_WIDTH)),
      imageHeight: Math.max(1, Math.floor(previewState.sharedSnapshotImageHeight ?? BROWSER_TAB_PREVIEW_PIXEL_HEIGHT)),
      useFullWebSnapshot: true
    };
  }

  buildWebRect(input: BrowserTabsSharedSnapshotWindowInput): BrowserTabsOverlayRect {
    if (this.isPositiveNumber(input.webWidth) && this.isPositiveNumber(input.webHeight)) {
      const measuredTop = Math.max(0, Math.round(input.webTop));
      const visualTop = this.resolveVisualWebTop(input);
      const topDelta = Math.max(0, visualTop - measuredTop);
      return {
        left: Math.max(0, Math.round(input.webLeft ?? 0)),
        top: visualTop,
        width: Math.max(1, Math.round(input.webWidth as number)),
        height: Math.max(1, Math.round((input.webHeight as number) - topDelta))
      };
    }
    const top = this.resolveVisualWebTop(input);
    return {
      left: 0,
      top: top,
      width: Math.max(1, Math.round(input.rootWidth)),
      height: Math.max(1, Math.round(input.rootHeight - top - Math.max(0, input.bottomInset)))
    };
  }

  buildTargetRect(input: BrowserTabsSharedSnapshotTargetRectInput): BrowserTabsOverlayRect {
    if (this.isUsableOptionalRect(input.measuredRect)) {
      return input.measuredRect as BrowserTabsOverlayRect;
    }
    const visibleTabs = this.resolveTargetSectionTabs(input.tabs, input.tabId);
    const layoutState = this.layoutViewModel.buildState({
      gridWidth: Math.max(1, input.rootWidth - (TAB_OVERVIEW_HORIZONTAL_PADDING * 2)),
      sheetWidth: input.rootWidth,
      sheetHeight: input.rootHeight ?? input.rootWidth
    });
    const rect = this.viewModel.buildPredictedPreviewRect({
      tabIds: visibleTabs.map((tab: BrowserTabState) => tab.id),
      tabId: input.tabId,
      gridWidth: Math.max(1, input.rootWidth - (TAB_OVERVIEW_HORIZONTAL_PADDING * 2)),
      fallbackSheetWidth: input.rootWidth,
      viewportHeight: input.rootHeight,
      horizontalPadding: TAB_OVERVIEW_HORIZONTAL_PADDING,
      columnCount: layoutState.columnCount,
      gridGap: layoutState.gridGap,
      topPadding: this.resolveTargetSectionTopPadding(input, visibleTabs),
      headerHeight: 0,
      headerContentGap: 0,
      identityHeaderHeight: layoutState.identityHeaderHeight,
      identityPreviewGap: layoutState.identityPreviewGap,
      previewHeight: layoutState.previewHeight
    });
    if (rect !== undefined) {
      return {
        left: Math.round(rect.left),
        top: Math.round(rect.top),
        width: Math.round(rect.width),
        height: Math.round(rect.height)
      };
    }
    return {
      left: TAB_OVERVIEW_HORIZONTAL_PADDING,
      top: this.resolveTargetSectionTopPadding(input, visibleTabs) +
        layoutState.identityHeaderHeight + layoutState.identityPreviewGap,
      width: Math.round(layoutState.cardWidth),
      height: Math.round(layoutState.previewHeight)
    };
  }

  private resolveTargetSectionTabs(tabs: BrowserTabState[], tabId: string): BrowserTabState[] {
    const targetTab = tabs.find((tab: BrowserTabState) => tab.id === tabId);
    const targetSection = this.sectionPolicy.resolveSectionForTab(targetTab);
    return tabs.filter((tab: BrowserTabState) => {
      if (tab.isHome) {
        return false;
      }
      return this.sectionPolicy.belongsToSection(tab, targetSection);
    });
  }

  private resolveTargetSectionTopPadding(
    input: BrowserTabsSharedSnapshotTargetRectInput,
    visibleTabs: BrowserTabState[]
  ): number {
    const baseTopPadding = Math.max(TAB_OVERVIEW_HORIZONTAL_PADDING, input.topSafeInset + TAB_OVERVIEW_TOP_SAFE_GAP);
    const targetTab = visibleTabs.find((tab: BrowserTabState) => tab.id === input.tabId);
    if (this.sectionPolicy.isPrivateTab(targetTab)) {
      return baseTopPadding + TAB_OVERVIEW_PRIVATE_NOTICE_HEIGHT + TAB_OVERVIEW_PRIVATE_NOTICE_BOTTOM_GAP;
    }
    return baseTopPadding;
  }

  buildTargetRectWithRememberedRect(input: BrowserTabsSharedSnapshotTargetRectInput): BrowserTabsOverlayRect {
    const rememberedRect = this.previewRectsByTabId[input.tabId];
    return this.buildTargetRect({
      tabs: input.tabs,
      tabId: input.tabId,
      measuredRect: this.isUsableOptionalRect(input.measuredRect) ? input.measuredRect : rememberedRect,
      rootWidth: input.rootWidth,
      rootHeight: input.rootHeight,
      topSafeInset: input.topSafeInset
    });
  }

  private buildExitTargetRect(input: BrowserTabsSharedSnapshotTargetRectInput): BrowserTabsOverlayRect {
    return this.buildTargetRectWithRememberedRect(input);
  }

  withProgress(
    state: BrowserTabsSharedSnapshotTransitionState,
    progress: number
  ): BrowserTabsSharedSnapshotTransitionState {
    return {
      phase: state.direction === 'enter' ? 'enterAnimating' : 'exitAnimating',
      direction: state.direction,
      tabId: state.tabId,
      progress: this.clampProgress(progress),
      sourceRect: state.sourceRect,
      targetRect: state.targetRect,
      imageUri: state.imageUri,
      imagePixelMap: state.imagePixelMap,
      imageRevision: state.imageRevision,
      imageWidth: state.imageWidth,
      imageHeight: state.imageHeight,
      useFullWebSnapshot: state.useFullWebSnapshot,
      sourceImageTopInset: state.sourceImageTopInset,
      previewCornerRadius: state.previewCornerRadius,
      imageBlurRadius: state.imageBlurRadius
    };
  }

  withTargetRect(
    state: BrowserTabsSharedSnapshotTransitionState,
    targetRect: BrowserTabsOverlayRect
  ): BrowserTabsSharedSnapshotTransitionState {
    if (state.direction === 'exit') {
      return state;
    }
    if (!this.isUsableRect(targetRect)) {
      return state;
    }
    return {
      phase: state.phase,
      direction: state.direction,
      tabId: state.tabId,
      progress: state.progress,
      sourceRect: state.sourceRect,
      targetRect: {
        left: Math.round(targetRect.left),
        top: Math.round(targetRect.top),
        width: Math.round(targetRect.width),
        height: Math.round(targetRect.height)
      },
      imageUri: state.imageUri,
      imagePixelMap: state.imagePixelMap,
      imageRevision: state.imageRevision,
      imageWidth: state.imageWidth,
      imageHeight: state.imageHeight,
      useFullWebSnapshot: state.useFullWebSnapshot,
      sourceImageTopInset: state.sourceImageTopInset,
      previewCornerRadius: state.previewCornerRadius,
      imageBlurRadius: state.imageBlurRadius
    };
  }

  buildExitStateFromInterruptedEnter(
    state: BrowserTabsSharedSnapshotTransitionState,
    targetRect: BrowserTabsOverlayRect
  ): BrowserTabsSharedSnapshotTransitionState | undefined {
    if (state.direction !== 'enter' || !this.isUsableRect(state.sourceRect) || !this.isUsableRect(targetRect)) {
      return undefined;
    }
    return {
      phase: 'exitPreparing',
      direction: 'exit',
      tabId: state.tabId,
      progress: 0,
      sourceRect: state.sourceRect,
      targetRect: {
        left: Math.round(targetRect.left),
        top: Math.round(targetRect.top),
        width: Math.round(targetRect.width),
        height: Math.round(targetRect.height)
      },
      imageUri: state.imageUri,
      imagePixelMap: state.imagePixelMap,
      imageRevision: state.imageRevision,
      imageWidth: state.imageWidth,
      imageHeight: state.imageHeight,
      useFullWebSnapshot: state.useFullWebSnapshot,
      sourceImageTopInset: state.sourceImageTopInset,
      previewCornerRadius: state.previewCornerRadius,
      imageBlurRadius: state.imageBlurRadius
    };
  }

  buildInterruptedEntryExitTargetRect(
    state: BrowserTabsSharedSnapshotTransitionState,
    measuredFrame?: BrowserTabsOverlayRect
  ): BrowserTabsOverlayRect {
    const visualState = this.buildVisualState(state);
    const frame = this.isUsableOptionalRect(measuredFrame) ? measuredFrame as BrowserTabsOverlayRect : visualState.frame;
    const progress = this.resolveInterruptedEntryProgress(state, frame);
    const sourceImageHeight = Math.max(1, state.sourceRect.height);
    const targetImageHeight = Math.max(1, state.targetRect.height);
    const imageHeight = Math.max(1, Math.round(this.lerp(sourceImageHeight, targetImageHeight, progress)));
    return {
      left: Math.round(frame.left),
      top: Math.round(frame.top),
      width: Math.max(1, Math.round(frame.width)),
      height: Math.max(1, Math.min(Math.round(frame.height), imageHeight))
    };
  }

  resolveInterruptedEntryExitDurationMs(
    state: BrowserTabsSharedSnapshotTransitionState,
    targetRect: BrowserTabsOverlayRect,
    baseDurationMs: number
  ): number {
    const progress = this.resolveInterruptedEntryProgress(state, targetRect);
    return Math.max(120, Math.min(baseDurationMs, Math.round(baseDurationMs * Math.max(0.25, progress))));
  }

  buildVisualState(state: BrowserTabsSharedSnapshotTransitionState): BrowserTabsSharedSnapshotVisualState {
    return this.viewModel.buildSharedSnapshotVisualState({
      direction: state.direction,
      progress: state.progress,
      sourceRect: state.sourceRect,
      targetRect: state.targetRect,
      targetPreviewHeight: this.resolveTargetPreviewHeight(state),
      sourceImageTopInset: state.sourceImageTopInset,
      previewCornerRadius: state.previewCornerRadius,
      useFullWebSnapshot: state.useFullWebSnapshot,
      imageWidth: state.imageWidth,
      imageHeight: state.imageHeight
    });
  }

  buildEntryOverlayPresentationState(
    state: BrowserTabsSharedSnapshotTransitionState
  ): BrowserTabsSharedSnapshotEntryOverlayPresentationState {
    const visualState = this.buildVisualState(state);
    const frame = this.buildPositiveRect(visualState.frame);
    const imageFrame = this.buildPositiveRect(visualState.imageFrame);
    const clipImageToFrame = this.shouldClipOverlayImageToFrame(state);
    const imageClipHeight = this.resolveOverlayImageClipHeight(state, frame, imageFrame);
    return {
      frame: frame,
      imageFrame: imageFrame,
      cornerRadius: visualState.cornerRadius,
      imageClipHeight: imageClipHeight,
      clipImageToFrame: clipImageToFrame,
      imageBlurRadius: Math.max(0, state.imageBlurRadius)
    };
  }

  shouldShowOverlay(state: BrowserTabsSharedSnapshotTransitionState): boolean {
    if (state.phase === 'idle' || state.phase === 'settled') {
      return false;
    }
    const hasVisualSurface = this.hasImage(state);
    return state.tabId.length > 0 && hasVisualSurface &&
      this.isUsableRect(state.sourceRect) && this.isUsableRect(state.targetRect);
  }

  shouldHideWebLayer(state: BrowserTabsSharedSnapshotTransitionState): boolean {
    return this.shouldShowOverlay(state) && state.phase !== 'settled' && state.phase !== 'idle';
  }

  shouldRevealExitSourceSurface(state: BrowserTabsSharedSnapshotTransitionState): boolean {
    if (!this.shouldShowOverlay(state) || state.direction !== 'exit') {
      return true;
    }
    return state.progress >= EXIT_SOURCE_REVEAL_PROGRESS;
  }

  resolveLayerPolicy(): BrowserTabsSharedSnapshotLayerPolicy {
    return LAYER_POLICY;
  }

  private buildState(
    phase: BrowserTabsSharedSnapshotPhase,
    direction: BrowserTabsSharedSnapshotDirection,
    progress: number,
    input: BrowserTabsSharedSnapshotTransitionInput
  ): BrowserTabsSharedSnapshotTransitionState {
    return {
      phase: phase,
      direction: direction,
      tabId: input.tabId,
      progress: progress,
      sourceRect: input.sourceRect,
      targetRect: input.targetRect,
      imageUri: input.imageUri,
      imagePixelMap: input.imagePixelMap,
      imageRevision: this.normalizeImageRevision(input.imageRevision),
      imageWidth: Math.max(1, Math.floor(input.imageWidth)),
      imageHeight: Math.max(1, Math.floor(input.imageHeight)),
      useFullWebSnapshot: input.useFullWebSnapshot,
      sourceImageTopInset: this.normalizeSourceImageTopInset(input.sourceImageTopInset),
      previewCornerRadius: input.previewCornerRadius,
      imageBlurRadius: Math.max(0, input.imageBlurRadius ?? 0)
    };
  }

  private hasImage(state: BrowserTabsSharedSnapshotTransitionState): boolean {
    return state.imageUri.trim().length > 0 || state.imagePixelMap !== undefined;
  }

  private isUsableRect(rect: BrowserTabsOverlayRect): boolean {
    return rect.width > 0 && rect.height > 0;
  }

  private isUsableOptionalRect(rect?: BrowserTabsOverlayRect): boolean {
    return rect !== undefined && rect.width > 0 && rect.height > 0;
  }

  private isPositiveNumber(value?: number): boolean {
    return value !== undefined && Number.isFinite(value) && value > 0;
  }

  private normalizeSourceImageTopInset(value?: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0;
    }
    return Math.round(value);
  }

  private resolvePreviewImageRevision(previewState: BrowserTabPreviewState): number {
    return this.normalizeImageRevision(previewState.transitionCapturedAt ?? previewState.capturedAt);
  }

  private normalizeImageRevision(value?: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private resolveVisualWebTop(input: BrowserTabsSharedSnapshotWindowInput): number {
    const measuredTop = Math.max(0, Math.round(input.webTop));
    if (!this.isPositiveNumber(input.visualWebTop)) {
      return measuredTop;
    }
    return Math.max(measuredTop, Math.round(input.visualWebTop as number));
  }

  private resolveSourceImageTopInset(input: BrowserTabsSharedSnapshotWindowInput): number {
    if (input.sourceImageTopInset !== undefined && Number.isFinite(input.sourceImageTopInset)) {
      return Math.round(input.sourceImageTopInset);
    }
    const measuredTop = Math.max(0, Math.round(input.webTop));
    const visualTop = this.resolveVisualWebTop(input);
    return Math.max(0, visualTop - measuredTop);
  }

  private resolveTargetPreviewHeight(state: BrowserTabsSharedSnapshotTransitionState): number {
    return Math.max(1, state.targetRect.height);
  }

  private buildPositiveRect(rect: BrowserTabsOverlayRect): BrowserTabsOverlayRect {
    return {
      left: rect.left,
      top: rect.top,
      width: Math.max(1, rect.width),
      height: Math.max(1, rect.height)
    };
  }

  private shouldClipOverlayImageToFrame(_state: BrowserTabsSharedSnapshotTransitionState): boolean {
    return true;
  }

  private resolveOverlayImageClipHeight(
    _state: BrowserTabsSharedSnapshotTransitionState,
    frame: BrowserTabsOverlayRect,
    _imageFrame: BrowserTabsOverlayRect
  ): number {
    return Math.max(1, frame.height);
  }

  private resolveInterruptedEntryProgress(
    state: BrowserTabsSharedSnapshotTransitionState,
    frame: BrowserTabsOverlayRect
  ): number {
    const sourceWidth = Math.max(1, state.sourceRect.width);
    const targetWidth = Math.max(1, state.targetRect.width);
    if (Math.abs(targetWidth - sourceWidth) > 0.5) {
      return this.clampProgress((frame.width - sourceWidth) / (targetWidth - sourceWidth));
    }
    const sourceHeight = Math.max(1, state.sourceRect.height);
    const targetHeight = Math.max(1, state.targetRect.height);
    if (Math.abs(targetHeight - sourceHeight) > 0.5) {
      return this.clampProgress((frame.height - sourceHeight) / (targetHeight - sourceHeight));
    }
    return this.clampProgress(state.progress);
  }

  private clampProgress(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  private lerp(start: number, end: number, progress: number): number {
    return start + ((end - start) * progress);
  }

}
