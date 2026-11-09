import { JuMembershipOffer, JuMembershipSuite, JuMembershipFeature, JuReview } from 'design'

export const KITAPP_BUNDLE_NAME: string = 'app.kitapp.hub'
export const KITAPP_CONTACT_EMAIL: string = 'mason.life@proton.me'

/** 公共示例评价和头像，所有接入项目默认保留完整滚动板块。 */
function defaultReviews(): JuReview[] {
  return [
    { key: 'clear', author: '小禾', avatar: $r('app.media.km_review_avatar_clear'), rating: 5,
      title: '清晰又顺手', message: '常用的事情打开就能找到，操作很直接，日常用起来很省心。' },
    { key: 'spending', author: '阿远', avatar: $r('app.media.km_review_avatar_spending'), rating: 5,
      title: '细节很用心', message: '功能安排得很清楚，花一点时间整理好，之后使用就轻松多了。' },
    { key: 'simple', author: '木木', avatar: $r('app.media.km_review_avatar_simple'), rating: 5,
      title: '刚刚好的简洁', message: '不用研究复杂的操作，界面清爽，正好是我喜欢的风格。' },
    { key: 'cycles', author: '周末同学', avatar: $r('app.media.km_review_avatar_cycles'), rating: 5,
      title: '每天都会打开', message: '把零散的事情放在一起，需要的时候一眼就能看清，很适合日常使用。' },
    { key: 'tidy', author: '南风', avatar: $r('app.media.km_review_avatar_tidy'), rating: 5,
      title: '让日常更有条理', message: '没有多余的打扰，简单几步就能完成操作，使用起来很舒服。' }
  ]
}

/** 单应用配置起点；宿主只替换自己的资料，标准板块默认完整。 */
export function createKitappAppOffer(): JuMembershipOffer {
  const offer = new JuMembershipOffer()
  offer.badges = ['专注日常体验', '坚持简洁设计']
  offer.reviewTitle = '用户评价 · 示例'
  offer.reviews = defaultReviews()
  return offer
}

/** 内部标准化：不修改宿主对象；漏填评价仍保留轮播，功能图标底色统一分配。 */
export function completeKitappAppOffer(source: JuMembershipOffer): JuMembershipOffer {
  const offer = createKitappAppOffer()
  offer.name = source.name
  offer.icon = source.icon
  offer.planTitle = source.planTitle
  offer.summary = source.summary
  // badges 仍保留"空则用默认标语"：那是定位短语，属于成品页的文案，宿主要覆盖就传自己的。
  // 评价不一样——下面 reviews 那段不再回填，因为那会变成"替宿主编用户评价"。
  offer.badges = source.badges.length > 0 ? source.badges : offer.badges
  offer.price = source.price
  offer.period = source.period
  offer.priceNote = source.priceNote
  const plates: Resource[] = [$r('app.color.mine_icon_blue'), $r('app.color.sidebar_icon_orange'),
    $r('app.color.sidebar_icon_purple'), $r('app.color.sidebar_icon_green')]
  offer.features = source.features.map((feature: JuMembershipFeature, index: number): JuMembershipFeature => {
    return { key: feature.key, title: feature.title, icon: feature.icon, plate: plates[index % plates.length] }
  })
  // 同上：宿主没给评价就一条都不显示（面板本身对空数组是不渲染的）。
  // 只给评价补一个通用的头像插画——那是样式默认值，不是编造内容。
  const portraits: Resource[] = [$r('app.media.km_review_avatar_clear'), $r('app.media.km_review_avatar_spending'),
    $r('app.media.km_review_avatar_simple'), $r('app.media.km_review_avatar_cycles'), $r('app.media.km_review_avatar_tidy')]
  offer.reviews = source.reviews.map((review: JuReview, index: number): JuReview => {
    return { key: review.key, author: review.author, avatar: review.avatar ?? portraits[index % portraits.length],
      rating: review.rating, title: review.title, message: review.message }
  })
  offer.reviewTitle = source.reviewTitle.length > 0 ? source.reviewTitle : offer.reviewTitle
  offer.reviewNote = source.reviewNote
  offer.featureNote = source.featureNote
  offer.purchaseNote = source.purchaseNote
  offer.questions = source.questions
  offer.actionLabel = source.actionLabel
  offer.actionEnabled = source.actionEnabled
  return offer
}

