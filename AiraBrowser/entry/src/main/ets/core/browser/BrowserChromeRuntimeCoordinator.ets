import {
  BrowserResolvedThemeMode,
  BrowserThemeMode,
  ReaderModeTheme
} from '../../common/models/BrowserModels';
import { HomeWallpaperPresentationState } from '../../common/models/WallpaperModels';
import {
  BrowserForegroundBackdropEffectInput,
  BrowserForegroundPresentationViewModel
} from './BrowserForegroundPresentationViewModel';
import { AppChromeIconTone } from '../resources/AppIconResources';
export const BROWSER_DARK_WEB_TOP_SAFE_AREA_COLOR: string = '#000000';

export interface BrowserChromeRuntimeState {
  pageChromeThemes: Record<string, BrowserPageChromeThemeState>;
}

export interface BrowserPageChromeThemeState {
  themeColor: string;
  pageBackgroundColor: string;
  visualTopColor?: string;
  prefersDarkScheme: boolean;
  supportsDarkAppearance: boolean;
}

export type BrowserChromeFallbackColorToken = 'web_chrome_light_fallback' | 'web_chrome_dark_fallback';

export interface BrowserChromeBackdropColorResult {
  color: string;
  fallbackToken?: BrowserChromeFallbackColorToken;
}

export interface BrowserWebTopSafeAreaBackdropInput {
  state: BrowserChromeRuntimeState;
  activeTabId: string;
  webPageVisible: boolean;
  globalImmersionEnabled: boolean;
  resolvedThemeMode: BrowserResolvedThemeMode;
}

export interface BrowserStatusBarContentStyleInput extends BrowserWebTopSafeAreaBackdropInput {
  readerModeVisible: boolean;
  readerModeTheme: ReaderModeTheme;
  homePageVisible: boolean;
  homeWallpaperState: HomeWallpaperPresentationState;
  homeThemeBackgroundColor: ResourceColor;
  homeBackdropEffectTintColor?: ResourceColor;
  homeBackdropEffectTintOpacity?: number;
  webVideoControllerActive: boolean;
  bottomPanelHigh: boolean;
  bottomPanelVisible: boolean;
}

export class BrowserChromeRuntimeCoordinator {
  private browserForegroundPresentationViewModel: BrowserForegroundPresentationViewModel =
    new BrowserForegroundPresentationViewModel();

  createState(): BrowserChromeRuntimeState {
    return {
      pageChromeThemes: {}
    };
  }

  buildWebTopChromeInsetPx(
    systemTopInsetVp: number,
    contentGapVp: number
  ): number {
    return Math.max(0, Math.ceil(systemTopInsetVp + contentGapVp));
  }

  buildStableWebViewportBottomInsetPx(
    bottomSafeInsetVp: number,
    _homeSearchOverlayVisible: boolean,
    _webPageVisible: boolean
  ): number {
    return Math.max(0, Math.ceil(bottomSafeInsetVp));
  }

  resolveWebTopSafeAreaBackdropColor(input: BrowserWebTopSafeAreaBackdropInput): string {
    if (!input.webPageVisible || input.globalImmersionEnabled) {
      return '';
    }
    const theme = input.state.pageChromeThemes[input.activeTabId];
    if (theme === undefined) {
      if (input.resolvedThemeMode === 'dark') {
        return BROWSER_DARK_WEB_TOP_SAFE_AREA_COLOR;
      }
      return '';
    }
    if (this.shouldIgnoreStaleDarkThemeSnapshot(theme, input.resolvedThemeMode)) {
      return '';
    }
    if (this.shouldUsePageColor(theme.visualTopColor ?? '', theme, input.resolvedThemeMode)) {
      return theme.visualTopColor ?? '';
    }
    if (this.shouldPreferThemeColor(theme, input.resolvedThemeMode)) {
      return theme.themeColor;
    }
    if (this.shouldUsePageColor(theme.pageBackgroundColor, theme, input.resolvedThemeMode)) {
      return theme.pageBackgroundColor;
    }
    if (input.resolvedThemeMode === 'dark') {
      return BROWSER_DARK_WEB_TOP_SAFE_AREA_COLOR;
    }
    return '';
  }

