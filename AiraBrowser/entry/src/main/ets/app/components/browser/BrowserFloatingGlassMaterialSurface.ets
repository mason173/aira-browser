import { uiMaterial } from '@kit.ArkUI';
import { FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR } from '../common/FloatingGlassMaterialTokens';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT } from './BrowserFloatingGlassMaterialTokens';

@Component
export struct BrowserFloatingGlassMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop tintColor: ResourceColor = BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  @Prop materialStyle: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THIN;
  @Prop lightEffectColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR;
  @Prop materialShadowEnabled: boolean = true;
  @Prop materialInteractive: boolean = true;
  @Prop overlayColor: ResourceColor | undefined = undefined;
  @Prop overlayOpacity: number = 0;
  @Prop materialBorderWidth: number = 0;
  @Prop materialBorderColor: ResourceColor = '#00000000';
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack() {
      FloatingGlassMaterialSurface({
        surfaceWidth: this.surfaceWidth,
        surfaceHeight: this.surfaceHeight,
        surfaceRadius: this.surfaceRadius,
        tintColor: this.tintColor,
        materialStyle: this.materialStyle,
        lightEffectColor: this.lightEffectColor,
        materialShadowEnabled: this.materialShadowEnabled,
        materialInteractive: this.materialInteractive,
        overlayColor: this.overlayColor,
        overlayOpacity: this.overlayOpacity,
        materialBorderWidth: this.materialBorderWidth,
        materialBorderColor: this.materialBorderColor
      }) {
        this.content()
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
  }

  @Builder
  private emptyBuilder() {
  }
}
