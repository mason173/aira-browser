import {
  BrowserAppearanceSettings,
  DesktopBookmarkBarVisibility,
  normalizeDesktopBookmarkBarVisibility
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

/**
 * The three-state policy's wording and order, defined once: the bookmark bar's own context menu and
 * the Large-Screen setting both offer these choices, so a wording change stays a single edit.
 */
export interface DesktopBookmarkBarVisibilityChoice {
  visibility: DesktopBookmarkBarVisibility;
  label: string;
}

export const DESKTOP_BOOKMARK_BAR_VISIBILITY_CHOICES: DesktopBookmarkBarVisibilityChoice[] = [
  { visibility: 'never', label: '一律隐藏' },
  { visibility: 'always', label: '一律显示' },
  { visibility: 'new_tab_only', label: '仅在“新标签页”页面上显示' }
];

/**
 * Resolves the three-state bookmark bar policy. Installs that only stored the legacy two-state
 * switch are migrated on read: a hidden bar means "never", a shown bar means "always".
 */
export function resolveDesktopBookmarkBarVisibility(
  settings: BrowserAppearanceSettings
): DesktopBookmarkBarVisibility {
  return normalizeDesktopBookmarkBarVisibility(
    settings.desktopBookmarkBarVisibility,
    settings.showDesktopBookmarkBar === false ? 'never' : 'always'
  );
}

/** Whether the bar is enabled anywhere; the "new tab page only" state still counts as visible. */
export function isDesktopBookmarkBarVisible(settings: BrowserAppearanceSettings): boolean {
  return resolveDesktopBookmarkBarVisibility(settings) !== 'never';
}

/**
 * Whether the bar is painted for the page that is currently on screen. Only the
 * "new tab page only" state needs to know which surface the active tab shows.
 */
export function isDesktopBookmarkBarPainted(
  visibility: DesktopBookmarkBarVisibility | string | undefined,
  newTabPageActive: boolean
): boolean {
  const normalized = normalizeDesktopBookmarkBarVisibility(visibility);
  if (normalized === 'never') {
    return false;
  }
  return normalized === 'new_tab_only' ? newTabPageActive : true;
}

/**
 * Applies a policy change and keeps the legacy two-state projection in step so the settings
 * switch and Personalization Sync keep carrying a value they already understand.
 */
export function buildDesktopBookmarkBarVisibilitySettings(
  current: BrowserAppearanceSettings,
  visibility: DesktopBookmarkBarVisibility
): BrowserAppearanceSettings {
  return {
    bottomToolbarScrollBehavior: current.bottomToolbarScrollBehavior,
    toolbarChromeStyle: current.toolbarChromeStyle,
    globalImmersionEnabled: current.globalImmersionEnabled,
    alwaysTopImmersionEnabled: current.alwaysTopImmersionEnabled,
    forceDarkWebContentEnabled: current.forceDarkWebContentEnabled,
    blurPrivateTabPreviews: current.blurPrivateTabPreviews,
    showHomeRecentlyClosed: current.showHomeRecentlyClosed,
    showHomeShortcuts: current.showHomeShortcuts,
    homeRecentlyClosedLimit: current.homeRecentlyClosedLimit,
    homeShortcutLayoutDensity: current.homeShortcutLayoutDensity,
    homeShortcutIconSizeRatio: current.homeShortcutIconSizeRatio,
    siteIconCornerRadiusRatio: current.siteIconCornerRadiusRatio,
    themePaletteId: current.themePaletteId,
    tabsOverviewLayoutStyle: current.tabsOverviewLayoutStyle,
    tabsOverviewCloseButtonAlwaysVisible: current.tabsOverviewCloseButtonAlwaysVisible,
    showDesktopBookmarkBar: visibility !== 'never',
    desktopBookmarkBarVisibility: visibility,
    verticalTabsEnabled: current.verticalTabsEnabled,
    verticalTabsCollapsed: current.verticalTabsCollapsed,
    verticalTabsDoubleClickCloseEnabled: current.verticalTabsDoubleClickCloseEnabled
  };
}

export function buildToggledDesktopBookmarkBarSettings(
  current: BrowserAppearanceSettings
): BrowserAppearanceSettings {
  return buildDesktopBookmarkBarVisibilitySettings(
    current,
    isDesktopBookmarkBarVisible(current) ? 'never' : 'always'
  );
}

export async function setDesktopBookmarkBarVisibility(
  repository: PreferencesRepository,
  visibility: DesktopBookmarkBarVisibility
): Promise<DesktopBookmarkBarVisibility> {
  const next = buildDesktopBookmarkBarVisibilitySettings(repository.getPreferences().appearance, visibility);
  await repository.updateAppearanceSettings(next);
  return visibility;
}

export async function toggleDesktopBookmarkBarVisibility(
  repository: PreferencesRepository
): Promise<boolean> {
  const next = buildToggledDesktopBookmarkBarSettings(repository.getPreferences().appearance);
  await repository.updateAppearanceSettings(next);
  return isDesktopBookmarkBarVisible(next);
}
