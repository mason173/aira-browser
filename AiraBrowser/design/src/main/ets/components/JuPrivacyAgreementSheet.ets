import { JuImmersiveSheet } from './JuImmersiveSheet'
import { JuNoticeContent } from './JuNoticeContent'

/** 一条由宿主声明的真实信息处理摘要。组件不假定每个应用的数据行为。 */
export interface JuPrivacySummary {
  title: string
  message: string
}

/**
 * 可复用的「隐私与用户协议」Sheet 内容，包含图标、摘要、协议链接和沉浸式双按钮。
 * 不依赖业务模块，不联网、不保存同意、不自行关闭或退出；bindSheet 和业务门控归宿主。
 */
@Component
export struct JuPrivacyAgreementSheet {
  appName: string = ''
  summaries: JuPrivacySummary[] = []
  privacyUrl: string = ''
  userAgreementUrl: string = ''
  /** 宿主提供后续查看协议的入口说明；不同项目无需沿用同一路径。 */
  reviewHint: string = ''
  onOpenLink: (url: string) => void = (_url: string): void => {}
  onAccept: () => void = (): void => {}
  onDecline: () => void = (): void => {}

  build() {
    JuImmersiveSheet({
      showTitleBar: false,
      actions: [],
      contentInset: $r('app.float.sheet_card_inset'),
      contentTopInset: $r('app.float.privacy_copy_inset'),
      footerLabel: '同意并继续',
      secondaryLabel: '不同意',
      footerTappable: true,
      onFooterTap: (): void => { this.onAccept() },
      onSecondaryFooterTap: (): void => { this.onDecline() },
      content: (): void => { this.Body() }
    })
  }

  @Builder
  Body() {
    JuNoticeContent({
      title: '隐私与用户协议',
      icon: $r('app.media.shield_check_fill'),
      iconBackground: $r('app.color.mine_icon_blue'),
      content: (): void => { this.Copy() }
    })
  }

  @Builder
  Copy() {
    Column() {
      Text(`欢迎使用 ${this.appName}。开始前，请了解我们如何处理您的信息。`)
        .fontSize($r('app.float.font_size_body'))
        .lineHeight($r('app.float.privacy_copy_line_height'))
        .fontColor($r('app.color.foreground'))
        .margin({ bottom: $r('app.float.privacy_copy_gap') })

      ForEach(this.summaries, (summary: JuPrivacySummary) => {
        this.Summary(summary.title, summary.message)
      })

      Text() {
        Span('请阅读')
        Span('《隐私政策》')
          .decoration({ type: TextDecorationType.Underline })
          .fontWeight($r('app.integer.font_weight_medium'))
          .onClick((): void => { this.onOpenLink(this.privacyUrl) })
        Span('与')
        Span('《用户服务协议》')
          .decoration({ type: TextDecorationType.Underline })
          .fontWeight($r('app.integer.font_weight_medium'))
          .onClick((): void => { this.onOpenLink(this.userAgreementUrl) })
        Span(`。点击「同意并继续」，表示您已阅读并同意上述协议。${this.reviewHint}`)
      }
      .fontSize($r('app.float.font_size_caption'))
      .lineHeight($r('app.float.privacy_copy_line_height'))
      .fontColor($r('app.color.foreground'))
      .margin({ top: $r('app.float.gap_button_text') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Summary(title: string, message: string) {
    Column() {
      Text(title)
        .fontSize($r('app.float.font_size_caption'))
        .lineHeight($r('app.float.line_height_body'))
        .fontWeight($r('app.integer.font_weight_medium'))
        .fontColor($r('app.color.foreground'))
      Text(message)
        .fontSize($r('app.float.font_size_caption'))
        .lineHeight($r('app.float.line_height_body'))
        .fontColor($r('app.color.foreground'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: $r('app.float.gap_button') })
  }
}
