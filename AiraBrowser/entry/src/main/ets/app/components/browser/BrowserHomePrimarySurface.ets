import {
  BrowserHomePagePresentationState
} from '../../../core/browser/BrowserHomePresentationViewModel';
import {
  HOME_CONTENT_SNAPSHOT_ID,
  HOME_SURFACE_SNAPSHOT_ID
} from './BrowserShellPresentationTokens';

/**
 * Presentation owner for the native Home surface frame.
 *
 * The page supplies live Home content while this component owns the visual
 * transforms, hit testing, background, and snapshot boundaries.
 */
@Component
export struct BrowserHomePrimarySurface {
  @Prop presentation: BrowserHomePagePresentationState;
  @Prop surfaceBackgroundColor: ResourceColor;
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Stack({ alignContent: Alignment.Top }) {
        Stack({ alignContent: Alignment.Top }) {
          this.content()
        }
        .width('100%')
        .height('100%')
        .id(HOME_CONTENT_SNAPSHOT_ID)
      }
      .width('100%')
      .height('100%')
      .id(HOME_SURFACE_SNAPSHOT_ID)
      .backgroundColor(this.surfaceBackgroundColor)
      .scale({
        x: this.presentation.scale,
        y: this.presentation.scale,
        centerX: '50%',
        centerY: '50%'
      })
      .opacity(1)
      .hitTestBehavior(HitTestMode.Default)
      .zIndex(0)
    }
    .width('100%')
    .height('100%')
    .scale({
      x: this.presentation.searchBackdropScale,
      y: this.presentation.searchBackdropScale,
      centerX: '50%',
      centerY: '50%'
    })
    .blur(0)
    .opacity(this.presentation.opacity)
    .hitTestBehavior(this.presentation.hitTestEnabled ? HitTestMode.Default : HitTestMode.None)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
  }

  @Builder
  private emptyBuilder() {
  }
}
