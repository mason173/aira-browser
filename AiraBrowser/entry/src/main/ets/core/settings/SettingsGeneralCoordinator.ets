import { BrowserPreferences } from '../../common/models/BrowserModels';
import {
  CustomHomepageItem,
  CustomHomepageSettings
} from '../../common/models/CustomHomepageModels';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { GeneralTabAutoCloseSettingsViewModel } from './GeneralTabAutoCloseSettingsViewModel';

export interface SettingsGeneralState {
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
      historyRetentionLabel: this.resolveHistoryRetentionLabel(preferences),
      privateBrowsingLabel: this.resolvePrivateBrowsingLabel(preferences),
      privateModeAuthenticationEnabled: preferences.general.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: preferences.general.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: preferences.general.privateModePreserveCookiesOnClose,
      enhancedTrackingProtectionEnabled: preferences.general.enhancedTrackingProtectionEnabled === true
    };
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
    return `${preferences.historyRetention.maxAgeDays} 天 / ${preferences.historyRetention.maxRows} 条`;
  }

  private resolvePrivateBrowsingLabel(preferences: BrowserPreferences): string {
    if (preferences.general.privateTabRestorePolicy === 'restore_private_tabs') {
      return '允许恢复';
    }
    return '关闭后不恢复';
  }
}
