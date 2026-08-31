import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import { DesktopLoginConfirmSheetContent } from './DesktopLoginConfirmSheetContent';
import { AppProxyQuickSheetContent } from './AppProxyQuickSheetContent';
import { BrowserWifiQrResultOverlay } from '../browser/BrowserWifiQrResultOverlay';
import { SettingsCenterPresentationHost } from './SettingsCenterPresentationHost';
import {
  SettingsCenterDestination,
  SettingsCenterState,
  SettingsCenterViewModel
} from '../../../core/settings/SettingsCenterViewModel';
import {
  SettingsCenterPresentationIntent,
  SettingsCenterPresentationSnapshot
} from './SettingsCenterPresentationContract';
import {
  SettingsShellLayoutState
} from '../../../core/settings/SettingsShellLayoutPolicy';
import {
  DEFAULT_SETTINGS_PHONE_SHELL_PRESENTATION_STATE,
  SettingsPresentationShellFamily,
  SettingsShellPresentationCoordinator
} from '../../../core/settings/SettingsShellPresentationCoordinator';
import {
  SettingsAccountCardState
} from '../../../core/settings/SettingsAccountCardViewModel';
import {
  SettingsCenterAccountRefreshCoordinator,
  SettingsCenterAccountRefreshSnapshot
} from '../../../core/settings/SettingsCenterAccountRefreshCoordinator';
import {
  BrowserQrScanCoordinator,
  BrowserQrScanNavigationTarget,
  BrowserQrScanSessionSnapshot,
  BrowserQrScanShell,
  BrowserQrScanSurface,
  DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT
} from '../../../core/browser/BrowserQrScanCoordinator';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  SYNC_SETTINGS_REFRESH_REVISION_KEY,
  SyncSettingsRefreshSignal
} from '../../../core/sync/SyncSettingsRefreshSignal';
import {
  AppProxyQuickSheetCoordinator,
  AppProxyQuickSheetShell,
  AppProxyQuickSheetState
} from '../../../core/settings/AppProxyQuickSheetCoordinator';
import { AppProxySettingsCoordinator } from '../../../core/settings/AppProxySettingsCoordinator';
import { AppProxySettingsViewModel } from '../../../core/settings/AppProxySettingsViewModel';
import {
  sharedAiraSyncConfigStore,
  sharedArkWebAppProxyService,
  sharedBrowserProxyRuntimeRefreshCoordinator,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  DEFAULT_SETTINGS_CENTER_SEARCH_STATE,
  SettingsCenterSearchState,
  SettingsDestinationNavigationOwner,
  SettingsNavigationDispatchResult,
  SettingsNavigationIntent,
  SettingsNavigationSnapshot
} from '../../../core/settings/SettingsDestinationNavigationOwner';
import {
  SettingsDestinationNavigationRouterAdapter
} from '../../router/SettingsDestinationNavigationRouterAdapter';
import {
  BrowserWindowRuntime,
  buildBrowserLaunchPayload
} from '../../runtime/BrowserWindowRuntime';
import {
  resolveBrowserWindowSessionShellPresentationBinding
} from '../../../core/browser/BrowserWindowSessionApplication';
import {
  CustomHomepageSettingsPageBinding
} from '../../../core/customhome/CustomHomepageSettingsPageBinding';
import { BrowserSearchInvocationRuntime } from '../../runtime/BrowserSearchInvocationRuntime';

type SettingsCenterSheetType = 'none' | 'huaweiLogin' | 'desktopLoginConfirm' | 'appProxyQuick';

export class SettingsCenterScreenController {
  private backHandler: (() => boolean) | undefined;
  private pageShowHandler: (() => void) | undefined;

  bind(backHandler: () => boolean, pageShowHandler: () => void): void {
    this.backHandler = backHandler;
    this.pageShowHandler = pageShowHandler;
  }

  unbind(): void {
    this.backHandler = undefined;
    this.pageShowHandler = undefined;
  }

  handleBackPress(): boolean {
    return this.backHandler?.() ?? false;
  }

