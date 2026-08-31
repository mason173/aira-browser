import { curves } from '@kit.ArkUI';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { FloatingGlassMaterialSurface } from './FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from './FloatingGlassMaterialTokens';

const TOP_FLOATING_DEFAULT_HORIZONTAL_MARGIN: number = 14;
const TOP_FLOATING_DEFAULT_RADIUS: number = 18;
const TOP_FLOATING_DEFAULT_ANIMATION_MS: number = 520;
export const TOP_FLOATING_OVERLAY_ENTRY_CURVE: ICurve = curves.springMotion(0.5, 0.72);
export const TOP_FLOATING_OVERLAY_EXIT_CURVE: Curve = Curve.EaseIn;
const TOP_FLOATING_SWIPE_START_DISTANCE: number = 6;
const TOP_FLOATING_SWIPE_DISMISS_THRESHOLD: number = 34;
const TOP_FLOATING_SWIPE_DOWN_RESISTANCE: number = 0.22;
const TOP_FLOATING_SWIPE_DOWN_LIMIT: number = 10;
const TOP_FLOATING_SWIPE_SNAP_BACK_MS: number = 220;
const TOP_FLOATING_SWIPE_CLOSE_MS: number = 180;
const TOP_FLOATING_SWIPE_DEFAULT_FLYOUT_OFFSET_Y: number = -124;

@Component
export struct TopFloatingOverlayHost {
  @Watch('syncPresentedState')
  @Prop visible: boolean = false;
  @Prop topOffsetVp: number = 0;
  horizontalMarginVp: number = TOP_FLOATING_DEFAULT_HORIZONTAL_MARGIN;
  @Prop explicitWidthVp: number = 0;
  @Prop explicitLeftVp: number = -1;
  topGapVp: number = 6;
  hiddenOffsetYVp: number = -72;
  zIndexValue: number = 90;
  animationDurationMs: number = TOP_FLOATING_DEFAULT_ANIMATION_MS;
  animationCurve: Curve | string | ICurve = TOP_FLOATING_OVERLAY_ENTRY_CURVE;
  exitAnimationCurve: Curve | string | ICurve = TOP_FLOATING_OVERLAY_EXIT_CURVE;
  visibleHitTestMode: HitTestMode = HitTestMode.Default;
  @State private presented: boolean = false;
  private presentationTimer: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.syncPresentedState();
  }

  aboutToDisappear(): void {
    this.clearPresentationTimer();
  }

  build() {
    Column() {
      this.buildPresentationLayer()
    }
    .width(this.resolveSurfaceWidth())
    .position({
        x: this.resolveSurfaceLeft(),
        y: this.topOffsetVp + this.topGapVp
      })
    .hitTestBehavior(this.visible ? this.visibleHitTestMode : HitTestMode.None)
    .zIndex(this.zIndexValue)
  }

  @Builder
  private buildPresentationLayer() {
    Column() {
      this.content()
    }
    .width('100%')
    .opacity(this.presented ? 1 : 0)
    .translate({ y: this.presented ? 0 : this.hiddenOffsetYVp })
    .animation({
      duration: this.animationDurationMs,
      curve: this.visible ? this.animationCurve : this.exitAnimationCurve
    })
  }

  @Builder
  private emptyContent() {
  }

  private resolveSurfaceWidth(): Length {
    return this.explicitWidthVp > 0
      ? this.explicitWidthVp
      : `calc(100% - ${this.horizontalMarginVp * 2}vp)`;
  }

  private resolveSurfaceLeft(): number {
    return this.explicitLeftVp >= 0 ? this.explicitLeftVp : this.horizontalMarginVp;
  }

  private syncPresentedState(): void {
    this.clearPresentationTimer();
    if (!this.visible) {
      this.presented = false;
      return;
    }
    this.presented = false;
    this.presentationTimer = setTimeout(() => {
      this.presentationTimer = 0;
      this.presented = true;
    }, 24);
  }

  private clearPresentationTimer(): void {
    if (this.presentationTimer !== 0) {
      clearTimeout(this.presentationTimer);
      this.presentationTimer = 0;
    }
  }
}

@Component
export struct TopFloatingSwipeDismissContainer {
  @Watch('resetSwipeState')
  @Prop active: boolean = true;
  @Watch('resetSwipeState')
  @Prop resetKey: string = '';
  entryVisible: boolean = true;
  entryOffsetYVp: number = 0;
  flyoutOffsetYVp: number = TOP_FLOATING_SWIPE_DEFAULT_FLYOUT_OFFSET_Y;
  @State private swipeOffsetY: number = 0;
  @State private swipeDragging: boolean = false;
  @State private swipeClosing: boolean = false;
  private swipeCloseTimer: number = 0;
  private dismissedNotified: boolean = false;
  onDismissed: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;

  aboutToAppear(): void {
    this.resetSwipeState();
  }

