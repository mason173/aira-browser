import {
  BrowserThemeMode,
  BrowserTabsOverviewLayoutStyle,
  BrowserAppServiceMode,
  BrowserAppearanceSettings,
  BrowserThemePaletteId,
  BrowserExperimentSettings,
  BrowserRetentionSettings,
  BrowserRetentionProfileId,
  BrowserStartupRestorePolicy,
  BrowserTabAutoClosePolicy,
  BrowserPrivateTabRestorePolicy,
  HistoryRetentionSettings,
  ExternalNavigationAppOpenPolicy,
  SearchEngineId,
  SearchEngineOption,
  SEARCH_ENGINE_OPTIONS,
  SitePermissionDefaultSettings,
  SitePermissionKind,
  SitePermissionRule
} from '../../common/models/BrowserModels';
import { SettingsCenterDestination } from './SettingsCenterViewModel';
import { BrowserThemePaletteService } from '../../services/theme/BrowserThemePaletteService';
import {
  APP_ICP_FILING_NUMBER,
  APP_PREVIEW_VERSION_CODE,
  APP_PREVIEW_VERSION_NAME
} from '../../common/constants/AppVersionInfo';
import { SiteControlsDefaultCapabilityState } from '../sitecontrols/SiteControlsCoordinator';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService,
  BrowserPrivacyEffectTargetScope
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export type SettingsDetailRowKind = 'static' | 'navigation' | 'option' | 'switch' | 'dropdown';
export type SettingsDetailRowAction =
  'none' |
  'open_changelog' |
  'open_privacy_statement' |
  'open_user_service_agreement_web' |
  'open_pro_membership_service_agreement' |
  'open_pro_auto_renewal_service_agreement' |
  'open_third_party_sdk_and_services' |
  'open_personal_info_and_permissions' |
  'open_icp_filing_query' |
  'open_community_source_repository' |
  'open_community_license' |
  'open_third_party_notices' |
  'open_community_security_policy' |
  'copy_support_qq_group' |
  'open_app_review_page' |
  'open_search_settings' |
  'open_password_settings' |
  'open_ad_block_settings' |
  'open_site_settings' |
  'open_cookie_management' |
  'open_external_navigation_settings' |
  'open_download_settings' |
  'open_webpage_translation_settings' |
  'open_app_service_mode_settings' |
  'open_app_icon_settings' |
  'open_theme_palette_settings' |
  'open_tablet_interface_mode_settings' |
  'show_tab_overview_layout_sheet' |
  'open_browser_toolbar_customization' |
  'open_general_startup_settings' |
  'open_general_tab_auto_close_settings' |
  'open_general_private_tabs_settings' |
  'open_general_history_retention_settings' |
  'open_retention_runtime_policy_settings' |
  'open_local_backup' |
  'open_keyboard_shortcuts_settings' |
  'open_default_browser_settings' |
  'clear_all_site_data' |
  'refresh_site_icons' |
  'reset_site_permissions' |
  'open_site_permission_default_camera' |
  'open_site_permission_default_microphone' |
  'open_site_permission_default_location' |
  'open_site_permission_default_sensor' |
  'open_site_permission_default_clipboard' |
  'set_theme_light' |
  'set_theme_dark' |
  'set_theme_system' |
  'set_search_bing' |
  'set_search_google' |
  'set_search_duckduckgo' |
  'set_search_baidu' |
  'set_search_qihoo' |
  'set_search_sogou' |
  'set_search_shenma' |
  'set_search_brave' |
  'set_search_startpage' |
  'set_search_ecosia' |
  'set_search_yandex' |
  'toggle_global_immersion' |
  'toggle_always_top_immersion' |
  'toggle_force_dark_web_content' |
  'toggle_private_mode_authentication' |
  'toggle_always_use_private_mode' |
  'toggle_private_mode_preserve_cookies_on_close' |
  'toggle_blur_private_tab_previews' |
  'toggle_desktop_bookmark_bar' |
  'toggle_pause_web_animations_during_scroll' |
  'toggle_reduce_media_motion_during_scroll' |
  'toggle_strengthen_ad_blocking_for_smooth_scroll' |
  'toggle_pull_refresh' |
  'toggle_force_enable_web_zoom' |
  'toggle_smart_grip_tabs_actions' |
  'toggle_web_video_takeover' |
  'toggle_novel_mode' |
  'toggle_novel_auto_takeover' |
  'open_app_proxy_settings' |
  'open_secure_dns_settings' |
  'open_tracking_protection_settings' |
  'set_app_service_mode_full' |
  'set_app_service_mode_basic';

export type SettingsDetailActionButtonEmphasis = 'primary' | 'danger';

export interface SettingsDetailOption {
  id: string;
  label: string;
  helperText: string;
  isSelected: boolean;
  isEnabled: boolean;
}

export interface SettingsDetailRowState {
  id: string;
  kind: SettingsDetailRowKind;
  action: SettingsDetailRowAction;
  title: string;
  value: string;
  valueSwatchColor: string;
  helperText: string;
  isEnabled: boolean;
  isSelected: boolean;
  checked: boolean;
  options?: SettingsDetailOption[];
}

/**
 * Raw single-choice selections needed to project large-screen dropdown rows.
 * The presentation layer assembles this from live preferences and hands it to
 * {@link SettingsDetailViewModel.applyLargeScreenSingleChoiceDropdowns}.
 */
export interface SettingsSingleChoiceSelectionSnapshot {
  startupRestorePolicy: BrowserStartupRestorePolicy;
  tabAutoClosePolicy: BrowserTabAutoClosePolicy;
  privateTabRestorePolicy: BrowserPrivateTabRestorePolicy;
  historyRetention: HistoryRetentionSettings;
  retentionProfileId: BrowserRetentionProfileId;
  sitePermissionDefaults: SitePermissionDefaultSettings;
  appServiceMode: BrowserAppServiceMode;
}

export interface SettingsSitePolicyDisplayState {
  acceptCookies: boolean;
  acceptThirdPartyCookies: boolean;
  thirdPartyCookiePolicyLocked: boolean;
}

export interface SettingsExternalNavigationDisplayState {
  appOpenPolicy: ExternalNavigationAppOpenPolicy;
}

export interface SettingsGeneralDisplayState {
  homeLayoutLabel: string;
  customHomepageLabel: string;
  startupBehaviorLabel: string;
  tabAutoCloseLabel: string;
  defaultBrowserLabel: string;
  historyRetentionLabel: string;
  privateBrowsingLabel: string;
  privateModeAuthenticationEnabled: boolean;
  alwaysUsePrivateMode: boolean;
  privateModePreserveCookiesOnClose: boolean;
  enhancedTrackingProtectionEnabled: boolean;
}

export interface SettingsSitePermissionsDisplayState {
  savedOriginCount: number;
  allowRuleCount: number;
  blockRuleCount: number;
  askRuleCount: number;
  defaults: SitePermissionDefaultSettings;
  defaultCapabilities: SiteControlsDefaultCapabilityState[];
  canClearPermissions: boolean;
  summaryLine: string;
}

export interface SettingsAboutDisplayState {
  appName: string;
  bundleName: string;
  versionName: string;
  versionCode: string;
}

export interface SettingsDetailGroupState {
  id: string;
  title: string;
  rows: SettingsDetailRowState[];
  actionButtons?: SettingsDetailActionButtonState[];
  footerText?: string;
}

export interface SettingsDetailActionButtonState {
  id: string;
  title: string;
  action: SettingsDetailRowAction;
  isEnabled: boolean;
  emphasis: SettingsDetailActionButtonEmphasis;
}

export interface SettingsDetailState {
  id: SettingsCenterDestination;
  title: string;
  groups: SettingsDetailGroupState[];
  actionButtons: SettingsDetailActionButtonState[];
}

