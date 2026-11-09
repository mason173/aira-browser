import { JuIcon } from './JuIcon'
import { JuContextMenuItem } from './JuContextMenuItem'
import { juFormSeparator } from './JuFormSeparator'

/**
 * 长按菜单的正文。
 *
 * 只负责画一行行「图标 + 文字」：不自己承载弹出与定位，由宿主用
 * `bindContextMenu(content, ResponseType.LongPress)` 挂在要长按的节点上——
 * 那个接口会把菜单显示在按压位置，正是长按菜单该有的行为。
 *
 * 危险项（`danger`）与上面的常规项之间自动加一条分割线，危险项文字与图标转警示色。
 * 常规项之间不加线：与系统长按菜单一致，图标列本身已经形成视觉分隔。
 *
 * 用法：
 * ```typescript
 * private menu: JuContextMenuItem[] = [
 *   new JuContextMenuItem('copy', '复制验证码', $r('app.media.ic_copy')),
 *   new JuContextMenuItem('edit', '编辑账号', $r('app.media.pencil_edit')),
 *   new JuContextMenuItem('delete', '删除账号', $r('app.media.ic_trash'), true)
 * ]
 *
 * // 挂在要长按的节点上
 * Column() { ... }
 *   .bindContextMenu(this.Menu, ResponseType.LongPress, {
 *     enableArrow: false, backgroundColor: Color.Transparent
 *   })
 *
 * @Builder
 * Menu() {
 *   JuContextMenu({ items: this.menu, onSelect: (key: string): void => { this.onMenu(key) } })
 * }
 * ```
 */
@Component
export struct JuContextMenu {
  @Prop items: JuContextMenuItem[] = []
  onSelect: (key: string) => void = (_key: string): void => {}

  /** 危险组的第一项：在它上面补一条分割线。 */
  private startsDangerGroup(index: number): boolean {
    if (index <= 0 || index >= this.items.length) {
      return false
    }
    return this.items[index].danger && !this.items[index - 1].danger
  }

  private rowColor(danger: boolean): Resource {
    return danger ? $r('app.color.destructive') : $r('app.color.foreground')
  }

  /**
   * 图标比文字浅一档。库内图标是 2.2 描边，与正文同色时显得比文字重，
   * 看着比文字"粗"；转成中性色后就与正文的分量匹配了。
   */
  private iconColor(danger: boolean): Resource {
    return danger ? $r('app.color.destructive') : $r('app.color.muted_foreground')
  }

  build() {
    Column() {
      ForEach(this.items, (item: JuContextMenuItem, index: number) => {
        if (this.startsDangerGroup(index)) {
          juFormSeparator()
        }
        Row() {
          if (item.icon !== null) {
            JuIcon({
              name: item.icon,
              color: this.iconColor(item.danger),
              side: $r('app.float.icon_size')
            })
              .margin({ right: $r('app.float.gap_icon') })
          }
          Text(item.label)
            .layoutWeight(1)
            .fontSize($r('app.float.font_size_body'))
            .lineHeight($r('app.float.line_height_body'))
            .fontColor(this.rowColor(item.danger))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height($r('app.float.row_height'))
        .alignItems(VerticalAlign.Center)
        .padding({
          left: $r('app.float.padding_row_icon'),
          right: $r('app.float.padding_row_icon')
        })
        .borderRadius($r('app.float.radius_tooltip'))
        .stateStyles({
          pressed: { .backgroundColor($r('app.color.row_pressed')) },
          normal: { .backgroundColor(Color.Transparent) }
        })
        .onClick((): void => {
          this.onSelect(item.key)
        })
      }, (item: JuContextMenuItem, index: number) => `${index}-${item.key}`)
    }
    // 固定宽度：菜单撑满屏会显得又宽又方（圆角占比随之变小）。
    .width($r('app.float.menu_width'))
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.menu_radius'))
    // 卡片自己留一圈内距，但不额外往外扩：弹窗盒子必须与卡片对齐，
    // 否则弹出容器自带的一层淡底/描边会从缝里透出来，看着像菜单外面套了一层。
    .padding($r('app.float.gap_button_text'))
    // 投影由**宿主在弹层上**给（见组件文档）：把它画在这张卡片上没用——
    // 宿主把菜单挂在列表卡片上，而卡片外面通常有 clip(true) 的容器
    // （例如 JuReorderList 的自定义行），画在自身边界之外的投影会被裁掉。
    // 弹层是平台单独绘制的层，投影画在弹层上才不会被裁。
  }
}
