import { JuIcon } from './JuIcon'
import { JuSlider } from './JuSlider'
import { JuSwitch } from './JuSwitch'

/** 设置行的稳定标识。卡片用它决定哪一行画自定义尾部。 */
export class JuSettingItem {
  key: string = ''
  title: string = ''
  /** 可选的一行简短说明；空字符串保持原来的单行设置样式。 */
  description: string = ''
  icon: Resource | null = null
  plate: Resource = $r('app.color.mine_icon_blue')
  value: string = ''
  /** 右侧文字颜色。默认 muted_foreground，更浅的值用 section。 */
  valueColor: Resource = $r('app.color.muted_foreground')
  chevron: boolean = false
  toggle: boolean = false
  /**
   * 是否可用。false 时整行变淡、开关不接受点击，**但行本身仍然可点**——
   * 宿主可以借此给一句"为什么不能点"的提示（例如两个开关互斥时）。
   */
  enabled: boolean = true
  on: boolean = false
  /**
   * 滑块行：标签与右侧 `value` 保持不变，行下方再加一条整行宽的滑块。
   * 拖动中与松手后都会回调，宿主据此决定什么时候落盘。
   */
  slider: boolean = false
  sliderValue: number = 0
  sliderMin: number = 0
  sliderMax: number = 100
  sliderStep: number = 1

  constructor(key: string, title: string, icon: Resource | null = null,
    plate: Resource = $r('app.color.mine_icon_blue')) {
    this.key = key
    this.title = title
    this.icon = icon
    this.plate = plate
  }
}

/**
 * 设置卡片。一行或多行都用它，白底、圆角和分割线由卡片负责。
 * 行本身支持图标、标题、可选简短说明和右侧的文字、箭头或开关。需要别的控件时，
 * 传 customKey 和 customTrailing，只替换那一行的右侧。
 * 滑块行传 `slider: true`：行布局不变，只是在行下方多一条整行宽的滑块。
 */
@Component
export struct JuSettingGroup {
  @Prop items: JuSettingItem[] = []
  @Prop customKey: string = ''
  @BuilderParam customTrailing: () => void = this.Empty
  onSelect: (key: string) => void = (_key: string): void => {}
  onToggle: (key: string, on: boolean) => void = (_key: string, _on: boolean): void => {}
  /** 滑块行回调；`ended` 为 true 表示松手（拖动中为 false），用来区分预览与落盘。 */
  onSliderChange: (key: string, value: number, ended: boolean) => void =
    (_key: string, _value: number, _ended: boolean): void => {}

