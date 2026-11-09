import { curves } from '@kit.ArkUI'

/** 数字滚动的内部单格，不从 design 入口导出。 */
@Component
export struct JuDigit {
  @Prop @Watch('onText') text: string = '0'
  @Prop index: number = 0
  @Prop delay: number = 0
  @Prop rollIn: boolean = false
  @Prop lineVp: number = 30
  @Prop fontSize: Resource = $r('app.float.font_size_title')
  @Prop fontColor: ResourceColor = $r('app.color.foreground')
  @Prop fontWeight: Resource = $r('app.integer.font_weight_semibold')
  /** 字族。默认取系统字体族（HarmonyOS Sans），传自定义字体名可换成内置字体。 */
  @Prop fontFamily: string = 'HarmonyOS Sans'
  /** 当前滚到第几位（0~9）。这个一变就会滚过去。 */
  @State shown: number = 0
  private play: boolean = false
  private strip: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9']

  aboutToAppear(): void {
    if (this.rollIn) {
      // 新建的位：先停在 0，一帧后滚到目标，位数变多时新位也有滚动。
      this.shown = 0
      setTimeout(() => {
        this.play = true
        this.shown = this.place()
      }, 32)
    } else {
      this.shown = this.place()
      this.play = true
    }
  }

  onText(): void {
    if (!this.play) {
      return
    }
    this.shown = this.place()
  }

  build() {
    Column() {
      Column() {
        ForEach(this.strip, (digit: string) => {
          Text(digit)
            .height(this.lineVp)
            .fontSize(this.fontSize)
            .lineHeight(this.lineVp)
            .fontWeight(this.fontWeight)
            .fontColor(this.fontColor)
            .fontFamily(this.fontFamily)
            .textAlign(TextAlign.Center)
        }, (digit: string) => digit)
      }
      .translate({ y: -this.shown * this.lineVp })
      .animation({
        duration: this.play ? 270 : 0,
        delay: this.play ? this.delay : 0,
        curve: curves.cubicBezierCurve(0.26, 0.08, 0.25, 1)
      })
    }
    .height(this.lineVp)
    .clip(true)
  }

  private place(): number {
    const raw = this.index < this.text.length ? this.text.charAt(this.index) : '0'
    const parsed = Number.parseInt(raw)
    if (Number.isNaN(parsed) || parsed < 0 || parsed > 9) {
      return 0
    }
    return parsed
  }
}
