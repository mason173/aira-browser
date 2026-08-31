import { AppChromeIconTone } from '../resources/AppIconResources';
import { BrowserHomepageBackdropAppearanceState } from '../../common/models/BackdropAppearanceModels';
import { HomeWallpaperPresentationState } from '../../common/models/WallpaperModels';
import { BrowserHomeForegroundBackdropSource } from './BrowserHomeSurfaceProfileViewModel';

export type BrowserForegroundTone = 'light' | 'dark';

export interface BrowserForegroundPresentation {
  tone: BrowserForegroundTone;
  primaryTextColor: ResourceColor;
  secondaryTextColor: ResourceColor;
  iconColor: ResourceColor;
  iconTone: AppChromeIconTone;
  textShadow: Array<ShadowOptions>;
  freshnessKey: string;
}

export interface BrowserHomeForegroundPresentationInput {
  foregroundBackdropSource: BrowserHomeForegroundBackdropSource;
  backdropAppearanceState?: BrowserHomepageBackdropAppearanceState;
  wallpaperState: HomeWallpaperPresentationState;
  themeBackgroundColor: ResourceColor;
  themedPrimaryTextColor: ResourceColor;
  themedSecondaryTextColor: ResourceColor;
}

export interface BrowserForegroundBackdropEffectInput {
  tintColor: ResourceColor;
  tintOpacity: number;
}

interface BrowserForegroundRgbColor {
  r: number;
  g: number;
  b: number;
}

const IMAGE_LIGHT_PRIMARY: string = '#FFFFFFFF';
const IMAGE_LIGHT_SECONDARY: string = '#B3FFFFFF';
const IMAGE_LIGHT_ICON: string = '#FFFFFFFF';
const IMAGE_DARK_PRIMARY: string = '#FF000000';
const IMAGE_DARK_SECONDARY: string = '#99000000';
const IMAGE_DARK_ICON: string = '#FF000000';
const IMAGE_LIGHT_SHADOW: Array<ShadowOptions> = [
  { radius: 10, color: '#26000000', offsetX: 0, offsetY: 1 },
  { radius: 2, color: '#18000000', offsetX: 0, offsetY: 1 }
];
const IMAGE_DARK_SHADOW: Array<ShadowOptions> = [
  { radius: 10, color: '#1AFFFFFF', offsetX: 0, offsetY: 1 },
  { radius: 2, color: '#10FFFFFF', offsetX: 0, offsetY: 1 }
];
const WEB_LIGHT_PRIMARY: string = '#FFFFFFFF';
const WEB_LIGHT_SECONDARY: string = '#99FFFFFF';
const WEB_DARK_PRIMARY: string = '#FF000000';
const WEB_DARK_SECONDARY: string = '#99000000';
const BACKDROP_LIGHTNESS_THRESHOLD: number = 0.56;
const REPRESENTATIVE_LIGHT_LUMINANCE: number = 0.72;
const REPRESENTATIVE_DARK_LUMINANCE: number = 0.28;

export function createDefaultBrowserForegroundPresentation(): BrowserForegroundPresentation {
  return {
    tone: 'dark',
    primaryTextColor: '#FF000000',
    secondaryTextColor: '#99000000',
    iconColor: '#FF000000',
    iconTone: 'light',
    textShadow: [],
    freshnessKey: 'default'
  };
}

export class BrowserForegroundPresentationViewModel {
  resolveHomePresentation(
    input: BrowserHomeForegroundPresentationInput
  ): BrowserForegroundPresentation {
    if (input.foregroundBackdropSource === 'web_home') {
      return this.resolveWebHomePresentation(input);
    }
    if (input.foregroundBackdropSource === 'theme') {
      return this.resolveThemePresentation(input);
    }
    const tone = this.resolveHomeTone(input.wallpaperState, input.themeBackgroundColor);
    if (input.wallpaperState.kind === 'image') {
      return this.resolveImagePresentation(tone, `home:${input.wallpaperState.assetId}:${input.wallpaperState.updatedAt}`);
    }
    return this.resolveThemePresentation(input);
  }

  private resolveWebHomePresentation(
    input: BrowserHomeForegroundPresentationInput
  ): BrowserForegroundPresentation {
    const appearance = input.backdropAppearanceState;
    if (appearance === undefined || !appearance.available) {
      return this.resolveThemePresentation(input);
    }
    const fallback = this.resolveWebPresentation(
      appearance.toolbarForegroundTone,
      this.buildWebHomeFreshnessKey(appearance)
    );
    return {
      tone: appearance.toolbarForegroundTone,
      primaryTextColor: this.resolveAppearanceColor(
        appearance.toolbarLabelTextColor,
        fallback.primaryTextColor
      ),
      secondaryTextColor: this.resolveAppearanceColor(
        appearance.toolbarSecondaryTextColor,
        fallback.secondaryTextColor
      ),
      iconColor: this.resolveAppearanceColor(
        appearance.toolbarPrimaryTextColor,
        fallback.iconColor
      ),
      iconTone: fallback.iconTone,
      textShadow: [],
      freshnessKey: fallback.freshnessKey
    };
  }

  private resolveThemePresentation(
    input: BrowserHomeForegroundPresentationInput
  ): BrowserForegroundPresentation {
    const tone = this.resolveThemeTone(input.themeBackgroundColor);
    return {
      tone: tone,
      primaryTextColor: input.themedPrimaryTextColor,
      secondaryTextColor: input.themedSecondaryTextColor,
      iconColor: input.themedSecondaryTextColor,
      iconTone: tone === 'dark' ? 'light' : 'dark',
      textShadow: [],
      freshnessKey: `theme:${tone}:${input.themeBackgroundColor}:${input.themedPrimaryTextColor}:` +
        `${input.themedSecondaryTextColor}`
    };
  }

