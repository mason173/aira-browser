import {
  BrowserResolvedThemeMode,
  BrowserThemePaletteId
} from '../../common/models/BrowserModels';
import {
  BrowserActivityHeatmapTokenSet,
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet,
  BrowserThemePalette,
  BrowserThemeTokenSet,
  DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS,
  DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../features/theme/BrowserThemePaletteModels';
import {
  BUILT_IN_THEME_PALETTES,
  DEFAULT_BROWSER_THEME_PALETTE_ID,
  findBrowserThemePalette
} from '../../features/theme/BrowserThemePalettes';
export interface ResolvedBrowserThemeTokens extends BrowserThemeTokenSet {
  paletteId: BrowserThemePaletteId;
  paletteTitle: string;
  mode: 'light' | 'dark';
}

export class BrowserThemePaletteService {
  listPalettes(): BrowserThemePalette[] {
    return BUILT_IN_THEME_PALETTES.map((palette: BrowserThemePalette) => this.clonePalette(palette));
  }

  resolvePalette(id: BrowserThemePaletteId): BrowserThemePalette {
    return this.clonePalette(findBrowserThemePalette(id));
  }

  resolvePaletteLabel(id: BrowserThemePaletteId): string {
    return this.resolvePalette(id).title;
  }

  resolveTokens(
    paletteId: BrowserThemePaletteId,
    mode: BrowserResolvedThemeMode
  ): ResolvedBrowserThemeTokens {
    const palette = this.resolvePalette(paletteId);
    const baseTokens = mode === 'dark' ? palette.dark : palette.light;
    const tokens = this.cloneTokenSet(baseTokens);
    return {
      accent: tokens.accent,
      onAccent: tokens.onAccent,
      onPrimary: tokens.onPrimary,
      settingsIconForeground: tokens.settingsIconForeground,
      settingsIconBackgrounds: this.cloneSettingsIconBackgroundTokens(tokens.settingsIconBackgrounds),
      syncProviderIconBackgrounds: this.cloneSyncProviderIconBackgroundTokens(tokens.syncProviderIconBackgrounds),
      activityHeatmap: this.cloneActivityHeatmapTokens(tokens.activityHeatmap),
      pageBackground: tokens.pageBackground,
      surfaceBackground: tokens.surfaceBackground,
      floatingSurface: tokens.floatingSurface,
      controlBackground: tokens.controlBackground,
      pressedBackground: tokens.pressedBackground,
      divider: tokens.divider,
      outline: tokens.outline,
      textPrimary: tokens.textPrimary,
      textSecondary: tokens.textSecondary,
      paletteId: palette.id,
      paletteTitle: palette.title,
      mode
    };
  }

  getDefaultPaletteId(): BrowserThemePaletteId {
    return DEFAULT_BROWSER_THEME_PALETTE_ID;
  }

  private clonePalette(palette: BrowserThemePalette): BrowserThemePalette {
    return {
      id: palette.id,
      title: palette.title,
      subtitle: palette.subtitle,
      previewColor: palette.previewColor,
      light: this.cloneTokenSet(palette.light),
      dark: this.cloneTokenSet(palette.dark)
    };
  }

  private cloneTokenSet(tokens: BrowserThemeTokenSet): BrowserThemeTokenSet {
    return {
      accent: tokens.accent,
      onAccent: tokens.onAccent,
      onPrimary: tokens.onPrimary,
      settingsIconForeground: tokens.settingsIconForeground,
      settingsIconBackgrounds: this.cloneSettingsIconBackgroundTokens(tokens.settingsIconBackgrounds),
      syncProviderIconBackgrounds: this.cloneSyncProviderIconBackgroundTokens(tokens.syncProviderIconBackgrounds),
      activityHeatmap: this.cloneActivityHeatmapTokens(tokens.activityHeatmap),
      pageBackground: tokens.pageBackground,
      surfaceBackground: tokens.surfaceBackground,
      floatingSurface: tokens.floatingSurface,
      controlBackground: tokens.controlBackground,
      pressedBackground: tokens.pressedBackground,
      divider: tokens.divider,
      outline: tokens.outline,
      textPrimary: tokens.textPrimary,
      textSecondary: tokens.textSecondary
    };
  }

  private cloneSyncProviderIconBackgroundTokens(
    tokens: BrowserSyncProviderIconBackgroundTokenSet | undefined
  ): BrowserSyncProviderIconBackgroundTokenSet {
    const resolvedTokens = tokens ?? DEFAULT_BROWSER_SYNC_PROVIDER_ICON_BACKGROUND_TOKENS;
    return {
      cloud: resolvedTokens.cloud,
      webdav: resolvedTokens.webdav
    };
  }

  private cloneActivityHeatmapTokens(
    tokens: BrowserActivityHeatmapTokenSet | undefined
  ): BrowserActivityHeatmapTokenSet {
    const resolvedTokens = tokens ?? DEFAULT_BROWSER_ACTIVITY_HEATMAP_TOKENS;
    return {
      empty: resolvedTokens.empty,
      level1: resolvedTokens.level1,
      level2: resolvedTokens.level2,
      level3: resolvedTokens.level3,
      level4: resolvedTokens.level4,
      todayBorder: resolvedTokens.todayBorder
    };
  }

  private cloneSettingsIconBackgroundTokens(
    tokens: BrowserSettingsIconBackgroundTokenSet | undefined
  ): BrowserSettingsIconBackgroundTokenSet {
    const resolvedTokens = tokens ?? DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
    return {
      general: resolvedTokens.general,
      search: resolvedTokens.search,
      privacySecurity: resolvedTokens.privacySecurity,
      siteSettings: resolvedTokens.siteSettings,
      adBlocker: resolvedTokens.adBlocker,
      userScripts: resolvedTokens.userScripts,
      siteCustomization: resolvedTokens.siteCustomization,
      webpageTranslation: resolvedTokens.webpageTranslation,
      passwords: resolvedTokens.passwords,
      downloads: resolvedTokens.downloads,
      userAgent: resolvedTokens.userAgent,
      appearance: resolvedTokens.appearance,
      experiments: resolvedTokens.experiments,
      sync: resolvedTokens.sync,
      about: resolvedTokens.about
    };
  }
}
