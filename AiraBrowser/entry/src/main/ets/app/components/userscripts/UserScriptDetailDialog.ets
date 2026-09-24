import {
  UserScriptDetailRowView,
  UserScriptDetailState
} from '../../../core/userscripts/UserScriptDetailViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserLargeScreenModalHeader } from '../browser/BrowserLargeScreenModalHeader';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct UserScriptDetailDialog {
  controller?: CustomDialogController;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Link state: UserScriptDetailState;
  onToggleScript: (enabled: boolean) => void = (_enabled: boolean): void => {};
  onDeleteScript: () => void = (): void => {};
  onClose: () => void = (): void => {};

  build() {
    Column({ space: 0 }) {
      BrowserLargeScreenModalHeader({
        title: this.resolveTitle(),
        dialogMode: true,
        onClose: (): void => {
          this.onClose();
        }
      })

      Scroll() {
        Column({ space: 18 }) {
          this.buildStatusBlock()
          this.buildRowsSection('元数据', this.state.metadataRows)
          this.buildRowsSection('运行诊断', this.state.runtimeRows)
          this.buildRowsSection('脚本存储', this.state.storageRows)
          this.buildSourceSection()
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 4, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)

      if (this.state.found) {
        Row() {
          BrowserSheetActionButton({
            label: '删除脚本',
            emphasis: 'destructive',
            fillAvailableWidth: false,
            buttonWidth: 120,
            buttonHeight: 40,
            fontSize: 14,
            actionEnabled: this.state.actions.deleteEnabled,
            onAction: (): void => {
              this.onDeleteScript();
            }
          })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8, bottom: 20 })
        .justifyContent(FlexAlign.End)
      }
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_SURFACE_MODIFIER)
    .keyboardShortcut(FunctionKey.ESC, [], (): void => {
      this.onClose();
    })
  }

  @Builder
  private buildStatusBlock() {
    Column({ space: 8 }) {
      Text(this.state.subtitle)
        .width('100%')
        .fontSize(13)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.state.statusTitle)
            .width('100%')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.state.enabled ? this.storedAccentColor : this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.state.statusDescription)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.state.enabled })
          .enabled(this.state.found)
          .opacity(this.state.found ? 1 : 0.46)
          .selectedColor(this.storedAccentColor)
          .onChange((enabled: boolean): void => {
            this.onToggleScript(enabled);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildRowsSection(title: string, rows: UserScriptDetailRowView[]) {
    if (rows.length > 0) {
      Column({ space: 0 }) {
        Text(title)
          .width('100%')
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
          .padding({ bottom: 6 })
        Column({ space: 0 }) {
          ForEach(rows, (row: UserScriptDetailRowView, index: number) => {
            this.buildDetailRow(row, index, rows.length)
          }, (row: UserScriptDetailRowView, index: number): string => `${title}-${index}-${row.label}`)
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private buildDetailRow(row: UserScriptDetailRowView, index: number, total: number) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(row.label)
          .width(76)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
        Text(row.value)
          .layoutWeight(1)
          .fontSize(14)
          .lineHeight(19)
          .fontColor(this.storedPrimaryTextColor)
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Top)

      if (index < total - 1) {
        Divider()
          .width('100%')
          .height(1)
          .color(this.storedDividerColor)
      }
    }
    .width('100%')
  }

  @Builder
  private buildSourceSection() {
    if (this.state.sourcePreview.length > 0) {
      Column({ space: 8 }) {
        Text('源码预览')
          .width('100%')
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
        Text(this.state.sourcePreview)
          .width('100%')
          .fontSize(12)
          .fontFamily('monospace')
          .lineHeight(17)
          .fontColor(this.storedSecondaryTextColor)
          .padding(12)
          .backgroundColor(this.storedControlBackgroundColor)
          .borderRadius(12)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  private resolveTitle(): string {
    if (!this.state.found || this.state.title.length === 0) {
      return '脚本详情';
    }
    return this.state.title;
  }
}
