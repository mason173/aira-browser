/** JuDesign 公共入口。48 个通用组件；业务只从 design 导入。 */
export { JuLaurelBadges } from './src/main/ets/components/JuLaurelBadges'
export { JuReviewMarquee } from './src/main/ets/components/JuReviewMarquee'
export { JuReview } from './src/main/ets/components/JuReviewModels'

// 页面、面板与导航
export { JuMembershipPage } from './src/main/ets/components/JuMembershipPage'
export { JuMembershipOffer, JuMembershipSuite, JuMembershipFeature, JuMembershipApp, JuMembershipQuestion } from './src/main/ets/components/JuMembershipModels'
export { JuImmersivePage } from './src/main/ets/components/JuImmersivePage'
export { JuImmersivePageController } from './src/main/ets/components/JuImmersivePageController'
export { JuImmersiveSheet } from './src/main/ets/components/JuImmersiveSheet'
export { JuImmersiveSheetController } from './src/main/ets/components/JuImmersiveSheetController'
export { JuPrivacyAgreementSheet, JuPrivacySummary } from './src/main/ets/components/JuPrivacyAgreementSheet'
export { JuFloatingFooter } from './src/main/ets/components/JuFloatingFooter'
export { JuNavBar } from './src/main/ets/components/JuNavBar'
export { JuTabs, JuTabItem } from './src/main/ets/components/JuTabs'
// 旧自绘页签仅兼容历史界面；正式 App 底部导航统一使用上面的 JuTabs。
export { JuTabBar, TabBarItem } from './src/main/ets/components/JuTabBar'
export { JuCircleAction, juCircleAction, juCircleMenu } from './src/main/ets/components/JuCircleAction'
export { juNavigationTitleBar } from './src/main/ets/components/JuNavigationTitleBar'

// 按钮与输入
export { JuButton } from './src/main/ets/components/JuButton'
export { JuIconButton } from './src/main/ets/components/JuIconButton'
export { JuCircleButton } from './src/main/ets/components/JuCircleButton'
export { JuGlassIconBar } from './src/main/ets/components/JuGlassIconBar'
export { JuInput } from './src/main/ets/components/JuInput'
export { JuTitleInput } from './src/main/ets/components/JuTitleInput'
export { JuTextArea } from './src/main/ets/components/JuTextArea'
export { JuStepper } from './src/main/ets/components/JuStepper'
export { JuSlider } from './src/main/ets/components/JuSlider'

// 开关与选择
export { JuSwitch } from './src/main/ets/components/JuSwitch'
export { JuCheckbox } from './src/main/ets/components/JuCheckbox'
export { JuRadio } from './src/main/ets/components/JuRadio'
export { JuTextTab } from './src/main/ets/components/JuTextTab'
export { JuCapsuleTab } from './src/main/ets/components/JuCapsuleTab'
export { JuFilterChips, JuFilterChipOption } from './src/main/ets/components/JuFilterChips'

// 列表与设置
export { JuListRow } from './src/main/ets/components/JuListRow'
export { JuSettingGroup, JuSettingItem } from './src/main/ets/components/JuSettingGroup'
// 分组表单（编辑态）：卡片用 JuFormGroup，输入行用 JuFormInput／JuFormTextArea，
// 选择行用 JuFormChoice（点开 JuChoiceList 单选）。不要用 JuInput 自己拼卡片，
// 那样卡片里会多一层底色；也不要拿页面级分类标签 JuTextTab 当表单里的选择控件。
export { JuFormGroup } from './src/main/ets/components/JuFormGroup'
export { JuFormInput } from './src/main/ets/components/JuFormInput'
export { JuFormTextArea } from './src/main/ets/components/JuFormTextArea'
export { JuFormChoice } from './src/main/ets/components/JuFormChoice'
export { JuChoiceList } from './src/main/ets/components/JuChoiceList'
export { JuSettingHeading } from './src/main/ets/components/JuSettingHeading'
export { JuSettingNote } from './src/main/ets/components/JuSettingNote'
export { JuReorderList } from './src/main/ets/components/JuReorderList'

// 图标与信息展示
export { JuIcon } from './src/main/ets/components/JuIcon'
export { JuAvatar } from './src/main/ets/components/JuAvatar'
export { JuEmpty } from './src/main/ets/components/JuEmpty'
export { JuHeader } from './src/main/ets/components/JuHeader'
export { JuFitText } from './src/main/ets/components/JuFitText'
export { JuDigitRoll } from './src/main/ets/components/JuDigitRoll'
export { JuRingProgress } from './src/main/ets/components/JuRingProgress'
export { JuScrambleText } from './src/main/ets/components/JuScrambleText'
export { JuTooltip } from './src/main/ets/components/JuTooltip'
// 长按菜单：正文用 JuContextMenu，宿主用 bindContextMenu(content, ResponseType.LongPress) 挂上。
export { JuContextMenu } from './src/main/ets/components/JuContextMenu'
export { JuContextMenuItem } from './src/main/ets/components/JuContextMenuItem'

// 弹窗与告知正文
export { JuDialog } from './src/main/ets/components/JuDialog'
export { JuLoadingDialog } from './src/main/ets/components/JuLoadingDialog'
export { JuNoticeContent } from './src/main/ets/components/JuNoticeContent'

// 主题、外观、同步持久化与时间格式
export {
  ThemeRoles, themeRoles, currentRoles, themeInit, currentThemeHue,
  themeHueCount, setThemeHue, THEME_HUE_KEY, THEME_HUE_DEFAULT
} from './src/main/ets/theme/ThemeColor'
export {
  appearanceInit,
  currentColorMode, setColorMode, applyColorMode,
  APPEARANCE_COLOR_MODE_KEY, APPEARANCE_COLOR_MODE_DEFAULT,
  COLOR_MODE_DARK, COLOR_MODE_LIGHT, COLOR_MODE_SYSTEM
} from './src/main/ets/theme/Appearance'
export { clockLabel } from './src/main/ets/date/ClockLabel'
export { readPersistText, writePersistText } from './src/main/ets/theme/PersistStore'

// 多选（全局一份状态，供页面壳／底部页签／列表行共享）
export {
  JU_SELECTING_KEY, JU_SELECTED_KEY, selectionSelecting, selectionKeys, selectionCount,
  selectionHas, selectionEnter, selectionToggle, selectionSet, selectionClear, selectionExit
} from './src/main/ets/select/SelectionState'