  shouldUseLightStatusBarContentForWebTopSafeArea(input: BrowserWebTopSafeAreaBackdropInput): boolean {
    const color = this.resolveWebTopSafeAreaBackdropColor(input);
    return color.length > 0 && this.isDarkColor(color);
  }

  resolveChromeIconTone(resolvedThemeMode: BrowserResolvedThemeMode): AppChromeIconTone {
    return resolvedThemeMode === 'dark' ? 'dark' : 'light';
  }

  shouldUseLightStatusBarContent(input: BrowserStatusBarContentStyleInput): boolean {
    if (input.webVideoControllerActive) {
      return true;
    }
    if (input.readerModeVisible) {
      return input.readerModeTheme === 'dark' || input.readerModeTheme === 'charcoal';
    }
    const homeWallpaperStyle = this.resolveHomeWallpaperLightStatusBarContent(
      input.homePageVisible,
      input.homeWallpaperState,
      input.homeThemeBackgroundColor,
      this.resolveHomeBackdropToneEffect(input)
    );
    if (homeWallpaperStyle !== undefined) {
      return homeWallpaperStyle;
    }
    if (input.resolvedThemeMode === 'dark') {
      return true;
    }
    if (this.shouldUseLightStatusBarContentForWebTopSafeArea(input)) {
      return true;
    }
    return input.bottomPanelHigh && input.bottomPanelVisible;
  }

  private resolveHomeWallpaperLightStatusBarContent(
    homePageVisible: boolean,
    wallpaperState: HomeWallpaperPresentationState,
    themeBackgroundColor: ResourceColor,
    effect?: BrowserForegroundBackdropEffectInput
  ): boolean | undefined {
    if (!homePageVisible) {
      return undefined;
    }
    return this.browserForegroundPresentationViewModel.resolveHomeTone(
      wallpaperState,
      themeBackgroundColor,
      effect
    ) === 'light';
  }

  private resolveHomeBackdropToneEffect(
    input: BrowserStatusBarContentStyleInput
  ): BrowserForegroundBackdropEffectInput | undefined {
    if (input.homeBackdropEffectTintColor === undefined ||
      input.homeBackdropEffectTintOpacity === undefined ||
      input.homeBackdropEffectTintOpacity <= 0) {
      return undefined;
    }
    return {
      tintColor: input.homeBackdropEffectTintColor,
      tintOpacity: input.homeBackdropEffectTintOpacity
    };
  }

  applyPageChromeTheme(
    state: BrowserChromeRuntimeState,
    tabId: string,
    pageChromeTheme: BrowserPageChromeThemeState
  ): BrowserChromeRuntimeState {
    const nextTheme = this.normalizePageChromeTheme(pageChromeTheme);
    const currentTheme = state.pageChromeThemes[tabId];
    const mergedTheme = this.normalizePageChromeTheme({
      themeColor: nextTheme.themeColor,
      pageBackgroundColor: nextTheme.pageBackgroundColor,
      visualTopColor: currentTheme?.visualTopColor ?? '',
      prefersDarkScheme: nextTheme.prefersDarkScheme,
      supportsDarkAppearance: nextTheme.supportsDarkAppearance
    });
    if (this.arePageChromeThemesEqual(currentTheme, mergedTheme)) {
      return state;
    }
    const nextThemes = this.clonePageChromeThemes(state.pageChromeThemes);
    nextThemes[tabId] = mergedTheme;
    return {
      pageChromeThemes: nextThemes
    };
  }

