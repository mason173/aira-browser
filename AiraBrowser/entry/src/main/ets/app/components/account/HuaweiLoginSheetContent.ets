import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const HUAWEI_LOGIN_APP_ICON_SIZE: number = 64;
const HUAWEI_LOGIN_BUTTON_HEIGHT: number = 48;
const HUAWEI_LOGIN_BUTTON_RADIUS: number = 24;

@Component
export struct HuaweiLoginSheetContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private agreementAccepted: boolean = false;
  controller: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  onOpenUserAgreement: () => void = () => {};
  onOpenPrivacyPolicy: () => void = () => {};

  aboutToAppear(): void {
    this.syncAgreementStatus();
  }

  build() {
    Column({ space: 0 }) {
      Column({ space: 10 }) {
        Image($r('app.media.startup_brand_icon'))
          .width(HUAWEI_LOGIN_APP_ICON_SIZE)
          .height(HUAWEI_LOGIN_APP_ICON_SIZE)
          .borderRadius(18)

        Text('Aira')
          .fontSize(24)
          .lineHeight(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        Text('使用华为账号登录，安全同步你的书签')
          .width('100%')
          .fontSize(15)
          .lineHeight(22)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(2)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: 26, bottom: 54 })

      Stack() {
        LoginWithHuaweiIDButton({
          params: {
            style: loginComponentManager.Style.BUTTON_RED,
            loginType: loginComponentManager.LoginType.ID,
            borderRadius: HUAWEI_LOGIN_BUTTON_RADIUS,
            supportDarkMode: true,
            textAndIconStyle: true
          },
          controller: this.controller
        })
          .width('100%')
          .height(HUAWEI_LOGIN_BUTTON_HEIGHT)

        if (!this.agreementAccepted) {
          Button('')
            .width('100%')
            .height(HUAWEI_LOGIN_BUTTON_HEIGHT)
            .type(ButtonType.Normal)
            .backgroundColor(this.storedFloatingSurfaceColor)
            .opacity(0.01)
            .borderRadius(HUAWEI_LOGIN_BUTTON_RADIUS)
            .accessibilityText('请先同意用户服务协议和隐私政策')
            .onClick(() => {
              this.showAgreementRequiredToast();
            })
        }
      }
      .width('100%')
      .height(HUAWEI_LOGIN_BUTTON_HEIGHT)

      this.buildAgreementRow()
    }
    .width('100%')
    .padding({ left: 24, right: 24, bottom: 28 })
    .backgroundColor(this.storedFloatingSurfaceColor)
  }

  @Builder
  private buildAgreementRow() {
    Row({ space: 8 }) {
      Checkbox()
        .select(this.agreementAccepted)
        .selectedColor(this.storedAccentColor)
        .width(22)
        .height(22)
        .onChange((selected: boolean) => {
          this.agreementAccepted = selected;
          this.syncAgreementStatus();
        })

      Text('已阅读并同意')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .onClick(() => {
          this.toggleAgreementAccepted();
        })

      this.buildAgreementLink('《用户服务协议》', () => {
        this.onOpenUserAgreement();
      })

      Text('和')
        .fontSize(13)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)

      this.buildAgreementLink('《隐私政策》', () => {
        this.onOpenPrivacyPolicy();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 24 })
  }

  @Builder
  private buildAgreementLink(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .lineHeight(20)
      .fontColor(this.storedAccentColor)
      .maxLines(1)
      .onClick(action)
  }

  private toggleAgreementAccepted(): void {
    this.agreementAccepted = !this.agreementAccepted;
    this.syncAgreementStatus();
  }

  private syncAgreementStatus(): void {
    this.controller.setAgreementStatus(
      this.agreementAccepted ?
      loginComponentManager.AgreementStatus.ACCEPTED :
      loginComponentManager.AgreementStatus.NOT_ACCEPTED
    );
  }

  private showAgreementRequiredToast(): void {
    this.getUIContext().getPromptAction().showToast({
      message: '请先阅读并同意用户服务协议和隐私政策',
      duration: 1800
    });
  }
}
