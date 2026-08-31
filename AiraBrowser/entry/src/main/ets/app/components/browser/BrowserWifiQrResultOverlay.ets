import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserWifiQrCredentials } from '../../../services/browser/BrowserWifiQrCodeService';
import { BrowserWifiQrResultAction } from '../../../core/browser/BrowserQrScanCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS,
  BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS,
  BrowserBottomSheetSurface,
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from './BrowserModalBottomSheet';
import { BrowserAdaptiveModalOverlay } from './BrowserAdaptiveModalOverlay';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';

const EMPTY_WIFI_QR_CREDENTIALS: BrowserWifiQrCredentials = {
  networkName: '',
  password: ''
};

@Component
export struct BrowserWifiQrResultOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop credentials: BrowserWifiQrCredentials = EMPTY_WIFI_QR_CREDENTIALS;
  @Prop accentColor: ResourceColor = '';
  @Prop externallyControlled: boolean = false;
  @Prop presentationVisible: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @State private visible: boolean = false;
  private openTimer: number = -1;
  private closeTimer: number = -1;
  onAction: (action: BrowserWifiQrResultAction) => void = (_action: BrowserWifiQrResultAction) => {};
  onClosed: () => void = () => {};

  aboutToAppear(): void {
    this.clearTimers();
    if (this.externallyControlled) {
      return;
    }
    this.visible = false;
    this.openTimer = setTimeout(() => {
      this.openTimer = -1;
      this.visible = true;
    }, BROWSER_MODAL_BOTTOM_SHEET_OPEN_DELAY_MS);
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.externallyControlled ? this.presentationVisible : this.visible,
      layoutMode: this.layoutMode,
      title: 'Wi-Fi 信息',
      desktopWidth: '70%',
      desktopHeight: 390,
      desktopMinWidth: 500,
      desktopMaxWidth: 620,
      desktopMinHeight: 360,
      desktopMaxHeight: 430,
      onDismiss: () => {
        this.requestClose();
      }
    }) {
      BrowserBottomSheetSurface({
        presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
        topPadding: 20,
        bottomPadding: 22,
        surfaceColor: this.storedPageBackgroundColor
      }) {
        Column({ space: 18 }) {
          if (this.layoutMode === 'phone') {
            Row() {
              Column({ space: 4 }) {
                Text('Wi-Fi 信息')
                  .fontSize(19)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.storedPrimaryTextColor)
                  .width('100%')

                Text('可将密码复制到电脑或其他设备使用')
                  .fontSize(13)
                  .fontColor(this.storedSecondaryTextColor)
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              BrowserSheetIconButton({
                icon: $r('sys.symbol.xmark'),
                iconSize: 16,
                accessibilityLabel: '关闭',
                onAction: () => {
                  this.requestClose();
                }
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          } else {
            Text('可将密码复制到电脑或其他设备使用')
              .fontSize(13)
              .fontColor(this.storedSecondaryTextColor)
              .width('100%')
          }

          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            this.buildCredentialRow('网络名称', this.credentials.networkName, false)
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            this.buildCredentialRow(
              '密码',
              this.credentials.password.length > 0 ? this.credentials.password : '未包含密码',
              this.credentials.password.length <= 0
            )
          }

          Row({ space: 10 }) {
            BrowserSheetActionButton({
              label: '关闭',
              emphasis: 'secondary',
              onAction: () => {
                this.requestClose();
              }
            })

            BrowserSheetActionButton({
              label: '复制密码',
              emphasis: 'primary',
              actionEnabled: this.credentials.password.length > 0,
              accentColor: this.accentColor,
              onAction: () => {
                this.onAction('copy_password');
              }
            })
          }
          .width('100%')
        }
        .width('100%')
      }
    }
  }

  @Builder
  private buildCredentialRow(label: string, value: string, muted: boolean) {
    Column({ space: 8 }) {
      Text(label)
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .width('100%')

      Text(value)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(muted ? this.storedSecondaryTextColor : this.storedPrimaryTextColor)
        .maxLines(4)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  private requestClose(): void {
    if (this.externallyControlled) {
      this.onAction('dismiss');
      return;
    }
    if (this.closeTimer >= 0) {
      return;
    }
    if (this.openTimer >= 0) {
      clearTimeout(this.openTimer);
      this.openTimer = -1;
    }
    this.visible = false;
    this.closeTimer = setTimeout(() => {
      this.closeTimer = -1;
      this.onClosed();
    }, BROWSER_MODAL_BOTTOM_SHEET_ANIMATION_DURATION_MS);
  }

  private clearTimers(): void {
    if (this.openTimer >= 0) {
      clearTimeout(this.openTimer);
      this.openTimer = -1;
    }
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }
}
