import { BrowserThemePaletteId } from '../../common/models/BrowserModels';

export interface BrowserThemeTokenSet {
  accent: string;
  onAccent: string;
  onPrimary: string;
  settingsIconForeground: string;
  settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet;
  syncProviderIconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet;
  activityHeatmap: BrowserActivityHeatmapTokenSet;
  pageBackground: string;
  surfaceBackground: string;
  floatingSurface: string;
  controlBackground: string;
  pressedBackground: string;
  divider: string;
  outline: string;
  textPrimary: string;
  textSecondary: string;
}

export interface BrowserSettingsIconBackgroundTokenSet {
  general: string;
  search: string;
  privacySecurity: string;
  siteSettings: string;
  adBlocker: string;
  userScripts: string;
  siteCustomization: string;
  webpageTranslation: string;
  passwords: string;
  downloads: string;
  userAgent: string;
  appearance: string;
  experiments: string;
  sync: string;
  about: string;
}

export interface BrowserSyncProviderIconBackgroundTokenSet {
  cloud: string;
  webdav: string;
}

export interface BrowserActivityHeatmapTokenSet {
  empty: string;
  level1: string;
  level2: string;
  level3: string;
  level4: string;
  todayBorder: string;
}

export const DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS: BrowserActivityHeatmapTokenSet = {
  empty: '#EEF4F1',
  level1: '#B9DDC7',
  level2: '#73B995',
  level3: '#338767',
  level4: '#176148',
  todayBorder: '#176148'
};

export const DEFAULT_DARK_BROWSER_ACTIVITY_HEATMAP_TOKENS: BrowserActivityHeatmapTokenSet = {
  empty: '#1D2826',
  level1: '#244A3C',
  level2: '#317254',
  level3: '#49A074',
  level4: '#78D6A3',
  todayBorder: '#78D6A3'
};

export const DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS: BrowserSettingsIconBackgroundTokenSet = {
  general: '#2F45EA',
  search: '#3378E8',
  privacySecurity: '#6857F6',
  siteSettings: '#258A8A',
  adBlocker: '#C44E77',
  userScripts: '#7357D9',
  siteCustomization: '#5B74E8',
  webpageTranslation: '#A77A12',
  passwords: '#2B8D68',
  downloads: '#2569D8',
  userAgent: '#637494',
  appearance: '#8F7A18',
  experiments: '#9C55D7',
  sync: '#3A5DFF',
  about: '#56637D'
};

export const DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS: BrowserSyncProviderIconBackgroundTokenSet = {
  cloud: '#2F45EA',
  webdav: '#7758D8'
};

export interface BrowserThemePalette {
  id: BrowserThemePaletteId;
  title: string;
  subtitle: string;
  previewColor: string;
  light: BrowserThemeTokenSet;
  dark: BrowserThemeTokenSet;
}
