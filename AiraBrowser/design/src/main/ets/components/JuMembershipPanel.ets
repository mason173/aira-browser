import { JuIcon } from './JuIcon'
import { JuMembershipApp, JuMembershipFeature, JuMembershipOffer, JuMembershipSuite, JuMembershipQuestion } from './JuMembershipModels'
import { JuButton } from './JuButton'
import { JuCheckbox } from './JuCheckbox'
import { JuSettingGroup, JuSettingItem } from './JuSettingGroup'
import { JuSettingHeading } from './JuSettingHeading'
import { JuSettingNote } from './JuSettingNote'
import { JuReviewMarquee } from './JuReviewMarquee'
import { JuLaurelBadges } from './JuLaurelBadges'
import { THEME_HUE_DEFAULT, THEME_HUE_KEY, themeRoles } from '../theme/ThemeColor'

/** 内部面板：每个横向分页独立持有显示参数，切换时不会互相替换正文。 */
@Component
export struct JuMembershipPanel {
  @Prop app: JuMembershipOffer = new JuMembershipOffer()
  @Prop suite: JuMembershipSuite = new JuMembershipSuite()
  @Prop selectedTab: number = 0
  @Prop active: boolean = true
  /** 购买按钮随正文滚动、放在价格卡下方；文案与可用状态沿用当前 offer。 */
  @Prop inlineAction: boolean = false
  /** 内联按钮下的协议勾选行标题；空串不显示。勾选状态与协议跳转由宿主维护。 */
  @Prop agreementLabel: string = ''
  @Prop agreementChecked: boolean = false
  /** 完成态（如已开通）：替代按钮与勾选，显示完成提示。 */
  @Prop actionDone: boolean = false
  @Prop actionDoneNote: string = ''
  @BuilderParam endContent: () => void = this.Empty
  @StorageProp(THEME_HUE_KEY) hue: number = THEME_HUE_DEFAULT
  onAction: () => void = (): void => {}
  onAgreementToggle: (on: boolean) => void = (_on: boolean): void => {}
  onAgreementTap: () => void = (): void => {}
  onUserAgreement: () => void = (): void => {}
  onPrivacy: () => void = (): void => {}

  private offer(): JuMembershipOffer {
    return this.selectedTab === 0 ? this.app : this.suite.offer
  }

  private featureRows(features: JuMembershipFeature[], descriptions: boolean = false): JuSettingItem[] {
    return features.map((feature: JuMembershipFeature): JuSettingItem => {
      const item = new JuSettingItem(feature.key, feature.title, feature.icon,
        feature.plate === undefined ? $r('app.color.mine_icon_blue') : feature.plate)
      item.description = descriptions ? (feature.description ?? '') : ''
      return item
    })
  }

  build() {
    this.Body()
  }

  @Builder
  Empty() {}

  private purchaseNotes(): string {
    return [this.app.priceNote, this.app.featureNote, this.app.purchaseNote]
      .filter((note: string): boolean => note.length > 0).join('\n\n')
  }

