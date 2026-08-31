import { BrowserLargeScreenSidePanelPresentation } from '../../../core/browser/BrowserLargeScreenPresentationViewModel';

/**
 * Structural Side Panel slot for the Large-Screen shell.
 *
 * Width, position, and visibility come from the resolved presentation
 * snapshot. The panel's header/content/actions remain builder-owned so this
 * surface cannot reach bookmark, extension, or Web runtime owners directly.
 */
@Component
export struct BrowserLargeScreenSidePanelSurface {
  @Prop presentation: BrowserLargeScreenSidePanelPresentation;

  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Column({ space: 0 }) {
      this.content()
    }
    .width(this.presentation.widthVp)
    .height('100%')
  }

  @Builder
  private emptyBuilder() {
  }
}
