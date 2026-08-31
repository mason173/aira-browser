export interface BrowserHomeRootBackgroundInput {
  themeBackgroundColor: ResourceColor;
}

export interface BrowserWebRootBackgroundInput {
  showHomePage: boolean;
  webVideoControllerActive: boolean;
  videoBackdropColor: ResourceColor;
  themeHomeBackgroundColor: ResourceColor;
  themeHomeSurfaceBackgroundColor: ResourceColor;
  webPageBackdropColor: string;
}

export class BrowserRootBackgroundViewModel {
  resolveHomeRootBackgroundColor(input: BrowserHomeRootBackgroundInput): ResourceColor {
    return input.themeBackgroundColor;
  }

  resolveWebRootBackgroundColor(input: BrowserWebRootBackgroundInput): ResourceColor {
    if (!input.showHomePage && input.webVideoControllerActive) {
      return input.videoBackdropColor;
    }
    if (input.showHomePage) {
      return input.themeHomeBackgroundColor;
    }
    const pageBackdropColor = input.webPageBackdropColor.trim();
    if (pageBackdropColor.length > 0) {
      return pageBackdropColor;
    }
    return input.themeHomeSurfaceBackgroundColor;
  }
}
