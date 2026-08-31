import {
  createFloatingGlassMaterial,
  FLOATING_GLASS_MATERIAL_LIGHT_TINT,
  isFloatingGlassMaterialAvailable
} from './FloatingGlassMaterialTokens';

@Component
export struct FloatingGlassMaterialSurface {
  @Prop surfaceWidth: Length = 1;
  @Prop surfaceHeight: Length = 1;
  @Prop surfaceRadius: number = 0;
  @Prop tintColor: ResourceColor = FLOATING_GLASS_MATERIAL_LIGHT_TINT;
  @Prop overlayColor: ResourceColor | undefined = undefined;
  @Prop overlayOpacity: number = 0;
  @Prop materialBorderWidth: number = 0;
  @Prop materialBorderColor: ResourceColor = '#00000000';
  @BuilderParam content: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (!isFloatingGlassMaterialAvailable()) {
        Stack()
          .width('100%')
          .height('100%')
          .backgroundColor(this.tintColor)
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
    .systemMaterial(isFloatingGlassMaterialAvailable() ? createFloatingGlassMaterial(this.tintColor) : undefined)
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
