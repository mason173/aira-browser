import { curves, FrameCallback } from '@kit.ArkUI';
import {
  HomeSearchPanelDetent,
  HomeSearchPanelDetentMetrics,
  HomeSearchPanelDetentViewModel
} from '../../../core/browser/HomeSearchPanelDetentViewModel';
import {
  BrowserBottomPanelMotionState,
  DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE
} from '../../../core/browser/BrowserBottomAddressPanelViewModel';
import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HEADER_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING,
  BROWSER_BOTTOM_ADDRESS_PANEL_PEEK_HEIGHT,
  BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT,
  BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_BOTTOM_PANEL_GLASS_BACKDROP_BLUR_RADIUS,
  withBrowserBottomPanelGlassTint
} from '../../../core/theme/BrowserBottomPanelGlassTheme';
import {
  BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_DURATION_MS,
  BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS,
  BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  resolveBrowserBottomPanelFastExitCurve,
  resolveBrowserBottomPanelMiddleSnapCurve,
  resolveBrowserBottomPanelMotionCurve
} from '../../../core/browser/BrowserBottomPanelMotionTokens';
import {
  resolveBrowserBottomFloatingExpandedContainerColor,
  resolveBrowserBottomFloatingHeaderColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import {
  BROWSER_FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS,
  BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE,
  resolveBrowserFloatingGlassMaterialOptionsForMode,
  resolveBrowserFloatingGlassMaterialTintForMode
} from './BrowserFloatingGlassMaterialTokens';

export type BrowserDetentBottomPanelMode = 'bar' | 'overlay' | 'sheet';
export type BrowserDetentBottomPanelFloatingLayoutMode = 'stack' | 'input';
export type BrowserDetentBottomPanelMaterialThemeMode = 'system' | 'light' | 'dark';
export type BrowserDetentBottomPanelGestureReleaseDisposition = 'default' | 'stay-middle';
export type BrowserDetentBottomPanelGestureInterceptTarget = HomeSearchPanelDetent | undefined;

export interface BrowserDetentBottomPanelGestureFrame {
  phase: 'start' | 'update';
  panelHeight: number;
  offsetY: number;
  startX: number;
  panelWidth: number;
}

class BrowserDetentBottomPanelFrameCallback extends FrameCallback {
  private callback: (frameTimeInNano: number) => void;

  constructor(callback: (frameTimeInNano: number) => void) {
    super();
    this.callback = callback;
  }

  onFrame(frameTimeInNano: number): void {
    this.callback(frameTimeInNano);
  }
}

export const BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT: number = BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT;

interface BrowserDetentFloatingHeaderBackgroundState {
  keepDefaultChrome: boolean;
  collapsedDarkBackground: boolean;
  grayProgress: number;
}

const BROWSER_DETENT_PANEL_CLOSE_ANIMATION_DURATION_MS: number = BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS;
const BROWSER_DETENT_PANEL_OPEN_ANIMATION_DURATION_MS: number = BROWSER_DETENT_PANEL_CLOSE_ANIMATION_DURATION_MS;
const BROWSER_DETENT_PANEL_SNAP_ANIMATION_DURATION_MS: number = BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS;
const BROWSER_DETENT_PANEL_MIDDLE_SNAP_ANIMATION_DURATION_MS: number = BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS;
const BROWSER_DETENT_PANEL_CLOSE_CURVE: Curve = resolveBrowserBottomPanelFastExitCurve();
const BROWSER_DETENT_PANEL_OPEN_CURVE: ICurve = resolveBrowserBottomPanelMotionCurve();
const BROWSER_DETENT_PANEL_COLLAPSED_SIDE_INSET: number = 4;
const BROWSER_DETENT_PANEL_SIDE_PADDING: number = 22;
const BROWSER_DETENT_PANEL_SIDE_PADDING_WITH_HANDLE: number = 12;
const BROWSER_DETENT_PANEL_TOP_PADDING: number = 18;
const BROWSER_DETENT_PANEL_TOP_PADDING_WITH_HANDLE: number = 6;
const BROWSER_DETENT_PANEL_BOTTOM_PADDING: number = 30;
const BROWSER_DETENT_PANEL_RADIUS: number = BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT / 2;
const BROWSER_DETENT_FLOATING_HEADER_RADIUS: number = BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT / 2;
const BROWSER_DETENT_FLOATING_SIDE_INSET: number = BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET;
const BROWSER_DETENT_FLOATING_CONTENT_RADIUS: number = 36;
const BROWSER_DETENT_FLOATING_HEADER_MOTION_DURATION_MS: number = BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS;
const BROWSER_DETENT_FLOATING_HEADER_MOTION_CURVE: ICurve = resolveBrowserBottomPanelMotionCurve();
const BROWSER_DETENT_FLOATING_HEADER_CHROME_TRANSITION_MS: number = 140;
const BROWSER_DETENT_PANEL_SNAP_CURVE: ICurve = resolveBrowserBottomPanelMotionCurve();
const BROWSER_DETENT_PANEL_MIDDLE_SNAP_CURVE: ICurve = resolveBrowserBottomPanelMiddleSnapCurve();
const BROWSER_DETENT_PANEL_LOW_SETTLE_CURVE: ICurve = resolveBrowserBottomPanelMotionCurve();
const BROWSER_DETENT_DRAG_HANDLE_WIDTH: number = 34;
const BROWSER_DETENT_DRAG_HANDLE_HEIGHT: number = 4;
const BROWSER_DETENT_DRAG_HANDLE_BOTTOM_GAP: number = 6;
const BROWSER_DETENT_DRAG_HANDLE_RADIUS: number = BROWSER_DETENT_DRAG_HANDLE_HEIGHT / 2;
const BROWSER_DETENT_PAN_START_DISTANCE: number = 10;
const BROWSER_DETENT_CONTENT_DRAG_REVEAL_THRESHOLD: number = 2;
const BROWSER_DETENT_UPWARD_RUBBER_BAND_LINEAR_DISTANCE: number = 44;
const BROWSER_DETENT_UPWARD_RUBBER_BAND_LIMIT: number = 160;
const BROWSER_DETENT_UPWARD_RUBBER_BAND_DISTANCE: number = 160;
const BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LINEAR_DISTANCE: number = 24;
const BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LIMIT: number = 72;
const BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_DISTANCE: number = 132;
const BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_START_PROGRESS: number = 0;
const BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_END_PROGRESS: number = 0.18;
const BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_TRANSLATE_Y: number = 10;
const BROWSER_DETENT_FLOATING_CONTENT_ENTER_TRANSLATE_Y: number = 36;
const BROWSER_DETENT_FLOATING_CONTENT_ENTER_INITIAL_SCALE: number = 0.94;
const BROWSER_DETENT_FLOATING_CONTENT_EXIT_TRANSLATE_Y: number = 8;
const BROWSER_DETENT_FLOATING_CONTENT_ENTER_OPACITY_DURATION_MS: number = 160;
const BROWSER_DETENT_FLOATING_CONTENT_ENTER_CURVE: ICurve = curves.springMotion(0.42, 0.62);
const BROWSER_DETENT_FLOATING_PANEL_SHADOW_RADIUS: number = 16;
const BROWSER_DETENT_FLOATING_PANEL_SHADOW_COLOR: string = '#14000000';
const BROWSER_DETENT_FLOATING_PANEL_SHADOW_OFFSET_Y: number = 0;
const BROWSER_DETENT_FLOATING_HOST_RESIZE_MOTION_THRESHOLD: number = 2;

@Component
export struct BrowserDetentBottomPanel {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State private panelDetent: HomeSearchPanelDetent = 'low';
  @State private currentPanelHeight: number = BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT;
  @State private isDraggingPanel: boolean = false;
  @State private isPeekToLowPanelTransition: boolean = false;
  @State private shouldRevealPanelContent: boolean = false;
  @State private hostWidth: number = 0;
  @State private floatingInputStableHostHeight: number = 0;
  @State private floatingHostResizeTranslateY: number = 0;
  @State private floatingHostResizeMotionActive: boolean = false;
  @State private floatingHeaderShadowVisible: boolean = true;
  @State private floatingHeaderBackgroundKeepDefaultChrome: boolean = true;
  @State private floatingHeaderBackgroundCollapsedDark: boolean = true;
  @State private floatingHeaderBackgroundGrayProgress: number = 0;
  private hostGlobalTop: number = 0;
  private hostHeight: number = 0;
  private floatingInputStableHostWidth: number = 0;
  private lastGeometrySyncHostWidth: number = 0;
  private lastGeometrySyncHostHeight: number = 0;
  private dragStartPanelHeight: number = BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT;
  private dragStartLocalX: number = -1;
  private dragGestureWidth: number = 0;
  private dragLastOffsetY: number = 0;
  private dragLastUpdateAtMs: number = 0;
  private dragReleaseVelocityY: number = 0;
  private pendingPanelDragOffsetY: number | undefined = undefined;
  private panelDragFrameCallbackScheduled: boolean = false;
  private panelDragFrameRunId: number = 0;
  private deferredFloatingCollapseAfterContentExit: boolean = false;
  private lastReportedPanelVisualHeight: number = -1;
  private isSettlingPanelDetent: boolean = false;
  private panelSettlingTimer: number = -1;
  private floatingHostResizeMotionTimer: number = -1;
  private detentChangeNotificationTimer: number = -1;
  private pendingDetentChangeNotification: HomeSearchPanelDetent | undefined = undefined;
  private floatingInputHostResizeMotionConsumed: boolean = false;
  private lastFloatingLayoutMode: BrowserDetentBottomPanelFloatingLayoutMode = 'stack';
  private deferredPanelDetentChange: HomeSearchPanelDetent | undefined = undefined;
  private motionStateInitialized: boolean = false;
  private lastMotionStateVisible: boolean = true;
  private lastMotionStateTargetDetent: HomeSearchPanelDetent = 'low';
  private lastMotionStateGeometryKey: string = '';
  private panelDetentViewModel: HomeSearchPanelDetentViewModel = new HomeSearchPanelDetentViewModel();
  @Prop mode: BrowserDetentBottomPanelMode = 'overlay';
  @Prop @Watch('syncMotionState') motionState: BrowserBottomPanelMotionState =
    DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE;
  @Prop deferLowDetentChangeUntilSettled: boolean = false;
  @Prop barOpacity: number = 1;
  @Prop materialThemeMode: BrowserDetentBottomPanelMaterialThemeMode = 'system';
  @Prop panelBackgroundColor: ResourceColor | undefined = undefined;
  @Prop dragHandleColor: ResourceColor | undefined = undefined;
  @Prop showDragHandle: boolean = false;
  @Prop panelWidth: number = 0;
  @Prop panelOffsetX: number = 0;
  @Prop contentVisibleWhenMiddle: boolean = true;
  @Prop floatingBlocksEnabled: boolean = false;
  @Prop @Watch('syncCurrentPanelGeometry') floatingLayoutMode: BrowserDetentBottomPanelFloatingLayoutMode = 'stack';
  @Prop floatingExpandedContentPrepared: boolean = false;
  @Prop floatingExpandedContentVisible: boolean = true;
  @Prop floatingExpandedContentBodyVisible: boolean = true;
  @Prop floatingExpandedContentGeometryLocked: boolean = false;
  @Prop floatingContentFirstCollapseEnabled: boolean = false;
  @Prop @Watch('resumeDeferredFloatingCollapseAfterContentExit')
  floatingContentFirstCollapseActive: boolean = false;
  @Prop @Watch('syncFloatingExpandedContentHeight') floatingExpandedContentHeight: number = 0;
  @Prop floatingOverlayPanEnabled: boolean = false;
  @Prop @Watch('syncCurrentPanelGeometry') floatingExpandedSurfaceCoversHeader: boolean = false;
  @Prop @Watch('syncCurrentPanelGeometry') floatingExpandedSurfaceCoverProgress: number = 0;
  @Prop floatingExpandedSurfaceChromeVisible: boolean = true;
  @Prop floatingExpandedHeaderHorizontalInset: number = 0;
  @Watch('syncCurrentPanelGeometry')
  @Prop floatingTopContentVisible: boolean = false;
  @Watch('syncCurrentPanelGeometry')
  @Prop floatingTopContentHeight: number = 0;
  @Prop floatingContentRenderKey: string = '';
  @Prop floatingTopSurfaceChromeVisible: boolean = true;
  @Prop floatingHeaderChromeVisible: boolean = true;
  @Prop floatingHeaderPresentationOpacity: number = 1;
  @Prop floatingHeaderInteractionEnabled: boolean = true;
  @Prop floatingHeaderHorizontalPadding: number =
    BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HEADER_HORIZONTAL_PADDING;
  @Prop floatingHeaderPresentationTranslateY: number = 0;
  @Prop floatingHeaderInteractionWidth: number = 0;
  @Prop floatingHeaderInteractionHeight: number = 0;
  @Prop floatingHeaderInteractionOffsetY: number = 0;
  @Prop floatingHeaderTracksPanelMotion: boolean = false;
  @Prop lightweightCollapsedMotion: boolean = false;
  @Prop liveBackdropBlurSuppressed: boolean = false;
  onDetentChange: (detent: HomeSearchPanelDetent) => void = (_detent: HomeSearchPanelDetent) => {};
  onPanelGestureFrame: (frame: BrowserDetentBottomPanelGestureFrame) => void =
    (_frame: BrowserDetentBottomPanelGestureFrame) => {};
  onPanelVisualHeightChange: (panelHeight: number) => void = (_panelHeight: number) => {};
  onHostGeometryReady: (hostWidth: number, hostHeight: number) => void =
    (_hostWidth: number, _hostHeight: number) => {};
  onPanelGestureEnd: (panelHeight: number, targetDetent: HomeSearchPanelDetent) => void =
    (_panelHeight: number, _targetDetent: HomeSearchPanelDetent) => {};
  onPanelGestureEndIntercept:
    (panelHeight: number, targetDetent: HomeSearchPanelDetent, offsetY: number, startX: number, panelWidth: number) =>
    BrowserDetentBottomPanelGestureInterceptTarget =
    (_panelHeight: number, _targetDetent: HomeSearchPanelDetent, _offsetY: number, _startX: number,
      _panelWidth: number) => undefined;
  onPanelGestureRelease:
    (panelHeight: number, targetDetent: HomeSearchPanelDetent, offsetY: number, velocityY: number) =>
      BrowserDetentBottomPanelGestureReleaseDisposition =
    (_panelHeight: number, _targetDetent: HomeSearchPanelDetent, _offsetY: number, _velocityY: number) => 'default';
  onExpandToMiddle: () => void = () => {};
  onCollapse: () => void = () => {};
  onPanelSettled: (detent: HomeSearchPanelDetent) => void = (_detent: HomeSearchPanelDetent) => {};
  @BuilderParam floatingTopContent: () => void = this.emptyBuilder;
  @BuilderParam header: () => void = this.emptyBuilder;
  @BuilderParam expandedContent: () => void = this.emptyBuilder;

  aboutToAppear(): void {
    this.lastFloatingLayoutMode = this.floatingLayoutMode;
    this.motionStateInitialized = false;
    this.syncMotionState();
    this.syncFloatingHeaderBackgroundState(false);
  }

  aboutToDisappear(): void {
    this.invalidatePendingPanelDragFrame();
    this.deferredFloatingCollapseAfterContentExit = false;
    this.clearPanelSettlingTimer();
    this.clearFloatingHostResizeMotionTimer();
    this.clearDetentChangeNotification();
  }

  build() {
    if (this.mode === 'overlay' && this.floatingBlocksEnabled) {
      this.buildFloatingOverlay()
    } else if (this.mode === 'overlay') {
      Stack() {
        Column() {
          this.buildPanel(true)
        }
        .width(this.resolveOverlayPanelWidth())
        .height(this.getOverlayPanelLayoutHeight())
        .position({ x: this.resolveOverlayPanelOffsetX(), y: this.getOverlayPanelTop() })
        .translate({ y: this.resolveOverlayPanelTranslateY() })
        .opacity(this.shouldHideOverlayPanel() ? 0 : 1)
        .hitTestBehavior(this.shouldEnableOverlayPanelHitTest() ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
        .clip(this.shouldClipOverlayPanel())
        .animation({
          duration: this.isDraggingPanel ? 0 : this.getPanelAnimationDuration(),
          curve: this.getPanelAnimationCurve()
        })
      }
      .width('100%')
      .height('100%')
      .hitTestBehavior(this.motionState.visible ? HitTestMode.Transparent : HitTestMode.None)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.rememberOverlayHostArea(newArea);
      })
    } else if (this.mode === 'sheet') {
      Column() {
        this.buildPanel(true)
      }
      .width('100%')
      .height(this.getPanelHeight())
    } else {
      Column() {
        this.buildPanel(false)
      }
      .width(this.resolveCollapsedPanelWidth())
      .height(BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT)
      .padding({ left: BROWSER_DETENT_PANEL_COLLAPSED_SIDE_INSET, right: BROWSER_DETENT_PANEL_COLLAPSED_SIDE_INSET })
      .position({ x: this.resolveCollapsedPanelOffsetX(), y: 0 })
      .opacity(this.barOpacity)
    }
  }

  @Builder
  private buildFloatingOverlay() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.floatingOverlayPanEnabled) {
        this.buildFloatingOverlayPanSurface()
      }
      if (this.shouldAnchorFloatingHeaderToBottom()) {
        this.buildFloatingOverlayPanelMotionProbe()
      }
      if (this.shouldShowFloatingTopContent()) {
        this.buildFloatingOverlayTopSurface()
      }
      if (this.shouldPrepareFloatingExpandedContent()) {
        this.buildFloatingOverlayExpandedSurface()
      }
      this.buildFloatingOverlayHeaderShadowSurface()
      this.buildFloatingOverlayHeaderSurface()
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.motionState.visible ? HitTestMode.Transparent : HitTestMode.None)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.rememberOverlayHostArea(newArea);
    })
  }

  @Builder
  private buildFloatingOverlayPanSurface() {
    Column()
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)
      .gesture(
        PanGesture({
          direction: this.floatingOverlayPanEnabled ? PanDirection.Vertical : PanDirection.None,
          distance: BROWSER_DETENT_PAN_START_DISTANCE
        })
          .onActionStart((event: GestureEvent) => {
            if (!this.floatingOverlayPanEnabled) {
              return;
            }
            this.rememberPanelGestureStart(event);
            this.beginPanelDrag();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.floatingOverlayPanEnabled) {
              return;
            }
            this.updatePanelDrag(event);
          })
          .onActionEnd((event: GestureEvent) => {
            if (!this.floatingOverlayPanEnabled) {
              return;
            }
            this.handlePanelPanEnd(event);
          })
          .onActionCancel(() => {
            if (!this.floatingOverlayPanEnabled) {
              return;
            }
            this.endPanelDrag(0);
          }),
        GestureMask.Normal
      )
  }

  @Builder
  private buildFloatingOverlayPanelMotionProbe() {
    Column()
      .width(1)
      .height(1)
      .position({ x: 0, y: this.resolveFloatingPanelMotionGlobalTop() })
      .animation({
        duration: this.resolveFloatingSurfaceMotionDuration(),
        curve: this.getPanelAnimationCurve()
      })
      .hitTestBehavior(HitTestMode.None)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.reportFloatingPanelVisualHeightFromArea(newArea, 'motion-probe');
      })
  }

  @Builder
  private buildFloatingOverlayTopSurface() {
    Column() {
      ForEach([this.buildFloatingTopContentRenderKey()], (_renderKey: string) => {
        this.floatingTopContent()
      }, (renderKey: string) => renderKey)
    }
    .width(this.resolveOverlayPanelWidth())
    .height(this.resolveFloatingTopSurfaceHeight())
    .backgroundColor(this.resolveFloatingTopSurfaceBackgroundColor())
    .backdropBlur(this.resolveFloatingTopSurfaceBackdropBlurRadius())
    .borderRadius(this.resolveFloatingTopSurfaceRadius())
    .shadow(this.resolveFloatingTopSurfaceShadow())
    .position({ x: this.resolveOverlayPanelOffsetX(), y: this.resolveFloatingTopSurfaceGlobalTop() })
    .opacity(this.resolveFloatingTopSurfaceOpacity())
    .translate({ y: this.resolveFloatingTopSurfaceTranslateY() + this.floatingHostResizeTranslateY })
    .animation({
      duration: this.resolveFloatingSurfaceMotionDuration(),
      curve: BROWSER_DETENT_FLOATING_HEADER_MOTION_CURVE
    })
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .clip(this.floatingHeaderChromeVisible)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.reportFloatingPanelVisualHeightFromArea(newArea, 'top');
    })
  }

  @Builder
  private buildFloatingOverlayHeaderShadowSurface() {
    Column()
      .width(this.resolveFloatingHeaderSurfaceWidth())
      .height(this.getFloatingHeaderHeight())
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(BROWSER_DETENT_FLOATING_HEADER_RADIUS)
      .shadow(this.resolveFloatingPanelShadow())
      .position({ x: this.resolveFloatingHeaderSurfaceOffsetX(), y: this.resolveFloatingHeaderGlobalTop() })
      .translate({
        y: this.floatingHostResizeTranslateY + this.floatingHeaderPresentationTranslateY
      })
      .opacity(this.resolveFloatingHeaderShadowOpacity())
      .animation({
        duration: this.resolveFloatingSurfaceMotionDuration(),
        curve: this.getPanelAnimationCurve()
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFloatingOverlayHeaderSurface() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildFloatingOverlayHeaderMaterialBackground()
      this.buildFloatingOverlayHeaderColorOverlay()
      Column({ space: 0 }) {
        if (this.showDragHandle) {
          this.buildDragHandle()
        }
        this.header()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.floatingHeaderHorizontalPadding,
        right: this.floatingHeaderHorizontalPadding,
        top: BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING,
        bottom: BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING
      })
    }
    .width(this.resolveFloatingHeaderSurfaceWidth())
    .height(this.getFloatingHeaderHeight())
    .borderRadius(BROWSER_DETENT_FLOATING_HEADER_RADIUS)
    .shadow(this.resolveEmptyFloatingShadow())
    .position({ x: this.resolveFloatingHeaderSurfaceOffsetX(), y: this.resolveFloatingHeaderGlobalTop() })
    .translate({
      y: this.floatingHostResizeTranslateY + this.floatingHeaderPresentationTranslateY
    })
    .opacity(this.resolveFloatingHeaderPresentationOpacity())
    .animation({
      duration: this.resolveFloatingSurfaceMotionDuration(),
      curve: this.getPanelAnimationCurve()
    })
    .responseRegion({
      x: this.resolveFloatingHeaderInteractionOffsetX(),
      y: this.resolveFloatingHeaderInteractionOffsetY(),
      width: this.resolveFloatingHeaderInteractionWidth(),
      height: this.resolveFloatingHeaderInteractionHeight()
    })
    .hitTestBehavior(this.shouldEnableFloatingHeaderInteraction() ?
      HitTestMode.BLOCK_HIERARCHY : HitTestMode.BLOCK_DESCENDANTS)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.dragGestureWidth = this.parseAreaDimension(newArea.width);
      this.reportFloatingPanelVisualHeightFromArea(newArea, 'header');
    })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: BROWSER_DETENT_PAN_START_DISTANCE })
        .onActionStart((event: GestureEvent) => {
          this.rememberPanelGestureStart(event);
          this.beginPanelDrag();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updatePanelDrag(event);
        })
        .onActionEnd((event: GestureEvent) => {
          this.handlePanelPanEnd(event);
        })
        .onActionCancel(() => {
          this.endPanelDrag(0);
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildFloatingOverlayHeaderMaterialBackground() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .backgroundBlurStyle(
        this.resolveFloatingHeaderMaterialBackgroundBlurStyle(),
        this.resolveFloatingHeaderMaterialBackgroundBlurOptions()
      )
      .borderRadius(BROWSER_DETENT_FLOATING_HEADER_RADIUS)
      .opacity(this.resolveFloatingHeaderMaterialBackgroundOpacity())
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFloatingOverlayHeaderColorOverlay() {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveFloatingHeaderBackgroundColor())
      .borderRadius(BROWSER_DETENT_FLOATING_HEADER_RADIUS)
      .opacity(this.resolveFloatingHeaderColorOverlayOpacity())
      .animation({
        duration: this.resolveFloatingSurfaceMotionDuration(),
        curve: this.getPanelAnimationCurve()
      })
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFloatingOverlayExpandedSurface() {
    Column() {
      if (this.floatingExpandedContentBodyVisible) {
        Column() {
          ForEach([this.buildFloatingExpandedContentRenderKey()], (_renderKey: string) => {
            this.expandedContent()
          }, (renderKey: string) => renderKey)
        }
        .width('100%')
        .height('100%')
        .transition(TransitionEffect.asymmetric(
          TransitionEffect.translate({ y: BROWSER_DETENT_FLOATING_CONTENT_ENTER_TRANSLATE_Y })
            .animation({ curve: BROWSER_DETENT_FLOATING_CONTENT_ENTER_CURVE })
            .combine(TransitionEffect.scale({
              x: BROWSER_DETENT_FLOATING_CONTENT_ENTER_INITIAL_SCALE,
              y: BROWSER_DETENT_FLOATING_CONTENT_ENTER_INITIAL_SCALE,
              centerX: '50%',
              centerY: '100%'
            }).animation({ curve: BROWSER_DETENT_FLOATING_CONTENT_ENTER_CURVE }))
            .combine(TransitionEffect.opacity(0).animation({
              duration: BROWSER_DETENT_FLOATING_CONTENT_ENTER_OPACITY_DURATION_MS,
              curve: Curve.EaseOut
            })),
          TransitionEffect.translate({ y: BROWSER_DETENT_FLOATING_CONTENT_EXIT_TRANSLATE_Y })
            .combine(TransitionEffect.OPACITY)
            .animation({
              duration: BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_DURATION_MS,
              curve: Curve.EaseOut
            })
        ))
      }
    }
    .width(this.resolveOverlayPanelWidth())
    .height(this.resolveFloatingExpandedSurfaceHeight())
    .backgroundColor(this.resolveFloatingExpandedSurfaceBackgroundColor())
    .backgroundBlurStyle(
      this.resolveFloatingExpandedMaterialBackgroundBlurStyle(),
      BROWSER_FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS
    )
    .borderRadius(this.resolveFloatingExpandedSurfaceRadius())
    .shadow(this.resolveFloatingExpandedSurfaceShadow())
    .position({ x: this.resolveOverlayPanelOffsetX(), y: this.resolveFloatingExpandedSurfaceGlobalTop() })
    .opacity(this.resolveFloatingExpandedSurfaceOpacity())
    .translate({ y: this.resolveFloatingExpandedSurfaceTranslateY() + this.floatingHostResizeTranslateY })
    .animation({
      duration: this.resolveFloatingSurfaceMotionDuration(),
      curve: this.getPanelAnimationCurve()
    })
    .hitTestBehavior(this.shouldShowFloatingExpandedContent() ? HitTestMode.Transparent : HitTestMode.None)
    .clip(true)
  }

  private buildFloatingTopContentRenderKey(): string {
    return `floating-top:${this.floatingContentRenderKey}`;
  }

  private buildFloatingExpandedContentRenderKey(): string {
    return `floating-expanded:${this.floatingContentRenderKey}`;
  }

  @Builder
  private buildPanel(expanded: boolean) {
    this.buildAttachedPanel(expanded)
  }

  @Builder
  private buildAttachedPanel(expanded: boolean) {
    Column({ space: 0 }) {
      this.buildAttachedHeaderSurface()

      if (expanded) {
        Column() {
          this.expandedContent()
        }
        .width('100%')
        .layoutWeight(1)
        .opacity(this.shouldShowExpandedContent() ? 1 : 0)
        .translate({ y: this.shouldShowExpandedContent() ? 0 : 16 })
        .animation({
          duration: this.shouldShowExpandedContent() ? BROWSER_DETENT_PANEL_OPEN_ANIMATION_DURATION_MS :
          BROWSER_DETENT_PANEL_CLOSE_ANIMATION_DURATION_MS,
          curve: this.shouldShowExpandedContent() ? BROWSER_DETENT_PANEL_OPEN_CURVE : BROWSER_DETENT_PANEL_CLOSE_CURVE
        })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: this.getPanelSidePadding(),
      right: this.getPanelSidePadding(),
      top: this.getPanelTopPadding(),
      bottom: BROWSER_DETENT_PANEL_BOTTOM_PADDING
    })
    .backgroundColor(this.resolveGlassPanelTintColor())
    .backdropBlur(this.resolveBackdropBlurRadius())
    .borderRadius({
      topLeft: BROWSER_DETENT_PANEL_RADIUS,
      topRight: BROWSER_DETENT_PANEL_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    })
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .clip(true)
  }

  @Builder
  private buildAttachedHeaderSurface() {
    Column({ space: 0 }) {
      if (this.showDragHandle) {
        this.buildDragHandle()
      }
      this.header()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.dragGestureWidth = this.parseAreaDimension(newArea.width);
    })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: BROWSER_DETENT_PAN_START_DISTANCE })
        .onActionStart((event: GestureEvent) => {
          this.rememberPanelGestureStart(event);
          this.beginPanelDrag();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updatePanelDrag(event);
        })
        .onActionEnd((event: GestureEvent) => {
          this.handlePanelPanEnd(event);
        })
        .onActionCancel(() => {
          this.endPanelDrag(0);
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildDragHandle() {
    Row()
      .width(BROWSER_DETENT_DRAG_HANDLE_WIDTH)
      .height(BROWSER_DETENT_DRAG_HANDLE_HEIGHT)
      .margin({ bottom: BROWSER_DETENT_DRAG_HANDLE_BOTTOM_GAP })
      .borderRadius(BROWSER_DETENT_DRAG_HANDLE_RADIUS)
      .backgroundColor(this.resolveDragHandleColor())
      .hitTestBehavior(HitTestMode.None)
  }

  private beginPanelDrag(): void {
    if (this.mode !== 'overlay' || !this.motionState.detentDragEnabled ||
      this.deferredFloatingCollapseAfterContentExit) {
      return;
    }
    this.syncFloatingHeaderBackgroundState(false);
    this.syncFloatingHeaderShadowVisibility(false);
    this.deferredPanelDetentChange = undefined;
    this.invalidatePendingPanelDragFrame();
    this.isDraggingPanel = true;
    this.dragStartPanelHeight = this.getPanelHeight();
    this.resetPanelDragVelocityTracking();
    this.onPanelGestureFrame({
      phase: 'start',
      panelHeight: this.dragStartPanelHeight,
      offsetY: 0,
      startX: this.dragStartLocalX,
      panelWidth: this.dragGestureWidth
    });
  }

  private updatePanelDrag(event: GestureEvent): void {
    if (this.mode !== 'overlay' || !this.motionState.detentDragEnabled) {
      return;
    }
    const offsetY = Number(event.offsetY);
    this.trackPanelDragVelocity(offsetY, this.resolveGestureEventVelocityY(event));
    this.pendingPanelDragOffsetY = offsetY;
    this.schedulePendingPanelDragFrame();
  }

  private schedulePendingPanelDragFrame(): void {
    if (this.panelDragFrameCallbackScheduled) {
      return;
    }
    this.panelDragFrameCallbackScheduled = true;
    const runId = this.panelDragFrameRunId;
    this.getUIContext().postFrameCallback(new BrowserDetentBottomPanelFrameCallback((_frameTimeInNano: number): void => {
      this.commitScheduledPanelDragFrame(runId);
    }));
  }

  private commitScheduledPanelDragFrame(runId: number): void {
    if (runId !== this.panelDragFrameRunId) {
      return;
    }
    this.panelDragFrameCallbackScheduled = false;
    const offsetY = this.pendingPanelDragOffsetY;
    this.pendingPanelDragOffsetY = undefined;
    if (offsetY === undefined || !this.isDraggingPanel) {
      return;
    }
    this.commitPanelDragUpdate(offsetY);
  }

  private commitPanelDragUpdate(offsetY: number): void {
    if (!this.shouldHoldFloatingCollapseMotionForContentExit(offsetY)) {
      const metrics = this.buildGestureDetentMetrics();
      const effectiveOffsetY = this.resolveEffectivePanelDragOffsetY(offsetY);
      this.currentPanelHeight = this.resolveDraggedPanelHeight(
        this.dragStartPanelHeight - effectiveOffsetY,
        offsetY,
        metrics
      );
    }
    this.onPanelGestureFrame({
      phase: 'update',
      panelHeight: this.currentPanelHeight,
      offsetY: offsetY,
      startX: this.dragStartLocalX,
      panelWidth: this.dragGestureWidth
    });
  }

  private flushPendingPanelDragFrame(finalOffsetY?: number): void {
    let offsetY = this.pendingPanelDragOffsetY;
    if (finalOffsetY !== undefined && Number.isFinite(finalOffsetY)) {
      offsetY = finalOffsetY;
    }
    this.invalidatePendingPanelDragFrame();
    if (offsetY === undefined || !this.isDraggingPanel) {
      return;
    }
    this.commitPanelDragUpdate(offsetY);
  }

  private invalidatePendingPanelDragFrame(): void {
    this.panelDragFrameRunId += 1;
    this.panelDragFrameCallbackScheduled = false;
    this.pendingPanelDragOffsetY = undefined;
  }

  private resetPanelDragVelocityTracking(): void {
    this.dragLastOffsetY = 0;
    this.dragLastUpdateAtMs = Date.now();
    this.dragReleaseVelocityY = 0;
  }

  private trackPanelDragVelocity(offsetY: number, eventVelocityY: number): void {
    if (!Number.isFinite(offsetY)) {
      return;
    }
    if (this.isUsefulGestureVelocity(eventVelocityY)) {
      this.dragReleaseVelocityY = eventVelocityY;
    }
    const now = Date.now();
    if (this.dragLastUpdateAtMs > 0) {
      const elapsedMs = now - this.dragLastUpdateAtMs;
      if (elapsedMs > 0 && elapsedMs <= 120) {
        const velocityY = (offsetY - this.dragLastOffsetY) * 1000 / elapsedMs;
        if (!this.isUsefulGestureVelocity(eventVelocityY) && Number.isFinite(velocityY)) {
          this.dragReleaseVelocityY = velocityY;
        }
      } else if (elapsedMs > 120 && !this.isUsefulGestureVelocity(eventVelocityY)) {
        this.dragReleaseVelocityY = 0;
      }
    }
    this.dragLastOffsetY = offsetY;
    this.dragLastUpdateAtMs = now;
  }

  private resolvePanelDragReleaseVelocityY(event: GestureEvent, offsetY: number): number {
    const eventVelocityY = this.resolveGestureEventVelocityY(event);
    if (this.isUsefulGestureVelocity(eventVelocityY)) {
      return eventVelocityY;
    }
    if (!Number.isFinite(offsetY)) {
      return 0;
    }
    const now = Date.now();
    const elapsedMs = now - this.dragLastUpdateAtMs;
    if (elapsedMs > 0 && elapsedMs <= 80 && Math.abs(offsetY - this.dragLastOffsetY) > 0.01) {
      const velocityY = (offsetY - this.dragLastOffsetY) * 1000 / elapsedMs;
      return Number.isFinite(velocityY) ? velocityY : this.dragReleaseVelocityY;
    }
    if (elapsedMs <= 120) {
      return this.dragReleaseVelocityY;
    }
    return 0;
  }

  private resolveGestureEventVelocityY(event: GestureEvent): number {
    return Number(event.velocityY);
  }

  private isUsefulGestureVelocity(velocityY: number): boolean {
    return Number.isFinite(velocityY) && Math.abs(velocityY) > 0.01;
  }

  private resolveEffectivePanelDragOffsetY(offsetY: number): number {
    if (!this.shouldApplyUpwardRubberBand(offsetY)) {
      return this.resolveSheetDetentDragOffsetY(offsetY);
    }
    return -this.resolveUpwardRubberBandDistance(Math.abs(offsetY));
  }

  private resolveSheetDetentDragOffsetY(offsetY: number): number {
    return offsetY;
  }

  private resolveDraggedPanelHeight(
    height: number,
    offsetY: number,
    metrics: HomeSearchPanelDetentMetrics
  ): number {
    if (this.shouldApplyMiddleTopOverdrag(offsetY)) {
      return metrics.middleHeight + this.resolveMiddleTopOverdragDistance(Math.abs(offsetY));
    }
    return this.panelDetentViewModel.clampHeight(height, metrics);
  }

  private shouldApplyMiddleTopOverdrag(offsetY: number): boolean {
    return this.floatingBlocksEnabled &&
      !this.motionState.suppressExpandedContentFromDrag &&
      this.panelDetent === 'middle' &&
      Number.isFinite(offsetY) &&
      offsetY < 0;
  }

  private resolveMiddleTopOverdragDistance(distance: number): number {
    const pullDistance = Math.max(0, distance);
    if (pullDistance <= 0) {
      return 0;
    }
    if (pullDistance <= BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LINEAR_DISTANCE) {
      return pullDistance;
    }
    const resistedDistance = pullDistance - BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LINEAR_DISTANCE;
    return BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LIMIT *
      (resistedDistance / (resistedDistance + BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_DISTANCE)) +
      BROWSER_DETENT_MIDDLE_TOP_OVERDRAG_LINEAR_DISTANCE;
  }

  private shouldApplyUpwardRubberBand(offsetY: number): boolean {
    return this.motionState.suppressExpandedContentFromDrag &&
      this.floatingBlocksEnabled &&
      this.panelDetent === 'low' &&
      Number.isFinite(offsetY) &&
      offsetY < 0;
  }

  private resolveUpwardRubberBandDistance(distance: number): number {
    const pullDistance = Math.max(0, distance);
    if (pullDistance <= 0) {
      return 0;
    }
    if (pullDistance <= BROWSER_DETENT_UPWARD_RUBBER_BAND_LINEAR_DISTANCE) {
      return pullDistance;
    }
    const rubberBandDistance = pullDistance - BROWSER_DETENT_UPWARD_RUBBER_BAND_LINEAR_DISTANCE;
    return BROWSER_DETENT_UPWARD_RUBBER_BAND_LIMIT *
      (rubberBandDistance / (rubberBandDistance + BROWSER_DETENT_UPWARD_RUBBER_BAND_DISTANCE)) +
      BROWSER_DETENT_UPWARD_RUBBER_BAND_LINEAR_DISTANCE;
  }

  private handlePanelPanEnd(event: GestureEvent): void {
    if (this.mode !== 'overlay' || !this.motionState.detentDragEnabled) {
      return;
    }
    const offsetY = Number(event.offsetY);
    const velocityY = this.resolvePanelDragReleaseVelocityY(event, offsetY);
    this.flushPendingPanelDragFrame(offsetY);
    this.endPanelDrag(offsetY, velocityY);
  }

  private endPanelDrag(offsetY: number, velocityY: number = 0): void {
    if (this.mode !== 'overlay' || !this.motionState.detentDragEnabled) {
      return;
    }
    this.flushPendingPanelDragFrame();
    const metrics = this.buildGestureDetentMetrics();
    let targetDetent = this.resolveReleasedGestureTargetDetent(offsetY, velocityY, metrics);
    targetDetent = this.normalizeGestureTargetDetent(targetDetent);
    const interceptTarget = this.onPanelGestureEndIntercept(
      this.currentPanelHeight,
      targetDetent,
      Number(offsetY),
      this.dragStartLocalX,
      this.dragGestureWidth
    );
    if (interceptTarget !== undefined) {
      this.settleReleasedPanelDrag(interceptTarget, interceptTarget === 'low');
      this.clearPanelGestureTouchState();
      return;
    }
    const releaseDisposition = this.onPanelGestureRelease(
      this.currentPanelHeight,
      targetDetent,
      Number(offsetY),
      velocityY
    );
    if (releaseDisposition === 'stay-middle') {
      this.settleReleasedPanelDrag('middle', false);
      this.clearPanelGestureTouchState();
      return;
    }
    if (targetDetent === 'low' && this.shouldDeferFloatingCollapseForContentExit()) {
      this.deferFloatingCollapseUntilContentExit();
      this.clearPanelGestureTouchState();
      return;
    }
    this.settleReleasedPanelDrag(targetDetent);
    this.clearPanelGestureTouchState();
  }

  private settleReleasedPanelDrag(
    targetDetent: HomeSearchPanelDetent,
    dispatchTargetAction: boolean = true
  ): void {
    this.deferredFloatingCollapseAfterContentExit = false;
    this.shouldRevealPanelContent = targetDetent === 'middle';
    this.isDraggingPanel = false;
    this.isSettlingPanelDetent = true;
    this.onPanelGestureEnd(this.currentPanelHeight, targetDetent);
    const shouldDeferDetentChange = this.shouldDeferReleasedDetentChange(targetDetent);
    this.snapToPanelDetent(targetDetent, shouldDeferDetentChange);
    if (dispatchTargetAction) {
      this.dispatchReleasedPanelTargetAction(targetDetent);
    }
  }

  private shouldHoldFloatingCollapseMotionForContentExit(offsetY: number): boolean {
    return this.floatingContentFirstCollapseEnabled &&
      this.floatingExpandedSurfaceCoversHeader &&
      !this.isFloatingInputLayout() &&
      this.panelDetent === 'middle' &&
      Number.isFinite(offsetY) &&
      offsetY > 0 &&
      (this.floatingContentFirstCollapseActive || this.floatingExpandedContentBodyVisible);
  }

  private shouldDeferFloatingCollapseForContentExit(): boolean {
    return this.floatingContentFirstCollapseEnabled &&
      this.floatingContentFirstCollapseActive &&
      this.panelDetent === 'middle';
  }

  private deferFloatingCollapseUntilContentExit(): void {
    this.invalidatePendingPanelDragFrame();
    this.shouldRevealPanelContent = false;
    this.isDraggingPanel = false;
    this.isSettlingPanelDetent = false;
    this.deferredFloatingCollapseAfterContentExit = true;
  }

  private resumeDeferredFloatingCollapseAfterContentExit(): void {
    if (this.floatingContentFirstCollapseActive || !this.deferredFloatingCollapseAfterContentExit) {
      return;
    }
    this.settleReleasedPanelDrag('low');
  }

  private dispatchReleasedPanelTargetAction(targetDetent: HomeSearchPanelDetent): void {
    if (targetDetent === 'middle') {
      this.onExpandToMiddle();
      return;
    }
    this.onCollapse();
  }

  snapToPanelDetent(
    detent: HomeSearchPanelDetent,
    deferDetentChange: boolean = false,
    deferDetentChangeNotification: boolean = false
  ): void {
    const metrics = this.buildDetentMetrics();
    const normalizedDetent = this.normalizePanelDetent(detent);
    const shouldReveal = this.panelDetent === 'low' && normalizedDetent !== 'low';
    const isSameDetent = this.panelDetent === normalizedDetent;
    const shouldDeferVisualLowDetent = deferDetentChange &&
      normalizedDetent === 'low' &&
      this.panelDetent === 'middle';
    this.isPeekToLowPanelTransition = this.panelDetent === 'peek' && normalizedDetent === 'low';
    this.currentPanelHeight = this.panelDetentViewModel.resolveDetentHeight(normalizedDetent, metrics);
    if (!shouldDeferVisualLowDetent) {
      this.panelDetent = normalizedDetent;
      if (shouldReveal) {
        this.shouldRevealPanelContent = true;
      } else if (!isSameDetent) {
        this.shouldRevealPanelContent = false;
      }
    }
    if (deferDetentChange) {
      this.deferredPanelDetentChange = normalizedDetent;
    } else {
      this.deferredPanelDetentChange = undefined;
      this.dispatchDetentChange(normalizedDetent, deferDetentChangeNotification);
    }
    if (!this.isDraggingPanel && !this.isSettlingPanelDetent) {
      this.syncFloatingHeaderBackgroundState(false);
      this.syncFloatingHeaderShadowVisibility(false);
    }
    this.schedulePanelSettlingEnd(normalizedDetent);
  }

  private syncMotionState(): void {
    const geometryKey = this.buildMotionStateGeometryKey();
    const visibilityChanged = !this.motionStateInitialized ||
      this.lastMotionStateVisible !== this.motionState.visible;
    const targetDetentChanged = !this.motionStateInitialized ||
      this.lastMotionStateTargetDetent !== this.motionState.targetDetent;
    const geometryChanged = !this.motionStateInitialized || this.lastMotionStateGeometryKey !== geometryKey;
    this.motionStateInitialized = true;
    this.lastMotionStateVisible = this.motionState.visible;
    this.lastMotionStateTargetDetent = this.motionState.targetDetent;
    this.lastMotionStateGeometryKey = geometryKey;
    if (visibilityChanged) {
      this.syncVisibilityState();
    } else if (targetDetentChanged) {
      this.syncTargetDetent();
    }
    if (geometryChanged) {
      this.syncCurrentPanelGeometry();
    }
  }

  private buildMotionStateGeometryKey(): string {
    return `${this.motionState.bottomInset}:${this.motionState.panelHeight}:${this.motionState.middlePanelHeight}:` +
      `${this.motionState.overlayHostHeight}:${this.motionState.keyboardOverlayInset}`;
  }

  private syncVisibilityState(): void {
    if (this.mode !== 'overlay') {
      return;
    }
    this.deferredPanelDetentChange = undefined;
    if (this.motionState.visible) {
      this.snapToPanelDetent(this.motionState.targetDetent, false, true);
      return;
    }
    this.isDraggingPanel = false;
    this.isSettlingPanelDetent = false;
    this.clearPanelSettlingTimer();
    this.shouldRevealPanelContent = false;
    this.panelDetent = 'low';
    this.currentPanelHeight = this.getOverlayLowPanelHeight();
    this.syncFloatingHeaderBackgroundState(false);
    this.syncFloatingHeaderShadowVisibility(false);
  }

  private syncTargetDetent(): void {
    if (this.mode !== 'overlay') {
      return;
    }
    if (!this.motionState.visible) {
      return;
    }
    const targetDetent = this.motionState.targetDetent;
    if (targetDetent === 'middle' || this.shouldDeferTargetDetentChange(targetDetent)) {
      this.settleProgrammaticPanelDetent(targetDetent);
      return;
    }
    this.snapToPanelDetent(targetDetent, false, true);
  }

  private settleProgrammaticPanelDetent(targetDetent: HomeSearchPanelDetent): void {
    this.shouldRevealPanelContent = targetDetent === 'middle';
    this.isDraggingPanel = false;
    this.isSettlingPanelDetent = true;
    this.snapToPanelDetent(targetDetent, this.shouldDeferTargetDetentChange(targetDetent), true);
  }

  private shouldShowExpandedContent(): boolean {
    if (this.mode === 'bar' || this.panelDetent === 'peek' || this.panelDetent === 'low') {
      return this.shouldRevealExpandedContentDuringDrag();
    }
    return this.contentVisibleWhenMiddle;
  }

  private shouldRevealExpandedContentDuringDrag(): boolean {
    if (!this.isDraggingPanel || this.panelDetent === 'peek') {
      return false;
    }
    if (!this.contentVisibleWhenMiddle) {
      return this.currentPanelHeight >= this.buildGestureDetentMetrics().middleHeight -
      BROWSER_DETENT_CONTENT_DRAG_REVEAL_THRESHOLD;
    }
    return this.currentPanelHeight > this.getOverlayLowPanelHeight() + BROWSER_DETENT_CONTENT_DRAG_REVEAL_THRESHOLD;
  }

  private getPanelSidePadding(): number {
    return this.showDragHandle ? BROWSER_DETENT_PANEL_SIDE_PADDING_WITH_HANDLE : BROWSER_DETENT_PANEL_SIDE_PADDING;
  }

  private getPanelTopPadding(): number {
    return this.showDragHandle ? BROWSER_DETENT_PANEL_TOP_PADDING_WITH_HANDLE : BROWSER_DETENT_PANEL_TOP_PADDING;
  }

  private resolveCollapsedPanelWidth(): Length {
    if (this.floatingBlocksEnabled) {
      return this.resolveFloatingMeasuredPanelWidth();
    }
    return this.panelWidth > 0 ? this.panelWidth : '100%';
  }

  private resolveCollapsedPanelOffsetX(): number {
    if (this.floatingBlocksEnabled) {
      return this.resolveFloatingMeasuredPanelOffsetX();
    }
    return this.panelWidth > 0 ? this.panelOffsetX : 0;
  }

  private resolveFloatingMeasuredPanelWidth(): Length {
    if (this.panelWidth > 0) {
      return this.panelWidth;
    }
    const implicitWidth = this.resolveFloatingImplicitPanelPixelWidth();
    if (this.shouldUseFloatingMeasuredPanelWidth(implicitWidth)) {
      return implicitWidth;
    }
    return implicitWidth > 0 ? implicitWidth : '100%';
  }

  private resolveFloatingMeasuredPanelOffsetX(): number {
    if (this.panelWidth > 0) {
      return this.panelOffsetX;
    }
    const implicitWidth = this.resolveFloatingImplicitPanelPixelWidth();
    if (this.shouldUseFloatingMeasuredPanelWidth(implicitWidth)) {
      return Math.max(0, (this.hostWidth - implicitWidth) / 2);
    }
    return BROWSER_DETENT_FLOATING_SIDE_INSET;
  }

  private shouldUseFloatingMeasuredPanelWidth(implicitWidth: number): boolean {
    if (implicitWidth <= 0 || this.hostWidth <= 0) {
      return false;
    }
    return this.panelWidth <= 0;
  }

  private resolveFloatingImplicitPanelPixelWidth(): number {
    if (this.hostWidth > BROWSER_DETENT_FLOATING_SIDE_INSET * 2) {
      return this.hostWidth - BROWSER_DETENT_FLOATING_SIDE_INSET * 2;
    }
    return 0;
  }

  private resolveOverlayPanelWidth(): Length {
    return this.resolveCollapsedPanelWidth();
  }

  private resolveOverlayPanelOffsetX(): number {
    return this.resolveCollapsedPanelOffsetX();
  }

  private resolveFloatingHeaderSurfaceWidth(): Length {
    const overlayWidth = this.resolveOverlayPanelWidth();
    if (typeof overlayWidth !== 'number') {
      return overlayWidth;
    }
    const inset = this.resolveFloatingHeaderHorizontalInset();
    return Math.max(1, overlayWidth - inset * 2);
  }

  private resolveFloatingHeaderSurfaceOffsetX(): number {
    return this.resolveOverlayPanelOffsetX() + this.resolveFloatingHeaderHorizontalInset();
  }

  private resolveFloatingHeaderInteractionWidth(): number {
    const surfaceWidth = this.resolveFloatingHeaderSurfacePixelWidth();
    if (this.floatingHeaderInteractionWidth <= 0) {
      return surfaceWidth;
    }
    return Math.max(1, Math.min(surfaceWidth, this.floatingHeaderInteractionWidth));
  }

  private resolveFloatingHeaderInteractionHeight(): number {
    const surfaceHeight = Math.max(1, this.getFloatingHeaderHeight());
    if (this.floatingHeaderInteractionHeight <= 0) {
      return surfaceHeight;
    }
    return Math.max(1, Math.min(surfaceHeight, this.floatingHeaderInteractionHeight));
  }

  private resolveFloatingHeaderInteractionOffsetX(): number {
    return Math.max(0,
      (this.resolveFloatingHeaderSurfacePixelWidth() - this.resolveFloatingHeaderInteractionWidth()) / 2);
  }

  private resolveFloatingHeaderInteractionOffsetY(): number {
    const maximumOffsetY = Math.max(0,
      this.getFloatingHeaderHeight() - this.resolveFloatingHeaderInteractionHeight());
    return Math.max(0, Math.min(maximumOffsetY, this.floatingHeaderInteractionOffsetY));
  }

  private resolveFloatingHeaderSurfacePixelWidth(): number {
    const surfaceWidth = this.resolveFloatingHeaderSurfaceWidth();
    if (typeof surfaceWidth === 'number') {
      return Math.max(1, surfaceWidth);
    }
    return Math.max(1, this.hostWidth);
  }

  private resolveFloatingHeaderHorizontalInset(): number {
    if (!this.shouldApplyFloatingHeaderHorizontalInset()) {
      return 0;
    }
    const overlayWidth = this.resolveOverlayPanelWidth();
    if (typeof overlayWidth !== 'number') {
      return 0;
    }
    const targetInset = Math.max(0, Math.min(this.floatingExpandedHeaderHorizontalInset, (overlayWidth - 1) / 2));
    return targetInset * this.resolveFloatingHeaderHorizontalInsetProgress();
  }

  private shouldApplyFloatingHeaderHorizontalInset(): boolean {
    return this.floatingBlocksEnabled &&
      this.floatingExpandedHeaderHorizontalInset > 0;
  }

  private resolveFloatingHeaderHorizontalInsetProgress(): number {
    if (!this.shouldApplyFloatingHeaderHorizontalInset()) {
      return 0;
    }
    if (this.isDraggingPanel) {
      return this.resolveFloatingHeaderDetentInsetProgress(this.panelDetent);
    }
    if (this.isSettlingPanelDetent) {
      return this.resolveFloatingHeaderDetentInsetProgress(this.getSettlingTargetDetent());
    }
    if (this.panelDetent === 'middle') {
      return 1;
    }
    return 0;
  }

  private resolveFloatingHeaderDetentInsetProgress(detent: HomeSearchPanelDetent): number {
    return detent === 'middle' ? 1 : 0;
  }

  private getOverlayPanelTop(): number {
    const bottomGap = this.resolveFloatingBottomGap();
    return Math.max(0, this.getOverlayHostHeight() - this.getOverlayPanelAnchorHeight() - bottomGap);
  }

  private resolveFloatingBottomGap(): number {
    if (!this.floatingBlocksEnabled) {
      return 0;
    }
    return BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP + Math.max(0, this.motionState.keyboardOverlayInset);
  }

  private resolveOverlayPanelTranslateY(): number {
    if (!this.motionState.visible) {
      return this.resolveOverlayPanelHiddenTranslateY();
    }
    return 0;
  }

  private resolveOverlayPanelHiddenTranslateY(): number {
    return this.getOverlayLowPanelHeight() + this.resolveFloatingBottomGap();
  }

  private shouldHideOverlayPanel(): boolean {
    return this.isPeekDetent();
  }

  private shouldEnableOverlayPanelHitTest(): boolean {
    return this.motionState.visible && !this.isPeekDetent();
  }

  private shouldEnableFloatingHeaderInteraction(): boolean {
    return this.floatingHeaderInteractionEnabled &&
      this.resolveFloatingHeaderPresentationOpacity() > 0.001 &&
      this.shouldEnableOverlayPanelHitTest();
  }

  private shouldClipOverlayPanel(): boolean {
    return !this.floatingBlocksEnabled;
  }

  private getOverlayHostHeight(): number {
    const rawHostHeight = this.resolveRawOverlayHostHeight();
    if (this.shouldUseFloatingInputStableHostHeight(rawHostHeight)) {
      return Math.min(rawHostHeight, this.floatingInputStableHostHeight);
    }
    return rawHostHeight;
  }

  private resolveRawOverlayHostHeight(): number {
    if (this.motionState.overlayHostHeight > 0) {
      return this.motionState.overlayHostHeight;
    }
    if (this.motionState.panelHeight > 0) {
      return Math.max(this.motionState.panelHeight, this.getOverlayPanelLayoutHeight());
    }
    return this.getOverlayPanelLayoutHeight();
  }

  private getOverlayPanelAnchorHeight(): number {
    return this.getPanelHeight();
  }

  private getOverlayPanelLayoutHeight(): number {
    if (this.mode === 'overlay' && this.floatingBlocksEnabled && !this.isFloatingInputLayout()) {
      return this.resolveFloatingStackLayoutHeight();
    }
    return this.getPanelHeight();
  }

  private getPanelHeight(): number {
    if (this.mode !== 'overlay') {
      return this.motionState.panelHeight > 0 ? this.motionState.panelHeight : BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT;
    }
    return this.currentPanelHeight;
  }

  private resolveReleasedGestureTargetDetent(
    offsetY: number,
    velocityY: number,
    metrics: HomeSearchPanelDetentMetrics
  ): HomeSearchPanelDetent {
    return this.panelDetentViewModel.resolveOfficialSheetReleaseDetent({
      currentDetent: this.panelDetent,
      startHeight: this.dragStartPanelHeight,
      currentHeight: this.currentPanelHeight,
      offsetY,
      velocityY,
      metrics
    });
  }

  private getPanelAnimationDuration(): number {
    if (this.isSettlingPanelDetent) {
      if (this.getSettlingTargetDetent() === 'middle') {
        return BROWSER_DETENT_PANEL_MIDDLE_SNAP_ANIMATION_DURATION_MS;
      }
      return BROWSER_DETENT_PANEL_SNAP_ANIMATION_DURATION_MS;
    }
    if (this.panelDetent === 'middle') {
      return BROWSER_DETENT_PANEL_SNAP_ANIMATION_DURATION_MS;
    }
    if (this.isPeekToLowPanelTransition) {
      return this.motionState.peekToLowAnimationDurationMs;
    }
    if (this.panelDetent === 'peek') {
      return this.motionState.collapseToPeekAnimationDurationMs;
    }
    return BROWSER_DETENT_PANEL_CLOSE_ANIMATION_DURATION_MS;
  }

  private getPanelAnimationCurve(): Curve | string | ICurve {
    if (this.isSettlingPanelDetent) {
      if (this.getSettlingTargetDetent() === 'low') {
        return BROWSER_DETENT_PANEL_LOW_SETTLE_CURVE;
      }
      if (this.getSettlingTargetDetent() === 'middle') {
        return BROWSER_DETENT_PANEL_MIDDLE_SNAP_CURVE;
      }
      return BROWSER_DETENT_PANEL_SNAP_CURVE;
    }
    if (this.floatingBlocksEnabled) {
      return BROWSER_DETENT_PANEL_SNAP_CURVE;
    }
    return BROWSER_DETENT_PANEL_CLOSE_CURVE;
  }

  private getSettlingTargetDetent(): HomeSearchPanelDetent {
    return this.deferredPanelDetentChange ?? this.panelDetent;
  }

  private schedulePanelSettlingEnd(detent: HomeSearchPanelDetent): void {
    this.clearPanelSettlingTimer();
    const settleDuration = this.getPanelAnimationDuration();
    this.panelSettlingTimer = setTimeout(() => {
      this.panelSettlingTimer = -1;
      this.isSettlingPanelDetent = false;
      if (this.deferredPanelDetentChange === detent) {
        this.panelDetent = detent;
        this.currentPanelHeight = this.panelDetentViewModel.resolveDetentHeight(detent, this.buildDetentMetrics());
        this.shouldRevealPanelContent = detent === 'middle';
        this.dispatchDeferredPanelDetentChange(detent);
        this.syncFloatingHeaderBackgroundState(true);
        this.syncFloatingHeaderShadowVisibility(true);
        this.onPanelSettled(detent);
        return;
      }
      if (this.panelDetent === detent) {
        this.dispatchDeferredPanelDetentChange(detent);
        this.syncFloatingHeaderBackgroundState(true);
        this.syncFloatingHeaderShadowVisibility(true);
        this.onPanelSettled(detent);
      }
    }, settleDuration);
  }

  private dispatchDeferredPanelDetentChange(detent: HomeSearchPanelDetent): void {
    if (this.deferredPanelDetentChange !== detent) {
      return;
    }
    this.deferredPanelDetentChange = undefined;
    this.onDetentChange(detent);
  }

  private dispatchDetentChange(
    detent: HomeSearchPanelDetent,
    deferNotification: boolean
  ): void {
    if (!deferNotification) {
      this.clearDetentChangeNotification();
      this.onDetentChange(detent);
      return;
    }
    this.pendingDetentChangeNotification = detent;
    if (this.detentChangeNotificationTimer >= 0) {
      return;
    }
    this.detentChangeNotificationTimer = setTimeout(() => {
      this.detentChangeNotificationTimer = -1;
      const pendingDetent = this.pendingDetentChangeNotification;
      this.pendingDetentChangeNotification = undefined;
      if (pendingDetent === undefined || pendingDetent !== this.panelDetent) {
        return;
      }
      this.onDetentChange(pendingDetent);
    }, 0);
  }

  private clearDetentChangeNotification(): void {
    if (this.detentChangeNotificationTimer >= 0) {
      clearTimeout(this.detentChangeNotificationTimer);
      this.detentChangeNotificationTimer = -1;
    }
    this.pendingDetentChangeNotification = undefined;
  }

  private clearPanelSettlingTimer(): void {
    if (this.panelSettlingTimer < 0) {
      return;
    }
    clearTimeout(this.panelSettlingTimer);
    this.panelSettlingTimer = -1;
  }

  private clearFloatingHostResizeMotionTimer(): void {
    if (this.floatingHostResizeMotionTimer < 0) {
      return;
    }
    clearTimeout(this.floatingHostResizeMotionTimer);
    this.floatingHostResizeMotionTimer = -1;
  }

  private rememberOverlayHostArea(newArea: Area): void {
    this.syncFloatingLayoutModeResizeMotionState();
    const previousHeaderVisualTop = this.resolveFloatingHeaderGlobalTop() + this.floatingHostResizeTranslateY;
    const hadHostMetrics = this.hostHeight > 0;
    const previousHostHeight = this.hostHeight;
    this.hostWidth = this.parseAreaDimension(newArea.width);
    this.hostGlobalTop = this.parseAreaPosition(newArea.globalPosition.y);
    this.hostHeight = this.parseAreaDimension(newArea.height);
    this.syncFloatingInputStableHostSize();
    this.syncCurrentPanelGeometryForHostResize();
    this.playFloatingHostResizeMotion(previousHeaderVisualTop, hadHostMetrics, previousHostHeight);
    if (this.hostWidth > 0 && this.hostHeight > 0) {
      this.onHostGeometryReady(this.hostWidth, this.hostHeight);
    }
  }

  private playFloatingHostResizeMotion(
    previousHeaderVisualTop: number,
    hadHostMetrics: boolean,
    previousHostHeight: number
  ): void {
    if (!this.shouldAnimateFloatingHostResize(hadHostMetrics, previousHostHeight)) {
      return;
    }
    const nextHeaderTop = this.resolveFloatingHeaderGlobalTop();
    const offsetY = previousHeaderVisualTop - nextHeaderTop;
    if (Math.abs(offsetY) < BROWSER_DETENT_FLOATING_HOST_RESIZE_MOTION_THRESHOLD) {
      return;
    }
    this.floatingInputHostResizeMotionConsumed = true;
    this.clearFloatingHostResizeMotionTimer();
    this.floatingHostResizeMotionActive = true;
    this.floatingHostResizeTranslateY = offsetY;
    this.floatingHostResizeMotionTimer = setTimeout(() => {
      this.floatingHostResizeMotionTimer = -1;
      animateTo({
        duration: BROWSER_DETENT_FLOATING_HEADER_MOTION_DURATION_MS,
        curve: BROWSER_DETENT_FLOATING_HEADER_MOTION_CURVE,
        onFinish: () => {
          this.floatingHostResizeMotionActive = false;
          this.floatingHostResizeTranslateY = 0;
        }
      }, () => {
        this.floatingHostResizeMotionActive = false;
        this.floatingHostResizeTranslateY = 0;
      });
    }, 0);
  }

  private shouldAnimateFloatingHostResize(hadHostMetrics: boolean, previousHostHeight: number): boolean {
    const shouldAnimate = hadHostMetrics &&
      this.mode === 'overlay' &&
      this.motionState.visible &&
      this.isFloatingInputLayout() &&
      !this.isDraggingPanel &&
      !this.isSettlingPanelDetent;
    if (!shouldAnimate) {
      return false;
    }
    if (this.shouldLockFloatingInputGeometry()) {
      return false;
    }
    if (this.floatingInputHostResizeMotionConsumed) {
      return false;
    }
    if (Math.abs(this.hostHeight - previousHostHeight) < BROWSER_DETENT_FLOATING_HOST_RESIZE_MOTION_THRESHOLD) {
      return false;
    }
    return true;
  }

  private reportFloatingPanelVisualHeightFromArea(newArea: Area, source: string): void {
    if (this.mode !== 'overlay' || !this.floatingBlocksEnabled) {
      return;
    }
    if (this.shouldLockFloatingInputGeometry()) {
      this.reportPanelVisualHeight(this.resolveLockedFloatingInputVisualHeight());
      return;
    }
    if (source === 'header' && this.shouldShowFloatingTopContent()) {
      return;
    }
    if (source === 'top' && !this.shouldShowFloatingTopContent()) {
      return;
    }
    const hostHeight = this.getOverlayHostHeight();
    const hostBottom = this.hostGlobalTop + hostHeight;
    const surfaceTop = this.parseAreaPosition(newArea.globalPosition.y);
    const visualHeight = Math.max(0, hostBottom - surfaceTop - this.resolveFloatingBottomGap());
    this.reportPanelVisualHeight(visualHeight);
  }

  private reportPanelVisualHeight(panelHeight: number): void {
    if (this.isDraggingPanel || !Number.isFinite(panelHeight)) {
      return;
    }
    const nextHeight = Math.max(0, panelHeight);
    if (Math.abs(nextHeight - this.lastReportedPanelVisualHeight) < 0.5) {
      return;
    }
    this.lastReportedPanelVisualHeight = nextHeight;
    this.onPanelVisualHeightChange(nextHeight);
  }

  private syncFloatingExpandedContentHeight(): void {
    this.syncCurrentPanelGeometry();
  }

  private syncCurrentPanelGeometry(): void {
    this.syncFloatingLayoutModeResizeMotionState();
    this.syncFloatingInputStableHostSize();
    if (this.mode !== 'overlay' || !this.motionState.visible || this.isDraggingPanel ||
      (this.isSettlingPanelDetent && this.deferredPanelDetentChange !== undefined)) {
      return;
    }
    this.syncCurrentPanelGeometryNow();
  }

  private syncFloatingLayoutModeResizeMotionState(): void {
    if (this.lastFloatingLayoutMode === this.floatingLayoutMode) {
      return;
    }
    this.lastFloatingLayoutMode = this.floatingLayoutMode;
    this.resetFloatingInputStableHostSize();
    this.floatingInputHostResizeMotionConsumed = false;
    this.clearFloatingHostResizeMotionTimer();
    this.floatingHostResizeMotionActive = false;
    this.floatingHostResizeTranslateY = 0;
  }

  private syncCurrentPanelGeometryForHostResize(): void {
    if (this.mode !== 'overlay' || !this.motionState.visible || this.isDraggingPanel || this.isSettlingPanelDetent) {
      return;
    }
    if (!this.hasHostGeometryChangedSinceLastSync()) {
      return;
    }
    this.syncCurrentPanelGeometryNow();
  }

  private syncFloatingInputStableHostSize(): void {
    const rawHostHeight = this.resolveRawOverlayHostHeight();
    if (!this.shouldStabilizeFloatingInputHostHeight(rawHostHeight)) {
      this.resetFloatingInputStableHostSize();
      return;
    }
    const rawHostWidth = this.resolveFloatingInputRawHostWidth();
    if (this.shouldResetFloatingInputStableHostSize(rawHostWidth)) {
      this.floatingInputStableHostWidth = rawHostWidth;
      this.floatingInputStableHostHeight = rawHostHeight;
      return;
    }
    if (rawHostHeight < this.floatingInputStableHostHeight) {
      this.floatingInputStableHostHeight = rawHostHeight;
    }
  }

  private shouldStabilizeFloatingInputHostHeight(rawHostHeight: number): boolean {
    return this.mode === 'overlay' &&
      this.motionState.visible &&
      this.isFloatingInputLayout() &&
      rawHostHeight > 0;
  }

  private shouldUseFloatingInputStableHostHeight(rawHostHeight: number): boolean {
    return this.shouldStabilizeFloatingInputHostHeight(rawHostHeight) &&
      this.floatingInputStableHostHeight > 0;
  }

  private shouldResetFloatingInputStableHostSize(rawHostWidth: number): boolean {
    return this.floatingInputStableHostHeight <= 0 ||
      Math.abs(rawHostWidth - this.floatingInputStableHostWidth) >= 1;
  }

  private resetFloatingInputStableHostSize(): void {
    if (this.floatingInputStableHostHeight <= 0 && this.floatingInputStableHostWidth <= 0) {
      return;
    }
    this.floatingInputStableHostHeight = 0;
    this.floatingInputStableHostWidth = 0;
  }

  private resolveFloatingInputRawHostWidth(): number {
    if (this.hostWidth > 0) {
      return this.hostWidth;
    }
    if (this.panelWidth > 0) {
      return this.panelWidth;
    }
    return 0;
  }

  private syncCurrentPanelGeometryNow(): void {
    const metrics = this.buildDetentMetrics();
    this.currentPanelHeight = this.panelDetentViewModel.resolveDetentHeight(this.panelDetent, metrics);
    this.lastGeometrySyncHostWidth = this.hostWidth;
    this.lastGeometrySyncHostHeight = this.hostHeight;
  }

  private hasHostGeometryChangedSinceLastSync(): boolean {
    return Math.abs(this.hostWidth - this.lastGeometrySyncHostWidth) >= 1 ||
      Math.abs(this.hostHeight - this.lastGeometrySyncHostHeight) >= 1;
  }

  private resolveFloatingHeaderGlobalTop(): number {
    if (this.shouldLockFloatingInputGeometry()) {
      return this.resolveLockedFloatingInputHeaderGlobalTop();
    }
    if (this.shouldAnchorFloatingHeaderToBottom()) {
      return this.resolveFixedFloatingHeaderGlobalTop();
    }
    return this.resolveFloatingPanelMotionGlobalTop();
  }

  private shouldAnchorFloatingHeaderToBottom(): boolean {
    return this.floatingExpandedSurfaceCoversHeader &&
      !this.isFloatingInputLayout() &&
      this.getPanelHeight() >= this.getOverlayLowPanelHeight() &&
      !this.floatingHeaderTracksPanelMotion;
  }

  private resolveFixedFloatingHeaderGlobalTop(): number {
    return Math.max(0,
      this.getOverlayHostHeight() - this.resolveFloatingBottomGap() - this.getFloatingHeaderHeight()) +
      this.resolveOverlayPanelTranslateY();
  }

  private resolveFloatingPanelMotionGlobalTop(): number {
    return this.getOverlayPanelTop() + this.resolveOverlayPanelTranslateY() + this.resolveFloatingHeaderTop();
  }

  private shouldLockFloatingInputGeometry(): boolean {
    return this.mode === 'overlay' &&
      this.motionState.visible &&
      this.isFloatingInputLayout();
  }

  private resolveLockedFloatingInputHeaderGlobalTop(): number {
    const hostHeight = this.getOverlayHostHeight();
    return Math.max(0, hostHeight - this.resolveFloatingBottomGap() - this.getFloatingHeaderHeight()) +
      this.resolveOverlayPanelTranslateY();
  }

  private resolveLockedFloatingInputVisualHeight(): number {
    const surfaceTop = this.shouldShowFloatingTopContent() ?
      this.resolveFloatingTopSurfaceGlobalTop() :
      this.resolveLockedFloatingInputHeaderGlobalTop();
    return Math.max(0, this.getOverlayHostHeight() - surfaceTop - this.resolveFloatingBottomGap());
  }

  private buildDetentMetrics(): HomeSearchPanelDetentMetrics {
    return this.panelDetentViewModel.buildMetrics(
      this.resolveMiddleTargetHeight(),
      this.getOverlayLowPanelHeight(),
      this.motionState.peekEnabled ? this.getOverlayPeekPanelHeight() : this.getOverlayLowPanelHeight(),
      this.motionState.middlePanelHeight
    );
  }

  private buildGestureDetentMetrics(): HomeSearchPanelDetentMetrics {
    return this.panelDetentViewModel.buildMetrics(
      this.resolveMiddleTargetHeight(),
      this.getOverlayLowPanelHeight(),
      this.shouldAllowCurrentGesturePeek() ? this.getOverlayPeekPanelHeight() : this.getOverlayLowPanelHeight(),
      this.motionState.middlePanelHeight
    );
  }

  private normalizePanelDetent(detent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    if (!this.motionState.detentDragEnabled && detent !== 'peek') {
      return 'low';
    }
    if (!this.motionState.peekEnabled && detent === 'peek') {
      return 'low';
    }
    return detent;
  }

  private normalizeGestureTargetDetent(detent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    if (detent === 'peek' && !this.shouldAllowGesturePeek()) {
      return 'low';
    }
    return this.normalizePanelDetent(detent);
  }

  private shouldAllowGesturePeek(): boolean {
    return this.motionState.peekEnabled && this.motionState.peekGestureEnabled;
  }

  private shouldAllowCurrentGesturePeek(): boolean {
    return this.shouldAllowGesturePeek() && this.panelDetent !== 'middle';
  }

  private shouldDeferReleasedDetentChange(targetDetent: HomeSearchPanelDetent): boolean {
    return targetDetent === 'low' && this.panelDetent === 'middle';
  }

  private shouldDeferTargetDetentChange(targetDetent: HomeSearchPanelDetent): boolean {
    return this.deferLowDetentChangeUntilSettled &&
      targetDetent === 'low' &&
      this.panelDetent === 'middle';
  }

  private rememberPanelGestureStart(event: GestureEvent): void {
    const fingerInfos = event.fingerInfos;
    if (fingerInfos !== undefined && fingerInfos.length > 0) {
      this.dragStartLocalX = Number(fingerInfos[0].localX) - Number(event.offsetX);
      return;
    }
    if (event.fingerList.length > 0) {
      this.dragStartLocalX = Number(event.fingerList[0].localX) - Number(event.offsetX);
      return;
    }
    this.dragStartLocalX = -1;
  }

  private clearPanelGestureTouchState(): void {
    this.dragStartLocalX = -1;
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseAreaPosition(value?: Length): number {
    if (value === undefined) {
      return 0;
    }
    return this.parseAreaDimension(value);
  }

  private isPeekDetent(): boolean {
    return this.panelDetent === 'peek';
  }

  private getOverlayLowPanelHeight(): number {
    if (this.mode !== 'overlay') {
      return BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT;
    }
    if (this.floatingBlocksEnabled) {
      return BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT + Math.max(0, this.motionState.bottomInset);
    }
    return BROWSER_DETENT_BOTTOM_PANEL_LOW_HEIGHT + Math.max(0, this.motionState.bottomInset);
  }

  private getFloatingHeaderHeight(): number {
    return this.getOverlayLowPanelHeight();
  }

  private resolveFloatingStackLayoutHeight(): number {
    if (!this.floatingExpandedContentVisible || this.floatingExpandedContentHeight <= 0) {
      return this.getFloatingHeaderHeight();
    }
    if (this.floatingExpandedSurfaceCoversHeader) {
      return this.getFloatingTopTotalHeight() + Math.max(1, this.floatingExpandedContentHeight);
    }
    return this.getFloatingHeaderHeight() + BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP +
      Math.max(1, this.floatingExpandedContentHeight);
  }

  private resolveFloatingExpandedSurfaceHeight(): number {
    if (this.floatingExpandedContentGeometryLocked) {
      return Math.max(1, this.floatingExpandedContentHeight);
    }
    if (!this.shouldShowFloatingExpandedContent()) {
      return 0;
    }
    const fullHeight = this.resolveFloatingExpandedSurfaceFullHeight();
    if (!this.isFloatingInputLayout()) {
      return Math.min(fullHeight, this.resolveFloatingExpandedSurfaceAvailableHeight());
    }
    return fullHeight;
  }

  private resolveFloatingExpandedSurfaceFullHeight(): number {
    if (!this.isFloatingInputLayout() && this.floatingExpandedContentHeight > 0) {
      return Math.max(1, this.floatingExpandedContentHeight);
    }
    return this.resolveFloatingExpandedSurfaceAvailableHeight();
  }

  private resolveFloatingExpandedSurfaceAvailableHeight(): number {
    const fullHeaderReservedHeight = this.getFloatingHeaderHeight() + BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP;
    const headerReservedHeight = this.floatingExpandedSurfaceCoversHeader ?
      fullHeaderReservedHeight * (1 - this.resolveFloatingExpandedSurfaceCoverProgress()) :
      fullHeaderReservedHeight;
    const availableHeight = this.getPanelHeight() - this.getFloatingTopTotalHeight() - headerReservedHeight;
    return Math.max(1, availableHeight);
  }

  private resolveFloatingTopSurfaceGlobalTop(): number {
    if (this.shouldLockFloatingInputGeometry()) {
      return Math.max(0, this.resolveFloatingHeaderGlobalTop() -
        BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP - this.resolveFloatingTopSurfaceHeight());
    }
    return this.getOverlayPanelTop() + this.resolveOverlayPanelTranslateY();
  }

  private resolveFloatingExpandedSurfaceGlobalTop(): number {
    if (this.floatingExpandedContentGeometryLocked) {
      return Math.max(
        0,
        this.getOverlayHostHeight() - this.resolveFloatingBottomGap() -
          Math.max(1, this.floatingExpandedContentHeight)
      ) + this.resolveOverlayPanelTranslateY();
    }
    if (this.floatingExpandedSurfaceCoversHeader) {
      const headerReservedOffset = this.getFloatingHeaderHeight() + BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP;
      return this.resolveFloatingPanelMotionGlobalTop() +
        headerReservedOffset * (1 - this.resolveFloatingExpandedSurfaceCoverProgress());
    }
    return this.resolveFloatingHeaderGlobalTop() + this.getFloatingHeaderHeight() +
      BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP;
  }

  private resolveFloatingExpandedSurfaceCoverProgress(): number {
    return Math.max(0, Math.min(1, this.floatingExpandedSurfaceCoverProgress));
  }

  private resolveFloatingExpandedSurfaceOpacity(): number {
    if (!this.shouldShowFloatingExpandedContent()) {
      return 0;
    }
    return this.resolveFloatingExpandedSurfaceRevealProgress();
  }

  private resolveFloatingExpandedSurfaceTranslateY(): number {
    return (1 - this.resolveFloatingExpandedSurfaceRevealProgress()) *
      BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_TRANSLATE_Y;
  }

  private resolveFloatingExpandedSurfaceRevealProgress(): number {
    if (this.floatingExpandedContentGeometryLocked) {
      return 1;
    }
    if (this.panelDetent === 'middle' && !this.isDraggingPanel && !this.isSettlingPanelDetent) {
      return 1;
    }
    const metrics = this.buildGestureDetentMetrics();
    const travelDistance = Math.max(1, metrics.middleHeight - metrics.lowHeight);
    const rawProgress = (this.currentPanelHeight - metrics.lowHeight) / travelDistance;
    const normalizedProgress = (rawProgress - BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_START_PROGRESS) /
      Math.max(0.01, BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_END_PROGRESS -
      BROWSER_DETENT_FLOATING_EXPANDED_REVEAL_START_PROGRESS);
    return this.resolveSmoothProgress(normalizedProgress);
  }

  private resolveSmoothProgress(progress: number): number {
    const clampedProgress = Math.max(0, Math.min(1, progress));
    return clampedProgress * clampedProgress * (3 - 2 * clampedProgress);
  }

  private resolveFloatingHeaderTop(): number {
    if (this.isFloatingInputLayout()) {
      if (this.shouldLockFloatingInputGeometry()) {
        return Math.max(0, this.resolveLockedFloatingInputHeaderGlobalTop() -
          this.getOverlayPanelTop() - this.resolveOverlayPanelTranslateY());
      }
      return Math.max(0, this.getPanelHeight() - this.getFloatingHeaderHeight());
    }
    return this.getFloatingTopTotalHeight();
  }

  private shouldShowFloatingTopContent(): boolean {
    return this.floatingBlocksEnabled && this.floatingTopContentVisible &&
      this.resolveFloatingTopSurfaceHeight() > 0;
  }

  private shouldShowFloatingExpandedContent(): boolean {
    return this.floatingBlocksEnabled && this.floatingExpandedContentVisible &&
      (this.floatingExpandedContentGeometryLocked ||
        this.panelDetent === 'middle' || this.shouldRevealPanelContent ||
        this.shouldKeepFloatingExpandedContentDuringLowSettle() ||
        this.shouldRevealExpandedContentDuringDrag());
  }

  private shouldPrepareFloatingExpandedContent(): boolean {
    return this.floatingBlocksEnabled &&
      (this.floatingExpandedContentPrepared || this.shouldShowFloatingExpandedContent());
  }

  private shouldKeepFloatingExpandedContentDuringLowSettle(): boolean {
    return this.isSettlingPanelDetent && this.deferredPanelDetentChange === 'low';
  }

  private resolveFloatingTopSurfaceHeight(): number {
    if (!this.isFloatingInputLayout()) {
      return Math.max(0, this.floatingTopContentHeight);
    }
    const maxHeight = Math.max(0, this.resolveLockedFloatingInputHeaderGlobalTop() -
      BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP);
    return Math.min(Math.max(0, this.floatingTopContentHeight), maxHeight);
  }

  private resolveFloatingTopSurfaceOpacity(): number {
    return this.shouldShowFloatingTopContent() ? 1 : 0;
  }

  private resolveFloatingTopSurfaceTranslateY(): number {
    return 0;
  }

  private resolveFloatingSurfaceMotionDuration(): number {
    if (this.floatingHostResizeMotionActive) {
      return 0;
    }
    if (this.isDraggingPanel) {
      return 0;
    }
    return this.getPanelAnimationDuration();
  }

  private getFloatingTopTotalHeight(): number {
    if (!this.shouldShowFloatingTopContent()) {
      return 0;
    }
    return this.resolveFloatingTopSurfaceHeight() + BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP;
  }

  private isFloatingInputLayout(): boolean {
    return this.floatingBlocksEnabled && this.floatingLayoutMode === 'input';
  }

  private resolveMiddleTargetHeight(): number {
    return this.motionState.middlePanelHeight > 0 ? this.motionState.middlePanelHeight : this.getOverlayLowPanelHeight();
  }

  private getOverlayPeekPanelHeight(): number {
    return BROWSER_BOTTOM_ADDRESS_PANEL_PEEK_HEIGHT;
  }

  private resolveRegularPanelBackgroundColor(): ResourceColor {
    return this.panelBackgroundColor === undefined ? this.storedFloatingSurfaceColor : this.panelBackgroundColor;
  }

  private resolveGlassPanelTintColor(): ResourceColor {
    const color = this.resolveRegularPanelBackgroundColor();
    if (this.shouldSuppressLightweightGlassMaterial()) {
      return color;
    }
    return withBrowserBottomPanelGlassTint(color);
  }

  private resolveFloatingExpandedPanelBackgroundColor(): ResourceColor {
    return resolveBrowserBottomFloatingExpandedContainerColor(this.resolveNeutralThemeMode());
  }

  private resolveFloatingExpandedSurfaceBackgroundColor(): ResourceColor {
    return this.floatingExpandedSurfaceChromeVisible ?
      this.resolveFloatingExpandedPanelBackgroundColor() :
      $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveFloatingHeaderBackgroundColor(): ResourceColor {
    if (this.shouldUseFloatingHeaderSystemMaterial()) {
      return this.resolveFloatingHeaderTransparentGlassTint();
    }
    return resolveBrowserBottomFloatingHeaderColor({
      resolvedThemeMode: this.resolveNeutralThemeMode(),
      floatingInputLayout: this.isFloatingInputLayout(),
      keepDefaultChrome: this.shouldKeepFloatingHeaderDefaultChrome(),
      collapsedDarkBackground: this.shouldUseCollapsedFloatingHeaderDarkBackground(),
      grayProgress: this.floatingHeaderBackgroundGrayProgress
    });
  }

  private resolveFloatingHeaderMaterialBackgroundBlurStyle(): BlurStyle {
    if (!this.shouldMountFloatingHeaderSystemMaterial()) {
      return BlurStyle.NONE;
    }
    return this.shouldUseFloatingHeaderSystemMaterial() ?
      BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE :
      BlurStyle.COMPONENT_ULTRA_THICK;
  }

  private resolveFloatingHeaderMaterialBackgroundBlurOptions(): BackgroundBlurStyleOptions {
    return resolveBrowserFloatingGlassMaterialOptionsForMode(this.resolveNeutralThemeMode());
  }

  private resolveFloatingExpandedMaterialBackgroundBlurStyle(): BlurStyle {
    return this.floatingExpandedSurfaceChromeVisible ?
      BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE :
      BlurStyle.NONE;
  }

  private resolveFloatingHeaderTransparentGlassTint(): ResourceColor {
    return resolveBrowserFloatingGlassMaterialTintForMode(this.resolveNeutralThemeMode());
  }

  private resolveFloatingHeaderMaterialBackgroundOpacity(): number {
    return this.floatingHeaderChromeVisible && this.shouldMountFloatingHeaderSystemMaterial() ? 1 : 0;
  }

  private resolveFloatingHeaderColorOverlayOpacity(): number {
    if (!this.floatingHeaderChromeVisible) {
      return 0;
    }
    if (!this.shouldMountFloatingHeaderSystemMaterial()) {
      return 1;
    }
    if (this.isSettlingPanelDetent && this.getSettlingTargetDetent() === 'low' &&
      this.shouldKeepFloatingHeaderDefaultChrome()) {
      return 1;
    }
    return 1;
  }

  private shouldUseFloatingHeaderSystemMaterial(): boolean {
    return this.shouldMountFloatingHeaderSystemMaterial();
  }

  private shouldMountFloatingHeaderSystemMaterial(): boolean {
    return this.floatingBlocksEnabled &&
      this.floatingHeaderChromeVisible &&
      !this.shouldHideOverlayPanel();
  }

  private resolveNeutralThemeMode(): string {
    if (this.materialThemeMode === 'light' || this.materialThemeMode === 'dark') {
      return this.materialThemeMode;
    }
    return this.storedResolvedThemeMode;
  }

  private shouldKeepFloatingHeaderDefaultChrome(): boolean {
    if (this.isFloatingInputLayout()) {
      return true;
    }
    return this.floatingHeaderBackgroundKeepDefaultChrome;
  }

  private shouldUseCollapsedFloatingHeaderDarkBackground(): boolean {
    return this.floatingHeaderBackgroundCollapsedDark;
  }

  private resolveFloatingTopSurfaceBackdropBlurRadius(): number {
    if (!this.floatingTopSurfaceChromeVisible) {
      return 0;
    }
    if (this.isFixedFloatingDarkMode()) {
      return this.resolveBackdropBlurRadius();
    }
    return 0;
  }

  private isFixedFloatingDarkMode(): boolean {
    return this.storedResolvedThemeMode === 'dark';
  }

  private syncFloatingHeaderBackgroundState(allowTransition: boolean): void {
    const nextState = this.buildFloatingHeaderBackgroundStateForDetent(this.panelDetent);
    if (this.isSameFloatingHeaderBackgroundState(nextState)) {
      return;
    }
    if (allowTransition) {
      animateTo({
        duration: BROWSER_DETENT_FLOATING_HEADER_CHROME_TRANSITION_MS,
        curve: Curve.EaseOut
      }, () => {
        this.applyFloatingHeaderBackgroundState(nextState);
      });
      return;
    }
    this.applyFloatingHeaderBackgroundState(nextState);
  }

  private buildFloatingHeaderBackgroundStateForDetent(
    detent: HomeSearchPanelDetent
  ): BrowserDetentFloatingHeaderBackgroundState {
    if (this.shouldKeepFloatingHeaderChromeForUpwardRubberBand()) {
      return this.buildFloatingHeaderLowBackgroundState();
    }
    const grayProgress = this.resolveFloatingHeaderDetentGrayProgress(detent);
    return {
      keepDefaultChrome: this.isFloatingInputLayout() || (detent === 'low' && grayProgress <= 0.01),
      collapsedDarkBackground: this.resolveFloatingHeaderDetentCollapsedDarkBackground(detent),
      grayProgress
    };
  }

  private buildFloatingHeaderLowBackgroundState(): BrowserDetentFloatingHeaderBackgroundState {
    return {
      keepDefaultChrome: true,
      collapsedDarkBackground: true,
      grayProgress: 0
    };
  }

  private resolveFloatingHeaderDetentGrayProgress(detent: HomeSearchPanelDetent): number {
    return detent === 'middle' ? 1 : 0;
  }

  private resolveFloatingHeaderDetentCollapsedDarkBackground(detent: HomeSearchPanelDetent): boolean {
    if (!this.shouldApplyFloatingHeaderHorizontalInset()) {
      return true;
    }
    return this.resolveFloatingHeaderDetentInsetProgress(detent) <= 0.01;
  }

  private isSameFloatingHeaderBackgroundState(nextState: BrowserDetentFloatingHeaderBackgroundState): boolean {
    return this.floatingHeaderBackgroundKeepDefaultChrome === nextState.keepDefaultChrome &&
      this.floatingHeaderBackgroundCollapsedDark === nextState.collapsedDarkBackground &&
      Math.abs(this.floatingHeaderBackgroundGrayProgress - nextState.grayProgress) <= 0.001;
  }

  private applyFloatingHeaderBackgroundState(nextState: BrowserDetentFloatingHeaderBackgroundState): void {
    this.floatingHeaderBackgroundKeepDefaultChrome = nextState.keepDefaultChrome;
    this.floatingHeaderBackgroundCollapsedDark = nextState.collapsedDarkBackground;
    this.floatingHeaderBackgroundGrayProgress = nextState.grayProgress;
  }

  private syncFloatingHeaderShadowVisibility(allowTransition: boolean): void {
    const nextVisible = this.shouldShowFloatingHeaderShadowForDetent(this.panelDetent);
    if (this.floatingHeaderShadowVisible === nextVisible) {
      return;
    }
    if (allowTransition) {
      animateTo({
        duration: BROWSER_DETENT_FLOATING_HEADER_CHROME_TRANSITION_MS,
        curve: Curve.EaseOut
      }, () => {
        this.floatingHeaderShadowVisible = nextVisible;
      });
      return;
    }
    this.floatingHeaderShadowVisible = nextVisible;
  }

  private resolveFloatingPanelShadow(): ShadowOptions {
    return {
      radius: BROWSER_DETENT_FLOATING_PANEL_SHADOW_RADIUS,
      color: BROWSER_DETENT_FLOATING_PANEL_SHADOW_COLOR,
      offsetX: 0,
      offsetY: BROWSER_DETENT_FLOATING_PANEL_SHADOW_OFFSET_Y
    };
  }

  private resolveFloatingTopSurfaceBackgroundColor(): ResourceColor {
    return this.floatingTopSurfaceChromeVisible ?
      this.resolveFloatingExpandedPanelBackgroundColor() :
      $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveFloatingTopSurfaceRadius(): number {
    return this.floatingTopSurfaceChromeVisible ? BROWSER_DETENT_FLOATING_CONTENT_RADIUS : 0;
  }

  private resolveFloatingTopSurfaceShadow(): ShadowOptions {
    return this.floatingTopSurfaceChromeVisible ? this.resolveFloatingPanelShadow() :
      this.resolveEmptyFloatingShadow();
  }

  private resolveFloatingHeaderShadowOpacity(): number {
    if (!this.floatingHeaderChromeVisible || this.shouldHideOverlayPanel()) {
      return 0;
    }
    return this.floatingHeaderShadowVisible && this.shouldAllowFloatingHeaderShadow() ?
      this.resolveFloatingHeaderPresentationOpacity() : 0;
  }

  private resolveFloatingHeaderPresentationOpacity(): number {
    if (this.shouldHideOverlayPanel()) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.floatingHeaderPresentationOpacity));
  }

  private shouldShowFloatingHeaderShadowForDetent(detent: HomeSearchPanelDetent): boolean {
    if (!this.shouldAllowFloatingHeaderShadow()) {
      return false;
    }
    if (this.shouldKeepFloatingHeaderShadowForUpwardRubberBand()) {
      return true;
    }
    if (!this.shouldApplyFloatingHeaderHorizontalInset()) {
      return true;
    }
    return this.resolveFloatingHeaderDetentInsetProgress(detent) <= 0.01;
  }

  private shouldAllowFloatingHeaderShadow(): boolean {
    if (this.isFloatingInputLayout()) {
      return false;
    }
    if (this.storedResolvedThemeMode === 'dark' && !this.shouldUseFloatingHeaderSystemMaterial()) {
      return false;
    }
    return true;
  }

  private shouldKeepFloatingHeaderShadowForUpwardRubberBand(): boolean {
    return this.shouldKeepFloatingHeaderChromeForUpwardRubberBand();
  }

  private shouldKeepFloatingHeaderChromeForUpwardRubberBand(): boolean {
    return this.motionState.suppressExpandedContentFromDrag &&
      this.isDraggingPanel &&
      this.panelDetent === 'low';
  }

  private resolveFloatingExpandedSurfaceRadius(): number {
    return this.floatingExpandedSurfaceChromeVisible ? BROWSER_DETENT_FLOATING_CONTENT_RADIUS : 0;
  }

  private resolveFloatingExpandedSurfaceShadow(): ShadowOptions {
    return this.floatingExpandedSurfaceChromeVisible ? this.resolveFloatingPanelShadow() :
      this.resolveEmptyFloatingShadow();
  }

  private resolveEmptyFloatingShadow(): ShadowOptions {
    return {
      radius: 0,
      color: $r('sys.color.ohos_id_color_background_transparent'),
      offsetX: 0,
      offsetY: 0
    };
  }

  private resolveBackdropBlurRadius(): number {
    if (this.shouldSuppressLiveBackdropBlur()) {
      return 0;
    }
    return BROWSER_BOTTOM_PANEL_GLASS_BACKDROP_BLUR_RADIUS;
  }

  private shouldSuppressLiveBackdropBlur(): boolean {
    return this.liveBackdropBlurSuppressed;
  }

  private shouldSuppressLightweightGlassMaterial(): boolean {
    return this.shouldSuppressLightweightCollapsedMotionGlassMaterial();
  }

  private shouldSuppressLightweightCollapsedMotionGlassMaterial(): boolean {
    if (!this.lightweightCollapsedMotion || this.mode !== 'overlay' || !this.floatingBlocksEnabled) {
      return false;
    }
    return this.panelDetent === 'peek' ||
      this.isPeekToLowPanelTransition;
  }

  private resolveDragHandleColor(): ResourceColor {
    return this.dragHandleColor === undefined ? this.storedControlBackgroundColor : this.dragHandleColor;
  }

  @Builder
  private emptyBuilder() {
  }
}
