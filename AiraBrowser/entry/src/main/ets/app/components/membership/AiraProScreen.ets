import { ComponentActive, ComponentInactive } from '@kit.ArkUI';
import { JuMembershipOffer, JuSettingItem } from 'design';
import { KitappMembershipPage, KITAPP_CONTACT_EMAIL } from 'kitapp-membership';
import { createAiraProMembershipOffer, createAiraProMembershipActions } from '../../../core/membership/AiraProMembershipCatalog';
import { AIRA_SUITE_LIFETIME_PLAN_ID } from '../../../services/membership/HuaweiIapProductCatalog';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { loginComponentManager } from '@kit.AccountKit';
import {
  AiraProOverviewPlanState,
  AiraProOverviewViewModel,
  AiraProOverviewViewState
} from '../../../core/membership/AiraProOverviewViewModel';
import { AiraProComplimentaryClaimDialog } from './AiraProComplimentaryClaimDialog';
import { AiraProMembershipRedeemDialog } from './AiraProMembershipRedeemDialog';
import { AiraProMembershipRedeemResultDialog } from './AiraProMembershipRedeemResultDialog';
import {
  AiraProMembershipRedeemGrantKind,
  AiraProMembershipRedeemResultState,
  isValidMembershipRedeemCode,
  resolveAiraProMembershipRedeemResult
} from '../../../core/membership/AiraProMembershipRedeemResult';
import { AiraProOverviewScreen } from './AiraProOverviewScreen';
import { AiraDonateProIntroSheet } from './AiraDonateProIntroSheet';
import { AIRA_COMMUNITY_REPOSITORY_URL } from '../../../common/constants/AiraCommunityProjectLinks';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../../common/config/AiraDistributionCapabilityOwner';
import {
  resolveCenteredDialogControllerWidth,
  resolveCenteredDialogSurfaceColor,
  CENTERED_DIALOG_CORNER_RADIUS_VP
} from '../common/CenteredDialogSurface';
import { HuaweiPaymentLaunchDialog } from './HuaweiPaymentLaunchDialog';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import {
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
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
import { SyncDesktopBookmarkGuideContent } from '../sync/SyncDesktopBookmarkGuideContent';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
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
import { HuaweiIapProductView } from '../../../services/membership/HuaweiIapPurchaseService';
import {
  readCachedAiraProLifetimeStorePrice,
  rememberAiraProLifetimeStorePrice
} from '../../../services/membership/AiraProStorePricePolicy';
import { SyncSettingsRefreshSignal } from '../../../core/sync/SyncSettingsRefreshSignal';
import {
  sharedAiraSyncConfigStore,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  AiraComplimentaryClaimResult,
  AiraMembershipRedeemResult
} from '../../../features/membership/MembershipFeature';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS } from '../../../services/membership/MembershipRefreshPolicyService';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';

type AiraProSheetKind = 'none' | 'login' | 'legalDocument' | 'selfHostingGuide' | 'donateIntro';

/** Temporary while the intro sheet is still being tuned. Turn off before release. */
export type AiraProPresentationMode = 'page' | 'workspace';
export type AiraProPageLayoutMode = 'phone' | 'large_screen';

const AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP: number = 760;

