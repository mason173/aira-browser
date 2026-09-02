import { uiMaterial } from '@kit.ArkUI';
import {
  BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR,
  BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT
} from './BrowserFloatingGlassMaterialTokens';

@Component
export struct BrowserBottomChromeImmersiveMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop materialTint: ResourceColor = BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  @Prop materialStyle: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THIN;
  @Prop materialShadowEnabled: boolean = true;
  @Prop materialInteractive: boolean = true;
  @Prop materialLightEffectEnabled: boolean = true;
  @Prop materialLightEffectColor: ResourceColor = BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR;
  @Prop edgeHighlightWidth: number = 0;
  @Prop edgeHighlightColor: ResourceColor = $r('sys.color.ohos_id_color_background_transparent');
  @Prop overlayColor: ResourceColor | undefined = undefined;
  @Prop overlayOpacity: number = 0;
  @Prop materialBorderWidth: number = 0;
  @Prop materialBorderColor: ResourceColor = $r('sys.color.ohos_id_color_background_transparent');
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.overlayColor !== undefined && this.resolveOverlayOpacity() > 0) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.overlayColor as ResourceColor)
          .opacity(this.resolveOverlayOpacity())
          .hitTestBehavior(HitTestMode.None)
      }

      this.content()

      if (this.resolveEdgeHighlightWidth() > 0) {
        Stack()
          .width('100%')
          .height('100%')
          .borderRadius(this.resolveSurfaceRadius())
          .border({
            width: this.resolveEdgeHighlightWidth(),
            color: this.resolveEdgeHighlightColor()
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .borderRadius(this.resolveSurfaceRadius())
    .clip(true)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: this.materialStyle,
      materialColor: this.materialTint,
      colorInvert: true,
      applyShadow: this.materialShadowEnabled,
      interactive: this.materialInteractive,
      lightEffect: {
        color: this.materialLightEffectEnabled ? this.materialLightEffectColor : '#00000000'
      }
    }))
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

  private resolveEdgeHighlightWidth(): number {
    return this.edgeHighlightWidth > 0 ? Math.max(0, this.edgeHighlightWidth) : this.resolveBorderWidth();
  }

  private resolveEdgeHighlightColor(): ResourceColor {
    return this.edgeHighlightWidth > 0 ? this.edgeHighlightColor : this.materialBorderColor;
  }

  private resolveOverlayOpacity(): number {
    if (!Number.isFinite(this.overlayOpacity)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.overlayOpacity));
  }
}
