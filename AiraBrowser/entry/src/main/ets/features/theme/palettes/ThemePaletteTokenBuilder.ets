import {
  BrowserActivityHeatmapTokenSet,
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet,
  BrowserThemeTokenSet
} from '../BrowserThemePaletteModels';

interface BrowserThemeRgbColor {
  red: number;
  green: number;
  blue: number;
}

export function buildLightTokens(
  accent: string,
  onAccent: string,
  pageBackground: string,
  surfaceBackground: string,
  controlBackground: string,
  textPrimary: string
): BrowserThemeTokenSet {
  const softenedPageBackground = blendHexColor('#F0F2F4', pageBackground, 0.42);
  const softenedControlBackground = blendHexColor('#E9EDF2', controlBackground, 0.42);
  const softenedTextPrimary = blendHexColor('#111827', textPrimary, 0.38);
  const secondaryText = blendHexColor('#5B6676', accent, 0.08);
  return {
    accent,
    onAccent,
    onPrimary: onAccent,
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: buildSettingsIconBackgroundTokens(accent),
    syncProviderIconBackgrounds: buildSyncProviderIconBackgroundTokens(accent),
    activityHeatmap: buildActivityHeatmapTokens(accent, 'light'),
    pageBackground: softenedPageBackground,
    surfaceBackground,
    floatingSurface: surfaceBackground,
    controlBackground: softenedControlBackground,
    pressedBackground: '#14000000',
    divider: '#1F000000',
    outline: '#26000000',
    textPrimary: softenedTextPrimary,
    textSecondary: secondaryText
  };
}

export function buildDarkTokens(
  accent: string,
  onAccent: string,
  pageBackground: string,
  surfaceBackground: string,
  controlBackground: string
): BrowserThemeTokenSet {
  const softenedPageBackground = blendHexColor('#101214', pageBackground, 0.28);
  const softenedSurfaceBackground = blendHexColor('#191C20', surfaceBackground, 0.32);
  const softenedControlBackground = blendHexColor('#262B32', controlBackground, 0.34);
  const textPrimary = blendHexColor('#F4F7FB', accent, 0.025);
  const textSecondary = blendHexColor('#B5BECA', accent, 0.06);
  return {
    accent,
    onAccent,
    onPrimary: onAccent,
    settingsIconForeground: '#FFFFFF',
    settingsIconBackgrounds: buildSettingsIconBackgroundTokens(accent),
    syncProviderIconBackgrounds: buildSyncProviderIconBackgroundTokens(accent),
    activityHeatmap: buildActivityHeatmapTokens(accent, 'dark'),
    pageBackground: softenedPageBackground,
    surfaceBackground: softenedSurfaceBackground,
    floatingSurface: softenedSurfaceBackground,
    controlBackground: softenedControlBackground,
    pressedBackground: '#33FFFFFF',
    divider: '#26FFFFFF',
    outline: '#33FFFFFF',
    textPrimary,
    textSecondary
  };
}

export function buildActivityHeatmapTokens(
  accent: string,
  mode: 'light' | 'dark'
): BrowserActivityHeatmapTokenSet {
  if (mode === 'dark') {
    return {
      empty: blendHexColor('#1B2024', accent, 0.08),
      level1: blendHexColor('#20262C', accent, 0.22),
      level2: blendHexColor('#252E36', accent, 0.4),
      level3: blendHexColor('#324150', accent, 0.62),
      level4: blendHexColor('#F5F8FF', accent, 0.78),
      todayBorder: blendHexColor('#F8FAFF', accent, 0.78)
    };
  }
  return {
    empty: blendHexColor('#F1F4F5', accent, 0.05),
    level1: blendHexColor('#EEF2F4', accent, 0.18),
    level2: blendHexColor('#DCE5EA', accent, 0.36),
    level3: blendHexColor('#AABAC4', accent, 0.62),
    level4: blendHexColor('#1E2A32', accent, 0.78),
    todayBorder: blendHexColor('#18242B', accent, 0.82)
  };
}

function buildSyncProviderIconBackgroundTokens(accent: string): BrowserSyncProviderIconBackgroundTokenSet {
  return {
    cloud: accent,
    webdav: blendHexColor(accent, '#8C58D6', 0.5)
  };
}

function buildSettingsIconBackgroundTokens(accent: string): BrowserSettingsIconBackgroundTokenSet {
  return {
    general: accent,
    search: blendHexColor(accent, '#22A7D8', 0.42),
    privacySecurity: blendHexColor(accent, '#7158F6', 0.46),
    siteSettings: blendHexColor(accent, '#24A184', 0.48),
    adBlocker: blendHexColor(accent, '#D25076', 0.5),
    userScripts: blendHexColor(accent, '#8C58D6', 0.5),
    siteCustomization: blendHexColor(accent, '#4F79F0', 0.38),
    webpageTranslation: blendHexColor(accent, '#C09018', 0.48),
    passwords: blendHexColor(accent, '#2FA66B', 0.48),
    downloads: blendHexColor(accent, '#2E73E8', 0.36),
    userAgent: blendHexColor(accent, '#6A7890', 0.48),
    appearance: blendHexColor(accent, '#B3A52B', 0.5),
    experiments: blendHexColor(accent, '#A55BE0', 0.5),
    sync: blendHexColor(accent, '#5368FF', 0.34),
    about: blendHexColor(accent, '#5E687D', 0.48)
  };
}

function blendHexColor(baseColor: string, tintColor: string, tintRatio: number): string {
  const base = parseHexColor(baseColor);
  const tint = parseHexColor(tintColor);
  const ratio = clampRatio(tintRatio);
  return `#${blendChannel(base.red, tint.red, ratio)}${blendChannel(base.green, tint.green, ratio)}${blendChannel(base.blue, tint.blue, ratio)}`;
}

function parseHexColor(value: string): BrowserThemeRgbColor {
  const normalized = value.replace('#', '').trim();
  return {
    red: parseInt(normalized.substring(0, 2), 16),
    green: parseInt(normalized.substring(2, 4), 16),
    blue: parseInt(normalized.substring(4, 6), 16)
  };
}

function blendChannel(base: number, tint: number, ratio: number): string {
  const value = Math.round(base * (1 - ratio) + tint * ratio);
  return value.toString(16).padStart(2, '0').toUpperCase();
}

function clampRatio(value: number): number {
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}