export class SettingsDetailViewModel {
  private themePaletteService: BrowserThemePaletteService = new BrowserThemePaletteService();
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildExperimentUpdateToast(
    previousSettings: BrowserExperimentSettings,
    nextSettings: BrowserExperimentSettings
  ): string {
    if (previousSettings.pauseWebAnimationsDuringScroll !== nextSettings.pauseWebAnimationsDuringScroll) {
      return nextSettings.pauseWebAnimationsDuringScroll ? '滚动动画暂停已开启' : '滚动动画暂停已关闭';
    }
    if (previousSettings.reduceMediaMotionDuringScroll !== nextSettings.reduceMediaMotionDuringScroll) {
      return nextSettings.reduceMediaMotionDuringScroll ? '媒体弱化已开启' : '媒体弱化已关闭';
    }
    if (previousSettings.strengthenAdBlockingForSmoothScroll !== nextSettings.strengthenAdBlockingForSmoothScroll) {
      return nextSettings.strengthenAdBlockingForSmoothScroll ? '增强拦截已开启' : '增强拦截已关闭';
    }
    if (previousSettings.pullRefreshEnabled !== nextSettings.pullRefreshEnabled) {
      return nextSettings.pullRefreshEnabled ? '下拉刷新已开启' : '下拉刷新已关闭';
    }
    if (previousSettings.forceEnableWebZoom !== nextSettings.forceEnableWebZoom) {
      return nextSettings.forceEnableWebZoom ? '强制网页缩放已开启' : '强制网页缩放已关闭';
    }
    if (previousSettings.smartGripTabsActionsEnabled !== nextSettings.smartGripTabsActionsEnabled) {
      return nextSettings.smartGripTabsActionsEnabled ? '智感握姿已开启' : '智感握姿已关闭';
    }
    if (previousSettings.webVideoTakeoverEnabled !== nextSettings.webVideoTakeoverEnabled) {
      return nextSettings.webVideoTakeoverEnabled ? '网页视频接管已开启' : '网页视频接管已关闭';
    }
    if (previousSettings.novelModeEnabled !== nextSettings.novelModeEnabled) {
      return nextSettings.novelModeEnabled ? '小说模式已开启' : '小说模式已关闭';
    }
    if (previousSettings.novelAutoTakeoverEnabled !== nextSettings.novelAutoTakeoverEnabled) {
      return nextSettings.novelAutoTakeoverEnabled ? '小说自动接管已开启' : '小说自动接管已关闭';
    }
    if (previousSettings.appProxyEnabled !== nextSettings.appProxyEnabled) {
      return nextSettings.appProxyEnabled ? '应用内代理已开启' : '应用内代理已关闭';
    }
    return '实验室设置已更新';
  }

  buildState(
    rawId: string | undefined,
    dataScope: string = '',
    privacyMode: string = '',
    themeMode: BrowserThemeMode = 'system',
    searchEngineId: SearchEngineId = 'bing',
    general: SettingsGeneralDisplayState = {
      homeLayoutLabel: '搜索和书签',
      customHomepageLabel: '系统主页',
      startupBehaviorLabel: '恢复常规标签',
      tabAutoCloseLabel: '不自动关闭',
      defaultBrowserLabel: '由系统设置管理',
      historyRetentionLabel: '90 天 / 10000 条',
      privateBrowsingLabel: '关闭后不恢复',
      privateModeAuthenticationEnabled: false,
      alwaysUsePrivateMode: false,
      privateModePreserveCookiesOnClose: false,
      enhancedTrackingProtectionEnabled: false
    },
    sitePolicy: SettingsSitePolicyDisplayState = {
      acceptCookies: true,
      acceptThirdPartyCookies: true,
      thirdPartyCookiePolicyLocked: false
    },
    externalNavigation: SettingsExternalNavigationDisplayState = {
      appOpenPolicy: 'ask'
    },
    appearance: BrowserAppearanceSettings = {
      bottomToolbarScrollBehavior: 'compact',
      globalImmersionEnabled: false,
      alwaysTopImmersionEnabled: false,
      forceDarkWebContentEnabled: true,
      blurPrivateTabPreviews: true,
      showHomeRecentlyClosed: true,
      showHomeShortcuts: true,
      homeRecentlyClosedLimit: 8,
      homeShortcutLayoutDensity: 'standard',
      homeShortcutIconSizeRatio: 0.54,
      siteIconCornerRadiusRatio: 0.3,
      themePaletteId: 'default',
      tabsOverviewLayoutStyle: 'grid',
      tabsOverviewCloseButtonAlwaysVisible: false,
      showDesktopBookmarkBar: true
    },
    experiments: BrowserExperimentSettings = {
      pauseWebAnimationsDuringScroll: false,
      reduceMediaMotionDuringScroll: false,
      strengthenAdBlockingForSmoothScroll: false,
      pullRefreshEnabled: false,
      forceEnableWebZoom: false,
      smartGripTabsActionsEnabled: true,
      webVideoTakeoverEnabled: true,
      novelModeEnabled: true,
      novelAutoTakeoverEnabled: false,
      appProxyActiveProfileId: '',
      appProxyProfiles: [],
      appProxyEnabled: false,
      appProxy: {
        scheme: 'http',
        host: '',
        port: 0,
        username: '',
        password: '',
        bypassHosts: 'localhost,127.0.0.1,::1',
        updatedAt: 0
      }
    },
    retention: BrowserRetentionSettings = {
      profileId: 'balanced',
      deviceTierHint: 'auto',
      maxMountedRuntimeTabs: 15,
      maxHotBackgroundTabs: 5,
      maxWarmBackgroundTabs: 10,
      hotBackgroundMaxAgeMs: 30 * 60 * 1000,
      warmBackgroundMaxAgeMs: 24 * 60 * 60 * 1000,
      staleAfterMs: 24 * 60 * 60 * 1000
    },
    sitePermissions: SettingsSitePermissionsDisplayState = {
      savedOriginCount: 0,
      allowRuleCount: 0,
      blockRuleCount: 0,
      askRuleCount: 0,
      defaults: {
        camera: 'ask',
        microphone: 'ask',
        location: 'ask',
        sensor: 'ask',
        clipboard: 'ask'
      },
      defaultCapabilities: [
        {
          id: 'camera',
          title: '摄像头',
          rule: 'ask',
          valueLabel: '询问'
        },
        {
          id: 'microphone',
          title: '麦克风',
          rule: 'ask',
          valueLabel: '询问'
        },
        {
          id: 'location',
          title: '位置信息',
          rule: 'ask',
          valueLabel: '询问'
        },
        {
          id: 'sensor',
          title: '传感器',
          rule: 'ask',
          valueLabel: '询问'
        }
      ],
      canClearPermissions: false,
      summaryLine: '尚无已保存站点权限'
    },
    about: SettingsAboutDisplayState = {
      appName: 'Aira',
      bundleName: '',
      versionName: APP_PREVIEW_VERSION_NAME,
      versionCode: `${APP_PREVIEW_VERSION_CODE}`
    },
    siteIconRefreshing: boolean = false,
    appServiceMode: BrowserAppServiceMode = 'full',
    hideTopSafeAreaSettings: boolean = false,
    isLargeScreen: boolean = false,
    tabletInterfaceModeVisible: boolean = false,
    tabletInterfaceModeLabel: string = '自动',
    secureDnsSummaryLabel: string = '系统 DNS',
    adBlockEnabled: boolean = false
  ): SettingsDetailState {
    const id = this.normalizeId(rawId);
    const isPrivateContext = dataScope === 'session_ephemeral' || privacyMode === 'private';
    const canEditDevicePreferences = this.isDevicePreferenceEffectAllowed(
      'settings_device_preference_write',
      dataScope,
      privacyMode
    );
    const canDeactivateSyncForAppServiceMode = this.isPrivacyEffectAllowed(
      'app_service_mode_sync_deactivation',
      'remote_account_sync_state',
      dataScope,
      privacyMode
    );
    const state = this.buildBaseState(
      id,
      isPrivateContext,
      canEditDevicePreferences,
      canDeactivateSyncForAppServiceMode,
      themeMode,
      searchEngineId,
      general,
      sitePolicy,
      externalNavigation,
      appearance,
      experiments,
      retention,
      sitePermissions,
      about,
      siteIconRefreshing,
      appServiceMode,
      hideTopSafeAreaSettings,
      tabletInterfaceModeVisible,
      tabletInterfaceModeLabel,
      secureDnsSummaryLabel,
      adBlockEnabled,
      isLargeScreen
    );
    const baseGroups = isLargeScreen ? this.filterLargeScreenHiddenGroups(state.groups) : state.groups;
    return {
      id: state.id,
      title: state.title,
      groups: isPrivateContext ? this.buildPrivateContextGroups().concat(baseGroups) : baseGroups,
      actionButtons: state.actionButtons
    };
  }

