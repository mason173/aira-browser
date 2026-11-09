import { common } from '@kit.AbilityKit'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

@Component
export struct JuSwitch {
  @Prop isOn: boolean = false
  onChange: (on: boolean) => void = () => {}
  /** 订阅主题色，值一变就重渲染。默认 -1 = 原品牌色 token。 */
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  build() {
    Toggle({ type: ToggleType.Switch, isOn: this.isOn })
      .width($r('app.float.switch_width'))
      .height($r('app.float.switch_height'))
      .selectedColor(this.roles(this.themeHue).switchOn)
      .switchPointColor($r('app.color.card'))
      .switchStyle({
        pointColor: $r('app.color.card'),
        unselectedColor: $r('app.color.switch_off'),
        pointRadius: $r('app.float.switch_point_radius'),
        trackBorderRadius: $r('app.float.switch_track_radius')
      })
      .onChange((on: boolean) => {
        this.onChange(on)
      })
  }

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }
}
