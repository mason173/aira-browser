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
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  resolveBrowserSheetHeaderBlurRadius,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const CLEAR_BROWSING_DATA_RANGE_GROUP: string = 'clear-browsing-data-range';
const CLEAR_BROWSING_DATA_SHEET_SIDE_PADDING: number = 16;

@Component
export struct ClearBrowsingDataContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Link dialogState: SettingsBrowsingDataClearDialogState;
  @Link selectedTimeRangeId: SettingsBrowsingDataClearTimeRangeId;
  @Link selectedItemIds: SettingsBrowsingDataClearItemId[];
  /**
   * `sheet` uses the shared phone half-modal header. `dialog` is the PC pane's centered dialog.
   */
  @Prop layoutMode: 'dialog' | 'sheet' = 'dialog';
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};
  @State private sheetHeaderBlurRadius: number = 0;
  @State private sheetScrollOffset: number = 0;

  build() {
    if (this.layoutMode === 'sheet') {
      this.buildSheetLayout()
    } else {
      this.buildDialogLayout()
    }
  }

  @Builder
  private buildDialogLayout() {
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
        this.buildSectionList()
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

      this.buildActions()
    }
  }

  @Builder
  private buildSheetLayout() {
    // Immersive phone sheet: content scrolls under a blurred top, and the header row owns
    // both the title and the close button so the two are laid out on one line together.
    BrowserBottomSheetSurface({
      fullHeight: true,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedFloatingSurfaceColor
    }) {
      BrowserImmersiveSheetLayout({
        footerVisible: true,
        topBlurRadius: this.sheetHeaderBlurRadius,
        closeVisible: true,
        closeAccessibilityLabel: '关闭',
        onClose: (): void => {
          this.onCancel();
        },
        scrollContent: () => {
          this.buildSheetScrollContent()
        },
        header: () => {
          this.buildSheetHeader()
        },
        footer: () => {
          this.buildActions()
        }
      })
    }
  }

  private noteSheetScrollDelta(delta: number): void {
    if (!Number.isFinite(delta)) {
      return;
    }
    this.sheetScrollOffset = Math.max(0, this.sheetScrollOffset + delta);
    this.sheetHeaderBlurRadius = resolveBrowserSheetHeaderBlurRadius(this.sheetScrollOffset);
  }

  private resetSheetHeaderBlur(): void {
    this.sheetScrollOffset = 0;
    this.sheetHeaderBlurRadius = 0;
  }

  @Builder
  private buildSheetHeader() {
    BrowserFeatureSheetHeader({
      title: this.dialogState.title,
      titleColor: this.storedPrimaryTextColor
    })
  }

  @Builder
  private buildSheetScrollContent() {
    Scroll() {
      Column() {
        this.buildSectionList()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: CLEAR_BROWSING_DATA_SHEET_SIDE_PADDING,
        right: CLEAR_BROWSING_DATA_SHEET_SIDE_PADDING,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((delta: number) => {
      this.noteSheetScrollDelta(delta);
    })
    .clip(false)
  }

  @Builder
  private buildSectionList() {
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

  @Builder
  private buildActions() {
    Row({ space: 12 }) {
      BrowserSheetActionButton({
        label: this.dialogState.confirmLabel,
        emphasis: 'primary',
        actionEnabled: this.selectedItemIds.length > 0,
        accentColor: this.storedAccentColor,
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onConfirm();
        }
      })

      BrowserSheetActionButton({
        label: '取消',
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.onCancel();
        }
      })
    }
    .width('100%')
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

/**
 * The same content as a centered dialog for the PC pane. The phone shells host
 * `ClearBrowsingDataContent` in a bottom sheet instead, so this stays a thin wrapper.
 */
@CustomDialog
export struct ClearBrowsingDataDialog {
  controller?: CustomDialogController;
  @Link dialogState: SettingsBrowsingDataClearDialogState;
  @Link selectedTimeRangeId: SettingsBrowsingDataClearTimeRangeId;
  @Link selectedItemIds: SettingsBrowsingDataClearItemId[];
  confirm: () => void = () => {};

  build() {
    ClearBrowsingDataContent({
      dialogState: $dialogState,
      selectedTimeRangeId: $selectedTimeRangeId,
      selectedItemIds: $selectedItemIds,
      layoutMode: 'dialog',
      onConfirm: () => {
        this.confirm();
        this.controller?.close();
      },
      onCancel: () => {
        this.controller?.close();
      }
    })
      .attributeModifier(CENTERED_DIALOG_SYSTEM_TALL_PADDED_SURFACE_MODIFIER)
  }
}