  resolveWebPresentation(
    tone: BrowserForegroundTone,
    freshnessKey: string
  ): BrowserForegroundPresentation {
    if (tone === 'light') {
      return {
        tone: tone,
        primaryTextColor: WEB_LIGHT_PRIMARY,
        secondaryTextColor: WEB_LIGHT_SECONDARY,
        iconColor: WEB_LIGHT_PRIMARY,
        iconTone: 'dark',
        textShadow: [],
        freshnessKey: freshnessKey
      };
    }
    return {
      tone: tone,
      primaryTextColor: WEB_DARK_PRIMARY,
      secondaryTextColor: WEB_DARK_SECONDARY,
      iconColor: WEB_DARK_PRIMARY,
      iconTone: 'light',
      textShadow: [],
      freshnessKey: freshnessKey
    };
  }

  resolveHomeTone(
    wallpaperState: HomeWallpaperPresentationState,
    themeBackgroundColor: ResourceColor,
    effect?: BrowserForegroundBackdropEffectInput
  ): BrowserForegroundTone {
    const baseTone = this.resolveBaseHomeTone(wallpaperState, themeBackgroundColor);
    const tintOpacity = this.resolveTintOpacity(effect);
    if (tintOpacity <= 0 || effect === undefined) {
      return baseTone;
    }
    const tintColor = this.parseHexColor(`${effect.tintColor}`);
    if (tintColor === undefined) {
      return baseTone;
    }
    const baseLuminance = wallpaperState.kind === 'image'
      ? (baseTone === 'dark' ? REPRESENTATIVE_LIGHT_LUMINANCE : REPRESENTATIVE_DARK_LUMINANCE)
      : this.resolveColorLuminance(this.parseHexColor(`${themeBackgroundColor}`) ?? tintColor);
    const tintLuminance = this.resolveColorLuminance(tintColor);
    const effectiveLuminance = baseLuminance * (1 - tintOpacity) + tintLuminance * tintOpacity;
    return effectiveLuminance >= BACKDROP_LIGHTNESS_THRESHOLD ? 'dark' : 'light';
  }

  private resolveBaseHomeTone(
    wallpaperState: HomeWallpaperPresentationState,
    themeBackgroundColor: ResourceColor
  ): BrowserForegroundTone {
    if (wallpaperState.kind === 'image') {
      return wallpaperState.foregroundTone === 'lightText' ? 'light' : 'dark';
    }
    return this.resolveThemeTone(themeBackgroundColor);
  }

  private resolveThemeTone(themeBackgroundColor: ResourceColor): BrowserForegroundTone {
    const backgroundColor = this.parseHexColor(`${themeBackgroundColor}`);
    if (backgroundColor === undefined) {
      return 'dark';
    }
    return this.resolveColorLuminance(backgroundColor) >= BACKDROP_LIGHTNESS_THRESHOLD ? 'dark' : 'light';
  }

  private resolveAppearanceColor(value: string, fallback: ResourceColor): ResourceColor {
    return value.trim().length > 0 ? value : fallback;
  }

  private buildWebHomeFreshnessKey(appearance: BrowserHomepageBackdropAppearanceState): string {
    return `web-home:${appearance.sourceKey}:${appearance.snapshotSignature}:` +
      `${appearance.algorithmVersion}:${appearance.resolvedThemeMode}:${appearance.updatedAt}`;
  }

  private resolveImagePresentation(
    tone: BrowserForegroundTone,
    freshnessKey: string
  ): BrowserForegroundPresentation {
    if (tone === 'light') {
      return {
        tone: tone,
        primaryTextColor: IMAGE_LIGHT_PRIMARY,
        secondaryTextColor: IMAGE_LIGHT_SECONDARY,
        iconColor: IMAGE_LIGHT_ICON,
        iconTone: 'dark',
        textShadow: IMAGE_LIGHT_SHADOW,
        freshnessKey: freshnessKey
      };
    }
    return {
      tone: tone,
      primaryTextColor: IMAGE_DARK_PRIMARY,
      secondaryTextColor: IMAGE_DARK_SECONDARY,
      iconColor: IMAGE_DARK_ICON,
      iconTone: 'light',
      textShadow: IMAGE_DARK_SHADOW,
      freshnessKey: freshnessKey
    };
  }

  private resolveTintOpacity(effect?: BrowserForegroundBackdropEffectInput): number {
    if (effect === undefined || !Number.isFinite(effect.tintOpacity) || effect.tintOpacity <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, effect.tintOpacity));
  }

  private parseHexColor(value: string): BrowserForegroundRgbColor | undefined {
    let normalized = value.trim().replace('#', '');
    if (/^[0-9a-fA-F]{8}$/.test(normalized)) {
      normalized = normalized.substring(2);
    }
    if (!/^[0-9a-fA-F]{6}$/.test(normalized)) {
      return undefined;
    }
    return {
      r: Number.parseInt(normalized.substring(0, 2), 16) / 255,
      g: Number.parseInt(normalized.substring(2, 4), 16) / 255,
      b: Number.parseInt(normalized.substring(4, 6), 16) / 255
    };
  }

  private resolveColorLuminance(color: BrowserForegroundRgbColor): number {
    return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b;
  }
}
