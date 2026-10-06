import { HomeLogoCustomAsset } from './HomeLogoModels';

/**
 * System homepage frame.
 * `classic` is the original home.
 * `search_dock` (搜索导航主页) is the classic home with the search-dock phone chrome instead of the
 * floating capsule. It shares the classic frame; only its toolbar differs.
 * `centered` (简约主页) adds the wordmark and search field, and draws shortcuts smaller and circular.
 * `minimal` (极简主页) keeps that wordmark and search field, and leaves the shortcut grid off.
 * Toolbar chrome follows the frame: classic floats, centered and minimal split, search_dock docks.
 */
export type BrowserHomePageStyle = 'classic' | 'search_dock' | 'centered' | 'minimal';

export function readBrowserHomePageStyle(value: string | undefined): BrowserHomePageStyle | undefined {
  if (value === 'classic') {
    return 'classic';
  }
  if (value === 'search_dock') {
    return 'search_dock';
  }
  if (value === 'centered') {
    return 'centered';
  }
  if (value === 'minimal') {
    return 'minimal';
  }
  return undefined;
}

export function normalizeBrowserHomePageStyle(value: string | undefined): BrowserHomePageStyle {
  return readBrowserHomePageStyle(value) ?? 'classic';
}

/** Wordmark and search field, with the shortcut grid only on `centered`. */
export function usesCenteredHomeFrame(style: BrowserHomePageStyle): boolean {
  return style === 'centered' || style === 'minimal';
}

/**
 * The frame that must be mounted for a style. Each value is a different component, except
 * `search_dock`, which mounts the classic frame and differs only in its toolbar chrome.
 * Centered and minimal share a wordmark, but they are not the same frame.
 */
export function resolveMountedSystemHomeFrame(style: string | undefined): BrowserHomePageStyle {
  return normalizeBrowserHomePageStyle(style);
}

export interface HomePagePresentationSettings {
  showFavoritesTitle: boolean;
  showShortcutNames: boolean;
  showRecentlyClosedTitle: boolean;
  showSettingsButton: boolean;
  /**
   * Built-in homepage frame. Synced with the other core preferences.
   */
  homePageStyle: BrowserHomePageStyle;
  /**
   * Wordmark used by the centered and minimal frames. Custom files stay on this device.
   */
  homeLogoId: string;
  homeLogoCustomAssets: HomeLogoCustomAsset[];
  /**
   * Logo size as a multiple of the shipped wordmark height, so it adapts to the screen instead
   * of pinning one pixel size.
   */
  homeLogoScaleRatio: number;
  /**
   * How solid the centered and minimal wordmark is. 0 hides it without moving the search field.
   */
  homeLogoOpacity: number;
}
