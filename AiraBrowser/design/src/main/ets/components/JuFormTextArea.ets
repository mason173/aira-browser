import { JuTextArea } from './JuTextArea'
import { juFormSeparator } from './JuFormSeparator'

/**
 * 分组表单里的一行多行输入（备注这类）。
 * 同样不在卡片里再画一层底：给 `JuTextArea` 传 `bare: true`。
 * 宽高直接给在控件上，不套额外的容器。
 */
@Component
export struct JuFormTextArea {
  @Prop placeholder: string = ''
  @Prop text: string = ''
  /** 是否是这一组的第一行；第一行不画顶部分割线。 */
  @Prop divider: boolean = true
  /** 加高档（约四行），内容超出框内滚动。 */
  @Prop tall: boolean = false
  onValueChange: (value: string) => void = (_value: string): void => {}

  build() {
    Column() {
      if (this.divider) {
        juFormSeparator()
      }
      JuTextArea({
        text: this.text,
        placeholder: this.placeholder,
        bare: true,
        tall: this.tall,
        insetLeft: $r('app.float.mine_row_padding'),
        onValueChange: this.onValueChange
      })
        .width('100%')
    }
    .width('100%')
  }
}
