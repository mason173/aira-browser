import { SettingsCenterDestination } from './SettingsCenterViewModel';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type SettingsSearchTargetKind = 'root' | 'row' | 'subpage';
export type SettingsDestinationTwoPanePresentation = 'embedded' | 'desktop_embedded' | 'routed';
export type SettingsDestinationPanelKind =
  'settings_destination' |
  'keyboard_shortcuts' |
  'app_icon' |
  'theme_palette' |
  'tablet_interface_mode' |
  'tracking_protection' |
  'cookie_management' |
  'external_navigation' |
  'secure_dns' |
  'search_built_in_engines' |
  'download_settings_option' |
  'local_backup' |
  'adblock_rules' |
  'adblock_hidden_elements' |
  'toolbar_scroll_behavior';

export interface SettingsDestinationCatalogTarget {
  id: string;
  destination: SettingsCenterDestination;
  availabilityDestination: SettingsCenterDestination;
  title: string;
  path: string;
  aliases: string[];
  keywords: string[];
  kind: SettingsSearchTargetKind;
  revealTargetId: string;
  subpageId: string;
  compact: boolean;
  twoPane: boolean;
  twoPanePresentation: SettingsDestinationTwoPanePresentation;
}

export class SettingsDestinationCatalogMatch {
  target: SettingsDestinationCatalogTarget;
  tier: number;
  catalogOrder: number;

  constructor(target: SettingsDestinationCatalogTarget, tier: number, catalogOrder: number) {
    this.target = target;
    this.tier = tier;
    this.catalogOrder = catalogOrder;
  }
}

export class SettingsDestinationSubpagePresentation {
  subpageId: string;
  primaryDestination: SettingsCenterDestination;
  contentDestination: SettingsCenterDestination;
  title: string;
  panelKind: SettingsDestinationPanelKind;

  constructor(
    subpageId: string,
    primaryDestination: SettingsCenterDestination,
    contentDestination: SettingsCenterDestination,
    title: string,
    panelKind: SettingsDestinationPanelKind
  ) {
    this.subpageId = subpageId;
    this.primaryDestination = primaryDestination;
    this.contentDestination = contentDestination;
    this.title = title;
    this.panelKind = panelKind;
  }
}

class SettingsDestinationSubpageDescriptor {
  subpageId: string;
  titleTargetId: string;
  contentDestination: SettingsCenterDestination;
  panelKind: SettingsDestinationPanelKind;

  constructor(
    subpageId: string,
    titleTargetId: string,
    contentDestination: SettingsCenterDestination,
    panelKind: SettingsDestinationPanelKind
  ) {
    this.subpageId = subpageId;
    this.titleTargetId = titleTargetId;
    this.contentDestination = contentDestination;
    this.panelKind = panelKind;
  }
}

class CompiledSettingsDestinationCatalogTarget {
  target: SettingsDestinationCatalogTarget;
  normalizedTitle: string;
  normalizedPath: string;
  normalizedAliases: string[];
  normalizedKeywords: string[];
  searchableText: string;
  catalogOrder: number;

  constructor(
    target: SettingsDestinationCatalogTarget,
    normalizedTitle: string,
    normalizedPath: string,
    normalizedAliases: string[],
    normalizedKeywords: string[],
    searchableText: string,
    catalogOrder: number
  ) {
    this.target = target;
    this.normalizedTitle = normalizedTitle;
    this.normalizedPath = normalizedPath;
    this.normalizedAliases = normalizedAliases;
    this.normalizedKeywords = normalizedKeywords;
    this.searchableText = searchableText;
    this.catalogOrder = catalogOrder;
  }
}

function target(
  id: string,
  destination: SettingsCenterDestination,
  availabilityDestination: SettingsCenterDestination,
  title: string,
  path: string,
  kind: SettingsSearchTargetKind,
  revealTargetId: string = '',
  subpageId: string = '',
  aliases: string[] = [],
  keywords: string[] = [],
  compact: boolean = true,
  twoPane: boolean = true,
  twoPanePresentation: SettingsDestinationTwoPanePresentation = 'embedded'
): SettingsDestinationCatalogTarget {
  return {
    id: id,
    destination: destination,
    availabilityDestination: availabilityDestination,
    title: title,
    path: path,
    aliases: aliases,
    keywords: keywords,
    kind: kind,
    revealTargetId: revealTargetId,
    subpageId: subpageId,
    compact: compact,
    twoPane: twoPane,
    twoPanePresentation: twoPanePresentation
  };
}

const ACCOUNT_TARGETS: SettingsDestinationCatalogTarget[] = [
  target(
    'aira_pro',
    'aira_pro',
    'aira_pro',
    AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ? '本地能力' : 'Aira Pro',
    '账号与同步',
    'root',
    '',
    '',
    AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity() ? ['社区版'] : ['Pro', '会员'],
    AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()
      ? ['本地浏览', '免费功能', '社区版']
      : ['支持 Aira', '会员权益', '增强能力'],
    true,
    true,
    'desktop_embedded'
  ),
  target('sync', 'sync', 'sync', '同步', '账号与同步', 'root', '', '',
    ['WebDAV', '华为云'], ['书签同步', '同步方式', '远端', '恢复同步'])
];

