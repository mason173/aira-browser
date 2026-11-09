import { common } from '@kit.AbilityKit'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

/**
 * 连续取值滑块。只负责一条轨道：位置由宿主持有，拖动中与松手都会回调。
 *
 * 左右内边距由调用方给（例如设置行自己缩进），组件本身贴满可用宽度，
 * 这样同一个滑块放进卡片、表单或自绘面板时不会被组件预设的边距缩两次。
 */
@Component
export struct JuSlider {
  @Prop value: number = 0
  @Prop min: number = 0
  @Prop max: number = 100
  @Prop step: number = 1
  /** false 时变淡且不响应拖动。不用 `enabled` 这个名字：和 ArkUI 通用属性方法重名。 */
  @Prop active: boolean = true
  /** `ended` 为 true 表示松手，false 表示还在拖动：宿主可以只预览、松手再落盘。 */
  onChange: (value: number, ended: boolean) => void = () => {}
  /** 订阅主题色，选中色跟着主题 hue 走，与 JuSwitch 一致。 */
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  build() {
    Slider({
      value: this.value,
      min: this.min,
      max: this.max,
      step: this.step
    })
      .width('100%')
      .selectedColor(this.roles(this.themeHue).primary)
      .trackColor($r('app.color.switch_off'))
      .blockColor($r('app.color.card'))
      .trackThickness($r('app.float.slider_track_thickness'))
      .blockSize({
        width: $r('app.float.slider_block_size'),
        height: $r('app.float.slider_block_size')
      })
      // 公共库不替宿主申请振动权限，拖动手感交给宿主自行决定。
      .enableHapticFeedback(false)
      .enabled(this.active)
      .opacity(this.active ? 1 : 0.4)
      .onChange((value: number, mode: SliderChangeMode): void => {
        this.onChange(value, mode !== SliderChangeMode.Moving)
      })
  }

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }
}
