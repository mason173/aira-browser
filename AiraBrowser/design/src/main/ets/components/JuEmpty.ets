import { JuIcon } from './JuIcon'

/** 空状态：灰底圆圈衬线性图标，配半粗主标题与可选灰色说明。 */
@Component
export struct JuEmpty {
  /** 主标题，如「还没有订阅」。 */
  @Prop title: string = ''
  /** 标题下的灰色说明；留空不渲染。 */
  @Prop note: string = ''
  /** 圆圈里的线性图标。 */
  @Prop icon: Resource = $r('app.media.ic_bell')
  /** 内嵌空状态只占内容自身高度，整页空状态默认撑满并居中。 */
  @Prop compact: boolean = false

  build() {
    Column() {
      Column() {
        JuIcon({
          name: this.icon,
          color: $r('app.color.secondary_foreground'),
          side: $r('app.float.empty_badge_icon_size')
        })
      }
      .width($r('app.float.empty_badge_size'))
      .height($r('app.float.empty_badge_size'))
      .borderRadius('50%')
      .backgroundColor($r('app.color.secondary'))
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ bottom: $r('app.float.empty_badge_gap') })

      Text(this.title)
        .fontSize($r('app.float.font_size_title'))
        .lineHeight($r('app.float.line_height_title'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .textAlign(TextAlign.Center)

      if (this.note !== '') {
        Text(this.note)
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontColor($r('app.color.muted_foreground'))
          .textAlign(TextAlign.Center)
          .margin({ top: $r('app.float.empty_note_gap') })
          .padding({
            left: $r('app.float.padding_page'),
            right: $r('app.float.padding_page')
          })
      }
    }
    .width('100%')
    .height(this.compact ? 'auto' : '100%')
    .justifyContent(this.compact ? FlexAlign.Start : FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