  /**
   * 大屏（鼠标键盘）下隐藏只对触屏有意义的设置项：
   * - 实验室"页面手势"整组（下拉刷新 / 强制网页缩放 / 智感握姿）
   * - 外观里的"标签页样式"行（大屏标签管理默认平铺，不提供大卡片切换）
   * 若某组去掉该行后变空且无操作按钮，则整组略过，避免空卡片。
   */
  private filterLargeScreenHiddenGroups(groups: SettingsDetailGroupState[]): SettingsDetailGroupState[] {
    const result: SettingsDetailGroupState[] = [];
    for (let groupIndex = 0; groupIndex < groups.length; groupIndex += 1) {
      const group = groups[groupIndex];
      if (group.id === 'page_gestures') {
        continue;
      }
      const filteredRows = group.rows.filter((row: SettingsDetailRowState) => row.id !== 'tab_overview_layout');
      const actionButtons = group.actionButtons ?? [];
      if (filteredRows.length === 0 && actionButtons.length === 0) {
        continue;
      }
      result.push({
        id: group.id,
        title: group.title,
        rows: filteredRows,
        actionButtons: group.actionButtons,
        footerText: group.footerText
      });
    }
    return result;
  }

  private buildBaseState(
    id: SettingsCenterDestination,
    isPrivateContext: boolean,
    canEditDevicePreferences: boolean,
    canDeactivateSyncForAppServiceMode: boolean,
    themeMode: BrowserThemeMode,
    searchEngineId: SearchEngineId,
    general: SettingsGeneralDisplayState,
    sitePolicy: SettingsSitePolicyDisplayState,
    externalNavigation: SettingsExternalNavigationDisplayState,
    appearance: BrowserAppearanceSettings,
    experiments: BrowserExperimentSettings,
    retention: BrowserRetentionSettings,
    sitePermissions: SettingsSitePermissionsDisplayState,
    about: SettingsAboutDisplayState,
    siteIconRefreshing: boolean,
    appServiceMode: BrowserAppServiceMode,
    hideTopSafeAreaSettings: boolean,
    tabletInterfaceModeVisible: boolean,
    tabletInterfaceModeLabel: string,
    secureDnsSummaryLabel: string,
    adBlockEnabled: boolean,
    isLargeScreen: boolean
  ): SettingsDetailState {
    switch (id) {
      case 'app_service_mode':
        return this.buildAppServiceModeState(
          appServiceMode,
          canEditDevicePreferences,
          canDeactivateSyncForAppServiceMode
        );
      case 'advanced_settings':
        return this.buildAdvancedSettingsState(retention, canEditDevicePreferences, isPrivateContext);
      case 'privacy_security':
        return this.buildPrivacySecurityState(
          externalNavigation,
          general,
          sitePolicy,
          canEditDevicePreferences,
          isPrivateContext,
          secureDnsSummaryLabel,
          adBlockEnabled,
          appServiceMode !== 'basic'
        );
      case 'private_mode':
        return this.buildPrivateModeState(
          general,
          appearance,
          canEditDevicePreferences
        );
      case 'site_settings':
        return this.buildSiteSettingsState(
          sitePermissions,
          isPrivateContext,
          siteIconRefreshing
        );
      case 'about':
        return this.buildAboutState(about);
      case 'general':
        return this.buildCommonState(general);
      case 'search':
        return this.buildSearchState(searchEngineId, canEditDevicePreferences);
      case 'web_features':
        return this.buildWebFeaturesState(appServiceMode);
      case 'appearance_toolbar':
        return this.buildAppearanceToolbarState(
          themeMode,
          appearance,
          canEditDevicePreferences,
          isPrivateContext,
          hideTopSafeAreaSettings,
          tabletInterfaceModeVisible,
          tabletInterfaceModeLabel,
          isLargeScreen
        );
      case 'experiments':
        return this.buildExperimentsState(
          experiments,
          canEditDevicePreferences && appServiceMode !== 'basic'
        );
      default:
        return this.buildComingNextState(id, '设置');
    }
  }

  private buildPrivateContextGroups(): SettingsDetailGroupState[] {
    return [
      {
        id: 'private_context',
        title: '当前私密会话',
        rows: [
          this.staticRow('private_context_note', '私密入口', '仅限本次会话', '不改常规浏览资料')
        ]
      }
    ];
  }

  private buildAppServiceModeState(
    appServiceMode: BrowserAppServiceMode,
    canEditDevicePreferences: boolean,
    canDeactivateSync: boolean
  ): SettingsDetailState {
    let basicModeDescription = '仅保留基础浏览和本地数据能力，大部分增强功能不可用。';
    if (!canEditDevicePreferences) {
      basicModeDescription = '当前会话不可修改设备设置';
    } else if (!canDeactivateSync) {
      basicModeDescription = '私密会话不能停用同步';
    }
    return {
      id: 'app_service_mode',
      title: '应用服务模式',
      actionButtons: [],
      groups: [
        {
          id: 'mode',
          title: '服务模式',
          rows: [
            this.optionRow(
              'app_service_mode_full',
              '全量模式',
              '账号登录、云同步、远程建议、壁纸、翻译、会员、脚本、网页内容过滤和视频增强可用。',
              'set_app_service_mode_full',
              appServiceMode === 'full',
              canEditDevicePreferences
            ),
            this.optionRow(
              'app_service_mode_basic',
              '基本模式',
              basicModeDescription,
              'set_app_service_mode_basic',
              appServiceMode === 'basic',
              canEditDevicePreferences && canDeactivateSync
            )
          ],
          footerText: '切换到基本模式会关闭账号登录、同步、会员、翻译、脚本、网页内容过滤、壁纸、远程建议和实验功能；已保存的数据不会被删除。'
        }
      ]
    };
  }

  private buildAdvancedSettingsState(
    retention: BrowserRetentionSettings,
    canEditDevicePreferences: boolean,
    isPrivateContext: boolean
  ): SettingsDetailState {
    return {
      id: 'advanced_settings',
      title: '高级设置',
      actionButtons: [],
      groups: [
        {
          id: 'tab_runtime_retention',
          title: '标签页运行策略',
          rows: [
            this.navigationRow(
              'retention_runtime_policy',
              '后台标签页资源管理',
              this.buildRetentionProfileLabel(retention.profileId),
              '',
              'open_retention_runtime_policy_settings',
              canEditDevicePreferences
            )
          ],
          footerText: !canEditDevicePreferences
            ? '私密中不改全局设置。'
            : '这里设置平时的保活偏好。系统内存紧张时，Aira 会临时降低后台保活数量。'
        },
        {
          id: 'local_data',
          title: '本地数据',
          rows: [
            this.navigationRow(
              'local_backup',
              '本地备份',
              '',
              '',
              'open_local_backup',
              !isPrivateContext
            )
          ]
        },
        {
          id: 'service_mode',
          title: '服务模式',
          rows: [
            this.navigationRow(
              'app_service_mode',
              '应用服务模式',
              '',
              '全量模式或基本模式',
              'open_app_service_mode_settings'
            )
          ]
        }
      ]
    };
  }