function price(cents: number): string {
  return `¥${(cents / 100).toFixed(1).replace(/\.0$/, '')}`
}

/** 固定全家桶唯一来源。仅内部使用；不从公共入口导出，不接受宿主覆盖。 */
export function fixedKitappSuite(): JuMembershipSuite {
  const prices: number[] = [6880, 3880, 0, 2880, 1800]
  const suite = new JuMembershipSuite()
  suite.offer.name = 'Kitapp One'
  suite.offer.icon = $r('app.media.km_membership_kitapp')
  suite.offer.planTitle = '全家桶终身会员'
  suite.offer.summary = '一次买断，畅享旗下应用。'
  suite.offer.badges = ['多款应用协同', '持续完善体验']
  suite.offer.price = '¥68.8'
  suite.offer.originalPrice = price(prices.reduce((sum: number, value: number): number => sum + value, 0))
  suite.offer.actionLabel = '立即购买'
  suite.offer.purchaseNote = '请先下载 Kitapp，在 Kitapp 内开通全家桶，再到以下应用登录同一华为账号使用会员功能。此页仅展示方案，不在当前应用内扣款；开通与各应用权益以上线时为准，无自动续费。'
  suite.apps = [
    { key: 'aira', name: 'Aira', description: '浏览器', price: price(prices[0]), icon: $r('app.media.km_membership_aira') },
    { key: 'pinecone', name: '松果清单', description: '待办与习惯', price: price(prices[1]), icon: $r('app.media.km_membership_pinecone') },
    { key: 'shengxi', name: '声栖', description: '助眠与专注', price: '限时免费', icon: $r('app.media.km_membership_shengxi') },
    { key: 'subdock', name: 'SubDock', description: '订阅管理', price: price(prices[3]), icon: $r('app.media.km_membership_subdock') },
    { key: 'glimmerclock', name: '微光时钟', description: '桌面时钟与计时', price: '¥18.00', icon: $r('app.media.km_membership_glimmerclock') }
  ]
  suite.futureAppsTitle = '更多应用'
  suite.futureAppsDescription = '持续开发，敬请期待'
  suite.appsNote = '全家桶包含以上应用的会员。右侧为单独买断展示价，无需逐个购买；正式目录与权益以 Kitapp 为准。'
  suite.restoreNote = '已购买全家桶？请在 Kitapp 中使用原华为账号恢复购买。'
  return suite
}

/** Kitapp 自己售卖全家桶时使用的同一份资料；价目、图标与应用目录和兄弟应用共用一个版本，只换自售语境的文案。 */
export function fixedKitappStoreSuite(): JuMembershipSuite {
  const suite = fixedKitappSuite()
  suite.offer.actionLabel = '立即开通'
  suite.offer.purchaseNote = '一次买断，无自动续费。开通后，在全家桶所含应用登录同一个华为账号，即可使用各自的会员功能。'
  suite.appsNote = '全家桶包含以上应用的会员。右侧为单独买断展示价，无需逐个购买。'
  suite.restoreNote = '更换设备或重装 Kitapp 后，用原华为账号登录并恢复购买，即可找回全家桶。'
  return suite
}

/** 在兄弟应用内售卖同一全家桶；只改变购买说明和动作状态。 */
export function fixedKitappInAppSuite(owned: boolean, busy: boolean): JuMembershipSuite {
  const suite = fixedKitappSuite()
  suite.offer.actionLabel = owned ? '已解锁全家桶' : (busy ? '正在处理' : '立即购买')
  suite.offer.actionEnabled = !owned && !busy
  suite.offer.purchaseNote = '一次买断，无自动续费。由华为应用内购买处理支付，订单经服务端核验后开通；在所含应用登录同一华为账号即可使用会员功能。'
  suite.appsNote = '全家桶包含以上应用的会员。右侧为单独买断展示价，无需逐个购买。'
  suite.restoreNote = '已购买全家桶？使用原华为账号登录并恢复购买，即可核验本应用订单及其他应用已开通的全家桶权益。'
  return suite
}
