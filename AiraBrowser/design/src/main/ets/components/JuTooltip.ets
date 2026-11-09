/**
 * 提示气泡。底色固定是 tooltip，浅色深色都是这个黑，不跟着主题变。
 * 尖角由系统画，指向包住的那个节点。点外面自己收起。
 * 默认弹在下面，`placement` 传 `Placement.Top` 就弹在上面（贴近屏幕底部时用）。
 */
@Component
export struct JuTooltip {
  @Prop text: string = ''
  @Prop open: boolean = false
  /** 气泡相对被包节点的位置。默认下方；传 `Placement.Top` 则在上方。 */
  @Prop placement: Placement = Placement.Bottom
  /** 是否铺一层蒙层。默认铺（点外面自动收）。 */
  @Prop withMask: boolean = true
  onClose: () => void = () => {}
  @BuilderParam content: () => void = this.Empty

  build() {
    Column() {
      this.content()
    }
    .bindPopup(this.open, {
      builder: this.Bubble,
      placement: this.placement,
      popupColor: $r('app.color.tooltip'),
      backgroundBlurStyle: BlurStyle.NONE,
      enableArrow: true,
      arrowPointPosition: ArrowPointPosition.CENTER,
      radius: $r('app.float.radius_tooltip'),
      mask: this.withMask,
      autoCancel: true,
      targetSpace: $r('app.float.gap_title_body'),
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible && this.open) {
          this.onClose()
        }
      }
    })
  }

  @Builder
  Bubble() {
    Text(this.text)
      .fontSize($r('app.float.font_size_caption'))
      .lineHeight($r('app.float.line_height_caption'))
      .fontColor($r('app.color.primary_foreground'))
      .backgroundColor($r('app.color.tooltip'))
      // 气泡要有上限宽，长文案换行，别横着铺满整屏。
      .constraintSize({ maxWidth: $r('app.float.tooltip_max_width') })
      .padding({
        left: $r('app.float.padding_input'),
        right: $r('app.float.padding_input'),
        top: $r('app.float.gap_button_text'),
        bottom: $r('app.float.gap_button_text')
      })
  }

  @Builder
  Empty() {
  }
}
