import {
  BrowserHomePageStyle,
  usesCenteredHomeFrame
} from '../../common/models/HomePagePresentationSettingsModels';
import { BrowserToolbarChromeStyle } from '../../common/models/BrowserModels';

/**
 * Built-in homepage frames offered on the 自定义主页 page.
 *
 * These are catalog entries, not installed records. They never enter
 * `CustomHomepageSettings.items`, so import, export, delete, preview capture, site-icon
 * hydration, and Personalization Sync never see them. Adding another built-in frame is a
 * new entry here plus its rendering frame.
 */
export interface SystemHomepageStyleEntry {
  style: BrowserHomePageStyle;
  title: string;
}

export const SYSTEM_HOMEPAGE_STYLE_CATALOG: SystemHomepageStyleEntry[] = [
  { style: 'classic', title: '经典主页' },
  { style: 'search_dock', title: '搜索导航主页' },
  { style: 'centered', title: '简约主页' },
  { style: 'minimal', title: '极简主页' }
];

/**
 * Packaged card preview for a built-in frame. The assets are transparent wireframes
 * sharing one neutral palette, so they read on light and dark surfaces alike.
 */
export function resolveSystemHomepagePreviewResource(style: BrowserHomePageStyle): Resource {
  if (style === 'minimal') {
    return $rawfile('home_preview_minimal.svg');
  }
  if (style === 'centered') {
    return $rawfile('home_preview_centered.svg');
  }
  if (style === 'search_dock') {
    return $rawfile('home_preview_search_dock.svg');
  }
  return $rawfile('home_preview_classic.svg');
}

/**
 * Built-in frames ship with a matching toolbar. Classic keeps the floating capsule. Centered and
 * minimal use the split top search and bottom navigation. Search dock keeps the classic home but
 * docks the search box above a fixed bottom navigation row.
 */
export function resolveSystemHomepageToolbarChrome(style: BrowserHomePageStyle): BrowserToolbarChromeStyle {
  if (style === 'search_dock') {
    return 'dock';
  }
  return usesCenteredHomeFrame(style) ? 'split' : 'floating';
}
