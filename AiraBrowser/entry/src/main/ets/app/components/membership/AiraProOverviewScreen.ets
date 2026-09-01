import {
  AiraProOverviewBenefitState,
  AiraProOverviewPlanState,
  AiraProOverviewViewState
} from '../../../core/membership/AiraProOverviewViewModel';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';

const AIRA_PRO_LOGO_SIZE: number = 76;
const AIRA_PRO_HERO_CORNER_RADIUS: number = 24;
const AIRA_PRO_BENEFIT_ICON_SIZE: number = 40;
const AIRA_PRO_BENEFIT_ICON_IMAGE_SIZE: number = 22;
const AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING: number = 16;
const AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING: number = 14;
const AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS: number = 18;
const AIRA_PRO_PLAN_RADIO_GROUP: string = 'aira_pro_overview_plan';
const AIRA_PRO_PLAN_ROW_HEIGHT: number = 86;
const AIRA_PRO_PROMOTION_PLAN_ROW_HEIGHT: number = 102;
const AIRA_PRO_PLAN_PRICE_MAX_WIDTH: number = 112;
const AIRA_PRO_PLAN_ROW_CORNER_RADIUS: number = 18;
const AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT: number = 50;
const AIRA_PRO_RESTORE_BUTTON_HEIGHT: number = 36;
const AIRA_PRO_TRANSPARENT_COLOR: string = '#00000000';

@Component
export struct AiraProOverviewScreen {
  @Prop state: AiraProOverviewViewState = {
    title: 'Aira Pro',
    subtitle: '',
    benefits: [],
    plans: [],
    proValue: '查看',
    proActivatedActionText: '已开通 Aira Pro',
    proLegalPromptText: '我已阅读并同意',
    proLegalAgreementTitle: '会员服务协议',
    proLegalRenewalTitle: '自动续费服务协议',
    proActionsEnabled: true,
    proSubscribeEnabled: true,
    lifetimeUpgradePrompt: {
      title: '升级长期会员',
      message: '',
      cancelLabel: '暂不升级',
      manageLabel: '前往关闭自动续费'
    }
  };
  @Prop surfaceBackground: ResourceColor = '#FFFFFF';
  @Prop controlBackground: ResourceColor = '#EEF2F7';
  @Prop accentColor: ResourceColor = '#0A59F7';
  @Prop onAccentColor: ResourceColor = '#FFFFFF';
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop dividerColor: ResourceColor = '#E3E8EF';
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  @State private selectedPlanId: string = 'one_time';
  @State private proTermsAccepted: boolean = false;
  scroller?: Scroller;
  onSubscribe?: (planId: string) => void;
  onOpenMembershipTerms?: () => void;
  onOpenAutoRenewalNotice?: () => void;
  onManageSubscription?: () => void;
  onRestorePurchase?: (planId: string) => void;
  onOpenDesktopGuide?: () => void;

  build() {
    SettingsScrollBody({
      contentSpace: 18,
      topPadding: 8,
      bottomPadding: 28,
      scroller: this.scroller
    }) {
      this.buildHero()
      this.buildBenefitSection()
      if (this.state.plans.length > 0) {
        this.buildPlanSection()
      }
    }
  }

