import {
  BrowserGeneralSettings,
  BrowserStartupRestorePolicy
} from '../../common/models/BrowserModels';

export interface GeneralStartupRestoreOptionState {
  policy: BrowserStartupRestorePolicy;
  title: string;
}

export interface GeneralStartupSettingsState {
  startupRestorePolicy: BrowserStartupRestorePolicy;
  startupOptions: GeneralStartupRestoreOptionState[];
}

export class GeneralStartupSettingsViewModel {
  buildState(general: BrowserGeneralSettings): GeneralStartupSettingsState {
    return {
      startupRestorePolicy: general.startupRestorePolicy,
      startupOptions: [
        {
          policy: 'restore_regular_tabs',
          title: '恢复常规标签页'
        },
        {
          policy: 'open_home',
          title: '打开首页'
        }
      ]
    };
  }

  buildGeneralSettingsWithStartupRestorePolicy(
    current: BrowserGeneralSettings,
    policy: BrowserStartupRestorePolicy
  ): BrowserGeneralSettings {
    return {
      startupRestorePolicy: policy,
      tabAutoClosePolicy: current.tabAutoClosePolicy,
      privateTabRestorePolicy: current.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: current.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: current.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: current.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: current.privateModeThemeEnabled
    };
  }
}