  aboutToDisappear(): void {
    this.clearSwipeCloseTimer();
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .opacity(this.resolveOpacity())
    .translate({ y: this.resolveTranslateY() })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: TOP_FLOATING_SWIPE_START_DISTANCE })
        .onActionStart(() => {
          this.beginSwipeDismissGesture();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateSwipeDismissGesture(event);
        })
        .onActionEnd((event: GestureEvent) => {
          this.endSwipeDismissGesture(event);
        })
        .onActionCancel(() => {
          this.cancelSwipeDismissGesture();
        }),
      GestureMask.Normal
    )
  }

  private resetSwipeState(): void {
    this.clearSwipeCloseTimer();
    this.swipeOffsetY = 0;
    this.swipeDragging = false;
    this.swipeClosing = false;
    this.dismissedNotified = false;
  }

  private beginSwipeDismissGesture(): void {
    if (!this.active || this.swipeClosing) {
      return;
    }
    this.clearSwipeCloseTimer();
    this.swipeDragging = true;
    this.swipeOffsetY = 0;
  }

  private updateSwipeDismissGesture(event: GestureEvent): void {
    if (!this.active || this.swipeClosing) {
      return;
    }
    const offsetY = Number(event.offsetY);
    if (!Number.isFinite(offsetY)) {
      return;
    }
    this.swipeOffsetY = this.clampSwipeOffsetY(offsetY);
  }

  private endSwipeDismissGesture(event: GestureEvent): void {
    if (!this.active || this.swipeClosing) {
      return;
    }
    const eventOffsetY = Number(event.offsetY);
    const offsetY = Number.isFinite(eventOffsetY) ? this.clampSwipeOffsetY(eventOffsetY) : this.swipeOffsetY;
    if (offsetY <= -TOP_FLOATING_SWIPE_DISMISS_THRESHOLD) {
      this.dismissBySwipe();
      return;
    }
    this.cancelSwipeDismissGesture();
  }

  private cancelSwipeDismissGesture(): void {
    if (this.swipeClosing) {
      return;
    }
    this.swipeDragging = false;
    animateTo({
      duration: TOP_FLOATING_SWIPE_SNAP_BACK_MS,
      curve: Curve.EaseOut
    }, () => {
      this.swipeOffsetY = 0;
    });
  }

  private dismissBySwipe(): void {
    this.swipeDragging = false;
    this.clearSwipeCloseTimer();
    animateTo({
      duration: TOP_FLOATING_SWIPE_CLOSE_MS,
      curve: 'cubic-bezier(0.2, 0, 0, 1)',
      onFinish: () => {
        this.notifyDismissed();
      }
    }, () => {
      this.swipeClosing = true;
      this.swipeOffsetY = this.flyoutOffsetYVp;
    });
    this.swipeCloseTimer = setTimeout(() => {
      this.notifyDismissed();
    }, TOP_FLOATING_SWIPE_CLOSE_MS + 80);
  }

  private notifyDismissed(): void {
    if (this.dismissedNotified) {
      return;
    }
    this.dismissedNotified = true;
    this.clearSwipeCloseTimer();
    this.onDismissed();
  }

  private clearSwipeCloseTimer(): void {
    if (this.swipeCloseTimer !== 0) {
      clearTimeout(this.swipeCloseTimer);
      this.swipeCloseTimer = 0;
    }
  }

  private clampSwipeOffsetY(offsetY: number): number {
    if (offsetY > 0) {
      return Math.min(TOP_FLOATING_SWIPE_DOWN_LIMIT, offsetY * TOP_FLOATING_SWIPE_DOWN_RESISTANCE);
    }
    return Math.max(this.flyoutOffsetYVp, offsetY);
  }

  private resolveTranslateY(): number {
    const entryOffsetY = this.entryVisible ? 0 : this.entryOffsetYVp;
    return entryOffsetY + this.swipeOffsetY;
  }

  private resolveOpacity(): number {
    if (this.swipeClosing) {
      return 0;
    }
    const entryOpacity = this.entryVisible ? 1 : 0;
    if (this.swipeOffsetY >= 0) {
      return entryOpacity;
    }
    const progress = Math.min(1, Math.abs(this.swipeOffsetY) / (TOP_FLOATING_SWIPE_DISMISS_THRESHOLD * 1.4));
    return entryOpacity * (1 - progress * 0.28);
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct TopFloatingSurface {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  heightVp: number = 54;
  radiusVp: number = TOP_FLOATING_DEFAULT_RADIUS;
  paddingLeftVp: number = 0;
  paddingRightVp: number = 0;
  paddingTopVp: number = 0;
  paddingBottomVp: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Stack() {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.heightVp,
        surfaceRadius: this.radiusVp,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Row() {
          this.content()
        }
        .width('100%')
        .height('100%')
        .padding({
          left: this.paddingLeftVp,
          right: this.paddingRightVp,
          top: this.paddingTopVp,
          bottom: this.paddingBottomVp
        })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .height(this.heightVp)
    .borderRadius(this.radiusVp)
  }

  @Builder
  private emptyContent() {
  }
}
