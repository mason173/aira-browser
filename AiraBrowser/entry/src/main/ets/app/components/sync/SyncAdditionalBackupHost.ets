import { AiraAdditionalBackupIntervalDays } from '../../../common/models/AiraSyncModels';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  SyncAdditionalBackupActionOutcome
} from '../../../core/sync/SyncExperienceCoordinator';
import {
  createDefaultSyncAdditionalBackupViewState,
  SyncAdditionalBackupViewState
} from '../../../core/sync/SyncAdditionalBackupViewModel';
import {
  SyncOperationProgressController,
  SyncOperationProgressUiState
} from '../../../core/sync/SyncOperationProgressController';
import { SettingsColoredTileIconResources } from '../../../core/resources/SettingsColoredTileIconResources';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  sharedPreferencesRepository,
  sharedSyncExperienceCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsOptionRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SyncOperationProgressDialog } from './SyncOperationProgressDialog';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout
} from '../browser/BrowserModalBottomSheet';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

interface SyncAdditionalBackupIntervalOption {
  days: AiraAdditionalBackupIntervalDays;
  title: string;
}

const DEFAULT_ADDITIONAL_BACKUP_STATE: SyncAdditionalBackupViewState =
  createDefaultSyncAdditionalBackupViewState();
const ADDITIONAL_BACKUP_INTERVAL_OPTIONS: SyncAdditionalBackupIntervalOption[] = [
  { days: 1, title: '每天一次' },
  { days: 3, title: '每 3 天一次' },
  { days: 7, title: '每 7 天一次' }
];

