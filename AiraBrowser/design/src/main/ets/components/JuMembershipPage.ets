import { JuCapsuleTab } from './JuCapsuleTab'
import { JuImmersivePage } from './JuImmersivePage'
import { JuMembershipOffer, JuMembershipSuite } from './JuMembershipModels'
import { JuCircleAction } from './JuCircleAction'
import { JuMembershipPanel } from './JuMembershipPanel'

/** 单应用／全家桶共用购买页。只展示配置并发出动作，不保存权益、联网或拉起支付。 */
@Component
export struct JuMembershipPage {
  @Prop title: string = '会员'
  @Prop app: JuMembershipOffer = new JuMembershipOffer()
  @Prop suite: JuMembershipSuite = new JuMembershipSuite()
  @Prop asDestination: boolean = false
  /** 宿主前后台状态；用于暂停评价动画。 */
  @Prop active: boolean = true
  /** 悬浮在底部页签内时传 true，底栏按钮抬升避开页签。 */
  @Prop hasTabBar: boolean = false
  /** 只展示全家桶一页；此时底部按钮触发 onPurchase。 */
  @Prop suiteOnly: boolean = false
  /** 挂载期间固定；false 临时隐藏全家桶入口与整页内容，默认保留双页。 */
  @Prop showSuite: boolean = true
  @Prop showBack: boolean = true
  /** 顶栏改用账号圆形入口（替换恢复购买）；空串头像显示人形图标。 */
  @Prop accountButton: boolean = false
  @Prop accountAvatar: string = ''
  /** 购买按钮不悬浮，改为正文里价格卡下方的滚动按钮。 */
  @Prop inlineAction: boolean = false
  /** 内联按钮下的协议勾选行标题；空串不显示。 */
  @Prop agreementLabel: string = ''
  @Prop agreementChecked: boolean = false
  /** 完成态（如已开通）：替代按钮与勾选，显示完成提示。 */
  @Prop actionDone: boolean = false
  @Prop actionDoneNote: string = ''
  /** 正文末尾的补充内容，随页面滚动并沿用页面内边距。 */
  @BuilderParam endContent: () => void = this.Empty
  /** 单应用页专属补充内容；不进入固定全家桶页。 */
  @BuilderParam appEndContent: () => void = this.Empty
  @State selectedTab: number = 0
  onBack: () => void = (): void => {}
  onPurchase: () => void = (): void => {}
  onOpenSuite: () => void = (): void => {}
  onAccount: () => void = (): void => {}
  onAgreementToggle: (on: boolean) => void = (_on: boolean): void => {}
  onAgreementTap: () => void = (): void => {}
  onRestore: (suite: boolean) => void = (_suite: boolean): void => {}
  onUserAgreement: () => void = (): void => {}
  onPrivacy: () => void = (): void => {}

  private offer(): JuMembershipOffer {
    return this.isSuite() ? this.suite.offer : this.app
  }

  private isSuite(): boolean {
    return this.suiteOnly || (this.showSuite && this.selectedTab === 1)
  }

  build() {
    JuImmersivePage({
      title: this.title,
      asDestination: this.asDestination,
      showBack: this.showBack,
      hasTabBar: this.hasTabBar,
      actions: this.accountButton ? [] : [JuCircleAction.RestorePurchase],
      showAccountAction: this.accountButton,
      accountAvatar: this.accountAvatar,
      onAccount: this.onAccount,
      onAction: (action: JuCircleAction): void => {
        if (action === JuCircleAction.RestorePurchase) { this.onRestore(this.isSuite()) }
      },
      onBack: this.onBack,
      headerContentHeight: this.suiteOnly || !this.showSuite ? $r('app.float.edge_none') : $r('app.float.membership_tabs_height'),
      headerContent: (): void => { this.Tabs() },
      footerLabel: this.inlineAction ? '' : this.offer().actionLabel,
      footerTappable: !this.inlineAction && this.offer().actionEnabled,
      onFooterTap: (): void => {
        if (!this.offer().actionEnabled) { return }
        if (this.suiteOnly || !this.isSuite()) { this.onPurchase() } else { this.onOpenSuite() }
      },
      pageCount: this.suiteOnly || !this.showSuite ? 1 : 2,
      pageIndex: this.suiteOnly || !this.showSuite ? 0 : this.selectedTab,
      onPageChange: (index: number): void => { this.selectedTab = !this.suiteOnly && this.showSuite ? index : 0 },
      pageContent: (index: number): void => { this.Panel(index) }
    })
  }

  @Builder
  Empty() {}

  @Builder
  Tabs() {
    if (!this.suiteOnly && this.showSuite) {
      Column() {
        JuCapsuleTab({
          labels: ['单应用', '全家桶'],
          selected: this.selectedTab,
          onSelect: (index: number): void => {
            if (index === this.selectedTab) { return }
            this.selectedTab = index
          }
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: $r('app.float.padding_page_compact'), right: $r('app.float.padding_page_compact') })
    }
  }


  @Builder
  Panel(index: number) {
    JuMembershipPanel({
      app: this.app, suite: this.suite, selectedTab: this.suiteOnly ? 1 : (this.showSuite ? index : 0),
      active: this.active && (this.suiteOnly || !this.showSuite || this.selectedTab === index),
      inlineAction: this.inlineAction,
      agreementLabel: this.agreementLabel,
      agreementChecked: this.agreementChecked,
      actionDone: this.actionDone,
      actionDoneNote: this.actionDoneNote,
      endContent: (): void => { this.PanelEnd(index) },
      onAction: (): void => {
        if (!this.offer().actionEnabled) { return }
        if (this.suiteOnly || !this.isSuite()) { this.onPurchase() } else { this.onOpenSuite() }
      },
      onAgreementToggle: this.onAgreementToggle,
      onAgreementTap: this.onAgreementTap,
      onUserAgreement: this.onUserAgreement, onPrivacy: this.onPrivacy
    })
  }

  @Builder
  PanelEnd(index: number) {
    if (!this.suiteOnly && (!this.showSuite || index === 0)) {
      this.appEndContent()
    }
    this.endContent()
  }
}
