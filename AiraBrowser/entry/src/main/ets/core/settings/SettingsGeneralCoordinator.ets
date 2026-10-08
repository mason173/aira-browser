import {
  APP_LANGUAGE_ENGLISH,
  APP_LANGUAGE_FOLLOW_SYSTEM,
  APP_LANGUAGE_TRADITIONAL_CHINESE
} from '../resources/AppLanguageCatalog';

import { BrowserPreferences } from '../../common/models/BrowserModels';
import {
  CustomHomepageItem,
  CustomHomepageSettings
} from '../../common/models/CustomHomepageModels';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { GeneralTabAutoCloseSettingsViewModel } from './GeneralTabAutoCloseSettingsViewModel';

export interface SettingsGeneralState {
  appLanguageLabel: string;
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
  allowUserScriptsInPrivateMode: boolean;
}

export class SettingsGeneralCoordinator {
  private preferencesRepository: PreferencesRepository;
  private customHomepageRepository?: CustomHomepageRepository;
  private tabAutoCloseSettingsViewModel: GeneralTabAutoCloseSettingsViewModel =
    new GeneralTabAutoCloseSettingsViewModel();

  constructor(preferencesRepository: PreferencesRepository, customHomepageRepository?: CustomHomepageRepository) {
    this.preferencesRepository = preferencesRepository;
    this.customHomepageRepository = customHomepageRepository;
  }

  buildState(): SettingsGeneralState {
    const preferences = this.preferencesRepository.getPreferences();
    return {
      homeLayoutLabel: this.resolveHomeLayoutLabel(preferences.homeLayout),
      customHomepageLabel: this.resolveCustomHomepageLabel(),
      startupBehaviorLabel: this.resolveStartupBehaviorLabel(preferences),
      tabAutoCloseLabel: this.tabAutoCloseSettingsViewModel.resolveLabel(preferences.general.tabAutoClosePolicy),
      defaultBrowserLabel: '由系统设置管理',
      appLanguageLabel: this.resolveAppLanguageLabel(preferences.appLanguage),
      historyRetentionLabel: this.resolveHistoryRetentionLabel(preferences),
      privateBrowsingLabel: this.resolvePrivateBrowsingLabel(preferences),
      privateModeAuthenticationEnabled: preferences.general.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: preferences.general.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: preferences.general.privateModePreserveCookiesOnClose,
      enhancedTrackingProtectionEnabled: preferences.general.enhancedTrackingProtectionEnabled === true,
      allowUserScriptsInPrivateMode: preferences.general.allowUserScriptsInPrivateMode !== false
    };
  }

  /**
   * The value line names the language the app renders in, so a follow-system choice shows
   * the language the system resolved to rather than a bare "跟随系统".
   */
  private resolveAppLanguageLabel(appLanguage: string): string {
    if (appLanguage === APP_LANGUAGE_FOLLOW_SYSTEM) {
      return '跟随系统';
    }
    if (appLanguage === APP_LANGUAGE_ENGLISH) {
      return 'English';
    }
    if (appLanguage === APP_LANGUAGE_TRADITIONAL_CHINESE) {
      return '繁體中文';
    }
    return '简体中文';
  }

  private resolveHomeLayoutLabel(_homeLayout: string): string {
    const preferences = this.preferencesRepository.getPreferences();
    const parts: string[] = [];
    if (preferences.appearance.showHomeShortcuts) {
      parts.push('快捷方式');
    }
    if (preferences.appearance.showHomeRecentlyClosed) {
      parts.push('最近关闭');
    }
    return parts.length > 0 ? parts.join('、') : '仅搜索';
  }

  private resolveCustomHomepageLabel(): string {
    const settings: CustomHomepageSettings | undefined = this.customHomepageRepository?.getSettings();
    if (settings?.mode !== 'custom_html') {
      return '系统主页';
    }
    const selected = settings.items.find((item: CustomHomepageItem): boolean => {
      return item.id === settings.selectedItemId;
    });
    return selected?.kind === 'remote_url' ? '网址主页' : '自定义主页';
  }

