import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';

const BROWSER_BOTTOM_NEUTRAL_CONTAINER_LIGHT: string = '#CCFFFFFF';
const BROWSER_BOTTOM_NEUTRAL_CONTAINER_DARK: string = '#66000000';
const BROWSER_BOTTOM_NEUTRAL_PRESSED_LIGHT: string = '#E6FFFFFF';
const BROWSER_BOTTOM_NEUTRAL_PRESSED_DARK: string = '#8A000000';
const BROWSER_BOTTOM_NEUTRAL_PRIMARY_LIGHT: string = '#4D4D4D';
const BROWSER_BOTTOM_NEUTRAL_PRIMARY_DARK: string = '#F7F8FA';
const BROWSER_BOTTOM_NEUTRAL_SECONDARY_LIGHT: string = '#8A000000';
const BROWSER_BOTTOM_NEUTRAL_SECONDARY_DARK: string = '#99FFFFFF';
const BROWSER_BOTTOM_FLOATING_EXPANDED_CONTAINER_LIGHT: string = '#18FFFFFF';
const BROWSER_BOTTOM_FLOATING_EXPANDED_CONTAINER_DARK: string = '#18000000';
const BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_LIGHT: string = '#99FFFFFF';
const BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_DARK: string = '#14FFFFFF';
const BROWSER_BOTTOM_TOOLBAR_SHEET_ACTION_LIGHT: string = '#FFFFFFFF';
const BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_ICON_LIGHT: string = '#BF000000';
const BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_ICON_DARK: string = '#E6FFFFFF';
const BROWSER_BOTTOM_FLOATING_HEADER_GRAY_START_PROGRESS: number = 0.45;
const BROWSER_BOTTOM_FLOATING_HEADER_GRAY_END_PROGRESS: number = 1;
const BROWSER_BOTTOM_FLOATING_HEADER_DEFAULT_LIGHT_BACKGROUND: string = '#F5FFFFFF';
const BROWSER_BOTTOM_FLOATING_HEADER_DEFAULT_DARK_BACKGROUND: string = '#F5292929';
const BROWSER_BOTTOM_FLOATING_HEADER_LIGHT_BACKGROUND: string = '#CCFFFFFF';
const BROWSER_BOTTOM_FIXED_FLOATING_LIGHT_BACKGROUND: string = '#CCF4F5F7';
const BROWSER_BOTTOM_FLOATING_HEADER_COLLAPSED_DARK_BACKGROUND: string = '#B3292929';
const BROWSER_BOTTOM_FLOATING_MATERIAL_SHADOW_LIGHT: string = '#22000000';
const BROWSER_BOTTOM_FLOATING_MATERIAL_SHADOW_DARK: string = '#40000000';

export const BROWSER_BOTTOM_NEUTRAL_ICON_ENABLED_OPACITY: number = 1;
export const BROWSER_BOTTOM_NEUTRAL_ICON_DISABLED_OPACITY: number = 0.56;

export interface BrowserBottomFloatingHeaderColorInput {
  resolvedThemeMode: BrowserResolvedThemeMode | string;
  floatingInputLayout: boolean;
  keepDefaultChrome: boolean;
  collapsedDarkBackground: boolean;
  grayProgress: number;
}

export function resolveBrowserBottomNeutralContainerColor(mode: BrowserResolvedThemeMode | string): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_NEUTRAL_CONTAINER_DARK :
    BROWSER_BOTTOM_NEUTRAL_CONTAINER_LIGHT;
}

export function resolveBrowserBottomFloatingExpandedContainerColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_FLOATING_EXPANDED_CONTAINER_DARK :
    BROWSER_BOTTOM_FLOATING_EXPANDED_CONTAINER_LIGHT;
}

export function resolveBrowserBottomExpandedToolbarActionColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_DARK :
    BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_LIGHT;
}

export function resolveBrowserBottomToolbarSheetActionColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_DARK :
    BROWSER_BOTTOM_TOOLBAR_SHEET_ACTION_LIGHT;
}

export function resolveBrowserBottomExpandedToolbarActionIconColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_ICON_DARK :
    BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_ICON_LIGHT;
}

export function resolveBrowserBottomNeutralPressedColor(mode: BrowserResolvedThemeMode | string): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_NEUTRAL_PRESSED_DARK :
    BROWSER_BOTTOM_NEUTRAL_PRESSED_LIGHT;
}