  build() {
    Column() {
      ForEach(this.items, (item: JuSettingItem, index: number) => {
        this.Row(index)
      }, (item: JuSettingItem) => item.key)
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
  }

  @Builder
  Empty() {}

  // 按索引读取当前 @Prop 数组，稳定 key 复用时不捕获旧的行对象。
  @Builder
  Row(index: number) {
    Column() {
      Row() {
        if (this.items[index].icon !== null) {
          Stack() {
            JuIcon({
              name: this.items[index].icon as Resource,
              color: $r('app.color.mine_icon_mark'),
              side: $r('app.float.icon_size')
            })
          }
          .width($r('app.float.mine_row_icon'))
          .height($r('app.float.mine_row_icon'))
          .borderRadius($r('app.float.mine_row_icon_radius'))
          .backgroundColor(this.items[index].plate)
          .alignContent(Alignment.Center)
          .margin({ right: $r('app.float.gap_list') })
        }

        if (this.items[index].description.length > 0) {
          Column({ space: $r('app.float.gap_title_body') }) {
            Text(this.items[index].title)
              .width('100%')
              .fontSize($r('app.float.font_size_body'))
              .lineHeight($r('app.float.line_height_body'))
              .fontWeight($r('app.integer.font_weight_regular'))
              .fontColor($r('app.color.foreground'))
            Text(this.items[index].description)
              .width('100%')
              .fontSize($r('app.float.font_size_micro'))
              .lineHeight($r('app.float.line_height_micro'))
              .fontColor($r('app.color.muted_foreground'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        } else {
          Text(this.items[index].title)
            .layoutWeight(1)
            .fontSize($r('app.float.font_size_body'))
            .fontWeight($r('app.integer.font_weight_regular'))
            .fontColor($r('app.color.foreground'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        if (this.items[index].key === this.customKey && this.customKey.length > 0) {
          this.customTrailing()
        } else if (this.items[index].toggle) {
          JuSwitch({
            isOn: this.items[index].on,
            onChange: (on: boolean): void => { this.onToggle(this.items[index].key, on) }
          })
            // 置灰时开关自己不吃点击，交给整行的 onClick 去给提示。
            .hitTestBehavior(this.items[index].enabled ? HitTestMode.Default : HitTestMode.None)
        } else {
          if (this.items[index].value.length > 0) {
            Text(this.items[index].value)
              .fontSize($r('app.float.font_size_body'))
              .fontColor(this.items[index].valueColor)
              .margin({ right: this.items[index].chevron ? $r('app.float.gap_button_text') : $r('app.float.edge_none') })
          }
          if (this.items[index].chevron) {
            JuIcon({
              name: $r('app.media.chevron_right'),
              color: this.items[index].valueColor,
              side: $r('app.float.icon_size_secondary')
            })
          }
        }
      }
      .width('100%')
      .padding($r('app.float.mine_row_padding'))
      // 按下要有反馈：能点的行，按下去的瞬间底色变一下。
      // 整行都可点——开关行点行体也算，否则这一行看着能点、按下去却没反应。
      .stateStyles({
        pressed: { .backgroundColor($r('app.color.row_pressed')) },
        normal: { .backgroundColor(Color.Transparent) }
      })
      .opacity(this.items[index].enabled ? 1 : 0.4)
      .onClick((): void => {
        if (this.items[index].key === this.customKey) {
          return
        }
        // 滑块行不是点击行：整行点击会让“想拖滑块”变成“开了子页”。
        if (this.items[index].slider) {
          return
        }
        // 置灰的行不给切换／跳转，只把点击交回宿主——由宿主说明为什么点了没反应。
        if (!this.items[index].enabled) {
          this.onSelect(this.items[index].key)
          return
        }
        if (this.items[index].toggle) {
          this.onToggle(this.items[index].key, !this.items[index].on)
        } else {
          this.onSelect(this.items[index].key)
        }
      })

      if (this.items[index].slider) {
        JuSlider({
          value: this.items[index].sliderValue,
          min: this.items[index].sliderMin,
          max: this.items[index].sliderMax,
          step: this.items[index].sliderStep,
          active: this.items[index].enabled,
          onChange: (value: number, ended: boolean): void => {
            this.onSliderChange(this.items[index].key, value, ended)
          }
        })
          .width('100%')
          // 与行内文字同一内缩：滑块两端跟标签、右侧值对齐。组件自己不预设边距。
          .padding({
            left: $r('app.float.mine_row_padding'),
            right: $r('app.float.mine_row_padding'),
            bottom: $r('app.float.gap_row')
          })
      }

      if (index < this.items.length - 1) {
        Row() {
          if (this.items[index].icon !== null) {
            Blank()
              .width($r('app.float.mine_row_icon'))
              .margin({
                left: $r('app.float.mine_row_padding'),
                right: $r('app.float.gap_list')
              })
          } else {
            Blank().width($r('app.float.mine_row_padding'))
          }
          Row()
            .layoutWeight(1)
            .height($r('app.float.divider_height'))
            .margin({ right: $r('app.float.mine_row_padding') })
            .backgroundColor($r('app.color.setting_separator'))
        }
        .width('100%')
      }
    }
    .width('100%')
  }
}