  private buildPrivacySecurityState(
    externalNavigation: SettingsExternalNavigationDisplayState,
    general: SettingsGeneralDisplayState,
    sitePolicy: SettingsSitePolicyDisplayState,
    canEditDevicePreferences: boolean,
    isPrivateContext: boolean,
    secureDnsSummaryLabel: string,
    adBlockEnabled: boolean,
    adBlockAvailable: boolean
  ): SettingsDetailState {
    return {
      id: 'privacy_security',
      title: '隐私防护',
      actionButtons: [
        this.actionButton(
          'clear_data',
          isPrivateContext ? '清除本次私密数据' : '清除浏览数据',
          'clear_all_site_data',
          'danger'
        )
      ],
      groups: [
        {
          id: 'web_protection',
          title: '网页防护',
          rows: [
            this.navigationRow(
              'ad_blocker',
              '网页内容过滤',
              adBlockAvailable ? (adBlockEnabled ? '已开启' : '已关闭') : '需全量模式',
              '',
              'open_ad_block_settings',
              adBlockAvailable
            ),
            this.navigationRow(
              'tracking_protection',
              '防跟踪防护',
              general.enhancedTrackingProtectionEnabled ? '增强' : '标准',
              '',
              'open_tracking_protection_settings',
              canEditDevicePreferences
            ),
            this.navigationRow(
              'cookie_management',
              'Cookie 管理',
              this.resolveCookiePolicyLabel(sitePolicy),
              '',
              'open_cookie_management'
            ),
            this.navigationRow(
              'external_navigation',
              '外部应用跳转',
              this.resolveExternalNavigationPolicyLabel(externalNavigation.appOpenPolicy),
              '',
              'open_external_navigation_settings',
              canEditDevicePreferences
            )
          ],
          footerText: '增强反跟踪会减少跨网站关联，但不代表完整移除浏览器指纹。'
        },
        {
          id: 'site_privacy_data',
          title: '权限与隐私数据',
          rows: [
            this.navigationRow(
              'site_settings',
              '站点设置',
              '',
              '',
              'open_site_settings'
            )
          ],
          footerText: '管理站点权限与已保存的站点规则。'
        },
        {
          id: 'network_privacy',
          title: '网络保护',
          rows: [
            this.navigationRow(
              'secure_dns_settings',
              '安全 DNS',
              secureDnsSummaryLabel,
              '',
              'open_secure_dns_settings',
              canEditDevicePreferences
            )
          ],
          footerText: '安全 DNS 只影响域名解析，不会代理网页流量。'
        },
        {
          id: 'passwords',
          title: '密码',
          rows: [
            this.navigationRow(
              'passwords',
              '密码管理',
              '',
              '网页密码保险箱、自动填充和保存提示',
              'open_password_settings'
            )
          ]
        }
      ]
    };
  }

  private buildPrivateModeState(
    general: SettingsGeneralDisplayState,
    appearance: BrowserAppearanceSettings,
    canEditDevicePreferences: boolean
  ): SettingsDetailState {
    return {
      id: 'private_mode',
      title: '隐私模式',
      actionButtons: [],
      groups: [
        {
          id: 'private_entry',
          title: '进入方式',
          rows: [
            this.switchRow(
              'private_authentication',
              '进入隐私模式时验证身份',
              '',
              'toggle_private_mode_authentication',
              general.privateModeAuthenticationEnabled,
              canEditDevicePreferences
            ),
            this.switchRow(
              'always_use_private_mode',
              '始终保持隐私模式',
              '',
              'toggle_always_use_private_mode',
              general.alwaysUsePrivateMode,
              true
            )
          ],
          footerText: '控制如何进入隐私模式，不改变普通模式的防跟踪设置。'
        },
        {
          id: 'private_data',
          title: '数据与预览',
          rows: [
            this.switchRow(
              'private_preserve_cookies',
              '隐私模式保留 Cookie',
              '',
              'toggle_private_mode_preserve_cookies_on_close',
              general.privateModePreserveCookiesOnClose,
              canEditDevicePreferences
            ),
            this.switchRow(
              'blur_private_tab_previews',
              '模糊私密标签页预览',
              '',
              'toggle_blur_private_tab_previews',
              appearance.blurPrivateTabPreviews,
              canEditDevicePreferences
            ),
            this.staticRow(
              'private_scope',
              '普通与私密数据',
              '分开保存',
              ''
            )
          ],
          footerText: canEditDevicePreferences
            ? '关闭全部隐私标签页时按这里的规则处理数据；私密数据不会混入普通浏览资料。'
            : '当前私密会话不能修改设备级隐私设置。'
        },
        {
          id: 'private_restore',
          title: '恢复',
          rows: [
            this.navigationRow(
              'private_restore_policy',
              '私密标签页恢复',
              general.privateBrowsingLabel,
              '',
              'open_general_private_tabs_settings',
              canEditDevicePreferences
            )
          ],
          footerText: '设置关闭隐私标签页后是否参与下次启动恢复。'
        }
      ]
    };
  }

  private resolveCookiePolicyLabel(sitePolicy: SettingsSitePolicyDisplayState): string {
    if (!sitePolicy.acceptCookies) {
      return '阻止全部';
    }
    if (sitePolicy.thirdPartyCookiePolicyLocked || !sitePolicy.acceptThirdPartyCookies) {
      return '阻止第三方';
    }
    return '不阻止';
  }

  private resolveExternalNavigationPolicyLabel(policy: ExternalNavigationAppOpenPolicy): string {
    if (policy === 'block') {
      return '阻止';
    }
    if (policy === 'allow') {
      return '始终允许';
    }
    return '跳转前询问';
  }

  private buildSiteSettingsState(
    sitePermissions: SettingsSitePermissionsDisplayState,
    isPrivateContext: boolean,
    siteIconRefreshing: boolean
  ): SettingsDetailState {
    const permissionRows = sitePermissions.defaultCapabilities.map(
      (capability: SiteControlsDefaultCapabilityState): SettingsDetailRowState => {
        return this.navigationRow(
          capability.id,
          capability.title,
          capability.valueLabel,
          '没有单独规则时使用',
          this.resolvePermissionDefaultAction(capability.id)
        );
      }
    );
    const storedPermissionRows = [
      this.staticRow(
        'saved_permission_origins',
        isPrivateContext ? '本次会话站点' : '已保存站点',
        `${sitePermissions.savedOriginCount}`,
        sitePermissions.summaryLine
      ),
      this.staticRow('allow_permission_rules', '允许规则', `${sitePermissions.allowRuleCount}`, ''),
      this.staticRow('block_permission_rules', '阻止规则', `${sitePermissions.blockRuleCount}`, '')
    ];
    return {
      id: 'site_settings',
      title: '站点设置',
      actionButtons: [],
      groups: [
        {
          id: 'permissions',
          title: '权限',
          rows: permissionRows
        },
        {
          id: 'stored_permissions',
          title: '已保存权限统计',
          rows: storedPermissionRows
        },
        {
          id: 'stored_permissions_actions',
          title: '权限管理',
          rows: [],
          actionButtons: [
            this.actionButton(
              'reset_site_permissions',
              isPrivateContext ? '清除临时权限' : '重置站点权限',
              'reset_site_permissions',
              'danger',
              sitePermissions.canClearPermissions
            )
          ]
        },
        {
          id: 'site_icons',
          title: '维护',
          rows: [],
          actionButtons: [
            this.actionButton(
              'refresh_site_icons',
              siteIconRefreshing ? '刷新中...' : '刷新网站图标',
              'refresh_site_icons',
              'primary',
              !isPrivateContext && !siteIconRefreshing
            )
          ],
          footerText: isPrivateContext ? '私密会话不刷新常规图标缓存。' : '重新获取书签、历史、快捷方式和离线页面的网站图标。'
        }
      ]
    };
  }

