/**
 * System homepage frame. `classic` is the current home. `centered` adds the wordmark and
 * search field, and presents the same shortcuts smaller and circular. Toolbar chrome is not
 * part of this choice.
 */
export type BrowserHomePageStyle = 'classic' | 'centered';

export function normalizeBrowserHomePageStyle(value: string | undefined): BrowserHomePageStyle {
  return value === 'centered' ? 'centered' : 'classic';
}

export interface HomePagePresentationSettings {
  showFavoritesTitle: boolean;
  showShortcutNames: boolean;
  showRecentlyClosedTitle: boolean;
  showSettingsButton: boolean;
  /**
   * Device-local homepage frame. Intentionally excluded from Personalization Sync.
   */
  homePageStyle: BrowserHomePageStyle;
}