  @Builder
  Body() {
    Column() {
      this.Hero()
      if (this.offer().badges.length > 0) {
        JuLaurelBadges({ labels: this.offer().badges })
      }
      if (this.selectedTab === 0) {
        if (this.app.features.length > 0) {
          JuSettingHeading({ text: '会员功能', prominent: true })
          this.Features(this.app.features)
        }
        if (this.app.reviews.length > 0) {
          JuSettingHeading({ text: this.app.reviewTitle, prominent: true })
          JuReviewMarquee({ reviews: this.app.reviews, active: this.active })
          if (this.app.reviewNote.length > 0) {
            JuSettingNote({ text: this.app.reviewNote })
          }
        }
        if (!this.actionDone) {
          this.SinglePurchase()
        }
        if (this.inlineAction) {
          this.ActionArea()
        }
        if (!this.actionDone) {
          this.PurchaseNote()
        }
        if (this.app.questions.length > 0) {
          JuSettingHeading({ text: '购买前了解', prominent: true })
          this.Questions()
        }
      } else {
        if (!this.actionDone) {
          this.PriceCard()
          if (this.offer().priceNote.length > 0) {
            JuSettingNote({ text: this.offer().priceNote, centered: false })
          }
        }
        if (this.inlineAction) {
          this.ActionArea()
        }
        JuSettingHeading({ text: '全家桶包含的应用', prominent: true })
        this.Apps()
        if (this.suite.appsNote.length > 0) {
          JuSettingNote({ text: this.suite.appsNote, centered: false })
        }
        if (this.suite.guide.length > 0) {
          JuSettingHeading({ text: this.suite.guideTitle, prominent: true })
          this.Features(this.suite.guide, true)
        }
      }
      if (this.selectedTab === 1 && this.offer().purchaseNote.length > 0) {
        JuSettingNote({ text: this.offer().purchaseNote, centered: false })
          .margin({ top: $r('app.float.gap_section') })
      }
      this.Links()
      if (this.selectedTab === 1 && this.suite.restoreNote.length > 0) {
        JuSettingNote({ text: this.suite.restoreNote, centered: false })
      }
      this.endContent()
    }
    .width('100%')
    .padding({ left: $r('app.float.padding_page_compact'), right: $r('app.float.padding_page_compact') })
  }

  /** 随正文滚动的操作区：完成态提示，或购买按钮＋可选的协议勾选行。 */
  @Builder
  ActionArea() {
    Column({ space: $r('app.float.gap_row') }) {
      if (this.actionDone) {
        this.DoneNotice()
      } else {
        this.InlineButton()
        if (this.agreementLabel.length > 0) {
          this.AgreementRow()
        }
      }
    }
    .width('100%')
  }

  @Builder
  InlineButton() {
    JuButton({ label: this.offer().actionLabel, available: this.offer().actionEnabled,
      action: this.onAction })
      .margin({ top: $r('app.float.gap_row') })
  }

