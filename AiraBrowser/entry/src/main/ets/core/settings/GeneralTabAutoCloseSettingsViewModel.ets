import {
  BrowserGeneralSettings,
  BrowserTabAutoClosePolicy
} from '../../common/models/BrowserModels';

export interface GeneralTabAutoCloseOptionState {
  policy: BrowserTabAutoClosePolicy;
  title: string;
}

export interface GeneralTabAutoCloseSettingsState {
  tabAutoClosePolicy: BrowserTabAutoClosePolicy;
  tabAutoCloseOptions: GeneralTabAutoCloseOptionState[];
  footer: string;
}

export class GeneralTabAutoCloseSettingsViewModel {
  buildState(general: BrowserGeneralSettings): GeneralTabAutoCloseSettingsState {
    return {
      tabAutoClosePolicy: general.tabAutoClosePolicy,
      tabAutoCloseOptions: [
        {
          policy: 'manual',
          title: '不自动关闭'
        },
        {
          policy: 'after_15_days',
          title: '15 天未使用'
        },
        {
          policy: 'after_7_days',
          title: '7 天未使用'
        },
        {
          policy: 'after_3_days',
          title: '3 天未使用'
        },
        {
          policy: 'after_1_day',
          title: '1 天未使用'
        },
        {
          policy: 'on_app_exit',
          title: '退出后清除'
        }
      ],
      footer: this.resolveFooter(general.tabAutoClosePolicy)
    };
  }

  buildGeneralSettingsWithPolicy(
    current: BrowserGeneralSettings,
    policy: BrowserTabAutoClosePolicy
  ): BrowserGeneralSettings {
    return {
      startupRestorePolicy: current.startupRestorePolicy,
      tabAutoClosePolicy: policy,
      privateTabRestorePolicy: current.privateTabRestorePolicy,
      privateModeAuthenticationEnabled: current.privateModeAuthenticationEnabled,
      alwaysUsePrivateMode: current.alwaysUsePrivateMode === true,
      privateModePreserveCookiesOnClose: current.privateModePreserveCookiesOnClose,
      privateModeThemeEnabled: current.privateModeThemeEnabled
    };
  }

  resolveLabel(policy: BrowserTabAutoClosePolicy): string {
    switch (policy) {
      case 'after_15_days':
        return '15 天';
      case 'after_7_days':
        return '7 天';
      case 'after_3_days':
        return '3 天';
      case 'after_1_day':
        return '1 天';
      case 'on_app_exit':
        return '退出后清除';
      case 'manual':
      default:
        return '不自动关闭';
    }
  }

  private resolveFooter(policy: BrowserTabAutoClosePolicy): string {
    if (policy === 'on_app_exit') {
      return '退出后清除会在下次启动时不再恢复上次打开的常规标签页。';
    }
    if (policy === 'manual') {
      return 'Aira 会保留常规标签页，直到你手动关闭。';
    }
    return `超过 ${this.resolveLabel(policy)} 没有使用的常规标签页，会在下次启动或保存会话时自动关闭。`;
  }
}
