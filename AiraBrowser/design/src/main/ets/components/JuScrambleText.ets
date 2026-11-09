/**
 * 文字乱码收敛（Text Scramble）。
 *
 * 目标文字变化时，整串先变成随机字符，然后**从左往右逐个落定**成真字符。
 * 参数语义与 motion-primitives 的 TextScramble 一致：
 *   durationMs ÷ stepMs = 步数；第 step 步时，位置 i 满足
 *   `progress × 长度 > i` 就显示真字符，其余位置随机取字符。
 *
 * 为什么需要 `animateOnAppear`：宿主列表若在数据变化时重建了卡片（ForEach 键包含数据），
 * 新挂载的组件收到的直接就是新文字，"变化"根本没发生——想看到动画必须从挂载那一刻开始。
 * 这与 `JuRingProgress.growOnAppear` 是同一类问题。
 *
 * 验证码用数字字符集（`charSet` 传数字），免得字母跳进来；长度不变，所以不会跳版面。
 */
@Component
export struct JuScrambleText {
  /** 宿主隐藏时立即停止；恢复时显示真实文字，下一次目标变化再播放。 */
  @Prop @Watch('onActiveChange') active: boolean = true
  /** 目标文字。它一变就开始一次收敛。 */
  @Prop @Watch('onTargetChange') text: string = ''
  /** 收敛总时长（毫秒）。 */
  @Prop durationMs: number = 800
  /** 每步间隔（毫秒）。步数 = durationMs ÷ stepMs。 */
  @Prop stepMs: number = 40
  /** 乱码字符集。 */
  @Prop charSet: string = '0123456789'
  /** 挂载时也跑一次；列表卡片会随数据重建时用它。 */
  @Prop animateOnAppear: boolean = false
  @Prop fontSize: Resource = $r('app.float.font_size_title')
  @Prop lineHeight: Resource = $r('app.float.line_height_title')
  @Prop fontColor: ResourceColor = $r('app.color.foreground')
  /** 字族。默认取系统字体族，与 `JuDigitRoll` 一致。 */
  @Prop fontFamily: string = 'HarmonyOS Sans'
  @Prop fontWeight: Resource = $r('app.integer.font_weight_semibold')
  @Prop letterSpacing: number = 0
  /** 一次收敛跑完时回调。 */
  onComplete: () => void = (): void => {}

  @State shown: string = ''
  private step: number = 0
  private timerId: number = -1

  aboutToAppear(): void {
    this.shown = this.text
    if (this.active && this.animateOnAppear && this.text.length > 0) {
      this.start()
    }
  }

  aboutToDisappear(): void {
    this.stop()
  }

  onTargetChange(): void {
    if (!this.active || this.text.length === 0) {
      this.stop()
      this.shown = this.text
      return
    }
    this.start()
  }

  private onActiveChange(): void {
    this.stop()
    this.shown = this.text
  }

  private steps(): number {
    return Math.max(1, Math.round(this.durationMs / Math.max(1, this.stepMs)))
  }

  private stop(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId)
      this.timerId = -1
    }
  }

  private start(): void {
    this.stop()
    this.step = 0
    this.timerId = setInterval((): void => { this.tick() }, Math.max(1, this.stepMs))
  }

  private tick(): void {
    const total: number = this.steps()
    const progress: number = this.step / total
    let next: string = ''
    for (let index = 0; index < this.text.length; index++) {
      const character: string = this.text.charAt(index)
      if (character === ' ') {
        next += character
        continue
      }
      if (progress * this.text.length > index) {
        // 已经轮到它落定。
        next += character
      } else {
        const pick: number = Math.floor(Math.random() * this.charSet.length)
        next += this.charSet.charAt(pick)
      }
    }
    this.shown = next
    this.step = this.step + 1
    if (this.step > total) {
      this.stop()
      this.shown = this.text
      this.onComplete()
    }
  }

  build() {
    Text(this.shown)
      .fontSize(this.fontSize)
      .lineHeight(this.lineHeight)
      .fontColor(this.fontColor)
      .fontFamily(this.fontFamily)
      .fontWeight(this.fontWeight)
      .letterSpacing(this.letterSpacing)
  }
}
