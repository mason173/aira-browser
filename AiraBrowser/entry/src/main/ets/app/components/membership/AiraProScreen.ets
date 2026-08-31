import { common } from '@kit.AbilityKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import {
  AiraProOverviewViewModel,
  AiraProOverviewViewState
} from '../../../core/membership/AiraProOverviewViewModel';
import {
  AiraProEntryConfirmationViewModel,
  AiraProEntryConfirmationViewState
} from '../../../core/membership/AiraProEntryConfirmationViewModel';
import { AiraProOverviewScreen } from './AiraProOverviewScreen';
import { AiraProEntryConfirmationSheet } from './AiraProEntryConfirmationSheet';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../../common/utils/RouteParamUtils';
import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { HuaweiLoginSheetContent } from '../account/HuaweiLoginSheetContent';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import { SyncDesktopBookmarkGuideContent } from '../sync/SyncDesktopBookmarkGuideContent';
import {
  SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE
} from '../../../services/sync/SyncDesktopBookmarkGuideMarkdownService';
import { AiraLegalWebDocumentContent } from '../legal/AiraLegalWebDocumentContent';
import {
  AiraLegalDocumentId,
  AiraLegalDocumentLink,
  resolveAiraLegalDocumentLink
} from '../../../services/legal/AiraLegalDocuments';
import {
  AiraProPurchaseCoordinator,
  AiraProPurchaseFlowHostAdapter
} from '../../../core/membership/AiraProPurchaseCoordinator';
import { SyncSettingsRefreshSignal } from '../../../core/sync/SyncSettingsRefreshSignal';
import {
  sharedAiraSyncConfigStore,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository,
  sharedSettingsNoticeDismissalRepository
} from '../../bootstrap/BrowserAppRuntime';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS } from '../../../services/membership/MembershipRefreshPolicyService';
import { SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION } from '../../../data/preferences/SettingsNoticeDismissalRepository';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';

type AiraProSheetKind = 'none' | 'entryConfirmation' | 'login' | 'desktopGuide' | 'legalDocument';
export type AiraProPresentationMode = 'page' | 'workspace';
export type AiraProPageLayoutMode = 'phone' | 'large_screen';

const AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP: number = 760;
const AIRA_PRO_DESKTOP_DIALOG_MIN_WIDTH_VP: number = 520;
const AIRA_PRO_DESKTOP_DIALOG_MAX_WIDTH_VP: number = 720;
const AIRA_PRO_DESKTOP_DIALOG_MIN_HEIGHT_VP: number = 420;
const AIRA_PRO_DESKTOP_DIALOG_MAX_HEIGHT_VP: number = 720;