  applyPageChromeVisualTopColor(
    state: BrowserChromeRuntimeState,
    tabId: string,
    visualTopColor: string
  ): BrowserChromeRuntimeState {
    const currentTheme = state.pageChromeThemes[tabId] ?? {
      themeColor: '',
      pageBackgroundColor: '',
      visualTopColor: '',
      prefersDarkScheme: false,
      supportsDarkAppearance: false
    };
    const nextTheme = this.normalizePageChromeTheme({
      themeColor: currentTheme.themeColor,
      pageBackgroundColor: currentTheme.pageBackgroundColor,
      visualTopColor: visualTopColor,
      prefersDarkScheme: currentTheme.prefersDarkScheme,
      supportsDarkAppearance: currentTheme.supportsDarkAppearance
    });
    if (this.arePageChromeThemesEqual(currentTheme, nextTheme)) {
      return state;
    }
    const nextThemes = this.clonePageChromeThemes(state.pageChromeThemes);
    nextThemes[tabId] = nextTheme;
    return {
      pageChromeThemes: nextThemes
    };
  }

  clearPageChromeTheme(state: BrowserChromeRuntimeState, tabId: string): BrowserChromeRuntimeState {
    if (state.pageChromeThemes[tabId] === undefined) {
      return state;
    }
    return {
      pageChromeThemes: this.removePageChromeTheme(state.pageChromeThemes, tabId)
    };
  }

  resolveWebViewportBackdropColor(
    state: BrowserChromeRuntimeState,
    activeTabId: string,
    browserThemeMode: BrowserThemeMode
  ): BrowserChromeBackdropColorResult {
    if (browserThemeMode === 'light') {
      return this.resolveFallbackBackdropColorForMode(browserThemeMode);
    }
    const theme = state.pageChromeThemes[activeTabId];
    if (theme === undefined) {
      return this.resolveFallbackBackdropColorForMode(browserThemeMode);
    }
    if (this.shouldUsePageColor(theme.pageBackgroundColor, theme, browserThemeMode)) {
      return { color: theme.pageBackgroundColor };
    }
    return this.resolveFallbackBackdropColor(theme, browserThemeMode);
  }

  resolveWebTopChromeBackdropColor(
    state: BrowserChromeRuntimeState,
    activeTabId: string,
    webAddressMaskCompact: boolean,
    browserThemeMode: BrowserThemeMode
  ): BrowserChromeBackdropColorResult {
    if (browserThemeMode === 'light') {
      return this.resolveFallbackBackdropColorForMode(browserThemeMode);
    }
    const theme = state.pageChromeThemes[activeTabId];
    if (theme === undefined) {
      return this.resolveFallbackBackdropColorForMode(browserThemeMode);
    }
    if (webAddressMaskCompact && this.shouldUsePageColor(theme.themeColor, theme, browserThemeMode)) {
      return { color: theme.themeColor };
    }
    if (this.shouldUsePageColor(theme.pageBackgroundColor, theme, browserThemeMode)) {
      return { color: theme.pageBackgroundColor };
    }
    return this.resolveFallbackBackdropColor(theme, browserThemeMode);
  }

  private normalizePageChromeTheme(pageChromeTheme: BrowserPageChromeThemeState): BrowserPageChromeThemeState {
    return {
      themeColor: pageChromeTheme.themeColor.trim().toUpperCase(),
      pageBackgroundColor: pageChromeTheme.pageBackgroundColor.trim().toUpperCase(),
      visualTopColor: (pageChromeTheme.visualTopColor ?? '').trim().toUpperCase(),
      prefersDarkScheme: pageChromeTheme.prefersDarkScheme === true,
      supportsDarkAppearance: pageChromeTheme.supportsDarkAppearance === true
    };
  }

  private arePageChromeThemesEqual(
    currentTheme: BrowserPageChromeThemeState | undefined,
    nextTheme: BrowserPageChromeThemeState
  ): boolean {
    if (currentTheme === undefined) {
      return false;
    }
    return currentTheme.themeColor === nextTheme.themeColor &&
      currentTheme.pageBackgroundColor === nextTheme.pageBackgroundColor &&
      (currentTheme.visualTopColor ?? '') === (nextTheme.visualTopColor ?? '') &&
      currentTheme.prefersDarkScheme === nextTheme.prefersDarkScheme &&
      currentTheme.supportsDarkAppearance === nextTheme.supportsDarkAppearance;
  }

