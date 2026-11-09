import { curves } from '@kit.ArkUI'
import { JuDigitRoll } from './JuDigitRoll'
import { JuIconButton } from './JuIconButton'

/** 步进器。靠右排列。位数变多时往左挤开，数字本身贴在一起。 */
@Component
export struct JuStepper {
  @Prop @Watch('syncSpan') value: number = 1
  @Prop min: number = 1
  @Prop max: number = 365
  /**
   * 数字格固定位数。大于 0 时不再按当前值自适应宽度，整组宽度恒定，
   * 多行叠下来减号、加号能对齐（设置列表那种一列步进器用）。0 是原来的自适应。
   */
  @Prop slotDigits: number = 0
  /** 加减按钮的圆底色。默认 secondary；放在 secondary 底色的卡片里时要传别的色，否则和卡片同色看不见。 */
  @Prop plateColor: ResourceColor = $r('app.color.secondary')
  onChange: (value: number) => void = () => {}
  @State span: number = 0
  @State slide: boolean = false
  /** slotDigits > 0 时的数字格宽（按最宽数字量出来），只读一次。 */
  private slotVp: number = 0
  private holdDelta: number = 0
  private repeating: boolean = false
  private ticks: number = 0
  private arm: number = -1

  aboutToAppear(): void {
    if (this.slotDigits > 0) {
      this.slotVp = this.measureSlot()
    } else {
      this.span = this.measure()
    }
    setTimeout(() => {
      this.slide = true
    }, 32)
  }

  aboutToDisappear(): void {
    this.stopHold()
  }

  syncSpan(): void {
    if (this.slotDigits > 0) {
      return
    }
    const next = this.measure()
    if (!this.slide || next === this.span) {
      this.span = next
      return
    }
    this.getUIContext().animateTo({
      duration: 270,
      curve: curves.cubicBezierCurve(0.26, 0.08, 0.25, 1)
    }, () => {
      this.span = next
    })
  }

  build() {
    Row() {
      JuIconButton({
        name: $r('app.media.fab_minus'),
        color: this.value <= this.min ? $r('app.color.muted_foreground') : $r('app.color.foreground'),
        iconSide: $r('app.float.stepper_icon_size'),
        // 圆别太大：可见的圆用 stepper_circle_size（34vp），外面仍留 48vp 触控区。
        side: $r('app.float.icon_button_size'),
        insetPlate: true,
        plateSide: $r('app.float.stepper_circle_size'),
        plateRadius: $r('app.float.stepper_circle_radius'),
        plateColor: this.plateColor,
        onPressIn: (): void => this.begin(-1),
        onPressOut: (): void => this.finish(true),
        onPressCancel: (): void => this.finish(false)
      })
      // 数字在「减」「加」之间居中：数字格宽是固定的（slotDigits 时按最宽数字量），
      // 居中对齐后一位数 5 和两位数 25 都落在两个按钮的正中间。
      Stack({ alignContent: Alignment.Center }) {
        JuDigitRoll({ value: this.value })
      }
      .width(this.slotDigits > 0 ? this.slotVp : this.span)
      .height($r('app.float.line_height_title'))
      .clip(true)
      .margin({
        left: $r('app.float.gap_button_text'),
        right: $r('app.float.gap_button_text')
      })
      JuIconButton({
        name: $r('app.media.fab_plus'),
        color: this.value >= this.max ? $r('app.color.muted_foreground') : $r('app.color.foreground'),
        iconSide: $r('app.float.stepper_icon_size'),
        side: $r('app.float.icon_button_size'),
        insetPlate: true,
        plateSide: $r('app.float.stepper_circle_size'),
        plateRadius: $r('app.float.stepper_circle_radius'),
        plateColor: this.plateColor,
        onPressIn: (): void => this.begin(1),
        onPressOut: (): void => this.finish(true),
        onPressCancel: (): void => this.finish(false)
      })
    }
    .alignItems(VerticalAlign.Center)
  }

  /** 量一段数字在当前字号下的宽度（vp）。量不出来返回 0。 */
  private measureTextOf(text: string): number {
    try {
      const px = this.getUIContext().getMeasureUtils().measureText({
        textContent: text,
        fontSize: $r('app.float.font_size_title'),
        fontWeight: 600
      })
      const vp = this.getUIContext().px2vp(px)
      if (vp > 0) {
        return vp
      }
    } catch (_err) {
    }
    return 0
  }

  private measure(): number {
    const text = `${Math.round(Math.abs(this.value))}`
    const vp = this.measureTextOf(text.length > 0 ? text : '0')
    return vp > 0 ? vp : this.span
  }

  /** 固定数字格宽：按 slotDigits 个最宽数字量，所有值都装得下、宽度还一致。 */
  private measureSlot(): number {
    let sample = ''
    for (let index = 0; index < this.slotDigits; index++) {
      sample += '8'
    }
    const vp = this.measureTextOf(sample)
    return vp > 0 ? vp : this.span
  }

  private begin(delta: number): void {
    this.stopHold()
    this.holdDelta = delta
    this.repeating = false
    this.ticks = 0
    this.arm = setTimeout(() => {
      this.repeating = true
      this.pump()
    }, 350)
  }

  private finish(commitTap: boolean): void {
    const repeating = this.repeating
    this.stopHold()
    if (commitTap && !repeating) {
      this.stepBy(this.holdDelta)
    }
  }

  private pump(): void {
    const amount = this.holdDelta < 0 ? -this.jump() : this.jump()
    if (!this.stepBy(amount)) {
      this.stopHold()
      return
    }
    this.ticks++
    this.arm = setTimeout(() => {
      this.pump()
    }, this.pace())
  }

  private jump(): number {
    if (this.ticks < 8) {
      return 1
    }
    if (this.ticks < 18) {
      return 5
    }
    return 10
  }

  private pace(): number {
    if (this.ticks < 8) {
      return 80
    }
    return 50
  }

  private stepBy(delta: number): boolean {
    let next = this.value + delta
    if (next < this.min) {
      next = this.min
    }
    if (next > this.max) {
      next = this.max
    }
    if (next === this.value) {
      return false
    }
    this.onChange(next)
    return true
  }

  private stopHold(): void {
    if (this.arm >= 0) {
      clearTimeout(this.arm)
      this.arm = -1
    }
    this.repeating = false
  }
}