  private buildCommonState(general: SettingsGeneralDisplayState): SettingsDetailState {
    return {
      id: 'general',
      title: '通用',
      actionButtons: [],
      groups: [
        {
          id: 'system',
          title: '系统',
          rows: [
            this.navigationRow(
              'default_browser',
              '默认浏览器',
              general.defaultBrowserLabel,
              '到系统默认浏览器设置中更改',
              'open_default_browser_settings'
            )
          ]
        },
        {
          id: 'startup_tabs',
          title: '启动与标签页',
          rows: [
            this.navigationRow(
              'startup_behavior',
              '启动行为',
              general.startupBehaviorLabel,
              '设置启动时是否恢复常规标签页',
              'open_general_startup_settings'
            ),
            this.navigationRow(
              'tab_auto_close',
              '自动关闭标签页',
              general.tabAutoCloseLabel,
              '选择多久后自动关闭未使用标签页',
              'open_general_tab_auto_close_settings'
            )
          ]
        },
        {
          id: 'browsing_data',
          title: '浏览资料',
          rows: [
            this.navigationRow(
              'history_retention',
              '历史保留',
              general.historyRetentionLabel,
              '选择历史记录保留条数',
              'open_general_history_retention_settings'
            )
          ]
        },
        {
          id: 'keyboard',
          title: '键盘',
          rows: [
            this.navigationRow(
              'keyboard_shortcuts',
              '键盘快捷键',
              '查看',
              '外接键盘可用的浏览器操作',
              'open_keyboard_shortcuts_settings'
            )
          ]
        }
      ]
    };
  }

