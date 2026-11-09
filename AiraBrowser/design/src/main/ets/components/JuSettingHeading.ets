/**
 * 设置组的小标题。没有底，左右和卡片里的文字对齐，放在卡片前面、宽度跟卡片一样。
 *
 * 两个变体都是 semibold：加粗才立得住"这是一组的标题"，不加粗时它和卡片里的正文
 * 只差一点颜色，读起来像正文而不是标题。
 * - 默认：caption 14fp、中性色、左右内缩，用于设置页与表单页。
 * - `prominent: true`：subtitle 16fp、正文色、无左右内缩，用于内容介绍页（会员页那种）。
 *
 * 下间距用自己的 `setting_heading_gap_bottom`（6vp），不借用被多处共用的 `gap_title_body`：
 * 那个也管着设置组内部标题与描述的间距、提示气泡的间距，改它会连带变动别处。
 *
 * 注意左内缩是 `mine_row_padding`，与设置行的文字起点对齐；如果卡片里的文字用了
 * 别的内距（例如输入框自带的 `padding_input`），需要另做对齐。
 */
@Component
export struct JuSettingHeading {
  @Prop text: string = ''
  /** 内容介绍页的小节标题；默认保留设置页原样。 */
  @Prop prominent: boolean = false

  build() {
    Text(this.text)
      .width('100%')
      .fontSize(this.prominent ? $r('app.float.font_size_subtitle') : $r('app.float.font_size_caption'))
      .fontWeight($r('app.integer.font_weight_semibold'))
      .fontColor(this.prominent ? $r('app.color.foreground') : $r('app.color.muted_foreground'))
      .padding({
        top: $r('app.float.setting_heading_gap'),
        bottom: this.prominent ? $r('app.float.gap_row') : $r('app.float.setting_heading_gap_bottom'),
        left: this.prominent ? $r('app.float.edge_none') : $r('app.float.mine_row_padding'),
        right: this.prominent ? $r('app.float.edge_none') : $r('app.float.mine_row_padding')
      })
  }
}
