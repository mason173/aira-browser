import {
  SettingsBrowsingDataClearDialogState,
  SettingsBrowsingDataClearItemId,
  SettingsBrowsingDataClearItemState,
  SettingsBrowsingDataClearTimeRangeId,
  SettingsBrowsingDataClearTimeRangeState
} from '../../../core/settings/SettingsSiteDataClearCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const CLEAR_BROWSING_DATA_RANGE_GROUP: string = 'clear-browsing-data-range';

@CustomDialog
export struct ClearBrowsingDataDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link dialogState: SettingsBrowsingDataClearDialogState;
  @Link selectedTimeRangeId: SettingsBrowsingDataClearTimeRangeId;
  @Link selectedItemIds: SettingsBrowsingDataClearItemId[];
  confirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text(this.dialogState.title)
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Scroll() {
        Column({ space: 12 }) {
          if (this.dialogState.showTimeRange) {
            this.buildSectionTitle(this.dialogState.timeRangeTitle)
            this.buildTimeRanges()
          }
          this.buildSectionTitle(this.dialogState.dataTypesTitle)
          this.buildDataItems()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: this.dialogState.confirmLabel,
          emphasis: 'primary',
          actionEnabled: this.selectedItemIds.length > 0,
          accentColor: this.storedAccentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER)
  }

  @Builder
  private buildSectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedSecondaryTextColor)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildTimeRanges() {
    Column() {
      ForEach(this.dialogState.ranges, (range: SettingsBrowsingDataClearTimeRangeState, index: number) => {
        this.buildTimeRangeRow(range, index)
      }, (range: SettingsBrowsingDataClearTimeRangeState) => range.id)
    }
    .width('100%')
    .clip(true)
    .backgroundColor(this.storedFloatingSurfaceColor)
    .borderRadius(16)
  }

  @Builder
  private buildTimeRangeRow(range: SettingsBrowsingDataClearTimeRangeState, index: number) {
    Row({ space: 12 }) {
      Text(range.title)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Radio({
        value: range.id,
        group: CLEAR_BROWSING_DATA_RANGE_GROUP
      })
        .checked(this.selectedTimeRangeId === range.id)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.storedAccentColor
        })
    }
    .width('100%')
    .height(44)
    .padding({ left: 14, right: 12 })
    .alignItems(VerticalAlign.Center)
    .border({
      width: { bottom: index < this.dialogState.ranges.length - 1 ? 0.5 : 0 },
      color: this.storedControlBackgroundColor
    })
    .onClick(() => {
      this.selectedTimeRangeId = range.id;
    })
  }

  @Builder
  private buildDataItems() {
    Column() {
      ForEach(this.dialogState.items, (item: SettingsBrowsingDataClearItemState, index: number) => {
        this.buildDataItemRow(item, index)
      }, (item: SettingsBrowsingDataClearItemState) => item.id)
    }
    .width('100%')
    .clip(true)
    .backgroundColor(this.storedFloatingSurfaceColor)
    .borderRadius(16)
  }

  @Builder
  private buildDataItemRow(item: SettingsBrowsingDataClearItemState, index: number) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(item.title)
          .width('100%')
          .fontSize(15)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.summary)
          .width('100%')
          .fontSize(12)
          .lineHeight(17)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Checkbox()
        .select(this.isItemSelected(item.id))
        .selectedColor(this.storedAccentColor)
        .enabled(item.isEnabled)
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .opacity(item.isEnabled ? 1 : 0.48)
    .border({
      width: { bottom: index < this.dialogState.items.length - 1 ? 0.5 : 0 },
      color: this.storedControlBackgroundColor
    })
    .onClick(() => {
      if (item.isEnabled) {
        this.toggleItem(item.id);
      }
    })
  }

  private isItemSelected(id: SettingsBrowsingDataClearItemId): boolean {
    return this.selectedItemIds.indexOf(id) >= 0;
  }

  private toggleItem(id: SettingsBrowsingDataClearItemId): void {
    if (this.isItemSelected(id)) {
      this.selectedItemIds = this.selectedItemIds.filter((itemId: SettingsBrowsingDataClearItemId) => itemId !== id);
      return;
    }
    const nextIds = this.selectedItemIds.slice();
    nextIds.push(id);
    this.selectedItemIds = nextIds;
  }
}