  private buildAboutState(about: SettingsAboutDisplayState): SettingsDetailState {
    const supportRows: SettingsDetailRowState[] = [
      this.navigationRow('changelog', '更新日志', '', '', 'open_changelog')
    ];
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
      supportRows.push(
        this.navigationRow('app_review', '好评鼓励', '', '', 'open_app_review_page')
      );
    }
    supportRows.push(
      this.navigationRow('qq_group', '交流QQ群', '1049806927', '', 'copy_support_qq_group')
    );
    const groups: SettingsDetailGroupState[] = [
      {
        id: 'identity',
        title: '应用',
        rows: [
          this.staticRow('name', '应用名称', about.appName, ''),
          this.staticRow('version', '版本', `${about.versionName} (${about.versionCode})`, ''),
          this.staticRow('bundle', '包名', about.bundleName, '')
        ]
      },
      {
        id: 'support',
        title: '应用支持',
        rows: supportRows
      }
    ];
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      groups.push({
        id: 'open_source',
        title: '开源项目',
        rows: [
          this.navigationRow(
            'source_repository',
            '源代码仓库',
            'GitHub',
            '',
            'open_community_source_repository'
          ),
          this.navigationRow(
            'open_source_license',
            '开源许可',
            'GPL-3.0-only',
            '',
            'open_community_license'
          ),
          this.navigationRow(
            'third_party_notices',
            '第三方开源许可',
            '',
            '',
            'open_third_party_notices'
          ),
          this.navigationRow(
            'security_policy',
            '安全问题反馈',
            '',
            '',
            'open_community_security_policy'
          )
        ],
        footerText: 'Aira 源代码按 GPL-3.0-only 发布；第三方组件和品牌资产按各自许可使用。'
      });
    } else {
      const legalRows: SettingsDetailRowState[] = [
        this.navigationRow(
          'user_agreement',
          '用户服务协议',
          '',
          '',
          'open_user_service_agreement_web'
        ),
        this.navigationRow(
          'privacy_statement',
          '隐私声明',
          '',
          '',
          'open_privacy_statement'
        ),
        this.navigationRow(
          'pro_membership_service_agreement',
          'Aira Pro会员服务协议',
          '',
          '',
          'open_pro_membership_service_agreement'
        ),
        this.navigationRow(
          'pro_auto_renewal_service_agreement',
          'Aira Pro自动续费服务协议',
          '',
          '',
          'open_pro_auto_renewal_service_agreement'
        ),
        this.navigationRow(
          'third_party_sdk_and_services',
          '第三方SDK及第三方服务清单',
          '',
          '',
          'open_third_party_sdk_and_services'
        ),
        this.navigationRow(
          'third_party_notices',
          '第三方开源许可',
          '',
          '',
          'open_third_party_notices'
        ),
        this.navigationRow(
          'personal_info_and_permissions',
          '个人信息收集与权限使用清单',
          '',
          '',
          'open_personal_info_and_permissions'
        ),
        this.navigationRow(
          'icp_filing',
          '备案号',
          APP_ICP_FILING_NUMBER,
          '',
          'open_icp_filing_query'
        )
      ];
      groups.push({
        id: 'legal_compliance',
        title: '协议与合规',
        rows: legalRows,
        footerText: '相关协议和清单由 Aira 官方公开网页提供。'
      });
    }
    return {
      id: 'about',
      title: '关于Aira',
      actionButtons: [],
      groups: groups
    };
  }

  private buildAppearanceToolbarState(
    themeMode: BrowserThemeMode,
    appearance: BrowserAppearanceSettings,
    canEditDevicePreferences: boolean,
    isPrivateContext: boolean,
    hideTopSafeAreaSettings: boolean,
    tabletInterfaceModeVisible: boolean,
    tabletInterfaceModeLabel: string,
    isLargeScreen: boolean
  ): SettingsDetailState {
    const groups: SettingsDetailGroupState[] = [
        {
          id: 'theme_mode',
          title: '主题模式',
          rows: [
            this.optionRow(
              'theme_mode_light',
              '浅色',
              canEditDevicePreferences ? '' : '当前会话不可修改全局设置',
              'set_theme_light',
              themeMode === 'light',
              canEditDevicePreferences
            ),
            this.optionRow(
              'theme_mode_dark',
              '深色',
              canEditDevicePreferences ? '' : '当前会话不可修改全局设置',
              'set_theme_dark',
              themeMode === 'dark',
              canEditDevicePreferences
            ),
            this.optionRow(
              'theme_mode_system',
              '跟随系统',
              canEditDevicePreferences ? '' : '当前会话不可修改全局设置',
              'set_theme_system',
              themeMode === 'system',
              canEditDevicePreferences
            )
          ]
        },
        {
          id: 'theme',
          title: '主题',
          rows: [
            this.navigationRow(
              'theme_palette',
              '主题色',
              this.getThemePaletteLabel(appearance.themePaletteId),
              canEditDevicePreferences ? '选择内置颜色风格' : '当前会话不可修改全局设置',
              'open_theme_palette_settings',
              canEditDevicePreferences,
              this.getThemePalettePreviewColor(appearance.themePaletteId)
            )
          ]
        },
        {
          id: 'icons_web',
          title: '应用与网页外观',
          rows: [
            this.navigationRow(
              'app_icon',
              '应用图标',
              '可切换',
              '切换桌面应用图标',
              'open_app_icon_settings',
              true
            ),
            this.switchRow(
              'force_dark_web_content',
              '强制网页深色',
              canEditDevicePreferences ? '' : '当前会话不可修改全局设置',
              'toggle_force_dark_web_content',
              appearance.forceDarkWebContentEnabled,
              canEditDevicePreferences
            )
          ]
        },
        {
          id: 'tabs_overview',
          title: '标签页',
          rows: [
            this.navigationRow(
              'tab_overview_layout',
              '标签页样式',
              this.getTabOverviewLayoutStyleLabel(appearance.tabsOverviewLayoutStyle),
              '',
              'show_tab_overview_layout_sheet',
              canEditDevicePreferences
            )
          ],
          footerText: '只改变标签管理页的排列方式，不影响网页内容和恢复。'
        }
    ];
    if (tabletInterfaceModeVisible) {
      groups.unshift({
        id: 'interface_mode',
        title: '界面',
        rows: [
          this.navigationRow(
            'tablet_interface_mode',
            '界面模式',
            tabletInterfaceModeLabel,
            '',
            'open_tablet_interface_mode_settings',
            canEditDevicePreferences
          )
        ]
      });
    }
    if (isLargeScreen) {
      groups.push({
        id: 'desktop_bookmark_bar',
        title: '大屏浏览器栏',
        rows: [
          this.switchRow(
            'desktop_bookmark_bar',
            '显示书签栏',
            canEditDevicePreferences ? '' : '当前会话不可修改全局设置',
            'toggle_desktop_bookmark_bar',
            appearance.showDesktopBookmarkBar !== false,
            canEditDevicePreferences
          )
        ],
        footerText: '仅在平板和桌面窗口显示，设置保存在本设备。'
      });
    }
    if (!hideTopSafeAreaSettings) {
      groups.push({
        id: 'scroll_top_immersion',
        title: '顶部沉浸',
        rows: [
          this.switchRow(
            'global_immersion',
            '滚动时顶部沉浸',
            '',
            'toggle_global_immersion',
            appearance.globalImmersionEnabled,
            canEditDevicePreferences && !appearance.alwaysTopImmersionEnabled
          )
        ],
        footerText: this.buildScrollTopImmersionFooter(canEditDevicePreferences)
      });
      groups.push({
        id: 'always_top_immersion',
        title: '',
        rows: [
          this.switchRow(
            'always_top_immersion',
            '始终顶部沉浸',
            '',
            'toggle_always_top_immersion',
            appearance.alwaysTopImmersionEnabled,
            canEditDevicePreferences
          )
        ],
        footerText: '网页内容始终延伸到屏幕顶部，不单独保留顶部安全区域。'
      });
    }
    return {
      id: 'appearance_toolbar',
      title: '外观设置',
      actionButtons: [],
      groups: groups
    };
  }

  private buildScrollTopImmersionFooter(canEditDevicePreferences: boolean): string {
    if (!canEditDevicePreferences) {
      return '私密中不改全局设置。';
    }
    return '向下滚动网页时收起顶部安全区域，向上滚动或停止后恢复。';
  }

  private buildExperimentsState(
    experiments: BrowserExperimentSettings,
    canEditDevicePreferences: boolean
  ): SettingsDetailState {
    return {
      id: 'experiments',
      title: '实验室',
      actionButtons: [],
      groups: [
        {
          id: 'page_gestures',
          title: '页面手势',
          rows: [
            this.switchRow(
              'pull_refresh',
              '下拉刷新',
              '',
              'toggle_pull_refresh',
              experiments.pullRefreshEnabled,
              canEditDevicePreferences
            ),
            this.switchRow(
              'force_enable_web_zoom',
              '强制允许网页缩放',
              '',
              'toggle_force_enable_web_zoom',
              experiments.forceEnableWebZoom,
              canEditDevicePreferences
            ),
            this.switchRow(
              'smart_grip_tabs_actions',
              '智感握姿',
              '',
              'toggle_smart_grip_tabs_actions',
              experiments.smartGripTabsActionsEnabled,
              canEditDevicePreferences
            )
          ],
          footerText: '下拉刷新会在普通网页顶部下拉时刷新当前页；强制网页缩放会在系统支持时忽略页面 viewport 里的缩放限制；智感握姿会在系统支持时识别握持手，用于优化单手操作布局。'
        },
        {
          id: 'video_takeover',
          title: '视频接管',
          rows: [
            this.switchRow(
              'web_video_takeover',
              '网页视频接管',
              '',
              'toggle_web_video_takeover',
              experiments.webVideoTakeoverEnabled,
              canEditDevicePreferences
            )
          ],
          footerText: '开启后，可使用 Aira 播放器控制网页中的真实视频。'
        },
        {
          id: 'novel_takeover',
          title: '小说模式',
          rows: [
            this.switchRow(
              'novel_mode',
              '小说模式',
              '',
              'toggle_novel_mode',
              experiments.novelModeEnabled,
              canEditDevicePreferences
            ),
            this.switchRow(
              'novel_auto_takeover',
              '自动进入小说模式',
              '',
              'toggle_novel_auto_takeover',
              experiments.novelAutoTakeoverEnabled,
              canEditDevicePreferences && experiments.novelModeEnabled
            )
          ],
          footerText: '关闭自动进入后，仍可通过悬浮按钮手动进入；关闭小说模式后，悬浮按钮也会隐藏。'
        },
        {
          id: 'network',
          title: '高级网络',
          rows: [
            this.navigationRow(
              'app_proxy_settings',
              '应用内代理',
              this.buildAppProxySummary(experiments),
              '',
              'open_app_proxy_settings',
              canEditDevicePreferences
            )
          ],
          footerText: '开启后，网页会通过你设置的代理访问网络；修改后会自动生效。'
        },
        {
          id: 'smooth_browsing',
          title: '网页丝滑模式',
          rows: [
            this.switchRow(
              'pause_web_animations_during_scroll',
              '滚动时暂停网页动画',
              '滚动时临时暂停 CSS 动画和过渡',
              'toggle_pause_web_animations_during_scroll',
              experiments.pauseWebAnimationsDuringScroll,
              canEditDevicePreferences
            ),
            this.switchRow(
              'reduce_media_motion_during_scroll',
              '滚动时降低媒体扰动',
              '滚动时弱化广告 iframe，并暂停离屏视频',
              'toggle_reduce_media_motion_during_scroll',
              experiments.reduceMediaMotionDuringScroll,
              canEditDevicePreferences
            ),
            this.switchRow(
              'strengthen_ad_blocking_for_smooth_scroll',
              '加强广告资源拦截',
              '额外拦截常见广告、埋点和重媒体资源',
              'toggle_strengthen_ad_blocking_for_smooth_scroll',
              experiments.strengthenAdBlockingForSmoothScroll,
              canEditDevicePreferences
            )
          ],
          footerText: '三个实验选项可单独开关；遇到页面表现异常时关闭对应项即可。'
        }
      ]
    };
  }

  private isDevicePreferenceEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    dataScope: string,
    privacyMode: string
  ): boolean {
    return this.isPrivacyEffectAllowed(intent, 'device_preferences', dataScope, privacyMode);
  }

  private isPrivacyEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    targetScope: BrowserPrivacyEffectTargetScope,
    dataScope: string,
    privacyMode: string
  ): boolean {
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: targetScope,
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildWebFeaturesState(appServiceMode: BrowserAppServiceMode): SettingsDetailState {
    const isFullServiceMode = appServiceMode !== 'basic';
    return {
      id: 'web_features',
      title: '网页功能',
      actionButtons: [],
      groups: [
        {
          id: 'translation',
          title: '网页翻译',
          rows: [
            this.navigationRow(
              'webpage_translation',
              '网页翻译',
              this.getFullModeRequiredValue(isFullServiceMode),
              isFullServiceMode ? '选择翻译服务、编辑服务配置和目标语言' : '全量模式下可用',
              'open_webpage_translation_settings',
              isFullServiceMode
            )
          ]
        },
        {
          id: 'downloads',
          title: '下载',
          rows: [
            this.navigationRow(
              'downloads',
              '下载设置',
              '',
              '保存位置、自动清理和私密下载策略',
              'open_download_settings'
            )
          ]
        }
      ]
    };
  }

  private buildSearchState(searchEngineId: SearchEngineId, canEditDevicePreferences: boolean): SettingsDetailState {
    return {
      id: 'search',
      title: '搜索',
      actionButtons: [],
      groups: [
        {
          id: 'search_engine',
          title: '搜索引擎',
          rows: SEARCH_ENGINE_OPTIONS.map((option: SearchEngineOption): SettingsDetailRowState => {
            return this.optionRow(
              `search_${option.id}`,
              option.name,
              this.resolveSearchEngineHelperText(option.id),
              this.resolveSearchEngineAction(option.id),
              option.id === searchEngineId,
              canEditDevicePreferences
            );
          })
        },
        {
          id: 'suggestions',
          title: '搜索建议',
          rows: [
            this.staticRow('suggestions_info', '搜索建议', '已启用', '地址栏显示本地建议')
          ]
        }
      ]
    };
  }

  private buildAppProxySummary(experiments: BrowserExperimentSettings): string {
    if (!experiments.appProxyEnabled) {
      return '关闭';
    }
    if (experiments.appProxy.host.trim().length === 0 || experiments.appProxy.port <= 0) {
      return '待配置';
    }
    const scheme = experiments.appProxy.scheme === 'socks5' ? 'socks' : experiments.appProxy.scheme;
    const activeProfile = this.resolveActiveAppProxyProfile(experiments);
    if (activeProfile !== undefined && activeProfile.name.trim().length > 0) {
      return `${activeProfile.name} · ${scheme}://${experiments.appProxy.host}:${experiments.appProxy.port}`;
    }
    return `${scheme}://${experiments.appProxy.host}:${experiments.appProxy.port}`;
  }

  private resolveActiveAppProxyProfile(experiments: BrowserExperimentSettings) {
    for (let index = 0; index < experiments.appProxyProfiles.length; index += 1) {
      const profile = experiments.appProxyProfiles[index];
      if (profile.id === experiments.appProxyActiveProfileId) {
        return profile;
      }
    }
    return undefined;
  }

  private buildComingNextState(id: SettingsCenterDestination, title: string): SettingsDetailState {
    return {
      id: id,
      title: title,
      actionButtons: [],
      groups: [
        {
          id: 'coming_next',
          title: '即将推出',
          rows: [
            this.staticRow('coming_next', title, '后续补充', '暂未开放设置项')
          ]
        }
      ]
    };
  }

  private staticRow(id: string, title: string, value: string, helperText: string): SettingsDetailRowState {
    return {
      id: id,
      kind: 'static',
      action: 'none',
      title: title,
      value: value,
      valueSwatchColor: '',
      helperText: helperText,
      isEnabled: true,
      isSelected: false,
      checked: false
    };
  }

  private navigationRow(
    id: string,
    title: string,
    value: string,
    helperText: string,
    action: SettingsDetailRowAction,
    isEnabled: boolean = action !== 'none',
    valueSwatchColor: string = ''
  ): SettingsDetailRowState {
    return {
      id: id,
      kind: 'navigation',
      action: action,
      title: title,
      value: value,
      valueSwatchColor: valueSwatchColor,
      helperText: helperText,
      isEnabled: isEnabled,
      isSelected: false,
      checked: false
    };
  }

  private optionRow(
    id: string,
    title: string,
    helperText: string,
    action: SettingsDetailRowAction,
    isSelected: boolean,
    isEnabled: boolean = true
  ): SettingsDetailRowState {
    return {
      id: id,
      kind: 'option',
      action: action,
      title: title,
      value: '',
      valueSwatchColor: '',
      helperText: helperText,
      isEnabled: isEnabled,
      isSelected: isSelected,
      checked: false
    };
  }

  private buildRetentionProfileLabel(profileId: string): string {
    if (profileId === 'memory_saver') {
      return '省电优先';
    }
    if (profileId === 'keep_more_tabs') {
      return '多标签性能';
    }
    return '均衡';
  }

  private switchRow(
    id: string,
    title: string,
    helperText: string,
    action: SettingsDetailRowAction,
    checked: boolean,
    isEnabled: boolean = true
  ): SettingsDetailRowState {
    return {
      id: id,
      kind: 'switch',
      action: action,
      title: title,
      value: '',
      valueSwatchColor: '',
      helperText: helperText,
      isEnabled: isEnabled,
      isSelected: false,
      checked: checked
    };
  }

  private actionButton(
    id: string,
    title: string,
    action: SettingsDetailRowAction,
    emphasis: SettingsDetailActionButtonEmphasis,
    isEnabled: boolean = action !== 'none'
  ): SettingsDetailActionButtonState {
    return {
      id: id,
      title: title,
      action: action,
      isEnabled: isEnabled,
      emphasis: emphasis
    };
  }

  private resolveSearchEngineAction(searchEngineId: SearchEngineId): SettingsDetailRowAction {
    if (searchEngineId === 'google') {
      return 'set_search_google';
    }
    if (searchEngineId === 'duckduckgo') {
      return 'set_search_duckduckgo';
    }
    if (searchEngineId === 'baidu') {
      return 'set_search_baidu';
    }
    if (searchEngineId === 'qihoo') {
      return 'set_search_qihoo';
    }
    if (searchEngineId === 'sogou') {
      return 'set_search_sogou';
    }
    if (searchEngineId === 'shenma') {
      return 'set_search_shenma';
    }
    if (searchEngineId === 'brave') {
      return 'set_search_brave';
    }
    if (searchEngineId === 'startpage') {
      return 'set_search_startpage';
    }
    if (searchEngineId === 'ecosia') {
      return 'set_search_ecosia';
    }
    if (searchEngineId === 'yandex') {
      return 'set_search_yandex';
    }
    return 'set_search_bing';
  }

  private resolveSearchEngineHelperText(searchEngineId: SearchEngineId): string {
    if (searchEngineId === 'qihoo' || searchEngineId === 'sogou' || searchEngineId === 'shenma') {
      return '适合中文内容搜索';
    }
    if (searchEngineId === 'brave' || searchEngineId === 'startpage' || searchEngineId === 'ecosia') {
      return '更注重隐私';
    }
    if (searchEngineId === 'yandex') {
      return '国际搜索补充';
    }
    if (searchEngineId === 'duckduckgo') {
      return '更注重隐私';
    }
    if (searchEngineId === 'baidu') {
      return '适合中文内容搜索';
    }
    if (searchEngineId === 'google') {
      return '使用 Google 搜索';
    }
    return '使用 Bing 搜索';
  }

  private getFullModeRequiredValue(isFullServiceMode: boolean): string {
    return isFullServiceMode ? '' : '需全量模式';
  }

  private getThemePaletteLabel(id: BrowserThemePaletteId): string {
    return this.themePaletteService.resolvePaletteLabel(id);
  }

  private getThemePalettePreviewColor(id: BrowserThemePaletteId): string {
    return this.themePaletteService.resolvePalette(id).previewColor;
  }

  private getTabOverviewLayoutStyleLabel(style: BrowserTabsOverviewLayoutStyle): string {
    return style === 'horizontal_cards' ? '横向大卡片' : '卡片平铺';
  }

  private resolvePermissionDefaultAction(kind: SitePermissionKind): SettingsDetailRowAction {
    if (kind === 'microphone') {
      return 'open_site_permission_default_microphone';
    }
    if (kind === 'location') {
      return 'open_site_permission_default_location';
    }
    if (kind === 'sensor') {
      return 'open_site_permission_default_sensor';
    }
    if (kind === 'clipboard') {
      return 'open_site_permission_default_clipboard';
    }
    return 'open_site_permission_default_camera';
  }

  /**
   * Large-screen only: rewrites the single-choice navigation rows (which on phone
   * push a dedicated picker page) into inline dropdown rows so the desktop shell
   * never opens a new full-screen page just to pick one value.
   */
  applyLargeScreenSingleChoiceDropdowns(
    state: SettingsDetailState,
    snapshot: SettingsSingleChoiceSelectionSnapshot
  ): SettingsDetailState {
    const nextGroups: SettingsDetailGroupState[] = state.groups.map(
      (group: SettingsDetailGroupState): SettingsDetailGroupState => {
        return {
          id: group.id,
          title: group.title,
          rows: group.rows.map(
            (row: SettingsDetailRowState): SettingsDetailRowState => this.convertRowToDropdownIfNeeded(row, snapshot)
          ),
          actionButtons: group.actionButtons,
          footerText: group.footerText
        };
      }
    );
    return {
      id: state.id,
      title: state.title,
      groups: nextGroups,
      actionButtons: state.actionButtons
    };
  }

  private convertRowToDropdownIfNeeded(
    row: SettingsDetailRowState,
    snapshot: SettingsSingleChoiceSelectionSnapshot
  ): SettingsDetailRowState {
    if (row.kind !== 'navigation') {
      return row;
    }
    const options = this.buildSingleChoiceDropdownOptions(row.action, row.isEnabled, snapshot);
    if (options === undefined || options.length === 0) {
      return row;
    }
    const selectedOption = options.find((option: SettingsDetailOption) => option.isSelected);
    return {
      id: row.id,
      kind: 'dropdown',
      action: row.action,
      title: row.title,
      value: selectedOption !== undefined ? selectedOption.label : row.value,
      valueSwatchColor: row.valueSwatchColor,
      helperText: row.helperText,
      isEnabled: row.isEnabled,
      isSelected: row.isSelected,
      checked: row.checked,
      options: options
    };
  }

  private buildSingleChoiceDropdownOptions(
    action: SettingsDetailRowAction,
    rowEnabled: boolean,
    snapshot: SettingsSingleChoiceSelectionSnapshot
  ): SettingsDetailOption[] | undefined {
    if (action === 'open_general_startup_settings') {
      return [
        this.dropdownOption('restore_regular_tabs', '恢复常规标签页', '', snapshot.startupRestorePolicy === 'restore_regular_tabs', rowEnabled),
        this.dropdownOption('open_home', '打开首页', '', snapshot.startupRestorePolicy === 'open_home', rowEnabled)
      ];
    }
    if (action === 'open_general_tab_auto_close_settings') {
      return [
        this.dropdownOption('manual', '不自动关闭', '', snapshot.tabAutoClosePolicy === 'manual', rowEnabled),
        this.dropdownOption('after_15_days', '15 天未使用', '', snapshot.tabAutoClosePolicy === 'after_15_days', rowEnabled),
        this.dropdownOption('after_7_days', '7 天未使用', '', snapshot.tabAutoClosePolicy === 'after_7_days', rowEnabled),
        this.dropdownOption('after_3_days', '3 天未使用', '', snapshot.tabAutoClosePolicy === 'after_3_days', rowEnabled),
        this.dropdownOption('after_1_day', '1 天未使用', '', snapshot.tabAutoClosePolicy === 'after_1_day', rowEnabled),
        this.dropdownOption('on_app_exit', '退出后清除', '', snapshot.tabAutoClosePolicy === 'on_app_exit', rowEnabled)
      ];
    }
    if (action === 'open_general_history_retention_settings') {
      const retention = snapshot.historyRetention;
      return [
        this.dropdownOption('off', '不保存历史', '', !retention.enabled, rowEnabled),
        this.dropdownOption('10000', '90 天 / 10000 条', '', retention.enabled && retention.maxAgeDays === 90 && retention.maxRows === 10000, rowEnabled),
        this.dropdownOption('30_3000', '30 天 / 3000 条', '', retention.enabled && retention.maxAgeDays === 30 && retention.maxRows === 3000, rowEnabled)
      ];
    }
    if (action === 'open_general_private_tabs_settings') {
      return [
        this.dropdownOption('never_restore', '关闭后不恢复', '关闭后不进入下次启动恢复', snapshot.privateTabRestorePolicy === 'never_restore', rowEnabled),
        this.dropdownOption('restore_private_tabs', '允许恢复', '会降低隐私边界，请谨慎开启', snapshot.privateTabRestorePolicy === 'restore_private_tabs', rowEnabled)
      ];
    }
    if (action === 'open_retention_runtime_policy_settings') {
      return [
        this.dropdownOption('memory_saver', '省电优先', '更快释放后台标签页', snapshot.retentionProfileId === 'memory_saver', rowEnabled),
        this.dropdownOption('balanced', '均衡', '日常推荐', snapshot.retentionProfileId === 'balanced', rowEnabled),
        this.dropdownOption('keep_more_tabs', '多标签性能', '保留更多后台标签页', snapshot.retentionProfileId === 'keep_more_tabs', rowEnabled)
      ];
    }
    if (action === 'open_app_service_mode_settings') {
      return [
        this.dropdownOption('full', '全量模式', '', snapshot.appServiceMode === 'full', rowEnabled),
        this.dropdownOption('basic', '基本模式', '', snapshot.appServiceMode === 'basic', rowEnabled)
      ];
    }
    const permissionKind = this.resolveSitePermissionKindForAction(action);
    if (permissionKind !== undefined) {
      const currentRule = this.resolveSitePermissionDefaultRule(snapshot.sitePermissionDefaults, permissionKind);
      return [
        this.dropdownOption('ask', '询问', '每次请求都确认', currentRule === 'ask', rowEnabled),
        this.dropdownOption('allow', '允许', '默认允许', currentRule === 'allow', rowEnabled),
        this.dropdownOption('block', '阻止', '默认阻止', currentRule === 'block', rowEnabled)
      ];
    }
    return undefined;
  }

  private dropdownOption(
    id: string,
    label: string,
    helperText: string,
    isSelected: boolean,
    isEnabled: boolean
  ): SettingsDetailOption {
    return {
      id: id,
      label: label,
      helperText: helperText,
      isSelected: isSelected,
      isEnabled: isEnabled
    };
  }

  private resolveSitePermissionKindForAction(action: SettingsDetailRowAction): SitePermissionKind | undefined {
    if (action === 'open_site_permission_default_camera') {
      return 'camera';
    }
    if (action === 'open_site_permission_default_microphone') {
      return 'microphone';
    }
    if (action === 'open_site_permission_default_location') {
      return 'location';
    }
    if (action === 'open_site_permission_default_sensor') {
      return 'sensor';
    }
    if (action === 'open_site_permission_default_clipboard') {
      return 'clipboard';
    }
    return undefined;
  }

  private resolveSitePermissionDefaultRule(
    defaults: SitePermissionDefaultSettings,
    kind: SitePermissionKind
  ): SitePermissionRule {
    if (kind === 'microphone') {
      return defaults.microphone;
    }
    if (kind === 'location') {
      return defaults.location;
    }
    if (kind === 'sensor') {
      return defaults.sensor;
    }
    if (kind === 'clipboard') {
      return defaults.clipboard;
    }
    return defaults.camera;
  }

  private normalizeId(rawId: string | undefined): SettingsCenterDestination {
    switch (rawId) {
      case 'general':
      case 'advanced_settings':
      case 'app_service_mode':
      case 'search':
      case 'privacy_security':
      case 'private_mode':
      case 'site_settings':
      case 'downloads':
      case 'appearance_toolbar':
      case 'experiments':
      case 'sync':
      case 'passwords':
      case 'ad_blocker':
      case 'user_scripts':
      case 'webpage_translation':
      case 'web_features':
      case 'user_agent':
      case 'about':
        return rawId;
      default:
        return 'general';
    }
  }
}
