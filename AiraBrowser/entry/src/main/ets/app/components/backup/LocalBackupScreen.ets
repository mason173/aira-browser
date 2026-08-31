import { common } from '@kit.AbilityKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserBoundaryRouteState,
  isPrivateBoundaryRoute,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import {
  LocalBackupInspection,
  LocalBackupSectionId,
  LocalBackupSectionPreview,
  LocalBackupSelection
} from '../../../features/backup/LocalBackupModels';
import {
  LocalBackupActionOutcome
} from '../../../core/backup/LocalBackupCoordinator';
import {
  sharedLocalBackupCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsActionButton,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import {
  LocalBackupImportContent,
  LocalBackupImportDialog,
  LocalBackupImportProgressDialog
} from './LocalBackupImportDialog';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct LocalBackupScreen {
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private preparedInspection?: LocalBackupInspection;
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop useCenteredImportDialog: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  onBack?: () => void;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @State private boundary: BrowserBoundaryRouteState = {
    dataScope: '',
    privacyMode: '',
    boundarySource: ''
  };
  @State private isBusy: boolean = false;
  @State private exportBookmarks: boolean = true;
  @State private exportHistory: boolean = true;
  @State private exportPersonalization: boolean = true;
  @State private exportUserScripts: boolean = true;
  @State private exportUserScriptValues: boolean = true;
  @State private hasImportPreview: boolean = false;
  @State private importExportedAt: number = 0;
  @State private importVersionName: string = '';
  @State private importVersionCode: number = 0;
  @State private importBookmarksAvailable: boolean = false;
  @State private importBookmarksCount: number = 0;
  @State private importBookmarks: boolean = false;
  @State private importHistoryAvailable: boolean = false;
  @State private importHistoryCount: number = 0;
  @State private importHistory: boolean = false;
  @State private importPersonalizationAvailable: boolean = false;
  @State private importPersonalizationCount: number = 0;
  @State private importPersonalization: boolean = false;
  @State private importUserScriptsAvailable: boolean = false;
  @State private importUserScriptsCount: number = 0;
  @State private importUserScripts: boolean = false;
  @State private importUserScriptValuesAvailable: boolean = false;
  @State private importUserScriptValuesCount: number = 0;
  @State private importUserScriptValues: boolean = false;
  @State private importSelectionSheetVisible: boolean = false;
  private importSheetDismissedForImport: boolean = false;
  private importDialogDismissedForImport: boolean = false;
  private importProgressDialogOpen: boolean = false;
  private importSelectionDialogController: CustomDialogController = new CustomDialogController({
    builder: LocalBackupImportDialog({
      isBusy: $isBusy,
      exportedAt: $importExportedAt,
      versionName: $importVersionName,
      versionCode: $importVersionCode,
      bookmarksAvailable: $importBookmarksAvailable,
      bookmarksCount: $importBookmarksCount,
      bookmarks: $importBookmarks,
      historyAvailable: $importHistoryAvailable,
      historyCount: $importHistoryCount,
      history: $importHistory,
      personalizationAvailable: $importPersonalizationAvailable,
      personalizationCount: $importPersonalizationCount,
      personalization: $importPersonalization,
      userScriptsAvailable: $importUserScriptsAvailable,
      userScriptsCount: $importUserScriptsCount,
      userScripts: $importUserScripts,
      userScriptValuesAvailable: $importUserScriptValuesAvailable,
      userScriptValuesCount: $importUserScriptValuesCount,
      userScriptValues: $importUserScriptValues,
      onCancel: (): void => {
        this.clearPreparedImport();
      },
      onImport: (): void => {
        this.importFromDialog();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: true,
    onDidDisappear: (): void => {
      this.handleImportDialogDisappear();
    }
  });
  private importProgressDialogController: CustomDialogController = new CustomDialogController({
    builder: LocalBackupImportProgressDialog({}),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: true,
    onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
      if (!this.isBusy) {
        dismissDialogAction.dismiss();
      }
    },
    onDidDisappear: (): void => {
      this.importProgressDialogOpen = false;
    }
  });

  aboutToAppear(): void {
    if (this.embedded) {
      this.boundary = {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      };
      return;
    }
    this.boundary = readBrowserBoundaryRouteState(this.boundary);
  }

  build() {
    Column() {
      if (this.embedded) {
        this.buildContent(16)
      } else {
        SettingsHdsScaffold({
          title: '本地备份',
          backIconKind: 'back',
          pageBackground: this.storedPageBackgroundColor,
          headerButtonBackground: this.storedPressedBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          onBack: () => {
            if (!this.isBusy) {
              if (this.onBack !== undefined) {
                this.onBack();
                return;
              }
              this.navigationCoordinator.back();
            }
          }
        }) {
          this.buildContent(12)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .bindSheet($$this.importSelectionSheetVisible, this.buildImportSelectionSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      title: {
        title: '选择导入内容'
      },
      dragBar: true,
      showClose: true,
      backgroundColor: this.storedPageBackgroundColor,
      onDisappear: (): void => {
        this.handleImportSheetDisappear();
      }
    })
  }

  @Builder
  private buildContent(topPadding: number) {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: topPadding,
      bottomPadding: 28
    }) {
      this.buildExportSection()
      this.buildImportSection()
    }
  }

  @Builder
  private buildExportSection() {
    SettingsSection({ title: '导出到文件', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsSwitchRow({
          title: '书签',
          desktopPresentation: this.desktopPresentation,
          checked: this.exportBookmarks,
          rowPosition: 'first',
          isEnabled: this.canOperate(),
          onChange: (value: boolean) => {
            this.exportBookmarks = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '历史记录',
          desktopPresentation: this.desktopPresentation,
          checked: this.exportHistory,
          rowPosition: 'middle',
          isEnabled: this.canOperate(),
          onChange: (value: boolean) => {
            this.exportHistory = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '常用设置',
          desktopPresentation: this.desktopPresentation,
          checked: this.exportPersonalization,
          rowPosition: 'middle',
          isEnabled: this.canOperate(),
          onChange: (value: boolean) => {
            this.exportPersonalization = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '用户脚本',
          desktopPresentation: this.desktopPresentation,
          checked: this.exportUserScripts,
          rowPosition: 'middle',
          isEnabled: this.canOperate(),
          onChange: (value: boolean) => {
            this.exportUserScripts = value;
            if (!value) {
              this.exportUserScriptValues = false;
            }
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '脚本数据',
          desktopPresentation: this.desktopPresentation,
          checked: this.exportUserScriptValues,
          rowPosition: 'last',
          isEnabled: this.canOperate() && this.exportUserScripts,
          onChange: (value: boolean) => {
            this.exportUserScriptValues = value;
          }
        })
      }
      SettingsActionButton({
        title: this.isBusy ? '正在处理' : '导出备份',
        variant: 'filled',
        isEnabled: this.canOperate() && this.hasAnyExportSelection(),
        accentColor: this.storedAccentColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          void this.exportBackup();
        }
      })
    }
  }

  @Builder
  private buildImportSection() {
    SettingsSection({ title: '从文件导入', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsActionButton({
        title: this.isBusy ? '正在读取' : (this.hasImportPreview ? '继续导入' : '选择备份文件'),
        isEnabled: this.canOperate(),
        accentColor: this.storedAccentColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          if (this.preparedInspection !== undefined) {
            this.openImportSelectionSurface();
            return;
          }
          void this.prepareImport();
        }
      })
    }
  }

  @Builder
  private buildImportSelectionSheet() {
    LocalBackupImportContent({
      presentationKind: 'sheet',
      isBusy: $isBusy,
      exportedAt: $importExportedAt,
      versionName: $importVersionName,
      versionCode: $importVersionCode,
      bookmarksAvailable: $importBookmarksAvailable,
      bookmarksCount: $importBookmarksCount,
      bookmarks: $importBookmarks,
      historyAvailable: $importHistoryAvailable,
      historyCount: $importHistoryCount,
      history: $importHistory,
      personalizationAvailable: $importPersonalizationAvailable,
      personalizationCount: $importPersonalizationCount,
      personalization: $importPersonalization,
      userScriptsAvailable: $importUserScriptsAvailable,
      userScriptsCount: $importUserScriptsCount,
      userScripts: $importUserScripts,
      userScriptValuesAvailable: $importUserScriptValuesAvailable,
      userScriptValuesCount: $importUserScriptValuesCount,
      userScriptValues: $importUserScriptValues,
      onImport: (): void => {
        this.importFromSheet();
      }
    })
  }

  private async exportBackup(): Promise<void> {
    if (!this.canOperate() || !this.hasAnyExportSelection()) {
      return;
    }
    this.isBusy = true;
    const selection: LocalBackupSelection = {
      bookmarks: this.exportBookmarks,
      history: this.exportHistory,
      personalization: this.exportPersonalization,
      userScripts: this.exportUserScripts,
      userScriptValues: this.exportUserScriptValues
    };
    try {
      const outcome = await sharedLocalBackupCoordinator.exportBackup(
        getContext(this) as common.UIAbilityContext,
        selection,
        this.boundary
      );
      this.presentOutcome(outcome);
    } finally {
      this.isBusy = false;
    }
  }

  private async prepareImport(): Promise<void> {
    if (!this.canOperate()) {
      return;
    }
    this.isBusy = true;
    try {
      const outcome = await sharedLocalBackupCoordinator.prepareImport(
        getContext(this) as common.UIAbilityContext,
        this.boundary
      );
      if (outcome.status === 'completed' && outcome.inspection !== undefined) {
        this.preparedInspection = outcome.inspection;
        this.applyInspection(outcome.inspection);
        this.openImportSelectionSurface();
        return;
      }
      this.presentOutcome(outcome);
    } finally {
      this.isBusy = false;
    }
  }

  private async importPrepared(): Promise<void> {
    const inspection = this.preparedInspection;
    if (!this.canOperate() || inspection === undefined) {
      return;
    }
    this.isBusy = true;
    this.openImportProgressDialog();
    const selection: LocalBackupSelection = {
      bookmarks: this.importBookmarks,
      history: this.importHistory,
      personalization: this.importPersonalization,
      userScripts: this.importUserScripts,
      userScriptValues: this.importUserScriptValues
    };
    let outcome: LocalBackupActionOutcome | undefined = undefined;
    try {
      outcome = await sharedLocalBackupCoordinator.importPrepared(inspection, selection, this.boundary);
      if (outcome.status === 'completed') {
        this.clearPreparedImport();
      }
    } finally {
      this.isBusy = false;
      this.closeImportProgressDialog();
    }
    if (outcome !== undefined) {
      this.presentOutcome(outcome);
    }
  }

  private applyInspection(inspection: LocalBackupInspection): void {
    const bookmarks = this.resolvePreviewSection(inspection, 'bookmarks');
    const history = this.resolvePreviewSection(inspection, 'history');
    const personalization = this.resolvePreviewSection(inspection, 'personalization');
    const userScripts = this.resolvePreviewSection(inspection, 'userScripts');
    const userScriptValues = this.resolvePreviewSection(inspection, 'userScriptValues');
    this.importExportedAt = inspection.preview.exportedAt;
    this.importVersionName = inspection.preview.exportedBy.versionName;
    this.importVersionCode = inspection.preview.exportedBy.versionCode;
    this.importBookmarksAvailable = bookmarks.available;
    this.importBookmarksCount = bookmarks.count;
    this.importHistoryAvailable = history.available;
    this.importHistoryCount = history.count;
    this.importPersonalizationAvailable = personalization.available;
    this.importPersonalizationCount = personalization.count;
    this.importUserScriptsAvailable = userScripts.available;
    this.importUserScriptsCount = userScripts.count;
    this.importUserScriptValuesAvailable = userScriptValues.available;
    this.importUserScriptValuesCount = userScriptValues.count;
    this.importBookmarks = this.importBookmarksAvailable;
    this.importHistory = this.importHistoryAvailable;
    this.importPersonalization = this.importPersonalizationAvailable;
    this.importUserScripts = this.importUserScriptsAvailable;
    this.importUserScriptValues = this.importUserScriptValuesAvailable && this.importUserScripts;
    this.hasImportPreview = true;
  }

  private clearPreparedImport(): void {
    this.preparedInspection = undefined;
    this.hasImportPreview = false;
  }

  private openImportSelectionSurface(): void {
    if (this.useCenteredImportDialog) {
      this.importSelectionDialogController.open();
      return;
    }
    this.importSelectionSheetVisible = true;
  }

  private importFromSheet(): void {
    if (!this.canOperate() || this.preparedInspection === undefined) {
      return;
    }
    this.importSheetDismissedForImport = true;
    this.importSelectionSheetVisible = false;
  }

  private handleImportSheetDisappear(): void {
    this.importSelectionSheetVisible = false;
    if (this.importSheetDismissedForImport) {
      this.importSheetDismissedForImport = false;
      void this.importPrepared();
      return;
    }
    this.clearPreparedImport();
  }

  private importFromDialog(): void {
    if (!this.canOperate() || this.preparedInspection === undefined) {
      return;
    }
    this.importDialogDismissedForImport = true;
  }

  private handleImportDialogDisappear(): void {
    if (!this.importDialogDismissedForImport) {
      return;
    }
    this.importDialogDismissedForImport = false;
    void this.importPrepared();
  }

  private openImportProgressDialog(): void {
    if (this.importProgressDialogOpen) {
      return;
    }
    this.importProgressDialogOpen = true;
    this.importProgressDialogController.open();
  }

  private closeImportProgressDialog(): void {
    if (!this.importProgressDialogOpen) {
      return;
    }
    this.importProgressDialogOpen = false;
    this.importProgressDialogController.close();
  }

  private resolvePreviewSection(
    inspection: LocalBackupInspection,
    id: LocalBackupSectionId
  ): LocalBackupSectionPreview {
    return inspection.preview.sections.find((section: LocalBackupSectionPreview): boolean => section.id === id) ?? {
      id: id,
      available: false,
      count: 0
    };
  }

  private presentOutcome(outcome: LocalBackupActionOutcome): void {
    if (outcome.status === 'cancelled' || outcome.title.length <= 0) {
      return;
    }
    showCenteredAlertDialog({
      title: outcome.title,
      message: outcome.message,
      autoCancel: true,
      confirm: { value: '知道了', action: () => {} }
    });
  }

  private canOperate(): boolean {
    return !this.isBusy && !isPrivateBoundaryRoute(this.boundary.dataScope, this.boundary.privacyMode);
  }

  private hasAnyExportSelection(): boolean {
    return this.exportBookmarks || this.exportHistory || this.exportPersonalization ||
      this.exportUserScripts || this.exportUserScriptValues;
  }

}
