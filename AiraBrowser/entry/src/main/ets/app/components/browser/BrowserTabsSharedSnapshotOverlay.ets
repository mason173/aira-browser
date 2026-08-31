import { image } from '@kit.ImageKit';
import { BrowserTabsOverlayAnimationViewModel } from '../../../core/browser/BrowserTabsOverlayAnimationViewModel';
import { BrowserTabsOverlayRect } from '../../../core/browser/BrowserTabsOverlayViewModel';
import {
  BrowserTabsSharedSnapshotTransitionCoordinator,
  BrowserTabsSharedSnapshotEntryOverlayPresentationState,
  BrowserTabsSharedSnapshotTransitionState
} from '../../../core/browser/BrowserTabsSharedSnapshotTransitionCoordinator';
import {
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const SNAPSHOT_DECORATION_REVEAL_MOUNT_DELAY_MS: number = 72;

@Component
export struct BrowserTabsSharedSnapshotOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @Watch('syncOverlayState')
  @Prop state: BrowserTabsSharedSnapshotTransitionState =
    new BrowserTabsSharedSnapshotTransitionCoordinator().buildIdleState();
  @Prop snapshotBackgroundColor: ResourceColor | undefined = undefined;
  @Prop snapshotLayerZIndex: number = -1;
  @Prop snapshotDecorationLayerZIndex: number = -1;
  @Prop viewportLeft: number = 0;
  @Prop viewportTop: number = 0;

  @State decorationRevealOpacity: number = 0;
  @State private renderSnapshotImageUri: string = '';
  @State private renderSnapshotPixelMap: image.PixelMap | undefined = undefined;
  @State private renderSnapshotImageRevision: number = 0;

  private coordinator: BrowserTabsSharedSnapshotTransitionCoordinator =
    new BrowserTabsSharedSnapshotTransitionCoordinator();
  private animationViewModel: BrowserTabsOverlayAnimationViewModel = new BrowserTabsOverlayAnimationViewModel();
  private decorationRevealKey: string = '';
  private decorationRevealVersion: number = 0;
  private imageKey: string = '';

  onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => void = (_rect: BrowserTabsOverlayRect) => {};
  onSnapshotTap: (tabId: string) => void = (_tabId: string) => {};

  aboutToAppear(): void {
    this.syncOverlayState();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.coordinator.shouldShowOverlay(this.state)) {
          this.buildImage()
        }
      }
      .width(this.frameWidth())
      .height(this.frameHeight())
      .position({
        x: this.frameLeft(),
        y: this.frameTop()
      })
      .backgroundColor(this.resolveBackgroundColor())
      .borderRadius(this.cornerRadius())
      .clip(this.shouldClipOverlayFrame())
      .opacity(this.overlayOpacity())
      .visibility(this.coordinator.shouldShowOverlay(this.state) ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(HitTestMode.None)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.onSnapshotRectChange(this.buildLocalSnapshotRect(newArea));
      })
      .onClick(() => {
        this.onSnapshotTap(this.state.tabId);
      })
      .zIndex(this.resolveSnapshotLayerZIndex())

      if (this.shouldShowDecoration()) {
        this.buildDecoration()
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .zIndex(this.resolveSnapshotDecorationLayerZIndex())
  }

  @Builder
  private buildImage() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Mirror the gallery card's preference order (uri first, pixel map fallback)
      // so the morph shows the exact image the card renders. A late/blank session
      // capture must never win over the known-good shared-snapshot uri.
      if (this.resolveRenderableImageUri().length > 0) {
        this.buildUriImage()
      } else if (this.resolveRenderablePixelMap() !== undefined) {
        this.buildPixelMapImage()
      }
    }
    .width(this.frameWidth())
    .height(this.imageClipHeight())
    .clip(this.shouldClipImageToFrame())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildUriImage() {
    Image(this.resolveRenderableImageUri())
      .width(Math.max(1, this.resolvePresentationState().imageFrame.width))
      .height(Math.max(1, this.resolvePresentationState().imageFrame.height))
      .position({
        x: this.resolvePresentationState().imageFrame.left,
        y: this.resolvePresentationState().imageFrame.top
      })
      .objectFit(ImageFit.Fill)
      .syncLoad(true)
      .interpolation(ImageInterpolation.Medium)
      .blur(this.imageBlurRadius())
  }

  @Builder
  private buildPixelMapImage() {
    Image(this.resolveRenderablePixelMap() as image.PixelMap)
      .width(Math.max(1, this.resolvePresentationState().imageFrame.width))
      .height(Math.max(1, this.resolvePresentationState().imageFrame.height))
      .position({
        x: this.resolvePresentationState().imageFrame.left,
        y: this.resolvePresentationState().imageFrame.top
      })
      .objectFit(ImageFit.Fill)
      .syncLoad(true)
      .interpolation(ImageInterpolation.Medium)
      .blur(this.imageBlurRadius())
  }

  private resolvePresentationState(): BrowserTabsSharedSnapshotEntryOverlayPresentationState {
    return this.coordinator.buildEntryOverlayPresentationState(this.state);
  }

  private resolveRenderableImageUri(): string {
    return this.renderSnapshotImageUri.trim();
  }

  private resolveRenderablePixelMap(): image.PixelMap | undefined {
    return this.renderSnapshotPixelMap ?? this.state.imagePixelMap;
  }

  private syncOverlayState(): void {
    this.syncImageRenderState();
    this.syncDecorationRevealState();
  }

  private syncImageRenderState(): void {
    const nextImageUri = this.state.imageUri.trim();
    const nextImageRevision = Math.max(0, Math.floor(this.state.imageRevision ?? 0));
    const hasPixelMap = this.state.imagePixelMap !== undefined ? 'pixelmap' : 'none';
    const nextKey = `${this.state.direction}:${this.state.tabId}:${nextImageUri}:${nextImageRevision}:${hasPixelMap}`;
    if (this.imageKey === nextKey &&
      this.renderSnapshotImageUri === nextImageUri &&
      this.renderSnapshotPixelMap === this.state.imagePixelMap &&
      this.renderSnapshotImageRevision === nextImageRevision) {
      return;
    }
    this.imageKey = nextKey;
    this.renderSnapshotImageUri = nextImageUri;
    this.renderSnapshotPixelMap = this.state.imagePixelMap;
    this.renderSnapshotImageRevision = nextImageRevision;
  }

  @Builder
  private buildDecoration() {
    Stack()
    .width(this.decorationWidth())
    .height(this.decorationHeight())
    .position({
      x: this.decorationLeft(),
      y: this.decorationTop()
    })
    .opacity(this.decorationRevealOpacity)
    .hitTestBehavior(HitTestMode.None)
    .zIndex(this.resolveSnapshotDecorationLayerZIndex())
  }

  private resolveSnapshotLayerZIndex(): number {
    return this.snapshotLayerZIndex >= 0 ?
      this.snapshotLayerZIndex : this.coordinator.resolveLayerPolicy().snapshotZIndex;
  }

  private resolveSnapshotDecorationLayerZIndex(): number {
    return this.snapshotDecorationLayerZIndex >= 0 ?
      this.snapshotDecorationLayerZIndex : this.coordinator.resolveLayerPolicy().snapshotDecorationZIndex;
  }

  private buildLocalSnapshotRect(area: Area): BrowserTabsOverlayRect {
    return {
      left: this.parseAreaPosition(area.globalPosition.x) - this.viewportLeft,
      top: this.parseAreaPosition(area.globalPosition.y) - this.viewportTop,
      width: this.parseAreaDimension(area.width),
      height: this.parseAreaDimension(area.height)
    };
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`.replace('vp', '').replace('px', ''));
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseAreaPosition(value?: Length): number {
    return value === undefined ? 0 : this.parseAreaDimension(value);
  }

  private frameLeft(): number {
    return this.resolvePresentationState().frame.left;
  }

  private frameTop(): number {
    return this.resolvePresentationState().frame.top;
  }

  private frameWidth(): number {
    return Math.max(1, this.resolvePresentationState().frame.width);
  }

  private frameHeight(): number {
    return Math.max(1, this.resolvePresentationState().frame.height);
  }

  private imageClipHeight(): number {
    return this.resolvePresentationState().imageClipHeight;
  }

  private shouldClipOverlayFrame(): boolean {
    return this.resolvePresentationState().clipImageToFrame;
  }

  private shouldClipImageToFrame(): boolean {
    return this.resolvePresentationState().clipImageToFrame;
  }

  private cornerRadius(): number {
    return this.resolvePresentationState().cornerRadius;
  }

  private overlayOpacity(): number {
    if (!this.coordinator.shouldShowOverlay(this.state)) {
      return 0;
    }
    return 1;
  }

  private imageBlurRadius(): number {
    return this.resolvePresentationState().imageBlurRadius;
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.state.direction === 'exit') {
      return $r('sys.color.ohos_id_color_background_transparent');
    }
    return this.snapshotBackgroundColor === undefined ? this.storedSurfaceBackgroundColor : this.snapshotBackgroundColor;
  }

  private syncDecorationRevealState(): void {
    if (!this.coordinator.shouldShowOverlay(this.state)) {
      this.decorationRevealVersion += 1;
      this.decorationRevealKey = '';
      this.decorationRevealOpacity = 0;
      return;
    }
    const key = `${this.state.direction}:${this.state.tabId}`;
    if (this.decorationRevealKey === key) {
      return;
    }
    this.decorationRevealKey = key;
    this.decorationRevealVersion += 1;
    const version = this.decorationRevealVersion;
    if (this.state.direction === 'exit') {
      this.decorationRevealOpacity = 0;
      return;
    }
    this.decorationRevealOpacity = 0;
    setTimeout(() => {
      if (!this.isCurrentDecorationReveal(version, 'enter')) {
        return;
      }
      animateTo({
        duration: this.animationViewModel.getSharedSnapshotEnterHandoffDelayMs(),
        curve: Curve.EaseOut
      }, () => {
        if (!this.isCurrentDecorationReveal(version, 'enter')) {
          return;
        }
        this.decorationRevealOpacity = 1;
      });
    }, this.animationViewModel.getSharedSnapshotEnterDurationMs() + SNAPSHOT_DECORATION_REVEAL_MOUNT_DELAY_MS);
  }

  private isCurrentDecorationReveal(version: number, direction: string): boolean {
    return this.decorationRevealVersion === version &&
      this.state.direction === direction &&
      this.coordinator.shouldShowOverlay(this.state);
  }

  private shouldShowDecoration(): boolean {
    return this.coordinator.shouldShowOverlay(this.state);
  }

  private decorationLeft(): number {
    return this.state.targetRect.left;
  }

  private decorationTop(): number {
    return this.state.targetRect.top;
  }

  private decorationWidth(): number {
    return Math.max(1, this.state.targetRect.width);
  }

  private decorationHeight(): number {
    return Math.max(1, this.state.targetRect.height);
  }
}