  notifyPageShow(): void {
    this.pageShowHandler?.();
  }
}

@Component
export struct SettingsCenterScreen {
  controller: SettingsCenterScreenController = new SettingsCenterScreenController();
  @Prop presentationMode: 'page' | 'native_tab' = 'page';
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  @Prop embeddedBoundarySource: string = '';
  @Prop @Watch('handleRequestedDestinationChanged') requestedDestination: SettingsCenterDestination = 'general';
  onOpenAppProxySettings: () => void = () => {};
  onPrimaryDestinationChanged: (destination: SettingsCenterDestination) => void =
    (_destination: SettingsCenterDestination): void => {};
  private customHomepagePageBinding: CustomHomepageSettingsPageBinding =
    new CustomHomepageSettingsPageBinding();
  private viewModel: SettingsCenterViewModel = new SettingsCenterViewModel();
  private settingsPresentationCoordinator: SettingsShellPresentationCoordinator =
    new SettingsShellPresentationCoordinator();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsNavigationRouterAdapter: SettingsDestinationNavigationRouterAdapter =
    new SettingsDestinationNavigationRouterAdapter(this.navigationCoordinator);
  private settingsNavigationOwner: SettingsDestinationNavigationOwner = new SettingsDestinationNavigationOwner(
    this.settingsNavigationRouterAdapter
  );
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appProxySettingsViewModel: AppProxySettingsViewModel = new AppProxySettingsViewModel();
  private appProxySettingsCoordinator: AppProxySettingsCoordinator = new AppProxySettingsCoordinator(
    sharedPreferencesRepository,
    sharedArkWebAppProxyService,
    this.appProxySettingsViewModel,
    (): void => {
      sharedBrowserProxyRuntimeRefreshCoordinator.requestRefresh();
    }
  );
  private appProxyQuickSheetShell: AppProxyQuickSheetShell = {
    publishState: (state: AppProxyQuickSheetState): void => {
      this.appProxyQuickSheetState = state;
    },
    setSurfaceVisible: (visible: boolean): void => {
      if (visible) {
        this.openSettingsSheet('appProxyQuick');
      } else {
        this.closeSettingsSheet();
      }
    },
    showMessage: (message: string): void => {
      this.showToast(message);
    },
    openSettings: (): void => {
      this.openAppProxySettings();
    },
    refreshConsumers: (): void => {
      this.refreshSettingsCenterState();
      this.refreshSearchState();
      this.settingsRefreshRevision += 1;
    }
  };
  private appProxyQuickSheetCoordinator: AppProxyQuickSheetCoordinator =
    new AppProxyQuickSheetCoordinator(this.appProxySettingsCoordinator, this.appProxyQuickSheetShell);
  private accountRefreshCoordinator: SettingsCenterAccountRefreshCoordinator =
    new SettingsCenterAccountRefreshCoordinator({
      membershipFeature: sharedMembershipFeature,
      syncConfigStore: sharedAiraSyncConfigStore,
      accountMutationCoordinator: sharedHuaweiAccountMutationCoordinator,
      onSnapshotChanged: (snapshot: SettingsCenterAccountRefreshSnapshot) => {
        this.applyAccountSnapshot(snapshot, true);
      }
    });
  private qrScanShell: BrowserQrScanShell = {
    publishSnapshot: (snapshot: BrowserQrScanSessionSnapshot): void => {
      this.qrScanSessionSnapshot = snapshot;
    },
    showToast: (message: string): void => {
      this.showToast(message);
    },
    openNavigation: (target: BrowserQrScanNavigationTarget, value: string): void => {
      if (target === 'account_settings') {
        this.openHuaweiAccountLogin();
      } else {
        this.openScannedUrlInBrowser(value);
      }
    },
    setSurfaceVisible: (surface: BrowserQrScanSurface, visible: boolean): void => {
      if (surface !== 'desktop_login_confirm') {
        return;
      }
      if (visible) {
        this.openSettingsSheet('desktopLoginConfirm');
      } else {
        this.closeSettingsSheet();
      }
    }
  };
  private qrScanCoordinator: BrowserQrScanCoordinator =
    new BrowserQrScanCoordinator(sharedAiraSyncConfigStore, this.qrScanShell);
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ) => {
        this.handleHuaweiLoginPanelResult(error, response);
      });
  private themePreferencesListenerKey: string = '';
  private settingsNavigationObserverKey: string = '';
  @StorageLink(SYNC_SETTINGS_REFRESH_REVISION_KEY) @Watch('refreshAccountCardFromSignal')
  private syncSettingsRefreshRevision: number = 0;
  @State private state: SettingsCenterState = this.viewModel.buildState();
  @State private searchQuery: string = '';
  @State private searchState: SettingsCenterSearchState = DEFAULT_SETTINGS_CENTER_SEARCH_STATE;
  @State private settingsNavigationSnapshot: SettingsNavigationSnapshot = this.settingsNavigationOwner.snapshot();
  @State private shellLayoutState: SettingsShellLayoutState =
    DEFAULT_SETTINGS_PHONE_SHELL_PRESENTATION_STATE.layoutState;
  @State private settingsShellFamily: SettingsPresentationShellFamily = 'phone';
  @State private viewportWidth: number = 390;
  @State private accountCard: SettingsAccountCardState =
    this.accountRefreshCoordinator.buildCachedSnapshot('', '').accountCard;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private settingsRefreshRevision: number = 0;
  @State private settingsSheetVisible: boolean = false;
  @State private activeSettingsSheet: SettingsCenterSheetType = 'none';
  @State private qrScanSessionSnapshot: BrowserQrScanSessionSnapshot =
    DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT;
  @State private appProxyQuickSheetState: AppProxyQuickSheetState = this.appProxyQuickSheetCoordinator.getSnapshot();
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.controller.bind(
      (): boolean => this.handleBackPress(),
      (): void => this.handlePageShow()
    );
    BrowserSearchInvocationRuntime.activateSettingsNavigation(BrowserWindowRuntime.getActiveWindowId());
    this.bindSettingsNavigationOwner();
    this.bindThemePreferencesUpdates();
    this.refreshState();
    this.applyRequestedDestination();
  }

  aboutToDisappear(): void {
    this.controller.unbind();
    this.unbindSettingsNavigationOwner();
    this.unbindThemePreferencesUpdates();
    this.accountRefreshCoordinator.cancelDeferredRefresh();
    this.qrScanCoordinator.resetSession();
    this.appProxyQuickSheetCoordinator.handleSurfaceDismissed();
  }

  onPageShow(): void {
    this.handlePageShow();
  }

  private handlePageShow(): void {
    this.refreshState();
    this.customHomepagePageBinding.notifyPageShow();
  }

  private refreshAccountCardFromSignal(): void {
    this.refreshState();
  }

  build() {
    Stack() {
      SettingsCenterPresentationHost({
        customHomepagePageBinding: this.customHomepagePageBinding,
        snapshot: this.buildSettingsPresentationSnapshot(),
        onIntent: (intent: SettingsCenterPresentationIntent) => {
          this.handleSettingsPresentationIntent(intent);
        }
      })
        .width('100%')
        .height('100%')

      if (this.qrScanSessionSnapshot.wifiCredentials !== undefined) {
        BrowserWifiQrResultOverlay({
          credentials: this.qrScanSessionSnapshot.wifiCredentials,
          accentColor: this.theme.accent,
          layoutMode: this.presentationMode === 'native_tab' ? 'large_screen' : 'phone',
          onAction: (action) => {
            this.qrScanCoordinator.handleWifiResultAction(action);
          },
          onClosed: () => {
            this.qrScanCoordinator.handleSurfaceDismissed('wifi_credentials');
          }
        })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.viewportWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
      this.refreshShellLayoutState();
    })
    .bindSheet($$this.settingsSheetVisible, this.buildSettingsSheet(), {
      // Large-screen (native tab) presents settings sheets centered, not as a
      // phone-style bottom sheet.
      preferType: this.presentationMode === 'native_tab' ? SheetType.CENTER : SheetType.BOTTOM,
      height: this.resolveSettingsSheetHeight(),
      dragBar: this.presentationMode !== 'native_tab' && this.activeSettingsSheet !== 'appProxyQuick',
      showClose: this.activeSettingsSheet !== 'appProxyQuick',
      onDisappear: () => {
        this.handleSettingsSheetDisappear();
      }
    })
  }

  private buildSettingsPresentationSnapshot(): SettingsCenterPresentationSnapshot {
    return {
      shellFamily: this.settingsShellFamily,
      showCloseButton: this.presentationMode !== 'native_tab',
      state: this.settingsNavigationOwner.projectDirectoryState(this.state),
      searchState: this.searchState,
      navigationSnapshot: this.settingsNavigationSnapshot,
      boundary: this.buildBoundaryRouteState(),
      theme: {
        pageBackground: this.theme.pageBackground,
        surfaceBackground: this.theme.surfaceBackground,
        headerButtonBackground: this.theme.controlBackground,
        headerIconColor: this.theme.accent,
        pressedBackground: this.theme.pressedBackground,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        dividerColor: this.theme.divider,
        iconForegroundColor: this.theme.settingsIconForeground,
        resolvedThemeMode: this.theme.resolvedMode,
        settingsIconBackgrounds: this.theme.settingsIconBackgrounds
      },
      accountCard: this.accountCard,
      layoutState: this.shellLayoutState,
      settingsRefreshRevision: this.settingsRefreshRevision
    };
  }

  private handleSettingsPresentationIntent(intent: SettingsCenterPresentationIntent): void {
    if (intent.kind === 'close') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.close());
    } else if (intent.kind === 'account_action') {
      this.handleAccountCardAction();
    } else if (intent.kind === 'open_app_proxy_quick') {
      this.appProxyQuickSheetCoordinator.open(this.buildDataBoundaryInput());
    } else if (intent.kind === 'open_app_proxy_settings') {
      this.openAppProxySettings();
    } else if (intent.kind === 'open_embedded_subpage') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.openEmbeddedSubpage(intent.subpageId));
    } else if (intent.kind === 'edit_secure_dns_profile') {
      this.openSecureDnsProfileEdit(intent.profileId);
    } else if (intent.kind === 'open_user_script_gallery_source') {
      this.openBrowserUrlFromSettings(intent.url, 'userscript_install');
    } else if (intent.kind === 'scan_login') {
      this.scanQrCode();
    } else if (intent.kind === 'change_search_query') {
      this.updateSearchQuery(intent.query);
    } else if (intent.kind === 'select_search_target') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.selectSearchTarget(
        intent.targetId,
        this.state,
        this.buildBoundaryRouteState()
      ));
    } else if (intent.kind === 'select_destination') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.selectPrimary(
        intent.destination,
        this.state,
        this.buildBoundaryRouteState()
      ));
    } else if (intent.kind === 'back_detail') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.back());
    } else if (intent.kind === 'open_web_app_detail') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.openWebAppDetail(intent.shortcutId));
    } else if (intent.kind === 'open_web_app_permission') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.openSitePermission(
        intent.host,
        intent.origin,
        intent.permissionKind
      ));
    } else if (intent.kind === 'open_web_app_desktop_site') {
      this.dispatchSettingsNavigation(SettingsNavigationIntent.openDesktopSite(intent.host, intent.origin));
    } else if (intent.kind === 'settings_changed') {
      this.refreshState();
    }
  }

  @Builder
  private buildSettingsSheet() {
    if (this.activeSettingsSheet === 'desktopLoginConfirm') {
      this.buildDesktopLoginConfirmSheet()
    } else if (this.activeSettingsSheet === 'appProxyQuick') {
      this.buildAppProxyQuickSheet()
    } else {
      this.buildHuaweiLoginSheet()
    }
  }

  @Builder
  private buildHuaweiLoginSheet() {
    HuaweiLoginSheetContent({
      controller: this.huaweiLoginButtonController,
      onOpenUserAgreement: () => {
        this.openHuaweiLoginUserAgreement();
      },
      onOpenPrivacyPolicy: () => {
        this.openHuaweiLoginPrivacyPolicy();
      }
    })
  }

  @Builder
  private buildDesktopLoginConfirmSheet() {
    DesktopLoginConfirmSheetContent({
      displayName: this.qrScanSessionSnapshot.desktopLoginDisplayName,
      uid: this.qrScanSessionSnapshot.desktopLoginUid,
      avatarUri: this.qrScanSessionSnapshot.desktopLoginAvatarUri,
      confirming: this.qrScanSessionSnapshot.desktopLoginConfirming,
      onAction: (action) => {
        this.qrScanCoordinator.handleDesktopLoginConfirmAction(action);
      }
    })
  }

  @Builder
  private buildAppProxyQuickSheet() {
    AppProxyQuickSheetContent({
      state: this.appProxyQuickSheetState,
      layoutMode: this.presentationMode === 'native_tab' ? 'large_screen' : 'phone',
      onClose: () => {
        this.appProxyQuickSheetCoordinator.dismiss();
      },
      onToggleGlobalEnabled: (enabled: boolean) => {
        void this.appProxyQuickSheetCoordinator.setGlobalEnabled(enabled);
      },
      onSelectProfile: (profileId: string) => {
        void this.appProxyQuickSheetCoordinator.selectProfile(profileId);
      },
      onOpenSettings: () => {
        this.appProxyQuickSheetCoordinator.openSettings();
      }
    })
  }

  private resolveSettingsSheetHeight(): SheetSize | Length {
    if (this.activeSettingsSheet === 'desktopLoginConfirm') {
      return SheetSize.LARGE;
    }
    if (this.activeSettingsSheet === 'appProxyQuick') {
      return SheetSize.LARGE;
    }
    return SheetSize.FIT_CONTENT;
  }

  private openSettingsSheet(type: SettingsCenterSheetType): void {
    this.activeSettingsSheet = type;
    this.settingsSheetVisible = true;
  }

  private closeSettingsSheet(): void {
    this.settingsSheetVisible = false;
  }

  private handleSettingsSheetDisappear(): void {
    if (this.settingsSheetVisible) {
      return;
    }
    if (this.activeSettingsSheet === 'desktopLoginConfirm' &&
      !this.qrScanSessionSnapshot.desktopLoginConfirming) {
      this.qrScanCoordinator.handleSurfaceDismissed('desktop_login_confirm');
    } else if (this.activeSettingsSheet === 'appProxyQuick') {
      this.appProxyQuickSheetCoordinator.handleSurfaceDismissed();
    }
    this.activeSettingsSheet = 'none';
  }

  private refreshState(): void {
    const boundaryState: BrowserBoundaryRouteState = this.presentationMode === 'native_tab'
      ? {
        dataScope: this.embeddedDataScope,
        privacyMode: this.embeddedPrivacyMode,
        boundarySource: this.embeddedBoundarySource
      }
      : readBrowserBoundaryRouteState({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshSettingsCenterState();
    this.refreshSearchState();
    this.ensureSelectedDestination();
    this.applyAccountSnapshot(
      this.accountRefreshCoordinator.buildCachedSnapshot(this.dataScope, this.privacyMode),
      false
    );
    this.accountRefreshCoordinator.scheduleDeferredRefresh(this.dataScope, this.privacyMode);
    this.refreshThemeState();
    this.refreshShellLayoutState();
    this.settingsRefreshRevision += 1;
  }

  private handleAccountCardAction(): void {
    if (sharedPreferencesRepository.getPreferences().appServiceMode === 'basic') {
      this.showToast('账号与会员需切换到全量模式后使用。');
      return;
    }
    if (this.isHuaweiAccountSignedIn()) {
      this.navigationCoordinator.openHuaweiAccountInfo(this.buildBoundaryRouteState());
      return;
    }
    this.openHuaweiAccountLogin();
  }

  private openAppProxySettings(): void {
    if (this.presentationMode === 'native_tab') {
      this.closeSettingsSheet();
      this.onOpenAppProxySettings();
      return;
    }
    this.navigationCoordinator.openAppProxySettings(this.buildBoundaryRouteState(), () => {
      this.showToast('代理设置暂时无法打开，请稍后重试。');
    });
  }

  private openSecureDnsProfileEdit(profileId: string): void {
    this.navigationCoordinator.openSecureDnsProfileEdit(this.buildBoundaryRouteState(), profileId, () => {
      this.showToast('自定义 DNS 编辑页暂时无法打开，请稍后重试。');
    });
  }

  private scanQrCode(): void {
    void this.qrScanCoordinator.scan(this.getHostContext());
  }

  private openScannedUrlInBrowser(value: string): void {
    this.openBrowserUrlFromSettings(value, 'settings_qr_scan');
  }

  private openBrowserUrlFromSettings(value: string, source: string): void {
    BrowserWindowRuntime.stageLaunchPayload(buildBrowserLaunchPayload({
      uri: value,
      source: source,
      privacyMode: this.privacyMode,
      dataScope: this.dataScope
    }));
    this.dispatchSettingsNavigation(SettingsNavigationIntent.close());
  }

  private refreshSettingsCenterState(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.state = this.viewModel.buildState(
      this.dataScope,
      this.privacyMode,
      preferences.appServiceMode,
      preferences.experiments.appProxyEnabled
    );
  }

  private handleHuaweiLoginPanelResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential
  ): void {
    if (error !== undefined) {
      if (error.code !== 1001502012) {
        this.showToast(error.message.length > 0 ? error.message : '华为账号登录失败');
      }
      return;
    }
    if (response.authorizationCode.trim().length <= 0 && response.openID.trim().length <= 0) {
      this.showToast('华为账号登录未完成');
      return;
    }
    this.closeSettingsSheet();
    this.signInHuaweiAccount();
  }

  private openHuaweiLoginUserAgreement(): void {
    this.closeSettingsSheet();
    this.navigationCoordinator.openLegalWebDocument(
      'user_service_agreement',
      this.buildBoundaryRouteState()
    );
  }

  private openHuaweiLoginPrivacyPolicy(): void {
    this.closeSettingsSheet();
    this.navigationCoordinator.openPrivacyStatement(this.buildBoundaryRouteState());
  }

  private signInHuaweiAccount(): void {
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildDataBoundaryInput())
      .then((result) => {
        if (result.type === 'failed') {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.syncSettingsRefreshSignal.bump();
        this.accountRefreshCoordinator.resetSnapshotSignature();
        this.refreshState();
        this.showToast(result.title);
      })
      .catch((_error: Error) => {
        this.showToast('华为账号登录失败');
      });
  }

  private openHuaweiAccountLogin(): void {
    if (!sharedHuaweiAccountMutationCoordinator.canSignIn(this.buildDataBoundaryInput())) {
      this.showToast('请回到普通会话后登录华为账号。');
      return;
    }
    this.openSettingsSheet('huaweiLogin');
  }

  private isHuaweiAccountSignedIn(): boolean {
    return sharedAiraSyncConfigStore.getSettings().huaweiCloud.uid.trim().length > 0;
  }

  private applyAccountSnapshot(snapshot: SettingsCenterAccountRefreshSnapshot, refreshCenterState: boolean): void {
    this.accountCard = snapshot.accountCard;
    if (refreshCenterState) {
      this.refreshSettingsCenterState();
      this.refreshSearchState();
    }
  }

  private buildBoundaryRouteState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    };
  }

  private buildDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private getHostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private refreshShellLayoutState(): void {
    const sessionBinding = BrowserWindowRuntime.connectShellPresentation(
      this.getUIContext().getSharedLocalStorage()
    );
    const sessionSnapshot = resolveBrowserWindowSessionShellPresentationBinding(sessionBinding)?.snapshot();
    const presentation = this.settingsPresentationCoordinator.resolve({
      viewportWidth: this.viewportWidth,
      browserShellFamily: this.presentationMode === 'native_tab'
        ? 'large_screen'
        : sessionSnapshot?.shellFamily
    });
    this.settingsShellFamily = presentation.family;
    this.shellLayoutState = presentation.layoutState;
    this.dispatchSettingsNavigation(SettingsNavigationIntent.setShell(presentation.navigationMode), false);
    this.refreshSearchState();
  }

  private updateSearchQuery(query: string): void {
    this.searchQuery = query;
    this.refreshSearchState();
  }

  private refreshSearchState(): void {
    this.searchState = this.settingsNavigationOwner.search(this.state, this.searchQuery);
  }

  private ensureSelectedDestination(): void {
    const embeddedDestination = this.settingsNavigationOwner.resolveAvailablePrimary(
      this.state,
      this.settingsNavigationSnapshot.selectedPrimaryDestination
    );
    if (embeddedDestination === this.settingsNavigationSnapshot.selectedPrimaryDestination) {
      return;
    }
    this.dispatchSettingsNavigation(SettingsNavigationIntent.selectPrimary(
      embeddedDestination,
      this.state,
      this.buildBoundaryRouteState()
    ), false);
  }

  private handleRequestedDestinationChanged(): void {
    this.applyRequestedDestination();
  }

  private applyRequestedDestination(): void {
    const destination = this.settingsNavigationOwner.resolveAvailablePrimary(
      this.state,
      this.requestedDestination
    );
    if (destination === this.settingsNavigationSnapshot.selectedPrimaryDestination) {
      return;
    }
    this.dispatchSettingsNavigation(SettingsNavigationIntent.selectPrimary(
      destination,
      this.state,
      this.buildBoundaryRouteState()
    ), false);
  }

  onBackPress(): boolean {
    return this.handleBackPress();
  }

  private handleBackPress(): boolean {
    if (this.customHomepagePageBinding.dispatchBack()) {
      return true;
    }
    this.dispatchSettingsNavigation(SettingsNavigationIntent.back());
    return true;
  }

  private bindSettingsNavigationOwner(): void {
    if (this.settingsNavigationObserverKey.length > 0) {
      return;
    }
    this.settingsNavigationObserverKey = this.settingsNavigationOwner.observe(
      (snapshot: SettingsNavigationSnapshot): void => {
        const previousDestination = this.settingsNavigationSnapshot.selectedPrimaryDestination;
        this.settingsNavigationSnapshot = snapshot;
        if (this.presentationMode === 'native_tab' &&
          snapshot.selectedPrimaryDestination !== previousDestination) {
          this.onPrimaryDestinationChanged(snapshot.selectedPrimaryDestination);
        }
      }
    );
    this.settingsNavigationSnapshot = this.settingsNavigationOwner.snapshot();
  }

  private unbindSettingsNavigationOwner(): void {
    if (this.settingsNavigationObserverKey.length <= 0) {
      return;
    }
    this.settingsNavigationOwner.unobserve(this.settingsNavigationObserverKey);
    this.settingsNavigationObserverKey = '';
  }

  private dispatchSettingsNavigation(intent: SettingsNavigationIntent, reportFailure: boolean = true): void {
    this.settingsNavigationOwner.dispatch(intent)
      .then((result: SettingsNavigationDispatchResult) => {
        if (reportFailure && result.failureReason.length > 0) {
          const target = result.targetTitle.length > 0 ? `“${result.targetTitle}”` : '设置页面';
          this.showToast(`无法打开${target}，请重试`);
        }
      })
      .catch((_error: Error) => {
        if (reportFailure) {
          this.showToast('设置页面导航失败，请重试');
        }
      });
  }

  private parseAreaDimension(value: Length): number {
    const rawValue = `${value}`.replace('vp', '').replace('px', '');
    const parsedValue = Number(rawValue);
    return Number.isFinite(parsedValue) ? parsedValue : 0;
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
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
}
