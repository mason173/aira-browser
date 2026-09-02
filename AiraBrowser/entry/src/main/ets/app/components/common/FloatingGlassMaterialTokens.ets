import { uiMaterial } from '@kit.ArkUI';

export const FLOATING_GLASS_MATERIAL_BLUR_STYLE: BlurStyle = BlurStyle.COMPONENT_THIN;
export const FLOATING_GLASS_MATERIAL_LIGHT_TINT: ResourceColor = '#18FFFFFF';
export const FLOATING_GLASS_MATERIAL_DARK_TINT: ResourceColor = '#18000000';
export const FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR: ResourceColor = '#25FFFFFF';
export const FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THIN;

let cachedFloatingGlassMaterialAvailable: boolean | undefined = undefined;

export function resolveFloatingGlassMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolvedThemeMode === 'dark' ?
    FLOATING_GLASS_MATERIAL_DARK_TINT :
    FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}

export function createFloatingGlassMaterial(
  tintColor: ResourceColor,
  style: uiMaterial.ImmersiveStyle = FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE,
  lightEffectColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR,
  applyShadow: boolean = true,
  interactive: boolean = true
): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: style,
    materialColor: tintColor,
    colorInvert: true,
    applyShadow: applyShadow,
    interactive: interactive,
    lightEffect: {
      color: lightEffectColor
    }
  });
}

export function isFloatingGlassMaterialAvailable(): boolean {
  if (cachedFloatingGlassMaterialAvailable !== undefined) {
    return cachedFloatingGlassMaterialAvailable;
  }
  try {
    const materialState = uiMaterial.getMaterialInfo().state;
    cachedFloatingGlassMaterialAvailable = materialState !== uiMaterial.MaterialState.DISABLE;
  } catch (_error) {
    cachedFloatingGlassMaterialAvailable = false;
  }
  return cachedFloatingGlassMaterialAvailable;
}
