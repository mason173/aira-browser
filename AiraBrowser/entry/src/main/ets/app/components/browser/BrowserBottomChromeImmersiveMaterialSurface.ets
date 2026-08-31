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

      if (this.resolveBorderWidth() > 0) {
        Stack()
          .width('100%')
          .height('100%')
          .borderRadius(this.resolveSurfaceRadius())
          .border({
            width: this.resolveBorderWidth(),
            color: this.materialBorderColor
          })
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.surfaceWidth)
    .height(this.surfaceHeight)
    .borderRadius(this.resolveSurfaceRadius())
    .clip(true)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: this.materialTint,
      colorInvert: true,
      applyShadow: true,
      interactive: true,
      lightEffect: {
        color: BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR
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

  private resolveOverlayOpacity(): number {
    if (!Number.isFinite(this.overlayOpacity)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.overlayOpacity));
  }
}
