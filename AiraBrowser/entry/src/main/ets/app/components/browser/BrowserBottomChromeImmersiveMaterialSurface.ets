import { uiMaterial } from '@kit.ArkUI';
import {
  BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR,
  BROWSER_FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS,
  BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE,
  BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT
} from './BrowserFloatingGlassMaterialTokens';
import {
  createFloatingGlassMaterial,
  isFloatingGlassMaterialAvailable
} from '../common/FloatingGlassMaterialTokens';

@Component
export struct BrowserBottomChromeImmersiveMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop materialTint: ResourceColor = BROWSER_FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  @Prop fallbackColor: ResourceColor = $r('app.color.browser_bottom_toolbar_glass_background');
  @Prop materialStyle: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.THIN;
  @Prop materialShadowEnabled: boolean = false;
  @Prop materialInteractive: boolean = true;
  @Prop materialLightEffectEnabled: boolean = true;
  @Prop materialLightEffectColor: ResourceColor = BROWSER_BOTTOM_CHROME_IMMERSIVE_LIGHT_EFFECT_COLOR;
  @Prop materialEnabled: boolean = false;
  @Prop edgeHighlightWidth: number = 0;
  @Prop edgeHighlightColor: ResourceColor = $r('sys.color.ohos_id_color_background_transparent');
  @Prop overlayColor: ResourceColor | undefined = undefined;
  @Prop overlayOpacity: number = 0;
  @Prop materialBorderWidth: number = 0;
  @Prop materialBorderColor: ResourceColor = $r('sys.color.ohos_id_color_background_transparent');
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
    // The fallback blur is mutually exclusive with systemMaterial: custom browser
    // chrome is not a supported immersive-material placement on every device.
    .backgroundBlurStyle(
      this.shouldApplyMaterial() ? BlurStyle.NONE : BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE,
      BROWSER_FLOATING_GLASS_MATERIAL_ADAPTIVE_OPTIONS
    )
    .systemMaterial(this.shouldApplyMaterial() ? createFloatingGlassMaterial(
      this.materialTint,
      this.materialStyle,
      this.materialLightEffectEnabled ? this.materialLightEffectColor : null,
      this.materialShadowEnabled,
      this.materialInteractive
    ) : undefined)
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

  private shouldApplyMaterial(): boolean {
    return this.materialEnabled && isFloatingGlassMaterialAvailable();
  }
}
