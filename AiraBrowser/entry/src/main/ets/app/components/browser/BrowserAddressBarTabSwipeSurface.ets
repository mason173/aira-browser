import { image } from '@kit.ImageKit';
import {
  BrowserAddressBarTabSwipeState,
  createIdleAddressBarTabSwipeState
} from '../../../core/browser/BrowserAddressBarTabSwipeCoordinator';
import { BrowserTabPreviewState } from '../../../core/browser/BrowserTabPreviewCoordinator';

/** A temporary neighbor cover; the live Web stays mounted in its original content slot. */
@Component
export struct BrowserAddressBarTabSwipeSurface {
  @Prop state: BrowserAddressBarTabSwipeState = createIdleAddressBarTabSwipeState();
  // @Prop deep-copies objects and loses PixelMap's native backing. Share the leased image;
  // the shell remains its only writer and the cover coordinator owns its lifetime.
  @Link preview: BrowserTabPreviewState | undefined;
  @Prop surfaceColor: ResourceColor = Color.White;
  @Prop textColor: ResourceColor = Color.Black;
  /** Window offset where the captured web page starts. */
  @Prop topInset: number = 0;
  /** Privacy blur carried over from the tab management thumbnail. */
  @Prop previewBlurRadius: number = 0;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Stack({ alignContent: Alignment.TopStart }) {
        this.content()
      }
      .width('100%')
      .height('100%')
      .borderRadius(this.resolveRadius())
      .clip(true)
      .translate({ x: this.resolveLiveOffset() })
      .hitTestBehavior(this.state.stage === 'idle' ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)

      if (this.state.stage !== 'idle' && this.state.targetTabId.length > 0) {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.preview === undefined) {
            // Only a tab with no stored thumbnail at all falls back to the identity. Keeping this
            // layer out of the image case removes the title that flashed for a frame or two while
            // the cover image was still being decoded.
            this.buildPreviewIdentity()
          } else {
            // Render one leased source for the entire gesture; asynchronous thumbnail updates must
            // not swap image nodes or paint a second, not-yet-ready image over this cover.
            if (this.preview.sharedSnapshotPixelMap !== undefined) {
              this.buildPreviewImage()
            } else if (this.previewUri().length > 0) {
              this.buildPreviewImage()
            }
          }
          if (this.state.loadingPlaceholder) {
            Row({ space: 8 }) {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(this.textColor)
              Text('正在恢复页面…')
                .fontSize(14)
                .fontColor(this.textColor)
            }
            .padding(12)
            .backgroundColor(this.surfaceColor)
            .borderRadius(12)
            .position({ x: 16, y: 16 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.surfaceColor)
        .borderRadius(this.resolveRadius())
        .clip(true)
        .translate({ x: this.resolvePreviewOffset() })
        .opacity(this.resolvePreviewOpacity())
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no-hide-descendants')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.surfaceColor)
    .clip(true)
  }

  private resolveLiveOffset(): number {
    return this.state.stage === 'handoff' || this.state.reduceMotion ? 0 : this.state.offsetX;
  }

  private resolvePreviewOffset(): number {
    return this.state.reduceMotion ? 0 :
      this.state.offsetX - this.state.direction * (this.state.width + 12);
  }

  private resolvePreviewOpacity(): number {
    return this.state.reduceMotion ? this.state.previewOpacity *
      Math.min(1, Math.abs(this.state.offsetX) / this.state.width) : this.state.previewOpacity;
  }

  private resolveRadius(): number {
    if (this.state.stage === 'idle' || this.state.stage === 'handoff' || this.state.reduceMotion) {
      return 0;
    }
    const progress = Math.min(1, Math.abs(this.state.offsetX) / (this.state.width + 12));
    return 16 * Math.min(1, progress * 8, (1 - progress) * 8);
  }

  @Builder
  private buildPreviewImage() {
    // syncLoad keeps a file-backed thumbnail from being drawn one or more frames late, which is
    // exactly the window a swipe shows it in.
    if (this.usesPageFrame()) {
      // A web page capture holds page pixels only, so it starts below the top chrome.
      Image(this.resolvePreviewImageSource())
        .width('100%')
        .height(this.resolvePagePreviewHeight())
        .objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.Medium)
        .syncLoad(true)
        .blur(this.previewBlurRadius)
        .position({ x: 0, y: this.topInset })
    } else {
      // A shell screenshot was taken from this same window box, so filling the surface aligns it
      // with the screen and the live floating chrome covers the captured toolbar.
      Image(this.resolvePreviewImageSource())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.Medium)
        .syncLoad(true)
        .blur(this.previewBlurRadius)
        .position({ x: 0, y: 0 })
    }
  }

  private resolvePreviewImageSource(): string | image.PixelMap {
    // Read state inside the Image update scope. A by-value Builder argument would keep the
    // first neighbor's pixels when the gesture reverses without recreating the image branch.
    return this.preview?.sharedSnapshotPixelMap ?? this.previewUri();
  }

  private usesPageFrame(): boolean {
    return this.preview?.transitionSource?.captureScope === 'web-content';
  }

  private resolvePagePreviewHeight(): Length {
    const width = this.preview?.sharedSnapshotImageWidth ?? 0;
    const height = this.preview?.sharedSnapshotImageHeight ?? 0;
    return width > 0 && height > 0 ? this.state.width * height / width : '100%';
  }

  private previewUri(): string {
    return (this.preview?.sharedSnapshotImageUri ?? '').trim();
  }

  @Builder
  private buildPreviewIdentity() {
    Column({ space: 16 }) {
      if (this.state.loadingPlaceholder) {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(this.textColor)
      } else if (this.preview?.favicon !== undefined) {
        Image(this.preview.favicon as image.PixelMap)
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
      }
      Text(this.state.targetTitle || this.state.targetAddress)
        .fontSize(18)
        .fontColor(this.textColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.state.targetAddress)
        .fontSize(13)
        .fontColor(this.textColor)
        .opacity(0.6)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private emptyContent() {}
}
