/**
 * Chrome-less primary surface for an installed Web App session.
 *
 * The stable host keeps ownership of Hosted Web slots. This adapter only
 * mounts the supplied Web surface without Phone or Large-Screen browser chrome.
 */
@Component
export struct BrowserWebAppPrimarySurface {
  @BuilderParam webSurface: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Top }) {
      this.webSurface()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private emptyBuilder() {
  }
}
