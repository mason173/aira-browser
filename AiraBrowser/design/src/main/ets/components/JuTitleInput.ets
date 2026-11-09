import { JuInput } from './JuInput'

/** 单行标题输入。字数上限读 `input_title_max_length`。 */
@Component
export struct JuTitleInput {
  text: string = ''
  @Prop placeholder: string = ''
  @Prop autoFocus: boolean = false
  @Prop tone: ResourceColor = $r('app.color.input')
  /** 透传给 JuInput，分组表单里传 true。 */
  @Prop bare: boolean = false
  @Prop insetLeft: Resource = $r('app.float.padding_input')
  /** 0 用系统默认。600 等于 font_weight_semibold。 */
  @Prop weight: number = 0
  onValueChange: (value: string) => void = () => {}
  @State limit: number = 0

  aboutToAppear(): void {
    const host = this.getUIContext().getHostContext()
    if (!host) {
      return
    }
    try {
      this.limit = host.resourceManager.getNumberByName('input_title_max_length')
    } catch (_err) {
      this.limit = 0
    }
  }

  build() {
    JuInput({
      text: this.text,
      placeholder: this.placeholder,
      autoFocus: this.autoFocus,
      maxLength: this.limit,
      tone: this.tone,
      bare: this.bare,
      insetLeft: this.insetLeft,
      weight: this.weight,
      onValueChange: (value: string): void => this.onValueChange(value)
    })
  }
}
