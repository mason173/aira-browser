import {
  createFloatingGlassMaterial,
  FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS,
  FLOATING_GLASS_MATERIAL_BLUR_STYLE,
  FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE,
  FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR,
  FLOATING_GLASS_MATERIAL_LIGHT_TINT,
  isFloatingGlassMaterialAvailable,
  systemMaterialModifier
} from './FloatingGlassMaterialTokens';

@Component
export struct FloatingGlassMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop tintColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  // Keep a visible glass-like surface when API 26 material is unavailable or opt-out.
  @Prop fallbackColor: ResourceColor = $r('app.color.surface_glass_background');
  @Prop materialStyle: number = FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE;
  @Prop lightEffectColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR;
  @Prop materialShadowEnabled: boolean = false;
  @Prop materialInteractive: boolean = true;
  @Prop materialEnabled: boolean = false;
  @Prop backgroundBlurEnabled: boolean = false;
  @Prop overlayColor: ResourceColor | undefined = undefined;
  @Prop overlayOpacity: number = 0;
  @Prop materialBorderWidth: number = 0;
  @Prop materialBorderColor: ResourceColor = '#00000000';
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!this.shouldApplyMaterial()) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.fallbackColor)
          .hitTestBehavior(HitTestMode.None)
      }

      if (this.overlayColor !== undefined && this.resolveOverlayOpacity() > 0) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.overlayColor as ResourceColor)
          .opacity(this.resolveOverlayOpacity())
          .hitTestBehavior(HitTestMode.None)
      }

      this.content()

      if (this.resolveBorderWidth() > 0) {
        Stack()
          .width('100%')
          .height('100%')
          .border({
            width: this.resolveBorderWidth(),
            color: this.materialBorderColor
          })
          .borderRadius(this.resolveSurfaceRadius())
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .borderRadius(this.resolveSurfaceRadius())
    .clip(true)
    .backgroundBlurStyle(
      this.shouldApplyBackgroundBlur() ? FLOATING_GLASS_MATERIAL_BLUR_STYLE : BlurStyle.NONE,
      FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS
    )
    .attributeModifier(systemMaterialModifier(this.shouldApplyMaterial() ? createFloatingGlassMaterial(
      this.tintColor,
      this.materialStyle,
      this.lightEffectColor,
      this.materialShadowEnabled,
      this.materialInteractive
    ) : undefined))
  }

  @Builder
  private emptyBuilder() {
  }

  private resolveSurfaceRadius(): number {
    return Math.max(0, this.surfaceRadius);
  }

  private resolveBorderWidth(): number {
    return Math.max(0, this.materialBorderWidth);
  }

  private resolveOverlayOpacity(): number {
    if (!Number.isFinite(this.overlayOpacity)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.overlayOpacity));
  }

  private shouldApplyMaterial(): boolean {
    return this.materialEnabled && isFloatingGlassMaterialAvailable();
  }

  private shouldApplyBackgroundBlur(): boolean {
    return this.backgroundBlurEnabled && !this.shouldApplyMaterial();
  }
}
