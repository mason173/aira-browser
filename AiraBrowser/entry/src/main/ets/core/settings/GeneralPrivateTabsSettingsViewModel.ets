import {
  BrowserGeneralSettings,
  BrowserPrivateTabRestorePolicy
} from '../../common/models/BrowserModels';

export interface GeneralPrivateTabsSettingsState {
  restorePolicy: BrowserPrivateTabRestorePolicy;
  alwaysUsePrivateMode: boolean;
  preserveCookiesOnClose: boolean;
}

export class GeneralPrivateTabsSettingsViewModel {
  buildState(general: BrowserGeneralSettings): GeneralPrivateTabsSettingsState {
    return {
      restorePolicy: general.privateTabRestorePolicy,
      alwaysUsePrivateMode: general.alwaysUsePrivateMode === true,
      preserveCookiesOnClose: general.privateModePreserveCookiesOnClose
    };
  }

  buildGeneralSettingsWithAlwaysUsePrivateMode(
    current: BrowserGeneralSettings,
    enabled: boolean
  ): BrowserGeneralSettings {
    return this.buildGeneralSettings(current, { alwaysUsePrivateMode: enabled });
  }

  buildGeneralSettingsWithRestorePolicy(
    current: BrowserGeneralSettings,
    policy: BrowserPrivateTabRestorePolicy
  ): BrowserGeneralSettings {
    return this.buildGeneralSettings(current, { privateTabRestorePolicy: policy });
  }

  buildGeneralSettingsWithPreserveCookiesOnClose(
    current: BrowserGeneralSettings,
    enabled: boolean
  ): BrowserGeneralSettings {
    return this.buildGeneralSettings(current, { privateModePreserveCookiesOnClose: enabled });
  }

  private buildGeneralSettings(
    current: BrowserGeneralSettings,
    patch: Partial<BrowserGeneralSettings>
  ): BrowserGeneralSettings {
    return {
      startupRestorePolicy: current.startupRestorePolicy,
      tabAutoClosePolicy: current.tabAutoClosePolicy,
      privateTabRestorePolicy: patch.privateTabRestorePolicy ?? current.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: current.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: patch.alwaysUsePrivateMode ?? current.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: patch.privateModePreserveCookiesOnClose ?? current.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: current.privateModeThemeEnabled
    };
  }

}
