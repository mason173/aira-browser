import { common } from '@kit.AbilityKit'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

@Component
export struct JuCheckbox {
  @Prop checked: boolean = false
  /** 只是分组名，系统不会因此变成单选。每一项要各用各的名字。 */
  @Prop group: string = 'checks'
  /** 选中时的填充色。不传就是默认的 checkbox_on，列表里按优先级传。 */
  @Prop markColor: ResourceColor = $r('app.color.checkbox_on')
  onChange: (on: boolean) => void = () => {}
  /** 订阅主题色，值一变就重渲染。默认 -1 = 原品牌色 token。 */
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  build() {
    Checkbox({ name: this.group, group: this.group })
      .select(this.checked)
      .width($r('app.float.icon_size'))
      .height($r('app.float.icon_size'))
      .selectedColor(this.roles(this.themeHue).checkboxOn)
      .unselectedColor(this.markColor)
      .shape(CheckBoxShape.CIRCLE)
      .onChange((on: boolean) => {
        this.onChange(on)
      })
  }

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }
}
