import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct AlwaysPrivateModeConfirmationDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link accepted: boolean;
  onCancel: () => void = () => {};
  onConfirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 8 }) {
        Text('始终保持隐私模式')
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text('开启后，重新启动 Aira 会默认进入隐私模式。你仍然可以在本次使用中临时切换到普通模式，但下次启动会再次回到隐私模式。')
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Start)
      }
      .width('100%')

      this.buildAcceptanceRow()

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.onCancel();
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '确认开启',
          emphasis: 'primary',
          actionEnabled: this.accepted,
          accentColor: this.storedAccentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.onConfirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildAcceptanceRow() {
    Row({ space: 10 }) {
      Checkbox()
        .select(this.accepted)
        .selectedColor(this.storedAccentColor)
        .width(20)
        .height(20)
        .hitTestBehavior(HitTestMode.None)

      Text('我理解重启后会默认回到隐私模式')
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.accepted = !this.accepted;
    })
  }
}
