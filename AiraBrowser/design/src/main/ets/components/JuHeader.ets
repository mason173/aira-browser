import { JuIconButton } from './JuIconButton'
import { JuTooltip } from './JuTooltip'

/** 顶栏。左边菜单图标加标题，右边一排图标按钮。 */
@Component
export struct JuHeader {
  @Prop name: string = ''
  /** 左边的主图标。需要交互时由调用方传入 onMenu。 */
  @Prop menuIcon: Resource = $r('app.media.menu_01_header')
  @Prop menuIconColor: ResourceColor = $r('app.color.foreground')
  @Prop menuIconSide: Resource = $r('app.float.icon_size')
  @Prop menuIconPlated: boolean = false
  @Prop menuIconInsetPlate: boolean = false
  @Prop menuIconPlateColor: ResourceColor = $r('app.color.secondary')
  @Prop menuIconPlateSide: Resource = $r('app.float.icon_button_size')
  @Prop menuIconPlateRadius: Resource = $r('app.float.icon_button_radius')
  @Prop menuIconPlateOpacity: number = 1
  /** 圆底里放文字（emoji）时用它。非空就盖过 menuIcon。 */
  @Prop menuIconPlateText: string = ''
  onMenuPlateAreaChange: (area: Area) => void = (_area: Area) => {}
  @Prop menuIconVisible: boolean = true
  /** 左边徽章上挂的新手气泡（只出现一次那种）。空字符串不挂。 */
  @Prop menuTip: string = ''
  @Prop menuTipOpen: boolean = false
  onMenuTipClose: () => void = () => {}
  /** 右边几个图标按钮，按顺序排 */
  @Prop actions: Array<Resource> = []
  onMenu: () => void = () => {}
  onAction: (index: number) => void = () => {}

  build() {
    Row() {
      if (this.menuIconVisible) {
        if (this.menuTip.length > 0) {
          JuTooltip({
            text: this.menuTip,
            open: this.menuTipOpen,
            placement: Placement.Bottom,
            onClose: () => this.onMenuTipClose()
          }) {
            this.MenuButton()
          }
        } else {
          this.MenuButton()
        }
      } else {
        Blank()
          .width($r('app.float.icon_button_size'))
          .height($r('app.float.icon_button_size'))
      }

      Text(this.name)
        .fontSize($r('app.float.font_size_display'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Row() {
        if (this.actions.length > 0) {
          JuIconButton({
            name: this.actions[0],
            onTap: () => this.onAction(0)
          })
        }
        if (this.actions.length > 1) {
          JuIconButton({
            name: this.actions[1],
            onTap: () => this.onAction(1)
          })
        }
        if (this.actions.length > 2) {
          JuIconButton({
            name: this.actions[2],
            onTap: () => this.onAction(2)
          })
        }
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: $r('app.float.padding_header_actions'),
      right: $r('app.float.padding_header_actions')
    })
  }

  @Builder
  MenuButton() {
    JuIconButton({
      name: this.menuIcon,
      color: this.menuIconColor,
      iconSide: this.menuIconSide,
      plated: this.menuIconPlated,
      insetPlate: this.menuIconInsetPlate,
      plateColor: this.menuIconPlateColor,
      plateSide: this.menuIconPlateSide,
      plateRadius: this.menuIconPlateRadius,
      plateOpacity: this.menuIconPlateOpacity,
      plateText: this.menuIconPlateText,
      onPlateAreaChange: (area: Area) => this.onMenuPlateAreaChange(area),
      onTap: () => this.onMenu()
    })
  }
}
