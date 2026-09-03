import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SyncFailureDetailItem } from '../../../core/sync/SyncFailurePresentationService';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct SyncFailureDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link title: string;
  @Link summary: string;
  @Link details: SyncFailureDetailItem[];
  copyDetails: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text(this.title.length > 0 ? this.title : '同步失败')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.summary)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column({ space: 10 }) {
        Text('技术详情')
          .width('100%')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Start)

        ForEach(this.details, (detail: SyncFailureDetailItem) => {
          this.buildDetailRow(detail)
        }, (detail: SyncFailureDetailItem) => detail.label)
      }
      .width('100%')

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '复制详情',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.copyDetails();
          }
        })

        BrowserSheetActionButton({
          label: '知道了',
          emphasis: 'primary',
          accentColor: this.storedAccentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildDetailRow(detail: SyncFailureDetailItem) {
    Row({ space: 12 }) {
      Text(detail.label)
        .width(78)
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(detail.value)
        .layoutWeight(1)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