  @Builder
  private buildHero() {
    Column({ space: 12 }) {
      Image(this.state.title === 'Aira Community'
        ? $r('app.media.aira_logo_brand')
        : $r('app.media.app_membership_pro_logo'))
        .width(AIRA_PRO_LOGO_SIZE)
        .height(AIRA_PRO_LOGO_SIZE)
        .objectFit(ImageFit.Contain)

      Text(this.state.title)
        .width('100%')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.state.subtitle)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.secondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 28, bottom: 28 })
    .backgroundColor(this.surfaceBackground)
    .borderRadius(AIRA_PRO_HERO_CORNER_RADIUS)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildBenefitSection() {
    SettingsSection({
      title: this.state.title === 'Aira Community' ? '本地能力' : '官方托管云服务',
      secondaryTextColor: this.secondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        ForEach(this.state.benefits, (benefit: AiraProOverviewBenefitState, index: number) => {
          this.buildBenefitRow(benefit, index, this.resolveRowPosition(index, this.state.benefits.length))
          if (index < this.state.benefits.length - 1) {
            SettingsGroupDivider({ dividerColor: this.dividerColor })
          }
        }, (benefit: AiraProOverviewBenefitState) => benefit.id)
      }
    }
  }

  @Builder
  private buildBenefitRow(
    benefit: AiraProOverviewBenefitState,
    index: number,
    rowPosition: 'single' | 'first' | 'middle' | 'last'
  ) {
    Row({ space: 14 }) {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(AIRA_PRO_BENEFIT_ICON_SIZE)
          .height(AIRA_PRO_BENEFIT_ICON_SIZE)
          .fill(this.resolveBenefitIconBackgroundColor(index))

        AiraIcon({
          airaIconId: this.resolveBenefitIcon(benefit.id),
          iconSize: AIRA_PRO_BENEFIT_ICON_IMAGE_SIZE,
          iconColor: this.onAccentColor
        })
      }
      .width(AIRA_PRO_BENEFIT_ICON_SIZE)
      .height(AIRA_PRO_BENEFIT_ICON_SIZE)

      Column({ space: 4 }) {
        Text(benefit.title)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (benefit.description.length > 0) {
          if (benefit.tutorialText.length > 0) {
            Button({ type: ButtonType.Normal }) {
              Text() {
                Span(benefit.description)
                  .fontColor(this.secondaryTextColor)
                Span(` ${benefit.tutorialText}`)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.accentColor)
              }
              .width('100%')
              .fontSize(13)
              .lineHeight(18)
              .maxLines(2)
              .textAlign(TextAlign.Start)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding(0)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .backgroundColor(AIRA_PRO_TRANSPARENT_COLOR)
            .stateEffect(true)
            .accessibilityText(`${benefit.description} ${benefit.tutorialText}`)
            .onClick(() => {
              this.onOpenDesktopGuide?.();
            })
          } else {
            Text(benefit.description)
              .width('100%')
              .fontSize(13)
              .lineHeight(18)
              .fontColor(this.secondaryTextColor)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      right: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      top: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING,
      bottom: AIRA_PRO_BENEFIT_ROW_VERTICAL_PADDING
    })
    .borderRadius(this.resolveRowBorderRadius(rowPosition))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPlanSection() {
    SettingsSection({ title: '开通方式', secondaryTextColor: this.secondaryTextColor }) {
      Column({ space: 12 }) {
        ForEach(this.state.plans, (plan: AiraProOverviewPlanState) => {
          this.buildPlanRow(plan)
        }, (plan: AiraProOverviewPlanState) => plan.id)

        this.buildLegalConsent()
        this.buildSubscriptionActions()
      }
      .width('100%')
    }
  }

  @Builder
  private buildPlanRow(plan: AiraProOverviewPlanState) {
    Row({ space: 13 }) {
      Radio({
        value: plan.id,
        group: AIRA_PRO_PLAN_RADIO_GROUP
      })
        .checked(this.selectedPlanId === plan.id)
        .enabled(this.canSelectPlan(plan))
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.accentColor
        })

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(plan.title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (plan.badgeText.length > 0) {
            Text(plan.badgeText)
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.accentColor)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(this.controlBackground)
              .borderRadius(9)
              .maxLines(1)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(plan.description)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.secondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 3 }) {
        Text(plan.priceText)
          .fontSize(plan.originalPriceText.length > 0 ? 18 : 14)
          .fontWeight(FontWeight.Bold)
          .fontColor(plan.originalPriceText.length > 0 ? this.accentColor : this.primaryTextColor)
          .textAlign(TextAlign.End)
          .maxLines(2)
          .constraintSize({ maxWidth: AIRA_PRO_PLAN_PRICE_MAX_WIDTH })
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (plan.originalPriceText.length > 0) {
          Text(plan.originalPriceText)
            .fontSize(12)
            .fontColor(this.secondaryTextColor)
            .textAlign(TextAlign.End)
            .decoration({ type: TextDecorationType.LineThrough, color: this.secondaryTextColor })
            .maxLines(1)
        }
      }
      .constraintSize({ maxWidth: AIRA_PRO_PLAN_PRICE_MAX_WIDTH })
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .height(plan.originalPriceText.length > 0 ? AIRA_PRO_PROMOTION_PLAN_ROW_HEIGHT : AIRA_PRO_PLAN_ROW_HEIGHT)
    .padding({
      left: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      right: AIRA_PRO_BENEFIT_ROW_HORIZONTAL_PADDING,
      top: 0,
      bottom: 0
    })
    .backgroundColor(this.surfaceBackground)
    .borderRadius(AIRA_PRO_PLAN_ROW_CORNER_RADIUS)
    .alignItems(VerticalAlign.Center)
    .enabled(this.canSelectPlan(plan))
    .opacity(this.canSelectPlan(plan) ? 1 : 0.52)
    .onClick(() => {
      if (this.canSelectPlan(plan)) {
        this.selectedPlanId = plan.id;
      }
    })
  }

  @Builder
  private buildLegalConsent() {
    Column({ space: 6 }) {
      if (this.selectedPlanRequiresConsent()) {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Checkbox()
            .select(this.proTermsAccepted)
            .selectedColor(this.accentColor)
            .enabled(this.canUseSelectedPlan())
            .width(18)
            .height(18)
            .onChange((selected: boolean) => {
              if (this.canUseSelectedPlan()) {
                this.proTermsAccepted = selected;
              }
            })
            .margin({ right: 6, bottom: 4 })

          Text(this.state.proLegalPromptText)
            .fontSize(12)
            .lineHeight(20)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .onClick(() => {
              this.toggleTermsAccepted();
            })
            .margin({ right: 6, bottom: 4 })

          this.buildLegalTextLink(this.state.proLegalAgreementTitle, () => {
            this.onOpenMembershipTerms?.();
          })
          if (this.shouldShowAutoRenewalNotice()) {
            Text('、')
              .fontSize(12)
              .lineHeight(20)
              .fontColor(this.secondaryTextColor)
              .maxLines(1)
              .margin({ right: 2, bottom: 4 })
            this.buildLegalTextLink(this.state.proLegalRenewalTitle, () => {
              this.onOpenAutoRenewalNotice?.();
            })
          }
        }
        .width('100%')
      }

      Text(this.resolveSubscriptionFooterText())
        .width('100%')
        .fontSize(11)
        .lineHeight(16)
        .fontColor(this.secondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 6, right: 6 })
    .opacity(this.canOpenLegal() ? 1 : 0.52)
  }

  @Builder
  private buildLegalTextLink(label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .lineHeight(20)
        .maxLines(2)
    }
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .padding(0)
    .margin({ right: 6, bottom: 4 })
    .enabled(this.canOpenLegal())
    .stateEffect(this.canOpenLegal())
    .onClick(action)
  }

  @Builder
  private buildSubscriptionActions() {
    Column({ space: 8 }) {
      this.buildSubscribeButton()
      this.buildRestorePurchaseButton()
    }
    .width('100%')
  }

  @Builder
  private buildSubscribeButton() {
    Button() {
      Text(this.resolveSubscribeButtonLabel())
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.onAccentColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.accentColor)
    .borderRadius(AIRA_PRO_SUBSCRIBE_BUTTON_HEIGHT / 2)
    .opacity(this.canSubscribe() ? 1 : 0.56)
    .enabled(this.canSubscribe())
    .stateEffect(this.canSubscribe())
    .onClick(() => {
      if (this.canSubscribe()) {
        const selectedPlan = this.resolveSelectedPlan();
        if (selectedPlan === undefined) {
          return;
        }
        if (selectedPlan.action === 'manage_subscription') {
          this.onManageSubscription?.();
          return;
        }
        this.onSubscribe?.(selectedPlan.id);
      }
    })
  }

  @Builder
  private buildRestorePurchaseButton() {
    Button() {
      Text(this.resolveRestorePurchaseLabel())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accentColor)
        .maxLines(1)
    }
    .width('100%')
    .height(AIRA_PRO_RESTORE_BUTTON_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(AIRA_PRO_TRANSPARENT_COLOR)
    .borderRadius(AIRA_PRO_RESTORE_BUTTON_HEIGHT / 2)
    .enabled(this.state.proActionsEnabled)
    .opacity(this.state.proActionsEnabled ? 1 : 0.52)
    .stateEffect(this.state.proActionsEnabled)
    .onClick(() => {
      if (this.state.proActionsEnabled) {
        const selectedPlan = this.resolveSelectedPlan();
        if (selectedPlan !== undefined) {
          this.onRestorePurchase?.(selectedPlan.id);
        }
      }
    })
  }

  private resolveBenefitIconBackgroundColor(index: number): ResourceColor {
    const colors: ResourceColor[] = [
      this.settingsIconBackgrounds.sync,
      this.settingsIconBackgrounds.userScripts,
      this.settingsIconBackgrounds.adBlocker,
      this.settingsIconBackgrounds.appearance,
      this.settingsIconBackgrounds.siteSettings,
      this.settingsIconBackgrounds.search,
      this.settingsIconBackgrounds.experiments
    ];
    return colors[index % colors.length];
  }

  private resolveBenefitIcon(id: string): AiraRenderableIconId {
    switch (id) {
      case 'cross_system_bookmark_sync':
        return 'membership.benefit.sync';
      case 'page_handoff':
        return 'browser.toolbar.sendToDesktop';
      case 'cross_device_tabs':
        return 'browser.toolbar.tabs';
      case 'aira_cloud_history':
        return 'membership.benefit.sync';
      case 'offline_page_save':
        return 'membership.benefit.experiments';
      case 'userscript_install':
        return 'membership.benefit.userScripts';
      case 'manual_element_hide':
        return 'membership.benefit.adBlocker';
      case 'local_theme_and_search':
        return 'membership.benefit.appearance';
      default:
        return 'membership.benefit.experiments';
    }
  }

  private canSelectPlan(plan: AiraProOverviewPlanState): boolean {
    return this.state.proActionsEnabled && plan.action !== 'unavailable';
  }

  private canUseSelectedPlan(): boolean {
    const selectedPlan = this.resolveSelectedPlan();
    return selectedPlan !== undefined && this.canSelectPlan(selectedPlan);
  }

  private canSubscribe(): boolean {
    const selectedPlan = this.resolveSelectedPlan();
    if (selectedPlan === undefined || !this.canSelectPlan(selectedPlan)) {
      return false;
    }
    return selectedPlan.action !== 'purchase' || this.proTermsAccepted;
  }

  private canOpenLegal(): boolean {
    return true;
  }

  private toggleTermsAccepted(): void {
    if (!this.canUseSelectedPlan() || !this.selectedPlanRequiresConsent()) {
      return;
    }
    this.proTermsAccepted = !this.proTermsAccepted;
  }

  private resolveSubscribeButtonLabel(): string {
    if (!this.state.proActionsEnabled) {
      return '当前会话不可订阅';
    }
    if (!this.state.proSubscribeEnabled) {
      return this.state.proActivatedActionText;
    }
    const selectedPlan = this.resolveSelectedPlan();
    if (selectedPlan?.action === 'purchase' && !this.proTermsAccepted) {
      return selectedPlan?.consentActionText ?? '同意协议后继续';
    }
    return selectedPlan?.actionText ?? '继续';
  }

  private resolveSubscriptionFooterText(): string {
    if (!this.state.proActionsEnabled) {
      return '当前为私密会话，请在普通会话中订阅或恢复购买。';
    }
    if (!this.state.proSubscribeEnabled) {
      return this.state.proValue;
    }
    return this.resolveSelectedPlan()?.footerText ?? '';
  }

  private resolveRestorePurchaseLabel(): string {
    return this.resolveSelectedPlan()?.purchaseKind === 'one_time' ? '恢复一次购' : '恢复订阅';
  }

  private shouldShowAutoRenewalNotice(): boolean {
    return this.resolveSelectedPlan()?.purchaseKind === 'subscription';
  }

  private selectedPlanRequiresConsent(): boolean {
    return this.resolveSelectedPlan()?.action === 'purchase';
  }

  private resolveSelectedPlan(): AiraProOverviewPlanState | undefined {
    return this.state.plans.find((plan: AiraProOverviewPlanState) => plan.id === this.selectedPlanId);
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveRowBorderRadius(position: 'single' | 'first' | 'middle' | 'last'): BorderRadiuses {
    if (position === 'single') {
      return {
        topLeft: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        topRight: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        bottomLeft: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        bottomRight: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS
      };
    }
    if (position === 'first') {
      return {
        topLeft: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        topRight: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        bottomLeft: 0,
        bottomRight: 0
      };
    }
    if (position === 'last') {
      return {
        topLeft: 0,
        topRight: 0,
        bottomLeft: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS,
        bottomRight: AIRA_PRO_BENEFIT_ROW_CORNER_RADIUS
      };
    }
    return {
      topLeft: 0,
      topRight: 0,
      bottomLeft: 0,
      bottomRight: 0
    };
  }
}
