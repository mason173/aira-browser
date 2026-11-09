import { JuInput } from './JuInput'
import { juFormSeparator } from './JuFormSeparator'

/**
 * 分组表单里的一行单行输入：占位符承担字段名，不另写标签文字。
 *
 * 必须配合 `JuFormGroup` 使用（白卡由它提供）。这里给 `JuInput` 传 `bare: true`，
 * 让输入框落在卡片上而不是再套一层底色。
 *
 * 结构就是"分割线 + 控件"两行，控件本身直接用通用属性定宽，不套额外的 Row：
 * 行高由 `JuInput` 自己的 `input_height` 决定。
 *
 * 左内距传 `mine_row_padding`（而不是 `JuInput` 默认的 `padding_input`）：卡片里的文字
 * 要和上方小标题、下方卡外说明共用同一条左基线。
 */
@Component
export struct JuFormInput {
  @Prop placeholder: string = ''
  @Prop text: string = ''
  /** 是否是这一组的第一行；第一行不画顶部分割线。 */
  @Prop divider: boolean = true
  /** 出现时聚焦并弹出键盘。一组里只给需要立刻输入的那一行。 */
  @Prop autoFocus: boolean = false
  /** 密码输入，透传给 JuInput。 */
  @Prop secure: boolean = false
  /** 最多多少字。0 表示不限制。 */
  @Prop maxLength: number = 0
  onValueChange: (value: string) => void = (_value: string): void => {}

  build() {
    Column() {
      if (this.divider) {
        juFormSeparator()
      }
      JuInput({
        text: this.text,
        placeholder: this.placeholder,
        autoFocus: this.autoFocus,
      secure: this.secure,
        maxLength: this.maxLength,
        bare: true,
        insetLeft: $r('app.float.mine_row_padding'),
        onValueChange: this.onValueChange
      })
        .width('100%')
    }
    .width('100%')
  }
}