  /** 协议勾选行：勾选状态与「点协议名看全文」均交宿主处理。 */
  @Builder
  AgreementRow() {
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
      justifyContent: FlexAlign.Center }) {
      JuCheckbox({
        checked: this.agreementChecked,
        onChange: (on: boolean): void => { this.onAgreementToggle(on) }
      })
        .margin({ right: $r('app.float.gap_button_text') })
      Text('已阅读并同意')
        .fontSize($r('app.float.font_size_micro'))
        .lineHeight($r('app.float.line_height_micro'))
        .fontColor($r('app.color.muted_foreground'))
      Text(this.agreementLabel)
        .fontSize($r('app.float.font_size_micro'))
        .lineHeight($r('app.float.line_height_micro'))
        .fontWeight($r('app.integer.font_weight_medium'))
        .fontColor($r('app.color.foreground'))
        .decoration({ type: TextDecorationType.Underline })
        .onClick((): void => { this.onAgreementTap() })
    }
    .width('100%')
  }

  /** 完成态提示：绿色对勾徽章、标题（沿用 offer 的按钮文案）与说明居中纵排。 */
  @Builder
  DoneNotice() {
    Column({ space: $r('app.float.gap_title_body') }) {
      Stack() {
        JuIcon({ name: $r('app.media.shield_check_fill'), side: $r('app.float.icon_size'),
          color: $r('app.color.mine_icon_mark') })
      }
      .width($r('app.float.mine_row_icon'))
      .height($r('app.float.mine_row_icon'))
      .borderRadius($r('app.float.mine_row_icon_radius'))
      .backgroundColor($r('app.color.sidebar_icon_green'))
      .alignContent(Alignment.Center)
      Text(this.offer().actionLabel)
        .width('100%')
        .fontSize($r('app.float.font_size_body'))
        .lineHeight($r('app.float.line_height_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .textAlign(TextAlign.Center)
      if (this.actionDoneNote.length > 0) {
        Text(this.actionDoneNote)
          .width('100%')
          .fontSize($r('app.float.font_size_caption'))
          .lineHeight($r('app.float.line_height_caption'))
          .fontColor($r('app.color.muted_foreground'))
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: $r('app.float.gap_section'), bottom: $r('app.float.gap_row') })
  }

  @Builder
  Hero() {    Column() {
      if (this.offer().icon !== null) {
        Image(this.offer().icon)
          .width($r('app.float.membership_hero_icon_size'))
          .height($r('app.float.membership_hero_icon_size'))
          .objectFit(ImageFit.Contain)
          .borderRadius($r('app.float.membership_hero_icon_radius'))
          .accessibilityText(this.offer().name)
      } else {
        Stack() {
          JuIcon({ name: $r('app.media.star_fill'), side: $r('app.float.membership_app_icon_size'),
            color: themeRoles(this.hue, this.getUIContext().getHostContext()).primary })
        }
        .width($r('app.float.membership_hero_icon_size'))
        .height($r('app.float.membership_hero_icon_size'))
        .backgroundColor($r('app.color.card'))
        .borderRadius($r('app.float.membership_hero_icon_radius'))
      }
      Text(this.offer().name)
        .width('100%')
        .fontSize($r('app.float.font_size_display'))
        .lineHeight($r('app.float.line_height_display'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .textAlign(TextAlign.Center)
        .margin({ top: $r('app.float.membership_hero_title_gap') })
      Text(this.offer().summary)
        .width('100%')
        .fontSize($r('app.float.font_size_body'))
        .lineHeight($r('app.float.line_height_subtitle'))
        .fontColor($r('app.color.muted_foreground'))
        .textAlign(TextAlign.Center)
        .margin({ top: $r('app.float.membership_copy_gap') })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: $r('app.float.membership_hero_top'), bottom: $r('app.float.gap_section') })
  }

  @Builder
  PriceCard() {
    Row({ space: $r('app.float.gap_icon') }) {
      Column({ space: $r('app.float.membership_compact_copy_gap') }) {
        Text(this.offer().planTitle)
          .width('100%')
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
        Text(this.offer().period)
          .width('100%')
          .fontSize($r('app.float.font_size_micro'))
          .lineHeight($r('app.float.line_height_micro'))
          .fontColor($r('app.color.muted_foreground'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Column({ space: $r('app.float.membership_compact_copy_gap') }) {
        Text(this.offer().price)
          .fontSize($r('app.float.membership_price_size'))
          .lineHeight($r('app.float.membership_price_line_height'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
        if (this.offer().originalPrice.length > 0) {
          Text(this.offer().originalPrice)
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontColor($r('app.color.muted_foreground'))
            .decoration({ type: TextDecorationType.LineThrough })
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding($r('app.float.membership_card_padding'))
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .margin({ top: this.offer().badges.length > 0 ?
      $r('app.float.membership_suite_card_gap') : $r('app.float.edge_none') })
  }

  @Builder
  SinglePurchase() {
    Column({ space: $r('app.float.gap_icon') }) {
      Row({ space: $r('app.float.gap_icon') }) {
        Column({ space: $r('app.float.membership_copy_gap') }) {
          Text(this.app.planTitle)
            .width('100%')
            .fontSize($r('app.float.font_size_body'))
            .lineHeight($r('app.float.line_height_body'))
            .fontWeight($r('app.integer.font_weight_semibold'))
            .fontColor($r('app.color.foreground'))
          Text(this.app.period)
            .width('100%')
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontColor($r('app.color.muted_foreground'))
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Text(this.app.price)
          .fontSize($r('app.float.font_size_display'))
          .lineHeight($r('app.float.line_height_display'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.membership_card_padding'))
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .margin({ top: $r('app.float.gap_section') })
  }

  @Builder
  PurchaseNote() {
    if (this.purchaseNotes().length > 0) {
      JuSettingNote({ text: this.purchaseNotes() })
    }
  }

  @Builder
  Questions() {
    Column() {
      ForEach(this.app.questions, (question: JuMembershipQuestion, index: number) => {
        Column({ space: $r('app.float.membership_copy_gap') }) {
          Text(question.title)
            .width('100%')
            .fontSize($r('app.float.font_size_body'))
            .lineHeight($r('app.float.line_height_body'))
            .fontWeight($r('app.integer.font_weight_semibold'))
            .fontColor($r('app.color.foreground'))
          Text(question.answer)
            .width('100%')
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontColor($r('app.color.muted_foreground'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding($r('app.float.mine_row_padding'))
        if (index < this.app.questions.length - 1) {
          Row() {
            Row()
              .width('100%')
              .height($r('app.float.divider_height'))
              .backgroundColor($r('app.color.setting_separator'))
          }
          .width('100%')
          .padding({ left: $r('app.float.mine_row_padding'), right: $r('app.float.mine_row_padding') })
        }
      }, (question: JuMembershipQuestion): string => question.key)
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
  }

  @Builder
  Features(features: JuMembershipFeature[], descriptions: boolean = false) {
    JuSettingGroup({ items: this.featureRows(features, descriptions) })
  }

  @Builder
  Apps() {
    Column() {
      ForEach(this.suite.apps, (app: JuMembershipApp, index: number) => {
        Row({ space: $r('app.float.gap_icon') }) {
          Image(app.icon)
            .width($r('app.float.membership_app_icon_size'))
            .height($r('app.float.membership_app_icon_size'))
            .borderRadius($r('app.float.membership_app_icon_radius'))
            .objectFit(ImageFit.Contain)
            .accessibilityText(app.name)
          Column({ space: $r('app.float.membership_compact_copy_gap') }) {
            Text(app.name)
              .width('100%')
              .fontSize($r('app.float.font_size_body'))
              .lineHeight($r('app.float.line_height_body'))
              .fontWeight($r('app.integer.font_weight_semibold'))
              .fontColor($r('app.color.foreground'))
            Text(app.description)
              .width('100%')
              .fontSize($r('app.float.font_size_caption'))
              .lineHeight($r('app.float.line_height_caption'))
              .fontWeight($r('app.integer.font_weight_regular'))
              .fontColor($r('app.color.muted_foreground'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(app.price)
            .fontSize($r('app.float.membership_app_price_size'))
            .lineHeight($r('app.float.membership_app_price_line_height'))
            .fontWeight($r('app.integer.font_weight_semibold'))
            .fontColor($r('app.color.foreground'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding($r('app.float.mine_row_padding'))
        if (index < this.suite.apps.length - 1 || this.suite.futureAppsTitle.length > 0) {
          Row() {
            Row()
              .width('100%')
              .height($r('app.float.divider_height'))
              .backgroundColor($r('app.color.setting_separator'))
          }
          .width('100%')
          .padding({ left: $r('app.float.mine_row_padding'), right: $r('app.float.mine_row_padding') })
        }
      }, (app: JuMembershipApp): string => app.key)
      if (this.suite.futureAppsTitle.length > 0) {
        this.FutureApps()
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
  }

  @Builder
  FutureApps() {
    Row({ space: $r('app.float.gap_icon') }) {
      Stack() {
        JuIcon({ name: $r('app.media.grid_view_fill'), side: $r('app.float.icon_size'),
          color: $r('app.color.mine_icon_mark') })
      }
      .width($r('app.float.membership_app_icon_size'))
      .height($r('app.float.membership_app_icon_size'))
      .backgroundColor($r('app.color.sidebar_icon_purple'))
      .borderRadius($r('app.float.membership_app_icon_radius'))
      .accessibilityLevel('no-hide-descendants')
      Column({ space: $r('app.float.membership_compact_copy_gap') }) {
        Text(this.suite.futureAppsTitle)
          .width('100%')
          .fontSize($r('app.float.font_size_body'))
          .lineHeight($r('app.float.line_height_body'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
        if (this.suite.futureAppsDescription.length > 0) {
          Text(this.suite.futureAppsDescription)
            .width('100%')
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontColor($r('app.color.muted_foreground'))
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding($r('app.float.mine_row_padding'))
  }

  @Builder
  Links() {
    Column() {
      Row() {
        JuButton({ label: '用户协议', text: true, subtle: true, action: this.onUserAgreement })
          .layoutWeight(1)
        JuButton({ label: '隐私政策', text: true, subtle: true, action: this.onPrivacy })
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .margin({ top: $r('app.float.gap_row') })
  }
}
