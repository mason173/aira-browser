import { BrowserPreferences, BrowserResolvedThemeMode } from '../../common/models/BrowserModels';
import { BrowserThemeModeCoordinator } from '../browser/BrowserThemeModeCoordinator';
import { sharedPreferencesRepository } from '../../app/bootstrap/BrowserAppRuntime';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';
import {
  BrowserActivityHeatmapTokenSet,
  BrowserSettingsIconBackgroundTokenSet,
  BrowserSyncProviderIconBackgroundTokenSet
} from '../../features/theme/BrowserThemePaletteModels';

export interface BrowserThemeViewState {
  pageBackground: string;
  surfaceBackground: string;
  floatingSurface: string;
  controlBackground: string;
  pressedBackground: string;
  divider: string;
  outline: string;
  accent: string;
  onAccent: string;
  onPrimary: string;
  resolvedMode: BrowserResolvedThemeMode;
  settingsIconForeground: string;
  settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet;
  syncProviderIconBackgrounds: BrowserSyncProviderIconBackgroundTokenSet;
  activityHeatmap: BrowserActivityHeatmapTokenSet;
  textPrimary: string;
  textSecondary: string;
}

export class BrowserThemeViewStateFactory {
  private paletteService: BrowserThemePaletteService;
  private themeModeCoordinator: BrowserThemeModeCoordinator;

  constructor(
    paletteService: BrowserThemePaletteService = new BrowserThemePaletteService(),
    themeModeCoordinator: BrowserThemeModeCoordinator = new BrowserThemeModeCoordinator(sharedPreferencesRepository)
  ) {
    this.paletteService = paletteService;
    this.themeModeCoordinator = themeModeCoordinator;
  }

  build(preferences: BrowserPreferences): BrowserThemeViewState {
    const resolvedMode = this.themeModeCoordinator.resolveEffectiveMode(preferences.themeMode);
    const tokens = this.paletteService.resolveTokens(
      preferences.appearance.themePaletteId,
      resolvedMode
    );
    return {
      pageBackground: tokens.pageBackground,
      surfaceBackground: tokens.surfaceBackground,
      floatingSurface: tokens.floatingSurface,
      controlBackground: tokens.controlBackground,
      pressedBackground: tokens.pressedBackground,
      divider: tokens.divider,
      outline: tokens.outline,
      accent: tokens.accent,
      onAccent: tokens.onAccent,
      onPrimary: tokens.onPrimary,
      settingsIconForeground: tokens.settingsIconForeground,
      settingsIconBackgrounds: tokens.settingsIconBackgrounds,
      syncProviderIconBackgrounds: tokens.syncProviderIconBackgrounds,
      activityHeatmap: tokens.activityHeatmap,
      textPrimary: tokens.textPrimary,
      textSecondary: tokens.textSecondary,
      resolvedMode: tokens.mode
    };
  }
}
