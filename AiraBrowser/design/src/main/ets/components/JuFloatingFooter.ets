import { JuButton } from './JuButton'

/**
 * 页面叠层：自己占满宿主，将按钮与渐变作为一个整体固定到底部。
 * 放在有确定高度的页面 Stack 中、Scroll 外，不依赖调用方设置 align。
 * 可点时仅按钮接收点击；其余区域以及纯展示模式不挡正文手势。
 */
@Component
export struct JuFloatingFooter {
  @Prop label: string = ''
  @Prop tappable: boolean = false
  /** 底部有悬浮页签等叠加物时，渐变与按钮整体抬升避让的高度。 */
  @Prop lift: Resource = $r('app.float.edge_none')
  /** 第二个按钮。空字符串时仍是原来的单按钮。 */
  @Prop secondaryLabel: string = ''
  @Prop secondaryDanger: boolean = false
  @Prop secondarySolid: boolean = false
  onTap: () => void = (): void => {}
  onSecondaryTap: () => void = (): void => {}

  build() {
    Column() {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [
              [$r('app.color.canvas_fade'), 0],
              [$r('app.color.canvas_fade'), 0.5],
              [$r('app.color.canvas'), 1]
            ]
          })
          .hitTestBehavior(HitTestMode.None)
        Row() {
          if (this.secondaryLabel.length > 0) {
            JuButton({
              label: this.secondaryLabel,
              primary: false,
              danger: this.secondaryDanger,
              solid: this.secondarySolid,
              action: (): void => { if (this.tappable) { this.onSecondaryTap() } }
            })
              .layoutWeight(1)
              .hitTestBehavior(this.tappable ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
          }
          JuButton({ label: this.label, action: (): void => { if (this.tappable) { this.onTap() } } })
            .layoutWeight(1)
            .margin({ left: this.secondaryLabel.length > 0 ? $r('app.float.gap_button') : $r('app.float.edge_none') })
            .hitTestBehavior(this.tappable ? HitTestMode.Default : HitTestMode.BLOCK_DESCENDANTS)
        }
        .width('100%')
        .padding({
          left: $r('app.float.sheet_card_inset'),
          right: $r('app.float.sheet_card_inset'),
          bottom: $r('app.float.gap_section')
        })
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height($r('app.float.sheet_footer_fade_height'))
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .padding({ bottom: this.lift })
    .hitTestBehavior(this.tappable ? HitTestMode.Transparent : HitTestMode.BLOCK_DESCENDANTS)
  }
}
