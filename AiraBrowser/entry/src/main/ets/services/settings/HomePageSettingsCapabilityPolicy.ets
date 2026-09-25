import { BrowserHomePageStyle } from '../../common/models/HomePagePresentationSettingsModels';
import { HomePageRecoveryEntry } from './HomePageRecoveryEntryPolicyService';

/**
 * Which homepage-settings controls a frame actually honors.
 *
 * Classic owns the full sheet. Centered keeps only controls that change that frame:
 * wallpaper, favorites visibility, icon names, and icon size. Compact layout, section titles,
 * icon radius, recently closed, system search, and the settings button are classic-only.
 *
 * The centered frame does not offer a toggleable settings entry: it pins an undeletable
 * `主页设置` tile into the favorites grid, so `settingsButton` is false there.
 */
export interface HomePageSettingsCapabilities {
  wallpaper: boolean;
  favorites: boolean;
  compactFavorites: boolean;
  favoritesTitle: boolean;
  shortcutNames: boolean;
  iconSize: boolean;
  iconCornerRadius: boolean;
  recentlyClosed: boolean;
  systemSearch: boolean;
  settingsButton: boolean;
}

export function resolveHomePageSettingsCapabilities(
  style: BrowserHomePageStyle
): HomePageSettingsCapabilities {
  if (style === 'centered') {
    return {
      wallpaper: true,
      favorites: true,
      compactFavorites: false,
      favoritesTitle: false,
      shortcutNames: true,
      iconSize: true,
      iconCornerRadius: false,
      recentlyClosed: false,
      systemSearch: false,
      settingsButton: false
    };
  }
  return {
    wallpaper: true,
    favorites: true,
    compactFavorites: true,
    favoritesTitle: true,
    shortcutNames: true,
    iconSize: true,
    iconCornerRadius: true,
    recentlyClosed: true,
    systemSearch: true,
    settingsButton: true
  };
}

/**
 * Entries that can still open homepage settings on the active frame.
 *
 * The classic frame must keep at least one of favorites, recently closed, or its settings button.
 * The centered frame pins an undeletable `主页设置` tile into the grid, so a visible entry always
 * exists and no stored flag has to be kept or repaired on that frame.
 */
export function resolveHomePageRecoveryEntries(style: BrowserHomePageStyle): HomePageRecoveryEntry[] {
  if (style === 'centered') {
    return [];
  }
  return ['favorites', 'recently_closed', 'settings_button'];
}

export function resolveHomePageSettingsRecoveryFooter(style: BrowserHomePageStyle): string {
  if (style === 'centered') {
    return '主页设置入口固定显示，不可移除。';
  }
  return '收藏、最近关闭和主页设置按钮至少保留一项。';
}
