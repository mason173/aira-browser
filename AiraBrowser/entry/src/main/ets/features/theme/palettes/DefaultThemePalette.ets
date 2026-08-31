import {
  BrowserThemePalette,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS
} from '../BrowserThemePaletteModels';
import { buildActivityHeatmapTokens } from './ThemePaletteTokenBuilder';

export const DEFAULT_THEME_PALETTE: BrowserThemePalette = {
  id: 'default',
  title: '清风',
  subtitle: '蓝色主调，中性灰阶',
  previewColor: '#0A59F7',
  light: {
    accent: '#0A59F7',
    onAccent: '#FFFFFF',
    onPrimary: '#FFFFFF',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
    syncProviderIconBackgrounds: DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS,
    activityHeatmap: buildActivityHeatmapTokens('#0A59F7', 'light'),
    pageBackground: '#F2F3F5',
    surfaceBackground: '#FFFFFF',
    floatingSurface: '#FFFFFF',
    controlBackground: '#ECEDEF',
    pressedBackground: '#14000000',
    divider: '#1F000000',
    outline: '#26000000',
    textPrimary: '#111318',
    textSecondary: '#5F6368'
  },
  dark: {
    accent: '#7EA7FF',
    onAccent: '#0B0D12',
    onPrimary: '#0B0D12',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS,
    syncProviderIconBackgrounds: DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS,
    activityHeatmap: buildActivityHeatmapTokens('#7EA7FF', 'dark'),
    pageBackground: '#101010',
    surfaceBackground: '#1C1C1E',
    floatingSurface: '#242426',
    controlBackground: '#2C2C2E',
    pressedBackground: '#33FFFFFF',
    divider: '#26FFFFFF',
    outline: '#33FFFFFF',
    textPrimary: '#F4F4F5',
    textSecondary: '#B8B8BD'
  }
};

export const AIRA_CLASSIC_THEME_PALETTE: BrowserThemePalette = {
  id: 'aira_classic',
  title: '晨光',
  subtitle: '蓝紫晨光',
  previewColor: '#2F45EA',
  light: {
    accent: '#2F45EA',
    onAccent: '#FFFFFF',
    onPrimary: '#FFFFFF',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: {
      general: '#2F45EA',
      search: '#3378E8',
      privacySecurity: '#6656F4',
      siteSettings: '#258A8A',
      adBlocker: '#C44E77',
      userScripts: '#7758D8',
      siteCustomization: '#5D74E8',
      webpageTranslation: '#A77A12',
      passwords: '#2B8D68',
      downloads: '#2569D8',
      userAgent: '#637494',
      appearance: '#8F7A18',
      experiments: '#9C55D7',
      sync: '#3A5DFF',
      about: '#56637D'
    },
    syncProviderIconBackgrounds: {
      cloud: '#2F45EA',
      webdav: '#7758D8'
    },
    activityHeatmap: buildActivityHeatmapTokens('#2F45EA', 'light'),
    pageBackground: '#EEF3F8',
    surfaceBackground: '#FFFFFF',
    floatingSurface: '#FFFFFF',
    controlBackground: '#DDE5F1',
    pressedBackground: '#D6E0F2',
    divider: '#1F2441D7',
    outline: '#2A2441D7',
    textPrimary: '#101735',
    textSecondary: '#5E6A86'
  },
  dark: {
    accent: '#9BAAFF',
    onAccent: '#121625',
    onPrimary: '#121625',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: {
      general: '#5368FF',
      search: '#3F8DF2',
      privacySecurity: '#7C67FF',
      siteSettings: '#2F9C9D',
      adBlocker: '#D65C87',
      userScripts: '#8A6AF3',
      siteCustomization: '#6981FF',
      webpageTranslation: '#B38A28',
      passwords: '#35A27B',
      downloads: '#3C79ED',
      userAgent: '#74839F',
      appearance: '#AAA02E',
      experiments: '#B168F0',
      sync: '#5B72FF',
      about: '#69758F'
    },
    syncProviderIconBackgrounds: {
      cloud: '#5368FF',
      webdav: '#8A6AF3'
    },
    activityHeatmap: buildActivityHeatmapTokens('#9BAAFF', 'dark'),
    pageBackground: '#111318',
    surfaceBackground: '#1A1D24',
    floatingSurface: '#20242D',
    controlBackground: '#272C36',
    pressedBackground: '#343A46',
    divider: '#2BFFFFFF',
    outline: '#33FFFFFF',
    textPrimary: '#F2F5FA',
    textSecondary: '#B8BFCC'
  }
};

export const AIRA_ORIGIN_THEME_PALETTE: BrowserThemePalette = {
  id: 'aira_origin',
  title: '铅云',
  subtitle: '中性灰阶',
  previewColor: '#5F6875',
  light: {
    accent: '#5F6875',
    onAccent: '#151A20',
    onPrimary: '#FFFFFF',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: {
      general: '#5F6875',
      search: '#45829F',
      privacySecurity: '#6761B0',
      siteSettings: '#43837C',
      adBlocker: '#995C76',
      userScripts: '#7660A6',
      siteCustomization: '#596EA4',
      webpageTranslation: '#8E7B48',
      passwords: '#488670',
      downloads: '#4D6C9E',
      userAgent: '#647082',
      appearance: '#898750',
      experiments: '#8262AB',
      sync: '#5B68A4',
      about: '#5F6879'
    },
    syncProviderIconBackgrounds: {
      cloud: '#5F6875',
      webdav: '#7660A6'
    },
    activityHeatmap: buildActivityHeatmapTokens('#5F6875', 'light'),
    pageBackground: '#F0F2F4',
    surfaceBackground: '#FFFFFF',
    floatingSurface: '#FFFFFF',
    controlBackground: '#E8ECF0',
    pressedBackground: '#14000000',
    divider: '#1F000000',
    outline: '#26000000',
    textPrimary: '#131924',
    textSecondary: '#5B6676'
  },
  dark: {
    accent: '#AAB3BF',
    onAccent: '#10151B',
    onPrimary: '#10151B',
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: {
      general: '#AAB3BF',
      search: '#71AECA',
      privacySecurity: '#9089D8',
      siteSettings: '#6AAAA3',
      adBlocker: '#BE829B',
      userScripts: '#9B86CA',
      siteCustomization: '#879DD2',
      webpageTranslation: '#B5A26F',
      passwords: '#6FAD97',
      downloads: '#7D9CCE',
      userAgent: '#8B97A8',
      appearance: '#AFAC75',
      experiments: '#A887D0',
      sync: '#8C9AD5',
      about: '#868F9F'
    },
    syncProviderIconBackgrounds: {
      cloud: '#AAB3BF',
      webdav: '#9B86CB'
    },
    activityHeatmap: buildActivityHeatmapTokens('#AAB3BF', 'dark'),
    pageBackground: '#101214',
    surfaceBackground: '#191C20',
    floatingSurface: '#191C20',
    controlBackground: '#262B31',
    pressedBackground: '#33FFFFFF',
    divider: '#26FFFFFF',
    outline: '#33FFFFFF',
    textPrimary: '#F5F7FA',
    textSecondary: '#B4BDC9'
  }
};
