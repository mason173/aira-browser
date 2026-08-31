import {
  BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  resolveBrowserBottomPanelMotionCurve
} from '../../../core/browser/BrowserBottomPanelMotionTokens';
import { BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT } from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import {
  BrowserBottomPanelHostMode,
  BrowserRootBottomPanelScene
} from '../../../core/browser/BrowserRootBottomPanelSessionCoordinator';
import {
  BrowserBottomPanelResponsiveState,
  DEFAULT_BROWSER_BOTTOM_PANEL_RESPONSIVE_STATE
} from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import {
  BrowserBottomPanelLivePresentation,
  BrowserBottomPanelPresentationChannel,
  DEFAULT_BROWSER_BOTTOM_PANEL_LIVE_PRESENTATION
} from '../../../core/browser/BrowserBottomPanelPresentationChannel';

interface BrowserBottomPanelHostTransitionSpec {
  durationMs: number;
  settleDelayMs: number;
  curve: Curve | string | ICurve;
  incomingStartOpacity: number;
  incomingStartScale: number;
  incomingStartOffsetY: number;
  outgoingEndOpacity: number;
  outgoingEndScale: number;
  outgoingEndOffsetY: number;
}

interface BrowserBottomPanelHostTabsOverviewHomeEntrySpec {
  durationMs: number;
  settleDelayMs: number;
  curve: Curve | string | ICurve;
  startOpacity: number;
  startOffsetY: number;
}

const BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC: BrowserBottomPanelHostTransitionSpec = {
  durationMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  settleDelayMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  curve: resolveBrowserBottomPanelMotionCurve(),
  incomingStartOpacity: 0,
  incomingStartScale: 0.997,
  incomingStartOffsetY: 4,
  outgoingEndOpacity: 0,
  outgoingEndScale: 0.997,
  outgoingEndOffsetY: 4
};
const BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC:
BrowserBottomPanelHostTabsOverviewHomeEntrySpec = {
  durationMs: 180,
  settleDelayMs: 220,
  curve: BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_CURVE,
  startOpacity: 1,
  startOffsetY: BROWSER_BOTTOM_ADDRESS_PANEL_LOW_HEIGHT + 8
};

export interface BrowserBottomPanelRenderContext {
  responsiveState: BrowserBottomPanelResponsiveState;
  presentationChannel: BrowserBottomPanelPresentationChannel;
}

@Component
export struct BrowserBottomPanelHost {
  @State private renderedMode: BrowserBottomPanelHostMode = 'hidden';
  @State private previousMode: BrowserBottomPanelHostMode = 'hidden';
  @State private incomingOpacity: number = 1;
  @State private incomingScale: number = 1;
  @State private incomingOffsetY: number = 0;
  @State private outgoingOpacity: number = 0;
  @State private outgoingScale: number = 1;
  @State private outgoingOffsetY: number = 0;
  private transitionVersion: number = 0;
  private handledTabsOverviewHomeEntryRequestVersion: number = 0;
  private presentationChannel: BrowserBottomPanelPresentationChannel =
    new BrowserBottomPanelPresentationChannel();
  @Prop
  @Watch('syncModeTransition')
  mode: BrowserBottomPanelHostMode = 'hidden';
  @Prop
  scene: BrowserRootBottomPanelScene = 'inactive';
  @Prop
  @Watch('syncTabsOverviewHomeEntryRequest')
  tabsOverviewHomeEntryRequestVersion: number = 0;
  @Prop
  @Watch('syncTabsOverviewHomeEntryEligibility')
  tabsOverviewHomeEntryEligible: boolean = false;
  @Prop hostHeight: number = 0;
  @Prop responsiveState: BrowserBottomPanelResponsiveState = DEFAULT_BROWSER_BOTTOM_PANEL_RESPONSIVE_STATE;
  @Prop
  @Watch('publishLivePresentation')
  livePresentation: BrowserBottomPanelLivePresentation = DEFAULT_BROWSER_BOTTOM_PANEL_LIVE_PRESENTATION;
  @Prop layoutRenderKey: string = '';
  @Prop layerZIndex: number = 120;
  @Prop interactiveOutsidePanel: boolean = false;
  @BuilderParam homePanel: (context: BrowserBottomPanelRenderContext) => void = this.emptyPanelBuilder;
  @BuilderParam webPanel: (context: BrowserBottomPanelRenderContext) => void = this.emptyPanelBuilder;

  aboutToAppear(): void {
    this.renderedMode = this.mode;
    this.previousMode = 'hidden';
    this.incomingOpacity = 1;
    this.incomingScale = 1;
    this.incomingOffsetY = 0;
    this.outgoingOpacity = 0;
    this.outgoingScale = 1;
    this.outgoingOffsetY = 0;
    this.publishLivePresentation();
    this.prepareInitialTabsOverviewHomeEntryIfNeeded();
  }

