import {
  BrowserPreferences,
  BrowserResolvedThemeMode
} from '../../../common/models/BrowserModels';
import {
  BrowserThemePaletteService,
  ResolvedBrowserThemeTokens
} from '../../../services/theme/BrowserThemePaletteService';

export interface BrowserTabsOverviewThemeState {
  backgroundColor: string;
  surfaceBackground: string;
  controlBackground: string;
  pressedBackground: string;
  outlineColor: string;
  textPrimaryColor: string;
  textSecondaryColor: string;
  accentColor: string;
  blurPrivateTabPreviews: boolean;
}

export interface BrowserTabsOverviewThemeInput {
  preferences: BrowserPreferences;
  resolvedThemeMode: BrowserResolvedThemeMode;
  paletteService: BrowserThemePaletteService;
}

export class BrowserTabsOverviewThemeViewModel {
  buildState(input: BrowserTabsOverviewThemeInput): BrowserTabsOverviewThemeState {
    const preferences = input.preferences;
    const tokens = input.paletteService.resolveTokens(
      preferences.appearance.themePaletteId,
      input.resolvedThemeMode
    );
    return {
      backgroundColor: this.resolveBackgroundColor(tokens),
      surfaceBackground: tokens.floatingSurface,
      controlBackground: tokens.controlBackground,
      pressedBackground: tokens.pressedBackground,
      outlineColor: tokens.outline,
      textPrimaryColor: tokens.textPrimary,
      textSecondaryColor: tokens.textSecondary,
      accentColor: tokens.accent,
      blurPrivateTabPreviews: preferences.appearance.blurPrivateTabPreviews
    };
  }

  private resolveBackgroundColor(tokens: ResolvedBrowserThemeTokens): string {
    return tokens.mode === 'light' ? tokens.controlBackground : tokens.pageBackground;
  }
}
