import { SyncExperienceActionOutcome } from '../../../core/sync/SyncExperienceCoordinator';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  createDefaultSyncExperienceViewState,
  SyncExperienceViewState
} from '../../../core/sync/SyncExperienceViewModel';
import {
  SyncOperationProgressController,
  SyncOperationProgressUiState
} from '../../../core/sync/SyncOperationProgressController';
import { SyncSettingsRefreshSignal } from '../../../core/sync/SyncSettingsRefreshSignal';
import { SettingsColoredTileIconResources } from '../../../core/resources/SettingsColoredTileIconResources';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { sharedSyncExperienceCoordinator } from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsSection
} from '../settings/SettingsLayout';
import { SettingsSwitchRow } from '../settings/SettingsRows';
import { SyncOperationProgressDialog } from './SyncOperationProgressDialog';

const DEFAULT_SYNC_EXPERIENCE_STATE: SyncExperienceViewState = createDefaultSyncExperienceViewState();

@Component
export struct SyncMasterControlSection {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string =
    DEFAULT_THEME_PALETTE.light.settingsIconForeground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop isPrivateSession: boolean = false;
  @Prop pageBusy: boolean = false;
  @State private state: SyncExperienceViewState = DEFAULT_SYNC_EXPERIENCE_STATE;
  @State private isBusy: boolean = false;
  @State private progressTitle: string = '';
  @State private progressSubtitle: string = '';
  @State private progressValue: number = 0;
  @State private progressInProgress: boolean = false;
  @State private progressDetails: string = '';
  @State private progressDetailOpacity: number = 1;
  private refreshRevision: number = 0;
  private progressDialogOpen: boolean = false;
  private refreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private progressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $progressInProgress,
      title: $progressTitle,
      subtitle: $progressSubtitle,
      progress: $progressValue,
      details: $progressDetails,
      detailOpacity: $progressDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: true,
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (!this.progressInProgress) {
        dismissDialogAction.dismiss();
      }
    }
  });
  private progressController: SyncOperationProgressController = new SyncOperationProgressController(
    (state: SyncOperationProgressUiState): void => {
      this.progressTitle = state.title;
      this.progressSubtitle = state.subtitle;
      this.progressValue = state.progress;
      this.progressInProgress = state.inProgress;
      this.progressDetails = state.details;
      this.progressDetailOpacity = state.detailOpacity;
    },
    (): boolean => this.progressDialogOpen,
    (): void => {
      this.openProgressDialog();
    },
    (): void => {
      this.closeProgressDialog();
    },
    (title: string, subtitle: string): void => {
      this.showDialog(title, subtitle);
    }
  );

  aboutToAppear(): void {
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.progressController.dispose();
  }

  build() {
    SettingsSection({
      title: '同步控制',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '同步总开关',
          checked: this.state.masterEnabled,
          icon: $r('sys.symbol.arrow_clockwise'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
          iconBackgroundColor: this.storedAccentColor,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'single',
          isEnabled: this.state.hasConfiguredSync && !this.isPrivateSession && !this.pageBusy && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (enabled: boolean) => {
            this.requestMasterStateChange(enabled);
          }
        })
      }
      SettingsFooterText({
        text: '关闭后会暂停书签、历史记录、主页收藏、小说书架和所有常用设置同步，但不会删除本机或云端已有数据。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  private requestMasterStateChange(enabled: boolean): void {
    if (enabled) {
      this.changeMasterState(true);
      return;
    }
    showCenteredAlertDialog({
      title: '关闭同步？',
      message: '关闭后会暂停书签、历史记录、主页收藏、小说书架和所有常用设置同步，但不会删除本机或云端已有数据。',
      autoCancel: true,
      primaryButton: {
        value: '继续同步',
        action: () => {}
      },
      secondaryButton: {
        value: '确认关闭',
        fontColor: this.storedAccentColor,
        action: () => {
          this.changeMasterState(false);
        }
      }
    });
  }

  private changeMasterState(enabled: boolean): void {
    if (this.isBusy || this.pageBusy || this.isPrivateSession) {
      return;
    }
    this.isBusy = true;
    this.progressController.begin(
      enabled ? '正在开启同步' : '正在暂停同步',
      enabled ? '正在恢复同步方式和内容' : '正在安全保存当前同步状态'
    );
    sharedSyncExperienceCoordinator.setMasterEnabled(enabled)
      .then((outcome: SyncExperienceActionOutcome) => {
        if (outcome.type === 'completed') {
          this.progressController.finish(outcome.title, outcome.message, undefined, false);
          return;
        }
        this.progressController.complete();
        this.showDialog(outcome.title, outcome.message);
      })
      .catch((_error: Error) => {
        this.progressController.complete();
        this.showDialog('同步设置未更改', '本机和云端已有数据都已保留，请稍后再试。');
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshSignal.bump();
        this.refreshState();
      });
  }

  private refreshState(): void {
    const revision = ++this.refreshRevision;
    sharedSyncExperienceCoordinator.load()
      .then((state: SyncExperienceViewState) => {
        if (revision === this.refreshRevision) {
          this.state = state;
        }
      })
      .catch((_error: Error) => undefined);
  }

  private showDialog(title: string, message: string): void {
    showCenteredAlertDialog({
      title: title,
      message: message,
      confirm: { value: '知道了', action: () => {} }
    });
  }

  private openProgressDialog(): void {
    if (this.progressDialogOpen) {
      return;
    }
    this.progressDialogOpen = true;
    this.progressDialogController.open();
  }

  private closeProgressDialog(): void {
    if (!this.progressDialogOpen) {
      return;
    }
    this.progressDialogOpen = false;
    this.progressDialogController.close();
  }
}
