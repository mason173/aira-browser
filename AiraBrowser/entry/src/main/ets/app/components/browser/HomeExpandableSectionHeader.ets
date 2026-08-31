import {
  HOME_WALLPAPER_APPEARANCE_TRANSITION_MS
} from '../../../core/wallpaper/HomeWallpaperPresentationTokens';

@Component
export struct HomeExpandableSectionHeader {
  @Prop title: string = '';
  @Prop expanded: boolean = true;
  @Prop collapsible: boolean = true;
  @Prop toggleEnabled: boolean = true;
  @Prop leftInset: number = 16;
  @Prop rightInset: number = 16;
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop pressedBackgroundColor: ResourceColor = '#DDE4EC';
  @Prop pressedBackdropBlurRadius: number = 0;
  @Prop textShadow: Array<ShadowOptions> = [];
  @State private pressed: boolean = false;

  onToggle: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvePrimaryTextColor())
        .textShadow(this.textShadow)
        .animation({ duration: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS, curve: Curve.EaseInOut })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.collapsible) {
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolveSecondaryTextColor()])
          .rotate({ angle: this.expanded ? 0 : -90 })
          .animation({ duration: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS, curve: Curve.EaseInOut })
      }
    }
    .width('100%')
    .padding({ left: this.leftInset, right: this.rightInset, top: 8, bottom: 12 })
    .backgroundColor(this.resolveBackgroundColor())
    .backdropBlur(this.resolveBackdropBlurRadius())
    .borderRadius(12)
    .clip(true)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.collapsible && this.toggleEnabled) {
        this.onToggle();
      }
    })
  }

  private updatePressed(type: TouchType): void {
    if (!this.collapsible || !this.toggleEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed
      ? this.resolvePressedBackgroundColor()
      : $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    return this.pressedBackgroundColor;
  }

  private resolveBackdropBlurRadius(): number {
    return this.pressed ? Math.max(0, this.pressedBackdropBlurRadius) : 0;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor;
  }

}
