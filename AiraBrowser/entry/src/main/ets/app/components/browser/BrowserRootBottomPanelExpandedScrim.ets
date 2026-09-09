import {
  BrowserSearchBackdropPresentation,
  BrowserSearchBackdropPresentationChannel,
  BrowserSearchBackdropPresentationListener
} from '../../../core/browser/BrowserSearchBackdropPresentationChannel';

@Component
export struct BrowserRootBottomPanelExpandedScrim {
  @State private liveScrimOpacity: number = 0;
  @State private surfaceSuppressed: boolean = false;
  private activePresentationRunId: number = 0;
  private disconnectPresentation: () => boolean = (): boolean => false;
  private presentationListener: BrowserSearchBackdropPresentationListener =
    (presentation: BrowserSearchBackdropPresentation): void => {
      this.applyPresentation(presentation);
    };
  @Prop scrimOpacity: number = 0;
  @Prop blockHitTest: boolean = false;
  @Prop surfaceEligible: boolean = true;
  @Prop settledVisible: boolean = false;
  presentationChannel?: BrowserSearchBackdropPresentationChannel = undefined;
  onDismiss: () => void = () => {};

  aboutToAppear(): void {
    if (this.presentationChannel === undefined) {
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(this.scrimOpacity);
      return;
    }
    this.disconnectPresentation = this.presentationChannel.connect(this.presentationListener);
  }

  aboutToDisappear(): void {
    this.disconnectPresentation();
    this.disconnectPresentation = (): boolean => false;
  }

  build() {
    Stack() {
      if (this.shouldMountScrimSurface()) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.start_window_background'))
          .opacity(this.resolveEffectiveScrimOpacity())
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.shouldBlockHitTest() ? '100%' : 0)
    .height(this.shouldBlockHitTest() ? '100%' : 0)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .hitTestBehavior(this.shouldBlockHitTest() ? HitTestMode.BLOCK_HIERARCHY : HitTestMode.None)
    .onClick(() => {
      this.onDismiss();
    })
  }

  private applyPresentation(presentation: BrowserSearchBackdropPresentation): void {
    this.activePresentationRunId = presentation.runId;
    this.surfaceSuppressed = presentation.surfaceSuppressed;
    if (presentation.durationMs <= 0) {
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(presentation.progress);
      this.presentationChannel?.finishPresentation(presentation.runId);
      return;
    }
    animateTo({
      duration: presentation.durationMs,
      curve: presentation.curve,
      onFinish: () => {
        if (this.activePresentationRunId !== presentation.runId) {
          return;
        }
        this.presentationChannel?.finishPresentation(presentation.runId);
      }
    }, () => {
      if (this.activePresentationRunId !== presentation.runId) {
        return;
      }
      this.liveScrimOpacity = this.resolveClampedScrimOpacity(presentation.progress);
    });
  }

  private shouldMountScrimSurface(): boolean {
    return !this.surfaceSuppressed && this.surfaceEligible &&
      (this.settledVisible || this.resolveEffectiveScrimOpacity() > 0.01);
  }

  private shouldBlockHitTest(): boolean {
    if (this.surfaceSuppressed || !this.surfaceEligible) {
      return false;
    }
    if (this.settledVisible || this.resolveEffectiveScrimOpacity() > 0.01) {
      return true;
    }
    // The connected channel is the live animation source; parent props can lag behind its completed transition.
    return this.presentationChannel === undefined && this.blockHitTest;
  }

  private resolveEffectiveScrimOpacity(): number {
    if (this.surfaceSuppressed || !this.surfaceEligible) {
      return 0;
    }
    if (this.presentationChannel === undefined) {
      return this.resolveClampedScrimOpacity(this.scrimOpacity);
    }
    return this.resolveClampedScrimOpacity(this.liveScrimOpacity);
  }

  private resolveClampedScrimOpacity(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }
}
