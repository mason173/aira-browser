import { JuIconButton } from './JuIconButton'

/** 文字 Tab。选中项深色加粗，支持右侧次要操作图标。 */
@Component
export struct JuTextTab {
  @Prop labels: Array<string> = []
  @Prop @Watch('revealSelected') selected: number = 0
  private labelScroller: Scroller = new Scroller()
  /** 每个名字在这一行里的位置。用来判断有没有被右边的按钮挡住。 */
  private labelLeft: number[] = []
  private labelWidth: number[] = []
  private namesWidth: number = 0
  @Prop showTrailingAction: boolean = false
  @Prop trailingIcon: Resource = $r('app.media.sliders_horizontal')
  @Prop trailingColor: ResourceColor = $r('app.color.muted_foreground')
  @Prop trailingIconSide: Resource = $r('app.float.icon_size_secondary')
  /** 设置图标左边再放一颗加号，用来新建分组。 */
  @Prop showLeadingAction: boolean = false
  @Prop leadingIcon: Resource = $r('app.media.fab_plus')
  @Prop leadingColor: ResourceColor = $r('app.color.muted_foreground')
  @Prop leadingIconSide: Resource = $r('app.float.icon_size_secondary')
  onSelect: (index: number) => void = () => {}
  onTrailingAction: () => void = () => {}
  onLeadingAction: () => void = () => {}

  build() {
    Column() {
      Row() {
        Scroll(this.labelScroller) {
          Row() {
            ForEach(this.labels, (label: string, index: number) => {
              Column() {
                Text(label)
                  .id(this.labelId(index))
                  .fontSize($r('app.float.font_size_subtitle'))
                  .fontWeight(this.selected === index
                    ? $r('app.integer.font_weight_semibold')
                    : $r('app.integer.font_weight_medium'))
                  .fontColor(this.selected === index
                    ? $r('app.color.foreground')
                    : $r('app.color.muted_foreground'))
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
              }
              .height($r('app.float.text_tab_height'))
              .justifyContent(FlexAlign.Center)
              .margin({ right: $r('app.float.gap_text_tab_item') })
              .onAreaChange((_oldArea: Area, newArea: Area) => {
                this.rememberLabel(index, newArea)
              })
              .onClick(() => {
                this.onSelect(index)
              })
            }, (label: string, index: number) => `${label}-${index}`)
          }
          .constraintSize({ minWidth: '100%' })
          .height($r('app.float.text_tab_height'))
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .align(Alignment.Start)
        .clip(true)
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          this.namesWidth = this.areaNumber(newArea.width)
          this.revealSelected()
        })
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        if (this.showLeadingAction) {
          JuIconButton({
            name: this.leadingIcon,
            color: this.leadingColor,
            iconSide: this.leadingIconSide,
            side: $r('app.float.icon_button_size'),
            radius: $r('app.float.icon_button_radius'),
            onTap: () => this.onLeadingAction()
          })
            .margin({ right: $r('app.float.icon_button_pair_overlap') })
        }

        if (this.showTrailingAction) {
          JuIconButton({
            name: this.trailingIcon,
            color: this.trailingColor,
            iconSide: this.trailingIconSide,
            side: $r('app.float.icon_button_size'),
            radius: $r('app.float.icon_button_radius'),
            onTap: () => this.onTrailingAction()
          })
            .margin({ right: $r('app.float.padding_header_actions') })
        }
      }
      .width('100%')
      .height($r('app.float.text_tab_height'))
      .alignItems(VerticalAlign.Center)
      .clip(false)
      .padding({ left: $r('app.float.padding_page_compact') })

      Row() {
        Row()
          .width('100%')
          .height($r('app.float.divider_height'))
          .backgroundColor($r('app.color.separator'))
      }
      .width('100%')
      .height($r('app.float.divider_height'))
      .padding({
        left: $r('app.float.padding_page_compact'),
        right: $r('app.float.padding_page_compact')
      })
    }
    .width('100%')
  }

  /** 选中的名字如果在按钮后面，滚出来，整颗都露在看得见的地方。 */
  private revealSelected(): void {
    const index = this.selected
    if (!this.scrollLabelIntoView(index)) {
      setTimeout(() => {
        this.scrollLabelIntoView(index)
      }, 32)
    }
  }

  private rememberLabel(index: number, area: Area): void {
    const x = area.position.x
    if (x === undefined) {
      return
    }
    const left = this.areaNumber(x)
    const width = this.areaNumber(area.width)
    if (width <= 0) {
      return
    }
    this.labelLeft[index] = left
    this.labelWidth[index] = width
  }

  /** 名字这一行不是 List，scrollToIndex 不起作用，只能按量到的位置滚。 */
  private scrollLabelIntoView(index: number): boolean {
    const left = this.labelLeft[index]
    const width = this.labelWidth[index]
    if (this.namesWidth <= 0 || width === undefined || width <= 0 || left === undefined) {
      return false
    }
    const shown = this.labelScroller.currentOffset().xOffset
    const right = left + width
    let target = shown
    if (right > shown + this.namesWidth) {
      target = right - this.namesWidth
    } else if (left < shown) {
      target = left
    }
    if (target < 0) {
      target = 0
    }
    if (Math.abs(target - shown) < 1) {
      return true
    }
    this.labelScroller.scrollTo({
      xOffset: target,
      yOffset: 0,
      animation: { duration: 280, curve: Curve.EaseOut }
    })
    return true
  }

  private areaNumber(value: Length): number {
    if (typeof value === 'number') {
      return value
    }
    const parsed = parseFloat(`${value}`)
    return Number.isFinite(parsed) ? parsed : 0
  }

  private labelId(index: number): string {
    return `group-label-${index}`
  }
}
