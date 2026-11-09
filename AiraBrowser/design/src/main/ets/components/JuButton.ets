import { common } from '@kit.AbilityKit'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

@Component
export struct JuButton {
  @Prop label: string = ''
  primary: boolean = true
  /** 中性高对比主操作（例如隐私确认）；不改变其他主按钮的主题色。 */
  monochrome: boolean = false
  text: boolean = false
  /** 次要文字入口：小号、中性色，保留完整按钮触控区。仅 text 模式生效。 */
  subtle: boolean = false
  /** 确认／告知的中性灰胶囊，Dialog 与 Sheet 共用；危险操作只改变文字色。 */
  confirmation: boolean = false
  /** 清除、删除。浅红底，红字。solid 时才是实心红底、白字。 */
  danger: boolean = false
  solid: boolean = false
  /** 为假时是禁用，不接收点击。主按钮用浅主色底。 */
  @Prop available: boolean = true
  /** 点击回调。 */
  action: () => void = () => {}
  /** 订阅主题色，值一变就重渲染。默认 -1 = 原品牌色 token。 */
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }

  build() {
    Column() {
      if (this.text) {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize(this.subtle ? $r('app.float.font_size_caption') : $r('app.float.font_size_button'))
          // Button.fontWeight 不吃 Resource：500 = font_weight_medium，600 = font_weight_semibold
          .fontWeight(this.subtle ? 500 : 600)
          .fontColor(this.danger && this.available ? $r('app.color.destructive') :
            this.available && !this.subtle ? this.roles(this.themeHue).primary : $r('app.color.muted_foreground'))
          .backgroundColor(Color.Transparent)
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      } else if (this.confirmation) {
        Button({ type: ButtonType.Capsule }) {
          Text(this.label)
            .fontSize($r('app.float.dialog_font_size'))
            .lineHeight($r('app.float.dialog_line_height'))
            .fontWeight($r('app.integer.font_weight_medium'))
            .fontColor(!this.available ? $r('app.color.muted_foreground') :
              (this.danger ? $r('app.color.destructive') : $r('app.color.foreground')))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height($r('app.float.button_height'))
        .borderRadius($r('app.float.button_radius'))
        .padding({ left: $r('app.float.dialog_action_padding'), right: $r('app.float.dialog_action_padding') })
        .backgroundColor($r('app.color.dialog_action_background'))
      } else if (this.danger && this.solid && this.available) {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize($r('app.float.font_size_button'))
          .fontWeight(600)
          .fontColor($r('app.color.destructive_foreground'))
          .backgroundColor($r('app.color.destructive'))
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      } else if (this.danger && this.available) {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize($r('app.float.font_size_button'))
          .fontWeight(600)
          .fontColor($r('app.color.destructive'))
          .backgroundColor($r('app.color.destructive_soft'))
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      } else if (this.primary && this.available) {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize($r('app.float.font_size_button'))
          // Button.fontWeight 不吃 Resource，只能用数字。600 = font_weight_semibold
          .fontWeight(600)
          .fontColor(this.monochrome ? $r('app.color.background') : this.roles(this.themeHue).onPrimary)
          .backgroundColor(this.monochrome ? $r('app.color.foreground') : this.roles(this.themeHue).primary)
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      } else if (!this.available) {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize($r('app.float.font_size_button'))
          .fontWeight(600)
          .fontColor(this.primary ? this.roles(this.themeHue).primary : $r('app.color.muted_foreground'))
          .backgroundColor(this.primary ? this.roles(this.themeHue).disabled : $r('app.color.secondary'))
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      } else {
        Button(this.label)
          .type(ButtonType.Capsule)
          .width('100%')
          .height($r('app.float.button_height'))
          .borderRadius($r('app.float.button_radius'))
          .fontSize($r('app.float.font_size_button'))
          // Button.fontWeight 不吃 Resource，只能用数字。600 = font_weight_semibold
          .fontWeight(600)
          .fontColor($r('app.color.secondary_foreground'))
          .backgroundColor($r('app.color.secondary'))
          .border({ width: $r('app.float.border_width'), color: $r('app.color.border') })
          .padding({
            left: $r('app.float.padding_button'),
            right: $r('app.float.padding_button')
          })
      }
    }
    .width('100%')
    .enabled(this.available)
    .hitTestBehavior(this.available ? HitTestMode.Default : HitTestMode.None)
    .onClick(this.action)
  }
}