@Component
export struct AiraProScreen {
  @Prop presentationMode: AiraProPresentationMode = 'page';
  @Prop pageLayoutMode: AiraProPageLayoutMode = 'phone';
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  @Prop embeddedBoundarySource: string = '';
  onRequestClose: () => void = () => {};
  private viewModel: AiraProOverviewViewModel = new AiraProOverviewViewModel();
  private entryConfirmationViewModel: AiraProEntryConfirmationViewModel = new AiraProEntryConfirmationViewModel();
  private purchaseCoordinator: AiraProPurchaseCoordinator = new AiraProPurchaseCoordinator(sharedMembershipFeature);
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private purchaseFlowHost: AiraProPurchaseFlowHostAdapter = new AiraProPurchaseFlowHostAdapter(
    () => {
      this.applyAiraProState();
      this.syncSettingsRefreshSignal.bump();
    },
    () => {
      this.ensureHuaweiAccountSignedIn();
    },
    (message: string) => {
      this.showToast(message);
    }
  );
  private entryConfirmationLeaving: boolean = false;
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ) => {
        this.handleHuaweiLoginPanelResult(error, response);
      });
  private contentScroller: Scroller = new Scroller();
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private state: AiraProOverviewViewState = this.viewModel.buildState(
    sharedMembershipFeature.getState(),
    this.dataScope,
    this.privacyMode
  );
  @State private entryConfirmationState: AiraProEntryConfirmationViewState =
    this.entryConfirmationViewModel.buildState();
  @State private entryConfirmationAccepted: boolean =
    sharedSettingsNoticeDismissalRepository.hasDismissed(SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION);
  @State private entryConfirmationFreeBrowsingAccepted: boolean = false;
  @State private entryConfirmationOptionalSupportAccepted: boolean = false;
  @State private entryConfirmationDeveloperChargeAccepted: boolean = false;
  @State private entryConfirmationSubmitting: boolean = false;
  @State private activeSheetVisible: boolean = false;
  @State private activeSheetMounted: boolean = false;
  @State private activeSheetKind: AiraProSheetKind = 'none';
  @State private legalDocument: AiraLegalDocumentLink =
    resolveAiraLegalDocumentLink('user_service_agreement');
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('handleStoredThemeChanged')
  private storedResolvedThemeMode: string = 'light';

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
    if (this.isDesktopPresentation()) {
      this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
    }
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  onPageShow(): void {
    this.refreshState();
    this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
  }

  build() {
    if (this.isDesktopPresentation()) {
      this.buildDesktopSurface()
    } else {
      this.buildPageSurface()
    }
  }

  @Builder
  private buildPageSurface() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.controlBackground,
        primaryTextColor: this.theme.textPrimary,
        dividerColor: this.theme.divider,
        scrollers: [this.contentScroller],
        contentKind: 'standard',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        this.buildAiraProContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.activeSheetVisible, this.buildActiveSheet(), {
      preferType: this.pageLayoutMode === 'large_screen' ? SheetType.CENTER : SheetType.BOTTOM,
      height: this.resolveActiveSheetHeight(),
      dragBar: this.pageLayoutMode !== 'large_screen' && this.activeSheetKind !== 'entryConfirmation',
      showClose: this.activeSheetKind === 'login',
      backgroundColor: this.resolveActiveSheetBackgroundColor(),
      onDisappear: () => {
        this.handleActiveSheetDisappear();
      }
    })
  }

  @Builder
  private buildDesktopSurface() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Column() {
          this.buildAiraProContent()
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: this.resolveDesktopContentMaxWidth() })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      if (this.activeSheetMounted) {
        BrowserAdaptiveModalOverlay({
          visible: this.activeSheetVisible,
          layoutMode: 'large_screen',
          title: this.resolveDesktopDialogTitle(),
          showDesktopHeader: this.shouldShowDesktopDialogHeader(),
          desktopWidth: '76%',
          desktopHeight: this.resolveDesktopDialogHeight(),
          desktopMinWidth: AIRA_PRO_DESKTOP_DIALOG_MIN_WIDTH_VP,
          desktopMaxWidth: AIRA_PRO_DESKTOP_DIALOG_MAX_WIDTH_VP,
          desktopMinHeight: AIRA_PRO_DESKTOP_DIALOG_MIN_HEIGHT_VP,
          desktopMaxHeight: AIRA_PRO_DESKTOP_DIALOG_MAX_HEIGHT_VP,
          onDismiss: () => {
            this.handleActiveSheetDisappear();
          }
        }) {
          this.buildActiveSheet()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
  }

  @Builder
  private buildAiraProContent() {
    if (this.entryConfirmationAccepted) {
      AiraProOverviewScreen({
        state: this.state,
        surfaceBackground: this.theme.surfaceBackground,
        controlBackground: this.theme.controlBackground,
        accentColor: this.theme.accent,
        onAccentColor: this.theme.onAccent,
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        dividerColor: this.theme.divider,
        settingsIconBackgrounds: this.theme.settingsIconBackgrounds,
        scroller: this.contentScroller,
        onSubscribe: (planId: string) => {
          this.openProPurchase(planId);
        },
        onOpenMembershipTerms: () => {
          this.openMembershipTerms();
        },
        onOpenAutoRenewalNotice: () => {
          this.openAutoRenewalNotice();
        },
        onManageSubscription: () => {
          this.confirmLifetimeUpgradeSubscriptionCancellation();
        },
        onRestorePurchase: (planId: string) => {
          this.restorePurchase(planId);
        },
        onOpenDesktopGuide: () => {
          this.openDesktopGuide();
        }
      })
    } else {
      Column()
        .width('100%')
        .height('100%')
    }
  }

  private resolveDesktopContentMaxWidth(): Length {
    return this.presentationMode === 'workspace' ? '100%' : AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP;
  }

  @Builder
  private buildActiveSheet() {
    if (this.activeSheetKind === 'entryConfirmation') {
      this.buildEntryConfirmationSheet()
    } else if (this.activeSheetKind === 'desktopGuide') {
      SyncDesktopBookmarkGuideContent()
        .width('100%')
        .height('100%')
    } else if (this.activeSheetKind === 'legalDocument') {
      AiraLegalWebDocumentContent({
        documentUrl: this.legalDocument.url,
        styleId: 'aira-pro-legal-document-style'
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildHuaweiLoginSheet()
    }
  }

  @Builder
  private buildEntryConfirmationSheet() {
    AiraProEntryConfirmationSheet({
      state: this.entryConfirmationState,
      confirming: this.entryConfirmationSubmitting,
      freeBrowsingAccepted: $entryConfirmationFreeBrowsingAccepted,
      optionalSupportAccepted: $entryConfirmationOptionalSupportAccepted,
      developerChargeAccepted: $entryConfirmationDeveloperChargeAccepted,
      onConfirm: () => {
        this.confirmEntryConfirmation();
      },
      onCancel: () => {
        this.cancelEntryConfirmation();
      }
    })
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

  private refreshState(): void {
    if (!this.appServiceModeGateService.canUseOptionalService()) {
      if (this.isDesktopPresentation()) {
        this.onRequestClose();
      } else {
        this.navigationCoordinator.back();
      }
      return;
    }
    const boundaryState = this.isDesktopPresentation()
      ? readBrowserBoundaryRouteState({
        dataScope: this.embeddedDataScope,
        privacyMode: this.embeddedPrivacyMode,
        boundarySource: this.embeddedBoundarySource
      })
      : readBrowserBoundaryRouteState({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshThemeState();
    this.applyAiraProState();
    this.refreshEntryConfirmationPresentation();
    sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), {
      minFreshMs: MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS
    })
      .then(() => {
        this.applyAiraProState();
      })
      .catch((_error: Error) => {
        this.applyAiraProState();
      });
  }

  private applyAiraProState(): void {
    this.state = this.viewModel.buildState(
      sharedMembershipFeature.getState(),
      this.dataScope,
      this.privacyMode
    );
  }

  private refreshEntryConfirmationPresentation(): void {
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      this.entryConfirmationAccepted = true;
      return;
    }
    sharedSettingsNoticeDismissalRepository.initialize()
      .then(() => {
        this.applyEntryConfirmationPresentation();
      })
      .catch((_error: Error) => {
        this.applyEntryConfirmationPresentation();
      });
  }

  private applyEntryConfirmationPresentation(): void {
    if (this.entryConfirmationLeaving) {
      return;
    }
    if (sharedSettingsNoticeDismissalRepository.hasDismissed(SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION)) {
      this.entryConfirmationAccepted = true;
      return;
    }
    this.entryConfirmationAccepted = false;
    if (this.activeSheetKind !== 'entryConfirmation') {
      this.openActiveSheet('entryConfirmation');
    }
  }

  private confirmEntryConfirmation(): void {
    if (!this.canConfirmEntryConfirmation() || this.entryConfirmationSubmitting) {
      this.showToast('请先勾选全部确认项');
      return;
    }
    this.entryConfirmationSubmitting = true;
    sharedSettingsNoticeDismissalRepository.dismiss(SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION)
      .then(() => {
        this.entryConfirmationAccepted = true;
        this.closeActiveSheet();
      })
      .catch((_error: Error) => {
        this.showToast('确认状态保存失败，请稍后重试');
      })
      .finally(() => {
        this.entryConfirmationSubmitting = false;
      });
  }

  private cancelEntryConfirmation(): void {
    this.entryConfirmationLeaving = true;
    sharedSettingsNoticeDismissalRepository.dismiss(SETTINGS_NOTICE_AIRA_PRO_ENTRY_CONFIRMATION)
      .finally(() => {
        if (this.isDesktopPresentation()) {
          this.onRequestClose();
        } else {
          this.navigationCoordinator.back();
        }
      });
  }

  private canConfirmEntryConfirmation(): boolean {
    return this.entryConfirmationFreeBrowsingAccepted &&
      this.entryConfirmationOptionalSupportAccepted &&
      this.entryConfirmationDeveloperChargeAccepted;
  }

  private openProPurchase(planId: string = 'monthly'): void {
    this.purchaseCoordinator.startPurchaseFlow(
      getContext(this) as common.UIAbilityContext,
      planId,
      this.getHuaweiUid(),
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  private confirmLifetimeUpgradeSubscriptionCancellation(): void {
    const prompt = this.state.lifetimeUpgradePrompt;
    showCenteredAlertDialog({
      title: prompt.title,
      message: prompt.message,
      autoCancel: true,
      primaryButton: {
        value: prompt.cancelLabel,
        action: () => {
        }
      },
      secondaryButton: {
        value: prompt.manageLabel,
        action: () => {
          this.purchaseCoordinator.openLifetimeUpgradeSubscriptionManagement(
            getContext(this) as common.UIAbilityContext,
            this.purchaseFlowHost,
            this.buildAiraProDataBoundaryInput()
          );
        }
      }
    });
  }

  private restorePurchase(planId: string = 'monthly'): void {
    this.purchaseCoordinator.restorePurchaseFlow(
      getContext(this) as common.UIAbilityContext,
      this.getHuaweiUid(),
      planId,
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  private openDesktopGuide(): void {
    if (this.isDesktopPresentation()) {
      this.openActiveSheet('desktopGuide');
      return;
    }
    this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.buildAiraProBoundaryState());
  }

  private openMembershipTerms(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('pro_membership_service_agreement');
      return;
    }
    this.navigationCoordinator.openLegalWebDocument(
      'pro_membership_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openAutoRenewalNotice(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('pro_auto_renewal_service_agreement');
      return;
    }
    this.navigationCoordinator.openLegalWebDocument(
      'pro_auto_renewal_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openHuaweiLoginUserAgreement(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('user_service_agreement');
      return;
    }
    this.closeActiveSheet();
    this.navigationCoordinator.openLegalWebDocument(
      'user_service_agreement',
      this.buildAiraProBoundaryState()
    );
  }

  private openHuaweiLoginPrivacyPolicy(): void {
    if (this.isDesktopPresentation()) {
      this.openDesktopLegalDocument('privacy_statement');
      return;
    }
    this.closeActiveSheet();
    this.navigationCoordinator.openPrivacyStatement(this.buildAiraProBoundaryState());
  }

  private openDesktopLegalDocument(documentId: AiraLegalDocumentId): void {
    this.legalDocument = resolveAiraLegalDocumentLink(documentId);
    this.openActiveSheet('legalDocument');
  }

  private buildAiraProBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: 'aira_pro'
    };
  }

  private buildAiraProDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private isDesktopPresentation(): boolean {
    return this.presentationMode === 'workspace';
  }

  private getHuaweiUid(): string {
    return sharedAiraSyncConfigStore.getSettings().huaweiCloud.uid.trim();
  }

  private ensureHuaweiAccountSignedIn(): boolean {
    if (this.getHuaweiUid().length > 0) {
      return true;
    }
    if (!sharedHuaweiAccountMutationCoordinator.canSignIn(this.buildAiraProDataBoundaryInput())) {
      this.showToast('请回到普通会话后登录华为账号。');
      return false;
    }
    this.showToast('请先使用华为账号登录后再开通 Aira Pro 权益。');
    this.openActiveSheet('login');
    return false;
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
    this.closeActiveSheet();
    this.signInHuaweiAccount();
  }

  private openActiveSheet(kind: AiraProSheetKind): void {
    this.activeSheetKind = kind;
    this.activeSheetMounted = true;
    this.activeSheetVisible = true;
  }

  private closeActiveSheet(): void {
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    this.activeSheetKind = 'none';
  }

  private handleActiveSheetDisappear(): void {
    const dismissedKind = this.activeSheetKind;
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    if (dismissedKind === 'entryConfirmation' && !this.entryConfirmationAccepted && !this.entryConfirmationLeaving) {
      this.activeSheetKind = 'none';
      this.cancelEntryConfirmation();
      return;
    }
    this.activeSheetKind = 'none';
  }

  private resolveActiveSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT;
  }

  private resolveActiveSheetBackgroundColor(): ResourceColor {
    return this.activeSheetKind === 'entryConfirmation' ?
      this.storedPageBackgroundColor :
      this.storedFloatingSurfaceColor;
  }

  private resolveDesktopDialogTitle(): string {
    if (this.activeSheetKind === 'login') {
      return '登录华为账号';
    }
    if (this.activeSheetKind === 'desktopGuide') {
      return SYNC_DESKTOP_BOOKMARK_GUIDE_TITLE;
    }
    if (this.activeSheetKind === 'legalDocument') {
      return this.legalDocument.title;
    }
    return '进入 Aira Pro';
  }

  private shouldShowDesktopDialogHeader(): boolean {
    return this.activeSheetKind === 'login' ||
      this.activeSheetKind === 'desktopGuide' ||
      this.activeSheetKind === 'legalDocument';
  }

  private resolveDesktopDialogHeight(): Length {
    if (this.activeSheetKind === 'desktopGuide' ||
      this.activeSheetKind === 'legalDocument') {
      return '82%';
    }
    if (this.activeSheetKind === 'entryConfirmation') {
      return 620;
    }
    return 500;
  }

  private signInHuaweiAccount(): void {
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildAiraProDataBoundaryInput())
      .then((result) => {
        if (result.type === 'failed') {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.syncSettingsRefreshSignal.bump();
        this.refreshState();
        this.showToast(result.title);
      })
      .catch((_error: Error) => {
        this.showToast('华为账号登录失败');
      });
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private handleStoredThemeChanged(): void {
    this.refreshThemeState();
    this.applyAiraProState();
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

}
