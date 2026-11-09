import { JuIcon } from './JuIcon'
import { juFormSeparator } from './JuFormSeparator'

/**
 * 分组表单里的一行选择：左标签，中间当前值，右箭头；点整行打开选择。
 *
 * 与 `JuFormInput` 同一套几何（`mine_row_padding` 内距、`input_height` 行高、顶部内缩分割线），
 * 所以输入行和选择行可以放在同一张 `JuFormGroup` 里。
 *
 * 值只用中性色显示当前选择，具体选项由 `JuChoiceList` 在面板里给出。
 */
@Component
export struct JuFormChoice {
  @Prop label: string = ''
  /** 当前值，直接显示在右侧。空串只显示标签和箭头。 */
  @Prop value: string = ''
  /** 是否是这一组的第一行；第一行不画顶部分割线。 */
  @Prop divider: boolean = true
  onTap: () => void = (): void => {}

  build() {
    Column() {
      if (this.divider) {
        juFormSeparator()
      }
      Row() {
        Text(this.label)
          .layoutWeight(1)
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontColor($r('app.color.foreground'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.value.length > 0) {
          Text(this.value)
            .fontSize($r('app.float.font_size_body'))
            .fontColor($r('app.color.muted_foreground'))
            .margin({ right: $r('app.float.gap_button_text') })
        }

        JuIcon({
          name: $r('app.media.chevron_right'),
          color: $r('app.color.muted_foreground'),
          side: $r('app.float.icon_size_secondary')
        })
      }
      .width('100%')
      .height($r('app.float.input_height'))
      .alignItems(VerticalAlign.Center)
      .padding({
        left: $r('app.float.mine_row_padding'),
        right: $r('app.float.mine_row_padding')
      })
      .onClick((): void => {
        this.onTap()
      })
    }
    .width('100%')
  }
}
