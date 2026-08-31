import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import {
  FLOATING_GLASS_MATERIAL_BLUR_STYLE,
  FLOATING_GLASS_MATERIAL_DARK_TINT,
  FLOATING_GLASS_MATERIAL_LIGHT_TINT,
  resolveFloatingGlassMaterialTintForMode
} from '../common/FloatingGlassMaterialTokens';

export const BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE: BlurStyle = FLOATING_GLASS_MATERIAL_BLUR_STYLE;
export const BROWSER_FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS: BackgroundBlurStyleOptions = {
  adaptiveColor: AdaptiveColor.AVERAGE,
  policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
};
export const BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_TINT;
export const BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT: ResourceColor = FLOATING_GLASS_MATERIAL_DARK_TINT;
export const BROWSER_BOTTOM_CHROME_DARK_MATERIAL_TINT: ResourceColor = '#332C2C2E';
export const BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR: ResourceColor = '#25FFFFFF';
export const BROWSER_HOME_SHORTCUT_DARK_MATERIAL_TINT: ResourceColor = '#332C2C2E';
export const BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_OPTIONS: BackgroundBlurStyleOptions = {
  colorMode: ThemeColorMode.LIGHT
};
export const BROWSER_FLOATING_GLASS_MATERIAL_DARK_OPTIONS: BackgroundBlurStyleOptions = {
  colorMode: ThemeColorMode.DARK
};
export const BROWSER_TABS_OVERVIEW_GLASS_MATERIAL_TINT: ResourceColor = BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT;
export const BROWSER_TABS_OVERVIEW_GLASS_MATERIAL_OPTIONS: BackgroundBlurStyleOptions =
  BROWSER_FLOATING_GLASS_MATERIAL_DARK_OPTIONS;

export function resolveBrowserFloatingGlassMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolveFloatingGlassMaterialTintForMode(resolvedThemeMode);
}

export function resolveBrowserBottomChromeMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolvedThemeMode === 'dark' ?
    BROWSER_BOTTOM_CHROME_DARK_MATERIAL_TINT :
    BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}

export function resolveBrowserHomeShortcutMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolvedThemeMode === 'dark' ?
    BROWSER_HOME_SHORTCUT_DARK_MATERIAL_TINT :
    BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}

export function resolveBrowserFloatingGlassMaterialOptionsForMode(
  resolvedThemeMode: string
): BackgroundBlurStyleOptions {
  return resolvedThemeMode === 'dark' ?
    BROWSER_FLOATING_GLASS_MATERIAL_DARK_OPTIONS :
    BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_OPTIONS;
}

export function resolveBrowserFloatingGlassMaterialTintForTone(tone: AppChromeIconTone): ResourceColor {
  return tone === 'dark' ?
    BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT :
    BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}
