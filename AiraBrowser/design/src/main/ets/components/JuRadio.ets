import { common } from '@kit.AbilityKit'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

/** 单选。同一组里同时只能选中一个，不是勾选。 */
@Component
export struct JuRadio {
  @Prop checked: boolean = false
  @Prop group: string = 'radio'
  @Prop value: string = ''
  onPick: (on: boolean) => void = () => {}
  /** 订阅主题色，值一变就重渲染。默认 -1 = 原品牌色 token。 */
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  build() {
    Radio({
      value: this.value,
      group: this.group,
      indicatorType: RadioIndicatorType.DOT
    })
      .checked(this.checked)
      .width($r('app.float.icon_size'))
      .height($r('app.float.icon_size'))
      .radioStyle({
        checkedBackgroundColor: this.roles(this.themeHue).checkboxOn,
        uncheckedBorderColor: $r('app.color.checkbox_off'),
        indicatorColor: this.roles(this.themeHue).onPrimary
      })
      .onChange((on: boolean) => {
        this.onPick(on)
      })
  }

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }
}
