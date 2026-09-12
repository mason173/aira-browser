import router from '@ohos.router';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  StartupWelcomeIntroActionState,
  StartupWelcomeIntroViewState
} from '../../core/onboarding/StartupWelcomeIntroViewModel';
import {
  StartupWelcomeIntroCoordinator,
  StartupWelcomeIntroHost,
  StartupWelcomeIntroLoginCredential
} from '../../core/onboarding/StartupWelcomeIntroCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { BrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { HuaweiLoginSheetContent } from '../components/account/HuaweiLoginSheetContent';
import { SettingsActionButton } from '../components/settings/SettingsRows';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../components/common/AppLayoutTokens';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsTopSafeInsetService } from '../../services/settings/SettingsTopSafeInsetService';
import { BROWSER_SHELL_ROUTE } from '../router/AppRoutes';

const STARTUP_WELCOME_TOP_BAR_HEIGHT: number = 56;
const STARTUP_WELCOME_HORIZONTAL_PADDING: number = 24;
const STARTUP_WELCOME_BOTTOM_PADDING: number = 24;
const STARTUP_WELCOME_CONTENT_MAX_WIDTH: number = 430;
const STARTUP_WELCOME_ICON_SIZE: number = 88;
const STARTUP_WELCOME_ICON_RADIUS: number = 20;
const STARTUP_WELCOME_ACTION_HEIGHT: number = 44;
const STARTUP_WELCOME_ACTION_GAP: number = 10;
const STARTUP_WELCOME_SKIP_HEIGHT: number = 36;

const STARTUP_WELCOME_EMPTY_BOUNDARY: BrowserBoundaryRouteState = {
  dataScope: '',
  privacyMode: '',
  boundarySource: ''
};

@Entry
@Component
struct StartupWelcomeIntroPage {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private busy: boolean = false;
  @State private topInset: number = 0;
  private readonly navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private readonly topSafeInsetService: SettingsTopSafeInsetService = new SettingsTopSafeInsetService();
  private readonly host: StartupWelcomeIntroHost = {
    setBusy: (busy: boolean): void => {
      this.busy = busy;
    },
    showMessage: (message: string): void => {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    },
    navigateToPersonalServer: (): void => {
      this.navigationCoordinator.openSyncPersonalServerConfig(STARTUP_WELCOME_EMPTY_BOUNDARY, true);
    },
    navigateToWebdavConfig: (): void => {
      // The WebDAV config page owns the provider picker; entering it directly keeps
      // the flow self-contained so a saved config resumes straight into the shell.
      this.navigationCoordinator.openSyncWebdavConfig(STARTUP_WELCOME_EMPTY_BOUNDARY, 'active', true);
    },
    openUserAgreement: (): void => {
      this.navigationCoordinator.openLegalWebDocument('user_service_agreement', STARTUP_WELCOME_EMPTY_BOUNDARY);
    },
    openPrivacyPolicy: (): void => {
      this.navigationCoordinator.openPrivacyStatement(STARTUP_WELCOME_EMPTY_BOUNDARY);
    },
    leaveIntro: (): void => {
      router.replaceUrl({ url: BROWSER_SHELL_ROUTE }).catch((_error: Error) => {
        this.busy = false;
      });
    }
  };
  private readonly coordinator: StartupWelcomeIntroCoordinator =
    new StartupWelcomeIntroCoordinator(this.host);
  private readonly huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential | undefined
      ) => {
        this.coordinator.handleLoginCredential(this.toCredential(error, response));
      });

  onBackPress(): boolean {
    return true;
  }

  onPageShow(): void {
    this.readTopInset();
    this.coordinator.finishIfConfiguredOnResume();
  }

  build() {
    Column() {
      this.buildTopBar()

      Scroll() {
        Column() {
          this.buildAppIcon()

          Text(this.resolveState().hero.title)
            .width('100%')
            .fontSize(26)
            .lineHeight(34)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
            .margin({ top: 24 })

          Text(this.resolveState().hero.subtitle)
            .width('100%')
            .fontSize(15)
            .lineHeight(23)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .margin({ top: 10 })
        }
        .width('100%')
        .constraintSize({ maxWidth: STARTUP_WELCOME_CONTENT_MAX_WIDTH })
        .padding({ left: STARTUP_WELCOME_HORIZONTAL_PADDING, right: STARTUP_WELCOME_HORIZONTAL_PADDING })
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Center)

      this.buildBottomActions()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildTopBar() {
    Row() {
      Blank()

      Button(this.resolveState().skipActionLabel)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .height(STARTUP_WELCOME_SKIP_HEIGHT)
        .padding({ left: 12, right: 12 })
        .fontSize(15)
        .fontColor(this.storedSecondaryTextColor)
        .enabled(!this.busy)
        .opacity(this.busy ? 0.58 : 1)
        .onClick(() => {
          this.coordinator.completeIntro();
        })
    }
    .width('100%')
    .height(STARTUP_WELCOME_TOP_BAR_HEIGHT)
    .padding({ left: STARTUP_WELCOME_HORIZONTAL_PADDING, right: STARTUP_WELCOME_HORIZONTAL_PADDING })
    .margin({ top: this.topInset })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildAppIcon() {
    Image($r('app.media.aira_default_app_icon'))
      .width(STARTUP_WELCOME_ICON_SIZE)
      .height(STARTUP_WELCOME_ICON_SIZE)
      .borderRadius(STARTUP_WELCOME_ICON_RADIUS)
      .clip(true)
      .objectFit(ImageFit.Cover)
      .interpolation(ImageInterpolation.High)
  }

  @Builder
  private buildBottomActions() {
    Column({ space: STARTUP_WELCOME_ACTION_GAP }) {
      if (this.resolveState().showHuaweiLogin) {
        HuaweiLoginSheetContent({
          contentMode: 'inline',
          buttonHeight: STARTUP_WELCOME_ACTION_HEIGHT,
          controller: this.huaweiLoginButtonController,
          onOpenUserAgreement: () => {
            this.coordinator.openUserAgreement();
          },
          onOpenPrivacyPolicy: () => {
            this.coordinator.openPrivacyPolicy();
          }
        })
      }

      ForEach(this.resolveState().actions, (action: StartupWelcomeIntroActionState) => {
        SettingsActionButton({
          title: action.label,
          variant: 'tonal',
          isEnabled: !this.busy,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.coordinator.handleAction(action.id);
          }
        })
      }, (action: StartupWelcomeIntroActionState) => action.id)
    }
    .width('100%')
    .constraintSize({ maxWidth: STARTUP_WELCOME_CONTENT_MAX_WIDTH })
    .padding({
      left: STARTUP_WELCOME_HORIZONTAL_PADDING,
      right: STARTUP_WELCOME_HORIZONTAL_PADDING,
      bottom: STARTUP_WELCOME_BOTTOM_PADDING
    })
    .enabled(!this.busy)
    .opacity(this.busy ? 0.58 : 1)
  }

  private readTopInset(): void {
    this.topSafeInsetService.resolve(this.getUIContext().getHostContext() as common.UIAbilityContext)
      .then((inset: number) => {
        this.topInset = inset;
      });
  }

  private toCredential(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential | undefined
  ): StartupWelcomeIntroLoginCredential {
    return {
      errorCode: error === undefined ? 0 : error.code,
      errorMessage: error === undefined ? '' : error.message,
      authorizationCode: response === undefined ? '' : response.authorizationCode.trim(),
      openId: response === undefined ? '' : response.openID.trim()
    };
  }

  private resolveState(): StartupWelcomeIntroViewState {
    return this.coordinator.buildState();
  }
}
