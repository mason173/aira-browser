import { SettingsAboutAppIdentity } from './SettingsAboutCoordinator';

export interface SettingsAboutOverviewState {
  appTitle: string;
  versionTitle: string;
  versionText: string;
  moreButtonTitle: string;
}

export class SettingsAboutOverviewViewModel {
  buildState(identity: SettingsAboutAppIdentity): SettingsAboutOverviewState {
    return {
      appTitle: 'Aira',
      versionTitle: '当前版本',
      versionText: `${identity.versionName} (${identity.versionCode})`,
      moreButtonTitle: '查看更多'
    };
  }
}