  private resolveStartupBehaviorLabel(preferences: BrowserPreferences): string {
    return preferences.general.startupRestorePolicy === 'open_home' ? '打开首页' : '恢复常规标签';
  }

  private resolveHistoryRetentionLabel(preferences: BrowserPreferences): string {
    if (!preferences.historyRetention.enabled) {
      return '不保存历史';
    }
    return `${preferences.historyRetention.maxRows} 条`;
  }

  private resolvePrivateBrowsingLabel(preferences: BrowserPreferences): string {
    if (preferences.general.privateTabRestorePolicy === 'restore_private_tabs') {
      return '允许恢复';
    }
    return '关闭后不恢复';
  }
}

export function localizeGeneralSettingsCopy(value: ResourceStr): ResourceStr {
  if (typeof value !== 'string') {
    return value;
  }
  switch (value) {
    case '默认浏览器':
      return $r('app.string.settings_general_default_browser');
    case '到系统默认浏览器设置中更改':
      return $r('app.string.settings_general_default_browser_detail');
    case '由系统设置管理':
      return $r('app.string.settings_general_system_managed');
    case '启动行为':
      return $r('app.string.settings_general_startup');
    case '设置启动时是否恢复常规标签页':
      return $r('app.string.settings_general_startup_detail');
    case '恢复常规标签':
      return $r('app.string.settings_general_restore_tabs');
    case '恢复常规标签页':
      return $r('app.string.settings_general_restore_tabs_page');
    case '打开首页':
      return $r('app.string.settings_general_open_home');
    case '自动关闭标签页':
      return $r('app.string.settings_general_tab_auto_close');
    case '选择多久后自动关闭未使用标签页':
      return $r('app.string.settings_general_tab_auto_close_detail');
    case '不自动关闭':
      return $r('app.string.settings_general_tab_manual');
    case '退出后清除':
      return $r('app.string.settings_general_clear_on_exit');
    case '历史保留':
      return $r('app.string.settings_general_history_retention');
    case '选择历史记录保留条数':
      return $r('app.string.settings_general_history_retention_detail');
    case '不保存历史':
      return $r('app.string.settings_general_history_off');
    case '键盘快捷键':
      return $r('app.string.settings_general_keyboard_shortcuts');
    case '查看':
      return $r('app.string.settings_pro_value_view');
    case '外接键盘可用的浏览器操作':
      return $r('app.string.settings_general_keyboard_detail');
    case '语言':
      return $r('app.string.settings_general_language');
    case '默认跟随系统语言':
      return $r('app.string.settings_general_language_detail');
    case '跟随系统':
      return $r('app.string.settings_general_language_follow_system');
    case '简体中文':
      return $r('app.string.settings_general_language_chinese');
    case '繁體中文':
      return $r('app.string.settings_general_language_traditional');
    default:
      break;
  }
  return localizeGeneralSettingsCount(value);
}

function localizeGeneralSettingsCount(value: string): ResourceStr {
  const unusedMarker = ' 天未使用';
  if (value.endsWith(unusedMarker)) {
    const daysText = value.substring(0, value.length - unusedMarker.length);
    const days = Number(daysText);
    if (daysText.length > 0 && `${days}` === daysText) {
      return $r('app.string.settings_general_unused_days', days);
    }
  }
  const dayMarker = ' 天';
  if (value.endsWith(dayMarker) && value.indexOf('/') < 0) {
    const daysText = value.substring(0, value.length - dayMarker.length);
    const days = Number(daysText);
    if (daysText.length > 0 && `${days}` === daysText) {
      return $r('app.string.settings_general_days', days);
    }
  }
  const entryMarker = ' 条';
  if (value.endsWith(entryMarker)) {
    const rowsText = value.substring(0, value.length - entryMarker.length);
    const rows = Number(rowsText);
    if (rowsText.length > 0 && `${rows}` === rowsText) {
      return $r('app.string.settings_general_history_count', rows);
    }
  }
  return value;
}
