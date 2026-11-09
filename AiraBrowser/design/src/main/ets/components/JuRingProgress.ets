/** 环形进度。插值由原生 Progress 驱动，不为每个圆环创建逐帧 JS 定时器。 */
@Component
export struct JuRingProgress {
  @Prop @Watch('onValueChange') value: number = 0
  @Prop total: number = 60
  @Prop label: string = ''
  @Prop color: ResourceColor = $r('app.color.primary')
  @Prop trackColor: ResourceColor = $r('app.color.secondary')
  @Prop side: Resource = $r('app.float.ring_progress_side')
  @Prop thickness: Resource = $r('app.float.ring_progress_stroke')
  /** 正数启用系统平滑，具体插值节拍由平台维护；非正数直接更新。 */
  @Prop smoothMs: number = 1000
  @Prop growOnAppear: boolean = false
  @Prop @Watch('onActiveChange') active: boolean = true
  @BuilderParam center: () => void = this.Empty
  @State private shown: number = 0
  private appearTimerId: number = -1

  @Builder
  Empty() {}

  aboutToAppear(): void {
    this.shown = this.growOnAppear && this.active && this.smoothMs > 0 ? 0 : this.value
  }

  aboutToDisappear(): void { this.cancelAppear() }

  private cancelAppear(): void {
    if (this.appearTimerId >= 0) { clearTimeout(this.appearTimerId); this.appearTimerId = -1 }
  }

  private onValueChange(): void {
    this.cancelAppear()
    this.shown = this.value
  }

  private onActiveChange(): void { this.onValueChange() }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Progress({ value: this.shown, total: this.total, type: ProgressType.Ring })
        .width(this.side)
        .height(this.side)
        .color(this.color)
        .backgroundColor(this.trackColor)
        .style({ strokeWidth: this.thickness, enableSmoothEffect: this.active && this.smoothMs > 0 })

      if (this.center !== this.Empty) {
        this.center()
      } else if (this.label.length > 0) {
        Text(this.label)
          .fontSize($r('app.float.font_size_caption'))
          .lineHeight($r('app.float.line_height_caption'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor(this.color)
      }
    }
    .width(this.side)
    .height(this.side)
    .onAppear((): void => {
      if (this.growOnAppear && this.active && this.smoothMs > 0) {
        this.appearTimerId = setTimeout((): void => {
          this.appearTimerId = -1
          this.shown = this.value
        }, 0)
      }
    })
  }
}
