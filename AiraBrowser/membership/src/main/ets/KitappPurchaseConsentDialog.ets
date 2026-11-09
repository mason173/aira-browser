import { common } from '@kit.AbilityKit'
import {
  JuDialog, JuButton, JuCheckbox, JuSettingNote, JuIcon,
  ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles
} from 'design'
import { KitappPurchaseAgreement, KitappPurchaseConsentModel } from './KitappPurchaseConsentModel'

@Component
struct KitappPurchaseConsentDialog {
  @Prop model: KitappPurchaseConsentModel = new KitappPurchaseConsentModel(
    { appName: '', appPrice: '', isCurrent: (): boolean => false }, (): void => {})
  @State private agreed: boolean = false
  @State private finishing: boolean = false
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }

  @Builder
  Product() {
    Row({ space: $r('app.float.gap_icon') }) {
      if (this.model.icon !== undefined) {
        Image(this.model.icon)
          .width($r('app.float.membership_app_icon_size'))
          .height($r('app.float.membership_app_icon_size'))
          .borderRadius($r('app.float.membership_app_icon_radius'))
          .objectFit(ImageFit.Cover)
          .draggable(false)
          .accessibilityLevel('no')
      } else {
        JuIcon({ name: $r('app.media.ic_wallet_fill'), color: this.roles(this.themeHue).primary,
          side: $r('app.float.membership_app_icon_size') })
      }
      Column({ space: $r('app.float.gap_button_text') }) {
        Text(this.model.name)
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontWeight($r('app.integer.font_weight_medium'))
          .fontColor($r('app.color.foreground'))
          .width('100%')
        Text(this.model.price)
          .fontSize($r('app.float.font_size_display'))
          .lineHeight($r('app.float.line_height_display'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding($r('app.float.membership_card_padding'))
    .backgroundColor($r('app.color.secondary'))
    .borderRadius($r('app.float.input_radius'))
  }

  @Builder
  Agreement() {
    Row({ space: $r('app.float.gap_button_text') }) {
      JuCheckbox({ checked: this.agreed, onChange: (on: boolean): void => { this.agreed = on } })
      Text() {
        Span('我已阅读并同意')
        ForEach(this.model.links, (link: KitappPurchaseAgreement) => {
          Span(link.title)
            .fontColor(this.roles(this.themeHue).primary)
            .decoration({ type: TextDecorationType.Underline })
            .onClick((): void => { this.model.openLink(link.key) })
        }, (link: KitappPurchaseAgreement): string => link.key)
      }
      .fontSize($r('app.float.font_size_caption'))
      .lineHeight($r('app.float.line_height_caption'))
      .fontColor($r('app.color.muted_foreground'))
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  Actions() {
    Row({ space: $r('app.float.dialog_action_gap') }) {
      JuButton({ label: '取消', confirmation: true, action: (): void => { this.model.cancel() } })
        .layoutWeight(1)
      JuButton({ label: '确认购买', available: this.agreed && !this.finishing,
        action: (): void => { this.finishing = this.model.confirm(this.agreed) } })
        .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  Body() {
    Column({ space: $r('app.float.gap_title_body') }) {
      Text('确认购买')
        .fontSize($r('app.float.dialog_font_size'))
        .lineHeight($r('app.float.dialog_line_height'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
      Column() {
        this.Product()
        JuSettingNote({ text: this.model.description })
      }
      .width('100%')
      this.Agreement()
      this.Actions()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() { JuDialog({ content: (): void => { this.Body() } }) }
}

@Builder
export function kitappPurchaseConsentBuilder(model: KitappPurchaseConsentModel) {
  KitappPurchaseConsentDialog({ model })
}
