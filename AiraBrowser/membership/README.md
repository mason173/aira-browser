# KitappMembership 1.3.16

这是系列应用统一的会员成品模块，依赖 JuDesign 1.35.13。公开页面是 `KitappMembershipPage` 与 `KitappSuitePage`，从 `kitapp-membership` 导入。

当前全家桶目录为 Aira（¥68.8）、松果清单（¥38.8）、声栖（限时免费）、SubDock（¥28.8）、微光时钟（¥18.00）。单买合计展示价为 ¥154.4，全家桶售价 ¥68.8。兄弟应用页与 Kitapp 自售页均不显示「如何开通全家桶」标题和三步说明。

## KitappMembershipPage：兄弟应用展示会员

只传 `app`（JuMembershipOffer）、`active`、`asDestination`、`showSuite`、`contactEmail` 与 onBack/onPurchase/onOpenSuite/onRestore/onUserAgreement/onPrivacy 回调。不接受 title 或 suite 配置，不导出全家桶工厂。全家桶所有文字、价格、图标、目录、麦穗、划线价和更多应用均固定，文案面向「到 Kitapp 开通」的引流语境。

单应用从 `createKitappAppOffer()` 创建。可换本应用名称、图标、简介、售价、权益、评价和说明；五张默认示例评价及头像随模块提供，空／单张评价自动回落到五张默认评价，功能图标自动按蓝橙紫绿分配底色。布局、轮播和颜色不是宿主可删减项。

## KitappSuitePage：Kitapp 自售全家桶

Kitapp 自己的售卖入口（如「关于」页签）使用。传 `title`、`active`、`hasTabBar`、`accountAvatar`、`inlineAction`、`owned`、`agreementChecked`、`actionLabel`、`actionEnabled` 与 onAccount/onPurchase/onAgreementChange/onAgreementTap/onUserAgreement/onPrivacy 回调。价目、图标和应用目录与兄弟应用共用同一版本；没有单应用页签和返回键。

购买按钮下方固定渲染「已阅读并同意《Kitapp One 会员服务协议》」勾选行：勾选状态由宿主维护（`agreementChecked`＋`onAgreementChange`），点协议名触发 `onAgreementTap` 打开全文，宿主应在勾选前保持 `actionEnabled` 为假。已购买时传 `owned: true`，按钮与勾选替换为开通完成提示（绿色对勾＋固定说明文案）。

顶栏右侧是账号圆形入口：`accountAvatar` 传头像地址显示头像，空串显示人形图标，点击触发 onAccount；宿主在自己的账号面板里放登录、设置和恢复购买。

自售页面底部在恢复购买说明后使用 `JuSettingGroup` 展示「联系我们」：青绿色邮箱图标、标题、右侧邮箱，保持单行设置样式。`KITAPP_CONTACT_EMAIL` 从公共入口导出，供宿主的账号面板和关于应用页使用同一联系方式。

完整入口：公共工程 `docs/会员页接入.md`。固定副本通过 `scripts/vendor-membership.cjs` 接入，版本与逐文件 SHA-256 在工程根 kitapp-membership.lock.json。禁止直接改副本。`tools/check-integration.cjs` 在宿主构建时检查模块完整性，禁止另写 MembershipSuite/SuiteCatalog、直接调用底层 JuMembershipPage/JuMembershipSuite 或深层导入模块。

本模块不联网、不产生订单、不判定权益、不存账号或协议。支付、前后台、隐私门控与恢复动作仍由宿主处理；不要用展示价格或按钮点击给用户发放会员。

`showSuite` 默认 true。临时隐藏全家桶页传 false，页面不显示分段且无法横滑到全家桶，购买与恢复只指向单应用。固定资料仍保留；改回 true 并重新进入页面即可恢复。参数挂载期间固定，不影响 KitappSuitePage。

`contactEmail` 默认空，不显示联系信息。传入后，在两页协议及恢复说明下方显示「联系邮箱：邮箱地址」居中小字，统一使用 `JuSettingNote`（12fp／17fp），随正文滚动；无额外卡片或复制按钮。系列应用可使用公共导出的 `KITAPP_CONTACT_EMAIL`。

1.3.11 将全家桶底部按钮文案统一为「立即购买」；点击仍通过既有 onOpenSuite 交给宿主，本次不改变支付或商店接线。


2026-11-06：全家桶统一增加微光时钟（¥18.00），现为5款应用，单买合计¥154.4，套装¥68.8。资料源为公共suite-catalog.json，使用sync-suite-catalog.cjs同步；原宿主接口及购买模式保持。


Aira 接入补充：KitappMembership 1.3.14 允许宿主传 `appActions: JuSettingItem[]` 与 `onAppAction(key)`，用于保留其他订阅方案、兑换、免费领取及订阅管理。入口仅出现在单应用页末尾，使用统一设置分组；空数组保持原外观，忙碌、后台或禁用行不触发回调。全家桶资料与页面不受这些操作项影响。依赖 JuDesign 1.35.13 的 `appEndContent` 插槽，宿主仍只使用成品会员入口。


购买前主动确认（1.3.16／松果兼容1.0.11）：使用公共 `KitappPurchaseConsentRequest(ui, options)`；`result` 仅在本次勾选、确认、弹窗关闭成功且 `isCurrent` 仍有效后返回 accepted。取消、遮罩、返回、页面卸载调用 cancel、账号失效及系统异常均拒绝。协议链接返回非购买 link 结果，宿主随后打开本应用真实文档。套装商品名和价格在模块内部取固定目录，订阅必须 recurring:true 并提供周期/续费说明，额外展示自动续费协议。宿主用既有支付锁包住确认和付款，恢复不弹新购确认；不持久化成全局已同意，不绕过服务端验单。


购买确认排版（1.3.17／松果兼容1.0.12）：紧凑标题，图标/商品名称/价格合并在一块中性商品摘要中，卡外 JuSettingNote 显示买断或续费说明；勾选文字与可点击协议为同一段落。底部左侧取消、右侧确认购买并排，主操作仍须本次主动勾选。可选 appIcon 使用宿主当前应用图标，全家桶图标与价格由固定资料内部取。主题色与明暗色均来自公共 token/themeRoles；不会以阅读协议或点击取消代替同意。
