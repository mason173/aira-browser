/**
 * Stable placeholder used when the Session reports that the requested Shell
 * adapter is not ready. It avoids silently rendering a different family.
 */
@Component
export struct BrowserShellPresentationUnavailableSurface {
  build() {
    Stack()
      .width('100%')
      .height('100%')
  }
}
