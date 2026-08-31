import {
  BrowserResolvedThemeMode,
  BrowserThemeMode,
  BrowserThemePaletteId
} from '../../common/models/BrowserModels';
import {
  CustomHomepageThemePaletteState,
  CustomHomepageThemeState
} from './CustomHomepageBridgeService';
import {
  BrowserThemePaletteService,
  ResolvedBrowserThemeTokens
} from '../theme/BrowserThemePaletteService';

export interface CustomHomepageThemePaletteProjectionInput {
  preferences: CustomHomepageThemePreferenceSnapshot;
  mode: BrowserThemeMode;
  effectiveMode: BrowserResolvedThemeMode;
}

export interface CustomHomepageThemePreferenceSnapshot {
  themePaletteId: BrowserThemePaletteId;
}

export class CustomHomepageThemePaletteProjectionService {
  private themePaletteService: BrowserThemePaletteService;

  constructor(themePaletteService: BrowserThemePaletteService = new BrowserThemePaletteService()) {
    this.themePaletteService = themePaletteService;
  }

  build(input: CustomHomepageThemePaletteProjectionInput): CustomHomepageThemeState {
    const tokens = this.themePaletteService.resolveTokens(
      input.preferences.themePaletteId,
      input.effectiveMode
    );
    return {
      mode: input.mode,
      effectiveMode: tokens.mode,
      palette: this.buildPalette(tokens)
    };
  }

  private buildPalette(tokens: ResolvedBrowserThemeTokens): CustomHomepageThemePaletteState {
    return {
      id: tokens.paletteId,
      title: tokens.paletteTitle,
      colors: {
        accent: this.resolveCssColor(tokens.accent),
        onAccent: this.resolveCssColor(tokens.onAccent),
        pageBackground: this.resolveCssColor(tokens.pageBackground),
        surfaceBackground: this.resolveCssColor(tokens.surfaceBackground),
        controlBackground: this.resolveCssColor(tokens.controlBackground),
        textPrimary: this.resolveCssColor(tokens.textPrimary),
        textSecondary: this.resolveCssColor(tokens.textSecondary),
        divider: this.resolveCssColor(tokens.divider),
        outline: this.resolveCssColor(tokens.outline)
      }
    };
  }

  private resolveCssColor(value: string): string {
    const normalized = value.trim();
    if (normalized.match(/^#[0-9a-fA-F]{8}$/) === null) {
      return normalized;
    }
    const alpha = parseInt(normalized.substring(1, 3), 16) / 255;
    const red = parseInt(normalized.substring(3, 5), 16);
    const green = parseInt(normalized.substring(5, 7), 16);
    const blue = parseInt(normalized.substring(7, 9), 16);
    const normalizedAlpha = Math.round(Math.min(1, Math.max(0, alpha)) * 1000) / 1000;
    return `rgba(${red},${green},${blue},${normalizedAlpha})`;
  }
}
