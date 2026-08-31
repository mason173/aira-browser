import { AiraProEntryConfirmationViewState } from '../../../core/membership/AiraProEntryConfirmationViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';

const AIRA_PRO_ENTRY_CONFIRMATION_HORIZONTAL_PADDING: number = 24;
const AIRA_PRO_ENTRY_CONFIRMATION_BOTTOM_PADDING: number = 26;
const AIRA_PRO_ENTRY_CONFIRMATION_ROW_RADIUS: number = 16;
const AIRA_PRO_ENTRY_CONFIRMATION_BUTTON_HEIGHT: number = 48;
const AIRA_PRO_ENTRY_CONFIRMATION_CANCEL_HEIGHT: number = 36;

@Component
struct AiraProEntryConfirmationRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: string = '';
  @Prop message: string = '';
  @Link selected: boolean;
  @State private visualSelected: boolean = false;

  aboutToAppear(): void {
    this.visualSelected = this.selected;
  }

  build() {
    Row({ space: 12 }) {
      this.buildSelectionIndicator()

      Column({ space: 3 }) {
        Text(this.title)
          .width('100%')
          .fontSize(15)
          .lineHeight(21)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)

        Text(this.message)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(AIRA_PRO_ENTRY_CONFIRMATION_ROW_RADIUS)
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.toggleSelected();
    })
  }

  @Builder
  private buildSelectionIndicator() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.visualSelected) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.storedOnAccentColor)
      }
    }
    .width(22)
    .height(22)
    .borderRadius(11)
    .backgroundColor(this.visualSelected ? this.storedAccentColor : '#00000000')
    .border({
      width: this.visualSelected ? 0 : 1,
      color: this.visualSelected ? this.storedAccentColor : this.storedSecondaryTextColor
    })
  }

  private toggleSelected(): void {
    const nextSelected = !this.visualSelected;
    this.visualSelected = nextSelected;
    this.selected = nextSelected;
  }
}

@Component
export struct AiraProEntryConfirmationSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AiraProEntryConfirmationViewState = {
    title: 'Pro 是自愿的',
    message: '',
    freeTitle: '',
    freeMessage: '',
    optionalTitle: '',
    optionalMessage: '',
    developerTitle: '',
    developerMessage: '',
    confirmActionTitle: '查看Pro能力',
    cancelActionTitle: '不接受，返回免费版'
  };
  @Prop confirming: boolean = false;
  @Link freeBrowsingAccepted: boolean;
  @Link optionalSupportAccepted: boolean;
  @Link developerChargeAccepted: boolean;
  onConfirm: () => void = () => {};
  onCancel: () => void = () => {};

  build() {
    Column({ space: 18 }) {
      this.buildHeader()

      Column({ space: 10 }) {
        AiraProEntryConfirmationRow({
          title: this.state.freeTitle,
          message: this.state.freeMessage,
          selected: $freeBrowsingAccepted
        })
        AiraProEntryConfirmationRow({
          title: this.state.optionalTitle,
          message: this.state.optionalMessage,
          selected: $optionalSupportAccepted
        })
        AiraProEntryConfirmationRow({
          title: this.state.developerTitle,
          message: this.state.developerMessage,
          selected: $developerChargeAccepted
        })
      }
      .width('100%')

      this.buildActions()
    }
    .width('100%')
    .padding({
      left: AIRA_PRO_ENTRY_CONFIRMATION_HORIZONTAL_PADDING,
      right: AIRA_PRO_ENTRY_CONFIRMATION_HORIZONTAL_PADDING,
      top: 28,
      bottom: AIRA_PRO_ENTRY_CONFIRMATION_BOTTOM_PADDING
    })
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildHeader() {
    Column({ space: 8 }) {
      Text(this.state.title)
        .width('100%')
        .fontSize(22)
        .lineHeight(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.state.message)
        .width('100%')
        .fontSize(14)
        .lineHeight(21)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private buildActions() {
    Column({ space: 8 }) {
      Row() {
        BrowserSheetActionButton({
          label: this.confirming ? '正在进入...' : this.state.confirmActionTitle,
          emphasis: 'primary',
          actionEnabled: this.canConfirm(),
          accentColor: this.storedAccentColor,
          buttonHeight: AIRA_PRO_ENTRY_CONFIRMATION_BUTTON_HEIGHT,
          onAction: () => {
            if (this.canConfirm()) {
              this.onConfirm();
            }
          }
        })
      }
      .width('100%')
      .height(AIRA_PRO_ENTRY_CONFIRMATION_BUTTON_HEIGHT)

      Row() {
        BrowserSheetActionButton({
          label: this.state.cancelActionTitle,
          actionEnabled: !this.confirming,
          buttonHeight: AIRA_PRO_ENTRY_CONFIRMATION_CANCEL_HEIGHT,
          fontSize: 14,
          onAction: () => {
            if (!this.confirming) {
              this.onCancel();
            }
          }
        })
      }
      .width('100%')
      .height(AIRA_PRO_ENTRY_CONFIRMATION_CANCEL_HEIGHT)
    }
    .width('100%')
  }

  private canConfirm(): boolean {
    return this.freeBrowsingAccepted &&
      this.optionalSupportAccepted &&
      this.developerChargeAccepted &&
      !this.confirming;
  }

}
