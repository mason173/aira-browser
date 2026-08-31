import { image } from '@kit.ImageKit';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserTabOverviewItemPresentation } from '../../../core/browser/BrowserTabsOverlayViewModel';
import { BrowserTabState } from '../../../core/tabs/TabManager';
import {
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT,
  BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_REVEAL_DURATION_MS,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP,
  BROWSER_TABS_OVERVIEW_IDENTITY_MAX_WIDTH_RATIO,
  BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP
} from '../../../core/browser/BrowserTabsOverviewVisualTokens';
import { SiteIconView } from '../common/SiteIconView';
import { BrowserTabOverviewCard, BrowserTabOverviewCardSelectRect } from './BrowserTabOverviewCard';

const TAB_OVERVIEW_ITEM_PRESSED_SCALE: number = 0.965;
const TAB_OVERVIEW_ITEM_PRESSED_ANIMATION_MS: number = 120;
const TAB_OVERVIEW_ITEM_SWIPE_START_DISTANCE: number = 6;
const TAB_OVERVIEW_ITEM_SWIPE_SNAP_BACK_DURATION_MS: number = 260;
const TAB_OVERVIEW_ITEM_SWIPE_FLYOUT_DURATION_MS: number = 260;
const TAB_OVERVIEW_ITEM_SWIPE_OPACITY_FADE_START_RATIO: number = 0.25;
const TAB_OVERVIEW_ITEM_SWIPE_OPACITY_MIN_BEFORE_DISMISS: number = 0.72;

type BrowserTabOverviewItemSwipePhase = 'idle' | 'dragging' | 'settling' | 'dismissing';
type BrowserTabOverviewItemSwipeDismissMode = 'horizontal' | 'upward';

@Reusable
@Component
export struct BrowserTabOverviewItem {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  @Prop tab: BrowserTabState;
  @Watch('handlePresentationChanged')
  @Prop presentation: BrowserTabOverviewItemPresentation;
  @Prop snapshotImageUri: string = '';
  @Prop snapshotPixelMap: image.PixelMap | undefined = undefined;
  @Prop snapshotAspectFitEnabled: boolean = false;
  @Prop previewHeight: number = 1;
  @Prop cardWidth: number = 132;
  @Prop identityHeaderHeight: number = BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT;
  @Prop identityPreviewGap: number = BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP;
  @Prop tabTranslateX: number = 0;
  @Prop tabTranslateY: number = 0;
  @Prop tabScale: number = 1;
  @Prop tabOpacity: number = 1;
  @Prop identityOpacity: number = 1;
  @Prop identityTranslateY: number = 0;
  @Prop previewCardOpacity: number = 1;
  @Prop snapshotImageOpacity: number = 1;
  @Prop decorationOpacity: number = 1;
  @Prop coveredByMorph: boolean = false;
  @Prop tabEnabled: boolean = true;
  @Prop trackPreviewRectChanges: boolean = false;
  @Prop motionDurationMs: number = 0;
  @Prop motionCurve: Curve | string | ICurve = Curve.Linear;
  @Prop motionDelayMs: number = 0;
  @Prop entryMountAnimationEnabled: boolean = false;
  @Prop entryMountOffsetX: number = 0;
  @Prop entryMountDurationMs: number = 0;
  @Prop entryMountCurve: Curve | string | ICurve = Curve.Linear;
  @Prop entryMountDelayMs: number = 0;
  @Prop swipeDismissThreshold: number = 96;
  @Prop swipeFlyoutOffset: number = 480;
  @Prop swipeDismissMode: BrowserTabOverviewItemSwipeDismissMode = 'horizontal';
  @Prop closeButtonEnabled: boolean = true;
  @Prop closeButtonAlwaysVisible: boolean = false;
  @Prop keyboardBadgeText: string = '';
  @Prop showKeyboardBadge: boolean = false;

  @State private isPressed: boolean = false;
  @State private localSwipeOffsetX: number = 0;
  @State private localSwipeOffsetY: number = 0;
  @State private localSwipePhase: BrowserTabOverviewItemSwipePhase = 'idle';
  @State private localSwipeThresholdReached: boolean = false;
  @State private mountEntryOffsetX: number = 0;
  @State private identityIconOpacity: number = 1;
  private mountEntryTimer: number = 0;
  private closeSelectionSuppressionTimer: number = 0;
  private suppressNextSelection: boolean = false;
  private identityIconKey: string = '';
  private lastPreviewRect: BrowserTabOverviewCardSelectRect | undefined = undefined;

