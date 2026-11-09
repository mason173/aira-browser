import { JuDialog } from './JuDialog'

/** 长任务等待弹窗。宿主控制打开/关闭与任务生命周期，不展示操作按钮或虚假进度。 */
@CustomDialog
export struct JuLoadingDialog {
  controller: CustomDialogController
  @Prop message: string = '正在处理'

  build() {
    JuDialog({ content: (): void => { this.Body() } })
  }

  @Builder
  Body() {
    Row({ space: $r('app.float.gap_icon') }) {
      Text(this.message)
        .fontSize($r('app.float.font_size_body'))
        .lineHeight($r('app.float.line_height_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .layoutWeight(1)
      LoadingProgress()
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
        .color($r('app.color.muted_foreground'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
