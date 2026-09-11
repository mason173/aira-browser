import { uiMaterial } from '@kit.ArkUI';

export type ImmersiveMaterialHandle = uiMaterial.ImmersiveMaterial;
export type ImmersiveStyleHandle = uiMaterial.ImmersiveStyle;

export const IMMERSIVE_STYLE_STANDARD: ImmersiveStyleHandle = 1 as uiMaterial.ImmersiveStyle;
export const IMMERSIVE_STYLE_THICK: ImmersiveStyleHandle = 3 as uiMaterial.ImmersiveStyle;
export const IMMERSIVE_STYLE_ULTRA_THICK: ImmersiveStyleHandle = 4 as uiMaterial.ImmersiveStyle;

class SystemMaterialAttributeModifier implements AttributeModifier<CommonAttribute> {
  private readonly material: ImmersiveMaterialHandle | undefined;

  constructor(material: ImmersiveMaterialHandle | undefined) {
    this.material = material;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    instance.systemMaterial(this.material);
  }
}

export function createImmersiveMaterial(
  style: ImmersiveStyleHandle,
  materialColor?: ResourceColor,
  lightEffectColor: ResourceColor | null = null,
  applyShadow: boolean = true,
  interactive: boolean = true
): ImmersiveMaterialHandle {
  return new uiMaterial.ImmersiveMaterial({
    style: style,
    materialColor: materialColor,
    colorInvert: false,
    applyShadow: applyShadow,
    interactive: interactive,
    lightEffect: lightEffectColor === null ? null : {
      color: lightEffectColor
    }
  });
}

export function createDialogImmersiveMaterial(style: ImmersiveStyleHandle): ImmersiveMaterialHandle {
  return new uiMaterial.ImmersiveMaterial({
    style: style,
    applyShadow: true,
    interactive: false
  });
}

export function isKitMaterialEnabled(): boolean {
  return uiMaterial.getMaterialInfo().state !== uiMaterial.MaterialState.DISABLE;
}

export function applyCommonSystemMaterial(
  instance: CommonAttribute,
  material: ImmersiveMaterialHandle | undefined
): void {
  instance.systemMaterial(material);
}

export function systemMaterialModifier(
  material: ImmersiveMaterialHandle | undefined
): AttributeModifier<CommonAttribute> {
  return new SystemMaterialAttributeModifier(material);
}

export function dialogSystemMaterialField(
  material: ImmersiveMaterialHandle | undefined
): Record<string, ImmersiveMaterialHandle | undefined> {
  const fields: Record<string, ImmersiveMaterialHandle | undefined> =
    new Object() as Record<string, ImmersiveMaterialHandle | undefined>;
  if (material !== undefined) {
    fields.systemMaterial = material;
  }
  return fields;
}

export function assignDialogSystemMaterial(
  params: Object,
  material: ImmersiveMaterialHandle | undefined
): void {
  (params as Record<string, ImmersiveMaterialHandle | undefined>).systemMaterial = material;
}