@Component
export struct SyncAdditionalBackupHost {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
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
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  onBack?: () => void;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };
  @State private state: SyncAdditionalBackupViewState = DEFAULT_ADDITIONAL_BACKUP_STATE;
  @State private isBusy: boolean = false;
  @State private frequencySheetVisible: boolean = false;
  @State private progressTitle: string = '';
  @State private progressSubtitle: string = '';
  @State private progressValue: number = 0;
  @State private progressInProgress: boolean = false;
  @State private progressDetailsText: string = '';
  @State private progressDetailOpacity: number = 1;
  private stateRevision: number = 0;
  private progressDialogOpen: boolean = false;
  private progressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $progressInProgress,
      title: $progressTitle,
      subtitle: $progressSubtitle,
      progress: $progressValue,
      details: $progressDetailsText,
      detailOpacity: $progressDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
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
      this.progressDetailsText = state.details;
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

  onPageShow(): void {
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.progressController.dispose();
  }

  onBackPress(): boolean {
    return this.isBusy;
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '额外备份',
          showBackButton: true,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          onBack: () => {
            this.handleBack();
          }
        })
        this.buildContentScroll()
      } else {
        SettingsHdsScaffold({
          title: '额外备份',
          backIconKind: 'back',
          pageBackground: this.storedPageBackgroundColor,
          headerButtonBackground: this.storedPressedBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          showPrivateIndicator: this.isPrivateSession(),
          onBack: () => {
            this.handleBack();
          }
        }) {
          this.buildContentScroll()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .bindSheet($$this.frequencySheetVisible, this.buildFrequencySheet(), {
      preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: !this.desktopPresentation,
      showClose: true
    })
  }

  @Builder
  private buildContentScroll() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      contentSpace: 16,
      topPadding: 8,
      bottomPadding: 28
    }) {
      this.buildOverviewContent()
    }
  }

  @Builder
  private buildOverviewContent() {
    SettingsSection({ title: '备份设置', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '额外备份',
          desktopPresentation: this.desktopPresentation,
          checked: this.state.enabled,
          icon: $r('sys.symbol.externaldrive_fill'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
          iconBackgroundColor: this.settingsIconBackgrounds.sync,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'first',
          isEnabled: !this.isPrivateSession() && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (enabled: boolean) => {
            this.changeEnabled(enabled);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '备份频率',
          desktopPresentation: this.desktopPresentation,
          value: this.state.intervalLabel,
          icon: $r('sys.symbol.clock_fill'),
          iconBackgroundColor: this.settingsIconBackgrounds.general,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'middle',
          isEnabled: !this.isPrivateSession() && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.frequencySheetVisible = true;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '备份位置',
          desktopPresentation: this.desktopPresentation,
          value: this.state.providerSummary,
          icon: $r('sys.symbol.folder_fill'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('webdav'),
          iconBackgroundColor: this.settingsIconBackgrounds.sync,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'last',
          isEnabled: !this.isPrivateSession() && !this.isBusy && this.canConfigureWebdavBackup(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.openWebdavBackupDestination();
          }
        })
      }
      SettingsFooterText({
        text: this.state.statusMessage,
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }

    Column({ space: 8 }) {
      SettingsActionButton({
        title: this.isBusy ? '正在备份' : '立即备份',
        variant: 'filled',
        isEnabled: this.state.canBackupNow && !this.isPrivateSession() && !this.isBusy,
        accentColor: this.storedAccentColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          this.backupNow();
        }
      })
      Text(`上次备份：${this.state.lastBackupLabel}`)
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private buildFrequencySheet() {
    if (this.desktopPresentation) {
      CenteredDialogSurface() {
        this.buildFrequencyCenteredContent()
      }
    } else {
      BrowserBottomSheetSurface({
        fullHeight: true,
        horizontalPadding: 0,
        topPadding: 0,
        bottomPadding: 0,
        surfaceColor: this.storedPageBackgroundColor
      }) {
        BrowserImmersiveSheetLayout({
          scrollContent: () => {
            this.buildFrequencyPhoneScrollContent()
          },
          header: () => {
            this.buildFrequencyPhoneHeader()
          }
        })
      }
    }
  }

  @Builder
  private buildFrequencyPhoneHeader() {
    // Keep this header in a @Builder. API 24 bindSheet crashes with
    // "class constructor cannot called without 'new'" if BrowserFeatureSheetHeader
    // is constructed directly inside a @BuilderParam arrow function.
    BrowserFeatureSheetHeader({
      title: '备份频率',
      leadingAccessibilityLabel: '关闭',
      onLeadingAction: () => {
        this.frequencySheetVisible = false;
      }
    })
  }

  @Builder
  private buildFrequencyCenteredContent() {
    Column({ space: 8 }) {
      Text('备份频率')
        .width('100%')
        .fontSize(22)
        .lineHeight(29)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)

      Text('选择额外备份自动执行的时间间隔。')
        .width('100%')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)

      this.buildFrequencyOptions()
    }
    .width('100%')
  }

  @Builder
  private buildFrequencyPhoneScrollContent() {
    Scroll() {
      Column({ space: 12 }) {
        Text('选择额外备份自动执行的时间间隔。')
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
        this.buildFrequencyOptions()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: APP_STANDARD_HORIZONTAL_PADDING,
        right: APP_STANDARD_HORIZONTAL_PADDING,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  @Builder
  private buildFrequencyOptions() {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      ForEach(ADDITIONAL_BACKUP_INTERVAL_OPTIONS, (
        option: SyncAdditionalBackupIntervalOption,
        index: number
      ) => {
        SettingsOptionRow({
          title: option.title,
          desktopPresentation: this.desktopPresentation,
          helperText: '',
          rowPosition: this.resolveRowPosition(index, ADDITIONAL_BACKUP_INTERVAL_OPTIONS.length),
          isSelected: option.days === this.state.intervalDays,
          isEnabled: !this.isBusy,
          radioGroup: 'sync-additional-backup-frequency',
          radioValue: `${option.days}`,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          selectedIndicatorColor: this.storedAccentColor,
          onAction: () => {
            this.changeInterval(option.days);
          }
        })
        if (index < ADDITIONAL_BACKUP_INTERVAL_OPTIONS.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (option: SyncAdditionalBackupIntervalOption) => {
        return `${option.days}:${option.days === this.state.intervalDays ? 'selected' : 'idle'}`;
      })
    }
  }

  private refreshState(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      this.handleBack();
      return;
    }
    this.boundary = this.desktopPresentation
      ? {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      }
      : readBrowserBoundaryRouteState(this.boundary);
    const revision = ++this.stateRevision;
    sharedSyncExperienceCoordinator.loadAdditionalBackup(this.isPrivateSession())
      .then((state: SyncAdditionalBackupViewState) => {
        if (revision !== this.stateRevision) {
          return;
        }
        this.state = state;
      })
      .catch((_error: Error) => {
        if (revision !== this.stateRevision) {
          return;
        }
        this.state = DEFAULT_ADDITIONAL_BACKUP_STATE;
      });
  }

  private changeEnabled(enabled: boolean): void {
    if (this.isBusy || this.isPrivateSession()) {
      return;
    }
    this.isBusy = true;
    sharedSyncExperienceCoordinator.setAdditionalBackupEnabled(enabled)
      .then((outcome: SyncAdditionalBackupActionOutcome) => {
        if (outcome.type === 'completed') {
          return;
        }
        if (outcome.requiresOptions === true) {
          this.showOptionsRequiredDialog(outcome.title, outcome.message);
          return;
        }
        this.showDialog(outcome.title, outcome.message);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private changeInterval(days: AiraAdditionalBackupIntervalDays): void {
    if (this.isBusy || this.isPrivateSession() || days === this.state.intervalDays) {
      this.frequencySheetVisible = false;
      return;
    }
    this.isBusy = true;
    sharedSyncExperienceCoordinator.setAdditionalBackupIntervalDays(days)
      .then((outcome: SyncAdditionalBackupActionOutcome) => {
        if (outcome.type === 'completed') {
          this.frequencySheetVisible = false;
          return;
        }
        this.showDialog(outcome.title, outcome.message);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private backupNow(): void {
    if (this.isBusy || this.isPrivateSession()) {
      return;
    }
    this.isBusy = true;
    this.progressController.begin('正在备份', '正在保存书签、主页收藏、小说书架和常用设置的额外副本');
    sharedSyncExperienceCoordinator.runAdditionalBackupNow()
      .then((outcome: SyncAdditionalBackupActionOutcome) => {
        if (outcome.type === 'completed') {
          this.progressController.finish(outcome.title, outcome.message, undefined, false);
          return;
        }
        this.progressController.complete();
        if (outcome.requiresOptions === true) {
          this.showOptionsRequiredDialog(outcome.title, outcome.message);
          return;
        }
        this.showDialog(outcome.title, outcome.message);
      })
      .finally(() => {
        this.isBusy = false;
        this.refreshState();
      });
  }

  private showOptionsRequiredDialog(title: string, message: string): void {
    if (!this.canConfigureWebdavBackup()) {
      this.showDialog(title, message);
      return;
    }
    showCenteredAlertDialog({
      title: title,
      message: message,
      autoCancel: true,
      primaryButton: { value: '稍后', action: () => {} },
      secondaryButton: {
        value: '设置 WebDAV',
        action: () => {
          this.openWebdavBackupDestination();
        }
      }
    });
  }

  private openWebdavBackupDestination(): void {
    if (!this.canConfigureWebdavBackup()) {
      this.showDialog('无法设置额外备份', '当前同步方式已经是 WebDAV，无需再设额外备份。');
      return;
    }
    this.navigationCoordinator.openSyncWebdavConfig(
      this.buildBoundary('sync_additional_backup'),
      'additional_backup'
    );
  }

  private canConfigureWebdavBackup(): boolean {
    return this.state.providerCards.length > 0;
  }

  private handleBack(): void {
    if (this.desktopPresentation) {
      this.onBack?.();
      return;
    }
    this.navigationCoordinator.back();
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

  private isPrivateSession(): boolean {
    return this.boundary.privacyMode === 'private' || this.boundary.dataScope === 'session_ephemeral';
  }

  private buildBoundary(source: string): BrowserBoundaryRouteState {
    return {
      dataScope: this.boundary.dataScope,
      privacyMode: this.boundary.privacyMode,
      boundarySource: source
    };
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
