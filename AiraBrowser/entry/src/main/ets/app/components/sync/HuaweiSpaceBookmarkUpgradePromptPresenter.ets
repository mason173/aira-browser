import { SyncExperienceCoordinator } from '../../../core/sync/SyncExperienceCoordinator';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';

export class HuaweiSpaceBookmarkUpgradePromptPresenter {
  private syncExperienceCoordinator: SyncExperienceCoordinator;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private presenting: boolean = false;

  constructor(syncExperienceCoordinator: SyncExperienceCoordinator) {
    this.syncExperienceCoordinator = syncExperienceCoordinator;
  }

  async presentIfNeeded(): Promise<void> {
    if (this.presenting) {
      return;
    }
    const state = await this.syncExperienceCoordinator.prepareHuaweiSpaceBookmarkUpgrade();
    if (!state.shouldPresent) {
      return;
    }
    this.presenting = true;
    try {
      showCenteredAlertDialog({
        title: '重新开启华为云空间书签同步',
        message: '书签同步方式已经升级。请重新开启一次，以便将本机书签真正同步到华为云空间。本机书签、主页收藏、小说书架、常用设置和其他同步方式都不会受到影响。',
        autoCancel: false,
        primaryButton: {
          value: '稍后处理',
          action: () => {
            this.presenting = false;
            void this.syncExperienceCoordinator.acknowledgeHuaweiSpaceBookmarkUpgradePrompt();
          }
        },
        secondaryButton: {
          value: '前往重新开启',
          action: () => {
            this.presenting = false;
            void this.syncExperienceCoordinator.acknowledgeHuaweiSpaceBookmarkUpgradePrompt()
              .finally((): void => {
                this.navigationCoordinator.openSyncSettings({
                  dataScope: 'profile_persistent',
                  privacyMode: 'regular',
                  boundarySource: 'huawei_space_bookmark_g6_upgrade'
                });
              });
          }
        }
      });
    } catch (error) {
      this.presenting = false;
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(JSON.stringify(error));
    }
  }
}
