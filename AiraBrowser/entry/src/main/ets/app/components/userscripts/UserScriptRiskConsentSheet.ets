import { UserScriptRiskConsentSheetState } from '../../../core/userscripts/UserScriptManagementSessionCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';
import { AiraIcon } from '../common/AiraIcon';

const USER_SCRIPT_RISK_SHEET_MAX_WIDTH: number = 540;
const USER_SCRIPT_RISK_BODY_MAX_HEIGHT: number = 460;
@Component
export struct UserScriptRiskConsentSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: UserScriptRiskConsentSheetState = {
    title: '',
    intro: '',
    riskItems: [],
    confirmation: '',
    primaryActionLabel: '',
    secondaryActionLabel: ''
  };
  @Prop fillAvailableHeight: boolean = false;
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAccept: () => void = () => {};
  onDecline: () => void = () => {};

  build() {
    BrowserBottomSheetSurface({
      maxWidth: USER_SCRIPT_RISK_SHEET_MAX_WIDTH,
      fullHeight: this.layoutMode === 'phone' || this.fillAvailableHeight,
      presentation: this.layoutMode === 'large_screen' && this.fillAvailableHeight ? 'flat_content' : 'bottom_sheet',
      horizontalPadding: this.layoutMode === 'phone' ? 0 : 16,
      topPadding: this.layoutMode === 'phone' ? 0 : 26,
      bottomPadding: this.layoutMode === 'phone' ? 0 : 24
    }) {
      if (this.layoutMode === 'phone') {
        this.buildImmersivePhoneLayout()
      } else {
        this.buildLargeScreenLayout()
      }
    }
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: true,
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      },
      footer: () => {
        this.buildActions()
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll() {
      Column() {
        this.buildRiskContent()
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_FOOTER_CLEARANCE
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  @Builder
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: this.state.title,
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: '关闭用户脚本风险提示',
      onLeadingAction: () => {
        this.onDecline();
      }
    })
  }

  @Builder
  private buildLargeScreenLayout() {
    Column({ space: 18 }) {
      this.buildHeader()

      Scroll() {
        this.buildRiskContent()
      }
      .width('100%')
      .height(this.fillAvailableHeight ? '100%' : '')
      .constraintSize({ maxHeight: this.fillAvailableHeight ? '100%' : USER_SCRIPT_RISK_BODY_MAX_HEIGHT })
      .layoutWeight(this.fillAvailableHeight ? 1 : 0)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })

      Row({ space: 12 }) {
        this.buildActions()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.fillAvailableHeight ? '100%' : '')
  }

  @Builder
  private buildHeader() {
    Column({ space: 8 }) {
      AiraIcon({
        airaIconId: 'settings.notice.userShield',
        iconSize: 34,
        iconColor: this.storedPrimaryTextColor
      })

      Text(this.state.title)
        .width('100%')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildRiskContent() {
    Column({ space: 14 }) {
      Text(this.state.intro)
        .width('100%')
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)

      Column({ space: 12 }) {
        ForEach(this.state.riskItems, (item: string, index: number) => {
          this.buildRiskItem(item, index)
        }, (item: string) => item)
      }
      .width('100%')

      Text(this.state.confirmation)
        .width('100%')
        .fontSize(14)
        .lineHeight(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
  }

  @Builder
  private buildActions() {
    BrowserSheetActionButton({
      label: this.state.secondaryActionLabel,
      onAction: () => {
        this.onDecline();
      }
    })

    BrowserSheetActionButton({
      label: this.state.primaryActionLabel,
      emphasis: 'primary',
      accentColor: this.storedAccentColor,
      onAction: () => {
        this.onAccept();
      }
    })
  }

  @Builder
  private buildRiskItem(item: string, index: number) {
    Row({ space: 10 }) {
      Text(`${index + 1}`)
        .width(22)
        .height(22)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(11)

      Text(item)
        .layoutWeight(1)
        .fontSize(14)
        .lineHeight(20)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}
