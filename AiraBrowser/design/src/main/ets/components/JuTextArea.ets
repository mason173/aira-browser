/** 多行输入。固定两行高，字超出后在框内滚动，并按需露出短滚动条。 */
@Component
export struct JuTextArea {
  text: string = ''
  placeholder: string = ''
  /** 为真时不画自己的底，交给外面的备注容器。 */
  @Prop bare: boolean = false
  /** 为真时占满父级剩下的高度，用来写长文。 */
  @Prop fill: boolean = false
  /** 为真时用加高档（约四行）；宽屏详情面板的备注用，内容超出框内滚。 */
  @Prop tall: boolean = false
  /** 底色。编辑弹窗里要和下面的列表一样，用 secondary。 */
  @Prop tone: ResourceColor = $r('app.color.input')
  /** 左边内距。默认与输入框一致；分组表单里传 mine_row_padding，和标题、卡外说明对齐。 */
  @Prop insetLeft: Resource = $r('app.float.padding_input')
  onValueChange: (value: string) => void = () => {}
  @State value: string = ''

  aboutToAppear(): void {
    this.value = this.text
  }

  build() {
    TextArea({ text: this.value, placeholder: this.placeholder })
        .onChange((value: string) => {
          if (value === this.value) {
            return
          }
          this.value = value
          this.onValueChange(value)
        })
      .width('100%')
      .height(this.fill ? '100%'
        : this.tall ? $r('app.float.input_area_height_tall') : $r('app.float.input_area_height'))
      .layoutWeight(this.fill ? 1 : 0)
      .fontSize($r('app.float.font_size_body'))
      .fontColor($r('app.color.foreground'))
      .placeholderColor($r('app.color.input_muted'))
      .placeholderFont({ size: $r('app.float.font_size_body') })
      .backgroundColor(this.bare ? Color.Transparent : this.tone)
      .borderRadius($r('app.float.input_area_radius'))
      .padding({
        left: this.insetLeft,
        right: $r('app.float.padding_input')
      })
      .barState(BarState.Auto)
  }
}