  build() {
    if ((this.renderedMode !== 'hidden' || this.previousMode !== 'hidden') && this.hostHeight > 0) {
      Stack({ alignContent: Alignment.Bottom }) {
        if (this.previousMode !== 'hidden') {
          Stack({ alignContent: Alignment.Bottom }) {
            this.buildPanelForMode(this.previousMode)
          }
          .width('100%')
          .height(this.resolveEffectiveHostHeight())
          .opacity(this.outgoingOpacity)
          .scale({ x: this.outgoingScale, y: this.outgoingScale, centerX: '50%', centerY: '100%' })
          .translate({ y: this.outgoingOffsetY })
          .hitTestBehavior(HitTestMode.None)
        }

        if (this.renderedMode !== 'hidden') {
          Stack({ alignContent: Alignment.Bottom }) {
            this.buildPanelForMode(this.renderedMode)
          }
          .width('100%')
          .height(this.resolveEffectiveHostHeight())
          .opacity(this.incomingOpacity)
          .scale({ x: this.incomingScale, y: this.incomingScale, centerX: '50%', centerY: '100%' })
          .translate({ y: this.incomingOffsetY })
          .hitTestBehavior(this.interactiveOutsidePanel ? HitTestMode.Default : HitTestMode.Transparent)
        }
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Bottom)
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(this.layerZIndex)
    }
  }

  @Builder
  private buildPanelForMode(mode: BrowserBottomPanelHostMode) {
    if (mode === 'browser') {
      if (this.scene === 'home') {
        ForEach([this.resolvePanelLayoutIdentity(mode, 'home')], (_layoutIdentity: string) => {
          this.homePanel(this.buildPanelRenderContext())
        }, (layoutIdentity: string) => layoutIdentity)
      } else if (this.scene === 'web') {
        ForEach([this.resolvePanelLayoutIdentity(mode, 'web')], (_layoutIdentity: string) => {
          this.webPanel(this.buildPanelRenderContext())
        }, (layoutIdentity: string) => layoutIdentity)
      }
    }
  }

  private resolvePanelLayoutIdentity(mode: BrowserBottomPanelHostMode, scene: BrowserRootBottomPanelScene): string {
    return `${mode}:${scene}:${this.layoutRenderKey}`;
  }

  private buildPanelRenderContext(): BrowserBottomPanelRenderContext {
    return {
      responsiveState: this.responsiveState,
      presentationChannel: this.presentationChannel
    };
  }

  private publishLivePresentation(): void {
    this.presentationChannel.publish(this.livePresentation);
  }

  private resolveEffectiveHostHeight(): number {
    return Math.max(1, this.hostHeight);
  }

  private syncModeTransition(): void {
    if (this.mode === this.renderedMode) {
      return;
    }
    const fromMode = this.renderedMode;
    const toMode = this.mode;
    if (this.isVisibleMode(fromMode) && this.isVisibleMode(toMode)) {
      this.previousMode = 'hidden';
      this.renderedMode = toMode;
      this.incomingOpacity = 1;
      this.incomingScale = 1;
      this.incomingOffsetY = 0;
      this.outgoingOpacity = 0;
      this.outgoingScale = 1;
      this.outgoingOffsetY = 0;
      return;
    }
    if (this.isVisibleMode(toMode) &&
      this.tabsOverviewHomeEntryEligible &&
      this.consumeTabsOverviewHomeEntryRequest()) {
      this.renderedMode = toMode;
      this.startTabsOverviewHomeEntryTransition();
      return;
    }
    const version = this.transitionVersion + 1;
    this.transitionVersion = version;
    this.previousMode = fromMode;
    this.renderedMode = toMode;
    this.incomingOpacity = toMode === 'hidden' ? 0 : BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.incomingStartOpacity;
    this.incomingScale = toMode === 'hidden' ? 1 : BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.incomingStartScale;
    this.incomingOffsetY = toMode === 'hidden' ? 0 : BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.incomingStartOffsetY;
    this.outgoingOpacity = fromMode === 'hidden' ? 0 : 1;
    this.outgoingScale = 1;
    this.outgoingOffsetY = 0;
    animateTo({
      duration: BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.durationMs,
      curve: BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.curve
    }, () => {
      this.incomingOpacity = toMode === 'hidden' ? 0 : 1;
      this.incomingScale = 1;
      this.incomingOffsetY = 0;
      this.outgoingOpacity = BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.outgoingEndOpacity;
      this.outgoingScale = BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.outgoingEndScale;
      this.outgoingOffsetY = BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.outgoingEndOffsetY;
    });
    setTimeout(() => {
      if (this.transitionVersion !== version) {
        return;
      }
      this.previousMode = 'hidden';
      this.outgoingOpacity = 0;
      this.outgoingScale = 1;
      this.outgoingOffsetY = 0;
    }, BROWSER_BOTTOM_PANEL_HOST_TRANSITION_SPEC.settleDelayMs);
  }