export function resolveBrowserBottomNeutralPrimaryColor(mode: BrowserResolvedThemeMode | string): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_NEUTRAL_PRIMARY_DARK :
    BROWSER_BOTTOM_NEUTRAL_PRIMARY_LIGHT;
}

export function resolveBrowserBottomNeutralSecondaryColor(mode: BrowserResolvedThemeMode | string): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_NEUTRAL_SECONDARY_DARK :
    BROWSER_BOTTOM_NEUTRAL_SECONDARY_LIGHT;
}

export function resolveBrowserBottomFloatingMaterialShadowColor(
  mode: BrowserResolvedThemeMode | string
): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_FLOATING_MATERIAL_SHADOW_DARK :
    BROWSER_BOTTOM_FLOATING_MATERIAL_SHADOW_LIGHT;
}

export function resolveBrowserBottomFloatingHeaderColor(input: BrowserBottomFloatingHeaderColorInput): ResourceColor {
  if (input.keepDefaultChrome) {
    return resolveBrowserBottomFloatingHeaderDefaultColor(input.resolvedThemeMode);
  }
  if (isBrowserBottomNeutralDarkMode(input.resolvedThemeMode) && input.floatingInputLayout) {
    return resolveBrowserBottomNeutralContainerColor(input.resolvedThemeMode);
  }
  return resolveBrowserBottomFloatingHeaderDynamicColor(
    input.resolvedThemeMode,
    input.collapsedDarkBackground,
    input.grayProgress
  );
}

export function resolveBrowserBottomFloatingHeaderGrayProgress(rawProgress: number): number {
  const normalizedProgress = (rawProgress - BROWSER_BOTTOM_FLOATING_HEADER_GRAY_START_PROGRESS) /
    Math.max(0.01, BROWSER_BOTTOM_FLOATING_HEADER_GRAY_END_PROGRESS -
    BROWSER_BOTTOM_FLOATING_HEADER_GRAY_START_PROGRESS);
  return resolveBrowserBottomSmoothProgress(normalizedProgress);
}

function resolveBrowserBottomFloatingHeaderDefaultColor(mode: BrowserResolvedThemeMode | string): ResourceColor {
  return isBrowserBottomNeutralDarkMode(mode) ? BROWSER_BOTTOM_FLOATING_HEADER_DEFAULT_DARK_BACKGROUND :
    BROWSER_BOTTOM_FLOATING_HEADER_DEFAULT_LIGHT_BACKGROUND;
}

function resolveBrowserBottomFloatingHeaderDynamicColor(
  mode: BrowserResolvedThemeMode | string,
  collapsedDarkBackground: boolean,
  grayProgress: number
): ResourceColor {
  if (isBrowserBottomNeutralDarkMode(mode)) {
    if (collapsedDarkBackground) {
      return BROWSER_BOTTOM_FLOATING_HEADER_COLLAPSED_DARK_BACKGROUND;
    }
    return resolveBrowserBottomNeutralContainerColor(mode);
  }
  const progress = Math.max(0, Math.min(1, grayProgress));
  if (progress <= 0) {
    return BROWSER_BOTTOM_FLOATING_HEADER_LIGHT_BACKGROUND;
  }
  if (progress >= 1) {
    return BROWSER_BOTTOM_FIXED_FLOATING_LIGHT_BACKGROUND;
  }
  const red = resolveBrowserBottomMixedColorChannel(255, 244, progress);
  const green = resolveBrowserBottomMixedColorChannel(255, 245, progress);
  const blue = resolveBrowserBottomMixedColorChannel(255, 247, progress);
  return `#CC${red}${green}${blue}`;
}

function resolveBrowserBottomMixedColorChannel(start: number, end: number, progress: number): string {
  const value = Math.round(start + (end - start) * Math.max(0, Math.min(1, progress)));
  return Math.max(0, Math.min(255, value)).toString(16).padStart(2, '0').toUpperCase();
}

function resolveBrowserBottomSmoothProgress(progress: number): number {
  const clampedProgress = Math.max(0, Math.min(1, progress));
  return clampedProgress * clampedProgress * (3 - 2 * clampedProgress);
}

function isBrowserBottomNeutralDarkMode(mode: BrowserResolvedThemeMode | string): boolean {
  return mode === 'dark';
}
