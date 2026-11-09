@Component
export struct JuInput {
  /** 输入内容。加 @Watch：外部改了 text 要能进到框里（见 syncText）。 */
  @Prop @Watch('syncText') text: string = ''
  @Prop placeholder: string = ''
  /** 出现时聚焦并弹出键盘。只给需要立刻输入的那一个。 */
  @Prop autoFocus: boolean = false
  /** 最多多少字。0 表示不限制。 */
  @Prop maxLength: number = 0
  /** 底色。编辑弹窗里要和下面的列表一样，用 secondary。 */
  @Prop tone: ResourceColor = $r('app.color.input')
  /** 不画自己的底，交给外面的卡片或备注容器。分组表单里必须为 true，否则卡片里会多一层底色。 */
  @Prop bare: boolean = false
  /** 左边再留一截，给外面已经放好的图标。 */
  @Prop insetLeft: Resource = $r('app.float.padding_input')
  /** 输入文字颜色。彩色卡片上要传白色。 */
  @Prop textColor: ResourceColor = $r('app.color.foreground')
  /** 占位文字颜色。默认 input_muted，彩色卡片上可传和输入文字同色。 */
  @Prop placeholderTone: ResourceColor = $r('app.color.input_muted')
  /** 密码输入：内容显示为圆点，并且不进入输入法的联想与历史。 */
  @Prop secure: boolean = false
  /** 字号。列表名这种要跟着标题放大时传更大的档。 */
  @Prop textSize: Resource = $r('app.float.font_size_body')
  /** 文字和光标居中。列表名那种居中的标题用。 */
  @Prop alignCenter: boolean = false
  /**
   * 字重。TextInput 不吃字重资源，只能传数字。
   * 0 用系统默认。600 等于 font_weight_semibold。
   */
  @Prop weight: number = 0
  onValueChange: (value: string) => void = () => {}
  /** 键盘回车。不接就什么都不做。 */
  onSubmit: () => void = () => {}
  /** 失焦。交给调用方在这里收尾（比如自动保存）。 */
  onEditEnd: () => void = () => {}
  @State value: string = ''

  aboutToAppear(): void {
    this.value = this.text
  }

  /**
   * 外部改了 text 要能进来。
   *
   * 原先只在 aboutToAppear 里复制一次，那之后宿主再改 text 完全传不进来——
   * 表现是"程序填好的值不显示，输入框还是空的"（TOKI 选中服务商自动填地址时暴露的）。
   * 只在值确实不同时才覆盖，所以不会顶掉用户正在输入的内容。
   */
  private syncText(): void {
    if (this.text !== this.value) {
      this.value = this.text
    }
  }

  /**
   * 只在值真的变了才回调。TextInput 用 text 初始化后会回报一次同样的值，
   * 那不是用户输入，不能往外传，否则调用方会把初始值当成一次编辑。
   */
  private emit(value: string): void {
    if (value === this.value) {
      return
    }
    this.value = value
    this.onValueChange(value)
  }

  build() {
    if (this.maxLength > 0) {
      TextInput({ text: this.value, placeholder: this.placeholder })
        .type(this.secure ? InputType.Password : InputType.Normal)
        .maxLength(this.maxLength)
        .id(this.autoFocus ? 'ju_input_autofocus' : '')
        .defaultFocus(this.autoFocus)
        .onAppear(() => {
          if (this.autoFocus) {
            this.getUIContext().getFocusController().requestFocus('ju_input_autofocus')
          }
        })
        .onChange((value: string) => this.emit(value))
        .enterKeyType(EnterKeyType.Done)
        .onSubmit(() => this.onSubmit())
        .onBlur(() => this.onEditEnd())
        .textAlign(this.alignCenter ? TextAlign.Center : TextAlign.Start)
        .width('100%')
        .height($r('app.float.input_height'))
        .fontSize(this.textSize)
        .fontWeight(this.weight > 0 ? this.weight : FontWeight.Normal)
        .fontColor(this.textColor)
        .placeholderColor(this.placeholderTone)
        .placeholderFont({ size: this.textSize, weight: this.weight > 0 ? this.weight : FontWeight.Normal })
        .backgroundColor(this.bare ? Color.Transparent : this.tone)
        .borderRadius($r('app.float.input_radius'))
        .padding({
          left: this.insetLeft,
          right: $r('app.float.padding_input')
        })
    } else {
      TextInput({ text: this.value, placeholder: this.placeholder })
        .type(this.secure ? InputType.Password : InputType.Normal)
        .id(this.autoFocus ? 'ju_input_autofocus' : '')
        .defaultFocus(this.autoFocus)
        .onAppear(() => {
          if (this.autoFocus) {
            this.getUIContext().getFocusController().requestFocus('ju_input_autofocus')
          }
        })
        .onChange((value: string) => this.emit(value))
        .enterKeyType(EnterKeyType.Done)
        .onSubmit(() => this.onSubmit())
        .onBlur(() => this.onEditEnd())
        .textAlign(this.alignCenter ? TextAlign.Center : TextAlign.Start)
        .width('100%')
        .height($r('app.float.input_height'))
        .fontSize(this.textSize)
        .fontWeight(this.weight > 0 ? this.weight : FontWeight.Normal)
        .fontColor(this.textColor)
        .placeholderColor(this.placeholderTone)
        .placeholderFont({ size: this.textSize, weight: this.weight > 0 ? this.weight : FontWeight.Normal })
        .backgroundColor(this.bare ? Color.Transparent : this.tone)
        .borderRadius($r('app.float.input_radius'))
        .padding({
          left: this.insetLeft,
          right: $r('app.float.padding_input')
        })
    }
  }
}
