import {
  BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserModalPresentationTokens';
import { BrowserLargeScreenModalHeader } from './BrowserLargeScreenModalHeader';
import { BrowserModalBottomOverlay } from './BrowserModalBottomSheet';
import {
  AppWindowModalLayout,
  AppWindowModalLayoutService
} from '../../../services/layout/AppWindowModalLayoutService';

export type BrowserAdaptiveModalLayoutMode = 'phone' | 'large_screen';

@Component
export struct BrowserAdaptiveModalOverlay {
  @Prop @Watch('syncVisible') visible: boolean = false;
  @Prop @Watch('handleLayoutModeChanged') layoutMode: BrowserAdaptiveModalLayoutMode = 'phone';
  @Prop title: string = '';
  @Prop showDesktopHeader: boolean = true;
  @Prop showDesktopRefreshButton: boolean = false;
  @Prop phoneSheetHeight: Length = '';
  @Prop phoneEnterOffsetY: number = 48;
  @Prop animationDurationMs: number = 220;
  @Prop zIndexValue: number = 220;
  @Prop desktopWidth: Length = '82%';
  @Prop desktopHeight: Length = '72%';
  @Prop desktopMinWidth: number = 520;
  @Prop desktopMaxWidth: number = 720;
  @Prop desktopMinHeight: number = 400;
  @Prop desktopMaxHeight: number = 620;
  onDismiss: () => void = () => {};
  onDidDismiss: () => void = () => {};
  refreshAction: () => void = () => {};
  @BuilderParam content: () => void = this.emptyContent;
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  @State private largeScreenCoverVisible: boolean = false;
  @State private largeScreenPresentationVisible: boolean = false;
  private largeScreenRevealTimer: number = -1;
  private largeScreenDismissTimer: number = -1;
  private largeScreenDismissRequested: boolean = false;
  private largeScreenDismissCompletionPending: boolean = false;
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

  aboutToAppear(): void {
    this.syncVisible();
  }

  aboutToDisappear(): void {
    this.clearLargeScreenTimers();
  }

  build() {
    if (this.layoutMode === 'large_screen') {
      Row()
        .width(0)
        .height(0)
        .hitTestBehavior(HitTestMode.None)
        .bindContentCover($$this.largeScreenCoverVisible, this.buildLargeScreenDialog(), {
          modalTransition: ModalTransition.NONE,
          backgroundColor: Color.Transparent,
          onWillDismiss: (_action: DismissContentCoverAction): void => {
            this.requestDismiss();
          },
          onDisappear: (): void => {
            this.handleLargeScreenCoverDisappear();
          }
        })
    } else {
      BrowserModalBottomOverlay({
        visible: this.visible,
        sheetHeight: this.phoneSheetHeight,
        enterOffsetY: this.phoneEnterOffsetY,
        animationDurationMs: this.animationDurationMs,
        zIndexValue: this.zIndexValue,
        onDismiss: this.onDismiss
      }) {
        this.content()
      }
    }
  }

  @Builder
  private buildLargeScreenDialog() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isViewportMeasured()) {
        Stack()
          .backgroundColor($r('app.color.browser_overlay_scrim'))
          .opacity(this.largeScreenPresentationVisible ? 1 : 0)
          .animation({ duration: this.animationDurationMs, curve: Curve.EaseOut })
          .width('100%')
          .height('100%')
          .transition(TransitionEffect.opacity(0).animation({
            duration: this.animationDurationMs,
            curve: Curve.EaseOut
          }))
          .hitTestBehavior(this.largeScreenPresentationVisible ? HitTestMode.Default : HitTestMode.None)
          .onClick((): void => {
            this.requestDismiss();
          })

        Column({ space: 0 }) {
          if (this.showDesktopHeader) {
            BrowserLargeScreenModalHeader({
              title: this.title,
              showRefreshButton: this.showDesktopRefreshButton,
              onRefresh: this.refreshAction,
              onClose: (): void => {
                this.requestDismiss();
              }
            })
          }

          Column() {
            this.content()
          }
          .width('100%')
          .layoutWeight(1)
        }
        .backgroundColor($r('app.color.surface_floating_background'))
        .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
        .clip(true)
        .opacity(this.largeScreenPresentationVisible ? 1 : 0)
        .scale({
          x: this.largeScreenPresentationVisible ? 1 : 0.97,
          y: this.largeScreenPresentationVisible ? 1 : 0.97
        })
        .animation({ duration: this.animationDurationMs, curve: Curve.EaseOut })
        .width(this.resolveDesktopLayout().width)
        .height(this.resolveDesktopLayout().height)
        .transition(TransitionEffect.scale({ x: 0.97, y: 0.97 })
          .combine(TransitionEffect.opacity(0))
          .animation({ duration: this.animationDurationMs, curve: Curve.EaseOut }))
        .hitTestBehavior(this.largeScreenPresentationVisible ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
        .keyboardShortcut(FunctionKey.ESC, [], (): void => {
          this.requestDismiss();
        })
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(this.zIndexValue)
    .hitTestBehavior(this.largeScreenPresentationVisible && this.isViewportMeasured()
      ? HitTestMode.Transparent
      : HitTestMode.None)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
  }

  private resolveDesktopLayout(): AppWindowModalLayout {
    const viewportWidth = this.viewportWidthVp;
    const viewportHeight = this.viewportHeightVp;
    return this.modalLayoutService.resolveModal({
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      preferredWidth: this.resolvePreferredExtent(this.desktopWidth, viewportWidth, 0.82),
      preferredHeight: this.resolvePreferredExtent(this.desktopHeight, viewportHeight, 0.72),
      softMinWidth: this.desktopMinWidth,
      maxWidth: this.desktopMaxWidth,
      softMinHeight: this.desktopMinHeight,
      maxHeight: this.desktopMaxHeight
    });
  }

  private resolvePreferredExtent(value: Length, viewportExtent: number, fallbackRatio: number): number {
    if (typeof value === 'number') {
      return Math.max(1, value);
    }
    if (typeof value === 'string') {
      const normalizedValue = value.trim();
      if (normalizedValue.endsWith('%')) {
        const percentage = Number(normalizedValue.substring(0, normalizedValue.length - 1));
        if (Number.isFinite(percentage) && percentage > 0) {
          return viewportExtent * percentage / 100;
        }
      }
      const absoluteValue = Number(normalizedValue);
      if (Number.isFinite(absoluteValue) && absoluteValue > 0) {
        return absoluteValue;
      }
    }
    return viewportExtent * fallbackRatio;
  }

  private isViewportMeasured(): boolean {
    return Number.isFinite(this.viewportWidthVp) && this.viewportWidthVp > 0 &&
      Number.isFinite(this.viewportHeightVp) && this.viewportHeightVp > 0;
  }

  private handleLayoutModeChanged(): void {
    this.clearLargeScreenTimers();
    this.viewportWidthVp = 0;
    this.viewportHeightVp = 0;
    this.largeScreenCoverVisible = false;
    this.largeScreenPresentationVisible = false;
    this.syncVisible();
  }

  private syncVisible(): void {
    this.clearLargeScreenTimers();
    if (this.layoutMode !== 'large_screen') {
      this.largeScreenCoverVisible = false;
      this.largeScreenPresentationVisible = false;
      this.largeScreenDismissRequested = false;
      return;
    }
    if (!this.visible) {
      this.largeScreenDismissRequested = false;
      this.largeScreenDismissCompletionPending = this.largeScreenCoverVisible;
      this.hideLargeScreenCoverAfterTransition();
      return;
    }
    this.largeScreenDismissRequested = false;
    this.largeScreenDismissCompletionPending = false;
    this.largeScreenCoverVisible = true;
    this.largeScreenPresentationVisible = false;
    this.largeScreenRevealTimer = setTimeout((): void => {
      this.largeScreenRevealTimer = -1;
      if (this.visible && this.layoutMode === 'large_screen') {
        this.largeScreenPresentationVisible = true;
      }
    }, 0);
  }

  private hideLargeScreenCoverAfterTransition(): void {
    this.largeScreenPresentationVisible = false;
    if (!this.largeScreenCoverVisible) {
      return;
    }
    this.largeScreenDismissTimer = setTimeout((): void => {
      this.largeScreenDismissTimer = -1;
      if (!this.visible || this.layoutMode !== 'large_screen') {
        this.largeScreenCoverVisible = false;
      }
    }, this.animationDurationMs);
  }

  private requestDismiss(): void {
    if (!this.visible || !this.largeScreenPresentationVisible || this.largeScreenDismissRequested) {
      return;
    }
    this.largeScreenDismissRequested = true;
    this.onDismiss();
  }

  private handleLargeScreenCoverDisappear(): void {
    const shouldNotifyDismissed: boolean = this.largeScreenDismissCompletionPending;
    this.largeScreenDismissCompletionPending = false;
    this.largeScreenPresentationVisible = false;
    this.viewportWidthVp = 0;
    this.viewportHeightVp = 0;
    if (shouldNotifyDismissed) {
      this.onDidDismiss();
    }
  }

  private clearLargeScreenTimers(): void {
    if (this.largeScreenRevealTimer >= 0) {
      clearTimeout(this.largeScreenRevealTimer);
      this.largeScreenRevealTimer = -1;
    }
    if (this.largeScreenDismissTimer >= 0) {
      clearTimeout(this.largeScreenDismissTimer);
      this.largeScreenDismissTimer = -1;
    }
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  @Builder
  private emptyContent() {
  }
}
