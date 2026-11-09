import { JuReview } from './JuReviewModels'

/** 会员页的纯展示配置。价格由宿主格式化，支付与权益校验由宿主处理。 */
export interface JuMembershipFeature {
  key: string
  title: string
  /** 开通步骤的可选详情；会员功能行仅展示标题与图标。 */
  description?: string
  icon: Resource
  /** 设置行图标底色；不传时沿用设置组默认蓝色。 */
  plate?: Resource
}

export interface JuMembershipApp {
  key: string
  name: string
  description: string
  price: string
  icon: Resource
}

export interface JuMembershipQuestion {
  key: string
  title: string
  answer: string
}

export class JuMembershipOffer {
  name: string = ''
  icon: Resource | null = null
  planTitle: string = '终身会员'
  summary: string = ''
  /** 简介下的双麦穗产品短语；默认空，不显示装饰区。 */
  badges: string[] = []
  price: string = ''
  /** 宿主计算并格式化的单独购买合计；为空时不显示划线原价。 */
  originalPrice: string = ''
  period: string = '一次买断 · 永久使用'
  priceNote: string = ''
  features: JuMembershipFeature[] = []
  reviews: JuReview[] = []
  reviewTitle: string = '用户评价'
  reviewNote: string = ''
  featureNote: string = ''
  purchaseNote: string = ''
  questions: JuMembershipQuestion[] = []
  actionLabel: string = '立即购买'
  actionEnabled: boolean = true
}

export class JuMembershipSuite {
  offer: JuMembershipOffer = new JuMembershipOffer()
  apps: JuMembershipApp[] = []
  /** 非空时在应用列表末尾展示未来应用预告，不带价格。 */
  futureAppsTitle: string = ''
  futureAppsDescription: string = ''
  appsNote: string = ''
  guideTitle: string = ''
  guide: JuMembershipFeature[] = []
  restoreNote: string = ''
}