@Component
export struct AiraProScreen {
  @Prop presentationMode: AiraProPresentationMode = 'page';
  @Prop pageLayoutMode: AiraProPageLayoutMode = 'phone';
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  @Prop embeddedBoundarySource: string = '';
  onRequestClose: () => void = () => {};
  private viewModel: AiraProOverviewViewModel = new AiraProOverviewViewModel();
  private purchaseCoordinator: AiraProPurchaseCoordinator = new AiraProPurchaseCoordinator(sharedMembershipFeature);
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal();
  private purchaseFlowHost: AiraProPurchaseFlowHostAdapter = new AiraProPurchaseFlowHostAdapter(
    () => {
      if (this.membershipMounted) {
        this.applyAiraProState();
        this.syncSettingsRefreshSignal.bump();
      }
    },
    () => {
      if (this.membershipMounted && this.membershipActive) { this.ensureHuaweiAccountSignedIn(); }
    },
    (message: ResourceStr) => {
      if (this.membershipMounted && this.membershipActive) { this.showToast(message); }
    },
    (visible: boolean): void => {
      if (this.membershipMounted) { this.setHuaweiPaymentLaunchVisible(visible); }
    }
  );
  private huaweiLoginButtonController: loginComponentManager.LoginWithHuaweiIDButtonController =
    new loginComponentManager.LoginWithHuaweiIDButtonController()
      .onClickLoginWithHuaweiIDButton((
        error: BusinessError | undefined,
        response: loginComponentManager.HuaweiIDCredential
      ) => {
        this.handleHuaweiLoginPanelResult(error, response);
      });
  private contentScroller: Scroller = new Scroller();
  private membershipMounted: boolean = false;
  @State private membershipActive: boolean = true;
  @State private membershipPaymentBusy: boolean = false;
  @State private suiteOwned: boolean = false;
  @State private membershipActions: JuSettingItem[] = [];
  /** Set when this visit dismisses the intro, so a late membership refresh cannot reopen it. */
  private donateIntroDismissedThisEntry: boolean = false;
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  private lifetimeStorePriceText: string = readCachedAiraProLifetimeStorePrice();
  private lifetimeStorePriceRequest: number = 0;
  @State private state: AiraProOverviewViewState = this.viewModel.buildState(
    sharedMembershipFeature.getState(),
    this.dataScope,
    this.privacyMode,
    this.lifetimeStorePriceText
  );
  @State private membershipOffer: JuMembershipOffer = createAiraProMembershipOffer(this.state);
  private complimentaryClaimInFlight: boolean = false;
  private membershipRedeemInFlight: boolean = false;
  private complimentaryClaimDialogController: CustomDialogController = new CustomDialogController({
    builder: AiraProComplimentaryClaimDialog({
      state: $state,
      onClaim: (): void => {
        this.claimComplimentaryMembership();
      }
    }),
    customStyle: true,
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('s'),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  @State private membershipRedeemCode: string = '';
  @State private membershipRedeemResult: AiraProMembershipRedeemResultState =
    resolveAiraProMembershipRedeemResult('month');
  private membershipRedeemDialogController: CustomDialogController = new CustomDialogController({
    builder: AiraProMembershipRedeemDialog({
      codeDraft: $membershipRedeemCode,
      onRedeem: (code: string): void => {
        this.submitMembershipRedeemCode(code);
      }
    }),
    customStyle: true,
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('s'),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });
  private membershipRedeemResultDialogController: CustomDialogController = new CustomDialogController({
    builder: AiraProMembershipRedeemResultDialog({
      result: $membershipRedeemResult
    }),
    customStyle: true,
    backgroundBlurStyle: BlurStyle.NONE,
    autoCancel: true,
    alignment: DialogAlignment.Center,
    openAnimation: { duration: 0 },
    closeAnimation: { duration: 160 }
  });
  private huaweiPaymentLaunchVisible: boolean = false;
  private huaweiPaymentLaunchDialogController: CustomDialogController = new CustomDialogController({
    builder: HuaweiPaymentLaunchDialog(),
    autoCancel: false,
    isModal: true,
    alignment: DialogAlignment.Center,
    customStyle: false,
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: 280,
    onWillDismiss: (_dismissDialogAction: DismissDialogAction): void => {
    }
  });
  @State private activeSheetVisible: boolean = false;
  @State private activeSheetMounted: boolean = false;
  @State private activeSheetKind: AiraProSheetKind = 'none';
  @State private legalDocument: AiraLegalDocumentLink =
    resolveAiraLegalDocumentLink('user_service_agreement');
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('handleStoredThemeChanged')
  private storedResolvedThemeMode: string = 'light';

  aboutToAppear(): void {
    this.membershipMounted = true;
    this.bindThemePreferencesUpdates();
    this.donateIntroDismissedThisEntry = false;
    this.refreshState();
    this.presentDonateIntro();
    this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
  }

  aboutToDisappear(): void {
    this.membershipMounted = false;
    this.purchaseCoordinator.cancelPurchaseConsent();
    this.lifetimeStorePriceRequest += 1;
    this.unbindThemePreferencesUpdates();
    try {
      this.complimentaryClaimDialogController.close();
    } catch (_error) {
    }
    try {
      this.membershipRedeemDialogController.close();
    } catch (_error) {
    }
    try {
      this.membershipRedeemResultDialogController.close();
    } catch (_error) {
    }
    this.setHuaweiPaymentLaunchVisible(false);
  }

  @ComponentActive
  private handleMembershipActive(): void {
    this.membershipActive = true;
    this.donateIntroDismissedThisEntry = false;
    this.refreshState();
    this.presentDonateIntro();
    this.purchaseCoordinator.handlePageShow(this.purchaseFlowHost, this.buildAiraProDataBoundaryInput());
  }

  @ComponentInactive
  private handleMembershipInactive(): void {
    this.purchaseCoordinator.cancelPurchaseConsent();
    this.membershipActive = false;
    this.lifetimeStorePriceRequest += 1;
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
      if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
        SettingsHdsScaffold({
          showTitleBar: false,
          useTopSafeInset: true,
          contentKind: 'unframed',
          pageBackground: this.theme.pageBackground
        }) {
          this.buildSharedMembership()
        }
      } else {
        SettingsHdsScaffold({
          title: this.state.title,
          backIconKind: 'close',
          pageBackground: this.theme.pageBackground,
          headerButtonBackground: this.theme.controlBackground,
          primaryTextColor: this.theme.textPrimary,
          dividerColor: this.theme.divider,
          menuActionText: this.resolveRestorePurchaseActionLabel(),
          scrollers: [this.contentScroller],
          contentKind: 'standard',
          onBack: () => {
            this.navigationCoordinator.back();
          },
          onMenuAction: () => {
            this.restorePurchase();
          }
        }) {
          this.buildAiraProContent()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.activeSheetVisible, this.buildActiveSheet(), applyDesktopDialogSheetChrome({
      preferType: this.pageLayoutMode === 'large_screen' ? SheetType.CENTER : SheetType.BOTTOM,
      height: this.activeSheetKind === 'donateIntro' ? SheetSize.LARGE : this.resolveActiveSheetHeight(),
      dragBar: this.pageLayoutMode !== 'large_screen',
      showClose: this.activeSheetKind === 'login',
      onWillDismiss: (action: DismissSheetAction): void => {
        action.dismiss();
      },
      backgroundColor: this.resolveActiveSheetBackgroundColor(),
      onDisappear: () => {
        this.handleActiveSheetDisappear();
      }
    }, 'l', this.pageLayoutMode === 'large_screen'))
  }

  @Builder
  private buildDesktopSurface() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Column() {
          if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isOfficial()) {
            this.buildSharedMembership()
          } else {
            this.buildAiraProContent()
          }
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
          tier: 'l',
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
  private buildSharedMembership() {
    KitappMembershipPage({
      app: this.membershipOffer,
      asDestination: true,
      appActions: this.membershipActions,
      contactEmail: KITAPP_CONTACT_EMAIL,
      active: this.membershipActive && !this.activeSheetVisible,
      paymentBusy: this.membershipPaymentBusy,
      suitePurchaseEnabled: true,
      suiteOwned: this.suiteOwned,
      onBack: (): void => {
        if (this.isDesktopPresentation()) { this.onRequestClose(); }
        else { this.navigationCoordinator.back(); }
      },
      onPurchase: (): void => { this.openProPurchase('one_time'); },
      onOpenSuite: (): void => { this.openProPurchase(AIRA_SUITE_LIFETIME_PLAN_ID); },
      onRestore: (suite: boolean): void => {
        if (suite) { this.restorePurchaseForPlan(AIRA_SUITE_LIFETIME_PLAN_ID); }
        else { this.restorePurchase(); }
      },
      onAppAction: (key: string): void => { this.handleSharedMembershipAction(key); },
      onUserAgreement: (): void => { this.openSharedLegalDocument('user_service_agreement'); },
      onPrivacy: (): void => { this.openSharedLegalDocument('privacy_statement'); }
    })
  }

  private handleSharedMembershipAction(key: string): void {
    if (!this.membershipMounted || !this.membershipActive || this.membershipPaymentBusy || !this.state.proActionsEnabled) { return; }
    if (key.startsWith('plan:')) {
      const plan = this.state.plans.find((item: AiraProOverviewPlanState): boolean => 'plan:' + item.id === key);
      if (plan !== undefined && plan.action !== 'unavailable') { this.openProPurchase(plan.id); }
    } else if (key === 'manage_subscription' && this.state.showManageSubscription) {
      this.openSubscriptionManagement();
    } else if (key === 'redeem') { this.openMembershipRedeem(); }
    else if (key === 'claim') { this.openComplimentaryClaim(); }
    else if (key === 'self_hosting') { this.openSelfHostingGuide(); }
    else if (key === 'membership_terms') { this.openMembershipTerms(); }
    else if (key === 'auto_renewal_terms') { this.openAutoRenewalNotice(); }
  }

  private openSharedLegalDocument(documentId: AiraLegalDocumentId): void {
    if (this.isDesktopPresentation()) { this.openDesktopLegalDocument(documentId); }
    else { this.navigationCoordinator.openLegalWebDocument(documentId, this.buildAiraProBoundaryState()); }
  }


  @Builder
  private buildAiraProContent() {
    AiraProOverviewScreen({
      state: this.state,
      surfaceBackground: this.theme.surfaceBackground,
      controlBackground: this.theme.controlBackground,
      accentColor: this.theme.accent,
      onAccentColor: this.theme.onAccent,
      primaryTextColor: this.theme.textPrimary,
      secondaryTextColor: this.theme.textSecondary,
      dividerColor: this.theme.divider,
      settingsIconForeground: this.theme.settingsIconForeground,
      settingsIconBackgrounds: this.theme.settingsIconBackgrounds,
      syncProviderIconBackgrounds: this.theme.syncProviderIconBackgrounds,
      logoDark: this.theme.resolvedMode === 'dark',
      scroller: this.contentScroller,
      onSubscribe: (planId: string) => {
        this.openProPurchase(planId);
      },
      onOpenMembershipRedeem: () => {
        this.openMembershipRedeem();
      },
      onOpenSelfHostingGuide: () => {
        this.openSelfHostingGuide();
      },
      onOpenMembershipTerms: () => {
        this.openMembershipTerms();
      },
      onOpenAutoRenewalNotice: () => {
        this.openAutoRenewalNotice();
      },
      onManageSubscription: () => {
        this.openSubscriptionManagement();
      },
      onOpenComplimentaryClaim: () => {
        this.openComplimentaryClaim();
      }
    })
  }

  /**
   * The page's only title-bar action. “恢复购买” is low frequency but must stay
   * findable, so it sits opposite the close action instead of in a footer link
   * the user has to scroll to. It is hidden when there is nothing to restore.
   */
  private resolveRestorePurchaseActionLabel(): ResourceStr {
    if (!this.state.proActionsEnabled) {
      return '';
    }
    return this.state.plans.length > 0 ? $r('app.string.settings_pro_restore') : '';
  }

  private restorePurchase(): void {
    const selectedPlan = this.state.plans.length > 0 ? this.state.plans[0].id : 'monthly';
    this.restorePurchaseForPlan(selectedPlan);
  }

  private resolveDesktopContentMaxWidth(): Length {
    return this.presentationMode === 'workspace' ? '100%' : AIRA_PRO_PAGE_CONTENT_MAX_WIDTH_VP;
  }

  @Builder
  private buildActiveSheet() {
    if (this.activeSheetKind === 'legalDocument') {
      AiraLegalWebDocumentContent({
        documentUrl: this.legalDocument.url,
        styleId: 'aira-pro-legal-document-style'
      })
        .width('100%')
        .height('100%')
    } else if (this.activeSheetKind === 'selfHostingGuide') {
      SyncDesktopBookmarkGuideContent()
        .width('100%')
        .height('100%')
    } else if (this.activeSheetKind === 'donateIntro') {
      AiraDonateProIntroSheet({
        primaryTextColor: this.theme.textPrimary,
        secondaryTextColor: this.theme.textSecondary,
        accentColor: this.theme.accent,
        onAccentColor: this.theme.onAccent,
        surfaceColor: this.storedFloatingSurfaceColor,
        onEnter: (): void => {
          this.closeActiveSheet();
        },
        onOpenRepository: (): void => {
          this.closeActiveSheet();
          this.navigationCoordinator.openBrowserUrlFromGuide(
            AIRA_COMMUNITY_REPOSITORY_URL,
            this.buildAiraProBoundaryState()
          );
        }
      })
        .width('100%')
        .height('100%')
    } else {
      this.buildHuaweiLoginSheet()
    }
  }

  private openMembershipRedeem(): void {
    if (!this.state.showMembershipRedeem) {
      return;
    }
    this.membershipRedeemCode = '';
    this.membershipRedeemDialogController.open();
  }

  private submitMembershipRedeemCode(code: string): void {
    if (this.membershipRedeemInFlight) {
      return;
    }
    if (!isValidMembershipRedeemCode(code)) {
      this.showToast($r('app.string.settings_pro_redeem_invalid'));
      return;
    }
    this.membershipRedeemInFlight = true;
    sharedMembershipFeature.redeemMembershipCode(code, this.buildAiraProDataBoundaryInput())
      .then((result: AiraMembershipRedeemResult) => {
        this.membershipRedeemInFlight = false;
        if (!result.ok) {
          this.showToast(this.preferMessage(result.message, $r('app.string.settings_pro_redeem_failed')));
          return;
        }
        const kind = this.resolveRedeemGrantKind(result.kind);
        if (kind === undefined) {
          this.showToast(this.preferMessage(result.message, $r('app.string.settings_pro_redeem_failed')));
          return;
        }
        this.presentMembershipRedeemResult(kind);
        this.applyAiraProState();
        sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), { force: true })
          .then(() => {
            this.applyAiraProState();
          })
          .catch((_error: Error) => {
            this.applyAiraProState();
          });
      })
      .catch((_error: Error) => {
        this.membershipRedeemInFlight = false;
        this.showToast($r('app.string.settings_pro_redeem_failed'));
      });
  }

