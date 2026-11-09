import { JuMembershipPage, JuMembershipOffer, JuMembershipSuite, JuSettingNote, JuSettingGroup, JuSettingItem } from 'design'
import { completeKitappAppOffer, createKitappAppOffer, fixedKitappSuite, fixedKitappInAppSuite } from './KitappMembershipData'

/** 产品统一入口：只能配置单应用资料和动作，全家桶内容由共享模块固定。 */
@Component
export struct KitappMembershipPage {
  @Prop @Watch('refreshOffer') app: JuMembershipOffer = createKitappAppOffer()
  @State private preparedApp: JuMembershipOffer = createKitappAppOffer()
  /** 已完成服务端接入的宿主启用本应用内售卖；默认保留商店入口。 */
  @Prop @Watch('refreshOffer') suitePurchaseEnabled: boolean = false
  @Prop @Watch('refreshOffer') suiteOwned: boolean = false
  @Prop @Watch('refreshOffer') paymentBusy: boolean = false
  @State private preparedSuite: JuMembershipSuite = fixedKitappSuite()
  @Prop asDestination: boolean = false
  @Prop active: boolean = true
  /** 临时隐藏全家桶页；恢复 true 即重新显示，挂载期间固定。 */
  @Prop showSuite: boolean = true
  /** 宿主联系邮箱；空串不显示，非空时在协议下方展示居中小字。 */
  @Prop contactEmail: string = ''
  /** 本应用附加入口，如其他订阅方案、兑换和订阅管理；仅出现在单应用页。 */
  @Prop appActions: JuSettingItem[] = []
  onAppAction: (key: string) => void = (_key: string): void => {}
  onBack: () => void = (): void => {}
  onPurchase: () => void = (): void => {}
  onOpenSuite: () => void = (): void => {}
  onRestore: (suite: boolean) => void = (_suite: boolean): void => {}
  onUserAgreement: () => void = (): void => {}
  onPrivacy: () => void = (): void => {}

  aboutToAppear(): void { this.refreshOffer() }

  private refreshOffer(): void {
    const app = completeKitappAppOffer(this.app)
    if (this.paymentBusy) { app.actionEnabled = false; app.actionLabel = '正在处理' }
    this.preparedApp = app
    this.preparedSuite = this.suitePurchaseEnabled
      ? fixedKitappInAppSuite(this.suiteOwned, this.paymentBusy) : fixedKitappSuite()
  }

  @Builder
  Contact() {
    if (this.contactEmail.length > 0) {
      JuSettingNote({ text: `联系邮箱：${this.contactEmail}`, centered: true })
    }
  }

  @Builder
  AppActions() {
    if (this.appActions.length > 0) {
      JuSettingGroup({
        items: this.appActions,
        onSelect: (key: string): void => {
          const item = this.appActions.find((row: JuSettingItem): boolean => row.key === key)
          if (this.active && !this.paymentBusy && item !== undefined && item.enabled) {
            this.onAppAction(key)
          }
        }
      })
    }
  }

  build() {
    JuMembershipPage({
      app: this.preparedApp, suite: this.preparedSuite,
      asDestination: this.asDestination, active: this.active, showSuite: this.showSuite,
      endContent: (): void => { this.Contact() },
      appEndContent: (): void => { this.AppActions() },
      onBack: this.onBack, onPurchase: this.onPurchase, onOpenSuite: this.onOpenSuite,
      onRestore: this.onRestore, onUserAgreement: this.onUserAgreement, onPrivacy: this.onPrivacy
    })
  }
}