const GENERAL_TARGETS: SettingsDestinationCatalogTarget[] = [
  target('general', 'general', 'general', '通用', '通用', 'root', '', '',
    [], ['启动', '历史记录', '键盘快捷键', '默认浏览器']),
  target('default_browser', 'general', 'general', '默认浏览器', '通用 / 系统', 'row', 'default_browser', '',
    ['系统默认浏览器'], ['默认应用']),
  target('startup_behavior', 'general', 'general', '启动行为', '通用 / 启动与标签页', 'row', 'startup_behavior', '',
    ['启动设置'], ['恢复标签页', '启动时恢复']),
  target('tab_auto_close', 'general', 'general', '自动关闭标签页', '通用 / 启动与标签页', 'row',
    'tab_auto_close', '', ['标签页自动关闭'], ['标签清理']),
  target('history_retention', 'general', 'general', '历史保留', '通用 / 浏览资料', 'row', 'history_retention', '',
    ['历史记录保留'], ['保留时间', '保留条数']),
  target('keyboard_shortcuts', 'general', 'general', '键盘快捷键', '通用 / 键盘', 'subpage', '',
    'keyboard_shortcuts', ['快捷键'], ['外接键盘']),
  target('appearance_toolbar', 'appearance_toolbar', 'appearance_toolbar', '外观设置', '通用', 'root', '', '',
    ['外观'], ['主题', '网页深色', '应用图标']),
  target('theme_mode', 'appearance_toolbar', 'appearance_toolbar', '主题模式', '通用 / 外观设置', 'row',
    'theme_mode_system', '', ['主题'], ['浅色', '深色', '跟随系统']),
  target('theme_mode_light', 'appearance_toolbar', 'appearance_toolbar', '浅色',
    '通用 / 外观设置 / 主题模式', 'row', 'theme_mode_light'),
  target('theme_mode_dark', 'appearance_toolbar', 'appearance_toolbar', '深色',
    '通用 / 外观设置 / 主题模式', 'row', 'theme_mode_dark'),
  target('theme_mode_system', 'appearance_toolbar', 'appearance_toolbar', '跟随系统',
    '通用 / 外观设置 / 主题模式', 'row', 'theme_mode_system', '', ['系统主题']),
  target('theme_palette', 'appearance_toolbar', 'appearance_toolbar', '主题色',
    '通用 / 外观设置 / 主题模式', 'subpage', '', 'theme_palette', ['调色板'], ['颜色风格']),
  target('app_icon', 'appearance_toolbar', 'appearance_toolbar', '应用图标',
    '通用 / 外观设置 / 图标', 'subpage', '', 'app_icon', ['图标'], ['图标圆角']),
  target('force_dark_web_content', 'appearance_toolbar', 'appearance_toolbar', '强制网页深色',
    '通用 / 外观设置 / 网页外观', 'row', 'force_dark_web_content', '', ['网页深色'], ['暗色网页']),
  target('tab_overview_layout', 'appearance_toolbar', 'appearance_toolbar', '标签页样式',
    '通用 / 外观设置 / 外观样式', 'row', 'tab_overview_layout', '', ['标签管理'], ['卡片平铺', '横向大卡片'],
    true, false),
  target('tablet_interface_mode', 'appearance_toolbar', 'appearance_toolbar', '界面模式',
    '通用 / 外观设置 / 界面', 'subpage', '', 'tablet_interface_mode', ['平板界面模式'], ['桌面界面']),
  target('global_immersion', 'appearance_toolbar', 'appearance_toolbar', '滚动时顶部沉浸',
    '通用 / 外观设置 / 顶部沉浸', 'row', 'global_immersion', '', ['动态沉浸'], ['状态栏'], true, false),
  target('always_top_immersion', 'appearance_toolbar', 'appearance_toolbar', '始终顶部沉浸',
    '通用 / 外观设置 / 顶部沉浸', 'row', 'always_top_immersion', '', ['始终沉浸'], ['状态栏'], true, false),
  target('custom_homepage', 'custom_homepage', 'custom_homepage', '自定义主页', '通用', 'root', '', '',
    ['主页', '首页'], ['远程主页', '本地主页', '恢复系统主页']),
  target('toolbar_customization', 'toolbar_customization', 'toolbar_customization', '工具栏设置', '通用', 'root', '', '',
    ['自定义工具栏'], ['按钮定制', '按钮顺序', '底部工具栏'], true, false),
  target('toolbar_scroll_behavior', 'toolbar_customization', 'toolbar_customization', '滚动行为',
    '通用 / 工具栏设置', 'subpage', '', 'toolbar_scroll_behavior', ['工具栏滚动行为'], [], true, false),
  target('toolbar_scroll_fixed', 'toolbar_customization', 'toolbar_customization', '始终显示',
    '通用 / 工具栏设置 / 滚动行为', 'row', 'toolbar_scroll_fixed', 'toolbar_scroll_behavior', [], [], true, false),
  target('toolbar_scroll_compact', 'toolbar_customization', 'toolbar_customization', '滚动时收起',
    '通用 / 工具栏设置 / 滚动行为', 'row', 'toolbar_scroll_compact', 'toolbar_scroll_behavior', [], [], true, false),
  target('toolbar_scroll_hidden', 'toolbar_customization', 'toolbar_customization', '滚动时隐藏',
    '通用 / 工具栏设置 / 滚动行为', 'row', 'toolbar_scroll_hidden', 'toolbar_scroll_behavior', [], [], true, false),
  target('search', 'search', 'search', '搜索设置', '通用', 'root', '', '',
    ['搜索'], ['搜索引擎', '搜索建议', '默认搜索']),
  target('search_engine', 'search', 'search', '搜索引擎', '通用 / 搜索设置', 'row', 'search_engine', '',
    ['默认搜索'], ['Bing', 'Google', 'DuckDuckGo', '百度']),
  target('search_suggestions', 'search', 'search', '搜索建议', '通用 / 搜索设置', 'row', 'suggestions_info', '',
    ['地址栏建议'], ['本地建议', '历史建议']),
  target('default_search_engine', 'search', 'search', '默认搜索引擎',
    '通用 / 搜索设置 / 搜索引擎', 'row', 'default_search_engine', '', ['主搜索引擎']),
  target('built_in_search_engines', 'search', 'search', '管理更多搜索引擎',
    '通用 / 搜索设置 / 默认搜索引擎', 'subpage', '', 'search_built_in_engines',
    ['更多搜索引擎']),
  target('search_engine_bing', 'search', 'search', 'Bing',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_bing', 'search_built_in_engines',
    ['必应']),
  target('search_engine_google', 'search', 'search', 'Google',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_google', 'search_built_in_engines',
    ['谷歌']),
  target('search_engine_duckduckgo', 'search', 'search', 'DuckDuckGo',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_duckduckgo', 'search_built_in_engines',
    ['DuckDuckGo 搜索']),
  target('search_engine_baidu', 'search', 'search', 'Baidu',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_baidu', 'search_built_in_engines',
    ['百度']),
  target('search_engine_qihoo', 'search', 'search', '360 搜索',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_qihoo', 'search_built_in_engines',
    ['360']),
  target('search_engine_sogou', 'search', 'search', '搜狗',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_sogou', 'search_built_in_engines'),
  target('search_engine_shenma', 'search', 'search', '神马',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_shenma', 'search_built_in_engines'),
  target('search_engine_brave', 'search', 'search', 'Brave Search',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_brave', 'search_built_in_engines',
    ['Brave']),
  target('search_engine_startpage', 'search', 'search', 'Startpage',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_startpage', 'search_built_in_engines'),
  target('search_engine_ecosia', 'search', 'search', 'Ecosia',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_ecosia', 'search_built_in_engines'),
  target('search_engine_yandex', 'search', 'search', 'Yandex',
    '通用 / 搜索设置 / 更多搜索引擎', 'row', 'search_engine_yandex', 'search_built_in_engines',
    ['俄罗斯搜索']),
  target('quick_search_switching', 'search', 'search', '快速切换搜索引擎',
    '通用 / 搜索设置 / 搜索引擎', 'row', 'quick_search_switching', '', ['快速切换']),
  target('smart_search_fallback', 'search', 'search', '智能搜索回退',
    '通用 / 搜索设置 / 搜索引擎', 'row', 'smart_search_fallback', '', ['自动回退']),
  target('fallback_search_engine', 'search', 'search', '备用搜索引擎',
    '通用 / 搜索设置 / 搜索引擎', 'row', 'fallback_search_engine', '', ['回退搜索引擎']),
  target('fallback_notice', 'search', 'search', '回退提示',
    '通用 / 搜索设置 / 搜索引擎', 'row', 'fallback_notice'),
  target('search_history_suggestions', 'search', 'search', '搜索历史建议',
    '通用 / 搜索设置 / 搜索建议', 'row', 'search_history_suggestions', '', ['本地搜索建议']),
  target('remote_search_suggestions', 'search', 'search', '网络搜索建议',
    '通用 / 搜索设置 / 搜索建议', 'row', 'remote_search_suggestions', '', ['远程搜索建议']),
  target('external_app_search', 'search', 'search', '跨应用搜索',
    '通用 / 搜索设置 / 更多搜索方式', 'row', 'external_app_search', '', ['系统搜索']),
  target('clear_search_history', 'search', 'search', '清除搜索历史',
    '通用 / 搜索设置 / 搜索历史', 'row', 'clear_search_history', '', ['删除搜索历史'])
];

const PRIVACY_TARGETS: SettingsDestinationCatalogTarget[] = [
  target('privacy_security', 'privacy_security', 'privacy_security', '隐私防护', '隐私与安全', 'root', '', '',
    ['隐私', '安全', '隐私与安全'], ['防跟踪', '外部应用', '保护数据']),
  target('private_mode', 'private_mode', 'private_mode', '隐私模式', '隐私与安全', 'root', '', '',
    ['私密浏览', '无痕模式'], ['身份验证', '私密数据', '私密标签页恢复']),
  target('clear_browsing_data', 'privacy_security', 'privacy_security', '清除浏览数据', '隐私防护', 'row',
    'clear_data', '', ['清除数据'], ['缓存', 'Cookie', '历史记录']),
  target('tracking_protection', 'privacy_security', 'privacy_security', '防跟踪防护',
    '隐私防护 / 网页防护', 'row', 'tracking_protection', '', ['增强反跟踪', '反指纹']),
  target('external_navigation_settings', 'privacy_security', 'privacy_security', '外部应用跳转',
    '隐私防护 / 网页防护', 'subpage', '', 'privacy_external_navigation',
    ['打开应用'], ['跳转前询问', '始终允许', '阻止']),
  target('private_authentication', 'private_mode', 'private_mode', '进入隐私模式时验证身份',
    '隐私模式 / 进入方式', 'row', 'private_authentication', '', ['隐私身份验证']),
  target('always_use_private_mode', 'private_mode', 'private_mode', '始终保持隐私模式',
    '隐私模式 / 进入方式', 'row', 'always_use_private_mode', '', ['始终隐私模式']),
  target('private_preserve_cookies', 'private_mode', 'private_mode', '隐私模式保留 Cookie',
    '隐私模式 / 数据与预览', 'row', 'private_preserve_cookies', '', ['私密 Cookie']),
  target('blur_private_tab_previews', 'private_mode', 'private_mode', '模糊私密标签页预览',
    '隐私模式 / 数据与预览', 'row', 'blur_private_tab_previews', '', ['私密预览']),
  target('private_restore_policy', 'private_mode', 'private_mode', '私密标签页恢复',
    '隐私模式 / 恢复', 'row', 'private_restore_policy', '', ['私密恢复']),
  target('private_scope', 'private_mode', 'private_mode', '普通与私密数据',
    '隐私模式 / 数据与预览', 'row', 'private_scope', '', ['数据隔离']),
  target('secure_dns_settings', 'privacy_security', 'privacy_security', '安全 DNS',
    '隐私防护 / 网络保护', 'row', 'secure_dns_settings', '', ['DNS', 'DoH', '加密 DNS'], ['域名解析']),
  target('passwords', 'privacy_security', 'privacy_security', '密码管理', '隐私防护', 'subpage', '', 'passwords',
    ['密码', '密码保险箱'], ['自动填充', '保存密码', '凭据']),
  target('password_official_vault', 'privacy_security', 'privacy_security', '网页密码保险箱',
    '隐私防护 / 密码管理 / 官方能力', 'row', 'password_official_vault', 'passwords',
    ['密码保险箱'], ['系统密码能力']),
  target('password_regular_autofill', 'privacy_security', 'privacy_security', '自动填充已有密码',
    '隐私防护 / 密码管理 / 普通标签页', 'row', 'password_regular_autofill', 'passwords',
    ['自动填充密码']),
  target('password_save_prompt', 'privacy_security', 'privacy_security', '提示保存新密码',
    '隐私防护 / 密码管理 / 普通标签页', 'row', 'password_save_prompt', 'passwords',
    ['保存密码提示']),
  target('password_private_autofill', 'privacy_security', 'privacy_security', '一次性填充已有密码',
    '隐私防护 / 密码管理 / 私密标签页', 'row', 'password_private_autofill', 'passwords',
    ['私密自动填充']),
  target('site_settings', 'privacy_security', 'privacy_security', '站点设置',
    '隐私防护 / 权限与隐私数据', 'subpage', '', 'privacy_site_settings',
    [], ['权限', '摄像头', '麦克风', '位置']),
  target('camera_permission', 'privacy_security', 'privacy_security', '摄像头',
    '隐私防护 / 站点设置 / 默认站点权限', 'row', 'camera', 'privacy_site_settings'),
  target('microphone_permission', 'privacy_security', 'privacy_security', '麦克风',
    '隐私防护 / 站点设置 / 默认站点权限', 'row', 'microphone', 'privacy_site_settings'),
  target('location_permission', 'privacy_security', 'privacy_security', '位置信息',
    '隐私防护 / 站点设置 / 默认站点权限', 'row', 'location', 'privacy_site_settings', ['位置']),
  target('sensor_permission', 'privacy_security', 'privacy_security', '传感器',
    '隐私防护 / 站点设置 / 默认站点权限', 'row', 'sensor', 'privacy_site_settings'),
  target('clipboard_permission', 'privacy_security', 'privacy_security', '剪贴板',
    '隐私防护 / 站点设置 / 默认站点权限', 'row', 'clipboard', 'privacy_site_settings'),
  target('cookie_management', 'privacy_security', 'privacy_security', 'Cookie 管理',
    '隐私防护 / 网页防护', 'subpage', '', 'privacy_cookie_management',
    ['Cookie', '允许 Cookie', '第三方 Cookie'], ['不阻止', '阻止所有 Cookie']),
  target('saved_permission_origins', 'privacy_security', 'privacy_security', '已保存站点',
    '隐私防护 / 站点设置 / 权限管理', 'row', 'saved_permission_origins', 'privacy_site_settings', ['站点权限']),
  target('allow_permission_rules', 'privacy_security', 'privacy_security', '允许规则',
    '隐私防护 / 站点设置 / 权限管理', 'row', 'allow_permission_rules', 'privacy_site_settings'),
  target('block_permission_rules', 'privacy_security', 'privacy_security', '阻止规则',
    '隐私防护 / 站点设置 / 权限管理', 'row', 'block_permission_rules', 'privacy_site_settings'),
  target('reset_site_permissions', 'privacy_security', 'privacy_security', '重置站点权限',
    '隐私防护 / 站点设置 / 权限管理', 'row', 'reset_site_permissions', 'privacy_site_settings'),
  target('refresh_site_icons', 'privacy_security', 'privacy_security', '刷新站点图标',
    '隐私防护 / 站点设置 / 权限管理', 'row', 'refresh_site_icons', 'privacy_site_settings'),
  target('ad_blocker', 'privacy_security', 'user_scripts', '网页内容过滤',
    '隐私防护 / 网页防护', 'subpage', '', 'privacy_ad_blocker',
    ['广告拦截'], ['过滤规则', '自定义规则', '手动隐藏']),
  target('adblock_rules', 'privacy_security', 'user_scripts', '过滤规则',
    '隐私防护 / 网页内容过滤', 'row', 'adblock_rules', 'privacy_ad_blocker',
    ['自定义规则'], ['第三方规则']),
  target('adblock_hidden_elements', 'privacy_security', 'user_scripts', '已清理页面元素',
    '隐私防护 / 网页内容过滤', 'row', 'adblock_hidden_elements', 'privacy_ad_blocker', ['手动隐藏']),
  target('clear_adblock_stats', 'privacy_security', 'user_scripts', '清空统计',
    '隐私防护 / 网页内容过滤', 'row', 'clear_adblock_stats', 'privacy_ad_blocker', ['清除拦截统计'])
];

const WEB_FEATURE_TARGETS: SettingsDestinationCatalogTarget[] = [
  target('web_features', 'web_features', 'web_features', '网页功能', '网页功能', 'root', '', '',
    [], ['网页翻译', '下载', '视频']),
  target('webpage_translation', 'web_features', 'user_scripts', '网页翻译', '网页功能', 'subpage', '',
    'webpage_translation',
    ['翻译'], ['语言', '翻译服务', '翻译提供商']),
  target('translation_provider_selection', 'web_features', 'user_scripts', '选择翻译服务',
    '网页功能 / 网页翻译 / 服务管理', 'row', 'translation_provider_selection', 'webpage_translation',
    ['翻译服务']),
  target('translation_provider_config', 'web_features', 'user_scripts', '编辑服务配置',
    '网页功能 / 网页翻译 / 服务管理', 'row', 'translation_provider_config', 'webpage_translation',
    ['翻译配置'], ['API Key', 'Endpoint']),
  target('translation_target_language', 'web_features', 'user_scripts', '目标语言',
    '网页功能 / 网页翻译 / 语言', 'row', 'translation_target_language', 'webpage_translation',
    ['翻译语言']),
  target('translation_private_tabs', 'web_features', 'user_scripts', '私密标签页允许翻译',
    '网页功能 / 网页翻译 / 隐私', 'row', 'translation_private_tabs', 'webpage_translation',
    ['私密翻译']),
  target('downloads', 'web_features', 'web_features', '下载设置', '网页功能', 'subpage', '', 'downloads',
    ['下载'], ['保存位置', '下载确认', 'HLS 分片并发数', '下载恢复', '私密下载']),
  target('download_location', 'web_features', 'web_features', '下载位置',
    '网页功能 / 下载设置 / 存储', 'row', 'download_location', 'downloads', ['保存位置']),
  target('ask_before_download', 'web_features', 'web_features', '下载前询问',
    '网页功能 / 下载设置 / 下载确认', 'row', 'ask_before_download', 'downloads', ['下载确认']),
  target('allow_cellular_downloads', 'web_features', 'web_features', '允许使用移动数据',
    '网页功能 / 下载设置 / 网络', 'row', 'allow_cellular_downloads', 'downloads', ['移动网络下载']),
  target('hls_segment_concurrency', 'web_features', 'web_features', 'HLS 分片并发数',
    '网页功能 / 下载设置 / 分片下载', 'row', 'hls_segment_concurrency', 'downloads', ['M3U8', 'HLS', '下载线程']),
  target('auto_resume_downloads', 'web_features', 'web_features', '启动后自动恢复',
    '网页功能 / 下载设置 / 下载恢复', 'row', 'auto_resume_downloads', 'downloads', ['自动恢复下载']),
  target('download_auto_clear', 'web_features', 'web_features', '自动清理',
    '网页功能 / 下载设置 / 记录清理', 'row', 'download_auto_clear', 'downloads', ['清理下载记录']),
  target('private_download_file', 'web_features', 'web_features', '私密下载文件',
    '网页功能 / 下载设置 / 私密下载', 'row', 'private_download_file', 'downloads'),
  target('private_download_record', 'web_features', 'web_features', '私密下载记录',
    '网页功能 / 下载设置 / 私密下载', 'row', 'private_download_record', 'downloads'),
  target('user_scripts', 'user_scripts', 'user_scripts', '用户脚本', '网页功能', 'root', '', '',
    ['UserScript', '油猴'], ['脚本', '注入脚本']),
  target('web_apps', 'web_apps', 'web_apps', '网页应用', '网页功能', 'root', '', '',
    ['WebApp'], ['桌面应用', '已安装网页应用'])
];

const ADVANCED_TARGETS: SettingsDestinationCatalogTarget[] = [
  target('user_agent', 'user_agent', 'user_agent', '网页标识', '高级', 'root', '', '',
    ['User Agent', 'UA'], ['桌面网站', '移动网站', '设备标识']),
  target('default_user_agent', 'user_agent', 'user_agent', '默认网页标识',
    '高级 / 网页标识 / 当前默认', 'row', 'default_user_agent'),
  target('user_agent_preset_system_default', 'user_agent', 'user_agent', 'Aira默认',
    '高级 / 网页标识 / 默认', 'row', 'user_agent_preset_system_default', '', ['Aira 默认']),
  target('user_agent_preset_arkweb_original', 'user_agent', 'user_agent', 'ArkWeb 原始标识',
    '高级 / 网页标识 / 移动端网页', 'row', 'user_agent_preset_arkweb_original', '', ['ArkWeb UA'], [], true, false),
  target('user_agent_preset_mobile_huawei_browser', 'user_agent', 'user_agent', '华为浏览器',
    '高级 / 网页标识 / 移动端网页', 'row', 'user_agent_preset_mobile_huawei_browser', '', [], [], true, false),
  target('user_agent_preset_mobile_chrome_android', 'user_agent', 'user_agent', 'Chrome Android',
    '高级 / 网页标识 / 移动端网页', 'row', 'user_agent_preset_mobile_chrome_android', '', ['安卓 Chrome'], [],
    true, false),
  target('user_agent_preset_mobile_safari_iphone', 'user_agent', 'user_agent', 'Safari iPhone',
    '高级 / 网页标识 / 移动端网页', 'row', 'user_agent_preset_mobile_safari_iphone', '', ['iPhone Safari'], [],
    true, false),
  target('user_agent_preset_desktop_chrome_windows', 'user_agent', 'user_agent', 'Chrome Windows',
    '高级 / 网页标识 / 桌面端网页', 'row', 'user_agent_preset_desktop_chrome_windows', '', ['桌面 Chrome']),
  target('user_agent_preset_desktop_edge_windows', 'user_agent', 'user_agent', 'Microsoft Edge Windows',
    '高级 / 网页标识 / 桌面端网页', 'row', 'user_agent_preset_desktop_edge_windows', '', ['Edge Windows']),
  target('user_agent_preset_desktop_safari_mac', 'user_agent', 'user_agent', 'Safari macOS',
    '高级 / 网页标识 / 桌面端网页', 'row', 'user_agent_preset_desktop_safari_mac', '', ['Mac Safari']),
  target('user_agent_preset_desktop_firefox_windows', 'user_agent', 'user_agent', 'Firefox Windows',
    '高级 / 网页标识 / 桌面端网页', 'row', 'user_agent_preset_desktop_firefox_windows', '', ['桌面 Firefox']),
  target('custom_user_agent', 'user_agent', 'user_agent', '自定义 UA',
    '高级 / 网页标识 / 自定义', 'row', 'custom_user_agent', '', ['自定义网页标识'], [], true, false),
  target('experiments', 'experiments', 'experiments', '实验室', '高级', 'root', '', '',
    ['实验'], ['页面手势', '丝滑模式', '应用内代理']),
  target('pull_refresh', 'experiments', 'experiments', '下拉刷新', '高级 / 实验室 / 页面手势', 'row',
    'pull_refresh', '', ['下滑刷新']),
  target('force_enable_web_zoom', 'experiments', 'experiments', '强制允许网页缩放',
    '高级 / 实验室 / 页面手势', 'row', 'force_enable_web_zoom', '', ['强制网页缩放']),
  target('smart_grip_tabs_actions', 'experiments', 'experiments', '智感握姿',
    '高级 / 实验室 / 页面手势', 'row', 'smart_grip_tabs_actions', '', ['握姿']),
  target('web_video_takeover', 'experiments', 'experiments', '网页视频接管',
    '高级 / 实验室 / 媒体增强', 'row', 'web_video_takeover', '', ['视频接管']),
  target('novel_mode', 'experiments', 'experiments', '小说模式',
    '高级 / 实验室 / 阅读增强', 'row', 'novel_mode', '', ['小说阅读']),
  target('novel_auto_takeover', 'experiments', 'experiments', '自动进入小说模式',
    '高级 / 实验室 / 阅读增强', 'row', 'novel_auto_takeover', '', ['小说自动接管']),
  target('app_proxy_settings', 'experiments', 'experiments', '应用内代理',
    '高级 / 实验室 / 高级网络', 'row', 'app_proxy_settings', '', ['网络代理'], ['HTTP 代理', 'SOCKS 代理']),
  target('pause_web_animations_during_scroll', 'experiments', 'experiments', '滚动时暂停网页动画',
    '高级 / 实验室 / 网页丝滑模式', 'row', 'pause_web_animations_during_scroll'),
  target('reduce_media_motion_during_scroll', 'experiments', 'experiments', '滚动时降低媒体扰动',
    '高级 / 实验室 / 网页丝滑模式', 'row', 'reduce_media_motion_during_scroll'),
  target('strengthen_ad_blocking_for_smooth_scroll', 'experiments', 'experiments', '加强广告资源拦截',
    '高级 / 实验室 / 网页丝滑模式', 'row', 'strengthen_ad_blocking_for_smooth_scroll'),
  target('advanced_settings', 'advanced_settings', 'advanced_settings', '高级设置', '高级', 'root'),
  target('local_backup', 'advanced_settings', 'advanced_settings', '本地备份', '高级 / 高级设置',
    'subpage', '', 'local_backup', ['导入', '导出'],
    ['书签', '历史记录', '常用设置', '用户脚本', '脚本数据']),
  target('retention_runtime_policy', 'advanced_settings', 'advanced_settings', '后台标签页资源管理',
    '高级 / 高级设置 / 标签页运行策略', 'row', 'retention_runtime_policy', '', ['后台标签页'], ['资源管理']),
  target('app_service_mode', 'advanced_settings', 'advanced_settings', '应用服务模式',
    '高级 / 高级设置 / 服务模式', 'subpage', '', 'app_service_mode', ['服务模式'], ['基本模式', '全量模式']),
  target('app_service_mode_full', 'advanced_settings', 'advanced_settings', '全量模式',
    '高级 / 高级设置 / 应用服务模式', 'row', 'app_service_mode_full', 'app_service_mode'),
  target('app_service_mode_basic', 'advanced_settings', 'advanced_settings', '基本模式',
    '高级 / 高级设置 / 应用服务模式', 'row', 'app_service_mode_basic', 'app_service_mode'),
  target('about', 'about', 'about', '关于Aira', '高级', 'root', '', '', ['关于'], ['版本', '协议', '合规']),
  target('app_name', 'about', 'about', '应用名称', '高级 / 关于Aira / 应用', 'subpage', 'name', 'about_details'),
  target('version', 'about', 'about', '版本', '高级 / 关于Aira / 应用', 'subpage', 'version', 'about_details',
    ['版本号']),
  target('bundle', 'about', 'about', '包名', '高级 / 关于Aira / 应用', 'subpage', 'bundle', 'about_details'),
  target('changelog', 'about', 'about', '更新日志', '高级 / 关于Aira / 应用支持', 'subpage', 'changelog',
    'about_details', ['更新记录'], ['版本变化']),
  target('app_review', 'about', 'about', '好评鼓励', '高级 / 关于Aira / 应用支持', 'subpage', 'app_review',
    'about_details', ['应用市场评论']),
  target('qq_group', 'about', 'about', '交流QQ群', '高级 / 关于Aira / 应用支持', 'subpage', 'qq_group',
    'about_details', ['QQ群']),
  target('user_agreement', 'about', 'about', '用户服务协议', '高级 / 关于Aira / 协议与合规', 'subpage',
    'user_agreement', 'about_details', ['用户协议']),
  target('privacy_statement', 'about', 'about', '隐私声明', '高级 / 关于Aira / 协议与合规', 'subpage',
    'privacy_statement', 'about_details', ['隐私政策']),
  target('pro_membership_service_agreement', 'about', 'about', 'Aira Pro会员服务协议',
    '高级 / 关于Aira / 协议与合规', 'subpage', 'pro_membership_service_agreement', 'about_details',
    ['会员服务协议']),
  target('pro_auto_renewal_service_agreement', 'about', 'about', 'Aira Pro自动续费服务协议',
    '高级 / 关于Aira / 协议与合规', 'subpage', 'pro_auto_renewal_service_agreement', 'about_details',
    ['自动续费协议']),
  target('third_party_sdk_and_services', 'about', 'about', '第三方SDK及第三方服务清单',
    '高级 / 关于Aira / 协议与合规', 'subpage', 'third_party_sdk_and_services', 'about_details',
    ['第三方 SDK']),
  target('personal_info_and_permissions', 'about', 'about', '个人信息收集与权限使用清单',
    '高级 / 关于Aira / 协议与合规', 'subpage', 'personal_info_and_permissions', 'about_details',
    ['权限使用清单']),
  target('icp_filing', 'about', 'about', '备案号', '高级 / 关于Aira / 协议与合规', 'subpage',
    'icp_filing', 'about_details', ['ICP备案'])
];

const SETTINGS_DESTINATION_CATALOG_TARGETS: SettingsDestinationCatalogTarget[] = ACCOUNT_TARGETS
  .concat(GENERAL_TARGETS)
  .concat(PRIVACY_TARGETS)
  .concat(WEB_FEATURE_TARGETS)
  .concat(ADVANCED_TARGETS)
  .filter((item: SettingsDestinationCatalogTarget): boolean => {
    return AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial() ||
      (item.id !== 'pro_membership_service_agreement' && item.id !== 'pro_auto_renewal_service_agreement');
  });

const SETTINGS_DESTINATION_SUBPAGE_DESCRIPTORS: SettingsDestinationSubpageDescriptor[] = [
  new SettingsDestinationSubpageDescriptor('local_backup', 'local_backup', 'advanced_settings', 'local_backup'),
  new SettingsDestinationSubpageDescriptor(
    'keyboard_shortcuts', 'keyboard_shortcuts', 'general', 'keyboard_shortcuts'
  ),
  new SettingsDestinationSubpageDescriptor('app_icon', 'app_icon', 'appearance_toolbar', 'app_icon'),
  new SettingsDestinationSubpageDescriptor(
    'theme_palette', 'theme_palette', 'appearance_toolbar', 'theme_palette'
  ),
  new SettingsDestinationSubpageDescriptor(
    'tablet_interface_mode', 'tablet_interface_mode', 'appearance_toolbar', 'tablet_interface_mode'
  ),
  new SettingsDestinationSubpageDescriptor(
    'tracking_protection', 'tracking_protection', 'privacy_security', 'tracking_protection'
  ),
  new SettingsDestinationSubpageDescriptor(
    'secure_dns_settings', 'secure_dns_settings', 'privacy_security', 'secure_dns'
  ),
  new SettingsDestinationSubpageDescriptor(
    'privacy_ad_blocker', 'ad_blocker', 'ad_blocker', 'settings_destination'
  ),
  new SettingsDestinationSubpageDescriptor(
    'adblock_rules', 'adblock_rules', 'ad_blocker', 'adblock_rules'
  ),
  new SettingsDestinationSubpageDescriptor(
    'adblock_hidden_elements', 'adblock_hidden_elements', 'ad_blocker', 'adblock_hidden_elements'
  ),
  new SettingsDestinationSubpageDescriptor(
    'privacy_site_settings', 'site_settings', 'site_settings', 'settings_destination'
  ),
  new SettingsDestinationSubpageDescriptor(
    'privacy_external_navigation', 'external_navigation_settings', 'privacy_security', 'external_navigation'
  ),
  new SettingsDestinationSubpageDescriptor(
    'privacy_cookie_management', 'cookie_management', 'privacy_security', 'cookie_management'
  ),
  new SettingsDestinationSubpageDescriptor('passwords', 'passwords', 'passwords', 'settings_destination'),
  new SettingsDestinationSubpageDescriptor('downloads', 'downloads', 'downloads', 'settings_destination'),
  new SettingsDestinationSubpageDescriptor(
    'hls_concurrency', 'hls_segment_concurrency', 'downloads', 'download_settings_option'
  ),
  new SettingsDestinationSubpageDescriptor(
    'auto_clear', 'download_auto_clear', 'downloads', 'download_settings_option'
  ),
  new SettingsDestinationSubpageDescriptor(
    'private_file', 'private_download_file', 'downloads', 'download_settings_option'
  ),
  new SettingsDestinationSubpageDescriptor(
    'private_record', 'private_download_record', 'downloads', 'download_settings_option'
  ),
  new SettingsDestinationSubpageDescriptor(
    'webpage_translation', 'webpage_translation', 'webpage_translation', 'settings_destination'
  ),
  new SettingsDestinationSubpageDescriptor(
    'app_service_mode', 'app_service_mode', 'app_service_mode', 'settings_destination'
  ),
  new SettingsDestinationSubpageDescriptor(
    'search_built_in_engines', 'built_in_search_engines', 'search', 'search_built_in_engines'
  ),
  new SettingsDestinationSubpageDescriptor(
    'toolbar_scroll_behavior', 'toolbar_scroll_behavior', 'toolbar_customization', 'toolbar_scroll_behavior'
  )
];

export class SettingsDestinationCatalog {
  private compiledTargets: CompiledSettingsDestinationCatalogTarget[];

  constructor() {
    this.compiledTargets = SETTINGS_DESTINATION_CATALOG_TARGETS.map(
      (target: SettingsDestinationCatalogTarget, index: number): CompiledSettingsDestinationCatalogTarget => {
        const normalizedTitle = this.normalize(target.title);
        const normalizedPath = this.normalize(target.path);
        const normalizedAliases = target.aliases.map((value: string): string => this.normalize(value));
        const normalizedKeywords = target.keywords.map((value: string): string => this.normalize(value));
        return new CompiledSettingsDestinationCatalogTarget(
          target,
          normalizedTitle,
          normalizedPath,
          normalizedAliases,
          normalizedKeywords,
          [normalizedTitle, normalizedPath]
            .concat(normalizedAliases)
            .concat(normalizedKeywords)
            .join(' '),
          index
        );
      }
    );
  }

  search(query: string, shellMode: 'compact' | 'touchTwoPane' | 'twoPane'): SettingsDestinationCatalogMatch[] {
    const normalizedQuery = this.normalize(query);
    if (normalizedQuery.length === 0) {
      return [];
    }
    const tokens = normalizedQuery.split(' ').filter((token: string): boolean => token.length > 0);
    const matches: SettingsDestinationCatalogMatch[] = [];
    for (let index = 0; index < this.compiledTargets.length; index += 1) {
      const compiled = this.compiledTargets[index];
      if (!this.supportsShell(compiled.target, shellMode) || !this.matchesAllTokens(compiled, tokens)) {
        continue;
      }
      matches.push(new SettingsDestinationCatalogMatch(
        compiled.target,
        this.resolveTier(compiled, normalizedQuery),
        compiled.catalogOrder
      ));
    }
    return matches;
  }

  findTarget(targetId: string): SettingsDestinationCatalogTarget | undefined {
    const normalizedId = targetId.trim();
    for (let index = 0; index < this.compiledTargets.length; index += 1) {
      if (this.compiledTargets[index].target.id === normalizedId) {
        return this.compiledTargets[index].target;
      }
    }
    return undefined;
  }

  findSubpagePresentation(subpageId: string): SettingsDestinationSubpagePresentation | undefined {
    const normalizedId = subpageId.trim();
    for (let index = 0; index < SETTINGS_DESTINATION_SUBPAGE_DESCRIPTORS.length; index += 1) {
      const descriptor = SETTINGS_DESTINATION_SUBPAGE_DESCRIPTORS[index];
      if (descriptor.subpageId !== normalizedId) {
        continue;
      }
      const titleTarget = this.findTarget(descriptor.titleTargetId);
      if (titleTarget === undefined) {
        return undefined;
      }
      return new SettingsDestinationSubpagePresentation(
        descriptor.subpageId,
        titleTarget.destination,
        descriptor.contentDestination,
        titleTarget.title,
        descriptor.panelKind
      );
    }
    return undefined;
  }

  isTargetPresentable(
    target: SettingsDestinationCatalogTarget,
    shellMode: 'compact' | 'touchTwoPane' | 'twoPane'
  ): boolean {
    return this.supportsShell(target, shellMode);
  }

  requiresRoutedPresentation(
    target: SettingsDestinationCatalogTarget,
    shellMode: 'compact' | 'touchTwoPane' | 'twoPane'
  ): boolean {
    return shellMode === 'compact' ||
      (shellMode === 'touchTwoPane' && !target.twoPane) ||
      (shellMode === 'touchTwoPane' && target.twoPanePresentation === 'desktop_embedded') ||
      target.twoPanePresentation === 'routed';
  }

  private supportsShell(
    target: SettingsDestinationCatalogTarget,
    shellMode: 'compact' | 'touchTwoPane' | 'twoPane'
  ): boolean {
    return shellMode === 'twoPane' ? target.twoPane : target.compact;
  }

  private matchesAllTokens(compiled: CompiledSettingsDestinationCatalogTarget, tokens: string[]): boolean {
    for (let index = 0; index < tokens.length; index += 1) {
      if (compiled.searchableText.indexOf(tokens[index]) < 0) {
        return false;
      }
    }
    return true;
  }

  private resolveTier(compiled: CompiledSettingsDestinationCatalogTarget, normalizedQuery: string): number {
    if (compiled.normalizedTitle === normalizedQuery) {
      return 0;
    }
    if (compiled.normalizedAliases.indexOf(normalizedQuery) >= 0) {
      return 1;
    }
    if (this.hasPrefix(compiled.normalizedTitle, compiled.normalizedAliases, normalizedQuery)) {
      return 2;
    }
    if (this.hasContains(compiled.normalizedTitle, compiled.normalizedAliases, normalizedQuery)) {
      return 3;
    }
    if (compiled.normalizedPath.indexOf(normalizedQuery) >= 0) {
      return 4;
    }
    return 5;
  }

  private hasPrefix(title: string, aliases: string[], query: string): boolean {
    if (title.indexOf(query) === 0) {
      return true;
    }
    for (let index = 0; index < aliases.length; index += 1) {
      if (aliases[index].indexOf(query) === 0) {
        return true;
      }
    }
    return false;
  }

  private hasContains(title: string, aliases: string[], query: string): boolean {
    if (title.indexOf(query) >= 0) {
      return true;
    }
    for (let index = 0; index < aliases.length; index += 1) {
      if (aliases[index].indexOf(query) >= 0) {
        return true;
      }
    }
    return false;
  }

  private normalize(value: string): string {
    let normalized = '';
    const punctuation = '，。！？；：、,.!?;:/\\|()[]{}<>《》「」『』_-';
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      let char = value.charAt(index).toLowerCase();
      if (code === 0x3000) {
        char = ' ';
      } else if (code >= 0xFF01 && code <= 0xFF5E) {
        char = String.fromCharCode(code - 0xFEE0).toLowerCase();
      }
      normalized += punctuation.indexOf(char) >= 0 ? ' ' : char;
    }
    return normalized.trim().split(/\s+/).join(' ');
  }
}