  private resolveFallbackBackdropColor(
    theme: BrowserPageChromeThemeState,
    browserThemeMode: BrowserThemeMode
  ): BrowserChromeBackdropColorResult {
    if (theme.prefersDarkScheme && theme.supportsDarkAppearance) {
      return { color: '', fallbackToken: 'web_chrome_dark_fallback' };
    }
    return this.resolveFallbackBackdropColorForMode(browserThemeMode);
  }

  private resolveFallbackBackdropColorForMode(browserThemeMode: BrowserThemeMode): BrowserChromeBackdropColorResult {
    if (browserThemeMode === 'dark') {
      return { color: '', fallbackToken: 'web_chrome_dark_fallback' };
    }
    return { color: '', fallbackToken: 'web_chrome_light_fallback' };
  }

  private shouldUsePageColor(
    color: string,
    theme: BrowserPageChromeThemeState,
    browserThemeMode: BrowserThemeMode
  ): boolean {
    if (color.length <= 0) {
      return false;
    }
    if (browserThemeMode === 'dark' && !theme.supportsDarkAppearance && this.isLightColor(color)) {
      return false;
    }
    return true;
  }

  private shouldPreferThemeColor(
    theme: BrowserPageChromeThemeState,
    browserThemeMode: BrowserThemeMode
  ): boolean {
    if (!this.shouldUsePageColor(theme.themeColor, theme, browserThemeMode)) {
      return false;
    }
    if (!this.shouldUsePageColor(theme.pageBackgroundColor, theme, browserThemeMode)) {
      return true;
    }
    return this.colorsShareVisualTone(theme.themeColor, theme.pageBackgroundColor);
  }

  private shouldIgnoreStaleDarkThemeSnapshot(
    theme: BrowserPageChromeThemeState,
    browserThemeMode: BrowserThemeMode
  ): boolean {
    return browserThemeMode === 'light' && theme.prefersDarkScheme;
  }

  private colorsShareVisualTone(firstColor: string, secondColor: string): boolean {
    return this.isDarkColor(firstColor) === this.isDarkColor(secondColor);
  }

  private isLightColor(color: string): boolean {
    const normalized = color.trim().replace('#', '');
    if (!/^[0-9A-F]{6}$/.test(normalized)) {
      return false;
    }
    const red = parseInt(normalized.substring(0, 2), 16);
    const green = parseInt(normalized.substring(2, 4), 16);
    const blue = parseInt(normalized.substring(4, 6), 16);
    const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    return luminance >= 180;
  }

  private isDarkColor(color: string): boolean {
    const normalized = color.trim().replace('#', '');
    if (!/^[0-9A-F]{6}$/.test(normalized)) {
      return false;
    }
    const red = parseInt(normalized.substring(0, 2), 16);
    const green = parseInt(normalized.substring(2, 4), 16);
    const blue = parseInt(normalized.substring(4, 6), 16);
    const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
    return luminance < 128;
  }

  private clonePageChromeThemes(
    source: Record<string, BrowserPageChromeThemeState>
  ): Record<string, BrowserPageChromeThemeState> {
    const result: Record<string, BrowserPageChromeThemeState> = {};
    Object.keys(source).forEach((key: string) => {
      result[key] = source[key];
    });
    return result;
  }

  private removePageChromeTheme(
    source: Record<string, BrowserPageChromeThemeState>,
    removedTabId: string
  ): Record<string, BrowserPageChromeThemeState> {
    const result: Record<string, BrowserPageChromeThemeState> = {};
    Object.keys(source).forEach((key: string) => {
      if (key !== removedTabId) {
        result[key] = source[key];
      }
    });
    return result;
  }
}
