import { deviceInfo } from '@kit.BasicServicesKit';
import {
  createImmersiveMaterial,
  IMMERSIVE_STYLE_STANDARD,
  IMMERSIVE_STYLE_THICK,
  IMMERSIVE_STYLE_ULTRA_THICK,
  isKitMaterialEnabled,
  systemMaterialModifier as createSystemMaterialModifier,
  ImmersiveMaterialHandle,
  ImmersiveStyleHandle
} from './ArkUiMaterialAccess';

export function systemMaterialModifier(
  material: ImmersiveMaterialHandle | undefined
): AttributeModifier<CommonAttribute> {
  return createSystemMaterialModifier(material);
}

export const IMMERSIVE_MATERIAL_MIN_API_VERSION: number = 26;
export const FLOATING_GLASS_MATERIAL_BLUR_STYLE: BlurStyle = BlurStyle.COMPONENT_THIN;
export const FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS: BackgroundBlurStyleOptions = {
  adaptiveColor: AdaptiveColor.AVERAGE,
  policy: BlurStyleActivePolicy.ALWAYS_ACTIVE
};
export const FLOATING_GLASS_MATERIAL_LIGHT_TINT: ResourceColor = '#18FFFFFF';
export const FLOATING_GLASS_MATERIAL_DARK_TINT: ResourceColor = '#18000000';
export const FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR: ResourceColor = '#25FFFFFF';
export const FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE: ImmersiveStyleHandle = IMMERSIVE_STYLE_STANDARD;
export const FLOATING_GLASS_MATERIAL_THICK_STYLE: ImmersiveStyleHandle = IMMERSIVE_STYLE_THICK;
export const FLOATING_GLASS_MATERIAL_ULTRA_THICK_STYLE: ImmersiveStyleHandle = IMMERSIVE_STYLE_ULTRA_THICK;

let cachedFloatingGlassMaterialAvailable: boolean | undefined = undefined;

export function resolveFloatingGlassMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolvedThemeMode === 'dark' ?
    FLOATING_GLASS_MATERIAL_DARK_TINT :
    FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}

export function createFloatingGlassMaterial(
  tintColor: ResourceColor,
  style: ImmersiveStyleHandle = FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE,
  lightEffectColor: ResourceColor | null = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR,
  applyShadow: boolean = true,
  interactive: boolean = true
): ImmersiveMaterialHandle {
  return createImmersiveMaterial(style, tintColor, lightEffectColor, applyShadow, interactive);
}

export function createFloatingGlassMaterialIfAvailable(
  tintColor: ResourceColor,
  style: ImmersiveStyleHandle = FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE,
  lightEffectColor: ResourceColor | null = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR,
  applyShadow: boolean = true,
  interactive: boolean = true
): ImmersiveMaterialHandle | undefined {
  return isFloatingGlassMaterialAvailable() ?
    createFloatingGlassMaterial(tintColor, style, lightEffectColor, applyShadow, interactive) :
    undefined;
}

export function resolveFloatingGlassMaterialBackgroundColor(
  fallbackColor: ResourceColor
): ResourceColor {
  return isFloatingGlassMaterialAvailable() ? Color.Transparent : fallbackColor;
}

export function isFloatingGlassMaterialAvailable(): boolean {
  if (cachedFloatingGlassMaterialAvailable !== undefined) {
    return cachedFloatingGlassMaterialAvailable;
  }
  try {
    if (deviceInfo.sdkApiVersion < IMMERSIVE_MATERIAL_MIN_API_VERSION) {
      cachedFloatingGlassMaterialAvailable = false;
      return cachedFloatingGlassMaterialAvailable;
    }
    cachedFloatingGlassMaterialAvailable = isKitMaterialEnabled();
  } catch (_error) {
    cachedFloatingGlassMaterialAvailable = false;
  }
  return cachedFloatingGlassMaterialAvailable;
}
