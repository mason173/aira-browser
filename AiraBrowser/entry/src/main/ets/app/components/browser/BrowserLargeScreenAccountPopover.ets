import { loginComponentManager } from '@kit.AccountKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import {
  BrowserLargeScreenAccountLoginCredential,
  BrowserLargeScreenAccountPopoverCoordinator,
  BrowserLargeScreenAccountPopoverHost,
  BrowserLargeScreenAccountPopoverSnapshot
} from '../../../core/browser/BrowserLargeScreenAccountPopoverCoordinator';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import {
  SYNC_SETTINGS_REFRESH_REVISION_KEY,
  SyncSettingsRefreshSignal
} from '../../../core/sync/SyncSettingsRefreshSignal';
import {
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  sharedAiraSyncConfigStore,
  sharedActivityRepository,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { HuaweiAccountInfoContent } from '../account/HuaweiAccountInfoContent';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';

const LARGE_SCREEN_ACCOUNT_BUTTON_SIZE_VP: number = 34;
const LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP: number = 26;
const LARGE_SCREEN_ACCOUNT_PLACEHOLDER_ICON_SIZE_VP: number = 17;
const LARGE_SCREEN_ACCOUNT_POPUP_WIDTH_VP: number = 408;
const LARGE_SCREEN_ACCOUNT_PROFILE_HEIGHT_VP: number = 560;
const LARGE_SCREEN_ACCOUNT_POPUP_RADIUS_VP: number = 20;
const LARGE_SCREEN_ACCOUNT_POPUP_TARGET_SPACE_VP: number = 4;

class BrowserLargeScreenAccountPopoverHostAdapter implements BrowserLargeScreenAccountPopoverHost {
  private onPublishSnapshot: (snapshot: BrowserLargeScreenAccountPopoverSnapshot) => void;
  private onShowMessage: (message: string) => void;
  private onCopyText: (text: string) => Promise<void>;
  private onCloseSurface: () => void;
  private onNotifyAccountChanged: () => void;

  constructor(
    onPublishSnapshot: (snapshot: BrowserLargeScreenAccountPopoverSnapshot) => void,
    onShowMessage: (message: string) => void,
    onCopyText: (text: string) => Promise<void>,
    onCloseSurface: () => void,
    onNotifyAccountChanged: () => void
  ) {
    this.onPublishSnapshot = onPublishSnapshot;
    this.onShowMessage = onShowMessage;
    this.onCopyText = onCopyText;
    this.onCloseSurface = onCloseSurface;
    this.onNotifyAccountChanged = onNotifyAccountChanged;
  }

  publishSnapshot(snapshot: BrowserLargeScreenAccountPopoverSnapshot): void {
    this.onPublishSnapshot(snapshot);
  }

  showMessage(message: string): void {
    this.onShowMessage(message);
  }

  copyText(text: string): Promise<void> {
    return this.onCopyText(text);
  }

  closeSurface(): void {
    this.onCloseSurface();
  }

  notifyAccountChanged(): void {
    this.onNotifyAccountChanged();
  }
}

@Component
export struct BrowserLargeScreenAccountPopover {
  @Prop privateMode: boolean = false;
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  @Prop popupReservedTopVp: number = 0;
  onOpenAiraPro: () => void = () => {};
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY)
  private storedSettingsIconForegroundColor: string = '#FFFFFF';
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('handleAccountRefreshSignal')
  private syncSettingsRefreshRevision: number = 0;

  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private themePreferencesListenerKey: string = '';
  private accountHost: BrowserLargeScreenAccountPopoverHost =
    new BrowserLargeScreenAccountPopoverHostAdapter(
      (snapshot: BrowserLargeScreenAccountPopoverSnapshot): void => {
        this.snapshot = snapshot;
      },
      (message: string): void => {
        this.showToast(message);
      },
      (text: string): Promise<void> => this.copyText(text),
      (): void => {
        this.popupVisible = false;
      },
      (): void => {
        this.syncSettingsRefreshSignal.bump();
      }
    );
  private coordinator: BrowserLargeScreenAccountPopoverCoordinator =
    new BrowserLargeScreenAccountPopoverCoordinator(
      sharedAiraSyncConfigStore,
      sharedMembershipFeature,
      sharedActivityRepository,
      sharedHuaweiAccountMutationCoordinator,
      this.accountHost
    );
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential | undefined
      ) => {
        this.handleHuaweiLoginResult(error, response);
      });

  @State private popupVisible: boolean = false;
  @State private snapshot: BrowserLargeScreenAccountPopoverSnapshot = this.coordinator.getSnapshot();
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.coordinator.refresh(this.buildDataBoundaryInput());
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      this.buildAvatar()
    }
    .width(LARGE_SCREEN_ACCOUNT_BUTTON_SIZE_VP)
    .height(LARGE_SCREEN_ACCOUNT_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(this.snapshot.signedIn ? '账号信息' : '登录华为账号')
    .onClick(() => {
      if (!this.snapshot.signedIn && !this.coordinator.canSignIn(this.buildDataBoundaryInput())) {
        this.showToast('请回到普通会话后登录华为账号。');
        return;
      }
      const shouldOpen = !this.popupVisible;
      this.popupVisible = shouldOpen;
      if (shouldOpen) {
        this.coordinator.refresh(this.buildDataBoundaryInput());
      }
    })
    .bindPopup(this.popupVisible, {
      builder: this.buildAccountPopup,
      placement: Placement.BottomRight,
      popupColor: this.theme.floatingSurface,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: LARGE_SCREEN_ACCOUNT_POPUP_TARGET_SPACE_VP,
      width: this.resolvePopupWidth(),
      radius: LARGE_SCREEN_ACCOUNT_POPUP_RADIUS_VP,
      showInSubWindow: false,
      focusable: true,
      shadow: {
        radius: 24,
        color: $r('app.color.elevation_shadow'),
        offsetX: 0,
        offsetY: 8
      },
      onStateChange: (event: PopupStateChangeParam) => {
        this.popupVisible = event.isVisible;
      }
    })
  }

  @Builder
  private buildAvatar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.snapshot.profile.avatarUri.trim().length > 0) {
        Image(this.snapshot.profile.avatarUri)
          .width(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP)
          .height(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP)
          .borderRadius(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP / 2)
          .clip(true)
          .objectFit(ImageFit.Cover)
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(LARGE_SCREEN_ACCOUNT_PLACEHOLDER_ICON_SIZE_VP)
          .fontColor([this.theme.textPrimary])
      }
    }
    .width(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP)
    .height(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP)
    .borderRadius(LARGE_SCREEN_ACCOUNT_AVATAR_SIZE_VP / 2)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .clip(true)
  }

  @Builder
  private buildAccountPopup() {
    if (this.snapshot.signedIn) {
      Scroll() {
        HuaweiAccountInfoContent({
          state: this.snapshot.profile,
          theme: this.theme,
          iconForegroundColor: this.storedSettingsIconForegroundColor,
          isBusy: this.snapshot.busy,
          contentMode: 'embedded_popup',
          showAiraProEntry: true,
          onOpenAiraPro: () => {
            this.popupVisible = false;
            this.onOpenAiraPro();
          },
          onCopyAccountId: () => {
            this.coordinator.requestCopyAccountId();
          },
          onRequestSignOut: () => {
            this.confirmSignOut();
          }
        })
      }
      .width('100%')
      .height(this.resolveProfileHeight())
      .padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)
      .backgroundColor(this.theme.pageBackground)
    } else {
      HuaweiLoginSheetContent({
        controller: this.huaweiLoginButtonController,
        onOpenUserAgreement: () => {
          this.openUserAgreement();
        },
        onOpenPrivacyPolicy: () => {
          this.openPrivacyPolicy();
        }
      })
    }
  }

  private resolvePopupWidth(): number {
    return this.modalLayoutService.resolvePopupWidth(
      this.viewportWidthVp,
      LARGE_SCREEN_ACCOUNT_POPUP_WIDTH_VP
    );
  }

  private resolveProfileHeight(): number {
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      LARGE_SCREEN_ACCOUNT_PROFILE_HEIGHT_VP,
      this.popupReservedTopVp
    );
  }

  private handleHuaweiLoginResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential | undefined
  ): void {
    const credential: BrowserLargeScreenAccountLoginCredential = {
      errorCode: error === undefined ? 0 : error.code,
      errorMessage: error === undefined ? '' : error.message,
      authorizationCode: response === undefined ? '' : response.authorizationCode,
      openId: response === undefined ? '' : response.openID
    };
    this.coordinator.handleLoginCredential(credential, this.buildDataBoundaryInput());
  }

  private confirmSignOut(): void {
    if (!this.snapshot.profile.canSignOut || this.snapshot.busy) {
      return;
    }
    if (!this.coordinator.canSignOut(this.buildDataBoundaryInput())) {
      this.showToast('请回到普通会话后退出华为账号。');
      return;
    }
    showCenteredAlertDialog({
      title: '退出华为账号吗',
      message: '退出后会关闭书签云同步并清除本机保存的华为账号身份，本机书签不会删除。WebDAV 配置和同步状态会保留。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.coordinator.signOutHuaweiAccount(this.buildDataBoundaryInput());
        }
      }
    });
  }

  private openUserAgreement(): void {
    this.popupVisible = false;
    this.navigationCoordinator.openLegalWebDocument('user_service_agreement', this.buildBoundaryState());
  }

  private openPrivacyPolicy(): void {
    this.popupVisible = false;
    this.navigationCoordinator.openPrivacyStatement(this.buildBoundaryState());
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.privateMode ? 'session_ephemeral' : 'profile_persistent',
      privacyMode: this.privateMode ? 'private' : 'regular',
      boundarySource: 'browser_large_screen_account'
    };
  }

  private buildDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.privateMode ? 'session_ephemeral' : 'profile_persistent',
      privacyMode: this.privateMode ? 'private' : 'regular'
    };
  }

  private copyText(text: string): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      return pasteboard.getSystemPasteboard().setData(data);
    } catch (error) {
      return Promise.reject(error as Error);
    }
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private handleAccountRefreshSignal(): void {
    this.coordinator.refresh(this.buildDataBoundaryInput());
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshTheme();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private refreshTheme(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }
}