  private resolveRedeemGrantKind(kind: string): AiraProMembershipRedeemGrantKind | undefined {
    if (kind === 'month' || kind === 'year' || kind === 'lifetime') {
      return kind;
    }
    return undefined;
  }

  private presentMembershipRedeemResult(kind: AiraProMembershipRedeemGrantKind): void {
    this.membershipRedeemResult = resolveAiraProMembershipRedeemResult(kind);
    try {
      this.membershipRedeemDialogController.close();
    } catch (_error) {
    }
    setTimeout((): void => {
      try {
        this.membershipRedeemResultDialogController.open();
      } catch (_error) {
      }
    }, 200);
  }

  private openComplimentaryClaim(): void {
    if (!this.state.complimentaryClaim.entryVisible) {
      return;
    }
    this.complimentaryClaimDialogController.open();
  }

  /**
   * The centered dialog only starts the claim. The hosted service decides
   * whether this account receives the 15 days and returns the grant to store.
   */
  private claimComplimentaryMembership(): void {
    if (!this.state.complimentaryClaim.actionEnabled || this.complimentaryClaimInFlight) {
      return;
    }
    this.complimentaryClaimInFlight = true;
    sharedMembershipFeature.claimComplimentaryMembership(this.buildAiraProDataBoundaryInput())
      .then((result: AiraComplimentaryClaimResult) => {
        this.complimentaryClaimInFlight = false;
        if (result.ok) {
          this.complimentaryClaimDialogController.close();
        }
        this.applyAiraProState();
        this.showToast(this.preferMessage(result.message, $r('app.string.settings_pro_claim_failed')));
        if (result.ok) {
          sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), { force: true })
            .then(() => {
              this.applyAiraProState();
            })
            .catch((_error: Error) => {
              this.applyAiraProState();
            });
        }
      })
      .catch((_error: Error) => {
        this.complimentaryClaimInFlight = false;
        this.showToast($r('app.string.settings_pro_claim_failed'));
      });
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
    this.refreshLifetimeStorePrice();
    sharedMembershipFeature.refreshStateForBoundary(this.buildAiraProDataBoundaryInput(), {
      minFreshMs: MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS
    })
      .then(() => {
        this.applyAiraProState();
        this.presentDonateIntro();
      })
      .catch((_error: Error) => {
        this.applyAiraProState();
        this.presentDonateIntro();
      });
  }

  private applyAiraProState(): void {
    if (!this.membershipMounted) { return; }
    const livePrice = this.lifetimeStorePriceText.length > 0
      ? this.lifetimeStorePriceText
      : readCachedAiraProLifetimeStorePrice();
    this.state = this.viewModel.buildState(
      sharedMembershipFeature.getState(),
      this.dataScope,
      this.privacyMode,
      livePrice
    );
    this.suiteOwned = sharedMembershipFeature.getAppSuiteState().owned;
    this.membershipOffer = createAiraProMembershipOffer(this.state);
    this.membershipActions = createAiraProMembershipActions(this.state);
  }

  /**
   * Reads the price Huawei is charging right now. A console price change,
   * including one that ends on its own, replaces the card the next time this
   * page is shown. A failed query keeps the last price instead of flashing
   * the catalog price over an active discount.
   */
  private refreshLifetimeStorePrice(): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_iap')) {
      return;
    }
    let context: common.UIAbilityContext;
    try {
      context = getContext(this) as common.UIAbilityContext;
    } catch (_error) {
      return;
    }
    const accountUid = this.getHuaweiUid();
    const request = this.lifetimeStorePriceRequest + 1;
    this.lifetimeStorePriceRequest = request;
    this.purchaseCoordinator.queryProProducts(context)
      .then((products: HuaweiIapProductView[]) => {
        if (!this.membershipMounted || !this.membershipActive || accountUid !== this.getHuaweiUid() ||
          request !== this.lifetimeStorePriceRequest) {
          return;
        }
        const priceText = this.findLifetimeStorePriceText(products);
        if (priceText.length === 0) {
          return;
        }
        rememberAiraProLifetimeStorePrice(priceText);
        this.lifetimeStorePriceText = priceText;
        this.applyAiraProState();
      })
      .catch((_error: Error) => {
      });
  }

  private findLifetimeStorePriceText(products: HuaweiIapProductView[]): string {
    for (let index = 0; index < products.length; index++) {
      if (products[index].period === 'one_time') {
        return products[index].priceText;
      }
    }
    return '';
  }

  private setHuaweiPaymentLaunchVisible(visible: boolean): void {
    if (visible === this.huaweiPaymentLaunchVisible) {
      return;
    }
    this.huaweiPaymentLaunchVisible = visible;
    try {
      if (visible) {
        this.huaweiPaymentLaunchDialogController.open();
      } else {
        this.huaweiPaymentLaunchDialogController.close();
      }
    } catch (_error) {
    }
  }

  private openProPurchase(planId: string = 'monthly'): void {
    if (!this.membershipMounted || !this.membershipActive || this.membershipPaymentBusy) { return; }
    this.membershipPaymentBusy = true;
    this.purchaseCoordinator.startPurchaseFlow(
      getContext(this) as common.UIAbilityContext, planId, this.getHuaweiUid(),
      this.purchaseFlowHost, this.buildAiraProDataBoundaryInput()
    ).finally((): void => {
      if (this.membershipMounted) { this.membershipPaymentBusy = false; }
    });
  }

  /**
   * The active-member card's single action. An active subscription has exactly
   * one thing left to do — open Huawei's subscription management — so the
   * page goes straight there instead of routing through a confirmation dialog
   * that only had one real outcome.
   */
  private openSubscriptionManagement(): void {
    this.purchaseCoordinator.openLifetimeUpgradeSubscriptionManagement(
      getContext(this) as common.UIAbilityContext,
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    );
  }

  /**
   * The free-route row's only action. Cold self-hosting has nothing to configure
   * on this page, so it hands off to the existing deployment guide instead of a
   * second copy of the recipe. The desktop workspace keeps its own scroll host,
   * so it reuses the same guide as an in-workspace sheet rather than pushing a
   * page route behind the workspace scaffold.
   */
  private openSelfHostingGuide(): void {
    if (this.isDesktopPresentation()) {
      this.openActiveSheet('selfHostingGuide');
      return;
    }
    this.navigationCoordinator.openSyncDesktopBookmarkGuide(this.buildAiraProBoundaryState());
  }

  private restorePurchaseForPlan(planId: string): void {
    if (!this.membershipMounted || !this.membershipActive || this.membershipPaymentBusy) { return; }
    this.membershipPaymentBusy = true;
    this.purchaseCoordinator.restorePurchaseFlow(
      getContext(this) as common.UIAbilityContext,
      this.getHuaweiUid(),
      planId,
      this.purchaseFlowHost,
      this.buildAiraProDataBoundaryInput()
    ).finally((): void => {
      if (this.membershipMounted) { this.membershipPaymentBusy = false; }
    });
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
      this.showToast($r('app.string.settings_pro_sign_in_private'));
      return false;
    }
    this.showToast($r('app.string.settings_pro_sign_in_required'));
    this.openActiveSheet('login');
    return false;
  }

  private handleHuaweiLoginPanelResult(
    error: BusinessError | undefined,
    response: loginComponentManager.HuaweiIDCredential
  ): void {
    if (error !== undefined) {
      if (error.code !== 1001502012) {
        this.showToast(this.preferMessage(error.message, $r('app.string.settings_pro_sign_in_failed')));
      }
      return;
    }
    if (response.authorizationCode.trim().length <= 0 && response.openID.trim().length <= 0) {
      this.showToast($r('app.string.settings_pro_sign_in_incomplete'));
      return;
    }
    this.closeActiveSheet();
    this.signInHuaweiAccount();
  }

  /**
   * Official only. A non-member sees this every time they enter the page.
   * A current member does not, including a member recognized after refresh.
   */
  private presentDonateIntro(): void {
    if (AIRA_DISTRIBUTION_CAPABILITY_OWNER.isCommunity()) {
      return;
    }
    if (this.state.showMembershipStatus) {
      if (this.activeSheetKind === 'donateIntro') {
        this.closeActiveSheet();
      }
      return;
    }
    if (this.activeSheetVisible || this.donateIntroDismissedThisEntry) {
      return;
    }
    this.openActiveSheet('donateIntro');
  }

  private openActiveSheet(kind: AiraProSheetKind): void {
    this.activeSheetKind = kind;
    this.activeSheetMounted = true;
    this.activeSheetVisible = true;
  }

  private closeActiveSheet(): void {
    if (this.activeSheetKind === 'donateIntro') {
      this.donateIntroDismissedThisEntry = true;
    }
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    this.activeSheetKind = 'none';
  }

  private handleActiveSheetDisappear(): void {
    if (this.activeSheetKind === 'donateIntro') {
      this.donateIntroDismissedThisEntry = true;
    }
    this.activeSheetVisible = false;
    this.activeSheetMounted = false;
    this.activeSheetKind = 'none';
  }

  private resolveActiveSheetHeight(): SheetSize {
    return SheetSize.FIT_CONTENT;
  }

  private resolveActiveSheetBackgroundColor(): ResourceColor {
    return this.storedFloatingSurfaceColor;
  }

  private resolveDesktopDialogTitle(): ResourceStr {
    if (this.activeSheetKind === 'login') {
      return $r('app.string.settings_pro_sign_in_title');
    }
    if (this.activeSheetKind === 'selfHostingGuide') {
      return $r('app.string.settings_pro_self_hosting_guide');
    }
    if (this.activeSheetKind === 'legalDocument') {
      return this.resolveLegalDocumentTitle(this.legalDocument.id);
    }
    if (this.activeSheetKind === 'donateIntro') {
      return $r('app.string.settings_pro_donate_intro_title');
    }
    return $r('app.string.settings_pro_enter');
  }

  private resolveLegalDocumentTitle(documentId: AiraLegalDocumentId): ResourceStr {
    if (documentId === 'user_service_agreement') {
      return $r('app.string.settings_pro_legal_user');
    }
    if (documentId === 'privacy_statement') {
      return $r('app.string.settings_pro_legal_privacy');
    }
    if (documentId === 'pro_membership_service_agreement') {
      return $r('app.string.settings_pro_legal_membership_full');
    }
    if (documentId === 'pro_auto_renewal_service_agreement') {
      return $r('app.string.settings_pro_legal_renewal_full');
    }
    return this.legalDocument.title;
  }

  private shouldShowDesktopDialogHeader(): boolean {
    return this.activeSheetKind === 'login' ||
      this.activeSheetKind === 'legalDocument' ||
      this.activeSheetKind === 'selfHostingGuide' ||
      this.activeSheetKind === 'donateIntro';
  }

  private signInHuaweiAccount(): void {
    sharedHuaweiAccountMutationCoordinator.signIn(this.buildAiraProDataBoundaryInput())
      .then((result) => {
        if (result.type === 'failed') {
          this.showToast(this.preferMessage(result.message, result.title));
          return;
        }
        this.syncSettingsRefreshSignal.bump();
        this.refreshState();
        this.showToast(result.title);
      })
      .catch((_error: Error) => {
        this.showToast($r('app.string.settings_pro_sign_in_failed'));
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

  private preferMessage(message: string, fallback: ResourceStr): ResourceStr {
    return message.length > 0 ? message : fallback;
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

}
