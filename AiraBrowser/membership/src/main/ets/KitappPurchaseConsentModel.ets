import { fixedKitappSuite } from './KitappMembershipData'

export type KitappPurchaseAgreementLink = 'membership' | 'privacy' | 'renewal'
export interface KitappPurchaseConsentResult {
  accepted: boolean
  link?: KitappPurchaseAgreementLink
}
export interface KitappPurchaseConsentOptions {
  appName: string
  appPrice: string
  appIcon?: Resource | null
  suite?: boolean
  recurring?: boolean
  description?: string
  membershipTitle?: string
  isCurrent: () => boolean
}
export interface KitappPurchaseAgreement {
  key: KitappPurchaseAgreementLink
  title: string
}

/** One attempt only. A link, dismissal or stale session never counts as acceptance. */
export class KitappPurchaseConsentModel {
  name: string
  price: string
  icon: Resource | undefined
  description: string
  links: KitappPurchaseAgreement[]
  private options: KitappPurchaseConsentOptions
  private decide: (result: KitappPurchaseConsentResult) => void
  private completed: boolean = false

  constructor(options: KitappPurchaseConsentOptions, decide: (result: KitappPurchaseConsentResult) => void) {
    this.options = options
    this.decide = decide
    const suite = options.suite ? fixedKitappSuite() : undefined
    this.name = suite ? suite.offer.name : options.appName
    this.price = suite ? suite.offer.price : options.appPrice
    this.icon = (suite ? suite.offer.icon : options.appIcon) ?? undefined
    this.description = options.description || (options.recurring ?
      '自动续费，可在华为账号的订阅管理中取消。' : '一次购买，永久有效，无自动续费。')
    this.links = [
      { key: 'membership', title: options.membershipTitle || '《会员服务协议》' },
      { key: 'privacy', title: '《隐私政策》' }
    ]
    if (options.recurring) { this.links.push({ key: 'renewal', title: '《自动续费服务协议》' }) }
  }

  confirm(checked: boolean): boolean {
    if (this.completed || !checked) { return false }
    const accepted = this.isCurrent() && this.name.length > 0 && this.price.length > 0
    this.finish({ accepted })
    return accepted
  }

  openLink(link: KitappPurchaseAgreementLink): void {
    if (!this.links.some((item: KitappPurchaseAgreement): boolean => item.key === link)) { return }
    this.finish(this.isCurrent() ? { accepted: false, link } : { accepted: false })
  }

  cancel(): void { this.finish({ accepted: false }) }

  isCurrent(): boolean {
    try { return this.options.isCurrent() } catch (_) { return false }
  }

  private finish(result: KitappPurchaseConsentResult): void {
    if (this.completed) { return }
    this.completed = true
    this.decide(result)
  }
}
