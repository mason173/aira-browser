import {
  FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE,
  FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR
} from '../common/FloatingGlassMaterialTokens';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT } from './BrowserFloatingGlassMaterialTokens';

@Component
export struct BrowserFloatingGlassMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop tintColor: ResourceColor = BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  @Prop fallbackColor: ResourceColor = $r('app.color.surface_glass_background');
  @Prop materialStyle: number = FLOATING_GLASS_MATERIAL_IMMERSIVE_STYLE;
  @Prop lightEffectColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_EFFECT_COLOR;
  @Prop materialShadowEnabled: boolean = false;
  @Prop materialInteractive: boolean = true;
  @Prop materialEnabled: boolean = false;
  @Prop backgroundBlurEnabled: boolean = true;
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
        fallbackColor: this.fallbackColor,
        materialStyle: this.materialStyle,
        lightEffectColor: this.lightEffectColor,
        materialShadowEnabled: this.materialShadowEnabled,
        materialInteractive: this.materialInteractive,
        materialEnabled: this.materialEnabled,
        backgroundBlurEnabled: this.backgroundBlurEnabled,
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