  private prepareInitialTabsOverviewHomeEntryIfNeeded(): void {
    if (!this.isVisibleMode(this.mode)) {
      return;
    }
    if (!this.tabsOverviewHomeEntryEligible) {
      this.rememberCurrentTabsOverviewHomeEntryRequest();
      return;
    }
    if (!this.consumeTabsOverviewHomeEntryRequest()) {
      return;
    }
    this.startTabsOverviewHomeEntryTransition();
  }

  private syncTabsOverviewHomeEntryRequest(): void {
    if (!this.isVisibleMode(this.mode) || !this.isVisibleMode(this.renderedMode) ||
      !this.tabsOverviewHomeEntryEligible ||
      !this.consumeTabsOverviewHomeEntryRequest()) {
      return;
    }
    this.startTabsOverviewHomeEntryTransition();
  }

  private syncTabsOverviewHomeEntryEligibility(): void {
    if (!this.tabsOverviewHomeEntryEligible ||
      !this.isVisibleMode(this.mode) ||
      !this.isVisibleMode(this.renderedMode) ||
      !this.consumeTabsOverviewHomeEntryRequest()) {
      return;
    }
    this.startTabsOverviewHomeEntryTransition();
  }

  private rememberCurrentTabsOverviewHomeEntryRequest(): void {
    this.handledTabsOverviewHomeEntryRequestVersion = this.resolveTabsOverviewHomeEntryRequestVersion();
  }

  private consumeTabsOverviewHomeEntryRequest(): boolean {
    const requestVersion = this.resolveTabsOverviewHomeEntryRequestVersion();
    if (requestVersion <= 0 || requestVersion === this.handledTabsOverviewHomeEntryRequestVersion) {
      return false;
    }
    this.handledTabsOverviewHomeEntryRequestVersion = requestVersion;
    return true;
  }

  private resolveTabsOverviewHomeEntryRequestVersion(): number {
    return Math.max(0, Math.floor(this.tabsOverviewHomeEntryRequestVersion));
  }

  private startTabsOverviewHomeEntryTransition(): void {
    const version = this.transitionVersion + 1;
    this.transitionVersion = version;
    this.previousMode = 'hidden';
    this.renderedMode = this.mode;
    this.incomingOpacity = BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC.startOpacity;
    this.incomingScale = 1;
    this.incomingOffsetY = this.resolveTabsOverviewHomeEntryStartOffsetY();
    this.outgoingOpacity = 0;
    this.outgoingScale = 1;
    this.outgoingOffsetY = 0;
    setTimeout(() => {
      this.playTabsOverviewHomeEntryTransition(version);
    }, 0);
    setTimeout(() => {
      this.finishTabsOverviewHomeEntryTransition(version);
    }, BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC.settleDelayMs);
  }

  private playTabsOverviewHomeEntryTransition(version: number): void {
    if (this.transitionVersion !== version || !this.isVisibleMode(this.renderedMode)) {
      return;
    }
    animateTo({
      duration: BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC.durationMs,
      curve: BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC.curve,
      onFinish: () => {
        this.finishTabsOverviewHomeEntryTransition(version);
      }
    }, () => {
      if (this.transitionVersion !== version) {
        return;
      }
      this.incomingOpacity = 1;
      this.incomingScale = 1;
      this.incomingOffsetY = 0;
    });
  }

  private finishTabsOverviewHomeEntryTransition(version: number): void {
    if (this.transitionVersion !== version) {
      return;
    }
    this.previousMode = 'hidden';
    this.incomingOpacity = 1;
    this.incomingScale = 1;
    this.incomingOffsetY = 0;
    this.outgoingOpacity = 0;
    this.outgoingScale = 1;
    this.outgoingOffsetY = 0;
  }

  private resolveTabsOverviewHomeEntryStartOffsetY(): number {
    return Math.min(
      Math.max(1, this.resolveEffectiveHostHeight()),
      BROWSER_BOTTOM_PANEL_HOST_TABS_OVERVIEW_HOME_ENTRY_SPEC.startOffsetY
    );
  }

  @Builder
  private emptyPanelBuilder(_context: BrowserBottomPanelRenderContext) {
  }

  private isVisibleMode(mode: BrowserBottomPanelHostMode): boolean {
    return mode !== 'hidden';
  }
}
