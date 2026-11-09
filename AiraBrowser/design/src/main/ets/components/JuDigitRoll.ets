import { JuDigit } from './JuDigit'

/**
 * 可复用的数字滚动。传入 value 即可。
 * 变大时旧数字向上离开、新数字从下面进来；变小时相反。
 * 高位先动，低位隔 50ms。lineVp 要和所用字号的 line_height 一致（注意单位，见下）。
 */
@Component
export struct JuDigitRoll {
  @Prop @Watch('handleValue') value: number = 0
  @Prop fontSize: Resource = $r('app.float.font_size_title')
  /**
   * 每一格的高度。要和所用字号的行高一致（标题档是 30，即 line_height_title）。
   * 从资源取值要用 px2vp 换算：getNumberByName 返回的是 px，3.25 倍屏上 30 会返回 97.5，
   * 直接当 vp 用会让每格高到 97.5vp，面板被撑高、数字还被裁掉。
   */
  @Prop lineVp: number = 30
  @Prop fontColor: ResourceColor = $r('app.color.foreground')
  @Prop fontWeight: Resource = $r('app.integer.font_weight_semibold')
  /** 字族，透传给每一位。默认系统字体族；传已注册的自定义字体名即换成内置字体。 */
  @Prop fontFamily: string = 'HarmonyOS Sans'
  /**
   * 为真时，新出现的位（位数变多时新建的那一位）从 0 滚上来。入场动画用。
   * 为假时新位直接就位，只有后续值变化才滚——不然日历月份每次打开都会从 0 滚一遍。
   */
  @Prop rollIn: boolean = false
  /**
   * 固定位数。大于 0 时把 value 左侧补 padChar 到这个位数，位数不跳变。
   * 倒计时这种「05:30」要保持两位，用它。0 是不固定，按数值位数走。
   */
  @Prop fixedSlots: number = 0
  @Prop padChar: string = '0'
  @State text: string = '0'
  private ready: boolean = false

  aboutToAppear(): void {
    this.text = this.current()
    this.ready = true
  }

  handleValue(): void {
    if (!this.ready) {
      return
    }
    this.text = this.current()
  }

  /** 固定位数时左侧补零，否则按数值本身的位数。 */
  private current(): string {
    let raw = `${this.value}`
    if (this.fixedSlots > 0) {
      while (raw.length < this.fixedSlots) {
        raw = `${this.padChar}${raw}`
      }
    }
    return raw
  }

  build() {
    Row() {
      ForEach(this.slots(), (index: number) => {
        JuDigit({
          text: this.text,
          index: index,
          delay: index * 50,
          rollIn: this.rollIn,
          lineVp: this.lineVp,
          fontSize: this.fontSize,
          fontColor: this.fontColor,
          fontWeight: this.fontWeight,
          fontFamily: this.fontFamily
        })
      }, (index: number) => `${index}`)
    }
    .alignItems(VerticalAlign.Center)
  }

  private slots(): number[] {
    const list: number[] = []
    for (let index = 0; index < this.text.length; index++) {
      list.push(index)
    }
    return list
  }
}
