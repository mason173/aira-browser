import { BrowserHomePageStyle } from '../../common/models/HomePagePresentationSettingsModels';

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
  { style: 'classic', title: '默认主页' },
  { style: 'centered', title: '居中主页' }
];

/**
 * Packaged card preview for a built-in frame. Both assets are transparent wireframes
 * sharing one neutral palette, so they read on light and dark surfaces alike.
 */
export function resolveSystemHomepagePreviewResource(style: BrowserHomePageStyle): Resource {
  if (style === 'centered') {
    return $rawfile('home_preview_centered.svg');
  }
  return $rawfile('home_preview_classic.svg');
}
