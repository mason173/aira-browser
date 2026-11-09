/**
 * 设置卡片下面的说明。没有底，字比正文小，左右和卡片里的文字对齐。
 * 放在卡片后面，宽度跟卡片一样，不要再加左右边距。
 */
@Component
export struct JuSettingNote {
  @Prop text: string = ''
  @Prop centered: boolean = false

  build() {
    Text(this.text)
      .width('100%')
      .fontSize($r('app.float.font_size_micro'))
      .lineHeight($r('app.float.line_height_micro'))
      .fontColor($r('app.color.muted_foreground'))
      .textAlign(this.centered ? TextAlign.Center : TextAlign.Start)
      .padding({
        top: $r('app.float.setting_note_gap'),
        left: $r('app.float.mine_row_padding'),
        right: $r('app.float.mine_row_padding')
      })
  }
}
