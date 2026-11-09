import { JuMembershipPage, JuMembershipSuite, JuSettingGroup, JuSettingItem } from 'design'
import { fixedKitappStoreSuite, KITAPP_CONTACT_EMAIL } from './KitappMembershipData'

/**
 * Kitapp 自售入口：只展示固定的全家桶资料，可悬浮在底部页签内。
 * 顶栏右侧是账号圆形入口（头像或人形图标）；恢复购买由宿主放进自己的账号面板。
 * 购买按钮默认禁用，勾选《Kitapp One 会员服务协议》后由宿主放开；已开通后显示完成提示。
 */
@Component
export struct KitappSuitePage {
  @Prop title: string = '会员'
  @Prop active: boolean = true
  /** 放在 JuTabs 等悬浮页签内时传 true，购买按钮抬升避开页签。 */
  @Prop hasTabBar: boolean = false
  /** 顶栏账号入口的头像地址；空串显示人形图标（未登录）。 */
  @Prop accountAvatar: string = ''
  /** 购买按钮不悬浮，改为价格卡下方随正文滚动的按钮。 */
  @Prop inlineAction: boolean = false
  /** 已购买全家桶；替代按钮与勾选，显示开通完成提示。 */
  @Prop owned: boolean = false
  /** 协议勾选状态；由宿主维护，勾选后才应放开购买按钮。 */
  @Prop agreementChecked: boolean = false
  @Prop @Watch('refreshSuite') actionLabel: string = '立即开通'
  @Prop @Watch('refreshSuite') actionEnabled: boolean = true
  @State private preparedSuite: JuMembershipSuite = fixedKitappStoreSuite()
  onAccount: () => void = (): void => {}
  onPurchase: () => void = (): void => {}
  onAgreementChange: (on: boolean) => void = (_on: boolean): void => {}
  onAgreementTap: () => void = (): void => {}
  onUserAgreement: () => void = (): void => {}
  onPrivacy: () => void = (): void => {}

  aboutToAppear(): void { this.refreshSuite() }

  private refreshSuite(): void {
    const suite = fixedKitappStoreSuite()
    suite.offer.actionLabel = this.actionLabel
    suite.offer.actionEnabled = this.actionEnabled
    this.preparedSuite = suite
  }

  private contactRows(): JuSettingItem[] {
    const contact = new JuSettingItem('contact', '联系我们', $r('app.media.ic_mail'), $r('app.color.sidebar_icon_teal'))
    contact.value = KITAPP_CONTACT_EMAIL
    return [contact]
  }

  @Builder
  Contact() {
    JuSettingGroup({ items: this.contactRows() })
      .margin({ top: $r('app.float.gap_section') })
  }

  build() {
    JuMembershipPage({
      title: this.title, suite: this.preparedSuite,
      suiteOnly: true, showBack: false, hasTabBar: this.hasTabBar, active: this.active,
      accountButton: true, accountAvatar: this.accountAvatar, onAccount: this.onAccount,
      inlineAction: this.inlineAction,
      agreementLabel: '《Kitapp One 会员服务协议》',
      agreementChecked: this.agreementChecked,
      onAgreementToggle: this.onAgreementChange,
      onAgreementTap: this.onAgreementTap,
      actionDone: this.owned,
      actionDoneNote: '权益已生效，在全家桶所含应用登录同一个华为账号，即可使用各自的会员功能。',
      endContent: (): void => { this.Contact() },
      onPurchase: this.onPurchase,
      onUserAgreement: this.onUserAgreement, onPrivacy: this.onPrivacy
    })
  }
}
