# JuDesign 公共 HAR

37 个公开组件由 Index.ets 导出；JuDigit、JuCircleMaterialPlate、JuMembershipPanel 为内部实现，不从公共入口导出。

公共源码统一在 JuDesign 项目维护。应用中的本模块为固定版本副本，随 judesign.lock.json 校验；升级请使用 JuDesign 的 scripts/vendor-design.cjs，不直接在各 App 各改一份。

完整目录、资源和接入示例位于 JuDesign 项目的 docs/。图标授权见 THIRD_PARTY_HUGEICONS.txt。

正式应用底部导航使用 JuTabs（官方 HdsTabs），业务传 JuTabItem、选中状态与正文。旧 JuTabBar 仅兼容历史界面。

会员组件跨项目接入见 JuDesign 的 docs/会员页接入.md；公开入口 JuMembershipPage，宿主只配置资料与动作。