  onSelect: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => void =
    (_tabId: string, _rect?: BrowserTabOverviewCardSelectRect) => {};
  onCloseTab: (tabId: string) => void = (_tabId: string) => {};
  onSwipeStart: (tabId: string) => void = (_tabId: string) => {};
  onSwipeUpdate: (tabId: string, offset: number) => void = (_tabId: string, _offset: number) => {};
  onSwipeEnd: (tabId: string, offset: number, direction: number) => void =
    (_tabId: string, _offset: number, _direction: number) => {};
  onSwipeCancel: (tabId: string) => void = (_tabId: string) => {};
  onSwipeThresholdReached: (tabId: string) => void = (_tabId: string) => {};
  onPreviewRectChange: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};

  aboutToAppear(): void {
    this.identityIconKey = this.resolveIdentityIconKey();
    this.identityIconOpacity = 1;
    this.prepareMountEntryAnimation();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.tab = params.tab as BrowserTabState;
    this.presentation = params.presentation as BrowserTabOverviewItemPresentation;
    this.snapshotImageUri = params.snapshotImageUri as string;
    this.snapshotPixelMap = params.snapshotPixelMap as image.PixelMap | undefined;
    this.snapshotAspectFitEnabled = (params.snapshotAspectFitEnabled as boolean) === true;
    this.previewHeight = params.previewHeight as number;
    this.cardWidth = params.cardWidth as number;
    this.identityHeaderHeight = this.resolveReusableNumber(
      params.identityHeaderHeight as number,
      BROWSER_TABS_OVERVIEW_IDENTITY_HEADER_HEIGHT
    );
    this.identityPreviewGap = this.resolveReusableNumber(
      params.identityPreviewGap as number,
      BROWSER_TABS_OVERVIEW_IDENTITY_PREVIEW_GAP
    );
    this.tabTranslateX = params.tabTranslateX as number;
    this.tabTranslateY = params.tabTranslateY as number;
    this.tabScale = params.tabScale as number;
    this.tabOpacity = params.tabOpacity as number;
    this.identityOpacity = this.resolveReusableNumber(params.identityOpacity as number, 1);
    this.identityTranslateY = this.resolveReusableNumber(params.identityTranslateY as number, 0);
    this.previewCardOpacity = params.previewCardOpacity as number;
    this.snapshotImageOpacity = params.snapshotImageOpacity as number;
    this.decorationOpacity = params.decorationOpacity as number;
    this.coveredByMorph = (params.coveredByMorph as boolean) === true;
    this.tabEnabled = params.tabEnabled as boolean;
    this.trackPreviewRectChanges = params.trackPreviewRectChanges as boolean;
    this.motionDurationMs = params.motionDurationMs as number;
    this.motionCurve = params.motionCurve as Curve | string | ICurve;
    this.motionDelayMs = params.motionDelayMs as number;
    this.entryMountAnimationEnabled = (params.entryMountAnimationEnabled as boolean) === true;
    this.entryMountOffsetX = this.resolveReusableNumber(params.entryMountOffsetX as number, 0);
    this.entryMountDurationMs = this.resolveReusableNumber(params.entryMountDurationMs as number, 0);
    this.entryMountCurve = params.entryMountCurve !== undefined ?
      params.entryMountCurve as Curve | string | ICurve : Curve.Linear;
    this.entryMountDelayMs = this.resolveReusableNumber(params.entryMountDelayMs as number, 0);
    this.swipeDismissThreshold = params.swipeDismissThreshold as number;
    this.swipeFlyoutOffset = params.swipeFlyoutOffset as number;
    this.swipeDismissMode = params.swipeDismissMode === 'upward' ? 'upward' : 'horizontal';
    this.closeButtonEnabled = params.closeButtonEnabled === undefined ||
      (params.closeButtonEnabled as boolean) === true;
    this.closeButtonAlwaysVisible = (params.closeButtonAlwaysVisible as boolean) === true;
    this.keyboardBadgeText = params.keyboardBadgeText as string;
    this.showKeyboardBadge = params.showKeyboardBadge as boolean;
    this.onSelect = params.onSelect as (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => void;
    this.onCloseTab = params.onCloseTab as (tabId: string) => void;
    this.onSwipeStart = params.onSwipeStart === undefined ?
      (_tabId: string) => {} : params.onSwipeStart as (tabId: string) => void;
    this.onSwipeUpdate = params.onSwipeUpdate === undefined ?
      (_tabId: string, _offset: number) => {} :
      params.onSwipeUpdate as (tabId: string, offset: number) => void;
    this.onSwipeEnd = params.onSwipeEnd as (tabId: string, offset: number, direction: number) => void;
    this.onSwipeCancel = params.onSwipeCancel === undefined ?
      (_tabId: string) => {} : params.onSwipeCancel as (tabId: string) => void;
    this.onSwipeThresholdReached = params.onSwipeThresholdReached as (tabId: string) => void;
    this.onPreviewRectChange = params.onPreviewRectChange as (
      tabId: string,
      left: number,
      top: number,
      width: number,
      height: number
    ) => void;
    this.resetLocalInteractionStateForReuse();
    this.identityIconKey = this.resolveIdentityIconKey();
    this.identityIconOpacity = 1;
    this.prepareMountEntryAnimation();
  }

  aboutToDisappear(): void {
    this.clearMountEntryTimer();
    this.clearCloseSelectionSuppressionTimer();
  }

  build() {
    Stack() {
      Column({ space: this.identityPreviewGap }) {
        this.buildIdentityHeader()

        BrowserTabOverviewCard({
          tab: this.tab,
          presentation: this.presentation.preview,
          snapshotImageUri: this.snapshotImageUri,
          snapshotPixelMap: this.snapshotPixelMap,
          snapshotAspectFitEnabled: this.snapshotAspectFitEnabled,
          previewHeight: this.previewHeight,
          cardWidth: this.cardWidth,
          previewCardOpacity: this.previewCardOpacity,
          snapshotImageOpacity: this.snapshotImageOpacity,
          decorationOpacity: this.decorationOpacity,
          coveredByMorph: this.coveredByMorph,
          tabEnabled: this.tabEnabled,
          trackPreviewRectChanges: true,
          closeButtonEnabled: this.closeButtonEnabled,
          closeButtonAlwaysVisible: this.closeButtonAlwaysVisible,
          keyboardBadgeText: this.keyboardBadgeText,
          showKeyboardBadge: this.showKeyboardBadge,
          onCloseTab: (tabId: string): void => {
            this.suppressSelectionFromClose();
            this.isPressed = false;
            this.onCloseTab(tabId);
          },
          onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number): void => {
            this.recordPreviewRect(tabId, left, top, width, height);
          }
        })
          .width(this.cardWidth)
          .height(this.previewHeight)
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .scale({ x: this.resolvePressedScale(), y: this.resolvePressedScale() })
      .animation({
        duration: TAB_OVERVIEW_ITEM_PRESSED_ANIMATION_MS,
        curve: Curve.EaseOut
      })
    }
    .width('100%')
    .height(this.resolveItemHeight())
    .translate({
      x: this.tabTranslateX + this.mountEntryOffsetX + this.localSwipeOffsetX,
      y: this.tabTranslateY + this.localSwipeOffsetY
    })
    .scale({ x: this.tabScale, y: this.tabScale })
    .opacity(this.tabOpacity * this.resolveLocalSwipeOpacity())
    .enabled(this.tabEnabled)
    .hitTestBehavior(this.tabEnabled ? HitTestMode.Default : HitTestMode.None)
    .accessibilityText(`切换到${this.presentation.identity.label}`)
    .onClick((event: ClickEvent) => {
      if (this.consumeCloseSelectionSuppression()) {
        return;
      }
      if (this.tabEnabled && this.localSwipePhase === 'idle') {
        this.onSelect(this.tab.id, this.buildPreviewRectFromClickEvent(event) ?? this.lastPreviewRect);
      }
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .gesture(
      PanGesture({
        direction: this.swipeDismissMode === 'upward' ? PanDirection.Vertical : PanDirection.Horizontal,
        distance: TAB_OVERVIEW_ITEM_SWIPE_START_DISTANCE
      })
        .onActionStart(() => {
          this.beginLocalSwipe();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateLocalSwipe(event);
        })
        .onActionEnd((event: GestureEvent) => {
          this.endLocalSwipe(event);
        })
        .onActionCancel(() => {
          this.cancelLocalSwipe();
        }),
      GestureMask.Normal
    )
    .animation({
      duration: this.resolveRootMotionDurationMs(),
      curve: this.resolveRootMotionCurve(),
      delay: this.motionDelayMs
    })
  }

  @Builder
  private buildIdentityHeader() {
    Row({ space: BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP }) {
      SiteIconView({
        iconUri: this.presentation.identity.iconUri,
        iconPixelMap: this.presentation.identity.iconPixelMap,
        fallbackLabel: this.presentation.identity.fallbackLabel,
        fallbackAiraIconId: this.presentation.identity.fallbackAiraIconId,
        fallbackIconSize: 16,
        iconSize: BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE,
        cornerRadiusRatio: 0.22,
        frameBorderWidth: 0,
        contentPadding: 0,
        fallbackFontSize: 12,
        fallbackFontWeight: FontWeight.Medium,
        containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        preferPixelMap: this.presentation.identity.iconPixelMap !== undefined,
        sourceRevision: this.presentation.identity.sourceRevision,
        hitTestMode: HitTestMode.None
      })
        .opacity(this.identityIconOpacity)

      Text(this.presentation.identity.label)
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(this.resolveIdentityHeaderWidth())
    .height(this.identityHeaderHeight)
    .margin({ left: BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .opacity(this.identityOpacity)
    .translate({ y: this.identityTranslateY })
    .hitTestBehavior(HitTestMode.None)
  }

  private handlePresentationChanged(): void {
    const nextKey = this.resolveIdentityIconKey();
    if (nextKey === this.identityIconKey) {
      return;
    }
    this.identityIconKey = nextKey;
    if (this.presentation.identity.iconUri.trim().length <= 0) {
      this.identityIconOpacity = 1;
      return;
    }
    this.identityIconOpacity = 0;
    animateTo({
      duration: BROWSER_TABS_OVERVIEW_IDENTITY_ICON_REVEAL_DURATION_MS,
      curve: Curve.EaseOut
    }, () => {
      this.identityIconOpacity = 1;
    });
  }

  private resolveIdentityIconKey(): string {
    const identity = this.presentation.identity;
    const kind = identity.iconPixelMap !== undefined ? 'pixelmap' : 'uri';
    return `${kind}|${identity.iconUri.trim()}|${Math.max(0, Math.floor(identity.sourceRevision))}`;
  }

  private recordPreviewRect(
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ): void {
    this.lastPreviewRect = { left: left, top: top, width: width, height: height };
    if (this.trackPreviewRectChanges) {
      this.onPreviewRectChange(tabId, left, top, width, height);
    }
  }

  private buildPreviewRectFromClickEvent(event: ClickEvent): BrowserTabOverviewCardSelectRect | undefined {
    const area = event.target.area;
    const width = this.parseAreaDimension(area.width);
    if (width <= 0) {
      return undefined;
    }
    return {
      left: this.resolveClickTargetLeft(event, area),
      top: this.resolveClickTargetTop(event, area) + this.identityHeaderHeight + this.identityPreviewGap,
      width: width,
      height: Math.max(1, this.previewHeight)
    };
  }

  private resolveClickTargetLeft(event: ClickEvent, area: Area): number {
    const left = event.windowX - event.x;
    return Number.isFinite(left) ? left : this.parseAreaPosition(area.globalPosition.x);
  }

  private resolveClickTargetTop(event: ClickEvent, area: Area): number {
    const top = event.windowY - event.y;
    return Number.isFinite(top) ? top : this.parseAreaPosition(area.globalPosition.y);
  }

  private updatePressed(type: TouchType): void {
    if (!this.tabEnabled) {
      this.isPressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.isPressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.isPressed = false;
    }
  }

  private resetLocalInteractionStateForReuse(): void {
    this.clearCloseSelectionSuppressionTimer();
    this.isPressed = false;
    this.localSwipeOffsetX = 0;
    this.localSwipeOffsetY = 0;
    this.localSwipePhase = 'idle';
    this.localSwipeThresholdReached = false;
    this.lastPreviewRect = undefined;
  }

  private suppressSelectionFromClose(): void {
    this.clearCloseSelectionSuppressionTimer();
    this.suppressNextSelection = true;
    this.closeSelectionSuppressionTimer = setTimeout(() => {
      this.closeSelectionSuppressionTimer = 0;
      this.suppressNextSelection = false;
    }, 0);
  }

  private consumeCloseSelectionSuppression(): boolean {
    if (!this.suppressNextSelection) {
      return false;
    }
    this.clearCloseSelectionSuppressionTimer();
    return true;
  }

  private clearCloseSelectionSuppressionTimer(): void {
    if (this.closeSelectionSuppressionTimer !== 0) {
      clearTimeout(this.closeSelectionSuppressionTimer);
      this.closeSelectionSuppressionTimer = 0;
    }
    this.suppressNextSelection = false;
  }

  private prepareMountEntryAnimation(): void {
    this.clearMountEntryTimer();
    if (!this.entryMountAnimationEnabled || Math.abs(this.entryMountOffsetX) < 1) {
      this.mountEntryOffsetX = 0;
      return;
    }
    this.mountEntryOffsetX = this.entryMountOffsetX;
    const delayMs = Math.max(0, Math.floor(this.entryMountDelayMs));
    this.mountEntryTimer = setTimeout(() => {
      this.mountEntryTimer = 0;
      animateTo({
        duration: Math.max(0, Math.floor(this.entryMountDurationMs)),
        curve: this.entryMountCurve
      }, () => {
        this.mountEntryOffsetX = 0;
      });
    }, delayMs);
  }

  private clearMountEntryTimer(): void {
    if (this.mountEntryTimer !== 0) {
      clearTimeout(this.mountEntryTimer);
      this.mountEntryTimer = 0;
    }
  }

  private resolveReusableNumber(value: number, fallback: number): number {
    return Number.isFinite(value) ? value : fallback;
  }

  private resolvePressedScale(): number {
    return this.isPressed && this.tabEnabled ? TAB_OVERVIEW_ITEM_PRESSED_SCALE : 1;
  }

  private beginLocalSwipe(): void {
    if (!this.tabEnabled) {
      return;
    }
    this.isPressed = false;
    this.localSwipePhase = 'dragging';
    this.localSwipeOffsetX = 0;
    this.localSwipeOffsetY = 0;
    this.localSwipeThresholdReached = false;
    this.onSwipeStart(this.tab.id);
  }

  private updateLocalSwipe(event: GestureEvent): void {
    if (!this.tabEnabled || this.localSwipePhase === 'dismissing') {
      return;
    }
    const gestureOffset = this.resolveLocalSwipeGestureOffset(event);
    if (!Number.isFinite(gestureOffset)) {
      return;
    }
    this.localSwipePhase = 'dragging';
    if (this.swipeDismissMode === 'upward') {
      this.localSwipeOffsetX = 0;
      this.localSwipeOffsetY = Math.min(0, gestureOffset);
    } else {
      this.localSwipeOffsetX = gestureOffset;
      this.localSwipeOffsetY = 0;
    }
    const swipeOffset = this.resolveActiveLocalSwipeOffset();
    if (this.hasReachedLocalSwipeDismissThreshold(swipeOffset)) {
      this.markLocalSwipeThresholdReached();
    }
    this.onSwipeUpdate(this.tab.id, swipeOffset);
  }

  private endLocalSwipe(event: GestureEvent): void {
    if (this.localSwipePhase === 'idle' || this.localSwipePhase === 'dismissing') {
      return;
    }
    const eventOffset = this.resolveLocalSwipeGestureOffset(event);
    const normalizedEventOffset = this.normalizeLocalSwipeGestureOffset(eventOffset);
    const swipeOffset = Number.isFinite(normalizedEventOffset) ?
      normalizedEventOffset : this.resolveActiveLocalSwipeOffset();
    const direction = swipeOffset < 0 ? -1 : 1;
    if (this.hasReachedLocalSwipeDismissThreshold(swipeOffset)) {
      this.markLocalSwipeThresholdReached();
      this.dismissLocalSwipe(direction);
      this.onSwipeEnd(this.tab.id, swipeOffset, direction);
      return;
    }
    this.settleLocalSwipe();
    this.onSwipeCancel(this.tab.id);
  }

  private cancelLocalSwipe(): void {
    if (this.localSwipePhase === 'idle' || this.localSwipePhase === 'dismissing') {
      return;
    }
    this.settleLocalSwipe();
    this.onSwipeCancel(this.tab.id);
  }

  private settleLocalSwipe(): void {
    this.localSwipePhase = 'settling';
    this.localSwipeOffsetX = 0;
    this.localSwipeOffsetY = 0;
    setTimeout(() => {
      if (this.localSwipePhase === 'settling') {
        this.localSwipePhase = 'idle';
        this.localSwipeThresholdReached = false;
      }
    }, TAB_OVERVIEW_ITEM_SWIPE_SNAP_BACK_DURATION_MS);
  }

  private dismissLocalSwipe(direction: number): void {
    this.localSwipePhase = 'dismissing';
    const normalizedDirection = direction < 0 ? -1 : 1;
    if (this.swipeDismissMode === 'upward') {
      this.localSwipeOffsetX = 0;
      this.localSwipeOffsetY = this.resolveLocalSwipeFlyoutOffset(-1);
      return;
    }
    this.localSwipeOffsetX = this.resolveLocalSwipeFlyoutOffset(normalizedDirection);
    this.localSwipeOffsetY = 0;
  }

  private markLocalSwipeThresholdReached(): void {
    if (this.localSwipeThresholdReached) {
      return;
    }
    this.localSwipeThresholdReached = true;
    this.onSwipeThresholdReached(this.tab.id);
  }

  private resolveLocalSwipeOpacity(): number {
    if (this.localSwipePhase === 'idle') {
      return 1;
    }
    const threshold = this.resolveLocalSwipeDismissThreshold();
    const activeOffset = this.resolveActiveLocalSwipeOffset();
    const offset = Math.abs(activeOffset);
    const fadeStart = threshold * TAB_OVERVIEW_ITEM_SWIPE_OPACITY_FADE_START_RATIO;
    const dragProgress = this.normalizeProgress(offset, fadeStart, threshold);
    const dragOpacity = 1 - dragProgress * (1 - TAB_OVERVIEW_ITEM_SWIPE_OPACITY_MIN_BEFORE_DISMISS);
    if (this.localSwipePhase !== 'dismissing' || offset <= threshold) {
      return dragOpacity;
    }
    const flyoutDistance = Math.max(threshold + 1, Math.abs(this.resolveLocalSwipeFlyoutOffset(
      activeOffset < 0 ? -1 : 1)));
    const dismissProgress = this.normalizeProgress(offset, threshold, flyoutDistance);
    return TAB_OVERVIEW_ITEM_SWIPE_OPACITY_MIN_BEFORE_DISMISS * (1 - dismissProgress);
  }

  private resolveRootMotionDurationMs(): number {
    if (this.localSwipePhase === 'dragging') {
      return 0;
    }
    if (this.localSwipePhase === 'settling') {
      return TAB_OVERVIEW_ITEM_SWIPE_SNAP_BACK_DURATION_MS;
    }
    if (this.localSwipePhase === 'dismissing') {
      return TAB_OVERVIEW_ITEM_SWIPE_FLYOUT_DURATION_MS;
    }
    return this.motionDurationMs;
  }

  private resolveRootMotionCurve(): Curve | string | ICurve {
    if (this.localSwipePhase === 'settling') {
      return 'interpolatingSpring(0, 1, 280, 28)';
    }
    if (this.localSwipePhase === 'dismissing') {
      return 'cubic-bezier(0.32, 0, 0.67, 0)';
    }
    return this.motionCurve;
  }

  private resolveLocalSwipeDismissThreshold(): number {
    return Math.max(1, this.swipeDismissThreshold);
  }

  private resolveLocalSwipeFlyoutOffset(direction: number): number {
    return (direction < 0 ? -1 : 1) * Math.max(
      this.resolveLocalSwipeDismissThreshold() + 1,
      this.swipeFlyoutOffset
    );
  }

  private resolveLocalSwipeGestureOffset(event: GestureEvent): number {
    return this.swipeDismissMode === 'upward' ? Number(event.offsetY) : Number(event.offsetX);
  }

  private normalizeLocalSwipeGestureOffset(offset: number): number {
    if (!Number.isFinite(offset)) {
      return offset;
    }
    return this.swipeDismissMode === 'upward' ? Math.min(0, offset) : offset;
  }

  private resolveActiveLocalSwipeOffset(): number {
    return this.swipeDismissMode === 'upward' ? this.localSwipeOffsetY : this.localSwipeOffsetX;
  }

  private hasReachedLocalSwipeDismissThreshold(offset: number): boolean {
    if (this.swipeDismissMode === 'upward') {
      return offset <= -this.resolveLocalSwipeDismissThreshold();
    }
    return Math.abs(offset) >= this.resolveLocalSwipeDismissThreshold();
  }

  private normalizeProgress(value: number, start: number, end: number): number {
    if (end <= start) {
      return value >= end ? 1 : 0;
    }
    return Math.max(0, Math.min(1, (value - start) / (end - start)));
  }

  private resolveItemHeight(): number {
    return Math.max(1, this.identityHeaderHeight + this.identityPreviewGap + this.previewHeight);
  }

  private resolveIdentityHeaderWidth(): number {
    const availableWidth = Math.max(1, this.cardWidth - BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET);
    return Math.min(
      availableWidth,
      Math.max(
        BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE + BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP,
        this.cardWidth * BROWSER_TABS_OVERVIEW_IDENTITY_MAX_WIDTH_RATIO
      )
    );
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseAreaPosition(value?: Length): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
