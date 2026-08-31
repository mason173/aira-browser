import { uiMaterial } from '@kit.ArkUI';

export const FLOATING_GLASS_MATERIAL_BLUR_STYLE: BlurStyle = BlurStyle.COMPONENT_THIN;
export const FLOATING_GLASS_MATERIAL_LIGHT_TINT: ResourceColor = '#18FFFFFF';
export const FLOATING_GLASS_MATERIAL_DARK_TINT: ResourceColor = '#18000000';
export const FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR: ResourceColor = '#25FFFFFF';

let cachedFloatingGlassMaterialAvailable: boolean | undefined = undefined;

export function resolveFloatingGlassMaterialTintForMode(resolvedThemeMode: string): ResourceColor {
  return resolvedThemeMode === 'dark' ?
    FLOATING_GLASS_MATERIAL_DARK_TINT :
    FLOATING_GLASS_MATERIAL_LIGHT_TINT;
}

export function createFloatingGlassMaterial(tintColor: ResourceColor): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THIN,
    materialColor: tintColor,
    colorInvert: true,
    applyShadow: true,
    interactive: true,
    lightEffect: {
      color: FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR
    }
  });
}

export function isFloatingGlassMaterialAvailable(): boolean {
  if (cachedFloatingGlassMaterialAvailable !== undefined) {
    return cachedFloatingGlassMaterialAvailable;
  }
  try {
    cachedFloatingGlassMaterialAvailable = uiMaterial.isImmersiveMaterialSupported() &&
      uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
  } catch (_error) {
    cachedFloatingGlassMaterialAvailable = false;
  }
  return cachedFloatingGlassMaterialAvailable;
}
