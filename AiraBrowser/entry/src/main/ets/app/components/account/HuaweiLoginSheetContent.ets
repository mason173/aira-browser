import { LoginWithHuaweiIDButton, loginComponentManager } from '@kit.AccountKit';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const HUAWEI_LOGIN_APP_ICON_SIZE: number = 64;
const HUAWEI_LOGIN_BUTTON_HEIGHT: number = 48;
const HUAWEI_LOGIN_AGREEMENT_CHECKBOX_SIZE: number = 18;
const HUAWEI_LOGIN_AGREEMENT_FONT_SIZE: number = 12;

@Component
export struct HuaweiLoginSheetContent {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private agreementAccepted: boolean = false;
  @Prop contentMode: 'sheet' | 'inline' = 'sheet';
  @Prop buttonHeight: number = HUAWEI_LOGIN_BUTTON_HEIGHT;
  controller: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController();
  onOpenUserAgreement: () => void = () => {};
  onOpenPrivacyPolicy: () => void = () => {};

  aboutToAppear(): void {
    this.syncAgreementStatus();
  }

  build() {
    Column({ space: 0 }) {
      if (this.contentMode === 'sheet') {
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
      }

      Stack() {
        LoginWithHuaweiIDButton({
          params: {
            style: loginComponentManager.Style.BUTTON_RED,
            loginType: loginComponentManager.LoginType.ID,
            borderRadius: this.buttonHeight / 2,
            supportDarkMode: true,
            textAndIconStyle: true
          },
          controller: this.controller
        })
          .width('100%')
          .height(this.buttonHeight)

        if (!this.agreementAccepted) {
          Button('')
            .width('100%')
            .height(this.buttonHeight)
            .type(ButtonType.Normal)
            .backgroundColor(this.storedFloatingSurfaceColor)
            .opacity(0.01)
            .borderRadius(this.buttonHeight / 2)
            .accessibilityText('请先同意用户服务协议和隐私政策')
            .onClick(() => {
              this.showAgreementRequiredToast();
            })
        }
      }
      .width('100%')
      .height(this.buttonHeight)

      this.buildAgreementRow()
    }
    .width('100%')
    .padding(this.resolveContainerPadding())
    .backgroundColor(this.contentMode === 'sheet' ? this.storedFloatingSurfaceColor : Color.Transparent)
  }

  private resolveContainerPadding(): Padding {
    if (this.contentMode === 'inline') {
      return { left: 0, right: 0, bottom: 0 };
    }
    return { left: 24, right: 24, bottom: 28 };
  }

  @Builder
  private buildAgreementRow() {
    // Wrapping row, matching the app's other legal-consent surfaces, so the two
    // agreement links never clip on narrow screens.
    Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center, justifyContent: FlexAlign.Center }) {
      Checkbox()
        .select(this.agreementAccepted)
        .selectedColor(this.storedAccentColor)
        .width(HUAWEI_LOGIN_AGREEMENT_CHECKBOX_SIZE)
        .height(HUAWEI_LOGIN_AGREEMENT_CHECKBOX_SIZE)
        .onChange((selected: boolean) => {
          this.agreementAccepted = selected;
          this.syncAgreementStatus();
        })
        .margin({ right: 6, bottom: 4 })

      Text('已阅读并同意')
        .fontSize(HUAWEI_LOGIN_AGREEMENT_FONT_SIZE)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .onClick(() => {
          this.toggleAgreementAccepted();
        })
        .margin({ right: 6, bottom: 4 })

      this.buildAgreementLink('《用户服务协议》', () => {
        this.onOpenUserAgreement();
      })

      Text('和')
        .fontSize(HUAWEI_LOGIN_AGREEMENT_FONT_SIZE)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .margin({ right: 2, bottom: 4 })

      this.buildAgreementLink('《隐私政策》', () => {
        this.onOpenPrivacyPolicy();
      })
    }
    .width('100%')
    .margin({ top: 20 })
  }

  @Builder
  private buildAgreementLink(label: string, action: () => void) {
    Text(label)
      .fontSize(HUAWEI_LOGIN_AGREEMENT_FONT_SIZE)
      .lineHeight(20)
      .fontColor(this.storedAccentColor)
      .maxLines(1)
      .onClick(action)
      .margin({ right: 6, bottom: 4 })
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
