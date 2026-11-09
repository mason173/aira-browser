import { JuRadio } from './JuRadio'
import { juFormSeparator } from './JuFormSeparator'

/**
 * 单选列表：一组选项，同一时间只能选中一个。
 *
 * 用在 `JuImmersiveSheet` 的面板正文里（宿主自己持有显示状态并绑定 bindSheet），
 * 配合 `JuFormChoice` 使用：选择行显示当前值，点开面板由本组件给出选项。
 *
 * 整行可点，右侧是库内既有的单选框；点整行与点单选框都会回调 `onSelect`。
 * 卡片、内距、行间内缩分割线与分组表单保持同一套几何。
 */
@Component
export struct JuChoiceList {
  @Prop options: string[] = []
  /** 当前选中项索引，宿主持有。 */
  @Prop selected: number = 0
  onSelect: (index: number) => void = (_index: number): void => {}

  build() {
    Column() {
      ForEach(this.options, (option: string, index: number) => {
        Column() {
          if (index > 0) {
            juFormSeparator()
          }
          Row() {
            Text(option)
              .layoutWeight(1)
              .fontSize($r('app.float.font_size_body'))
              .lineHeight($r('app.float.line_height_body'))
              .fontColor($r('app.color.foreground'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            JuRadio({
              checked: this.selected === index,
              group: 'ju_choice_list',
              value: `${index}`,
              // 只有"被选中"才算选择。**取消选中同样会触发 onChange**，
              // 把它当成选择会让"选了别的项"变成"又选回原来那项"：
              // 宿主把选中项清空（例如图标选择页里"都不选＝手动挑了图标"）时，
              // 这里会把上一次的选项又报回去（2026-10-18 修）。
              onPick: (on: boolean): void => {
                if (on) {
                  this.onSelect(index)
                }
              }
            })
          }
          .width('100%')
          .height($r('app.float.input_height'))
          .alignItems(VerticalAlign.Center)
          .padding({
            left: $r('app.float.mine_row_padding'),
            right: $r('app.float.mine_row_padding')
          })
          .stateStyles({
            pressed: { .backgroundColor($r('app.color.row_pressed')) },
            normal: { .backgroundColor(Color.Transparent) }
          })
          .onClick((): void => {
            this.onSelect(index)
          })
        }
        .width('100%')
      }, (option: string, index: number) => `${index}-${option}`)
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
  }
}
