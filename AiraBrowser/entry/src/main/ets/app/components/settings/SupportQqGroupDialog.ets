import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const SUPPORT_QQ_GROUP_QR_CONTAINER_SIZE: number = 236;
const SUPPORT_QQ_GROUP_QR_CONTAINER_LIGHT: string = '#FFFFFF';
const SUPPORT_QQ_GROUP_QR_CONTAINER_DARK: string = '#28292B';

@CustomDialog
export struct SupportQqGroupDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Prop groupNumber: string = '';
  copyGroupNumber: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text('交流QQ群')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Column({ space: 18 }) {
        Stack({ alignContent: Alignment.Center }) {
          Image($r('app.media.support_qq_group_qr'))
            .width('94%')
            .height('94%')
            .objectFit(ImageFit.Contain)
        }
        .width('100%')
        .aspectRatio(1)
        .constraintSize({
          maxWidth: SUPPORT_QQ_GROUP_QR_CONTAINER_SIZE,
          maxHeight: SUPPORT_QQ_GROUP_QR_CONTAINER_SIZE
        })
        .backgroundColor(this.resolveQrContainerColor())
        .borderRadius(24)

        Column({ space: 4 }) {
          Text('QQ群号')
            .fontSize(13)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.groupNumber)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')

      BrowserSheetActionButton({
        label: '复制群号码',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        fillAvailableWidth: false,
        buttonWidth: '100%',
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.copyGroupNumber();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  private resolveQrContainerColor(): ResourceColor {
    return this.storedResolvedThemeMode === 'dark' ?
      SUPPORT_QQ_GROUP_QR_CONTAINER_DARK :
      SUPPORT_QQ_GROUP_QR_CONTAINER_LIGHT;
  }
}
