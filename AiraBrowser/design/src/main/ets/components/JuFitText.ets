/**
 * 单行文字。不超过最大宽度时原样显示。
 * 超出后在这个宽度里循环滚动，不用省略号。
 */
@Component
export struct JuFitText {
  @Prop @Watch('measure') text: string = ''
  /** 可用的最大宽度，单位 vp。小于等于 0 时不限制。 */
  @Prop maxWidth: number = 0
  @Prop fontColor: ResourceColor = $r('app.color.foreground')
  onTap: () => void = () => {}
  @State textWidth: number = 0

  aboutToAppear(): void {
    this.measure()
  }

  build() {
    if (this.maxWidth > 0) {
      Text(this.text)
        .width(this.limit())
        .maxLines(1)
        .fontSize($r('app.float.font_size_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor(this.fontColor)
        .textOverflow({ overflow: this.scrolls() ? TextOverflow.MARQUEE : TextOverflow.Clip })
        .marqueeOptions({
          start: this.scrolls(),
          fromStart: true,
          loop: -1
        })
        .onClick(() => this.onTap())
    } else {
      Text(this.text)
        .maxLines(1)
        .fontSize($r('app.float.font_size_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor(this.fontColor)
        .onClick(() => this.onTap())
    }
  }

  /** 短的用文字本身的宽度，长的卡在最大宽度里。 */
  private limit(): number {
    if (this.textWidth > 0 && this.textWidth < this.maxWidth) {
      return this.textWidth
    }
    return this.maxWidth
  }

  private scrolls(): boolean {
    return this.maxWidth > 0 && this.textWidth > this.maxWidth
  }

  private measure(): void {
    if (this.text.length === 0) {
      this.textWidth = 0
      return
    }
    try {
      const px = this.getUIContext().getMeasureUtils().measureText({
        textContent: this.text,
        fontSize: $r('app.float.font_size_body'),
        fontWeight: 600
      })
      this.textWidth = this.getUIContext().px2vp(px)
    } catch (_err) {
      this.textWidth = 0
    }
  }
}
