import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsActionButton } from './SettingsRows';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserDesktopLoginConfirmAction } from '../../../core/browser/BrowserQrScanCoordinator';

const DESKTOP_LOGIN_AVATAR_SIZE: number = 64;

@Component
export struct DesktopLoginConfirmSheetContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop displayName: string = '';
  @Prop uid: string = '';
  @Prop avatarUri: string = '';
  @Prop confirming: boolean = false;
  onAction: (action: BrowserDesktopLoginConfirmAction) => void =
    (_action: BrowserDesktopLoginConfirmAction) => {};

  build() {
    Column() {
      Column({ space: 14 }) {
        this.buildHeaderIcon()

        Text('确认登录桌面插件')
          .fontSize(24)
          .lineHeight(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        Text('请确认是否使用当前账号登录电脑上的 Aira 插件。')
          .width('100%')
          .fontSize(15)
          .lineHeight(22)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 34, left: 24, right: 24, bottom: 26 })

      Column({ space: 0 }) {
        Row({ space: 14 }) {
          this.buildAccountAvatar()

          Column({ space: 4 }) {
            Text(this.resolveDisplayName())
              .fontSize(17)
              .lineHeight(24)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.resolveUidLabel())
              .fontSize(13)
              .lineHeight(18)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      }
      .width('100%')
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(18)
      .clip(true)
      .margin({ left: 24, right: 24 })

      Blank()
        .layoutWeight(1)

      Column({ space: 12 }) {
        SettingsActionButton({
          title: this.confirming ? '正在确认登录' : '确认登录',
          variant: 'filled',
          isEnabled: !this.confirming,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onAction('confirm');
          }
        })

        Button('取消')
          .width('100%')
          .height(44)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
          .enabled(!this.confirming)
          .opacity(this.confirming ? 0.48 : 1)
          .onClick(() => {
            if (!this.confirming) {
              this.onAction('cancel');
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 30 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedFloatingSurfaceColor)
  }

  @Builder
  private buildHeaderIcon() {
    Stack() {
      AiraIcon({
        airaIconId: 'browser.toolbar.addToDesktop',
        iconSize: 34,
        iconColor: this.storedAccentColor
      })
    }
    .width(64)
    .height(64)
    .borderRadius(20)
    .backgroundColor(this.storedPressedBackgroundColor)
  }

  @Builder
  private buildAccountAvatar() {
    Stack() {
      if (this.avatarUri.trim().length > 0) {
        Image(this.avatarUri)
          .width(DESKTOP_LOGIN_AVATAR_SIZE)
          .height(DESKTOP_LOGIN_AVATAR_SIZE)
          .objectFit(ImageFit.Cover)
          .borderRadius(DESKTOP_LOGIN_AVATAR_SIZE / 2)
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(28)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width(DESKTOP_LOGIN_AVATAR_SIZE)
    .height(DESKTOP_LOGIN_AVATAR_SIZE)
    .borderRadius(DESKTOP_LOGIN_AVATAR_SIZE / 2)
    .backgroundColor(this.storedPressedBackgroundColor)
    .clip(true)
  }

  private resolveDisplayName(): string {
    const normalized = this.displayName.trim();
    return normalized.length > 0 ? normalized : 'Aira 账号';
  }

  private resolveUidLabel(): string {
    const normalized = this.uid.trim();
    if (normalized.length <= 0) {
      return '当前华为账号';
    }
    return `用户ID：${normalized}`;
  }
}
