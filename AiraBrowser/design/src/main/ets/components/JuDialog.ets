import { JuNoticeContent } from './JuNoticeContent'
import { JuButton } from './JuButton'

/** 通用提示／确认弹窗。业务只提供内容参数和回调，样式统一维护于此。 */
@Component
export struct JuDialog {
  title: string = ''
  message: string = ''
  /** 提示图案统一传面性填充版 SVG（*_fill），不使用描边图标。 */
  icon: Resource | undefined = undefined
  /** 可选的图标底色，仅调整图标，不改变按钮的危险操作语义。 */
  iconBackground: ResourceColor | undefined = undefined
  confirmLabel: string = '确定'
  /** 留空时只显示一个确认按钮，用于信息提示。 */
  cancelLabel: string = ''
  /** 危险操作使用红色图标底与确认文字，按钮仍是灰底。 */
  danger: boolean = false
  onConfirm: () => void = (): void => {}
  onCancel: () => void = (): void => {}
  /** 兼容输入型弹窗：不传 title 时，只提供卡片壳，正文由业务传入。 */
  @BuilderParam content: () => void = this.Empty

  build() {
    Column() {
      Column() {
        if (this.title.length > 0) {
          this.Confirmation()
        } else {
          this.content()
        }
      }
      .width('100%')
      .padding(this.title.length > 0 ? $r('app.float.dialog_padding') : $r('app.float.padding_dialog'))
      .constraintSize({
        maxWidth: this.title.length > 0 ? '100%' : $r('app.float.dialog_max_width')
      })
      .backgroundColor($r('app.color.card'))
      .borderRadius($r('app.float.dialog_radius'))
      .clip(true)
    }
    .width('100%')
    .padding({
      left: this.title.length > 0 ? $r('app.float.dialog_screen_inset') : $r('app.float.padding_input'),
      right: this.title.length > 0 ? $r('app.float.dialog_screen_inset') : $r('app.float.padding_input')
    })
  }

  @Builder
  Confirmation() {
    Column({ space: $r('app.float.dialog_content_gap') }) {
      JuNoticeContent({
        title: this.title,
        message: this.message,
        icon: this.icon,
        iconBackground: this.iconBackground,
        danger: this.danger
      })
      Row({ space: $r('app.float.dialog_action_gap') }) {
        if (this.cancelLabel.length > 0) {
          this.Action(this.cancelLabel, false, this.onCancel)
        }
        this.Action(this.confirmLabel, this.danger, this.onConfirm)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Action(label: string, danger: boolean, action: () => void) {
    JuButton({ label, confirmation: true, danger, action })
      .layoutWeight(1)
  }

  @Builder
  Empty() {
  }
}
