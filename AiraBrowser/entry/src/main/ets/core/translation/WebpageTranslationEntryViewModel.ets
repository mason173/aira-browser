export interface WebpageTranslationEntrySurfaceInput {
  activeTabIsWebPage: boolean;
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  targetUrls?: string[];
}

export class WebpageTranslationEntryViewModel {
  canShowToolbarEntry(input: WebpageTranslationEntrySurfaceInput): boolean {
    return this.canShowPromptSurface(input);
  }

  canShowPromptSurface(input: WebpageTranslationEntrySurfaceInput): boolean {
    return (input.activeTabIsWebPage || input.webPageVisible || this.hasNetworkTargetUrl(input.targetUrls ?? [])) &&
      !input.tabsSheetVisible;
  }

  private hasNetworkTargetUrl(urls: string[]): boolean {
    for (let index = 0; index < urls.length; index += 1) {
      const lower = urls[index].trim().toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return true;
      }
    }
    return false;
  }
}
