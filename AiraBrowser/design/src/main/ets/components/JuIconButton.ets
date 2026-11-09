import { JuIcon } from './JuIcon'
import { JuAvatar } from './JuAvatar'

/** 图标按钮。统一提供 48vp 触控区和按压缩放反馈。 */
@Component
export struct JuIconButton {
  @Prop name: Resource = $r('app.media.ellipsis')
  /** 系统圆形操作由 JuCircleButton 传入，普通内容区图标仍用 name。 */
  @Prop symbol: Resource | null = null
  @Prop color: ResourceColor = $r('app.color.foreground')
  @Prop iconSide: Resource = $r('app.float.icon_size')
  /** 按钮边长。默认是 48vp 触控区；关闭按钮会传更小的尺寸。 */
  @Prop side: Resource = $r('app.float.icon_button_size')
  @Prop radius: Resource = $r('app.float.icon_button_radius')
  /** 为真时按钮本身就是一圈圆底。默认 secondary，可传别的底色。 */
  @Prop plated: boolean = false
  @Prop plateColor: ResourceColor = $r('app.color.secondary')
  /** 徽章的视觉尺寸。仅在 insetPlate 模式下使用，触控区仍由 side 控制。 */
  @Prop insetPlate: boolean = false
  @Prop plateSide: Resource = $r('app.float.icon_button_size')
  @Prop plateRadius: Resource = $r('app.float.icon_button_radius')
  @Prop plateOpacity: number = 1
  /** 圆底里放文字（emoji）时用它。非空就盖过 name 图标。 */
  @Prop plateText: string = ''
  /**
   * 圆底里放头像图（账号登录后的头像）。非空就盖过 name 和 plateText，
   * 铺满整个圆底、按半径裁圆。配合 insetPlate 用。
   */
  @Prop avatarUrl: string = ''
  onPlateAreaChange: (area: Area) => void = (_area: Area) => {}
  @State pressedScale: number = 1
  onTap: () => void = () => {}
  onPressIn: () => void = () => {}
  onPressOut: () => void = () => {}
  onPressCancel: () => void = () => {}

  build() {
    Column() {
      if (this.insetPlate) {
        if (this.avatarUrl.length > 0) {
          JuAvatar({
            url: this.avatarUrl,
            side: this.plateSide,
            radius: this.plateRadius,
            plate: this.plateColor,
            iconColor: this.color,
            iconSide: this.iconSide
          })
        } else {
          Column() {
            if (this.plateText.length > 0) {
              Text(this.plateText)
                .fontSize($r('app.float.font_size_body'))
            } else {
              this.Icon()
            }
          }
            .width(this.plateSide)
            .height(this.plateSide)
            .borderRadius(this.plateRadius)
            .backgroundColor(this.plateColor)
            .opacity(this.plateOpacity)
            .justifyContent(FlexAlign.Center)
            .onAreaChange((_old: Area, next: Area) => {
              this.onPlateAreaChange(next)
            })
        }
      } else {
        this.Icon()
      }
    }
    .width(this.side)
    .height(this.side)
    .borderRadius(this.radius)
    .backgroundColor(this.plated ? this.plateColor : Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .scale({ x: this.pressedScale, y: this.pressedScale })
    .animation({ duration: 100, curve: Curve.EaseOut })
    .onTouch((event?: TouchEvent) => {
      if (!event) {
        return
      }
      if (event.type === TouchType.Down) {
        this.pressedScale = 0.92
        this.onPressIn()
      } else if (event.type === TouchType.Up) {
        this.pressedScale = 1
        this.onPressOut()
      } else if (event.type === TouchType.Cancel) {
        this.pressedScale = 1
        this.onPressCancel()
      }
    })
    .onClick(() => {
      this.onTap()
    })
  }

  @Builder
  Icon() {
    if (this.symbol !== null) {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSide)
        .fontColor([this.color])
    } else {
      JuIcon({ name: this.name, color: this.color, side: this.iconSide })
    }
  }
}
