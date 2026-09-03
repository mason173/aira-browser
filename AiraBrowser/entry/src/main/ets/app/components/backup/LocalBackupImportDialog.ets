import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER,
  CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER
} from '../common/CenteredDialogSurface';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SettingsGroupCard, SettingsGroupDivider } from '../settings/SettingsLayout';
import {
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import {
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from '../browser/BrowserModalBottomSheet';

export type LocalBackupImportPresentationKind = 'sheet' | 'dialog';

function formatLocalBackupExportedAt(exportedAt: number): string {
  return exportedAt > 0 ? new Date(exportedAt).toLocaleString() : '时间未知';
}

function formatLocalBackupAppVersion(versionName: string, versionCode: number): string {
  return versionName.length > 0
    ? `${versionName} (${Math.max(0, Math.floor(versionCode))})`
    : '版本未知';
}

function buildLocalBackupImportSummary(
  exportedAt: number,
  versionName: string,
  versionCode: number
): string {
  return `${formatLocalBackupExportedAt(exportedAt)} · Aira ${formatLocalBackupAppVersion(versionName, versionCode)}`;
}

@CustomDialog
export struct LocalBackupImportProgressDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  controller?: CustomDialogController;

  build() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(this.storedAccentColor)

      Text('正在导入备份')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text('正在恢复所选内容，请稍候。')
        .width('100%')
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@Component
export struct LocalBackupImportContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop presentationKind: LocalBackupImportPresentationKind = 'sheet';
  @Link isBusy: boolean;
  @Link exportedAt: number;
  @Link versionName: string;
  @Link versionCode: number;
  @Link bookmarksAvailable: boolean;
  @Link bookmarksCount: number;
  @Link bookmarks: boolean;
  @Link historyAvailable: boolean;
  @Link historyCount: number;
  @Link history: boolean;
  @Link personalizationAvailable: boolean;
  @Link personalizationCount: number;
  @Link personalization: boolean;
  @Link userScriptsAvailable: boolean;
  @Link userScriptsCount: number;
  @Link userScripts: boolean;
  @Link userScriptValuesAvailable: boolean;
  @Link userScriptValuesCount: number;
  @Link userScriptValues: boolean;
  onCancel: () => void = () => {};
  onImport: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      if (this.presentationKind === 'dialog') {
        Row({ space: 12 }) {
          Blank()
            .width(36)
            .height(36)

          Column({ space: 4 }) {
            Text('选择导入内容')
              .width('100%')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(buildLocalBackupImportSummary(this.exportedAt, this.versionName, this.versionCode))
              .width('100%')
              .fontSize(13)
              .fontColor(this.storedSecondaryTextColor)
              .textAlign(TextAlign.Center)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Center)

          BrowserSheetIconButton({
            icon: $r('sys.symbol.xmark'),
            iconSize: 18,
            buttonSize: 36,
            accessibilityLabel: '关闭',
            onAction: (): void => {
              this.onCancel();
            }
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: this.buildSectionLabel('书签', this.bookmarksCount),
          checked: this.bookmarks,
          rowPosition: 'first',
          isEnabled: !this.isBusy && this.bookmarksAvailable,
          onChange: (value: boolean): void => {
            this.bookmarks = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: this.buildSectionLabel('历史记录', this.historyCount),
          checked: this.history,
          rowPosition: 'middle',
          isEnabled: !this.isBusy && this.historyAvailable,
          onChange: (value: boolean): void => {
            this.history = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: this.buildSectionLabel('常用设置', this.personalizationCount),
          checked: this.personalization,
          rowPosition: 'middle',
          isEnabled: !this.isBusy && this.personalizationAvailable,
          onChange: (value: boolean): void => {
            this.personalization = value;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: this.buildSectionLabel('用户脚本', this.userScriptsCount),
          checked: this.userScripts,
          rowPosition: 'middle',
          isEnabled: !this.isBusy && this.userScriptsAvailable,
          onChange: (value: boolean): void => {
            this.userScripts = value;
            this.userScriptValues = value && this.userScriptValuesAvailable;
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: this.buildSectionLabel('脚本数据', this.userScriptValuesCount),
          checked: this.userScriptValues,
          rowPosition: 'last',
          isEnabled: !this.isBusy && this.userScriptValuesAvailable && this.userScripts,
          onChange: (value: boolean): void => {
            this.userScriptValues = value;
          }
        })
      }

      if (this.presentationKind === 'sheet') {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsStaticValueRow({
            title: '备份时间',
            value: formatLocalBackupExportedAt(this.exportedAt),
            rowPosition: 'first'
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsStaticValueRow({
            title: '应用版本',
            value: formatLocalBackupAppVersion(this.versionName, this.versionCode),
            rowPosition: 'last'
          })
        }
      }

      BrowserSheetActionButton({
        label: this.isBusy ? '正在导入' : '导入',
        emphasis: 'primary',
        actionEnabled: !this.isBusy && this.hasAnySelection(),
        accentColor: this.storedAccentColor,
        fillAvailableWidth: false,
        buttonWidth: '100%',
        buttonHeight: 44,
        fontSize: 15,
        onAction: (): void => {
          this.onImport();
        }
      })
    }
    .width('100%')
    .padding({
      left: this.presentationKind === 'sheet' ? 16 : 20,
      right: this.presentationKind === 'sheet' ? 16 : 20,
      top: this.presentationKind === 'sheet' ? 8 : 22,
      bottom: this.presentationKind === 'sheet' ? 24 : 18
    })
  }

  private hasAnySelection(): boolean {
    return this.bookmarks || this.history || this.personalization || this.userScripts || this.userScriptValues;
  }

  private buildSectionLabel(label: string, count: number): string {
    return `${label}（${Math.max(0, Math.floor(count))}）`;
  }
}

@CustomDialog
export struct LocalBackupImportDialog {
  controller?: CustomDialogController;
  @Link isBusy: boolean;
  @Link exportedAt: number;
  @Link versionName: string;
  @Link versionCode: number;
  @Link bookmarksAvailable: boolean;
  @Link bookmarksCount: number;
  @Link bookmarks: boolean;
  @Link historyAvailable: boolean;
  @Link historyCount: number;
  @Link history: boolean;
  @Link personalizationAvailable: boolean;
  @Link personalizationCount: number;
  @Link personalization: boolean;
  @Link userScriptsAvailable: boolean;
  @Link userScriptsCount: number;
  @Link userScripts: boolean;
  @Link userScriptValuesAvailable: boolean;
  @Link userScriptValuesCount: number;
  @Link userScriptValues: boolean;
  onCancel: () => void = () => {};
  onImport: () => void = () => {};

  build() {
    Column() {
      LocalBackupImportContent({
        presentationKind: 'dialog',
        isBusy: $isBusy,
        exportedAt: $exportedAt,
        versionName: $versionName,
        versionCode: $versionCode,
        bookmarksAvailable: $bookmarksAvailable,
        bookmarksCount: $bookmarksCount,
        bookmarks: $bookmarks,
        historyAvailable: $historyAvailable,
        historyCount: $historyCount,
        history: $history,
        personalizationAvailable: $personalizationAvailable,
        personalizationCount: $personalizationCount,
        personalization: $personalization,
        userScriptsAvailable: $userScriptsAvailable,
        userScriptsCount: $userScriptsCount,
        userScripts: $userScripts,
        userScriptValuesAvailable: $userScriptValuesAvailable,
        userScriptValuesCount: $userScriptValuesCount,
        userScriptValues: $userScriptValues,
        onCancel: (): void => {
          this.cancelAndClose();
        },
        onImport: (): void => {
          this.onImport();
          this.controller?.close();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SCROLL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      this.cancelAndClose();
    })
  }

  private cancelAndClose(): void {
    this.onCancel();
    this.controller?.close();
  }
}
