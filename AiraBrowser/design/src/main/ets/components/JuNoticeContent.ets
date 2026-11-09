import { common } from '@kit.AbilityKit'
import { JuIcon } from './JuIcon'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

/** 确认／告知的共用正文排版，不含卡片、滚动壳或按钮。可放入 Dialog 或 Sheet。 */
@Component
export struct JuNoticeContent {
  title: string = ''
  message: string = ''
  /**
   * 弹窗左上角的图标。**不传就是默认的警示图标（alert_02_fill）**。
   *
   * 以前不传就不画图标，结果删除、退出登录这些弹窗左上角都空着——
   * 而组件里本来就带了 `?? alert_02_fill` 的回退，那个判断反而把默认图标挡住了（2026-10-19 改）。
   * 统一传面性填充版 SVG。
   */
  icon: Resource | undefined = undefined
  iconBackground: ResourceColor | undefined = undefined
  danger: boolean = false
  @BuilderParam content: () => void = this.Empty
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT

  private roles(hue: number): ThemeRoles {
    return themeRoles(hue, this.getUIContext().getHostContext() as common.Context)
  }

  build() {
    Column({ space: $r('app.float.dialog_content_gap') }) {
      // 图标不是可选的：不传就用默认警示图标，弹窗左上角不留空。
      Row() {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .linearGradient({
              direction: GradientDirection.Bottom,
              colors: [[$r('app.color.dialog_icon_gradient_top'), 0], [Color.Transparent, 1]]
            })
          JuIcon({
            name: this.icon ?? $r('app.media.alert_02_fill'),
            color: $r('app.color.dialog_icon_foreground'),
            side: $r('app.float.dialog_icon_size')
          })
        }
        .width($r('app.float.dialog_icon_plate_size'))
        .height($r('app.float.dialog_icon_plate_size'))
        .backgroundColor(this.iconBackground ??
          (this.danger ? $r('app.color.destructive') : this.roles(this.themeHue).primary))
        .borderRadius($r('app.float.dialog_icon_plate_radius'))
        .clip(true)
        .accessibilityLevel('no')
      }
      .width('100%')
      .padding($r('app.float.dialog_icon_inset'))

      Column({ space: $r('app.float.dialog_content_gap') }) {
        Text(this.title)
          .width('100%')
          .fontSize($r('app.float.dialog_font_size'))
          .lineHeight($r('app.float.dialog_line_height'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
          .textAlign(TextAlign.Start)
        if (this.message.length > 0) {
          Text(this.message)
            .width('100%')
            .fontSize($r('app.float.dialog_font_size'))
            .lineHeight($r('app.float.dialog_line_height'))
            .fontWeight($r('app.integer.font_weight_regular'))
            .fontColor($r('app.color.muted_foreground'))
            .textAlign(TextAlign.Start)
        }
        this.content()
      }
      .width('100%')
      .padding({
        left: $r('app.float.dialog_copy_inset'), right: $r('app.float.dialog_copy_inset'),
        top: $r('app.float.dialog_copy_inset'), bottom: $r('app.float.dialog_copy_bottom')
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Empty() {}
}
